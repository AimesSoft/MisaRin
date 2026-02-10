import 'dart:async';
import 'dart:typed_data';

class CanvasEngineFfi {
  CanvasEngineFfi._();

  static final CanvasEngineFfi instance = CanvasEngineFfi._();

  bool get isSupported => false;

  Stream<int> get frameRequests => const Stream<int>.empty();

  void pushPointsPacked({
    required int handle,
    required Uint8List bytes,
    required int pointCount,
  }) {}

  void requestFrame({required int handle}) {}

  Future<int> getInputQueueLen(int handle) async => 0;

  Future<bool> pollFrameReady({required int handle}) async => false;

  Future<Uint8List?> readPresent({
    required int handle,
    required int width,
    required int height,
  }) async {
    return null;
  }

  void setBrush({
    required int handle,
    required int colorArgb,
    required double baseRadius,
    bool usePressure = true,
    bool erase = false,
    int antialiasLevel = 1,
    int brushShape = 0,
    bool randomRotation = false,
    int rotationSeed = 0,
    double spacing = 0.15,
    double hardness = 0.8,
    double flow = 1.0,
    double scatter = 0.0,
    double rotationJitter = 1.0,
    bool snapToPixel = false,
    bool hollow = false,
    double hollowRatio = 0.0,
    bool hollowEraseOccludedParts = false,
    double streamlineStrength = 0.0,
  }) {}

  void beginSpray({required int handle}) {}

  void drawSpray({
    required int handle,
    required Float32List points,
    required int pointCount,
    required int colorArgb,
    int brushShape = 0,
    bool erase = false,
    int antialiasLevel = 1,
    double softness = 0.0,
    bool accumulate = true,
  }) {}

  void endSpray({required int handle}) {}

  Future<bool> applyFilter({
    required int handle,
    required int layerIndex,
    required int filterType,
    double param0 = 0.0,
    double param1 = 0.0,
    double param2 = 0.0,
    double param3 = 0.0,
  }) async {
    return false;
  }

  Future<bool> applyAntialias({
    required int handle,
    required int layerIndex,
    required int level,
  }) async {
    return false;
  }

  void setActiveLayer({required int handle, required int layerIndex}) {}

  void setLayerOpacity({
    required int handle,
    required int layerIndex,
    required double opacity,
  }) {}

  void setLayerVisible({
    required int handle,
    required int layerIndex,
    required bool visible,
  }) {}

  void setLayerClippingMask({
    required int handle,
    required int layerIndex,
    required bool clippingMask,
  }) {}

  void setLayerBlendMode({
    required int handle,
    required int layerIndex,
    required int blendModeIndex,
  }) {}

  void reorderLayer({
    required int handle,
    required int fromIndex,
    required int toIndex,
  }) {}

  void setViewFlags({
    required int handle,
    required bool mirror,
    required bool blackWhite,
  }) {}

  void clearLayer({required int handle, required int layerIndex}) {}

  void fillLayer({
    required int handle,
    required int layerIndex,
    required int colorArgb,
  }) {}

  Future<bool> bucketFill({
    required int handle,
    required int layerIndex,
    required int startX,
    required int startY,
    required int colorArgb,
    bool contiguous = true,
    bool sampleAllLayers = false,
    int tolerance = 0,
    int fillGap = 0,
    int antialiasLevel = 0,
    Uint32List? swallowColors,
    Uint8List? selectionMask,
  }) async {
    return false;
  }

  Future<Uint8List?> magicWandMask({
    required int handle,
    required int layerIndex,
    required int startX,
    required int startY,
    required int maskLength,
    bool sampleAllLayers = true,
    int tolerance = 0,
    Uint8List? selectionMask,
  }) async {
    return null;
  }

  Future<Uint32List?> readLayer({
    required int handle,
    required int layerIndex,
    required int width,
    required int height,
  }) async {
    return null;
  }

  Future<Uint8List?> readLayerPreview({
    required int handle,
    required int layerIndex,
    required int width,
    required int height,
  }) async {
    return null;
  }

  Future<bool> writeLayer({
    required int handle,
    required int layerIndex,
    required Uint32List pixels,
    bool recordUndo = true,
  }) async {
    return false;
  }

  Future<bool> translateLayer({
    required int handle,
    required int layerIndex,
    required int deltaX,
    required int deltaY,
  }) async {
    return false;
  }

  Future<bool> setLayerTransformPreview({
    required int handle,
    required int layerIndex,
    required Float32List matrix,
    bool enabled = true,
    bool bilinear = true,
  }) async {
    return false;
  }

  Future<bool> applyLayerTransform({
    required int handle,
    required int layerIndex,
    required Float32List matrix,
    bool bilinear = true,
  }) async {
    return false;
  }

  Future<Int32List?> getLayerBounds({
    required int handle,
    required int layerIndex,
  }) async {
    return null;
  }

  void setSelectionMask({required int handle, Uint8List? selectionMask}) {}

  void resetCanvas({required int handle, required int backgroundColorArgb}) {}

  void undo({required int handle}) {}

  void redo({required int handle}) {}
}
