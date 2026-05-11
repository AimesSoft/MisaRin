use std::borrow::Cow;
use std::sync::Arc;

use wgpu::{ComputePipeline, Queue};

use crate::gpu::layer_format::LAYER_TEXTURE_FORMAT;
use crate::gpu::shared_device::SharedRenderDevice;
use crate::gpu::wgpu_utils;

pub const FILTER_HUE_SATURATION: u32 = 0;
pub const FILTER_BRIGHTNESS_CONTRAST: u32 = 1;
pub const FILTER_BLACK_WHITE: u32 = 2;
pub const FILTER_GAUSSIAN_BLUR: u32 = 3;
pub const FILTER_LEAK_REMOVAL: u32 = 4;
pub const FILTER_LINE_NARROW: u32 = 5;
pub const FILTER_FILL_EXPAND: u32 = 6;
pub const FILTER_BINARIZE: u32 = 7;
pub const FILTER_SCAN_PAPER_DRAWING: u32 = 8;
pub const FILTER_INVERT: u32 = 9;

const FILTER_PREMULTIPLY: u32 = 10;
const FILTER_UNPREMULTIPLY: u32 = 11;

const WORKGROUP_SIZE: u32 = 16;

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct FilterConfig {
    width: u32,
    height: u32,
    radius: u32,
    flags: u32,
    params0: [f32; 4],
    params1: [f32; 4],
}

pub struct FilterRenderer {
    device: SharedRenderDevice,
    queue: Arc<Queue>,
    bind_group_layout: wgpu::BindGroupLayout,
    uniform_buffer: wgpu::Buffer,
    pipeline_color: ComputePipeline,
    pipeline_blur: ComputePipeline,
    pipeline_morph: ComputePipeline,
    pipeline_antialias_alpha: ComputePipeline,
    pipeline_antialias_edge: ComputePipeline,
    scratch_a: wgpu::Texture,
    scratch_a_view: wgpu::TextureView,
    scratch_b: wgpu::Texture,
    scratch_b_view: wgpu::TextureView,
    width: u32,
    height: u32,
}

impl FilterRenderer {
    fn write_config(&self, config: &FilterConfig) {
        wgpu_utils::write_buffer(
            self.device.as_ref(),
            self.queue.as_ref(),
            &self.uniform_buffer,
            0,
            bytemuck::bytes_of(config),
        );
    }

