use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::gpu::compositor::{GpuCompositor, LayerData};
use crate::gpu::debug::{self, LogLevel};

static GPU_COMPOSITOR: OnceLock<Mutex<Option<GpuCompositor>>> = OnceLock::new();

fn compositor_cell() -> &'static Mutex<Option<GpuCompositor>> {
    GPU_COMPOSITOR.get_or_init(|| Mutex::new(None))
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
    let mut guard = compositor_cell()
        .lock()
        .map_err(|_| "gpu compositor lock poisoned".to_string())?;
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
}

pub fn gpu_composite_layers(
    layers: Vec<GpuLayerData>,
    width: u32,
    height: u32,
) -> Result<Vec<u32>, String> {
    let seq = debug::next_seq();
    let t0 = Instant::now();

    if width == 0 || height == 0 {
        return Ok(Vec::new());
    }

    let mut guard = compositor_cell()
        .lock()
        .map_err(|_| "gpu compositor lock poisoned".to_string())?;
    if guard.is_none() {
        let result = cpu_composite_layers_impl(&layers, width, height);
        let elapsed = t0.elapsed();
        match &result {
            Ok(out) => {
                let out_len = out.len() as u64;
                if elapsed >= Duration::from_millis(50) {
                    debug::log(
                        LogLevel::Warn,
                        format_args!(
                            "#{seq} cpu_composite_layers SLOW ok out_len={out_len} in {:?}.",
                            elapsed
                        ),
                    );
                } else {
                    debug::log(
                        LogLevel::Verbose,
                        format_args!(
                            "#{seq} cpu_composite_layers ok out_len={out_len} in {:?}.",
                            elapsed
                        ),
                    );
                }
            }
            Err(err) => {
                debug::log(
                    LogLevel::Warn,
                    format_args!("#{seq} cpu_composite_layers ERR in {:?}: {err}", elapsed),
                );
            }
        }
        return result;
    }
    let compositor = guard
        .as_mut()
        .ok_or_else(|| "gpu compositor not initialized".to_string())?;

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
        LogLevel::Verbose,
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
}

#[flutter_rust_bridge::frb(sync)]
pub fn gpu_compositor_dispose() {
    if let Some(cell) = GPU_COMPOSITOR.get() {
        if let Ok(mut guard) = cell.lock() {
            *guard = None;
        }
    }
}

const EPS: f32 = 1.0e-7;

#[flutter_rust_bridge::frb]
pub fn cpu_composite_layers(
    layers: Vec<GpuLayerData>,
    width: u32,
    height: u32,
) -> Result<Vec<u32>, String> {
    cpu_composite_layers_impl(&layers, width, height)
}

fn cpu_composite_layers_impl(
    layers: &[GpuLayerData],
    width: u32,
    height: u32,
) -> Result<Vec<u32>, String> {
    let pixel_count_u64 = (width as u64).saturating_mul(height as u64);
    if pixel_count_u64 > usize::MAX as u64 {
        return Err("cpu_composite_layers: canvas too large".to_string());
    }
    let pixel_count = pixel_count_u64 as usize;
    if pixel_count == 0 {
        return Ok(Vec::new());
    }

    let expected_len = pixel_count;
    let mut layer_slices: Vec<Option<&[u32]>> = Vec::with_capacity(layers.len());
    for layer in layers {
        if layer.pixels.len() == expected_len {
            layer_slices.push(Some(layer.pixels.as_slice()));
        } else {
            layer_slices.push(None);
        }
    }

    let mut out = vec![0u32; pixel_count];
    for idx in 0..pixel_count {
        let mut dst: u32 = 0;
        let mut initialized = false;
        let mut mask_alpha: f32 = 0.0;

        for (layer_index, layer) in layers.iter().enumerate() {
            if !layer.visible {
                continue;
            }

            let opacity = clamp_unit_f64_to_f32(layer.opacity);
            if opacity <= 0.0 {
                if !layer.clipping_mask {
                    mask_alpha = 0.0;
                }
                continue;
            }

            let src = match layer_slices[layer_index] {
                Some(slice) => slice[idx],
                None => 0,
            };
            let src_a_u8 = ((src >> 24) & 0xFF) as u32;
            if src_a_u8 == 0 {
                if !layer.clipping_mask {
                    mask_alpha = 0.0;
                }
                continue;
            }

            let mut total_opacity = opacity;
            if layer.clipping_mask {
                if mask_alpha <= 0.0 {
                    continue;
                }
                total_opacity *= mask_alpha;
                if total_opacity <= 0.0 {
                    continue;
                }
            }

            let src_a = src_a_u8 as f32 / 255.0;
            let mut effective_a = src_a * total_opacity;
            if effective_a <= 0.0 {
                if !layer.clipping_mask {
                    mask_alpha = 0.0;
                }
                continue;
            }
            effective_a = clamp01(effective_a);

            if !layer.clipping_mask {
                mask_alpha = effective_a;
            }

            let effective_a_u8 = to_u8(effective_a);
            let effective_color = (effective_a_u8 << 24) | (src & 0x00FFFFFF);

            if !initialized {
                dst = effective_color;
                initialized = true;
            } else {
                dst = blend_argb(dst, effective_color, layer.blend_mode_index, idx as u32);
            }
        }

        out[idx] = if initialized { dst } else { 0 };
    }

    Ok(out)
}

