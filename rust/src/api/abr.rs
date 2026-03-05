use std::path::Path;

#[flutter_rust_bridge::frb]
pub struct AbrTip {
    pub name: String,
    pub width: i32,
    pub height: i32,
    pub alpha_mask: Vec<u8>,
    pub brush_type: i32,
    pub spacing_raw: Option<i32>,
    pub spacing: Option<f32>,
    pub antialias: Option<bool>,
    pub short_top: Option<i32>,
    pub short_left: Option<i32>,
    pub short_bottom: Option<i32>,
    pub short_right: Option<i32>,
    pub top: i32,
    pub left: i32,
    pub bottom: i32,
    pub right: i32,
    pub depth: i32,
    pub compression: i32,
    pub bytes_per_pixel: i32,
}

#[flutter_rust_bridge::frb]
pub struct AbrFile {
    pub version: i32,
    pub subversion: i32,
    pub tips: Vec<AbrTip>,
}

#[derive(Clone, Copy)]
struct AbrTipMeta {
    brush_type: i16,
    spacing_raw: Option<i16>,
    antialias: Option<bool>,
    short_top: Option<i16>,
    short_left: Option<i16>,
    short_bottom: Option<i16>,
    short_right: Option<i16>,
}

#[flutter_rust_bridge::frb]
pub fn abr_decode(bytes: Vec<u8>, file_name: Option<String>) -> Result<AbrFile, String> {
    if bytes.is_empty() {
        return Err("ABR 文件为空".to_string());
    }

    let mut reader = AbrReader::new(&bytes);
    let version = reader
        .read_i16()
        .ok_or_else(|| "ABR 缺少版本号".to_string())?;
    let source_name = base_name_without_extension(file_name.as_deref());

    match version {
        1 | 2 => {
            let count = reader
                .read_i16()
                .ok_or_else(|| "ABR 缺少笔刷数量".to_string())?;
            if count <= 0 {
                return Err("ABR 笔刷数量无效".to_string());
            }

            let mut tips: Vec<AbrTip> = Vec::new();
            for index in 1..=(count as usize) {
                if let Some(tip) = read_v12_brush(&mut reader, version, &source_name, index) {
                    tips.push(tip);
                }
            }
            if tips.is_empty() {
                return Err("ABR 中没有可导入的笔刷".to_string());
            }

            Ok(AbrFile {
                version: version as i32,
                subversion: 0,
                tips,
            })
        }
        6 => {
            let subversion = reader
                .read_i16()
                .ok_or_else(|| "ABR 缺少子版本号".to_string())?;
            if subversion != 1 && subversion != 2 {
                return Err(format!("不支持的 ABR 子版本: {subversion}"));
            }

            let count = find_sample_count_v6(&mut reader)
                .ok_or_else(|| "ABR v6 未找到 samp 采样区块".to_string())?;
            if count == 0 {
                return Err("ABR v6 采样区块为空".to_string());
            }

            let mut tips: Vec<AbrTip> = Vec::new();
            for index in 1..=count {
                if let Some(tip) = read_v6_brush(&mut reader, subversion, &source_name, index) {
                    tips.push(tip);
                }
            }
            if tips.is_empty() {
                return Err("ABR 中没有可导入的笔刷".to_string());
            }

            Ok(AbrFile {
                version: version as i32,
                subversion: subversion as i32,
                tips,
            })
        }
        _ => Err(format!("不支持的 ABR 版本: {version}")),
    }
}

fn find_sample_count_v6(reader: &mut AbrReader<'_>) -> Option<usize> {
    let origin = reader.position();
    if !reach_8bim_section(reader, *b"samp") {
        reader.seek(origin);
        return None;
    }

    let section_size = reader.read_i32()?;
    if section_size < 0 {
        reader.seek(origin);
        return None;
    }

    let data_start = reader.position();
    let section_end = data_start.checked_add(section_size as usize)?;
    if !reader.can_seek(section_end) {
        reader.seek(origin);
        return None;
    }

    let mut samples: usize = 0;
    while reader.position() < section_end {
        let brush_size = reader.read_i32()?;
        if brush_size < 0 {
            reader.seek(origin);
            return None;
        }
        let aligned = align4(brush_size as usize)?;
        let next = reader.position().checked_add(aligned)?;
        if !reader.can_seek(next) || next > section_end {
            reader.seek(origin);
            return None;
        }
        reader.seek(next);
        samples = samples.checked_add(1)?;
    }

    if !reader.seek(data_start) {
        reader.seek(origin);
        return None;
    }
    Some(samples)
}

