use serde::Deserialize;
use serde_json::{json, Map, Value};
use spade::{ConstrainedDelaunayTriangulation, Point2, Triangulation};
use std::collections::{BTreeMap, HashMap, HashSet};
use ttf_parser::{name_id, Face, GlyphId, OutlineBuilder};

const PLACEHOLDER_WIDTH_RATIO: f64 = 0.6;
const PLACEHOLDER_HEIGHT_RATIO: f64 = 0.8;
const CURVE_SEGMENTS: usize = 12;
const EPSILON: f64 = 1e-7;

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug, Default)]
pub struct CubeTextFontAsset {
    pub id: String,
    pub json: String,
}

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug, Default)]
pub struct CubeTextMaterialOption {
    pub mode: String,
    pub color: String,
    pub color_gradual_start: String,
    pub color_gradual_end: String,
    pub repeat: f32,
    pub offset: f32,
    pub image: String,
    pub repeat_x: f32,
    pub repeat_y: f32,
    pub offset_x: f32,
    pub offset_y: f32,
}

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug, Default)]
pub struct CubeTextMaterials {
    pub front: CubeTextMaterialOption,
    pub back: CubeTextMaterialOption,
    pub up: CubeTextMaterialOption,
    pub down: CubeTextMaterialOption,
    pub left: CubeTextMaterialOption,
    pub right: CubeTextMaterialOption,
    pub outline: CubeTextMaterialOption,
}

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug, Default)]
pub struct CubeTextOptions {
    pub size: f32,
    pub depth: f32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub rot_y: f32,
    pub rot_x: f32,
    pub rot_z: f32,
    pub outline_width: f32,
    pub letter_spacing: f32,
    pub spacing_width: f32,
    pub overlay: String,
    pub materials: CubeTextMaterials,
}

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug, Default)]
pub struct CubeTextObject {
    pub content: String,
    pub font_id: String,
    pub opts: CubeTextOptions,
}

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug, Default)]
pub struct CubeTextSceneMaterial {
    pub name: String,
    pub slot: String,
    pub option: CubeTextMaterialOption,
}

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug, Default)]
pub struct CubeTextScene {
    pub positions: Vec<f32>,
    pub normals: Vec<f32>,
    pub uvs: Vec<f32>,
    pub indices: Vec<u32>,
    pub material_indices: Vec<i32>,
    pub materials: Vec<CubeTextSceneMaterial>,
    pub bounds_min: Vec<f32>,
    pub bounds_max: Vec<f32>,
    pub warnings: Vec<String>,
}

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug, Default)]
pub struct CubeTextExportResult {
    pub file_name: String,
    pub mime_type: String,
    pub bytes: Vec<u8>,
    pub warnings: Vec<String>,
}

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug, Default)]
pub struct CubeTextFontConvertResult {
    pub font_id: String,
    pub json: String,
}

#[derive(Deserialize)]
struct FontJson {
    glyphs: HashMap<String, GlyphJson>,
    #[serde(default)]
    #[serde(rename = "familyName")]
    family_name: Option<String>,
    #[serde(default)]
    resolution: Option<f64>,
}

#[derive(Deserialize)]
struct GlyphJson {
    #[serde(default)]
    ha: Option<f64>,
    #[serde(default)]
    x_min: Option<f64>,
    #[serde(default)]
    x_max: Option<f64>,
    #[serde(default)]
    o: Option<String>,
}

#[derive(Clone, Copy, Debug)]
struct P2 {
    x: f64,
    y: f64,
}

#[derive(Clone, Copy, Debug)]
struct P3 {
    x: f64,
    y: f64,
    z: f64,
}

#[derive(Clone, Debug)]
struct Shape2D {
    outer: Vec<P2>,
    holes: Vec<Vec<P2>>,
}

#[derive(Clone, Copy, Debug)]
struct Bounds2D {
    min: P2,
    max: P2,
}

#[derive(Clone, Copy, Debug)]
struct Bounds3D {
    min: P3,
    max: P3,
}

struct MeshBuilder {
    positions: Vec<f32>,
    normals: Vec<f32>,
    uvs: Vec<f32>,
    indices: Vec<u32>,
    material_indices: Vec<i32>,
}

