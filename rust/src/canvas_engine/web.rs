use std::ptr;

use wasm_bindgen::prelude::*;

use super::ffi;
use super::types::{EnginePoint, SprayPoint};

fn handle_from_js(handle: f64) -> u64 {
    if handle <= 0.0 {
        0
    } else {
        handle as u64
    }
}

#[wasm_bindgen]
pub fn canvas_engine_create(width: u32, height: u32) -> f64 {
    ffi::engine_create(width, height) as f64
}

#[wasm_bindgen]
pub fn canvas_engine_dispose(handle: f64) {
    ffi::engine_dispose(handle_from_js(handle));
}

#[wasm_bindgen]
pub fn canvas_engine_attach_present(handle: f64, width: u32, height: u32) {
    let handle = handle_from_js(handle);
    if handle == 0 {
        return;
    }
    let bytes_per_row = width.saturating_mul(4);
    ffi::engine_attach_present_texture(handle, ptr::null_mut(), width, height, bytes_per_row);
}

#[wasm_bindgen]
pub fn canvas_engine_reset_canvas_with_layers(
    handle: f64,
    layer_count: u32,
    background_color_argb: u32,
) {
    ffi::engine_reset_canvas_with_layers(handle_from_js(handle), layer_count, background_color_argb);
}

#[wasm_bindgen]
pub fn canvas_engine_resize_canvas(
    handle: f64,
    width: u32,
    height: u32,
    layer_count: u32,
    background_color_argb: u32,
) -> bool {
    ffi::engine_resize_canvas(
        handle_from_js(handle),
        width,
        height,
        layer_count,
        background_color_argb,
    ) != 0
}

#[wasm_bindgen]
pub fn canvas_engine_poll_frame_ready(handle: f64) -> bool {
    ffi::engine_poll_frame_ready(handle_from_js(handle))
}

#[wasm_bindgen]
pub fn canvas_engine_get_input_queue_len(handle: f64) -> u32 {
    ffi::engine_get_input_queue_len(handle_from_js(handle)) as u32
}

#[wasm_bindgen]
pub fn canvas_engine_push_points(handle: f64, points: &[u8], point_count: usize) {
    let handle = handle_from_js(handle);
    if handle == 0 || point_count == 0 {
        return;
    }
    let stride = std::mem::size_of::<EnginePoint>();
    let required = stride.saturating_mul(point_count);
    if points.len() < required {
        return;
    }
    let mut decoded: Vec<EnginePoint> = Vec::with_capacity(point_count);
    let mut offset = 0usize;
    for _ in 0..point_count {
        let ptr = unsafe { points.as_ptr().add(offset) as *const EnginePoint };
        let point = unsafe { ptr::read_unaligned(ptr) };
        decoded.push(point);
        offset += stride;
    }
    ffi::engine_push_points(handle, decoded.as_ptr(), decoded.len());
}

#[wasm_bindgen]
pub fn canvas_engine_set_active_layer(handle: f64, layer_index: u32) {
    ffi::engine_set_active_layer(handle_from_js(handle), layer_index);
}

#[wasm_bindgen]
pub fn canvas_engine_set_layer_opacity(handle: f64, layer_index: u32, opacity: f32) {
    ffi::engine_set_layer_opacity(handle_from_js(handle), layer_index, opacity);
}

#[wasm_bindgen]
pub fn canvas_engine_set_layer_visible(handle: f64, layer_index: u32, visible: u8) {
    ffi::engine_set_layer_visible(handle_from_js(handle), layer_index, visible != 0);
}

#[wasm_bindgen]
pub fn canvas_engine_set_layer_clipping_mask(handle: f64, layer_index: u32, clipping_mask: u8) {
    ffi::engine_set_layer_clipping_mask(handle_from_js(handle), layer_index, clipping_mask != 0);
}

#[wasm_bindgen]
pub fn canvas_engine_set_layer_blend_mode(handle: f64, layer_index: u32, blend_mode: u32) {
    ffi::engine_set_layer_blend_mode(handle_from_js(handle), layer_index, blend_mode);
}

#[wasm_bindgen]
pub fn canvas_engine_reorder_layer(handle: f64, from_index: u32, to_index: u32) {
    ffi::engine_reorder_layer(handle_from_js(handle), from_index, to_index);
}

#[wasm_bindgen]
pub fn canvas_engine_set_view_flags(handle: f64, view_flags: u32) {
    ffi::engine_set_view_flags(handle_from_js(handle), view_flags);
}

