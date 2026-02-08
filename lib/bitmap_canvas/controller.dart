import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
// ignore: unused_import
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';

import '../app/debug/rust_canvas_timeline.dart';
import '../backend/canvas_painting_worker.dart';
import '../backend/canvas_raster_backend.dart';
import '../backend/rgba_utils.dart';
import '../canvas/canvas_layer.dart';
import '../canvas/canvas_settings.dart';
import '../canvas/canvas_tools.dart';
import '../canvas/brush_random_rotation.dart';
import '../canvas/text_renderer.dart';
import '../src/rust/api/bucket_fill.dart' as rust_bucket_fill;
import '../src/rust/api/gpu_brush.dart' as rust_gpu_brush;
import '../src/rust/api/image_ops.dart' as rust_image_ops;
import '../src/rust/rust_init.dart';
import 'bitmap_blend_utils.dart' as blend_utils;
import 'bitmap_canvas.dart';
import 'bitmap_layer_state.dart';
import 'raster_frame.dart';
import 'raster_tile_cache.dart';
import 'raster_int_rect.dart';
import 'soft_brush_profile.dart';
import 'stroke_dynamics.dart';
import 'stroke_pressure_simulator.dart';

export 'bitmap_layer_state.dart';

part 'controller_active_transform.dart';
part 'controller_layer_management.dart';
part 'controller_stroke.dart';
part 'controller_fill.dart';
part 'controller_composite.dart';
part 'controller_paint_commands.dart';
part 'controller_filters.dart';
part 'controller_filters_gpu.dart';
part 'controller_worker_queue.dart';
part 'controller_text.dart';

class BitmapCanvasController extends ChangeNotifier {
  BitmapCanvasController({
    required int width,
    required int height,
    required Color backgroundColor,
    List<CanvasLayerData>? initialLayers,
    CanvasCreationLogic creationLogic = CanvasCreationLogic.multiThread,
    bool enableRasterOutput = true,
  }) : _width = width,
       _height = height,
       _backgroundColor = backgroundColor,
       _isMultithreaded =
           CanvasSettings.supportsMultithreadedCanvas &&
           creationLogic == CanvasCreationLogic.multiThread,
       _rasterOutputEnabled = enableRasterOutput,
       _rasterBackend = CanvasRasterBackend(
         width: width,
         height: height,
       ) {
    if (creationLogic == CanvasCreationLogic.multiThread && !_isMultithreaded) {
      debugPrint('CanvasPaintingWorker 未启用：当前平台不支持多线程画布，已自动回退到单线程。');
    }
    _tileCache = RasterTileCache(
      surfaceWidth: _width,
      surfaceHeight: _height,
      tileSize: _rasterBackend.tileSize,
    );
    if (initialLayers != null && initialLayers.isNotEmpty) {
      _loadFromCanvasLayers(this, initialLayers, backgroundColor);
    } else {
      _initializeDefaultLayers(this, backgroundColor);
    }
    if (_rasterOutputEnabled) {
      _scheduleCompositeRefresh();
    }
  }

  final int _width;
  final int _height;
  Color _backgroundColor;
  final List<BitmapLayerState> _layers = <BitmapLayerState>[];
  int _activeIndex = 0;
  final bool _isMultithreaded;
  bool _rasterOutputEnabled;
  bool _synchronousRasterOverride = false;

  final List<Offset> _currentStrokePoints = <Offset>[];
  final List<double> _currentStrokeRadii = <double>[];
  final List<PaintingDrawCommand> _deferredStrokeCommands =
      <PaintingDrawCommand>[];
  final List<PaintingDrawCommand> _committingStrokes =
      <PaintingDrawCommand>[]; // Strokes being rasterized
  double _currentStrokeRadius = 0;
  double _currentStrokeLastRadius = 0;
  double _currentStrokeSpacing = 0.15;
  double _currentStrokeSoftness = 0.0;
  double _currentStrokeScatter = 0.0;
  double _currentStrokeRotationJitter = 1.0;
  bool _currentStrokeSnapToPixel = false;
  bool _currentStrokeStylusPressureEnabled = false;
  double _currentStylusCurve = 1.0;
  double? _currentStylusLastPressure;
  int _currentStrokeAntialiasLevel = 0;
  bool _currentStrokeHasMoved = false;
  BrushShape _currentBrushShape = BrushShape.circle;
  bool _currentStrokeRandomRotationEnabled = false;
  int _currentStrokeRotationSeed = 0;
  final StrokePressureSimulator _strokePressureSimulator =
      StrokePressureSimulator();
  Color _currentStrokeColor = const Color(0xFF000000);
  bool _currentStrokeEraseMode = false;
  bool _currentStrokeHollowEnabled = false;
  double _currentStrokeHollowRatio = 0.0;
  bool _currentStrokeEraseOccludedParts = false;
  bool _stylusPressureEnabled = true;
  double _stylusCurve = 0.85;
  static const double _kStylusSmoothing = 0.55;
  CanvasPaintingWorker? _paintingWorker;
  _PendingWorkerDrawBatch? _pendingWorkerDrawBatch;
  bool _pendingWorkerDrawScheduled = false;
  final Map<int, PaintingWorkerPatch?> _pendingWorkerPatches =
      <int, PaintingWorkerPatch?>{};
  int _paintingWorkerNextSequence = 0;
  int _paintingWorkerNextApplySequence = 0;
  int _paintingWorkerPendingTasks = 0;
  int _paintingWorkerGeneration = 0;
  final List<Completer<void>> _paintingWorkerIdleWaiters = <Completer<void>>[];
  Completer<void>? _nextFrameCompleter;
  String? _paintingWorkerSyncedLayerId;
  int _paintingWorkerSyncedRevision = -1;
  bool _paintingWorkerSelectionDirty = true;
  final Map<String, int> _gpuBrushSyncedRevisions = <String, int>{};
  Future<void> _gpuBrushQueue = Future<void>.value();

