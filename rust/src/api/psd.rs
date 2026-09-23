use rayon::prelude::*;

pub struct PsdDocument {
    pub width: i32,
    pub height: i32,
    pub layers: Vec<PsdLayer>,
}

pub struct PsdLayer {
    pub name: String,
    pub visible: bool,
    pub opacity: u8,
    pub clipping_mask: bool,
    pub blend_mode_key: String,
    pub bitmap: Vec<u8>, // RGBA8888, tightly packed
    pub bitmap_width: i32,
    pub bitmap_height: i32,
    pub bitmap_left: i32,
    pub bitmap_top: i32,
}

pub fn import_psd(bytes: Vec<u8>) -> Result<PsdDocument, String> {
    let psd = psd::Psd::from_bytes(&bytes).map_err(|e| e.to_string())?;

    if psd.depth() != psd::PsdDepth::Eight {
        return Err(format!("仅支持 8bit PSD，当前深度：{:?}", psd.depth()));
    }
    if psd.color_mode() != psd::ColorMode::Rgb {
        return Err(format!(
            "仅支持 RGB PSD，当前色彩模式：{:?}",
            psd.color_mode()
        ));
    }

    let width: i32 = psd.width() as i32;
    let height: i32 = psd.height() as i32;

    let layers: Vec<PsdLayer> = {
        let src_layers = psd.layers();
        let process_layer = |layer: &psd::PsdLayer| -> Option<PsdLayer> {
            let left: i32 = layer.layer_left();
            let top: i32 = layer.layer_top();
            let layer_width: i32 = layer.width() as i32;
            let layer_height: i32 = layer.height() as i32;
            if layer_width <= 0 || layer_height <= 0 {
                return None;
            }

            let right: i32 = left.saturating_add(layer_width);
            let bottom: i32 = top.saturating_add(layer_height);

            let clipped_left = left.clamp(0, width);
            let clipped_top = top.clamp(0, height);
            let clipped_right = right.clamp(0, width);
            let clipped_bottom = bottom.clamp(0, height);
            let clipped_width = clipped_right - clipped_left;
            let clipped_height = clipped_bottom - clipped_top;
            if clipped_width <= 0 || clipped_height <= 0 {
                return None;
            }

            let layer_width_usize: usize = layer_width as usize;
            let layer_height_usize: usize = layer_height as usize;
            let expected_len: usize = layer_width_usize.checked_mul(layer_height_usize)?;

            let mut red = layer
                .channel_bytes(psd::PsdChannelKind::Red)
                .unwrap_or_else(|| vec![0; expected_len]);
            let mut green = layer
                .channel_bytes(psd::PsdChannelKind::Green)
                .unwrap_or_else(|| vec![0; expected_len]);
            let mut blue = layer
                .channel_bytes(psd::PsdChannelKind::Blue)
                .unwrap_or_else(|| vec![0; expected_len]);

            if red.len() != expected_len {
                red.resize(expected_len, 0);
            }
            if green.len() != expected_len {
                green.resize(expected_len, 0);
            }
            if blue.len() != expected_len {
                blue.resize(expected_len, 0);
            }

            let mut alpha = layer.channel_bytes(psd::PsdChannelKind::TransparencyMask);
            if let Some(ref mut alpha) = alpha {
                if alpha.len() != expected_len {
                    alpha.resize(expected_len, 255);
                }
            }

            let src_offset_x: usize = (clipped_left - left).max(0) as usize;
            let src_offset_y: usize = (clipped_top - top).max(0) as usize;
            let clipped_width_usize: usize = clipped_width as usize;
            let clipped_height_usize: usize = clipped_height as usize;

            let row_bytes = clipped_width_usize.checked_mul(4)?;
            let dest_len = row_bytes.checked_mul(clipped_height_usize)?;
            let mut bitmap: Vec<u8> = Vec::with_capacity(dest_len);
            unsafe {
                bitmap.set_len(dest_len);
            }

            for y in 0..clipped_height_usize {
                let src_y = src_offset_y + y;
                let src_row_start = src_y * layer_width_usize + src_offset_x;
                let dest_row_start = y * row_bytes;

                let mut dst = unsafe { bitmap.as_mut_ptr().add(dest_row_start) };
                let mut r = unsafe { red.as_ptr().add(src_row_start) };
                let mut g = unsafe { green.as_ptr().add(src_row_start) };
                let mut b = unsafe { blue.as_ptr().add(src_row_start) };

                match alpha.as_ref() {
                    Some(alpha) => {
                        let mut a = unsafe { alpha.as_ptr().add(src_row_start) };
                        for _ in 0..clipped_width_usize {
                            unsafe {
                                *dst = *r;
                                *dst.add(1) = *g;
                                *dst.add(2) = *b;
                                *dst.add(3) = *a;
                                dst = dst.add(4);
                                r = r.add(1);
                                g = g.add(1);
                                b = b.add(1);
                                a = a.add(1);
                            }
                        }
                    }
                    None => {
                        for _ in 0..clipped_width_usize {
                            unsafe {
                                *dst = *r;
                                *dst.add(1) = *g;
                                *dst.add(2) = *b;
                                *dst.add(3) = 255;
                                dst = dst.add(4);
                                r = r.add(1);
                                g = g.add(1);
                                b = b.add(1);
                            }
                        }
                    }
                }
            }

            Some(PsdLayer {
                name: layer.name().to_string(),
                visible: layer.visible(),
                opacity: layer.opacity(),
                clipping_mask: layer.is_clipping_mask(),
                blend_mode_key: String::from_utf8_lossy(&layer.blend_mode_key()).to_string(),
                bitmap,
                bitmap_width: clipped_width,
                bitmap_height: clipped_height,
                bitmap_left: clipped_left,
                bitmap_top: clipped_top,
            })
        };

        if src_layers.len() >= 5 {
            src_layers
                .par_iter()
                .map(process_layer)
                .collect::<Vec<_>>()
                .into_iter()
                .flatten()
                .collect()
        } else {
            src_layers.iter().filter_map(process_layer).collect()
        }
    };

    Ok(PsdDocument {
        width,
        height,
        layers,
    })
}
