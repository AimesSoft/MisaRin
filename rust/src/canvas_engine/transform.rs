use std::borrow::Cow;
use std::sync::Arc;

use crate::gpu::debug::{self, LogLevel};

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct TransformUniform {
    matrix: [f32; 16],
    layer_index: u32,
    flags: u32,
    _pad0: u32,
    _pad1: u32,
}

pub(crate) struct LayerTransformRenderer {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    pipeline: wgpu::ComputePipeline,
    bind_group_layout: wgpu::BindGroupLayout,
    uniform_buffer: wgpu::Buffer,
    output_texture: Option<wgpu::Texture>,
    output_view: Option<wgpu::TextureView>,
    output_width: u32,
    output_height: u32,
}

impl LayerTransformRenderer {
    pub(crate) fn new(device: Arc<wgpu::Device>, queue: Arc<wgpu::Queue>) -> Result<Self, String> {
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("misa-rin layer transform shader"),
            source: wgpu::ShaderSource::Wgsl(Cow::Borrowed(include_str!("transform.wgsl"))),
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("misa-rin layer transform bgl"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Uint,
                        view_dimension: wgpu::TextureViewDimension::D2Array,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::StorageTexture {
                        access: wgpu::StorageTextureAccess::WriteOnly,
                        format: wgpu::TextureFormat::R32Uint,
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
                        min_binding_size: wgpu::BufferSize::new(
                            std::mem::size_of::<TransformUniform>() as u64,
                        ),
                    },
                    count: None,
                },
            ],
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("misa-rin layer transform pipeline layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("misa-rin layer transform pipeline"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: "main",
        });

        let uniform_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("misa-rin layer transform uniforms"),
            size: std::mem::size_of::<TransformUniform>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        Ok(Self {
            device,
            queue,
            pipeline,
            bind_group_layout,
            uniform_buffer,
            output_texture: None,
            output_view: None,
            output_width: 0,
            output_height: 0,
        })
    }

    fn ensure_output_texture(&mut self, width: u32, height: u32) {
        if self.output_width == width && self.output_height == height {
            return;
        }
        self.output_width = width;
        self.output_height = height;
        let texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("misa-rin layer transform output"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::R32Uint,
            usage: wgpu::TextureUsages::STORAGE_BINDING | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        self.output_texture = Some(texture);
        self.output_view = Some(view);
    }

    pub(crate) fn apply_transform(
        &mut self,
        layers_view: &wgpu::TextureView,
        layers_texture: &wgpu::Texture,
        canvas_width: u32,
        canvas_height: u32,
        layer_index: u32,
        matrix: [f32; 16],
        bilinear: bool,
    ) -> Result<(), String> {
        if canvas_width == 0 || canvas_height == 0 {
            return Ok(());
        }
        self.ensure_output_texture(canvas_width, canvas_height);
        let output_view = self
            .output_view
            .as_ref()
            .ok_or_else(|| "transform output view not initialized".to_string())?;
        let output_texture = self
            .output_texture
            .as_ref()
            .ok_or_else(|| "transform output texture not initialized".to_string())?;

        let flags = if bilinear { 2 } else { 0 };
        let uniform = TransformUniform {
            matrix,
            layer_index,
            flags,
            _pad0: 0,
            _pad1: 0,
        };
        self.queue
            .write_buffer(&self.uniform_buffer, 0, bytemuck::bytes_of(&uniform));

        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("misa-rin layer transform bind group"),
            layout: &self.bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(layers_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::TextureView(output_view),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: self.uniform_buffer.as_entire_binding(),
                },
            ],
        });

        device_push_scopes(self.device.as_ref());
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("misa-rin layer transform encoder"),
            });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("misa-rin layer transform pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            let dispatch_x = (canvas_width + 7) / 8;
            let dispatch_y = (canvas_height + 7) / 8;
            pass.dispatch_workgroups(dispatch_x, dispatch_y, 1);
        }
        encoder.copy_texture_to_texture(
            wgpu::ImageCopyTexture {
                texture: output_texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::ImageCopyTexture {
                texture: layers_texture,
                mip_level: 0,
                origin: wgpu::Origin3d {
                    x: 0,
                    y: 0,
                    z: layer_index,
                },
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::Extent3d {
                width: canvas_width,
                height: canvas_height,
                depth_or_array_layers: 1,
            },
        );
        self.queue.submit(Some(encoder.finish()));

        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            debug::log(
                LogLevel::Warn,
                format_args!("layer transform GPU failed: {err}"),
            );
            return Err("layer transform GPU failed".to_string());
        }
        Ok(())
    }
}

fn device_push_scopes(device: &wgpu::Device) {
    #[cfg(target_family = "wasm")]
    {
        let _ = device;
        return;
    }
    #[cfg(not(target_family = "wasm"))]
    {
        device.push_error_scope(wgpu::ErrorFilter::OutOfMemory);
        device.push_error_scope(wgpu::ErrorFilter::Validation);
    }
}

fn device_pop_scope(device: &wgpu::Device) -> Option<wgpu::Error> {
    #[cfg(target_family = "wasm")]
    {
        let _ = device;
        return None;
    }
    #[cfg(not(target_family = "wasm"))]
    {
        let mut out: Option<wgpu::Error> = None;
        for _ in 0..2 {
            match pollster::block_on(device.pop_error_scope()) {
                Some(err) => {
                    if out.is_none() {
                        out = Some(err);
                    }
                }
                None => {}
            }
        }
        out
    }
}