fn reach_8bim_section(reader: &mut AbrReader<'_>, name: [u8; 4]) -> bool {
    while !reader.is_done() {
        let Some(tag) = reader.read_4() else {
            return false;
        };
        if tag != *b"8BIM" {
            return false;
        }

        let Some(section_name) = reader.read_4() else {
            return false;
        };
        if section_name == name {
            return true;
        }

        let Some(section_size) = reader.read_i32() else {
            return false;
        };
        if section_size < 0 {
            return false;
        }
        if !reader.skip(section_size as usize) {
            return false;
        }
    }
    false
}

fn read_v12_brush(
    reader: &mut AbrReader<'_>,
    version: i16,
    source_name: &str,
    index: usize,
) -> Option<AbrTip> {
    let brush_type = reader.read_i16()?;
    let brush_size = reader.read_i32()?;
    if brush_size < 0 {
        return None;
    }
    let next_brush = reader.position().checked_add(brush_size as usize)?;
    if !reader.can_seek(next_brush) {
        return None;
    }

    if brush_type != 2 {
        reader.seek(next_brush);
        return None;
    }

    if !reader.skip(4) {
        reader.seek(next_brush);
        return None;
    }
    let spacing_raw = reader.read_i16()?;

    let mut name = if version == 2 {
        read_ucs2_text(reader).unwrap_or_default()
    } else {
        String::new()
    };
    if name.is_empty() {
        name = format!("{source_name}_{index}");
    }

    let antialias = reader.read_u8().map(|value| value != 0)?;
    let short_top = reader.read_i16()?;
    let short_left = reader.read_i16()?;
    let short_bottom = reader.read_i16()?;
    let short_right = reader.read_i16()?;

    let meta = AbrTipMeta {
        brush_type,
        spacing_raw: Some(spacing_raw),
        antialias: Some(antialias),
        short_top: Some(short_top),
        short_left: Some(short_left),
        short_bottom: Some(short_bottom),
        short_right: Some(short_right),
    };

    let tip = read_brush_sample(reader, name, meta, next_brush);
    if tip.is_none() {
        reader.seek(next_brush);
    }
    reader.seek(next_brush);
    tip
}

fn read_v6_brush(
    reader: &mut AbrReader<'_>,
    subversion: i16,
    source_name: &str,
    index: usize,
) -> Option<AbrTip> {
    let brush_size = reader.read_i32()?;
    if brush_size < 0 {
        return None;
    }
    let aligned = align4(brush_size as usize)?;
    let next_brush = reader.position().checked_add(aligned)?;
    if !reader.can_seek(next_brush) {
        return None;
    }

    if !reader.skip(37) {
        reader.seek(next_brush);
        return None;
    }

    let extra = if subversion == 1 { 10usize } else { 264usize };
    if !reader.skip(extra) {
        reader.seek(next_brush);
        return None;
    }

    let tip = read_brush_sample(
        reader,
        format!("{source_name}_{index}"),
        AbrTipMeta {
            brush_type: 2,
            spacing_raw: None,
            antialias: None,
            short_top: None,
            short_left: None,
            short_bottom: None,
            short_right: None,
        },
        next_brush,
    );
    reader.seek(next_brush);
    tip
}

