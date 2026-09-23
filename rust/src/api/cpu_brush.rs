use crate::cpu_brush::{
    cpu_brush_apply_streamline, cpu_brush_draw_capsule_segment, cpu_brush_draw_spray,
    cpu_brush_draw_stamp, cpu_brush_draw_stamp_segment, cpu_brush_fill_polygon,
};

#[flutter_rust_bridge::frb]
pub struct CpuBrushResult {
    pub ok: bool,
    pub pixels: Vec<u32>,
}

#[flutter_rust_bridge::frb]
pub struct CpuStreamlineResult {
    pub ok: bool,
    pub samples: Vec<f32>,
}

#[flutter_rust_bridge::frb]
pub struct CpuBrushCommand {
    pub kind: u32,
    pub ax: f32,
    pub ay: f32,
    pub bx: f32,
    pub by: f32,
    pub start_radius: f32,
    pub end_radius: f32,
    pub center_x: f32,
    pub center_y: f32,
    pub radius: f32,
    pub color_argb: u32,
    pub brush_shape: u32,
    pub antialias_level: u32,
    pub softness: f32,
    pub erase: bool,
    pub include_start_cap: bool,
    pub include_start: bool,
    pub random_rotation: bool,
    pub smooth_rotation: bool,
    pub rotation_seed: u32,
    pub rotation_jitter: f32,
    pub spacing: f32,
    pub scatter: f32,
    pub screentone_enabled: bool,
    pub screentone_spacing: f32,
    pub screentone_dot_size: f32,
    pub screentone_rotation: f32,
    pub screentone_softness: f32,
    pub screentone_shape: u32,
    pub snap_to_pixel: bool,
}