fn clamp01(x: f32) -> f32 {
    if x <= 0.0 {
        return 0.0;
    }
    if x >= 1.0 {
        return 1.0;
    }
    x
}

fn to_u8(x: f32) -> u32 {
    let v = (clamp01(x) * 255.0 + 0.5).floor();
    let clamped = if v < 0.0 {
        0.0
    } else if v > 255.0 {
        255.0
    } else {
        v
    };
    clamped as u32
}

fn pack_argb(a: f32, r: f32, g: f32, b: f32) -> u32 {
    let aa = to_u8(a);
    let rr = to_u8(r);
    let gg = to_u8(g);
    let bb = to_u8(b);
    (aa << 24) | (rr << 16) | (gg << 8) | bb
}

fn unpack_a(c: u32) -> f32 {
    ((c >> 24) & 0xFF) as f32 / 255.0
}

fn unpack_r(c: u32) -> f32 {
    ((c >> 16) & 0xFF) as f32 / 255.0
}

fn unpack_g(c: u32) -> f32 {
    ((c >> 8) & 0xFF) as f32 / 255.0
}

fn unpack_b(c: u32) -> f32 {
    (c & 0xFF) as f32 / 255.0
}

fn blend_color_burn(s: f32, d: f32) -> f32 {
    if s <= EPS {
        return 0.0;
    }
    1.0 - ((1.0 - d) / s).min(1.0)
}

fn blend_color_dodge(s: f32, d: f32) -> f32 {
    if s >= 1.0 - EPS {
        return 1.0;
    }
    (d / (1.0 - s)).min(1.0)
}

fn blend_overlay(s: f32, d: f32) -> f32 {
    if d <= 0.5 {
        return 2.0 * s * d;
    }
    1.0 - 2.0 * (1.0 - s) * (1.0 - d)
}

fn blend_hard_light(s: f32, d: f32) -> f32 {
    if s <= 0.5 {
        return 2.0 * s * d;
    }
    1.0 - 2.0 * (1.0 - s) * (1.0 - d)
}

fn soft_light_lum(d: f32) -> f32 {
    if d <= 0.25 {
        return ((16.0 * d - 12.0) * d + 4.0) * d;
    }
    d.sqrt()
}

fn blend_soft_light(s: f32, d: f32) -> f32 {
    if s <= 0.5 {
        return d - (1.0 - 2.0 * s) * d * (1.0 - d);
    }
    d + (2.0 * s - 1.0) * (soft_light_lum(d) - d)
}

fn blend_vivid_light(s: f32, d: f32) -> f32 {
    if s <= 0.5 {
        if s <= EPS {
            return 0.0;
        }
        return 1.0 - ((1.0 - d) / (2.0 * s)).min(1.0);
    }
    if s >= 1.0 - EPS {
        return 1.0;
    }
    (d / (2.0 * (1.0 - s))).min(1.0)
}

fn blend_pin_light(s: f32, d: f32) -> f32 {
    if s <= 0.5 {
        return d.min(2.0 * s);
    }
    d.max(2.0 * s - 1.0)
}

fn blend_hard_mix(s: f32, d: f32) -> f32 {
    if blend_vivid_light(s, d) < 0.5 {
        return 0.0;
    }
    1.0
}

fn blend_divide(s: f32, d: f32) -> f32 {
    if s <= EPS {
        return 1.0;
    }
    clamp01(d / s)
}