    pub fn new(device: SharedRenderDevice, queue: Arc<Queue>) -> Result<Self, String> {
        device_push_scopes(device.as_ref());

        let shader_source = include_str!("filter_shaders_rgba8.wgsl");
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("FilterRenderer shader"),
            source: wgpu::ShaderSource::Wgsl(Cow::Borrowed(shader_source)),
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("FilterRenderer bind group layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::StorageTexture {
                        access: wgpu::StorageTextureAccess::ReadOnly,
                        format: LAYER_TEXTURE_FORMAT,
                        view_dimension: wgpu::TextureViewDimension::D2,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::StorageTexture {
                        access: wgpu::StorageTextureAccess::ReadWrite,
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
            ],
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("FilterRenderer pipeline layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline_color = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("FilterRenderer color pipeline"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: "color_filter",
        });
        let pipeline_blur = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("FilterRenderer blur pipeline"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: "blur_pass",
        });
        let pipeline_morph = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("FilterRenderer morph pipeline"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: "morphology_pass",
        });
        let pipeline_antialias_alpha =
            device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("FilterRenderer antialias alpha pipeline"),
                layout: Some(&pipeline_layout),
                module: &shader,
                entry_point: "antialias_alpha",
            });
        let pipeline_antialias_edge =
            device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("FilterRenderer antialias edge pipeline"),
                layout: Some(&pipeline_layout),
                module: &shader,
                entry_point: "antialias_edge",
            });

        let uniform_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("FilterRenderer uniform buffer"),
            size: std::mem::size_of::<FilterConfig>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        if let Some(err) = device_pop_scope(device.as_ref()) {
            return Err(format!("wgpu validation error during filter init: {err}"));
        }
        if let Some(err) = device_pop_scope(device.as_ref()) {
            return Err(format!(
                "wgpu out-of-memory error during filter init: {err}"
            ));
        }

        let (scratch_a, scratch_a_view) = create_scratch(device.as_ref(), 1, 1, "A");
        let (scratch_b, scratch_b_view) = create_scratch(device.as_ref(), 1, 1, "B");

        Ok(Self {
            device,
            queue,
            bind_group_layout,
            uniform_buffer,
            pipeline_color,
            pipeline_blur,
            pipeline_morph,
            pipeline_antialias_alpha,
            pipeline_antialias_edge,
            scratch_a,
            scratch_a_view,
            scratch_b,
            scratch_b_view,
            width: 1,
            height: 1,
        })
    }

    pub fn set_canvas_size(&mut self, width: u32, height: u32) {
        if self.width == width && self.height == height {
            return;
        }
        let (scratch_a, scratch_a_view) = create_scratch(self.device.as_ref(), width, height, "A");
        let (scratch_b, scratch_b_view) = create_scratch(self.device.as_ref(), width, height, "B");
        self.scratch_a = scratch_a;
        self.scratch_a_view = scratch_a_view;
        self.scratch_b = scratch_b;
        self.scratch_b_view = scratch_b_view;
        self.width = width.max(1);
        self.height = height.max(1);
    }

    pub fn apply_color_filter(
        &mut self,
        layer_texture: &wgpu::Texture,
        layer_view: &wgpu::TextureView,
        layer_index: u32,
        filter_type: u32,
        params0: [f32; 4],
        params1: [f32; 4],
    ) -> Result<(), String> {
        if self.width == 0 || self.height == 0 {
            return Ok(());
        }
        device_push_scopes(self.device.as_ref());

        let config = FilterConfig {
            width: self.width,
            height: self.height,
            radius: 0,
            flags: filter_type,
            params0,
            params1,
        };
        self.write_config(&config);

        self.run_pass(&self.pipeline_color, layer_view, &self.scratch_a_view)?;
        copy_texture(
            self.device.as_ref(),
            self.queue.as_ref(),
            &self.scratch_a,
            layer_texture,
            self.width,
            self.height,
            layer_index,
        );

        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!("wgpu validation error during filter pass: {err}"));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu out-of-memory error during filter pass: {err}"
            ));
        }
        Ok(())
    }

    pub fn apply_gaussian_blur(
        &mut self,
        layer_view: &wgpu::TextureView,
        radius: f32,
    ) -> Result<(), String> {
        if self.width == 0 || self.height == 0 {
            return Ok(());
        }
        let sigma = gaussian_sigma(radius);
        if sigma <= 0.0 {
            return Ok(());
        }
        let box_sizes = compute_box_sizes(sigma, 3);
        if box_sizes.is_empty() {
            return Ok(());
        }

        device_push_scopes(self.device.as_ref());

        let premul_config = FilterConfig {
            width: self.width,
            height: self.height,
            radius: 0,
            flags: FILTER_PREMULTIPLY,
            params0: [0.0; 4],
            params1: [0.0; 4],
        };
        self.write_config(&premul_config);
        self.run_pass(&self.pipeline_color, layer_view, &self.scratch_a_view)?;

        let mut src_view = &self.scratch_a_view;
        for box_size in box_sizes {
            let pass_radius = ((box_size - 1) / 2).max(0) as u32;
            if pass_radius == 0 {
                continue;
            }
            let horizontal = FilterConfig {
                width: self.width,
                height: self.height,
                radius: pass_radius,
                flags: 0,
                params0: [0.0; 4],
                params1: [0.0; 4],
            };
            self.write_config(&horizontal);
            self.run_pass(&self.pipeline_blur, src_view, &self.scratch_b_view)?;

            let vertical = FilterConfig {
                width: self.width,
                height: self.height,
                radius: pass_radius,
                flags: 1,
                params0: [0.0; 4],
                params1: [0.0; 4],
            };
            self.write_config(&vertical);
            self.run_pass(
                &self.pipeline_blur,
                &self.scratch_b_view,
                &self.scratch_a_view,
            )?;
            src_view = &self.scratch_a_view;
        }

        let unpremul_config = FilterConfig {
            width: self.width,
            height: self.height,
            radius: 0,
            flags: FILTER_UNPREMULTIPLY,
            params0: [0.0; 4],
            params1: [0.0; 4],
        };
        self.write_config(&unpremul_config);
        self.run_pass(&self.pipeline_color, src_view, layer_view)?;

        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!("wgpu validation error during gaussian blur: {err}"));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu out-of-memory error during gaussian blur: {err}"
            ));
        }
        Ok(())
    }

    pub fn apply_morphology(
        &mut self,
        layer_texture: &wgpu::Texture,
        layer_view: &wgpu::TextureView,
        layer_index: u32,
        radius: u32,
        dilate: bool,
    ) -> Result<(), String> {
        if self.width == 0 || self.height == 0 || radius == 0 {
            return Ok(());
        }
        device_push_scopes(self.device.as_ref());

        let morph_config = FilterConfig {
            width: self.width,
            height: self.height,
            radius: 0,
            flags: if dilate { 1 } else { 0 },
            params0: [0.0; 4],
            params1: [0.0; 4],
        };
        self.write_config(&morph_config);

        if radius == 1 {
            self.run_pass(&self.pipeline_morph, layer_view, &self.scratch_a_view)?;
            copy_texture(
                self.device.as_ref(),
                self.queue.as_ref(),
                &self.scratch_a,
                layer_texture,
                self.width,
                self.height,
                layer_index,
            );
        } else {
            let mut src_view = layer_view;
            let mut use_a = true;
            for step in 0..radius {
                let last = step + 1 == radius;
                let dst_view: &wgpu::TextureView = if last {
                    layer_view
                } else if use_a {
                    &self.scratch_a_view
                } else {
                    &self.scratch_b_view
                };
                if last && std::ptr::eq(src_view, dst_view) {
                    break;
                }
                self.run_pass(&self.pipeline_morph, src_view, dst_view)?;
                src_view = dst_view;
                use_a = !use_a;
            }
        }

        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!("wgpu validation error during morphology: {err}"));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!("wgpu out-of-memory error during morphology: {err}"));
        }
        Ok(())
    }

    pub fn apply_antialias(
        &mut self,
        layer_view: &wgpu::TextureView,
        level: u32,
    ) -> Result<(), String> {
        if self.width == 0 || self.height == 0 {
            return Ok(());
        }
        let profile =
            antialias_profile(level).ok_or_else(|| "antialias level invalid".to_string())?;
        if profile.is_empty() {
            return Ok(());
        }
        device_push_scopes(self.device.as_ref());

        let mut src_view = layer_view;
        let mut use_a = true;
        for &blend in profile {
            let config = FilterConfig {
                width: self.width,
                height: self.height,
                radius: 0,
                flags: 0,
                params0: [blend as f32, 0.0, 0.0, 0.0],
                params1: [0.0; 4],
            };
            self.write_config(&config);
            let dst_view = if use_a {
                &self.scratch_a_view
            } else {
                &self.scratch_b_view
            };
            self.run_pass(&self.pipeline_antialias_alpha, src_view, dst_view)?;
            src_view = dst_view;
            use_a = !use_a;
        }

        let edge_config = FilterConfig {
            width: self.width,
            height: self.height,
            radius: 0,
            flags: 0,
            params0: [0.0; 4],
            params1: [0.0; 4],
        };
        self.write_config(&edge_config);
        self.run_pass(&self.pipeline_antialias_edge, src_view, layer_view)?;

        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!("wgpu validation error during antialias: {err}"));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!("wgpu out-of-memory error during antialias: {err}"));
        }
        Ok(())
    }

    fn run_pass(
        &self,
        pipeline: &ComputePipeline,
        src_view: &wgpu::TextureView,
        dst_view: &wgpu::TextureView,
    ) -> Result<(), String> {
        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("FilterRenderer bind group"),
            layout: &self.bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(src_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::TextureView(dst_view),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: self.uniform_buffer.as_entire_binding(),
                },
            ],
        });

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("FilterRenderer encoder"),
            });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("FilterRenderer pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            let wg_x = (self.width + (WORKGROUP_SIZE - 1)) / WORKGROUP_SIZE;
            let wg_y = (self.height + (WORKGROUP_SIZE - 1)) / WORKGROUP_SIZE;
            pass.dispatch_workgroups(wg_x, wg_y, 1);
        }
        self.queue.submit(Some(encoder.finish()));
        Ok(())
    }
}

