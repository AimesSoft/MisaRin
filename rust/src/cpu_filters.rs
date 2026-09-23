const ANTIALIAS_CENTER_WEIGHT: i32 = 4;
const ANTIALIAS_DX: [i32; 8] = [-1, 0, 1, -1, 1, -1, 0, 1];
const ANTIALIAS_DY: [i32; 8] = [-1, -1, -1, 0, 0, 1, 1, 1];
const ANTIALIAS_WEIGHTS: [i32; 8] = [1, 2, 1, 2, 2, 1, 2, 1];

static ANTIALIAS_PROFILE_0: [f32; 1] = [0.25];
static ANTIALIAS_PROFILE_1: [f32; 2] = [0.35, 0.35];
static ANTIALIAS_PROFILE_2: [f32; 3] = [0.45, 0.5, 0.5];
static ANTIALIAS_PROFILE_3: [f32; 4] = [0.6, 0.65, 0.7, 0.75];
static ANTIALIAS_PROFILE_4: [f32; 5] = [0.6, 0.65, 0.7, 0.75, 0.8];
static ANTIALIAS_PROFILE_5: [f32; 5] = [0.65, 0.7, 0.75, 0.8, 0.85];
static ANTIALIAS_PROFILE_6: [f32; 5] = [0.7, 0.75, 0.8, 0.85, 0.9];
static ANTIALIAS_PROFILE_7: [f32; 6] = [0.7, 0.75, 0.8, 0.85, 0.9, 0.9];
static ANTIALIAS_PROFILE_8: [f32; 6] = [0.75, 0.8, 0.85, 0.9, 0.9, 0.9];
static ANTIALIAS_PROFILE_9: [f32; 6] = [0.8, 0.85, 0.9, 0.9, 0.9, 0.9];

static ANTIALIAS_PROFILES: [&[f32]; 10] = [
    &ANTIALIAS_PROFILE_0,
    &ANTIALIAS_PROFILE_1,
    &ANTIALIAS_PROFILE_2,
    &ANTIALIAS_PROFILE_3,
    &ANTIALIAS_PROFILE_4,
    &ANTIALIAS_PROFILE_5,
    &ANTIALIAS_PROFILE_6,
    &ANTIALIAS_PROFILE_7,
    &ANTIALIAS_PROFILE_8,
    &ANTIALIAS_PROFILE_9,
];

const EDGE_DETECT_MIN: f32 = 0.015;
const EDGE_DETECT_MAX: f32 = 0.4;
const EDGE_SMOOTH_STRENGTH: f32 = 1.0;
const EDGE_SMOOTH_GAMMA: f32 = 0.55;

const GAUSSIAN_KERNEL_5X5: [i32; 25] = [
    1, 4, 6, 4, 1, 4, 16, 24, 16, 4, 6, 24, 36, 24, 6, 4, 16, 24, 16, 4, 1, 4, 6, 4, 1,
];

fn clamp_u8(value: i32) -> u8 {
    if value <= 0 {
        0
    } else if value >= 255 {
        255
    } else {
        value as u8
    }
}

fn antialias_pass(src: &[u32], dest: &mut [u32], width: usize, height: usize, factor: f32) -> bool {
    dest.copy_from_slice(src);
    if factor <= 0.0 {
        return false;
    }
    let factor = factor.clamp(0.0, 1.0);
    let mut modified = false;
    for y in 0..height {
        let row_offset = y * width;
        for x in 0..width {
            let index = row_offset + x;
            let center = src[index];
            let alpha = ((center >> 24) & 0xff) as i32;
            let center_r = ((center >> 16) & 0xff) as i32;
            let center_g = ((center >> 8) & 0xff) as i32;
            let center_b = (center & 0xff) as i32;

            let mut total_weight = ANTIALIAS_CENTER_WEIGHT;
            let mut weighted_alpha = alpha * ANTIALIAS_CENTER_WEIGHT;
            let mut weighted_premul_r = (center_r * alpha * ANTIALIAS_CENTER_WEIGHT) as i64;
            let mut weighted_premul_g = (center_g * alpha * ANTIALIAS_CENTER_WEIGHT) as i64;
            let mut weighted_premul_b = (center_b * alpha * ANTIALIAS_CENTER_WEIGHT) as i64;

            for i in 0..ANTIALIAS_DX.len() {
                let nx = x as i32 + ANTIALIAS_DX[i];
                let ny = y as i32 + ANTIALIAS_DY[i];
                if nx < 0 || ny < 0 || nx >= width as i32 || ny >= height as i32 {
                    continue;
                }
                let neighbor = src[ny as usize * width + nx as usize];
                let neighbor_alpha = ((neighbor >> 24) & 0xff) as i32;
                let weight = ANTIALIAS_WEIGHTS[i];
                total_weight += weight;
                if neighbor_alpha == 0 {
                    continue;
                }
                weighted_alpha += neighbor_alpha * weight;
                let nr = ((neighbor >> 16) & 0xff) as i32;
                let ng = ((neighbor >> 8) & 0xff) as i32;
                let nb = (neighbor & 0xff) as i32;
                weighted_premul_r += (nr * neighbor_alpha * weight) as i64;
                weighted_premul_g += (ng * neighbor_alpha * weight) as i64;
                weighted_premul_b += (nb * neighbor_alpha * weight) as i64;
            }

            if total_weight <= 0 {
                continue;
            }
            let mut candidate_alpha = weighted_alpha / total_weight;
            if candidate_alpha < 0 {
                candidate_alpha = 0;
            } else if candidate_alpha > 255 {
                candidate_alpha = 255;
            }
            let delta_alpha = candidate_alpha - alpha;
            if delta_alpha == 0 {
                continue;
            }

            let delta = (delta_alpha as f32 * factor).round() as i32;
            let mut new_alpha = alpha + delta;
            if new_alpha < 0 {
                new_alpha = 0;
            } else if new_alpha > 255 {
                new_alpha = 255;
            }
            if new_alpha == alpha {
                continue;
            }

            let mut new_r = center_r;
            let mut new_g = center_g;
            let mut new_b = center_b;
            if delta_alpha > 0 {
                let denom = weighted_alpha.max(1) as i64;
                new_r = (weighted_premul_r / denom).clamp(0, 255) as i32;
                new_g = (weighted_premul_g / denom).clamp(0, 255) as i32;
                new_b = (weighted_premul_b / denom).clamp(0, 255) as i32;
            }

            dest[index] = ((new_alpha as u32) << 24)
                | ((new_r as u32) << 16)
                | ((new_g as u32) << 8)
                | (new_b as u32);
            modified = true;
        }
    }
    modified
}

