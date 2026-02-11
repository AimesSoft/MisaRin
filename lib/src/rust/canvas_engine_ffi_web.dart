import 'dart:js_util' as js_util;
import 'dart:typed_data';

const int _kPointStrideBytes = 32;
const int _kViewFlagMirror = 1;
const int _kViewFlagBlackWhite = 2;

class CanvasEngineFfi {
  CanvasEngineFfi._();

  static final CanvasEngineFfi instance = CanvasEngineFfi._();

  bool get isSupported => _hasWasmFunction('canvas_engine_create');

  bool _hasWasmFunction(String name) {
    final Object? wasm = _wasmBindgen;
    if (wasm == null) {
      return false;
    }
    return js_util.hasProperty(wasm, name);
  }

  Object? get _wasmBindgen =>
      js_util.getProperty<Object?>(js_util.globalThis, 'wasm_bindgen');

  double _handleArg(int handle) => handle.toDouble();

  void _callVoid(String name, List<Object?> args) {
    final Object? wasm = _wasmBindgen;
    if (wasm == null) {
      return;
    }
    js_util.callMethod<Object?>(wasm, name, args);
  }

  int _callInt(String name, List<Object?> args, {int fallback = 0}) {
    final Object? wasm = _wasmBindgen;
    if (wasm == null) {
      return fallback;
    }
    final Object? result = js_util.callMethod<Object?>(wasm, name, args);
    if (result is num) {
      return result.toInt();
    }
    return fallback;
  }

  bool _callBool(String name, List<Object?> args, {bool fallback = false}) {
    final Object? wasm = _wasmBindgen;
    if (wasm == null) {
      return fallback;
    }
    final Object? result = js_util.callMethod<Object?>(wasm, name, args);
    if (result is bool) {
      return result;
    }
    if (result is num) {
      return result != 0;
    }
    return fallback;
  }

  void pushPointsPacked({
    required int handle,
    required Uint8List bytes,
    required int pointCount,
  }) {
    if (!isSupported || handle == 0 || pointCount <= 0) {
      return;
    }
    final int requiredBytes = pointCount * _kPointStrideBytes;
    if (bytes.length < requiredBytes) {
      throw RangeError.range(bytes.length, requiredBytes, null, 'bytes.length');
    }
    _callVoid('canvas_engine_push_points', <Object?>[
      _handleArg(handle),
      bytes,
      pointCount,
    ]);
  }

  int getInputQueueLen(int handle) {
    if (!isSupported || handle == 0) {
      return 0;
    }
    return _callInt('canvas_engine_get_input_queue_len', <Object?>[
      _handleArg(handle),
    ]);
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
    _callVoid('canvas_engine_set_brush', <Object?>[
      _handleArg(handle),
      colorArgb,
      baseRadius,
      usePressure ? 1 : 0,
      erase ? 1 : 0,
      antialiasLevel,
      brushShape,
      randomRotation ? 1 : 0,
      rotationSeed,
      spacing,
      hardness,
      flow,
      scatter,
      rotationJitter,
      snapToPixel ? 1 : 0,
      hollow ? 1 : 0,
      hollowRatio,
      hollowEraseOccludedParts ? 1 : 0,
      streamlineStrength,
    ]);
  }

