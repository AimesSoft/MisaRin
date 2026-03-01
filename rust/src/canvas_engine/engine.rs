use std::collections::HashMap;
use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[cfg(any(target_os = "macos", target_os = "ios"))]
use metal::foreign_types::ForeignType;
#[cfg(any(target_os = "macos", target_os = "ios"))]
use wgpu_hal::api::Metal;

use crate::api::bucket_fill;
use crate::gpu::blend_modes::map_canvas_blend_mode_index;
use crate::gpu::brush_renderer::{BrushRenderer, BrushShape, Color, Point2D, MAX_POINTS};
use crate::gpu::bucket_fill_renderer::BucketFillRenderer;
use crate::gpu::debug::{self, LogLevel};
use crate::gpu::filter_renderer::{
    FilterRenderer, FILTER_BINARIZE, FILTER_BLACK_WHITE, FILTER_BRIGHTNESS_CONTRAST,
    FILTER_FILL_EXPAND, FILTER_GAUSSIAN_BLUR, FILTER_HUE_SATURATION, FILTER_INVERT,
    FILTER_LEAK_REMOVAL, FILTER_LINE_NARROW, FILTER_SCAN_PAPER_DRAWING,
};
use crate::gpu::layer_format::LAYER_TEXTURE_FORMAT;

use super::layers::LayerTextures;
use super::present::{
    attach_present_texture, create_present_params_buffer, create_present_transform_buffer,
    copy_render_to_shared, signal_frame_ready, write_present_config, write_present_transform,
    PresentRenderer, PresentTarget,
};
use super::preview::{PreviewConfig, PreviewRenderer, PreviewSegment};
#[cfg(target_os = "windows")]
use super::present::create_dxgi_shared_present_target;
use super::stroke::{
    apply_streamline, brush_random_rotation_radians, map_brush_shape, prepare_brush_samples,
    EngineBrushSettings, StrokeResampler,
};
use super::transform::LayerTransformRenderer;
use super::types::{EnginePoint, SprayPoint};
use super::undo::UndoManager;

const INITIAL_LAYER_CAPACITY: usize = 4;
const VIEW_FLAG_MIRROR: u32 = 1;
const VIEW_FLAG_BLACK_WHITE: u32 = 2;
const ENABLE_STREAMLINE_VECTOR_PREVIEW: bool = false;
static PIXEL_SAMPLE_LAST_MS: AtomicU64 = AtomicU64::new(0);
const RESAMPLE_BACKLOG_SMALL: u64 = 24;
const RESAMPLE_BACKLOG_MEDIUM: u64 = 64;
const RESAMPLE_BACKLOG_LARGE: u64 = 128;
const RESAMPLE_BACKLOG_XL: u64 = 256;

#[cfg(target_os = "windows")]
const PRESENT_WAIT_LOG_EVERY: u64 = 120;
#[cfg(target_os = "windows")]
static PRESENT_WAIT_ACCUM_US: AtomicU64 = AtomicU64::new(0);
#[cfg(target_os = "windows")]
static PRESENT_WAIT_MAX_US: AtomicU64 = AtomicU64::new(0);
#[cfg(target_os = "windows")]
static PRESENT_WAIT_COUNT: AtomicU64 = AtomicU64::new(0);

#[cfg(target_os = "windows")]
fn record_present_wait(waited_us: u64) {
    PRESENT_WAIT_ACCUM_US.fetch_add(waited_us, Ordering::Relaxed);
    let mut prev = PRESENT_WAIT_MAX_US.load(Ordering::Relaxed);
    while waited_us > prev {
        match PRESENT_WAIT_MAX_US.compare_exchange(
            prev,
            waited_us,
            Ordering::Relaxed,
            Ordering::Relaxed,
        ) {
            Ok(_) => break,
            Err(next) => prev = next,
        }
    }
    let count = PRESENT_WAIT_COUNT.fetch_add(1, Ordering::Relaxed) + 1;
    if count % PRESENT_WAIT_LOG_EVERY == 0 {
        let sum = PRESENT_WAIT_ACCUM_US.swap(0, Ordering::Relaxed);
        let max = PRESENT_WAIT_MAX_US.swap(0, Ordering::Relaxed);
        let avg_ms = (sum as f64) / (PRESENT_WAIT_LOG_EVERY as f64) / 1000.0;
        let max_ms = (max as f64) / 1000.0;
        debug::log(
            LogLevel::Info,
            format_args!(
                "[perf] present wait avg={avg_ms:.2}ms max={max_ms:.2}ms"
            ),
        );
    }
}

pub(crate) enum EngineCommand {
    AttachPresentTexture {
        mtl_texture_ptr: usize,
        width: u32,
        height: u32,
        bytes_per_row: u32,
    },
    #[cfg(target_os = "windows")]
    AttachPresentDxgi {
        width: u32,
        height: u32,
        reply: mpsc::Sender<Option<usize>>,
    },
    ResetCanvas {
        background_color_argb: u32,
    },
    ResetCanvasWithLayers {
        layer_count: u32,
        background_color_argb: u32,
    },
    ResizeCanvas {
        width: u32,
        height: u32,
        layer_count: u32,
        background_color_argb: u32,
        reply: mpsc::Sender<bool>,
    },
    FillLayer {
        layer_index: u32,
        color_argb: u32,
    },
    ClearLayer {
        layer_index: u32,
    },
    SetActiveLayer {
        layer_index: u32,
    },
    SetLayerOpacity {
        layer_index: u32,
        opacity: f32,
    },
    SetLayerVisible {
        layer_index: u32,
        visible: bool,
    },
    SetLayerClippingMask {
        layer_index: u32,
        clipping_mask: bool,
    },
    SetLayerBlendMode {
        layer_index: u32,
        blend_mode_index: u32,
    },
    ReorderLayer {
        from_index: u32,
        to_index: u32,
    },
    SetViewFlags {
        view_flags: u32,
    },
    SetBrush {
        color_argb: u32,
        base_radius: f32,
        use_pressure: bool,
        erase: bool,
        antialias_level: u32,
        brush_shape: u32,
        random_rotation: bool,
        smooth_rotation: bool,
        rotation_seed: u32,
        spacing: f32,
        hardness: f32,
        flow: f32,
        scatter: f32,
        rotation_jitter: f32,
        snap_to_pixel: bool,
        screentone_enabled: bool,
        screentone_spacing: f32,
        screentone_dot_size: f32,
        screentone_rotation: f32,
        screentone_softness: f32,
        screentone_shape: u32,
        hollow_enabled: bool,
        hollow_ratio: f32,
        hollow_erase_occluded: bool,
        streamline_strength: f32,
        smoothing_mode: u32,
        stabilizer_strength: f32,
    },
    SetBrushMask {
        width: u32,
        height: u32,
        mask: Vec<u8>,
    },
    ClearBrushMask,
    BeginSpray,
    DrawSpray {
        points: Vec<SprayPoint>,
        color_argb: u32,
        brush_shape: u32,
        erase: bool,
        antialias_level: u32,
        softness: f32,
        accumulate: bool,
    },
    EndSpray,
    ApplyFilter {
        layer_index: u32,
        filter_type: u32,
        param0: f32,
        param1: f32,
        param2: f32,
        param3: f32,
        reply: mpsc::Sender<bool>,
    },
    ApplyAntialias {
        layer_index: u32,
        level: u32,
        reply: mpsc::Sender<bool>,
    },
    BucketFill {
        layer_index: u32,
        start_x: i32,
        start_y: i32,
        color_argb: u32,
        contiguous: bool,
        sample_all_layers: bool,
        tolerance: u8,
        fill_gap: u8,
        antialias_level: u8,
        swallow_colors: Vec<u32>,
        selection_mask: Option<Vec<u8>>,
        reply: mpsc::Sender<bool>,
    },
    MagicWandMask {
        layer_index: u32,
        start_x: i32,
        start_y: i32,
        sample_all_layers: bool,
        tolerance: u8,
        selection_mask: Option<Vec<u8>>,
        reply: mpsc::Sender<Option<Vec<u8>>>,
    },
    ReadLayer {
        layer_index: u32,
        reply: mpsc::Sender<Option<Vec<u32>>>,
    },
    ReadLayerPreview {
        layer_index: u32,
        width: u32,
        height: u32,
        reply: mpsc::Sender<Option<Vec<u8>>>,
    },
    ReadPresent {
        reply: mpsc::Sender<Option<Vec<u8>>>,
    },
    WriteLayer {
        layer_index: u32,
        pixels: Vec<u32>,
        record_undo: bool,
        reply: mpsc::Sender<bool>,
    },
    TranslateLayer {
        layer_index: u32,
        delta_x: i32,
        delta_y: i32,
        reply: mpsc::Sender<bool>,
    },
    SetLayerTransformPreview {
        layer_index: u32,
        matrix: [f32; 16],
        enabled: bool,
        bilinear: bool,
    },
    ApplyLayerTransform {
        layer_index: u32,
        matrix: [f32; 16],
        bilinear: bool,
        reply: mpsc::Sender<bool>,
    },
    GetLayerBounds {
        layer_index: u32,
        reply: mpsc::Sender<Option<(i32, i32, i32, i32)>>,
    },
    SetSelectionMask {
        selection_mask: Option<Vec<u8>>,
    },
    Undo,
    Redo,
    Stop,
}

pub(crate) struct EngineInputBatch {
    pub(crate) points: Vec<EnginePoint>,
}

pub(crate) struct EngineEntry {
    pub(crate) mtl_device_ptr: usize,
    pub(crate) frame_ready: Arc<AtomicBool>,
    pub(crate) frame_in_flight: Arc<AtomicBool>,
    pub(crate) cmd_tx: mpsc::Sender<EngineCommand>,
    pub(crate) input_tx: mpsc::Sender<EngineInputBatch>,
    pub(crate) input_queue_len: Arc<AtomicU64>,
}

static ENGINES: OnceLock<Mutex<HashMap<u64, EngineEntry>>> = OnceLock::new();
static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);

fn engines() -> &'static Mutex<HashMap<u64, EngineEntry>> {
    ENGINES.get_or_init(|| Mutex::new(HashMap::new()))
}

struct EngineDeviceContext {
    _instance: wgpu::Instance,
    _adapter: wgpu::Adapter,
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
}

static DEVICE_CONTEXT: OnceLock<Result<EngineDeviceContext, String>> = OnceLock::new();

fn device_context() -> Result<&'static EngineDeviceContext, String> {
    let init_result = DEVICE_CONTEXT.get_or_init(|| {
        debug::set_level(LogLevel::Info);
        let start = std::time::Instant::now();
        debug::log(LogLevel::Info, format_args!("device_context: starting initialization"));
        let backends = if cfg!(any(target_os = "macos", target_os = "ios")) {
            wgpu::Backends::METAL
        } else if cfg!(target_os = "windows") {
            wgpu::Backends::DX12
        } else {
            wgpu::Backends::PRIMARY
        };
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends,
            ..Default::default()
        });

        debug::log(LogLevel::Info, format_args!("device_context: instance created in {}ms", start.elapsed().as_millis()));
        let adapter_start = std::time::Instant::now();
        let adapter =
            pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                compatible_surface: None,
                force_fallback_adapter: false,
            }))
            .ok_or_else(|| "wgpu: no compatible adapter found".to_string())?;
        debug::log(LogLevel::Info, format_args!("device_context: adapter requested in {}ms", adapter_start.elapsed().as_millis()));

        let device_start = std::time::Instant::now();
        let required_features = wgpu::Features::TEXTURE_ADAPTER_SPECIFIC_FORMAT_FEATURES;
        if !adapter.features().contains(required_features) {
            return Err(
                "wgpu: adapter does not support TEXTURE_ADAPTER_SPECIFIC_FORMAT_FEATURES (required for read-write storage textures)"
                    .to_string(),
            );
        }

        let (device, queue) = pollster::block_on(adapter.request_device(
            &wgpu::DeviceDescriptor {
                label: Some("misa-rin CanvasEngine device"),
                required_features,
                required_limits: wgpu::Limits::default(),
            },
            None,
        ))
        .map_err(|e| format!("wgpu: request_device failed: {e:?}"))?;
        debug::log(LogLevel::Info, format_args!("device_context: device requested in {}ms", device_start.elapsed().as_millis()));

        device.on_uncaptured_error(Box::new(|err| {
            eprintln!("[misa-rin][wgpu] {err}");
        }));

        debug::log(LogLevel::Info, format_args!("device_context: total initialization took {}ms", start.elapsed().as_millis()));
        Ok(EngineDeviceContext {
            _instance: instance,
            _adapter: adapter,
            device: Arc::new(device),
            queue: Arc::new(queue),
        })
    });

    match init_result {
        Ok(ctx) => Ok(ctx),
        Err(err) => Err(err.clone()),
    }
}

struct StreamlineAnimation {
    start: Instant,
    duration: Duration,
    next_frame_at: Instant,
    frame_interval: Duration,
    pending_first_frame: bool,
    from_points: Vec<(Point2D, f32)>,
    to_points: Vec<(Point2D, f32)>,
    preview_from_points: Option<Vec<(Point2D, f32)>>,
    preview_to_points: Option<Vec<(Point2D, f32)>>,
    scratch: Vec<(Point2D, f32)>,
    layer_index: u32,
    brush_settings: EngineBrushSettings,
    use_hollow_mask: bool,
    use_hollow_base: bool,
}

struct PreviewStrokeState {
    layer_index: u32,
    brush_settings: EngineBrushSettings,
    points: Vec<(Point2D, f32)>,
    use_accumulate: bool,
}

impl StreamlineAnimation {
    fn progress(&self, now: Instant) -> f32 {
        if self.duration.is_zero() {
            return 1.0;
        }
        let elapsed = now.saturating_duration_since(self.start);
        (elapsed.as_secs_f32() / self.duration.as_secs_f32()).clamp(0.0, 1.0)
    }

    fn should_render(&mut self, now: Instant) -> bool {
        if now < self.next_frame_at {
            return false;
        }
        self.next_frame_at = now + self.frame_interval;
        true
    }
}

fn streamline_animation_duration(strength: f32) -> Duration {
    let s = if strength.is_finite() {
        strength.clamp(0.0, 1.0)
    } else {
        0.0
    };
    let eased = s.powf(0.7);
    let ms = (150.0 + 150.0 * eased).round() as u64;
    Duration::from_millis(ms.max(150))
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn read_layer_pixel_u32(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    layer_texture: &wgpu::Texture,
    layer_index: u32,
    x: u32,
    y: u32,
) -> Option<u32> {
    if x == u32::MAX || y == u32::MAX {
        return None;
    }
    let bytes_per_row: u32 = 256;
    let buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("misa-rin layer sample buffer"),
        size: bytes_per_row as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("misa-rin layer sample encoder"),
    });
    encoder.copy_texture_to_buffer(
        wgpu::ImageCopyTexture {
            texture: layer_texture,
            mip_level: 0,
            origin: wgpu::Origin3d {
                x,
                y,
                z: layer_index,
            },
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::ImageCopyBuffer {
            buffer: &buffer,
            layout: wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(bytes_per_row),
                rows_per_image: Some(1),
            },
        },
        wgpu::Extent3d {
            width: 1,
            height: 1,
            depth_or_array_layers: 1,
        },
    );
    queue.submit(Some(encoder.finish()));
    let slice = buffer.slice(..bytes_per_row as u64);
    let (tx, rx) = mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |res| {
        let _ = tx.send(res);
    });
    device.poll(wgpu::Maintain::Wait);
    match rx.recv() {
        Ok(Ok(())) => {}
        _ => {
            buffer.unmap();
            return None;
        }
    }
    let data = slice.get_mapped_range();
    if data.len() < 4 {
        drop(data);
        buffer.unmap();
        return None;
    }
    let pixel = u32::from_le_bytes([data[0], data[1], data[2], data[3]]);
    drop(data);
    buffer.unmap();
    Some(pixel)
}

fn maybe_log_layer_sample(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    layer_texture: &wgpu::Texture,
    layer_index: u32,
    canvas_width: u32,
    canvas_height: u32,
    dirty: (i32, i32, i32, i32),
    tag: &str,
    sample_point: Option<Point2D>,
) {
    if debug::level() < LogLevel::Info {
        return;
    }
    let now = now_ms();
    let last = PIXEL_SAMPLE_LAST_MS.load(Ordering::Relaxed);
    if now.saturating_sub(last) < 200 {
        return;
    }
    PIXEL_SAMPLE_LAST_MS.store(now, Ordering::Relaxed);
    let (left, top, width, height) = dirty;
    if canvas_width == 0 || canvas_height == 0 {
        return;
    }
    let (x_u, y_u, source) = if let Some(point) = sample_point {
        if point.x.is_finite() && point.y.is_finite() {
            let max_x = canvas_width.saturating_sub(1) as f32;
            let max_y = canvas_height.saturating_sub(1) as f32;
            let x = point.x.round().clamp(0.0, max_x) as u32;
            let y = point.y.round().clamp(0.0, max_y) as u32;
            (x, y, "point")
        } else {
            if width <= 0 || height <= 0 {
                return;
            }
            let mut x = left + width / 2;
            let mut y = top + height / 2;
            if x < 0 {
                x = 0;
            }
            if y < 0 {
                y = 0;
            }
            let x_u = (x as u32).min(canvas_width.saturating_sub(1));
            let y_u = (y as u32).min(canvas_height.saturating_sub(1));
            (x_u, y_u, "dirty")
        }
    } else {
        if width <= 0 || height <= 0 {
            return;
        }
        let mut x = left + width / 2;
        let mut y = top + height / 2;
        if x < 0 {
            x = 0;
        }
        if y < 0 {
            y = 0;
        }
        let x_u = (x as u32).min(canvas_width.saturating_sub(1));
        let y_u = (y as u32).min(canvas_height.saturating_sub(1));
        (x_u, y_u, "dirty")
    };
    let Some(pixel) = read_layer_pixel_u32(
        device,
        queue,
        layer_texture,
        layer_index,
        x_u,
        y_u,
    ) else {
        debug::log(
            LogLevel::Warn,
            format_args!(
                "layer sample failed tag={tag} layer={layer_index} x={x_u} y={y_u}"
            ),
        );
        return;
    };
    debug::log(
        LogLevel::Info,
        format_args!(
            "layer sample tag={tag} source={source} layer={layer_index} x={x_u} y={y_u} argb=0x{pixel:08X} dirty=({left},{top},{width},{height})"
        ),
    );
}

fn ease_out_cubic(t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    let inv = 1.0 - t;
    1.0 - inv * inv * inv
}

fn resample_scale_for_backlog(backlog_points: u64) -> f32 {
    let _ = backlog_points;
    1.0
}

const STREAMLINE_PREVIEW_MAX_POINTS: usize = 512;

fn downsample_streamline_points(
    points: &[(Point2D, f32)],
    target_count: usize,
) -> Vec<(Point2D, f32)> {
    let len = points.len();
    if len <= target_count {
        return points.to_vec();
    }
    if target_count <= 1 {
        return vec![points[len.saturating_sub(1)]];
    }
    let last = len - 1;
    let mut output = Vec::with_capacity(target_count);
    for i in 0..target_count {
        let idx = (i * last) / (target_count - 1);
        output.push(points[idx]);
    }
    output
}

