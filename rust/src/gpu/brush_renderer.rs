use std::borrow::Cow;
use std::collections::HashSet;
use std::sync::Arc;
use std::time::Instant;

use wgpu::{ComputePipeline, Device, Queue};

use crate::gpu::debug::{self, LogLevel};
use crate::gpu::layer_format::LAYER_TEXTURE_FORMAT;
use crate::gpu::wgpu_utils;

#[derive(Debug, Clone, Copy)]
pub struct Point2D {
    pub x: f32,
    pub y: f32,
}

#[derive(Debug, Clone, Copy)]
pub struct Color {
    pub argb: u32,
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct PointRotation {
    pub(crate) sin: f32,
    pub(crate) cos: f32,
}

#[derive(Debug, Clone, Copy)]
pub enum BrushShape {
    Circle,
    Triangle,
    Square,
    Star,
}

#[derive(Debug, Clone, Copy)]
enum BrushStrokeMode {
    Segments,
    Points,
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct ShaderStrokePoint {
    pos: [f32; 2],
    radius: f32,
    alpha: f32,
    sat: f32,
    rot_sin: f32,
    rot_cos: f32,
    pad: f32,
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct BrushShaderConfig {
    canvas_width: u32,
    canvas_height: u32,
    origin_x: u32,
    origin_y: u32,
    region_width: u32,
    region_height: u32,
    point_count: u32,
    brush_shape: u32,
    erase_mode: u32,
    composite_mode: u32,
    antialias_level: u32,
    color_argb: u32,
    softness: f32,
    rotation_sin: f32,
    rotation_cos: f32,
    hollow_mode: u32,
    hollow_ratio: f32,
    hollow_erase: u32,
    stroke_mask_mode: u32,
    stroke_base_mode: u32,
    stroke_accumulate_mode: u32,
    stroke_mode: u32,
    selection_mask_mode: u32,
    custom_mask_mode: u32,
    screentone_enabled: u32,
    screentone_spacing: f32,
    screentone_dot_size: f32,
    screentone_rotation_sin: f32,
    screentone_rotation_cos: f32,
    screentone_softness: f32,
    screentone_shape: u32,
}

#[derive(Debug, Clone, Copy)]
struct DirtyRect {
    origin_x: u32,
    origin_y: u32,
    width: u32,
    height: u32,
}

const WORKGROUP_SIZE: u32 = 16;
pub(crate) const MAX_POINTS: usize = 8192;
const STROKE_BASE_TILE_SIZE: u32 = 256;

#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq)]
struct StrokeBaseTile {
    tx: u32,
    ty: u32,
}

pub struct BrushRenderer {
    device: Arc<Device>,
    queue: Arc<Queue>,
    pipeline: ComputePipeline,

    bind_group_layout: wgpu::BindGroupLayout,
    uniform_buffer: wgpu::Buffer,
    points_buffer: Option<wgpu::Buffer>,
    points_capacity: usize,
    stroke_mask: wgpu::Texture,
    stroke_mask_view: wgpu::TextureView,
    stroke_mask_width: u32,
    stroke_mask_height: u32,
    stroke_base: wgpu::Texture,
    stroke_base_view: wgpu::TextureView,
    stroke_base_width: u32,
    stroke_base_height: u32,
    stroke_base_valid: bool,
    stroke_base_tiles: HashSet<StrokeBaseTile>,
    selection_mask: wgpu::Texture,
    selection_mask_view: wgpu::TextureView,
    selection_mask_width: u32,
    selection_mask_height: u32,
    selection_mask_enabled: bool,
    custom_mask: wgpu::Texture,
    custom_mask_view: wgpu::TextureView,
    custom_mask_width: u32,
    custom_mask_height: u32,
    custom_mask_enabled: bool,
    layer_read: Option<wgpu::Texture>,
    layer_read_view: Option<wgpu::TextureView>,
    layer_read_width: u32,
    layer_read_height: u32,

    canvas_width: u32,
    canvas_height: u32,
    softness: f32,
    screentone_enabled: bool,
    screentone_spacing: f32,
    screentone_dot_size: f32,
    screentone_rotation_sin: f32,
    screentone_rotation_cos: f32,
    screentone_softness: f32,
    screentone_shape: BrushShape,
}

impl BrushRenderer {
    pub fn new(device: Arc<Device>, queue: Arc<Queue>) -> Result<Self, String> {
        device_push_scopes(device.as_ref());

        let shader_source = include_str!("brush_shaders_rgba8.wgsl");
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("BrushRenderer shader"),
            source: wgpu::ShaderSource::Wgsl(Cow::Borrowed(shader_source)),
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("BrushRenderer bind group layout (rgba8)"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::StorageTexture {
                        access: wgpu::StorageTextureAccess::WriteOnly,
                        format: LAYER_TEXTURE_FORMAT,
                        view_dimension: wgpu::TextureViewDimension::D2,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 3,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Texture {
                        multisampled: false,
                        view_dimension: wgpu::TextureViewDimension::D2,
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 4,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Texture {
                        multisampled: false,
                        view_dimension: wgpu::TextureViewDimension::D2,
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 5,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Texture {
                        multisampled: false,
                        view_dimension: wgpu::TextureViewDimension::D2,
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                    },
                    count: None,
                },
            ],
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("BrushRenderer pipeline layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("BrushRenderer compute pipeline"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: "draw_brush_stroke",
        });

        let uniform_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BrushRenderer uniform buffer"),
            size: std::mem::size_of::<BrushShaderConfig>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        if let Some(err) = device_pop_scope(device.as_ref()) {
            return Err(format!("wgpu validation error during brush init: {err}"));
        }
        if let Some(err) = device_pop_scope(device.as_ref()) {
            return Err(format!("wgpu out-of-memory error during brush init: {err}"));
        }

        let (stroke_mask, stroke_mask_view) = create_stroke_mask(device.as_ref(), 1, 1);
        let (stroke_base, stroke_base_view) = create_stroke_base(device.as_ref(), 1, 1);
        let (selection_mask, selection_mask_view) = create_selection_mask(device.as_ref(), 1, 1);
        let (custom_mask, custom_mask_view) = create_custom_mask(device.as_ref(), 1, 1);

        Ok(Self {
            device,
            queue,
            pipeline,
            bind_group_layout,
            uniform_buffer,
            points_buffer: None,
            points_capacity: 0,
            stroke_mask,
            stroke_mask_view,
            stroke_mask_width: 1,
            stroke_mask_height: 1,
            stroke_base,
            stroke_base_view,
            stroke_base_width: 1,
            stroke_base_height: 1,
            stroke_base_valid: false,
            stroke_base_tiles: HashSet::new(),
            selection_mask,
            selection_mask_view,
            selection_mask_width: 1,
            selection_mask_height: 1,
            selection_mask_enabled: false,
            custom_mask,
            custom_mask_view,
            custom_mask_width: 1,
            custom_mask_height: 1,
            custom_mask_enabled: false,
            layer_read: None,
            layer_read_view: None,
            layer_read_width: 0,
            layer_read_height: 0,
            canvas_width: 0,
            canvas_height: 0,
            softness: 0.0,
            screentone_enabled: false,
            screentone_spacing: 10.0,
            screentone_dot_size: 0.6,
            screentone_rotation_sin: 0.0,
            screentone_rotation_cos: 1.0,
            screentone_softness: 0.0,
            screentone_shape: BrushShape::Circle,
        })
    }

    pub fn set_canvas_size(&mut self, width: u32, height: u32) {
        if self.canvas_width != width || self.canvas_height != height {
            self.stroke_base_valid = false;
            self.selection_mask_enabled = false;
            self.stroke_base_tiles.clear();
            self.layer_read = None;
            self.layer_read_view = None;
            self.layer_read_width = 0;
            self.layer_read_height = 0;
        }
        self.canvas_width = width;
        self.canvas_height = height;
    }

    pub fn clear_stroke_mask(&mut self) -> Result<(), String> {
        self.ensure_stroke_mask()?;
        self.stroke_base_valid = false;
        self.stroke_base_tiles.clear();
        device_push_scopes(self.device.as_ref());
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("BrushRenderer clear stroke mask"),
            });
        encoder.clear_texture(
            &self.stroke_mask,
            &wgpu::ImageSubresourceRange {
                aspect: wgpu::TextureAspect::All,
                base_mip_level: 0,
                mip_level_count: Some(1),
                base_array_layer: 0,
                array_layer_count: Some(1),
            },
        );
        self.queue.submit(Some(encoder.finish()));
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!("wgpu validation error during mask clear: {err}"));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!("wgpu out-of-memory error during mask clear: {err}"));
        }
        Ok(())
    }

    pub fn begin_stroke_base_capture(&mut self) {
        self.stroke_base_valid = false;
        self.stroke_base_tiles.clear();
    }

    pub fn capture_stroke_base_region(
        &mut self,
        layer_texture: &wgpu::Texture,
        layer_index: u32,
        dirty: (i32, i32, i32, i32),
    ) -> Result<(), String> {
        if self.canvas_width == 0 || self.canvas_height == 0 {
            self.stroke_base_valid = false;
            self.stroke_base_tiles.clear();
            return Ok(());
        }
        let (left_i, top_i, width_i, height_i) = dirty;
        if width_i <= 0 || height_i <= 0 {
            return Ok(());
        }
        self.ensure_stroke_base()?;
        let left = (left_i.max(0) as u32).min(self.canvas_width);
        let top = (top_i.max(0) as u32).min(self.canvas_height);
        let right = (left_i.saturating_add(width_i).max(0) as u32).min(self.canvas_width);
        let bottom = (top_i.saturating_add(height_i).max(0) as u32).min(self.canvas_height);
        if right <= left || bottom <= top {
            return Ok(());
        }

        let tile_size = STROKE_BASE_TILE_SIZE.max(1);
        let tx0 = left / tile_size;
        let ty0 = top / tile_size;
        let tx1 = right.saturating_sub(1) / tile_size;
        let ty1 = bottom.saturating_sub(1) / tile_size;

        let mut encoder: Option<wgpu::CommandEncoder> = None;
        let mut captured_any = false;
        let mut scopes_pushed = false;

        for ty in ty0..=ty1 {
            for tx in tx0..=tx1 {
                let key = StrokeBaseTile { tx, ty };
                if self.stroke_base_tiles.contains(&key) {
                    continue;
                }
                let tile_left = tx.saturating_mul(tile_size);
                let tile_top = ty.saturating_mul(tile_size);
                if tile_left >= self.canvas_width || tile_top >= self.canvas_height {
                    continue;
                }
                let tile_width = tile_size.min(self.canvas_width.saturating_sub(tile_left));
                let tile_height = tile_size.min(self.canvas_height.saturating_sub(tile_top));
                if tile_width == 0 || tile_height == 0 {
                    continue;
                }
                if !scopes_pushed {
                    device_push_scopes(self.device.as_ref());
                    scopes_pushed = true;
                }
                let enc = encoder.get_or_insert_with(|| {
                    self.device
                        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("BrushRenderer capture stroke base (tiles)"),
                        })
                });
                enc.copy_texture_to_texture(
                    wgpu::ImageCopyTexture {
                        texture: layer_texture,
                        mip_level: 0,
                        origin: wgpu::Origin3d {
                            x: tile_left,
                            y: tile_top,
                            z: layer_index,
                        },
                        aspect: wgpu::TextureAspect::All,
                    },
                    wgpu::ImageCopyTexture {
                        texture: &self.stroke_base,
                        mip_level: 0,
                        origin: wgpu::Origin3d {
                            x: tile_left,
                            y: tile_top,
                            z: 0,
                        },
                        aspect: wgpu::TextureAspect::All,
                    },
                    wgpu::Extent3d {
                        width: tile_width,
                        height: tile_height,
                        depth_or_array_layers: 1,
                    },
                );
                self.stroke_base_tiles.insert(key);
                captured_any = true;
            }
        }

        if let Some(enc) = encoder {
            self.queue.submit(Some(enc.finish()));
        }
        if scopes_pushed {
            if let Some(err) = device_pop_scope(self.device.as_ref()) {
                self.stroke_base_valid = false;
                return Err(format!(
                    "wgpu validation error during stroke base capture: {err}"
                ));
            }
            if let Some(err) = device_pop_scope(self.device.as_ref()) {
                self.stroke_base_valid = false;
                return Err(format!(
                    "wgpu out-of-memory error during stroke base capture: {err}"
                ));
            }
        }
        if captured_any {
            self.stroke_base_valid = true;
        }
        Ok(())
    }

    pub fn prepare_layer_read(
        &mut self,
        layer_texture: &wgpu::Texture,
        layer_index: u32,
        dirty: (i32, i32, i32, i32),
    ) -> Result<(), String> {
        if self.canvas_width == 0 || self.canvas_height == 0 {
            return Ok(());
        }
        let (left_i, top_i, width_i, height_i) = dirty;
        if width_i <= 0 || height_i <= 0 {
            return Ok(());
        }
        self.ensure_layer_read()?;
        let left = (left_i.max(0) as u32).min(self.canvas_width);
        let top = (top_i.max(0) as u32).min(self.canvas_height);
        let right = (left_i.saturating_add(width_i).max(0) as u32).min(self.canvas_width);
        let bottom = (top_i.saturating_add(height_i).max(0) as u32).min(self.canvas_height);
        if right <= left || bottom <= top {
            return Ok(());
        }

        let layer_read = self
            .layer_read
            .as_ref()
            .ok_or_else(|| "layer read texture missing".to_string())?;

        device_push_scopes(self.device.as_ref());
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("BrushRenderer prepare layer read"),
            });
        encoder.copy_texture_to_texture(
            wgpu::ImageCopyTexture {
                texture: layer_texture,
                mip_level: 0,
                origin: wgpu::Origin3d {
                    x: left,
                    y: top,
                    z: layer_index,
                },
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::ImageCopyTexture {
                texture: layer_read,
                mip_level: 0,
                origin: wgpu::Origin3d {
                    x: left,
                    y: top,
                    z: 0,
                },
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::Extent3d {
                width: right - left,
                height: bottom - top,
                depth_or_array_layers: 1,
            },
        );
        self.queue.submit(Some(encoder.finish()));
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu validation error during layer read copy: {err}"
            ));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu out-of-memory error during layer read copy: {err}"
            ));
        }
        Ok(())
    }

    pub fn set_softness(&mut self, softness: f32) {
        self.softness = if softness.is_finite() {
            softness.clamp(0.0, 1.0)
        } else {
            0.0
        };
    }

    pub fn set_screentone(
        &mut self,
        enabled: bool,
        spacing: f32,
        dot_size: f32,
        rotation_radians: f32,
        softness: f32,
        shape: BrushShape,
    ) {
        self.screentone_enabled = enabled;
        self.screentone_spacing = if spacing.is_finite() {
            spacing.clamp(2.0, 200.0)
        } else {
            10.0
        };
        self.screentone_dot_size = if dot_size.is_finite() {
            dot_size.clamp(0.0, 1.0)
        } else {
            0.6
        };
        let angle = if rotation_radians.is_finite() {
            rotation_radians
        } else {
            0.0
        };
        self.screentone_rotation_sin = angle.sin();
        self.screentone_rotation_cos = angle.cos();
        self.screentone_softness = if softness.is_finite() {
            softness.clamp(0.0, 1.0)
        } else {
            0.0
        };
        self.screentone_shape = shape;
    }

    pub fn set_selection_mask(&mut self, mask: Option<&[u8]>) -> Result<(), String> {
        let Some(mask) = mask else {
            self.selection_mask_enabled = false;
            return Ok(());
        };
        if self.canvas_width == 0 || self.canvas_height == 0 {
            self.selection_mask_enabled = false;
            return Ok(());
        }
        let expected_len = (self.canvas_width as usize)
            .checked_mul(self.canvas_height as usize)
            .ok_or_else(|| "selection mask size overflow".to_string())?;
        if mask.len() != expected_len {
            self.selection_mask_enabled = false;
            return Err(format!(
                "selection mask size mismatch: {} vs {}",
                mask.len(),
                expected_len
            ));
        }
        self.ensure_selection_mask()?;
        write_selection_mask(
            self.device.as_ref(),
            self.queue.as_ref(),
            &self.selection_mask,
            self.canvas_width,
            self.canvas_height,
            mask,
        )?;
        self.selection_mask_enabled = true;
        Ok(())
    }

    pub fn set_custom_mask(
        &mut self,
        width: u32,
        height: u32,
        mask: &[u8],
    ) -> Result<(), String> {
        if width == 0 || height == 0 {
            self.custom_mask_enabled = false;
            return Ok(());
        }
        let expected_len = (width as usize)
            .checked_mul(height as usize)
            .and_then(|v| v.checked_mul(2))
            .ok_or_else(|| "custom mask size overflow".to_string())?;
        if mask.len() != expected_len {
            return Err(format!(
                "custom mask length mismatch: {} vs {}",
                mask.len(),
                expected_len
            ));
        }

        if self.custom_mask_width != width || self.custom_mask_height != height {
            let (tex, view) = create_custom_mask(self.device.as_ref(), width, height);
            self.custom_mask = tex;
            self.custom_mask_view = view;
            self.custom_mask_width = width;
            self.custom_mask_height = height;
        }

        write_custom_mask(
            self.device.as_ref(),
            self.queue.as_ref(),
            &self.custom_mask,
            width,
            height,
            mask,
        )?;
        self.custom_mask_enabled = true;
        Ok(())
    }

    pub fn clear_custom_mask(&mut self) {
        self.custom_mask_enabled = false;
    }

    pub fn draw_stroke(
        &mut self,
        layer_view: &wgpu::TextureView,
        points: &[Point2D],
        radii: &[f32],
        color: Color,
        brush_shape: BrushShape,
        erase: bool,
        antialias_level: u32,
        rotation_radians: f32,
        hollow_enabled: bool,
        hollow_ratio: f32,
        hollow_erase_occluded: bool,
        use_stroke_mask: bool,
        accumulate_segments: bool,
    ) -> Result<(), String> {
        self.draw_stroke_internal(
            layer_view,
            points,
            radii,
            None,
            None,
            None,
            color,
            brush_shape,
            erase,
            antialias_level,
            rotation_radians,
            hollow_enabled,
            hollow_ratio,
            hollow_erase_occluded,
            use_stroke_mask,
            accumulate_segments,
            self.softness,
            BrushStrokeMode::Segments,
            0,
            None,
        )
    }

    pub fn draw_points(
        &mut self,
        layer_view: &wgpu::TextureView,
        points: &[Point2D],
        radii: &[f32],
        alphas: Option<&[f32]>,
        saturations: Option<&[f32]>,
        point_rotations: Option<&[PointRotation]>,
        color: Color,
        brush_shape: BrushShape,
        erase: bool,
        antialias_level: u32,
        softness: f32,
        hollow_enabled: bool,
        hollow_ratio: f32,
        hollow_erase_occluded: bool,
        use_stroke_mask: bool,
        accumulate: bool,
        composite_mode: u32,
        custom_mask_mode_override: Option<u32>,
    ) -> Result<(), String> {
        self.draw_stroke_internal(
            layer_view,
            points,
            radii,
            alphas,
            saturations,
            point_rotations,
            color,
            brush_shape,
            erase,
            antialias_level,
            0.0,
            hollow_enabled,
            hollow_ratio,
            hollow_erase_occluded,
            use_stroke_mask,
            accumulate,
            softness,
            BrushStrokeMode::Points,
            composite_mode,
            custom_mask_mode_override,
        )
    }

    fn draw_stroke_internal(
        &mut self,
        layer_view: &wgpu::TextureView,
        points: &[Point2D],
        radii: &[f32],
        point_alphas: Option<&[f32]>,
        point_saturations: Option<&[f32]>,
        point_rotations: Option<&[PointRotation]>,
        color: Color,
        brush_shape: BrushShape,
        erase: bool,
        antialias_level: u32,
        rotation_radians: f32,
        hollow_enabled: bool,
        hollow_ratio: f32,
        hollow_erase_occluded: bool,
        use_stroke_mask: bool,
        accumulate_segments: bool,
        softness: f32,
        stroke_mode: BrushStrokeMode,
        composite_mode: u32,
        custom_mask_mode_override: Option<u32>,
    ) -> Result<(), String> {
        if points.is_empty() {
            return Ok(());
        }
        if points.len() != radii.len() {
            return Err(format!(
                "points/radii length mismatch: {} vs {}",
                points.len(),
                radii.len()
            ));
        }
        if points.len() > MAX_POINTS {
            return Err(format!(
                "too many stroke points: {} (max {MAX_POINTS})",
                points.len()
            ));
        }
        if let Some(alphas) = point_alphas {
            if alphas.len() != points.len() {
                return Err(format!(
                    "points/alphas length mismatch: {} vs {}",
                    points.len(),
                    alphas.len()
                ));
            }
        }
        if let Some(rotations) = point_rotations {
            if rotations.len() != points.len() {
                return Err(format!(
                    "points/rotations length mismatch: {} vs {}",
                    points.len(),
                    rotations.len()
                ));
            }
        }
        if self.canvas_width == 0 || self.canvas_height == 0 {
            return Err("brush renderer canvas size not set".to_string());
        }

        let verbose = debug::level() >= LogLevel::Verbose;
        let t0 = if verbose { Some(Instant::now()) } else { None };

        let rotation = if rotation_radians.is_finite() {
            rotation_radians
        } else {
            0.0
        };
        let ratio = if hollow_enabled && !erase {
            if hollow_ratio.is_finite() {
                hollow_ratio.clamp(0.0, 1.0)
            } else {
                0.0
            }
        } else {
            0.0
        };
        let hollow_mode = if ratio > 0.0001 { 1 } else { 0 };
        let hollow_erase = if hollow_mode != 0 && hollow_erase_occluded {
            1
        } else {
            0
        };
        let stroke_mask_mode = if hollow_mode != 0 && use_stroke_mask {
            self.ensure_stroke_mask()?;
            1
        } else {
            0
        };
        let stroke_base_mode = if hollow_mode != 0
            && hollow_erase == 0
            && self.stroke_base_valid
            && stroke_mask_mode != 0
        {
            1
        } else {
            0
        };
        let softness = if softness.is_finite() {
            softness.clamp(0.0, 1.0)
        } else {
            0.0
        };
        let radius_scale = if softness > 0.0001 { 1.0 + softness } else { 1.0 };
        let dirty = compute_dirty_rect(
            points,
            radii,
            self.canvas_width,
            self.canvas_height,
            radius_scale,
            antialias_level,
        )?;
        if dirty.width == 0 || dirty.height == 0 {
            return Ok(());
        }

        debug::log(
            LogLevel::Verbose,
            format_args!(
                "BrushRenderer draw_stroke canvas={}x{} dirty=({},{}) {}x{} points={} aa={} erase={} shape={brush_shape:?}",
                self.canvas_width,
                self.canvas_height,
                dirty.origin_x,
                dirty.origin_y,
                dirty.width,
                dirty.height,
                points.len(),
                antialias_level,
                erase
            ),
        );

        self.ensure_points_buffer(points.len())?;
        let points_buffer = self
            .points_buffer
            .as_ref()
            .ok_or_else(|| "wgpu points buffer not initialized".to_string())?;

        let mut shader_points: Vec<ShaderStrokePoint> = Vec::with_capacity(points.len());
        let use_point_rotation = matches!(stroke_mode, BrushStrokeMode::Points);
        let default_sin = rotation.sin();
        let default_cos = rotation.cos();
        for (idx, (p, &r)) in points.iter().zip(radii.iter()).enumerate() {
            let radius = if r.is_finite() { r.max(0.0) } else { 0.0 };
            let alpha = if let Some(alphas) = point_alphas {
                let value = alphas[idx];
                if value.is_finite() {
                    value.clamp(0.0, 1.0)
                } else {
                    0.0
                }
            } else {
                1.0
            };
            let sat = if let Some(sats) = point_saturations {
                let value = sats[idx];
                if value.is_finite() {
                    value.clamp(0.0, 2.0)
                } else {
                    1.0
                }
            } else {
                1.0
            };
            let (rot_sin, rot_cos) = if use_point_rotation {
                if let Some(rotations) = point_rotations {
                    let rot = rotations[idx];
                    (finite_f32(rot.sin), finite_f32(rot.cos))
                } else {
                    (default_sin, default_cos)
                }
            } else {
                (default_sin, default_cos)
            };
            shader_points.push(ShaderStrokePoint {
                pos: [finite_f32(p.x), finite_f32(p.y)],
                radius,
                alpha,
                sat,
                rot_sin,
                rot_cos,
                pad: 0.0,
            });
        }

        self.queue
            .write_buffer(points_buffer, 0, bytemuck::cast_slice(&shader_points));

        let custom_mask_mode = match custom_mask_mode_override {
            Some(mode) => mode.min(1),
            None => {
                if self.custom_mask_enabled {
                    1
                } else {
                    0
                }
            }
        };
        let config = BrushShaderConfig {
            canvas_width: self.canvas_width,
            canvas_height: self.canvas_height,
            origin_x: dirty.origin_x,
            origin_y: dirty.origin_y,
            region_width: dirty.width,
            region_height: dirty.height,
            point_count: shader_points.len() as u32,
            brush_shape: match brush_shape {
                BrushShape::Circle => 0,
                BrushShape::Triangle => 1,
                BrushShape::Square => 2,
                BrushShape::Star => 3,
            },
            erase_mode: if erase { 1 } else { 0 },
            composite_mode: composite_mode.min(1),
            antialias_level: antialias_level.clamp(0, 9),
            color_argb: color.argb,
            softness,
            rotation_sin: rotation.sin(),
            rotation_cos: rotation.cos(),
            hollow_mode,
            hollow_ratio: ratio,
            hollow_erase,
            stroke_mask_mode,
            stroke_base_mode,
            stroke_accumulate_mode: if accumulate_segments { 1 } else { 0 },
            stroke_mode: match stroke_mode {
                BrushStrokeMode::Segments => 0,
                BrushStrokeMode::Points => 1,
            },
            selection_mask_mode: if self.selection_mask_enabled { 1 } else { 0 },
            custom_mask_mode,
            screentone_enabled: if self.screentone_enabled { 1 } else { 0 },
            screentone_spacing: self.screentone_spacing,
            screentone_dot_size: self.screentone_dot_size,
            screentone_rotation_sin: self.screentone_rotation_sin,
            screentone_rotation_cos: self.screentone_rotation_cos,
            screentone_softness: self.screentone_softness,
            screentone_shape: match self.screentone_shape {
                BrushShape::Circle => 0,
                BrushShape::Triangle => 1,
                BrushShape::Square => 2,
                BrushShape::Star => 3,
            },
        };
        self.queue
            .write_buffer(&self.uniform_buffer, 0, bytemuck::bytes_of(&config));

        let mut entries: Vec<wgpu::BindGroupEntry> = vec![
            wgpu::BindGroupEntry {
                binding: 0,
                resource: points_buffer.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: wgpu::BindingResource::TextureView(layer_view),
            },
            wgpu::BindGroupEntry {
                binding: 2,
                resource: self.uniform_buffer.as_entire_binding(),
            },
        ];
        let layer_read_view = self
            .layer_read_view
            .as_ref()
            .ok_or_else(|| "brush layer read view not initialized".to_string())?;
        entries.push(wgpu::BindGroupEntry {
            binding: 3,
            resource: wgpu::BindingResource::TextureView(layer_read_view),
        });
        entries.push(wgpu::BindGroupEntry {
            binding: 4,
            resource: wgpu::BindingResource::TextureView(&self.selection_mask_view),
        });
        entries.push(wgpu::BindGroupEntry {
            binding: 5,
            resource: wgpu::BindingResource::TextureView(&self.custom_mask_view),
        });
        device_push_scopes(self.device.as_ref());
        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("BrushRenderer bind group"),
            layout: &self.bind_group_layout,
            entries: &entries,
        });
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu validation error during brush bind group: {err}"
            ));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu out-of-memory error during brush bind group: {err}"
            ));
        }

        device_push_scopes(self.device.as_ref());

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("BrushRenderer encoder"),
            });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("BrushRenderer pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            let wg_x = (dirty.width + (WORKGROUP_SIZE - 1)) / WORKGROUP_SIZE;
            let wg_y = (dirty.height + (WORKGROUP_SIZE - 1)) / WORKGROUP_SIZE;
            pass.dispatch_workgroups(wg_x, wg_y, 1);
        }

        self.queue.submit(Some(encoder.finish()));

        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!("wgpu validation error during brush draw: {err}"));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!("wgpu out-of-memory error during brush draw: {err}"));
        }

        if let Some(t0) = t0 {
            debug::log(
                LogLevel::Verbose,
                format_args!("BrushRenderer draw_stroke dispatch in {:?}.", t0.elapsed()),
            );
        }

        Ok(())
    }

    fn ensure_points_buffer(&mut self, point_count: usize) -> Result<(), String> {
        let required_bytes: u64 = (point_count as u64)
            .checked_mul(std::mem::size_of::<ShaderStrokePoint>() as u64)
            .ok_or_else(|| "points buffer size overflow".to_string())?;

        if self.points_buffer.is_some()
            && point_count <= self.points_capacity
            && required_bytes <= self.device.limits().max_buffer_size
        {
            return Ok(());
        }

        let max_buffer_size = self.device.limits().max_buffer_size;
        let max_storage_binding_size = self.device.limits().max_storage_buffer_binding_size as u64;
        if required_bytes > max_buffer_size {
            return Err(format!(
                "stroke points buffer too large: {required_bytes} bytes (device max {max_buffer_size})"
            ));
        }
        if required_bytes > max_storage_binding_size {
            return Err(format!(
                "stroke points binding too large: {required_bytes} bytes (storage binding max {max_storage_binding_size})"
            ));
        }

        device_push_scopes(self.device.as_ref());

        let buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BrushRenderer stroke points buffer"),
            size: required_bytes,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu validation error during brush buffer alloc: {err}"
            ));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu out-of-memory error during brush buffer alloc: {err}"
            ));
        }

        self.points_buffer = Some(buffer);
        self.points_capacity = point_count;
        debug::log(
            LogLevel::Info,
            format_args!(
                "BrushRenderer allocated points buffer: capacity_points={} bytes={required_bytes}",
                point_count
            ),
        );
        Ok(())
    }

    fn ensure_stroke_mask(&mut self) -> Result<(), String> {
        if self.canvas_width == 0 || self.canvas_height == 0 {
            return Ok(());
        }
        if self.stroke_mask_width == self.canvas_width
            && self.stroke_mask_height == self.canvas_height
        {
            return Ok(());
        }
        let (mask, view) =
            create_stroke_mask(self.device.as_ref(), self.canvas_width, self.canvas_height);
        self.stroke_mask = mask;
        self.stroke_mask_view = view;
        self.stroke_mask_width = self.canvas_width;
        self.stroke_mask_height = self.canvas_height;
        Ok(())
    }

    fn ensure_stroke_base(&mut self) -> Result<(), String> {
        if self.canvas_width == 0 || self.canvas_height == 0 {
            return Ok(());
        }
        if self.stroke_base_width == self.canvas_width
            && self.stroke_base_height == self.canvas_height
        {
            return Ok(());
        }
        let (base, view) =
            create_stroke_base(self.device.as_ref(), self.canvas_width, self.canvas_height);
        self.stroke_base = base;
        self.stroke_base_view = view;
        self.stroke_base_width = self.canvas_width;
        self.stroke_base_height = self.canvas_height;
        self.stroke_base_valid = false;
        self.stroke_base_tiles.clear();
        Ok(())
    }

    fn ensure_layer_read(&mut self) -> Result<(), String> {
        if self.canvas_width == 0 || self.canvas_height == 0 {
            return Ok(());
        }
        if self.layer_read_width == self.canvas_width
            && self.layer_read_height == self.canvas_height
        {
            return Ok(());
        }

        device_push_scopes(self.device.as_ref());

        let texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("BrushRenderer layer read"),
            size: wgpu::Extent3d {
                width: self.canvas_width.max(1),
                height: self.canvas_height.max(1),
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: LAYER_TEXTURE_FORMAT,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());

        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu validation error during layer read alloc: {err}"
            ));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu out-of-memory error during layer read alloc: {err}"
            ));
        }

        self.layer_read = Some(texture);
        self.layer_read_view = Some(view);
        self.layer_read_width = self.canvas_width;
        self.layer_read_height = self.canvas_height;
        Ok(())
    }

    fn ensure_selection_mask(&mut self) -> Result<(), String> {
        if self.canvas_width == 0 || self.canvas_height == 0 {
            return Ok(());
        }
        if self.selection_mask_width == self.canvas_width
            && self.selection_mask_height == self.canvas_height
        {
            return Ok(());
        }
        let (mask, view) =
            create_selection_mask(self.device.as_ref(), self.canvas_width, self.canvas_height);
        self.selection_mask = mask;
        self.selection_mask_view = view;
        self.selection_mask_width = self.canvas_width;
        self.selection_mask_height = self.canvas_height;
        Ok(())
    }
}

