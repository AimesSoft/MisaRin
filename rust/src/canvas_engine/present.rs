use std::borrow::Cow;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
#[cfg(target_os = "windows")]
use std::sync::atomic::AtomicU64;
#[cfg(target_os = "windows")]
use std::time::Instant;
#[cfg(target_os = "android")]
use std::{ffi::c_void, ptr::NonNull};

use crate::gpu::debug::{self, LogLevel};

#[cfg(any(target_os = "macos", target_os = "ios"))]
use metal::foreign_types::ForeignType;
#[cfg(any(target_os = "macos", target_os = "ios"))]
use metal::MTLTextureType;
#[cfg(any(target_os = "macos", target_os = "ios"))]
use wgpu_hal::{api::Metal, CopyExtent};
#[cfg(target_os = "windows")]
use wgpu_hal::api::Dx12;
#[cfg(target_os = "windows")]
use wgpu_hal::dx12;
#[cfg(target_os = "windows")]
use winapi::shared::{dxgiformat, dxgitype};
#[cfg(target_os = "windows")]
use winapi::Interface as _;
#[cfg(target_os = "windows")]
use winapi::um::{d3d12 as d3d12_ty, handleapi::CloseHandle, winnt};
#[cfg(target_os = "android")]
use {
    ndk_sys::ANativeWindow,
    raw_window_handle::{AndroidDisplayHandle, AndroidNdkWindowHandle, RawDisplayHandle, RawWindowHandle},
    wgpu::SurfaceTargetUnsafe,
};

#[cfg(target_os = "android")]
#[link(name = "android")]
extern "C" {
    fn ANativeWindow_release(window: *mut ANativeWindow);
}

pub(crate) enum PresentTarget {
    Texture(PresentTextureTarget),
    #[cfg(target_os = "android")]
    Surface(PresentSurfaceTarget),
}

pub(crate) struct PresentTextureTarget {
    render_texture: wgpu::Texture,
    pub(crate) render_view: wgpu::TextureView,
    shared_texture: Option<wgpu::Texture>,
    pub(crate) width: u32,
    pub(crate) height: u32,
    _bytes_per_row: u32,
    #[cfg(target_os = "windows")]
    dxgi_handle: Option<winnt::HANDLE>,
}

impl PresentTarget {
    pub(crate) fn format(&self) -> wgpu::TextureFormat {
        match self {
            PresentTarget::Texture(_) => wgpu::TextureFormat::Bgra8Unorm,
            #[cfg(target_os = "android")]
            PresentTarget::Surface(surface) => surface.format(),
        }
    }

    pub(crate) fn width(&self) -> u32 {
        match self {
            PresentTarget::Texture(target) => target.width,
            #[cfg(target_os = "android")]
            PresentTarget::Surface(surface) => surface.width(),
        }
    }

    pub(crate) fn height(&self) -> u32 {
        match self {
            PresentTarget::Texture(target) => target.height,
            #[cfg(target_os = "android")]
            PresentTarget::Surface(surface) => surface.height(),
        }
    }

    pub(crate) fn as_texture(&self) -> Option<&PresentTextureTarget> {
        match self {
            PresentTarget::Texture(target) => Some(target),
            #[cfg(target_os = "android")]
            PresentTarget::Surface(_) => None,
        }
    }

    pub(crate) fn as_texture_mut(&mut self) -> Option<&mut PresentTextureTarget> {
        match self {
            PresentTarget::Texture(target) => Some(target),
            #[cfg(target_os = "android")]
            PresentTarget::Surface(_) => None,
        }
    }

    #[cfg(target_os = "android")]
    pub(crate) fn as_surface_mut(&mut self) -> Option<&mut PresentSurfaceTarget> {
        match self {
            PresentTarget::Surface(surface) => Some(surface),
            _ => None,
        }
    }
}

impl PresentTextureTarget {
    pub(crate) fn render_texture(&self) -> &wgpu::Texture {
        &self.render_texture
    }

    pub(crate) fn render_view(&self) -> &wgpu::TextureView {
        &self.render_view
    }

