use crate::gpu::layer_format::LAYER_TEXTURE_FORMAT;

pub(crate) struct LayerTextures {
    texture: wgpu::Texture,
    array_view: wgpu::TextureView,
    layer_views: Vec<wgpu::TextureView>,
    width: u32,
    height: u32,
    capacity: usize,
}

impl LayerTextures {
    pub(crate) fn new(
        device: &wgpu::Device,
        width: u32,
        height: u32,
        capacity: usize,
    ) -> Result<Self, String> {
        let capacity = capacity.max(1);
        let max_layers = device.limits().max_texture_array_layers as usize;
        if capacity > max_layers {
            return Err(format!(
                "layer capacity {capacity} exceeds device max {max_layers}"
            ));
        }
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("misa-rin layer array (Rgba8Unorm)"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: capacity as u32,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: LAYER_TEXTURE_FORMAT,
            usage: wgpu::TextureUsages::TEXTURE_BINDING
                | wgpu::TextureUsages::COPY_DST
                | wgpu::TextureUsages::COPY_SRC
                | wgpu::TextureUsages::STORAGE_BINDING,
            view_formats: &[],
        });
        let array_view = texture.create_view(&wgpu::TextureViewDescriptor {
            dimension: Some(wgpu::TextureViewDimension::D2Array),
            base_array_layer: 0,
            array_layer_count: Some(capacity as u32),
            ..Default::default()
        });
        let mut layer_views = Vec::with_capacity(capacity);
        for idx in 0..capacity {
            let view = texture.create_view(&wgpu::TextureViewDescriptor {
                dimension: Some(wgpu::TextureViewDimension::D2),
                base_array_layer: idx as u32,
                array_layer_count: Some(1),
                ..Default::default()
            });
            layer_views.push(view);
        }

        Ok(Self {
            texture,
            array_view,
            layer_views,
            width,
            height,
            capacity,
        })
    }

    pub(crate) fn capacity(&self) -> usize {
        self.capacity
    }

    pub(crate) fn texture(&self) -> &wgpu::Texture {
        &self.texture
    }

    pub(crate) fn array_view(&self) -> &wgpu::TextureView {
        &self.array_view
    }

    pub(crate) fn layer_view(&self, index: usize) -> Option<&wgpu::TextureView> {
        self.layer_views.get(index)
    }

    pub(crate) fn ensure_capacity(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        required: usize,
    ) -> Result<Option<usize>, String> {
        if required <= self.capacity {
            return Ok(None);
        }

        let max_layers = device.limits().max_texture_array_layers as usize;
        let mut next_capacity = self.capacity.max(1);
        while next_capacity < required {
            next_capacity = next_capacity.saturating_mul(2).max(required);
        }
        if next_capacity > max_layers {
            return Err(format!(
                "layer capacity {next_capacity} exceeds device max {max_layers}"
            ));
        }

        let old_capacity = self.capacity;
        let new_texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("misa-rin layer array (Rgba8Unorm)"),
            size: wgpu::Extent3d {
                width: self.width,
                height: self.height,
                depth_or_array_layers: next_capacity as u32,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: LAYER_TEXTURE_FORMAT,
            usage: wgpu::TextureUsages::TEXTURE_BINDING
                | wgpu::TextureUsages::COPY_DST
                | wgpu::TextureUsages::COPY_SRC
                | wgpu::TextureUsages::STORAGE_BINDING,
            view_formats: &[],
        });

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("misa-rin layer array resize encoder"),
        });
        encoder.copy_texture_to_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &self.texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::TexelCopyTextureInfo {
                texture: &new_texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::Extent3d {
                width: self.width,
                height: self.height,
                depth_or_array_layers: old_capacity as u32,
            },
        );
        queue.submit(Some(encoder.finish()));

        let array_view = new_texture.create_view(&wgpu::TextureViewDescriptor {
            dimension: Some(wgpu::TextureViewDimension::D2Array),
            base_array_layer: 0,
            array_layer_count: Some(next_capacity as u32),
            ..Default::default()
        });
        let mut layer_views = Vec::with_capacity(next_capacity);
        for idx in 0..next_capacity {
            let view = new_texture.create_view(&wgpu::TextureViewDescriptor {
                dimension: Some(wgpu::TextureViewDimension::D2),
                base_array_layer: idx as u32,
                array_layer_count: Some(1),
                ..Default::default()
            });
            layer_views.push(view);
        }

        self.texture = new_texture;
        self.array_view = array_view;
        self.layer_views = layer_views;
        self.capacity = next_capacity;

        Ok(Some(old_capacity))
    }
}
