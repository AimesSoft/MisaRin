import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:misa_rin/src/rust/canvas_engine_ffi.dart';

import '../debug/rust_canvas_timeline.dart';
import '../../canvas/canvas_tools.dart';
import '../utils/tablet_input_bridge.dart';

const MethodChannel _rustCanvasChannel = MethodChannel(
  'misarin/rust_canvas_texture',
);

const bool _kDebugRustCanvasInput = bool.fromEnvironment(
  'MISA_RIN_DEBUG_RUST_CANVAS_INPUT',
  defaultValue: false,
);

String _surfaceIdForKey(String surfaceKey) {
  final String normalized = surfaceKey.trim();
  assert(normalized.isNotEmpty, 'surfaceKey must be non-empty');
  return 'rust_canvas_project_$normalized';
}

const int _kPointStrideBytes = 32;
const int _kPointFlagDown = 1;
const int _kPointFlagMove = 2;
const int _kPointFlagUp = 4;

final class _PackedPointBuffer {
  _PackedPointBuffer({int initialCapacityPoints = 256})
    : _bytes = Uint8List(initialCapacityPoints * _kPointStrideBytes) {
    _data = ByteData.view(_bytes.buffer);
  }

  Uint8List _bytes;
  late ByteData _data;
  int _len = 0;

  int get length => _len;

  Uint8List get bytes => _bytes;

  void clear() => _len = 0;

  void add({
    required double x,
    required double y,
    required double pressure,
    required int timestampUs,
    required int flags,
    required int pointerId,
  }) {
    _ensureCapacity(_len + 1);
    final int base = _len * _kPointStrideBytes;
    _data.setFloat32(base + 0, x, Endian.little);
    _data.setFloat32(base + 4, y, Endian.little);
    _data.setFloat32(base + 8, pressure, Endian.little);
    _data.setFloat32(base + 12, 0.0, Endian.little); // pad
    _data.setUint64(base + 16, timestampUs, Endian.little);
    _data.setUint32(base + 24, flags, Endian.little);
    _data.setUint32(base + 28, pointerId, Endian.little);
    _len++;
  }

  void _ensureCapacity(int neededPoints) {
    final int neededBytes = neededPoints * _kPointStrideBytes;
    if (_bytes.lengthInBytes >= neededBytes) {
      return;
    }
    int nextBytes = _bytes.lengthInBytes;
    while (nextBytes < neededBytes) {
      nextBytes = nextBytes * 2;
    }
    final Uint8List next = Uint8List(nextBytes);
    next.setRange(0, _len * _kPointStrideBytes, _bytes, 0);
    _bytes = next;
    _data = ByteData.view(_bytes.buffer);
  }
}

class _RustSurfaceInfo {
  const _RustSurfaceInfo({
    required this.textureId,
    required this.engineHandle,
    required this.engineWidth,
    required this.engineHeight,
    required this.backgroundColorArgb,
    required this.fromWarmup,
    required this.isNewEngine,
  });

  final int? textureId;
  final int? engineHandle;
  final int? engineWidth;
  final int? engineHeight;
  final int backgroundColorArgb;
  final bool fromWarmup;
  final bool isNewEngine;

  bool get isValid => textureId != null && engineHandle != null;
}

final class _WarmupEntry {
  const _WarmupEntry({
    required this.width,
    required this.height,
    required this.layerCount,
    required this.backgroundColorArgb,
    required this.future,
  });

  final int width;
  final int height;
  final int layerCount;
  final int backgroundColorArgb;
  final Future<_RustSurfaceInfo> future;

  bool matches({
    required int width,
    required int height,
    required int layerCount,
    required int backgroundColorArgb,
  }) {
    return this.width == width &&
        this.height == height &&
        this.layerCount == layerCount &&
        this.backgroundColorArgb == backgroundColorArgb;
  }
}

class _RustSurfaceWarmupCache {
  _RustSurfaceWarmupCache._();

  static final _RustSurfaceWarmupCache instance =
      _RustSurfaceWarmupCache._();