    pub(crate) fn shared_texture(&self) -> Option<&wgpu::Texture> {
        self.shared_texture.as_ref()
    }

    pub(crate) fn texture(&self) -> &wgpu::Texture {
        &self.render_texture
    }

    #[cfg(target_os = "windows")]
    pub(crate) fn dxgi_handle(&self) -> Option<usize> {
        self.dxgi_handle.map(|handle| handle as usize)
    }

    #[cfg(target_os = "windows")]
    pub(crate) fn take_dxgi_handle(&mut self) -> Option<usize> {
        self.dxgi_handle.take().map(|handle| handle as usize)
    }
}

#[cfg(target_os = "windows")]
impl Drop for PresentTextureTarget {
    fn drop(&mut self) {
        if let Some(handle) = self.dxgi_handle.take() {
            unsafe {
                CloseHandle(handle);
            }
        }
    }
}

#[cfg(target_os = "android")]
pub(crate) struct PresentSurfaceTarget {
    surface: wgpu::Surface<'static>,
    config: wgpu::SurfaceConfiguration,
    window: AndroidNativeWindow,
}

#[cfg(target_os = "android")]
impl PresentSurfaceTarget {
    pub(crate) fn format(&self) -> wgpu::TextureFormat {
        self.config.format
    }

    pub(crate) fn width(&self) -> u32 {
        self.config.width
    }

    pub(crate) fn height(&self) -> u32 {
        self.config.height
    }

    pub(crate) fn surface(&self) -> &wgpu::Surface<'static> {
        &self.surface
    }

    pub(crate) fn configure(&mut self, device: &wgpu::Device) {
        self.surface.configure(device, &self.config);
    }
}

#[cfg(target_os = "android")]
struct AndroidNativeWindow {
    ptr: NonNull<ANativeWindow>,
}

#[cfg(target_os = "android")]
impl AndroidNativeWindow {
    unsafe fn from_raw(ptr: *mut ANativeWindow) -> Option<Self> {
        NonNull::new(ptr).map(|ptr| Self { ptr })
    }

    fn as_ptr(&self) -> *mut ANativeWindow {
        self.ptr.as_ptr()
    }
}

#[cfg(target_os = "android")]
unsafe impl Send for AndroidNativeWindow {}

#[cfg(target_os = "android")]
unsafe impl Sync for AndroidNativeWindow {}

#[cfg(target_os = "android")]
impl Drop for AndroidNativeWindow {
    fn drop(&mut self) {
        unsafe {
            ANativeWindow_release(self.ptr.as_ptr());
        }
    }
}

pub(crate) struct PresentRenderer {
    format: wgpu::TextureFormat,
    pipeline: wgpu::RenderPipeline,
    bind_group_layout: wgpu::BindGroupLayout,
}

#[cfg(target_os = "windows")]
const PRESENT_GPU_LOG_EVERY: u64 = 120;
#[cfg(target_os = "windows")]
static PRESENT_GPU_ACCUM_US: AtomicU64 = AtomicU64::new(0);
#[cfg(target_os = "windows")]
static PRESENT_GPU_MAX_US: AtomicU64 = AtomicU64::new(0);
#[cfg(target_os = "windows")]
static PRESENT_GPU_COUNT: AtomicU64 = AtomicU64::new(0);

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub(crate) struct PresentCompositeHeader {
    layer_count: u32,
    view_flags: u32,
    transform_layer: u32,
    transform_flags: u32,
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct PresentLayerParams {
    opacity: f32,
    visible: f32,
    clipping_mask: f32,
    blend_mode: u32,
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub(crate) struct PresentTransformConfig {
    matrix: [f32; 16],
}

pub(crate) fn write_present_config(
    queue: &wgpu::Queue,
    header_buffer: &wgpu::Buffer,
    params_buffer: &wgpu::Buffer,
    layer_count: usize,
    view_flags: u32,
    transform_layer: u32,
    transform_flags: u32,
    layer_opacity: &[f32],
    layer_visible: &[bool],
    layer_clipping_mask: &[bool],
    layer_blend_mode: &[u32],
) {
    let header = PresentCompositeHeader {
        layer_count: layer_count as u32,
        view_flags,
        transform_layer,
        transform_flags,
    };
    queue.write_buffer(header_buffer, 0, bytemuck::bytes_of(&header));

    if layer_count == 0 {
        return;
    }

    let mut params: Vec<PresentLayerParams> = Vec::with_capacity(layer_count);
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
        let blend_mode = layer_blend_mode.get(i).copied().unwrap_or(0);
        params.push(PresentLayerParams {
            opacity,
            visible,
            clipping_mask,
            blend_mode,
        });
    }
    queue.write_buffer(params_buffer, 0, bytemuck::cast_slice(&params));
}

pub(crate) fn write_present_transform(
    queue: &wgpu::Queue,
    buffer: &wgpu::Buffer,
    matrix: [f32; 16],
) {
    let config = PresentTransformConfig { matrix };
    queue.write_buffer(buffer, 0, bytemuck::bytes_of(&config));
}

pub(crate) fn create_present_transform_buffer(device: &wgpu::Device) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("misa-rin present transform config"),
        size: std::mem::size_of::<PresentTransformConfig>() as u64,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    })
}

