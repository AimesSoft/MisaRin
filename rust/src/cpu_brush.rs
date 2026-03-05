use std::f32::consts::{FRAC_1_SQRT_2, PI};

const EPS: f32 = 1.0e-6;
const SUBPIXEL_RADIUS_LIMIT: f32 = 0.6;
const HALF_PIXEL: f32 = 0.5;
const SUPERSAMPLE_DIAMETER_THRESHOLD: f32 = 10.0;
const SUPERSAMPLE_FINE_DIAMETER: f32 = 1.0;
const MIN_INTEGRATION_SLICES: i32 = 6;
const MAX_INTEGRATION_SLICES: i32 = 20;

#[derive(Clone, Copy)]
struct ScreentoneSettings {
    enabled: bool,
    spacing: f32,
    dot_size: f32,
    rot_sin: f32,
    rot_cos: f32,
    softness: f32,
    shape: u32,
}

impl ScreentoneSettings {
    fn disabled() -> Self {
        Self {
            enabled: false,
            spacing: 10.0,
            dot_size: 0.6,
            rot_sin: 0.0,
            rot_cos: 1.0,
            softness: 0.0,
            shape: 0,
        }
    }
}

fn clamp01(v: f32) -> f32 {
    if v.is_finite() {
        v.clamp(0.0, 1.0)
    } else {
        0.0
    }
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

fn antialias_samples_per_axis(level: u32) -> u32 {
    let clamped = level.min(9);
    if clamped <= 3 {
        1u32 << clamped
    } else {
        8 + (clamped - 3) * 2
    }
}

fn screentone_settings_from_params(
    enabled: u8,
    spacing: f32,
    dot_size: f32,
    rotation_deg: f32,
    softness: f32,
    shape: u32,
) -> ScreentoneSettings {
    if enabled == 0 {
        return ScreentoneSettings::disabled();
    }
    let spacing = if spacing.is_finite() { spacing } else { 10.0 }.clamp(2.0, 200.0);
    let dot_size = if dot_size.is_finite() { dot_size } else { 0.6 }.clamp(0.0, 1.0);
    let rotation = if rotation_deg.is_finite() {
        rotation_deg
    } else {
        45.0
    }
    .clamp(-180.0, 180.0);
    let angle = rotation * (PI / 180.0);
    let rot_sin = angle.sin();
    let rot_cos = angle.cos();
    let softness = if softness.is_finite() { softness } else { 0.0 }.clamp(0.0, 1.0);
    ScreentoneSettings {
        enabled: true,
        spacing,
        dot_size,
        rot_sin,
        rot_cos,
        softness,
        shape,
    }
}

fn screentone_mask_at(
    sample_x: f32,
    sample_y: f32,
    settings: ScreentoneSettings,
    antialias_level: u32,
) -> f32 {
    if !settings.enabled {
        return 1.0;
    }
    let spacing = settings.spacing;
    if !spacing.is_finite() || spacing <= 0.0 {
        return 1.0;
    }
    let dot_radius = (spacing * 0.5 * settings.dot_size).max(0.0);
    if dot_radius <= 0.0 {
        return 0.0;
    }
    let rx = sample_x * settings.rot_cos + sample_y * settings.rot_sin;
    let ry = -sample_x * settings.rot_sin + sample_y * settings.rot_cos;
    let cell_x = (rx / spacing).floor();
    let cell_y = (ry / spacing).floor();
    let center_x = (cell_x + 0.5) * spacing;
    let center_y = (cell_y + 0.5) * spacing;
    let dx = rx - center_x;
    let dy = ry - center_y;
    let aa_feather = antialias_feather(antialias_level);
    let edge = (dot_radius * settings.softness).max(aa_feather);
    let dist = match settings.shape {
        2 => {
            let half_side = dot_radius * FRAC_1_SQRT_2;
            let sd = signed_distance_box(dx, dy, half_side);
            dot_radius + sd
        }
        1 | 3 => {
            if dot_radius <= EPS {
                dot_radius
            } else {
                let inv_r = 1.0 / dot_radius;
                let ux = dx * inv_r;
                let uy = dy * inv_r;
                let sd_unit = if settings.shape == 3 {
                    signed_distance_star_unit(ux, uy)
                } else {
                    signed_distance_triangle_unit(ux, uy)
                };
                dot_radius + sd_unit * dot_radius
            }
        }
        _ => (dx * dx + dy * dy).sqrt(),
    };
    let coverage = brush_alpha(dist, dot_radius, settings.softness, antialias_level);
    if edge <= 0.0 {
        return if coverage > 0.0 { 1.0 } else { 0.0 };
    }
    coverage
}

fn needs_supersampling(radius: f32, antialias_level: u32) -> bool {
    if antialias_level == 0 || radius <= 0.0 {
        return false;
    }
    let diameter = radius * 2.0;
    if diameter < SUPERSAMPLE_FINE_DIAMETER {
        return true;
    }
    diameter < SUPERSAMPLE_DIAMETER_THRESHOLD
}

fn supersample_factor(radius: f32) -> i32 {
    let diameter = radius * 2.0;
    if diameter < SUPERSAMPLE_FINE_DIAMETER {
        return 6;
    }
    if diameter < SUPERSAMPLE_DIAMETER_THRESHOLD {
        return 3;
    }
    1
}

fn brush_alpha(dist: f32, radius: f32, softness: f32, aa_level: u32) -> f32 {
    if radius <= 0.0 {
        return 0.0;
    }
    let s = clamp01(softness);
    let aa_feather = antialias_feather(aa_level);
    let edge = aa_feather.max(radius * s);
    if edge <= 0.0 {
        return if dist <= radius { 1.0 } else { 0.0 };
    }
    let inner = (radius - edge).max(0.0);
    let outer = radius + edge;
    if dist <= inner {
        return 1.0;
    }
    if dist >= outer {
        return 0.0;
    }
    (outer - dist) / (outer - inner)
}

fn radial_coverage(distance: f32, radius: f32, feather: f32, antialias_level: u32) -> f32 {
    if radius <= 0.0 {
        return 0.0;
    }
    if antialias_level == 0 || feather <= 0.0 {
        return if distance <= radius { 1.0 } else { 0.0 };
    }
    let inner = (radius - feather).max(0.0);
    let outer = radius + feather;
    if distance <= inner {
        return 1.0;
    }
    if distance >= outer || outer <= inner {
        return 0.0;
    }
    (outer - distance) / (outer - inner)
}

fn integration_slices_for_radius(radius: f32) -> i32 {
    let scaled =
        (radius * 32.0).clamp(MIN_INTEGRATION_SLICES as f32, MAX_INTEGRATION_SLICES as f32);
    let rounded = scaled.round() as i32;
    rounded.clamp(MIN_INTEGRATION_SLICES, MAX_INTEGRATION_SLICES)
}

fn vertical_intersection_length(sample_x: f32, cx: f32, cy: f32, radius: f32) -> f32 {
    let dx = sample_x - cx;
    let rad_sq = radius * radius;
    let remainder = rad_sq - dx * dx;
    if remainder <= 0.0 {
        return 0.0;
    }
    let chord = remainder.sqrt();
    let low = (-HALF_PIXEL).max(cy - chord);
    let high = HALF_PIXEL.min(cy + chord);
    let span = high - low;
    if span > 0.0 {
        span
    } else {
        0.0
    }
}

fn projected_pixel_coverage(dx: f32, dy: f32, radius: f32) -> f32 {
    let abs_dx = dx.abs();
    let abs_dy = dy.abs();
    if abs_dx >= radius + HALF_PIXEL || abs_dy >= radius + HALF_PIXEL {
        return 0.0;
    }
    if abs_dx + radius <= HALF_PIXEL && abs_dy + radius <= HALF_PIXEL {
        let area = std::f32::consts::PI * radius * radius;
        return if area >= 1.0 { 1.0 } else { area };
    }
    let cx = -dx;
    let cy = -dy;
    let min_x = (-HALF_PIXEL).max(cx - radius);
    let max_x = HALF_PIXEL.min(cx + radius);
    if min_x >= max_x {
        return 0.0;
    }
    let width = max_x - min_x;
    let slices = integration_slices_for_radius(radius);
    let mut area = 0.0;
    for i in 0..slices {
        let start = min_x + width * (i as f32 / slices as f32);
        let end = min_x + width * ((i + 1) as f32 / slices as f32);
        let mid = (start + end) * 0.5;
        let span = vertical_intersection_length(mid, cx, cy, radius);
        if span <= 0.0 {
            continue;
        }
        area += span * (end - start);
    }
    area.clamp(0.0, 1.0)
}

fn supersample_circle_coverage(
    dx: f32,
    dy: f32,
    radius: f32,
    feather: f32,
    antialias_level: u32,
) -> f32 {
    let samples = supersample_factor(radius).clamp(1, 6);
    if samples <= 1 {
        let dist = (dx * dx + dy * dy).sqrt();
        return radial_coverage(dist, radius, feather, antialias_level);
    }
    let step = 1.0 / samples as f32;
    let start = -0.5 + step * 0.5;
    let mut accum = 0.0;
    for sy in 0..samples {
        let offset_y = start + sy as f32 * step;
        for sx in 0..samples {
            let offset_x = start + sx as f32 * step;
            let sample_dx = dx + offset_x;
            let sample_dy = dy + offset_y;
            let distance = (sample_dx * sample_dx + sample_dy * sample_dy).sqrt();
            accum += radial_coverage(distance, radius, feather, antialias_level);
        }
    }
    let inv = 1.0 / (samples * samples) as f32;
    accum * inv
}

fn compute_pixel_coverage(
    dx: f32,
    dy: f32,
    distance: f32,
    radius: f32,
    feather: f32,
    antialias_level: u32,
) -> f32 {
    if radius <= 0.0 {
        return 0.0;
    }
    if needs_supersampling(radius, antialias_level) {
        return supersample_circle_coverage(dx, dy, radius, feather, antialias_level);
    }
    if antialias_level > 0 && radius <= SUBPIXEL_RADIUS_LIMIT {
        return projected_pixel_coverage(dx, dy, radius);
    }
    radial_coverage(distance, radius, feather, antialias_level)
}

fn rotate_to_brush_space(x: f32, y: f32, rot_sin: f32, rot_cos: f32) -> (f32, f32) {
    (x * rot_cos + y * rot_sin, -x * rot_sin + y * rot_cos)
}

#[derive(Clone, Copy)]
struct CustomMaskView<'a> {
    width: u32,
    height: u32,
    data: &'a [u8],
}