fn mix_hash(hash: u32, value: u32) -> u32 {
    let mut mixed = hash ^ value;
    mixed = mixed.wrapping_mul(0x7FEB352D);
    mixed ^= mixed >> 15;
    mixed = mixed.wrapping_mul(0x846CA68B);
    mixed ^= mixed >> 16;
    mixed
}

fn pseudo_random(index: u32, src: u32, dst: u32) -> f32 {
    let mut hash = 0x9E3779B9u32;
    hash = mix_hash(hash, index);
    hash = mix_hash(hash, src);
    hash = mix_hash(hash, dst);
    hash ^= hash >> 16;
    hash as f32 / 4294967295.0
}

fn rgb_to_hsl(r: f32, g: f32, b: f32) -> (f32, f32, f32) {
    let maxc = r.max(g).max(b);
    let minc = r.min(g).min(b);
    let l = (maxc + minc) * 0.5;
    let mut h = 0.0;
    let mut s = 0.0;
    if (maxc - minc).abs() > EPS {
        let d = maxc - minc;
        if l > 0.5 {
            s = d / (2.0 - maxc - minc);
        } else {
            s = d / (maxc + minc);
        }
        if (maxc - r).abs() <= EPS {
            h = (g - b) / d;
            if g < b {
                h += 6.0;
            }
        } else if (maxc - g).abs() <= EPS {
            h = (b - r) / d + 2.0;
        } else {
            h = (r - g) / d + 4.0;
        }
        h /= 6.0;
    }
    (h, s, l)
}

fn hue_to_rgb(p: f32, q: f32, t: f32) -> f32 {
    let mut tt = t;
    if tt < 0.0 {
        tt += 1.0;
    }
    if tt > 1.0 {
        tt -= 1.0;
    }
    if tt < 1.0 / 6.0 {
        return p + (q - p) * 6.0 * tt;
    }
    if tt < 0.5 {
        return q;
    }
    if tt < 2.0 / 3.0 {
        return p + (q - p) * (2.0 / 3.0 - tt) * 6.0;
    }
    p
}

fn hsl_to_rgb(h: f32, s: f32, l: f32) -> (f32, f32, f32) {
    if s <= 0.0 {
        return (l, l, l);
    }
    let q = if l >= 0.5 {
        l + s - l * s
    } else {
        l * (1.0 + s)
    };
    let p = 2.0 * l - q;
    let r = hue_to_rgb(p, q, h + 1.0 / 3.0);
    let g = hue_to_rgb(p, q, h);
    let b = hue_to_rgb(p, q, h - 1.0 / 3.0);
    (r, g, b)
}

fn blend_channel(mode: u32, s: f32, d: f32) -> f32 {
    match mode {
        0 => s,
        1 => s * d,
        3 => s.min(d),
        4 => blend_color_burn(s, d),
        5 => clamp01(d + s - 1.0),
        7 => s.max(d),
        8 => 1.0 - (1.0 - s) * (1.0 - d),
        9 => blend_color_dodge(s, d),
        10 => clamp01(d + s),
        12 => blend_overlay(s, d),
        13 => blend_soft_light(s, d),
        14 => blend_hard_light(s, d),
        15 => blend_vivid_light(s, d),
        16 => clamp01(d + 2.0 * s - 1.0),
        17 => blend_pin_light(s, d),
        18 => blend_hard_mix(s, d),
        19 => (d - s).abs(),
        20 => d + s - 2.0 * d * s,
        21 => 0.0f32.max(d - s),
        22 => blend_divide(s, d),
        _ => s,
    }
}

