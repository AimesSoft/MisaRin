use std::ops::Deref;

use bevy::render::renderer::RenderDevice;

#[derive(Clone)]
pub(crate) struct SharedRenderDevice {
    render_device: RenderDevice,
}

impl SharedRenderDevice {
    pub(crate) fn new(device: wgpu::Device) -> Self {
        Self {
            render_device: RenderDevice::from(device),
        }
    }

    pub(crate) fn bevy_render_device(&self) -> RenderDevice {
        self.render_device.clone()
    }
}

impl Deref for SharedRenderDevice {
    type Target = wgpu::Device;

    fn deref(&self) -> &Self::Target {
        self.render_device.wgpu_device()
    }
}

impl AsRef<wgpu::Device> for SharedRenderDevice {
    fn as_ref(&self) -> &wgpu::Device {
        self.render_device.wgpu_device()
    }
}