fn custom_mask_view_from_params<'a>(
    width: u32,
    height: u32,
    mask_ptr: *const u8,
    mask_len: usize,
) -> Option<CustomMaskView<'a>> {
    if mask_ptr.is_null() || width == 0 || height == 0 {
        return None;
    }
    let expected = (width as usize)
        .checked_mul(height as usize)
        .and_then(|v| v.checked_mul(2));
    let expected = match expected {
        Some(value) => value,
        None => return None,
    };
    if mask_len < expected {
        return None;
    }
    let data = unsafe { std::slice::from_raw_parts(mask_ptr, mask_len) };
    Some(CustomMaskView {
        width,
        height,
        data: &data[..expected],
    })
}

fn custom_mask_alpha(
    rel_x: f32,
    rel_y: f32,
    radius: f32,
    softness: f32,
    mask: &CustomMaskView<'_>,
) -> f32 {
    if radius <= EPS {
        return 0.0;
    }
    if mask.width == 0 || mask.height == 0 {
        return 0.0;
    }
    // Preserve the original tip aspect ratio. `radius` controls the half-size
    // of the longer side, matching Krita-style image brush scaling.
    let mask_w = mask.width as f32;
    let mask_h = mask.height as f32;
    let max_dim = mask_w.max(mask_h).max(1.0);
    let half_w = radius * (mask_w / max_dim);
    let half_h = radius * (mask_h / max_dim);
    if half_w <= EPS || half_h <= EPS {
        return 0.0;
    }
    let u = rel_x / half_w * 0.5 + 0.5;
    let v = rel_y / half_h * 0.5 + 0.5;
    if u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0 {
        return 0.0;
    }
    let max_x = (mask.width - 1) as f32;
    let max_y = (mask.height - 1) as f32;
    let fx = u * max_x;
    let fy = v * max_y;
    let x0 = fx.floor() as i32;
    let y0 = fy.floor() as i32;
    let x1 = (x0 + 1).min(mask.width as i32 - 1);
    let y1 = (y0 + 1).min(mask.height as i32 - 1);
    let tx = fx - x0 as f32;
    let ty = fy - y0 as f32;

    let stride = (mask.width as usize) * 2;
    let sample = |x: i32, y: i32| -> (f32, f32) {
        let idx = (y as usize) * stride + (x as usize) * 2;
        let a = mask.data.get(idx).copied().unwrap_or(0) as f32 / 255.0;
        let b = mask.data.get(idx + 1).copied().unwrap_or(0) as f32 / 255.0;
        (a, b)
    };
    let c00 = sample(x0, y0);
    let c10 = sample(x1, y0);
    let c01 = sample(x0, y1);
    let c11 = sample(x1, y1);
    let lerp = |a: (f32, f32), b: (f32, f32), t: f32| -> (f32, f32) {
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
    };
    let a0 = lerp(c00, c10, tx);
    let a1 = lerp(c01, c11, tx);
    let sample = lerp(a0, a1, ty);
    let t = clamp01(softness);
    sample.0 + (sample.1 - sample.0) * t
}

fn tri_vert(i: u32) -> (f32, f32) {
    match i {
        0 => (0.0, -1.0),
        1 => (0.866025404, 0.5),
        _ => (-0.866025404, 0.5),
    }
}

fn star_vert(i: u32) -> (f32, f32) {
    match i {
        0 => (0.0, -1.0),
        1 => (0.224513988, -0.309016994),
        2 => (0.951056516, -0.309016994),
        3 => (0.363271264, 0.118033989),
        4 => (0.587785252, 0.809016994),
        5 => (0.0, 0.381966011),
        6 => (-0.587785252, 0.809016994),
        7 => (-0.363271264, 0.118033989),
        8 => (-0.951056516, -0.309016994),
        _ => (-0.224513988, -0.309016994),
    }
}

fn segment_distance(px: f32, py: f32, ax: f32, ay: f32, bx: f32, by: f32) -> f32 {
    let abx = bx - ax;
    let aby = by - ay;
    let apx = px - ax;
    let apy = py - ay;
    let ab_len2 = abx * abx + aby * aby;
    if ab_len2 <= EPS {
        return ((px - ax) * (px - ax) + (py - ay) * (py - ay)).sqrt();
    }
    let t = (apx * abx + apy * aby) / ab_len2;
    let t = t.clamp(0.0, 1.0);
    let cx = ax + abx * t;
    let cy = ay + aby * t;
    ((px - cx) * (px - cx) + (py - cy) * (py - cy)).sqrt()
}

fn signed_distance_box(px: f32, py: f32, half: f32) -> f32 {
    let dx = px.abs() - half;
    let dy = py.abs() - half;
    let outside = (dx.max(0.0) * dx.max(0.0) + dy.max(0.0) * dy.max(0.0)).sqrt();
    let inside = dx.max(dy).min(0.0);
    outside + inside
}

fn signed_distance_triangle_unit(px: f32, py: f32) -> f32 {
    let mut min_dist: f32 = 1.0e9;
    let mut inside = false;
    let mut j = 2u32;
    for i in 0..3u32 {
        let (ax, ay) = tri_vert(j);
        let (bx, by) = tri_vert(i);
        min_dist = min_dist.min(segment_distance(px, py, ax, ay, bx, by));
        if (ay > py) != (by > py) {
            let x = ax + (py - ay) * (bx - ax) / (by - ay);
            if px < x {
                inside = !inside;
            }
        }
        j = i;
    }
    if inside {
        -min_dist
    } else {
        min_dist
    }
}

fn signed_distance_star_unit(px: f32, py: f32) -> f32 {
    let mut min_dist: f32 = 1.0e9;
    let mut inside = false;
    let mut j = 9u32;
    for i in 0..10u32 {
        let (ax, ay) = star_vert(j);
        let (bx, by) = star_vert(i);
        min_dist = min_dist.min(segment_distance(px, py, ax, ay, bx, by));
        if (ay > py) != (by > py) {
            let x = ax + (py - ay) * (bx - ax) / (by - ay);
            if px < x {
                inside = !inside;
            }
        }
        j = i;
    }
    if inside {
        -min_dist
    } else {
        min_dist
    }
}