  final Map<String, _WarmupEntry> _warmups = <String, _WarmupEntry>{};

  Future<void> startWarmup({
    required String surfaceId,
    required int width,
    required int height,
    required int layerCount,
    required int backgroundColorArgb,
  }) async {
    final _WarmupEntry? existing = _warmups[surfaceId];
    if (existing != null &&
        existing.matches(
          width: width,
          height: height,
          layerCount: layerCount,
          backgroundColorArgb: backgroundColorArgb,
        )) {
      return;
    }
    if (existing != null) {
      _warmups.remove(surfaceId);
      await _disposeWarmup(surfaceId, existing.future);
    }
    final Future<_RustSurfaceInfo> future = () async {
      RustCanvasTimeline.mark(
        'rustSurface: warmup request surface=$surfaceId '
        'size=${width}x${height} layers=$layerCount',
      );
      try {
        return await _requestTextureInfo(
          surfaceId: surfaceId,
          width: width,
          height: height,
          layerCount: layerCount,
          backgroundColorArgb: backgroundColorArgb,
          fromWarmup: true,
        );
      } catch (error) {
        RustCanvasTimeline.mark('rustSurface: warmup failed $error');
        rethrow;
      }
    }();
    _warmups[surfaceId] = _WarmupEntry(
      width: width,
      height: height,
      layerCount: layerCount,
      backgroundColorArgb: backgroundColorArgb,
      future: future,
    );
  }

  Future<_RustSurfaceInfo> takeOrRequest({
    required String surfaceId,
    required int width,
    required int height,
    required int layerCount,
    required int backgroundColorArgb,
  }) async {
    final _WarmupEntry? pending = _warmups.remove(surfaceId);
    if (pending != null) {
      if (pending.matches(
        width: width,
        height: height,
        layerCount: layerCount,
        backgroundColorArgb: backgroundColorArgb,
      )) {
        try {
          return await pending.future;
        } catch (_) {
          // Fall through to a fresh request.
        }
      } else {
        await _disposeWarmup(surfaceId, pending.future);
      }
    }
    return _requestTextureInfo(
      surfaceId: surfaceId,
      width: width,
      height: height,
      layerCount: layerCount,
      backgroundColorArgb: backgroundColorArgb,
      fromWarmup: false,
    );
  }

  Future<void> cancelWarmup({required String surfaceId}) async {
    final _WarmupEntry? pending = _warmups.remove(surfaceId);
    if (pending == null) {
      return;
    }
    await _disposeWarmup(surfaceId, pending.future);
  }

  void drop(String surfaceId) {
    _warmups.remove(surfaceId);
  }

  Future<void> _disposeWarmup(
    String surfaceId,
    Future<_RustSurfaceInfo> pending,
  ) async {
    try {
      try {
        await pending;
      } catch (_) {}
      RustCanvasTimeline.mark(
        'rustSurface: warmup canceled surface=$surfaceId',
      );
      await _rustCanvasChannel.invokeMethod<void>(
        'disposeTexture',
        <String, Object?>{'surfaceId': surfaceId},
      );
    } catch (_) {}
  }
}

