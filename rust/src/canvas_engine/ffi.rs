use std::ffi::c_void;
use std::os::raw::c_char;

use super::types::{EnginePoint, SprayPoint};

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
use super::engine::{create_engine, lookup_engine, remove_engine, EngineCommand, EngineInputBatch};
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
use crate::gpu::debug::{self, LogLevel};
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
use std::ffi::CString;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
use std::collections::HashMap;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
use std::sync::atomic::{AtomicU64, Ordering};
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
use std::sync::{Mutex, OnceLock};
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
use std::sync::mpsc;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
use std::time::{SystemTime, UNIX_EPOCH};

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_create(width: u32, height: u32) -> u64 {
    match create_engine(width, height) {
        Ok(handle) => {
            debug::log(
                LogLevel::Info,
                format_args!("engine_create ok handle={handle} size={width}x{height}"),
            );
            handle
        }
        Err(err) => {
            debug::log(LogLevel::Warn, format_args!("engine_create failed: {err}"));
            0
        }
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_create(_width: u32, _height: u32) -> u64 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_get_mtl_device(handle: u64) -> *mut c_void {
    lookup_engine(handle)
        .map(|entry| entry.mtl_device_ptr as *mut c_void)
        .unwrap_or(std::ptr::null_mut())
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_get_mtl_device(_handle: u64) -> *mut c_void {
    std::ptr::null_mut()
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_attach_present_texture(
    handle: u64,
    mtl_texture_ptr: *mut c_void,
    width: u32,
    height: u32,
    bytes_per_row: u32,
) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::AttachPresentTexture {
        mtl_texture_ptr: mtl_texture_ptr as usize,
        width,
        height,
        bytes_per_row,
    });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_attach_present_texture(
    _handle: u64,
    _mtl_texture_ptr: *mut c_void,
    _width: u32,
    _height: u32,
    _bytes_per_row: u32,
) {
}

#[cfg(target_os = "windows")]
#[no_mangle]
pub extern "C" fn engine_create_present_dxgi_surface(
    handle: u64,
    width: u32,
    height: u32,
) -> *mut c_void {
    if width == 0 || height == 0 {
        return std::ptr::null_mut();
    }
    let Some(entry) = lookup_engine(handle) else {
        return std::ptr::null_mut();
    };

    let start = std::time::Instant::now();
    println!("[misa-rin][rust] dxgi_surface: request handle={handle} size={width}x{height}");

    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::AttachPresentDxgi {
            width,
            height,
            reply: tx,
        })
        .is_err()
    {
        println!("[misa-rin][rust] dxgi_surface: request failed (send)");
        return std::ptr::null_mut();
    }

    match rx.recv() {
        Ok(Some(shared_handle)) => {
            println!(
                "[misa-rin][rust] dxgi_surface: ready handle={handle} shared=0x{:x} took {}ms",
                shared_handle,
                start.elapsed().as_millis()
            );
            shared_handle as *mut c_void
        }
        Ok(None) => {
            println!("[misa-rin][rust] dxgi_surface: failed (null) took {}ms", start.elapsed().as_millis());
            std::ptr::null_mut()
        }
        Err(_) => {
            println!("[misa-rin][rust] dxgi_surface: failed (recv) took {}ms", start.elapsed().as_millis());
            std::ptr::null_mut()
        }
    }
}

#[cfg(not(target_os = "windows"))]
#[no_mangle]
pub extern "C" fn engine_create_present_dxgi_surface(
    _handle: u64,
    _width: u32,
    _height: u32,
) -> *mut c_void {
    std::ptr::null_mut()
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_dispose(handle: u64) {
    let Some(entry) = remove_engine(handle) else {
        debug::log(
            LogLevel::Warn,
            format_args!("engine_dispose missing handle={handle}"),
        );
        return;
    };
    debug::log(LogLevel::Info, format_args!("engine_dispose handle={handle}"));
    let _ = entry.cmd_tx.send(EngineCommand::Stop);
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_dispose(_handle: u64) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[derive(Default)]
struct FrameReadyPollStats {
    last_log_ms: u64,
    poll_count: u64,
    ready_count: u64,
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
static FRAME_READY_STATS: OnceLock<Mutex<HashMap<u64, FrameReadyPollStats>>> = OnceLock::new();
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
static LAST_INPUT_LOG_MS: AtomicU64 = AtomicU64::new(0);
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
static LAST_BRUSH_LOG_MS: AtomicU64 = AtomicU64::new(0);
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
static LAST_FILL_LOG_MS: AtomicU64 = AtomicU64::new(0);

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
fn frame_ready_stats() -> &'static Mutex<HashMap<u64, FrameReadyPollStats>> {
    FRAME_READY_STATS.get_or_init(|| Mutex::new(HashMap::new()))
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_poll_frame_ready(handle: u64) -> bool {
    let Some(entry) = lookup_engine(handle) else {
        return false;
    };
    let ready = entry.frame_ready.swap(false, Ordering::AcqRel);
    if debug::level() >= LogLevel::Info {
        let now = now_ms();
        let mut guard = frame_ready_stats()
            .lock()
            .unwrap_or_else(|err| err.into_inner());
        let stats = guard.entry(handle).or_default();
        stats.poll_count = stats.poll_count.saturating_add(1);
        if ready {
            stats.ready_count = stats.ready_count.saturating_add(1);
        }
        if now.saturating_sub(stats.last_log_ms) >= 1000 {
            debug::log(
                LogLevel::Info,
                format_args!(
                    "frame_ready poll handle={handle} polls={} ready={}",
                    stats.poll_count, stats.ready_count
                ),
            );
            stats.last_log_ms = now;
            stats.poll_count = 0;
            stats.ready_count = 0;
        }
    }
    ready
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_poll_frame_ready(_handle: u64) -> bool {
    false
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_push_points(handle: u64, points: *const EnginePoint, len: usize) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    if points.is_null() || len == 0 {
        return;
    }
    let slice = unsafe { std::slice::from_raw_parts(points, len) };
    let mut owned: Vec<EnginePoint> = Vec::with_capacity(len);
    owned.extend_from_slice(slice);
    let queue_len = entry
        .input_queue_len
        .fetch_add(len as u64, Ordering::Relaxed)
        + len as u64;

    if debug::level() >= LogLevel::Info {
        let now = now_ms();
        let last = LAST_INPUT_LOG_MS.load(Ordering::Relaxed);
        if now.saturating_sub(last) >= 500 {
            LAST_INPUT_LOG_MS.store(now, Ordering::Relaxed);
            let first_flags = slice.first().map(|p| p.flags).unwrap_or(0);
            let last_flags = slice.last().map(|p| p.flags).unwrap_or(0);
            debug::log(
                LogLevel::Info,
                format_args!(
                    "engine_push_points handle={handle} len={len} first_flags={first_flags} last_flags={last_flags} queue_len={queue_len}"
                ),
            );
        }
    }

    if debug::level() >= LogLevel::Verbose {
        const FLAG_DOWN: u32 = 1;
        const FLAG_UP: u32 = 4;
        let mut down_count: usize = 0;
        let mut up_count: usize = 0;
        for p in slice {
            if (p.flags & FLAG_DOWN) != 0 {
                down_count += 1;
            }
            if (p.flags & FLAG_UP) != 0 {
                up_count += 1;
            }
        }
        debug::log(
            LogLevel::Verbose,
            format_args!(
                "engine_push_points handle={handle} len={len} down={down_count} up={up_count} queue_len={queue_len}"
            ),
        );
    }

    if entry
        .input_tx
        .send(EngineInputBatch { points: owned })
        .is_err()
    {
        entry
            .input_queue_len
            .fetch_sub(len as u64, Ordering::Relaxed);
        debug::log(
            LogLevel::Warn,
            format_args!("engine_push_points dropped: input thread disconnected"),
        );
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_push_points(_handle: u64, _points: *const EnginePoint, _len: usize) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_get_input_queue_len(handle: u64) -> u64 {
    lookup_engine(handle)
        .map(|entry| entry.input_queue_len.load(Ordering::Relaxed))
        .unwrap_or(0)
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_set_log_level(level: u32) {
    debug::set_level_from_u32(level);
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_is_valid(handle: u64) -> u8 {
    if lookup_engine(handle).is_some() { 1 } else { 0 }
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_log_pop() -> *mut c_char {
    match debug::pop_log_line() {
        Some(line) => CString::new(line).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_log_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { let _ = CString::from_raw(ptr); };
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_get_input_queue_len(_handle: u64) -> u64 {
    0
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_set_log_level(_level: u32) {}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_is_valid(_handle: u64) -> u8 {
    0
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_log_pop() -> *mut c_char {
    std::ptr::null_mut()
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_log_free(_ptr: *mut c_char) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_set_active_layer(handle: u64, layer_index: u32) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry
        .cmd_tx
        .send(EngineCommand::SetActiveLayer { layer_index });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_set_active_layer(_handle: u64, _layer_index: u32) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_set_layer_opacity(handle: u64, layer_index: u32, opacity: f32) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::SetLayerOpacity {
        layer_index,
        opacity,
    });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_set_layer_opacity(_handle: u64, _layer_index: u32, _opacity: f32) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_set_layer_visible(handle: u64, layer_index: u32, visible: bool) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::SetLayerVisible {
        layer_index,
        visible,
    });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_set_layer_visible(_handle: u64, _layer_index: u32, _visible: bool) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_set_layer_clipping_mask(
    handle: u64,
    layer_index: u32,
    clipping_mask: bool,
) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::SetLayerClippingMask {
        layer_index,
        clipping_mask,
    });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_set_layer_clipping_mask(
    _handle: u64,
    _layer_index: u32,
    _clipping_mask: bool,
) {
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_set_layer_blend_mode(
    handle: u64,
    layer_index: u32,
    blend_mode_index: u32,
) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::SetLayerBlendMode {
        layer_index,
        blend_mode_index,
    });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_set_layer_blend_mode(
    _handle: u64,
    _layer_index: u32,
    _blend_mode_index: u32,
) {
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_reorder_layer(handle: u64, from_index: u32, to_index: u32) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::ReorderLayer {
        from_index,
        to_index,
    });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_reorder_layer(_handle: u64, _from_index: u32, _to_index: u32) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_set_view_flags(handle: u64, view_flags: u32) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry
        .cmd_tx
        .send(EngineCommand::SetViewFlags { view_flags });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_set_view_flags(_handle: u64, _view_flags: u32) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_set_brush(
    handle: u64,
    color_argb: u32,
    base_radius: f32,
    use_pressure: u8,
    erase: u8,
    antialias_level: u32,
    brush_shape: u32,
    random_rotation: u8,
    smooth_rotation: u8,
    rotation_seed: u32,
    spacing: f32,
    hardness: f32,
    flow: f32,
    scatter: f32,
    rotation_jitter: f32,
    snap_to_pixel: u8,
    screentone_enabled: u8,
    screentone_spacing: f32,
    screentone_dot_size: f32,
    screentone_rotation: f32,
    screentone_softness: f32,
    screentone_shape: u32,
    hollow_enabled: u8,
    hollow_ratio: f32,
    hollow_erase_occluded: u8,
    streamline_strength: f32,
    smoothing_mode: u32,
    stabilizer_strength: f32,
) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    if debug::level() >= LogLevel::Info {
        let now = now_ms();
        let last = LAST_BRUSH_LOG_MS.load(Ordering::Relaxed);
        if now.saturating_sub(last) >= 500 {
            LAST_BRUSH_LOG_MS.store(now, Ordering::Relaxed);
            debug::log(
                LogLevel::Info,
                format_args!(
                    "engine_set_brush handle={handle} color=0x{color_argb:08X} radius={base_radius:.2} erase={} shape={} aa={antialias_level} pressure={}",
                    erase != 0,
                    brush_shape,
                    use_pressure != 0
                ),
            );
        }
    }
    let _ = entry.cmd_tx.send(EngineCommand::SetBrush {
        color_argb,
        base_radius,
        use_pressure: use_pressure != 0,
        erase: erase != 0,
        antialias_level,
        brush_shape,
        random_rotation: random_rotation != 0,
        smooth_rotation: smooth_rotation != 0,
        rotation_seed,
        spacing,
        hardness,
        flow,
        scatter,
        rotation_jitter,
        snap_to_pixel: snap_to_pixel != 0,
        screentone_enabled: screentone_enabled != 0,
        screentone_spacing,
        screentone_dot_size,
        screentone_rotation,
        screentone_softness,
        screentone_shape,
        hollow_enabled: hollow_enabled != 0,
        hollow_ratio,
        hollow_erase_occluded: hollow_erase_occluded != 0,
        streamline_strength,
        smoothing_mode,
        stabilizer_strength,
    });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_set_brush(
    _handle: u64,
    _color_argb: u32,
    _base_radius: f32,
    _use_pressure: u8,
    _erase: u8,
    _antialias_level: u32,
    _brush_shape: u32,
    _random_rotation: u8,
    _smooth_rotation: u8,
    _rotation_seed: u32,
    _spacing: f32,
    _hardness: f32,
    _flow: f32,
    _scatter: f32,
    _rotation_jitter: f32,
    _snap_to_pixel: u8,
    _screentone_enabled: u8,
    _screentone_spacing: f32,
    _screentone_dot_size: f32,
    _screentone_rotation: f32,
    _screentone_softness: f32,
    _screentone_shape: u32,
    _hollow_enabled: u8,
    _hollow_ratio: f32,
    _hollow_erase_occluded: u8,
    _streamline_strength: f32,
    _smoothing_mode: u32,
    _stabilizer_strength: f32,
) {
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_set_brush_mask(
    handle: u64,
    width: u32,
    height: u32,
    mask_ptr: *const u8,
    mask_len: usize,
) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    if mask_ptr.is_null() || mask_len == 0 || width == 0 || height == 0 {
        let _ = entry.cmd_tx.send(EngineCommand::ClearBrushMask);
        return;
    }
    let expected_len = (width as usize)
        .checked_mul(height as usize)
        .and_then(|v| v.checked_mul(2));
    if expected_len.is_none() || expected_len != Some(mask_len) {
        let _ = entry.cmd_tx.send(EngineCommand::ClearBrushMask);
        return;
    }
    let mask = unsafe { std::slice::from_raw_parts(mask_ptr, mask_len).to_vec() };
    let _ = entry
        .cmd_tx
        .send(EngineCommand::SetBrushMask { width, height, mask });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_set_brush_mask(
    _handle: u64,
    _width: u32,
    _height: u32,
    _mask_ptr: *const u8,
    _mask_len: usize,
) {
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_clear_brush_mask(handle: u64) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::ClearBrushMask);
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_clear_brush_mask(_handle: u64) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_spray_begin(handle: u64) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::BeginSpray);
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_spray_begin(_handle: u64) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_spray_draw(
    handle: u64,
    points: *const f32,
    len: usize,
    color_argb: u32,
    brush_shape: u32,
    erase: u8,
    antialias_level: u32,
    softness: f32,
    accumulate: u8,
) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    if points.is_null() || len == 0 {
        return;
    }
    let float_len = match len.checked_mul(4) {
        Some(value) => value,
        None => return,
    };
    let slice = unsafe { std::slice::from_raw_parts(points, float_len) };
    let mut owned: Vec<SprayPoint> = Vec::with_capacity(len);
    for i in 0..len {
        let base = i * 4;
        let x = slice[base];
        let y = slice[base + 1];
        let radius = slice[base + 2];
        let alpha = slice[base + 3];
        owned.push(SprayPoint {
            x,
            y,
            radius,
            alpha,
        });
    }
    let _ = entry.cmd_tx.send(EngineCommand::DrawSpray {
        points: owned,
        color_argb,
        brush_shape,
        erase: erase != 0,
        antialias_level,
        softness,
        accumulate: accumulate != 0,
    });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_spray_draw(
    _handle: u64,
    _points: *const f32,
    _len: usize,
    _color_argb: u32,
    _brush_shape: u32,
    _erase: u8,
    _antialias_level: u32,
    _softness: f32,
    _accumulate: u8,
) {
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_spray_end(handle: u64) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::EndSpray);
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_spray_end(_handle: u64) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_apply_filter(
    handle: u64,
    layer_index: u32,
    filter_type: u32,
    param0: f32,
    param1: f32,
    param2: f32,
    param3: f32,
) -> u8 {
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };
    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::ApplyFilter {
            layer_index,
            filter_type,
            param0,
            param1,
            param2,
            param3,
            reply: tx,
        })
        .is_err()
    {
        return 0;
    }
    match rx.recv() {
        Ok(changed) => if changed { 1 } else { 0 },
        Err(_) => 0,
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_apply_filter(
    _handle: u64,
    _layer_index: u32,
    _filter_type: u32,
    _param0: f32,
    _param1: f32,
    _param2: f32,
    _param3: f32,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_apply_antialias(
    handle: u64,
    layer_index: u32,
    level: u32,
) -> u8 {
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };
    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::ApplyAntialias {
            layer_index,
            level,
            reply: tx,
        })
        .is_err()
    {
        return 0;
    }
    match rx.recv() {
        Ok(changed) => if changed { 1 } else { 0 },
        Err(_) => 0,
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_apply_antialias(
    _handle: u64,
    _layer_index: u32,
    _level: u32,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_clear_layer(handle: u64, layer_index: u32) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::ClearLayer { layer_index });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_clear_layer(_handle: u64, _layer_index: u32) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_fill_layer(handle: u64, layer_index: u32, color_argb: u32) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    if debug::level() >= LogLevel::Info {
        let now = now_ms();
        let last = LAST_FILL_LOG_MS.load(Ordering::Relaxed);
        if now.saturating_sub(last) >= 500 {
            LAST_FILL_LOG_MS.store(now, Ordering::Relaxed);
            debug::log(
                LogLevel::Info,
                format_args!(
                    "engine_fill_layer handle={handle} layer={layer_index} color=0x{color_argb:08X}"
                ),
            );
        }
    }
    let _ = entry.cmd_tx.send(EngineCommand::FillLayer {
        layer_index,
        color_argb,
    });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_fill_layer(_handle: u64, _layer_index: u32, _color_argb: u32) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_bucket_fill(
    handle: u64,
    layer_index: u32,
    start_x: i32,
    start_y: i32,
    color_argb: u32,
    contiguous: u8,
    sample_all_layers: u8,
    tolerance: u32,
    fill_gap: u32,
    antialias_level: u32,
    swallow_colors_ptr: *const u32,
    swallow_colors_len: usize,
    selection_mask_ptr: *const u8,
    selection_mask_len: usize,
) -> u8 {
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };

    let swallow_colors: Vec<u32> = if swallow_colors_ptr.is_null() || swallow_colors_len == 0 {
        Vec::new()
    } else {
        unsafe { std::slice::from_raw_parts(swallow_colors_ptr, swallow_colors_len).to_vec() }
    };
    let selection_mask: Option<Vec<u8>> = if selection_mask_ptr.is_null() || selection_mask_len == 0
    {
        None
    } else {
        Some(unsafe { std::slice::from_raw_parts(selection_mask_ptr, selection_mask_len).to_vec() })
    };

    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::BucketFill {
            layer_index,
            start_x,
            start_y,
            color_argb,
            contiguous: contiguous != 0,
            sample_all_layers: sample_all_layers != 0,
            tolerance: tolerance.min(255) as u8,
            fill_gap: fill_gap.min(64) as u8,
            antialias_level: antialias_level.min(9) as u8,
            swallow_colors,
            selection_mask,
            reply: tx,
        })
        .is_err()
    {
        return 0;
    }

    match rx.recv() {
        Ok(changed) => {
            if changed {
                1
            } else {
                0
            }
        }
        Err(_) => 0,
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_bucket_fill(
    _handle: u64,
    _layer_index: u32,
    _start_x: i32,
    _start_y: i32,
    _color_argb: u32,
    _contiguous: u8,
    _sample_all_layers: u8,
    _tolerance: u32,
    _fill_gap: u32,
    _antialias_level: u32,
    _swallow_colors_ptr: *const u32,
    _swallow_colors_len: usize,
    _selection_mask_ptr: *const u8,
    _selection_mask_len: usize,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_magic_wand_mask(
    handle: u64,
    layer_index: u32,
    start_x: i32,
    start_y: i32,
    sample_all_layers: u8,
    tolerance: u32,
    selection_mask_ptr: *const u8,
    selection_mask_len: usize,
    out_mask_ptr: *mut u8,
    out_mask_len: usize,
) -> u8 {
    if out_mask_ptr.is_null() || out_mask_len == 0 {
        return 0;
    }
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };

    let selection_mask: Option<Vec<u8>> = if selection_mask_ptr.is_null() || selection_mask_len == 0
    {
        None
    } else {
        Some(unsafe { std::slice::from_raw_parts(selection_mask_ptr, selection_mask_len).to_vec() })
    };

    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::MagicWandMask {
            layer_index,
            start_x,
            start_y,
            sample_all_layers: sample_all_layers != 0,
            tolerance: tolerance.min(255) as u8,
            selection_mask,
            reply: tx,
        })
        .is_err()
    {
        return 0;
    }

    match rx.recv() {
        Ok(Some(mask)) => {
            if mask.len() != out_mask_len {
                return 0;
            }
            unsafe {
                std::ptr::copy_nonoverlapping(mask.as_ptr(), out_mask_ptr, mask.len());
            }
            1
        }
        _ => 0,
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_magic_wand_mask(
    _handle: u64,
    _layer_index: u32,
    _start_x: i32,
    _start_y: i32,
    _sample_all_layers: u8,
    _tolerance: u32,
    _selection_mask_ptr: *const u8,
    _selection_mask_len: usize,
    _out_mask_ptr: *mut u8,
    _out_mask_len: usize,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_read_layer(
    handle: u64,
    layer_index: u32,
    out_pixels_ptr: *mut u32,
    out_pixels_len: usize,
) -> u8 {
    if out_pixels_ptr.is_null() || out_pixels_len == 0 {
        return 0;
    }
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };

    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::ReadLayer {
            layer_index,
            reply: tx,
        })
        .is_err()
    {
        return 0;
    }

    match rx.recv() {
        Ok(Some(pixels)) => {
            if pixels.len() != out_pixels_len {
                return 0;
            }
            unsafe {
                std::ptr::copy_nonoverlapping(pixels.as_ptr(), out_pixels_ptr, pixels.len());
            }
            1
        }
        _ => 0,
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_read_layer(
    _handle: u64,
    _layer_index: u32,
    _out_pixels_ptr: *mut u32,
    _out_pixels_len: usize,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_read_layer_preview(
    handle: u64,
    layer_index: u32,
    width: u32,
    height: u32,
    out_pixels_ptr: *mut u8,
    out_pixels_len: usize,
) -> u8 {
    if out_pixels_ptr.is_null() || out_pixels_len == 0 {
        return 0;
    }
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };
    let expected_len = (width as usize)
        .saturating_mul(height as usize)
        .saturating_mul(4);
    if expected_len == 0 || out_pixels_len != expected_len {
        return 0;
    }

    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::ReadLayerPreview {
            layer_index,
            width,
            height,
            reply: tx,
        })
        .is_err()
    {
        return 0;
    }

    match rx.recv() {
        Ok(Some(pixels)) => {
            if pixels.len() != out_pixels_len {
                return 0;
            }
            unsafe {
                std::ptr::copy_nonoverlapping(pixels.as_ptr(), out_pixels_ptr, pixels.len());
            }
            1
        }
        _ => 0,
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_read_layer_preview(
    _handle: u64,
    _layer_index: u32,
    _width: u32,
    _height: u32,
    _out_pixels_ptr: *mut u8,
    _out_pixels_len: usize,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_read_present(
    handle: u64,
    out_pixels_ptr: *mut u8,
    out_pixels_len: usize,
) -> u8 {
    if out_pixels_ptr.is_null() || out_pixels_len == 0 {
        return 0;
    }
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };

    let (tx, rx) = mpsc::channel();
    if entry.cmd_tx.send(EngineCommand::ReadPresent { reply: tx }).is_err() {
        return 0;
    }

    match rx.recv() {
        Ok(Some(pixels)) => {
            if pixels.len() != out_pixels_len {
                return 0;
            }
            unsafe {
                std::ptr::copy_nonoverlapping(pixels.as_ptr(), out_pixels_ptr, pixels.len());
            }
            1
        }
        _ => 0,
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_read_present(
    _handle: u64,
    _out_pixels_ptr: *mut u8,
    _out_pixels_len: usize,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_write_layer(
    handle: u64,
    layer_index: u32,
    pixels_ptr: *const u32,
    pixels_len: usize,
    record_undo: u8,
) -> u8 {
    if pixels_ptr.is_null() || pixels_len == 0 {
        return 0;
    }
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };
    let pixels = unsafe { std::slice::from_raw_parts(pixels_ptr, pixels_len).to_vec() };

    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::WriteLayer {
            layer_index,
            pixels,
            record_undo: record_undo != 0,
            reply: tx,
        })
        .is_err()
    {
        return 0;
    }

    match rx.recv() {
        Ok(applied) => {
            if applied {
                1
            } else {
                0
            }
        }
        Err(_) => 0,
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_write_layer(
    _handle: u64,
    _layer_index: u32,
    _pixels_ptr: *const u32,
    _pixels_len: usize,
    _record_undo: u8,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_translate_layer(
    handle: u64,
    layer_index: u32,
    delta_x: i32,
    delta_y: i32,
) -> u8 {
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };

    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::TranslateLayer {
            layer_index,
            delta_x,
            delta_y,
            reply: tx,
        })
        .is_err()
    {
        return 0;
    }

    match rx.recv() {
        Ok(applied) => {
            if applied {
                1
            } else {
                0
            }
        }
        Err(_) => 0,
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_translate_layer(
    _handle: u64,
    _layer_index: u32,
    _delta_x: i32,
    _delta_y: i32,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_set_layer_transform_preview(
    handle: u64,
    layer_index: u32,
    matrix_ptr: *const f32,
    matrix_len: usize,
    enabled: u8,
    bilinear: u8,
) -> u8 {
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };
    if matrix_ptr.is_null() || matrix_len < 16 {
        return 0;
    }
    let slice = unsafe { std::slice::from_raw_parts(matrix_ptr, matrix_len) };
    let mut matrix = [0f32; 16];
    matrix.copy_from_slice(&slice[..16]);
    if entry
        .cmd_tx
        .send(EngineCommand::SetLayerTransformPreview {
            layer_index,
            matrix,
            enabled: enabled != 0,
            bilinear: bilinear != 0,
        })
        .is_err()
    {
        return 0;
    }
    1
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_set_layer_transform_preview(
    _handle: u64,
    _layer_index: u32,
    _matrix_ptr: *const f32,
    _matrix_len: usize,
    _enabled: u8,
    _bilinear: u8,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_apply_layer_transform(
    handle: u64,
    layer_index: u32,
    matrix_ptr: *const f32,
    matrix_len: usize,
    bilinear: u8,
) -> u8 {
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };
    if matrix_ptr.is_null() || matrix_len < 16 {
        return 0;
    }
    let slice = unsafe { std::slice::from_raw_parts(matrix_ptr, matrix_len) };
    let mut matrix = [0f32; 16];
    matrix.copy_from_slice(&slice[..16]);
    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::ApplyLayerTransform {
            layer_index,
            matrix,
            bilinear: bilinear != 0,
            reply: tx,
        })
        .is_err()
    {
        return 0;
    }

    match rx.recv() {
        Ok(applied) => {
            if applied {
                1
            } else {
                0
            }
        }
        Err(_) => 0,
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_apply_layer_transform(
    _handle: u64,
    _layer_index: u32,
    _matrix_ptr: *const f32,
    _matrix_len: usize,
    _bilinear: u8,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_get_layer_bounds(
    handle: u64,
    layer_index: u32,
    out_ptr: *mut i32,
    out_len: usize,
) -> u8 {
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };
    if out_ptr.is_null() || out_len < 4 {
        return 0;
    }
    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::GetLayerBounds {
            layer_index,
            reply: tx,
        })
        .is_err()
    {
        return 0;
    }
    let bounds = match rx.recv() {
        Ok(bounds) => bounds,
        Err(_) => None,
    };
    if let Some((left, top, right, bottom)) = bounds {
        let out_slice = unsafe { std::slice::from_raw_parts_mut(out_ptr, out_len) };
        out_slice[0] = left;
        out_slice[1] = top;
        out_slice[2] = right;
        out_slice[3] = bottom;
        1
    } else {
        0
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_get_layer_bounds(
    _handle: u64,
    _layer_index: u32,
    _out_ptr: *mut i32,
    _out_len: usize,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_set_selection_mask(
    handle: u64,
    selection_mask_ptr: *const u8,
    selection_mask_len: usize,
) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let selection_mask: Option<Vec<u8>> = if selection_mask_ptr.is_null() || selection_mask_len == 0
    {
        None
    } else {
        Some(unsafe { std::slice::from_raw_parts(selection_mask_ptr, selection_mask_len).to_vec() })
    };
    let _ = entry
        .cmd_tx
        .send(EngineCommand::SetSelectionMask { selection_mask });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_set_selection_mask(
    _handle: u64,
    _selection_mask_ptr: *const u8,
    _selection_mask_len: usize,
) {
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_reset_canvas(handle: u64, background_color_argb: u32) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::ResetCanvas {
        background_color_argb,
    });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_reset_canvas(_handle: u64, _background_color_argb: u32) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_reset_canvas_with_layers(
    handle: u64,
    layer_count: u32,
    background_color_argb: u32,
) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    debug::log(
        LogLevel::Info,
        format_args!(
            "engine_reset_canvas_with_layers handle={handle} layers={layer_count} bg=0x{background_color_argb:08X}"
        ),
    );
    let _ = entry.cmd_tx.send(EngineCommand::ResetCanvasWithLayers {
        layer_count,
        background_color_argb,
    });
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_reset_canvas_with_layers(
    _handle: u64,
    _layer_count: u32,
    _background_color_argb: u32,
) {
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_resize_canvas(
    handle: u64,
    width: u32,
    height: u32,
    layer_count: u32,
    background_color_argb: u32,
) -> u8 {
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };
    if width == 0 || height == 0 {
        return 0;
    }
    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::ResizeCanvas {
            width,
            height,
            layer_count,
            background_color_argb,
            reply: tx,
        })
        .is_err()
    {
        return 0;
    }
    match rx.recv() {
        Ok(ok) => {
            if ok {
                1
            } else {
                0
            }
        }
        Err(_) => 0,
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_resize_canvas(
    _handle: u64,
    _width: u32,
    _height: u32,
    _layer_count: u32,
    _background_color_argb: u32,
) -> u8 {
    0
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_undo(handle: u64) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::Undo);
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_undo(_handle: u64) {}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios"))]
#[no_mangle]
pub extern "C" fn engine_redo(handle: u64) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::Redo);
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "ios")))]
#[no_mangle]
pub extern "C" fn engine_redo(_handle: u64) {}
