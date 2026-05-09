import 'dart:typed_data';

import '../src/rust/api/gpu_composite.dart' as rust_gpu;

typedef RustWgpuLayerData = rust_gpu.GpuLayerData;

void rustWgpuCompositorInit() => rust_gpu.gpuCompositorInit();

void rustWgpuCompositorDispose() => rust_gpu.gpuCompositorDispose();

Future<Uint32List> rustWgpuCompositeLayers({
  required List<RustWgpuLayerData> layers,
  required int width,
  required int height,
}) {
  return rust_gpu.gpuCompositeLayers(
    layers: layers,
    width: width,
    height: height,
  );
}
