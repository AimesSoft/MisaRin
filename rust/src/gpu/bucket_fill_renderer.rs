use std::sync::Arc;

use wgpu::{BindGroup, BindGroupLayout, ComputePipeline, Device, Queue};

use crate::gpu::layer_format::LAYER_TEXTURE_FORMAT;
use crate::gpu::wgpu_utils;

const WORKGROUP_SIZE: u32 = 16;
const QUEUE_GROUP_SIZE: u32 = WORKGROUP_SIZE * WORKGROUP_SIZE;
const READBACK_BATCH: u32 = 16;

const MODE_CLEAR: u32 = 0;
const MODE_READ_BASE: u32 = 1;
const MODE_BUILD_TARGET: u32 = 2;
const MODE_COPY_TARGET_TO_FILL: u32 = 3;
const MODE_INIT_INVERSE: u32 = 4;
const MODE_DILATE_STEP: u32 = 5;
const MODE_INVERT_MASKB: u32 = 6;
const MODE_INIT_OUTSIDE: u32 = 7;
const MODE_EXPAND_OUTSIDE: u32 = 8;
const MODE_FRONTIER_SWAP: u32 = 9;
const MODE_FILL_INIT: u32 = 10;
const MODE_FILL_EXPAND: u32 = 11;
const MODE_SNAP_INIT: u32 = 12;
const MODE_SNAP_EXPAND: u32 = 13;
const MODE_TOUCH_INIT: u32 = 14;
const MODE_TOUCH_EXPAND: u32 = 15;
const MODE_APPLY_FILL: u32 = 16;
const MODE_SWALLOW_SEED: u32 = 17;
const MODE_SWALLOW_EXPAND: u32 = 18;
const MODE_EXPAND_MASK: u32 = 19;
const MODE_AA_PASS: u32 = 20;
const MODE_COPY_TEMP_TO_LAYER: u32 = 21;
const MODE_COPY_MASKB_BIT: u32 = 22;
const MODE_EXPAND_FILL_ONE: u32 = 23;
const MODE_FILL_QUEUE_CLEAR: u32 = 24;
const MODE_FILL_QUEUE_PREPARE: u32 = 25;
const MODE_FILL_QUEUE_EXPAND: u32 = 26;
const MODE_FILL_QUEUE_SWAP: u32 = 27;
const MODE_LABEL_INIT: u32 = 28;
const MODE_LABEL_HOOK: u32 = 29;
const MODE_LABEL_COMPRESS: u32 = 30;
const MODE_LABEL_SEED: u32 = 31;
const MODE_LABEL_MARK: u32 = 32;

const MASK_OPENED: u32 = 1;
const MASK_TEMP: u32 = 64;