fn build_streamline_preview(
    from: &[(Point2D, f32)],
    to: &[(Point2D, f32)],
) -> Option<(Vec<(Point2D, f32)>, Vec<(Point2D, f32)>)> {
    if from.len() != to.len() || from.len() <= STREAMLINE_PREVIEW_MAX_POINTS {
        return None;
    }
    let preview_from = downsample_streamline_points(from, STREAMLINE_PREVIEW_MAX_POINTS);
    let preview_to = downsample_streamline_points(to, preview_from.len());
    if preview_from.len() != preview_to.len() || preview_from.len() < 2 {
        return None;
    }
    Some((preview_from, preview_to))
}

fn has_visible_layer_above(
    active_layer_index: usize,
    layer_visible: &[bool],
    layer_opacity: &[f32],
    layer_count: usize,
) -> bool {
    let count = layer_count
        .min(layer_visible.len())
        .min(layer_opacity.len());
    if active_layer_index + 1 >= count {
        return false;
    }
    for idx in (active_layer_index + 1)..count {
        if !layer_visible.get(idx).copied().unwrap_or(true) {
            continue;
        }
        let opacity = layer_opacity.get(idx).copied().unwrap_or(1.0);
        if opacity > 0.0001 {
            return true;
        }
    }
    false
}

fn brush_shape_index(shape: BrushShape) -> u32 {
    match shape {
        BrushShape::Circle => 0,
        BrushShape::Triangle => 1,
        BrushShape::Square => 2,
        BrushShape::Star => 3,
    }
}

fn can_use_vector_preview(
    brush_settings: &EngineBrushSettings,
    selection_mask_active: bool,
    layer_blend_mode: u32,
    view_flags: u32,
    has_visible_above: bool,
) -> bool {
    if !ENABLE_STREAMLINE_VECTOR_PREVIEW {
        return false;
    }
    if brush_settings.streamline_strength <= 0.0001 {
        return false;
    }
    if brush_settings.custom_mask_enabled {
        return false;
    }
    if selection_mask_active {
        return false;
    }
    if layer_blend_mode != 0 {
        return false;
    }
    if (view_flags & VIEW_FLAG_BLACK_WHITE) != 0 {
        return false;
    }
    if has_visible_above {
        return false;
    }
    true
}

fn preview_use_accumulate(_brush_settings: &EngineBrushSettings) -> bool {
    // Preview is drawn over the composited frame; max blending hides dark strokes
    // on light backgrounds, so use alpha blending for visibility.
    true
}

fn build_preview_config(
    brush_settings: &EngineBrushSettings,
    canvas_width: u32,
    canvas_height: u32,
    view_flags: u32,
    layer_opacity: f32,
) -> PreviewConfig {
    let hollow_ratio = if brush_settings.hollow_enabled {
        brush_settings.hollow_ratio
    } else {
        0.0
    };
    let softness = brush_settings.softness();
    PreviewConfig {
        canvas_width,
        canvas_height,
        brush_shape: brush_shape_index(brush_settings.shape),
        antialias_level: brush_settings.antialias_level,
        color_argb: brush_settings.color_argb,
        erase_mode: brush_settings.erase as u32,
        mirror_x: ((view_flags & VIEW_FLAG_MIRROR) != 0) as u32,
        _pad0: 0,
        hollow_ratio,
        softness,
        layer_opacity: layer_opacity.clamp(0.0, 1.0),
        _pad1: 0.0,
    }
}

fn build_preview_segments(
    samples: &[(Point2D, f32)],
    brush_settings: &EngineBrushSettings,
) -> Vec<PreviewSegment> {
    if samples.is_empty() {
        return Vec::new();
    }
    let (points, radii) = prepare_brush_samples(brush_settings, samples);
    if points.is_empty() || points.len() != radii.len() {
        return Vec::new();
    }
    let supports_rotation = brush_settings.supports_rotation();
    let use_smooth = brush_settings.smooth_rotation && supports_rotation;
    let use_random = brush_settings.random_rotation
        && brush_settings.rotation_jitter > 0.0001
        && supports_rotation;
    let jitter = if brush_settings.rotation_jitter.is_finite() {
        brush_settings.rotation_jitter.clamp(0.0, 1.0)
    } else {
        1.0
    };
    let mut segments: Vec<PreviewSegment> = Vec::with_capacity(points.len() + 2);
    if points.len() == 1 {
        let p0 = points[0];
        let radius = radii[0];
        let mut rotation = 0.0;
        if use_random {
            rotation += brush_random_rotation_radians(p0, brush_settings.rotation_seed) * jitter;
        }
        return vec![PreviewSegment {
            p0: [p0.x, p0.y],
            p1: [p0.x, p0.y],
            r0: radius,
            r1: radius,
            rot_sin: rotation.sin(),
            rot_cos: rotation.cos(),
        }];
    }
    {
        let p0 = points[0];
        let radius = radii[0];
        let mut rotation = if use_smooth {
            (points[1].y - p0.y).atan2(points[1].x - p0.x)
        } else {
            0.0
        };
        if use_random {
            rotation += brush_random_rotation_radians(p0, brush_settings.rotation_seed) * jitter;
        }
        segments.push(PreviewSegment {
            p0: [p0.x, p0.y],
            p1: [p0.x, p0.y],
            r0: radius,
            r1: radius,
            rot_sin: rotation.sin(),
            rot_cos: rotation.cos(),
        });
    }
    for i in 0..points.len().saturating_sub(1) {
        let p0 = points[i];
        let p1 = points[i + 1];
        let r0 = radii[i];
        let r1 = radii[i + 1];
        let mut rotation = if use_smooth {
            (p1.y - p0.y).atan2(p1.x - p0.x)
        } else {
            0.0
        };
        if use_random {
            rotation += brush_random_rotation_radians(p0, brush_settings.rotation_seed) * jitter;
        }
        segments.push(PreviewSegment {
            p0: [p0.x, p0.y],
            p1: [p1.x, p1.y],
            r0,
            r1,
            rot_sin: rotation.sin(),
            rot_cos: rotation.cos(),
        });
    }
    {
        let last = points.len() - 1;
        let p0 = points[last];
        let radius = radii[last];
        let mut rotation = if use_smooth {
            (p0.y - points[last - 1].y).atan2(p0.x - points[last - 1].x)
        } else {
            0.0
        };
        if use_random {
            rotation += brush_random_rotation_radians(p0, brush_settings.rotation_seed) * jitter;
        }
        segments.push(PreviewSegment {
            p0: [p0.x, p0.y],
            p1: [p0.x, p0.y],
            r0: radius,
            r1: radius,
            rot_sin: rotation.sin(),
            rot_cos: rotation.cos(),
        });
    }
    segments
}

fn antialias_feather(level: u32) -> f32 {
    match level {
        0 => 0.0,
        1 => 0.7,
        2 => 1.1,
        3 => 1.6,
        4 => 1.9,
        5 => 2.2,
        6 => 2.5,
        7 => 2.8,
        8 => 3.1,
        _ => 3.4,
    }
}

fn compute_spray_dirty_rect(
    points: &[SprayPoint],
    canvas_width: u32,
    canvas_height: u32,
    softness: f32,
    antialias_level: u32,
) -> (i32, i32, i32, i32) {
    if canvas_width == 0 || canvas_height == 0 || points.is_empty() {
        return (0, 0, 0, 0);
    }

    let mut min_x: f32 = f32::INFINITY;
    let mut min_y: f32 = f32::INFINITY;
    let mut max_x: f32 = f32::NEG_INFINITY;
    let mut max_y: f32 = f32::NEG_INFINITY;
    let mut max_r: f32 = 0.0;

    for p in points {
        let x = if p.x.is_finite() { p.x } else { 0.0 };
        let y = if p.y.is_finite() { p.y } else { 0.0 };
        let radius = if p.radius.is_finite() {
            p.radius.max(0.0)
        } else {
            0.0
        };
        min_x = min_x.min(x);
        min_y = min_y.min(y);
        max_x = max_x.max(x);
        max_y = max_y.max(y);
        max_r = max_r.max(radius);
    }

    if !min_x.is_finite() || !min_y.is_finite() || !max_x.is_finite() || !max_y.is_finite() {
        return (0, 0, 0, 0);
    }

    let soft = if softness.is_finite() {
        softness.clamp(0.0, 1.0)
    } else {
        0.0
    };
    let aa = antialias_feather(antialias_level);
    let extra = (max_r * soft).max(aa);
    let pad = max_r + extra + 2.0;

    let left = ((min_x - pad).floor() as i64).clamp(0, canvas_width as i64);
    let top = ((min_y - pad).floor() as i64).clamp(0, canvas_height as i64);
    let right = ((max_x + pad).ceil() as i64).clamp(0, canvas_width as i64);
    let bottom = ((max_y + pad).ceil() as i64).clamp(0, canvas_height as i64);

    let width = (right - left).max(0) as i32;
    let height = (bottom - top).max(0) as i32;
    (left as i32, top as i32, width, height)
}

fn interpolate_streamline_points(
    from: &[(Point2D, f32)],
    to: &[(Point2D, f32)],
    t: f32,
    out: &mut Vec<(Point2D, f32)>,
) {
    out.clear();
    if from.len() != to.len() || from.is_empty() {
        out.extend_from_slice(to);
        return;
    }
    let t = t.clamp(0.0, 1.0);
    out.reserve(from.len());
    for (orig, smooth) in from.iter().zip(to.iter()) {
        let x = orig.0.x + (smooth.0.x - orig.0.x) * t;
        let y = orig.0.y + (smooth.0.y - orig.0.y) * t;
        let blended = orig.1 + (smooth.1 - orig.1) * t;
        let pres = if blended.is_finite() {
            blended.clamp(0.0, 1.0)
        } else {
            orig.1
        };
        out.push((Point2D { x, y }, pres));
    }
}

fn render_streamline_frame(
    animation: &mut StreamlineAnimation,
    t: f32,
    stroke: &mut StrokeResampler,
    brush: &mut Option<BrushRenderer>,
    device: &Arc<wgpu::Device>,
    queue: &Arc<wgpu::Queue>,
    layers: &LayerTextures,
    undo_manager: &mut UndoManager,
    layer_uniform: &mut Vec<Option<u32>>,
    canvas_width: u32,
    canvas_height: u32,
) -> bool {
    let brush_ref = match ensure_brush(brush, device, queue, canvas_width, canvas_height) {
        Ok(brush_ref) => brush_ref,
        Err(err) => {
            debug::log(
                LogLevel::Warn,
                format_args!("BrushRenderer init failed: {err}"),
            );
            return false;
        }
    };
    let layer_idx = animation.layer_index as usize;
    let Some(active_layer_view) = layers
        .layer_view(layer_idx)
        .or_else(|| layers.layer_view(0))
    else {
        return false;
    };
    let layer_texture = layers.texture();
    if !undo_manager.restore_current_before(device.as_ref(), queue.as_ref(), layer_texture) {
        if debug::level() >= LogLevel::Info {
            debug::log(
                LogLevel::Info,
                format_args!("streamline restore skipped: no undo tiles"),
            );
        }
        return false;
    }
    if animation.use_hollow_mask {
        if let Err(err) = brush_ref.clear_stroke_mask() {
            debug::log(
                LogLevel::Warn,
                format_args!("Brush stroke mask clear failed: {err}"),
            );
        }
        brush_ref.begin_stroke_base_capture();
    }
    let (from_points, to_points) = if t >= 0.999 {
        (&animation.from_points, &animation.to_points)
    } else if let (Some(preview_from), Some(preview_to)) = (
        animation.preview_from_points.as_ref(),
        animation.preview_to_points.as_ref(),
    ) {
        (preview_from, preview_to)
    } else {
        (&animation.from_points, &animation.to_points)
    };
    interpolate_streamline_points(from_points, to_points, t, &mut animation.scratch);
    if animation.scratch.is_empty() {
        return false;
    }
    let mut before_draw = |brush: &mut BrushRenderer, dirty_rect| {
        if let Err(err) =
            brush.prepare_layer_read(layer_texture, animation.layer_index, dirty_rect)
        {
            debug::log(
                LogLevel::Warn,
                format_args!("Brush layer read prep failed: {err}"),
            );
        }
        undo_manager.capture_before_for_dirty_rect(
            device.as_ref(),
            queue.as_ref(),
            layer_texture,
            animation.layer_index,
            dirty_rect,
        );
        if animation.use_hollow_base {
            if let Err(err) =
                brush.capture_stroke_base_region(layer_texture, animation.layer_index, dirty_rect)
            {
                debug::log(
                    LogLevel::Warn,
                    format_args!("Brush stroke base capture failed: {err}"),
                );
            }
        }
    };
    let drawn_any = stroke.draw_emitted_points(
        brush_ref,
        &animation.brush_settings,
        active_layer_view,
        &animation.scratch,
        canvas_width,
        canvas_height,
        &mut before_draw,
    );
    if debug::level() >= LogLevel::Info {
        debug::log(
            LogLevel::Info,
            format_args!(
                "streamline frame t={:.3} points={} drawn={}",
                t,
                animation.scratch.len(),
                drawn_any
            ),
        );
    }
    if drawn_any {
        if let Some(entry) = layer_uniform.get_mut(layer_idx) {
            *entry = None;
        }
        if let Some(dirty) = stroke.last_tick_dirty() {
            maybe_log_layer_sample(
                device.as_ref(),
                queue.as_ref(),
                layer_texture,
                animation.layer_index,
                canvas_width,
                canvas_height,
                dirty,
                "streamline",
                stroke.last_tick_point(),
            );
        }
    }
    drawn_any
}

fn commit_preview_stroke(
    stroke: &mut StrokeResampler,
    brush: &mut Option<BrushRenderer>,
    brush_settings: &EngineBrushSettings,
    points: &[(Point2D, f32)],
    layer_index: u32,
    layers: &LayerTextures,
    undo_manager: &mut UndoManager,
    layer_uniform: &mut Vec<Option<u32>>,
    device: &Arc<wgpu::Device>,
    queue: &Arc<wgpu::Queue>,
    canvas_width: u32,
    canvas_height: u32,
) -> bool {
    if points.is_empty() {
        return false;
    }
    let brush_ref = match ensure_brush(brush, device, queue, canvas_width, canvas_height) {
        Ok(brush_ref) => brush_ref,
        Err(err) => {
            debug::log(
                LogLevel::Warn,
                format_args!("BrushRenderer init failed: {err}"),
            );
            return false;
        }
    };
    let layer_idx = layer_index as usize;
    let Some(active_layer_view) = layers
        .layer_view(layer_idx)
        .or_else(|| layers.layer_view(0))
    else {
        return false;
    };
    let layer_texture = layers.texture();
    undo_manager.begin_stroke(layer_index);
    let use_hollow_mask = brush_settings.hollow_enabled
        && !brush_settings.erase
        && brush_settings.hollow_ratio > 0.0001;
    if use_hollow_mask {
        if let Err(err) = brush_ref.clear_stroke_mask() {
            debug::log(
                LogLevel::Warn,
                format_args!("Brush stroke mask clear failed: {err}"),
            );
        }
        brush_ref.begin_stroke_base_capture();
    }
    let use_hollow_base = use_hollow_mask && !brush_settings.hollow_erase_occluded;
    let mut before_draw = |brush: &mut BrushRenderer, dirty_rect| {
        if let Err(err) = brush.prepare_layer_read(layer_texture, layer_index, dirty_rect) {
            debug::log(
                LogLevel::Warn,
                format_args!("Brush layer read prep failed: {err}"),
            );
        }
        undo_manager.capture_before_for_dirty_rect(
            device.as_ref(),
            queue.as_ref(),
            layer_texture,
            layer_index,
            dirty_rect,
        );
        if use_hollow_base {
            if let Err(err) =
                brush.capture_stroke_base_region(layer_texture, layer_index, dirty_rect)
            {
                debug::log(
                    LogLevel::Warn,
                    format_args!("Brush stroke base capture failed: {err}"),
                );
            }
        }
    };
    let drawn_any = stroke.draw_emitted_points(
        brush_ref,
        brush_settings,
        active_layer_view,
        points,
        canvas_width,
        canvas_height,
        &mut before_draw,
    );
    undo_manager.end_stroke(device.as_ref(), queue.as_ref(), layer_texture);
    if drawn_any {
        if let Some(entry) = layer_uniform.get_mut(layer_idx) {
            *entry = None;
        }
    }
    drawn_any
}

fn spawn_render_thread(
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    layer_textures: LayerTextures,
    cmd_rx: mpsc::Receiver<EngineCommand>,
    input_rx: mpsc::Receiver<EngineInputBatch>,
    frame_ready: Arc<AtomicBool>,
    frame_in_flight: Arc<AtomicBool>,
    input_queue_len: Arc<AtomicU64>,
    canvas_width: u32,
    canvas_height: u32,
) {
    let _ = thread::Builder::new()
        .name("misa-rin-canvas-render".to_string())
        .spawn(move || {
            render_thread_main(
                device,
                queue,
                layer_textures,
                cmd_rx,
                input_rx,
                frame_ready,
                frame_in_flight,
                input_queue_len,
                canvas_width,
                canvas_height,
            )
        });
}

