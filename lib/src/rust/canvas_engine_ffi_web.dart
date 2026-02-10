import 'dart:async';

import 'api/canvas_engine.dart' as rust_canvas_engine;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:misa_rin/app/utils/web_log.dart';

class CanvasEngineFfi {
  CanvasEngineFfi._();

  static final CanvasEngineFfi instance = CanvasEngineFfi._();

  final bool isSupported = true;
  int _readPresentMismatchCount = 0;
  bool _readPresentLoggedOk = false;
  int _pushPointsLogCount = 0;
  int _frameRequestLogCount = 0;
  final StreamController<int> _frameRequestController =
      StreamController<int>.broadcast();

  Stream<int> get frameRequests => _frameRequestController.stream;

  PlatformInt64 _toPlatformInt64(int value) => PlatformInt64Util.from(value);

  int _fromPlatformInt64(PlatformInt64 value) => value.toInt();

  void pushPointsPacked({
    required int handle,
    required Uint8List bytes,
    required int pointCount,
  }) {
    if (!isSupported || handle == 0 || pointCount <= 0) {
      return;
    }
    if (_pushPointsLogCount < 5) {
      _pushPointsLogCount += 1;
      reportWebLog(
        'pushPointsPacked call handle=$handle count=$pointCount bytes=${bytes.length}',
      );
    }
    final int requiredBytes = pointCount * 32;
    if (bytes.length < requiredBytes) {
      throw RangeError.range(bytes.length, requiredBytes, null, 'bytes.length');
    }
    unawaited(
      rust_canvas_engine
          .canvasEnginePushPointsPacked(
            handle: _toPlatformInt64(handle),
            bytes: bytes,
            pointCount: BigInt.from(pointCount),
          )
          .catchError((Object error, StackTrace stackTrace) {
            reportWebLog(
              'canvasEnginePushPointsPacked error $error\n$stackTrace',
            );
          }),
    );
  }

  void requestFrame({required int handle}) {
    if (!isSupported || handle == 0) {
      return;
    }
    if (_frameRequestLogCount < 5) {
      _frameRequestLogCount += 1;
      reportWebLog('webFrameRequest handle=$handle');
    }
    _frameRequestController.add(handle);
  }

  Future<int> getInputQueueLen(int handle) async {
    if (!isSupported || handle == 0) {
      return 0;
    }
    final PlatformInt64 len = await rust_canvas_engine
        .canvasEngineGetInputQueueLen(handle: _toPlatformInt64(handle));
    return _fromPlatformInt64(len);
  }

  Future<bool> pollFrameReady({required int handle}) async {
    if (!isSupported || handle == 0) {
      return false;
    }
    return await rust_canvas_engine.canvasEnginePollFrameReady(
      handle: _toPlatformInt64(handle),
    );
  }

  Future<Uint8List?> readPresent({
    required int handle,
    required int width,
    required int height,
  }) async {
    if (!isSupported || handle == 0 || width <= 0 || height <= 0) {
      return null;
    }
    final Uint8List? bytes = await rust_canvas_engine.canvasEngineReadPresent(
      handle: _toPlatformInt64(handle),
    );
    final int expected = width * height * 4;
    if (bytes == null) {
      return null;
    }
    if (bytes.length != expected) {
      if (_readPresentMismatchCount < 3) {
        _readPresentMismatchCount += 1;
        reportWebLog(
          'canvasEngineReadPresent size mismatch bytes=${bytes.length} expected=$expected '
          'size=${width}x$height',
        );
      }
      return null;
    }
    if (!_readPresentLoggedOk) {
      _readPresentLoggedOk = true;
      reportWebLog(
        'canvasEngineReadPresent ok bytes=${bytes.length} size=${width}x$height',
      );
    }
    return bytes;
  }