pub(crate) fn create_present_params_buffer(
    device: &wgpu::Device,
    capacity: usize,
) -> Result<wgpu::Buffer, String> {
    let size = capacity
        .checked_mul(std::mem::size_of::<PresentLayerParams>())
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
        label: Some("misa-rin present layer params"),
        size: size as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    }))
}

impl PresentRenderer {
    pub(crate) fn new(device: &wgpu::Device, format: wgpu::TextureFormat) -> Self {
        let shader_source = include_str!("../canvas_present_rgba8.wgsl");
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("misa-rin present renderer shader"),
            source: wgpu::ShaderSource::Wgsl(Cow::Borrowed(shader_source)),
        });

        let layer_sample_type = wgpu::TextureSampleType::Float { filterable: false };
        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("misa-rin present renderer bgl"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: layer_sample_type,
                        view_dimension: wgpu::TextureViewDimension::D2Array,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: wgpu::BufferSize::new(std::mem::size_of::<
                            PresentCompositeHeader,
                        >() as u64),
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 3,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: wgpu::BufferSize::new(std::mem::size_of::<
                            PresentTransformConfig,
                        >() as u64),
                    },
                    count: None,
                },
            ],
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("misa-rin present renderer pipeline layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("misa-rin present renderer pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: "vs_main",
                buffers: &[],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: "fs_main",
                targets: &[Some(wgpu::ColorTargetState {
                    format,
                    blend: None,
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
        });

        Self {
            format,
            pipeline,
            bind_group_layout,
        }
    }

    pub(crate) fn create_bind_group(
        &self,
        device: &wgpu::Device,
        layer_view: &wgpu::TextureView,
        config_buffer: &wgpu::Buffer,
        params_buffer: &wgpu::Buffer,
        transform_buffer: &wgpu::Buffer,
    ) -> wgpu::BindGroup {
        device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("misa-rin present renderer bind group"),
            layout: &self.bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(layer_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: config_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: params_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: transform_buffer.as_entire_binding(),
                },
            ],
        })
    }

    pub(crate) fn render_present(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        bind_group: &wgpu::BindGroup,
        target: &PresentTextureTarget,
        frame_ready: Arc<AtomicBool>,
        frame_in_flight: Arc<AtomicBool>,
    ) {
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("misa-rin present renderer encoder"),
        });
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("misa-rin present renderer pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: target.render_view(),
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, bind_group, &[]);
            pass.draw(0..3, 0..1);
        }

        copy_render_to_shared(&mut encoder, target);
        queue.submit(Some(encoder.finish()));
        signal_frame_ready(queue, frame_ready, frame_in_flight);
    }

    pub(crate) fn render_base(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        bind_group: &wgpu::BindGroup,
        present_view: &wgpu::TextureView,
    ) {
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("misa-rin present renderer encoder"),
        });
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("misa-rin present renderer pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: present_view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, bind_group, &[]);
            pass.draw(0..3, 0..1);
        }
        queue.submit(Some(encoder.finish()));
    }
}