fn shape_distance_to_point(
    sample_x: f32,
    sample_y: f32,
    center_x: f32,
    center_y: f32,
    radius: f32,
    rot_sin: f32,
    rot_cos: f32,
    shape: u32,
) -> f32 {
    let rel_x = sample_x - center_x;
    let rel_y = sample_y - center_y;
    let (rx, ry) = rotate_to_brush_space(rel_x, rel_y, rot_sin, rot_cos);
    match shape {
        0 => (rx * rx + ry * ry).sqrt(), // circle
        2 => {
            if radius <= EPS {
                radius
            } else {
                let half_side = radius * FRAC_1_SQRT_2;
                let sd = signed_distance_box(rx, ry, half_side);
                radius + sd
            }
        }
        1 | 3 => {
            if radius <= EPS {
                return radius;
            }
            let inv_r = 1.0 / radius;
            let ux = rx * inv_r;
            let uy = ry * inv_r;
            let sd_unit = if shape == 3 {
                signed_distance_star_unit(ux, uy)
            } else {
                signed_distance_triangle_unit(ux, uy)
            };
            radius + sd_unit * radius
        }
        _ => (rx * rx + ry * ry).sqrt(),
    }
}

fn unpack_a(argb: u32) -> f32 {
    ((argb >> 24) & 0xff) as f32 / 255.0
}

fn unpack_r(argb: u32) -> f32 {
    ((argb >> 16) & 0xff) as f32 / 255.0
}

fn unpack_g(argb: u32) -> f32 {
    ((argb >> 8) & 0xff) as f32 / 255.0
}

fn unpack_b(argb: u32) -> f32 {
    (argb & 0xff) as f32 / 255.0
}

fn pack_argb(a: f32, r: f32, g: f32, b: f32) -> u32 {
    let aa = (clamp01(a) * 255.0 + 0.5).floor().clamp(0.0, 255.0) as u32;
    let rr = (clamp01(r) * 255.0 + 0.5).floor().clamp(0.0, 255.0) as u32;
    let gg = (clamp01(g) * 255.0 + 0.5).floor().clamp(0.0, 255.0) as u32;
    let bb = (clamp01(b) * 255.0 + 0.5).floor().clamp(0.0, 255.0) as u32;
    (aa << 24) | (rr << 16) | (gg << 8) | bb
}

fn blend_paint(dst: u32, src_r: f32, src_g: f32, src_b: f32, src_a: f32) -> u32 {
    if src_a <= 0.0 {
        return dst;
    }
    let da = unpack_a(dst);
    let dr = unpack_r(dst);
    let dg = unpack_g(dst);
    let db = unpack_b(dst);
    let out_a = src_a + da * (1.0 - src_a);
    if out_a <= 0.0 {
        return 0;
    }
    let dst_w = da * (1.0 - src_a);
    let out_r = (src_r * src_a + dr * dst_w) / out_a;
    let out_g = (src_g * src_a + dg * dst_w) / out_a;
    let out_b = (src_b * src_a + db * dst_w) / out_a;
    pack_argb(out_a, out_r, out_g, out_b)
}

fn blend_erase(dst: u32, erase_a: f32) -> u32 {
    if erase_a <= 0.0 {
        return dst;
    }
    let da = unpack_a(dst);
    if da <= 0.0 {
        return dst;
    }
    let out_a = da * (1.0 - clamp01(erase_a));
    if out_a <= 0.0 {
        return 0;
    }
    pack_argb(out_a, unpack_r(dst), unpack_g(dst), unpack_b(dst))
}

#[derive(Clone, Copy, Debug)]
struct CapsuleCoverageSample {
    coverage: f32,
    radius: f32,
}

fn capsule_coverage_sample(
    px: f32,
    py: f32,
    ax: f32,
    ay: f32,
    abx: f32,
    aby: f32,
    inv_len_sq: f32,
    include_start_cap: bool,
    variable_radius: bool,
    start_radius: f32,
    radius_delta: f32,
    feather: f32,
    antialias_level: u32,
) -> Option<CapsuleCoverageSample> {
    let raw_t = ((px - ax) * abx + (py - ay) * aby) * inv_len_sq;
    let mut t = raw_t;
    if t < 0.0 {
        if !include_start_cap && t < -1.0e-6 {
            return None;
        }
        t = 0.0;
    } else if t > 1.0 {
        t = 1.0;
    }
    let closest_x = ax + abx * t;
    let closest_y = ay + aby * t;
    let dxp = px - closest_x;
    let dyp = py - closest_y;
    let distance = (dxp * dxp + dyp * dyp).sqrt();
    let mut radius = if variable_radius {
        start_radius + radius_delta * t
    } else {
        start_radius
    };
    radius = radius.abs();
    if radius == 0.0 && feather == 0.0 {
        return None;
    }
    let coverage = compute_pixel_coverage(dxp, dyp, distance, radius, feather, antialias_level);
    if coverage <= 0.0 {
        return None;
    }
    Some(CapsuleCoverageSample { coverage, radius })
}

fn supersample_capsule_coverage(
    px: f32,
    py: f32,
    ax: f32,
    ay: f32,
    abx: f32,
    aby: f32,
    inv_len_sq: f32,
    include_start_cap: bool,
    variable_radius: bool,
    start_radius: f32,
    radius_delta: f32,
    feather: f32,
    antialias_level: u32,
    supersample: i32,
) -> f32 {
    if supersample <= 1 {
        return capsule_coverage_sample(
            px,
            py,
            ax,
            ay,
            abx,
            aby,
            inv_len_sq,
            include_start_cap,
            variable_radius,
            start_radius,
            radius_delta,
            feather,
            antialias_level,
        )
        .map(|s| s.coverage)
        .unwrap_or(0.0);
    }
    let step = 1.0 / supersample as f32;
    let start = -0.5 + step * 0.5;
    let mut accum = 0.0;
    for sy in 0..supersample {
        let offset_y = start + sy as f32 * step;
        let sample_py = py + offset_y;
        for sx in 0..supersample {
            let offset_x = start + sx as f32 * step;
            let sample_px = px + offset_x;
            if let Some(sample) = capsule_coverage_sample(
                sample_px,
                sample_py,
                ax,
                ay,
                abx,
                aby,
                inv_len_sq,
                include_start_cap,
                variable_radius,
                start_radius,
                radius_delta,
                feather,
                antialias_level,
            ) {
                accum += sample.coverage;
            }
        }
    }
    let inv = 1.0 / (supersample * supersample) as f32;
    accum * inv
}

fn signed_distance_to_polygon(px: f32, py: f32, vertices: &[(f32, f32)]) -> f32 {
    let count = vertices.len();
    if count < 3 {
        return f32::INFINITY;
    }
    let mut min_dist_sq = f32::INFINITY;
    let mut inside = false;
    for i in 0..count {
        let (ax, ay) = vertices[i];
        let (bx, by) = vertices[(i + 1) % count];
        let abx = bx - ax;
        let aby = by - ay;
        let mut proj = 0.0;
        let denom = abx * abx + aby * aby;
        if denom > 0.0 {
            proj = ((px - ax) * abx + (py - ay) * aby) / denom;
            if proj < 0.0 {
                proj = 0.0;
            } else if proj > 1.0 {
                proj = 1.0;
            }
        }
        let closest_x = ax + abx * proj;
        let closest_y = ay + aby * proj;
        let dx = px - closest_x;
        let dy = py - closest_y;
        let dist_sq = dx * dx + dy * dy;
        if dist_sq < min_dist_sq {
            min_dist_sq = dist_sq;
        }
        if (ay > py) != (by > py) {
            let x = ax + (bx - ax) * (py - ay) / (by - ay);
            if px < x {
                inside = !inside;
            }
        }
    }
    let distance = (min_dist_sq.max(0.0)).sqrt();
    if inside {
        -distance
    } else {
        distance
    }
}

