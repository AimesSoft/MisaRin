use crate::cpu_transform::{cpu_build_overflow_snapshot, cpu_layer_translate};

#[flutter_rust_bridge::frb]
pub struct CpuTransformTranslateResult {
    pub ok: bool,
    pub canvas: Vec<u32>,
    pub overflow_x: Vec<i32>,
    pub overflow_y: Vec<i32>,
    pub overflow_color: Vec<u32>,
}

#[flutter_rust_bridge::frb]
pub struct CpuTransformSnapshotResult {
    pub ok: bool,
    pub snapshot: Vec<u32>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn cpu_transform_translate_layer(
    canvas: Vec<u32>,
    canvas_width: u32,
    canvas_height: u32,
    snapshot: Vec<u32>,
    snapshot_width: u32,
    snapshot_height: u32,
    origin_x: i32,
    origin_y: i32,
    dx: i32,
    dy: i32,
    overflow_capacity: u64,
) -> CpuTransformTranslateResult {
    let mut canvas = canvas;
    let mut overflow_x: Vec<i32> = if overflow_capacity > 0 {
        vec![0i32; overflow_capacity as usize]
    } else {
        Vec::new()
    };
    let mut overflow_y: Vec<i32> = if overflow_capacity > 0 {
        vec![0i32; overflow_capacity as usize]
    } else {
        Vec::new()
    };
    let mut overflow_color: Vec<u32> = if overflow_capacity > 0 {
        vec![0u32; overflow_capacity as usize]
    } else {
        Vec::new()
    };
    let mut overflow_count: u64 = 0;

    let (out_x_ptr, out_y_ptr, out_color_ptr, out_count_ptr, out_capacity) =
        if overflow_capacity > 0 {
            (
                overflow_x.as_mut_ptr(),
                overflow_y.as_mut_ptr(),
                overflow_color.as_mut_ptr(),
                &mut overflow_count as *mut u64,
                overflow_capacity,
            )
        } else {
            (
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                0,
            )
        };

    let ok = cpu_layer_translate(
        canvas.as_mut_ptr(),
        canvas.len() as u64,
        canvas_width,
        canvas_height,
        snapshot.as_ptr(),
        snapshot.len() as u64,
        snapshot_width,
        snapshot_height,
        origin_x,
        origin_y,
        dx,
        dy,
        out_x_ptr,
        out_y_ptr,
        out_color_ptr,
        out_capacity,
        out_count_ptr,
    );

    if ok != 0 && overflow_capacity > 0 {
        let used = overflow_count.min(overflow_capacity) as usize;
        overflow_x.truncate(used);
        overflow_y.truncate(used);
        overflow_color.truncate(used);
    } else {
        overflow_x.clear();
        overflow_y.clear();
        overflow_color.clear();
    }

    CpuTransformTranslateResult {
        ok: ok != 0,
        canvas,
        overflow_x,
        overflow_y,
        overflow_color,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn cpu_transform_build_overflow_snapshot(
    canvas: Vec<u32>,
    canvas_width: u32,
    canvas_height: u32,
    snapshot_width: u32,
    snapshot_height: u32,
    origin_x: i32,
    origin_y: i32,
    overflow_x: Vec<i32>,
    overflow_y: Vec<i32>,
    overflow_color: Vec<u32>,
) -> CpuTransformSnapshotResult {
    let snapshot_len = (snapshot_width as u64).saturating_mul(snapshot_height as u64) as usize;
    let mut snapshot = vec![0u32; snapshot_len];

    let overflow_len = overflow_x
        .len()
        .min(overflow_y.len())
        .min(overflow_color.len());
    let (overflow_x_ptr, overflow_y_ptr, overflow_color_ptr, overflow_len_u64) = if overflow_len > 0
    {
        (
            overflow_x.as_ptr(),
            overflow_y.as_ptr(),
            overflow_color.as_ptr(),
            overflow_len as u64,
        )
    } else {
        (std::ptr::null(), std::ptr::null(), std::ptr::null(), 0)
    };

    let ok = cpu_build_overflow_snapshot(
        canvas.as_ptr(),
        canvas.len() as u64,
        canvas_width,
        canvas_height,
        snapshot.as_mut_ptr(),
        snapshot.len() as u64,
        snapshot_width,
        snapshot_height,
        origin_x,
        origin_y,
        overflow_x_ptr,
        overflow_y_ptr,
        overflow_color_ptr,
        overflow_len_u64,
    );

    CpuTransformSnapshotResult {
        ok: ok != 0,
        snapshot,
    }
}