const STATE_BASE_COLOR_OFFSET: u64 = 0;
const STATE_CHANGED_OFFSET: u64 = 4;
const STATE_ITER_OFFSET: u64 = 8;
const STATE_EFFECTIVE_START_OFFSET: u64 = 12;
const STATE_TOUCHES_OFFSET: u64 = 16;
const STATE_SNAP_FOUND_OFFSET: u64 = 20;
const STATE_SEED_ROOT_OFFSET: u64 = 24;
const STATE_SIZE: u64 = 28;
const INDIRECT_ARGS_SIZE: u64 = 12;

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct BucketFillConfig {
    width: u32,
    height: u32,
    start_x: u32,
    start_y: u32,
    start_index: u32,
    layer_index: u32,
    layer_count: u32,
    tolerance: u32,
    fill_gap: u32,
    antialias_level: u32,
    contiguous: u32,
    sample_all_layers: u32,
    selection_enabled: u32,
    swallow_count: u32,
    fill_color: u32,
    mode: u32,
    aux0: u32,
    aux1: u32,
    aux2: u32,
    aa_factor: f32,
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct BucketFillLayerParams {
    opacity: f32,
    visible: f32,
    clipping_mask: f32,
    _pad0: f32,
}

#[derive(Clone, Copy, Debug)]
struct BucketFillStateSnapshot {
    base_color: u32,
    changed: u32,
    iter_flag: u32,
    effective_start: u32,
    touches_outside: u32,
    snap_found: u32,
    seed_root: u32,
}

pub struct BucketFillRenderer {
    device: Arc<Device>,
    queue: Arc<Queue>,
    pipeline: ComputePipeline,
    bind_group_layout: BindGroupLayout,

    mask_a: wgpu::Texture,
    mask_a_view: wgpu::TextureView,
    mask_b: wgpu::Texture,
    mask_b_view: wgpu::TextureView,
    mask_width: u32,
    mask_height: u32,
    dummy_layer: wgpu::Texture,
    dummy_layer_view: wgpu::TextureView,
    dummy_layers: wgpu::Texture,
    dummy_layers_view: wgpu::TextureView,

    config_buffer: wgpu::Buffer,
    state_buffer: wgpu::Buffer,
    state_readback: wgpu::Buffer,
    frontier_a: wgpu::Buffer,
    frontier_b: wgpu::Buffer,
    frontier_counts: wgpu::Buffer,
    frontier_indirect_storage: wgpu::Buffer,
    frontier_indirect_args: wgpu::Buffer,
    visited_bits: wgpu::Buffer,
    frontier_capacity: u32,
    visited_capacity: u32,

    layer_params_buffer: wgpu::Buffer,
    layer_params_capacity: usize,

    swallow_buffer: wgpu::Buffer,
    swallow_capacity: usize,
}

impl BucketFillRenderer {
    pub fn new(device: Arc<Device>, queue: Arc<Queue>) -> Result<Self, String> {
        device_push_scopes(device.as_ref());

        let shader_source = include_str!("bucket_fill_shaders_rgba8.wgsl");
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("BucketFillRenderer shader"),
            source: wgpu::ShaderSource::Wgsl(shader_source.into()),
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("BucketFillRenderer bind group layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::StorageTexture {
                        access: wgpu::StorageTextureAccess::ReadWrite,
                        format: LAYER_TEXTURE_FORMAT,
                        view_dimension: wgpu::TextureViewDimension::D2,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: false },
                        view_dimension: wgpu::TextureViewDimension::D2Array,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::StorageTexture {
                        access: wgpu::StorageTextureAccess::ReadWrite,
                        format: LAYER_TEXTURE_FORMAT,
                        view_dimension: wgpu::TextureViewDimension::D2,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 3,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::StorageTexture {
                        access: wgpu::StorageTextureAccess::ReadWrite,
                        format: LAYER_TEXTURE_FORMAT,
                        view_dimension: wgpu::TextureViewDimension::D2,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 4,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 5,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 6,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 7,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 8,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 9,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 10,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 11,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 12,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("BucketFillRenderer pipeline layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("BucketFillRenderer compute pipeline"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: "bucket_fill_main",
        });

        let config_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BucketFillRenderer config buffer"),
            size: std::mem::size_of::<BucketFillConfig>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let state_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BucketFillRenderer state buffer"),
            size: STATE_SIZE,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_DST
                | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        let state_readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BucketFillRenderer state readback"),
            size: STATE_SIZE,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let frontier_a = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BucketFillRenderer frontier A"),
            size: 4,
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        });
        let frontier_b = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BucketFillRenderer frontier B"),
            size: 4,
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        });
        let frontier_counts = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BucketFillRenderer frontier counts"),
            size: 8,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let frontier_indirect_storage = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BucketFillRenderer frontier indirect storage"),
            size: INDIRECT_ARGS_SIZE,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let frontier_indirect_args = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BucketFillRenderer frontier indirect args"),
            size: INDIRECT_ARGS_SIZE,
            usage: wgpu::BufferUsages::INDIRECT | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let visited_bits = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BucketFillRenderer visited bits"),
            size: 4,
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        });

        let layer_params_buffer = create_layer_params_buffer(device.as_ref(), 1)?;
        let swallow_buffer = create_swallow_buffer(device.as_ref(), 1)?;
        let (mask_a, mask_a_view) = create_mask_texture(device.as_ref(), 1, 1, "BucketFill mask A");
        let (mask_b, mask_b_view) = create_mask_texture(device.as_ref(), 1, 1, "BucketFill mask B");
        let (dummy_layer, dummy_layer_view) =
            create_mask_texture(device.as_ref(), 1, 1, "BucketFill dummy layer");
        let (dummy_layers, dummy_layers_view) =
            create_sampled_layers_texture(device.as_ref(), 1, 1, "BucketFill dummy layers");

        if let Some(err) = device_pop_scope(device.as_ref()) {
            return Err(format!(
                "wgpu validation error during bucket fill init: {err}"
            ));
        }
        if let Some(err) = device_pop_scope(device.as_ref()) {
            return Err(format!(
                "wgpu out-of-memory error during bucket fill init: {err}"
            ));
        }

        Ok(Self {
            device,
            queue,
            pipeline,
            bind_group_layout,
            mask_a,
            mask_a_view,
            mask_b,
            mask_b_view,
            mask_width: 1,
            mask_height: 1,
            dummy_layer,
            dummy_layer_view,
            dummy_layers,
            dummy_layers_view,
            config_buffer,
            state_buffer,
            state_readback,
            frontier_a,
            frontier_b,
            frontier_counts,
            frontier_indirect_storage,
            frontier_indirect_args,
            visited_bits,
            frontier_capacity: 1,
            visited_capacity: 1,
            layer_params_buffer,
            layer_params_capacity: 1,
            swallow_buffer,
            swallow_capacity: 1,
        })
    }

    pub fn bucket_fill(
        &mut self,
        layer_view: &wgpu::TextureView,
        layers_view: &wgpu::TextureView,
        layer_index: u32,
        layer_count: usize,
        layer_opacity: &[f32],
        layer_visible: &[bool],
        layer_clipping_mask: &[bool],
        canvas_width: u32,
        canvas_height: u32,
        start_x: i32,
        start_y: i32,
        color_argb: u32,
        contiguous: bool,
        sample_all_layers: bool,
        tolerance: u8,
        fill_gap: u8,
        antialias_level: u8,
        swallow_colors: &[u32],
        selection_mask: Option<&[u8]>,
    ) -> Result<bool, String> {
        if canvas_width == 0 || canvas_height == 0 {
            return Ok(false);
        }
        let width = canvas_width;
        let height = canvas_height;
        if start_x < 0 || start_y < 0 {
            return Ok(false);
        }
        let start_x = start_x as u32;
        let start_y = start_y as u32;
        if start_x >= width || start_y >= height {
            return Ok(false);
        }

        self.ensure_masks(width, height)?;
        self.ensure_frontier_buffers(width, height)?;
        self.ensure_layer_params_capacity(layer_count)?;
        self.write_layer_params(
            layer_count,
            layer_opacity,
            layer_visible,
            layer_clipping_mask,
        )?;

        let filtered_swallow: Vec<u32> = swallow_colors
            .iter()
            .copied()
            .filter(|&c| c != color_argb)
            .collect();
        self.ensure_swallow_capacity(filtered_swallow.len().max(1))?;
        self.write_swallow_colors(&filtered_swallow)?;

        let expected_len = (width as usize)
            .checked_mul(height as usize)
            .ok_or_else(|| "bucket fill selection mask size overflow".to_string())?;
        let selection_enabled = selection_mask
            .filter(|mask| mask.len() == expected_len)
            .is_some();
        if selection_enabled {
            if let Some(mask) = selection_mask {
                write_mask_texture(self.device.as_ref(), self.queue.as_ref(), &self.mask_a, width, height, mask)?;
            }
        }

        let start_index = start_y.saturating_mul(width).saturating_add(start_x);

        let mut config = BucketFillConfig {
            width,
            height,
            start_x,
            start_y,
            start_index,
            layer_index,
            layer_count: layer_count as u32,
            tolerance: tolerance as u32,
            fill_gap: fill_gap as u32,
            antialias_level: antialias_level as u32,
            contiguous: if contiguous { 1 } else { 0 },
            sample_all_layers: if sample_all_layers { 1 } else { 0 },
            selection_enabled: if selection_enabled { 1 } else { 0 },
            swallow_count: filtered_swallow.len() as u32,
            fill_color: color_argb,
            mode: MODE_CLEAR,
            aux0: 0,
            aux1: 0,
            aux2: 0,
            aa_factor: 0.0,
        };

        self.write_state_field(STATE_BASE_COLOR_OFFSET, 0);
        self.write_state_field(STATE_CHANGED_OFFSET, 0);
        self.write_state_field(STATE_ITER_OFFSET, 0);
        self.write_state_field(STATE_EFFECTIVE_START_OFFSET, u32::MAX);
        self.write_state_field(STATE_TOUCHES_OFFSET, 0);
        self.write_state_field(STATE_SNAP_FOUND_OFFSET, 0);
        self.write_state_field(STATE_SEED_ROOT_OFFSET, u32::MAX);

        let write_bind_group = self.create_bind_group(layer_view, &self.dummy_layers_view)?;
        let sample_bind_group = self.create_bind_group(&self.dummy_layer_view, layers_view)?;
        let dispatch = |config: &BucketFillConfig| -> Result<(), String> {
            let bind_group = if matches!(config.mode, MODE_READ_BASE | MODE_BUILD_TARGET) {
                &sample_bind_group
            } else {
                &write_bind_group
            };
            self.dispatch_full(bind_group, config)
        };

        config.mode = MODE_CLEAR;
        dispatch(&config)?;

        config.mode = MODE_READ_BASE;
        dispatch(&config)?;

        config.mode = MODE_BUILD_TARGET;
        dispatch(&config)?;

        if config.contiguous == 0 {
            config.mode = MODE_COPY_TARGET_TO_FILL;
            dispatch(&config)?;
        } else if config.fill_gap > 0 {
            config.mode = MODE_INIT_INVERSE;
            dispatch(&config)?;

            for _ in 0..config.fill_gap {
                config.mode = MODE_DILATE_STEP;
                config.aux0 = MASK_OPENED;
                config.aux1 = MASK_TEMP;
                config.aux2 = 0;
                dispatch(&config)?;

                config.mode = MODE_COPY_MASKB_BIT;
                config.aux0 = MASK_TEMP;
                config.aux1 = MASK_OPENED;
                dispatch(&config)?;
            }

            config.mode = MODE_INVERT_MASKB;
            config.aux0 = MASK_OPENED;
            dispatch(&config)?;

            for _ in 0..config.fill_gap {
                config.mode = MODE_DILATE_STEP;
                config.aux0 = MASK_OPENED;
                config.aux1 = MASK_TEMP;
                config.aux2 = 1;
                dispatch(&config)?;

                config.mode = MODE_COPY_MASKB_BIT;
                config.aux0 = MASK_TEMP;
                config.aux1 = MASK_OPENED;
                dispatch(&config)?;
            }

            config.mode = MODE_INIT_OUTSIDE;
            dispatch(&config)?;

            let _ =
                self.run_batched_until(&mut config, MODE_EXPAND_OUTSIDE, &dispatch, |snapshot| {
                    snapshot.iter_flag == 0
                })?;

            let mut snap_found = false;
            let mut effective_start = start_index;
            config.mode = MODE_SNAP_INIT;
            dispatch(&config)?;
            let max_depth = config.fill_gap.saturating_add(1);
            for _ in 0..=max_depth {
                self.write_state_field(STATE_ITER_OFFSET, 0);
                self.write_state_field(STATE_SNAP_FOUND_OFFSET, 0);
                config.mode = MODE_SNAP_EXPAND;
                dispatch(&config)?;
                config.mode = MODE_FRONTIER_SWAP;
                dispatch(&config)?;
                let snapshot = self.read_state()?;
                if snapshot.snap_found != 0 {
                    effective_start = snapshot.effective_start;
                    snap_found = true;
                    break;
                }
                if snapshot.iter_flag == 0 {
                    break;
                }
            }
            if snap_found {
                self.write_state_field(STATE_EFFECTIVE_START_OFFSET, effective_start);
            }

            let touches_outside = if snap_found {
                self.write_state_field(STATE_TOUCHES_OFFSET, 0);
                config.mode = MODE_TOUCH_INIT;
                dispatch(&config)?;
                let snapshot = self.run_batched_until(
                    &mut config,
                    MODE_TOUCH_EXPAND,
                    &dispatch,
                    |snapshot| snapshot.iter_flag == 0 || snapshot.touches_outside != 0,
                )?;
                snapshot.touches_outside != 0
            } else {
                true
            };

            config.aux0 = if touches_outside { 0 } else { 1 };
            if touches_outside {
                config.start_index = start_index;
            } else {
                config.start_index = effective_start;
            }
            self.run_label_union_find(&mut config, &dispatch)?;
        } else {
            config.aux0 = 0;
            config.start_index = start_index;
            self.run_label_union_find(&mut config, &dispatch)?;

            if config.tolerance > 0 {
                config.mode = MODE_EXPAND_FILL_ONE;
                dispatch(&config)?;
            }
        }

        config.mode = MODE_APPLY_FILL;
        dispatch(&config)?;

        if !filtered_swallow.is_empty() {
            for (idx, _) in filtered_swallow.iter().enumerate() {
                self.write_state_field(STATE_ITER_OFFSET, 0);
                config.mode = MODE_SWALLOW_SEED;
                config.aux0 = idx as u32;
                dispatch(&config)?;
                let mut snapshot = self.read_state()?;
                if snapshot.iter_flag == 0 {
                    continue;
                }
                config.aux0 = idx as u32;
                let _ = self.run_batched_until(
                    &mut config,
                    MODE_SWALLOW_EXPAND,
                    &dispatch,
                    |snapshot| snapshot.iter_flag == 0,
                )?;
            }
        }

        if config.antialias_level > 0 {
            config.mode = MODE_EXPAND_MASK;
            dispatch(&config)?;

            let profile: &[f32] = match config.antialias_level {
                1 => &[0.35, 0.35],
                2 => &[0.45, 0.5, 0.5],
                3 => &[0.6, 0.65, 0.7, 0.75],
                4 => &[0.6, 0.65, 0.7, 0.75, 0.8],
                5 => &[0.65, 0.7, 0.75, 0.8, 0.85],
                6 => &[0.7, 0.75, 0.8, 0.85, 0.9],
                7 => &[0.7, 0.75, 0.8, 0.85, 0.9, 0.9],
                8 => &[0.75, 0.8, 0.85, 0.9, 0.9, 0.9],
                _ => &[0.8, 0.85, 0.9, 0.9, 0.9, 0.9],
            };

            let mut src_is_layer = true;
            for &factor in profile {
                if factor <= 0.0 {
                    continue;
                }
                config.mode = MODE_AA_PASS;
                config.aux0 = if src_is_layer { 1 } else { 0 };
                config.aa_factor = factor;
                dispatch(&config)?;
                src_is_layer = !src_is_layer;
            }

            if !src_is_layer {
                config.mode = MODE_COPY_TEMP_TO_LAYER;
                dispatch(&config)?;
            }
        }

        let snapshot = self.read_state()?;
        Ok(snapshot.changed != 0)
    }

    fn ensure_masks(&mut self, width: u32, height: u32) -> Result<(), String> {
        if width == self.mask_width && height == self.mask_height {
            return Ok(());
        }
        let (mask_a, mask_a_view) =
            create_mask_texture(self.device.as_ref(), width, height, "BucketFill mask A");
        let (mask_b, mask_b_view) =
            create_mask_texture(self.device.as_ref(), width, height, "BucketFill mask B");
        self.mask_a = mask_a;
        self.mask_a_view = mask_a_view;
        self.mask_b = mask_b;
        self.mask_b_view = mask_b_view;
        self.mask_width = width;
        self.mask_height = height;
        Ok(())
    }

    fn ensure_frontier_buffers(&mut self, width: u32, height: u32) -> Result<(), String> {
        let pixel_count = width
            .checked_mul(height)
            .ok_or_else(|| "bucket fill frontier size overflow".to_string())?;
        if pixel_count == 0 {
            return Ok(());
        }
        let word_count = pixel_count.saturating_add(31) / 32;
        if pixel_count <= self.frontier_capacity && word_count <= self.visited_capacity {
            return Ok(());
        }
        let frontier_size = (pixel_count as u64) * std::mem::size_of::<u32>() as u64;
        let visited_size = (word_count as u64) * std::mem::size_of::<u32>() as u64;

        self.frontier_a = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BucketFillRenderer frontier A"),
            size: frontier_size,
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        });
        self.frontier_b = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BucketFillRenderer frontier B"),
            size: frontier_size,
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        });
        self.visited_bits = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("BucketFillRenderer visited bits"),
            size: visited_size.max(4),
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        });
        self.frontier_capacity = pixel_count;
        self.visited_capacity = word_count;
        Ok(())
    }

    fn ensure_layer_params_capacity(&mut self, layer_count: usize) -> Result<(), String> {
        if layer_count <= self.layer_params_capacity {
            return Ok(());
        }
        let buffer = create_layer_params_buffer(self.device.as_ref(), layer_count)?;
        self.layer_params_buffer = buffer;
        self.layer_params_capacity = layer_count;
        Ok(())
    }

    fn ensure_swallow_capacity(&mut self, count: usize) -> Result<(), String> {
        if count <= self.swallow_capacity {
            return Ok(());
        }
        let buffer = create_swallow_buffer(self.device.as_ref(), count)?;
        self.swallow_buffer = buffer;
        self.swallow_capacity = count;
        Ok(())
    }

    fn write_layer_params(
        &self,
        layer_count: usize,
        layer_opacity: &[f32],
        layer_visible: &[bool],
        layer_clipping_mask: &[bool],
    ) -> Result<(), String> {
        if layer_count == 0 {
            return Ok(());
        }
        let mut params: Vec<BucketFillLayerParams> = Vec::with_capacity(layer_count);
        for i in 0..layer_count {
            let raw_opacity = layer_opacity.get(i).copied().unwrap_or(1.0);
            let opacity = if raw_opacity.is_finite() {
                raw_opacity.clamp(0.0, 1.0)
            } else {
                0.0
            };
            let visible = if *layer_visible.get(i).unwrap_or(&true) {
                1.0
            } else {
                0.0
            };
            let clipping_mask = if *layer_clipping_mask.get(i).unwrap_or(&false) {
                1.0
            } else {
                0.0
            };
            params.push(BucketFillLayerParams {
                opacity,
                visible,
                clipping_mask,
                _pad0: 0.0,
            });
        }
        self.queue
            .write_buffer(&self.layer_params_buffer, 0, bytemuck::cast_slice(&params));
        Ok(())
    }

    fn write_swallow_colors(&self, colors: &[u32]) -> Result<(), String> {
        if colors.is_empty() {
            let zero = [0u32; 1];
            self.queue
                .write_buffer(&self.swallow_buffer, 0, bytemuck::bytes_of(&zero));
            return Ok(());
        }
        self.queue
            .write_buffer(&self.swallow_buffer, 0, bytemuck::cast_slice(colors));
        Ok(())
    }

    fn create_bind_group(
        &self,
        layer_view: &wgpu::TextureView,
        layers_view: &wgpu::TextureView,
    ) -> Result<BindGroup, String> {
        Ok(self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("BucketFillRenderer bind group"),
            layout: &self.bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(layer_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::TextureView(layers_view),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(&self.mask_a_view),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: wgpu::BindingResource::TextureView(&self.mask_b_view),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: self.layer_params_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 5,
                    resource: self.state_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 6,
                    resource: self.swallow_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 7,
                    resource: self.config_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 8,
                    resource: self.frontier_a.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 9,
                    resource: self.frontier_b.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 10,
                    resource: self.frontier_counts.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 11,
                    resource: self.frontier_indirect_storage.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 12,
                    resource: self.visited_bits.as_entire_binding(),
                },
            ],
        }))
    }

    fn dispatch_full(
        &self,
        bind_group: &BindGroup,
        config: &BucketFillConfig,
    ) -> Result<(), String> {
        let dispatch_x = (config.width + WORKGROUP_SIZE - 1) / WORKGROUP_SIZE;
        let dispatch_y = (config.height + WORKGROUP_SIZE - 1) / WORKGROUP_SIZE;
        self.dispatch_groups(bind_group, config, dispatch_x, dispatch_y, 1)
    }

    fn dispatch_groups(
        &self,
        bind_group: &BindGroup,
        config: &BucketFillConfig,
        dispatch_x: u32,
        dispatch_y: u32,
        dispatch_z: u32,
    ) -> Result<(), String> {
        wgpu_utils::write_buffer(
            self.device.as_ref(),
            self.queue.as_ref(),
            &self.config_buffer,
            0,
            bytemuck::bytes_of(config),
        );
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("BucketFillRenderer encoder"),
            });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("BucketFillRenderer compute pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, bind_group, &[]);
            pass.dispatch_workgroups(dispatch_x, dispatch_y, dispatch_z);
        }
        self.queue.submit(Some(encoder.finish()));
        Ok(())
    }

    fn dispatch_groups_with_indirect_copy(
        &self,
        bind_group: &BindGroup,
        config: &BucketFillConfig,
        dispatch_x: u32,
        dispatch_y: u32,
        dispatch_z: u32,
    ) -> Result<(), String> {
        self.queue
            .write_buffer(&self.config_buffer, 0, bytemuck::bytes_of(config));
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("BucketFillRenderer encoder"),
            });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("BucketFillRenderer compute pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, bind_group, &[]);
            pass.dispatch_workgroups(dispatch_x, dispatch_y, dispatch_z);
        }
        encoder.copy_buffer_to_buffer(
            &self.frontier_indirect_storage,
            0,
            &self.frontier_indirect_args,
            0,
            INDIRECT_ARGS_SIZE,
        );
        self.queue.submit(Some(encoder.finish()));
        Ok(())
    }

    fn dispatch_indirect(
        &self,
        bind_group: &BindGroup,
        config: &BucketFillConfig,
    ) -> Result<(), String> {
        self.queue
            .write_buffer(&self.config_buffer, 0, bytemuck::bytes_of(config));
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("BucketFillRenderer encoder"),
            });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("BucketFillRenderer compute pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, bind_group, &[]);
            pass.dispatch_workgroups_indirect(&self.frontier_indirect_args, 0);
        }
        self.queue.submit(Some(encoder.finish()));
        Ok(())
    }

    fn reset_frontier_state(&self) {
        let counts = [0u32; 2];
        wgpu_utils::write_buffer(
            self.device.as_ref(),
            self.queue.as_ref(),
            &self.frontier_counts,
            0,
            bytemuck::cast_slice(&counts),
        );
        let indirect = [0u32, 1u32, 1u32];
        wgpu_utils::write_buffer(
            self.device.as_ref(),
            self.queue.as_ref(),
            &self.frontier_indirect_storage,
            0,
            bytemuck::cast_slice(&indirect),
        );
        wgpu_utils::write_buffer(
            self.device.as_ref(),
            self.queue.as_ref(),
            &self.frontier_indirect_args,
            0,
            bytemuck::cast_slice(&indirect),
        );
    }

    fn dispatch_frontier_clear(
        &self,
        config: &mut BucketFillConfig,
        bind_group: &BindGroup,
    ) -> Result<(), String> {
        let total_pixels = (config.width as u64) * (config.height as u64);
        if total_pixels == 0 {
            return Ok(());
        }
        let word_count = (total_pixels + 31) / 32;
        let dispatch_x =
            ((word_count + (QUEUE_GROUP_SIZE as u64) - 1) / (QUEUE_GROUP_SIZE as u64)) as u32;
        if dispatch_x == 0 {
            return Ok(());
        }
        config.mode = MODE_FILL_QUEUE_CLEAR;
        self.dispatch_groups(bind_group, config, dispatch_x, 1, 1)
    }

    fn dispatch_frontier_prepare(
        &self,
        config: &mut BucketFillConfig,
        bind_group: &BindGroup,
        input_is_b: bool,
    ) -> Result<(), String> {
        config.mode = MODE_FILL_QUEUE_PREPARE;
        config.aux1 = if input_is_b { 1 } else { 0 };
        self.dispatch_groups_with_indirect_copy(bind_group, config, 1, 1, 1)
    }

    fn dispatch_frontier_expand(
        &self,
        config: &mut BucketFillConfig,
        bind_group: &BindGroup,
        input_is_b: bool,
    ) -> Result<(), String> {
        config.mode = MODE_FILL_QUEUE_EXPAND;
        config.aux1 = if input_is_b { 1 } else { 0 };
        self.dispatch_indirect(bind_group, config)
    }

    fn dispatch_frontier_swap(
        &self,
        config: &mut BucketFillConfig,
        bind_group: &BindGroup,
        input_is_b: bool,
    ) -> Result<(), String> {
        config.mode = MODE_FILL_QUEUE_SWAP;
        config.aux1 = if input_is_b { 1 } else { 0 };
        self.dispatch_groups_with_indirect_copy(bind_group, config, 1, 1, 1)
    }

    fn run_fill_queue(
        &self,
        config: &mut BucketFillConfig,
        bind_group: &BindGroup,
    ) -> Result<(), String> {
        // GPU worklist: iterate frontier buffers and drive dispatch via indirect counts.
        self.dispatch_frontier_prepare(config, bind_group, false)?;
        let max_steps = config.width.saturating_add(config.height);
        let mut input_is_b = false;
        for _ in 0..max_steps {
            self.dispatch_frontier_expand(config, bind_group, input_is_b)?;
            self.dispatch_frontier_swap(config, bind_group, input_is_b)?;
            input_is_b = !input_is_b;
        }
        Ok(())
    }

    fn run_label_union_find<F>(
        &self,
        config: &mut BucketFillConfig,
        dispatch: &F,
    ) -> Result<(), String>
    where
        F: Fn(&BucketFillConfig) -> Result<(), String>,
    {
        self.write_state_field(STATE_SEED_ROOT_OFFSET, u32::MAX);

        config.mode = MODE_LABEL_INIT;
        dispatch(config)?;

        let iterations = Self::label_iterations(config.width, config.height);
        for _ in 0..iterations {
            config.mode = MODE_LABEL_HOOK;
            dispatch(config)?;
            config.mode = MODE_LABEL_COMPRESS;
            dispatch(config)?;
        }

        config.mode = MODE_LABEL_SEED;
        dispatch(config)?;
        config.mode = MODE_LABEL_MARK;
        dispatch(config)?;
        Ok(())
    }

    fn label_iterations(width: u32, height: u32) -> u32 {
        let total = (width as u64) * (height as u64);
        if total <= 1 {
            return 0;
        }
        let bits = 64 - (total - 1).leading_zeros();
        bits.min(32)
    }

    fn run_batched_until<F, S>(
        &self,
        config: &mut BucketFillConfig,
        expand_mode: u32,
        dispatch: &F,
        mut stop: S,
    ) -> Result<BucketFillStateSnapshot, String>
    where
        F: Fn(&BucketFillConfig) -> Result<(), String>,
        S: FnMut(&BucketFillStateSnapshot) -> bool,
    {
        loop {
            self.write_state_field(STATE_ITER_OFFSET, 0);
            for _ in 0..READBACK_BATCH {
                config.mode = expand_mode;
                dispatch(config)?;
                config.mode = MODE_FRONTIER_SWAP;
                dispatch(config)?;
            }
            let snapshot = self.read_state()?;
            if stop(&snapshot) {
                return Ok(snapshot);
            }
        }
    }

    fn read_state(&self) -> Result<BucketFillStateSnapshot, String> {
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("BucketFillRenderer state readback encoder"),
            });
        encoder.copy_buffer_to_buffer(&self.state_buffer, 0, &self.state_readback, 0, STATE_SIZE);
        self.queue.submit(Some(encoder.finish()));

        let slice = self.state_readback.slice(0..STATE_SIZE);
        let (tx, rx) = std::sync::mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |res| {
            let _ = tx.send(res);
        });
        self.device.poll(wgpu::Maintain::Wait);
        match rx.recv() {
            Ok(Ok(())) => {}
            Ok(Err(err)) => return Err(format!("wgpu map_async failed: {err:?}")),
            Err(err) => return Err(format!("wgpu map_async channel failed: {err}")),
        }
        let data = slice.get_mapped_range();
        let values: &[u32] = bytemuck::cast_slice(&data);
        let snapshot = BucketFillStateSnapshot {
            base_color: values.get(0).copied().unwrap_or(0),
            changed: values.get(1).copied().unwrap_or(0),
            iter_flag: values.get(2).copied().unwrap_or(0),
            effective_start: values.get(3).copied().unwrap_or(u32::MAX),
            touches_outside: values.get(4).copied().unwrap_or(0),
            snap_found: values.get(5).copied().unwrap_or(0),
            seed_root: values.get(6).copied().unwrap_or(u32::MAX),
        };
        drop(data);
        self.state_readback.unmap();
        Ok(snapshot)
    }

    fn write_state_field(&self, offset: u64, value: u32) {
        self.queue
            .write_buffer(&self.state_buffer, offset, bytemuck::bytes_of(&value));
    }

    //
}

