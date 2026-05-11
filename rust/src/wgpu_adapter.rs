use crate::gpu::debug::{self, LogLevel};

pub(crate) fn select_compute_adapter(
    instance: &wgpu::Instance,
    backends: wgpu::Backends,
) -> Option<wgpu::Adapter> {
    let mut adapters: Vec<wgpu::Adapter> = instance.enumerate_adapters(backends);
    if adapters.is_empty() {
        return None;
    }

    let mut take = |predicate: &dyn Fn(&wgpu::Adapter) -> bool| {
        if let Some(pos) = adapters.iter().position(predicate) {
            Some(adapters.remove(pos))
        } else {
            None
        }
    };

    let is_compute =
        |adapter: &wgpu::Adapter| adapter.limits().max_compute_workgroups_per_dimension > 0;

    let is_software = |adapter: &wgpu::Adapter| {
        let info = adapter.get_info();
        if matches!(info.device_type, wgpu::DeviceType::Cpu) {
            return true;
        }
        let name = info.name.to_ascii_lowercase();
        name.contains("swiftshader") || name.contains("software")
    };

    let is_vulkan_compute = |adapter: &wgpu::Adapter| {
        adapter.get_info().backend == wgpu::Backend::Vulkan && is_compute(adapter)
    };

    let is_gl_compute = |adapter: &wgpu::Adapter| {
        adapter.get_info().backend == wgpu::Backend::Gl && is_compute(adapter)
    };

    let log_selected = |adapter: &wgpu::Adapter, label: &str| {
        if debug::level() >= LogLevel::Info {
            let info = adapter.get_info();
            debug::log(
                LogLevel::Info,
                format_args!(
                    "Selected {label} adapter: backend={:?} device_type={:?} name='{}'",
                    info.backend, info.device_type, info.name
                ),
            );
        }
    };

    if let Some(adapter) = take(&|adapter| is_vulkan_compute(adapter) && !is_software(adapter)) {
        log_selected(&adapter, "Vulkan compute");
        return Some(adapter);
    }

    if let Some(adapter) = take(&|adapter| is_gl_compute(adapter) && !is_software(adapter)) {
        log_selected(&adapter, "GL compute");
        return Some(adapter);
    }

    if let Some(adapter) = take(&is_gl_compute) {
        log_selected(&adapter, "GL compute");
        return Some(adapter);
    }

    if let Some(adapter) = take(&is_vulkan_compute) {
        if is_software(&adapter) {
            log_selected(&adapter, "software Vulkan compute (fallback)");
        } else {
            log_selected(&adapter, "Vulkan compute");
        }
        return Some(adapter);
    }

    if let Some(adapter) = take(&is_compute) {
        log_selected(&adapter, "compute-capable");
        return Some(adapter);
    }

    None
}