#[wasm_bindgen]
pub fn canvas_engine_clear_layer(handle: f64, layer_index: u32) {
    ffi::engine_clear_layer(handle_from_js(handle), layer_index);
}

#[wasm_bindgen]
pub fn canvas_engine_fill_layer(handle: f64, layer_index: u32, color_argb: u32) {
    ffi::engine_fill_layer(handle_from_js(handle), layer_index, color_argb);
}

#[wasm_bindgen]
pub fn canvas_engine_bucket_fill(
    handle: f64,
    layer_index: u32,
    start_x: i32,
    start_y: i32,
    color_argb: u32,
    contiguous: u8,
    sample_all_layers: u8,
    tolerance: u32,
    fill_gap: u32,
    antialias_level: u32,
    swallow_colors: &[u32],
    selection_mask: &[u8],
) -> bool {
    let swallow_ptr = if swallow_colors.is_empty() {
        ptr::null()
    } else {
        swallow_colors.as_ptr()
    };
    let selection_ptr = if selection_mask.is_empty() {
        ptr::null()
    } else {
        selection_mask.as_ptr()
    };
    ffi::engine_bucket_fill(
        handle_from_js(handle),
        layer_index,
        start_x,
        start_y,
        color_argb,
        contiguous,
        sample_all_layers,
        tolerance,
        fill_gap,
        antialias_level,
        swallow_ptr,
        swallow_colors.len(),
        selection_ptr,
        selection_mask.len(),
    )
        != 0
}

#[wasm_bindgen]
pub fn canvas_engine_magic_wand_mask(
    handle: f64,
    layer_index: u32,
    start_x: i32,
    start_y: i32,
    sample_all_layers: u8,
    tolerance: u32,
    selection_mask: &[u8],
    out_mask: &mut [u8],
) -> bool {
    let selection_ptr = if selection_mask.is_empty() {
        ptr::null()
    } else {
        selection_mask.as_ptr()
    };
    if out_mask.is_empty() {
        return false;
    }
    ffi::engine_magic_wand_mask(
        handle_from_js(handle),
        layer_index,
        start_x,
        start_y,
        sample_all_layers,
        tolerance,
        selection_ptr,
        selection_mask.len(),
        out_mask.as_mut_ptr(),
        out_mask.len(),
    )
        != 0
}

#[wasm_bindgen]
pub fn canvas_engine_read_layer(
    handle: f64,
    layer_index: u32,
    out_pixels: &mut [u32],
) -> bool {
    if out_pixels.is_empty() {
        return false;
    }
    ffi::engine_read_layer(
        handle_from_js(handle),
        layer_index,
        out_pixels.as_mut_ptr(),
        out_pixels.len(),
    )
        != 0
}

#[wasm_bindgen]
pub fn canvas_engine_read_layer_preview(
    handle: f64,
    layer_index: u32,
    width: u32,
    height: u32,
    out_pixels: &mut [u8],
) -> bool {
    if out_pixels.is_empty() {
        return false;
    }
    ffi::engine_read_layer_preview(
        handle_from_js(handle),
        layer_index,
        width,
        height,
        out_pixels.as_mut_ptr(),
        out_pixels.len(),
    )
        != 0
}

#[wasm_bindgen]
pub fn canvas_engine_read_present(handle: f64, out_pixels: &mut [u8]) -> bool {
    if out_pixels.is_empty() {
        return false;
    }
    ffi::engine_read_present(handle_from_js(handle), out_pixels.as_mut_ptr(), out_pixels.len()) != 0
}

#[wasm_bindgen]
pub fn canvas_engine_write_layer(
    handle: f64,
    layer_index: u32,
    pixels: &[u32],
    record_undo: u8,
) -> bool {
    if pixels.is_empty() {
        return false;
    }
    ffi::engine_write_layer(
        handle_from_js(handle),
        layer_index,
        pixels.as_ptr(),
        pixels.len(),
        record_undo,
    )
        != 0
}

#[wasm_bindgen]
pub fn canvas_engine_translate_layer(
    handle: f64,
    layer_index: u32,
    delta_x: i32,
    delta_y: i32,
) -> bool {
    ffi::engine_translate_layer(handle_from_js(handle), layer_index, delta_x, delta_y) != 0
}

#[wasm_bindgen]
pub fn canvas_engine_set_layer_transform_preview(
    handle: f64,
    layer_index: u32,
    matrix: &[f32],
    enabled: u8,
    bilinear: u8,
) -> bool {
    ffi::engine_set_layer_transform_preview(
        handle_from_js(handle),
        layer_index,
        matrix.as_ptr(),
        matrix.len(),
        enabled,
        bilinear,
    )
        != 0
}