fn create_mask_texture(
    device: &wgpu::Device,
    width: u32,
    height: u32,
    label: &str,
) -> (wgpu::Texture, wgpu::TextureView) {
    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some(label),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: LAYER_TEXTURE_FORMAT,
        usage: wgpu::TextureUsages::STORAGE_BINDING
            | wgpu::TextureUsages::COPY_SRC
            | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    let view = texture.create_view(&wgpu::TextureViewDescriptor {
        dimension: Some(wgpu::TextureViewDimension::D2),
        ..Default::default()
    });
    (texture, view)
}

fn create_sampled_layers_texture(
    device: &wgpu::Device,
    width: u32,
    height: u32,
    label: &str,
) -> (wgpu::Texture, wgpu::TextureView) {
    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some(label),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: LAYER_TEXTURE_FORMAT,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    let view = texture.create_view(&wgpu::TextureViewDescriptor {
        dimension: Some(wgpu::TextureViewDimension::D2Array),
        ..Default::default()
    });
    (texture, view)
}

fn create_layer_params_buffer(
    device: &wgpu::Device,
    capacity: usize,
) -> Result<wgpu::Buffer, String> {
    let size = capacity
        .checked_mul(std::mem::size_of::<BucketFillLayerParams>())
        .ok_or_else(|| "layer params buffer size overflow".to_string())?;
    let max_storage_binding = device.limits().max_storage_buffer_binding_size as u64;
    let max_buffer_size = device.limits().max_buffer_size;
    if (size as u64) > max_buffer_size {
        return Err(format!(
            "layer params buffer too large: {size} bytes (max {max_buffer_size})"
        ));
    }
    if (size as u64) > max_storage_binding {
        return Err(format!(
            "layer params buffer too large: {size} bytes (max {max_storage_binding})"
        ));
    }
    Ok(device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("BucketFillRenderer layer params"),
        size: size as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    }))
}