  static const int _kAntialiasCenterWeight = 4;
  static const List<int> _kAntialiasDx = <int>[-1, 0, 1, -1, 1, -1, 0, 1];
  static const List<int> _kAntialiasDy = <int>[-1, -1, -1, 0, 0, 1, 1, 1];
  static const List<int> _kAntialiasWeights = <int>[1, 2, 1, 2, 2, 1, 2, 1];
  static const Map<int, List<double>> _kAntialiasBlendProfiles =
      <int, List<double>>{
        0: <double>[0.25],
        1: <double>[0.35, 0.35],
        2: <double>[0.45, 0.5, 0.5],
        3: <double>[0.6, 0.65, 0.7, 0.75],
        4: <double>[0.6, 0.65, 0.7, 0.75, 0.8],
        5: <double>[0.65, 0.7, 0.75, 0.8, 0.85],
        6: <double>[0.7, 0.75, 0.8, 0.85, 0.9],
        7: <double>[0.7, 0.75, 0.8, 0.85, 0.9, 0.9],
        8: <double>[0.75, 0.8, 0.85, 0.9, 0.9, 0.9],
        9: <double>[0.8, 0.85, 0.9, 0.9, 0.9, 0.9],
      };
  static const double _kEdgeDetectMin = 0.015;
  static const double _kEdgeDetectMax = 0.4;
  static const double _kEdgeSmoothStrength = 1.0;
  static const double _kEdgeSmoothGamma = 0.55;
  static const List<int> _kGaussianKernel5x5 = <int>[
    1,
    4,
    6,
    4,
    1,
    4,
    16,
    24,
    16,
    4,
    6,
    24,
    36,
    24,
    6,
    4,
    16,
    24,
    16,
    4,
    1,
    4,
    6,
    4,
    1,
  ];
  static const int _kGaussianKernel5x5Weight = 256;
  static const int _kMaxWorkerBatchCommands = 24;
  static const int _kMaxWorkerBatchPixels = 512 * 512;

  bool _refreshScheduled = false;
  bool _compositeProcessing = false;
  Uint8List? _selectionMask;
  final CanvasRasterBackend _rasterBackend;
  final CanvasTextRenderer _textRenderer = CanvasTextRenderer();
  late final RasterTileCache _tileCache;
  BitmapCanvasFrame? _currentFrame;
  final List<ui.Image> _pendingTileDisposals = <ui.Image>[];
  bool _tileDisposalScheduled = false;
  Uint32List? _activeLayerTranslationSnapshot;
  String? _activeLayerTranslationId;
  int _activeLayerTranslationDx = 0;
  int _activeLayerTranslationDy = 0;
  int _activeLayerTransformSnapshotWidth = 0;
  int _activeLayerTransformSnapshotHeight = 0;
  int _activeLayerTransformOriginX = 0;
  int _activeLayerTransformOriginY = 0;
  ui.Image? _activeLayerTransformImage;
  bool _activeLayerTransformPreparing = false;
  Rect? _activeLayerTransformBounds;
  Rect? _activeLayerTransformDirtyRegion;
  bool _pendingActiveLayerTransformCleanup = false;
  bool _clipLayerOverflow = false;
  final Map<String, _LayerOverflowStore> _layerOverflowStores =
      <String, _LayerOverflowStore>{};

  Uint32List? get _compositePixels => _rasterBackend.compositePixels;