fn render_thread_main(
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    layer_textures: LayerTextures,
    cmd_rx: mpsc::Receiver<EngineCommand>,
    input_rx: mpsc::Receiver<EngineInputBatch>,
    frame_ready: Arc<AtomicBool>,
    frame_in_flight: Arc<AtomicBool>,
    input_queue_len: Arc<AtomicU64>,
    canvas_width: u32,
    canvas_height: u32,
) {
    let mut canvas_width = canvas_width;
    let mut canvas_height = canvas_height;
    let mut present: Option<PresentTarget> = None;
    let mut layers = layer_textures;
    if layers.capacity() == 0 {
        return;
    }
    // Layer order is bottom-to-top.
    let mut layer_count: usize = 1;
    let mut active_layer_index: usize = 0;
    let mut layer_uniform: Vec<Option<u32>> = vec![None; layer_count];

    let mut brush: Option<BrushRenderer> = None;
    let mut brush_settings = EngineBrushSettings::default();

    let mut bucket_fill_renderer: Option<BucketFillRenderer> = None;
    let mut filter_renderer: Option<FilterRenderer> = None;

    let present_renderer = PresentRenderer::new(device.as_ref());
    let mut layer_opacity: Vec<f32> = vec![1.0; layer_count];
    let mut layer_visible: Vec<bool> = vec![true; layer_count];
    let mut layer_clipping_mask: Vec<bool> = vec![false; layer_count];
    let mut layer_blend_mode: Vec<u32> = vec![0; layer_count];
    let mut view_flags: u32 = 0;
    let present_config_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("misa-rin present composite config"),
        size: std::mem::size_of::<super::present::PresentCompositeHeader>() as u64,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let present_transform_buffer = create_present_transform_buffer(device.as_ref());
    let mut transform_matrix: [f32; 16] = [
        1.0, 0.0, 0.0, 0.0, //
        0.0, 1.0, 0.0, 0.0, //
        0.0, 0.0, 1.0, 0.0, //
        0.0, 0.0, 0.0, 1.0, //
    ];
    let mut transform_layer_index: u32 = 0;
    let mut transform_flags: u32 = 0;
    let mut present_params_capacity = layers.capacity();
    let mut present_params_buffer =
        match create_present_params_buffer(device.as_ref(), present_params_capacity) {
            Ok(buffer) => buffer,
            Err(err) => {
                debug::log(
                    LogLevel::Warn,
                    format_args!("Present params buffer init failed: {err}"),
                );
                return;
            }
        };
    write_present_config(
        queue.as_ref(),
        &present_config_buffer,
        &present_params_buffer,
        layer_count,
        view_flags,
        transform_layer_index,
        transform_flags,
        &layer_opacity,
        &layer_visible,
        &layer_clipping_mask,
        &layer_blend_mode,
    );
    write_present_transform(queue.as_ref(), &present_transform_buffer, transform_matrix);
    let mut present_bind_group = present_renderer.create_bind_group(
        device.as_ref(),
        layers.array_view(),
        &present_config_buffer,
        &present_params_buffer,
        &present_transform_buffer,
    );

    let mut stroke = StrokeResampler::new();
    let mut undo_manager = UndoManager::new(canvas_width, canvas_height);
    let mut transform_renderer: Option<LayerTransformRenderer> = None;
    let mut streamline_animation: Option<StreamlineAnimation> = None;
    let mut preview_renderer: Option<PreviewRenderer> = None;
    let mut preview_state: Option<PreviewStrokeState> = None;
    let mut selection_mask_active = false;
    let mut spray_active_layer: Option<u32> = None;
    let mut pending_present = false;
    let mut pending_present_since: Option<Instant> = None;
    let mut deferred_reads: Vec<EngineCommand> = Vec::new();

    loop {
        let mut needs_render = false;
        while let Ok(cmd) = cmd_rx.try_recv() {
            if present.is_none()
                && matches!(
                    cmd,
                    EngineCommand::ReadLayer { .. }
                        | EngineCommand::ReadLayerPreview { .. }
                        | EngineCommand::ReadPresent { .. }
                )
            {
                deferred_reads.push(cmd);
                continue;
            }
            if let Some(mut animation) = streamline_animation.take() {
                if let Some(state) = preview_state.take() {
                    let committed = commit_preview_stroke(
                        &mut stroke,
                        &mut brush,
                        &state.brush_settings,
                        &animation.to_points,
                        state.layer_index,
                        &layers,
                        &mut undo_manager,
                        &mut layer_uniform,
                        &device,
                        &queue,
                        canvas_width,
                        canvas_height,
                    );
                    if committed {
                        needs_render = true;
                    }
                } else {
                    let frame_drawn = render_streamline_frame(
                        &mut animation,
                        1.0,
                        &mut stroke,
                        &mut brush,
                        &device,
                        &queue,
                        &layers,
                        &mut undo_manager,
                        &mut layer_uniform,
                        canvas_width,
                        canvas_height,
                    );
                    undo_manager
                        .end_stroke(device.as_ref(), queue.as_ref(), layers.texture());
                    if frame_drawn {
                        if let Some(entry) = layer_uniform.get_mut(active_layer_index) {
                            *entry = None;
                        }
                        needs_render = true;
                    }
                }
            }
            let outcome = handle_engine_command(
                &device,
                &queue,
                &mut present,
                cmd,
                &mut bucket_fill_renderer,
                &mut filter_renderer,
                &mut layers,
                &mut layer_count,
                &mut active_layer_index,
                &mut layer_opacity,
                &mut layer_visible,
                &mut layer_clipping_mask,
                &mut layer_blend_mode,
                &mut layer_uniform,
                &mut view_flags,
                &present_renderer,
                &present_config_buffer,
                &present_transform_buffer,
                &mut transform_matrix,
                &mut transform_layer_index,
                &mut transform_flags,
                &mut present_params_buffer,
                &mut present_params_capacity,
                &mut present_bind_group,
                &mut transform_renderer,
                &mut brush,
                &mut brush_settings,
                &mut stroke,
                &mut selection_mask_active,
                &mut spray_active_layer,
                &mut undo_manager,
                canvas_width,
                canvas_height,
            );
            if outcome.stop {
                return;
            }
            if let Some((new_width, new_height)) = outcome.new_canvas_size {
                canvas_width = new_width;
                canvas_height = new_height;
                stroke = StrokeResampler::new();
            }
            needs_render |= outcome.needs_render;
        }

        let mut batches: Vec<EngineInputBatch> = Vec::new();
        let mut next_timeout = if present.is_some() {
            Duration::from_millis(4)
        } else {
            Duration::from_millis(16)
        };
        if let Some(anim) = streamline_animation.as_ref() {
            let now = Instant::now();
            if now >= anim.next_frame_at {
                next_timeout = Duration::from_millis(0);
            } else {
                let until = anim.next_frame_at.saturating_duration_since(now);
                if until < next_timeout {
                    next_timeout = until;
                }
            }
        }
        match input_rx.recv_timeout(next_timeout) {
            Ok(batch) => {
                input_queue_len.fetch_sub(batch.points.len() as u64, Ordering::Relaxed);
                batches.push(batch);
                while let Ok(more) = input_rx.try_recv() {
                    input_queue_len.fetch_sub(more.points.len() as u64, Ordering::Relaxed);
                    batches.push(more);
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => return,
        }

        if present.is_none() {
            while let Ok(cmd) = cmd_rx.try_recv() {
                if matches!(
                    cmd,
                    EngineCommand::ReadLayer { .. }
                        | EngineCommand::ReadLayerPreview { .. }
                        | EngineCommand::ReadPresent { .. }
                ) {
                    deferred_reads.push(cmd);
                    continue;
                }
                if let Some(mut animation) = streamline_animation.take() {
                    if let Some(state) = preview_state.take() {
                        let committed = commit_preview_stroke(
                            &mut stroke,
                            &mut brush,
                            &state.brush_settings,
                            &animation.to_points,
                            state.layer_index,
                            &layers,
                            &mut undo_manager,
                            &mut layer_uniform,
                            &device,
                            &queue,
                            canvas_width,
                            canvas_height,
                        );
                        if committed {
                            needs_render = true;
                        }
                    } else {
                        let frame_drawn = render_streamline_frame(
                            &mut animation,
                            1.0,
                            &mut stroke,
                            &mut brush,
                            &device,
                            &queue,
                            &layers,
                            &mut undo_manager,
                            &mut layer_uniform,
                            canvas_width,
                            canvas_height,
                        );
                        undo_manager
                            .end_stroke(device.as_ref(), queue.as_ref(), layers.texture());
                        if frame_drawn {
                            if let Some(entry) = layer_uniform.get_mut(active_layer_index) {
                                *entry = None;
                            }
                            needs_render = true;
                        }
                    }
                }
                let outcome = handle_engine_command(
                    &device,
                    &queue,
                    &mut present,
                    cmd,
                    &mut bucket_fill_renderer,
                    &mut filter_renderer,
                    &mut layers,
                    &mut layer_count,
                    &mut active_layer_index,
                    &mut layer_opacity,
                    &mut layer_visible,
                    &mut layer_clipping_mask,
                    &mut layer_blend_mode,
                    &mut layer_uniform,
                    &mut view_flags,
                    &present_renderer,
                    &present_config_buffer,
                    &present_transform_buffer,
                    &mut transform_matrix,
                    &mut transform_layer_index,
                    &mut transform_flags,
                    &mut present_params_buffer,
                    &mut present_params_capacity,
                    &mut present_bind_group,
                    &mut transform_renderer,
                    &mut brush,
                    &mut brush_settings,
                    &mut stroke,
                    &mut selection_mask_active,
                    &mut spray_active_layer,
                    &mut undo_manager,
                    canvas_width,
                    canvas_height,
                );
                if outcome.stop {
                    return;
                }
                if let Some((new_width, new_height)) = outcome.new_canvas_size {
                    canvas_width = new_width;
                    canvas_height = new_height;
                    stroke = StrokeResampler::new();
                }
                needs_render |= outcome.needs_render;
            }
        }

        if !batches.is_empty() {
            const FLAG_DOWN: u32 = 1;
            const FLAG_UP: u32 = 4;
            let mut raw_points: Vec<EnginePoint> = Vec::new();
            for batch in batches {
                raw_points.extend(batch.points);
            }
            let backlog_points =
                raw_points.len() as u64 + input_queue_len.load(Ordering::Relaxed);
            stroke.set_resample_scale(resample_scale_for_backlog(backlog_points));
            let layer_blend_mode_value =
                layer_blend_mode.get(active_layer_index).copied().unwrap_or(0);
            let has_visible_above = has_visible_layer_above(
                active_layer_index,
                &layer_visible,
                &layer_opacity,
                layer_count,
            );
            let preview_allowed = present.is_some()
                && can_use_vector_preview(
                    &brush_settings,
                    selection_mask_active,
                    layer_blend_mode_value,
                    view_flags,
                    has_visible_above,
                );
            let preview_active = preview_state.is_some() || preview_allowed;
            let has_down = raw_points.iter().any(|p| (p.flags & FLAG_DOWN) != 0);
            let has_up = raw_points.iter().any(|p| (p.flags & FLAG_UP) != 0);
            if debug::level() >= LogLevel::Info && (has_down || has_up) {
                debug::log(
                    LogLevel::Info,
                    format_args!(
                        "input batch points={} down={} up={} active_layer={} preview_allowed={}",
                        raw_points.len(),
                        has_down,
                        has_up,
                        active_layer_index,
                        preview_allowed
                    ),
                );
            }
            if has_down {
                if let Some(mut animation) = streamline_animation.take() {
                    if let Some(state) = preview_state.take() {
                        let committed = commit_preview_stroke(
                            &mut stroke,
                            &mut brush,
                            &state.brush_settings,
                            &animation.to_points,
                            state.layer_index,
                            &layers,
                            &mut undo_manager,
                            &mut layer_uniform,
                            &device,
                            &queue,
                            canvas_width,
                            canvas_height,
                        );
                        if committed {
                            needs_render = true;
                        }
                    } else {
                        let _ = render_streamline_frame(
                            &mut animation,
                            1.0,
                            &mut stroke,
                            &mut brush,
                            &device,
                            &queue,
                            &layers,
                            &mut undo_manager,
                            &mut layer_uniform,
                            canvas_width,
                            canvas_height,
                        );
                        undo_manager.end_stroke(
                            device.as_ref(),
                            queue.as_ref(),
                            layers.texture(),
                        );
                        if let Some(entry) = layer_uniform.get_mut(active_layer_index) {
                            *entry = None;
                        }
                        needs_render = true;
                    }
                }
            }

            if preview_active {
                let mut segment: Vec<EnginePoint> = Vec::new();
                let mut preview_updated = false;
                for p in raw_points {
                    let is_down = (p.flags & FLAG_DOWN) != 0;
                    let is_up = (p.flags & FLAG_UP) != 0;

                    if is_down && preview_state.is_none() && preview_allowed {
                        preview_state = Some(PreviewStrokeState {
                            layer_index: active_layer_index as u32,
                            brush_settings,
                            points: Vec::new(),
                            use_accumulate: preview_use_accumulate(&brush_settings),
                        });
                    }

                    segment.push(p);

                    if is_up {
                        if let Some(state) = preview_state.as_mut() {
                            let emitted = stroke.consume_points(
                                &state.brush_settings,
                                std::mem::take(&mut segment),
                            );
                            if !emitted.is_empty() {
                                state.points.extend(emitted);
                                preview_updated = true;
                            }
                        } else {
                            segment.clear();
                        }

                        if let Some(payload) = stroke.take_streamline_payload() {
                            let mut from_points = payload.points;
                            let strength = payload.strength;
                            if let Some(state) = preview_state.as_ref() {
                                if state.points.len() == from_points.len()
                                    && !state.points.is_empty()
                                {
                                    from_points = state.points.clone();
                                }
                            }
                            if from_points.len() > 2 && strength > 0.0001 {
                                let smoothed = apply_streamline(&from_points, strength);
                                if !smoothed.is_empty()
                                    && smoothed.len() == from_points.len()
                                {
                                    let duration =
                                        streamline_animation_duration(strength);
                                    let (preview_from, preview_to, preview_len) =
                                        match build_streamline_preview(
                                            &from_points, &smoothed,
                                        ) {
                                            Some((preview_from, preview_to)) => {
                                                let len = preview_from.len();
                                                (
                                                    Some(preview_from),
                                                    Some(preview_to),
                                                    len,
                                                )
                                            }
                                            None => (None, None, from_points.len()),
                                        };
                                    if debug::level() >= LogLevel::Info {
                                        debug::log(
                                            LogLevel::Info,
                                            format_args!(
                                                "streamline start points={} preview_points={} strength={:.3} duration_ms={}",
                                                from_points.len(),
                                                preview_len,
                                                strength,
                                                duration.as_millis()
                                            ),
                                        );
                                    }
                                    let now = Instant::now();
                                    streamline_animation = Some(StreamlineAnimation {
                                        start: now,
                                        duration,
                                        next_frame_at: now,
                                        frame_interval: Duration::from_millis(16),
                                        pending_first_frame: true,
                                        from_points,
                                        to_points: smoothed,
                                        preview_from_points: preview_from,
                                        preview_to_points: preview_to,
                                        scratch: Vec::new(),
                                        layer_index: active_layer_index as u32,
                                        brush_settings,
                                        use_hollow_mask: false,
                                        use_hollow_base: false,
                                    });
                                }
                            }
                        } else if let Some(state) = preview_state.take() {
                            let committed = commit_preview_stroke(
                                &mut stroke,
                                &mut brush,
                                &state.brush_settings,
                                &state.points,
                                state.layer_index,
                                &layers,
                                &mut undo_manager,
                                &mut layer_uniform,
                                &device,
                                &queue,
                                canvas_width,
                                canvas_height,
                            );
                            if committed {
                                needs_render = true;
                            }
                        }
                    }
                }

                if !segment.is_empty() {
                    if let Some(state) = preview_state.as_mut() {
                        let emitted =
                            stroke.consume_points(&state.brush_settings, segment);
                        if !emitted.is_empty() {
                            state.points.extend(emitted);
                            preview_updated = true;
                        }
                    }
                }

                if preview_updated {
                    needs_render = true;
                }
            } else {
                let brush_ref = match ensure_brush(
                    &mut brush,
                    &device,
                    &queue,
                    canvas_width,
                    canvas_height,
                ) {
                    Ok(brush_ref) => brush_ref,
                    Err(err) => {
                        debug::log(
                            LogLevel::Warn,
                            format_args!("BrushRenderer init failed: {err}"),
                        );
                        stroke = StrokeResampler::new();
                        continue;
                    }
                };

                let active_layer_view = layers
                    .layer_view(active_layer_index)
                    .or_else(|| layers.layer_view(0))
                    .expect("layers non-empty");
                let layer_texture = layers.texture();
                let mut segment: Vec<EnginePoint> = Vec::new();
                let mut drawn_any = false;

                for p in raw_points {
                    let is_down = (p.flags & FLAG_DOWN) != 0;
                    let is_up = (p.flags & FLAG_UP) != 0;

                    if is_down {
                        undo_manager.begin_stroke(active_layer_index as u32);
                        let use_hollow_mask = brush_settings.hollow_enabled
                            && !brush_settings.erase
                            && brush_settings.hollow_ratio > 0.0001;
                        if use_hollow_mask {
                            if let Err(err) = brush_ref.clear_stroke_mask() {
                                debug::log(
                                    LogLevel::Warn,
                                    format_args!("Brush stroke mask clear failed: {err}"),
                                );
                            }
                            brush_ref.begin_stroke_base_capture();
                        }
                    } else {
                        undo_manager.begin_stroke_if_needed(active_layer_index as u32);
                    }

                    segment.push(p);

                    if is_up {
                        let layer_idx = active_layer_index as u32;
                        let use_hollow_mask = brush_settings.hollow_enabled
                            && !brush_settings.erase
                            && brush_settings.hollow_ratio > 0.0001;
                        let use_hollow_base =
                            use_hollow_mask && !brush_settings.hollow_erase_occluded;
                        let mut defer_end_stroke = false;
                        let segment_drawn = {
                            let mut before_draw =
                                |brush: &mut BrushRenderer, dirty_rect| {
                                    if let Err(err) = brush.prepare_layer_read(
                                        layer_texture,
                                        layer_idx,
                                        dirty_rect,
                                    ) {
                                        debug::log(
                                            LogLevel::Warn,
                                            format_args!(
                                                "Brush layer read prep failed: {err}"
                                            ),
                                        );
                                    }
                                    undo_manager.capture_before_for_dirty_rect(
                                        device.as_ref(),
                                        queue.as_ref(),
                                        layer_texture,
                                        layer_idx,
                                        dirty_rect,
                                    );
                                    if use_hollow_base {
                                        if let Err(err) =
                                            brush.capture_stroke_base_region(
                                                layer_texture,
                                                layer_idx,
                                                dirty_rect,
                                            )
                                        {
                                            debug::log(
                                                LogLevel::Warn,
                                                format_args!(
                                                    "Brush stroke base capture failed: {err}"
                                                ),
                                            );
                                        }
                                    }
                                };
                            stroke.consume_and_draw(
                                brush_ref,
                                &brush_settings,
                                active_layer_view,
                                std::mem::take(&mut segment),
                                canvas_width,
                                canvas_height,
                                &mut before_draw,
                            )
                        };
                        if segment_drawn && brush_settings.streamline_strength > 0.0001 {
                            if let Some(dirty) = stroke.last_tick_dirty() {
                                maybe_log_layer_sample(
                                    device.as_ref(),
                                    queue.as_ref(),
                                    layer_texture,
                                    layer_idx,
                                    canvas_width,
                                    canvas_height,
                                    dirty,
                                    "stroke",
                                    stroke.last_tick_point(),
                                );
                            }
                        }
                        drawn_any |= segment_drawn;

                        if let Some(payload) = stroke.take_streamline_payload() {
                            let from_points = payload.points;
                            let strength = payload.strength;
                            if from_points.len() > 2 && strength > 0.0001 {
                                let smoothed = apply_streamline(&from_points, strength);
                                if !smoothed.is_empty()
                                    && smoothed.len() == from_points.len()
                                {
                                    let duration =
                                        streamline_animation_duration(strength);
                                    let (preview_from, preview_to, preview_len) =
                                        match build_streamline_preview(
                                            &from_points, &smoothed,
                                        ) {
                                            Some((preview_from, preview_to)) => {
                                                let len = preview_from.len();
                                                (
                                                    Some(preview_from),
                                                    Some(preview_to),
                                                    len,
                                                )
                                            }
                                            None => (None, None, from_points.len()),
                                        };
                                    if debug::level() >= LogLevel::Info {
                                        debug::log(
                                            LogLevel::Info,
                                            format_args!(
                                                "streamline start points={} preview_points={} strength={:.3} duration_ms={}",
                                                from_points.len(),
                                                preview_len,
                                                strength,
                                                duration.as_millis()
                                            ),
                                        );
                                    }
                                    let now = Instant::now();
                                    streamline_animation = Some(StreamlineAnimation {
                                        start: now,
                                        duration,
                                        next_frame_at: now,
                                        frame_interval: Duration::from_millis(16),
                                        pending_first_frame: true,
                                        from_points,
                                        to_points: smoothed,
                                        preview_from_points: preview_from,
                                        preview_to_points: preview_to,
                                        scratch: Vec::new(),
                                        layer_index: layer_idx,
                                        brush_settings,
                                        use_hollow_mask,
                                        use_hollow_base,
                                    });
                                    defer_end_stroke = true;
                                }
                            }
                        }
                        if !defer_end_stroke {
                            undo_manager.end_stroke(
                                device.as_ref(),
                                queue.as_ref(),
                                layer_texture,
                            );
                        }
                    }
                }

                if !segment.is_empty() {
                    let layer_idx = active_layer_index as u32;
                    let use_hollow_base = brush_settings.hollow_enabled
                        && !brush_settings.erase
                        && brush_settings.hollow_ratio > 0.0001
                        && !brush_settings.hollow_erase_occluded;
                    let mut before_draw = |brush: &mut BrushRenderer, dirty_rect| {
                        if let Err(err) =
                            brush.prepare_layer_read(layer_texture, layer_idx, dirty_rect)
                        {
                            debug::log(
                                LogLevel::Warn,
                                format_args!(
                                    "Brush layer read prep failed: {err}"
                                ),
                            );
                        }
                        undo_manager.capture_before_for_dirty_rect(
                            device.as_ref(),
                            queue.as_ref(),
                            layer_texture,
                            layer_idx,
                            dirty_rect,
                        );
                        if use_hollow_base {
                            if let Err(err) = brush.capture_stroke_base_region(
                                layer_texture,
                                layer_idx,
                                dirty_rect,
                            ) {
                                debug::log(
                                    LogLevel::Warn,
                                    format_args!(
                                        "Brush stroke base capture failed: {err}"
                                    ),
                                );
                            }
                        }
                    };
                    let segment_drawn = stroke.consume_and_draw(
                        brush_ref,
                        &brush_settings,
                        active_layer_view,
                        segment,
                        canvas_width,
                        canvas_height,
                        &mut before_draw,
                    );
                    if segment_drawn && brush_settings.streamline_strength > 0.0001 {
                        if let Some(dirty) = stroke.last_tick_dirty() {
                            maybe_log_layer_sample(
                                device.as_ref(),
                                queue.as_ref(),
                                layer_texture,
                                layer_idx,
                                canvas_width,
                                canvas_height,
                                dirty,
                                "stroke",
                                stroke.last_tick_point(),
                            );
                        }
                    }
                    drawn_any |= segment_drawn;
                }

                if drawn_any {
                    if let Some(entry) = layer_uniform.get_mut(active_layer_index) {
                        *entry = None;
                    }
                }
                needs_render |= drawn_any;
            }
        }

        let mut clear_animation = false;
        if let Some(animation) = streamline_animation.as_mut() {
            let now = Instant::now();
            if animation.pending_first_frame {
                animation.pending_first_frame = false;
                animation.start = now;
                animation.next_frame_at = now + animation.frame_interval;
            } else if animation.should_render(now) {
                let mut t = ease_out_cubic(animation.progress(now));
                let done = t >= 0.999;
                if done {
                    t = 1.0;
                }
                if preview_state.is_some() {
                    let (from_points, to_points) = if t >= 0.999 {
                        (&animation.from_points, &animation.to_points)
                    } else if let (Some(preview_from), Some(preview_to)) = (
                        animation.preview_from_points.as_ref(),
                        animation.preview_to_points.as_ref(),
                    ) {
                        (preview_from, preview_to)
                    } else {
                        (&animation.from_points, &animation.to_points)
                    };
                    interpolate_streamline_points(
                        from_points,
                        to_points,
                        t,
                        &mut animation.scratch,
                    );
                    if debug::level() >= LogLevel::Info {
                        debug::log(
                            LogLevel::Info,
                            format_args!(
                                "streamline preview t={:.3} points={}",
                                t,
                                animation.scratch.len()
                            ),
                        );
                    }
                    if !animation.scratch.is_empty() {
                        needs_render = true;
                    }
                    if done {
                        if let Some(state) = preview_state.take() {
                            let committed = commit_preview_stroke(
                                &mut stroke,
                                &mut brush,
                                &state.brush_settings,
                                &animation.to_points,
                                state.layer_index,
                                &layers,
                                &mut undo_manager,
                                &mut layer_uniform,
                                &device,
                                &queue,
                                canvas_width,
                                canvas_height,
                            );
                            if committed {
                                needs_render = true;
                            }
                        }
                        clear_animation = true;
                    }
                } else {
                    let frame_drawn = render_streamline_frame(
                        animation,
                        t,
                        &mut stroke,
                        &mut brush,
                        &device,
                        &queue,
                        &layers,
                        &mut undo_manager,
                        &mut layer_uniform,
                        canvas_width,
                        canvas_height,
                    );
                    if frame_drawn {
                        needs_render = true;
                    }
                    if done {
                        undo_manager.end_stroke(
                            device.as_ref(),
                            queue.as_ref(),
                            layers.texture(),
                        );
                        clear_animation = true;
                    }
                }
            }
        }
        if clear_animation {
            streamline_animation = None;
        }

        if !deferred_reads.is_empty()
            && input_queue_len.load(Ordering::Relaxed) == 0
        {
            let pending = std::mem::take(&mut deferred_reads);
            for cmd in pending {
                let outcome = handle_engine_command(
                    &device,
                    &queue,
                    &mut present,
                    cmd,
                    &mut bucket_fill_renderer,
                    &mut filter_renderer,
                    &mut layers,
                    &mut layer_count,
                    &mut active_layer_index,
                    &mut layer_opacity,
                    &mut layer_visible,
                    &mut layer_clipping_mask,
                    &mut layer_blend_mode,
                    &mut layer_uniform,
                    &mut view_flags,
                    &present_renderer,
                    &present_config_buffer,
                    &present_transform_buffer,
                    &mut transform_matrix,
                    &mut transform_layer_index,
                    &mut transform_flags,
                    &mut present_params_buffer,
                    &mut present_params_capacity,
                    &mut present_bind_group,
                    &mut transform_renderer,
                    &mut brush,
                    &mut brush_settings,
                    &mut stroke,
                    &mut selection_mask_active,
                    &mut spray_active_layer,
                    &mut undo_manager,
                    canvas_width,
                    canvas_height,
                );
                if outcome.stop {
                    return;
                }
                if let Some((new_width, new_height)) = outcome.new_canvas_size {
                    canvas_width = new_width;
                    canvas_height = new_height;
                    stroke = StrokeResampler::new();
                }
                needs_render |= outcome.needs_render;
            }
        }

        if needs_render {
            if !pending_present {
                pending_present_since = Some(Instant::now());
            }
            pending_present = true;
        }

        if pending_present {
            if let Some(target) = &present {
                let mut block_present = if cfg!(target_os = "windows") {
                    frame_in_flight.load(Ordering::Acquire)
                        || frame_ready.load(Ordering::Acquire)
                } else {
                    false
                };
                let mut forced_present = false;
                if block_present && cfg!(target_os = "windows") {
                    if let Some(since) = pending_present_since {
                        if since.elapsed() >= Duration::from_millis(100) {
                            block_present = false;
                            forced_present = true;
                        }
                    }
                }
                if block_present {
                    // Avoid overwriting a frame that is still in-flight or unconsumed.
                } else {
                    #[cfg(target_os = "windows")]
                    if let Some(since) = pending_present_since {
                        record_present_wait(since.elapsed().as_micros() as u64);
                    }
                    pending_present = false;
                    pending_present_since = None;
                    if forced_present {
                        debug::log(
                            LogLevel::Warn,
                            format_args!(
                                "present render forced after stalled ready frame seq={} active_layer={}",
                                debug::next_seq(),
                                active_layer_index,
                            ),
                        );
                    }
                    if debug::level() >= LogLevel::Info {
                        debug::log(
                            LogLevel::Info,
                            format_args!(
                                "present render call seq={} active_layer={} streamline_active={}",
                                debug::next_seq(),
                                active_layer_index,
                                streamline_animation.is_some()
                            ),
                        );
                    }
                    if let Some(state) = preview_state.as_ref() {
                        present_renderer.render_base(
                            device.as_ref(),
                            queue.as_ref(),
                            &present_bind_group,
                            target.render_view(),
                        );
                        let layer_idx = state.layer_index as usize;
                        let layer_visible_value =
                            layer_visible.get(layer_idx).copied().unwrap_or(true);
                        let layer_opacity_value =
                            layer_opacity.get(layer_idx).copied().unwrap_or(1.0);
                        if layer_visible_value && layer_opacity_value > 0.0001 {
                            let preview_points: &[(
                                Point2D,
                                f32,
                            )] = if let Some(animation) = streamline_animation.as_ref() {
                                if animation.scratch.is_empty() {
                                    state.points.as_slice()
                                } else {
                                    animation.scratch.as_slice()
                                }
                            } else {
                                state.points.as_slice()
                            };
                            if !preview_points.is_empty() {
                                let segments = build_preview_segments(
                                    preview_points,
                                    &state.brush_settings,
                                );
                                if !segments.is_empty() {
                                    let preview = preview_renderer.get_or_insert_with(
                                        || PreviewRenderer::new(device.as_ref()),
                                    );
                                    let config = build_preview_config(
                                        &state.brush_settings,
                                        canvas_width,
                                        canvas_height,
                                        view_flags,
                                        layer_opacity_value,
                                    );
                                    preview.render(
                                        device.as_ref(),
                                        queue.as_ref(),
                                        target.render_view(),
                                        config,
                                        &segments,
                                        state.use_accumulate,
                                    );
                                }
                            }
                        }
                        if target.shared_texture().is_some() {
                            let mut encoder = device.create_command_encoder(
                                &wgpu::CommandEncoderDescriptor {
                                    label: Some("misa-rin present copy encoder"),
                                },
                            );
                            copy_render_to_shared(&mut encoder, target);
                            queue.submit(Some(encoder.finish()));
                        }
                        signal_frame_ready(
                            queue.as_ref(),
                            Arc::clone(&frame_ready),
                            Arc::clone(&frame_in_flight),
                        );
                    } else {
                        present_renderer.render_present(
                            device.as_ref(),
                            queue.as_ref(),
                            &present_bind_group,
                            target,
                            Arc::clone(&frame_ready),
                            Arc::clone(&frame_in_flight),
                        );
                    }
                }
            } else {
                pending_present = false;
            }
        }

        device.poll(wgpu::Maintain::Poll);
    }
}

fn handle_engine_command(
    device: &Arc<wgpu::Device>,
    queue: &Arc<wgpu::Queue>,
    present: &mut Option<PresentTarget>,
    cmd: EngineCommand,
    bucket_fill_renderer: &mut Option<BucketFillRenderer>,
    filter_renderer: &mut Option<FilterRenderer>,
    layers: &mut LayerTextures,
    layer_count: &mut usize,
    active_layer_index: &mut usize,
    layer_opacity: &mut Vec<f32>,
    layer_visible: &mut Vec<bool>,
    layer_clipping_mask: &mut Vec<bool>,
    layer_blend_mode: &mut Vec<u32>,
    layer_uniform: &mut Vec<Option<u32>>,
    present_view_flags: &mut u32,
    present_renderer: &PresentRenderer,
    present_config_buffer: &wgpu::Buffer,
    present_transform_buffer: &wgpu::Buffer,
    transform_matrix: &mut [f32; 16],
    transform_layer_index: &mut u32,
    transform_flags: &mut u32,
    present_params_buffer: &mut wgpu::Buffer,
    present_params_capacity: &mut usize,
    present_bind_group: &mut wgpu::BindGroup,
    transform_renderer: &mut Option<LayerTransformRenderer>,
    brush: &mut Option<BrushRenderer>,
    brush_settings: &mut EngineBrushSettings,
    stroke: &mut StrokeResampler,
    selection_mask_active: &mut bool,
    spray_active_layer: &mut Option<u32>,
    undo: &mut UndoManager,
    canvas_width: u32,
    canvas_height: u32,
) -> EngineCommandOutcome {
    let mut ensure_layer_index = |layer_count: &mut usize,
                                  idx: usize,
                                  transform_layer_index: u32,
                                  transform_flags: u32|
     -> bool {
        if idx < *layer_count {
            return true;
        }
        let old_count = *layer_count;
        let new_count = idx + 1;
        let resized = match layers.ensure_capacity(device, queue, new_count) {
            Ok(Some(_)) => true,
            Ok(None) => false,
            Err(err) => {
                debug::log(
                    LogLevel::Warn,
                    format_args!("Layer capacity resize failed: {err}"),
                );
                return false;
            }
        };
        if resized {
            *present_params_capacity = layers.capacity();
            match create_present_params_buffer(device, *present_params_capacity) {
                Ok(buffer) => {
                    *present_params_buffer = buffer;
                    *present_bind_group = present_renderer.create_bind_group(
                        device,
                        layers.array_view(),
                        present_config_buffer,
                        present_params_buffer,
                        present_transform_buffer,
                    );
                }
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("Present params buffer resize failed: {err}"),
                    );
                    return false;
                }
            }
        }

        if new_count > layer_opacity.len() {
            layer_opacity.resize(new_count, 1.0);
        }
        if new_count > layer_visible.len() {
            layer_visible.resize(new_count, true);
        }
        if new_count > layer_clipping_mask.len() {
            layer_clipping_mask.resize(new_count, false);
        }
        if new_count > layer_blend_mode.len() {
            layer_blend_mode.resize(new_count, 0);
        }
        if new_count > layer_uniform.len() {
            layer_uniform.resize(new_count, None);
        }

        for layer in old_count..new_count {
            fill_r32uint_texture(
                queue,
                layers.texture(),
                canvas_width,
                canvas_height,
                layer as u32,
                0x00000000,
            );
            layer_uniform[layer] = Some(0x00000000);
        }

        *layer_count = new_count;
        write_present_config(
            queue,
            present_config_buffer,
            present_params_buffer,
            *layer_count,
            *present_view_flags,
            transform_layer_index,
            transform_flags,
            layer_opacity,
            layer_visible,
            layer_clipping_mask,
            layer_blend_mode,
        );
        true
    };

    match cmd {
        EngineCommand::Stop => {
            return EngineCommandOutcome {
                stop: true,
                needs_render: false,
                new_canvas_size: None,
            }
        }
        EngineCommand::AttachPresentTexture {
            mtl_texture_ptr,
            width,
            height,
            bytes_per_row,
        } => {
            if mtl_texture_ptr == 0 || width == 0 || height == 0 {
                debug::log(
                    LogLevel::Warn,
                    format_args!(
                        "AttachPresentTexture ignored: ptr=0x{mtl_texture_ptr:x} size={width}x{height}"
                    ),
                );
                *present = None;
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            *present =
                attach_present_texture(device, mtl_texture_ptr, width, height, bytes_per_row);
            if present.is_some() {
                debug::log(
                    LogLevel::Info,
                    format_args!(
                        "Present texture attached: ptr=0x{mtl_texture_ptr:x} size={width}x{height} bytes_per_row={bytes_per_row}"
                    ),
                );
                // Initialize layers so the first composite is deterministic.
                // Layer 0 is the background fill layer (default white), others start transparent.
                layer_uniform.resize(*layer_count, None);
                for idx in 0..*layer_count {
                    let fill = if idx == 0 { 0xFFFFFFFF } else { 0x00000000 };
                    fill_r32uint_texture(
                        queue,
                        layers.texture(),
                        canvas_width,
                        canvas_height,
                        idx as u32,
                        fill,
                    );
                    if let Some(entry) = layer_uniform.get_mut(idx) {
                        *entry = Some(fill);
                    }
                }
                // Request one render so Flutter gets an actual composited frame immediately.
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: true,
                    new_canvas_size: None,
                };
            }
        }
        #[cfg(target_os = "windows")]
        EngineCommand::AttachPresentDxgi {
            width,
            height,
            reply,
        } => {
            if width == 0 || height == 0 {
                let _ = reply.send(None);
                *present = None;
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if let Some(existing) = present.as_mut() {
                if existing.width == width && existing.height == height {
                    if let Some(handle) = existing.take_dxgi_handle() {
                        debug::log(
                            LogLevel::Info,
                            format_args!(
                                "AttachPresentDxgi reuse size={width}x{height} shared=0x{handle:x}"
                            ),
                        );
                        let _ = reply.send(Some(handle));
                        return EngineCommandOutcome {
                            stop: false,
                            needs_render: false,
                            new_canvas_size: None,
                        };
                    }
                }
            }

            match create_dxgi_shared_present_target(device.as_ref(), width, height) {
                Ok(mut target) => {
                    let handle = target.take_dxgi_handle();
                    *present = Some(target);
                    if handle.is_some() {
                        if let Some(shared) = handle {
                            debug::log(
                                LogLevel::Info,
                                format_args!(
                                    "AttachPresentDxgi ok size={width}x{height} shared=0x{shared:x}"
                                ),
                            );
                        }
                        // Initialize layers so the first composite is deterministic.
                        // Layer 0 is the background fill layer (default white), others start transparent.
                        layer_uniform.resize(*layer_count, None);
                        for idx in 0..*layer_count {
                            let fill = if idx == 0 { 0xFFFFFFFF } else { 0x00000000 };
                            fill_r32uint_texture(
                                queue,
                                layers.texture(),
                                canvas_width,
                                canvas_height,
                                idx as u32,
                                fill,
                            );
                            if let Some(entry) = layer_uniform.get_mut(idx) {
                                *entry = Some(fill);
                            }
                        }
                        let _ = reply.send(handle);
                        return EngineCommandOutcome {
                            stop: false,
                            needs_render: true,
                            new_canvas_size: None,
                        };
                    }

                    debug::log(
                        LogLevel::Warn,
                        format_args!("AttachPresentDxgi failed: shared handle missing"),
                    );
                }
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("AttachPresentDxgi failed: {err}"),
                    );
                }
            }

            let _ = reply.send(None);
            *present = None;
            return EngineCommandOutcome {
                stop: false,
                needs_render: false,
                new_canvas_size: None,
            };
        }
        EngineCommand::ResetCanvas {
            background_color_argb,
        } => {
            // Reset undo history so a fresh canvas doesn't "undo" back into the previous one.
            undo.reset();
            // Layer 0 is background fill; everything above starts transparent.
            layer_uniform.resize(*layer_count, None);
            for idx in 0..*layer_count {
                let fill = if idx == 0 {
                    background_color_argb
                } else {
                    0x00000000
                };
                fill_r32uint_texture(
                    queue,
                    layers.texture(),
                    canvas_width,
                    canvas_height,
                    idx as u32,
                    fill,
                );
                if let Some(entry) = layer_uniform.get_mut(idx) {
                    *entry = Some(fill);
                }
            }
            return EngineCommandOutcome {
                stop: false,
                needs_render: present.is_some(),
                new_canvas_size: None,
            };
        }
        EngineCommand::ResetCanvasWithLayers {
            layer_count: requested_count,
            background_color_argb,
        } => {
            let target_count: usize = (requested_count.max(1)) as usize;
            if target_count > *layer_count {
                let idx = target_count - 1;
                if !ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            }
            *layer_count = target_count;
            layer_opacity.resize(target_count, 1.0);
            layer_visible.resize(target_count, true);
            layer_clipping_mask.resize(target_count, false);
            layer_blend_mode.resize(target_count, 0);
            layer_uniform.resize(target_count, None);

            for idx in 0..target_count {
                let fill = if idx == 0 {
                    background_color_argb
                } else {
                    0x00000000
                };
                fill_r32uint_texture(
                    queue,
                    layers.texture(),
                    canvas_width,
                    canvas_height,
                    idx as u32,
                    fill,
                );
                if let Some(entry) = layer_uniform.get_mut(idx) {
                    *entry = Some(fill);
                }
            }

            *active_layer_index = (*active_layer_index).min(target_count.saturating_sub(1));
            *transform_layer_index = 0;
            *transform_flags = 0;
            write_present_config(
                queue,
                present_config_buffer,
                present_params_buffer,
                *layer_count,
                *present_view_flags,
                *transform_layer_index,
                *transform_flags,
                layer_opacity,
                layer_visible,
                layer_clipping_mask,
                layer_blend_mode,
            );
            undo.reset();
            return EngineCommandOutcome {
                stop: false,
                needs_render: present.is_some(),
                new_canvas_size: None,
            };
        }
        EngineCommand::ResizeCanvas {
            width,
            height,
            layer_count: requested_count,
            background_color_argb,
            reply,
        } => {
            let new_width = width.max(1);
            let new_height = height.max(1);
            let target_layer_count = (requested_count.max(1)) as usize;
            let target_capacity = layers.capacity().max(target_layer_count).max(1);
            let new_layers =
                match LayerTextures::new(device.as_ref(), new_width, new_height, target_capacity) {
                    Ok(layers) => layers,
                    Err(err) => {
                        let _ = reply.send(false);
                        debug::log(
                            LogLevel::Warn,
                            format_args!("ResizeCanvas: layer init failed: {err}"),
                        );
                        return EngineCommandOutcome {
                            stop: false,
                            needs_render: false,
                            new_canvas_size: None,
                        };
                    }
                };
            let new_params_capacity = new_layers.capacity();
            let new_params_buffer =
                match create_present_params_buffer(device.as_ref(), new_params_capacity) {
                    Ok(buffer) => buffer,
                    Err(err) => {
                        let _ = reply.send(false);
                        debug::log(
                            LogLevel::Warn,
                            format_args!("ResizeCanvas: present params buffer init failed: {err}"),
                        );
                        return EngineCommandOutcome {
                            stop: false,
                            needs_render: false,
                            new_canvas_size: None,
                        };
                    }
                };

            layer_opacity.resize(target_layer_count, 1.0);
            layer_visible.resize(target_layer_count, true);
            layer_clipping_mask.resize(target_layer_count, false);
            layer_blend_mode.resize(target_layer_count, 0);
            layer_uniform.resize(target_layer_count, None);

            for idx in 0..target_layer_count {
                let fill = if idx == 0 {
                    background_color_argb
                } else {
                    0x00000000
                };
                fill_r32uint_texture(
                    queue,
                    new_layers.texture(),
                    new_width,
                    new_height,
                    idx as u32,
                    fill,
                );
                if let Some(entry) = layer_uniform.get_mut(idx) {
                    *entry = Some(fill);
                }
            }

            *layer_count = target_layer_count;
            *present_params_capacity = new_layers.capacity();
            *present_params_buffer = new_params_buffer;
            *present_bind_group = present_renderer.create_bind_group(
                device,
                new_layers.array_view(),
                present_config_buffer,
                present_params_buffer,
                present_transform_buffer,
            );
            *layers = new_layers;
            *active_layer_index = (*active_layer_index).min(target_layer_count.saturating_sub(1));
            *transform_layer_index = 0;
            *transform_flags = 0;
            *transform_matrix = [
                1.0, 0.0, 0.0, 0.0, //
                0.0, 1.0, 0.0, 0.0, //
                0.0, 0.0, 1.0, 0.0, //
                0.0, 0.0, 0.0, 1.0, //
            ];
            write_present_transform(queue.as_ref(), present_transform_buffer, *transform_matrix);
            write_present_config(
                queue,
                present_config_buffer,
                present_params_buffer,
                *layer_count,
                *present_view_flags,
                *transform_layer_index,
                *transform_flags,
                layer_opacity,
                layer_visible,
                layer_clipping_mask,
                layer_blend_mode,
            );
            *undo = UndoManager::new(new_width, new_height);
            *present = None;
            *bucket_fill_renderer = None;
            *transform_renderer = None;

            let _ = reply.send(true);
            return EngineCommandOutcome {
                stop: false,
                needs_render: false,
                new_canvas_size: Some((new_width, new_height)),
            };
        }
        EngineCommand::FillLayer {
            layer_index,
            color_argb,
        } => {
            let idx = layer_index as usize;
            if ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                fill_r32uint_texture(
                    queue,
                    layers.texture(),
                    canvas_width,
                    canvas_height,
                    idx as u32,
                    color_argb,
                );
                if let Some(entry) = layer_uniform.get_mut(idx) {
                    *entry = Some(color_argb);
                }
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: present.is_some(),
                    new_canvas_size: None,
                };
            }
        }
        EngineCommand::ClearLayer { layer_index } => {
            let idx = layer_index as usize;
            if ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                fill_r32uint_texture(
                    queue,
                    layers.texture(),
                    canvas_width,
                    canvas_height,
                    idx as u32,
                    0x00000000,
                );
                if let Some(entry) = layer_uniform.get_mut(idx) {
                    *entry = Some(0x00000000);
                }
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: present.is_some(),
                    new_canvas_size: None,
                };
            }
        }
        EngineCommand::SetActiveLayer { layer_index } => {
            let idx = layer_index as usize;
            if ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                *active_layer_index = idx;
            }
        }
        EngineCommand::SetLayerOpacity {
            layer_index,
            opacity,
        } => {
            let idx = layer_index as usize;
            if ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                layer_opacity[idx] = if opacity.is_finite() {
                    opacity.clamp(0.0, 1.0)
                } else {
                    0.0
                };
                write_present_config(
                    queue,
                    present_config_buffer,
                    present_params_buffer,
                    *layer_count,
                    *present_view_flags,
                    *transform_layer_index,
                    *transform_flags,
                    layer_opacity,
                    layer_visible,
                    layer_clipping_mask,
                    layer_blend_mode,
                );
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: present.is_some(),
                    new_canvas_size: None,
                };
            }
        }
        EngineCommand::SetLayerVisible {
            layer_index,
            visible,
        } => {
            let idx = layer_index as usize;
            if ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                layer_visible[idx] = visible;
                write_present_config(
                    queue,
                    present_config_buffer,
                    present_params_buffer,
                    *layer_count,
                    *present_view_flags,
                    *transform_layer_index,
                    *transform_flags,
                    layer_opacity,
                    layer_visible,
                    layer_clipping_mask,
                    layer_blend_mode,
                );
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: present.is_some(),
                    new_canvas_size: None,
                };
            }
        }
        EngineCommand::SetLayerClippingMask {
            layer_index,
            clipping_mask,
        } => {
            let idx = layer_index as usize;
            if ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                layer_clipping_mask[idx] = clipping_mask;
                write_present_config(
                    queue,
                    present_config_buffer,
                    present_params_buffer,
                    *layer_count,
                    *present_view_flags,
                    *transform_layer_index,
                    *transform_flags,
                    layer_opacity,
                    layer_visible,
                    layer_clipping_mask,
                    layer_blend_mode,
                );
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: present.is_some(),
                    new_canvas_size: None,
                };
            }
        }
        EngineCommand::SetLayerBlendMode {
            layer_index,
            blend_mode_index,
        } => {
            let idx = layer_index as usize;
            if ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                layer_blend_mode[idx] = map_canvas_blend_mode_index(blend_mode_index).as_u32();
                write_present_config(
                    queue,
                    present_config_buffer,
                    present_params_buffer,
                    *layer_count,
                    *present_view_flags,
                    *transform_layer_index,
                    *transform_flags,
                    layer_opacity,
                    layer_visible,
                    layer_clipping_mask,
                    layer_blend_mode,
                );
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: present.is_some(),
                    new_canvas_size: None,
                };
            }
        }
        EngineCommand::ReorderLayer {
            from_index,
            to_index,
        } => {
            let len = *layer_count;
            if len <= 1 {
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let from = from_index as usize;
            if from >= len {
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let mut target = to_index as usize;
            if target > len {
                target = len;
            }
            if target > from {
                target = target.saturating_sub(1);
            }
            if target >= len {
                target = len.saturating_sub(1);
            }
            if target == from {
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }

            reorder_vec(layer_opacity, from, target);
            reorder_vec(layer_visible, from, target);
            reorder_vec(layer_clipping_mask, from, target);
            reorder_vec(layer_blend_mode, from, target);
            reorder_vec(layer_uniform, from, target);

            reorder_layer_textures(
                device.as_ref(),
                queue.as_ref(),
                layers.texture(),
                canvas_width,
                canvas_height,
                from,
                target,
            );

            *active_layer_index = remap_layer_index(*active_layer_index, from, target);
            if (*transform_layer_index as usize) < *layer_count {
                *transform_layer_index =
                    remap_layer_index(*transform_layer_index as usize, from, target) as u32;
            } else {
                *transform_layer_index = 0;
            }
            undo.reorder_layers(from as u32, target as u32);

            write_present_config(
                queue,
                present_config_buffer,
                present_params_buffer,
                *layer_count,
                *present_view_flags,
                *transform_layer_index,
                *transform_flags,
                layer_opacity,
                layer_visible,
                layer_clipping_mask,
                layer_blend_mode,
            );
            return EngineCommandOutcome {
                stop: false,
                needs_render: present.is_some(),
                new_canvas_size: None,
            };
        }
        EngineCommand::SetViewFlags { view_flags } => {
            let sanitized = view_flags & (VIEW_FLAG_MIRROR | VIEW_FLAG_BLACK_WHITE);
            if *present_view_flags != sanitized {
                *present_view_flags = sanitized;
                write_present_config(
                    queue,
                    present_config_buffer,
                    present_params_buffer,
                    *layer_count,
                    *present_view_flags,
                    *transform_layer_index,
                    *transform_flags,
                    layer_opacity,
                    layer_visible,
                    layer_clipping_mask,
                    layer_blend_mode,
                );
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: present.is_some(),
                    new_canvas_size: None,
                };
            }
        }
        EngineCommand::SetBrush {
            color_argb,
            base_radius,
            use_pressure,
            erase,
            antialias_level,
            brush_shape,
            random_rotation,
            smooth_rotation,
            rotation_seed,
            spacing,
            hardness,
            flow,
            scatter,
            rotation_jitter,
            snap_to_pixel,
            screentone_enabled,
            screentone_spacing,
            screentone_dot_size,
            screentone_rotation,
            screentone_softness,
            screentone_shape,
            hollow_enabled,
            hollow_ratio,
            hollow_erase_occluded,
            streamline_strength,
            smoothing_mode,
            stabilizer_strength,
        } => {
            brush_settings.color_argb = color_argb;
            brush_settings.base_radius = base_radius;
            brush_settings.use_pressure = use_pressure;
            brush_settings.erase = erase;
            brush_settings.antialias_level = antialias_level;
            brush_settings.shape = map_brush_shape(brush_shape);
            brush_settings.random_rotation = random_rotation;
            brush_settings.smooth_rotation = smooth_rotation;
            brush_settings.rotation_seed = rotation_seed;
            brush_settings.spacing = spacing;
            brush_settings.hardness = hardness;
            brush_settings.flow = flow;
            brush_settings.scatter = scatter;
            brush_settings.rotation_jitter = rotation_jitter;
            brush_settings.snap_to_pixel = snap_to_pixel;
            brush_settings.screentone_enabled = screentone_enabled;
            brush_settings.screentone_spacing = screentone_spacing;
            brush_settings.screentone_dot_size = screentone_dot_size;
            brush_settings.screentone_rotation = screentone_rotation;
            brush_settings.screentone_softness = screentone_softness;
            brush_settings.screentone_shape = map_brush_shape(screentone_shape);
            brush_settings.hollow_enabled = hollow_enabled;
            brush_settings.hollow_ratio = hollow_ratio;
            brush_settings.hollow_erase_occluded = hollow_erase_occluded;
            brush_settings.streamline_strength = streamline_strength;
            brush_settings.smoothing_mode = (smoothing_mode as u8).min(3);
            brush_settings.stabilizer_strength = stabilizer_strength;
            brush_settings.sanitize();
            if brush.is_none() {
                if let Err(err) = ensure_brush(brush, device, queue, canvas_width, canvas_height) {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("BrushRenderer prewarm failed: {err}"),
                    );
                }
            }
        }
        EngineCommand::SetBrushMask {
            width,
            height,
            mask,
        } => {
            brush_settings.custom_mask_enabled = false;
            if width == 0 || height == 0 || mask.is_empty() {
                if let Some(renderer) = brush.as_mut() {
                    renderer.clear_custom_mask();
                }
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let brush_ref = match ensure_brush(brush, device, queue, canvas_width, canvas_height) {
                Ok(brush_ref) => brush_ref,
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("BrushRenderer init failed: {err}"),
                    );
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            };
            match brush_ref.set_custom_mask(width, height, &mask) {
                Ok(()) => {
                    brush_settings.custom_mask_enabled = true;
                }
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("BrushRenderer set custom mask failed: {err}"),
                    );
                    brush_ref.clear_custom_mask();
                }
            }
            return EngineCommandOutcome {
                stop: false,
                needs_render: false,
                new_canvas_size: None,
            };
        }
        EngineCommand::ClearBrushMask => {
            brush_settings.custom_mask_enabled = false;
            if let Some(renderer) = brush.as_mut() {
                renderer.clear_custom_mask();
            }
            return EngineCommandOutcome {
                stop: false,
                needs_render: false,
                new_canvas_size: None,
            };
        }
        EngineCommand::BeginSpray => {
            let layer_idx = *active_layer_index as u32;
            *spray_active_layer = Some(layer_idx);
            undo.begin_stroke(layer_idx);
        }
        EngineCommand::DrawSpray {
            points,
            color_argb,
            brush_shape,
            erase,
            antialias_level,
            softness,
            accumulate,
        } => {
            if points.is_empty() {
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let layer_idx = match *spray_active_layer {
                Some(layer) => layer,
                None => *active_layer_index as u32,
            };
            let idx = layer_idx as usize;
            if !ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if canvas_width == 0 || canvas_height == 0 {
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }

            let brush_ref = match ensure_brush(brush, device, queue, canvas_width, canvas_height) {
                Ok(brush_ref) => brush_ref,
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("BrushRenderer init failed: {err}"),
                    );
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            };

            let dirty = compute_spray_dirty_rect(
                &points,
                canvas_width,
                canvas_height,
                softness,
                antialias_level,
            );
            if let Err(err) = brush_ref.prepare_layer_read(layers.texture(), layer_idx, dirty) {
                debug::log(
                    LogLevel::Warn,
                    format_args!("Brush layer read prep failed: {err}"),
                );
            }
            undo.begin_stroke_if_needed(layer_idx);
            undo.capture_before_for_dirty_rect(
                device.as_ref(),
                queue.as_ref(),
                layers.texture(),
                layer_idx,
                dirty,
            );

            let shape = map_brush_shape(brush_shape);
            let draw_softness = if softness.is_finite() {
                softness.clamp(0.0, 1.0)
            } else {
                0.0
            };
            let mut positions: Vec<Point2D> = Vec::with_capacity(points.len());
            let mut radii: Vec<f32> = Vec::with_capacity(points.len());
            let mut alphas: Vec<f32> = Vec::with_capacity(points.len());
            for p in &points {
                let x = if p.x.is_finite() { p.x } else { 0.0 };
                let y = if p.y.is_finite() { p.y } else { 0.0 };
                let radius = if p.radius.is_finite() {
                    p.radius.max(0.0)
                } else {
                    0.0
                };
                let alpha = if p.alpha.is_finite() {
                    p.alpha.clamp(0.0, 1.0)
                } else {
                    0.0
                };
                positions.push(Point2D { x, y });
                radii.push(radius);
                alphas.push(alpha);
            }

            let layer_view = layers
                .layer_view(idx)
                .or_else(|| layers.layer_view(0))
                .expect("layers non-empty");

            let mut any_drawn = false;
            let mut start = 0usize;
            while start < positions.len() {
                let end = (start + MAX_POINTS).min(positions.len());
                let pts = &positions[start..end];
                let rs = &radii[start..end];
                let as_ = &alphas[start..end];
                if let Err(err) = brush_ref.draw_points(
                    layer_view,
                    pts,
                    rs,
                    Some(as_),
                    None,
                    None,
                    Color { argb: color_argb },
                    shape,
                    erase,
                    antialias_level,
                    draw_softness,
                    false,
                    0.0,
                    false,
                    false,
                    accumulate,
                    0,
                    None,
                ) {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("BrushRenderer spray draw failed: {err}"),
                    );
                } else {
                    any_drawn = true;
                }
                start = end;
            }

            if any_drawn {
                if let Some(entry) = layer_uniform.get_mut(idx) {
                    *entry = None;
                }
            }
            return EngineCommandOutcome {
                stop: false,
                needs_render: any_drawn && present.is_some(),
                new_canvas_size: None,
            };
        }
        EngineCommand::EndSpray => {
            if spray_active_layer.is_some() {
                undo.end_stroke(device.as_ref(), queue.as_ref(), layers.texture());
            }
            *spray_active_layer = None;
        }
        EngineCommand::ApplyFilter {
            layer_index,
            filter_type,
            param0,
            param1,
            param2,
            param3: _,
            reply,
        } => {
            let idx = layer_index as usize;
            if !ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if canvas_width == 0 || canvas_height == 0 {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let Some(layer_view) = layers.layer_view(idx) else {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            };

            let renderer = match ensure_filter_renderer(
                filter_renderer,
                device,
                queue,
                canvas_width,
                canvas_height,
            ) {
                Ok(renderer) => renderer,
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("FilterRenderer init failed: {err}"),
                    );
                    let _ = reply.send(false);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            };

            let mut applied = false;
            let mut result: Result<(), String> = Ok(());
            match filter_type {
                FILTER_HUE_SATURATION => {
                    let params0 = [
                        param0 / 360.0,
                        param1 / 100.0,
                        param2 / 100.0,
                        0.0,
                    ];
                    undo.begin_stroke(layer_index);
                    undo.capture_before_for_dirty_rect(
                        device,
                        queue,
                        layers.texture(),
                        layer_index,
                        (0, 0, canvas_width as i32, canvas_height as i32),
                    );
                    result = renderer.apply_color_filter(
                        layers.texture(),
                        layer_view,
                        layer_index,
                        0,
                        params0,
                        [0.0; 4],
                    );
                    applied = result.is_ok();
                }
                FILTER_BRIGHTNESS_CONTRAST => {
                    let brightness = param0 / 100.0;
                    let contrast = (1.0 + param1 / 100.0).max(0.0);
                    let params0 = [brightness, contrast, 0.0, 0.0];
                    undo.begin_stroke(layer_index);
                    undo.capture_before_for_dirty_rect(
                        device,
                        queue,
                        layers.texture(),
                        layer_index,
                        (0, 0, canvas_width as i32, canvas_height as i32),
                    );
                    result = renderer.apply_color_filter(
                        layers.texture(),
                        layer_view,
                        layer_index,
                        1,
                        params0,
                        [0.0; 4],
                    );
                    applied = result.is_ok();
                }
                FILTER_BLACK_WHITE => {
                    let black = (param0 / 100.0).clamp(0.0, 1.0);
                    let white = (param1 / 100.0).clamp(0.0, 1.0);
                    let safe_white = (black + 0.01).max(white);
                    let inv_range = 1.0 / (safe_white - black).max(1.0e-4);
                    let gamma = 2.0_f32.powf(param2.clamp(-100.0, 100.0) / 100.0);
                    let params0 = [black, inv_range, gamma, 0.0];
                    undo.begin_stroke(layer_index);
                    undo.capture_before_for_dirty_rect(
                        device,
                        queue,
                        layers.texture(),
                        layer_index,
                        (0, 0, canvas_width as i32, canvas_height as i32),
                    );
                    result = renderer.apply_color_filter(
                        layers.texture(),
                        layer_view,
                        layer_index,
                        2,
                        params0,
                        [0.0; 4],
                    );
                    applied = result.is_ok();
                }
                FILTER_SCAN_PAPER_DRAWING => {
                    let black = (param0 / 100.0).clamp(0.0, 1.0);
                    let white = (param1 / 100.0).clamp(0.0, 1.0);
                    let safe_white = (black + 0.01).max(white);
                    let inv_range = 1.0 / (safe_white - black).max(1.0e-4);
                    let gamma = 2.0_f32.powf(param2.clamp(-100.0, 100.0) / 100.0);
                    let tone_enabled = if param0.abs() > 1.0e-4
                        || (param1 - 100.0).abs() > 1.0e-4
                        || param2.abs() > 1.0e-4
                    {
                        1.0
                    } else {
                        0.0
                    };
                    let params0 = [black, inv_range, gamma, tone_enabled];
                    undo.begin_stroke(layer_index);
                    undo.capture_before_for_dirty_rect(
                        device,
                        queue,
                        layers.texture(),
                        layer_index,
                        (0, 0, canvas_width as i32, canvas_height as i32),
                    );
                    result = renderer.apply_color_filter(
                        layers.texture(),
                        layer_view,
                        layer_index,
                        4,
                        params0,
                        [0.0; 4],
                    );
                    applied = result.is_ok();
                }
                FILTER_BINARIZE => {
                    let threshold = param0.clamp(0.0, 255.0) / 255.0;
                    let params0 = [threshold, 0.0, 0.0, 0.0];
                    undo.begin_stroke(layer_index);
                    undo.capture_before_for_dirty_rect(
                        device,
                        queue,
                        layers.texture(),
                        layer_index,
                        (0, 0, canvas_width as i32, canvas_height as i32),
                    );
                    result = renderer.apply_color_filter(
                        layers.texture(),
                        layer_view,
                        layer_index,
                        3,
                        params0,
                        [0.0; 4],
                    );
                    applied = result.is_ok();
                }
                FILTER_INVERT => {
                    undo.begin_stroke(layer_index);
                    undo.capture_before_for_dirty_rect(
                        device,
                        queue,
                        layers.texture(),
                        layer_index,
                        (0, 0, canvas_width as i32, canvas_height as i32),
                    );
                    result = renderer.apply_color_filter(
                        layers.texture(),
                        layer_view,
                        layer_index,
                        5,
                        [0.0; 4],
                        [0.0; 4],
                    );
                    applied = result.is_ok();
                }
                FILTER_GAUSSIAN_BLUR => {
                    let radius = param0;
                    if radius <= 0.0 {
                        let _ = reply.send(false);
                        return EngineCommandOutcome {
                            stop: false,
                            needs_render: false,
                            new_canvas_size: None,
                        };
                    }
                    undo.begin_stroke(layer_index);
                    undo.capture_before_for_dirty_rect(
                        device,
                        queue,
                        layers.texture(),
                        layer_index,
                        (0, 0, canvas_width as i32, canvas_height as i32),
                    );
                    result = renderer.apply_gaussian_blur(layer_view, radius);
                    applied = result.is_ok();
                }
                FILTER_LINE_NARROW => {
                    let steps = param0.round().clamp(0.0, 20.0) as u32;
                    if steps == 0 {
                        let _ = reply.send(false);
                        return EngineCommandOutcome {
                            stop: false,
                            needs_render: false,
                            new_canvas_size: None,
                        };
                    }
                    undo.begin_stroke(layer_index);
                    undo.capture_before_for_dirty_rect(
                        device,
                        queue,
                        layers.texture(),
                        layer_index,
                        (0, 0, canvas_width as i32, canvas_height as i32),
                    );
                    result = renderer.apply_morphology(
                        layers.texture(),
                        layer_view,
                        layer_index,
                        steps,
                        false,
                    );
                    applied = result.is_ok();
                }
                FILTER_FILL_EXPAND => {
                    let steps = param0.round().clamp(0.0, 20.0) as u32;
                    if steps == 0 {
                        let _ = reply.send(false);
                        return EngineCommandOutcome {
                            stop: false,
                            needs_render: false,
                            new_canvas_size: None,
                        };
                    }
                    undo.begin_stroke(layer_index);
                    undo.capture_before_for_dirty_rect(
                        device,
                        queue,
                        layers.texture(),
                        layer_index,
                        (0, 0, canvas_width as i32, canvas_height as i32),
                    );
                    result = renderer.apply_morphology(
                        layers.texture(),
                        layer_view,
                        layer_index,
                        steps,
                        true,
                    );
                    applied = result.is_ok();
                }
                FILTER_LEAK_REMOVAL => {
                    let steps = param0.round().clamp(0.0, 20.0) as u32;
                    if steps == 0 {
                        let _ = reply.send(false);
                        return EngineCommandOutcome {
                            stop: false,
                            needs_render: false,
                            new_canvas_size: None,
                        };
                    }
                    undo.begin_stroke(layer_index);
                    undo.capture_before_for_dirty_rect(
                        device,
                        queue,
                        layers.texture(),
                        layer_index,
                        (0, 0, canvas_width as i32, canvas_height as i32),
                    );
                    result = renderer.apply_morphology(
                        layers.texture(),
                        layer_view,
                        layer_index,
                        steps,
                        true,
                    );
                    if result.is_ok() {
                        result = renderer.apply_morphology(
                            layers.texture(),
                            layer_view,
                            layer_index,
                            steps,
                            false,
                        );
                    }
                    applied = result.is_ok();
                }
                _ => {}
            }

            if applied {
                undo.end_stroke(device, queue, layers.texture());
                if let Some(entry) = layer_uniform.get_mut(idx) {
                    *entry = None;
                }
                let _ = reply.send(true);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: present.is_some(),
                    new_canvas_size: None,
                };
            }

            undo.cancel_stroke();
            if let Err(err) = result {
                debug::log(LogLevel::Warn, format_args!("Filter apply failed: {err}"));
            }
            let _ = reply.send(false);
            return EngineCommandOutcome {
                stop: false,
                needs_render: false,
                new_canvas_size: None,
            };
        }
        EngineCommand::ApplyAntialias {
            layer_index,
            level,
            reply,
        } => {
            let idx = layer_index as usize;
            if !ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if canvas_width == 0 || canvas_height == 0 {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let Some(layer_view) = layers.layer_view(idx) else {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            };

            let renderer = match ensure_filter_renderer(
                filter_renderer,
                device,
                queue,
                canvas_width,
                canvas_height,
            ) {
                Ok(renderer) => renderer,
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("FilterRenderer init failed: {err}"),
                    );
                    let _ = reply.send(false);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            };

            undo.begin_stroke(layer_index);
            undo.capture_before_for_dirty_rect(
                device,
                queue,
                layers.texture(),
                layer_index,
                (0, 0, canvas_width as i32, canvas_height as i32),
            );
            let result = renderer.apply_antialias(layer_view, level);
            if result.is_ok() {
                undo.end_stroke(device, queue, layers.texture());
                if let Some(entry) = layer_uniform.get_mut(idx) {
                    *entry = None;
                }
                let _ = reply.send(true);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: present.is_some(),
                    new_canvas_size: None,
                };
            }

            undo.cancel_stroke();
            if let Err(err) = result {
                debug::log(LogLevel::Warn, format_args!("Antialias apply failed: {err}"));
            }
            let _ = reply.send(false);
            return EngineCommandOutcome {
                stop: false,
                needs_render: false,
                new_canvas_size: None,
            };
        }
        EngineCommand::BucketFill {
            layer_index,
            start_x,
            start_y,
            color_argb,
            contiguous,
            sample_all_layers,
            tolerance,
            fill_gap,
            antialias_level,
            swallow_colors,
            selection_mask,
            reply,
        } => {
            let idx = layer_index as usize;
            if !ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if canvas_width == 0 || canvas_height == 0 {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if start_x < 0
                || start_y < 0
                || (start_x as u32) >= canvas_width
                || (start_y as u32) >= canvas_height
            {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }

            // Fast path: uniform layer with no selection mask can be filled directly.
            if !sample_all_layers && selection_mask.is_none() {
                if let Some(base_color) = layer_uniform.get(idx).copied().flatten() {
                    if base_color == color_argb {
                        let _ = reply.send(false);
                        return EngineCommandOutcome {
                            stop: false,
                            needs_render: false,
                            new_canvas_size: None,
                        };
                    }
                    undo.begin_stroke(layer_index);
                    undo.capture_before_for_dirty_rect(
                        device,
                        queue,
                        layers.texture(),
                        layer_index,
                        (0, 0, canvas_width as i32, canvas_height as i32),
                    );
                    fill_r32uint_texture(
                        queue,
                        layers.texture(),
                        canvas_width,
                        canvas_height,
                        layer_index,
                        color_argb,
                    );
                    undo.end_stroke(device, queue, layers.texture());
                    if let Some(entry) = layer_uniform.get_mut(idx) {
                        *entry = Some(color_argb);
                    }
                    let _ = reply.send(true);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: present.is_some(),
                        new_canvas_size: None,
                    };
                }
            }

            if bucket_fill_renderer.is_none() {
                match BucketFillRenderer::new(device.clone(), queue.clone()) {
                    Ok(renderer) => *bucket_fill_renderer = Some(renderer),
                    Err(err) => {
                        debug::log(
                            LogLevel::Warn,
                            format_args!("BucketFillRenderer init failed: {err}"),
                        );
                    }
                }
            }

            if let Some(renderer) = bucket_fill_renderer.as_mut() {
                let Some(layer_view) = layers.layer_view(idx) else {
                    let _ = reply.send(false);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                };

                undo.begin_stroke(layer_index);
                undo.capture_before_for_dirty_rect(
                    device,
                    queue,
                    layers.texture(),
                    layer_index,
                    (0, 0, canvas_width as i32, canvas_height as i32),
                );

                let applied = match renderer.bucket_fill(
                    layer_view,
                    layers.array_view(),
                    layer_index,
                    *layer_count,
                    layer_opacity,
                    layer_visible,
                    layer_clipping_mask,
                    canvas_width,
                    canvas_height,
                    start_x,
                    start_y,
                    color_argb,
                    contiguous,
                    sample_all_layers,
                    tolerance,
                    fill_gap,
                    antialias_level,
                    &swallow_colors,
                    selection_mask.as_deref(),
                ) {
                    Ok(changed) => changed,
                    Err(err) => {
                        debug::log(
                            LogLevel::Warn,
                            format_args!("bucket fill GPU failed: {err}"),
                        );
                        false
                    }
                };

                if applied {
                    undo.end_stroke(device, queue, layers.texture());
                    if let Some(entry) = layer_uniform.get_mut(idx) {
                        *entry = None;
                    }
                } else {
                    undo.cancel_stroke();
                }

                let _ = reply.send(applied);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: present.is_some(),
                    new_canvas_size: None,
                };
            }

            let (active_pixels, sample_pixels) = if sample_all_layers {
                let mut layers_pixels: Vec<Vec<u32>> = Vec::with_capacity(*layer_count);
                for layer_idx in 0..*layer_count {
                    match read_r32uint_layer(
                        device,
                        queue,
                        layers.texture(),
                        canvas_width,
                        canvas_height,
                        layer_idx as u32,
                    ) {
                        Ok(pixels) => layers_pixels.push(pixels),
                        Err(err) => {
                            debug::log(
                                LogLevel::Warn,
                                format_args!("bucket fill readback failed: {err}"),
                            );
                            let _ = reply.send(false);
                            return EngineCommandOutcome {
                                stop: false,
                                needs_render: false,
                                new_canvas_size: None,
                            };
                        }
                    }
                }
                let sample = composite_layers_for_bucket_fill(
                    canvas_width as usize,
                    canvas_height as usize,
                    &layers_pixels,
                    layer_opacity,
                    layer_visible,
                    layer_clipping_mask,
                );
                let active = std::mem::take(&mut layers_pixels[idx]);
                (active, Some(sample))
            } else {
                match read_r32uint_layer(
                    device,
                    queue,
                    layers.texture(),
                    canvas_width,
                    canvas_height,
                    idx as u32,
                ) {
                    Ok(pixels) => (pixels, None),
                    Err(err) => {
                        debug::log(
                            LogLevel::Warn,
                            format_args!("bucket fill readback failed: {err}"),
                        );
                        let _ = reply.send(false);
                        return EngineCommandOutcome {
                            stop: false,
                            needs_render: false,
                            new_canvas_size: None,
                        };
                    }
                }
            };

            let patch = bucket_fill::flood_fill_patch(
                canvas_width as i32,
                canvas_height as i32,
                active_pixels,
                sample_pixels,
                start_x,
                start_y,
                color_argb,
                None,
                contiguous,
                tolerance as i32,
                fill_gap as i32,
                selection_mask,
                if swallow_colors.is_empty() {
                    None
                } else {
                    Some(swallow_colors)
                },
                antialias_level as i32,
            );

            if patch.width <= 0 || patch.height <= 0 {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }

            let left = patch.left.max(0) as u32;
            let top = patch.top.max(0) as u32;
            let width = patch.width.max(0) as u32;
            let height = patch.height.max(0) as u32;
            if width == 0 || height == 0 {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }

            let bytes_per_row_unpadded = match width.checked_mul(4) {
                Some(v) => v,
                None => {
                    let _ = reply.send(false);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            };
            let bytes_per_row_padded = align_up_u32(bytes_per_row_unpadded, 256);
            if bytes_per_row_padded == 0 {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let packed = match pack_u32_rows_with_padding(
                &patch.pixels,
                width,
                height,
                bytes_per_row_padded,
            ) {
                Ok(data) => data,
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("bucket fill pack failed: {err}"),
                    );
                    let _ = reply.send(false);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            };

            undo.begin_stroke(layer_index);
            undo.capture_before_for_dirty_rect(
                device,
                queue,
                layers.texture(),
                layer_index,
                (patch.left, patch.top, patch.width, patch.height),
            );

            write_r32uint_region(
                queue,
                layers.texture(),
                left,
                top,
                width,
                height,
                layer_index,
                bytes_per_row_padded,
                &packed,
            );
            undo.end_stroke(device, queue, layers.texture());
            if let Some(entry) = layer_uniform.get_mut(idx) {
                *entry = None;
            }

            let _ = reply.send(true);
            return EngineCommandOutcome {
                stop: false,
                needs_render: present.is_some(),
                new_canvas_size: None,
            };
        }
        EngineCommand::MagicWandMask {
            layer_index,
            start_x,
            start_y,
            sample_all_layers,
            tolerance,
            selection_mask,
            reply,
        } => {
            let idx = layer_index as usize;
            if !ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                let _ = reply.send(None);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if canvas_width == 0 || canvas_height == 0 {
                let _ = reply.send(None);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if start_x < 0
                || start_y < 0
                || (start_x as u32) >= canvas_width
                || (start_y as u32) >= canvas_height
            {
                let _ = reply.send(None);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }

            let pixels = if sample_all_layers {
                let mut layers_pixels: Vec<Vec<u32>> = Vec::with_capacity(*layer_count);
                for layer_idx in 0..*layer_count {
                    match read_r32uint_layer(
                        device,
                        queue,
                        layers.texture(),
                        canvas_width,
                        canvas_height,
                        layer_idx as u32,
                    ) {
                        Ok(pixels) => layers_pixels.push(pixels),
                        Err(err) => {
                            debug::log(
                                LogLevel::Warn,
                                format_args!("magic wand readback failed: {err}"),
                            );
                            let _ = reply.send(None);
                            return EngineCommandOutcome {
                                stop: false,
                                needs_render: false,
                                new_canvas_size: None,
                            };
                        }
                    }
                }
                composite_layers_for_bucket_fill(
                    canvas_width as usize,
                    canvas_height as usize,
                    &layers_pixels,
                    layer_opacity,
                    layer_visible,
                    layer_clipping_mask,
                )
            } else {
                match read_r32uint_layer(
                    device,
                    queue,
                    layers.texture(),
                    canvas_width,
                    canvas_height,
                    idx as u32,
                ) {
                    Ok(pixels) => pixels,
                    Err(err) => {
                        debug::log(
                            LogLevel::Warn,
                            format_args!("magic wand readback failed: {err}"),
                        );
                        let _ = reply.send(None);
                        return EngineCommandOutcome {
                            stop: false,
                            needs_render: false,
                            new_canvas_size: None,
                        };
                    }
                }
            };

            let mask = bucket_fill::magic_wand_mask(
                canvas_width as i32,
                canvas_height as i32,
                pixels,
                start_x,
                start_y,
                tolerance as i32,
                selection_mask,
            );
            let _ = reply.send(mask);
            return EngineCommandOutcome {
                stop: false,
                needs_render: false,
                new_canvas_size: None,
            };
        }
        EngineCommand::ReadLayer { layer_index, reply } => {
            let idx = layer_index as usize;
            if idx >= *layer_count {
                let _ = reply.send(None);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if canvas_width == 0 || canvas_height == 0 {
                let _ = reply.send(None);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            match read_r32uint_layer(
                device,
                queue,
                layers.texture(),
                canvas_width,
                canvas_height,
                layer_index,
            ) {
                Ok(pixels) => {
                    let _ = reply.send(Some(pixels));
                }
                Err(err) => {
                    debug::log(LogLevel::Warn, format_args!("layer readback failed: {err}"));
                    let _ = reply.send(None);
                }
            }
            return EngineCommandOutcome {
                stop: false,
                needs_render: false,
                new_canvas_size: None,
            };
        }
        EngineCommand::ReadLayerPreview {
            layer_index,
            width,
            height,
            reply,
        } => {
            let idx = layer_index as usize;
            if idx >= *layer_count || width == 0 || height == 0 {
                let _ = reply.send(None);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if canvas_width == 0 || canvas_height == 0 {
                let _ = reply.send(None);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }

            let preview_texture = device.create_texture(&wgpu::TextureDescriptor {
                label: Some("misa-rin layer preview target"),
                size: wgpu::Extent3d {
                    width,
                    height,
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::Bgra8Unorm,
                usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
                view_formats: &[],
            });
            let preview_view = preview_texture.create_view(&wgpu::TextureViewDescriptor::default());

            let layer_view = layers.texture().create_view(&wgpu::TextureViewDescriptor {
                label: Some("misa-rin layer preview array view"),
                dimension: Some(wgpu::TextureViewDimension::D2Array),
                base_array_layer: layer_index,
                array_layer_count: Some(1),
                ..Default::default()
            });

            let scale_x = canvas_width as f32 / width as f32;
            let scale_y = canvas_height as f32 / height as f32;
            let preview_matrix = [
                scale_x, 0.0, 0.0, 0.0, 0.0, scale_y, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0,
                0.0, 1.0,
            ];
            let preview_layer_opacity = [1.0f32];
            let preview_layer_visible = [true];
            let preview_layer_clipping = [false];
            let preview_layer_blend_mode = [0u32];
            let preview_transform_layer = 0u32;
            let preview_transform_flags = 1u32;

            write_present_transform(queue, present_transform_buffer, preview_matrix);
            write_present_config(
                queue,
                present_config_buffer,
                present_params_buffer,
                1,
                0,
                preview_transform_layer,
                preview_transform_flags,
                &preview_layer_opacity,
                &preview_layer_visible,
                &preview_layer_clipping,
                &preview_layer_blend_mode,
            );

            let preview_bind_group = present_renderer.create_bind_group(
                device,
                &layer_view,
                present_config_buffer,
                present_params_buffer,
                present_transform_buffer,
            );
            present_renderer.render_base(device, queue, &preview_bind_group, &preview_view);

            let preview_bytes = match read_bgra_texture(device, queue, &preview_texture, width, height)
            {
                Ok(bytes) => Some(bgra_to_rgba(bytes)),
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("layer preview readback failed: {err}"),
                    );
                    None
                }
            };

            write_present_transform(queue, present_transform_buffer, *transform_matrix);
            write_present_config(
                queue,
                present_config_buffer,
                present_params_buffer,
                *layer_count,
                *present_view_flags,
                *transform_layer_index,
                *transform_flags,
                layer_opacity,
                layer_visible,
                layer_clipping_mask,
                layer_blend_mode,
            );

            let _ = reply.send(preview_bytes);
            return EngineCommandOutcome {
                stop: false,
                needs_render: false,
                new_canvas_size: None,
            };
        }
        EngineCommand::ReadPresent { reply } => {
            let Some(target) = &present else {
                let _ = reply.send(None);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            };
            if target.width == 0 || target.height == 0 {
                let _ = reply.send(None);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            match read_bgra_texture(
                device,
                queue,
                target.texture(),
                target.width,
                target.height,
            ) {
                Ok(bytes) => {
                    let _ = reply.send(Some(bytes));
                }
                Err(err) => {
                    debug::log(LogLevel::Warn, format_args!("present readback failed: {err}"));
                    let _ = reply.send(None);
                }
            }
            return EngineCommandOutcome {
                stop: false,
                needs_render: false,
                new_canvas_size: None,
            };
        }
        EngineCommand::WriteLayer {
            layer_index,
            pixels,
            record_undo,
            reply,
        } => {
            let idx = layer_index as usize;
            if !ensure_layer_index(layer_count, idx, *transform_layer_index, *transform_flags) {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let expected_len = (canvas_width as usize).saturating_mul(canvas_height as usize);
            if expected_len == 0 || pixels.len() != expected_len {
                if expected_len > 0 {
                    debug::log(
                        LogLevel::Warn,
                        format_args!(
                            "layer write size mismatch: got {}, expected {}",
                            pixels.len(),
                            expected_len
                        ),
                    );
                }
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let bytes_per_row_unpadded = match canvas_width.checked_mul(4) {
                Some(v) => v,
                None => {
                    let _ = reply.send(false);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            };
            let bytes_per_row_padded = align_up_u32(bytes_per_row_unpadded, 256);
            if bytes_per_row_padded == 0 {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let packed = match pack_u32_rows_with_padding(
                &pixels,
                canvas_width,
                canvas_height,
                bytes_per_row_padded,
            ) {
                Ok(data) => data,
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("layer write pack failed: {err}"),
                    );
                    let _ = reply.send(false);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            };
            if record_undo {
                undo.begin_stroke(layer_index);
                undo.capture_before_for_dirty_rect(
                    device,
                    queue,
                    layers.texture(),
                    layer_index,
                    (0, 0, canvas_width as i32, canvas_height as i32),
                );
            }
            write_r32uint_region(
                queue,
                layers.texture(),
                0,
                0,
                canvas_width,
                canvas_height,
                layer_index,
                bytes_per_row_padded,
                &packed,
            );
            if record_undo {
                undo.end_stroke(device, queue, layers.texture());
            }
            if let Some(entry) = layer_uniform.get_mut(idx) {
                *entry = None;
            }
            let _ = reply.send(true);
            return EngineCommandOutcome {
                stop: false,
                needs_render: present.is_some(),
                new_canvas_size: None,
            };
        }
        EngineCommand::TranslateLayer {
            layer_index,
            delta_x,
            delta_y,
            reply,
        } => {
            let idx = layer_index as usize;
            if idx >= *layer_count {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if canvas_width == 0 || canvas_height == 0 {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if delta_x == 0 && delta_y == 0 {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if transform_renderer.is_none() {
                if let Err(err) = ensure_transform_renderer(transform_renderer, device, queue) {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("LayerTransformRenderer init failed: {err}"),
                    );
                }
            }
            if let Some(renderer) = transform_renderer.as_mut() {
                let matrix = translation_matrix(delta_x, delta_y);
                undo.begin_stroke(layer_index);
                undo.capture_before_for_dirty_rect(
                    device,
                    queue,
                    layers.texture(),
                    layer_index,
                    (0, 0, canvas_width as i32, canvas_height as i32),
                );
                if let Err(err) = renderer.apply_transform(
                    layers.array_view(),
                    layers.texture(),
                    canvas_width,
                    canvas_height,
                    layer_index,
                    matrix,
                    false,
                ) {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("layer translate GPU failed: {err}"),
                    );
                    undo.cancel_stroke();
                    let _ = reply.send(false);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
                undo.end_stroke(device, queue, layers.texture());
                if let Some(entry) = layer_uniform.get_mut(idx) {
                    *entry = None;
                }
                let _ = reply.send(true);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: present.is_some(),
                    new_canvas_size: None,
                };
            }
            let pixels = match read_r32uint_layer(
                device,
                queue,
                layers.texture(),
                canvas_width,
                canvas_height,
                layer_index,
            ) {
                Ok(pixels) => pixels,
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("layer translate readback failed: {err}"),
                    );
                    let _ = reply.send(false);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            };
            let width = canvas_width as i64;
            let height = canvas_height as i64;
            let dx = delta_x as i64;
            let dy = delta_y as i64;
            let mut shifted = vec![0u32; pixels.len()];
            let src_x_start = if dx >= 0 { 0 } else { (-dx).min(width) };
            let src_x_end = if dx >= 0 { (width - dx).max(0) } else { width };
            let src_y_start = if dy >= 0 { 0 } else { (-dy).min(height) };
            let src_y_end = if dy >= 0 {
                (height - dy).max(0)
            } else {
                height
            };
            if src_x_start < src_x_end && src_y_start < src_y_end {
                let src_width = width as usize;
                let dst_width = width as usize;
                for y in src_y_start..src_y_end {
                    let dst_y = y + dy;
                    if dst_y < 0 || dst_y >= height {
                        continue;
                    }
                    let src_row = (y as usize) * src_width;
                    let dst_row = (dst_y as usize) * dst_width;
                    let src_start = src_row + src_x_start as usize;
                    let src_end = src_row + src_x_end as usize;
                    let dst_start = dst_row + (src_x_start + dx) as usize;
                    let dst_end = dst_start + (src_end - src_start);
                    shifted[dst_start..dst_end].copy_from_slice(&pixels[src_start..src_end]);
                }
            }
            let bytes_per_row_unpadded = match canvas_width.checked_mul(4) {
                Some(v) => v,
                None => {
                    let _ = reply.send(false);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            };
            let bytes_per_row_padded = align_up_u32(bytes_per_row_unpadded, 256);
            if bytes_per_row_padded == 0 {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let packed = match pack_u32_rows_with_padding(
                &shifted,
                canvas_width,
                canvas_height,
                bytes_per_row_padded,
            ) {
                Ok(data) => data,
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("layer translate pack failed: {err}"),
                    );
                    let _ = reply.send(false);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            };
            undo.begin_stroke(layer_index);
            undo.capture_before_for_dirty_rect(
                device,
                queue,
                layers.texture(),
                layer_index,
                (0, 0, canvas_width as i32, canvas_height as i32),
            );
            write_r32uint_region(
                queue,
                layers.texture(),
                0,
                0,
                canvas_width,
                canvas_height,
                layer_index,
                bytes_per_row_padded,
                &packed,
            );
            undo.end_stroke(device, queue, layers.texture());
            if let Some(entry) = layer_uniform.get_mut(idx) {
                *entry = None;
            }
            let _ = reply.send(true);
            return EngineCommandOutcome {
                stop: false,
                needs_render: present.is_some(),
                new_canvas_size: None,
            };
        }
        EngineCommand::SetLayerTransformPreview {
            layer_index,
            matrix,
            enabled,
            bilinear,
        } => {
            if enabled && (layer_index as usize) < *layer_count {
                *transform_layer_index = layer_index;
                *transform_flags = 1 | if bilinear { 2 } else { 0 };
                *transform_matrix = matrix;
                write_present_transform(queue, present_transform_buffer, *transform_matrix);
            } else {
                *transform_flags = 0;
            }
            write_present_config(
                queue,
                present_config_buffer,
                present_params_buffer,
                *layer_count,
                *present_view_flags,
                *transform_layer_index,
                *transform_flags,
                layer_opacity,
                layer_visible,
                layer_clipping_mask,
                layer_blend_mode,
            );
            return EngineCommandOutcome {
                stop: false,
                needs_render: present.is_some(),
                new_canvas_size: None,
            };
        }
        EngineCommand::ApplyLayerTransform {
            layer_index,
            matrix,
            bilinear,
            reply,
        } => {
            let idx = layer_index as usize;
            if idx >= *layer_count {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if canvas_width == 0 || canvas_height == 0 {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            if transform_renderer.is_none() {
                if let Err(err) = ensure_transform_renderer(transform_renderer, device, queue) {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("LayerTransformRenderer init failed: {err}"),
                    );
                }
            }
            let Some(renderer) = transform_renderer.as_mut() else {
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            };
            undo.begin_stroke(layer_index);
            undo.capture_before_for_dirty_rect(
                device,
                queue,
                layers.texture(),
                layer_index,
                (0, 0, canvas_width as i32, canvas_height as i32),
            );
            let result = renderer.apply_transform(
                layers.array_view(),
                layers.texture(),
                canvas_width,
                canvas_height,
                layer_index,
                matrix,
                bilinear,
            );
            if let Err(err) = result {
                debug::log(
                    LogLevel::Warn,
                    format_args!("layer transform apply failed: {err}"),
                );
                undo.cancel_stroke();
                let _ = reply.send(false);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            undo.end_stroke(device, queue, layers.texture());
            if let Some(entry) = layer_uniform.get_mut(idx) {
                *entry = None;
            }
            let _ = reply.send(true);
            return EngineCommandOutcome {
                stop: false,
                needs_render: present.is_some(),
                new_canvas_size: None,
            };
        }
        EngineCommand::GetLayerBounds { layer_index, reply } => {
            let idx = layer_index as usize;
            if idx >= *layer_count || canvas_width == 0 || canvas_height == 0 {
                let _ = reply.send(None);
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let pixels = match read_r32uint_layer(
                device,
                queue,
                layers.texture(),
                canvas_width,
                canvas_height,
                layer_index,
            ) {
                Ok(pixels) => pixels,
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("layer bounds readback failed: {err}"),
                    );
                    let _ = reply.send(None);
                    return EngineCommandOutcome {
                        stop: false,
                        needs_render: false,
                        new_canvas_size: None,
                    };
                }
            };
            if pixels.is_empty() {
                let _ = reply.send(Some((0, 0, canvas_width as i32, canvas_height as i32)));
                return EngineCommandOutcome {
                    stop: false,
                    needs_render: false,
                    new_canvas_size: None,
                };
            }
            let width = canvas_width as i32;
            let height = canvas_height as i32;
            let mut min_x = width;
            let mut min_y = height;
            let mut max_x = -1;
            let mut max_y = -1;
            for y in 0..height {
                let row_offset = (y as usize) * (width as usize);
                for x in 0..width {
                    let argb = pixels[row_offset + (x as usize)];
                    if (argb >> 24) == 0 {
                        continue;
                    }
                    if x < min_x {
                        min_x = x;
                    }
                    if x > max_x {
                        max_x = x;
                    }
                    if y < min_y {
                        min_y = y;
                    }
                    if y > max_y {
                        max_y = y;
                    }
                }
            }
            if max_x < min_x || max_y < min_y {
                let _ = reply.send(Some((0, 0, width, height)));
            } else {
                let _ = reply.send(Some((min_x, min_y, max_x + 1, max_y + 1)));
            }
            return EngineCommandOutcome {
                stop: false,
                needs_render: false,
                new_canvas_size: None,
            };
        }
        EngineCommand::SetSelectionMask { selection_mask } => {
            let expected_len = (canvas_width as usize).saturating_mul(canvas_height as usize);
            let valid_mask = match selection_mask {
                Some(mask) => {
                    if mask.len() == expected_len {
                        Some(mask)
                    } else {
                        if expected_len > 0 {
                            debug::log(
                                LogLevel::Warn,
                                format_args!(
                                    "selection mask size mismatch: got {}, expected {}",
                                    mask.len(),
                                    expected_len
                                ),
                            );
                        }
                        None
                    }
                }
                None => None,
            };
            *selection_mask_active = valid_mask.is_some();
            match ensure_brush(brush, device, queue, canvas_width, canvas_height) {
                Ok(brush_ref) => {
                    if let Err(err) = brush_ref.set_selection_mask(valid_mask.as_deref()) {
                        debug::log(
                            LogLevel::Warn,
                            format_args!("selection mask update failed: {err}"),
                        );
                    }
                }
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("selection mask skipped: {err}"),
                    );
                }
            }
        }
        EngineCommand::Undo => {
            let applied = undo.undo(device, queue, layers.texture(), *layer_count);
            if applied {
                for entry in layer_uniform.iter_mut() {
                    *entry = None;
                }
            }
            return EngineCommandOutcome {
                stop: false,
                needs_render: applied && present.is_some(),
                new_canvas_size: None,
            };
        }
        EngineCommand::Redo => {
            let applied = undo.redo(device, queue, layers.texture(), *layer_count);
            if applied {
                for entry in layer_uniform.iter_mut() {
                    *entry = None;
                }
            }
            return EngineCommandOutcome {
                stop: false,
                needs_render: applied && present.is_some(),
                new_canvas_size: None,
            };
        }
    }
    EngineCommandOutcome {
        stop: false,
        needs_render: false,
        new_canvas_size: None,
    }
}

#[derive(Clone, Copy, Debug)]
struct EngineCommandOutcome {
    stop: bool,
    needs_render: bool,
    new_canvas_size: Option<(u32, u32)>,
}

fn remap_layer_index(index: usize, from: usize, to: usize) -> usize {
    if from == to {
        return index;
    }
    if index == from {
        return to;
    }
    if from < to {
        if index > from && index <= to {
            return index - 1;
        }
    } else if from > to {
        if index >= to && index < from {
            return index + 1;
        }
    }
    index
}

fn reorder_vec<T>(vec: &mut Vec<T>, from: usize, to: usize) {
    if from == to || from >= vec.len() {
        return;
    }
    let item = vec.remove(from);
    let insert_at = to.min(vec.len());
    vec.insert(insert_at, item);
}

fn reorder_layer_textures(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    texture: &wgpu::Texture,
    width: u32,
    height: u32,
    from: usize,
    to: usize,
) {
    if from == to || width == 0 || height == 0 {
        return;
    }

    let scratch = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("misa-rin layer reorder scratch"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: LAYER_TEXTURE_FORMAT,
        usage: wgpu::TextureUsages::COPY_SRC | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("misa-rin layer reorder encoder"),
    });
    let extent = wgpu::Extent3d {
        width,
        height,
        depth_or_array_layers: 1,
    };
    let copy_layer = |encoder: &mut wgpu::CommandEncoder,
                      src_texture: &wgpu::Texture,
                      src_layer: u32,
                      dst_texture: &wgpu::Texture,
                      dst_layer: u32| {
        encoder.copy_texture_to_texture(
            wgpu::ImageCopyTexture {
                texture: src_texture,
                mip_level: 0,
                origin: wgpu::Origin3d {
                    x: 0,
                    y: 0,
                    z: src_layer,
                },
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::ImageCopyTexture {
                texture: dst_texture,
                mip_level: 0,
                origin: wgpu::Origin3d {
                    x: 0,
                    y: 0,
                    z: dst_layer,
                },
                aspect: wgpu::TextureAspect::All,
            },
            extent,
        );
    };

    copy_layer(&mut encoder, texture, from as u32, &scratch, 0);
    if from < to {
        for idx in from..to {
            copy_layer(
                &mut encoder,
                texture,
                (idx + 1) as u32,
                texture,
                idx as u32,
            );
        }
    } else {
        for idx in (to..from).rev() {
            copy_layer(
                &mut encoder,
                texture,
                idx as u32,
                texture,
                (idx + 1) as u32,
            );
        }
    }
    copy_layer(&mut encoder, &scratch, 0, texture, to as u32);
    queue.submit(Some(encoder.finish()));
}

fn ensure_brush<'a>(
    brush: &'a mut Option<BrushRenderer>,
    device: &Arc<wgpu::Device>,
    queue: &Arc<wgpu::Queue>,
    canvas_width: u32,
    canvas_height: u32,
) -> Result<&'a mut BrushRenderer, String> {
    if brush.is_none() {
        let mut renderer =
            BrushRenderer::new(device.clone(), queue.clone()).map_err(|err| err.to_string())?;
        renderer.set_canvas_size(canvas_width, canvas_height);
        renderer.set_softness(0.0);
        *brush = Some(renderer);
    }
    let brush_ref = brush.as_mut().expect("brush present after init");
    brush_ref.set_canvas_size(canvas_width, canvas_height);
    Ok(brush_ref)
}

fn ensure_filter_renderer<'a>(
    filter_renderer: &'a mut Option<FilterRenderer>,
    device: &Arc<wgpu::Device>,
    queue: &Arc<wgpu::Queue>,
    canvas_width: u32,
    canvas_height: u32,
) -> Result<&'a mut FilterRenderer, String> {
    if filter_renderer.is_none() {
        let mut renderer =
            FilterRenderer::new(device.clone(), queue.clone()).map_err(|err| err.to_string())?;
        renderer.set_canvas_size(canvas_width, canvas_height);
        *filter_renderer = Some(renderer);
    }
    let renderer_ref = filter_renderer
        .as_mut()
        .ok_or_else(|| "filter renderer missing after init".to_string())?;
    renderer_ref.set_canvas_size(canvas_width, canvas_height);
    Ok(renderer_ref)
}

fn ensure_transform_renderer<'a>(
    transform_renderer: &'a mut Option<LayerTransformRenderer>,
    device: &Arc<wgpu::Device>,
    queue: &Arc<wgpu::Queue>,
) -> Result<&'a mut LayerTransformRenderer, String> {
    if transform_renderer.is_none() {
        let renderer = LayerTransformRenderer::new(device.clone(), queue.clone())?;
        *transform_renderer = Some(renderer);
    }
    transform_renderer
        .as_mut()
        .ok_or_else(|| "transform renderer missing after init".to_string())
}