fn polygon_coverage_at_point(px: f32, py: f32, vertices: &[(f32, f32)], feather: f32) -> f32 {
    let signed_distance = signed_distance_to_polygon(px, py, vertices);
    if !signed_distance.is_finite() {
        return 0.0;
    }
    if feather <= 0.0 {
        return if signed_distance <= 0.0 { 1.0 } else { 0.0 };
    }
    if signed_distance <= -feather {
        return 1.0;
    }
    if signed_distance >= feather {
        return 0.0;
    }
    (feather - signed_distance) / (2.0 * feather)
}

fn mix32(mut h: u32) -> u32 {
    h ^= h >> 16;
    h = h.wrapping_mul(0x7feb352d);
    h ^= h >> 15;
    h = h.wrapping_mul(0x846ca68b);
    h ^= h >> 16;
    h
}

fn brush_random_rotation_radians(center_x: f32, center_y: f32, seed: u32) -> f32 {
    let x = (center_x * 256.0).round() as i32;
    let y = (center_y * 256.0).round() as i32;

    let mut h: u32 = 0;
    h ^= seed;
    h ^= (x as u32).wrapping_mul(0x9e3779b1);
    h ^= (y as u32).wrapping_mul(0x85ebca77);
    h = mix32(h);

    let unit = (h as f64) / 4294967296.0;
    (unit * std::f64::consts::PI * 2.0) as f32
}

fn brush_random_unit(center_x: f32, center_y: f32, seed: u32, salt: u32) -> f32 {
    let x = (center_x * 256.0).round() as i32;
    let y = (center_y * 256.0).round() as i32;

    let mut h: u32 = 0;
    h ^= seed;
    h ^= salt;
    h ^= (x as u32).wrapping_mul(0x9e3779b1);
    h ^= (y as u32).wrapping_mul(0x85ebca77);
    h = mix32(h);

    (h as f64 / 4294967296.0) as f32
}

fn brush_scatter_offset(
    center_x: f32,
    center_y: f32,
    seed: u32,
    radius: f32,
    salt: u32,
) -> (f32, f32) {
    if !radius.is_finite() || radius <= 0.0 {
        return (0.0, 0.0);
    }
    let u = brush_random_unit(center_x, center_y, seed, salt);
    let v = brush_random_unit(center_x, center_y, seed, salt.wrapping_add(1));
    let dist = u.sqrt() * radius;
    let angle = v * std::f32::consts::PI * 2.0;
    (angle.cos() * dist, angle.sin() * dist)
}

fn stroke_stamp_spacing(radius: f32, spacing: f32) -> f32 {
    let mut r = if radius.is_finite() {
        radius.abs()
    } else {
        0.0
    };
    if !r.is_finite() {
        r = 0.0;
    }
    let mut s = if spacing.is_finite() { spacing } else { 0.15 };
    s = s.clamp(0.02, 2.5);
    (r * 2.0 * s).max(0.1)
}

fn custom_mask_half_extents(radius: f32, mask_width: u32, mask_height: u32) -> (f32, f32) {
    let mut r = if radius.is_finite() {
        radius.abs()
    } else {
        0.0
    };
    if !r.is_finite() || r <= 0.0 {
        r = 0.0;
    }

    let w = mask_width as f32;
    let h = mask_height as f32;
    if w <= 0.0 || h <= 0.0 || r <= 0.0 {
        return (0.0, 0.0);
    }

    let max_dim = w.max(h).max(1.0);
    (r * (w / max_dim), r * (h / max_dim))
}

fn projected_half_extent_along_direction(
    half_w: f32,
    half_h: f32,
    dir_x: f32,
    dir_y: f32,
    rot_sin: f32,
    rot_cos: f32,
) -> f32 {
    if half_w <= EPS || half_h <= EPS {
        return 0.0;
    }

    let len = (dir_x * dir_x + dir_y * dir_y).sqrt();
    if !len.is_finite() || len <= EPS {
        return half_w.min(half_h);
    }

    let ux = dir_x / len;
    let uy = dir_y / len;

    // Convert the movement direction into brush local space.
    let bx = ux * rot_cos + uy * rot_sin;
    let by = -ux * rot_sin + uy * rot_cos;

    let inv_w2 = 1.0 / (half_w * half_w);
    let inv_h2 = 1.0 / (half_h * half_h);
    let denom = bx * bx * inv_w2 + by * by * inv_h2;
    if !denom.is_finite() || denom <= EPS {
        return half_w.min(half_h);
    }

    let extent = 1.0 / denom.sqrt();
    if extent.is_finite() {
        extent
    } else {
        half_w.min(half_h)
    }
}

fn stroke_stamp_spacing_custom_mask(
    radius: f32,
    spacing: f32,
    mask_width: u32,
    mask_height: u32,
    dir_x: f32,
    dir_y: f32,
    rot_sin: f32,
    rot_cos: f32,
    may_random_rotate: bool,
) -> f32 {
    let mut s = if spacing.is_finite() { spacing } else { 0.15 };
    s = s.clamp(0.02, 2.5);

    let (half_w, half_h) = custom_mask_half_extents(radius, mask_width, mask_height);
    if half_w <= EPS || half_h <= EPS {
        return (radius.abs() * 2.0 * s).max(0.1);
    }

    // If random rotation is enabled, use the most conservative axis so stamps
    // don't separate when orientation jitters.
    let extent = if may_random_rotate {
        half_w.min(half_h)
    } else {
        projected_half_extent_along_direction(half_w, half_h, dir_x, dir_y, rot_sin, rot_cos)
    };

    (extent * 2.0 * s).max(0.1)
}

#[derive(Clone, Copy)]
struct BrushPoint {
    x: f32,
    y: f32,
    radius: f32,
    alpha: f32,
    rot_sin: f32,
    rot_cos: f32,
}