fn read_brush_sample(
    reader: &mut AbrReader<'_>,
    name: String,
    meta: AbrTipMeta,
    fallback_seek: usize,
) -> Option<AbrTip> {
    let top = reader.read_i32()?;
    let left = reader.read_i32()?;
    let bottom = reader.read_i32()?;
    let right = reader.read_i32()?;
    let depth = reader.read_i16()?;
    let compression = reader.read_u8()?;

    let width = right.saturating_sub(left);
    let height = bottom.saturating_sub(top);
    if width <= 0 || height <= 0 {
        reader.seek(fallback_seek);
        return None;
    }
    if depth <= 0 {
        reader.seek(fallback_seek);
        return None;
    }

    let bytes_per_pixel = (depth as i32) >> 3;
    if bytes_per_pixel <= 0 {
        reader.seek(fallback_seek);
        return None;
    }

    let width_usize = width as usize;
    let height_usize = height as usize;
    let bytes_per_pixel_usize = bytes_per_pixel as usize;
    let pixel_count = width_usize.checked_mul(height_usize)?;
    let sample_byte_count = pixel_count.checked_mul(bytes_per_pixel_usize)?;

    let sample_bytes = match compression {
        0 => reader.read_bytes(sample_byte_count)?.to_vec(),
        1 => {
            let row_bytes = width_usize.checked_mul(bytes_per_pixel_usize)?;
            decode_packbits(reader, height_usize, row_bytes)?
        }
        _ => {
            reader.seek(fallback_seek);
            return None;
        }
    };

    if sample_bytes.len() < sample_byte_count {
        reader.seek(fallback_seek);
        return None;
    }

    // Krita's ABR path ultimately uses the decompressed sample byte as mask
    // coverage. Do not invert here, otherwise the brush turns into a mostly
    // opaque rectangle.
    let mut alpha_mask: Vec<u8> = vec![0; pixel_count];
    if bytes_per_pixel_usize == 1 {
        for (dst, &src) in alpha_mask.iter_mut().zip(sample_bytes.iter()) {
            *dst = src;
        }
    } else {
        for (i, dst) in alpha_mask.iter_mut().enumerate() {
            *dst = sample_bytes[i * bytes_per_pixel_usize];
        }
    }

    Some(AbrTip {
        name,
        width,
        height,
        alpha_mask,
        brush_type: meta.brush_type as i32,
        spacing_raw: meta.spacing_raw.map(i32::from),
        spacing: meta.spacing_raw.and_then(abr_spacing_to_ratio),
        antialias: meta.antialias,
        short_top: meta.short_top.map(i32::from),
        short_left: meta.short_left.map(i32::from),
        short_bottom: meta.short_bottom.map(i32::from),
        short_right: meta.short_right.map(i32::from),
        top,
        left,
        bottom,
        right,
        depth: depth as i32,
        compression: compression as i32,
        bytes_per_pixel,
    })
}

fn decode_packbits(
    reader: &mut AbrReader<'_>,
    row_count: usize,
    row_bytes: usize,
) -> Option<Vec<u8>> {
    if row_count == 0 || row_bytes == 0 {
        return None;
    }

    let mut compressed_row_sizes: Vec<usize> = Vec::with_capacity(row_count);
    for _ in 0..row_count {
        compressed_row_sizes.push(reader.read_u16()? as usize);
    }

    let out_len = row_count.checked_mul(row_bytes)?;
    let mut out: Vec<u8> = vec![0; out_len];
    let mut out_offset: usize = 0;

    for row_compressed in compressed_row_sizes {
        let mut consumed: usize = 0;
        let row_end = out_offset.checked_add(row_bytes)?;

        while consumed < row_compressed && out_offset < row_end {
            let control = reader.read_u8()?;
            consumed = consumed.checked_add(1)?;
            let n = control as i8;

            if n >= 0 {
                let literal_count = (n as usize).checked_add(1)?;
                let literals = reader.read_bytes(literal_count)?;
                consumed = consumed.checked_add(literal_count)?;
                for &value in literals {
                    if out_offset >= row_end {
                        break;
                    }
                    out[out_offset] = value;
                    out_offset += 1;
                }
            } else if n != -128 {
                let run_length = ((-n as i16) as usize).checked_add(1)?;
                let value = reader.read_u8()?;
                consumed = consumed.checked_add(1)?;
                for _ in 0..run_length {
                    if out_offset >= row_end {
                        break;
                    }
                    out[out_offset] = value;
                    out_offset += 1;
                }
            }
        }

        if consumed < row_compressed && !reader.skip(row_compressed - consumed) {
            return None;
        }

        if out_offset < row_end {
            out_offset = row_end;
        } else if out_offset > row_end {
            out_offset = row_end;
        }
    }

    Some(out)
}

