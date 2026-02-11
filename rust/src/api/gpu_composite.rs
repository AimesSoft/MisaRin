#[cfg(target_family = "wasm")]
use std::cell::RefCell;
#[cfg(not(target_family = "wasm"))]
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::gpu::compositor::{GpuCompositor, LayerData};
use crate::gpu::debug::{self, LogLevel};

#[cfg(not(target_family = "wasm"))]
static GPU_COMPOSITOR: OnceLock<Mutex<Option<GpuCompositor>>> = OnceLock::new();

#[cfg(not(target_family = "wasm"))]
fn compositor_cell() -> &'static Mutex<Option<GpuCompositor>> {
    GPU_COMPOSITOR.get_or_init(|| Mutex::new(None))
}

#[cfg(not(target_family = "wasm"))]
fn with_compositor_mut<R>(
    f: impl FnOnce(&mut Option<GpuCompositor>) -> Result<R, String>,
) -> Result<R, String> {
    let mut guard = compositor_cell()
        .lock()
        .map_err(|_| "gpu compositor lock poisoned".to_string())?;
    f(&mut *guard)
}

#[cfg(target_family = "wasm")]
thread_local! {
    static GPU_COMPOSITOR: RefCell<Option<GpuCompositor>> = RefCell::new(None);
}

#[cfg(target_family = "wasm")]
fn with_compositor_mut<R>(
    f: impl FnOnce(&mut Option<GpuCompositor>) -> Result<R, String>,
) -> Result<R, String> {
    GPU_COMPOSITOR.with(|cell| f(&mut *cell.borrow_mut()))
}

#[flutter_rust_bridge::frb]
pub struct GpuLayerData {
    pub pixels: Vec<u32>,
    pub opacity: f64,
    pub blend_mode_index: u32,
    pub visible: bool,
    pub clipping_mask: bool,
}

#[flutter_rust_bridge::frb(sync)]
pub fn gpu_compositor_init() -> Result<(), String> {
    with_compositor_mut(|guard| {
        if guard.is_some() {
            return Ok(());
        }
        let t0 = Instant::now();
        let compositor = GpuCompositor::new()?;
        *guard = Some(compositor);
        debug::log(
            LogLevel::Info,
            format_args!("gpu_compositor_init ok in {:?}.", t0.elapsed()),
        );
        Ok(())
    })
}

pub fn gpu_composite_layers(
    layers: Vec<GpuLayerData>,
    width: u32,
    height: u32,
) -> Result<Vec<u32>, String> {
    let seq = debug::next_seq();
    let t0 = Instant::now();

    return with_compositor_mut(|guard| {
        let compositor = guard.as_mut().ok_or_else(|| {
            "gpu compositor not initialized (call gpu_compositor_init first)".to_string()
        })?;

    let pixel_count_u64 = (width as u64).saturating_mul(height as u64);
    let expected_len_u64 = pixel_count_u64;

    let mut non_empty_layers: usize = 0;
    let mut empty_layers: usize = 0;
    let mut mismatched_layers: usize = 0;
    let mut total_input_u32: u64 = 0;
    for layer in &layers {
        let len = layer.pixels.len() as u64;
        total_input_u32 = total_input_u32.saturating_add(len);
        if layer.pixels.is_empty() {
            empty_layers += 1;
            continue;
        }
        non_empty_layers += 1;
        if expected_len_u64 > 0 && len != expected_len_u64 {
            mismatched_layers += 1;
        }
    }

    debug::log(
        LogLevel::Info,
        format_args!(
            "#{seq} gpu_composite_layers canvas={width}x{height} layers={} upload_layers={non_empty_layers} empty_layers={empty_layers} mismatched_layers={mismatched_layers} total_input_u32={total_input_u32}",
            layers.len()
        ),
    );
    if !layers.is_empty() && non_empty_layers == 0 {
        debug::log(
            LogLevel::Warn,
            format_args!(
                "#{seq} gpu_composite_layers: ALL layers have empty pixels (canvas={width}x{height}); compositor will rely on cached GPU state"
            ),
        );
    }
    if mismatched_layers > 0 {
        debug::log(
            LogLevel::Warn,
            format_args!(
                "#{seq} gpu_composite_layers: {mismatched_layers} layer(s) pixel length mismatch vs expected={expected_len_u64}"
            ),
        );
    }
    if debug::level() >= LogLevel::Verbose {
        for (idx, layer) in layers.iter().enumerate() {
            debug::log(
                LogLevel::Verbose,
                format_args!(
                    "#{seq}  layer[{idx}] pixels_len={} opacity={:.3} visible={} clip={} blend={}",
                    layer.pixels.len(),
                    layer.opacity,
                    layer.visible,
                    layer.clipping_mask,
                    layer.blend_mode_index
                ),
            );
        }
    }

    let converted: Vec<LayerData> = layers
        .into_iter()
        .map(|layer| LayerData {
            pixels: layer.pixels,
            opacity: clamp_unit_f64_to_f32(layer.opacity),
            blend_mode: layer.blend_mode_index,
            visible: layer.visible,
            clipping_mask: layer.clipping_mask,
        })
        .collect();

    let result = compositor.composite_layers(converted, width, height);

    let elapsed = t0.elapsed();
    match &result {
        Ok(out) => {
            let out_len = out.len() as u64;
            if elapsed >= Duration::from_millis(50) {
                debug::log(
                    LogLevel::Warn,
                    format_args!(
                        "#{seq} gpu_composite_layers SLOW ok out_len={out_len} in {:?}.",
                        elapsed
                    ),
                );
            } else {
                debug::log(
                    LogLevel::Verbose,
                    format_args!(
                        "#{seq} gpu_composite_layers ok out_len={out_len} in {:?}.",
                        elapsed
                    ),
                );
            }
        }
        Err(err) => {
            debug::log(
                LogLevel::Warn,
                format_args!("#{seq} gpu_composite_layers ERR in {:?}: {err}", elapsed),
            );
        }
    }

        result
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn gpu_compositor_dispose() {
    let _ = with_compositor_mut(|guard| {
        *guard = None;
        Ok(())
    });
}

fn clamp_unit_f64_to_f32(value: f64) -> f32 {
    if !value.is_finite() {
        return 0.0;
    }
    let clamped = value.clamp(0.0, 1.0);
    clamped as f32
}
