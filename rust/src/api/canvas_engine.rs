use std::sync::atomic::Ordering;
use std::sync::mpsc;

use crate::canvas_engine::engine::{
    create_engine, init_device_context_wasm, lookup_engine, pump_engine, remove_engine,
    EngineCommand, EngineInputBatch,
};
use crate::canvas_engine::types::{EnginePoint, SprayPoint};
use crate::gpu::debug::{self, LogLevel};
use crate::wasm_log::wasm_post_log;

const POINT_STRIDE_BYTES: usize = 32;
const SPRAY_POINT_STRIDE_FLOATS: usize = 4;

fn handle_to_u64(handle: i64) -> Option<u64> {
    if handle <= 0 {
        None
    } else {
        Some(handle as u64)
    }
}

fn pump_engine_if_needed(handle: u64) {
    #[cfg(target_family = "wasm")]
    {
        pump_engine(handle);
    }
}

fn parse_engine_points(bytes: &[u8], point_count: usize) -> Result<Vec<EnginePoint>, String> {
    let required_bytes = point_count
        .checked_mul(POINT_STRIDE_BYTES)
        .ok_or_else(|| "point buffer size overflow".to_string())?;
    if bytes.len() < required_bytes {
        return Err(format!(
            "point buffer too short: {} < {}",
            bytes.len(),
            required_bytes
        ));
    }
    let mut points = Vec::with_capacity(point_count);
    for idx in 0..point_count {
        let base = idx * POINT_STRIDE_BYTES;
        let x = f32::from_le_bytes(bytes[base..base + 4].try_into().unwrap());
        let y = f32::from_le_bytes(bytes[base + 4..base + 8].try_into().unwrap());
        let pressure = f32::from_le_bytes(bytes[base + 8..base + 12].try_into().unwrap());
        let pad = f32::from_le_bytes(bytes[base + 12..base + 16].try_into().unwrap());
        let timestamp_us =
            u64::from_le_bytes(bytes[base + 16..base + 24].try_into().unwrap());
        let flags = u32::from_le_bytes(bytes[base + 24..base + 28].try_into().unwrap());
        let pointer_id =
            u32::from_le_bytes(bytes[base + 28..base + 32].try_into().unwrap());
        points.push(EnginePoint {
            x,
            y,
            pressure,
            _pad0: pad,
            timestamp_us,
            flags,
            pointer_id,
        });
    }
    Ok(points)
}

fn parse_spray_points(points: &[f32], point_count: usize) -> Result<Vec<SprayPoint>, String> {
    let required_floats = point_count
        .checked_mul(SPRAY_POINT_STRIDE_FLOATS)
        .ok_or_else(|| "spray point buffer size overflow".to_string())?;
    if points.len() < required_floats {
        return Err(format!(
            "spray point buffer too short: {} < {}",
            points.len(),
            required_floats
        ));
    }
    let mut out = Vec::with_capacity(point_count);
    for idx in 0..point_count {
        let base = idx * SPRAY_POINT_STRIDE_FLOATS;
        out.push(SprayPoint {
            x: points[base],
            y: points[base + 1],
            radius: points[base + 2],
            alpha: points[base + 3],
        });
    }
    Ok(out)
}