  String? get _translatingLayerIdForComposite {
    if (_activeLayerTranslationSnapshot != null &&
        !_pendingActiveLayerTransformCleanup &&
        _activeLayerTransformImage != null) {
      return _activeLayerTranslationId;
    }
    return null;
  }

  UnmodifiableListView<BitmapLayerState> get layers =>
      UnmodifiableListView<BitmapLayerState>(_layers);

  bool get isMultithreaded => _isMultithreaded;

  // Active stroke state for client-side prediction
  List<Offset> get activeStrokePoints =>
      UnmodifiableListView(_currentStrokePoints);
  List<double> get activeStrokeRadii =>
      UnmodifiableListView(_currentStrokeRadii);
  List<PaintingDrawCommand> get committingStrokes =>
      UnmodifiableListView(_committingStrokes);
  Color get activeStrokeColor => _currentStrokeColor;
  double get activeStrokeRadius => _currentStrokeRadius;
  BrushShape get activeStrokeShape => _currentBrushShape;
  bool get activeStrokeEraseMode => _currentStrokeEraseMode;
  int get activeStrokeAntialiasLevel => _currentStrokeAntialiasLevel;
  bool get activeStrokeHollowEnabled => _currentStrokeHollowEnabled;
  double get activeStrokeHollowRatio => _currentStrokeHollowRatio;
  bool get activeStrokeEraseOccludedParts => _currentStrokeEraseOccludedParts;
  bool get activeStrokeRandomRotationEnabled => _currentStrokeRandomRotationEnabled;
  int get activeStrokeRotationSeed => _currentStrokeRotationSeed;

  String? get activeLayerId =>
      _layers.isEmpty ? null : _layers[_activeIndex].id;

  BitmapLayerState get activeLayer => _activeLayer;

  void _flushDeferredStrokeCommands() =>
      _controllerFlushDeferredStrokeCommands(this);

  void _flushRealtimeStrokeCommands() =>
      _controllerFlushRealtimeStrokeCommands(this);

  void _commitDeferredStrokeCommandsAsRaster({bool keepStrokeState = false}) =>
      _controllerCommitDeferredStrokeCommandsAsRaster(
        this,
        keepStrokeState: keepStrokeState,
      );

  void _dispatchDirectPaintCommand(PaintingDrawCommand command) =>
      _controllerDispatchDirectPaintCommand(this, command);

  bool get _useWorkerForRaster =>
      _isMultithreaded && !_synchronousRasterOverride;

  Rect? _dirtyRectForCommand(PaintingDrawCommand command) =>
      _controllerDirtyRectForCommand(this, command);

  BitmapCanvasFrame? get frame => _currentFrame;
  bool get rasterOutputEnabled => _rasterOutputEnabled;
  Color get backgroundColor => _backgroundColor;
  int get width => _width;
  int get height => _height;
  Uint8List? get selectionMask => _selectionMask;
  bool get isActiveLayerTransforming => _activeLayerTranslationSnapshot != null;
  ui.Image? get activeLayerTransformImage => _activeLayerTransformImage;
  Offset get activeLayerTransformOffset => Offset(
    (_activeLayerTransformOriginX + _activeLayerTranslationDx).toDouble(),
    (_activeLayerTransformOriginY + _activeLayerTranslationDy).toDouble(),
  );
  Offset get activeLayerTransformOrigin => Offset(
    _activeLayerTransformOriginX.toDouble(),
    _activeLayerTransformOriginY.toDouble(),
  );
  Rect? get activeLayerTransformBounds => _activeLayerTransformBounds;
  double get activeLayerTransformOpacity => _activeLayer.opacity;
  CanvasLayerBlendMode get activeLayerTransformBlendMode =>
      _activeLayer.blendMode;
  bool get isActiveLayerTransformPendingCleanup =>
      _pendingActiveLayerTransformCleanup;

  bool get clipLayerOverflow => _clipLayerOverflow;

  void setLayerOverflowCropping(bool enabled) {
    if (_clipLayerOverflow == enabled) {
      return;
    }
    _clipLayerOverflow = enabled;
  }

  bool get hasVisibleContent {
    for (int i = 0; i < _layers.length; i++) {
      final BitmapLayerState layer = _layers[i];
      if (i == 0) {
        continue;
      }
      if (layer.visible && !_isSurfaceEmpty(layer.surface)) {
        return true;
      }
    }
    return false;
  }

  void _notify() => notifyListeners();

  Future<T> _enqueueGpuBrushTask<T>(Future<T> Function() task) {
    final Future<T> future = _gpuBrushQueue.then((_) => task());
    _gpuBrushQueue = future.then((_) {}, onError: (_, __) {});
    return future;
  }

