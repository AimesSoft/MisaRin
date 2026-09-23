use crate::api::gpu_composite::{cpu_blend_on_canvas, cpu_blend_overflow};

#[flutter_rust_bridge::frb]
pub struct CpuBlendResult {
    pub ok: bool,
    pub canvas: Vec<u32>,
}

#[flutter_rust_bridge::frb]
pub struct CpuBlendOverflowResult {
    pub ok: bool,
    pub canvas: Vec<u32>,
    pub out_x: Vec<i32>,
    pub out_y: Vec<i32>,
    pub out_color: Vec<u32>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn cpu_blend_on_canvas_rgba(
    src: Vec<u32>,
    dst: Vec<u32>,
    width: u32,
    height: u32,
    start_x: i32,
    end_x: i32,
    start_y: i32,
    end_y: i32,
    opacity: f32,
    blend_mode: u32,
    mask: Option<Vec<u32>>,
    mask_opacity: f32,
) -> CpuBlendResult {
    let mut dst = dst;
    let (mask_ptr, mask_len) = match mask.as_ref() {
        Some(m) => (m.as_ptr(), m.len() as u64),
        None => (std::ptr::null(), 0),
    };
    let ok = cpu_blend_on_canvas(
        src.as_ptr(),
        dst.as_mut_ptr(),
        dst.len() as u64,
        width,
        height,
        start_x,
        end_x,
        start_y,
        end_y,
        opacity,
        blend_mode,
        mask_ptr,
        mask_len,
        mask_opacity,
    );
    CpuBlendResult {
        ok: ok != 0,
        canvas: dst,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cpu_blend_overflow_rgba(
    canvas: Vec<u32>,
    width: u32,
    height: u32,
    upper_x: Vec<i32>,
    upper_y: Vec<i32>,
    upper_color: Vec<u32>,
    lower_x: Vec<i32>,
    lower_y: Vec<i32>,
    lower_color: Vec<u32>,
    opacity: f32,
    blend_mode: u32,
    mask: Option<Vec<u32>>,
    mask_opacity: f32,
    mask_overflow_x: Vec<i32>,
    mask_overflow_y: Vec<i32>,
    mask_overflow_color: Vec<u32>,
    out_capacity: u64,
) -> CpuBlendOverflowResult {
    let mut canvas = canvas;

    let upper_len = upper_x.len().min(upper_y.len()).min(upper_color.len()) as u64;
    let lower_len = lower_x.len().min(lower_y.len()).min(lower_color.len()) as u64;
    let mask_overflow_len = mask_overflow_x
        .len()
        .min(mask_overflow_y.len())
        .min(mask_overflow_color.len()) as u64;

    let (mask_ptr, mask_len) = match mask.as_ref() {
        Some(m) => (m.as_ptr(), m.len() as u64),
        None => (std::ptr::null(), 0),
    };

    let mut out_x: Vec<i32> = if out_capacity > 0 {
        vec![0i32; out_capacity as usize]
    } else {
        Vec::new()
    };
    let mut out_y: Vec<i32> = if out_capacity > 0 {
        vec![0i32; out_capacity as usize]
    } else {
        Vec::new()
    };
    let mut out_color: Vec<u32> = if out_capacity > 0 {
        vec![0u32; out_capacity as usize]
    } else {
        Vec::new()
    };
    let mut out_count: u64 = 0;

    let (out_x_ptr, out_y_ptr, out_color_ptr, out_count_ptr, out_cap) = if out_capacity > 0 {
        (
            out_x.as_mut_ptr(),
            out_y.as_mut_ptr(),
            out_color.as_mut_ptr(),
            &mut out_count as *mut u64,
            out_capacity,
        )
    } else {
        (
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            &mut out_count as *mut u64,
            0,
        )
    };

    let ok = cpu_blend_overflow(
        canvas.as_mut_ptr(),
        canvas.len() as u64,
        width,
        height,
        upper_x.as_ptr(),
        upper_y.as_ptr(),
        upper_color.as_ptr(),
        upper_len,
        if lower_len > 0 {
            lower_x.as_ptr()
        } else {
            std::ptr::null()
        },
        if lower_len > 0 {
            lower_y.as_ptr()
        } else {
            std::ptr::null()
        },
        if lower_len > 0 {
            lower_color.as_ptr()
        } else {
            std::ptr::null()
        },
        lower_len,
        opacity,
        blend_mode,
        mask_ptr,
        mask_len,
        mask_opacity,
        if mask_overflow_len > 0 {
            mask_overflow_x.as_ptr()
        } else {
            std::ptr::null()
        },
        if mask_overflow_len > 0 {
            mask_overflow_y.as_ptr()
        } else {
            std::ptr::null()
        },
        if mask_overflow_len > 0 {
            mask_overflow_color.as_ptr()
        } else {
            std::ptr::null()
        },
        mask_overflow_len,
        out_x_ptr,
        out_y_ptr,
        out_color_ptr,
        out_cap,
        out_count_ptr,
    );

    if ok != 0 && out_capacity > 0 {
        let used = out_count.min(out_capacity) as usize;
        out_x.truncate(used);
        out_y.truncate(used);
        out_color.truncate(used);
    } else {
        out_x.clear();
        out_y.clear();
        out_color.clear();
    }

    CpuBlendOverflowResult {
        ok: ok != 0,
        canvas,
        out_x,
        out_y,
        out_color,
    }
}