Future<_RustSurfaceInfo> _requestTextureInfo({
  required String surfaceId,
  required int width,
  required int height,
  required int layerCount,
  required int backgroundColorArgb,
  required bool fromWarmup,
}) async {
  if (!CanvasEngineFfi.instance.isSupported) {
    return _RustSurfaceInfo(
      textureId: null,
      engineHandle: null,
      engineWidth: width,
      engineHeight: height,
      backgroundColorArgb: backgroundColorArgb,
      fromWarmup: fromWarmup,
      isNewEngine: false,
    );
  }
  final Map<dynamic, dynamic>? info =
      await _rustCanvasChannel.invokeMethod<Map<dynamic, dynamic>>(
    'getTextureInfo',
    <String, Object?>{
      'surfaceId': surfaceId,
      'width': width,
      'height': height,
      'layerCount': layerCount,
      'backgroundColorArgb': backgroundColorArgb,
    },
  );
  final int? textureId = (info?['textureId'] as num?)?.toInt();
  final int? engineHandle = (info?['engineHandle'] as num?)?.toInt();
  final int? engineWidth = (info?['width'] as num?)?.toInt();
  final int? engineHeight = (info?['height'] as num?)?.toInt();
  final Object? rawIsNewEngine = info?['isNewEngine'];
  final bool isNewEngine =
      rawIsNewEngine == true ||
      (rawIsNewEngine is num && rawIsNewEngine.toInt() != 0);
  return _RustSurfaceInfo(
    textureId: textureId,
    engineHandle: engineHandle,
    engineWidth: engineWidth,
    engineHeight: engineHeight,
    backgroundColorArgb: backgroundColorArgb,
    fromWarmup: fromWarmup,
    isNewEngine: isNewEngine,
  );
}

class RustCanvasSurface extends StatefulWidget {
  const RustCanvasSurface({
    super.key,
    required this.surfaceKey,
    required this.canvasSize,
    required this.enableDrawing,
    this.layerCount = 1,
    required this.brushColorArgb,
    required this.brushRadius,
    required this.erase,
    required this.brushShape,
    required this.brushRandomRotationEnabled,
    required this.brushRotationSeed,
    required this.brushSpacing,
    required this.brushHardness,
    required this.brushFlow,
    required this.brushScatter,
    required this.brushRotationJitter,
    required this.brushSnapToPixel,
    this.hollowStrokeEnabled = false,
    this.hollowStrokeRatio = 0.0,
    this.hollowStrokeEraseOccludedParts = false,
    this.antialiasLevel = 1,
    this.backgroundColorArgb = 0xFFFFFFFF,
    this.usePressure = true,
    this.stylusCurve = 1.0,
    this.streamlineStrength = 0.0,
    this.onStrokeBegin,
    this.onEngineInfoChanged,
  });

  static Future<void> prewarm({
    required String surfaceKey,
    required Size canvasSize,
    required int layerCount,
    required int backgroundColorArgb,
  }) async {
    final int width = canvasSize.width.round().clamp(1, 16384);
    final int height = canvasSize.height.round().clamp(1, 16384);
    await _RustSurfaceWarmupCache.instance.startWarmup(
      surfaceId: _surfaceIdForKey(surfaceKey),
      width: width,
      height: height,
      layerCount: layerCount,
      backgroundColorArgb: backgroundColorArgb,
    );
  }

  static String surfaceIdFor(String surfaceKey) {
    return _surfaceIdForKey(surfaceKey);
  }

  static Future<void> cancelWarmup({required String surfaceKey}) {
    return _RustSurfaceWarmupCache.instance.cancelWarmup(
      surfaceId: _surfaceIdForKey(surfaceKey),
    );
  }

  static Future<void> prewarmTextureEngine() {
    return _RustCanvasSurfaceState.prewarmIfNeeded();
  }

  final String surfaceKey;
  final Size canvasSize;
  final bool enableDrawing;
  final int layerCount;
  final int brushColorArgb;
  final double brushRadius;
  final bool erase;
  final BrushShape brushShape;
  final bool brushRandomRotationEnabled;
  final int brushRotationSeed;
  final double brushSpacing;
  final double brushHardness;
  final double brushFlow;
  final double brushScatter;
  final double brushRotationJitter;
  final bool brushSnapToPixel;
  final bool hollowStrokeEnabled;
  final double hollowStrokeRatio;
  final bool hollowStrokeEraseOccludedParts;
  final int antialiasLevel;
  final int backgroundColorArgb;
  final bool usePressure;
  final double stylusCurve;
  final double streamlineStrength;
  final VoidCallback? onStrokeBegin;
  final void Function(
    int? handle,
    Size? engineSize,
    bool isNewEngine,
  )? onEngineInfoChanged;

  @override
  State<RustCanvasSurface> createState() => _RustCanvasSurfaceState();
}

