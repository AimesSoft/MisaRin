use std::collections::HashMap;
#[cfg(target_family = "wasm")]
use std::cell::RefCell;
use std::sync::Arc;
#[cfg(not(target_family = "wasm"))]
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

use crate::gpu::brush_renderer::{BrushRenderer, BrushShape, Color, Point2D};
use crate::gpu::debug::{self, LogLevel};
use crate::gpu::layer_texture::LayerTextureManager;

#[derive(Clone, Copy, Debug)]
struct StrokeEndpoint {
    point: Point2D,
    radius: f32,
    seq: u64,
    at: Instant,
}

struct GpuBrushEngine {
    textures: LayerTextureManager,
    brush: BrushRenderer,
    last_endpoints: HashMap<String, StrokeEndpoint>,
}

#[cfg(not(target_family = "wasm"))]
static GPU_BRUSH: OnceLock<Mutex<Option<GpuBrushEngine>>> = OnceLock::new();

#[cfg(not(target_family = "wasm"))]
fn brush_cell() -> &'static Mutex<Option<GpuBrushEngine>> {
    GPU_BRUSH.get_or_init(|| Mutex::new(None))
}

#[cfg(not(target_family = "wasm"))]
fn with_brush_mut<R>(
    f: impl FnOnce(&mut Option<GpuBrushEngine>) -> Result<R, String>,
) -> Result<R, String> {
    let mut guard = brush_cell()
        .lock()
        .map_err(|_| "gpu brush lock poisoned".to_string())?;
    f(&mut *guard)
}

#[cfg(not(target_family = "wasm"))]
fn with_brush<R>(
    f: impl FnOnce(&Option<GpuBrushEngine>) -> Result<R, String>,
) -> Result<R, String> {
    let guard = brush_cell()
        .lock()
        .map_err(|_| "gpu brush lock poisoned".to_string())?;
    f(&*guard)
}

#[cfg(target_family = "wasm")]
thread_local! {
    static GPU_BRUSH: RefCell<Option<GpuBrushEngine>> = RefCell::new(None);
}

#[cfg(target_family = "wasm")]
fn with_brush_mut<R>(
    f: impl FnOnce(&mut Option<GpuBrushEngine>) -> Result<R, String>,
) -> Result<R, String> {
    GPU_BRUSH.with(|cell| f(&mut *cell.borrow_mut()))
}

#[cfg(target_family = "wasm")]
fn with_brush<R>(
    f: impl FnOnce(&Option<GpuBrushEngine>) -> Result<R, String>,
) -> Result<R, String> {
    GPU_BRUSH.with(|cell| f(&*cell.borrow()))
}

#[flutter_rust_bridge::frb]
pub struct GpuPoint2D {
    pub x: f32,
    pub y: f32,
}

#[flutter_rust_bridge::frb]
pub struct GpuStrokeResult {
    pub dirty_left: i32,
    pub dirty_top: i32,
    pub dirty_width: i32,
    pub dirty_height: i32,
    pub draw_calls: u32,
}

#[flutter_rust_bridge::frb(sync)]
pub fn gpu_brush_init() -> Result<(), String> {
    with_brush_mut(|guard| {
        if guard.is_some() {
            return Ok(());
        }

        let t0 = Instant::now();
        let (device, queue) = create_wgpu_device()?;
        let device = Arc::new(device);
        let queue = Arc::new(queue);
        let mut brush = BrushRenderer::new(device.clone(), queue.clone())?;
        brush.set_softness(0.0);

        let textures = LayerTextureManager::new(device.clone(), queue.clone());

        *guard = Some(GpuBrushEngine {
            textures,
            brush,
            last_endpoints: HashMap::new(),
        });
        debug::log(
            LogLevel::Info,
            format_args!("gpu_brush_init ok in {:?}.", t0.elapsed()),
        );
        Ok(())
    })
}

pub fn gpu_upload_layer(
    layer_id: String,
    pixels: Vec<u32>,
    width: u32,
    height: u32,
) -> Result<(), String> {
    with_brush_mut(|guard| {
        let engine = guard
            .as_mut()
            .ok_or_else(|| "gpu brush not initialized (call gpu_brush_init first)".to_string())?;

        let t0 = Instant::now();
        engine
            .textures
            .upload_layer(&layer_id, &pixels, width, height)?;
        engine.brush.set_canvas_size(width, height);
        debug::log(
            LogLevel::Info,
            format_args!(
                "gpu_upload_layer ok layer='{layer_id}' size={width}x{height} pixels={} in {:?}.",
                pixels.len(),
                t0.elapsed()
            ),
        );
        Ok(())
    })
}