fn translation_matrix(delta_x: i32, delta_y: i32) -> [f32; 16] {
    let tx = -(delta_x as f32);
    let ty = -(delta_y as f32);
    [
        1.0, 0.0, 0.0, 0.0, //
        0.0, 1.0, 0.0, 0.0, //
        0.0, 0.0, 1.0, 0.0, //
        tx, ty, 0.0, 1.0, //
    ]
}

fn fill_r32uint_texture(
    queue: &wgpu::Queue,
    texture: &wgpu::Texture,
    width: u32,
    height: u32,
    layer_index: u32,
    value: u32,
) {
    if width == 0 || height == 0 {
        return;
    }

    const BYTES_PER_PIXEL: u32 = 4;
    const COPY_BYTES_PER_ROW_ALIGNMENT: u32 = 256;
    // Keep temporary allocations bounded even for very large canvases.
    const MAX_CHUNK_BYTES: usize = 4 * 1024 * 1024;

    let bytes_per_row_unpadded = width.saturating_mul(BYTES_PER_PIXEL);
    let bytes_per_row_padded = align_up_u32(bytes_per_row_unpadded, COPY_BYTES_PER_ROW_ALIGNMENT);
    if bytes_per_row_padded == 0 {
        return;
    }

    let row_bytes = bytes_per_row_padded as usize;
    let rows_per_chunk = (MAX_CHUNK_BYTES / row_bytes).max(1) as u32;
    let texels_per_row = (bytes_per_row_padded / BYTES_PER_PIXEL) as usize;

    let mut y: u32 = 0;
    while y < height {
        let chunk_h = (height - y).min(rows_per_chunk);
        let texel_count = texels_per_row.saturating_mul(chunk_h as usize);
        let data: Vec<u32> = vec![value; texel_count];

        queue.write_texture(
            wgpu::ImageCopyTexture {
                texture,
                mip_level: 0,
                origin: wgpu::Origin3d {
                    x: 0,
                    y,
                    z: layer_index,
                },
                aspect: wgpu::TextureAspect::All,
            },
            bytemuck::cast_slice(&data),
            wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(bytes_per_row_padded),
                rows_per_image: Some(chunk_h),
            },
            wgpu::Extent3d {
                width,
                height: chunk_h,
                depth_or_array_layers: 1,
            },
        );

        y = y.saturating_add(chunk_h);
    }
}

