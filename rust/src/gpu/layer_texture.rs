use std::collections::HashMap;
use std::sync::mpsc;
use std::sync::Arc;
use std::time::Instant;

use wgpu::Queue;

use crate::gpu::debug::{self, LogLevel};
use crate::gpu::layer_format::LAYER_TEXTURE_FORMAT;
use crate::gpu::shared_device::SharedRenderDevice;
use crate::gpu::wgpu_utils;

const BYTES_PER_PIXEL: u32 = 4;
const COPY_BYTES_PER_ROW_ALIGNMENT: u32 = 256;

pub struct LayerTextureManager {
    device: SharedRenderDevice,
    queue: Arc<Queue>,
    textures: HashMap<String, wgpu::Texture>,
    width: u32,
    height: u32,
}

impl LayerTextureManager {
    pub fn new(device: SharedRenderDevice, queue: Arc<Queue>) -> Self {
        Self {
            device,
            queue,
            textures: HashMap::new(),
            width: 0,
            height: 0,
        }
    }

    pub fn width(&self) -> u32 {
        self.width
    }

    pub fn height(&self) -> u32 {
        self.height
    }

    pub fn upload_layer(
        &mut self,
        layer_id: &str,
        pixels: &[u32],
        width: u32,
        height: u32,
    ) -> Result<(), String> {
        if width == 0 || height == 0 {
            return Err("upload_layer: width/height must be > 0".to_string());
        }

        let expected_len: usize = (width as usize)
            .checked_mul(height as usize)
            .ok_or_else(|| "upload_layer: pixel_count overflow".to_string())?;
        if pixels.len() != expected_len {
            return Err(format!(
                "upload_layer: pixel len mismatch: got {}, expected {}",
                pixels.len(),
                expected_len
            ));
        }

        if self.width != width || self.height != height {
            debug::log(
                LogLevel::Info,
                format_args!(
                    "LayerTextureManager canvas resize {}x{} -> {}x{}, clearing textures.",
                    self.width, self.height, width, height
                ),
            );
            self.textures.clear();
            self.width = width;
            self.height = height;
        }

        self.ensure_layer_texture(layer_id)?;

        let texture = self
            .textures
            .get(layer_id)
            .ok_or_else(|| "upload_layer: texture missing after ensure".to_string())?;

        let bytes_per_row_unpadded: u32 = width
            .checked_mul(BYTES_PER_PIXEL)
            .ok_or_else(|| "upload_layer: bytes_per_row overflow".to_string())?;
        let bytes_per_row_padded =
            align_up(bytes_per_row_unpadded, COPY_BYTES_PER_ROW_ALIGNMENT)
                .ok_or_else(|| "upload_layer: bytes_per_row padded overflow".to_string())?;

        #[cfg(target_os = "android")]
        const MAX_CHUNK_BYTES: usize = 512 * 1024;
        #[cfg(not(target_os = "android"))]
        const MAX_CHUNK_BYTES: usize = 4 * 1024 * 1024;

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
                let src = &pixels[src_offset..src_offset + width as usize];
                let dst = &mut data[dst_offset..dst_offset + width as usize];
                dst.copy_from_slice(src);
            }
            wgpu_utils::write_texture(
                self.device.as_ref(),
                self.queue.as_ref(),
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

    pub fn download_layer(&self, layer_id: &str) -> Result<Vec<u32>, String> {
        let verbose = debug::level() >= LogLevel::Verbose;
        let t0 = if verbose { Some(Instant::now()) } else { None };

        let texture = self
            .textures
            .get(layer_id)
            .ok_or_else(|| format!("download_layer: layer '{layer_id}' not found"))?;
        if self.width == 0 || self.height == 0 {
            return Ok(Vec::new());
        }

        let bytes_per_row_unpadded: u32 = self
            .width
            .checked_mul(BYTES_PER_PIXEL)
            .ok_or_else(|| "download_layer: bytes_per_row overflow".to_string())?;
        let bytes_per_row_padded =
            align_up(bytes_per_row_unpadded, COPY_BYTES_PER_ROW_ALIGNMENT)
                .ok_or_else(|| "download_layer: bytes_per_row padded overflow".to_string())?;
        let readback_size: u64 = (bytes_per_row_padded as u64)
            .checked_mul(self.height as u64)
            .ok_or_else(|| "download_layer: readback_size overflow".to_string())?;

        device_push_scopes(self.device.as_ref());

        let readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("LayerTextureManager readback buffer"),
            size: readback_size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("LayerTextureManager download encoder"),
            });

