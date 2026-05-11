#[flutter_rust_bridge::frb(sync)]
pub fn convert_pixels_to_rgba(pixels: Vec<u32>) -> Vec<u8> {
    let mut rgba = vec![0u8; pixels.len().saturating_mul(4)];
    for (argb, out) in pixels.into_iter().zip(rgba.chunks_exact_mut(4)) {
        let a = ((argb >> 24) & 0xff) as u8;
        if a == 255 {
            out[0] = ((argb >> 16) & 0xff) as u8;
            out[1] = ((argb >> 8) & 0xff) as u8;
            out[2] = (argb & 0xff) as u8;
            out[3] = 255;
        } else if a == 0 {
            out[0] = 0;
            out[1] = 0;
            out[2] = 0;
            out[3] = 0;
        } else {
            let r = ((argb >> 16) & 0xff) as u32;
            let g = ((argb >> 8) & 0xff) as u32;
            let b = (argb & 0xff) as u32;
            let a_u32 = a as u32;

            // Fast premultiply: (val * a + 127) / 255
            out[0] = ((r * a_u32 + 127) / 255) as u8;
            out[1] = ((g * a_u32 + 127) / 255) as u8;
            out[2] = ((b * a_u32 + 127) / 255) as u8;
            out[3] = a;
        }
    }
    rgba
}