fn read_ucs2_text(reader: &mut AbrReader<'_>) -> Option<String> {
    let count = reader.read_u32()? as usize;
    if count == 0 {
        return Some(String::new());
    }

    let mut code_units: Vec<u16> = Vec::with_capacity(count);
    for _ in 0..count {
        code_units.push(reader.read_u16()?);
    }
    while code_units.last().copied() == Some(0) {
        code_units.pop();
    }

    Some(String::from_utf16_lossy(&code_units).trim().to_string())
}

fn abr_spacing_to_ratio(raw: i16) -> Option<f32> {
    if raw <= 0 {
        return None;
    }
    Some(raw as f32 / 100.0)
}

fn align4(value: usize) -> Option<usize> {
    value.checked_add(3).map(|v| v & !3)
}

fn base_name_without_extension(file_name: Option<&str>) -> String {
    let fallback = "abr_brush";
    let Some(file_name) = file_name else {
        return fallback.to_string();
    };
    if file_name.trim().is_empty() {
        return fallback.to_string();
    }

    let stem = Path::new(file_name)
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or(fallback)
        .trim();
    if stem.is_empty() {
        fallback.to_string()
    } else {
        stem.to_string()
    }
}

struct AbrReader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> AbrReader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    fn position(&self) -> usize {
        self.offset
    }

    fn is_done(&self) -> bool {
        self.offset >= self.bytes.len()
    }

    fn can_seek(&self, position: usize) -> bool {
        position <= self.bytes.len()
    }

    fn seek(&mut self, position: usize) -> bool {
        if !self.can_seek(position) {
            return false;
        }
        self.offset = position;
        true
    }

    fn skip(&mut self, length: usize) -> bool {
        let Some(next) = self.offset.checked_add(length) else {
            return false;
        };
        self.seek(next)
    }

    fn read_bytes(&mut self, len: usize) -> Option<&'a [u8]> {
        let end = self.offset.checked_add(len)?;
        if end > self.bytes.len() {
            return None;
        }
        let start = self.offset;
        self.offset = end;
        Some(&self.bytes[start..end])
    }

    fn read_4(&mut self) -> Option<[u8; 4]> {
        let bytes = self.read_bytes(4)?;
        Some([bytes[0], bytes[1], bytes[2], bytes[3]])
    }

    fn read_u8(&mut self) -> Option<u8> {
        Some(*self.read_bytes(1)?.first()?)
    }

    fn read_i16(&mut self) -> Option<i16> {
        let bytes = self.read_bytes(2)?;
        Some(i16::from_be_bytes([bytes[0], bytes[1]]))
    }

    fn read_u16(&mut self) -> Option<u16> {
        let bytes = self.read_bytes(2)?;
        Some(u16::from_be_bytes([bytes[0], bytes[1]]))
    }

    fn read_i32(&mut self) -> Option<i32> {
        let bytes = self.read_bytes(4)?;
        Some(i32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    fn read_u32(&mut self) -> Option<u32> {
        let bytes = self.read_bytes(4)?;
        Some(u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }
}

#[cfg(test)]
mod tests {
    use super::{abr_decode, AbrFile};
    use std::fs;

    fn push_i16_be(bytes: &mut Vec<u8>, value: i16) {
        bytes.extend_from_slice(&value.to_be_bytes());
    }

    fn push_i32_be(bytes: &mut Vec<u8>, value: i32) {
        bytes.extend_from_slice(&value.to_be_bytes());
    }

    fn push_u16_be(bytes: &mut Vec<u8>, value: u16) {
        bytes.extend_from_slice(&value.to_be_bytes());
    }

    fn push_u32_be(bytes: &mut Vec<u8>, value: u32) {
        bytes.extend_from_slice(&value.to_be_bytes());
    }

    #[test]
    fn rejects_invalid_bytes() {
        let parsed = abr_decode(vec![0, 1, 2], Some("invalid.abr".to_string()));
        assert!(parsed.is_err());
    }

    #[test]
    fn parses_krita_sample() {
        let bytes = fs::read("../krita/libs/brush/tests/data/brushes_by_mar_ka_d338ela.abr")
            .expect("failed to read krita abr sample");
        let parsed: AbrFile = abr_decode(bytes, Some("brushes_by_mar_ka_d338ela.abr".to_string()))
            .expect("failed to parse abr sample");

        assert!(!parsed.tips.is_empty());
        let first = &parsed.tips[0];
        assert!(first.width > 0);
        assert!(first.height > 0);
        assert_eq!(
            first.alpha_mask.len(),
            (first.width * first.height) as usize
        );
        assert!(first.alpha_mask.iter().any(|value| *value > 0));
        assert!(first.depth > 0);
        assert!(first.bytes_per_pixel > 0);
        assert!(first.compression == 0 || first.compression == 1);

        // Regression guard: an inverted mask becomes mostly opaque and causes
        // thick solid strokes. Keep this sample in the expected range.
        let mean_alpha = first.alpha_mask.iter().map(|v| *v as u64).sum::<u64>() as f64
            / first.alpha_mask.len() as f64;
        assert!(mean_alpha > 5.0 && mean_alpha < 140.0);
    }

    #[test]
    fn parses_v2_spacing_and_antialias() {
        let mut bytes: Vec<u8> = Vec::new();

        // Header: ABR v2 with one sampled brush.
        push_i16_be(&mut bytes, 2);
        push_i16_be(&mut bytes, 1);

        // Brush record header.
        push_i16_be(&mut bytes, 2); // sampled brush
        push_i32_be(&mut bytes, 46); // payload bytes

        // 4 unknown bytes + spacing.
        push_i32_be(&mut bytes, 0);
        push_i16_be(&mut bytes, 25); // 25%

        // UCS-2 name "A\0"
        push_u32_be(&mut bytes, 2);
        push_u16_be(&mut bytes, b'A' as u16);
        push_u16_be(&mut bytes, 0);

        // Antialias + short bounds.
        bytes.push(1);
        push_i16_be(&mut bytes, 0);
        push_i16_be(&mut bytes, 0);
        push_i16_be(&mut bytes, 2);
        push_i16_be(&mut bytes, 2);

        // Long bounds + depth + compression.
        push_i32_be(&mut bytes, 0);
        push_i32_be(&mut bytes, 0);
        push_i32_be(&mut bytes, 2);
        push_i32_be(&mut bytes, 2);
        push_i16_be(&mut bytes, 8);
        bytes.push(0);

        // 2x2 raw sample bytes.
        bytes.extend_from_slice(&[0, 64, 128, 255]);

        let parsed = abr_decode(bytes, Some("unit_v2.abr".to_string())).expect("decode v2 abr");
        assert_eq!(parsed.version, 2);
        assert_eq!(parsed.tips.len(), 1);

        let tip = &parsed.tips[0];
        assert_eq!(tip.name, "A");
        assert_eq!(tip.width, 2);
        assert_eq!(tip.height, 2);
        assert_eq!(tip.spacing_raw, Some(25));
        assert_eq!(tip.spacing, Some(0.25));
        assert_eq!(tip.antialias, Some(true));
        assert_eq!(tip.short_top, Some(0));
        assert_eq!(tip.short_left, Some(0));
        assert_eq!(tip.short_bottom, Some(2));
        assert_eq!(tip.short_right, Some(2));
        assert_eq!(tip.top, 0);
        assert_eq!(tip.left, 0);
        assert_eq!(tip.bottom, 2);
        assert_eq!(tip.right, 2);
        assert_eq!(tip.depth, 8);
        assert_eq!(tip.compression, 0);
        assert_eq!(tip.bytes_per_pixel, 1);
        assert_eq!(tip.alpha_mask, vec![0, 64, 128, 255]);
    }
}