pub fn gpu_download_layer(layer_id: String) -> Result<Vec<u32>, String> {
    with_brush(|guard| {
        let engine = guard
            .as_ref()
            .ok_or_else(|| "gpu brush not initialized (call gpu_brush_init first)".to_string())?;
        engine.textures.download_layer(&layer_id)
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn gpu_remove_layer(layer_id: String) -> Result<(), String> {
    with_brush_mut(|guard| {
        let Some(engine) = guard.as_mut() else {
            return Ok(());
        };
        engine.textures.remove_layer(&layer_id);
        engine.last_endpoints.remove(&layer_id);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn gpu_brush_dispose() {
    let _ = with_brush_mut(|guard| {
        *guard = None;
        Ok(())
    });
}

pub fn gpu_draw_stroke(
    layer_id: String,
    points: Vec<GpuPoint2D>,
    radii: Vec<f32>,
    color: u32, // ARGB
    brush_shape: u32,
    erase: bool,
    antialias_level: u32,
) -> Result<GpuStrokeResult, String> {
    let seq = debug::next_seq();
    let total_t0 = Instant::now();

    return with_brush_mut(|guard| {
        let engine = guard
            .as_mut()
            .ok_or_else(|| "gpu brush not initialized (call gpu_brush_init first)".to_string())?;

    let width = engine.textures.width();
    let height = engine.textures.height();
    if width == 0 || height == 0 {
        return Err(
            "gpu_draw_stroke: layer textures not initialized (upload a layer first)".to_string(),
        );
    }
    engine.brush.set_canvas_size(width, height);

    let layer_texture = engine
        .textures
        .get_texture(&layer_id)
        .ok_or_else(|| format!("gpu_draw_stroke: unknown layer '{layer_id}'"))?;

    if points.is_empty() {
        return Ok(GpuStrokeResult {
            dirty_left: 0,
            dirty_top: 0,
            dirty_width: 0,
            dirty_height: 0,
            draw_calls: 0,
        });
    }
    if points.len() != radii.len() {
        return Err(format!(
            "gpu_draw_stroke: points/radii length mismatch: {} vs {}",
            points.len(),
            radii.len()
        ));
    }

    let shape = map_brush_shape(brush_shape)?;

    let converted_points: Vec<Point2D> = points
        .into_iter()
        .map(|p| Point2D { x: p.x, y: p.y })
        .collect();

    // Detect unexpected discontinuities between successive segments on the same layer.
    // This helps distinguish "input/segmentation dropped points" vs "render/display cache".
    if let Some(first_point) = converted_points.first().copied() {
        let first_radius = radii.first().copied().unwrap_or(0.0).max(0.0);
        if let Some(prev) = engine.last_endpoints.get(&layer_id).copied() {
            let dx = first_point.x - prev.point.x;
            let dy = first_point.y - prev.point.y;
            let dist = (dx * dx + dy * dy).sqrt();
            let dt_ms = prev.at.elapsed().as_millis();
            if dist.is_finite() && dist >= 2.0 && dt_ms <= 250 {
                debug::log(
                    LogLevel::Warn,
                    format_args!(
                        "#{seq} stroke discontinuity layer='{layer_id}': prev_end=({:.2},{:.2}) r={:.2} (seq #{}) -> cur_start=({:.2},{:.2}) r={:.2} dist={:.2}px dt={}ms",
                        prev.point.x,
                        prev.point.y,
                        prev.radius,
                        prev.seq,
                        first_point.x,
                        first_point.y,
                        first_radius,
                        dist,
                        dt_ms
                    ),
                );
            } else {
                debug::log(
                    LogLevel::Verbose,
                    format_args!(
                        "#{seq} stroke continuity layer='{layer_id}': dist={:.3}px dt={}ms",
                        dist, dt_ms
                    ),
                );
            }
        }
    }

    if debug::level() >= LogLevel::Info {
        let mut min_x: f32 = f32::INFINITY;
        let mut min_y: f32 = f32::INFINITY;
        let mut max_x: f32 = f32::NEG_INFINITY;
        let mut max_y: f32 = f32::NEG_INFINITY;
        let mut min_r: f32 = f32::INFINITY;
        let mut max_r: f32 = 0.0;
        let mut non_finite_xy: usize = 0;
        let mut non_finite_r: usize = 0;
        let mut out_of_bounds: usize = 0;

        for (p, &r) in converted_points.iter().zip(radii.iter()) {
            if !p.x.is_finite() || !p.y.is_finite() {
                non_finite_xy += 1;
                continue;
            }
            if p.x < 0.0 || p.y < 0.0 || p.x > width as f32 || p.y > height as f32 {
                out_of_bounds += 1;
            }
            min_x = min_x.min(p.x);
            min_y = min_y.min(p.y);
            max_x = max_x.max(p.x);
            max_y = max_y.max(p.y);

            if !r.is_finite() {
                non_finite_r += 1;
                continue;
            }
            let rr = r.max(0.0);
            min_r = min_r.min(rr);
            max_r = max_r.max(rr);
        }

        let first = converted_points
            .first()
            .copied()
            .unwrap_or(Point2D { x: 0.0, y: 0.0 });
        let last = converted_points
            .last()
            .copied()
            .unwrap_or(Point2D { x: 0.0, y: 0.0 });
        debug::log(
            LogLevel::Info,
            format_args!(
                "#{seq} gpu_draw_stroke layer='{layer_id}' canvas={width}x{height} pts={} color=0x{color:08X} erase={erase} shape={shape:?} aa={antialias_level} bbox=({min_x:.2},{min_y:.2})-({max_x:.2},{max_y:.2}) r=[{min_r:.2},{max_r:.2}] first=({:.2},{:.2}) last=({:.2},{:.2}) oob={out_of_bounds} nan_xy={non_finite_xy} nan_r={non_finite_r}",
                converted_points.len(),
                first.x,
                first.y,
                last.x,
                last.y
            ),
        );

        if max_r.is_finite() && max_r < 0.75 {
            debug::log(
                LogLevel::Warn,
                format_args!(
                    "#{seq} suspicious small brush radius: max_r={max_r:.3} (canvas={width}x{height})"
                ),
            );
        }
    }

    // Flow 5 hard constraint: drawing must not perform any GPU→CPU readback.
    // Therefore this API returns only stats + dirty rect (no pixels).
    let draw_t0 = Instant::now();
    let mut dirty_union: Option<(i32, i32, i32, i32)> = None;
    let mut draw_calls: u32 = 0;

    let layer_view = layer_texture.create_view(&wgpu::TextureViewDescriptor::default());

    if converted_points.len() == 1 {
        let p0 = converted_points[0];
        let r0 = radii[0];
        engine.brush.draw_stroke(
            &layer_view,
            &[p0],
            &[r0],
            Color { argb: color },
            shape,
            erase,
            antialias_level,
            0.0,
            false,
            0.0,
            false,
            false,
            false,
        )?;
        draw_calls = 1;
        dirty_union = union_dirty_rect_i32(
            dirty_union,
            compute_dirty_rect_i32(&[p0], &[r0], width, height),
        );
    } else {
        for i in 0..converted_points.len().saturating_sub(1) {
            let pts = [converted_points[i], converted_points[i + 1]];
            let rs = [radii[i], radii[i + 1]];
            engine.brush.draw_stroke(
                &layer_view,
                &pts,
                &rs,
                Color { argb: color },
                shape,
                erase,
                antialias_level,
                0.0,
                false,
                0.0,
                false,
                false,
                false,
            )?;
            draw_calls = draw_calls.saturating_add(1);
            dirty_union = union_dirty_rect_i32(
                dirty_union,
                compute_dirty_rect_i32(&pts, &rs, width, height),
            );
        }
    }

    debug::log(
        LogLevel::Verbose,
        format_args!(
            "#{seq} brush.draw_stroke ok calls={draw_calls} in {:?}.",
            draw_t0.elapsed()
        ),
    );

    let (dirty_left, dirty_top, dirty_width, dirty_height) = dirty_union.unwrap_or((0, 0, 0, 0));
    debug::log(
        LogLevel::Info,
        format_args!(
            "#{seq} dirty=({dirty_left},{dirty_top}) {dirty_width}x{dirty_height} calls={draw_calls}"
        ),
    );

    // Update last endpoint tracking for continuity diagnostics.
    if let Some(last_point) = converted_points.last().copied() {
        let last_radius = radii.last().copied().unwrap_or(0.0).max(0.0);
        engine.last_endpoints.insert(
            layer_id.clone(),
            StrokeEndpoint {
                point: last_point,
                radius: last_radius,
                seq,
                at: Instant::now(),
            },
        );
    }

    debug::log(
        LogLevel::Verbose,
        format_args!("#{seq} gpu_draw_stroke total {:?}.", total_t0.elapsed()),
    );
        Ok(GpuStrokeResult {
            dirty_left,
            dirty_top,
            dirty_width,
            dirty_height,
            draw_calls,
        })
    })
}

fn map_brush_shape(index: u32) -> Result<BrushShape, String> {
    // Dart enum: circle=0, triangle=1, square=2, star=3.
    match index {
        0 => Ok(BrushShape::Circle),
        1 => Ok(BrushShape::Triangle),
        2 => Ok(BrushShape::Square),
        3 => Ok(BrushShape::Star),
        _ => Ok(BrushShape::Circle),
    }
}

fn compute_dirty_rect_i32(
    points: &[Point2D],
    radii: &[f32],
    width: u32,
    height: u32,
) -> (i32, i32, i32, i32) {
    if width == 0 || height == 0 || points.is_empty() || points.len() != radii.len() {
        return (0, 0, 0, 0);
    }

    let mut min_x: f32 = f32::INFINITY;
    let mut min_y: f32 = f32::INFINITY;
    let mut max_x: f32 = f32::NEG_INFINITY;
    let mut max_y: f32 = f32::NEG_INFINITY;
    let mut max_r: f32 = 0.0;

    for (p, &r) in points.iter().zip(radii.iter()) {
        let x = if p.x.is_finite() { p.x } else { 0.0 };
        let y = if p.y.is_finite() { p.y } else { 0.0 };
        let radius = if r.is_finite() { r.max(0.0) } else { 0.0 };
        min_x = min_x.min(x);
        min_y = min_y.min(y);
        max_x = max_x.max(x);
        max_y = max_y.max(y);
        max_r = max_r.max(radius);
    }

    if !min_x.is_finite() || !min_y.is_finite() || !max_x.is_finite() || !max_y.is_finite() {
        return (0, 0, 0, 0);
    }

    let pad = max_r + 2.0;
    let left = ((min_x - pad).floor() as i64).clamp(0, width as i64);
    let top = ((min_y - pad).floor() as i64).clamp(0, height as i64);
    let right = ((max_x + pad).ceil() as i64).clamp(0, width as i64);
    let bottom = ((max_y + pad).ceil() as i64).clamp(0, height as i64);

    let dirty_w = (right - left).max(0) as i32;
    let dirty_h = (bottom - top).max(0) as i32;
    (left as i32, top as i32, dirty_w, dirty_h)
}

fn union_dirty_rect_i32(
    existing: Option<(i32, i32, i32, i32)>,
    candidate: (i32, i32, i32, i32),
) -> Option<(i32, i32, i32, i32)> {
    let (cl, ct, cw, ch) = candidate;
    if cw <= 0 || ch <= 0 {
        return existing;
    }
    let Some((el, et, ew, eh)) = existing else {
        return Some(candidate);
    };
    if ew <= 0 || eh <= 0 {
        return Some(candidate);
    }

    let el64 = el as i64;
    let et64 = et as i64;
    let er64 = el64 + ew as i64;
    let eb64 = et64 + eh as i64;

    let cl64 = cl as i64;
    let ct64 = ct as i64;
    let cr64 = cl64 + cw as i64;
    let cb64 = ct64 + ch as i64;

    let left = el64.min(cl64);
    let top = et64.min(ct64);
    let right = er64.max(cr64);
    let bottom = eb64.max(cb64);

    let width = (right - left).max(0) as i32;
    let height = (bottom - top).max(0) as i32;
    Some((left as i32, top as i32, width, height))
}

fn create_wgpu_device() -> Result<(wgpu::Device, wgpu::Queue), String> {
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::all(),
        ..Default::default()
    });

    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: None,
        force_fallback_adapter: false,
    }))
    .ok_or_else(|| "wgpu: no compatible GPU adapter found".to_string())?;

    if debug::level() >= LogLevel::Info {
        let info = adapter.get_info();
        let limits = adapter.limits();
        debug::log(
            LogLevel::Info,
            format_args!(
                "wgpu adapter: backend={:?} device_type={:?} name='{}' max_tex_2d={} max_buf={} max_storage_binding={}",
                info.backend,
                info.device_type,
                info.name,
                limits.max_texture_dimension_2d,
                limits.max_buffer_size,
                limits.max_storage_buffer_binding_size
            ),
        );
    }

    let adapter_limits = adapter.limits();
    let adapter_features = adapter.features();
    let required_limits = wgpu::Limits {
        max_buffer_size: adapter_limits.max_buffer_size,
        max_storage_buffer_binding_size: adapter_limits.max_storage_buffer_binding_size,
        ..wgpu::Limits::default()
    };

    let required_features = wgpu::Features::TEXTURE_ADAPTER_SPECIFIC_FORMAT_FEATURES;
    if !adapter_features.contains(required_features) {
        return Err(
            "wgpu: adapter does not support TEXTURE_ADAPTER_SPECIFIC_FORMAT_FEATURES".to_string(),
        );
    }

    pollster::block_on(adapter.request_device(
        &wgpu::DeviceDescriptor {
            label: Some("misa-rin GpuBrush device"),
            required_features,
            required_limits,
        },
        None,
    ))
    .map_err(|e| format!("wgpu: request_device failed: {e:?}"))
}