  void runSynchronousRasterization(VoidCallback action) {
    final bool previous = _synchronousRasterOverride;
    _synchronousRasterOverride = true;
    try {
      action();
    } finally {
      _synchronousRasterOverride = previous;
    }
  }

  void setRasterOutputEnabled(bool enabled) {
    if (_rasterOutputEnabled == enabled) {
      return;
    }
    _rasterOutputEnabled = enabled;
    if (enabled) {
      _scheduleCompositeRefresh();
    }
  }

  void configureStylusPressure({
    required bool enabled,
    required double curve,
  }) => _strokeConfigureStylusPressure(this, enabled: enabled, curve: curve);

  void configureSharpTips({required bool enabled}) =>
      _strokeConfigureSharpTips(this, enabled: enabled);

  void setSelectionMask(Uint8List? mask) => _fillSetSelectionMask(this, mask);

  bool _runAntialiasPass(
    Uint32List src,
    Uint32List dest,
    int width,
    int height,
    double blendFactor,
  ) => _controllerRunAntialiasPass(
    this,
    src,
    dest,
    width,
    height,
    blendFactor,
  );

  bool _runEdgeAwareColorSmoothPass(
    Uint32List src,
    Uint32List dest,
    Uint32List blurBuffer,
    int width,
    int height,
  ) => _controllerRunEdgeAwareColorSmoothPass(
    this,
    src,
    dest,
    blurBuffer,
    width,
    height,
  );

  double _computeEdgeGradient(
    Uint32List src,
    int width,
    int height,
    int x,
    int y,
  ) => _controllerComputeEdgeGradient(src, width, height, x, y);

  double _edgeSmoothWeight(double gradient) =>
      _controllerEdgeSmoothWeight(gradient);

  void _computeGaussianBlur(
    Uint32List src,
    Uint32List dest,
    int width,
    int height,
  ) => _controllerComputeGaussianBlur(src, dest, width, height);

  static double _computeLuma(int color) =>
      _controllerComputeLuma(color);

  static int _lerpArgb(int a, int b, double t) =>
      _controllerLerpArgb(a, b, t);

  void translateActiveLayer(int dx, int dy) =>
      _translateActiveLayer(this, dx, dy);

  void commitActiveLayerTranslation() => _commitActiveLayerTranslation(this);

  void cancelActiveLayerTranslation() => _cancelActiveLayerTranslation(this);

  void disposeActiveLayerTransformSession() =>
      _disposeActiveLayerTransformSession(this);

  Future<ui.Image> snapshotImage() async {
    await _rasterBackend.composite(
      layers: _layers,
      requiresFullSurface: true,
      regions: null,
      translatingLayerId: _translatingLayerIdForComposite,
    );
    final Uint8List rgba = _rasterBackend.copySurfaceRgba();
    return _decodeRgbaImage(rgba, _width, _height);
  }

  Future<void> disposeController() async {
    _tileCache.dispose();
    await _rasterBackend.dispose();
    await _paintingWorker?.dispose();
    _paintingWorker = null;
    _disposePendingTileImages();
    _disposeActiveLayerTransformImage(this);
    _activeLayerTransformPreparing = false;
  }

  void setActiveLayer(String id) => _layerManagerSetActiveLayer(this, id);

  void updateLayerVisibility(String id, bool visible) =>
      _layerManagerUpdateVisibility(this, id, visible);

  void setLayerOpacity(String id, double opacity) =>
      _layerManagerSetOpacity(this, id, opacity);

  void setLayerLocked(String id, bool locked) =>
      _layerManagerSetLocked(this, id, locked);

  void setLayerClippingMask(String id, bool clippingMask) =>
      _layerManagerSetClippingMask(this, id, clippingMask);

  void setLayerBlendMode(String id, CanvasLayerBlendMode mode) =>
      _layerManagerSetBlendMode(this, id, mode);

  void renameLayer(String id, String name) =>
      _layerManagerRenameLayer(this, id, name);

  void addLayer({String? aboveLayerId, String? name}) =>
      _layerManagerAddLayer(this, aboveLayerId: aboveLayerId, name: name);

  Future<String> createTextLayer(
    CanvasTextData data, {
    String? aboveLayerId,
    String? name,
  }) =>
      _textLayerCreate(
        this,
        data,
        aboveLayerId: aboveLayerId,
        name: name,
      );

  Future<void> updateTextLayer(String id, CanvasTextData data) =>
      _textLayerUpdate(this, id, data);

  void rasterizeTextLayer(String id) => _textLayerRasterize(this, id);

  void removeLayer(String id) => _layerManagerRemoveLayer(this, id);

