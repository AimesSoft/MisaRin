use std::borrow::Cow;

use wgpu::util::DeviceExt as _;

use crate::gpu::wgpu_utils;

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub(crate) struct PreviewSegment {
    pub(crate) p0: [f32; 2],
    pub(crate) p1: [f32; 2],
    pub(crate) r0: f32,
    pub(crate) r1: f32,
    pub(crate) rot_sin: f32,
    pub(crate) rot_cos: f32,
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub(crate) struct PreviewConfig {
    pub(crate) canvas_width: u32,
    pub(crate) canvas_height: u32,
    pub(crate) brush_shape: u32,
    pub(crate) antialias_level: u32,
    pub(crate) color_argb: u32,
    pub(crate) erase_mode: u32,
    pub(crate) mirror_x: u32,
    pub(crate) _pad0: u32,
    pub(crate) hollow_ratio: f32,
    pub(crate) softness: f32,
    pub(crate) layer_opacity: f32,
    pub(crate) _pad1: f32,
}

enum PreviewPipelineKind {
    Alpha,
    Max,
    Erase,
}

pub(crate) struct PreviewRenderer {
    format: wgpu::TextureFormat,
    pipeline_alpha: wgpu::RenderPipeline,
    pipeline_max: wgpu::RenderPipeline,
    pipeline_erase: wgpu::RenderPipeline,
    bind_group_layout: wgpu::BindGroupLayout,
    config_buffer: wgpu::Buffer,
    segments_buffer: wgpu::Buffer,
    segments_capacity: usize,
    bind_group: wgpu::BindGroup,
}

impl PreviewRenderer {
    pub(crate) fn new(device: &wgpu::Device, format: wgpu::TextureFormat) -> Self {
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("misa-rin preview renderer shader"),
            source: wgpu::ShaderSource::Wgsl(Cow::Borrowed(include_str!("preview_stroke.wgsl"))),
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("misa-rin preview renderer bgl"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::VERTEX | wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::VERTEX | wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: wgpu::BufferSize::new(
                            std::mem::size_of::<PreviewConfig>() as u64,
                        ),
                    },
                    count: None,
                },
            ],
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("misa-rin preview renderer pipeline layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline_alpha =
            create_pipeline(device, &shader, &pipeline_layout, format, PreviewPipelineKind::Alpha);
        let pipeline_max =
            create_pipeline(device, &shader, &pipeline_layout, format, PreviewPipelineKind::Max);
        let pipeline_erase =
            create_pipeline(device, &shader, &pipeline_layout, format, PreviewPipelineKind::Erase);

        let config_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("misa-rin preview renderer config"),
            size: std::mem::size_of::<PreviewConfig>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let segments_capacity = 256usize;
        let segments_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("misa-rin preview renderer segments"),
            contents: bytemuck::cast_slice(&vec![
                PreviewSegment {
                    p0: [0.0, 0.0],
                    p1: [0.0, 0.0],
                    r0: 0.0,
                    r1: 0.0,
                    rot_sin: 0.0,
                    rot_cos: 1.0,
                };
                segments_capacity
            ]),
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        });

        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("misa-rin preview renderer bind group"),
            layout: &bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: segments_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: config_buffer.as_entire_binding(),
                },
            ],
        });

        Self {
            format,
            pipeline_alpha,
            pipeline_max,
            pipeline_erase,
            bind_group_layout,
            config_buffer,
            segments_buffer,
            segments_capacity,
            bind_group,
        }
    }

    fn ensure_segments_capacity(&mut self, device: &wgpu::Device, len: usize) {
        if len <= self.segments_capacity {
            return;
        }
        let mut next = self.segments_capacity.max(1);
        while next < len {
            next *= 2;
        }
        let buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("misa-rin preview renderer segments"),
            size: (next as u64) * std::mem::size_of::<PreviewSegment>() as u64,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        self.segments_buffer = buffer;
        self.segments_capacity = next;
        self.bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("misa-rin preview renderer bind group"),
            layout: &self.bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: self.segments_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: self.config_buffer.as_entire_binding(),
                },
            ],
        });
    }

    pub(crate) fn render(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        present_view: &wgpu::TextureView,
        config: PreviewConfig,
        segments: &[PreviewSegment],
        use_accumulate: bool,
    ) {
        if segments.is_empty() {
            return;
        }
        self.ensure_segments_capacity(device, segments.len());
        wgpu_utils::write_buffer(
            device,
            queue,
            &self.segments_buffer,
            0,
            bytemuck::cast_slice(segments),
        );
        wgpu_utils::write_buffer(
            device,
            queue,
            &self.config_buffer,
            0,
            bytemuck::bytes_of(&config),
        );

        let pipeline = if config.erase_mode != 0 {
            &self.pipeline_erase
        } else if use_accumulate {
            &self.pipeline_alpha
        } else {
            &self.pipeline_max
        };

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("misa-rin preview renderer encoder"),
        });
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("misa-rin preview renderer pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: present_view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Load,
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            pass.set_pipeline(pipeline);
            pass.set_bind_group(0, &self.bind_group, &[]);
            pass.draw(0..6, 0..segments.len() as u32);
        }
        queue.submit(Some(encoder.finish()));
    }
}

fn create_pipeline(
    device: &wgpu::Device,
    shader: &wgpu::ShaderModule,
    layout: &wgpu::PipelineLayout,
    format: wgpu::TextureFormat,
    kind: PreviewPipelineKind,
) -> wgpu::RenderPipeline {
    let blend = match kind {
        PreviewPipelineKind::Alpha => Some(wgpu::BlendState::ALPHA_BLENDING),
        PreviewPipelineKind::Max => Some(wgpu::BlendState {
            color: wgpu::BlendComponent {
                src_factor: wgpu::BlendFactor::One,
                dst_factor: wgpu::BlendFactor::One,
                operation: wgpu::BlendOperation::Max,
            },
            alpha: wgpu::BlendComponent {
                src_factor: wgpu::BlendFactor::One,
                dst_factor: wgpu::BlendFactor::One,
                operation: wgpu::BlendOperation::Max,
            },
        }),
        PreviewPipelineKind::Erase => Some(wgpu::BlendState {
            color: wgpu::BlendComponent {
                src_factor: wgpu::BlendFactor::Zero,
                dst_factor: wgpu::BlendFactor::OneMinusSrcAlpha,
                operation: wgpu::BlendOperation::Add,
            },
            alpha: wgpu::BlendComponent {
                src_factor: wgpu::BlendFactor::Zero,
                dst_factor: wgpu::BlendFactor::OneMinusSrcAlpha,
                operation: wgpu::BlendOperation::Add,
            },
        }),
    };

    device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("misa-rin preview renderer pipeline"),
        layout: Some(layout),
        vertex: wgpu::VertexState {
            module: shader,
            entry_point: "vs_main",
            buffers: &[],
        },
        fragment: Some(wgpu::FragmentState {
            module: shader,
            entry_point: "fs_main",
            targets: &[Some(wgpu::ColorTargetState {
                format,
                blend,
                write_mask: wgpu::ColorWrites::ALL,
            })],
        }),
        primitive: wgpu::PrimitiveState {
            topology: wgpu::PrimitiveTopology::TriangleList,
            strip_index_format: None,
            front_face: wgpu::FrontFace::Ccw,
            cull_mode: None,
            polygon_mode: wgpu::PolygonMode::Fill,
            unclipped_depth: false,
            conservative: false,
        },
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        multiview: None,
    })
}