fn bool_to_u8(v: bool) -> u8 {
    if v {
        1
    } else {
        0
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cpu_brush_draw_stamp_rgba(
    pixels: Vec<u32>,
    width: u32,
    height: u32,
    center_x: f32,
    center_y: f32,
    radius: f32,
    color_argb: u32,
    brush_shape: u32,
    antialias_level: u32,
    softness: f32,
    erase: bool,
    random_rotation: bool,
    smooth_rotation: bool,
    rotation_seed: u32,
    rotation_jitter: f32,
    screentone_enabled: bool,
    screentone_spacing: f32,
    screentone_dot_size: f32,
    screentone_rotation: f32,
    screentone_softness: f32,
    screentone_shape: u32,
    snap_to_pixel: bool,
    custom_mask_width: u32,
    custom_mask_height: u32,
    custom_mask: Option<Vec<u8>>,
    selection: Option<Vec<u8>>,
) -> CpuBrushResult {
    let mut pixels = pixels;
    let (selection_ptr, selection_len) = match selection.as_ref() {
        Some(mask) => (mask.as_ptr(), mask.len()),
        None => (std::ptr::null(), 0),
    };
    let (custom_mask_ptr, custom_mask_len) = match custom_mask.as_ref() {
        Some(mask) => (mask.as_ptr(), mask.len()),
        None => (std::ptr::null(), 0),
    };
    let ok = cpu_brush_draw_stamp(
        pixels.as_mut_ptr(),
        pixels.len(),
        width,
        height,
        center_x,
        center_y,
        radius,
        color_argb,
        brush_shape,
        antialias_level,
        softness,
        bool_to_u8(erase),
        bool_to_u8(random_rotation),
        bool_to_u8(smooth_rotation),
        rotation_seed,
        rotation_jitter,
        bool_to_u8(screentone_enabled),
        screentone_spacing,
        screentone_dot_size,
        screentone_rotation,
        screentone_softness,
        screentone_shape,
        bool_to_u8(snap_to_pixel),
        custom_mask_width,
        custom_mask_height,
        custom_mask_ptr,
        custom_mask_len,
        selection_ptr,
        selection_len,
    );
    CpuBrushResult {
        ok: ok != 0,
        pixels,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cpu_brush_draw_capsule_segment_rgba(
    pixels: Vec<u32>,
    width: u32,
    height: u32,
    ax: f32,
    ay: f32,
    bx: f32,
    by: f32,
    start_radius: f32,
    end_radius: f32,
    color_argb: u32,
    antialias_level: u32,
    include_start_cap: bool,
    erase: bool,
    screentone_enabled: bool,
    screentone_spacing: f32,
    screentone_dot_size: f32,
    screentone_rotation: f32,
    screentone_softness: f32,
    screentone_shape: u32,
    selection: Option<Vec<u8>>,
) -> CpuBrushResult {
    let mut pixels = pixels;
    let (selection_ptr, selection_len) = match selection.as_ref() {
        Some(mask) => (mask.as_ptr(), mask.len()),
        None => (std::ptr::null(), 0),
    };
    let ok = cpu_brush_draw_capsule_segment(
        pixels.as_mut_ptr(),
        pixels.len(),
        width,
        height,
        ax,
        ay,
        bx,
        by,
        start_radius,
        end_radius,
        color_argb,
        antialias_level,
        bool_to_u8(include_start_cap),
        bool_to_u8(erase),
        bool_to_u8(screentone_enabled),
        screentone_spacing,
        screentone_dot_size,
        screentone_rotation,
        screentone_softness,
        screentone_shape,
        selection_ptr,
        selection_len,
    );
    CpuBrushResult {
        ok: ok != 0,
        pixels,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cpu_brush_fill_polygon_rgba(
    pixels: Vec<u32>,
    width: u32,
    height: u32,
    vertices: Vec<f32>,
    radius: f32,
    color_argb: u32,
    antialias_level: u32,
    softness: f32,
    erase: bool,
    selection: Option<Vec<u8>>,
) -> CpuBrushResult {
    let mut pixels = pixels;
    let (selection_ptr, selection_len) = match selection.as_ref() {
        Some(mask) => (mask.as_ptr(), mask.len()),
        None => (std::ptr::null(), 0),
    };
    let ok = cpu_brush_fill_polygon(
        pixels.as_mut_ptr(),
        pixels.len(),
        width,
        height,
        vertices.as_ptr(),
        vertices.len(),
        radius,
        color_argb,
        antialias_level,
        softness,
        bool_to_u8(erase),
        selection_ptr,
        selection_len,
    );
    CpuBrushResult {
        ok: ok != 0,
        pixels,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cpu_brush_draw_stamp_segment_rgba(
    pixels: Vec<u32>,
    width: u32,
    height: u32,
    start_x: f32,
    start_y: f32,
    end_x: f32,
    end_y: f32,
    start_radius: f32,
    end_radius: f32,
    color_argb: u32,
    brush_shape: u32,
    antialias_level: u32,
    include_start: bool,
    erase: bool,
    random_rotation: bool,
    smooth_rotation: bool,
    rotation_seed: u32,
    rotation_jitter: f32,
    screentone_enabled: bool,
    screentone_spacing: f32,
    screentone_dot_size: f32,
    screentone_rotation: f32,
    screentone_softness: f32,
    screentone_shape: u32,
    spacing: f32,
    scatter: f32,
    softness: f32,
    snap_to_pixel: bool,
    accumulate: bool,
    custom_mask_width: u32,
    custom_mask_height: u32,
    custom_mask: Option<Vec<u8>>,
    selection: Option<Vec<u8>>,
) -> CpuBrushResult {
    let mut pixels = pixels;
    let (selection_ptr, selection_len) = match selection.as_ref() {
        Some(mask) => (mask.as_ptr(), mask.len()),
        None => (std::ptr::null(), 0),
    };
    let (custom_mask_ptr, custom_mask_len) = match custom_mask.as_ref() {
        Some(mask) => (mask.as_ptr(), mask.len()),
        None => (std::ptr::null(), 0),
    };
    let ok = cpu_brush_draw_stamp_segment(
        pixels.as_mut_ptr(),
        pixels.len(),
        width,
        height,
        start_x,
        start_y,
        end_x,
        end_y,
        start_radius,
        end_radius,
        color_argb,
        brush_shape,
        antialias_level,
        bool_to_u8(include_start),
        bool_to_u8(erase),
        bool_to_u8(random_rotation),
        bool_to_u8(smooth_rotation),
        rotation_seed,
        rotation_jitter,
        bool_to_u8(screentone_enabled),
        screentone_spacing,
        screentone_dot_size,
        screentone_rotation,
        screentone_softness,
        screentone_shape,
        spacing,
        scatter,
        softness,
        bool_to_u8(snap_to_pixel),
        bool_to_u8(accumulate),
        custom_mask_width,
        custom_mask_height,
        custom_mask_ptr,
        custom_mask_len,
        selection_ptr,
        selection_len,
    );
    CpuBrushResult {
        ok: ok != 0,
        pixels,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cpu_brush_draw_spray_rgba(
    pixels: Vec<u32>,
    width: u32,
    height: u32,
    points: Vec<f32>,
    color_argb: u32,
    brush_shape: u32,
    antialias_level: u32,
    softness: f32,
    erase: bool,
    accumulate: bool,
    selection: Option<Vec<u8>>,
) -> CpuBrushResult {
    let mut pixels = pixels;
    let (selection_ptr, selection_len) = match selection.as_ref() {
        Some(mask) => (mask.as_ptr(), mask.len()),
        None => (std::ptr::null(), 0),
    };
    let ok = cpu_brush_draw_spray(
        pixels.as_mut_ptr(),
        pixels.len(),
        width,
        height,
        points.as_ptr(),
        points.len(),
        color_argb,
        brush_shape,
        antialias_level,
        softness,
        bool_to_u8(erase),
        bool_to_u8(accumulate),
        selection_ptr,
        selection_len,
    );
    CpuBrushResult {
        ok: ok != 0,
        pixels,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cpu_brush_apply_commands_rgba(
    pixels: Vec<u32>,
    width: u32,
    height: u32,
    commands: Vec<CpuBrushCommand>,
    selection: Option<Vec<u8>>,
) -> CpuBrushResult {
    let mut pixels = pixels;
    let (selection_ptr, selection_len) = match selection.as_ref() {
        Some(mask) => (mask.as_ptr(), mask.len()),
        None => (std::ptr::null(), 0),
    };
    let mut ok = true;
    for cmd in commands {
        let result = match cmd.kind {
            0 => cpu_brush_draw_stamp(
                pixels.as_mut_ptr(),
                pixels.len(),
                width,
                height,
                cmd.center_x,
                cmd.center_y,
                cmd.radius,
                cmd.color_argb,
                cmd.brush_shape,
                cmd.antialias_level,
                cmd.softness,
                bool_to_u8(cmd.erase),
                bool_to_u8(cmd.random_rotation),
                bool_to_u8(cmd.smooth_rotation),
                cmd.rotation_seed,
                cmd.rotation_jitter,
                bool_to_u8(cmd.screentone_enabled),
                cmd.screentone_spacing,
                cmd.screentone_dot_size,
                cmd.screentone_rotation,
                cmd.screentone_softness,
                cmd.screentone_shape,
                bool_to_u8(cmd.snap_to_pixel),
                0,
                0,
                std::ptr::null(),
                0,
                selection_ptr,
                selection_len,
            ),
            1 => cpu_brush_draw_stamp_segment(
                pixels.as_mut_ptr(),
                pixels.len(),
                width,
                height,
                cmd.ax,
                cmd.ay,
                cmd.bx,
                cmd.by,
                cmd.start_radius,
                cmd.end_radius,
                cmd.color_argb,
                cmd.brush_shape,
                cmd.antialias_level,
                bool_to_u8(cmd.include_start),
                bool_to_u8(cmd.erase),
                bool_to_u8(cmd.random_rotation),
                bool_to_u8(cmd.smooth_rotation),
                cmd.rotation_seed,
                cmd.rotation_jitter,
                bool_to_u8(cmd.screentone_enabled),
                cmd.screentone_spacing,
                cmd.screentone_dot_size,
                cmd.screentone_rotation,
                cmd.screentone_softness,
                cmd.screentone_shape,
                cmd.spacing,
                cmd.scatter,
                cmd.softness,
                bool_to_u8(cmd.snap_to_pixel),
                1,
                0,
                0,
                std::ptr::null(),
                0,
                selection_ptr,
                selection_len,
            ),
            2 => cpu_brush_draw_capsule_segment(
                pixels.as_mut_ptr(),
                pixels.len(),
                width,
                height,
                cmd.ax,
                cmd.ay,
                cmd.bx,
                cmd.by,
                cmd.start_radius,
                cmd.end_radius,
                cmd.color_argb,
                cmd.antialias_level,
                bool_to_u8(cmd.include_start_cap),
                bool_to_u8(cmd.erase),
                bool_to_u8(cmd.screentone_enabled),
                cmd.screentone_spacing,
                cmd.screentone_dot_size,
                cmd.screentone_rotation,
                cmd.screentone_softness,
                cmd.screentone_shape,
                selection_ptr,
                selection_len,
            ),
            _ => 0,
        };
        if result == 0 {
            ok = false;
            break;
        }
    }
    CpuBrushResult { ok, pixels }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cpu_brush_apply_streamline_samples(samples: Vec<f32>, strength: f32) -> CpuStreamlineResult {
    let mut samples = samples;
    let ok = cpu_brush_apply_streamline(samples.as_mut_ptr(), samples.len(), strength);
    CpuStreamlineResult {
        ok: ok != 0,
        samples,
    }
}
