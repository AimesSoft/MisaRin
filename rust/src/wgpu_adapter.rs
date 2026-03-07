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

    let is_compute = |adapter: &wgpu::Adapter| {
        adapter.limits().max_compute_workgroups_per_dimension > 0
    };

    let is_vulkan_compute = |adapter: &wgpu::Adapter| {
        adapter.get_info().backend == wgpu::Backend::Vulkan && is_compute(adapter)
    };

    if let Some(adapter) = take(&is_vulkan_compute) {
        if debug::level() >= LogLevel::Info {
            let info = adapter.get_info();
            debug::log(
                LogLevel::Info,
                format_args!("Selected Vulkan adapter: {}", info.name),
            );
        }
        return Some(adapter);
    }

    if let Some(adapter) = take(&is_compute) {
        if debug::level() >= LogLevel::Info {
            let info = adapter.get_info();
            debug::log(
                LogLevel::Info,
                format_args!(
                    "Selected compute-capable adapter: backend={:?} name='{}'",
                    info.backend, info.name
                ),
            );
        }
        return Some(adapter);
    }

    None
}