pub(crate) fn copy_render_to_shared(
    encoder: &mut wgpu::CommandEncoder,
    target: &PresentTextureTarget,
) {
    let Some(shared_texture) = target.shared_texture() else {
        return;
    };
    if target.width == 0 || target.height == 0 {
        return;
    }
    encoder.copy_texture_to_texture(
        wgpu::ImageCopyTexture {
            texture: target.render_texture(),
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::ImageCopyTexture {
            texture: shared_texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::Extent3d {
            width: target.width,
            height: target.height,
            depth_or_array_layers: 1,
        },
    );
}

pub(crate) fn signal_frame_ready(
    queue: &wgpu::Queue,
    frame_ready: Arc<AtomicBool>,
    frame_in_flight: Arc<AtomicBool>,
) {
    debug::log(LogLevel::Verbose, format_args!("frame_ready queued"));
    #[cfg(target_os = "windows")]
    let submitted_at = Instant::now();
    // Mark in-flight; only flip to ready once GPU work completes.
    frame_ready.store(false, Ordering::Release);
    frame_in_flight.store(true, Ordering::Release);
    let frame_ready_done = Arc::clone(&frame_ready);
    let frame_in_flight_done = Arc::clone(&frame_in_flight);
    queue.on_submitted_work_done(move || {
        frame_in_flight_done.store(false, Ordering::Release);
        frame_ready_done.store(true, Ordering::Release);
        debug::log(LogLevel::Verbose, format_args!("frame_ready done"));
        #[cfg(target_os = "windows")]
        {
            let elapsed_us = submitted_at.elapsed().as_micros() as u64;
            PRESENT_GPU_ACCUM_US.fetch_add(elapsed_us, Ordering::Relaxed);
            let mut prev = PRESENT_GPU_MAX_US.load(Ordering::Relaxed);
            while elapsed_us > prev {
                match PRESENT_GPU_MAX_US.compare_exchange(
                    prev,
                    elapsed_us,
                    Ordering::Relaxed,
                    Ordering::Relaxed,
                ) {
                    Ok(_) => break,
                    Err(next) => prev = next,
                }
            }
            let count = PRESENT_GPU_COUNT.fetch_add(1, Ordering::Relaxed) + 1;
            if count % PRESENT_GPU_LOG_EVERY == 0 {
                let sum = PRESENT_GPU_ACCUM_US.swap(0, Ordering::Relaxed);
                let max = PRESENT_GPU_MAX_US.swap(0, Ordering::Relaxed);
                let avg_ms = (sum as f64) / (PRESENT_GPU_LOG_EVERY as f64) / 1000.0;
                let max_ms = (max as f64) / 1000.0;
                debug::log(
                    LogLevel::Info,
                    format_args!(
                        "[perf] present gpu done avg={avg_ms:.2}ms max={max_ms:.2}ms"
                    ),
                );
            }
        }
    });
}

pub(crate) fn attach_present_texture(
    device: &wgpu::Device,
    mtl_texture_ptr: usize,
    width: u32,
    height: u32,
    bytes_per_row: u32,
) -> Option<PresentTarget> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        let raw_ptr = mtl_texture_ptr as *mut metal::MTLTexture;
        if raw_ptr.is_null() {
            return None;
        }

        // Use ForeignTypeRef logic to avoid taking ownership if possible,
        // or ensure we clone it properly.
        // metal::Texture::from_ptr wraps it.
        // In metal-rs 0.24+, from_ptr calls objc_retain.
        // So dropping it will call release. This is correct if we want to share ownership.
        let raw_texture = unsafe { metal::Texture::from_ptr(raw_ptr) };
        let hal_texture = unsafe {
            wgpu_hal::metal::Device::texture_from_raw(
                raw_texture,
                wgpu::TextureFormat::Bgra8Unorm,
                MTLTextureType::D2,
                1,
                1,
                CopyExtent {
                    width,
                    height,
                    depth: 1,
                },
            )
        };

        let desc = wgpu::TextureDescriptor {
            label: Some("misa-rin present texture (external MTLTexture)"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Bgra8Unorm,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            view_formats: &[],
        };

        let texture = unsafe { device.create_texture_from_hal::<Metal>(hal_texture, &desc) };
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());

        return Some(PresentTarget::Texture(PresentTextureTarget {
            render_texture: texture,
            render_view: view,
            shared_texture: None,
            width,
            height,
            _bytes_per_row: bytes_per_row,
            #[cfg(target_os = "windows")]
            dxgi_handle: None,
        }));
    }
    #[cfg(target_os = "windows")]
    {
        let _ = (device, mtl_texture_ptr, width, height, bytes_per_row);
        None
    }
    #[cfg(all(not(any(target_os = "macos", target_os = "ios")), not(target_os = "windows")))]
    {
        let _ = (mtl_texture_ptr, bytes_per_row);
        if width == 0 || height == 0 {
            return None;
        }
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("misa-rin present texture (internal)"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Bgra8Unorm,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT
                | wgpu::TextureUsages::TEXTURE_BINDING
                | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        let bytes_per_row = width.saturating_mul(4);
        return Some(PresentTarget::Texture(PresentTextureTarget {
            render_texture: texture,
            render_view: view,
            shared_texture: None,
            width,
            height,
            _bytes_per_row: bytes_per_row,
            #[cfg(target_os = "windows")]
            dxgi_handle: None,
        }));
    }
}

#[cfg(target_os = "android")]
pub(crate) fn attach_present_surface(
    instance: &wgpu::Instance,
    adapter: &wgpu::Adapter,
    device: &wgpu::Device,
    native_window_ptr: *mut c_void,
    width: u32,
    height: u32,
) -> Result<PresentTarget, String> {
    if native_window_ptr.is_null() || width == 0 || height == 0 {
        return Err("present surface requires valid window and size".to_string());
    }

    let window = unsafe {
        AndroidNativeWindow::from_raw(native_window_ptr as *mut ANativeWindow)
            .ok_or_else(|| "present surface invalid ANativeWindow".to_string())?
    };

    let raw_window_handle = RawWindowHandle::AndroidNdk(AndroidNdkWindowHandle::new(
        // Safety: ANativeWindow pointer must be valid and non-null.
        NonNull::new(window.as_ptr() as *mut c_void)
            .ok_or_else(|| "present surface invalid window pointer".to_string())?,
    ));
    let raw_display_handle = RawDisplayHandle::Android(AndroidDisplayHandle::new());

    let surface = unsafe {
        instance
            .create_surface_unsafe(SurfaceTargetUnsafe::RawHandle {
                raw_display_handle,
                raw_window_handle,
            })
            .map_err(|err| format!("wgpu: create_surface failed: {err:?}"))?
    };

    let caps = surface.get_capabilities(adapter);
    let format = if caps
        .formats
        .iter()
        .any(|fmt| *fmt == wgpu::TextureFormat::Bgra8Unorm)
    {
        wgpu::TextureFormat::Bgra8Unorm
    } else if caps
        .formats
        .iter()
        .any(|fmt| *fmt == wgpu::TextureFormat::Rgba8Unorm)
    {
        wgpu::TextureFormat::Rgba8Unorm
    } else {
        *caps
            .formats
            .first()
            .ok_or_else(|| "wgpu: surface has no supported formats".to_string())?
    };

    let alpha_mode = caps
        .alpha_modes
        .first()
        .copied()
        .unwrap_or(wgpu::CompositeAlphaMode::Opaque);

    let config = wgpu::SurfaceConfiguration {
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
        format,
        width,
        height,
        present_mode: wgpu::PresentMode::Fifo,
        alpha_mode,
        desired_maximum_frame_latency: 2,
        view_formats: vec![],
    };

    surface.configure(device, &config);

    Ok(PresentTarget::Surface(PresentSurfaceTarget {
        surface,
        config,
        window,
    }))
}

#[cfg(target_os = "windows")]
pub(crate) fn create_dxgi_shared_present_target(
    device: &wgpu::Device,
    width: u32,
    height: u32,
) -> Result<PresentTarget, String> {
    if width == 0 || height == 0 {
        return Err("present target size must be > 0".to_string());
    }

    let (resource, shared_handle) = unsafe {
        device
            .as_hal::<Dx12, _, _>(|hal_device| {
                let Some(hal_device) = hal_device else {
                    return Err("wgpu: dx12 backend unavailable".to_string());
                };

                let raw_device = hal_device.raw_device();
                let mut resource = d3d12::ComPtr::<d3d12_ty::ID3D12Resource>::null();

                let heap_props = d3d12_ty::D3D12_HEAP_PROPERTIES {
                    Type: d3d12_ty::D3D12_HEAP_TYPE_DEFAULT,
                    CPUPageProperty: d3d12_ty::D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
                    MemoryPoolPreference: d3d12_ty::D3D12_MEMORY_POOL_UNKNOWN,
                    CreationNodeMask: 0,
                    VisibleNodeMask: 0,
                };

                let desc = d3d12_ty::D3D12_RESOURCE_DESC {
                    Dimension: d3d12_ty::D3D12_RESOURCE_DIMENSION_TEXTURE2D,
                    Alignment: 0,
                    Width: width as u64,
                    Height: height,
                    DepthOrArraySize: 1,
                    MipLevels: 1,
                    Format: dxgiformat::DXGI_FORMAT_B8G8R8A8_UNORM,
                    SampleDesc: dxgitype::DXGI_SAMPLE_DESC { Count: 1, Quality: 0 },
                    Layout: d3d12_ty::D3D12_TEXTURE_LAYOUT_UNKNOWN,
                    Flags: d3d12_ty::D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET
                        | d3d12_ty::D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS,
                };

                let hr = raw_device.CreateCommittedResource(
                    &heap_props,
                    d3d12_ty::D3D12_HEAP_FLAG_SHARED,
                    &desc,
                    d3d12_ty::D3D12_RESOURCE_STATE_COMMON,
                    std::ptr::null(),
                    &d3d12_ty::ID3D12Resource::uuidof(),
                    resource.mut_void(),
                );
                if hr < 0 || resource.is_null() {
                    return Err(format!(
                        "dx12 CreateCommittedResource failed: 0x{hr:08X}"
                    ));
                }

                let mut handle: winnt::HANDLE = std::ptr::null_mut();
                let hr = raw_device.CreateSharedHandle(
                    resource.as_mut_ptr() as *mut _,
                    std::ptr::null(),
                    winnt::GENERIC_ALL,
                    std::ptr::null(),
                    &mut handle,
                );
                if hr < 0 || handle.is_null() {
                    return Err(format!("dx12 CreateSharedHandle failed: 0x{hr:08X}"));
                }

                Ok((resource, handle))
            })
            .ok_or_else(|| "wgpu: dx12 backend unavailable".to_string())?
    }?;

    let render_texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("misa-rin present texture (internal render)"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Bgra8Unorm,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT
            | wgpu::TextureUsages::TEXTURE_BINDING
            | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let render_view = render_texture.create_view(&wgpu::TextureViewDescriptor::default());

    let hal_texture = unsafe {
        dx12::Device::texture_from_raw(
            resource,
            wgpu::TextureFormat::Bgra8Unorm,
            wgpu::TextureDimension::D2,
            wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            1,
            1,
        )
    };

    let desc = wgpu::TextureDescriptor {
        label: Some("misa-rin present texture (dxgi shared)"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Bgra8Unorm,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    };

    let shared_texture = unsafe { device.create_texture_from_hal::<Dx12>(hal_texture, &desc) };
    let bytes_per_row = width.saturating_mul(4);

    Ok(PresentTarget::Texture(PresentTextureTarget {
        render_texture,
        render_view,
        shared_texture: Some(shared_texture),
        width,
        height,
        _bytes_per_row: bytes_per_row,
        dxgi_handle: Some(shared_handle),
    }))
}