fn align_up_u32(value: u32, alignment: u32) -> u32 {
    if alignment == 0 {
        return value;
    }
    let rem = value % alignment;
    if rem == 0 {
        value
    } else {
        value + (alignment - rem)
    }
}

fn read_r32uint_layer(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    texture: &wgpu::Texture,
    width: u32,
    height: u32,
    layer_index: u32,
) -> Result<Vec<u32>, String> {
    if width == 0 || height == 0 {
        return Ok(Vec::new());
    }

    const BYTES_PER_PIXEL: u32 = 4;
    const COPY_BYTES_PER_ROW_ALIGNMENT: u32 = 256;

    let bytes_per_row_unpadded = width
        .checked_mul(BYTES_PER_PIXEL)
        .ok_or_else(|| "read_r32uint_layer: bytes_per_row overflow".to_string())?;
    let bytes_per_row_padded = align_up_u32(bytes_per_row_unpadded, COPY_BYTES_PER_ROW_ALIGNMENT);
    if bytes_per_row_padded == 0 {
        return Err("read_r32uint_layer: bytes_per_row_padded == 0".to_string());
    }
    let readback_size = (bytes_per_row_padded as u64)
        .checked_mul(height as u64)
        .ok_or_else(|| "read_r32uint_layer: readback_size overflow".to_string())?;

    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("misa-rin canvas layer readback"),
        size: readback_size,
        usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("misa-rin canvas layer readback encoder"),
    });
    encoder.copy_texture_to_buffer(
        wgpu::ImageCopyTexture {
            texture,
            mip_level: 0,
            origin: wgpu::Origin3d {
                x: 0,
                y: 0,
                z: layer_index,
            },
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::ImageCopyBuffer {
            buffer: &readback,
            layout: wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(bytes_per_row_padded),
                rows_per_image: Some(height),
            },
        },
        wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
    );
    queue.submit(Some(encoder.finish()));

    let buffer_slice = readback.slice(0..readback_size);
    let (tx, rx) = mpsc::channel();
    buffer_slice.map_async(wgpu::MapMode::Read, move |res| {
        let _ = tx.send(res);
    });
    device.poll(wgpu::Maintain::Wait);

    let map_status: Result<(), String> = match rx.recv() {
        Ok(Ok(())) => Ok(()),
        Ok(Err(e)) => Err(format!("read_r32uint_layer: map_async failed: {e:?}")),
        Err(e) => Err(format!("read_r32uint_layer: map_async channel failed: {e}")),
    };

    let mut result: Option<Vec<u32>> = None;
    if map_status.is_ok() {
        let mapped = buffer_slice.get_mapped_range();
        result = Some(unpack_u32_rows_without_padding(
            &mapped,
            width,
            height,
            bytes_per_row_padded,
        )?);
        drop(mapped);
        readback.unmap();
    }

    map_status?;
    Ok(result.unwrap_or_default())
}