fn draw_points_sampled<'a>(
    pixels_ptr: *mut u32,
    pixels_len: usize,
    width: u32,
    height: u32,
    points: &[BrushPoint],
    color_argb: u32,
    brush_shape: u32,
    antialias_level: u32,
    softness: f32,
    erase: u8,
    accumulate: bool,
    selection_ptr: *const u8,
    selection_len: usize,
    custom_mask: Option<CustomMaskView<'a>>,
    screentone: ScreentoneSettings,
) -> u8 {
    if points.is_empty() || pixels_ptr.is_null() || width == 0 || height == 0 {
        return 0;
    }
    let pixel_count = (width as usize).saturating_mul(height as usize);
    if pixel_count == 0 || pixels_len < pixel_count {
        return 0;
    }

    let selection = if selection_ptr.is_null() || selection_len < pixel_count {
        None
    } else {
        Some(unsafe { std::slice::from_raw_parts(selection_ptr, selection_len) })
    };

    let base_a = unpack_a(color_argb);
    if base_a <= 0.0 {
        return 1;
    }
    let src_r = unpack_r(color_argb);
    let src_g = unpack_g(color_argb);
    let src_b = unpack_b(color_argb);
    let aa_level = antialias_level.min(9);
    let soft = clamp01(softness);
    let feather = antialias_feather(aa_level);
    let samples = antialias_samples_per_axis(aa_level);
    let inv_samples = 1.0 / (samples as f32);
    let total_samples = (samples * samples) as f32;
    let use_screentone = screentone.enabled;
    let custom_mask = custom_mask.as_ref();

    let mut any_point = false;
    let mut union_min_x = width as i32;
    let mut union_min_y = height as i32;
    let mut union_max_x: i32 = 0;
    let mut union_max_y: i32 = 0;

    for p in points {
        if !p.x.is_finite() || !p.y.is_finite() || !p.radius.is_finite() {
            continue;
        }
        if p.radius <= 0.0 {
            continue;
        }
        let alpha = if p.alpha.is_finite() {
            p.alpha.clamp(0.0, 1.0)
        } else {
            0.0
        };
        if alpha <= 0.0 {
            continue;
        }
        let edge = feather.max(p.radius * soft);
        let outer = p.radius + edge + 1.5;
        let min_x = (p.x - outer).floor().max(0.0) as i32;
        let max_x = (p.x + outer).ceil().min((width as f32) - 1.0) as i32;
        let min_y = (p.y - outer).floor().max(0.0) as i32;
        let max_y = (p.y + outer).ceil().min((height as f32) - 1.0) as i32;
        if min_x > max_x || min_y > max_y {
            continue;
        }
        if !any_point {
            union_min_x = min_x;
            union_max_x = max_x;
            union_min_y = min_y;
            union_max_y = max_y;
            any_point = true;
        } else {
            union_min_x = union_min_x.min(min_x);
            union_max_x = union_max_x.max(max_x);
            union_min_y = union_min_y.min(min_y);
            union_max_y = union_max_y.max(max_y);
        }
    }

    if !any_point {
        return 1;
    }

    let pixels = unsafe { std::slice::from_raw_parts_mut(pixels_ptr, pixel_count) };
    for y in union_min_y..=union_max_y {
        let src_row = (y as usize) * (width as usize);
        for x in union_min_x..=union_max_x {
            let dst_idx = src_row + (x as usize);
            if let Some(mask) = selection {
                if mask.get(dst_idx).copied().unwrap_or(0) == 0 {
                    continue;
                }
            }
            let mut accum = 0.0f32;
            for sy in 0..samples {
                for sx in 0..samples {
                    let ox = (sx as f32 + 0.5) * inv_samples - 0.5;
                    let oy = (sy as f32 + 0.5) * inv_samples - 0.5;
                    let sample_x = x as f32 + 0.5 + ox;
                    let sample_y = y as f32 + 0.5 + oy;
                    let mut sample_cov = if accumulate {
                        let mut remain = 1.0f32;
                        for p in points {
                            let a = if let Some(mask) = custom_mask {
                                let rel_x = sample_x - p.x;
                                let rel_y = sample_y - p.y;
                                let (rx, ry) =
                                    rotate_to_brush_space(rel_x, rel_y, p.rot_sin, p.rot_cos);
                                custom_mask_alpha(rx, ry, p.radius, soft, mask) * clamp01(p.alpha)
                            } else {
                                let dist = shape_distance_to_point(
                                    sample_x,
                                    sample_y,
                                    p.x,
                                    p.y,
                                    p.radius,
                                    p.rot_sin,
                                    p.rot_cos,
                                    brush_shape,
                                );
                                brush_alpha(dist, p.radius, soft, aa_level) * clamp01(p.alpha)
                            };
                            if a > 0.0 {
                                remain *= 1.0 - a;
                                if remain <= 0.0001 {
                                    remain = 0.0;
                                    break;
                                }
                            }
                        }
                        1.0 - remain
                    } else {
                        let mut best = 0.0f32;
                        for p in points {
                            let a = if let Some(mask) = custom_mask {
                                let rel_x = sample_x - p.x;
                                let rel_y = sample_y - p.y;
                                let (rx, ry) =
                                    rotate_to_brush_space(rel_x, rel_y, p.rot_sin, p.rot_cos);
                                custom_mask_alpha(rx, ry, p.radius, soft, mask) * clamp01(p.alpha)
                            } else {
                                let dist = shape_distance_to_point(
                                    sample_x,
                                    sample_y,
                                    p.x,
                                    p.y,
                                    p.radius,
                                    p.rot_sin,
                                    p.rot_cos,
                                    brush_shape,
                                );
                                brush_alpha(dist, p.radius, soft, aa_level) * clamp01(p.alpha)
                            };
                            if a > best {
                                best = a;
                                if best >= 1.0 {
                                    break;
                                }
                            }
                        }
                        best
                    };
                    if use_screentone {
                        let mask = screentone_mask_at(sample_x, sample_y, screentone, aa_level);
                        if mask <= 0.0 {
                            continue;
                        }
                        sample_cov *= mask;
                    }
                    accum += sample_cov;
                }
            }
            let coverage = clamp01(accum / total_samples.max(1.0));
            if coverage <= 0.0 {
                continue;
            }
            let paint_a = clamp01(coverage * base_a);
            if paint_a <= 0.0 {
                continue;
            }
            let dst = pixels[dst_idx];
            pixels[dst_idx] = if erase != 0 {
                blend_erase(dst, paint_a)
            } else {
                blend_paint(dst, src_r, src_g, src_b, paint_a)
            };
        }
    }

    1
}

#[no_mangle]
pub extern "C" fn cpu_brush_draw_stamp(
    pixels_ptr: *mut u32,
    pixels_len: usize,
    width: u32,
    height: u32,
    center_x: f32,
    center_y: f32,
    radius: f32,
    color_argb: u32,
    brush_shape: u32,
    antialias_level: u32,
    softness: f32,
    erase: u8,
    random_rotation: u8,
    smooth_rotation: u8,
    rotation_seed: u32,
    rotation_jitter: f32,
    screentone_enabled: u8,
    screentone_spacing: f32,
    screentone_dot_size: f32,
    screentone_rotation: f32,
    screentone_softness: f32,
    screentone_shape: u32,
    snap_to_pixel: u8,
    custom_mask_width: u32,
    custom_mask_height: u32,
    custom_mask_ptr: *const u8,
    custom_mask_len: usize,
    selection_ptr: *const u8,
    selection_len: usize,
) -> u8 {
    if pixels_ptr.is_null() || width == 0 || height == 0 {
        return 0;
    }
    let pixel_count = (width as usize).saturating_mul(height as usize);
    if pixel_count == 0 || pixels_len < pixel_count {
        return 0;
    }

    let mut cx = center_x;
    let mut cy = center_y;
    let mut r = radius;
    if snap_to_pixel != 0 {
        cx = cx.floor() + 0.5;
        cy = cy.floor() + 0.5;
        if r.is_finite() {
            r = (r * 2.0).round() * 0.5;
        }
    }
    if !r.is_finite() || r <= 0.0 {
        r = 0.01;
    }
    let _ = smooth_rotation;
    let custom_mask = custom_mask_view_from_params(
        custom_mask_width,
        custom_mask_height,
        custom_mask_ptr,
        custom_mask_len,
    );
    let supports_rotation = brush_shape != 0 || custom_mask.is_some();
    let needs_rotation = random_rotation != 0 && rotation_jitter > 0.0001 && supports_rotation;
    let (rot_sin, rot_cos) = if needs_rotation {
        let jitter = if rotation_jitter.is_finite() {
            rotation_jitter.clamp(0.0, 1.0)
        } else {
            1.0
        };
        let angle = brush_random_rotation_radians(cx, cy, rotation_seed) * jitter;
        (angle.sin(), angle.cos())
    } else {
        (0.0, 1.0)
    };
    let point = BrushPoint {
        x: cx,
        y: cy,
        radius: r,
        alpha: 1.0,
        rot_sin,
        rot_cos,
    };
    let screentone = screentone_settings_from_params(
        screentone_enabled,
        screentone_spacing,
        screentone_dot_size,
        screentone_rotation,
        screentone_softness,
        screentone_shape,
    );
    draw_points_sampled(
        pixels_ptr,
        pixels_len,
        width,
        height,
        std::slice::from_ref(&point),
        color_argb,
        brush_shape,
        antialias_level,
        softness,
        erase,
        true,
        selection_ptr,
        selection_len,
        custom_mask,
        screentone,
    )
}