#[flutter_rust_bridge::frb]
pub async fn canvas_engine_init() -> bool {
    wasm_post_log("canvas_engine_init: enter");
    let result = init_device_context_wasm().await;
    wasm_post_log("canvas_engine_init: after init_device_context_wasm");
    match result {
        Ok(()) => true,
        Err(err) => {
            wasm_post_log(&format!("canvas_engine_init: error {err}"));
            debug::log(LogLevel::Warn, format_args!("engine_init failed: {err}"));
            false
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_create(width: u32, height: u32) -> i64 {
    #[cfg(target_family = "wasm")]
    wasm_post_log(&format!(
        "canvas_engine_create: enter {width}x{height}"
    ));
    match create_engine(width, height) {
        Ok(handle) => {
            #[cfg(target_family = "wasm")]
            wasm_post_log(&format!("canvas_engine_create: ok handle={handle}"));
            handle as i64
        }
        Err(err) => {
            #[cfg(target_family = "wasm")]
            wasm_post_log(&format!("canvas_engine_create: error {err}"));
            debug::log(LogLevel::Warn, format_args!("engine_create failed: {err}"));
            0
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_dispose(handle: i64) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    if let Some(entry) = remove_engine(handle) {
        let _ = entry.cmd_tx.send(EngineCommand::Stop);
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_attach_present(handle: i64, width: u32, height: u32) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    if width == 0 || height == 0 {
        return;
    }
    #[cfg(target_family = "wasm")]
    wasm_post_log(&format!(
        "canvas_engine_attach_present: handle={handle} size={width}x{height}"
    ));
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let bytes_per_row = width.saturating_mul(4);
    let _ = entry.cmd_tx.send(EngineCommand::AttachPresentTexture {
        mtl_texture_ptr: 0,
        width,
        height,
        bytes_per_row,
    });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_poll_frame_ready(handle: i64) -> bool {
    let Some(handle) = handle_to_u64(handle) else {
        return false;
    };
    pump_engine_if_needed(handle);
    lookup_engine(handle)
        .map(|entry| entry.frame_ready.swap(false, Ordering::AcqRel))
        .unwrap_or(false)
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_read_present(handle: i64) -> Option<Vec<u8>> {
    let Some(handle) = handle_to_u64(handle) else {
        return None;
    };
    let Some(entry) = lookup_engine(handle) else {
        return None;
    };
    let (tx, rx) = mpsc::channel();
    if entry.cmd_tx.send(EngineCommand::ReadPresent { reply: tx }).is_err() {
        return None;
    }
    pump_engine_if_needed(handle);
    #[cfg(target_family = "wasm")]
    {
        match rx.try_recv() {
            Ok(Some(pixels)) => Some(pixels),
            Ok(None) => None,
            Err(mpsc::TryRecvError::Empty) => None,
            Err(mpsc::TryRecvError::Disconnected) => None,
        }
    }
    #[cfg(not(target_family = "wasm"))]
    {
        match rx.recv() {
            Ok(Some(pixels)) => Some(pixels),
            _ => None,
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_push_points_packed(handle: i64, bytes: Vec<u8>, point_count: usize) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    if point_count == 0 {
        return;
    }
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let points = match parse_engine_points(&bytes, point_count) {
        Ok(points) => points,
        Err(err) => {
            debug::log(LogLevel::Warn, format_args!("push_points decode failed: {err}"));
            return;
        }
    };
    let queue_len = entry
        .input_queue_len
        .fetch_add(point_count as u64, Ordering::Relaxed)
        + point_count as u64;

    if debug::level() >= LogLevel::Verbose {
        const FLAG_DOWN: u32 = 1;
        const FLAG_UP: u32 = 4;
        let mut down_count: usize = 0;
        let mut up_count: usize = 0;
        for p in &points {
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
                "engine_push_points handle={handle} len={point_count} down={down_count} up={up_count} queue_len={queue_len}"
            ),
        );
    }

    if entry
        .input_tx
        .send(EngineInputBatch { points })
        .is_err()
    {
        entry
            .input_queue_len
            .fetch_sub(point_count as u64, Ordering::Relaxed);
        debug::log(
            LogLevel::Warn,
            format_args!("engine_push_points dropped: input thread disconnected"),
        );
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_get_input_queue_len(handle: i64) -> i64 {
    let Some(handle) = handle_to_u64(handle) else {
        return 0;
    };
    lookup_engine(handle)
        .map(|entry| entry.input_queue_len.load(Ordering::Relaxed))
        .unwrap_or(0) as i64
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_set_active_layer(handle: i64, layer_index: u32) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry
        .cmd_tx
        .send(EngineCommand::SetActiveLayer { layer_index });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_set_layer_opacity(handle: i64, layer_index: u32, opacity: f32) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::SetLayerOpacity {
        layer_index,
        opacity,
    });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_set_layer_visible(handle: i64, layer_index: u32, visible: bool) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::SetLayerVisible {
        layer_index,
        visible,
    });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_set_layer_clipping_mask(
    handle: i64,
    layer_index: u32,
    clipping_mask: bool,
) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry
        .cmd_tx
        .send(EngineCommand::SetLayerClippingMask {
            layer_index,
            clipping_mask,
        });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_set_layer_blend_mode(handle: i64, layer_index: u32, blend_mode_index: u32) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::SetLayerBlendMode {
        layer_index,
        blend_mode_index,
    });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_reorder_layer(handle: i64, from_index: u32, to_index: u32) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::ReorderLayer {
        from_index,
        to_index,
    });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_set_view_flags(handle: i64, view_flags: u32) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry
        .cmd_tx
        .send(EngineCommand::SetViewFlags { view_flags });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_clear_layer(handle: i64, layer_index: u32) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry
        .cmd_tx
        .send(EngineCommand::ClearLayer { layer_index });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_fill_layer(handle: i64, layer_index: u32, color_argb: u32) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry
        .cmd_tx
        .send(EngineCommand::FillLayer { layer_index, color_argb });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_bucket_fill(
    handle: i64,
    layer_index: u32,
    start_x: i32,
    start_y: i32,
    color_argb: u32,
    contiguous: bool,
    sample_all_layers: bool,
    tolerance: u32,
    fill_gap: u32,
    antialias_level: u32,
    swallow_colors: Vec<u32>,
    selection_mask: Option<Vec<u8>>,
) -> bool {
    let Some(handle) = handle_to_u64(handle) else {
        return false;
    };
    let Some(entry) = lookup_engine(handle) else {
        return false;
    };

    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::BucketFill {
            layer_index,
            start_x,
            start_y,
            color_argb,
            contiguous,
            sample_all_layers,
            tolerance: tolerance.min(255) as u8,
            fill_gap: fill_gap.min(64) as u8,
            antialias_level: antialias_level.min(9) as u8,
            swallow_colors,
            selection_mask,
            reply: tx,
        })
        .is_err()
    {
        return false;
    }
    pump_engine_if_needed(handle);
    match rx.recv() {
        Ok(changed) => changed,
        Err(_) => false,
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_magic_wand_mask(
    handle: i64,
    layer_index: u32,
    start_x: i32,
    start_y: i32,
    sample_all_layers: bool,
    tolerance: u32,
    selection_mask: Option<Vec<u8>>,
) -> Option<Vec<u8>> {
    #[cfg(target_family = "wasm")]
    {
        wasm_post_log("canvas_engine_magic_wand_mask: unsupported on web (readback)");
        let _ = (handle, layer_index, start_x, start_y, sample_all_layers, tolerance, selection_mask);
        return None;
    }
    let Some(handle) = handle_to_u64(handle) else {
        return None;
    };
    let Some(entry) = lookup_engine(handle) else {
        return None;
    };

    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::MagicWandMask {
            layer_index,
            start_x,
            start_y,
            sample_all_layers,
            tolerance: tolerance.min(255) as u8,
            selection_mask,
            reply: tx,
        })
        .is_err()
    {
        return None;
    }
    pump_engine_if_needed(handle);
    match rx.recv() {
        Ok(mask) => mask,
        Err(_) => None,
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_read_layer(handle: i64, layer_index: u32) -> Option<Vec<u32>> {
    #[cfg(target_family = "wasm")]
    {
        wasm_post_log("canvas_engine_read_layer: unsupported on web (readback)");
        let _ = (handle, layer_index);
        return None;
    }
    let Some(handle) = handle_to_u64(handle) else {
        return None;
    };
    let Some(entry) = lookup_engine(handle) else {
        return None;
    };
    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::ReadLayer { layer_index, reply: tx })
        .is_err()
    {
        return None;
    }
    pump_engine_if_needed(handle);
    match rx.recv() {
        Ok(pixels) => pixels,
        Err(_) => None,
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_read_layer_preview(
    handle: i64,
    layer_index: u32,
    width: u32,
    height: u32,
) -> Option<Vec<u8>> {
    #[cfg(target_family = "wasm")]
    {
        wasm_post_log("canvas_engine_read_layer_preview: unsupported on web (readback)");
        let _ = (handle, layer_index, width, height);
        return None;
    }
    let Some(handle) = handle_to_u64(handle) else {
        return None;
    };
    let Some(entry) = lookup_engine(handle) else {
        return None;
    };
    if width == 0 || height == 0 {
        return None;
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
        return None;
    }
    pump_engine_if_needed(handle);
    match rx.recv() {
        Ok(pixels) => pixels,
        Err(_) => None,
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_write_layer(
    handle: i64,
    layer_index: u32,
    pixels: Vec<u32>,
    record_undo: bool,
) -> bool {
    let Some(handle) = handle_to_u64(handle) else {
        return false;
    };
    let Some(entry) = lookup_engine(handle) else {
        return false;
    };
    if pixels.is_empty() {
        return false;
    }
    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::WriteLayer {
            layer_index,
            pixels,
            record_undo,
            reply: tx,
        })
        .is_err()
    {
        return false;
    }
    pump_engine_if_needed(handle);
    match rx.recv() {
        Ok(ok) => ok,
        Err(_) => false,
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_translate_layer(
    handle: i64,
    layer_index: u32,
    delta_x: i32,
    delta_y: i32,
) -> bool {
    let Some(handle) = handle_to_u64(handle) else {
        return false;
    };
    let Some(entry) = lookup_engine(handle) else {
        return false;
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
        return false;
    }
    pump_engine_if_needed(handle);
    match rx.recv() {
        Ok(ok) => ok,
        Err(_) => false,
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_set_layer_transform_preview(
    handle: i64,
    layer_index: u32,
    matrix: Vec<f32>,
    enabled: bool,
    bilinear: bool,
) -> bool {
    let Some(handle) = handle_to_u64(handle) else {
        return false;
    };
    let Some(entry) = lookup_engine(handle) else {
        return false;
    };
    if matrix.len() < 16 {
        return false;
    }
    let mut mat = [0.0f32; 16];
    mat.copy_from_slice(&matrix[0..16]);
    if entry
        .cmd_tx
        .send(EngineCommand::SetLayerTransformPreview {
            layer_index,
            matrix: mat,
            enabled,
            bilinear,
        })
        .is_err()
    {
        return false;
    }
    true
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_apply_layer_transform(
    handle: i64,
    layer_index: u32,
    matrix: Vec<f32>,
    bilinear: bool,
) -> bool {
    let Some(handle) = handle_to_u64(handle) else {
        return false;
    };
    let Some(entry) = lookup_engine(handle) else {
        return false;
    };
    if matrix.len() < 16 {
        return false;
    }
    let mut mat = [0.0f32; 16];
    mat.copy_from_slice(&matrix[0..16]);
    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::ApplyLayerTransform {
            layer_index,
            matrix: mat,
            bilinear,
            reply: tx,
        })
        .is_err()
    {
        return false;
    }
    pump_engine_if_needed(handle);
    match rx.recv() {
        Ok(ok) => ok,
        Err(_) => false,
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_get_layer_bounds(handle: i64, layer_index: u32) -> Option<Vec<i32>> {
    #[cfg(target_family = "wasm")]
    {
        wasm_post_log("canvas_engine_get_layer_bounds: unsupported on web (readback)");
        let _ = (handle, layer_index);
        return None;
    }
    let Some(handle) = handle_to_u64(handle) else {
        return None;
    };
    let Some(entry) = lookup_engine(handle) else {
        return None;
    };
    let (tx, rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::GetLayerBounds { layer_index, reply: tx })
        .is_err()
    {
        return None;
    }
    pump_engine_if_needed(handle);
    match rx.recv() {
        Ok(Some((left, top, right, bottom))) => Some(vec![left, top, right, bottom]),
        _ => None,
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_set_selection_mask(handle: i64, selection_mask: Option<Vec<u8>>) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry
        .cmd_tx
        .send(EngineCommand::SetSelectionMask { selection_mask });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_reset_canvas(handle: i64, background_color_argb: u32) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::ResetCanvas {
        background_color_argb,
    });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_reset_canvas_with_layers(
    handle: i64,
    layer_count: u32,
    background_color_argb: u32,
) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    #[cfg(target_family = "wasm")]
    wasm_post_log(&format!(
        "canvas_engine_reset_canvas_with_layers: handle={handle} layers={layer_count} bg=0x{background_color_argb:08x}"
    ));
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::ResetCanvasWithLayers {
        layer_count,
        background_color_argb,
    });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_resize_canvas(
    handle: i64,
    width: u32,
    height: u32,
    layer_count: u32,
    background_color_argb: u32,
) -> bool {
    let Some(handle) = handle_to_u64(handle) else {
        return false;
    };
    if width == 0 || height == 0 {
        return false;
    }
    #[cfg(target_family = "wasm")]
    wasm_post_log(&format!(
        "canvas_engine_resize_canvas: handle={handle} size={width}x{height} layers={layer_count} bg=0x{background_color_argb:08x}"
    ));
    let Some(entry) = lookup_engine(handle) else {
        return false;
    };
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
        return false;
    }
    pump_engine_if_needed(handle);
    match rx.recv() {
        Ok(ok) => ok,
        Err(_) => false,
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_undo(handle: i64) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::Undo);
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_redo(handle: i64) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::Redo);
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_set_brush(
    handle: i64,
    color_argb: u32,
    base_radius: f32,
    use_pressure: bool,
    erase: bool,
    antialias_level: u32,
    brush_shape: u32,
    random_rotation: bool,
    rotation_seed: u32,
    spacing: f32,
    hardness: f32,
    flow: f32,
    scatter: f32,
    rotation_jitter: f32,
    snap_to_pixel: bool,
    hollow_enabled: bool,
    hollow_ratio: f32,
    hollow_erase_occluded: bool,
    streamline_strength: f32,
) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::SetBrush {
        color_argb,
        base_radius,
        use_pressure,
        erase,
        antialias_level,
        brush_shape,
        random_rotation,
        rotation_seed,
        spacing,
        hardness,
        flow,
        scatter,
        rotation_jitter,
        snap_to_pixel,
        hollow_enabled,
        hollow_ratio,
        hollow_erase_occluded,
        streamline_strength,
    });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_spray_begin(handle: i64) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::BeginSpray);
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_spray_draw(
    handle: i64,
    points: Vec<f32>,
    point_count: usize,
    color_argb: u32,
    brush_shape: u32,
    erase: bool,
    antialias_level: u32,
    softness: f32,
    accumulate: bool,
) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    if point_count == 0 {
        return;
    }
    let spray_points = match parse_spray_points(&points, point_count) {
        Ok(points) => points,
        Err(err) => {
            debug::log(LogLevel::Warn, format_args!("spray draw decode failed: {err}"));
            return;
        }
    };
    let _ = entry.cmd_tx.send(EngineCommand::DrawSpray {
        points: spray_points,
        color_argb,
        brush_shape,
        erase,
        antialias_level,
        softness,
        accumulate,
    });
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_spray_end(handle: i64) {
    let Some(handle) = handle_to_u64(handle) else {
        return;
    };
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::EndSpray);
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_apply_filter(
    handle: i64,
    layer_index: u32,
    filter_type: u32,
    param0: f32,
    param1: f32,
    param2: f32,
    param3: f32,
) -> bool {
    let Some(handle) = handle_to_u64(handle) else {
        return false;
    };
    let Some(entry) = lookup_engine(handle) else {
        return false;
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
        return false;
    }
    pump_engine_if_needed(handle);
    match rx.recv() {
        Ok(ok) => ok,
        Err(_) => false,
    }
}

#[flutter_rust_bridge::frb]
pub fn canvas_engine_apply_antialias(handle: i64, layer_index: u32, level: u32) -> bool {
    let Some(handle) = handle_to_u64(handle) else {
        return false;
    };
    let Some(entry) = lookup_engine(handle) else {
        return false;
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
        return false;
    }
    pump_engine_if_needed(handle);
    match rx.recv() {
        Ok(ok) => ok,
        Err(_) => false,
    }
}
