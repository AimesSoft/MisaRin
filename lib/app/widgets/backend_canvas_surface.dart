import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:misa_rin/canvas/canvas_engine_bridge.dart';

import '../debug/backend_canvas_log.dart';
import '../debug/backend_canvas_timeline.dart';
import '../../canvas/canvas_tools.dart';
import '../../painting/stroke_stabilizer_curve.dart';
import '../utils/tablet_input_bridge.dart';

const MethodChannel _backendCanvasChannel = MethodChannel(
  'misarin/rust_canvas_texture',
);

const String _kDebugBackendCanvasInputEnv = String.fromEnvironment(
  'MISA_RIN_DEBUG_BACKEND_CANVAS_INPUT',
  defaultValue: '',
);
const String _kDebugRustCanvasInputEnv = String.fromEnvironment(
  'MISA_RIN_DEBUG_RUST_CANVAS_INPUT',
  defaultValue: '',
);
final bool _kDebugBackendCanvasInput =
    _kDebugBackendCanvasInputEnv == '1' ||
    _kDebugBackendCanvasInputEnv == 'true' ||
    _kDebugRustCanvasInputEnv == '1' ||
    _kDebugRustCanvasInputEnv == 'true';

String _surfaceIdForKey(String surfaceKey) {
  final String normalized = surfaceKey.trim();
  assert(normalized.isNotEmpty, 'surfaceKey must be non-empty');
  return 'backend_canvas_project_$normalized';
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

class _BackendSurfaceInfo {
  const _BackendSurfaceInfo({
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
  final Future<_BackendSurfaceInfo> future;

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

class _BackendSurfaceWarmupCache {
  _BackendSurfaceWarmupCache._();

  static final _BackendSurfaceWarmupCache instance =
      _BackendSurfaceWarmupCache._();

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
    final Future<_BackendSurfaceInfo> future = () async {
      BackendCanvasTimeline.mark(
        'backendSurface: warmup request surface=$surfaceId '
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
        BackendCanvasTimeline.mark('backendSurface: warmup failed $error');
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

  Future<_BackendSurfaceInfo> takeOrRequest({
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
    Future<_BackendSurfaceInfo> pending,
  ) async {
    try {
      try {
        await pending;
      } catch (_) {}
      BackendCanvasTimeline.mark(
        'backendSurface: warmup canceled surface=$surfaceId',
      );
      await _backendCanvasChannel.invokeMethod<void>(
        'disposeTexture',
        <String, Object?>{'surfaceId': surfaceId},
      );
    } catch (_) {}
  }
}

Future<_BackendSurfaceInfo> _requestTextureInfo({
  required String surfaceId,
  required int width,
  required int height,
  required int layerCount,
  required int backgroundColorArgb,
  required bool fromWarmup,
}) async {
  final Map<dynamic, dynamic>? info =
      await _backendCanvasChannel.invokeMethod<Map<dynamic, dynamic>>(
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
  return _BackendSurfaceInfo(
    textureId: textureId,
    engineHandle: engineHandle,
    engineWidth: engineWidth,
    engineHeight: engineHeight,
    backgroundColorArgb: backgroundColorArgb,
    fromWarmup: fromWarmup,
    isNewEngine: isNewEngine,
  );
}

class BackendCanvasSurface extends StatefulWidget {
  const BackendCanvasSurface({
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
    required this.brushSmoothRotationEnabled,
    required this.brushRotationSeed,
    required this.brushSpacing,
    required this.brushHardness,
    required this.brushFlow,
    required this.brushScatter,
    required this.brushRotationJitter,
    required this.brushSnapToPixel,
    required this.brushScreentoneEnabled,
    required this.brushScreentoneSpacing,
    required this.brushScreentoneDotSize,
    required this.brushScreentoneRotation,
    required this.brushScreentoneSoftness,
    required this.brushScreentoneShape,
    this.hollowStrokeEnabled = false,
    this.hollowStrokeRatio = 0.0,
    this.hollowStrokeEraseOccludedParts = false,
    this.antialiasLevel = 1,
    this.backgroundColorArgb = 0xFFFFFFFF,
    this.usePressure = true,
    this.stylusCurve = 1.0,
    this.streamlineStrength = 0.0,
    this.strokeStabilizerStrength = 0.0,
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
    await _BackendSurfaceWarmupCache.instance.startWarmup(
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
    return _BackendSurfaceWarmupCache.instance.cancelWarmup(
      surfaceId: _surfaceIdForKey(surfaceKey),
    );
  }

  static Future<void> prewarmTextureEngine() {
    return _BackendCanvasSurfaceState.prewarmIfNeeded();
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
  final bool brushSmoothRotationEnabled;
  final int brushRotationSeed;
  final double brushSpacing;
  final double brushHardness;
  final double brushFlow;
  final double brushScatter;
  final double brushRotationJitter;
  final bool brushSnapToPixel;
  final bool brushScreentoneEnabled;
  final double brushScreentoneSpacing;
  final double brushScreentoneDotSize;
  final double brushScreentoneRotation;
  final double brushScreentoneSoftness;
  final BrushShape brushScreentoneShape;
  final bool hollowStrokeEnabled;
  final double hollowStrokeRatio;
  final bool hollowStrokeEraseOccludedParts;
  final int antialiasLevel;
  final int backgroundColorArgb;
  final bool usePressure;
  final double stylusCurve;
  final double streamlineStrength;
  final double strokeStabilizerStrength;
  final VoidCallback? onStrokeBegin;
  final void Function(
    int? handle,
    Size? engineSize,
    bool isNewEngine,
    int? textureId,
  )? onEngineInfoChanged;

  @override
  State<BackendCanvasSurface> createState() => _BackendCanvasSurfaceState();
}

class _BackendCanvasSurfaceState extends State<BackendCanvasSurface> {
  static Future<void>? _prewarmFuture;
  static bool _debugFlagSent = false;

  static Future<void> _ensureBackendDebugFlag() async {
    if (_debugFlagSent || !BackendCanvasLog.enabled) {
      return;
    }
    _debugFlagSent = true;
    try {
      await _backendCanvasChannel.invokeMethod<void>(
        'setDebug',
        <String, Object?>{'enabled': true},
      );
    } catch (_) {}
  }

  int? _textureId;
  int? _engineHandle;
  Size? _engineSize;
  Object? _error;
  late final String _surfaceId;
  int _requestSerial = 0;
  int _activeRequest = 0;

  final _PackedPointBuffer _points = _PackedPointBuffer();
  int? _activeDrawingPointer;
  bool _activeStrokeUsesPressure = true;
  int? _lastNotifiedEngineHandle;
  Size? _lastNotifiedEngineSize;
  int? _lastNotifiedTextureId;
  int? _lastRequestedPresentHandle;

  @override
  void initState() {
    super.initState();
    _surfaceId = _surfaceIdForKey(widget.surfaceKey);
    unawaited(_ensureBackendDebugFlag());
    BackendCanvasLog.info(
      'initState surface=$_surfaceId key=${widget.surfaceKey} '
      'size=${widget.canvasSize.width.round()}x${widget.canvasSize.height.round()} '
      'layers=${widget.layerCount}',
    );
    BackendCanvasTimeline.mark(
      'backendSurface: initState id=$_surfaceId '
      'size=${widget.canvasSize.width}x${widget.canvasSize.height} '
      'layers=${widget.layerCount}',
    );
    unawaited(prewarmIfNeeded());
    unawaited(_loadTextureInfo());
  }

  @override
  void didUpdateWidget(covariant BackendCanvasSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.canvasSize != widget.canvasSize) {
      BackendCanvasLog.info(
        'size changed surface=$_surfaceId '
        'old=${oldWidget.canvasSize.width.round()}x${oldWidget.canvasSize.height.round()} '
        'new=${widget.canvasSize.width.round()}x${widget.canvasSize.height.round()}',
      );
      unawaited(_loadTextureInfo());
    }
    if (oldWidget.layerCount != widget.layerCount) {
      BackendCanvasLog.info(
        'layerCount changed surface=$_surfaceId '
        'old=${oldWidget.layerCount} new=${widget.layerCount}',
      );
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
        oldWidget.brushSmoothRotationEnabled !=
            widget.brushSmoothRotationEnabled ||
        oldWidget.brushRotationSeed != widget.brushRotationSeed ||
        (oldWidget.brushSpacing - widget.brushSpacing).abs() > 1e-6 ||
        (oldWidget.brushHardness - widget.brushHardness).abs() > 1e-6 ||
        (oldWidget.brushFlow - widget.brushFlow).abs() > 1e-6 ||
        (oldWidget.brushScatter - widget.brushScatter).abs() > 1e-6 ||
        (oldWidget.brushRotationJitter - widget.brushRotationJitter).abs() >
            1e-6 ||
        oldWidget.brushSnapToPixel != widget.brushSnapToPixel ||
        oldWidget.brushScreentoneEnabled != widget.brushScreentoneEnabled ||
        (oldWidget.brushScreentoneSpacing - widget.brushScreentoneSpacing)
                .abs() >
            1e-6 ||
        (oldWidget.brushScreentoneDotSize - widget.brushScreentoneDotSize)
                .abs() >
            1e-6 ||
        (oldWidget.brushScreentoneRotation - widget.brushScreentoneRotation)
                .abs() >
            1e-6 ||
        (oldWidget.brushScreentoneSoftness - widget.brushScreentoneSoftness)
                .abs() >
            1e-6 ||
        oldWidget.brushScreentoneShape != widget.brushScreentoneShape ||
        oldWidget.hollowStrokeEnabled != widget.hollowStrokeEnabled ||
        (oldWidget.hollowStrokeRatio - widget.hollowStrokeRatio).abs() > 1e-6 ||
        oldWidget.hollowStrokeEraseOccludedParts !=
            widget.hollowStrokeEraseOccludedParts ||
        (oldWidget.streamlineStrength - widget.streamlineStrength).abs() > 1e-6 ||
        (oldWidget.strokeStabilizerStrength - widget.strokeStabilizerStrength)
                .abs() >
            1e-6;
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
    if (defaultTargetPlatform == TargetPlatform.android) {
      BackendCanvasTimeline.mark('backendSurface: prewarm skipped on Android');
      return;
    }
    try {
      BackendCanvasTimeline.mark('backendSurface: prewarm start');
      const String warmSurfaceId = 'backend_canvas_prewarm';
      await _backendCanvasChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getTextureInfo',
        <String, Object?>{
          'surfaceId': warmSurfaceId,
          'width': 1,
          'height': 1,
          'layerCount': 1,
          'backgroundColorArgb': 0xFFFFFFFF,
        },
      );
      await _backendCanvasChannel.invokeMethod<void>('disposeTexture', <String, Object?>{
        'surfaceId': warmSurfaceId,
      });
      BackendCanvasTimeline.mark('backendSurface: prewarm done');
    } catch (e) {
      BackendCanvasTimeline.mark('backendSurface: prewarm failed $e');
      _prewarmFuture = null; // Allow retry if it failed
    }
  }

  Future<void> _loadTextureInfo() async {
    try {
      final int requestId = ++_requestSerial;
      _activeRequest = requestId;
      final int width = widget.canvasSize.width.round().clamp(1, 16384);
      final int height = widget.canvasSize.height.round().clamp(1, 16384);
      final int? prevTextureId = _textureId;
      final int? prevHandle = _engineHandle;
      final Size? prevEngineSize = _engineSize;
      BackendCanvasLog.info(
        'request req=$requestId size=${width}x$height '
        'layers=${widget.layerCount} id=$_surfaceId '
        'prevTexture=$prevTextureId prevHandle=$prevHandle '
        'prevEngine=${prevEngineSize?.width.round()}x${prevEngineSize?.height.round()}',
      );
      final _BackendSurfaceInfo info =
          await _BackendSurfaceWarmupCache.instance.takeOrRequest(
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
      if (engineWidth != null &&
          engineHeight != null &&
          (engineWidth != width || engineHeight != height)) {
        BackendCanvasLog.warn(
          'engine size mismatch req=${width}x$height '
          'got=${engineWidth}x${engineHeight} surface=$_surfaceId',
        );
      }
      if (!mounted) {
        BackendCanvasLog.warn(
          'request abandoned req=$requestId surface=$_surfaceId mounted=false',
        );
        return;
      }
      if (_activeRequest != requestId) {
        BackendCanvasLog.warn(
          'stale response req=$requestId surface=$_surfaceId '
          'active=$_activeRequest',
        );
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
      final bool textureChanged = prevTextureId != textureId;
      final bool handleChanged = prevHandle != engineHandle;
      final Size? nextSize = _engineSize;
      BackendCanvasLog.info(
        'response req=$requestId surface=$_surfaceId '
        'textureId=$textureId handle=$engineHandle '
        'engine=${engineWidth}x${engineHeight} '
        'newEngine=${info.isNewEngine} warmup=${info.fromWarmup} '
        'changedTexture=$textureChanged changedHandle=$handleChanged '
        'prevEngine=${prevEngineSize?.width.round()}x${prevEngineSize?.height.round()} '
        'nextEngine=${nextSize?.width.round()}x${nextSize?.height.round()}',
      );
      BackendCanvasLog.info(
        'ready textureId=$textureId handle=$engineHandle '
        'engine=${engineWidth}x${engineHeight} '
        'newEngine=${info.isNewEngine} id=$_surfaceId',
      );
      BackendCanvasTimeline.mark(
        'backendSurface: texture ready '
        'textureId=$textureId handle=$engineHandle '
        'engine=${engineWidth}x${engineHeight} '
        'newEngine=${info.isNewEngine} '
        'source=${info.fromWarmup ? 'warmup' : 'direct'}',
      );

      final int? handle = _engineHandle;
      if (handle != null) {
        final bool valid = CanvasBackendFacade.instance.isHandleValid(handle);
        BackendCanvasLog.info('engine handle valid=$valid handle=$handle');
        _applyBrushSettings(handle);
        if (backgroundNeedsUpdate) {
          _applyBackground(handle);
        }
        if (_lastRequestedPresentHandle != handle) {
          CanvasBackendFacade.instance.requestPresent(handle: handle);
          _lastRequestedPresentHandle = handle;
          BackendCanvasLog.info('requestPresent handle=$handle');
        }
      } else {
        BackendCanvasLog.warn(
          'engine handle is null after response surface=$_surfaceId '
          'textureId=$textureId',
        );
      }
      _notifyEngineInfoChanged(isNewEngine: info.isNewEngine);
    } catch (error) {
      if (!mounted) {
        return;
      }
      BackendCanvasLog.warn(
        'request failed surface=$_surfaceId error=$error',
      );
      setState(() {
        _textureId = null;
        _engineHandle = null;
        _engineSize = null;
        _error = error;
      });
      BackendCanvasTimeline.mark(
        'backendSurface: loadTextureInfo error $error',
      );
      _notifyEngineInfoChanged();
    }
  }

  void _notifyEngineInfoChanged({bool isNewEngine = false}) {
    final int? handle = _engineHandle;
    final Size? size = _engineSize;
    final int? textureId = _textureId;
    if (!isNewEngine &&
        _lastNotifiedEngineHandle == handle &&
        _lastNotifiedEngineSize == size &&
        _lastNotifiedTextureId == textureId) {
      return;
    }
    _lastNotifiedEngineHandle = handle;
    _lastNotifiedEngineSize = size;
    _lastNotifiedTextureId = textureId;
    widget.onEngineInfoChanged?.call(handle, size, isNewEngine, textureId);
  }

  @override
  void dispose() {
    BackendCanvasLog.info(
      'dispose surface=$_surfaceId '
      'textureId=$_textureId handle=$_engineHandle '
      'engine=${_engineSize?.width.round()}x${_engineSize?.height.round()}',
    );
    _BackendSurfaceWarmupCache.instance.drop(_surfaceId);
    unawaited(_disposeSurface());
    if (_lastNotifiedEngineHandle != null || _lastNotifiedEngineSize != null) {
      widget.onEngineInfoChanged?.call(null, null, false, null);
    }
    super.dispose();
  }

  Future<void> _disposeSurface() async {
    try {
      BackendCanvasLog.info(
        'disposeTexture surface=$_surfaceId '
        'textureId=$_textureId handle=$_engineHandle',
      );
      await _backendCanvasChannel.invokeMethod<void>('disposeTexture', <String, Object?>{
        'surfaceId': _surfaceId,
      });
      BackendCanvasLog.info('disposeTexture done surface=$_surfaceId');
    } catch (_) {}
  }

  void _applyBackground(int handle) {
    if (!CanvasBackendFacade.instance.isSupported) {
      BackendCanvasLog.warn('applyBackground skipped: backend not supported');
      return;
    }
    BackendCanvasLog.info(
      'applyBackground handle=$handle color=0x${widget.backgroundColorArgb.toRadixString(16)}',
    );
    // Background is represented by layer 0 in the backend compositor.
    CanvasBackendFacade.instance.fillLayer(
      handle: handle,
      layerIndex: 0,
      colorArgb: widget.backgroundColorArgb,
    );
  }

  bool _canSendPoints() {
    return CanvasBackendFacade.instance.isHandleReady(_engineHandle);
  }

  void _applyBrushSettings(int handle, {bool? usePressureOverride}) {
    if (!CanvasBackendFacade.instance.isSupported) {
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
    final double stabilizer =
        mapStrokeStabilizerStrength(widget.strokeStabilizerStrength);
    final int smoothingMode = stabilizer > 0.0001 ? 3 : 1;
    CanvasBackendFacade.instance.setBrush(
      handle: handle,
      colorArgb: widget.brushColorArgb,
      baseRadius: radius,
      usePressure: usePressureOverride ?? widget.usePressure,
      erase: widget.erase,
      antialiasLevel: widget.antialiasLevel,
      brushShape: widget.brushShape.index,
      randomRotation: widget.brushRandomRotationEnabled,
      smoothRotation: widget.brushSmoothRotationEnabled,
      rotationSeed: widget.brushRotationSeed,
      spacing: widget.brushSpacing,
      hardness: widget.brushHardness,
      flow: widget.brushFlow,
      scatter: widget.brushScatter,
      rotationJitter: widget.brushRotationJitter,
      snapToPixel: widget.brushSnapToPixel,
      screentoneEnabled: widget.brushScreentoneEnabled,
      screentoneSpacing: widget.brushScreentoneSpacing,
      screentoneDotSize: widget.brushScreentoneDotSize,
      screentoneRotation: widget.brushScreentoneRotation,
      screentoneSoftness: widget.brushScreentoneSoftness,
      screentoneShape: widget.brushScreentoneShape.index,
      hollow: widget.hollowStrokeEnabled,
      hollowRatio: widget.hollowStrokeRatio,
      hollowEraseOccludedParts: widget.hollowStrokeEraseOccludedParts,
      streamlineStrength: widget.streamlineStrength,
      smoothingMode: smoothingMode,
      stabilizerStrength: stabilizer,
    );
  }

  bool _isDrawingPointer(PointerEvent event) {
    if (TabletInputBridge.instance.isTabletPointer(event)) {
      return true;
    }
    if (event.kind == PointerDeviceKind.touch) {
      return true;
    }
    if (event.kind == PointerDeviceKind.mouse) {
      if (event.buttons == 0) {
        return event.down;
      }
      return (event.buttons & kPrimaryMouseButton) != 0;
    }
    if (event.kind == PointerDeviceKind.unknown) {
      if (event.buttons == 0) {
        return event.down;
      }
      return (event.buttons & kPrimaryMouseButton) != 0 ||
          (event.buttons & kPrimaryStylusButton) != 0;
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
    if (_kDebugBackendCanvasInput) {
      debugPrint(
        '[backend_canvas] down id=${event.pointer} pos=${event.localPosition} pressure=${event.pressure}',
      );
    }
    final bool supportsPressure =
        TabletInputBridge.instance.isTabletPointer(event);
    _activeStrokeUsesPressure = widget.usePressure && supportsPressure;
    _applyBrushSettings(handle, usePressureOverride: _activeStrokeUsesPressure);
    _activeDrawingPointer = event.pointer;
    _enqueuePoint(event, _kPointFlagDown);
    _flushToBackend(handle);
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
        _flushToBackend(handle);
        return;
      }
    } catch (_) {}
    _enqueuePoint(event, _kPointFlagMove);
    _flushToBackend(handle);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_activeDrawingPointer != event.pointer) {
      return;
    }
    if (_kDebugBackendCanvasInput) {
      debugPrint(
        '[backend_canvas] up id=${event.pointer} pos=${event.localPosition}',
      );
    }
    _enqueuePoint(event, _kPointFlagUp);
    final int? handle = _engineHandle;
    if (handle != null) {
      _flushToBackend(handle);
    }
    _activeDrawingPointer = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_activeDrawingPointer != event.pointer) {
      return;
    }
    if (_kDebugBackendCanvasInput) {
      debugPrint(
        '[backend_canvas] cancel id=${event.pointer} pos=${event.localPosition}',
      );
    }
    _enqueuePoint(event, _kPointFlagUp);
    final int? handle = _engineHandle;
    if (handle != null) {
      _flushToBackend(handle);
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

  void _flushToBackend(int handle) {
    final int count = _points.length;
    if (count == 0) {
      return;
    }
    if (_kDebugBackendCanvasInput) {
      final int queued = CanvasBackendFacade.instance.getInputQueueLen(handle);
      debugPrint('[backend_canvas] flush points=$count queued_before=$queued');
    }
    CanvasBackendFacade.instance.pushPointsPacked(
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
              'Canvas backend init failed: $error',
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