  void reorderLayer(int fromIndex, int toIndex) =>
      _layerManagerReorderLayer(this, fromIndex, toIndex);

  bool mergeLayerDown(String id) => _layerManagerMergeLayerDown(this, id);

  void clear() => _layerManagerClearAll(this);

  void beginStroke(
    Offset position, {
    required Color color,
    required double radius,
    bool simulatePressure = false,
    bool useDevicePressure = false,
    double stylusPressureBlend = 1.0,
    double? pressure,
    double? pressureMin,
    double? pressureMax,
    StrokePressureProfile profile = StrokePressureProfile.auto,
    double? timestampMillis,
    int antialiasLevel = 0,
    BrushShape brushShape = BrushShape.circle,
    bool enableNeedleTips = false,
    bool randomRotation = false,
    int? rotationSeed,
    double spacing = 0.15,
    double hardness = 0.8,
    double flow = 1.0,
    double scatter = 0.0,
    double rotationJitter = 1.0,
    bool snapToPixel = false,
    bool erase = false,
    bool hollow = false,
    double hollowRatio = 0.0,
    bool eraseOccludedParts = false,
  }) => _strokeBegin(
    this,
    position,
    color: color,
    radius: radius,
    simulatePressure: simulatePressure,
    useDevicePressure: useDevicePressure,
    stylusPressureBlend: stylusPressureBlend,
    pressure: pressure,
    pressureMin: pressureMin,
    pressureMax: pressureMax,
    profile: profile,
    timestampMillis: timestampMillis,
    antialiasLevel: antialiasLevel,
    brushShape: brushShape,
    enableNeedleTips: enableNeedleTips,
    randomRotation: randomRotation,
    rotationSeed: rotationSeed,
    spacing: spacing,
    hardness: hardness,
    flow: flow,
    scatter: scatter,
    rotationJitter: rotationJitter,
    snapToPixel: snapToPixel,
    erase: erase,
    hollow: hollow,
    hollowRatio: hollowRatio,
    eraseOccludedParts: eraseOccludedParts,
  );

  void extendStroke(
    Offset position, {
    double? deltaTimeMillis,
    double? timestampMillis,
    double? pressure,
    double? pressureMin,
    double? pressureMax,
  }) => _strokeExtend(
    this,
    position,
    deltaTimeMillis: deltaTimeMillis,
    timestampMillis: timestampMillis,
    pressure: pressure,
    pressureMin: pressureMin,
    pressureMax: pressureMax,
  );

  void endStroke() => _strokeEnd(this);

  void cancelStroke() => _strokeCancel(this);

  void drawFilledPolygon({
    required List<Offset> points,
    required Color color,
    int antialiasLevel = 0,
    bool erase = false,
  }) {
    if (_layers.isEmpty || _activeLayer.locked) {
      return;
    }
    if (points.length < 3) {
      return;
    }
    final PaintingDrawCommand command = PaintingDrawCommand.filledPolygon(
      points: List<Offset>.from(points),
      colorValue: color.value,
      antialiasLevel: antialiasLevel.clamp(0, 9),
      erase: erase,
    );
    _dispatchDirectPaintCommand(command);
  }

  void drawBrushStamp({
    required Offset center,
    required double radius,
    required Color color,
    BrushShape brushShape = BrushShape.circle,
    int antialiasLevel = 0,
    bool erase = false,
    double softness = 0.0,
  }) {
    if (_layers.isEmpty || _activeLayer.locked) {
      return;
    }
    final PaintingDrawCommand command = PaintingDrawCommand.brushStamp(
      center: center,
      radius: radius,
      colorValue: color.value,
      shapeIndex: brushShape.index,
      antialiasLevel: antialiasLevel.clamp(0, 9),
      erase: erase,
      softness: softness.clamp(0.0, 1.0),
    );
    _dispatchDirectPaintCommand(command);
  }

  Future<bool> applyAntialiasToActiveLayer(
    int level, {
    bool previewOnly = false,
  }) =>
      _controllerApplyAntialiasToActiveLayer(
        this,
        level,
        previewOnly: previewOnly,
      );

  void setStrokePressureProfile(StrokePressureProfile profile) =>
      _strokeSetPressureProfile(this, profile);

  double? _normalizeStylusPressure(
    double? pressure,
    double? pressureMin,
    double? pressureMax,
  ) => _strokeNormalizeStylusPressure(this, pressure, pressureMin, pressureMax);

  bool _selectionAllows(Offset position) =>
      _fillSelectionAllows(this, position);

  bool _selectionAllowsInt(int x, int y) => _fillSelectionAllowsInt(this, x, y);