  void setActiveLayer({required int handle, required int layerIndex}) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineSetActiveLayer(
        handle: _toPlatformInt64(handle),
        layerIndex: layerIndex,
      ),
    );
  }

  void setLayerOpacity({
    required int handle,
    required int layerIndex,
    required double opacity,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineSetLayerOpacity(
        handle: _toPlatformInt64(handle),
        layerIndex: layerIndex,
        opacity: opacity,
      ),
    );
  }

  void setLayerVisible({
    required int handle,
    required int layerIndex,
    required bool visible,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineSetLayerVisible(
        handle: _toPlatformInt64(handle),
        layerIndex: layerIndex,
        visible: visible,
      ),
    );
  }

  void setLayerClippingMask({
    required int handle,
    required int layerIndex,
    required bool clippingMask,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineSetLayerClippingMask(
        handle: _toPlatformInt64(handle),
        layerIndex: layerIndex,
        clippingMask: clippingMask,
      ),
    );
  }

  void setLayerBlendMode({
    required int handle,
    required int layerIndex,
    required int blendModeIndex,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineSetLayerBlendMode(
        handle: _toPlatformInt64(handle),
        layerIndex: layerIndex,
        blendModeIndex: blendModeIndex,
      ),
    );
  }

  void reorderLayer({
    required int handle,
    required int fromIndex,
    required int toIndex,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    if (fromIndex < 0 || toIndex < 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineReorderLayer(
        handle: _toPlatformInt64(handle),
        fromIndex: fromIndex,
        toIndex: toIndex,
      ),
    );
  }

  void setViewFlags({
    required int handle,
    required bool mirror,
    required bool blackWhite,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    int flags = 0;
    if (mirror) {
      flags |= 1;
    }
    if (blackWhite) {
      flags |= 2;
    }
    unawaited(
      rust_canvas_engine.canvasEngineSetViewFlags(
        handle: _toPlatformInt64(handle),
        viewFlags: flags,
      ),
    );
  }

  void clearLayer({required int handle, required int layerIndex}) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineClearLayer(
        handle: _toPlatformInt64(handle),
        layerIndex: layerIndex,
      ),
    );
  }

  void fillLayer({
    required int handle,
    required int layerIndex,
    required int colorArgb,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineFillLayer(
        handle: _toPlatformInt64(handle),
        layerIndex: layerIndex,
        colorArgb: colorArgb,
      ),
    );
  }

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
    if (!isSupported || handle == 0) {
      return false;
    }
    final int clampedTolerance = tolerance.clamp(0, 255);
    final int clampedFillGap = fillGap.clamp(0, 64);
    final int clampedAntialias = antialiasLevel.clamp(0, 9);
    return await rust_canvas_engine.canvasEngineBucketFill(
      handle: _toPlatformInt64(handle),
      layerIndex: layerIndex,
      startX: startX,
      startY: startY,
      colorArgb: colorArgb,
      contiguous: contiguous,
      sampleAllLayers: sampleAllLayers,
      tolerance: clampedTolerance,
      fillGap: clampedFillGap,
      antialiasLevel: clampedAntialias,
      swallowColors: swallowColors?.toList() ?? const <int>[],
      selectionMask: selectionMask,
    );
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
    if (!isSupported || handle == 0) {
      return null;
    }
    if (maskLength <= 0) {
      return null;
    }
    return await rust_canvas_engine.canvasEngineMagicWandMask(
      handle: _toPlatformInt64(handle),
      layerIndex: layerIndex,
      startX: startX,
      startY: startY,
      sampleAllLayers: sampleAllLayers,
      tolerance: tolerance,
      selectionMask: selectionMask,
    );
  }

  Future<Uint32List?> readLayer({
    required int handle,
    required int layerIndex,
    required int width,
    required int height,
  }) async {
    if (!isSupported || handle == 0 || width <= 0 || height <= 0) {
      return null;
    }
    final Uint32List? pixels = await rust_canvas_engine.canvasEngineReadLayer(
      handle: _toPlatformInt64(handle),
      layerIndex: layerIndex,
    );
    if (pixels == null || pixels.length != width * height) {
      return null;
    }
    return pixels;
  }

  Future<Uint8List?> readLayerPreview({
    required int handle,
    required int layerIndex,
    required int width,
    required int height,
  }) async {
    if (!isSupported || handle == 0 || width <= 0 || height <= 0) {
      return null;
    }
    final Uint8List? pixels = await rust_canvas_engine
        .canvasEngineReadLayerPreview(
      handle: _toPlatformInt64(handle),
      layerIndex: layerIndex,
      width: width,
      height: height,
    );
    if (pixels == null || pixels.length != width * height * 4) {
      return null;
    }
    return pixels;
  }

  Future<bool> writeLayer({
    required int handle,
    required int layerIndex,
    required Uint32List pixels,
    bool recordUndo = true,
  }) async {
    if (!isSupported || handle == 0 || pixels.isEmpty) {
      return false;
    }
    return await rust_canvas_engine.canvasEngineWriteLayer(
      handle: _toPlatformInt64(handle),
      layerIndex: layerIndex,
      pixels: pixels.toList(),
      recordUndo: recordUndo,
    );
  }

  Future<bool> translateLayer({
    required int handle,
    required int layerIndex,
    required int deltaX,
    required int deltaY,
  }) async {
    if (!isSupported || handle == 0) {
      return false;
    }
    return await rust_canvas_engine.canvasEngineTranslateLayer(
      handle: _toPlatformInt64(handle),
      layerIndex: layerIndex,
      deltaX: deltaX,
      deltaY: deltaY,
    );
  }

  Future<bool> setLayerTransformPreview({
    required int handle,
    required int layerIndex,
    required Float32List matrix,
    bool enabled = true,
    bool bilinear = true,
  }) async {
    if (!isSupported || handle == 0 || matrix.length < 16) {
      return false;
    }
    return await rust_canvas_engine.canvasEngineSetLayerTransformPreview(
      handle: _toPlatformInt64(handle),
      layerIndex: layerIndex,
      matrix: matrix,
      enabled: enabled,
      bilinear: bilinear,
    );
  }

  Future<bool> applyLayerTransform({
    required int handle,
    required int layerIndex,
    required Float32List matrix,
    bool bilinear = true,
  }) async {
    if (!isSupported || handle == 0 || matrix.length < 16) {
      return false;
    }
    return await rust_canvas_engine.canvasEngineApplyLayerTransform(
      handle: _toPlatformInt64(handle),
      layerIndex: layerIndex,
      matrix: matrix,
      bilinear: bilinear,
    );
  }

  Future<Int32List?> getLayerBounds({
    required int handle,
    required int layerIndex,
  }) async {
    if (!isSupported || handle == 0) {
      return null;
    }
    final List<int>? bounds = await rust_canvas_engine
        .canvasEngineGetLayerBounds(
          handle: _toPlatformInt64(handle),
          layerIndex: layerIndex,
        );
    if (bounds == null || bounds.length < 4) {
      return null;
    }
    return Int32List.fromList(bounds.take(4).toList());
  }

  void setSelectionMask({required int handle, Uint8List? selectionMask}) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineSetSelectionMask(
        handle: _toPlatformInt64(handle),
        selectionMask: selectionMask,
      ),
    );
  }

  void resetCanvas({required int handle, required int backgroundColorArgb}) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineResetCanvas(
        handle: _toPlatformInt64(handle),
        backgroundColorArgb: backgroundColorArgb,
      ),
    );
  }

  void undo({required int handle}) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineUndo(handle: _toPlatformInt64(handle)),
    );
  }

  void redo({required int handle}) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineRedo(handle: _toPlatformInt64(handle)),
    );
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
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    double radius = baseRadius;
    if (!radius.isFinite) {
      radius = 0.0;
    }
    if (radius < 0.0) {
      radius = 0.0;
    }
    final int shape = brushShape < 0 ? 0 : brushShape;
    final int seed = rotationSeed & 0xffffffff;
    double spacingValue = spacing;
    if (!spacingValue.isFinite) {
      spacingValue = 0.15;
    }
    spacingValue = spacingValue.clamp(0.02, 2.5);
    double hardnessValue = hardness;
    if (!hardnessValue.isFinite) {
      hardnessValue = 0.8;
    }
    hardnessValue = hardnessValue.clamp(0.0, 1.0);
    double flowValue = flow;
    if (!flowValue.isFinite) {
      flowValue = 1.0;
    }
    flowValue = flowValue.clamp(0.0, 1.0);
    double scatterValue = scatter;
    if (!scatterValue.isFinite) {
      scatterValue = 0.0;
    }
    scatterValue = scatterValue.clamp(0.0, 1.0);
    double rotationValue = rotationJitter;
    if (!rotationValue.isFinite) {
      rotationValue = 1.0;
    }
    rotationValue = rotationValue.clamp(0.0, 1.0);
    double ratio = hollowRatio;
    if (!ratio.isFinite) {
      ratio = 0.0;
    }
    ratio = ratio.clamp(0.0, 1.0);
    double streamline = streamlineStrength;
    if (!streamline.isFinite) {
      streamline = 0.0;
    }
    streamline = streamline.clamp(0.0, 1.0);
    unawaited(
      rust_canvas_engine
          .canvasEngineSetBrush(
            handle: _toPlatformInt64(handle),
            colorArgb: colorArgb,
            baseRadius: radius,
            usePressure: usePressure,
            erase: erase,
            antialiasLevel: antialiasLevel.clamp(0, 9),
            brushShape: shape,
            randomRotation: randomRotation,
            rotationSeed: seed,
            spacing: spacingValue,
            hardness: hardnessValue,
            flow: flowValue,
            scatter: scatterValue,
            rotationJitter: rotationValue,
            snapToPixel: snapToPixel,
            hollowEnabled: hollow,
            hollowRatio: ratio,
            hollowEraseOccluded: hollowEraseOccludedParts,
            streamlineStrength: streamline,
          )
          .catchError((Object error, StackTrace stackTrace) {
            reportWebLog('canvasEngineSetBrush error $error\n$stackTrace');
          }),
    );
  }

  void beginSpray({required int handle}) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineSprayBegin(
        handle: _toPlatformInt64(handle),
      ),
    );
  }

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
  }) {
    if (!isSupported || handle == 0 || pointCount <= 0) {
      return;
    }
    final int floatCount = pointCount * 4;
    if (points.length < floatCount) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineSprayDraw(
        handle: _toPlatformInt64(handle),
        points: points,
        pointCount: BigInt.from(pointCount),
        colorArgb: colorArgb,
        brushShape: brushShape,
        erase: erase,
        antialiasLevel: antialiasLevel.clamp(0, 9),
        softness: softness.clamp(0.0, 1.0),
        accumulate: accumulate,
      ),
    );
  }

  void endSpray({required int handle}) {
    if (!isSupported || handle == 0) {
      return;
    }
    unawaited(
      rust_canvas_engine.canvasEngineSprayEnd(handle: _toPlatformInt64(handle)),
    );
  }

  Future<bool> applyFilter({
    required int handle,
    required int layerIndex,
    required int filterType,
    double param0 = 0.0,
    double param1 = 0.0,
    double param2 = 0.0,
    double param3 = 0.0,
  }) async {
    if (!isSupported || handle == 0) {
      return false;
    }
    return await rust_canvas_engine.canvasEngineApplyFilter(
      handle: _toPlatformInt64(handle),
      layerIndex: layerIndex,
      filterType: filterType,
      param0: param0,
      param1: param1,
      param2: param2,
      param3: param3,
    );
  }

  Future<bool> applyAntialias({
    required int handle,
    required int layerIndex,
    required int level,
  }) async {
    if (!isSupported || handle == 0) {
      return false;
    }
    return await rust_canvas_engine.canvasEngineApplyAntialias(
      handle: _toPlatformInt64(handle),
      layerIndex: layerIndex,
      level: level,
    );
  }
}