#[no_mangle]
pub extern "C" fn cpu_brush_draw_stamp_segment(
    pixels_ptr: *mut u32,
    pixels_len: usize,
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
    include_start: u8,
    erase: u8,
    random_rotation: u8,
    smooth_rotation: u8,
    rotation_seed: u32,
    rotation_jitter: f32,
    screentone_enabled: u8,
    screentone_spacing: f32,
    screentone_dot_size: f32,
    screentone_rotation: f32,
    screentone_softness: f32,
    screentone_shape: u32,
    spacing: f32,
    scatter: f32,
    softness: f32,
    snap_to_pixel: u8,
    accumulate: u8,
    custom_mask_width: u32,
    custom_mask_height: u32,
    custom_mask_ptr: *const u8,
    custom_mask_len: usize,
    selection_ptr: *const u8,
    selection_len: usize,
) -> u8 {
    if pixels_ptr.is_null() || width == 0 || height == 0 {
        return 0;
    }
    let pixel_count = (width as usize).saturating_mul(height as usize);
    if pixel_count == 0 || pixels_len < pixel_count {
        return 0;
    }

    let distance = ((end_x - start_x).powi(2) + (end_y - start_y).powi(2)).sqrt();
    if !distance.is_finite() || distance <= 0.0001 {
        let sample_radius = if end_radius.is_finite() {
            end_radius
        } else {
            0.01
        };
        return cpu_brush_draw_stamp(
            pixels_ptr,
            pixels_len,
            width,
            height,
            end_x,
            end_y,
            sample_radius,
            color_argb,
            brush_shape,
            antialias_level,
            softness,
            erase,
            random_rotation,
            smooth_rotation,
            rotation_seed,
            rotation_jitter,
            screentone_enabled,
            screentone_spacing,
            screentone_dot_size,
            screentone_rotation,
            screentone_softness,
            screentone_shape,
            snap_to_pixel,
            custom_mask_width,
            custom_mask_height,
            custom_mask_ptr,
            custom_mask_len,
            selection_ptr,
            selection_len,
        );
    }

    let custom_mask = custom_mask_view_from_params(
        custom_mask_width,
        custom_mask_height,
        custom_mask_ptr,
        custom_mask_len,
    );
    let supports_rotation = brush_shape != 0 || custom_mask.is_some();
    let needs_rotation = random_rotation != 0 && rotation_jitter > 0.0001 && supports_rotation;
    let base_angle = if smooth_rotation != 0 && supports_rotation {
        (end_y - start_y).atan2(end_x - start_x)
    } else {
        0.0
    };
    let max_radius = start_radius.abs().max(end_radius.abs()).max(0.01);
    let (base_sin, base_cos) = (base_angle.sin(), base_angle.cos());
    let step = if let Some(mask) = custom_mask.as_ref() {
        stroke_stamp_spacing_custom_mask(
            max_radius,
            spacing,
            mask.width,
            mask.height,
            end_x - start_x,
            end_y - start_y,
            base_sin,
            base_cos,
            needs_rotation,
        )
    } else {
        stroke_stamp_spacing(max_radius, spacing)
    };
    let samples = ((distance / step).ceil() as i32).max(1);
    let start_index = if include_start != 0 { 0 } else { 1 };
    let scatter_factor = if scatter.is_finite() {
        scatter.clamp(0.0, 1.0)
    } else {
        0.0
    };
    let scatter_radius = max_radius * scatter_factor * 2.0;

    let mut points: Vec<BrushPoint> =
        Vec::with_capacity((samples - start_index + 1).max(1) as usize);
    for i in start_index..=samples {
        let t = if samples == 0 {
            1.0
        } else {
            i as f32 / samples as f32
        };
        let mut radius = if start_radius.is_finite() && end_radius.is_finite() {
            start_radius + (end_radius - start_radius) * t
        } else if end_radius.is_finite() {
            end_radius
        } else if start_radius.is_finite() {
            start_radius
        } else {
            0.01
        };
        let mut sample_x = if start_x.is_finite() && end_x.is_finite() {
            start_x + (end_x - start_x) * t
        } else {
            end_x
        };
        let mut sample_y = if start_y.is_finite() && end_y.is_finite() {
            start_y + (end_y - start_y) * t
        } else {
            end_y
        };
        let (jx, jy) = if scatter_radius > 0.0 {
            brush_scatter_offset(sample_x, sample_y, rotation_seed, scatter_radius, i as u32)
        } else {
            (0.0, 0.0)
        };
        sample_x += jx;
        sample_y += jy;
        if snap_to_pixel != 0 {
            sample_x = sample_x.floor() + 0.5;
            sample_y = sample_y.floor() + 0.5;
            if radius.is_finite() {
                radius = (radius * 2.0).round() * 0.5;
            }
        }
        if !radius.is_finite() || radius <= 0.0 {
            radius = 0.01;
        }
        let (rot_sin, rot_cos) = if needs_rotation || smooth_rotation != 0 {
            let mut angle = base_angle;
            if needs_rotation {
                angle += brush_random_rotation_radians(sample_x, sample_y, rotation_seed)
                    * rotation_jitter;
            }
            (angle.sin(), angle.cos())
        } else {
            (0.0, 1.0)
        };
        points.push(BrushPoint {
            x: sample_x,
            y: sample_y,
            radius,
            alpha: 1.0,
            rot_sin,
            rot_cos,
        });
    }
    let screentone = screentone_settings_from_params(
        screentone_enabled,
        screentone_spacing,
        screentone_dot_size,
        screentone_rotation,
        screentone_softness,
        screentone_shape,
    );
    draw_points_sampled(
        pixels_ptr,
        pixels_len,
        width,
        height,
        &points,
        color_argb,
        brush_shape,
        antialias_level,
        softness,
        erase,
        accumulate != 0,
        selection_ptr,
        selection_len,
        custom_mask,
        screentone,
    )
}

#[no_mangle]
pub extern "C" fn cpu_brush_draw_capsule_segment(
    pixels_ptr: *mut u32,
    pixels_len: usize,
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
    include_start_cap: u8,
    erase: u8,
    screentone_enabled: u8,
    screentone_spacing: f32,
    screentone_dot_size: f32,
    screentone_rotation: f32,
    screentone_softness: f32,
    screentone_shape: u32,
    selection_ptr: *const u8,
    selection_len: usize,
) -> u8 {
    if pixels_ptr.is_null() || width == 0 || height == 0 {
        return 0;
    }
    let pixel_count = (width as usize).saturating_mul(height as usize);
    if pixel_count == 0 || pixels_len < pixel_count {
        return 0;
    }

    let pixels = unsafe { std::slice::from_raw_parts_mut(pixels_ptr, pixels_len) };
    let selection = if selection_ptr.is_null() || selection_len < pixel_count {
        None
    } else {
        Some(unsafe { std::slice::from_raw_parts(selection_ptr, selection_len) })
    };

    let max_radius = start_radius.abs().max(end_radius.abs()).max(0.0);
    if max_radius <= 0.0 {
        return 1;
    }
    let abx = bx - ax;
    let aby = by - ay;
    let len_sq = abx * abx + aby * aby;
    let aa_level = antialias_level.min(9);
    let feather = antialias_feather(aa_level);
    let include_start = include_start_cap != 0;

    let src_a = unpack_a(color_argb);
    let src_r = unpack_r(color_argb);
    let src_g = unpack_g(color_argb);
    let src_b = unpack_b(color_argb);
    let screentone = screentone_settings_from_params(
        screentone_enabled,
        screentone_spacing,
        screentone_dot_size,
        screentone_rotation,
        screentone_softness,
        screentone_shape,
    );

    if len_sq <= 1.0e-6 {
        let expand = max_radius + feather + 1.5;
        let min_x = (ax - expand).floor().max(0.0) as i32;
        let max_x = (ax + expand).ceil().min((width as f32) - 1.0) as i32;
        let min_y = (ay - expand).floor().max(0.0) as i32;
        let max_y = (ay + expand).ceil().min((height as f32) - 1.0) as i32;
        if min_x > max_x || min_y > max_y {
            return 1;
        }
        for y in min_y..=max_y {
            let py = y as f32 + 0.5;
            let row = (y as usize) * (width as usize);
            for x in min_x..=max_x {
                let idx = row + (x as usize);
                if let Some(mask) = selection {
                    if mask.get(idx).copied().unwrap_or(0) == 0 {
                        continue;
                    }
                }
                let px = x as f32 + 0.5;
                let dx = px - ax;
                let dy = py - ay;
                let distance = (dx * dx + dy * dy).sqrt();
                let mut coverage =
                    compute_pixel_coverage(dx, dy, distance, max_radius, feather, aa_level);
                if screentone.enabled {
                    let mask = screentone_mask_at(px, py, screentone, aa_level);
                    if mask <= 0.0 {
                        continue;
                    }
                    coverage *= mask;
                }
                if coverage <= 0.0 {
                    continue;
                }
                let dst = pixels[idx];
                let alpha = if coverage >= 0.999 {
                    src_a
                } else {
                    clamp01(coverage * src_a)
                };
                if alpha <= 0.0 {
                    continue;
                }
                pixels[idx] = if erase != 0 {
                    blend_erase(dst, alpha)
                } else {
                    blend_paint(dst, src_r, src_g, src_b, alpha)
                };
            }
        }
        return 1;
    }

    let inv_len_sq = 1.0 / len_sq;
    let expand = max_radius + feather + 1.5;
    let min_x = (ax.min(bx) - expand).floor().max(0.0) as i32;
    let max_x = (ax.max(bx) + expand).ceil().min((width as f32) - 1.0) as i32;
    let min_y = (ay.min(by) - expand).floor().max(0.0) as i32;
    let max_y = (ay.max(by) + expand).ceil().min((height as f32) - 1.0) as i32;
    if min_x > max_x || min_y > max_y {
        return 1;
    }

    let variable_radius = (start_radius - end_radius).abs() > 1.0e-6;
    let radius_delta = end_radius - start_radius;

    for y in min_y..=max_y {
        let py = y as f32 + 0.5;
        let row = (y as usize) * (width as usize);
        for x in min_x..=max_x {
            let idx = row + (x as usize);
            if let Some(mask) = selection {
                if mask.get(idx).copied().unwrap_or(0) == 0 {
                    continue;
                }
            }
            let px = x as f32 + 0.5;
            let Some(center_sample) = capsule_coverage_sample(
                px,
                py,
                ax,
                ay,
                abx,
                aby,
                inv_len_sq,
                include_start,
                variable_radius,
                start_radius,
                radius_delta,
                feather,
                aa_level,
            ) else {
                continue;
            };
            let mut coverage = center_sample.coverage;
            if coverage <= 0.0 {
                continue;
            }
            if needs_supersampling(center_sample.radius, aa_level) {
                let supersample = supersample_factor(center_sample.radius);
                coverage = supersample_capsule_coverage(
                    px,
                    py,
                    ax,
                    ay,
                    abx,
                    aby,
                    inv_len_sq,
                    include_start,
                    variable_radius,
                    start_radius,
                    radius_delta,
                    feather,
                    aa_level,
                    supersample,
                );
                if coverage <= 0.0 {
                    continue;
                }
            }
            if screentone.enabled {
                let mask = screentone_mask_at(px, py, screentone, aa_level);
                if mask <= 0.0 {
                    continue;
                }
                coverage *= mask;
                if coverage <= 0.0 {
                    continue;
                }
            }
            let dst = pixels[idx];
            let alpha = if coverage >= 0.999 {
                src_a
            } else {
                clamp01(coverage * src_a)
            };
            if alpha <= 0.0 {
                continue;
            }
            pixels[idx] = if erase != 0 {
                blend_erase(dst, alpha)
            } else {
                blend_paint(dst, src_r, src_g, src_b, alpha)
            };
        }
    }

    1
}