  void beginSpray({required int handle}) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_spray_begin', <Object?>[_handleArg(handle)]);
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
    _callVoid('canvas_engine_spray_draw', <Object?>[
      _handleArg(handle),
      points,
      pointCount,
      colorArgb,
      brushShape,
      erase ? 1 : 0,
      antialiasLevel,
      softness,
      accumulate ? 1 : 0,
    ]);
  }

  void endSpray({required int handle}) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_spray_end', <Object?>[_handleArg(handle)]);
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
    if (!isSupported || handle == 0) {
      return false;
    }
    return _callBool('canvas_engine_apply_filter', <Object?>[
      _handleArg(handle),
      layerIndex,
      filterType,
      param0,
      param1,
      param2,
      param3,
    ]);
  }

  bool applyAntialias({
    required int handle,
    required int layerIndex,
    required int level,
  }) {
    if (!isSupported || handle == 0) {
      return false;
    }
    return _callBool('canvas_engine_apply_antialias', <Object?>[
      _handleArg(handle),
      layerIndex,
      level,
    ]);
  }

  void setActiveLayer({required int handle, required int layerIndex}) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_set_active_layer', <Object?>[
      _handleArg(handle),
      layerIndex,
    ]);
  }

  void setLayerOpacity({
    required int handle,
    required int layerIndex,
    required double opacity,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_set_layer_opacity', <Object?>[
      _handleArg(handle),
      layerIndex,
      opacity,
    ]);
  }

  void setLayerVisible({
    required int handle,
    required int layerIndex,
    required bool visible,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_set_layer_visible', <Object?>[
      _handleArg(handle),
      layerIndex,
      visible ? 1 : 0,
    ]);
  }

  void setLayerClippingMask({
    required int handle,
    required int layerIndex,
    required bool clippingMask,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_set_layer_clipping_mask', <Object?>[
      _handleArg(handle),
      layerIndex,
      clippingMask ? 1 : 0,
    ]);
  }

  void setLayerBlendMode({
    required int handle,
    required int layerIndex,
    required int blendModeIndex,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_set_layer_blend_mode', <Object?>[
      _handleArg(handle),
      layerIndex,
      blendModeIndex,
    ]);
  }

  void reorderLayer({
    required int handle,
    required int fromIndex,
    required int toIndex,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_reorder_layer', <Object?>[
      _handleArg(handle),
      fromIndex,
      toIndex,
    ]);
  }

  void setViewFlags({
    required int handle,
    required bool mirror,
    required bool blackWhite,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    final int flags =
        (mirror ? _kViewFlagMirror : 0) |
        (blackWhite ? _kViewFlagBlackWhite : 0);
    _callVoid('canvas_engine_set_view_flags', <Object?>[
      _handleArg(handle),
      flags,
    ]);
  }

  void clearLayer({required int handle, required int layerIndex}) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_clear_layer', <Object?>[
      _handleArg(handle),
      layerIndex,
    ]);
  }

  void fillLayer({
    required int handle,
    required int layerIndex,
    required int colorArgb,
  }) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_fill_layer', <Object?>[
      _handleArg(handle),
      layerIndex,
      colorArgb,
    ]);
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
    if (!isSupported || handle == 0) {
      return false;
    }
    return _callBool('canvas_engine_bucket_fill', <Object?>[
      _handleArg(handle),
      layerIndex,
      startX,
      startY,
      colorArgb,
      contiguous ? 1 : 0,
      sampleAllLayers ? 1 : 0,
      tolerance,
      fillGap,
      antialiasLevel,
      swallowColors ?? Uint32List(0),
      selectionMask ?? Uint8List(0),
    ]);
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
    if (!isSupported || handle == 0 || maskLength <= 0) {
      return null;
    }
    final Uint8List outMask = Uint8List(maskLength);
    final bool ok = _callBool('canvas_engine_magic_wand_mask', <Object?>[
      _handleArg(handle),
      layerIndex,
      startX,
      startY,
      sampleAllLayers ? 1 : 0,
      tolerance,
      selectionMask ?? Uint8List(0),
      outMask,
    ]);
    return ok ? outMask : null;
  }

  Uint32List? readLayer({
    required int handle,
    required int layerIndex,
    required int width,
    required int height,
  }) {
    if (!isSupported || handle == 0) {
      return null;
    }
    if (width <= 0 || height <= 0) {
      return null;
    }
    final Uint32List pixels = Uint32List(width * height);
    final bool ok = _callBool('canvas_engine_read_layer', <Object?>[
      _handleArg(handle),
      layerIndex,
      pixels,
    ]);
    return ok ? pixels : null;
  }

  Uint8List? readLayerPreview({
    required int handle,
    required int layerIndex,
    required int width,
    required int height,
  }) {
    if (!isSupported || handle == 0) {
      return null;
    }
    if (width <= 0 || height <= 0) {
      return null;
    }
    final Uint8List pixels = Uint8List(width * height * 4);
    final bool ok = _callBool('canvas_engine_read_layer_preview', <Object?>[
      _handleArg(handle),
      layerIndex,
      width,
      height,
      pixels,
    ]);
    return ok ? pixels : null;
  }

  bool writeLayer({
    required int handle,
    required int layerIndex,
    required Uint32List pixels,
    bool recordUndo = true,
  }) {
    if (!isSupported || handle == 0 || pixels.isEmpty) {
      return false;
    }
    return _callBool('canvas_engine_write_layer', <Object?>[
      _handleArg(handle),
      layerIndex,
      pixels,
      recordUndo ? 1 : 0,
    ]);
  }

  bool translateLayer({
    required int handle,
    required int layerIndex,
    required int deltaX,
    required int deltaY,
  }) {
    if (!isSupported || handle == 0) {
      return false;
    }
    return _callBool('canvas_engine_translate_layer', <Object?>[
      _handleArg(handle),
      layerIndex,
      deltaX,
      deltaY,
    ]);
  }

  bool setLayerTransformPreview({
    required int handle,
    required int layerIndex,
    required Float32List matrix,
    bool enabled = true,
    bool bilinear = true,
  }) {
    if (!isSupported || handle == 0 || matrix.length < 16) {
      return false;
    }
    return _callBool('canvas_engine_set_layer_transform_preview', <Object?>[
      _handleArg(handle),
      layerIndex,
      matrix,
      enabled ? 1 : 0,
      bilinear ? 1 : 0,
    ]);
  }

  bool applyLayerTransform({
    required int handle,
    required int layerIndex,
    required Float32List matrix,
    bool bilinear = true,
  }) {
    if (!isSupported || handle == 0 || matrix.length < 16) {
      return false;
    }
    return _callBool('canvas_engine_apply_layer_transform', <Object?>[
      _handleArg(handle),
      layerIndex,
      matrix,
      bilinear ? 1 : 0,
    ]);
  }

  Int32List? getLayerBounds({required int handle, required int layerIndex}) {
    if (!isSupported || handle == 0) {
      return null;
    }
    final Int32List bounds = Int32List(4);
    final bool ok = _callBool('canvas_engine_get_layer_bounds', <Object?>[
      _handleArg(handle),
      layerIndex,
      bounds,
    ]);
    return ok ? bounds : null;
  }

  void setSelectionMask({required int handle, Uint8List? selectionMask}) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_set_selection_mask', <Object?>[
      _handleArg(handle),
      selectionMask ?? Uint8List(0),
    ]);
  }

  void resetCanvas({required int handle, required int backgroundColorArgb}) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_reset_canvas', <Object?>[
      _handleArg(handle),
      backgroundColorArgb,
    ]);
  }

  void undo({required int handle}) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_undo', <Object?>[_handleArg(handle)]);
  }

  void redo({required int handle}) {
    if (!isSupported || handle == 0) {
      return;
    }
    _callVoid('canvas_engine_redo', <Object?>[_handleArg(handle)]);
  }

  bool pollFrameReady(int handle) {
    if (!isSupported || handle == 0) {
      return false;
    }
    return _callBool('canvas_engine_poll_frame_ready', <Object?>[
      _handleArg(handle),
    ]);
  }

  Uint8List? readPresent({
    required int handle,
    required int width,
    required int height,
  }) {
    if (!isSupported || handle == 0) {
      return null;
    }
    if (width <= 0 || height <= 0) {
      return null;
    }
    final Uint8List pixels = Uint8List(width * height * 4);
    final bool ok = _callBool('canvas_engine_read_present', <Object?>[
      _handleArg(handle),
      pixels,
    ]);
    return ok ? pixels : null;
  }
}