  void floodFill(
    Offset position, {
    required Color color,
    bool contiguous = true,
    bool sampleAllLayers = false,
    List<Color>? swallowColors,
    int tolerance = 0,
    int fillGap = 0,
    int antialiasLevel = 0,
  }) => _fillFloodFill(
    this,
    position,
    color: color,
    contiguous: contiguous,
    sampleAllLayers: sampleAllLayers,
    swallowColors: swallowColors,
    tolerance: tolerance,
    fillGap: fillGap,
    antialiasLevel: antialiasLevel,
  );

  Future<Uint8List?> computeMagicWandMask(
    Offset position, {
    bool sampleAllLayers = true,
    int tolerance = 0,
  }) => _fillComputeMagicWandMask(
    this,
    position,
    sampleAllLayers: sampleAllLayers,
    tolerance: tolerance,
  );

  List<CanvasLayerData> snapshotLayers() => _layerManagerSnapshotLayers(this);
  Future<void> waitForPendingWorkerTasks() async {
    await _waitForPendingWorkerTasks();
    await _gpuBrushQueue;
  }

  CanvasLayerData? buildClipboardLayer(String id, {Uint8List? mask}) =>
      _layerManagerBuildClipboardLayer(this, id, mask: mask);

  void clearLayerRegion(String id, {Uint8List? mask}) =>
      _layerManagerClearRegion(this, id, mask: mask);

  String insertLayerFromData(CanvasLayerData data, {String? aboveLayerId}) =>
      _layerManagerInsertFromData(this, data, aboveLayerId: aboveLayerId);

  void replaceLayer(String id, CanvasLayerData data) =>
      _layerManagerReplaceLayer(this, id, data);

  Rect? restoreLayerRegion(
    CanvasLayerData snapshot,
    Rect region, {
    Uint32List? pixelCache,
    bool markDirty = true,
  }) {
    final int index = _layers.indexWhere((layer) => layer.id == snapshot.id);
    if (index < 0 || region.isEmpty) {
      return null;
    }
    final Rect canvasRect = Rect.fromLTWH(
      0,
      0,
      _width.toDouble(),
      _height.toDouble(),
    );
    Rect target = region.intersect(canvasRect);
    if (target.isEmpty) {
      return null;
    }
    final BitmapLayerState layer = _layers[index];
    final BitmapSurface surface = layer.surface;

    if ((snapshot.rawPixels == null &&
            snapshot.bitmap == null &&
            pixelCache == null) ||
        snapshot.bitmapWidth == null ||
        snapshot.bitmapHeight == null) {
      final Color fill = snapshot.fillColor ?? const Color(0x00000000);
      _fillSurfaceRegion(surface, target, fill);
      surface.markDirty();
      if (markDirty) {
        _markDirty(region: target, layerId: layer.id, pixelsDirty: true);
      }
      return target;
    }

    final int srcWidth = snapshot.bitmapWidth!;
    final int srcHeight = snapshot.bitmapHeight!;
    final int offsetX = snapshot.bitmapLeft ?? 0;
    final int offsetY = snapshot.bitmapTop ?? 0;
    final Rect snapshotRect = Rect.fromLTWH(
      offsetX.toDouble(),
      offsetY.toDouble(),
      srcWidth.toDouble(),
      srcHeight.toDouble(),
    );
    target = target.intersect(snapshotRect);
    if (target.isEmpty) {
      return null;
    }

    final Uint32List srcPixels =
        snapshot.rawPixels ??
        (pixelCache ?? rgbaToPixels(snapshot.bitmap!, srcWidth, srcHeight));

    final int startX = math.max(0, math.max(target.left.floor(), offsetX));
    final int startY = math.max(0, math.max(target.top.floor(), offsetY));
    final int endX = math.min(
      _width,
      math.min(target.right.ceil(), offsetX + srcWidth),
    );
    final int endY = math.min(
      _height,
      math.min(target.bottom.ceil(), offsetY + srcHeight),
    );
    if (startX >= endX || startY >= endY) {
      return null;
    }

    final Uint32List destPixels = surface.pixels;
    final int copyWidth = endX - startX;
    final int copyHeight = endY - startY;
    Uint32List? workerPatch = _isMultithreaded
        ? Uint32List(copyWidth * copyHeight)
        : null;
    int workerOffset = 0;
    for (int y = startY; y < endY; y++) {
      final int srcY = y - offsetY;
      if (srcY < 0 || srcY >= srcHeight) {
        continue;
      }
      final int destOffset = y * _width + startX;
      final int srcOffset = srcY * srcWidth + (startX - offsetX);
      destPixels.setRange(
        destOffset,
        destOffset + copyWidth,
        srcPixels,
        srcOffset,
      );
      if (workerPatch != null) {
        workerPatch.setRange(
          workerOffset,
          workerOffset + copyWidth,
          srcPixels,
          srcOffset,
        );
        workerOffset += copyWidth;
      }
    }
    surface.markDirty();
    final Rect dirtyRegion = Rect.fromLTRB(
      startX.toDouble(),
      startY.toDouble(),
      endX.toDouble(),
      endY.toDouble(),
    );
    if (markDirty) {
      _markDirty(region: dirtyRegion, layerId: layer.id, pixelsDirty: true);
    }
    if (workerPatch != null) {
      unawaited(
        _ensurePaintingWorker().syncSurfacePatch(
          left: startX,
          top: startY,
          width: copyWidth,
          height: copyHeight,
          pixels: workerPatch,
        ),
      );
    }
    return dirtyRegion;
  }