fn blend_argb(dst: u32, src: u32, mode: u32, pixel_index: u32) -> u32 {
    let sa = unpack_a(src);
    if sa <= 0.0 {
        return dst;
    }

    let da = unpack_a(dst);
    let sr = unpack_r(src);
    let sg = unpack_g(src);
    let sb = unpack_b(src);
    let dr = unpack_r(dst);
    let dg = unpack_g(dst);
    let db = unpack_b(dst);

    if mode == 2 {
        let noise = pseudo_random(pixel_index, src, dst);
        if noise > sa {
            return dst;
        }
        return pack_argb(1.0, sr, sg, sb);
    }

    let mut fr = sr;
    let mut fg = sg;
    let mut fb = sb;
    if mode == 6 || mode == 11 {
        let src_sum = (sr + sg + sb) * sa;
        let dst_sum = (dr + dg + db) * da;
        let use_src = (mode == 6 && src_sum < dst_sum) || (mode == 11 && src_sum > dst_sum);
        if !use_src {
            fr = dr;
            fg = dg;
            fb = db;
        }
    } else if mode >= 23 {
        let (src_h, src_s, src_l) = rgb_to_hsl(sr, sg, sb);
        let (dst_h, dst_s, dst_l) = rgb_to_hsl(dr, dg, db);
        let (out_h, out_s, out_l) = match mode {
            23 => (src_h, dst_s, dst_l),
            24 => (dst_h, src_s, dst_l),
            25 => (src_h, src_s, dst_l),
            26 => (dst_h, dst_s, src_l),
            _ => (dst_h, dst_s, dst_l),
        };
        let (r, g, b) = hsl_to_rgb(out_h, out_s, out_l);
        fr = r;
        fg = g;
        fb = b;
    } else {
        fr = blend_channel(mode, sr, dr);
        fg = blend_channel(mode, sg, dg);
        fb = blend_channel(mode, sb, db);
    }

    let out_a = sa + da * (1.0 - sa);
    if out_a <= 0.0 {
        return 0;
    }

    let rr = ((fr * sa) + dr * da * (1.0 - sa)) / out_a;
    let rg = ((fg * sa) + dg * da * (1.0 - sa)) / out_a;
    let rb = ((fb * sa) + db * da * (1.0 - sa)) / out_a;

    pack_argb(out_a, rr, rg, rb)
}

fn color_with_opacity(src: u32, alpha: f32) -> u32 {
    let a = (clamp01(alpha) * 255.0).round();
    if a <= 0.0 {
        return 0;
    }
    let a_u8 = if a < 0.0 {
        0
    } else if a > 255.0 {
        255
    } else {
        a as u32
    };
    (a_u8 << 24) | (src & 0x00FF_FFFF)
}

fn overflow_key(x: i32, y: i32) -> i64 {
    ((x as i64) << 32) | (y as u32 as i64)
}

#[flutter_rust_bridge::frb(ignore)]
#[no_mangle]
pub extern "C" fn cpu_blend_on_canvas(
    src: *const u32,
    dst: *mut u32,
    pixels_len: u64,
    width: u32,
    height: u32,
    start_x: i32,
    end_x: i32,
    start_y: i32,
    end_y: i32,
    opacity: f32,
    blend_mode: u32,
    mask: *const u32,
    mask_len: u64,
    mask_opacity: f32,
) -> u8 {
    if src.is_null() || dst.is_null() {
        return 0;
    }
    if pixels_len == 0 || width == 0 || height == 0 {
        return 0;
    }
    let expected_len = width as u64 * height as u64;
    if expected_len != pixels_len {
        return 0;
    }
    let len = pixels_len as usize;
    if len == 0 || len > isize::MAX as usize {
        return 0;
    }

    let src_slice = unsafe { std::slice::from_raw_parts(src, len) };
    let dst_slice = unsafe { std::slice::from_raw_parts_mut(dst, len) };

    let mut opacity = if opacity.is_finite() { opacity } else { 0.0 };
    opacity = clamp01(opacity);
    if opacity <= 0.0 {
        return 1;
    }

    let mut use_mask = false;
    let mut mask_slice: &[u32] = &[];
    let mut mask_opacity = if mask_opacity.is_finite() { mask_opacity } else { 0.0 };
    mask_opacity = clamp01(mask_opacity);
    if !mask.is_null() && mask_len == pixels_len && mask_opacity > 0.0 {
        use_mask = true;
        mask_slice = unsafe { std::slice::from_raw_parts(mask, len) };
    }

    let width_i32 = width as i32;
    let height_i32 = height as i32;
    let sx0 = start_x.max(0).min(width_i32) as i32;
    let sx1 = end_x.max(0).min(width_i32) as i32;
    let sy0 = start_y.max(0).min(height_i32) as i32;
    let sy1 = end_y.max(0).min(height_i32) as i32;
    if sx0 >= sx1 || sy0 >= sy1 {
        return 1;
    }

    let width_usize = width as usize;
    for y in sy0..sy1 {
        let row_offset = y as usize * width_usize;
        for x in sx0..sx1 {
            let idx = row_offset + x as usize;
            let src_color = src_slice[idx];
            let src_a = ((src_color >> 24) & 0xFF) as u32;
            if src_a == 0 {
                continue;
            }
            let mut effective_alpha = (src_a as f32 / 255.0) * opacity;
            if effective_alpha <= 0.0 {
                continue;
            }
            if use_mask {
                let mask_color = mask_slice[idx];
                let mask_a = ((mask_color >> 24) & 0xFF) as u32;
                if mask_a == 0 {
                    continue;
                }
                let mask_alpha = (mask_a as f32 / 255.0) * mask_opacity;
                if mask_alpha <= 0.0 {
                    continue;
                }
                effective_alpha *= mask_alpha;
                if effective_alpha <= 0.0 {
                    continue;
                }
            }
            let effective_color = color_with_opacity(src_color, effective_alpha);
            if effective_color == 0 {
                continue;
            }
            let blended = blend_argb(dst_slice[idx], effective_color, blend_mode, idx as u32);
            dst_slice[idx] = blended;
        }
    }

    1
}