fn read_bgra_texture(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    texture: &wgpu::Texture,
    width: u32,
    height: u32,
) -> Result<Vec<u8>, String> {
    if width == 0 || height == 0 {
        return Ok(Vec::new());
    }

    const BYTES_PER_PIXEL: u32 = 4;
    const COPY_BYTES_PER_ROW_ALIGNMENT: u32 = 256;

    let bytes_per_row_unpadded = width
        .checked_mul(BYTES_PER_PIXEL)
        .ok_or_else(|| "read_bgra_texture: bytes_per_row overflow".to_string())?;
    let bytes_per_row_padded = align_up_u32(bytes_per_row_unpadded, COPY_BYTES_PER_ROW_ALIGNMENT);
    if bytes_per_row_padded == 0 {
        return Err("read_bgra_texture: bytes_per_row_padded == 0".to_string());
    }
    let readback_size = (bytes_per_row_padded as u64)
        .checked_mul(height as u64)
        .ok_or_else(|| "read_bgra_texture: readback_size overflow".to_string())?;

    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("misa-rin canvas present readback"),
        size: readback_size,
        usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("misa-rin canvas present readback encoder"),
    });
    encoder.copy_texture_to_buffer(
        wgpu::ImageCopyTexture {
            texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::ImageCopyBuffer {
            buffer: &readback,
            layout: wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(bytes_per_row_padded),
                rows_per_image: Some(height),
            },
        },
        wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
    );
    queue.submit(Some(encoder.finish()));

    let buffer_slice = readback.slice(0..readback_size);
    let (tx, rx) = mpsc::channel();
    buffer_slice.map_async(wgpu::MapMode::Read, move |res| {
        let _ = tx.send(res);
    });
    device.poll(wgpu::Maintain::Wait);

    let map_status: Result<(), String> = match rx.recv() {
        Ok(Ok(())) => Ok(()),
        Ok(Err(e)) => Err(format!("read_bgra_texture: map_async failed: {e:?}")),
        Err(e) => Err(format!("read_bgra_texture: map_async channel failed: {e}")),
    };

    let mut result: Option<Vec<u8>> = None;
    if map_status.is_ok() {
        let mapped = buffer_slice.get_mapped_range();
        result = Some(unpack_u8_rows_without_padding(
            &mapped,
            width,
            height,
            bytes_per_row_padded,
        )?);
        drop(mapped);
        readback.unmap();
    }

    map_status?;
    Ok(result.unwrap_or_default())
}