fn compute_luma(color: u32) -> f32 {
    let alpha = ((color >> 24) & 0xff) as i32;
    if alpha == 0 {
        return 0.0;
    }
    let r = ((color >> 16) & 0xff) as f32;
    let g = ((color >> 8) & 0xff) as f32;
    let b = (color & 0xff) as f32;
    (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
}

fn edge_gradient(src: &[u32], width: usize, height: usize, x: usize, y: usize) -> f32 {
    let index = y * width + x;
    let center = src[index];
    let alpha = ((center >> 24) & 0xff) as i32;
    if alpha == 0 {
        return 0.0;
    }
    let center_luma = compute_luma(center);
    let mut max_diff = 0.0;

    let mut accumulate = |nx: i32, ny: i32| {
        if nx < 0 || ny < 0 || nx >= width as i32 || ny >= height as i32 {
            return;
        }
        let neighbor = src[ny as usize * width + nx as usize];
        let neighbor_alpha = ((neighbor >> 24) & 0xff) as i32;
        if neighbor_alpha == 0 {
            return;
        }
        let diff = (center_luma - compute_luma(neighbor)).abs();
        if diff > max_diff {
            max_diff = diff;
        }
    };

    let x = x as i32;
    let y = y as i32;
    accumulate(x - 1, y);
    accumulate(x + 1, y);
    accumulate(x, y - 1);
    accumulate(x, y + 1);
    accumulate(x - 1, y - 1);
    accumulate(x + 1, y - 1);
    accumulate(x - 1, y + 1);
    accumulate(x + 1, y + 1);
    max_diff
}

fn edge_smooth_weight(gradient: f32) -> f32 {
    if gradient <= EDGE_DETECT_MIN {
        return 0.0;
    }
    let normalized =
        ((gradient - EDGE_DETECT_MIN) / (EDGE_DETECT_MAX - EDGE_DETECT_MIN)).clamp(0.0, 1.0);
    normalized.powf(EDGE_SMOOTH_GAMMA) * EDGE_SMOOTH_STRENGTH
}

fn lerp_argb(a: u32, b: u32, t: f32) -> u32 {
    let clamped_t = t.clamp(0.0, 1.0);
    let lerp_channel = |ca: i32, cb: i32| -> u8 {
        let v = ca as f32 + (cb - ca) as f32 * clamped_t;
        clamp_u8(v.round() as i32)
    };

    let a_a = ((a >> 24) & 0xff) as i32;
    let a_r = ((a >> 16) & 0xff) as i32;
    let a_g = ((a >> 8) & 0xff) as i32;
    let a_b = (a & 0xff) as i32;

    let b_a = ((b >> 24) & 0xff) as i32;
    let b_r = ((b >> 16) & 0xff) as i32;
    let b_g = ((b >> 8) & 0xff) as i32;
    let b_b = (b & 0xff) as i32;

    let out_a = lerp_channel(a_a, b_a);
    let out_r = lerp_channel(a_r, b_r);
    let out_g = lerp_channel(a_g, b_g);
    let out_b = lerp_channel(a_b, b_b);
    ((out_a as u32) << 24) | ((out_r as u32) << 16) | ((out_g as u32) << 8) | (out_b as u32)
}

fn gaussian_blur(src: &[u32], dest: &mut [u32], width: usize, height: usize) {
    for y in 0..height {
        for x in 0..width {
            let mut weighted_alpha = 0.0f32;
            let mut weighted_r = 0.0f32;
            let mut weighted_g = 0.0f32;
            let mut weighted_b = 0.0f32;
            let mut total_weight = 0.0f32;
            let mut kernel_index = 0usize;
            for ky in -2..=2 {
                let ny = (y as i32 + ky).clamp(0, height as i32 - 1) as usize;
                let row_offset = ny * width;
                for kx in -2..=2 {
                    let nx = (x as i32 + kx).clamp(0, width as i32 - 1) as usize;
                    let weight = GAUSSIAN_KERNEL_5X5[kernel_index] as f32;
                    kernel_index += 1;
                    let sample = src[row_offset + nx];
                    let alpha = ((sample >> 24) & 0xff) as f32;
                    if alpha == 0.0 {
                        continue;
                    }
                    total_weight += weight;
                    weighted_alpha += alpha * weight;
                    weighted_r += ((sample >> 16) & 0xff) as f32 * alpha * weight;
                    weighted_g += ((sample >> 8) & 0xff) as f32 * alpha * weight;
                    weighted_b += (sample & 0xff) as f32 * alpha * weight;
                }
            }
            if total_weight == 0.0 {
                dest[y * width + x] = src[y * width + x];
                continue;
            }
            let normalized_alpha = weighted_alpha / total_weight;
            let premul_alpha = weighted_alpha.max(1.0);
            let out_alpha = clamp_u8(normalized_alpha.round() as i32);
            let out_r = clamp_u8((weighted_r / premul_alpha).round() as i32);
            let out_g = clamp_u8((weighted_g / premul_alpha).round() as i32);
            let out_b = clamp_u8((weighted_b / premul_alpha).round() as i32);
            dest[y * width + x] = ((out_alpha as u32) << 24)
                | ((out_r as u32) << 16)
                | ((out_g as u32) << 8)
                | (out_b as u32);
        }
    }
}

fn edge_smooth_pass(
    src: &[u32],
    dest: &mut [u32],
    blur_buffer: &mut [u32],
    width: usize,
    height: usize,
) -> bool {
    gaussian_blur(src, blur_buffer, width, height);
    let mut modified = false;
    for y in 0..height {
        let row_offset = y * width;
        for x in 0..width {
            let index = row_offset + x;
            let base_color = src[index];
            let alpha = ((base_color >> 24) & 0xff) as i32;
            if alpha == 0 {
                dest[index] = base_color;
                continue;
            }
            let gradient = edge_gradient(src, width, height, x, y);
            let weight = edge_smooth_weight(gradient);
            if weight <= 0.0 {
                dest[index] = base_color;
                continue;
            }
            let blurred = blur_buffer[index];
            let new_color = lerp_argb(base_color, blurred, weight);
            dest[index] = new_color;
            if new_color != base_color {
                modified = true;
            }
        }
    }
    modified
}

#[no_mangle]
pub extern "C" fn cpu_filters_apply_antialias(
    pixels: *mut u32,
    pixels_len: u64,
    width: u32,
    height: u32,
    level: u32,
    preview_only: u8,
) -> u8 {
    if pixels.is_null() || pixels_len == 0 || width == 0 || height == 0 {
        return 0;
    }
    let expected_len = width as u64 * height as u64;
    if expected_len != pixels_len {
        return 0;
    }
    let len = pixels_len as usize;
    let pixels_slice = unsafe { std::slice::from_raw_parts_mut(pixels, len) };
    if len == 0 {
        return 0;
    }

    let level = level.min(9) as usize;
    let profile = match ANTIALIAS_PROFILES.get(level) {
        Some(p) => *p,
        None => return 0,
    };
    if profile.is_empty() {
        return 0;
    }

    let preview_only = preview_only != 0;
    let width = width as usize;
    let height = height as usize;

    let mut buffer_a = Vec::with_capacity(len);
    buffer_a.extend_from_slice(pixels_slice);
    let mut buffer_b = vec![0u32; len];
    let mut src_is_a = true;
    let mut any_change = false;

    for &factor in profile {
        if factor <= 0.0 {
            continue;
        }
        let (src, dest) = if src_is_a {
            (&buffer_a[..], &mut buffer_b[..])
        } else {
            (&buffer_b[..], &mut buffer_a[..])
        };
        let modified = antialias_pass(src, dest, width, height, factor);
        if !modified {
            continue;
        }
        if preview_only {
            return 1;
        }
        any_change = true;
        src_is_a = !src_is_a;
    }

    let mut blur_buffer = vec![0u32; len];
    let (src, dest) = if src_is_a {
        (&buffer_a[..], &mut buffer_b[..])
    } else {
        (&buffer_b[..], &mut buffer_a[..])
    };
    let color_changed = edge_smooth_pass(src, dest, &mut blur_buffer, width, height);
    if color_changed {
        if preview_only {
            return 1;
        }
        any_change = true;
        src_is_a = !src_is_a;
    }

    if !any_change {
        return 0;
    }
    if preview_only {
        return 1;
    }
    let final_buf = if src_is_a { &buffer_a } else { &buffer_b };
    pixels_slice.copy_from_slice(final_buf);
    1
}

const FILTER_TYPE_HUE_SATURATION: u32 = 0;
const FILTER_TYPE_BRIGHTNESS_CONTRAST: u32 = 1;
const FILTER_TYPE_BLACK_WHITE: u32 = 2;
const FILTER_TYPE_GAUSSIAN_BLUR: u32 = 3;
const FILTER_TYPE_LEAK_REMOVAL: u32 = 4;
const FILTER_TYPE_LINE_NARROW: u32 = 5;
const FILTER_TYPE_FILL_EXPAND: u32 = 6;
const FILTER_TYPE_BINARIZE: u32 = 7;
const FILTER_TYPE_SCAN_PAPER_DRAWING: u32 = 8;
const FILTER_TYPE_INVERT: u32 = 9;

const BLACK_WHITE_MIN_RANGE: f32 = 1.0;
const GAUSSIAN_BLUR_MAX_RADIUS: f32 = 1000.0;
const LEAK_REMOVAL_MAX_RADIUS: i32 = 20;
const MORPHOLOGY_MAX_RADIUS: i32 = 20;
const DEFAULT_BINARIZE_ALPHA_THRESHOLD: i32 = 128;
const SCAN_PAPER_WHITE_MAX_THRESHOLD: i32 = 190;
const SCAN_PAPER_WHITE_DELTA_THRESHOLD: i32 = 90;
const SCAN_PAPER_COLOR_DISTANCE_THRESHOLD_SQ: i32 = 180 * 180;
const SCAN_PAPER_BLACK_DISTANCE_THRESHOLD_SQ: i32 = 320 * 320;

fn clamp_index(value: i32, max: i32) -> i32 {
    if max <= 0 {
        return 0;
    }
    if value < 0 {
        0
    } else if value >= max {
        max - 1
    } else {
        value
    }
}

fn round_channel(value: f32) -> u8 {
    clamp_u8(value.round() as i32)
}

fn multiply_channel_by_alpha(channel: u8, alpha: u8) -> u8 {
    ((channel as u32 * alpha as u32 + 127) / 255) as u8
}

fn unmultiply_channel_by_alpha(channel: u8, alpha: u8) -> u8 {
    if alpha == 0 {
        return 0;
    }
    let value = ((channel as u32 * 255) + ((alpha as u32) >> 1)) / alpha as u32;
    if value > 255 {
        255
    } else {
        value as u8
    }
}

fn rgb_to_hsv(r: u8, g: u8, b: u8) -> (f32, f32, f32) {
    let rf = r as f32 / 255.0;
    let gf = g as f32 / 255.0;
    let bf = b as f32 / 255.0;
    let max = rf.max(gf).max(bf);
    let min = rf.min(gf).min(bf);
    let delta = max - min;
    let mut hue = if delta <= 0.0 {
        0.0
    } else if (max - rf).abs() < f32::EPSILON {
        60.0 * (((gf - bf) / delta) % 6.0)
    } else if (max - gf).abs() < f32::EPSILON {
        60.0 * (((bf - rf) / delta) + 2.0)
    } else {
        60.0 * (((rf - gf) / delta) + 4.0)
    };
    if hue < 0.0 {
        hue += 360.0;
    }
    let saturation = if max <= 0.0 { 0.0 } else { delta / max };
    (hue, saturation, max)
}

fn hsv_to_rgb(h: f32, s: f32, v: f32) -> (u8, u8, u8) {
    if s <= 0.0 {
        let value = round_channel(v * 255.0);
        return (value, value, value);
    }
    let hh = (h % 360.0 + 360.0) % 360.0;
    let c = v * s;
    let x = c * (1.0 - ((hh / 60.0) % 2.0 - 1.0).abs());
    let m = v - c;
    let (r1, g1, b1) = if hh < 60.0 {
        (c, x, 0.0)
    } else if hh < 120.0 {
        (x, c, 0.0)
    } else if hh < 180.0 {
        (0.0, c, x)
    } else if hh < 240.0 {
        (0.0, x, c)
    } else if hh < 300.0 {
        (x, 0.0, c)
    } else {
        (c, 0.0, x)
    };
    (
        round_channel((r1 + m) * 255.0),
        round_channel((g1 + m) * 255.0),
        round_channel((b1 + m) * 255.0),
    )
}

fn apply_hue_saturation(
    pixels: &mut [u8],
    hue_delta: f32,
    saturation_percent: f32,
    lightness_percent: f32,
) {
    let sat_delta = saturation_percent / 100.0;
    let val_delta = lightness_percent / 100.0;
    for chunk in pixels.chunks_exact_mut(4) {
        let alpha = chunk[3];
        if alpha == 0 {
            continue;
        }
        let (mut hue, mut sat, mut val) = rgb_to_hsv(chunk[0], chunk[1], chunk[2]);
        hue = (hue + hue_delta) % 360.0;
        if hue < 0.0 {
            hue += 360.0;
        }
        sat = (sat + sat_delta).clamp(0.0, 1.0);
        val = (val + val_delta).clamp(0.0, 1.0);
        let (r, g, b) = hsv_to_rgb(hue, sat, val);
        chunk[0] = r;
        chunk[1] = g;
        chunk[2] = b;
    }
}

fn apply_brightness_contrast(pixels: &mut [u8], brightness_percent: f32, contrast_percent: f32) {
    let brightness_offset = brightness_percent / 100.0 * 255.0;
    let contrast_factor = (1.0 + contrast_percent / 100.0).max(0.0);
    for chunk in pixels.chunks_exact_mut(4) {
        let alpha = chunk[3];
        if alpha == 0 {
            continue;
        }
        for channel in &mut chunk[0..3] {
            let adjusted =
                ((*channel as f32 - 128.0) * contrast_factor + 128.0 + brightness_offset)
                    .clamp(0.0, 255.0);
            *channel = round_channel(adjusted);
        }
    }
}

fn apply_black_white(pixels: &mut [u8], black_point: f32, white_point: f32, mid_tone: f32) {
    let black = black_point.clamp(0.0, 100.0) / 100.0;
    let white = white_point.clamp(0.0, 100.0) / 100.0;
    let safe_white = (black + (BLACK_WHITE_MIN_RANGE / 100.0)).max(white);
    let inv_range = 1.0 / (safe_white - black).max(0.0001);
    let gamma = 2.0_f32.powf(mid_tone / 100.0);
    for chunk in pixels.chunks_exact_mut(4) {
        let alpha = chunk[3];
        if alpha == 0 {
            continue;
        }
        let luminance =
            (chunk[0] as f32 * 0.299 + chunk[1] as f32 * 0.587 + chunk[2] as f32 * 0.114) / 255.0;
        let mut normalized = ((luminance - black) * inv_range).clamp(0.0, 1.0);
        normalized = normalized.powf(gamma).clamp(0.0, 1.0);
        let gray = round_channel(normalized * 255.0);
        chunk[0] = gray;
        chunk[1] = gray;
        chunk[2] = gray;
    }
}

fn apply_binarize(pixels: &mut [u8], threshold: i32) {
    let clamped = threshold.clamp(0, 255) as u8;
    for chunk in pixels.chunks_exact_mut(4) {
        let alpha = chunk[3];
        if alpha == 0 {
            continue;
        }
        if alpha >= clamped {
            if alpha != 255 {
                chunk[3] = 255;
            }
            continue;
        }
        if chunk[0] != 0 || chunk[1] != 0 || chunk[2] != 0 {
            chunk[0] = 0;
            chunk[1] = 0;
            chunk[2] = 0;
        }
        if alpha != 0 {
            chunk[3] = 0;
        }
    }
}

fn apply_invert(pixels: &mut [u8]) {
    for chunk in pixels.chunks_exact_mut(4) {
        if chunk[3] == 0 {
            continue;
        }
        chunk[0] = 255 - chunk[0];
        chunk[1] = 255 - chunk[1];
        chunk[2] = 255 - chunk[2];
    }
}

fn gaussian_blur_sigma_for_radius(radius: f32) -> f32 {
    let clamped = radius.clamp(0.0, GAUSSIAN_BLUR_MAX_RADIUS);
    if clamped <= 0.0 {
        return 0.0;
    }
    (clamped * 0.5).max(0.1)
}

fn filter_compute_box_sizes(sigma: f32, box_count: i32) -> Vec<i32> {
    let ideal_width = (12.0 * sigma * sigma / box_count as f32 + 1.0).sqrt();
    let mut lower_width = ideal_width.floor() as i32;
    if lower_width % 2 == 0 {
        lower_width = (lower_width - 1).max(1);
    }
    if lower_width < 1 {
        lower_width = 1;
    }
    let upper_width = lower_width + 2;
    let m_ideal = (12.0 * sigma * sigma
        - box_count as f32 * lower_width as f32 * lower_width as f32
        - 4.0 * box_count as f32 * lower_width as f32
        - 3.0 * box_count as f32)
        / (-4.0 * lower_width as f32 - 4.0);
    let m = m_ideal.round() as i32;
    let clamped_m = m.clamp(0, box_count);
    (0..box_count)
        .map(|i| {
            if i < clamped_m {
                lower_width
            } else {
                upper_width
            }
        })
        .collect()
}

fn filter_box_blur_pass(
    source: &[u8],
    destination: &mut [u8],
    width: usize,
    height: usize,
    radius: usize,
    horizontal: bool,
) {
    if radius == 0 {
        destination.copy_from_slice(source);
        return;
    }
    let kernel_size = (radius * 2 + 1) as f32;
    if horizontal {
        for y in 0..height {
            let row_offset = y * width;
            let mut sum_r = 0i32;
            let mut sum_g = 0i32;
            let mut sum_b = 0i32;
            let mut sum_a = 0i32;
            for k in -(radius as i32)..=(radius as i32) {
                let sample_x = clamp_index(k, width as i32) as usize;
                let sample_index = ((row_offset + sample_x) << 2) as usize;
                sum_r += source[sample_index] as i32;
                sum_g += source[sample_index + 1] as i32;
                sum_b += source[sample_index + 2] as i32;
                sum_a += source[sample_index + 3] as i32;
            }
            for x in 0..width {
                let dest_index = ((row_offset + x) << 2) as usize;
                destination[dest_index] = round_channel(sum_r as f32 / kernel_size);
                destination[dest_index + 1] = round_channel(sum_g as f32 / kernel_size);
                destination[dest_index + 2] = round_channel(sum_b as f32 / kernel_size);
                destination[dest_index + 3] = round_channel(sum_a as f32 / kernel_size);
                let remove_x = x as i32 - radius as i32;
                let add_x = x as i32 + radius as i32 + 1;
                let remove_index =
                    ((row_offset + clamp_index(remove_x, width as i32) as usize) << 2) as usize;
                let add_index =
                    ((row_offset + clamp_index(add_x, width as i32) as usize) << 2) as usize;
                sum_r += source[add_index] as i32 - source[remove_index] as i32;
                sum_g += source[add_index + 1] as i32 - source[remove_index + 1] as i32;
                sum_b += source[add_index + 2] as i32 - source[remove_index + 2] as i32;
                sum_a += source[add_index + 3] as i32 - source[remove_index + 3] as i32;
            }
        }
        return;
    }
    for x in 0..width {
        let mut sum_r = 0i32;
        let mut sum_g = 0i32;
        let mut sum_b = 0i32;
        let mut sum_a = 0i32;
        for k in -(radius as i32)..=(radius as i32) {
            let sample_y = clamp_index(k, height as i32) as usize;
            let sample_index = ((sample_y * width + x) << 2) as usize;
            sum_r += source[sample_index] as i32;
            sum_g += source[sample_index + 1] as i32;
            sum_b += source[sample_index + 2] as i32;
            sum_a += source[sample_index + 3] as i32;
        }
        for y in 0..height {
            let dest_index = ((y * width + x) << 2) as usize;
            destination[dest_index] = round_channel(sum_r as f32 / kernel_size);
            destination[dest_index + 1] = round_channel(sum_g as f32 / kernel_size);
            destination[dest_index + 2] = round_channel(sum_b as f32 / kernel_size);
            destination[dest_index + 3] = round_channel(sum_a as f32 / kernel_size);
            let remove_y = y as i32 - radius as i32;
            let add_y = y as i32 + radius as i32 + 1;
            let remove_index =
                ((clamp_index(remove_y, height as i32) as usize * width + x) << 2) as usize;
            let add_index =
                ((clamp_index(add_y, height as i32) as usize * width + x) << 2) as usize;
            sum_r += source[add_index] as i32 - source[remove_index] as i32;
            sum_g += source[add_index + 1] as i32 - source[remove_index + 1] as i32;
            sum_b += source[add_index + 2] as i32 - source[remove_index + 2] as i32;
            sum_a += source[add_index + 3] as i32 - source[remove_index + 3] as i32;
        }
    }
}

fn filter_premultiply_alpha(pixels: &mut [u8]) {
    for chunk in pixels.chunks_exact_mut(4) {
        let alpha = chunk[3];
        if alpha == 0 {
            chunk[0] = 0;
            chunk[1] = 0;
            chunk[2] = 0;
            continue;
        }
        chunk[0] = multiply_channel_by_alpha(chunk[0], alpha);
        chunk[1] = multiply_channel_by_alpha(chunk[1], alpha);
        chunk[2] = multiply_channel_by_alpha(chunk[2], alpha);
    }
}

fn filter_unpremultiply_alpha(pixels: &mut [u8]) {
    for chunk in pixels.chunks_exact_mut(4) {
        let alpha = chunk[3];
        if alpha == 0 {
            chunk[0] = 0;
            chunk[1] = 0;
            chunk[2] = 0;
            continue;
        }
        chunk[0] = unmultiply_channel_by_alpha(chunk[0], alpha);
        chunk[1] = unmultiply_channel_by_alpha(chunk[1], alpha);
        chunk[2] = unmultiply_channel_by_alpha(chunk[2], alpha);
    }
}

fn apply_gaussian_blur(pixels: &mut [u8], width: usize, height: usize, radius: f32) {
    if pixels.is_empty() || width == 0 || height == 0 {
        return;
    }
    let sigma = gaussian_blur_sigma_for_radius(radius);
    if sigma <= 0.0 {
        return;
    }
    filter_premultiply_alpha(pixels);
    let box_sizes = filter_compute_box_sizes(sigma, 3);
    let mut scratch = vec![0u8; pixels.len()];
    for size in box_sizes {
        let pass_radius = ((size - 1) >> 1).max(0) as usize;
        if pass_radius == 0 {
            continue;
        }
        filter_box_blur_pass(pixels, &mut scratch, width, height, pass_radius, true);
        filter_box_blur_pass(&scratch, pixels, width, height, pass_radius, false);
    }
    filter_unpremultiply_alpha(pixels);
}

fn build_luminance_mask_if_fully_opaque(
    pixels: &[u8],
    width: usize,
    height: usize,
) -> Option<Vec<u8>> {
    let pixel_count = width * height;
    if pixel_count == 0 {
        return None;
    }
    let mut mask = vec![0u8; pixel_count];
    let mut fully_opaque = true;
    let mut has_coverage = false;
    for i in 0..pixel_count {
        let offset = i * 4;
        let alpha = pixels[offset + 3];
        if alpha != 255 {
            fully_opaque = false;
            break;
        }
        let r = pixels[offset] as i32;
        let g = pixels[offset + 1] as i32;
        let b = pixels[offset + 2] as i32;
        let luma = ((r * 299 + g * 587 + b * 114) as f32 / 1000.0).round() as i32;
        let coverage = (255 - luma).clamp(0, 255) as u8;
        if coverage > 0 {
            has_coverage = true;
        }
        mask[i] = coverage;
    }
    if !fully_opaque || !has_coverage {
        return None;
    }
    Some(mask)
}

fn apply_morphology(pixels: &mut [u8], width: usize, height: usize, radius: i32, dilate: bool) {
    if pixels.is_empty() || width == 0 || height == 0 {
        return;
    }
    let clamped_radius = radius.clamp(1, MORPHOLOGY_MAX_RADIUS) as usize;
    let luminance_mask = build_luminance_mask_if_fully_opaque(pixels, width, height);
    let preserve_alpha = luminance_mask.is_some();
    let mut scratch = vec![0u8; pixels.len()];
    let mut src: Vec<u8> = pixels.to_vec();
    let mut dest: Vec<u8> = scratch;

    for _ in 0..clamped_radius {
        for y in 0..height {
            let row_offset = y * width;
            for x in 0..width {
                let pixel_index = row_offset + x;
                let mut best_offset = pixel_index * 4;
                let mut best_alpha = if let Some(mask) = &luminance_mask {
                    mask[pixel_index]
                } else {
                    src[best_offset + 3]
                };

                for dy in -1..=1 {
                    let ny = y as i32 + dy;
                    if ny < 0 || ny >= height as i32 {
                        continue;
                    }
                    let neighbor_row = ny as usize * width;
                    for dx in -1..=1 {
                        let nx = x as i32 + dx;
                        if nx < 0 || nx >= width as i32 {
                            continue;
                        }
                        let neighbor_index = neighbor_row + nx as usize;
                        let neighbor_offset = neighbor_index * 4;
                        let neighbor_alpha = if let Some(mask) = &luminance_mask {
                            mask[neighbor_index]
                        } else {
                            src[neighbor_offset + 3]
                        };
                        if dilate {
                            if neighbor_alpha > best_alpha {
                                best_alpha = neighbor_alpha;
                                best_offset = neighbor_offset;
                            }
                        } else if neighbor_alpha < best_alpha {
                            best_alpha = neighbor_alpha;
                            best_offset = neighbor_offset;
                        }
                    }
                }

                let out_offset = (row_offset + x) * 4;
                if best_alpha == 0 {
                    if preserve_alpha {
                        dest[out_offset] = src[out_offset];
                        dest[out_offset + 1] = src[out_offset + 1];
                        dest[out_offset + 2] = src[out_offset + 2];
                        dest[out_offset + 3] = src[out_offset + 3];
                    } else {
                        dest[out_offset] = 0;
                        dest[out_offset + 1] = 0;
                        dest[out_offset + 2] = 0;
                        dest[out_offset + 3] = 0;
                    }
                } else {
                    dest[out_offset] = src[best_offset];
                    dest[out_offset + 1] = src[best_offset + 1];
                    dest[out_offset + 2] = src[best_offset + 2];
                    dest[out_offset + 3] = if preserve_alpha {
                        src[out_offset + 3]
                    } else {
                        best_alpha
                    };
                }
            }
        }
        std::mem::swap(&mut src, &mut dest);
    }
    pixels.copy_from_slice(&src);
}

fn mark_leak_background(hole_mask: &mut [u8], width: usize, height: usize) {
    if width == 0 || height == 0 {
        return;
    }
    let pixel_count = width * height;
    let mut queue: Vec<usize> = Vec::with_capacity(pixel_count);
    let mut head = 0usize;

    let mut try_enqueue = |index: usize| {
        if index >= pixel_count {
            return;
        }
        if hole_mask[index] != 1 {
            return;
        }
        hole_mask[index] = 0;
        queue.push(index);
    };

    for x in 0..width {
        try_enqueue(x);
        if height > 1 {
            try_enqueue((height - 1) * width + x);
        }
    }
    for y in 1..height.saturating_sub(1) {
        try_enqueue(y * width);
        if width > 1 {
            try_enqueue(y * width + (width - 1));
        }
    }

    while head < queue.len() {
        let index = queue[head];
        head += 1;
        let row = index / width;
        let col = index - row * width;
        if row > 0 {
            let up = index - width;
            if hole_mask[up] == 1 {
                hole_mask[up] = 0;
                queue.push(up);
            }
        }
        if row + 1 < height {
            let down = index + width;
            if hole_mask[down] == 1 {
                hole_mask[down] = 0;
                queue.push(down);
            }
        }
        if col > 0 {
            let left = index - 1;
            if hole_mask[left] == 1 {
                hole_mask[left] = 0;
                queue.push(left);
            }
        }
        if col + 1 < width {
            let right = index + 1;
            if hole_mask[right] == 1 {
                hole_mask[right] = 0;
                queue.push(right);
            }
        }
    }
}

fn clear_leak_component(component_pixels: &[usize], hole_mask: &mut [u8]) {
    for &index in component_pixels {
        hole_mask[index] = 0;
    }
}

fn is_leak_boundary_index(index: usize, width: usize, height: usize, hole_mask: &[u8]) -> bool {
    let y = index / width;
    let x = index - y * width;
    if x == 0 || x + 1 == width || y == 0 || y + 1 == height {
        return true;
    }
    if hole_mask[index - 1] != 2 {
        return true;
    }
    if hole_mask[index + 1] != 2 {
        return true;
    }
    if hole_mask[index - width] != 2 {
        return true;
    }
    if hole_mask[index + width] != 2 {
        return true;
    }
    false
}

fn is_leak_component_within_radius(
    component_pixels: &[usize],
    width: usize,
    height: usize,
    max_radius: i32,
    hole_mask: &mut [u8],
) -> bool {
    if component_pixels.is_empty() || max_radius <= 0 {
        return false;
    }
    let mut queue: std::collections::VecDeque<(usize, i32)> = std::collections::VecDeque::new();
    for &index in component_pixels {
        if is_leak_boundary_index(index, width, height, hole_mask) {
            queue.push_back((index, 0));
            hole_mask[index] = 3;
        }
    }
    if queue.is_empty() {
        for &index in component_pixels {
            if hole_mask[index] == 3 {
                hole_mask[index] = 2;
            }
        }
        return false;
    }
    let mut visited_count = 0usize;
    let mut max_distance = 0i32;
    while let Some((index, distance)) = queue.pop_front() {
        visited_count += 1;
        if distance > max_distance {
            max_distance = distance;
            if max_distance > max_radius {
                for &idx in component_pixels {
                    if hole_mask[idx] == 3 {
                        hole_mask[idx] = 2;
                    }
                }
                return false;
            }
        }
        let y = index / width;
        let x = index - y * width;
        if x > 0 {
            let left = index - 1;
            if hole_mask[left] == 2 {
                hole_mask[left] = 3;
                queue.push_back((left, distance + 1));
            }
        }
        if x + 1 < width {
            let right = index + 1;
            if hole_mask[right] == 2 {
                hole_mask[right] = 3;
                queue.push_back((right, distance + 1));
            }
        }
        if y > 0 {
            let up = index - width;
            if hole_mask[up] == 2 {
                hole_mask[up] = 3;
                queue.push_back((up, distance + 1));
            }
        }
        if y + 1 < height {
            let down = index + width;
            if hole_mask[down] == 2 {
                hole_mask[down] = 3;
                queue.push_back((down, distance + 1));
            }
        }
    }
    let fully_covered = visited_count == component_pixels.len();
    for &idx in component_pixels {
        if hole_mask[idx] == 3 {
            hole_mask[idx] = 2;
        }
    }
    fully_covered
}

fn fill_leak_component(
    pixels: &mut [u8],
    width: usize,
    height: usize,
    hole_mask: &mut [u8],
    seeds: &[usize],
) {
    if seeds.is_empty() {
        return;
    }
    let mut frontier: Vec<usize> = seeds.to_vec();
    let mut next_frontier: Vec<usize> = Vec::new();
    while !frontier.is_empty() {
        next_frontier.clear();
        for &source_index in &frontier {
            let src_offset = source_index * 4;
            let alpha = pixels[src_offset + 3];
            if alpha == 0 {
                continue;
            }
            let sy = source_index / width;
            let sx = source_index - sy * width;
            for dy in -1..=1 {
                let ny = sy as i32 + dy;
                if ny < 0 || ny >= height as i32 {
                    continue;
                }
                for dx in -1..=1 {
                    if dx == 0 && dy == 0 {
                        continue;
                    }
                    let nx = sx as i32 + dx;
                    if nx < 0 || nx >= width as i32 {
                        continue;
                    }
                    let neighbor_index = ny as usize * width + nx as usize;
                    if hole_mask[neighbor_index] != 2 {
                        continue;
                    }
                    let dest_offset = neighbor_index * 4;
                    pixels[dest_offset] = pixels[src_offset];
                    pixels[dest_offset + 1] = pixels[src_offset + 1];
                    pixels[dest_offset + 2] = pixels[src_offset + 2];
                    pixels[dest_offset + 3] = alpha;
                    hole_mask[neighbor_index] = 0;
                    next_frontier.push(neighbor_index);
                }
            }
        }
        std::mem::swap(&mut frontier, &mut next_frontier);
    }
}

fn apply_leak_removal(pixels: &mut [u8], width: usize, height: usize, radius: i32) {
    if pixels.is_empty() || width == 0 || height == 0 {
        return;
    }
    let clamped_radius = radius.clamp(0, LEAK_REMOVAL_MAX_RADIUS);
    if clamped_radius <= 0 {
        return;
    }
    let luminance_mask = build_luminance_mask_if_fully_opaque(pixels, width, height);
    let use_luminance_mask = luminance_mask.is_some();
    let pixel_count = width * height;
    let mut hole_mask = vec![0u8; pixel_count];
    let mut has_transparent = false;
    for index in 0..pixel_count {
        let offset = index * 4;
        let coverage = if let Some(mask) = &luminance_mask {
            mask[index]
        } else {
            pixels[offset + 3]
        };
        if coverage == 0 {
            hole_mask[index] = 1;
            has_transparent = true;
        }
    }
    if !has_transparent {
        return;
    }
    mark_leak_background(&mut hole_mask, width, height);
    if !hole_mask.iter().any(|&v| v == 1) {
        return;
    }
    let max_component_extent = clamped_radius * 2 + 1;
    let max_component_pixels = max_component_extent * max_component_extent;
    let mut queue: std::collections::VecDeque<usize> = std::collections::VecDeque::new();
    let mut component_pixels: Vec<usize> = Vec::new();
    let mut seeds: Vec<usize> = Vec::new();
    let mut seed_flags = vec![false; pixel_count];

    for start in 0..pixel_count {
        if hole_mask[start] != 1 {
            continue;
        }
        queue.clear();
        component_pixels.clear();
        seeds.clear();
        let mut touches_opaque = false;
        let mut component_too_large = false;
        let mut min_x = start % width;
        let mut max_x = min_x;
        let mut min_y = start / width;
        let mut max_y = min_y;
        queue.push_back(start);
        hole_mask[start] = 2;

        while let Some(index) = queue.pop_front() {
            let y = index / width;
            let x = index - y * width;

            if component_too_large {
                hole_mask[index] = 0;
            } else {
                component_pixels.push(index);
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

            if x > 0 {
                let left = index - 1;
                if hole_mask[left] == 1 {
                    hole_mask[left] = 2;
                    queue.push_back(left);
                }
            }
            if x + 1 < width {
                let right = index + 1;
                if hole_mask[right] == 1 {
                    hole_mask[right] = 2;
                    queue.push_back(right);
                }
            }
            if y > 0 {
                let up = index - width;
                if hole_mask[up] == 1 {
                    hole_mask[up] = 2;
                    queue.push_back(up);
                }
            }
            if y + 1 < height {
                let down = index + width;
                if hole_mask[down] == 1 {
                    hole_mask[down] = 2;
                    queue.push_back(down);
                }
            }

            if component_too_large {
                continue;
            }

            for dy in -1..=1 {
                let ny = y as i32 + dy;
                if ny < 0 || ny >= height as i32 {
                    continue;
                }
                for dx in -1..=1 {
                    if dx == 0 && dy == 0 {
                        continue;
                    }
                    let nx = x as i32 + dx;
                    if nx < 0 || nx >= width as i32 {
                        continue;
                    }
                    let neighbor_index = ny as usize * width + nx as usize;
                    if hole_mask[neighbor_index] == 2 {
                        continue;
                    }
                    let neighbor_offset = neighbor_index * 4;
                    let neighbor_coverage = if use_luminance_mask {
                        luminance_mask.as_ref().unwrap()[neighbor_index]
                    } else {
                        pixels[neighbor_offset + 3]
                    };
                    if neighbor_coverage == 0 {
                        continue;
                    }
                    touches_opaque = true;
                    if !seed_flags[neighbor_index] {
                        seed_flags[neighbor_index] = true;
                        seeds.push(neighbor_index);
                    }
                }
            }

            let component_width = (max_x - min_x + 1) as i32;
            let component_height = (max_y - min_y + 1) as i32;
            if component_pixels.len() as i32 > max_component_pixels
                || component_width > max_component_extent
                || component_height > max_component_extent
            {
                component_too_large = true;
                touches_opaque = false;
                for &visited in &component_pixels {
                    hole_mask[visited] = 0;
                }
                component_pixels.clear();
                for &seed in &seeds {
                    seed_flags[seed] = false;
                }
                seeds.clear();
            }
        }

        for &seed in &seeds {
            seed_flags[seed] = false;
        }

        if component_too_large {
            continue;
        }
        if component_pixels.is_empty() || seeds.is_empty() || !touches_opaque {
            clear_leak_component(&component_pixels, &mut hole_mask);
            continue;
        }
        if !is_leak_component_within_radius(
            &component_pixels,
            width,
            height,
            clamped_radius,
            &mut hole_mask,
        ) {
            clear_leak_component(&component_pixels, &mut hole_mask);
            continue;
        }
        fill_leak_component(pixels, width, height, &mut hole_mask, &seeds);
        clear_leak_component(&component_pixels, &mut hole_mask);
    }
}

fn scan_paper_map_rgb_to_argb(r: u8, g: u8, b: u8) -> u32 {
    let max_channel = r.max(g).max(b) as i32;
    let min_channel = r.min(g).min(b) as i32;
    let delta = max_channel - min_channel;
    if max_channel >= SCAN_PAPER_WHITE_MAX_THRESHOLD && delta <= SCAN_PAPER_WHITE_DELTA_THRESHOLD {
        return 0;
    }

    let r2 = r as i32 * r as i32;
    let g2 = g as i32 * g as i32;
    let b2 = b as i32 * b as i32;
    let dr = 255 - r as i32;
    let dg = 255 - g as i32;
    let db = 255 - b as i32;

    let dist_red = dr * dr + g2 + b2;
    let dist_green = r2 + dg * dg + b2;
    let dist_blue = r2 + g2 + db * db;
    let mut min_dist = dist_red;
    let mut mapped = 0xFFFF0000u32;
    if dist_green < min_dist {
        min_dist = dist_green;
        mapped = 0xFF00FF00;
    }
    if dist_blue < min_dist {
        min_dist = dist_blue;
        mapped = 0xFF0000FF;
    }
    if min_dist <= SCAN_PAPER_COLOR_DISTANCE_THRESHOLD_SQ {
        return mapped;
    }

    let dist_black = r2 + g2 + b2;
    if dist_black <= SCAN_PAPER_BLACK_DISTANCE_THRESHOLD_SQ {
        return 0xFF000000;
    }
    0
}

fn scan_paper_map_rgb_to_argb_tone(
    r: u8,
    g: u8,
    b: u8,
    black: f32,
    inv_range: f32,
    gamma: f32,
) -> u32 {
    let max_channel = r.max(g).max(b) as i32;
    let min_channel = r.min(g).min(b) as i32;
    let delta = max_channel - min_channel;

    let luminance = (r as f32 * 0.299 + g as f32 * 0.587 + b as f32 * 0.114) / 255.0;
    let mut normalized = ((luminance - black) * inv_range).clamp(0.0, 1.0);
    normalized = normalized.powf(gamma).clamp(0.0, 1.0);
    let gray = round_channel(normalized * 255.0) as i32;
    if gray >= SCAN_PAPER_WHITE_MAX_THRESHOLD && delta <= SCAN_PAPER_WHITE_DELTA_THRESHOLD {
        return 0;
    }

    let r2 = r as i32 * r as i32;
    let g2 = g as i32 * g as i32;
    let b2 = b as i32 * b as i32;
    let dr = 255 - r as i32;
    let dg = 255 - g as i32;
    let db = 255 - b as i32;

    let dist_red = dr * dr + g2 + b2;
    let dist_green = r2 + dg * dg + b2;
    let dist_blue = r2 + g2 + db * db;
    let mut min_dist = dist_red;
    let mut mapped = 0xFFFF0000u32;
    if dist_green < min_dist {
        min_dist = dist_green;
        mapped = 0xFF00FF00;
    }
    if dist_blue < min_dist {
        min_dist = dist_blue;
        mapped = 0xFF0000FF;
    }
    if min_dist <= SCAN_PAPER_COLOR_DISTANCE_THRESHOLD_SQ {
        return mapped;
    }
    let dist_black = r2 + g2 + b2;
    if dist_black <= SCAN_PAPER_BLACK_DISTANCE_THRESHOLD_SQ {
        return 0xFF000000;
    }
    0
}

fn apply_scan_paper_drawing(pixels: &mut [u8], black_point: f32, white_point: f32, mid_tone: f32) {
    let tone_mapping_enabled =
        black_point.abs() > 1e-6 || (white_point - 100.0).abs() > 1e-6 || mid_tone.abs() > 1e-6;
    let black_norm = black_point.clamp(0.0, 100.0) / 100.0;
    let white_norm = white_point.clamp(0.0, 100.0) / 100.0;
    let safe_white = (black_norm + (BLACK_WHITE_MIN_RANGE / 100.0)).max(white_norm);
    let inv_range = 1.0 / (safe_white - black_norm).max(0.0001);
    let gamma = 2.0_f32.powf(mid_tone.clamp(-100.0, 100.0) / 100.0);

    for chunk in pixels.chunks_exact_mut(4) {
        let alpha = chunk[3];
        if alpha == 0 {
            continue;
        }
        let mapped = if tone_mapping_enabled {
            scan_paper_map_rgb_to_argb_tone(
                chunk[0], chunk[1], chunk[2], black_norm, inv_range, gamma,
            )
        } else {
            scan_paper_map_rgb_to_argb(chunk[0], chunk[1], chunk[2])
        };
        if mapped == 0 {
            chunk[0] = 0;
            chunk[1] = 0;
            chunk[2] = 0;
            chunk[3] = 0;
            continue;
        }
        chunk[0] = ((mapped >> 16) & 0xff) as u8;
        chunk[1] = ((mapped >> 8) & 0xff) as u8;
        chunk[2] = (mapped & 0xff) as u8;
        chunk[3] = 255;
    }
}

#[no_mangle]
pub extern "C" fn cpu_filters_apply_filter_rgba(
    pixels: *mut u8,
    pixels_len: u64,
    width: u32,
    height: u32,
    filter_type: u32,
    param0: f32,
    param1: f32,
    param2: f32,
    param3: f32,
) -> u8 {
    if pixels.is_null() || pixels_len == 0 {
        return 0;
    }
    let len = pixels_len as usize;
    if len % 4 != 0 {
        return 0;
    }
    if width > 0 && height > 0 {
        let expected_len = width as u64 * height as u64 * 4;
        if expected_len != pixels_len {
            return 0;
        }
    }
    let pixels_slice = unsafe { std::slice::from_raw_parts_mut(pixels, len) };
    match filter_type {
        FILTER_TYPE_HUE_SATURATION => {
            apply_hue_saturation(pixels_slice, param0, param1, param2);
        }
        FILTER_TYPE_BRIGHTNESS_CONTRAST => {
            apply_brightness_contrast(pixels_slice, param0, param1);
        }
        FILTER_TYPE_BLACK_WHITE => {
            apply_black_white(pixels_slice, param0, param1, param2);
        }
        FILTER_TYPE_BINARIZE => {
            let threshold = if param0.is_finite() {
                param0.round() as i32
            } else {
                DEFAULT_BINARIZE_ALPHA_THRESHOLD
            };
            apply_binarize(pixels_slice, threshold);
        }
        FILTER_TYPE_GAUSSIAN_BLUR => {
            let w = width as usize;
            let h = height as usize;
            if w == 0 || h == 0 {
                return 0;
            }
            apply_gaussian_blur(pixels_slice, w, h, param0);
        }
        FILTER_TYPE_LEAK_REMOVAL => {
            let w = width as usize;
            let h = height as usize;
            if w == 0 || h == 0 {
                return 0;
            }
            let steps = if param0.is_finite() {
                param0.round() as i32
            } else {
                0
            };
            apply_leak_removal(pixels_slice, w, h, steps);
        }
        FILTER_TYPE_LINE_NARROW => {
            let w = width as usize;
            let h = height as usize;
            if w == 0 || h == 0 {
                return 0;
            }
            let steps = if param0.is_finite() {
                param0.round() as i32
            } else {
                0
            };
            if steps <= 0 {
                return 0;
            }
            apply_morphology(pixels_slice, w, h, steps, false);
        }
        FILTER_TYPE_FILL_EXPAND => {
            let w = width as usize;
            let h = height as usize;
            if w == 0 || h == 0 {
                return 0;
            }
            let steps = if param0.is_finite() {
                param0.round() as i32
            } else {
                0
            };
            if steps <= 0 {
                return 0;
            }
            apply_morphology(pixels_slice, w, h, steps, true);
        }
        FILTER_TYPE_SCAN_PAPER_DRAWING => {
            apply_scan_paper_drawing(pixels_slice, param0, param1, param2);
        }
        FILTER_TYPE_INVERT => {
            apply_invert(pixels_slice);
        }
        _ => {
            return 0;
        }
    }
    1
}