fn create_stroke_mask(
    device: &wgpu::Device,
    width: u32,
    height: u32,
) -> (wgpu::Texture, wgpu::TextureView) {
    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("BrushRenderer stroke mask"),
        size: wgpu::Extent3d {
            width: width.max(1),
            height: height.max(1),
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: LAYER_TEXTURE_FORMAT,
        usage: wgpu::TextureUsages::STORAGE_BINDING | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
    (texture, view)
}

fn create_stroke_base(
    device: &wgpu::Device,
    width: u32,
    height: u32,
) -> (wgpu::Texture, wgpu::TextureView) {
    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("BrushRenderer stroke base"),
        size: wgpu::Extent3d {
            width: width.max(1),
            height: height.max(1),
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: LAYER_TEXTURE_FORMAT,
        usage: wgpu::TextureUsages::STORAGE_BINDING | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
    (texture, view)
}

fn create_selection_mask(
    device: &wgpu::Device,
    width: u32,
    height: u32,
) -> (wgpu::Texture, wgpu::TextureView) {
    let format = wgpu::TextureFormat::R8Unorm;
    let usage = wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST;
    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("BrushRenderer selection mask"),
        size: wgpu::Extent3d {
            width: width.max(1),
            height: height.max(1),
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage,
        view_formats: &[],
    });
    let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
    (texture, view)
}

fn create_custom_mask(
    device: &wgpu::Device,
    width: u32,
    height: u32,
) -> (wgpu::Texture, wgpu::TextureView) {
    let format = wgpu::TextureFormat::Rg8Unorm;
    let usage = wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST;
    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("BrushRenderer custom mask"),
        size: wgpu::Extent3d {
            width: width.max(1),
            height: height.max(1),
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage,
        view_formats: &[],
    });
    let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
    (texture, view)
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

fn compute_dirty_rect(
    points: &[Point2D],
    radii: &[f32],
    canvas_width: u32,
    canvas_height: u32,
    radius_scale: f32,
    antialias_level: u32,
) -> Result<DirtyRect, String> {
    if canvas_width == 0 || canvas_height == 0 {
        return Ok(DirtyRect {
            origin_x: 0,
            origin_y: 0,
            width: 0,
            height: 0,
        });
    }
    if points.is_empty() || points.len() != radii.len() {
        return Ok(DirtyRect {
            origin_x: 0,
            origin_y: 0,
            width: 0,
            height: 0,
        });
    }

    let mut min_x: f32 = f32::INFINITY;
    let mut min_y: f32 = f32::INFINITY;
    let mut max_x: f32 = f32::NEG_INFINITY;
    let mut max_y: f32 = f32::NEG_INFINITY;
    let mut max_r: f32 = 0.0;

    let scale = if radius_scale.is_finite() && radius_scale > 0.0 {
        radius_scale
    } else {
        1.0
    };
    for (p, &r) in points.iter().zip(radii.iter()) {
        let x = finite_f32(p.x);
        let y = finite_f32(p.y);
        let radius = if r.is_finite() {
            r.max(0.0) * scale
        } else {
            0.0
        };
        if x < min_x {
            min_x = x;
        }
        if y < min_y {
            min_y = y;
        }
        if x > max_x {
            max_x = x;
        }
        if y > max_y {
            max_y = y;
        }
        if radius > max_r {
            max_r = radius;
        }
    }

    if !min_x.is_finite() || !min_y.is_finite() || !max_x.is_finite() || !max_y.is_finite() {
        return Ok(DirtyRect {
            origin_x: 0,
            origin_y: 0,
            width: 0,
            height: 0,
        });
    }

    let aa = antialias_feather(antialias_level);
    let pad: f32 = max_r + aa + 2.0;
    let left = ((min_x - pad).floor() as i64).clamp(0, canvas_width as i64);
    let top = ((min_y - pad).floor() as i64).clamp(0, canvas_height as i64);
    let right = ((max_x + pad).ceil() as i64).clamp(0, canvas_width as i64);
    let bottom = ((max_y + pad).ceil() as i64).clamp(0, canvas_height as i64);

    let width = (right - left).max(0) as u32;
    let height = (bottom - top).max(0) as u32;
    Ok(DirtyRect {
        origin_x: left as u32,
        origin_y: top as u32,
        width,
        height,
    })
}

fn write_selection_mask(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    texture: &wgpu::Texture,
    width: u32,
    height: u32,
    mask: &[u8],
) -> Result<(), String> {
    if width == 0 || height == 0 {
        return Ok(());
    }

    let expected_len = (width as usize)
        .checked_mul(height as usize)
        .ok_or_else(|| "selection mask size overflow".to_string())?;
    if mask.len() != expected_len {
        return Err(format!(
            "selection mask length mismatch: {} vs {}",
            mask.len(),
            expected_len
        ));
    }

    const COPY_BYTES_PER_ROW_ALIGNMENT: u32 = 256;
    #[cfg(target_os = "android")]
    const MAX_CHUNK_BYTES: usize = 512 * 1024;
    #[cfg(not(target_os = "android"))]
    const MAX_CHUNK_BYTES: usize = 4 * 1024 * 1024;

    let bytes_per_row_unpadded = width;
    let bytes_per_row_padded =
        align_up_u32(bytes_per_row_unpadded, COPY_BYTES_PER_ROW_ALIGNMENT);
    if bytes_per_row_padded == 0 {
        return Err("selection mask bytes_per_row == 0".to_string());
    }
    let row_bytes = bytes_per_row_padded as usize;
    let rows_per_chunk = (MAX_CHUNK_BYTES / row_bytes).max(1) as u32;

    let mut y: u32 = 0;
    while y < height {
        let chunk_h = (height - y).min(rows_per_chunk);
        let mut data: Vec<u8> = vec![0; row_bytes * chunk_h as usize];
        for row in 0..chunk_h {
            let src_offset = ((y + row) * width) as usize;
            let dst_offset = row as usize * row_bytes;
            let src = &mask[src_offset..src_offset + width as usize];
            for (i, &value) in src.iter().enumerate() {
                data[dst_offset + i] = if value == 0 { 0 } else { 255 };
            }
        }

        wgpu_utils::write_texture(
            device,
            queue,
            texture,
            wgpu::Origin3d { x: 0, y, z: 0 },
            wgpu::Extent3d {
                width,
                height: chunk_h,
                depth_or_array_layers: 1,
            },
            bytes_per_row_padded,
            chunk_h,
            &data,
        );

        y = y.saturating_add(chunk_h);
    }

    Ok(())
}

fn write_custom_mask(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    texture: &wgpu::Texture,
    width: u32,
    height: u32,
    mask: &[u8],
) -> Result<(), String> {
    if width == 0 || height == 0 {
        return Ok(());
    }

    let expected_len = (width as usize)
        .checked_mul(height as usize)
        .and_then(|v| v.checked_mul(2))
        .ok_or_else(|| "custom mask size overflow".to_string())?;
    if mask.len() != expected_len {
        return Err(format!(
            "custom mask length mismatch: {} vs {}",
            mask.len(),
            expected_len
        ));
    }

    const COPY_BYTES_PER_ROW_ALIGNMENT: u32 = 256;
    #[cfg(target_os = "android")]
    const MAX_CHUNK_BYTES: usize = 512 * 1024;
    #[cfg(not(target_os = "android"))]
    const MAX_CHUNK_BYTES: usize = 4 * 1024 * 1024;

    let bytes_per_row_unpadded = width
        .checked_mul(2)
        .ok_or_else(|| "custom mask bytes_per_row overflow".to_string())?;
    let bytes_per_row_padded =
        align_up_u32(bytes_per_row_unpadded, COPY_BYTES_PER_ROW_ALIGNMENT);
    if bytes_per_row_padded == 0 {
        return Err("custom mask bytes_per_row == 0".to_string());
    }
    let row_bytes = bytes_per_row_padded as usize;
    let rows_per_chunk = (MAX_CHUNK_BYTES / row_bytes).max(1) as u32;

    let mut y: u32 = 0;
    while y < height {
        let chunk_h = (height - y).min(rows_per_chunk);
        let mut data: Vec<u8> = vec![0; row_bytes * chunk_h as usize];
        for row in 0..chunk_h {
            let src_offset = ((y + row) * width * 2) as usize;
            let dst_offset = row as usize * row_bytes;
            let src = &mask[src_offset..src_offset + (width * 2) as usize];
            data[dst_offset..dst_offset + src.len()].copy_from_slice(src);
        }

        wgpu_utils::write_texture(
            device,
            queue,
            texture,
            wgpu::Origin3d { x: 0, y, z: 0 },
            wgpu::Extent3d {
                width,
                height: chunk_h,
                depth_or_array_layers: 1,
            },
            bytes_per_row_padded,
            chunk_h,
            &data,
        );

        y = y.saturating_add(chunk_h);
    }

    Ok(())
}

fn finite_f32(value: f32) -> f32 {
    if value.is_finite() {
        value
    } else {
        0.0
    }
}

fn device_push_scopes(device: &wgpu::Device) {
    device.push_error_scope(wgpu::ErrorFilter::OutOfMemory);
    device.push_error_scope(wgpu::ErrorFilter::Validation);
}

fn device_pop_scope(device: &wgpu::Device) -> Option<wgpu::Error> {
    pollster::block_on(device.pop_error_scope())
}

fn align_up_u32(value: u32, alignment: u32) -> u32 {
    if alignment == 0 {
        return value;
    }
    let rem = value % alignment;
    if rem == 0 {
        value
    } else {
        value + (alignment - rem)
    }
}
