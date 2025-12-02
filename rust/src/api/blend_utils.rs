use flutter_rust_bridge::frb;

#[derive(Clone, Copy)]
pub enum BlendMode {
    Normal,
    Multiply,
    Dissolve,
    Darken,
    ColorBurn,
    LinearBurn,
    DarkerColor,
    Lighten,
    Screen,
    ColorDodge,
    LinearDodge,
    LighterColor,
    Overlay,
    SoftLight,
    HardLight,
    VividLight,
    LinearLight,
    PinLight,
    HardMix,
    Difference,
    Exclusion,
    Subtract,
    Divide,
    Hue,
    Saturation,
    Color,
    Luminosity,
}

pub fn blend_pixel(dst: u32, src: u32, mode: BlendMode) -> u32 {
    let src_a = (src >> 24) & 0xff;
    if src_a == 0 {
        return dst;
    }
    // TODO: Implement full blending logic
    // For now, simple alpha blend (Normal mode)
    let dst_a = (dst >> 24) & 0xff;
    
    let sa = src_a as f32 / 255.0;
    let da = dst_a as f32 / 255.0;
    
    let sr = ((src >> 16) & 0xff) as f32 / 255.0;
    let sg = ((src >> 8) & 0xff) as f32 / 255.0;
    let sb = (src & 0xff) as f32 / 255.0;

    let dr = ((dst >> 16) & 0xff) as f32 / 255.0;
    let dg = ((dst >> 8) & 0xff) as f32 / 255.0;
    let db = (dst & 0xff) as f32 / 255.0;

    let (fr, fg, fb) = match mode {
        BlendMode::Normal => (sr, sg, sb),
        BlendMode::Multiply => (sr * dr, sg * dg, sb * db),
        // Add other modes here
        _ => (sr, sg, sb), // Fallback to normal
    };

    let out_a = sa + da * (1.0 - sa);
    if out_a <= 0.0 {
        return 0;
    }

    let rr = ((fr * sa) + dr * da * (1.0 - sa)) / out_a;
    let rg = ((fg * sa) + dg * da * (1.0 - sa)) / out_a;
    let rb = ((fb * sa) + db * da * (1.0 - sa)) / out_a;

    let out_alpha = (out_a * 255.0).round() as u32;
    let out_r = (rr * 255.0).round() as u32;
    let out_g = (rg * 255.0).round() as u32;
    let out_b = (rb * 255.0).round() as u32;

    (out_alpha << 24) | (out_r << 16) | (out_g << 8) | out_b
}

#[frb(sync)] 
pub fn composite_region(
    width: i32,
    height: i32,
    layers_pixels: Vec<Vec<u32>>,
    layers_opacity: Vec<f64>,
    layers_blend_mode: Vec<BlendMode>,
) -> Vec<u32> {
    println!("Rust composite_region called! Size: {}x{}, Layers: {}", width, height, layers_pixels.len());
    let num_pixels = (width * height) as usize;
    let mut composite = vec![0u32; num_pixels];
    let num_layers = layers_pixels.len();

    // We iterate pixel by pixel. 
    // Optimizations like SIMD can be added here later.
    for i in 0..num_pixels {
        let mut current_dst = 0u32;
        let mut initialized = false;

        for layer_idx in 0..num_layers {
            let src_pixel = layers_pixels[layer_idx][i];
            let opacity = layers_opacity[layer_idx];
            
            let src_a_raw = (src_pixel >> 24) & 0xff;
            if src_a_raw == 0 {
                continue;
            }

            // Apply layer opacity
            let effective_a = (src_a_raw as f64 * opacity).round() as i32;
            let effective_a = effective_a.clamp(0, 255) as u32;
            
            if effective_a == 0 {
                continue;
            }

            // Construct effective source pixel (RGB unchanged, Alpha modified)
            // Note: This assumes Straight Alpha input.
            let effective_src = (effective_a << 24) | (src_pixel & 0x00FFFFFF);

            if !initialized {
                current_dst = effective_src;
                initialized = true;
            } else {
                current_dst = blend_pixel(current_dst, effective_src, layers_blend_mode[layer_idx]);
            }
        }
        composite[i] = current_dst;
    }
    composite
}

// Helper to avoid transmute if possible, but simpler to just use the enum directly.
// Since we are in the same file, we can just use the enum.
// But `layers_blend_mode` is a Vec.
// `BlendMode` needs to derive Copy/Clone to be easily used.