fn antialias_profile(level: u32) -> Option<&'static [f64]> {
    match level {
        0 => Some(&[0.25]),
        1 => Some(&[0.35, 0.35]),
        2 => Some(&[0.45, 0.5, 0.5]),
        3 => Some(&[0.6, 0.65, 0.7, 0.75]),
        4 => Some(&[0.6, 0.65, 0.7, 0.75, 0.8]),
        5 => Some(&[0.65, 0.7, 0.75, 0.8, 0.85]),
        6 => Some(&[0.7, 0.75, 0.8, 0.85, 0.9]),
        7 => Some(&[0.7, 0.75, 0.8, 0.85, 0.9, 0.9]),
        8 => Some(&[0.75, 0.8, 0.85, 0.9, 0.9, 0.9]),
        9 => Some(&[0.8, 0.85, 0.9, 0.9, 0.9, 0.9]),
        _ => None,
    }
}

fn gaussian_sigma(radius: f32) -> f32 {
    let clamped = radius.clamp(0.0, 1000.0);
    if clamped <= 0.0 {
        return 0.0;
    }
    (clamped * 0.5).max(0.1)
}

fn compute_box_sizes(sigma: f32, count: usize) -> Vec<i32> {
    if count == 0 {
        return Vec::new();
    }
    let n = count as f32;
    let ideal = ((12.0 * sigma * sigma / n) + 1.0).sqrt();
    let mut lower = ideal.floor() as i32;
    if lower % 2 == 0 {
        lower = (lower - 1).max(1);
    }
    if lower < 1 {
        lower = 1;
    }
    let upper = lower + 2;
    let m_ideal =
        (12.0 * sigma * sigma - n * (lower * lower) as f32 - 4.0 * n * lower as f32 - 3.0 * n)
            / (-4.0 * lower as f32 - 4.0);
    let m = m_ideal.round().clamp(0.0, n) as usize;
    let mut sizes = Vec::with_capacity(count);
    for i in 0..count {
        sizes.push(if i < m { lower } else { upper });
    }
    sizes
}