fn bgra_to_rgba(mut bytes: Vec<u8>) -> Vec<u8> {
    for chunk in bytes.chunks_exact_mut(4) {
        let b = chunk[0];
        chunk[0] = chunk[2];
        chunk[2] = b;
    }
    bytes
}

fn write_r32uint_region(
    queue: &wgpu::Queue,
    texture: &wgpu::Texture,
    left: u32,
    top: u32,
    width: u32,
    height: u32,
    layer_index: u32,
    bytes_per_row_padded: u32,
    data: &[u8],
) {
    if width == 0 || height == 0 {
        return;
    }
    queue.write_texture(
        wgpu::ImageCopyTexture {
            texture,
            mip_level: 0,
            origin: wgpu::Origin3d {
                x: left,
                y: top,
                z: layer_index,
            },
            aspect: wgpu::TextureAspect::All,
        },
        data,
        wgpu::ImageDataLayout {
            offset: 0,
            bytes_per_row: Some(bytes_per_row_padded),
            rows_per_image: Some(height),
        },
        wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
    );
}

fn pack_u32_rows_with_padding(
    pixels: &[u32],
    width: u32,
    height: u32,
    bytes_per_row_padded: u32,
) -> Result<Vec<u8>, String> {
    if width == 0 || height == 0 {
        return Ok(Vec::new());
    }
    let expected_len = (width as usize)
        .checked_mul(height as usize)
        .ok_or_else(|| "pack_u32_rows_with_padding: pixel_count overflow".to_string())?;
    if pixels.len() != expected_len {
        return Err(format!(
            "pack_u32_rows_with_padding: pixel len mismatch: got {}, expected {}",
            pixels.len(),
            expected_len
        ));
    }

    let bytes_per_row_unpadded: usize = (width as usize)
        .checked_mul(4)
        .ok_or_else(|| "pack_u32_rows_with_padding: bytes_per_row overflow".to_string())?;
    let bytes_per_row_padded_usize = bytes_per_row_padded as usize;
    let total_bytes: usize = bytes_per_row_padded_usize
        .checked_mul(height as usize)
        .ok_or_else(|| "pack_u32_rows_with_padding: total_bytes overflow".to_string())?;

    let mut out = vec![0u8; total_bytes];
    let width_usize = width as usize;
    for y in 0..height as usize {
        let src_row_start = y * width_usize;
        let row = &pixels[src_row_start..(src_row_start + width_usize)];
        let row_bytes: &[u8] = bytemuck::cast_slice(row);
        let dst_offset = y * bytes_per_row_padded_usize;
        out[dst_offset..(dst_offset + bytes_per_row_unpadded)].copy_from_slice(row_bytes);
    }
    Ok(out)
}