  void _fillSurfaceRegion(BitmapSurface surface, Rect region, Color color) {
    final int startX = math.max(0, region.left.floor());
    final int startY = math.max(0, region.top.floor());
    final int endX = math.min(_width, region.right.ceil());
    final int endY = math.min(_height, region.bottom.ceil());
    if (startX >= endX || startY >= endY) {
      return;
    }
    final int encoded = BitmapSurface.encodeColor(color);
    final Uint32List pixels = surface.pixels;
    for (int y = startY; y < endY; y++) {
      final int offset = y * _width + startX;
      pixels.fillRange(offset, offset + (endX - startX), encoded);
    }
  }

  void loadLayers(List<CanvasLayerData> layers, Color backgroundColor) =>
      _layerManagerLoadLayers(this, layers, backgroundColor);

  void markLayerRegionDirty(String id, Rect region) {
    if (region.isEmpty) {
      return;
    }
    _markDirty(region: region, layerId: id, pixelsDirty: true);
  }

  void _updateComposite({required bool requiresFullSurface, Rect? region}) {
    _compositeUpdate(
      this,
      requiresFullSurface: requiresFullSurface,
      regions: requiresFullSurface || region == null
          ? null
          : <RasterIntRect>[_rasterBackend.clipRectToSurface(region)],
    );
  }

  void _markDirty({Rect? region, String? layerId, bool pixelsDirty = true}) {
    if (pixelsDirty) {
      if (layerId == null) {
        for (final BitmapLayerState layer in _layers) {
          layer.revision += 1;
        }
      } else {
        for (final BitmapLayerState layer in _layers) {
          if (layer.id == layerId) {
            layer.revision += 1;
            break;
          }
        }
      }
    }
    _compositeMarkDirty(
      this,
      region: region,
      layerId: layerId,
      pixelsDirty: pixelsDirty,
    );
  }

  void _scheduleCompositeRefresh() => _compositeScheduleRefresh(this);

  Future<void> _waitForNextFrame() {
    if (_nextFrameCompleter == null || _nextFrameCompleter!.isCompleted) {
      _nextFrameCompleter = Completer<void>();
    }
    return _nextFrameCompleter!.future;
  }

  void _enqueuePaintingWorkerCommand({
    required Rect region,
    required PaintingDrawCommand command,
  }) => _controllerEnqueuePaintingWorkerCommand(this, region, command);

  void _scheduleWorkerDrawFlush({bool forceImmediate = false}) =>
      _controllerScheduleWorkerDrawFlush(this, forceImmediate: forceImmediate);

  void _processPendingWorkerDrawCommands() =>
      _controllerProcessPendingWorkerDrawCommands(this);

  void _flushPendingPaintingCommands() =>
      _controllerFlushPendingPaintingCommands(this);

  Future<void> _waitForPendingWorkerTasks() =>
      _controllerWaitForPendingWorkerTasks(this);

  void _notifyWorkerIdle() => _controllerNotifyWorkerIdle(this);

  void _cancelPendingWorkerTasks() =>
      _controllerCancelPendingWorkerTasks(this);

  CanvasPaintingWorker _ensurePaintingWorker() {
    return _paintingWorker ??= CanvasPaintingWorker();
  }

  Future<void> _ensureWorkerSurfaceSynced() =>
      _controllerEnsureWorkerSurfaceSynced(this);

  Future<void> _ensureWorkerSelectionMaskSynced() =>
      _controllerEnsureWorkerSelectionMaskSynced(this);

  void _resetWorkerSurfaceSync() =>
      _controllerResetWorkerSurfaceSync(this);

  void _enqueueWorkerPatchFuture(
    Future<PaintingWorkerPatch?> future, {
    VoidCallback? onError,
  }) => _controllerEnqueueWorkerPatchFuture(this, future, onError: onError);