impl MeshBuilder {
    fn new() -> Self {
        Self {
            positions: Vec::new(),
            normals: Vec::new(),
            uvs: Vec::new(),
            indices: Vec::new(),
            material_indices: Vec::new(),
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn cube_text_build_scene(
    fonts: Vec<CubeTextFontAsset>,
    global_font_id: String,
    texts: Vec<CubeTextObject>,
) -> Result<CubeTextScene, String> {
    build_scene(fonts, global_font_id, texts)
}

#[flutter_rust_bridge::frb]
pub fn cube_text_export_scene(
    fonts: Vec<CubeTextFontAsset>,
    global_font_id: String,
    texts: Vec<CubeTextObject>,
    format: String,
) -> Result<CubeTextExportResult, String> {
    let scene = build_scene(fonts, global_font_id, texts)?;
    let normalized = format.trim().to_ascii_lowercase();
    let (file_name, mime_type, bytes) = match normalized.as_str() {
        "obj" => (
            "cube-3d-text.obj".to_string(),
            "text/plain".to_string(),
            export_obj(&scene),
        ),
        "stl" => (
            "cube-3d-text.stl".to_string(),
            "model/stl".to_string(),
            export_stl(&scene),
        ),
        "gltf" => (
            "cube-3d-text.gltf".to_string(),
            "model/gltf+json".to_string(),
            export_gltf(&scene, false)?,
        ),
        "glb" => (
            "cube-3d-text.glb".to_string(),
            "model/gltf-binary".to_string(),
            export_gltf(&scene, true)?,
        ),
        _ => {
            return Err(format!(
                "不支持的艺术字体导出格式: {}",
                format.trim()
            ));
        }
    };
    Ok(CubeTextExportResult {
        file_name,
        mime_type,
        bytes,
        warnings: scene.warnings,
    })
}

#[flutter_rust_bridge::frb]
pub fn cube_text_convert_ttf_to_font_json(bytes: Vec<u8>) -> Result<CubeTextFontConvertResult, String> {
    convert_ttf_to_font_json(&bytes)
}

fn build_scene(
    fonts: Vec<CubeTextFontAsset>,
    global_font_id: String,
    texts: Vec<CubeTextObject>,
) -> Result<CubeTextScene, String> {
    if fonts.is_empty() {
        return Err("缺少字体数据".to_string());
    }

    let mut parsed_fonts: HashMap<String, FontJson> = HashMap::new();
    for font in fonts {
        if font.id.trim().is_empty() || font.json.trim().is_empty() {
            continue;
        }
        let parsed = serde_json::from_str::<FontJson>(&font.json)
            .map_err(|error| format!("字体 {} 解析失败: {error}", font.id))?;
        parsed_fonts.insert(font.id, parsed);
    }
    if parsed_fonts.is_empty() {
        return Err("没有可用的字体 JSON".to_string());
    }

    let mut mesh = MeshBuilder::new();
    let mut materials = Vec::new();
    let mut warnings = Vec::new();

    for (index, text) in texts.iter().enumerate() {
        if text.content.is_empty() {
            continue;
        }
        let font_id = if text.font_id.trim().is_empty() {
            global_font_id.as_str()
        } else {
            text.font_id.as_str()
        };
        let font = parsed_fonts
            .get(font_id)
            .or_else(|| parsed_fonts.get(global_font_id.as_str()))
            .or_else(|| parsed_fonts.values().next())
            .ok_or_else(|| "没有可用字体".to_string())?;

        let material_base = materials.len() as i32;
        append_text_materials(index, &text.opts.materials, &mut materials);
        build_text_mesh(
            font,
            text,
            material_base,
            &mut mesh,
            &mut warnings,
            font_id,
        );
    }

    let bounds = compute_bounds3(&mesh.positions);
    Ok(CubeTextScene {
        positions: mesh.positions,
        normals: mesh.normals,
        uvs: mesh.uvs,
        indices: mesh.indices,
        material_indices: mesh.material_indices,
        materials,
        bounds_min: vec![bounds.min.x as f32, bounds.min.y as f32, bounds.min.z as f32],
        bounds_max: vec![bounds.max.x as f32, bounds.max.y as f32, bounds.max.z as f32],
        warnings,
    })
}

fn convert_ttf_to_font_json(bytes: &[u8]) -> Result<CubeTextFontConvertResult, String> {
    let face = Face::parse(bytes, 0)
        .map_err(|error| format!("TTF 字体解析失败: {error:?}"))?;
    let units_per_em = f64::from(face.units_per_em()).max(1.0);
    let scale = (1000.0 * 100.0) / (units_per_em * 72.0);
    let family_name = font_name(&face).unwrap_or_else(|| "Custom Font".to_string());
    let mut glyphs: Map<String, Value> = Map::new();
    let mut seen = HashSet::<u32>::new();
    if let Some(cmap) = face.tables().cmap {
        for subtable in cmap.subtables {
            if !subtable.is_unicode() {
                continue;
            }
            subtable.codepoints(|codepoint| {
                if codepoint == 0 || !seen.insert(codepoint) {
                    return;
                }
                let Some(ch) = char::from_u32(codepoint) else {
                    return;
                };
                let Some(glyph_id) = face.glyph_index(ch) else {
                    return;
                };
                if let Some(value) = glyph_json_for_ttf_glyph(&face, glyph_id, scale) {
                    glyphs.insert(ch.to_string(), value);
                }
            });
        }
    }
    if glyphs.is_empty() {
        return Err("字体中没有可转换的 Unicode 轮廓字形".to_string());
    }

    let bbox = face.global_bounding_box();
    let underline = face.underline_metrics();
    let root = json!({
        "glyphs": glyphs,
        "familyName": family_name,
        "ascender": round_f64(f64::from(face.ascender()) * scale),
        "descender": round_f64(f64::from(face.descender()) * scale),
        "underlinePosition": underline
            .map(|metrics| round_f64(f64::from(metrics.position) * scale))
            .unwrap_or(0),
        "underlineThickness": underline
            .map(|metrics| round_f64(f64::from(metrics.thickness) * scale))
            .unwrap_or(0),
        "boundingBox": {
            "yMin": round_f64(f64::from(bbox.y_min) * scale),
            "xMin": round_f64(f64::from(bbox.x_min) * scale),
            "yMax": round_f64(f64::from(bbox.y_max) * scale),
            "xMax": round_f64(f64::from(bbox.x_max) * scale),
        },
        "resolution": 1000,
        "original_font_information": font_names_json(&face),
        "cssFontWeight": if face.is_bold() { "bold" } else { "normal" },
        "cssFontStyle": if face.is_italic() { "italic" } else { "normal" },
    });
    let json = serde_json::to_string(&root)
        .map_err(|error| format!("字体 JSON 生成失败: {error}"))?;
    Ok(CubeTextFontConvertResult {
        font_id: family_name,
        json,
    })
}

fn glyph_json_for_ttf_glyph(face: &Face<'_>, glyph_id: GlyphId, scale: f64) -> Option<Value> {
    let mut builder = FaceTypeOutlineBuilder::new(scale);
    let bounds = face.outline_glyph(glyph_id, &mut builder)?;
    if builder.commands.trim().is_empty() {
        return None;
    }
    Some(json!({
        "ha": round_f64(f64::from(face.glyph_hor_advance(glyph_id).unwrap_or_default()) * scale),
        "x_min": round_f64(f64::from(bounds.x_min) * scale),
        "x_max": round_f64(f64::from(bounds.x_max) * scale),
        "o": builder.commands.trim_end(),
    }))
}

fn font_name(face: &Face<'_>) -> Option<String> {
    let preferred = [
        name_id::FULL_NAME,
        name_id::TYPOGRAPHIC_FAMILY,
        name_id::FAMILY,
    ];
    for target in preferred {
        let mut fallback = None;
        for name in face.names() {
            if name.name_id != target {
                continue;
            }
            let Some(value) = name.to_string() else {
                continue;
            };
            let trimmed = value.trim();
            if trimmed.is_empty() {
                continue;
            }
            if name.language_id == 0x0409 || name.language_id == 0 {
                return Some(trimmed.to_string());
            }
            fallback.get_or_insert_with(|| trimmed.to_string());
        }
        if fallback.is_some() {
            return fallback;
        }
    }
    None
}

fn font_names_json(face: &Face<'_>) -> Value {
    let mut by_id: BTreeMap<String, String> = BTreeMap::new();
    for name in face.names() {
        let Some(value) = name.to_string() else {
            continue;
        };
        let trimmed = value.trim();
        if trimmed.is_empty() {
            continue;
        }
        by_id
            .entry(name.name_id.to_string())
            .or_insert_with(|| trimmed.to_string());
    }
    json!(by_id)
}

fn round_f64(value: f64) -> i64 {
    value.round() as i64
}

struct FaceTypeOutlineBuilder {
    scale: f64,
    commands: String,
}

impl FaceTypeOutlineBuilder {
    fn new(scale: f64) -> Self {
        Self {
            scale,
            commands: String::new(),
        }
    }

    fn push_point(&mut self, x: f32, y: f32) {
        self.commands
            .push_str(&format!("{} {} ", round_f64(f64::from(x) * self.scale), round_f64(f64::from(y) * self.scale)));
    }
}

impl OutlineBuilder for FaceTypeOutlineBuilder {
    fn move_to(&mut self, x: f32, y: f32) {
        self.commands.push_str("m ");
        self.push_point(x, y);
    }

    fn line_to(&mut self, x: f32, y: f32) {
        self.commands.push_str("l ");
        self.push_point(x, y);
    }

    fn quad_to(&mut self, x1: f32, y1: f32, x: f32, y: f32) {
        self.commands.push_str("q ");
        self.push_point(x1, y1);
        self.push_point(x, y);
    }

    fn curve_to(&mut self, x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) {
        self.commands.push_str("b ");
        self.push_point(x1, y1);
        self.push_point(x2, y2);
        self.push_point(x, y);
    }

    fn close(&mut self) {
        self.commands.push_str("z ");
    }
}

fn append_text_materials(
    text_index: usize,
    source: &CubeTextMaterials,
    materials: &mut Vec<CubeTextSceneMaterial>,
) {
    let items = [
        ("right", &source.right),
        ("left", &source.left),
        ("up", &source.up),
        ("down", &source.down),
        ("front", &source.front),
        ("back", &source.back),
        ("outline", &source.outline),
    ];
    for (slot, option) in items {
        materials.push(CubeTextSceneMaterial {
            name: format!("text{}_{}", text_index + 1, slot),
            slot: slot.to_string(),
            option: option.clone(),
        });
    }
}

fn build_text_mesh(
    font: &FontJson,
    text: &CubeTextObject,
    material_base: i32,
    mesh: &mut MeshBuilder,
    warnings: &mut Vec<String>,
    font_id: &str,
) {
    let size = text.opts.size.max(0.1) as f64;
    let depth = text.opts.depth.max(0.01) as f64;
    let spacing_width = text.opts.spacing_width as f64;
    let letter_spacing = text.opts.letter_spacing as f64;
    let outline_ratio = text.opts.outline_width.max(0.0) as f64;

    let shapes = layout_text_shapes(
        font,
        &text.content,
        size,
        spacing_width,
        letter_spacing,
        warnings,
        font_id,
    );
    if shapes.is_empty() {
        return;
    }

    let main_bounds = shapes_bounds(&shapes);
    let main_center = bounds_center(main_bounds);
    let transform = TextTransform::from_options(&text.opts);
    extrude_shapes(
        &shapes,
        depth,
        main_center,
        &transform,
        material_base,
        false,
        mesh,
    );

    if outline_ratio > 0.0 {
        let height = (main_bounds.max.y - main_bounds.min.y).abs().max(size);
        let outline_width = outline_ratio * (height / 10.0);
        let outline_shapes = create_outline_shapes(&shapes, outline_width);
        if !outline_shapes.is_empty() {
            let outline_bounds = shapes_bounds(&outline_shapes);
            let outline_center = bounds_center(outline_bounds);
            extrude_shapes(
                &outline_shapes,
                depth + outline_width * 2.0,
                outline_center,
                &transform,
                material_base,
                true,
                mesh,
            );
        }
    }
}

fn layout_text_shapes(
    font: &FontJson,
    text: &str,
    size: f64,
    spacing_width: f64,
    letter_spacing: f64,
    warnings: &mut Vec<String>,
    font_id: &str,
) -> Vec<Shape2D> {
    let mut shapes = Vec::new();
    let mut offset_x = 0.0;
    let spacing = size * 0.12;
    let scale = size / font.resolution.unwrap_or(1000.0).max(1.0);

    for ch in text.chars() {
        if ch == ' ' {
            offset_x += size * spacing_width + letter_spacing * spacing;
            continue;
        }

        let key = ch.to_string();
        let glyph = font.glyphs.get(&key);
        let mut glyph_shapes = match glyph.and_then(|g| g.o.as_deref()) {
            Some(outline) if !outline.trim().is_empty() => {
                shapes_from_glyph_outline(outline, scale, offset_x)
            }
            _ => Vec::new(),
        };

        let char_width = if glyph_shapes.is_empty() {
            warnings.push(format!(
                "字体 {} 不支持字符 \"{}\"，已使用方块占位符。",
                font.family_name.as_deref().unwrap_or(font_id),
                ch
            ));
            glyph_shapes = placeholder_shapes(offset_x, size);
            size * PLACEHOLDER_WIDTH_RATIO
        } else {
            glyph
                .and_then(|g| match (g.x_min, g.x_max) {
                    (Some(min), Some(max)) if max > min => Some((max - min) * scale),
                    _ => None,
                })
                .or_else(|| {
                    let bounds = shapes_bounds(&glyph_shapes);
                    let width = bounds.max.x - bounds.min.x;
                    (width > EPSILON).then_some(width)
                })
                .or_else(|| glyph.and_then(|g| g.ha).map(|ha| ha * scale))
                .unwrap_or(size)
        };

        shapes.append(&mut glyph_shapes);
        offset_x += char_width + letter_spacing * spacing;
    }
    shapes
}

fn shapes_from_glyph_outline(outline: &str, scale: f64, offset_x: f64) -> Vec<Shape2D> {
    let contours = parse_glyph_contours(outline, scale, offset_x);
    contours_to_shapes(contours)
}

fn parse_glyph_contours(outline: &str, scale: f64, offset_x: f64) -> Vec<Vec<P2>> {
    let tokens: Vec<&str> = outline.split_whitespace().collect();
    let mut index = 0usize;
    let mut contours: Vec<Vec<P2>> = Vec::new();
    let mut current: Vec<P2> = Vec::new();
    let mut cursor = p2_zero();

    while index < tokens.len() {
        let command = tokens[index];
        index += 1;
        match command {
            "m" => {
                finish_contour(&mut current, &mut contours);
                let Some(x) = parse_number(&tokens, &mut index) else {
                    break;
                };
                let Some(y) = parse_number(&tokens, &mut index) else {
                    break;
                };
                cursor = P2 {
                    x: x * scale + offset_x,
                    y: y * scale,
                };
                current.push(cursor);
            }
            "l" => {
                let Some(x) = parse_number(&tokens, &mut index) else {
                    break;
                };
                let Some(y) = parse_number(&tokens, &mut index) else {
                    break;
                };
                cursor = P2 {
                    x: x * scale + offset_x,
                    y: y * scale,
                };
                current.push(cursor);
            }
            "q" => {
                let Some(cpx) = parse_number(&tokens, &mut index) else {
                    break;
                };
                let Some(cpy) = parse_number(&tokens, &mut index) else {
                    break;
                };
                let Some(x) = parse_number(&tokens, &mut index) else {
                    break;
                };
                let Some(y) = parse_number(&tokens, &mut index) else {
                    break;
                };
                let control = P2 {
                    x: cpx * scale + offset_x,
                    y: cpy * scale,
                };
                let to = P2 {
                    x: x * scale + offset_x,
                    y: y * scale,
                };
                for step in 1..=CURVE_SEGMENTS {
                    let t = step as f64 / CURVE_SEGMENTS as f64;
                    current.push(quadratic_point(cursor, control, to, t));
                }
                cursor = to;
            }
            "b" => {
                let Some(cp1x) = parse_number(&tokens, &mut index) else {
                    break;
                };
                let Some(cp1y) = parse_number(&tokens, &mut index) else {
                    break;
                };
                let Some(cp2x) = parse_number(&tokens, &mut index) else {
                    break;
                };
                let Some(cp2y) = parse_number(&tokens, &mut index) else {
                    break;
                };
                let Some(x) = parse_number(&tokens, &mut index) else {
                    break;
                };
                let Some(y) = parse_number(&tokens, &mut index) else {
                    break;
                };
                let c1 = P2 {
                    x: cp1x * scale + offset_x,
                    y: cp1y * scale,
                };
                let c2 = P2 {
                    x: cp2x * scale + offset_x,
                    y: cp2y * scale,
                };
                let to = P2 {
                    x: x * scale + offset_x,
                    y: y * scale,
                };
                for step in 1..=CURVE_SEGMENTS {
                    let t = step as f64 / CURVE_SEGMENTS as f64;
                    current.push(cubic_point(cursor, c1, c2, to, t));
                }
                cursor = to;
            }
            "z" => {
                finish_contour(&mut current, &mut contours);
            }
            _ => {}
        }
    }
    finish_contour(&mut current, &mut contours);
    contours
}

fn parse_number(tokens: &[&str], index: &mut usize) -> Option<f64> {
    let token = *tokens.get(*index)?;
    *index += 1;
    token.parse::<f64>().ok()
}

fn finish_contour(current: &mut Vec<P2>, contours: &mut Vec<Vec<P2>>) {
    let mut cleaned = clean_loop(current);
    if cleaned.len() >= 3 && polygon_area(&cleaned).abs() > EPSILON {
        contours.push(std::mem::take(&mut cleaned));
    }
    current.clear();
}

fn clean_loop(points: &[P2]) -> Vec<P2> {
    let mut cleaned = Vec::new();
    for &point in points {
        if cleaned
            .last()
            .map(|last| distance2(*last, point) > EPSILON * EPSILON)
            .unwrap_or(true)
        {
            cleaned.push(point);
        }
    }
    if cleaned.len() > 1 && distance2(cleaned[0], *cleaned.last().unwrap()) <= EPSILON * EPSILON {
        cleaned.pop();
    }
    cleaned
}

fn contours_to_shapes(contours: Vec<Vec<P2>>) -> Vec<Shape2D> {
    if contours.is_empty() {
        return Vec::new();
    }
    let mut infos: Vec<ContourInfo> = contours
        .into_iter()
        .map(|points| ContourInfo {
            area_abs: polygon_area(&points).abs(),
            points,
            parent: None,
            depth: 0,
        })
        .collect();

    for i in 0..infos.len() {
        let probe = sample_point(&infos[i].points);
        let mut parent = None;
        let mut parent_area = f64::MAX;
        for j in 0..infos.len() {
            if i == j || infos[j].area_abs <= infos[i].area_abs {
                continue;
            }
            if point_in_polygon(probe, &infos[j].points) && infos[j].area_abs < parent_area {
                parent = Some(j);
                parent_area = infos[j].area_abs;
            }
        }
        infos[i].parent = parent;
    }

    for i in 0..infos.len() {
        let mut depth = 0;
        let mut parent = infos[i].parent;
        while let Some(parent_index) = parent {
            depth += 1;
            parent = infos[parent_index].parent;
        }
        infos[i].depth = depth;
    }

    let mut shapes = Vec::new();
    for i in 0..infos.len() {
        if infos[i].depth % 2 != 0 {
            continue;
        }
        let mut outer = infos[i].points.clone();
        ensure_orientation(&mut outer, true);
        let mut holes = Vec::new();
        for j in 0..infos.len() {
            if infos[j].parent == Some(i) && infos[j].depth % 2 == 1 {
                let mut hole = infos[j].points.clone();
                ensure_orientation(&mut hole, false);
                holes.push(hole);
            }
        }
        shapes.push(Shape2D { outer, holes });
    }
    shapes
}

struct ContourInfo {
    points: Vec<P2>,
    area_abs: f64,
    parent: Option<usize>,
    depth: usize,
}

fn placeholder_shapes(offset_x: f64, size: f64) -> Vec<Shape2D> {
    let width = size * PLACEHOLDER_WIDTH_RATIO;
    let height = size * PLACEHOLDER_HEIGHT_RATIO;
    vec![Shape2D {
        outer: vec![
            P2 { x: offset_x, y: 0.0 },
            P2 {
                x: offset_x + width,
                y: 0.0,
            },
            P2 {
                x: offset_x + width,
                y: height,
            },
            P2 {
                x: offset_x,
                y: height,
            },
        ],
        holes: Vec::new(),
    }]
}

fn create_outline_shapes(shapes: &[Shape2D], outline_width: f64) -> Vec<Shape2D> {
    let mut result = Vec::new();
    for shape in shapes {
        let mut outer = shape.outer.clone();
        ensure_orientation(&mut outer, true);
        let expanded = offset_polygon_miter(&outer, outline_width);
        if expanded.len() >= 3 && polygon_area(&expanded).abs() > EPSILON {
            result.push(Shape2D {
                outer: expanded,
                holes: Vec::new(),
            });
        }
    }
    result
}

fn offset_polygon_miter(points: &[P2], distance: f64) -> Vec<P2> {
    if points.len() < 3 || distance <= EPSILON {
        return points.to_vec();
    }
    let ccw = polygon_area(points) > 0.0;
    let count = points.len();
    let mut result = Vec::with_capacity(count);
    for i in 0..count {
        let prev = points[(i + count - 1) % count];
        let curr = points[i];
        let next = points[(i + 1) % count];
        let e1 = normalize(P2 {
            x: curr.x - prev.x,
            y: curr.y - prev.y,
        });
        let e2 = normalize(P2 {
            x: next.x - curr.x,
            y: next.y - curr.y,
        });
        let n1 = outward_normal(e1, ccw);
        let n2 = outward_normal(e2, ccw);
        let p1 = P2 {
            x: curr.x + n1.x * distance,
            y: curr.y + n1.y * distance,
        };
        let p2 = P2 {
            x: curr.x + n2.x * distance,
            y: curr.y + n2.y * distance,
        };
        if let Some(intersection) = line_intersection(p1, e1, p2, e2) {
            if distance2(intersection, curr) < distance * distance * 100.0 {
                result.push(intersection);
                continue;
            }
        }
        let joined = normalize(P2 {
            x: n1.x + n2.x,
            y: n1.y + n2.y,
        });
        result.push(P2 {
            x: curr.x + joined.x * distance,
            y: curr.y + joined.y * distance,
        });
    }
    result
}

fn extrude_shapes(
    shapes: &[Shape2D],
    depth: f64,
    center: P2,
    transform: &TextTransform,
    material_base: i32,
    outline: bool,
    mesh: &mut MeshBuilder,
) {
    let bounds = shapes_bounds(shapes);
    let z_front = depth / 2.0;
    let z_back = -depth / 2.0;
    for shape in shapes {
        let triangles = triangulate_shape(shape);
        for tri in triangles {
            let p0 = local_p3(tri[0], center, z_front);
            let p1 = local_p3(tri[1], center, z_front);
            let p2 = local_p3(tri[2], center, z_front);
            add_triangle(
                mesh,
                [p0, p1, p2],
                material_base + if outline { 6 } else { 4 },
                transform,
                bounds,
                depth,
            );
            let b0 = local_p3(tri[2], center, z_back);
            let b1 = local_p3(tri[1], center, z_back);
            let b2 = local_p3(tri[0], center, z_back);
            add_triangle(
                mesh,
                [b0, b1, b2],
                material_base + if outline { 6 } else { 5 },
                transform,
                bounds,
                depth,
            );
        }

        add_side_loop(
            &shape.outer,
            center,
            z_front,
            z_back,
            true,
            transform,
            material_base,
            outline,
            bounds,
            depth,
            mesh,
        );
        for hole in &shape.holes {
            add_side_loop(
                hole,
                center,
                z_front,
                z_back,
                false,
                transform,
                material_base,
                outline,
                bounds,
                depth,
                mesh,
            );
        }
    }
}

fn triangulate_shape(shape: &Shape2D) -> Vec<[P2; 3]> {
    let mut vertices = Vec::<Point2<f64>>::new();
    let mut edges = Vec::<[usize; 2]>::new();
    append_loop_for_triangulation(&shape.outer, &mut vertices, &mut edges);
    for hole in &shape.holes {
        append_loop_for_triangulation(hole, &mut vertices, &mut edges);
    }
    if vertices.len() < 3 {
        return Vec::new();
    }

    let triangulation =
        match ConstrainedDelaunayTriangulation::<Point2<f64>>::try_bulk_load_cdt(
            vertices,
            edges,
            |_| {},
        ) {
            Ok(value) => value,
            Err(_) => return triangulate_simple_polygon(&shape.outer),
        };

    let mut result = Vec::new();
    for face in triangulation.inner_faces() {
        let verts = face.vertices();
        let tri = [
            p2_from_point(verts[0].position()),
            p2_from_point(verts[1].position()),
            p2_from_point(verts[2].position()),
        ];
        let centroid = P2 {
            x: (tri[0].x + tri[1].x + tri[2].x) / 3.0,
            y: (tri[0].y + tri[1].y + tri[2].y) / 3.0,
        };
        if !point_in_shape(centroid, shape) {
            continue;
        }
        if polygon_area(&tri) < 0.0 {
            result.push([tri[0], tri[2], tri[1]]);
        } else {
            result.push(tri);
        }
    }
    result
}

fn append_loop_for_triangulation(
    points: &[P2],
    vertices: &mut Vec<Point2<f64>>,
    edges: &mut Vec<[usize; 2]>,
) {
    let start = vertices.len();
    for point in points {
        vertices.push(Point2::new(point.x, point.y));
    }
    let len = points.len();
    if len >= 2 {
        for i in 0..len {
            edges.push([start + i, start + ((i + 1) % len)]);
        }
    }
}

fn triangulate_simple_polygon(points: &[P2]) -> Vec<[P2; 3]> {
    let mut polygon = clean_loop(points);
    ensure_orientation(&mut polygon, true);
    let mut indices: Vec<usize> = (0..polygon.len()).collect();
    let mut result = Vec::new();
    let mut guard = 0usize;
    while indices.len() > 3 && guard < polygon.len() * polygon.len() {
        guard += 1;
        let mut clipped = false;
        for i in 0..indices.len() {
            let prev = indices[(i + indices.len() - 1) % indices.len()];
            let curr = indices[i];
            let next = indices[(i + 1) % indices.len()];
            let a = polygon[prev];
            let b = polygon[curr];
            let c = polygon[next];
            if cross(a, b, c) <= EPSILON {
                continue;
            }
            let mut contains = false;
            for &candidate in &indices {
                if candidate == prev || candidate == curr || candidate == next {
                    continue;
                }
                if point_in_triangle(polygon[candidate], a, b, c) {
                    contains = true;
                    break;
                }
            }
            if contains {
                continue;
            }
            result.push([a, b, c]);
            indices.remove(i);
            clipped = true;
            break;
        }
        if !clipped {
            break;
        }
    }
    if indices.len() == 3 {
        result.push([polygon[indices[0]], polygon[indices[1]], polygon[indices[2]]]);
    }
    result
}

#[allow(clippy::too_many_arguments)]
fn add_side_loop(
    loop_points: &[P2],
    center: P2,
    z_front: f64,
    z_back: f64,
    outer: bool,
    transform: &TextTransform,
    material_base: i32,
    outline: bool,
    bounds: Bounds2D,
    depth: f64,
    mesh: &mut MeshBuilder,
) {
    if loop_points.len() < 2 {
        return;
    }
    let ccw = polygon_area(loop_points) > 0.0;
    for i in 0..loop_points.len() {
        let a2 = loop_points[i];
        let b2 = loop_points[(i + 1) % loop_points.len()];
        if distance2(a2, b2) <= EPSILON * EPSILON {
            continue;
        }
        let edge = normalize(P2 {
            x: b2.x - a2.x,
            y: b2.y - a2.y,
        });
        let mut normal2 = outward_normal(edge, ccw);
        if !outer {
            normal2.x = -normal2.x;
            normal2.y = -normal2.y;
        }
        let material = if outline {
            material_base + 6
        } else {
            material_base + side_material_slot(normal2)
        };
        let af = local_p3(a2, center, z_front);
        let bf = local_p3(b2, center, z_front);
        let ab = local_p3(a2, center, z_back);
        let bb = local_p3(b2, center, z_back);
        if outer {
            add_triangle(mesh, [af, ab, bb], material, transform, bounds, depth);
            add_triangle(mesh, [af, bb, bf], material, transform, bounds, depth);
        } else {
            add_triangle(mesh, [af, bf, bb], material, transform, bounds, depth);
            add_triangle(mesh, [af, bb, ab], material, transform, bounds, depth);
        }
    }
}

fn side_material_slot(normal: P2) -> i32 {
    if normal.x.abs() >= normal.y.abs() {
        if normal.x >= 0.0 {
            0
        } else {
            1
        }
    } else if normal.y >= 0.0 {
        2
    } else {
        3
    }
}

fn add_triangle(
    mesh: &mut MeshBuilder,
    points: [P3; 3],
    material_index: i32,
    transform: &TextTransform,
    bounds: Bounds2D,
    depth: f64,
) {
    let normal = normalize3(cross3(
        sub3(points[1], points[0]),
        sub3(points[2], points[0]),
    ));
    let base = (mesh.positions.len() / 3) as u32;
    for point in points {
        let transformed = transform.apply(point);
        let transformed_normal = transform.apply_normal(normal);
        let uv = uv_for_point(point, normal, bounds, depth);
        mesh.positions.extend_from_slice(&[
            transformed.x as f32,
            transformed.y as f32,
            transformed.z as f32,
        ]);
        mesh.normals.extend_from_slice(&[
            transformed_normal.x as f32,
            transformed_normal.y as f32,
            transformed_normal.z as f32,
        ]);
        mesh.uvs.extend_from_slice(&[uv.x as f32, uv.y as f32]);
    }
    mesh.indices.extend_from_slice(&[base, base + 1, base + 2]);
    mesh.material_indices.push(material_index);
}

fn uv_for_point(point: P3, normal: P3, bounds: Bounds2D, depth: f64) -> P2 {
    let width = (bounds.max.x - bounds.min.x).abs().max(EPSILON);
    let height = (bounds.max.y - bounds.min.y).abs().max(EPSILON);
    if normal.z.abs() >= normal.x.abs() && normal.z.abs() >= normal.y.abs() {
        P2 {
            x: ((point.x + (bounds.max.x + bounds.min.x) / 2.0) - bounds.min.x) / width,
            y: ((point.y + (bounds.max.y + bounds.min.y) / 2.0) - bounds.min.y) / height,
        }
    } else if normal.y.abs() >= normal.x.abs() {
        P2 {
            x: ((point.x + (bounds.max.x + bounds.min.x) / 2.0) - bounds.min.x) / width,
            y: (point.z + depth / 2.0) / depth.max(EPSILON),
        }
    } else {
        P2 {
            x: ((point.y + (bounds.max.y + bounds.min.y) / 2.0) - bounds.min.y) / height,
            y: (point.z + depth / 2.0) / depth.max(EPSILON),
        }
    }
}

fn local_p3(point: P2, center: P2, z: f64) -> P3 {
    P3 {
        x: point.x - center.x,
        y: point.y - center.y,
        z,
    }
}

#[derive(Clone, Copy, Debug)]
struct TextTransform {
    position: P3,
    sx: f64,
    cx: f64,
    sy: f64,
    cy: f64,
    sz: f64,
    cz: f64,
}

impl TextTransform {
    fn from_options(opts: &CubeTextOptions) -> Self {
        let rx = (opts.rot_y as f64).to_radians();
        let ry = (opts.rot_x as f64).to_radians();
        let rz = (opts.rot_z as f64).to_radians();
        Self {
            position: P3 {
                x: opts.x as f64,
                y: opts.y as f64,
                z: opts.z as f64,
            },
            sx: rx.sin(),
            cx: rx.cos(),
            sy: ry.sin(),
            cy: ry.cos(),
            sz: rz.sin(),
            cz: rz.cos(),
        }
    }

    fn apply(&self, point: P3) -> P3 {
        let rotated = self.rotate(point);
        P3 {
            x: rotated.x + self.position.x,
            y: rotated.y + self.position.y,
            z: rotated.z + self.position.z,
        }
    }

    fn apply_normal(&self, normal: P3) -> P3 {
        normalize3(self.rotate(normal))
    }

    fn rotate(&self, point: P3) -> P3 {
        let x1 = point.x;
        let y1 = point.y * self.cx - point.z * self.sx;
        let z1 = point.y * self.sx + point.z * self.cx;

        let x2 = x1 * self.cy + z1 * self.sy;
        let y2 = y1;
        let z2 = -x1 * self.sy + z1 * self.cy;

        P3 {
            x: x2 * self.cz - y2 * self.sz,
            y: x2 * self.sz + y2 * self.cz,
            z: z2,
        }
    }
}

fn export_obj(scene: &CubeTextScene) -> Vec<u8> {
    let mut output = String::new();
    output.push_str("# cube-3d-text generated by Misa Rin\n");
    for material in &scene.materials {
        output.push_str(&format!(
            "# material {} slot={} mode={} color={}\n",
            material.name, material.slot, material.option.mode, material.option.color
        ));
    }
    for vertex in scene.positions.chunks_exact(3) {
        output.push_str(&format!("v {} {} {}\n", vertex[0], vertex[1], vertex[2]));
    }
    for uv in scene.uvs.chunks_exact(2) {
        output.push_str(&format!("vt {} {}\n", uv[0], uv[1]));
    }
    for normal in scene.normals.chunks_exact(3) {
        output.push_str(&format!("vn {} {} {}\n", normal[0], normal[1], normal[2]));
    }
    let mut last_material = None;
    for (tri_index, tri) in scene.indices.chunks_exact(3).enumerate() {
        let material_index = scene
            .material_indices
            .get(tri_index)
            .copied()
            .unwrap_or_default()
            .max(0) as usize;
        if last_material != Some(material_index) {
            let name = scene
                .materials
                .get(material_index)
                .map(|m| m.name.as_str())
                .unwrap_or("default");
            output.push_str(&format!("usemtl {}\n", name));
            last_material = Some(material_index);
        }
        output.push_str("f");
        for &index in tri {
            let obj_index = index + 1;
            output.push_str(&format!(" {0}/{0}/{0}", obj_index));
        }
        output.push('\n');
    }
    output.into_bytes()
}

fn export_stl(scene: &CubeTextScene) -> Vec<u8> {
    let mut output = String::from("solid cube_3d_text\n");
    for tri in scene.indices.chunks_exact(3) {
        let normal = normal_at(scene, tri[0] as usize);
        output.push_str(&format!(
            "  facet normal {} {} {}\n    outer loop\n",
            normal.x, normal.y, normal.z
        ));
        for &index in tri {
            let vertex = vertex_at(scene, index as usize);
            output.push_str(&format!(
                "      vertex {} {} {}\n",
                vertex.x, vertex.y, vertex.z
            ));
        }
        output.push_str("    endloop\n  endfacet\n");
    }
    output.push_str("endsolid cube_3d_text\n");
    output.into_bytes()
}

fn export_gltf(scene: &CubeTextScene, binary: bool) -> Result<Vec<u8>, String> {
    let mut buffer = Vec::<u8>::new();
    let positions_view = push_f32_buffer(&mut buffer, &scene.positions);
    let normals_view = push_f32_buffer(&mut buffer, &scene.normals);
    let uvs_view = push_f32_buffer(&mut buffer, &scene.uvs);

    let mut index_views = Vec::new();
    for material_index in 0..scene.materials.len() {
        let mut indices = Vec::<u32>::new();
        for (tri_index, tri) in scene.indices.chunks_exact(3).enumerate() {
            if scene
                .material_indices
                .get(tri_index)
                .copied()
                .unwrap_or_default()
                .max(0) as usize
                == material_index
            {
                indices.extend_from_slice(tri);
            }
        }
        index_views.push(push_u32_buffer(&mut buffer, &indices));
    }
    pad4(&mut buffer, 0);

    let position_count = scene.positions.len() / 3;
    let normal_count = scene.normals.len() / 3;
    let uv_count = scene.uvs.len() / 2;
    let bounds_min = if scene.bounds_min.len() == 3 {
        scene.bounds_min.clone()
    } else {
        vec![0.0, 0.0, 0.0]
    };
    let bounds_max = if scene.bounds_max.len() == 3 {
        scene.bounds_max.clone()
    } else {
        vec![0.0, 0.0, 0.0]
    };

    let mut buffer_views = Vec::new();
    buffer_views.push(json!({
        "buffer": 0,
        "byteOffset": positions_view.0,
        "byteLength": positions_view.1,
        "target": 34962
    }));
    buffer_views.push(json!({
        "buffer": 0,
        "byteOffset": normals_view.0,
        "byteLength": normals_view.1,
        "target": 34962
    }));
    buffer_views.push(json!({
        "buffer": 0,
        "byteOffset": uvs_view.0,
        "byteLength": uvs_view.1,
        "target": 34962
    }));
    for view in &index_views {
        buffer_views.push(json!({
            "buffer": 0,
            "byteOffset": view.0,
            "byteLength": view.1,
            "target": 34963
        }));
    }

    let mut accessors = Vec::new();
    accessors.push(json!({
        "bufferView": 0,
        "componentType": 5126,
        "count": position_count,
        "type": "VEC3",
        "min": bounds_min,
        "max": bounds_max
    }));
    accessors.push(json!({
        "bufferView": 1,
        "componentType": 5126,
        "count": normal_count,
        "type": "VEC3"
    }));
    accessors.push(json!({
        "bufferView": 2,
        "componentType": 5126,
        "count": uv_count,
        "type": "VEC2"
    }));
    for (i, view) in index_views.iter().enumerate() {
        let count = view.1 / 4;
        accessors.push(json!({
            "bufferView": 3 + i,
            "componentType": 5125,
            "count": count,
            "type": "SCALAR"
        }));
    }

    let mut images = Vec::new();
    let mut textures = Vec::new();
    let mut materials = Vec::new();
    for material in &scene.materials {
        let color = material_base_color(&material.option);
        let mut pbr = json!({
            "baseColorFactor": [color[0], color[1], color[2], color[3]],
            "roughnessFactor": 1.0,
            "metallicFactor": 0.0
        });
        if material.option.mode == "image" && material.option.image.starts_with("data:image/") {
            let image_index = images.len();
            images.push(json!({"uri": material.option.image}));
            let texture_index = textures.len();
            textures.push(json!({"source": image_index}));
            pbr["baseColorTexture"] = json!({"index": texture_index});
        }
        materials.push(json!({
            "name": material.name,
            "pbrMetallicRoughness": pbr,
            "doubleSided": true
        }));
    }

    let mut primitives = Vec::new();
    for material_index in 0..scene.materials.len() {
        let count = index_views[material_index].1 / 4;
        if count == 0 {
            continue;
        }
        primitives.push(json!({
            "attributes": {
                "POSITION": 0,
                "NORMAL": 1,
                "TEXCOORD_0": 2
            },
            "indices": 3 + material_index,
            "material": material_index,
            "mode": 4
        }));
    }

    let buffer_json = if binary {
        json!({"byteLength": buffer.len()})
    } else {
        json!({
            "byteLength": buffer.len(),
            "uri": format!("data:application/octet-stream;base64,{}", base64_encode(&buffer))
        })
    };

    let mut root = json!({
        "asset": {
            "version": "2.0",
            "generator": "Misa Rin cube-3d-text mesh pipeline"
        },
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "cube-3d-text", "mesh": 0}],
        "meshes": [{"name": "cube-3d-text", "primitives": primitives}],
        "materials": materials,
        "buffers": [buffer_json],
        "bufferViews": buffer_views,
        "accessors": accessors
    });
    if !images.is_empty() {
        root["images"] = json!(images);
        root["textures"] = json!(textures);
    }

    let json_bytes = serde_json::to_vec_pretty(&root)
        .map_err(|error| format!("glTF JSON 生成失败: {error}"))?;
    if !binary {
        return Ok(json_bytes);
    }
    Ok(build_glb(json_bytes, buffer))
}

fn push_f32_buffer(buffer: &mut Vec<u8>, values: &[f32]) -> (usize, usize) {
    pad4(buffer, 0);
    let start = buffer.len();
    for value in values {
        buffer.extend_from_slice(&value.to_le_bytes());
    }
    (start, buffer.len() - start)
}

fn push_u32_buffer(buffer: &mut Vec<u8>, values: &[u32]) -> (usize, usize) {
    pad4(buffer, 0);
    let start = buffer.len();
    for value in values {
        buffer.extend_from_slice(&value.to_le_bytes());
    }
    (start, buffer.len() - start)
}

fn build_glb(mut json_bytes: Vec<u8>, mut bin: Vec<u8>) -> Vec<u8> {
    pad4(&mut json_bytes, b' ');
    pad4(&mut bin, 0);
    let total_len = 12 + 8 + json_bytes.len() + 8 + bin.len();
    let mut glb = Vec::with_capacity(total_len);
    glb.extend_from_slice(&0x46546C67u32.to_le_bytes());
    glb.extend_from_slice(&2u32.to_le_bytes());
    glb.extend_from_slice(&(total_len as u32).to_le_bytes());
    glb.extend_from_slice(&(json_bytes.len() as u32).to_le_bytes());
    glb.extend_from_slice(&0x4E4F534Au32.to_le_bytes());
    glb.extend_from_slice(&json_bytes);
    glb.extend_from_slice(&(bin.len() as u32).to_le_bytes());
    glb.extend_from_slice(&0x004E4942u32.to_le_bytes());
    glb.extend_from_slice(&bin);
    glb
}

fn pad4(buffer: &mut Vec<u8>, value: u8) {
    while buffer.len() % 4 != 0 {
        buffer.push(value);
    }
}

fn material_base_color(option: &CubeTextMaterialOption) -> [f32; 4] {
    if option.mode == "gradient" {
        let a = parse_color(&option.color_gradual_start).unwrap_or([1.0, 1.0, 1.0, 1.0]);
        let b = parse_color(&option.color_gradual_end).unwrap_or(a);
        [
            (a[0] + b[0]) * 0.5,
            (a[1] + b[1]) * 0.5,
            (a[2] + b[2]) * 0.5,
            1.0,
        ]
    } else {
        parse_color(&option.color).unwrap_or([1.0, 1.0, 1.0, 1.0])
    }
}

fn parse_color(value: &str) -> Option<[f32; 4]> {
    let trimmed = value.trim();
    if let Some(hex) = trimmed.strip_prefix('#') {
        if hex.len() == 6 || hex.len() == 8 {
            let r = u8::from_str_radix(&hex[0..2], 16).ok()? as f32 / 255.0;
            let g = u8::from_str_radix(&hex[2..4], 16).ok()? as f32 / 255.0;
            let b = u8::from_str_radix(&hex[4..6], 16).ok()? as f32 / 255.0;
            let a = if hex.len() == 8 {
                u8::from_str_radix(&hex[6..8], 16).ok()? as f32 / 255.0
            } else {
                1.0
            };
            return Some([r, g, b, a]);
        }
    }
    if trimmed.starts_with("rgb(") || trimmed.starts_with("rgba(") {
        let start = trimmed.find('(')?;
        let end = trimmed.rfind(')')?;
        let parts: Vec<&str> = trimmed[start + 1..end].split(',').collect();
        if parts.len() >= 3 {
            let r = parts[0].trim().parse::<f32>().ok()? / 255.0;
            let g = parts[1].trim().parse::<f32>().ok()? / 255.0;
            let b = parts[2].trim().parse::<f32>().ok()? / 255.0;
            let a = parts
                .get(3)
                .and_then(|part| part.trim().parse::<f32>().ok())
                .unwrap_or(1.0);
            return Some([r, g, b, a]);
        }
    }
    None
}

fn base64_encode(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut output = String::with_capacity(bytes.len().div_ceil(3) * 4);
    let mut index = 0usize;
    while index < bytes.len() {
        let b0 = bytes[index];
        let b1 = *bytes.get(index + 1).unwrap_or(&0);
        let b2 = *bytes.get(index + 2).unwrap_or(&0);
        let triple = ((b0 as u32) << 16) | ((b1 as u32) << 8) | b2 as u32;
        output.push(TABLE[((triple >> 18) & 0x3f) as usize] as char);
        output.push(TABLE[((triple >> 12) & 0x3f) as usize] as char);
        if index + 1 < bytes.len() {
            output.push(TABLE[((triple >> 6) & 0x3f) as usize] as char);
        } else {
            output.push('=');
        }
        if index + 2 < bytes.len() {
            output.push(TABLE[(triple & 0x3f) as usize] as char);
        } else {
            output.push('=');
        }
        index += 3;
    }
    output
}

fn vertex_at(scene: &CubeTextScene, index: usize) -> P3 {
    let base = index * 3;
    P3 {
        x: *scene.positions.get(base).unwrap_or(&0.0) as f64,
        y: *scene.positions.get(base + 1).unwrap_or(&0.0) as f64,
        z: *scene.positions.get(base + 2).unwrap_or(&0.0) as f64,
    }
}

fn normal_at(scene: &CubeTextScene, index: usize) -> P3 {
    let base = index * 3;
    P3 {
        x: *scene.normals.get(base).unwrap_or(&0.0) as f64,
        y: *scene.normals.get(base + 1).unwrap_or(&0.0) as f64,
        z: *scene.normals.get(base + 2).unwrap_or(&1.0) as f64,
    }
}

fn compute_bounds3(positions: &[f32]) -> Bounds3D {
    if positions.len() < 3 {
        return Bounds3D {
            min: p3_zero(),
            max: p3_zero(),
        };
    }
    let mut min = P3 {
        x: f64::MAX,
        y: f64::MAX,
        z: f64::MAX,
    };
    let mut max = P3 {
        x: f64::MIN,
        y: f64::MIN,
        z: f64::MIN,
    };
    for vertex in positions.chunks_exact(3) {
        min.x = min.x.min(vertex[0] as f64);
        min.y = min.y.min(vertex[1] as f64);
        min.z = min.z.min(vertex[2] as f64);
        max.x = max.x.max(vertex[0] as f64);
        max.y = max.y.max(vertex[1] as f64);
        max.z = max.z.max(vertex[2] as f64);
    }
    Bounds3D { min, max }
}

fn shapes_bounds(shapes: &[Shape2D]) -> Bounds2D {
    let mut min = P2 {
        x: f64::MAX,
        y: f64::MAX,
    };
    let mut max = P2 {
        x: f64::MIN,
        y: f64::MIN,
    };
    for shape in shapes {
        for point in shape
            .outer
            .iter()
            .chain(shape.holes.iter().flat_map(|hole| hole.iter()))
        {
            min.x = min.x.min(point.x);
            min.y = min.y.min(point.y);
            max.x = max.x.max(point.x);
            max.y = max.y.max(point.y);
        }
    }
    if min.x == f64::MAX {
        min = p2_zero();
        max = p2_zero();
    }
    Bounds2D { min, max }
}

fn p2_zero() -> P2 {
    P2 { x: 0.0, y: 0.0 }
}

fn p3_zero() -> P3 {
    P3 {
        x: 0.0,
        y: 0.0,
        z: 0.0,
    }
}

fn bounds_center(bounds: Bounds2D) -> P2 {
    P2 {
        x: (bounds.min.x + bounds.max.x) * 0.5,
        y: (bounds.min.y + bounds.max.y) * 0.5,
    }
}

fn point_in_shape(point: P2, shape: &Shape2D) -> bool {
    point_in_polygon(point, &shape.outer)
        && !shape
            .holes
            .iter()
            .any(|hole| point_in_polygon(point, hole))
}

fn point_in_polygon(point: P2, polygon: &[P2]) -> bool {
    if polygon.len() < 3 {
        return false;
    }
    let mut inside = false;
    let mut j = polygon.len() - 1;
    for i in 0..polygon.len() {
        let pi = polygon[i];
        let pj = polygon[j];
        if ((pi.y > point.y) != (pj.y > point.y))
            && point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y).max(EPSILON)) + pi.x
        {
            inside = !inside;
        }
        j = i;
    }
    inside
}