fn create_scratch(
    device: &wgpu::Device,
    width: u32,
    height: u32,
    label_suffix: &str,
) -> (wgpu::Texture, wgpu::TextureView) {
    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some(&format!("FilterRenderer scratch {label_suffix}")),
        size: wgpu::Extent3d {
            width: width.max(1),
            height: height.max(1),
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: LAYER_TEXTURE_FORMAT,
        usage: wgpu::TextureUsages::STORAGE_BINDING
            | wgpu::TextureUsages::COPY_DST
            | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
    (texture, view)
}

fn copy_texture(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    src: &wgpu::Texture,
    dst: &wgpu::Texture,
    width: u32,
    height: u32,
    layer_index: u32,
) {
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("FilterRenderer copy encoder"),
    });
    encoder.copy_texture_to_texture(
        wgpu::ImageCopyTexture {
            texture: src,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::ImageCopyTexture {
            texture: dst,
            mip_level: 0,
            origin: wgpu::Origin3d {
                x: 0,
                y: 0,
                z: layer_index,
            },
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::Extent3d {
            width: width.max(1),
            height: height.max(1),
            depth_or_array_layers: 1,
        },
    );
    queue.submit(Some(encoder.finish()));
}

fn device_push_scopes(device: &wgpu::Device) {
    device.push_error_scope(wgpu::ErrorFilter::OutOfMemory);
    device.push_error_scope(wgpu::ErrorFilter::Validation);
}

fn device_pop_scope(device: &wgpu::Device) -> Option<wgpu::Error> {
    pollster::block_on(device.pop_error_scope())
}