  void _processPendingWorkerPatches() =>
      _controllerProcessPendingWorkerPatches(this);

  void _applyWorkerPatch(PaintingWorkerPatch patch) =>
      _controllerApplyWorkerPatch(this, patch);

  int _unpremultiplyChannel(int value, int alpha) =>
      _controllerUnpremultiplyChannel(value, alpha);

  bool _mergeVectorPatchOnMainThread({
    required Uint8List rgbaPixels,
    required int left,
    required int top,
    required int width,
    required int height,
    required bool erase,
    required bool eraseOccludedParts,
  }) => _controllerMergeVectorPatchOnMainThread(
    this,
    rgbaPixels: rgbaPixels,
    left: left,
    top: top,
    width: width,
    height: height,
    erase: erase,
    eraseOccludedParts: eraseOccludedParts,
  );

  void _scheduleTileImageDisposal() =>
      _controllerScheduleTileImageDisposal(this);

  void _flushTileImageDisposals() =>
      _controllerFlushTileImageDisposals(this);

  void _disposePendingTileImages() =>
      _controllerDisposePendingTileImages(this);

  BitmapLayerState get _activeLayer => _layers[_activeIndex];

  BitmapSurface get _activeSurface => _activeLayer.surface;

  static bool _isSurfaceEmpty(BitmapSurface surface) =>
      _controllerIsSurfaceEmpty(surface);

  Color sampleColor(Offset position, {bool sampleAllLayers = true}) =>
      _fillSampleColor(this, position, sampleAllLayers: sampleAllLayers);

  static Uint8List _surfaceToRgba(BitmapSurface surface) =>
      _controllerSurfaceToRgba(surface);

  static Uint32List rgbaToPixels(Uint8List rgba, int width, int height) =>
      _controllerRgbaToPixels(rgba, width, height);

  static Uint8List _pixelsToRgba(Uint32List pixels) =>
      _controllerPixelsToRgba(pixels);

  static Rect _unionRects(Rect a, Rect b) => _controllerUnionRects(a, b);

  static Uint8List _surfaceToMaskedRgba(BitmapSurface surface, Uint8List mask) =>
      _controllerSurfaceToMaskedRgba(surface, mask);

  static bool _maskHasCoverage(Uint8List mask) =>
      _controllerMaskHasCoverage(mask);

  static double _clampUnit(double value) => _controllerClampUnit(value);

  Future<ui.Image> _decodeRgbaImage(Uint8List bytes, int width, int height) =>
      _controllerDecodeRgbaImage(bytes, width, height);

  RasterIntRect _clipRectToSurface(Rect rect) =>
      _controllerClipRectToSurface(this, rect);

  Future<PaintingWorkerPatch?> _executeWorkerDraw({
    required Rect region,
    required List<PaintingDrawCommand> commands,
  }) => _controllerExecuteWorkerDraw(this, region: region, commands: commands);

  void _applyPaintingCommandsSynchronously(
    Rect region,
    List<PaintingDrawCommand> commands,
  ) => _controllerApplyPaintingCommandsSynchronously(
    this,
    region,
    commands,
  );

  void _applyStampSegmentFallback({
    required BitmapSurface surface,
    required Offset start,
    required Offset end,
    required double startRadius,
    required double endRadius,
    required bool includeStart,
    required BrushShape shape,
    required Color color,
    required Uint8List? mask,
    required int antialias,
    required bool erase,
  }) =>
      _controllerApplyStampSegmentFallback(
        surface: surface,
        start: start,
        end: end,
        startRadius: startRadius,
        endRadius: endRadius,
        includeStart: includeStart,
        shape: shape,
        color: color,
        mask: mask,
        antialias: antialias,
        erase: erase,
      );

  Future<PaintingWorkerPatch?> _executeFloodFill({
    required Offset start,
    required Color color,
    Color? targetColor,
    bool contiguous = true,
    int tolerance = 0,
    int fillGap = 0,
    Uint32List? samplePixels,
    Uint32List? swallowColors,
    int antialiasLevel = 0,
  }) => _controllerExecuteFloodFill(
    this,
    start: start,
    color: color,
    targetColor: targetColor,
    contiguous: contiguous,
    tolerance: tolerance,
    fillGap: fillGap,
    samplePixels: samplePixels,
    swallowColors: swallowColors,
    antialiasLevel: antialiasLevel,
  );

  Future<Uint8List?> _executeSelectionMask({
    required Offset start,
    required Uint32List pixels,
    int tolerance = 0,
  }) => _controllerExecuteSelectionMask(
    this,
    start: start,
    pixels: pixels,
    tolerance: tolerance,
  );
}