#[wasm_bindgen]
pub fn canvas_engine_apply_layer_transform(
    handle: f64,
    layer_index: u32,
    matrix: &[f32],
    bilinear: u8,
) -> bool {
    ffi::engine_apply_layer_transform(
        handle_from_js(handle),
        layer_index,
        matrix.as_ptr(),
        matrix.len(),
        bilinear,
    )
        != 0
}

#[wasm_bindgen]
pub fn canvas_engine_get_layer_bounds(
    handle: f64,
    layer_index: u32,
    out_bounds: &mut [i32],
) -> bool {
    if out_bounds.len() < 4 {
        return false;
    }
    ffi::engine_get_layer_bounds(
        handle_from_js(handle),
        layer_index,
        out_bounds.as_mut_ptr(),
        out_bounds.len(),
    )
        != 0
}

#[wasm_bindgen]
pub fn canvas_engine_set_selection_mask(handle: f64, selection_mask: &[u8]) {
    let selection_ptr = if selection_mask.is_empty() {
        ptr::null()
    } else {
        selection_mask.as_ptr()
    };
    ffi::engine_set_selection_mask(
        handle_from_js(handle),
        selection_ptr,
        selection_mask.len(),
    );
}

#[wasm_bindgen]
pub fn canvas_engine_reset_canvas(handle: f64, background_color_argb: u32) {
    ffi::engine_reset_canvas(handle_from_js(handle), background_color_argb);
}

#[wasm_bindgen]
pub fn canvas_engine_undo(handle: f64) {
    ffi::engine_undo(handle_from_js(handle));
}

#[wasm_bindgen]
pub fn canvas_engine_redo(handle: f64) {
    ffi::engine_redo(handle_from_js(handle));
}

#[wasm_bindgen]
pub fn canvas_engine_set_brush(
    handle: f64,
    color_argb: u32,
    base_radius: f32,
    use_pressure: u8,
    erase: u8,
    antialias_level: u32,
    brush_shape: u32,
    random_rotation: u8,
    rotation_seed: u32,
    spacing: f32,
    hardness: f32,
    flow: f32,
    scatter: f32,
    rotation_jitter: f32,
    snap_to_pixel: u8,
    hollow: u8,
    hollow_ratio: f32,
    hollow_erase_occluded: u8,
    streamline_strength: f32,
) {
    ffi::engine_set_brush(
        handle_from_js(handle),
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
        hollow,
        hollow_ratio,
        hollow_erase_occluded,
        streamline_strength,
    );
}

#[wasm_bindgen]
pub fn canvas_engine_spray_begin(handle: f64) {
    ffi::engine_spray_begin(handle_from_js(handle));
}

#[wasm_bindgen]
pub fn canvas_engine_spray_draw(
    handle: f64,
    points: &[f32],
    point_count: usize,
    color_argb: u32,
    brush_shape: u32,
    erase: u8,
    antialias_level: u32,
    softness: f32,
    accumulate: u8,
) {
    let handle = handle_from_js(handle);
    if handle == 0 || point_count == 0 {
        return;
    }
    let required = point_count.saturating_mul(4);
    if points.len() < required {
        return;
    }
    let mut decoded: Vec<SprayPoint> = Vec::with_capacity(point_count);
    for i in 0..point_count {
        let base = i.saturating_mul(4);
        decoded.push(SprayPoint {
            x: points[base],
            y: points[base + 1],
            radius: points[base + 2],
            alpha: points[base + 3],
        });
    }
    ffi::engine_spray_draw(
        handle,
        decoded.as_ptr(),
        decoded.len(),
        color_argb,
        brush_shape,
        erase,
        antialias_level,
        softness,
        accumulate,
    );
}

#[wasm_bindgen]
pub fn canvas_engine_spray_end(handle: f64) {
    ffi::engine_spray_end(handle_from_js(handle));
}

#[wasm_bindgen]
pub fn canvas_engine_apply_filter(
    handle: f64,
    layer_index: u32,
    filter_type: u32,
    param0: f32,
    param1: f32,
    param2: f32,
    param3: f32,
) -> bool {
    ffi::engine_apply_filter(
        handle_from_js(handle),
        layer_index,
        filter_type,
        param0,
        param1,
        param2,
        param3,
    )
        != 0
}

#[wasm_bindgen]
pub fn canvas_engine_apply_antialias(handle: f64, layer_index: u32, level: u32) -> bool {
    ffi::engine_apply_antialias(handle_from_js(handle), layer_index, level) != 0
}