#[no_mangle]
pub extern "C" fn cpu_brush_fill_polygon(
    pixels_ptr: *mut u32,
    pixels_len: usize,
    width: u32,
    height: u32,
    vertices_ptr: *const f32,
    vertices_len: usize,
    radius: f32,
    color_argb: u32,
    antialias_level: u32,
    softness: f32,
    erase: u8,
    selection_ptr: *const u8,
    selection_len: usize,
) -> u8 {
    if pixels_ptr.is_null() || width == 0 || height == 0 {
        return 0;
    }
    if vertices_ptr.is_null() || vertices_len < 6 {
        return 0;
    }
    let pixel_count = (width as usize).saturating_mul(height as usize);
    if pixel_count == 0 || pixels_len < pixel_count {
        return 0;
    }

    let vertices_floats = unsafe { std::slice::from_raw_parts(vertices_ptr, vertices_len) };
    let mut vertices: Vec<(f32, f32)> = Vec::with_capacity(vertices_len / 2);
    let mut min_x = f32::INFINITY;
    let mut max_x = f32::NEG_INFINITY;
    let mut min_y = f32::INFINITY;
    let mut max_y = f32::NEG_INFINITY;
    let mut iter = vertices_floats.chunks_exact(2);
    for chunk in &mut iter {
        let x = chunk[0];
        let y = chunk[1];
        if !x.is_finite() || !y.is_finite() {
            return 0;
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
        vertices.push((x, y));
    }
    if vertices.len() < 3 {
        return 0;
    }
    if !min_x.is_finite() || !max_x.is_finite() || !min_y.is_finite() || !max_y.is_finite() {
        return 0;
    }

    let aa_level = antialias_level.min(9);
    let base_feather = antialias_feather(aa_level);
    let soft = clamp01(softness);
    let softness_feather = radius * soft;
    let feather = if aa_level > 0 {
        base_feather.max(softness_feather)
    } else {
        softness_feather
    };
    let padding = feather + 1.5;
    let min_px = (min_x - padding).floor().max(0.0) as i32;
    let max_px = (max_x + padding).ceil().min((width as f32) - 1.0) as i32;
    let min_py = (min_y - padding).floor().max(0.0) as i32;
    let max_py = (max_y + padding).ceil().min((height as f32) - 1.0) as i32;
    if min_px > max_px || min_py > max_py {
        return 1;
    }

    let mut supersample = 1;
    let mut step = 1.0;
    let mut start = 0.0;
    let mut inv_sample_count = 1.0;
    if aa_level > 0 {
        let requires_supersampling = needs_supersampling(radius, aa_level);
        let adaptive_samples = if requires_supersampling {
            supersample_factor(radius).clamp(1, 6)
        } else {
            1
        };
        let desired_samples = (aa_level + 1) as i32 * 2;
        supersample = adaptive_samples.max(desired_samples).clamp(2, 6);
        step = 1.0 / supersample as f32;
        start = -0.5 + step * 0.5;
        inv_sample_count = 1.0 / (supersample * supersample) as f32;
    }

    let pixels = unsafe { std::slice::from_raw_parts_mut(pixels_ptr, pixels_len) };
    let selection = if selection_ptr.is_null() || selection_len < pixel_count {
        None
    } else {
        Some(unsafe { std::slice::from_raw_parts(selection_ptr, selection_len) })
    };

    let src_a = unpack_a(color_argb);
    let src_r = unpack_r(color_argb);
    let src_g = unpack_g(color_argb);
    let src_b = unpack_b(color_argb);

    for y in min_py..=max_py {
        let py = y as f32 + 0.5;
        let row = (y as usize) * (width as usize);
        for x in min_px..=max_px {
            let idx = row + (x as usize);
            if let Some(mask) = selection {
                if mask.get(idx).copied().unwrap_or(0) == 0 {
                    continue;
                }
            }
            let mut coverage = 0.0;
            if supersample <= 1 {
                coverage = polygon_coverage_at_point(x as f32 + 0.5, py, &vertices, feather);
            } else {
                let mut accumulated = 0.0;
                for sy in 0..supersample {
                    let offset_y = start + sy as f32 * step;
                    let sample_py = py + offset_y;
                    for sx in 0..supersample {
                        let offset_x = start + sx as f32 * step;
                        let sample_px = x as f32 + 0.5 + offset_x;
                        accumulated +=
                            polygon_coverage_at_point(sample_px, sample_py, &vertices, feather);
                    }
                }
                coverage = accumulated * inv_sample_count;
            }
            if coverage <= 0.0 {
                continue;
            }
            let dst = pixels[idx];
            let alpha = if coverage >= 0.999 {
                src_a
            } else {
                clamp01(coverage * src_a)
            };
            if alpha <= 0.0 {
                continue;
            }
            pixels[idx] = if erase != 0 {
                blend_erase(dst, alpha)
            } else {
                blend_paint(dst, src_r, src_g, src_b, alpha)
            };
        }
    }

    1
}

#[no_mangle]
pub extern "C" fn cpu_brush_draw_spray(
    pixels_ptr: *mut u32,
    pixels_len: usize,
    width: u32,
    height: u32,
    points_ptr: *const f32,
    points_len: usize,
    color_argb: u32,
    brush_shape: u32,
    antialias_level: u32,
    softness: f32,
    erase: u8,
    accumulate: u8,
    selection_ptr: *const u8,
    selection_len: usize,
) -> u8 {
    if pixels_ptr.is_null() || width == 0 || height == 0 {
        return 0;
    }
    if points_ptr.is_null() || points_len < 4 {
        return 0;
    }
    let pixel_count = (width as usize).saturating_mul(height as usize);
    if pixel_count == 0 || pixels_len < pixel_count {
        return 0;
    }
    let points = unsafe { std::slice::from_raw_parts(points_ptr, points_len) };
    let point_count = points_len / 4;
    if point_count == 0 {
        return 0;
    }

    let selection = if selection_ptr.is_null() || selection_len == 0 {
        None
    } else {
        Some(unsafe { std::slice::from_raw_parts(selection_ptr, selection_len) })
    };

    let mut brush_points: Vec<BrushPoint> = Vec::with_capacity(point_count);
    for i in 0..point_count {
        let idx = i * 4;
        let x = points[idx];
        let y = points[idx + 1];
        let radius = points[idx + 2];
        let alpha = points[idx + 3];
        if !x.is_finite() || !y.is_finite() || !radius.is_finite() {
            continue;
        }
        if radius <= 0.0 {
            continue;
        }
        let point_alpha = if alpha.is_finite() {
            alpha.clamp(0.0, 1.0)
        } else {
            0.0
        };
        if point_alpha <= 0.0 {
            continue;
        }
        brush_points.push(BrushPoint {
            x,
            y,
            radius,
            alpha: point_alpha,
            rot_sin: 0.0,
            rot_cos: 1.0,
        });
    }
    if brush_points.is_empty() {
        return 1;
    }
    draw_points_sampled(
        pixels_ptr,
        pixels_len,
        width,
        height,
        &brush_points,
        color_argb,
        brush_shape,
        antialias_level,
        softness,
        erase,
        accumulate != 0,
        selection_ptr,
        selection_len,
        None,
        ScreentoneSettings::disabled(),
    )
}

#[derive(Clone, Copy)]
struct StrokeSample {
    x: f32,
    y: f32,
    r: f32,
}

fn streamline_turning_angle(prev: StrokeSample, curr: StrokeSample, next: StrokeSample) -> f32 {
    let v1x = curr.x - prev.x;
    let v1y = curr.y - prev.y;
    let v2x = next.x - curr.x;
    let v2y = next.y - curr.y;
    let len1 = (v1x * v1x + v1y * v1y).sqrt();
    let len2 = (v2x * v2x + v2y * v2y).sqrt();
    if len1 <= 1.0e-6 || len2 <= 1.0e-6 {
        return 0.0;
    }
    let cos = ((v1x * v2x + v1y * v2y) / (len1 * len2)).clamp(-1.0, 1.0);
    cos.acos()
}

fn streamline_point_distance(a: StrokeSample, b: StrokeSample) -> f32 {
    let dx = a.x - b.x;
    let dy = a.y - b.y;
    (dx * dx + dy * dy).sqrt()
}

fn streamline_catmull_rom(
    p0: StrokeSample,
    p1: StrokeSample,
    p2: StrokeSample,
    p3: StrokeSample,
    t: f32,
) -> StrokeSample {
    let t = if t.is_finite() {
        t.clamp(0.0, 1.0)
    } else {
        0.0
    };
    let t2 = t * t;
    let t3 = t2 * t;
    let x = 0.5
        * ((2.0 * p1.x)
            + (-p0.x + p2.x) * t
            + (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2
            + (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3);
    let y = 0.5
        * ((2.0 * p1.y)
            + (-p0.y + p2.y) * t
            + (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2
            + (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3);
    StrokeSample { x, y, r: p1.r }
}

fn streamline_resample(samples: &[StrokeSample], target_count: usize) -> Vec<StrokeSample> {
    if samples.len() < 2 || target_count < 2 {
        return samples.to_vec();
    }

    let mut turning: Vec<f32> = vec![0.0; samples.len()];
    for i in 1..samples.len().saturating_sub(1) {
        turning[i] = streamline_turning_angle(samples[i - 1], samples[i], samples[i + 1]);
    }

    let curvature_weight = 0.75f32;
    let mut weights: Vec<f32> = Vec::with_capacity(samples.len().saturating_sub(1));
    let mut total_weight = 0.0f32;
    for i in 0..samples.len().saturating_sub(1) {
        let length = streamline_point_distance(samples[i], samples[i + 1]);
        let mut curvature = 0.0f32;
        let mut count = 0.0f32;
        if i > 0 {
            curvature += turning[i];
            count += 1.0;
        }
        if i + 1 < samples.len().saturating_sub(1) {
            curvature += turning[i + 1];
            count += 1.0;
        }
        if count > 0.0 {
            curvature /= count;
        }
        let weight = (length * (1.0 + curvature_weight * curvature)).max(1.0e-4);
        weights.push(weight);
        total_weight += weight;
    }
    if !total_weight.is_finite() || total_weight <= 0.0 {
        return samples.to_vec();
    }

    let mut output: Vec<StrokeSample> = Vec::with_capacity(target_count);
    output.push(samples[0]);

    let step = total_weight / (target_count.saturating_sub(1) as f32);
    if !step.is_finite() || step <= 0.0 {
        return samples.to_vec();
    }

    let mut seg_index = 0usize;
    let mut seg_start = 0.0f32;
    let mut seg_end = weights[0];

    for sample_idx in 1..target_count.saturating_sub(1) {
        let target = step * sample_idx as f32;
        while target > seg_end && seg_index + 1 < weights.len() {
            seg_index += 1;
            seg_start = seg_end;
            seg_end += weights[seg_index];
        }

        let denom = (seg_end - seg_start).max(1.0e-6);
        let t = ((target - seg_start) / denom).clamp(0.0, 1.0);

        let p0 = if seg_index == 0 {
            samples[0]
        } else {
            samples[seg_index - 1]
        };
        let p1 = samples[seg_index];
        let p2 = samples[seg_index + 1];
        let p3 = if seg_index + 2 < samples.len() {
            samples[seg_index + 2]
        } else {
            samples[samples.len() - 1]
        };
        let mut pos = streamline_catmull_rom(p0, p1, p2, p3, t);
        pos.r = p1.r + (p2.r - p1.r) * t;
        output.push(pos);
    }

    output.push(samples[samples.len() - 1]);
    output
}

fn apply_streamline_samples(samples: &[StrokeSample], strength: f32) -> Vec<StrokeSample> {
    let strength = if strength.is_finite() {
        strength.clamp(0.0, 1.0)
    } else {
        0.0
    };
    if strength <= 0.0001 || samples.len() < 3 {
        return samples.to_vec();
    }
    let eased = strength.powf(0.7);
    let passes = ((eased * 2.0).ceil() as usize).clamp(1, 3);
    let mut smoothed = streamline_resample(samples, samples.len());
    for _ in 1..passes {
        smoothed = streamline_resample(&smoothed, smoothed.len());
    }
    if smoothed.len() != samples.len() {
        return samples.to_vec();
    }
    let mut output: Vec<StrokeSample> = Vec::with_capacity(samples.len());
    for (orig, smooth) in samples.iter().zip(smoothed.iter()) {
        let x = orig.x + (smooth.x - orig.x) * eased;
        let y = orig.y + (smooth.y - orig.y) * eased;
        let blended_r = orig.r + (smooth.r - orig.r) * (eased * 0.5);
        let r = if blended_r.is_finite() {
            blended_r
        } else {
            orig.r
        };
        output.push(StrokeSample { x, y, r });
    }
    output
}

#[no_mangle]
pub extern "C" fn cpu_brush_apply_streamline(
    samples_ptr: *mut f32,
    samples_len: usize,
    strength: f32,
) -> u8 {
    if samples_ptr.is_null() || samples_len < 6 || samples_len % 3 != 0 {
        return 0;
    }
    let count = samples_len / 3;
    if count < 2 {
        return 0;
    }
    let slice = unsafe { std::slice::from_raw_parts_mut(samples_ptr, samples_len) };
    let mut samples: Vec<StrokeSample> = Vec::with_capacity(count);
    for i in 0..count {
        let idx = i * 3;
        samples.push(StrokeSample {
            x: slice[idx],
            y: slice[idx + 1],
            r: slice[idx + 2],
        });
    }
    let smoothed = apply_streamline_samples(&samples, strength);
    if smoothed.len() != samples.len() {
        return 0;
    }
    for i in 0..count {
        let idx = i * 3;
        slice[idx] = smoothed[i].x;
        slice[idx + 1] = smoothed[i].y;
        slice[idx + 2] = smoothed[i].r;
    }
    1
}