        encoder.copy_texture_to_buffer(
            wgpu::ImageCopyTexture {
                texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::ImageCopyBuffer {
                buffer: &readback,
                layout: wgpu::ImageDataLayout {
                    offset: 0,
                    bytes_per_row: Some(bytes_per_row_padded),
                    rows_per_image: Some(self.height),
                },
            },
            wgpu::Extent3d {
                width: self.width,
                height: self.height,
                depth_or_array_layers: 1,
            },
        );

        self.queue.submit(Some(encoder.finish()));

        let buffer_slice = readback.slice(0..readback_size);
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
            result = Some(unpack_u32_rows_without_padding(
                &mapped,
                self.width,
                self.height,
                bytes_per_row_padded,
            )?);
            drop(mapped);
            readback.unmap();
        }

        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu validation error during layer download: {err}"
            ));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu out-of-memory error during layer download: {err}"
            ));
        }

        map_status?;
        if let Some(t0) = t0 {
            debug::log(
                LogLevel::Verbose,
                format_args!(
                    "download_layer layer='{layer_id}' size={}x{} bytes_per_row_padded={bytes_per_row_padded} readback_size={readback_size} in {:?}.",
                    self.width,
                    self.height,
                    t0.elapsed()
                ),
            );
        }
        Ok(result.unwrap_or_default())
    }

    pub fn download_layer_region(
        &self,
        layer_id: &str,
        left: u32,
        top: u32,
        width: u32,
        height: u32,
    ) -> Result<Vec<u32>, String> {
        let verbose = debug::level() >= LogLevel::Verbose;
        let t0 = if verbose { Some(Instant::now()) } else { None };

        let texture = self
            .textures
            .get(layer_id)
            .ok_or_else(|| format!("download_layer_region: layer '{layer_id}' not found"))?;
        if width == 0 || height == 0 {
            return Ok(Vec::new());
        }
        if self.width == 0 || self.height == 0 {
            return Ok(Vec::new());
        }
        let right = left.saturating_add(width);
        let bottom = top.saturating_add(height);
        if right > self.width || bottom > self.height {
            let msg = format!(
                "download_layer_region: region out of bounds: ({left},{top}) {width}x{height} on {}x{}",
                self.width, self.height
            );
            debug::log(LogLevel::Warn, format_args!("{msg}"));
            return Err(msg);
        }

        let bytes_per_row_unpadded: u32 = width
            .checked_mul(BYTES_PER_PIXEL)
            .ok_or_else(|| "download_layer_region: bytes_per_row overflow".to_string())?;
        let bytes_per_row_padded = align_up(bytes_per_row_unpadded, COPY_BYTES_PER_ROW_ALIGNMENT)
            .ok_or_else(|| {
            "download_layer_region: bytes_per_row padded overflow".to_string()
        })?;
        let readback_size: u64 = (bytes_per_row_padded as u64)
            .checked_mul(height as u64)
            .ok_or_else(|| "download_layer_region: readback_size overflow".to_string())?;

        device_push_scopes(self.device.as_ref());

        let readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("LayerTextureManager readback region buffer"),
            size: readback_size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("LayerTextureManager download region encoder"),
            });

        encoder.copy_texture_to_buffer(
            wgpu::ImageCopyTexture {
                texture,
                mip_level: 0,
                origin: wgpu::Origin3d {
                    x: left,
                    y: top,
                    z: 0,
                },
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::ImageCopyBuffer {
                buffer: &readback,
                layout: wgpu::ImageDataLayout {
                    offset: 0,
                    bytes_per_row: Some(bytes_per_row_padded),
                    rows_per_image: Some(height),
                },
            },
            wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
        );

        self.queue.submit(Some(encoder.finish()));

        let buffer_slice = readback.slice(0..readback_size);
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
            result = Some(unpack_u32_rows_without_padding(
                &mapped,
                width,
                height,
                bytes_per_row_padded,
            )?);
            drop(mapped);
            readback.unmap();
        }

        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu validation error during layer region download: {err}"
            ));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu out-of-memory error during layer region download: {err}"
            ));
        }

        map_status?;
        if let Some(t0) = t0 {
            let bytes_per_row_unpadded = width.saturating_mul(BYTES_PER_PIXEL);
            let padding = bytes_per_row_padded.saturating_sub(bytes_per_row_unpadded);
            debug::log(
                LogLevel::Verbose,
                format_args!(
                    "download_layer_region layer='{layer_id}' region=({left},{top}) {width}x{height} bytes_per_row={bytes_per_row_unpadded} padded={bytes_per_row_padded} pad_bytes={padding} readback_size={readback_size} in {:?}.",
                    t0.elapsed()
                ),
            );
        }
        Ok(result.unwrap_or_default())
    }

    pub fn get_texture(&self, layer_id: &str) -> Option<&wgpu::Texture> {
        self.textures.get(layer_id)
    }

    pub fn remove_layer(&mut self, layer_id: &str) {
        self.textures.remove(layer_id);
    }

    fn ensure_layer_texture(&mut self, layer_id: &str) -> Result<(), String> {
        if self.textures.contains_key(layer_id) {
            return Ok(());
        }
        if self.width == 0 || self.height == 0 {
            return Err("ensure_layer_texture: manager size not set".to_string());
        }

        let max_dim = self.device.limits().max_texture_dimension_2d;
        if self.width > max_dim || self.height > max_dim {
            return Err(format!(
                "layer texture size {}x{} exceeds device max {}",
                self.width, self.height, max_dim
            ));
        }

        device_push_scopes(self.device.as_ref());

        let texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("LayerTextureManager layer texture"),
            size: wgpu::Extent3d {
                width: self.width,
                height: self.height,
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

        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu validation error during layer texture alloc: {err}"
            ));
        }
        if let Some(err) = device_pop_scope(self.device.as_ref()) {
            return Err(format!(
                "wgpu out-of-memory error during layer texture alloc: {err}"
            ));
        }

        self.textures.insert(layer_id.to_string(), texture);
        Ok(())
    }
}