fn point_in_triangle(p: P2, a: P2, b: P2, c: P2) -> bool {
    let area = cross(a, b, c).abs();
    let a1 = cross(p, a, b).abs();
    let a2 = cross(p, b, c).abs();
    let a3 = cross(p, c, a).abs();
    (a1 + a2 + a3 - area).abs() <= 1e-5
}

fn polygon_area(points: &[P2]) -> f64 {
    if points.len() < 3 {
        return 0.0;
    }
    let mut area = 0.0;
    for i in 0..points.len() {
        let a = points[i];
        let b = points[(i + 1) % points.len()];
        area += a.x * b.y - b.x * a.y;
    }
    area * 0.5
}

fn ensure_orientation(points: &mut [P2], ccw: bool) {
    let area = polygon_area(points);
    if (ccw && area < 0.0) || (!ccw && area > 0.0) {
        points.reverse();
    }
}

fn sample_point(points: &[P2]) -> P2 {
    let mut x = 0.0;
    let mut y = 0.0;
    for point in points {
        x += point.x;
        y += point.y;
    }
    let inv = 1.0 / points.len().max(1) as f64;
    P2 {
        x: x * inv,
        y: y * inv,
    }
}

fn quadratic_point(a: P2, b: P2, c: P2, t: f64) -> P2 {
    let mt = 1.0 - t;
    P2 {
        x: mt * mt * a.x + 2.0 * mt * t * b.x + t * t * c.x,
        y: mt * mt * a.y + 2.0 * mt * t * b.y + t * t * c.y,
    }
}

