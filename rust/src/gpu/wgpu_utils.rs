#[cfg(target_os = "android")]
use crate::gpu::debug::{self, LogLevel};

pub fn write_buffer(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    buffer: &wgpu::Buffer,
    offset: u64,
    data: &[u8],
) {
    if data.is_empty() {
        return;
    }

    #[cfg(target_os = "android")]
    {
        if offset % 4 != 0 || data.len() % 4 != 0 {
            debug::log(
                LogLevel::Warn,
                format_args!(
                    "wgpu write_buffer fallback to queue.write_buffer (unaligned) offset={} len={}",
                    offset,
                    data.len()
                ),
            );
            queue.write_buffer(buffer, offset, data);
            return;
        }

        let staging = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("misa-rin staging write buffer"),
            size: data.len() as u64,
            usage: wgpu::BufferUsages::MAP_WRITE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: true,
        });
        {
            let mut mapped = staging.slice(..).get_mapped_range_mut();
            mapped[..data.len()].copy_from_slice(data);
        }
        staging.unmap();

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("misa-rin staging write encoder"),
        });
        encoder.copy_buffer_to_buffer(&staging, 0, buffer, offset, data.len() as u64);
        queue.submit(Some(encoder.finish()));
        // Synchronize on Android to avoid driver crashes with async staging uploads.
        device.poll(wgpu::PollType::wait_indefinitely());
        return;
    }

    #[cfg(not(target_os = "android"))]
    {
        queue.write_buffer(buffer, offset, data);
    }
}

pub fn write_texture(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    texture: &wgpu::Texture,
    origin: wgpu::Origin3d,
    extent: wgpu::Extent3d,
    bytes_per_row: u32,
    rows_per_image: u32,
    data: &[u8],
) {
    if data.is_empty() || extent.width == 0 || extent.height == 0 {
        return;
    }

    #[cfg(target_os = "android")]
    {
        if bytes_per_row % wgpu::COPY_BYTES_PER_ROW_ALIGNMENT != 0 {
            debug::log(
                LogLevel::Warn,
                format_args!(
                    "wgpu write_texture fallback to queue.write_texture (unaligned) bpr={} rows={}",
                    bytes_per_row, rows_per_image
                ),
            );
            queue.write_texture(
                wgpu::TexelCopyTextureInfo {
                    texture,
                    mip_level: 0,
                    origin,
                    aspect: wgpu::TextureAspect::All,
                },
                data,
                wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(bytes_per_row),
                    rows_per_image: Some(rows_per_image),
                },
                extent,
            );
            return;
        }

        let staging = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("misa-rin staging write texture"),
            size: data.len() as u64,
            usage: wgpu::BufferUsages::MAP_WRITE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: true,
        });
        {
            let mut mapped = staging.slice(..).get_mapped_range_mut();
            mapped[..data.len()].copy_from_slice(data);
        }
        staging.unmap();

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("misa-rin staging texture encoder"),
        });
        encoder.copy_buffer_to_texture(
            wgpu::TexelCopyBufferInfo {
                buffer: &staging,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(bytes_per_row),
                    rows_per_image: Some(rows_per_image),
                },
            },
            wgpu::TexelCopyTextureInfo {
                texture,
                mip_level: 0,
                origin,
                aspect: wgpu::TextureAspect::All,
            },
            extent,
        );
        queue.submit(Some(encoder.finish()));
        // Synchronize on Android to avoid driver crashes with async staging uploads.
        device.poll(wgpu::PollType::wait_indefinitely());
        return;
    }

    #[cfg(not(target_os = "android"))]
    {
        queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture,
                mip_level: 0,
                origin,
                aspect: wgpu::TextureAspect::All,
            },
            data,
            wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(bytes_per_row),
                rows_per_image: Some(rows_per_image),
            },
            extent,
        );
    }
}
