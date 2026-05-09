enum CanvasBackend { rustWgpu }

enum CanvasFilterType {
  hueSaturation,
  brightnessContrast,
  blackWhite,
  binarize,
  gaussianBlur,
  leakRemoval,
  lineNarrow,
  fillExpand,
  scanPaperDrawing,
  invert,
}

class CanvasBackendCapabilities {
  const CanvasBackendCapabilities({
    required this.isSupported,
    required this.isReady,
    this.supportedFilters = const <CanvasFilterType>{},
    this.supportsLayerTransformPreview = false,
    this.supportsLayerTranslate = false,
    this.supportsAntialias = false,
    this.supportsStrokeStream = false,
    this.supportsInputQueue = false,
    this.supportsSpray = false,
  });

  final bool isSupported;
  final bool isReady;
  final Set<CanvasFilterType> supportedFilters;
  final bool supportsLayerTransformPreview;
  final bool supportsLayerTranslate;
  final bool supportsAntialias;
  final bool supportsStrokeStream;
  final bool supportsInputQueue;
  final bool supportsSpray;

  bool get isAvailable => isSupported && isReady;

  bool supportsFilter(CanvasFilterType type) => supportedFilters.contains(type);
}

abstract class CanvasBackendInterface {
  CanvasBackendCapabilities get capabilities;
}

extension CanvasBackendId on CanvasBackend {
  int get id => index;

  static CanvasBackend fromId(int id) {
    return CanvasBackend.rustWgpu;
  }
}