fn align_up(value: u32, alignment: u32) -> Option<u32> {
    if alignment == 0 {
        return None;
    }
    let rem = value % alignment;
    if rem == 0 {
        return Some(value);
    }
    value.checked_add(alignment - rem)
}

fn pack_u32_rows_with_padding(
    pixels: &[u32],
    width: u32,
    height: u32,
    bytes_per_row_padded: u32,
) -> Result<Vec<u8>, String> {
    let bytes_per_row_unpadded: usize = (width as usize)
        .checked_mul(BYTES_PER_PIXEL as usize)
        .ok_or_else(|| "pack_u32_rows_with_padding: bytes_per_row overflow".to_string())?;
    let bytes_per_row_padded_usize = bytes_per_row_padded as usize;
    let total_bytes: usize = bytes_per_row_padded_usize
        .checked_mul(height as usize)
        .ok_or_else(|| "pack_u32_rows_with_padding: total_bytes overflow".to_string())?;

    let mut out = vec![0u8; total_bytes];
    let width_usize = width as usize;
    for y in 0..height as usize {
        let src_row_start = y * width_usize;
        let src_row = &pixels[src_row_start..(src_row_start + width_usize)];
        let src_bytes: &[u8] = bytemuck::cast_slice(src_row);
        let dst_offset = y * bytes_per_row_padded_usize;
        out[dst_offset..(dst_offset + bytes_per_row_unpadded)].copy_from_slice(src_bytes);
    }
    Ok(out)
}

fn unpack_u32_rows_without_padding(
    data: &[u8],
    width: u32,
    height: u32,
    bytes_per_row_padded: u32,
) -> Result<Vec<u32>, String> {
    let bytes_per_row_unpadded: usize = (width as usize)
        .checked_mul(BYTES_PER_PIXEL as usize)
        .ok_or_else(|| "unpack_u32_rows_without_padding: bytes_per_row overflow".to_string())?;
    let bytes_per_row_padded_usize = bytes_per_row_padded as usize;

    let pixel_count: usize = (width as usize)
        .checked_mul(height as usize)
        .ok_or_else(|| "unpack_u32_rows_without_padding: pixel_count overflow".to_string())?;
    let mut out: Vec<u32> = vec![0u32; pixel_count];

    let width_usize = width as usize;
    for y in 0..height as usize {
        let src_offset = y * bytes_per_row_padded_usize;
        let row_bytes = &data[src_offset..(src_offset + bytes_per_row_unpadded)];
        let row_u32: &[u32] = bytemuck::cast_slice(row_bytes);
        let dst_row_start = y * width_usize;
        out[dst_row_start..(dst_row_start + width_usize)].copy_from_slice(row_u32);
    }

    Ok(out)
}

fn device_push_scopes(device: &wgpu::Device) {
    device.push_error_scope(wgpu::ErrorFilter::OutOfMemory);
    device.push_error_scope(wgpu::ErrorFilter::Validation);
}

fn device_pop_scope(device: &wgpu::Device) -> Option<wgpu::Error> {
    pollster::block_on(device.pop_error_scope())
}
