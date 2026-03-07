use std::sync::mpsc;
use std::time::Instant;

use wgpu::{ComputePipeline, Device, Queue};

use super::blend_modes::map_canvas_blend_mode_index;
use super::debug::{self, LogLevel};

const MAX_LAYERS: usize = 16;
const WORKGROUP_SIZE: u32 = 16;
const MAX_CANVAS_SIZE: u32 = 8192;
const NEEDS_FULL_UPLOAD_PREFIX: &str = "GPU_COMPOSITOR_NEEDS_FULL_UPLOAD";

pub struct LayerData {
    pub pixels: Vec<u32>, // ARGB
    pub opacity: f32,     // 0.0-1.0
    pub blend_mode: u32,  // CanvasLayerBlendMode.index
    pub visible: bool,
    pub clipping_mask: bool,
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct ShaderLayerParams {
    opacity: f32,
    blend_mode: u32,
    visible: u32,
    clipping_mask: u32,
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct ShaderConfig {
    width: u32,
    height: u32,
    layer_count: u32,
    _pad0: u32,
    layers: [ShaderLayerParams; MAX_LAYERS],
}

pub struct GpuCompositor {
    device: Device,
    queue: Queue,
    pipeline: ComputePipeline,

    bind_group_layout: wgpu::BindGroupLayout,
    bind_group: Option<wgpu::BindGroup>,

    input_buffer: Option<wgpu::Buffer>,
    output_buffer: Option<wgpu::Buffer>,
    readback_buffer: Option<wgpu::Buffer>,
    uniform_buffer: wgpu::Buffer,

    cached_width: u32,
    cached_height: u32,
    cached_layer_capacity: usize,

    layer_uploaded: [bool; MAX_LAYERS],
}

impl GpuCompositor {
    pub fn new() -> Result<Self, String> {
        let t0 = Instant::now();
        let backends = if cfg!(target_os = "android") {
            wgpu::Backends::VULKAN | wgpu::Backends::GL
        } else {
            wgpu::Backends::all()
        };
        let instance_flags = if cfg!(target_os = "android") {
            wgpu::InstanceFlags::empty()
        } else {
            wgpu::InstanceFlags::default()
        };
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends,
            flags: instance_flags,
            ..Default::default()
        });

        let adapter = if cfg!(target_os = "android") {
            crate::wgpu_adapter::select_compute_adapter(&instance, backends)
                .ok_or_else(|| "wgpu: no compute-capable GPU adapter found".to_string())?
        } else {
            pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                compatible_surface: None,
                force_fallback_adapter: false,
            }))
            .ok_or_else(|| "wgpu: no compatible GPU adapter found".to_string())?
        };

        if debug::level() >= LogLevel::Info {
            let info = adapter.get_info();
            let limits = adapter.limits();
            debug::log(
                LogLevel::Info,
                format_args!(
                    "GpuCompositor adapter: backend={:?} device_type={:?} name='{}' max_tex_2d={} max_buf={} max_storage_binding={}",
                    info.backend,
                    info.device_type,
                    info.name,
                    limits.max_texture_dimension_2d,
                    limits.max_buffer_size,
                    limits.max_storage_buffer_binding_size
                ),
            );
        }

        let adapter_limits = adapter.limits();
        let required_limits = adapter_limits;

        let (device, queue) = pollster::block_on(adapter.request_device(
            &wgpu::DeviceDescriptor {
                label: Some("misa-rin GpuCompositor device"),
                required_features: wgpu::Features::empty(),
                required_limits,
            },
            None,
        ))
        .map_err(|e| format!("wgpu: request_device failed: {e:?}"))?;

        device.push_error_scope(wgpu::ErrorFilter::OutOfMemory);
        device.push_error_scope(wgpu::ErrorFilter::Validation);

        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("GpuCompositor shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shaders.wgsl").into()),
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("GpuCompositor bind group layout"),
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
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
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
            label: Some("GpuCompositor pipeline layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("GpuCompositor compute pipeline"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: "composite_main",
        });

        let uniform_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GpuCompositor uniform buffer"),
            size: std::mem::size_of::<ShaderConfig>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        if let Some(err) = pollster::block_on(device.pop_error_scope()) {
            return Err(format!("wgpu validation error during init: {err}"));
        }
        if let Some(err) = pollster::block_on(device.pop_error_scope()) {
            return Err(format!("wgpu out-of-memory error during init: {err}"));
        }

        debug::log(
            LogLevel::Info,
            format_args!("GpuCompositor new ok in {:?}.", t0.elapsed()),
        );

        Ok(Self {
            device,
            queue,
            pipeline,
            bind_group_layout,
            bind_group: None,
            input_buffer: None,
            output_buffer: None,
            readback_buffer: None,
            uniform_buffer,
            cached_width: 0,
            cached_height: 0,
            cached_layer_capacity: 0,
            layer_uploaded: [false; MAX_LAYERS],
        })
    }

    pub fn composite_layers(
        &mut self,
        layers: Vec<LayerData>,
        width: u32,
        height: u32,
    ) -> Result<Vec<u32>, String> {
        let verbose = debug::level() >= LogLevel::Verbose;
        let t0 = if verbose { Some(Instant::now()) } else { None };

        if width == 0 || height == 0 {
            return Ok(Vec::new());
        }
        if width > MAX_CANVAS_SIZE || height > MAX_CANVAS_SIZE {
            return Err(format!(
                "canvas size {width}x{height} exceeds max {MAX_CANVAS_SIZE}x{MAX_CANVAS_SIZE}"
            ));
        }
        let pixel_count: usize = (width as usize)
            .checked_mul(height as usize)
            .ok_or_else(|| "pixel_count overflow".to_string())?;

        if layers.len() > MAX_LAYERS {
            return Err(format!(
                "too many layers: {} (max {MAX_LAYERS})",
                layers.len()
            ));
        }
        if layers.is_empty() {
            return Ok(vec![0u32; pixel_count]);
        }

        for (idx, layer) in layers.iter().enumerate() {
            if layer.pixels.is_empty() {
                continue;
            }
            if layer.pixels.len() != pixel_count {
                return Err(format!(
                    "layer[{idx}] pixel count mismatch: got {}, expected {}",
                    layer.pixels.len(),
                    pixel_count
                ));
            }
        }

        let pixel_bytes: u64 = (pixel_count as u64)
            .checked_mul(std::mem::size_of::<u32>() as u64)
            .ok_or_else(|| "pixel_bytes overflow".to_string())?;

        let input_bytes: u64 = pixel_bytes
            .checked_mul(layers.len() as u64)
            .ok_or_else(|| "input buffer size overflow".to_string())?;

        let limits = self.device.limits();
        let max_buffer_size = limits.max_buffer_size;
        let max_storage_binding_size = limits.max_storage_buffer_binding_size as u64;
        let max_storage_buffer_size = max_buffer_size.min(max_storage_binding_size);

        let needs_tiling = pixel_bytes > max_buffer_size
            || pixel_bytes > max_storage_buffer_size
            || input_bytes > max_storage_buffer_size;

        if needs_tiling {
            debug::log(
                LogLevel::Info,
                format_args!(
                    "GpuCompositor composite_layers needs tiling: canvas={width}x{height} layers={} pixel_bytes={pixel_bytes} input_bytes={input_bytes} max_buf={max_buffer_size} max_storage_buf={max_storage_buffer_size}",
                    layers.len()
                ),
            );
        }
        if needs_tiling {
            if layers.iter().any(|layer| layer.pixels.is_empty()) {
                return Err(format!(
                    "{NEEDS_FULL_UPLOAD_PREFIX}: tiled composite requires full layer pixels"
                ));
            }
            return self.composite_layers_tiled(layers, width, height, pixel_count);
        }

        let result = self.composite_layers_full(layers, width, height, pixel_bytes);
        if let Some(t0) = t0 {
            debug::log(
                LogLevel::Verbose,
                format_args!("GpuCompositor composite_layers done in {:?}.", t0.elapsed()),
            );
        }
        result
    }

    fn composite_layers_full(
        &mut self,
        layers: Vec<LayerData>,
        width: u32,
        height: u32,
        pixel_bytes: u64,
    ) -> Result<Vec<u32>, String> {
        self.ensure_resources(width, height, layers.len())?;

        let input_buffer = self
            .input_buffer
            .as_ref()
            .ok_or_else(|| "wgpu input buffer not initialized".to_string())?;
        for (i, layer) in layers.iter().enumerate() {
            if layer.pixels.is_empty() {
                if !self.layer_uploaded[i] {
                    return Err(format!(
                        "{NEEDS_FULL_UPLOAD_PREFIX}: layer[{i}] pixels missing"
                    ));
                }
                continue;
            }
            let offset: u64 = (i as u64)
                .checked_mul(pixel_bytes)
                .ok_or_else(|| "layer buffer offset overflow".to_string())?;
            self.queue
                .write_buffer(input_buffer, offset, bytemuck::cast_slice(&layer.pixels));
            self.layer_uploaded[i] = true;
        }

        let mut shader_layers: [ShaderLayerParams; MAX_LAYERS] = [ShaderLayerParams {
            opacity: 0.0,
            blend_mode: 0,
            visible: 0,
            clipping_mask: 0,
        }; MAX_LAYERS];
        for (i, layer) in layers.iter().enumerate() {
            shader_layers[i] = ShaderLayerParams {
                opacity: clamp_unit_f32(layer.opacity),
                blend_mode: map_canvas_blend_mode_index(layer.blend_mode).as_u32(),
                visible: if layer.visible { 1 } else { 0 },
                clipping_mask: if layer.clipping_mask { 1 } else { 0 },
            };
        }

        let config = ShaderConfig {
            width,
            height,
            layer_count: layers.len() as u32,
            _pad0: 0,
            layers: shader_layers,
        };
        self.queue
            .write_buffer(&self.uniform_buffer, 0, bytemuck::bytes_of(&config));

        let bind_group = self
            .bind_group
            .as_ref()
            .ok_or_else(|| "wgpu bind group not initialized".to_string())?;
        let output_buffer = self
            .output_buffer
            .as_ref()
            .ok_or_else(|| "wgpu output buffer not initialized".to_string())?;
        let readback_buffer = self
            .readback_buffer
            .as_ref()
            .ok_or_else(|| "wgpu readback buffer not initialized".to_string())?;

        device_push_scopes(&self.device);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("GpuCompositor encoder"),
            });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("GpuCompositor pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, bind_group, &[]);
            let wg_x = (width + (WORKGROUP_SIZE - 1)) / WORKGROUP_SIZE;
            let wg_y = (height + (WORKGROUP_SIZE - 1)) / WORKGROUP_SIZE;
            pass.dispatch_workgroups(wg_x, wg_y, 1);
        }

        encoder.copy_buffer_to_buffer(output_buffer, 0, readback_buffer, 0, pixel_bytes);

        self.queue.submit(Some(encoder.finish()));

        let buffer_slice = readback_buffer.slice(0..pixel_bytes);
        let (tx, rx) = mpsc::channel();
        buffer_slice.map_async(wgpu::MapMode::Read, move |res| {
            let _ = tx.send(res);
        });

        self.device.poll(wgpu::Maintain::Wait);

        let map_status: Result<(), String> = match rx.recv() {
            Ok(Ok(())) => Ok(()),
            Ok(Err(e)) => Err(format!("wgpu map_async failed: {e:?}")),
            Err(e) => Err(format!("wgpu map_async channel failed: {e}")),
        };

        let mut result: Option<Vec<u32>> = None;
        if map_status.is_ok() {
            let mapped = buffer_slice.get_mapped_range();
            result = Some(bytemuck::cast_slice(&mapped).to_vec());
            drop(mapped);
            readback_buffer.unmap();
        }

        if let Some(err) = device_pop_scope(&self.device) {
            return Err(format!("wgpu validation error during composite: {err}"));
        }
        if let Some(err) = device_pop_scope(&self.device) {
            return Err(format!("wgpu out-of-memory error during composite: {err}"));
        }

        map_status?;
        Ok(result.unwrap_or_default())
    }

    fn composite_layers_tiled(
        &mut self,
        layers: Vec<LayerData>,
        width: u32,
        height: u32,
        pixel_count: usize,
    ) -> Result<Vec<u32>, String> {
        if layers.is_empty() {
            return Ok(vec![0u32; pixel_count]);
        }

        let layer_count: usize = layers.len();
        let limits = self.device.limits();
        let max_buffer_size = limits.max_buffer_size;
        let max_storage_binding_size = limits.max_storage_buffer_binding_size as u64;
        let max_storage_buffer_size = max_buffer_size.min(max_storage_binding_size);
        let bytes_per_pixel = std::mem::size_of::<u32>() as u64;

        let max_tile_pixels: u64 = max_storage_buffer_size
            .checked_div(bytes_per_pixel)
            .and_then(|v| v.checked_div(layer_count as u64))
            .ok_or_else(|| "device storage buffer limit too small".to_string())?;
        if max_tile_pixels == 0 {
            return Err("device storage buffer limit too small".to_string());
        }

        let mut tile_dim: u32 = (max_tile_pixels as f64).sqrt().floor() as u32;
        tile_dim = (tile_dim / WORKGROUP_SIZE) * WORKGROUP_SIZE;
        if tile_dim < WORKGROUP_SIZE {
            return Err("device storage buffer limit too small for tiling".to_string());
        }
        tile_dim = tile_dim.min(1024);

        let tile_pixel_count: usize = (tile_dim as usize)
            .checked_mul(tile_dim as usize)
            .ok_or_else(|| "tile_pixel_count overflow".to_string())?;
        let tile_pixel_bytes: u64 = (tile_pixel_count as u64)
            .checked_mul(bytes_per_pixel)
            .ok_or_else(|| "tile_pixel_bytes overflow".to_string())?;

        self.ensure_resources(tile_dim, tile_dim, layer_count)?;

        let input_buffer = self
            .input_buffer
            .as_ref()
            .ok_or_else(|| "wgpu input buffer not initialized".to_string())?;
        let bind_group = self
            .bind_group
            .as_ref()
            .ok_or_else(|| "wgpu bind group not initialized".to_string())?;
        let output_buffer = self
            .output_buffer
            .as_ref()
            .ok_or_else(|| "wgpu output buffer not initialized".to_string())?;
        let readback_buffer = self
            .readback_buffer
            .as_ref()
            .ok_or_else(|| "wgpu readback buffer not initialized".to_string())?;

        let mut shader_layers: [ShaderLayerParams; MAX_LAYERS] = [ShaderLayerParams {
            opacity: 0.0,
            blend_mode: 0,
            visible: 0,
            clipping_mask: 0,
        }; MAX_LAYERS];
        for (i, layer) in layers.iter().enumerate() {
            shader_layers[i] = ShaderLayerParams {
                opacity: clamp_unit_f32(layer.opacity),
                blend_mode: map_canvas_blend_mode_index(layer.blend_mode).as_u32(),
                visible: if layer.visible { 1 } else { 0 },
                clipping_mask: if layer.clipping_mask { 1 } else { 0 },
            };
        }
        let config = ShaderConfig {
            width: tile_dim,
            height: tile_dim,
            layer_count: layer_count as u32,
            _pad0: 0,
            layers: shader_layers,
        };
        self.queue
            .write_buffer(&self.uniform_buffer, 0, bytemuck::bytes_of(&config));

        let mut result: Vec<u32> = vec![0u32; pixel_count];

        let mut tile_layer: Vec<u32> = vec![0u32; tile_pixel_count];
        let tile_step = tile_dim as usize;
        let canvas_width_usize = width as usize;

        for tile_y_usize in (0..height as usize).step_by(tile_step) {
            for tile_x_usize in (0..width as usize).step_by(tile_step) {
                let copy_w = (width as usize).saturating_sub(tile_x_usize).min(tile_step);
                let copy_h = (height as usize)
                    .saturating_sub(tile_y_usize)
                    .min(tile_step);

                for (layer_idx, layer) in layers.iter().enumerate() {
                    if !layer.visible || !(layer.opacity > 0.0) {
                        continue;
                    }

                    for row in 0..copy_h {
                        let src_y = tile_y_usize + row;
                        let src_row_start = src_y * canvas_width_usize + tile_x_usize;
                        let src_range = src_row_start..(src_row_start + copy_w);
                        let dst_row_start = row * tile_step;
                        let dst_range = dst_row_start..(dst_row_start + copy_w);
                        tile_layer[dst_range].copy_from_slice(&layer.pixels[src_range]);
                    }

                    let layer_offset: u64 = (layer_idx as u64)
                        .checked_mul(tile_pixel_bytes)
                        .ok_or_else(|| "tile layer buffer offset overflow".to_string())?;
                    self.queue.write_buffer(
                        input_buffer,
                        layer_offset,
                        bytemuck::cast_slice(&tile_layer),
                    );
                }

                device_push_scopes(&self.device);

                let mut encoder =
                    self.device
                        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("GpuCompositor tiled encoder"),
                        });
                {
                    let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                        label: Some("GpuCompositor tiled pass"),
                        timestamp_writes: None,
                    });
                    pass.set_pipeline(&self.pipeline);
                    pass.set_bind_group(0, bind_group, &[]);
                    let wg_x = (tile_dim + (WORKGROUP_SIZE - 1)) / WORKGROUP_SIZE;
                    let wg_y = (tile_dim + (WORKGROUP_SIZE - 1)) / WORKGROUP_SIZE;
                    pass.dispatch_workgroups(wg_x, wg_y, 1);
                }

                encoder.copy_buffer_to_buffer(
                    output_buffer,
                    0,
                    readback_buffer,
                    0,
                    tile_pixel_bytes,
                );
                self.queue.submit(Some(encoder.finish()));

                let buffer_slice = readback_buffer.slice(0..tile_pixel_bytes);
                let (tx, rx) = mpsc::channel();
                buffer_slice.map_async(wgpu::MapMode::Read, move |res| {
                    let _ = tx.send(res);
                });

                self.device.poll(wgpu::Maintain::Wait);

                let map_status: Result<(), String> = match rx.recv() {
                    Ok(Ok(())) => Ok(()),
                    Ok(Err(e)) => Err(format!("wgpu map_async failed: {e:?}")),
                    Err(e) => Err(format!("wgpu map_async channel failed: {e}")),
                };

                if map_status.is_ok() {
                    let mapped = buffer_slice.get_mapped_range();
                    let mapped_u32: &[u32] = bytemuck::cast_slice(&mapped);
                    for row in 0..copy_h {
                        let src_row_start = row * tile_step;
                        let dst_y = tile_y_usize + row;
                        let dst_row_start = dst_y * canvas_width_usize + tile_x_usize;
                        result[dst_row_start..(dst_row_start + copy_w)]
                            .copy_from_slice(&mapped_u32[src_row_start..(src_row_start + copy_w)]);
                    }
                    drop(mapped);
                    readback_buffer.unmap();
                }

                if let Some(err) = device_pop_scope(&self.device) {
                    return Err(format!("wgpu validation error during composite: {err}"));
                }
                if let Some(err) = device_pop_scope(&self.device) {
                    return Err(format!("wgpu out-of-memory error during composite: {err}"));
                }

                map_status?;
            }
        }

        Ok(result)
    }

    fn ensure_resources(
        &mut self,
        width: u32,
        height: u32,
        layer_capacity: usize,
    ) -> Result<(), String> {
        if layer_capacity == 0 || layer_capacity > MAX_LAYERS {
            return Err(format!(
                "invalid layer_capacity {layer_capacity} (max {MAX_LAYERS})"
            ));
        }

        let dims_changed = self.cached_width != width || self.cached_height != height;
        let target_layer_capacity = if dims_changed {
            layer_capacity
        } else {
            self.cached_layer_capacity.max(layer_capacity)
        };

        let needs_input_resize = dims_changed
            || self.input_buffer.is_none()
            || target_layer_capacity > self.cached_layer_capacity;
        let needs_output_resize =
            dims_changed || self.output_buffer.is_none() || self.readback_buffer.is_none();
        let needs_bind_group =
            self.bind_group.is_none() || needs_input_resize || needs_output_resize;

        if !needs_bind_group {
            return Ok(());
        }

        let pixel_count: u64 = (width as u64)
            .checked_mul(height as u64)
            .ok_or_else(|| "pixel_count overflow".to_string())?;
        let pixel_bytes: u64 = pixel_count
            .checked_mul(std::mem::size_of::<u32>() as u64)
            .ok_or_else(|| "pixel_bytes overflow".to_string())?;
        let input_bytes: u64 = pixel_bytes
            .checked_mul(target_layer_capacity as u64)
            .ok_or_else(|| "input buffer size overflow".to_string())?;

        let max_buffer_size = self.device.limits().max_buffer_size;
        let max_storage_binding_size = self.device.limits().max_storage_buffer_binding_size as u64;
        if needs_input_resize {
            if input_bytes > max_buffer_size {
                return Err(format!(
                    "input buffer too large: {input_bytes} bytes (device max {max_buffer_size})"
                ));
            }
            if input_bytes > max_storage_binding_size {
                return Err(format!(
                    "input binding too large: {input_bytes} bytes (storage binding max {max_storage_binding_size})"
                ));
            }
        }
        if needs_output_resize {
            if pixel_bytes > max_buffer_size {
                return Err(format!(
                    "output buffer too large: {pixel_bytes} bytes (device max {max_buffer_size})"
                ));
            }
            if pixel_bytes > max_storage_binding_size {
                return Err(format!(
                    "output binding too large: {pixel_bytes} bytes (storage binding max {max_storage_binding_size})"
                ));
            }
        }

        device_push_scopes(&self.device);

        if dims_changed {
            self.layer_uploaded = [false; MAX_LAYERS];
        }

        let input_buffer = if needs_input_resize {
            Some(self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("GpuCompositor input pixels"),
                size: input_bytes,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            }))
        } else {
            None
        };
        let output_buffer = if needs_output_resize {
            Some(self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("GpuCompositor output pixels"),
                size: pixel_bytes,
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            }))
        } else {
            None
        };
        let readback_buffer = if needs_output_resize {
            Some(self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("GpuCompositor readback buffer"),
                size: pixel_bytes,
                usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            }))
        } else {
            None
        };

        let input_buffer_ref = input_buffer
            .as_ref()
            .unwrap_or_else(|| self.input_buffer.as_ref().unwrap());
        let output_buffer_ref = output_buffer
            .as_ref()
            .unwrap_or_else(|| self.output_buffer.as_ref().unwrap());

        if needs_input_resize && !dims_changed {
            if let (Some(old), Some(new)) = (self.input_buffer.as_ref(), input_buffer.as_ref()) {
                let old_pixel_count: u64 = (self.cached_width as u64)
                    .checked_mul(self.cached_height as u64)
                    .ok_or_else(|| "old_pixel_count overflow".to_string())?;
                let old_pixel_bytes: u64 = old_pixel_count
                    .checked_mul(std::mem::size_of::<u32>() as u64)
                    .ok_or_else(|| "old_pixel_bytes overflow".to_string())?;
                let old_input_bytes: u64 = old_pixel_bytes
                    .checked_mul(self.cached_layer_capacity as u64)
                    .ok_or_else(|| "old_input_bytes overflow".to_string())?;

                if old_input_bytes > 0 {
                    let mut encoder =
                        self.device
                            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                                label: Some("GpuCompositor resize input copy encoder"),
                            });
                    encoder.copy_buffer_to_buffer(old, 0, new, 0, old_input_bytes);
                    self.queue.submit(Some(encoder.finish()));
                }
            }
        }

        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("GpuCompositor bind group"),
            layout: &self.bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: input_buffer_ref.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: output_buffer_ref.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: self.uniform_buffer.as_entire_binding(),
                },
            ],
        });

        if let Some(err) = device_pop_scope(&self.device) {
            return Err(format!("wgpu validation error during buffer alloc: {err}"));
        }
        if let Some(err) = device_pop_scope(&self.device) {
            return Err(format!(
                "wgpu out-of-memory error during buffer alloc: {err}"
            ));
        }

        self.cached_width = width;
        self.cached_height = height;
        self.cached_layer_capacity = target_layer_capacity;
        if let Some(input_buffer) = input_buffer {
            self.input_buffer = Some(input_buffer);
        }
        if let Some(output_buffer) = output_buffer {
            self.output_buffer = Some(output_buffer);
        }
        if let Some(readback_buffer) = readback_buffer {
            self.readback_buffer = Some(readback_buffer);
        }
        self.bind_group = Some(bind_group);

        Ok(())
    }
}

fn clamp_unit_f32(value: f32) -> f32 {
    if !value.is_finite() {
        return 0.0;
    }
    value.clamp(0.0, 1.0)
}

fn device_push_scopes(device: &wgpu::Device) {
    device.push_error_scope(wgpu::ErrorFilter::OutOfMemory);
    device.push_error_scope(wgpu::ErrorFilter::Validation);
}

fn device_pop_scope(device: &wgpu::Device) -> Option<wgpu::Error> {
    pollster::block_on(device.pop_error_scope())
}
