import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

import '../src/rust/api/selection_path.dart' as rust_selection_path;
import '../src/rust/canvas_engine_ffi.dart' as rust_wgpu_engine;
import 'canvas_backend.dart';
import 'canvas_backend_state.dart';

class CanvasEngineFfi {
  CanvasEngineFfi._();

  static final CanvasEngineFfi instance = CanvasEngineFfi._();
  static final rust_wgpu_engine.CanvasEngineFfi _rustWgpu =
      rust_wgpu_engine.CanvasEngineFfi.instance;

  bool get _useRustWgpu => CanvasBackendState.backend == CanvasBackend.rustWgpu;

  bool get isSupported => _useRustWgpu && _rustWgpu.isSupported;

  void pushPointsPacked({
    required int handle,
    required Uint8List bytes,
    required int pointCount,
  }) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.pushPointsPacked(
      handle: handle,
      bytes: bytes,
      pointCount: pointCount,
    );
  }

  int getInputQueueLen(int handle) {
    if (!isSupported) {
      return 0;
    }
    return _rustWgpu.getInputQueueLen(handle);
  }

  bool isHandleValid(int handle) {
    if (!isSupported) {
      return false;
    }
    return _rustWgpu.isHandleValid(handle);
  }

  List<String> drainLogs({int maxLines = 200}) {
    if (!isSupported) {
      return const <String>[];
    }
    return _rustWgpu.drainLogs(maxLines: maxLines);
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
    bool smoothRotation = false,
    int rotationSeed = 0,
    double spacing = 0.15,
    double hardness = 0.8,
    double flow = 1.0,
    double scatter = 0.0,
    double rotationJitter = 1.0,
    bool snapToPixel = false,
    bool screentoneEnabled = false,
    double screentoneSpacing = 10.0,
    double screentoneDotSize = 0.6,
    double screentoneRotation = 45.0,
    double screentoneSoftness = 0.0,
    int screentoneShape = 0,
    bool hollow = false,
    double hollowRatio = 0.0,
    bool hollowEraseOccludedParts = false,
    double streamlineStrength = 0.0,
    int smoothingMode = 1,
    double stabilizerStrength = 0.0,
  }) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.setBrush(
      handle: handle,
      colorArgb: colorArgb,
      baseRadius: baseRadius,
      usePressure: usePressure,
      erase: erase,
      antialiasLevel: antialiasLevel,
      brushShape: brushShape,
      randomRotation: randomRotation,
      smoothRotation: smoothRotation,
      rotationSeed: rotationSeed,
      spacing: spacing,
      hardness: hardness,
      flow: flow,
      scatter: scatter,
      rotationJitter: rotationJitter,
      snapToPixel: snapToPixel,
      screentoneEnabled: screentoneEnabled,
      screentoneSpacing: screentoneSpacing,
      screentoneDotSize: screentoneDotSize,
      screentoneRotation: screentoneRotation,
      screentoneSoftness: screentoneSoftness,
      screentoneShape: screentoneShape,
      hollow: hollow,
      hollowRatio: hollowRatio,
      hollowEraseOccludedParts: hollowEraseOccludedParts,
      streamlineStrength: streamlineStrength,
      smoothingMode: smoothingMode,
      stabilizerStrength: stabilizerStrength,
    );
  }

  void setBrushMask({
    required int handle,
    required int width,
    required int height,
    required Uint8List mask,
  }) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.setBrushMask(
      handle: handle,
      width: width,
      height: height,
      mask: mask,
    );
  }

  void clearBrushMask({required int handle}) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.clearBrushMask(handle: handle);
  }

  void beginSpray({required int handle}) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.beginSpray(handle: handle);
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
    if (!isSupported) {
      return;
    }
    _rustWgpu.drawSpray(
      handle: handle,
      points: points,
      pointCount: pointCount,
      colorArgb: colorArgb,
      brushShape: brushShape,
      erase: erase,
      antialiasLevel: antialiasLevel,
      softness: softness,
      accumulate: accumulate,
    );
  }

  void endSpray({required int handle}) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.endSpray(handle: handle);
  }

  bool applyFilter({
    required int handle,
    required int layerIndex,
    required int filterType,
    double param0 = 0.0,
    double param1 = 0.0,
    double param2 = 0.0,
    double param3 = 0.0,
  }) {
    if (!isSupported) {
      return false;
    }
    return _rustWgpu.applyFilter(
      handle: handle,
      layerIndex: layerIndex,
      filterType: filterType,
      param0: param0,
      param1: param1,
      param2: param2,
      param3: param3,
    );
  }

  bool applyAntialias({
    required int handle,
    required int layerIndex,
    required int level,
  }) {
    if (!isSupported) {
      return false;
    }
    return _rustWgpu.applyAntialias(
      handle: handle,
      layerIndex: layerIndex,
      level: level,
    );
  }

  void setActiveLayer({required int handle, required int layerIndex}) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.setActiveLayer(handle: handle, layerIndex: layerIndex);
  }

  void setLayerOpacity({
    required int handle,
    required int layerIndex,
    required double opacity,
  }) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.setLayerOpacity(
      handle: handle,
      layerIndex: layerIndex,
      opacity: opacity,
    );
  }

  void setLayerVisible({
    required int handle,
    required int layerIndex,
    required bool visible,
  }) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.setLayerVisible(
      handle: handle,
      layerIndex: layerIndex,
      visible: visible,
    );
  }

  void setLayerClippingMask({
    required int handle,
    required int layerIndex,
    required bool clippingMask,
  }) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.setLayerClippingMask(
      handle: handle,
      layerIndex: layerIndex,
      clippingMask: clippingMask,
    );
  }

  void setLayerBlendMode({
    required int handle,
    required int layerIndex,
    required int blendModeIndex,
  }) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.setLayerBlendMode(
      handle: handle,
      layerIndex: layerIndex,
      blendModeIndex: blendModeIndex,
    );
  }

  void reorderLayer({
    required int handle,
    required int fromIndex,
    required int toIndex,
  }) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.reorderLayer(
      handle: handle,
      fromIndex: fromIndex,
      toIndex: toIndex,
    );
  }

  void setViewFlags({
    required int handle,
    required bool mirror,
    required bool blackWhite,
  }) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.setViewFlags(
      handle: handle,
      mirror: mirror,
      blackWhite: blackWhite,
    );
  }

  void clearLayer({required int handle, required int layerIndex}) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.clearLayer(handle: handle, layerIndex: layerIndex);
  }

  void fillLayer({
    required int handle,
    required int layerIndex,
    required int colorArgb,
  }) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.fillLayer(
      handle: handle,
      layerIndex: layerIndex,
      colorArgb: colorArgb,
    );
  }

  bool bucketFill({
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
  }) {
    if (!isSupported) {
      return false;
    }
    return _rustWgpu.bucketFill(
      handle: handle,
      layerIndex: layerIndex,
      startX: startX,
      startY: startY,
      colorArgb: colorArgb,
      contiguous: contiguous,
      sampleAllLayers: sampleAllLayers,
      tolerance: tolerance,
      fillGap: fillGap,
      antialiasLevel: antialiasLevel,
      swallowColors: swallowColors,
      selectionMask: selectionMask,
    );
  }

  Uint8List? magicWandMask({
    required int handle,
    required int layerIndex,
    required int startX,
    required int startY,
    required int maskLength,
    bool sampleAllLayers = true,
    int tolerance = 0,
    Uint8List? selectionMask,
  }) {
    if (!isSupported) {
      return null;
    }
    return _rustWgpu.magicWandMask(
      handle: handle,
      layerIndex: layerIndex,
      startX: startX,
      startY: startY,
      maskLength: maskLength,
      sampleAllLayers: sampleAllLayers,
      tolerance: tolerance,
      selectionMask: selectionMask,
    );
  }

  Uint32List? readLayer({
    required int handle,
    required int layerIndex,
    required int width,
    required int height,
  }) {
    if (!isSupported) {
      return null;
    }
    return _rustWgpu.readLayer(
      handle: handle,
      layerIndex: layerIndex,
      width: width,
      height: height,
    );
  }

  Uint8List? readLayerPreview({
    required int handle,
    required int layerIndex,
    required int width,
    required int height,
  }) {
    if (!isSupported) {
      return null;
    }
    return _rustWgpu.readLayerPreview(
      handle: handle,
      layerIndex: layerIndex,
      width: width,
      height: height,
    );
  }

  bool writeLayer({
    required int handle,
    required int layerIndex,
    required Uint32List pixels,
    bool recordUndo = true,
  }) {
    if (!isSupported) {
      return false;
    }
    return _rustWgpu.writeLayer(
      handle: handle,
      layerIndex: layerIndex,
      pixels: pixels,
      recordUndo: recordUndo,
    );
  }

  bool translateLayer({
    required int handle,
    required int layerIndex,
    required int deltaX,
    required int deltaY,
  }) {
    if (!isSupported) {
      return false;
    }
    return _rustWgpu.translateLayer(
      handle: handle,
      layerIndex: layerIndex,
      deltaX: deltaX,
      deltaY: deltaY,
    );
  }

  bool setLayerTransformPreview({
    required int handle,
    required int layerIndex,
    required Float32List matrix,
    bool enabled = true,
    bool bilinear = true,
  }) {
    if (!isSupported) {
      return false;
    }
    return _rustWgpu.setLayerTransformPreview(
      handle: handle,
      layerIndex: layerIndex,
      matrix: matrix,
      enabled: enabled,
      bilinear: bilinear,
    );
  }

  bool applyLayerTransform({
    required int handle,
    required int layerIndex,
    required Float32List matrix,
    bool bilinear = true,
  }) {
    if (!isSupported) {
      return false;
    }
    return _rustWgpu.applyLayerTransform(
      handle: handle,
      layerIndex: layerIndex,
      matrix: matrix,
      bilinear: bilinear,
    );
  }

  Int32List? getLayerBounds({required int handle, required int layerIndex}) {
    if (!isSupported) {
      return null;
    }
    return _rustWgpu.getLayerBounds(handle: handle, layerIndex: layerIndex);
  }

  void setSelectionMask({required int handle, Uint8List? selectionMask}) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.setSelectionMask(handle: handle, selectionMask: selectionMask);
  }

  void resetCanvas({required int handle, required int backgroundColorArgb}) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.resetCanvas(
      handle: handle,
      backgroundColorArgb: backgroundColorArgb,
    );
  }

  void undo({required int handle}) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.undo(handle: handle);
  }

  void redo({required int handle}) {
    if (!isSupported) {
      return;
    }
    _rustWgpu.redo(handle: handle);
  }
}