fn unpack_u32_rows_without_padding(
    data: &[u8],
    width: u32,
    height: u32,
    bytes_per_row_padded: u32,
) -> Result<Vec<u32>, String> {
    if width == 0 || height == 0 {
        return Ok(Vec::new());
    }
    let bytes_per_row_unpadded: usize = (width as usize)
        .checked_mul(4)
        .ok_or_else(|| "unpack_u32_rows_without_padding: bytes_per_row overflow".to_string())?;
    let bytes_per_row_padded_usize = bytes_per_row_padded as usize;
    let pixel_count: usize = (width as usize)
        .checked_mul(height as usize)
        .ok_or_else(|| "unpack_u32_rows_without_padding: pixel_count overflow".to_string())?;
    let mut out: Vec<u32> = vec![0u32; pixel_count];

    let width_usize = width as usize;
    for y in 0..height as usize {
        let src_offset = y * bytes_per_row_padded_usize;
        let row_bytes = &data[src_offset..(src_offset + bytes_per_row_unpadded)];
        let row_u32: &[u32] = bytemuck::cast_slice(row_bytes);
        let dst_row_start = y * width_usize;
        out[dst_row_start..(dst_row_start + width_usize)].copy_from_slice(row_u32);
    }
    Ok(out)
}

fn unpack_u8_rows_without_padding(
    data: &[u8],
    width: u32,
    height: u32,
    bytes_per_row_padded: u32,
) -> Result<Vec<u8>, String> {
    if width == 0 || height == 0 {
        return Ok(Vec::new());
    }
    let bytes_per_row_unpadded: usize = (width as usize)
        .checked_mul(4)
        .ok_or_else(|| "unpack_u8_rows_without_padding: bytes_per_row overflow".to_string())?;
    let bytes_per_row_padded_usize = bytes_per_row_padded as usize;
    let total_bytes: usize = bytes_per_row_unpadded
        .checked_mul(height as usize)
        .ok_or_else(|| "unpack_u8_rows_without_padding: total_bytes overflow".to_string())?;
    let mut out: Vec<u8> = vec![0u8; total_bytes];

    for y in 0..height as usize {
        let src_offset = y * bytes_per_row_padded_usize;
        let dst_offset = y * bytes_per_row_unpadded;
        out[dst_offset..(dst_offset + bytes_per_row_unpadded)]
            .copy_from_slice(&data[src_offset..(src_offset + bytes_per_row_unpadded)]);
    }
    Ok(out)
}

fn composite_layers_for_bucket_fill(
    width: usize,
    height: usize,
    layers_pixels: &[Vec<u32>],
    layer_opacity: &[f32],
    layer_visible: &[bool],
    layer_clipping_mask: &[bool],
) -> Vec<u32> {
    let len = match width.checked_mul(height) {
        Some(v) => v,
        None => return Vec::new(),
    };
    let mut composite = vec![0u32; len];

    for index in 0..len {
        let mut color: u32 = 0;
        let mut initialized = false;
        let mut mask_alpha: u8 = 0;

        for layer_idx in 0..layers_pixels.len() {
            let visible = layer_visible.get(layer_idx).copied().unwrap_or(true);
            if !visible {
                continue;
            }
            let opacity = layer_opacity.get(layer_idx).copied().unwrap_or(1.0);
            let clipping = layer_clipping_mask.get(layer_idx).copied().unwrap_or(false);
            if opacity <= 0.0 {
                if !clipping {
                    mask_alpha = 0;
                }
                continue;
            }
            let pixels = &layers_pixels[layer_idx];
            if pixels.len() != len {
                if !clipping {
                    mask_alpha = 0;
                }
                continue;
            }
            let src = pixels[index];
            let src_a = ((src >> 24) & 0xff) as u32;
            if src_a == 0 {
                if !clipping {
                    mask_alpha = 0;
                }
                continue;
            }

            let mut total_opacity = opacity.clamp(0.0, 1.0);
            if clipping {
                if mask_alpha == 0 {
                    continue;
                }
                total_opacity *= (mask_alpha as f32) / 255.0;
                if total_opacity <= 0.0 {
                    continue;
                }
            }

            let mut effective_a = ((src_a as f32) * total_opacity).round() as i32;
            if effective_a <= 0 {
                if !clipping {
                    mask_alpha = 0;
                }
                continue;
            }
            if effective_a > 255 {
                effective_a = 255;
            }
            if !clipping {
                mask_alpha = effective_a as u8;
            }
            let effective_color = ((effective_a as u32) << 24) | (src & 0x00FFFFFF);
            if !initialized {
                color = effective_color;
                initialized = true;
            } else {
                color = blend_argb(color, effective_color);
            }
        }

        composite[index] = if initialized { color } else { 0 };
    }

    composite
}

fn blend_argb(dst: u32, src: u32) -> u32 {
    let src_a = (src >> 24) & 0xff;
    if src_a == 0 {
        return dst;
    }
    if src_a == 255 {
        return src;
    }
    let dst_a = (dst >> 24) & 0xff;
    let inv_src_a = 255 - src_a;
    let out_a = src_a + mul255(dst_a, inv_src_a);
    if out_a == 0 {
        return 0;
    }

    let src_r = (src >> 16) & 0xff;
    let src_g = (src >> 8) & 0xff;
    let src_b = src & 0xff;
    let dst_r = (dst >> 16) & 0xff;
    let dst_g = (dst >> 8) & 0xff;
    let dst_b = dst & 0xff;

    let src_prem_r = mul255(src_r, src_a);
    let src_prem_g = mul255(src_g, src_a);
    let src_prem_b = mul255(src_b, src_a);
    let dst_prem_r = mul255(dst_r, dst_a);
    let dst_prem_g = mul255(dst_g, dst_a);
    let dst_prem_b = mul255(dst_b, dst_a);

    let out_prem_r = src_prem_r + mul255(dst_prem_r, inv_src_a);
    let out_prem_g = src_prem_g + mul255(dst_prem_g, inv_src_a);
    let out_prem_b = src_prem_b + mul255(dst_prem_b, inv_src_a);

    let out_r = (((out_prem_r * 255) + (out_a >> 1)) / out_a).min(255);
    let out_g = (((out_prem_g * 255) + (out_a >> 1)) / out_a).min(255);
    let out_b = (((out_prem_b * 255) + (out_a >> 1)) / out_a).min(255);

    (out_a << 24) | (out_r << 16) | (out_g << 8) | out_b
}

fn mul255(channel: u32, alpha: u32) -> u32 {
    (channel * alpha + 127) / 255
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn mtl_device_ptr(device: &wgpu::Device) -> *mut c_void {
    let result = unsafe {
        device.as_hal::<Metal, _, _>(|hal_device| {
            hal_device.map(|hal_device| {
                let raw_device = hal_device.raw_device().lock();
                raw_device.as_ptr() as *mut c_void
            })
        })
    };
    result.flatten().unwrap_or(std::ptr::null_mut())
}

#[cfg(not(any(target_os = "macos", target_os = "ios")))]
fn mtl_device_ptr(_device: &wgpu::Device) -> *mut c_void {
    std::ptr::null_mut()
}

pub(crate) fn create_engine(width: u32, height: u32) -> Result<u64, String> {
    if width == 0 || height == 0 {
        return Err("engine_create: width/height must be > 0".to_string());
    }

    let ctx = device_context()?;

    let mtl_device_ptr = mtl_device_ptr(ctx.device.as_ref()) as usize;
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    if mtl_device_ptr == 0 {
        return Err("wgpu: failed to extract underlying MTLDevice".to_string());
    }

    let layers = LayerTextures::new(ctx.device.as_ref(), width, height, INITIAL_LAYER_CAPACITY)
        .map_err(|err| format!("engine_create: layer init failed: {err}"))?;

    let (cmd_tx, cmd_rx) = mpsc::channel();
    let (input_tx, input_rx) = mpsc::channel();
    let input_queue_len = Arc::new(AtomicU64::new(0));
    let frame_ready = Arc::new(AtomicBool::new(false));
    let frame_in_flight = Arc::new(AtomicBool::new(false));
    spawn_render_thread(
        Arc::clone(&ctx.device),
        Arc::clone(&ctx.queue),
        layers,
        cmd_rx,
        input_rx,
        Arc::clone(&frame_ready),
        Arc::clone(&frame_in_flight),
        Arc::clone(&input_queue_len),
        width,
        height,
    );

    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    let mut guard = engines()
        .lock()
        .map_err(|_| "engine registry lock poisoned".to_string())?;
    guard.insert(
        handle,
        EngineEntry {
            mtl_device_ptr,
            frame_ready,
            frame_in_flight,
            cmd_tx,
            input_tx,
            input_queue_len,
        },
    );

    Ok(handle)
}

pub(crate) fn lookup_engine(handle: u64) -> Option<EngineEntry> {
    if handle == 0 {
        return None;
    }
    let guard = engines().lock().ok()?;
    let entry = guard.get(&handle)?;
    Some(EngineEntry {
        mtl_device_ptr: entry.mtl_device_ptr,
        frame_ready: Arc::clone(&entry.frame_ready),
        frame_in_flight: Arc::clone(&entry.frame_in_flight),
        cmd_tx: entry.cmd_tx.clone(),
        input_tx: entry.input_tx.clone(),
        input_queue_len: Arc::clone(&entry.input_queue_len),
    })
}

pub(crate) fn remove_engine(handle: u64) -> Option<EngineEntry> {
    if handle == 0 {
        return None;
    }
    let mut guard = engines().lock().ok()?;
    guard.remove(&handle)
}