fn cubic_point(a: P2, b: P2, c: P2, d: P2, t: f64) -> P2 {
    let mt = 1.0 - t;
    P2 {
        x: mt * mt * mt * a.x + 3.0 * mt * mt * t * b.x + 3.0 * mt * t * t * c.x + t * t * t * d.x,
        y: mt * mt * mt * a.y + 3.0 * mt * mt * t * b.y + 3.0 * mt * t * t * c.y + t * t * t * d.y,
    }
}

fn p2_from_point(point: Point2<f64>) -> P2 {
    P2 {
        x: point.x,
        y: point.y,
    }
}

fn cross(a: P2, b: P2, c: P2) -> f64 {
    (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

fn cross3(a: P3, b: P3) -> P3 {
    P3 {
        x: a.y * b.z - a.z * b.y,
        y: a.z * b.x - a.x * b.z,
        z: a.x * b.y - a.y * b.x,
    }
}

fn sub3(a: P3, b: P3) -> P3 {
    P3 {
        x: a.x - b.x,
        y: a.y - b.y,
        z: a.z - b.z,
    }
}

fn normalize(point: P2) -> P2 {
    let len = (point.x * point.x + point.y * point.y).sqrt();
    if len <= EPSILON {
        P2 { x: 0.0, y: 0.0 }
    } else {
        P2 {
            x: point.x / len,
            y: point.y / len,
        }
    }
}

fn normalize3(point: P3) -> P3 {
    let len = (point.x * point.x + point.y * point.y + point.z * point.z).sqrt();
    if len <= EPSILON {
        P3 {
            x: 0.0,
            y: 0.0,
            z: 1.0,
        }
    } else {
        P3 {
            x: point.x / len,
            y: point.y / len,
            z: point.z / len,
        }
    }
}

fn outward_normal(edge: P2, ccw: bool) -> P2 {
    if ccw {
        P2 {
            x: edge.y,
            y: -edge.x,
        }
    } else {
        P2 {
            x: -edge.y,
            y: edge.x,
        }
    }
}

fn line_intersection(a: P2, da: P2, b: P2, db: P2) -> Option<P2> {
    let denom = da.x * db.y - da.y * db.x;
    if denom.abs() <= EPSILON {
        return None;
    }
    let t = ((b.x - a.x) * db.y - (b.y - a.y) * db.x) / denom;
    Some(P2 {
        x: a.x + da.x * t,
        y: a.y + da.y * t,
    })
}

fn distance2(a: P2, b: P2) -> f64 {
    let dx = a.x - b.x;
    let dy = a.y - b.y;
    dx * dx + dy * dy
}