class _RustCanvasSurfaceState extends State<RustCanvasSurface> {
  static Future<void>? _prewarmFuture;

  int? _textureId;
  int? _engineHandle;
  Size? _engineSize;
  Object? _error;
  late final String _surfaceId;

  final _PackedPointBuffer _points = _PackedPointBuffer();
  int? _activeDrawingPointer;
  bool _activeStrokeUsesPressure = true;
  int? _lastNotifiedEngineHandle;
  Size? _lastNotifiedEngineSize;

  @override
  void initState() {
    super.initState();
    _surfaceId = _surfaceIdForKey(widget.surfaceKey);
    RustCanvasTimeline.mark(
      'rustSurface: initState id=$_surfaceId '
      'size=${widget.canvasSize.width}x${widget.canvasSize.height} '
      'layers=${widget.layerCount}',
    );
    unawaited(prewarmIfNeeded());
    unawaited(_loadTextureInfo());
  }

  @override
  void didUpdateWidget(covariant RustCanvasSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.canvasSize != widget.canvasSize) {
      unawaited(_loadTextureInfo());
    }
    final bool brushChanged =
        oldWidget.brushColorArgb != widget.brushColorArgb ||
        (oldWidget.brushRadius - widget.brushRadius).abs() > 1e-6 ||
        oldWidget.erase != widget.erase ||
        oldWidget.antialiasLevel != widget.antialiasLevel ||
        oldWidget.usePressure != widget.usePressure ||
        oldWidget.brushShape != widget.brushShape ||
        oldWidget.brushRandomRotationEnabled !=
            widget.brushRandomRotationEnabled ||
        oldWidget.brushRotationSeed != widget.brushRotationSeed ||
        (oldWidget.brushSpacing - widget.brushSpacing).abs() > 1e-6 ||
        (oldWidget.brushHardness - widget.brushHardness).abs() > 1e-6 ||
        (oldWidget.brushFlow - widget.brushFlow).abs() > 1e-6 ||
        (oldWidget.brushScatter - widget.brushScatter).abs() > 1e-6 ||
        (oldWidget.brushRotationJitter - widget.brushRotationJitter).abs() >
            1e-6 ||
        oldWidget.brushSnapToPixel != widget.brushSnapToPixel ||
        oldWidget.hollowStrokeEnabled != widget.hollowStrokeEnabled ||
        (oldWidget.hollowStrokeRatio - widget.hollowStrokeRatio).abs() > 1e-6 ||
        oldWidget.hollowStrokeEraseOccludedParts !=
            widget.hollowStrokeEraseOccludedParts ||
        (oldWidget.streamlineStrength - widget.streamlineStrength).abs() > 1e-6;
    if (brushChanged && _activeDrawingPointer == null) {
      final int? handle = _engineHandle;
      if (handle != null) {
        _applyBrushSettings(handle);
      }
    }
    if (oldWidget.backgroundColorArgb != widget.backgroundColorArgb &&
        _activeDrawingPointer == null) {
      final int? handle = _engineHandle;
      if (handle != null) {
        _applyBackground(handle);
      }
    }
  }

  static Future<void> prewarmIfNeeded() async {
    if (_prewarmFuture != null) {
      return _prewarmFuture;
    }
    _prewarmFuture = _doPrewarm();
    return _prewarmFuture;
  }

  static Future<void> _doPrewarm() async {
    if (!CanvasEngineFfi.instance.isSupported) {
      return;
    }
    try {
      RustCanvasTimeline.mark('rustSurface: prewarm start');
      const String warmSurfaceId = 'rust_canvas_prewarm';
      await _rustCanvasChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getTextureInfo',
        <String, Object?>{
          'surfaceId': warmSurfaceId,
          'width': 1,
          'height': 1,
          'layerCount': 1,
          'backgroundColorArgb': 0xFFFFFFFF,
        },
      );
      await _rustCanvasChannel.invokeMethod<void>('disposeTexture', <String, Object?>{
        'surfaceId': warmSurfaceId,
      });
      RustCanvasTimeline.mark('rustSurface: prewarm done');
    } catch (e) {
      RustCanvasTimeline.mark('rustSurface: prewarm failed $e');
      _prewarmFuture = null; // Allow retry if it failed
    }
  }

  Future<void> _loadTextureInfo() async {
    if (!CanvasEngineFfi.instance.isSupported) {
      if (!mounted) {
        return;
      }
      setState(() {
        _textureId = null;
        _engineHandle = null;
        _engineSize = null;
        _error = null;
      });
      return;
    }
    try {
      final int width = widget.canvasSize.width.round().clamp(1, 16384);
      final int height = widget.canvasSize.height.round().clamp(1, 16384);
      debugPrint(
        'rustSurface: request size=${width}x$height '
        'layers=${widget.layerCount} id=$_surfaceId',
      );
      final _RustSurfaceInfo info =
          await _RustSurfaceWarmupCache.instance.takeOrRequest(
        surfaceId: _surfaceId,
        width: width,
        height: height,
        layerCount: widget.layerCount,
        backgroundColorArgb: widget.backgroundColorArgb,
      );
      final int? textureId = info.textureId;
      final int? engineHandle = info.engineHandle;
      final int? engineWidth = info.engineWidth;
      final int? engineHeight = info.engineHeight;
      final bool backgroundNeedsUpdate =
          info.backgroundColorArgb != widget.backgroundColorArgb;
      if (!mounted) {
        return;
      }
      setState(() {
        _textureId = textureId;
        _engineHandle = engineHandle;
        _engineSize = (engineWidth != null && engineHeight != null)
            ? Size(engineWidth.toDouble(), engineHeight.toDouble())
            : null;
        _error = (textureId == null || engineHandle == null)
            ? StateError('textureId/engineHandle == null: $info')
            : null;
      });
      debugPrint(
        'rustSurface: ready textureId=$textureId handle=$engineHandle '
        'engine=${engineWidth}x${engineHeight} '
        'newEngine=${info.isNewEngine} id=$_surfaceId',
      );
      RustCanvasTimeline.mark(
        'rustSurface: texture ready '
        'textureId=$textureId handle=$engineHandle '
        'engine=${engineWidth}x${engineHeight} '
        'newEngine=${info.isNewEngine} '
        'source=${info.fromWarmup ? 'warmup' : 'direct'}',
      );

      final int? handle = _engineHandle;
      if (handle != null) {
        _applyBrushSettings(handle);
        if (backgroundNeedsUpdate) {
          _applyBackground(handle);
        }
      }
      _notifyEngineInfoChanged(isNewEngine: info.isNewEngine);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _textureId = null;
        _engineHandle = null;
        _engineSize = null;
        _error = error;
      });
      RustCanvasTimeline.mark(
        'rustSurface: loadTextureInfo error $error',
      );
      _notifyEngineInfoChanged();
    }
  }

  void _notifyEngineInfoChanged({bool isNewEngine = false}) {
    final int? handle = _engineHandle;
    final Size? size = _engineSize;
    if (!isNewEngine &&
        _lastNotifiedEngineHandle == handle &&
        _lastNotifiedEngineSize == size) {
      return;
    }
    _lastNotifiedEngineHandle = handle;
    _lastNotifiedEngineSize = size;
    widget.onEngineInfoChanged?.call(handle, size, isNewEngine);
  }

  @override
  void dispose() {
    _RustSurfaceWarmupCache.instance.drop(_surfaceId);
    unawaited(_disposeSurface());
    if (_lastNotifiedEngineHandle != null || _lastNotifiedEngineSize != null) {
      widget.onEngineInfoChanged?.call(null, null, false);
    }
    super.dispose();
  }

  Future<void> _disposeSurface() async {
    try {
      await _rustCanvasChannel.invokeMethod<void>('disposeTexture', <String, Object?>{
        'surfaceId': _surfaceId,
      });
    } catch (_) {}
  }

  void _applyBackground(int handle) {
    if (!CanvasEngineFfi.instance.isSupported) {
      return;
    }
    // Background is represented by layer 0 in the Rust MVP compositor.
    CanvasEngineFfi.instance.fillLayer(
      handle: handle,
      layerIndex: 0,
      colorArgb: widget.backgroundColorArgb,
    );
  }

  bool _canSendPoints() {
    return CanvasEngineFfi.instance.isSupported && _engineHandle != null;
  }

  void _applyBrushSettings(int handle, {bool? usePressureOverride}) {
    if (!CanvasEngineFfi.instance.isSupported) {
      return;
    }
    double radius = widget.brushRadius;
    final Size engineSize = _engineSize ?? widget.canvasSize;
    if (engineSize != widget.canvasSize &&
        widget.canvasSize.width > 0 &&
        widget.canvasSize.height > 0) {
      final double sx = engineSize.width / widget.canvasSize.width;
      final double sy = engineSize.height / widget.canvasSize.height;
      final double scale = (sx.isFinite && sy.isFinite)
          ? ((sx + sy) / 2.0)
          : 1.0;
      if (scale.isFinite && scale > 0) {
        radius *= scale;
      }
    }
    CanvasEngineFfi.instance.setBrush(
      handle: handle,
      colorArgb: widget.brushColorArgb,
      baseRadius: radius,
      usePressure: usePressureOverride ?? widget.usePressure,
      erase: widget.erase,
      antialiasLevel: widget.antialiasLevel,
      brushShape: widget.brushShape.index,
      randomRotation: widget.brushRandomRotationEnabled,
      rotationSeed: widget.brushRotationSeed,
      spacing: widget.brushSpacing,
      hardness: widget.brushHardness,
      flow: widget.brushFlow,
      scatter: widget.brushScatter,
      rotationJitter: widget.brushRotationJitter,
      snapToPixel: widget.brushSnapToPixel,
      hollow: widget.hollowStrokeEnabled,
      hollowRatio: widget.hollowStrokeRatio,
      hollowEraseOccludedParts: widget.hollowStrokeEraseOccludedParts,
      streamlineStrength: widget.streamlineStrength,
    );
  }

  bool _isDrawingPointer(PointerEvent event) {
    if (TabletInputBridge.instance.isTabletPointer(event)) {
      return true;
    }
    if (event.kind == PointerDeviceKind.mouse) {
      return (event.buttons & kPrimaryMouseButton) != 0;
    }
    return false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enableDrawing) {
      return;
    }
    if (!_canSendPoints() || !_isDrawingPointer(event)) {
      return;
    }
    final int? handle = _engineHandle;
    if (handle == null) {
      return;
    }
    if (_kDebugRustCanvasInput) {
      debugPrint(
        '[rust_canvas] down id=${event.pointer} pos=${event.localPosition} pressure=${event.pressure}',
      );
    }
    final bool supportsPressure =
        TabletInputBridge.instance.isTabletPointer(event);
    _activeStrokeUsesPressure = widget.usePressure && supportsPressure;
    _applyBrushSettings(handle, usePressureOverride: _activeStrokeUsesPressure);
    _activeDrawingPointer = event.pointer;
    _enqueuePoint(event, _kPointFlagDown);
    _flushToRust(handle);
    widget.onStrokeBegin?.call();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activeDrawingPointer != event.pointer) {
      return;
    }
    final int? handle = _engineHandle;
    if (handle == null) {
      return;
    }
    final dynamic dyn = event;
    try {
      final List<dynamic>? coalesced = dyn.coalescedEvents as List<dynamic>?;
      if (coalesced != null && coalesced.isNotEmpty) {
        for (final dynamic e in coalesced) {
          if (e is PointerEvent) {
            _enqueuePoint(e, _kPointFlagMove);
          }
        }
        _flushToRust(handle);
        return;
      }
    } catch (_) {}
    _enqueuePoint(event, _kPointFlagMove);
    _flushToRust(handle);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_activeDrawingPointer != event.pointer) {
      return;
    }
    if (_kDebugRustCanvasInput) {
      debugPrint(
        '[rust_canvas] up id=${event.pointer} pos=${event.localPosition}',
      );
    }
    _enqueuePoint(event, _kPointFlagUp);
    final int? handle = _engineHandle;
    if (handle != null) {
      _flushToRust(handle);
    }
    _activeDrawingPointer = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_activeDrawingPointer != event.pointer) {
      return;
    }
    if (_kDebugRustCanvasInput) {
      debugPrint(
        '[rust_canvas] cancel id=${event.pointer} pos=${event.localPosition}',
      );
    }
    _enqueuePoint(event, _kPointFlagUp);
    final int? handle = _engineHandle;
    if (handle != null) {
      _flushToRust(handle);
    }
    _activeDrawingPointer = null;
  }

  Offset _toEngineSpace(Offset localPosition) {
    final Size engineSize = _engineSize ?? widget.canvasSize;
    if (engineSize == widget.canvasSize) {
      return localPosition;
    }
    final double sx = widget.canvasSize.width <= 0
        ? 1.0
        : engineSize.width / widget.canvasSize.width;
    final double sy = widget.canvasSize.height <= 0
        ? 1.0
        : engineSize.height / widget.canvasSize.height;
    return Offset(localPosition.dx * sx, localPosition.dy * sy);
  }

  void _enqueuePoint(PointerEvent event, int flags) {
    final int? handle = _engineHandle;
    if (handle == null) {
      return;
    }
    final Offset canvasPos = _toEngineSpace(event.localPosition);
    final double pressure = !_activeStrokeUsesPressure
        ? 1.0
        : (_normalizeStylusPressure(event) ?? 1.0);
    final int timestampUs = event.timeStamp.inMicroseconds;
    _points.add(
      x: canvasPos.dx,
      y: canvasPos.dy,
      pressure: pressure,
      timestampUs: timestampUs,
      flags: flags,
      pointerId: event.pointer,
    );
  }

  void _flushToRust(int handle) {
    final int count = _points.length;
    if (count == 0) {
      return;
    }
    if (_kDebugRustCanvasInput) {
      final int queued = CanvasEngineFfi.instance.getInputQueueLen(handle);
      debugPrint('[rust_canvas] flush points=$count queued_before=$queued');
    }
    CanvasEngineFfi.instance.pushPointsPacked(
      handle: handle,
      bytes: _points.bytes,
      pointCount: count,
    );
    _points.clear();
  }

  double? _normalizeStylusPressure(PointerEvent event) {
    final double? pressure = TabletInputBridge.instance.pressureForEvent(event);
    if (pressure == null || !pressure.isFinite) {
      return null;
    }
    double lower = event.pressureMin;
    double upper = event.pressureMax;
    if (!lower.isFinite) {
      lower = 0.0;
    }
    if (!upper.isFinite || upper <= lower) {
      upper = lower + 1.0;
    }
    final double normalized = (pressure - lower) / (upper - lower);
    if (!normalized.isFinite) {
      return null;
    }
    final double curve = widget.stylusCurve.isFinite ? widget.stylusCurve : 1.0;
    final double curved =
        math.pow(normalized.clamp(0.0, 1.0), curve).toDouble();
    return curved.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final Size canvasSize = widget.canvasSize;
    final Object? error = _error;
    final int? textureId = _textureId;

    if (error != null) {
      return SizedBox(
        width: canvasSize.width,
        height: canvasSize.height,
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: Center(
            child: Text(
              'Rust canvas init failed: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12),
            ),
          ),
        ),
      );
    }

    if (textureId == null) {
      return SizedBox(
        width: canvasSize.width,
        height: canvasSize.height,
        child: const ColoredBox(color: Color(0xFFFFFFFF)),
      );
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: SizedBox(
        width: canvasSize.width,
        height: canvasSize.height,
        child: Texture(textureId: textureId, filterQuality: FilterQuality.none),
      ),
    );
  }
}