#[flutter_rust_bridge::frb(ignore)]
#[no_mangle]
pub extern "C" fn cpu_blend_overflow(
    canvas: *mut u32,
    canvas_len: u64,
    width: u32,
    height: u32,
    upper_x: *const i32,
    upper_y: *const i32,
    upper_color: *const u32,
    upper_len: u64,
    lower_x: *const i32,
    lower_y: *const i32,
    lower_color: *const u32,
    lower_len: u64,
    opacity: f32,
    blend_mode: u32,
    mask: *const u32,
    mask_len: u64,
    mask_opacity: f32,
    mask_overflow_x: *const i32,
    mask_overflow_y: *const i32,
    mask_overflow_color: *const u32,
    mask_overflow_len: u64,
    out_x: *mut i32,
    out_y: *mut i32,
    out_color: *mut u32,
    out_capacity: u64,
    out_count: *mut u64,
) -> u8 {
    if canvas.is_null() || out_count.is_null() {
        return 0;
    }
    if canvas_len == 0 || width == 0 || height == 0 {
        return 0;
    }
    let expected_len = width as u64 * height as u64;
    if expected_len != canvas_len {
        return 0;
    }
    let len = canvas_len as usize;
    if len == 0 || len > isize::MAX as usize {
        return 0;
    }
    if upper_len > 0 {
        if upper_x.is_null() || upper_y.is_null() || upper_color.is_null() {
            return 0;
        }
        if upper_len as usize > isize::MAX as usize {
            return 0;
        }
    }
    if lower_len > 0 {
        if lower_x.is_null() || lower_y.is_null() || lower_color.is_null() {
            return 0;
        }
        if lower_len as usize > isize::MAX as usize {
            return 0;
        }
    }

    let canvas_slice = unsafe { std::slice::from_raw_parts_mut(canvas, len) };

    let mut lower_map: HashMap<i64, u32> = HashMap::new();
    if lower_len > 0 {
        let l_len = lower_len as usize;
        let xs = unsafe { std::slice::from_raw_parts(lower_x, l_len) };
        let ys = unsafe { std::slice::from_raw_parts(lower_y, l_len) };
        let colors = unsafe { std::slice::from_raw_parts(lower_color, l_len) };
        lower_map.reserve(l_len);
        for i in 0..l_len {
            let color = colors[i];
            if (color >> 24) == 0 {
                continue;
            }
            let key = overflow_key(xs[i], ys[i]);
            lower_map.insert(key, color);
        }
    }

    let mut opacity = if opacity.is_finite() { opacity } else { 0.0 };
    opacity = clamp01(opacity);

    let mut use_mask = false;
    let mut mask_slice: &[u32] = &[];
    let mut mask_opacity = if mask_opacity.is_finite() { mask_opacity } else { 0.0 };
    mask_opacity = clamp01(mask_opacity);
    let mut mask_overflow_map: HashMap<i64, u32> = HashMap::new();
    if !mask.is_null() && mask_len == canvas_len && mask_opacity > 0.0 {
        use_mask = true;
        mask_slice = unsafe { std::slice::from_raw_parts(mask, len) };
        if mask_overflow_len > 0 {
            if mask_overflow_x.is_null()
                || mask_overflow_y.is_null()
                || mask_overflow_color.is_null()
            {
                return 0;
            }
            if mask_overflow_len as usize > isize::MAX as usize {
                return 0;
            }
            let m_len = mask_overflow_len as usize;
            let xs = unsafe { std::slice::from_raw_parts(mask_overflow_x, m_len) };
            let ys = unsafe { std::slice::from_raw_parts(mask_overflow_y, m_len) };
            let colors = unsafe { std::slice::from_raw_parts(mask_overflow_color, m_len) };
            mask_overflow_map.reserve(m_len);
            for i in 0..m_len {
                let color = colors[i];
                if (color >> 24) == 0 {
                    continue;
                }
                let key = overflow_key(xs[i], ys[i]);
                mask_overflow_map.insert(key, color);
            }
        }
    }

    if upper_len > 0 && opacity > 0.0 {
        let u_len = upper_len as usize;
        let xs = unsafe { std::slice::from_raw_parts(upper_x, u_len) };
        let ys = unsafe { std::slice::from_raw_parts(upper_y, u_len) };
        let colors = unsafe { std::slice::from_raw_parts(upper_color, u_len) };
        let width_i64 = width as i64;
        let height_i64 = height as i64;
        let width_usize = width as usize;
        for i in 0..u_len {
            let src_color = colors[i];
            let src_a = ((src_color >> 24) & 0xFF) as u32;
            if src_a == 0 {
                continue;
            }
            let mut effective_alpha = (src_a as f32 / 255.0) * opacity;
            if effective_alpha <= 0.0 {
                continue;
            }
            let x = xs[i] as i64;
            let y = ys[i] as i64;
            if use_mask {
                let mask_a = if x >= 0 && y >= 0 && x < width_i64 && y < height_i64 {
                    let idx = y as usize * width_usize + x as usize;
                    (mask_slice[idx] >> 24) & 0xFF
                } else {
                    let key = overflow_key(x as i32, y as i32);
                    (mask_overflow_map.get(&key).copied().unwrap_or(0) >> 24) & 0xFF
                };
                if mask_a == 0 {
                    continue;
                }
                let mask_alpha = (mask_a as f32 / 255.0) * mask_opacity;
                if mask_alpha <= 0.0 {
                    continue;
                }
                effective_alpha *= mask_alpha;
                if effective_alpha <= 0.0 {
                    continue;
                }
            }
            let effective_color = color_with_opacity(src_color, effective_alpha);
            if effective_color == 0 {
                continue;
            }
            if x >= 0 && y >= 0 && x < width_i64 && y < height_i64 {
                let idx = y as usize * width_usize + x as usize;
                let blended = blend_argb(canvas_slice[idx], effective_color, blend_mode, idx as u32);
                canvas_slice[idx] = blended;
            } else {
                let key = overflow_key(x as i32, y as i32);
                let dst_color = lower_map.get(&key).copied().unwrap_or(0);
                let pixel_index = (y * width_i64 + x) as u32;
                let blended = blend_argb(dst_color, effective_color, blend_mode, pixel_index);
                if (blended >> 24) == 0 {
                    lower_map.remove(&key);
                } else {
                    lower_map.insert(key, blended);
                }
            }
        }
    }

    let mut entries: Vec<(i32, i32, u32)> = Vec::with_capacity(lower_map.len());
    for (key, color) in lower_map.into_iter() {
        let x = (key >> 32) as i32;
        let y = key as i32;
        entries.push((x, y, color));
    }
    entries.sort_by(|a, b| {
        let y_cmp = a.1.cmp(&b.1);
        if y_cmp == std::cmp::Ordering::Equal {
            a.0.cmp(&b.0)
        } else {
            y_cmp
        }
    });

    let count = entries.len();
    if count > out_capacity as usize {
        return 0;
    }
    unsafe {
        *out_count = count as u64;
    }
    if count == 0 {
        return 1;
    }
    if out_x.is_null() || out_y.is_null() || out_color.is_null() {
        return 0;
    }
    let out_x_slice = unsafe { std::slice::from_raw_parts_mut(out_x, count) };
    let out_y_slice = unsafe { std::slice::from_raw_parts_mut(out_y, count) };
    let out_color_slice = unsafe { std::slice::from_raw_parts_mut(out_color, count) };
    for (i, (x, y, color)) in entries.into_iter().enumerate() {
        out_x_slice[i] = x;
        out_y_slice[i] = y;
        out_color_slice[i] = color;
    }

    1
}

fn clamp_unit_f64_to_f32(value: f64) -> f32 {
    if !value.is_finite() {
        return 0.0;
    }
    let clamped = value.clamp(0.0, 1.0);
    clamped as f32
}