class CanvasBackendFacade {
  CanvasBackendFacade._() {
    _ensureLogPump();
  }

  static final CanvasBackendFacade instance = CanvasBackendFacade._();
  static final CanvasEngineFfi _ffi = CanvasEngineFfi.instance;
  static Timer? _logPump;

  void _ensureLogPump() {
    if (_logPump != null || kIsWeb || !kDebugMode) {
      return;
    }
    _logPump = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!isSupported) {
        return;
      }
      final List<String> lines = _ffi.drainLogs();
      for (final String line in lines) {
        debugPrint(line);
      }
    });
  }

  bool get isSupported => _ffi.isSupported;

  bool isHandleReady(int? handle) => isSupported && handle != null;

  int getInputQueueLen(int handle) => _ffi.getInputQueueLen(handle);

  bool isHandleValid(int handle) => _ffi.isHandleValid(handle);

  void pushPointsPacked({
    required int handle,
    required Uint8List bytes,
    required int pointCount,
  }) {
    _ffi.pushPointsPacked(handle: handle, bytes: bytes, pointCount: pointCount);
  }

  void fillLayer({
    required int handle,
    required int layerIndex,
    required int colorArgb,
  }) {
    _ffi.fillLayer(
      handle: handle,
      layerIndex: layerIndex,
      colorArgb: colorArgb,
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
    bool smoothRotation = false,
    int rotationSeed = 0,
    double spacing = 0.15,
    double hardness = 0.8,
    double flow = 1.0,
    double scatter = 0.0,
    double rotationJitter = 1.0,
    bool snapToPixel = false,
    bool screentoneEnabled = false,
    double screentoneSpacing = 10.0,
    double screentoneDotSize = 0.6,
    double screentoneRotation = 45.0,
    double screentoneSoftness = 0.0,
    int screentoneShape = 0,
    bool hollow = false,
    double hollowRatio = 0.0,
    bool hollowEraseOccludedParts = false,
    double streamlineStrength = 0.0,
    int smoothingMode = 1,
    double stabilizerStrength = 0.0,
  }) {
    _ffi.setBrush(
      handle: handle,
      colorArgb: colorArgb,
      baseRadius: baseRadius,
      usePressure: usePressure,
      erase: erase,
      antialiasLevel: antialiasLevel,
      brushShape: brushShape,
      randomRotation: randomRotation,
      smoothRotation: smoothRotation,
      rotationSeed: rotationSeed,
      spacing: spacing,
      hardness: hardness,
      flow: flow,
      scatter: scatter,
      rotationJitter: rotationJitter,
      snapToPixel: snapToPixel,
      screentoneEnabled: screentoneEnabled,
      screentoneSpacing: screentoneSpacing,
      screentoneDotSize: screentoneDotSize,
      screentoneRotation: screentoneRotation,
      screentoneSoftness: screentoneSoftness,
      screentoneShape: screentoneShape,
      hollow: hollow,
      hollowRatio: hollowRatio,
      hollowEraseOccludedParts: hollowEraseOccludedParts,
      streamlineStrength: streamlineStrength,
      smoothingMode: smoothingMode,
      stabilizerStrength: stabilizerStrength,
    );
  }

  void setBrushMask({
    required int handle,
    required int width,
    required int height,
    required Uint8List mask,
  }) {
    _ffi.setBrushMask(
      handle: handle,
      width: width,
      height: height,
      mask: mask,
    );
  }

  void clearBrushMask({required int handle}) {
    _ffi.clearBrushMask(handle: handle);
  }

  void setActiveLayer({required int handle, required int layerIndex}) {
    _ffi.setActiveLayer(handle: handle, layerIndex: layerIndex);
  }

  void setLayerVisible({
    required int handle,
    required int layerIndex,
    required bool visible,
  }) {
    _ffi.setLayerVisible(
      handle: handle,
      layerIndex: layerIndex,
      visible: visible,
    );
  }

  void setLayerOpacity({
    required int handle,
    required int layerIndex,
    required double opacity,
  }) {
    _ffi.setLayerOpacity(
      handle: handle,
      layerIndex: layerIndex,
      opacity: opacity,
    );
  }

  void clearLayer({required int handle, required int layerIndex}) {
    _ffi.clearLayer(handle: handle, layerIndex: layerIndex);
  }

  void undo({required int handle}) {
    _ffi.undo(handle: handle);
  }

  void redo({required int handle}) {
    _ffi.redo(handle: handle);
  }

  void beginSpray({required int handle}) {
    _ffi.beginSpray(handle: handle);
  }

  void endSpray({required int handle}) {
    _ffi.endSpray(handle: handle);
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
    _ffi.drawSpray(
      handle: handle,
      points: points,
      pointCount: pointCount,
      colorArgb: colorArgb,
      brushShape: brushShape,
      erase: erase,
      antialiasLevel: antialiasLevel,
      softness: softness,
      accumulate: accumulate,
    );
  }

  void setLayerClippingMask({
    required int handle,
    required int layerIndex,
    required bool clippingMask,
  }) {
    _ffi.setLayerClippingMask(
      handle: handle,
      layerIndex: layerIndex,
      clippingMask: clippingMask,
    );
  }

  void setLayerBlendMode({
    required int handle,
    required int layerIndex,
    required int blendModeIndex,
  }) {
    _ffi.setLayerBlendMode(
      handle: handle,
      layerIndex: layerIndex,
      blendModeIndex: blendModeIndex,
    );
  }

  void reorderLayer({
    required int handle,
    required int fromIndex,
    required int toIndex,
  }) {
    _ffi.reorderLayer(
      handle: handle,
      fromIndex: fromIndex,
      toIndex: toIndex,
    );
  }

  void setViewFlags({
    required int handle,
    required bool mirror,
    required bool blackWhite,
  }) {
    _ffi.setViewFlags(
      handle: handle,
      mirror: mirror,
      blackWhite: blackWhite,
    );
  }

  bool applyAntialias({
    required int handle,
    required int layerIndex,
    required int level,
  }) {
    return _ffi.applyAntialias(
      handle: handle,
      layerIndex: layerIndex,
      level: level,
    );
  }

  bool bucketFill({
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
  }) {
    return _ffi.bucketFill(
      handle: handle,
      layerIndex: layerIndex,
      startX: startX,
      startY: startY,
      colorArgb: colorArgb,
      contiguous: contiguous,
      sampleAllLayers: sampleAllLayers,
      tolerance: tolerance,
      fillGap: fillGap,
      antialiasLevel: antialiasLevel,
      swallowColors: swallowColors,
      selectionMask: selectionMask,
    );
  }

  Uint32List? readLayer({
    required int handle,
    required int layerIndex,
    required int width,
    required int height,
  }) {
    return _ffi.readLayer(
      handle: handle,
      layerIndex: layerIndex,
      width: width,
      height: height,
    );
  }

  Uint8List? readLayerPreview({
    required int handle,
    required int layerIndex,
    required int width,
    required int height,
  }) {
    return _ffi.readLayerPreview(
      handle: handle,
      layerIndex: layerIndex,
      width: width,
      height: height,
    );
  }

  bool writeLayer({
    required int handle,
    required int layerIndex,
    required Uint32List pixels,
    bool recordUndo = true,
  }) {
    return _ffi.writeLayer(
      handle: handle,
      layerIndex: layerIndex,
      pixels: pixels,
      recordUndo: recordUndo,
    );
  }

  bool translateLayer({
    required int handle,
    required int layerIndex,
    required int deltaX,
    required int deltaY,
  }) {
    return _ffi.translateLayer(
      handle: handle,
      layerIndex: layerIndex,
      deltaX: deltaX,
      deltaY: deltaY,
    );
  }

  bool setLayerTransformPreview({
    required int handle,
    required int layerIndex,
    required Float32List matrix,
    required bool enabled,
    required bool bilinear,
  }) {
    return _ffi.setLayerTransformPreview(
      handle: handle,
      layerIndex: layerIndex,
      matrix: matrix,
      enabled: enabled,
      bilinear: bilinear,
    );
  }

  bool applyLayerTransform({
    required int handle,
    required int layerIndex,
    required Float32List matrix,
    required bool bilinear,
  }) {
    return _ffi.applyLayerTransform(
      handle: handle,
      layerIndex: layerIndex,
      matrix: matrix,
      bilinear: bilinear,
    );
  }

  Int32List? getLayerBounds({
    required int handle,
    required int layerIndex,
  }) {
    return _ffi.getLayerBounds(handle: handle, layerIndex: layerIndex);
  }

  Uint8List? magicWandMask({
    required int handle,
    required int layerIndex,
    required int startX,
    required int startY,
    required int maskLength,
    bool sampleAllLayers = true,
    int tolerance = 0,
    Uint8List? selectionMask,
  }) {
    return _ffi.magicWandMask(
      handle: handle,
      layerIndex: layerIndex,
      startX: startX,
      startY: startY,
      maskLength: maskLength,
      sampleAllLayers: sampleAllLayers,
      tolerance: tolerance,
      selectionMask: selectionMask,
    );
  }

  void setSelectionMask({required int handle, Uint8List? selectionMask}) {
    _ffi.setSelectionMask(handle: handle, selectionMask: selectionMask);
  }

  bool applyFilter({
    required int handle,
    required int layerIndex,
    required int filterType,
    double param0 = 0.0,
    double param1 = 0.0,
    double param2 = 0.0,
    double param3 = 0.0,
  }) {
    return _ffi.applyFilter(
      handle: handle,
      layerIndex: layerIndex,
      filterType: filterType,
      param0: param0,
      param1: param1,
      param2: param2,
      param3: param3,
    );
  }

  Uint32List? selectionPathVerticesFromMask({
    required Uint8List mask,
    required int width,
  }) {
    if (mask.isEmpty || width <= 0) {
      return null;
    }
    try {
      return rust_selection_path.selectionPathVerticesFromMask(
        mask: mask,
        width: width,
      );
    } catch (_) {
      return null;
    }
  }
}