fn create_swallow_buffer(device: &wgpu::Device, capacity: usize) -> Result<wgpu::Buffer, String> {
    let size = capacity
        .checked_mul(std::mem::size_of::<u32>())
        .ok_or_else(|| "swallow buffer size overflow".to_string())?;
    Ok(device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("BucketFillRenderer swallow colors"),
        size: size as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    }))
}

fn write_mask_texture(
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

    const BYTES_PER_PIXEL: u32 = 4;
    const COPY_BYTES_PER_ROW_ALIGNMENT: u32 = 256;
    #[cfg(target_os = "android")]
    const MAX_CHUNK_BYTES: usize = 512 * 1024;
    #[cfg(not(target_os = "android"))]
    const MAX_CHUNK_BYTES: usize = 4 * 1024 * 1024;

    let bytes_per_row_unpadded = width.saturating_mul(BYTES_PER_PIXEL);
    let bytes_per_row_padded = align_up_u32(bytes_per_row_unpadded, COPY_BYTES_PER_ROW_ALIGNMENT);
    if bytes_per_row_padded == 0 {
        return Err("selection mask bytes_per_row == 0".to_string());
    }

    let row_texels = (bytes_per_row_padded / BYTES_PER_PIXEL) as usize;
    let row_bytes = bytes_per_row_padded as usize;
    let rows_per_chunk = (MAX_CHUNK_BYTES / row_bytes).max(1) as u32;

    let mut y: u32 = 0;
    while y < height {
        let chunk_h = (height - y).min(rows_per_chunk);
        let mut data: Vec<u32> = vec![0; row_texels * chunk_h as usize];
        for row in 0..chunk_h {
            let src_offset = ((y + row) * width) as usize;
            let dst_offset = row as usize * row_texels;
            let src = &mask[src_offset..src_offset + width as usize];
            for (i, &value) in src.iter().enumerate() {
                data[dst_offset + i] = value as u32;
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
            bytemuck::cast_slice(&data),
        );

        y = y.saturating_add(chunk_h);
    }

    Ok(())
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
