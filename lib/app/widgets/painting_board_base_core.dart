part of 'painting_board.dart';

enum _HistoryActionKind { dart, backend }

abstract class _PaintingBoardBaseCore extends State<PaintingBoard> {
  late CanvasFacade _controller;
  _CanvasBackendFacade get _backend => (this as _PaintingBoardBase)._backend;
  final ValueNotifier<int> _mobileUiRevision = ValueNotifier<int>(0);
  final FocusNode _focusNode = FocusNode();
  bool _boardReadyNotified = false;
  int? _backendCanvasEngineHandle;
  Size? _backendCanvasEngineSize;
  int? _backendCanvasTextureId;
  int _backendCanvasSyncedLayerCount = 0;
  final Map<String, Uint32List> _backendLayerSnapshots = <String, Uint32List>{};
  bool _backendLayerSnapshotDirty = false;
  bool _backendLayerSnapshotPendingRestore = false;
  bool _backendLayerSnapshotInFlight = false;
  int _backendLayerSnapshotWidth = 0;
  int _backendLayerSnapshotHeight = 0;
  int? _backendLayerSnapshotHandle;
  int? _backendPixelsSyncedHandle;
  bool _backendPixelsSyncInFlight = false;

  ValueListenable<int> get _mobileUiRebuildListenable => _mobileUiRevision;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _mobileUiRevision.value++;
  }

  @override
  void dispose() {
    _mobileUiRevision.dispose();
    super.dispose();
  }

  CanvasTool _activeTool = CanvasTool.pen;
  bool _isDrawing = false;
  bool _isDraggingBoard = false;
  bool _isRotatingBoard = false;
  bool _isDirty = false;
  bool _isScalingGesture = false;
  final Set<int> _activeTouchPointers = <int>{};
  int? _primaryTouchPointer;
  bool _touchIgnoreUntilAllUp = false;
  int? _pendingTouchStrokePointer;
  Offset? _pendingTouchStrokeStart;
  Duration? _pendingTouchStrokeTimestamp;
  PointerDownEvent? _pendingTouchStrokeEvent;
  bool _pixelGridVisible = false;
  bool _viewBlackWhiteOverlay = false;
  bool _viewMirrorOverlay = false;
  bool _viewTiledCanvas = false;
  double _scaleGestureInitialScale = 1.0;
  double _scaleGestureInitialRotation = 0.0;
  Offset? _scaleGestureAnchorBoardLocal;
  int _scaleGestureStartEpochMs = 0;
  int _scaleGestureMaxPointerCount = 0;
  double _scaleGestureAccumulatedFocalDistance = 0.0;
  double _scaleGestureMaxScaleDelta = 0.0;
  double _scaleGestureMaxRotationDelta = 0.0;
  int _twoFingerLastTapEpochMs = 0;
  double _penStrokeWidth = _defaultPenStrokeWidth;
  double _sprayStrokeWidth = _defaultSprayStrokeWidth;
  double _eraserStrokeWidth = _defaultEraserStrokeWidth;
  SprayMode _sprayMode = AppPreferences.defaultSprayMode;
  double _strokeStabilizerStrength =
      AppPreferences.defaultStrokeStabilizerStrength;
  double _streamlineStrength = AppPreferences.defaultStreamlineStrength;
  bool _simulatePenPressure = false;
  bool _touchDrawingEnabled = AppPreferences.defaultTouchDrawingEnabled;
  int _penAntialiasLevel = AppPreferences.defaultPenAntialiasLevel;
  CanvasTool _applePencilLastNonEraserTool = CanvasTool.pen;
  int _bucketAntialiasLevel = AppPreferences.defaultBucketAntialiasLevel;
  bool _stylusPressureEnabled = AppPreferences.defaultStylusPressureEnabled;
  double _stylusCurve = AppPreferences.defaultStylusCurve;
  bool _autoSharpPeakEnabled = AppPreferences.defaultAutoSharpPeakEnabled;
  BrushShape _brushShape = AppPreferences.defaultBrushShape;
  String _brushShapeId = 'circle';
  BrushShapeRaster? _brushShapeRaster;
  String? _backendBrushMaskId;
  int _backendBrushMaskWidth = 0;
  int _backendBrushMaskHeight = 0;
  bool _brushRandomRotationEnabled =
      AppPreferences.defaultBrushRandomRotationEnabled;
  bool _brushSmoothRotationEnabled = false;
  final math.Random _brushRotationRandom = math.Random();
  int _brushRandomRotationPreviewSeed = 0;
  BrushLibrary? _brushLibrary;
  BrushPreset? _activeBrushPreset;
  double _brushSpacing = 0.15;
  double _brushHardness = 0.8;
  double _brushFlow = 1.0;
  double _brushScatter = 0.0;
  double _brushRotationJitter = 1.0;
  bool _brushSnapToPixel = false;
  bool _brushScreentoneEnabled = false;
  double _brushScreentoneSpacing = 10.0;
  double _brushScreentoneDotSize = 0.6;
  double _brushScreentoneRotation = 45.0;
  double _brushScreentoneSoftness = 0.0;
  BrushShape _brushScreentoneShape = BrushShape.circle;
  bool _hollowStrokeEnabled = AppPreferences.defaultHollowStrokeEnabled;
  double _hollowStrokeRatio = AppPreferences.defaultHollowStrokeRatio;
  bool _hollowStrokeEraseOccludedParts =
      AppPreferences.defaultHollowStrokeEraseOccludedParts;
  PenStrokeSliderRange _penStrokeSliderRange =
      AppPreferences.defaultPenStrokeSliderRange;
  PenStrokeSliderRange _sprayStrokeSliderRange =
      AppPreferences.defaultSprayStrokeSliderRange;
  PenStrokeSliderRange _eraserStrokeSliderRange =
      AppPreferences.defaultEraserStrokeSliderRange;
  bool _bucketSampleAllLayers = false;
  bool _bucketContiguous = true;
  bool _bucketSwallowColorLine = AppPreferences.defaultBucketSwallowColorLine;
  BucketSwallowColorLineMode _bucketSwallowColorLineMode =
      AppPreferences.defaultBucketSwallowColorLineMode;
  int _bucketTolerance = AppPreferences.defaultBucketTolerance;
  int _bucketFillGap = AppPreferences.defaultBucketFillGap;
  int _magicWandTolerance = AppPreferences.defaultMagicWandTolerance;
  bool _brushToolsEraserMode = AppPreferences.defaultBrushToolsEraserMode;
  bool _shapeFillEnabled = AppPreferences.defaultShapeToolFillEnabled;
  bool _layerAdjustCropOutside = false;
  bool _layerOpacityGestureActive = false;
  String? _layerOpacityGestureLayerId;
  double? _layerOpacityUndoOriginalValue;
  String? _layerOpacityPreviewLayerId;
  double? _layerOpacityPreviewValue;
  bool _layerOpacityPreviewActive = false;
  int _layerOpacityPreviewRequestId = 0;
  int? _layerOpacityPreviewAwaitedGeneration;
  int? _layerOpacityPreviewCapturedSignature;
  bool _layerOpacityPreviewHasVisibleLowerLayers = false;
  ui.Image? _layerOpacityPreviewBackground;
  ui.Image? _layerOpacityPreviewActiveLayerImage;
  ui.Image? _layerOpacityPreviewForeground;
  final Map<String, _LayerPreviewCacheEntry> _layerPreviewCache =
      <String, _LayerPreviewCacheEntry>{};
  int _layerPreviewRequestSerial = 0;
  final Map<String, int> _backendLayerPreviewRevisions = <String, int>{};
  final Set<String> _backendLayerPreviewPending = <String>{};
  int _backendLayerPreviewSerial = 0;
  bool _backendLayerPreviewRefreshScheduled = false;
  bool _spacePanOverrideActive = false;
  bool _isLayerDragging = false;
  bool _layerAdjustBackendSynced = false;
  bool _layerAdjustUsingBackendPreview = false;
  String? _layerAdjustBackendPreviewLayerId;
  String? _layerAdjustBackendHiddenLayerId;
  bool _layerAdjustBackendHiddenVisible = false;
  String? _layerTransformBackendHiddenLayerId;
  bool _layerTransformBackendHiddenVisible = false;
  Future<void>? _layerAdjustFinalizeTask;
  Offset? _layerDragStart;
  int _layerDragAppliedDx = 0;
  int _layerDragAppliedDy = 0;
  final math.Random _syntheticStrokeRandom = math.Random();
  Offset? _curveAnchor;
  Offset? _curvePendingEnd;
  Offset? _curveDragOrigin;
  Offset _curveDragDelta = Offset.zero;
  bool _isCurvePlacingSegment = false;
  Path? _curvePreviewPath;
  CanvasLayerData? _curveRasterPreviewSnapshot;
  bool _curveUndoCapturedForPreview = false;
  Rect? _curvePreviewDirtyRect;
  Uint32List? _curveRasterPreviewPixels;
  ui.Image? _curvePreviewRasterImage;
  int _curvePreviewRasterToken = 0;
  ui.Image? _shapePreviewRasterImage;
  int _shapePreviewRasterToken = 0;
  String? _backendVectorPreviewHiddenLayerId;
  bool _backendVectorPreviewHiddenLayerVisible = false;
  int _backendVectorPreviewHideToken = 0;
  bool _isEyedropperSampling = false;
  bool _eyedropperOverrideActive = false;
  Offset? _lastEyedropperSample;
  Offset? _toolCursorPosition;
  Offset? _lastWorkspacePointer;
  Offset? _penCursorWorkspacePosition;
  final Set<int> _activeStylusPointers = <int>{};
  int _lastStylusContactEpochMs = 0;
  StreamSubscription<void>? _pencilDoubleTapSubscription;
  Duration? _lastPenSampleTimestamp;
  bool _activeStrokeUsesStylus = false;
  double? _activeStylusPressureMin;
  double? _activeStylusPressureMax;
  double? _lastStylusPressureValue;
  Offset? _lastStrokeBoardPosition;
  Offset? _lastBrushLineAnchor;
  Offset? _lastStylusDirection;
  final _StrokeStabilizer _strokeStabilizer = _StrokeStabilizer();
  bool _isSpraying = false;
  bool _backendSprayActive = false;
  bool _backendSprayHasDrawn = false;
  Offset? _sprayBoardPosition;
  Ticker? _sprayTicker;
  Duration? _sprayTickerTimestamp;
  double _sprayEmissionAccumulator = 0.0;
  double _sprayCurrentPressure = 1.0;
  KritaSprayEngine? _kritaSprayEngine;
  Color? _activeSprayColor;
  Offset? _softSprayLastPoint;
  double _softSprayResidual = 0.0;
  Size _toolSettingsCardSize = const Size(320, _toolbarButtonSize);
  CanvasToolbarLayout _toolbarLayout = const CanvasToolbarLayout(
    columns: 1,
    rows: CanvasToolbar.buttonCount,
    width: CanvasToolbar.buttonSize,
    height:
        CanvasToolbar.buttonSize * CanvasToolbar.buttonCount +
        CanvasToolbar.spacing * (CanvasToolbar.buttonCount - 1),
  );
  List<Rect> _toolbarHitRegions = const <Rect>[];
  BoardLayoutWorker? _layoutWorker;
  BoardLayoutMetrics? _layoutMetrics;
  Future<BoardLayoutMetrics>? _pendingLayoutTask;

  final CanvasViewport _viewport = CanvasViewport();
  bool _viewportInitialized = false;
  Size _workspaceSize = Size.zero;
  Offset _layoutBaseOffset = Offset.zero;
  bool _workspaceMeasurementScheduled = false;
  final ScrollController _layerScrollController = ScrollController();
  late final ValueNotifier<CanvasViewInfo> _viewInfoNotifier;
  bool _viewInfoNotificationScheduled = false;
  CanvasViewInfo? _pendingViewInfo;
  Color _primaryColor = AppPreferences.defaultPrimaryColor;
  late HSVColor _primaryHsv;

  bool get _brushShapeSupportsBackend {
    final BrushLibrary? library = _brushLibrary;
    final BrushShapeLibrary shapes =
        library?.shapeLibrary ?? BrushLibrary.instance.shapeLibrary;
    if (shapes.isBuiltInId(_brushShapeId)) {
      return true;
    }
    return _brushShapeRaster != null && _brushShapeRaster!.id == _brushShapeId;
  }

  String _shapeIdForBrush(BrushShape shape) {
    switch (shape) {
      case BrushShape.circle:
        return 'circle';
      case BrushShape.triangle:
        return 'triangle';
      case BrushShape.square:
        return 'square';
      case BrushShape.star:
        return 'star';
    }
  }

  /// 颜色更新后由颜色面板调用的钩子，子类/混入可以覆写以响应颜色变化。
  @protected
  void _handlePrimaryColorChanged() {}
  @protected
  void _handleTextStrokeColorChanged(Color color) {}
  void _updateBrushToolsEraserMode(bool value) {
    if (_brushToolsEraserMode == value) {
      return;
    }
    setState(() => _brushToolsEraserMode = value);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.brushToolsEraserMode = value;
    unawaited(AppPreferences.save());
  }

  @protected
  void _notifyBoardReadyIfNeeded();
  final List<Color> _recentColors = <Color>[];
  final List<Color> _mobileRecentFallbackColors = <Color>[];
  Color _colorLineColor = AppPreferences.defaultColorLineColor;
  final List<_CanvasHistoryEntry> _undoStack = <_CanvasHistoryEntry>[];
  final List<_CanvasHistoryEntry> _redoStack = <_CanvasHistoryEntry>[];
  final List<_HistoryActionKind> _historyUndoStack = <_HistoryActionKind>[];
  final List<_HistoryActionKind> _historyRedoStack = <_HistoryActionKind>[];
  bool _historyLocked = false;
  int _historyLimit = AppPreferences.instance.historyLimit;
  bool? _menuUndoEnabled;
  bool? _menuRedoEnabled;
  final List<_PaletteCardEntry> _paletteCards = <_PaletteCardEntry>[];
  int _paletteCardSerial = 0;
  bool _referenceCardResizeInProgress = false;
  double? _floatingColorPanelHeight;
  double? _floatingColorPanelMeasuredHeight;
  double? _sai2ColorPanelHeight;
  double? _sai2ColorPanelMeasuredHeight;
  double _sai2ToolSectionRatio = AppPreferences.defaultSai2ToolPanelSplit;
  double _sai2LayerPanelWidthRatio = AppPreferences.defaultSai2LayerPanelSplit;

  Future<bool> insertImageLayerFromBytes(
    Uint8List bytes, {
    String? name,
    int? svgRasterSizePx,
  });

  bool get _includeHistoryOnToolbar => false;

  int get _toolbarButtonCount =>
      CanvasToolbar.buttonCount +
      (_includeHistoryOnToolbar ? CanvasToolbar.historyButtonCount : 0);

  bool _isInsidePaletteCardArea(Offset workspacePosition) {
    for (final _PaletteCardEntry entry in _paletteCards) {
      final Size size = entry.size ?? const Size(_paletteCardWidth, 180.0);
      final Rect rect = Rect.fromLTWH(
        entry.offset.dx,
        entry.offset.dy,
        size.width,
        size.height,
      );
      if (rect.contains(workspacePosition)) {
        return true;
      }
    }
    return false;
  }

  bool _isInsideReferenceCardArea(Offset workspacePosition);

  bool _isInsideReferenceModelCardArea(Offset workspacePosition);

  bool _isInsideAntialiasCardArea(Offset workspacePosition);

  bool _isInsideColorRangeCardArea(Offset workspacePosition);

  bool _isInsideWorkspacePanelArea(Offset workspacePosition) {
    return _isInsidePaletteCardArea(workspacePosition) ||
        _isInsideReferenceCardArea(workspacePosition) ||
        _isInsideReferenceModelCardArea(workspacePosition) ||
        _isInsideAntialiasCardArea(workspacePosition) ||
        _isInsideColorRangeCardArea(workspacePosition);
  }

  // 透视辅助线相关成员由 _PaintingBoardPerspectiveMixin 提供。
  PerspectiveGuideMode get _perspectiveMode;
  bool get _perspectiveEnabled;
  bool get _perspectiveVisible;
  double get _perspectiveHorizonY;
  Offset get _perspectiveVp1;
  Offset? get _perspectiveVp2;
  Offset? get _perspectiveVp3;
  double get _perspectiveSnapAngleTolerance;
  _PerspectiveHandle? get _activePerspectiveHandle;
  _PerspectiveHandle? get _hoveringPerspectiveHandle;
  void togglePerspectiveGuide();
  void setPerspectiveMode(PerspectiveGuideMode mode);
  void _resetPerspectiveLock();
  void _updatePerspectiveHover(Offset boardLocal);
  void _clearPerspectiveHover();
  Offset _maybeSnapToPerspective(Offset position, {Offset? anchor});
  bool _handlePerspectivePointerDown(
    Offset boardLocal, {
    bool allowNearest = false,
  });
  bool get _isDraggingPerspectiveHandle;
  void _handlePerspectivePointerMove(Offset boardLocal);
  void _handlePerspectivePointerUp();

  void _clearLayerTransformCursorIndicator() {}

  Size get _canvasSize => widget.settings.size;

  Size get _scaledBoardSize => Size(
    _canvasSize.width * _viewport.scale,
    _canvasSize.height * _viewport.scale,
  );

  Color get _pixelGridColor => const ui.Color.fromARGB(255, 133, 133, 133);

  bool _isWithinCanvasBounds(Offset position) {
    final Size size = _canvasSize;
    return position.dx >= 0 &&
        position.dy >= 0 &&
        position.dx <= size.width &&
        position.dy <= size.height;
  }

  Offset _clampToCanvas(Offset value) {
    final Size size = _canvasSize;
    final double dx = value.dx.clamp(0.0, size.width);
    final double dy = value.dy.clamp(0.0, size.height);
    return Offset(dx, dy);
  }

  void _applyStylusSettingsToController() {
    _controller.configureStylusPressure(
      enabled: _stylusPressureEnabled,
      curve: _stylusCurve,
    );
    _controller.configureSharpTips(enabled: _autoSharpPeakEnabled);
  }

  void _markDirty() {
    if (_isDirty) {
      return;
    }
    _isDirty = true;
    widget.onDirtyChanged?.call(true);
  }

  CanvasLayerInfo? _activeLayerStateForBackendSync() {
    final String? activeId = _controller.activeLayerId;
    if (activeId == null) {
      return null;
    }
    for (final CanvasLayerInfo layer in _controller.layers) {
      if (layer.id == activeId) {
        return layer;
      }
    }
    return null;
  }

  bool _syncLayerPixelsFromBackend(CanvasLayerInfo layer) {
    if (!_backend.isReady) {
      return false;
    }
    final _LayerPixels? sourceLayer = _backend.readLayerPixelsFromBackend(
      layer.id,
    );
    if (sourceLayer == null) {
      return false;
    }
    final Size? surfaceSize = _controller.readLayerSurfaceSize(layer.id);
    if (surfaceSize == null ||
        surfaceSize.width.round() != sourceLayer.width ||
        surfaceSize.height.round() != sourceLayer.height) {
      return false;
    }
    return _controller.writeLayerPixels(
      layer.id,
      sourceLayer.pixels,
      markDirty: false,
    );
  }

  bool _syncActiveLayerPixelsFromBackend() {
    final CanvasLayerInfo? layer = _activeLayerStateForBackendSync();
    if (layer == null) {
      return false;
    }
    return _syncLayerPixelsFromBackend(layer);
  }

  bool _syncAllLayerPixelsFromBackend() {
    if (!_backend.isReady) {
      return false;
    }
    final List<CanvasLayerInfo> layers = _controller.layers;
    if (layers.isEmpty) {
      return true;
    }
    bool allOk = true;
    for (final CanvasLayerInfo layer in layers) {
      if (!_syncLayerPixelsFromBackend(layer)) {
        allOk = false;
      }
    }
    return allOk;
  }

  bool _commitActiveLayerToBackend({bool recordUndo = true}) {
    if (!_backend.isReady) {
      return false;
    }
    final CanvasLayerInfo? layer = _activeLayerStateForBackendSync();
    if (layer == null) {
      return false;
    }
    if (_backendCanvasLayerIndexForId(layer.id) == null) {
      return false;
    }
    final Size engineSize = _backendCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return false;
    }
    final Size? surfaceSize = _controller.readLayerSurfaceSize(layer.id);
    if (surfaceSize == null ||
        surfaceSize.width.round() != width ||
        surfaceSize.height.round() != height) {
      return false;
    }
    final Uint32List? pixels = _controller.readLayerPixels(layer.id);
    if (pixels == null || pixels.length != width * height) {
      return false;
    }
    return _backend.writeLayerPixelsToBackend(
      layerId: layer.id,
      pixels: pixels,
      recordUndo: recordUndo,
      recordHistory: true,
      markDirty: true,
    );
  }

  bool _syncAllLayerPixelsToBackend({bool recordUndo = false}) {
    if (!_backend.isReady) {
      return false;
    }
    final Size engineSize = _backendCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return false;
    }
    final List<CanvasLayerInfo> layers = _controller.layers;
    bool allOk = true;
    for (int i = 0; i < layers.length; i++) {
      final CanvasLayerInfo layer = layers[i];
      final Size? surfaceSize = _controller.readLayerSurfaceSize(layer.id);
      if (surfaceSize == null ||
          surfaceSize.width.round() != width ||
          surfaceSize.height.round() != height) {
        allOk = false;
        continue;
      }
      final Uint32List? pixels = _controller.readLayerPixels(layer.id);
      if (pixels == null || pixels.length != width * height) {
        allOk = false;
        continue;
      }
      final bool applied = _backend.writeLayerPixelsToBackend(
        layerId: layer.id,
        pixels: pixels,
        recordUndo: recordUndo,
        recordHistory: false,
        markDirty: false,
      );
      if (!applied) {
        allOk = false;
        continue;
      }
      _bumpBackendLayerPreviewRevision(layer.id);
    }
    return allOk;
  }

  List<_SyntheticStrokeSample> _buildSyntheticStrokeSamples(
    List<Offset> points,
    Offset initialPoint,
  ) {
    if (points.isEmpty) {
      return const <_SyntheticStrokeSample>[];
    }
    final List<_SyntheticStrokeSample> pending = <_SyntheticStrokeSample>[];
    double totalDistance = 0.0;
    Offset previous = initialPoint;
    for (final Offset point in points) {
      final double distance = (point - previous).distance;
      if (distance < 0.001) {
        previous = point;
        continue;
      }
      pending.add(
        _SyntheticStrokeSample(point: point, distance: distance, progress: 0.0),
      );
      totalDistance += distance;
      previous = point;
    }
    if (pending.isEmpty) {
      return const <_SyntheticStrokeSample>[];
    }
    if (totalDistance <= 0.0001) {
      final int count = pending.length;
      for (int i = 0; i < count; i++) {
        final _SyntheticStrokeSample sample = pending[i];
        pending[i] = _SyntheticStrokeSample(
          point: sample.point,
          distance: sample.distance,
          progress: (i + 1) / count,
        );
      }
      return pending;
    }
    double cumulative = 0.0;
    for (int i = 0; i < pending.length; i++) {
      final _SyntheticStrokeSample sample = pending[i];
      cumulative += sample.distance;
      pending[i] = _SyntheticStrokeSample(
        point: sample.point,
        distance: sample.distance,
        progress: (cumulative / totalDistance).clamp(0.0, 1.0),
      );
    }
    return pending;
  }

  void _emitSyntheticStrokeTimeline(
    List<_SyntheticStrokeSample> samples, {
    required double totalDistance,
    required double initialTimestamp,
    _SyntheticStrokeTimelineStyle style = _SyntheticStrokeTimelineStyle.natural,
    required void Function(
      _SyntheticStrokeSample sample,
      double timestamp,
      double deltaTime,
    )
    onSample,
  }) {
    if (samples.isEmpty) {
      return;
    }
    final bool useFastCurveStyle =
        style == _SyntheticStrokeTimelineStyle.fastCurve;
    final double effectiveDistance = totalDistance > 0.0001
        ? totalDistance
        : samples.length.toDouble();
    double targetDuration = _syntheticStrokeTargetDuration(
      effectiveDistance,
    ).clamp(160.0, 720.0);
    if (useFastCurveStyle) {
      targetDuration *= 0.62;
    }
    final double durationJitter =
        ui.lerpDouble(0.85, 1.25, _syntheticStrokeRandom.nextDouble()) ?? 1.0;
    targetDuration *= durationJitter;
    final double minimumTimeline = samples.length * _syntheticStrokeMinDeltaMs;
    final double resolvedDuration = math.max(targetDuration, minimumTimeline);
    final List<double> weights = <double>[];
    double totalWeight = 0.0;
    for (final _SyntheticStrokeSample sample in samples) {
      final double baseSpeed = _syntheticStrokeSpeedFactor(
        sample.progress,
        _penPressureProfile,
      );
      final double styleScale = _syntheticTimelineSpeedScale(
        sample.progress,
        style,
      );
      final double speed = math.max(baseSpeed * styleScale, 0.05);
      final double jitter =
          ui.lerpDouble(0.82, 1.24, _syntheticStrokeRandom.nextDouble()) ?? 1.0;
      final double normalizedDistance = math.max(sample.distance, 0.02) / speed;
      final double weight = math.max(0.001, normalizedDistance * jitter);
      weights.add(weight);
      totalWeight += weight;
    }
    if (totalWeight <= 0.0001) {
      totalWeight = samples.length.toDouble();
      for (int i = 0; i < weights.length; i++) {
        weights[i] = 1.0;
      }
    }
    final double scale = resolvedDuration / totalWeight;
    double timestamp = initialTimestamp;
    for (int i = 0; i < samples.length; i++) {
      final double deltaTime = math.max(
        _syntheticStrokeMinDeltaMs,
        weights[i] * scale,
      );
      timestamp += deltaTime;
      onSample(samples[i], timestamp, deltaTime);
    }
  }

  void _simulateStrokeWithSyntheticTimeline(
    List<_SyntheticStrokeSample> samples, {
    required double totalDistance,
    required double initialTimestamp,
    _SyntheticStrokeTimelineStyle style = _SyntheticStrokeTimelineStyle.natural,
  }) {
    _emitSyntheticStrokeTimeline(
      samples,
      totalDistance: totalDistance,
      initialTimestamp: initialTimestamp,
      style: style,
      onSample: (sample, timestamp, deltaTime) {
        _controller.extendStroke(
          sample.point,
          deltaTimeMillis: deltaTime,
          timestampMillis: timestamp,
        );
      },
    );
  }

  double _syntheticStrokeTotalDistance(List<_SyntheticStrokeSample> samples) {
    double total = 0.0;
    for (final _SyntheticStrokeSample sample in samples) {
      total += sample.distance;
    }
    return total;
  }

  /// Adds an optional speed bias so synthetic strokes can mimic a faster
  /// flick, which emphasises the contrast between slow and fast segments.
  double _syntheticTimelineSpeedScale(
    double progress,
    _SyntheticStrokeTimelineStyle style,
  ) {
    if (style == _SyntheticStrokeTimelineStyle.natural) {
      return 1.0;
    }
    final double normalized = progress.clamp(0.0, 1.0);
    final double sine = math.sin(normalized * math.pi).abs();
    final double eased = math.pow(sine, 0.78).toDouble().clamp(0.0, 1.0);
    final double scale = ui.lerpDouble(0.24, 4.25, eased) ?? 1.0;
    return scale.clamp(0.24, 4.25);
  }

  double _syntheticStrokeTargetDuration(double totalDistance) {
    final double normalized = (totalDistance / 320.0).clamp(0.0, 1.0);
    return ui.lerpDouble(200.0, 500.0, normalized) ?? 320.0;
  }

  double _syntheticStrokeSpeedFactor(
    double progress,
    StrokePressureProfile profile,
  ) {
    final double normalized = progress.clamp(0.0, 1.0);
    final double fromCenter = (normalized - 0.5).abs() * 2.0;
    switch (profile) {
      case StrokePressureProfile.taperEnds:
        return ui.lerpDouble(2.8, 0.38, fromCenter) ?? 1.0;
      case StrokePressureProfile.taperCenter:
        return ui.lerpDouble(0.42, 2.6, fromCenter) ?? 1.0;
      case StrokePressureProfile.auto:
        final double sine = math.sin(normalized * math.pi).abs();
        final double blend = ui.lerpDouble(1.8, 0.55, sine) ?? 1.0;
        final double edgeBias = ui.lerpDouble(1.1, 0.75, fromCenter) ?? 1.0;
        return blend * edgeBias;
    }
  }

  List<Offset> _densifyStrokePolyline(
    List<Offset> points, {
    double maxSegmentLength = 6.0,
  }) {
    if (points.length < 2) {
      return List<Offset>.from(points);
    }
    final double spacing = maxSegmentLength.clamp(0.8, 24.0);
    final List<Offset> dense = <Offset>[points.first];
    for (int i = 1; i < points.length; i++) {
      final Offset from = dense.last;
      final Offset to = points[i];
      final double segmentLength = (to - from).distance;
      if (segmentLength <= spacing + 1e-3) {
        dense.add(to);
        continue;
      }
      final int segments = math.max(1, (segmentLength / spacing).ceil());
      for (int s = 1; s <= segments; s++) {
        final double t = s / segments;
        final double x = ui.lerpDouble(from.dx, to.dx, t) ?? to.dx;
        final double y = ui.lerpDouble(from.dy, to.dy, t) ?? to.dy;
        dense.add(Offset(x, y));
      }
    }
    return dense;
  }

  void _refreshStylusPreferencesIfNeeded() {
    final AppPreferences prefs = AppPreferences.instance;
    const double epsilon = 0.0001;
    final bool needsUpdate =
        _stylusPressureEnabled != prefs.stylusPressureEnabled ||
        (_stylusCurve - prefs.stylusPressureCurve).abs() > epsilon;
    if (!needsUpdate) {
      return;
    }
    _stylusPressureEnabled = prefs.stylusPressureEnabled;
    _stylusCurve = prefs.stylusPressureCurve;
    if (mounted) {
      _applyStylusSettingsToController();
    }
  }

  Offset _baseOffsetForScale(double scale) {
    final Size workspace = _workspaceSize;
    if (workspace.width <= 0 ||
        workspace.height <= 0 ||
        !workspace.width.isFinite ||
        !workspace.height.isFinite) {
      return Offset.zero;
    }

    final double scaledWidth = _canvasSize.width * scale;
    final double scaledHeight = _canvasSize.height * scale;

    final double rawLeft = (workspace.width - scaledWidth) / 2;
    final double rawTop = (workspace.height - scaledHeight) / 2;

    final double left = rawLeft.isFinite ? rawLeft : 0.0;
    final double top = rawTop.isFinite ? rawTop : 0.0;

    return Offset(left, top);
  }

  void _updateToolSettingsCardSize(Size size) {
    final double width = size.width.isFinite && size.width > 0
        ? size.width
        : _toolSettingsCardSize.width;
    final double height = size.height.isFinite && size.height > 0
        ? size.height
        : _toolSettingsCardSize.height;
    if ((width - _toolSettingsCardSize.width).abs() < 0.5 &&
        (height - _toolSettingsCardSize.height).abs() < 0.5) {
      return;
    }
    _toolSettingsCardSize = Size(width, height);
  }

  void _scheduleWorkspaceMeasurement(BuildContext context) {
    if (_workspaceMeasurementScheduled) {
      return;
    }
    _workspaceMeasurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _workspaceMeasurementScheduled = false;
      if (!mounted) {
        return;
      }
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        return;
      }
      final Size size = box.size;
      if (size.width <= 0 ||
          size.height <= 0 ||
          !size.width.isFinite ||
          !size.height.isFinite) {
        return;
      }
      final bool widthChanged = (size.width - _workspaceSize.width).abs() > 0.5;
      final bool heightChanged =
          (size.height - _workspaceSize.height).abs() > 0.5;
      if (!widthChanged && !heightChanged) {
        return;
      }
      setState(() {
        _workspaceSize = size;
        final double reservedColorSpace =
            _colorIndicatorSize + CanvasToolbar.spacing;
        _toolbarLayout = CanvasToolbar.layoutForAvailableHeight(
          _workspaceSize.height - _toolButtonPadding * 2 - reservedColorSpace,
          toolCount: _toolbarButtonCount,
        );
        _layoutMetrics = null;
        if (!_viewportInitialized) {
          // 仍需初始化视口，下一帧会根据新尺寸完成初始化
        }
        _scheduleLayoutMetricsUpdate();
      });
    });
  }

  BoardLayoutWorker _layoutWorkerInstance() {
    return _layoutWorker ??= BoardLayoutWorker();
  }

  void _scheduleLayoutMetricsUpdate() {
    if (!mounted) {
      return;
    }
    final BoardLayoutInput input = BoardLayoutInput(
      workspaceWidth: _workspaceSize.width,
      workspaceHeight: _workspaceSize.height,
      toolButtonPadding: _toolButtonPadding,
      toolSettingsSpacing: _toolSettingsSpacing,
      sidePanelWidth: _sidePanelWidth,
      colorIndicatorSize: _colorIndicatorSize,
      toolbarButtonCount: _toolbarButtonCount,
    );
    final Future<BoardLayoutMetrics> task = _layoutWorkerInstance().compute(
      input,
    );
    _pendingLayoutTask = task;
    task
        .then((BoardLayoutMetrics metrics) {
          if (!mounted || _pendingLayoutTask != task) {
            return;
          }
          setState(() {
            _layoutMetrics = metrics;
            _toolbarLayout = metrics.layout;
          });
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('Layout worker failed: $error');
        });
  }

  void _applyToolbarLayout(CanvasToolbarLayout layout) {
    if (_toolbarLayout.columns == layout.columns &&
        (_toolbarLayout.height - layout.height).abs() < 0.5 &&
        (_toolbarLayout.width - layout.width).abs() < 0.5) {
      return;
    }
    setState(() {
      _toolbarLayout = layout;
      _layoutMetrics = null;
      _scheduleLayoutMetricsUpdate();
    });
  }

  void _ensureToolbarDoesNotOverlapColorIndicator() {
    if (_toolbarHitRegions.length < 3) {
      return;
    }
    final Rect toolbarRect = _toolbarHitRegions[0];
    final Rect colorRect = _toolbarHitRegions[2];
    final double gap = colorRect.top - toolbarRect.bottom;
    final double fullAvailableHeight =
        _workspaceSize.height - _toolButtonPadding * 2 - _colorIndicatorSize;
    final double safeAvailableHeight =
        fullAvailableHeight - CanvasToolbar.spacing;
    if (!safeAvailableHeight.isFinite || safeAvailableHeight <= 0) {
      return;
    }
    if (gap >= CanvasToolbar.spacing) {
      if (_toolbarLayout.isMultiColumn) {
        final CanvasToolbarLayout candidate =
            CanvasToolbar.layoutForAvailableHeight(
              safeAvailableHeight,
              toolCount: _toolbarButtonCount,
            );
        if (candidate.columns == 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            _applyToolbarLayout(candidate);
          });
        }
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final CanvasToolbarLayout wrappedLayout =
          CanvasToolbar.layoutForAvailableHeight(
            safeAvailableHeight,
            toolCount: _toolbarButtonCount,
          );
      _applyToolbarLayout(wrappedLayout);
    });
  }

  CanvasToolbarLayout _resolveToolbarLayoutForStyle(
    PaintingToolbarLayoutStyle style,
    CanvasToolbarLayout base, {
    required bool includeHistoryButtons,
  }) {
    if (style != PaintingToolbarLayoutStyle.sai2) {
      return base;
    }
    const int targetColumns = 4;
    final double availableWidth = math.max(0, _sidePanelWidth - 32);
    final double totalSpacing = CanvasToolbar.spacing * (targetColumns - 1);
    final double maxExtent = targetColumns > 0
        ? (availableWidth - totalSpacing) / targetColumns
        : CanvasToolbar.buttonSize;
    final double buttonExtent = maxExtent.isFinite && maxExtent > 0
        ? maxExtent.clamp(36.0, CanvasToolbar.buttonSize)
        : CanvasToolbar.buttonSize;
    final int toolCount =
        CanvasToolbar.buttonCount +
        (includeHistoryButtons ? CanvasToolbar.historyButtonCount : 0);
    final int rows = math.max(1, (toolCount / targetColumns).ceil());
    final double width = targetColumns * buttonExtent + totalSpacing;
    final double height =
        rows * buttonExtent + (rows - 1) * CanvasToolbar.spacing;
    return CanvasToolbarLayout(
      columns: targetColumns,
      rows: rows,
      width: width,
      height: height,
      buttonExtent: buttonExtent,
      horizontalFlow: true,
      flowDirection: Axis.horizontal,
    );
  }

  Rect get _boardRect {
    final Offset position = _layoutBaseOffset + _viewport.offset;
    final Size size = _scaledBoardSize;
    return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  }

  Offset _toBoardLocal(Offset workspacePosition) {
    final Rect boardRect = _boardRect;
    final double rotation = _viewport.rotation;
    Offset relative = workspacePosition - boardRect.topLeft;

    if (rotation != 0) {
      final Offset center = boardRect.size.center(Offset.zero);
      final double dx = relative.dx - center.dx;
      final double dy = relative.dy - center.dy;
      final double cosA = math.cos(-rotation);
      final double sinA = math.sin(-rotation);

      final double rotatedDx = dx * cosA - dy * sinA;
      final double rotatedDy = dx * sinA + dy * cosA;

      relative = Offset(rotatedDx + center.dx, rotatedDy + center.dy);
    }
    return relative / _viewport.scale;
  }

  Offset? _boardCursorPosition() {
    final Offset? workspacePointer = _lastWorkspacePointer;
    if (workspacePointer == null) {
      return null;
    }
    final Rect boardRect = _boardRect;
    if (!boardRect.contains(workspacePointer)) {
      return null;
    }
    return _toBoardLocal(workspacePointer);
  }

  CanvasViewInfo _buildViewInfo() {
    return CanvasViewInfo(
      canvasSize: _canvasSize,
      scale: _viewport.scale,
      cursorPosition: _boardCursorPosition(),
      pixelGridVisible: _pixelGridVisible,
      viewBlackWhiteEnabled: _viewBlackWhiteOverlay,
      viewMirrorEnabled: _viewMirrorOverlay,
      viewTiledEnabled: _viewTiledCanvas,
      perspectiveMode: _perspectiveMode,
      perspectiveEnabled: _perspectiveEnabled,
      perspectiveVisible: _perspectiveVisible,
    );
  }

  void _notifyViewInfoChanged() {
    final CanvasViewInfo next = _buildViewInfo();
    if (_viewInfoNotifier.value == next) {
      return;
    }
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    final bool safeToUpdateNow =
        phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks;
    if (safeToUpdateNow) {
      _viewInfoNotifier.value = next;
      _pendingViewInfo = null;
      return;
    }
    _pendingViewInfo = next;
    if (_viewInfoNotificationScheduled) {
      return;
    }
    _viewInfoNotificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewInfoNotificationScheduled = false;
      if (!mounted) {
        _pendingViewInfo = null;
        return;
      }
      final CanvasViewInfo? pending = _pendingViewInfo;
      _pendingViewInfo = null;
      if (pending != null && _viewInfoNotifier.value != pending) {
        _viewInfoNotifier.value = pending;
      }
    });
  }

  ValueListenable<CanvasViewInfo> get viewInfoListenable => _viewInfoNotifier;

  void _handleBackendCanvasEngineInfoChanged(
    int? handle,
    Size? engineSize,
    bool isNewEngine,
    int? textureId,
  ) {
    final bool textureChanged = _backendCanvasTextureId != textureId;
    if (textureChanged) {
      _backendCanvasTextureId = textureId;
      if (_viewTiledCanvas && mounted) {
        setState(() {});
      }
    }
    final int? prevHandle = _backendCanvasEngineHandle;
    final Size? prevSize = _backendCanvasEngineSize;
    final bool handleChanged = _backendCanvasEngineHandle != handle;
    final bool sizeChanged = _backendCanvasEngineSize != engineSize;
    final bool engineReset = handleChanged || sizeChanged || isNewEngine;
    if ((handleChanged || isNewEngine) && handle != null) {
      final String sizeText = engineSize == null
          ? 'null'
          : '${engineSize.width.round()}x${engineSize.height.round()}';
      BackendCanvasTimeline.mark(
        'paintingBoard: backend engine handle=$handle '
        'size=$sizeText newEngine=$isNewEngine',
      );
    }
    if (engineReset) {
      final String sizeText = engineSize == null
          ? 'null'
          : '${engineSize.width.round()}x${engineSize.height.round()}';
      final String prevSizeText = prevSize == null
          ? 'null'
          : '${prevSize.width.round()}x${prevSize.height.round()}';
      BackendCanvasLog.info(
        'engine info surfaceKey=${widget.surfaceKey} '
        'handle=$handle prevHandle=$prevHandle '
        'size=$sizeText prevSize=$prevSizeText newEngine=$isNewEngine',
      );
      if (kDebugMode &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          handle != null) {
        final bool valid = CanvasBackendFacade.instance.isHandleValid(handle);
        BackendCanvasLog.info('engine handle valid=$valid');
      }
    }
    if (engineReset) {
      _backendCanvasSyncedLayerCount = 0;
      _backendPixelsSyncedHandle = null;
      _backendPixelsSyncInFlight = false;
      _purgeBackendHistoryActions();
      _backendLayerSnapshotDirty = false;
      if (_backendLayerSnapshots.isNotEmpty) {
        _backendLayerSnapshotPendingRestore = true;
      }
      _backendLayerPreviewRevisions.clear();
      _backendLayerPreviewPending.clear();
      _backendLayerPreviewSerial = 0;
      _backendLayerPreviewRefreshScheduled = false;
    }
    _backendCanvasEngineHandle = handle;
    _backendCanvasEngineSize = engineSize;
    _syncBackendCanvasLayersToEngine();
    _syncBackendCanvasViewFlags();
    _syncBackendBrushMask(force: true);
    _restoreBackendLayerSnapshotIfNeeded();
    _syncBackendCanvasPixelsIfNeeded();
    _notifyBoardReadyIfNeeded();
  }

  int? _backendCanvasLayerIndexForId(String layerId) {
    final int index = _controller.layers.indexWhere(
      (CanvasLayerInfo layer) => layer.id == layerId,
    );
    if (index < 0) {
      return null;
    }
    return index;
  }

  bool get _isBackendVectorPreviewActive =>
      _curvePreviewRasterImage != null || _shapePreviewRasterImage != null;

  Uint8List _argbPixelsToRgbaForPreview(Uint32List pixels) {
    final Uint8List rgba = Uint8List(pixels.length * 4);
    for (int i = 0; i < pixels.length; i++) {
      final int argb = pixels[i];
      final int offset = i * 4;
      rgba[offset] = (argb >> 16) & 0xff;
      rgba[offset + 1] = (argb >> 8) & 0xff;
      rgba[offset + 2] = argb & 0xff;
      rgba[offset + 3] = (argb >> 24) & 0xff;
    }
    return rgba;
  }

  void _hideBackendLayerForVectorPreview(String layerId) {
    if (!_backend.isReady) {
      return;
    }
    if (_backendVectorPreviewHiddenLayerId == layerId) {
      return;
    }
    _restoreBackendLayerAfterVectorPreview();
    final int token = ++_backendVectorPreviewHideToken;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (!mounted || token != _backendVectorPreviewHideToken) {
        return;
      }
      if (!_isBackendVectorPreviewActive) {
        return;
      }
      final CanvasLayerInfo layer = _controller.activeLayer;
      if (layer.id != layerId || !layer.visible) {
        return;
      }
      final int? index = _backendCanvasLayerIndexForId(layerId);
      if (index == null) {
        return;
      }
      _backendVectorPreviewHiddenLayerId = layerId;
      _backendVectorPreviewHiddenLayerVisible = layer.visible;
      _backend.setBackendLayerVisibleByIndex(layerIndex: index, visible: false);
    });
  }

  void _restoreBackendLayerAfterVectorPreview() {
    _backendVectorPreviewHideToken++;
    final String? layerId = _backendVectorPreviewHiddenLayerId;
    if (layerId == null) {
      return;
    }
    if (_backend.isReady) {
      final int? index = _backendCanvasLayerIndexForId(layerId);
      if (index != null) {
        _backend.setBackendLayerVisibleByIndex(
          layerIndex: index,
          visible: _backendVectorPreviewHiddenLayerVisible,
        );
      }
    }
    _backendVectorPreviewHiddenLayerId = null;
    _backendVectorPreviewHiddenLayerVisible = false;
  }

  bool get _useCombinedHistory => true;

  void _syncHistoryMenuAvailability() {
    final bool canUndo = _useCombinedHistory
        ? _historyUndoStack.isNotEmpty
        : _undoStack.isNotEmpty;
    final bool canRedo = _useCombinedHistory
        ? _historyRedoStack.isNotEmpty
        : _redoStack.isNotEmpty;
    bool changed = false;
    if (_menuUndoEnabled != canUndo) {
      _menuUndoEnabled = canUndo;
      changed = true;
    }
    if (_menuRedoEnabled != canRedo) {
      _menuRedoEnabled = canRedo;
      changed = true;
    }
    if (changed) {
      MenuActionDispatcher.instance.refresh();
    }
  }

  void _recordDartHistoryAction() {
    _recordHistoryAction(_HistoryActionKind.dart);
  }

  void _recordBackendHistoryAction({
    String? layerId,
    bool deferPreview = false,
  }) {
    _backendLayerSnapshotDirty = true;
    _recordHistoryAction(_HistoryActionKind.backend);
    if (layerId == null) {
      return;
    }
    if (deferPreview) {
      _scheduleBackendLayerPreviewRefresh(layerId);
    } else {
      _bumpBackendLayerPreviewRevision(layerId);
    }
  }

  void _bumpBackendLayerPreviewRevision(String layerId) {
    _backendLayerPreviewSerial += 1;
    _backendLayerPreviewRevisions[layerId] = _backendLayerPreviewSerial;
  }

  void _scheduleBackendLayerPreviewRefresh(String layerId) {
    if (!_backend.supportsInputQueue) {
      return;
    }
    _backendLayerPreviewPending.add(layerId);
    if (_backendLayerPreviewRefreshScheduled) {
      return;
    }
    _backendLayerPreviewRefreshScheduled = true;
    unawaited(_runBackendLayerPreviewRefresh());
  }

  Future<void> _runBackendLayerPreviewRefresh() async {
    while (mounted && _backendLayerPreviewPending.isNotEmpty) {
      final int? handle = _backendCanvasEngineHandle;
      if (!_backend.supportsInputQueue || handle == null) {
        _backendLayerPreviewPending.clear();
        break;
      }
      final int queued = _backend.getInputQueueLen(handle: handle) ?? 0;
      if (queued > 0) {
        await Future.delayed(const Duration(milliseconds: 16));
        continue;
      }
      await Future.delayed(const Duration(milliseconds: 16));
      final List<String> pending = _backendLayerPreviewPending.toList(
        growable: false,
      );
      _backendLayerPreviewPending.clear();
      for (final String layerId in pending) {
        _bumpBackendLayerPreviewRevision(layerId);
      }
      if (mounted) {
        setState(() {});
      }
    }
    _backendLayerPreviewRefreshScheduled = false;
  }

  void _recordHistoryAction(_HistoryActionKind action) {
    if (!_useCombinedHistory) {
      return;
    }
    _historyUndoStack.add(action);
    _historyRedoStack.clear();
    _redoStack.clear();
    _trimHistoryActionStacks();
    _syncHistoryMenuAvailability();
  }

  _HistoryActionKind? _peekHistoryUndoAction() {
    if (!_useCombinedHistory || _historyUndoStack.isEmpty) {
      return null;
    }
    return _historyUndoStack.last;
  }

  _HistoryActionKind? _peekHistoryRedoAction() {
    if (!_useCombinedHistory || _historyRedoStack.isEmpty) {
      return null;
    }
    return _historyRedoStack.last;
  }

  _HistoryActionKind? _commitHistoryUndoAction() {
    if (!_useCombinedHistory || _historyUndoStack.isEmpty) {
      return null;
    }
    final _HistoryActionKind action = _historyUndoStack.removeLast();
    _historyRedoStack.add(action);
    _trimHistoryActionStacks();
    _syncHistoryMenuAvailability();
    return action;
  }

  _HistoryActionKind? _commitHistoryRedoAction() {
    if (!_useCombinedHistory || _historyRedoStack.isEmpty) {
      return null;
    }
    final _HistoryActionKind action = _historyRedoStack.removeLast();
    _historyUndoStack.add(action);
    _trimHistoryActionStacks();
    _syncHistoryMenuAvailability();
    return action;
  }

  void _trimHistoryActionStacks() {
    if (!_useCombinedHistory) {
      return;
    }
    while (_historyUndoStack.length > _historyLimit) {
      _historyUndoStack.removeAt(0);
    }
    while (_historyRedoStack.length > _historyLimit) {
      _historyRedoStack.removeAt(0);
    }
  }

  void _purgeBackendHistoryActions() {
    if (!_useCombinedHistory) {
      return;
    }
    _historyUndoStack.removeWhere(
      (_HistoryActionKind action) => action == _HistoryActionKind.backend,
    );
    _historyRedoStack.removeWhere(
      (_HistoryActionKind action) => action == _HistoryActionKind.backend,
    );
    _syncHistoryMenuAvailability();
  }

  void _syncBackendCanvasViewFlags() {
    if (!_backend.isReady) {
      return;
    }
    _backend.setViewFlags(
      mirror: _viewMirrorOverlay,
      blackWhite: _viewBlackWhiteOverlay,
    );
  }

  Uint8List? _buildBackendBrushMask(BrushShapeRaster raster) {
    final int width = raster.width;
    final int height = raster.height;
    if (width <= 0 || height <= 0) {
      return null;
    }
    final int count = width * height;
    if (raster.alpha.length != count || raster.softAlpha.length != count) {
      return null;
    }
    final Uint8List packed = Uint8List(count * 2);
    int out = 0;
    for (int i = 0; i < count; i++) {
      packed[out++] = raster.alpha[i];
      packed[out++] = raster.softAlpha[i];
    }
    return packed;
  }

  void _syncBackendBrushMask({bool force = false}) {
    final BrushShapeRaster? raster = _brushShapeRaster;
    final bool hasCustom = raster != null && raster.id == _brushShapeId;
    if (!hasCustom) {
      _backendBrushMaskId = null;
      _backendBrushMaskWidth = 0;
      _backendBrushMaskHeight = 0;
      if (_backend.isReady) {
        _backend.clearBrushMask();
      }
      return;
    }
    if (!_backend.isReady) {
      return;
    }
    if (!force &&
        _backendBrushMaskId == raster!.id &&
        _backendBrushMaskWidth == raster.width &&
        _backendBrushMaskHeight == raster.height) {
      return;
    }
    final Uint8List? mask = _buildBackendBrushMask(raster);
    if (mask == null || mask.isEmpty) {
      _backendBrushMaskId = null;
      _backendBrushMaskWidth = 0;
      _backendBrushMaskHeight = 0;
      _backend.clearBrushMask();
      return;
    }
    _backend.setBrushMask(
      width: raster.width,
      height: raster.height,
      mask: mask,
    );
    _backendBrushMaskId = raster.id;
    _backendBrushMaskWidth = raster.width;
    _backendBrushMaskHeight = raster.height;
  }

  void _syncBackendCanvasPixelsIfNeeded() {
    if (!_backend.isReady) {
      return;
    }
    if (_backendLayerSnapshotPendingRestore) {
      return;
    }
    if (_backendLayerSnapshotDirty) {
      return;
    }
    if (_backendLayerSnapshots.isNotEmpty) {
      return;
    }
    final int handle = _backendCanvasEngineHandle!;
    if (_backendPixelsSyncedHandle == handle) {
      return;
    }
    if (_backendPixelsSyncInFlight) {
      return;
    }
    _backendPixelsSyncInFlight = true;
    BackendCanvasLog.info(
      'sync backend pixels start surfaceKey=${widget.surfaceKey} '
      'handle=$handle prevSynced=$_backendPixelsSyncedHandle '
      'layers=${_controller.layers.length}',
    );
    Future<void>(() async {
      final bool ok = await _syncAllLayerPixelsToBackendAsync();
      if (!mounted) {
        return;
      }
      _backendPixelsSyncInFlight = false;
      if (ok && _backendCanvasEngineHandle == handle) {
        _backendPixelsSyncedHandle = handle;
        BackendCanvasLog.info(
          'sync backend pixels ok surfaceKey=${widget.surfaceKey} '
          'handle=$handle',
        );
      } else {
        BackendCanvasLog.warn(
          'sync backend pixels failed surfaceKey=${widget.surfaceKey} '
          'handle=$handle',
        );
      }
    });
  }

  Future<bool> _syncAllLayerPixelsToBackendAsync({
    bool recordUndo = false,
  }) async {
    if (!_backend.isReady) {
      return false;
    }
    final Size engineSize = _backendCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return false;
    }
    final List<CanvasLayerInfo> layers = _controller.layers;
    bool allOk = true;
    for (int i = 0; i < layers.length; i++) {
      if (!mounted) {
        return false;
      }
      final CanvasLayerInfo layer = layers[i];
      final Size? surfaceSize = _controller.readLayerSurfaceSize(layer.id);
      if (surfaceSize == null ||
          surfaceSize.width.round() != width ||
          surfaceSize.height.round() != height) {
        allOk = false;
        continue;
      }
      final Uint32List? pixels = _controller.readLayerPixels(layer.id);
      if (pixels == null || pixels.length != width * height) {
        allOk = false;
        continue;
      }
      final bool queued = _backend.queueLayerPixelsToBackend(
        layerId: layer.id,
        pixels: pixels,
        recordUndo: recordUndo,
      );
      if (!queued) {
        allOk = false;
        continue;
      }
      _bumpBackendLayerPreviewRevision(layer.id);
      await Future<void>.delayed(Duration.zero);
    }
    return allOk;
  }

  Future<void> _captureBackendLayerSnapshotIfNeeded() async {
    if (!_backend.isReady) {
      return;
    }
    if (!_backendLayerSnapshotDirty || _backendLayerSnapshotInFlight) {
      return;
    }
    final Size engineSize = _backendCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return;
    }
    _backendLayerSnapshotInFlight = true;
    bool allOk = true;
    final Map<String, Uint32List> next = <String, Uint32List>{};
    final List<CanvasLayerInfo> layers = _controller.layers;
    for (int i = 0; i < layers.length; i++) {
      final _LayerPixels? layerPixels = _backend.readLayerPixelsFromBackend(
        layers[i].id,
      );
      if (layerPixels == null) {
        allOk = false;
        continue;
      }
      next[layers[i].id] = layerPixels.pixels;
    }
    if (next.isNotEmpty) {
      _backendLayerSnapshots
        ..clear()
        ..addAll(next);
      _backendLayerSnapshotWidth = width;
      _backendLayerSnapshotHeight = height;
      _backendLayerSnapshotHandle = _backendCanvasEngineHandle;
      _backendLayerSnapshotPendingRestore = true;
      if (allOk) {
        _backendLayerSnapshotDirty = false;
      }
    }
    _backendLayerSnapshotInFlight = false;
    if (mounted && widget.isActive) {
      _restoreBackendLayerSnapshotIfNeeded();
    }
  }

  void _restoreBackendLayerSnapshotIfNeeded() {
    if (!_backendLayerSnapshotPendingRestore) {
      return;
    }
    if (_backendLayerSnapshotInFlight) {
      return;
    }
    if (!_backend.isReady) {
      return;
    }
    if (_backendLayerSnapshots.isEmpty) {
      _backendLayerSnapshotPendingRestore = false;
      _backendLayerSnapshotHandle = null;
      return;
    }
    final Size engineSize = _backendCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width != _backendLayerSnapshotWidth ||
        height != _backendLayerSnapshotHeight) {
      _backendLayerSnapshots.clear();
      _backendLayerSnapshotPendingRestore = false;
      _backendLayerSnapshotDirty = false;
      _backendLayerSnapshotHandle = null;
      return;
    }
    final List<CanvasLayerInfo> layers = _controller.layers;
    for (int i = 0; i < layers.length; i++) {
      final Uint32List? pixels = _backendLayerSnapshots[layers[i].id];
      if (pixels == null) {
        continue;
      }
      _backend.writeLayerPixelsToBackend(
        layerId: layers[i].id,
        pixels: pixels,
        recordUndo: false,
        recordHistory: false,
        markDirty: false,
      );
      _bumpBackendLayerPreviewRevision(layers[i].id);
    }
    _backendLayerSnapshotPendingRestore = false;
    _backendLayerSnapshotHandle = _backendCanvasEngineHandle;
  }

  void _showBackendCanvasMessage(String message) {
    if (!mounted) {
      return;
    }
    AppNotifications.show(
      context,
      message: message,
      severity: InfoBarSeverity.warning,
    );
  }

  void _syncBackendCanvasLayersToEngine() {
    if (!_backend.isReady) {
      return;
    }
    final List<CanvasLayerInfo> layers = _controller.layers;
    final int currentCount = layers.length;
    final String? hiddenAdjustId = _layerAdjustBackendHiddenLayerId;
    final String? hiddenTransformId = _layerTransformBackendHiddenLayerId;
    final int? hiddenAdjustIndex = hiddenAdjustId == null
        ? null
        : _backendCanvasLayerIndexForId(hiddenAdjustId);
    final int? hiddenTransformIndex = hiddenTransformId == null
        ? null
        : _backendCanvasLayerIndexForId(hiddenTransformId);
    for (int i = 0; i < currentCount; i++) {
      final CanvasLayerInfo layer = layers[i];
      final bool hideForAdjust =
          (hiddenAdjustIndex != null && hiddenAdjustIndex == i) ||
          (hiddenTransformIndex != null && hiddenTransformIndex == i);
      _backend.setBackendLayerVisibleByIndex(
        layerIndex: i,
        visible: hideForAdjust ? false : layer.visible,
      );
      _backend.setBackendLayerOpacityByIndex(
        layerIndex: i,
        opacity: layer.opacity,
      );
      _backend.setBackendLayerClippingByIndex(
        layerIndex: i,
        clippingMask: layer.clippingMask,
      );
      _backend.setBackendLayerBlendModeByIndex(
        layerIndex: i,
        blendMode: layer.blendMode,
      );
    }
    for (int i = currentCount; i < _backendCanvasSyncedLayerCount; i++) {
      _backend.setBackendLayerVisibleByIndex(layerIndex: i, visible: false);
      _backend.setBackendLayerOpacityByIndex(layerIndex: i, opacity: 1.0);
      _backend.setBackendLayerClippingByIndex(
        layerIndex: i,
        clippingMask: false,
      );
      _backend.setBackendLayerBlendModeByIndex(
        layerIndex: i,
        blendMode: CanvasLayerBlendMode.normal,
      );
      _backend.clearBackendLayerByIndex(layerIndex: i);
    }
    _backendCanvasSyncedLayerCount = currentCount;

    final String? activeLayerId = _controller.activeLayerId;
    int? activeIndex = activeLayerId != null
        ? _backendCanvasLayerIndexForId(activeLayerId)
        : null;
    if (activeIndex == null && layers.isNotEmpty) {
      activeIndex = layers.length - 1;
      final String fallbackLayerId = layers[activeIndex].id;
      if (fallbackLayerId != activeLayerId) {
        _controller.setActiveLayer(fallbackLayerId);
      }
    }
    if (activeIndex != null) {
      _backend.setBackendActiveLayerByIndex(layerIndex: activeIndex);
    }
  }

  void _backendCanvasSetActiveLayerById(String layerId) {
    _backend.setBackendActiveLayerById(layerId);
  }

  void _backendCanvasSetLayerVisibleById(String layerId, bool visible) {
    _backend.setBackendLayerVisible(layerId: layerId, visible: visible);
  }

  void _backendCanvasSetLayerClippingById(String layerId, bool clippingMask) {
    _backend.setBackendLayerClippingById(
      layerId: layerId,
      clippingMask: clippingMask,
    );
  }

  void _backendCanvasSetLayerOpacityById(String layerId, double opacity) {
    _backend.setBackendLayerOpacityById(layerId: layerId, opacity: opacity);
  }

  void _backendCanvasSetLayerBlendModeById(
    String layerId,
    CanvasLayerBlendMode blendMode,
  ) {
    _backend.setBackendLayerBlendModeById(
      layerId: layerId,
      blendMode: blendMode,
    );
  }

  CanvasTool get activeTool => _activeTool;
  CanvasTool get _effectiveActiveTool {
    if (_eyedropperOverrideActive) {
      return CanvasTool.eyedropper;
    }
    if (_spacePanOverrideActive) {
      return CanvasTool.hand;
    }
    return _activeTool;
  }

  bool get _isReferenceCardResizing => _referenceCardResizeInProgress;

  bool get _cursorRequiresOverlay =>
      ToolCursorStyles.hasOverlay(_effectiveActiveTool);

  bool get _penRequiresOverlay =>
      _effectiveActiveTool == CanvasTool.pen ||
      _effectiveActiveTool == CanvasTool.spray ||
      _effectiveActiveTool == CanvasTool.curvePen ||
      _effectiveActiveTool == CanvasTool.shape ||
      _effectiveActiveTool == CanvasTool.eraser ||
      _effectiveActiveTool == CanvasTool.selectionPen;

  bool get _isBrushEraserEnabled =>
      _brushToolsEraserMode || _activeTool == CanvasTool.eraser;

  CanvasBackend get canvasBackend => _controller.rasterBackend;
  bool get hasContent => _controller.hasVisibleContent;
  bool get isDirty => _isDirty;
}

final class _LayerPixels {
  const _LayerPixels({
    required this.pixels,
    required this.width,
    required this.height,
  });

  final Uint32List pixels;
  final int width;
  final int height;
}

final class _CanvasRasterEditSession {
  _CanvasRasterEditSession._(
    this._backend, {
    required this.useBackend,
    required this.ok,
  });

  final _CanvasBackendFacade _backend;
  final bool useBackend;
  final bool ok;

  Future<bool> commit({
    bool waitForPending = false,
    bool warnIfFailed = false,
    bool recordUndo = true,
  }) async {
    if (!ok || !useBackend) {
      return ok;
    }
    return _backend.commitActiveLayerToBackend(
      waitForPending: waitForPending,
      warnIfFailed: warnIfFailed,
      recordUndo: recordUndo,
    );
  }
}

final class _CanvasBackendFacade implements CanvasBackendInterface {
  _CanvasBackendFacade(this._owner);

  final _PaintingBoardBase _owner;
  final CanvasBackendFacade _ffi = CanvasBackendFacade.instance;
  static const Set<CanvasFilterType> _backendFilters = <CanvasFilterType>{
    CanvasFilterType.hueSaturation,
    CanvasFilterType.brightnessContrast,
    CanvasFilterType.blackWhite,
    CanvasFilterType.binarize,
    CanvasFilterType.gaussianBlur,
    CanvasFilterType.leakRemoval,
    CanvasFilterType.lineNarrow,
    CanvasFilterType.fillExpand,
    CanvasFilterType.scanPaperDrawing,
    CanvasFilterType.invert,
  };

  bool get _backendSupported => _ffi.isSupported;
  bool get _backendReady =>
      _backendSupported && _owner._backendCanvasEngineHandle != null;
  bool get isSupported => _backendSupported;
  bool get isReady => _backendReady;
  bool get supportsLayerTransformPreview =>
      capabilities.isAvailable && capabilities.supportsLayerTransformPreview;
  bool get supportsLayerTranslate =>
      capabilities.isAvailable && capabilities.supportsLayerTranslate;
  bool get supportsAntialias =>
      capabilities.isAvailable && capabilities.supportsAntialias;
  bool get supportsStrokeStream =>
      capabilities.isAvailable && capabilities.supportsStrokeStream;
  bool get supportsInputQueue =>
      capabilities.isAvailable && capabilities.supportsInputQueue;
  bool get supportsSpray =>
      capabilities.isAvailable && capabilities.supportsSpray;

  @override
  CanvasBackendCapabilities get capabilities => CanvasBackendCapabilities(
    isSupported: _backendSupported,
    isReady: _backendReady,
    supportedFilters: _backendSupported
        ? _backendFilters
        : const <CanvasFilterType>{},
    supportsLayerTransformPreview: _backendSupported,
    supportsLayerTranslate: _backendSupported,
    supportsAntialias: _backendSupported,
    supportsStrokeStream: _backendSupported,
    supportsInputQueue: _backendSupported,
    supportsSpray: _backendSupported,
  );

  bool supportsFilterType(CanvasFilterType? type) {
    if (type == null) {
      return false;
    }
    return capabilities.isAvailable && capabilities.supportsFilter(type);
  }

  bool _handleBackendUnavailable({
    bool skipIfUnavailable = false,
    bool warnIfFailed = false,
  }) {
    if (skipIfUnavailable) {
      return true;
    }
    if (warnIfFailed) {
      _owner._showBackendCanvasMessage('画布后端尚未准备好。');
    }
    return false;
  }

  Future<_CanvasRasterEditSession> beginRasterEdit({
    bool captureUndoOnFallback = true,
    bool warnIfFailed = false,
    bool requireBackend = false,
  }) async {
    if (!_backendReady) {
      if (requireBackend) {
        _handleBackendUnavailable(
          skipIfUnavailable: false,
          warnIfFailed: warnIfFailed,
        );
        return _CanvasRasterEditSession._(this, useBackend: false, ok: false);
      }
      if (captureUndoOnFallback) {
        await _owner._pushUndoSnapshot();
      }
      return _CanvasRasterEditSession._(this, useBackend: false, ok: true);
    }
    final bool ok = await syncActiveLayerFromBackend(
      warnIfFailed: warnIfFailed,
      skipIfUnavailable: false,
    );
    return _CanvasRasterEditSession._(this, useBackend: true, ok: ok);
  }

  Future<bool> syncActiveLayerFromBackend({
    bool waitForPending = false,
    bool warnIfFailed = false,
    bool skipIfUnavailable = true,
  }) async {
    if (!_backendReady) {
      return _handleBackendUnavailable(
        skipIfUnavailable: skipIfUnavailable,
        warnIfFailed: warnIfFailed,
      );
    }
    if (waitForPending) {
      await _owner._controller.waitForPendingWorkerTasks();
    }
    final bool ok = _owner._syncActiveLayerPixelsFromBackend();
    if (!ok && warnIfFailed) {
      _owner._showBackendCanvasMessage('画布后端同步图层失败。');
    }
    return ok;
  }

  Future<bool> syncAllLayerPixelsFromBackend({
    bool waitForPending = false,
    bool warnIfFailed = false,
    bool skipIfUnavailable = true,
  }) async {
    if (!_backendReady) {
      return _handleBackendUnavailable(
        skipIfUnavailable: skipIfUnavailable,
        warnIfFailed: warnIfFailed,
      );
    }
    if (waitForPending) {
      await _owner._controller.waitForPendingWorkerTasks();
    }
    final bool ok = _owner._syncAllLayerPixelsFromBackend();
    if (!ok && warnIfFailed) {
      _owner._showBackendCanvasMessage('画布后端同步图层失败。');
    }
    return ok;
  }

  Future<bool> commitActiveLayerToBackend({
    bool waitForPending = false,
    bool warnIfFailed = false,
    bool skipIfUnavailable = true,
    bool recordUndo = true,
  }) async {
    if (!_backendReady) {
      return _handleBackendUnavailable(
        skipIfUnavailable: skipIfUnavailable,
        warnIfFailed: warnIfFailed,
      );
    }
    if (waitForPending) {
      await _owner._controller.waitForPendingWorkerTasks();
    }
    final bool ok = _owner._commitActiveLayerToBackend(recordUndo: recordUndo);
    if (!ok && warnIfFailed) {
      _owner._showBackendCanvasMessage('画布后端写入图层失败。');
    }
    return ok;
  }

  Future<bool> syncAllLayerPixelsToBackend({
    bool waitForPending = false,
    bool warnIfFailed = false,
    bool skipIfUnavailable = true,
    bool recordUndo = false,
  }) async {
    if (!_backendReady) {
      return _handleBackendUnavailable(
        skipIfUnavailable: skipIfUnavailable,
        warnIfFailed: warnIfFailed,
      );
    }
    if (waitForPending) {
      await _owner._controller.waitForPendingWorkerTasks();
    }
    final bool ok = _owner._syncAllLayerPixelsToBackend(recordUndo: recordUndo);
    if (!ok && warnIfFailed) {
      _owner._showBackendCanvasMessage('画布后端写入图层失败。');
    }
    return ok;
  }

  Future<bool> waitForInputQueueIdle({
    int attempts = 6,
    Duration delay = const Duration(milliseconds: 16),
  }) async {
    if (!_backendReady) {
      return false;
    }
    final int? handle = _owner._backendCanvasEngineHandle;
    if (handle == null) {
      return false;
    }
    for (int attempt = 0; attempt < attempts; attempt++) {
      final int queued = getInputQueueLen(handle: handle) ?? 0;
      if (queued == 0) {
        return true;
      }
      await Future.delayed(delay);
    }
    return false;
  }

  int? getInputQueueLen({int? handle}) {
    if (!_backendReady) {
      return null;
    }
    final int? effectiveHandle = handle ?? _owner._backendCanvasEngineHandle;
    if (effectiveHandle == null) {
      return null;
    }
    return _ffi.getInputQueueLen(effectiveHandle);
  }

  void setViewFlags({required bool mirror, required bool blackWhite}) {
    if (!_backendReady) {
      return;
    }
    _ffi.setViewFlags(
      handle: _owner._backendCanvasEngineHandle!,
      mirror: mirror,
      blackWhite: blackWhite,
    );
  }

  bool setBrushMask({
    required int width,
    required int height,
    required Uint8List mask,
  }) {
    if (!_backendReady) {
      return false;
    }
    _ffi.setBrushMask(
      handle: _owner._backendCanvasEngineHandle!,
      width: width,
      height: height,
      mask: mask,
    );
    return true;
  }

  bool clearBrushMask() {
    if (!_backendReady) {
      return false;
    }
    _ffi.clearBrushMask(handle: _owner._backendCanvasEngineHandle!);
    return true;
  }

  bool setBackendActiveLayerByIndex({required int layerIndex}) {
    if (!_backendReady) {
      return false;
    }
    _ffi.setActiveLayer(
      handle: _owner._backendCanvasEngineHandle!,
      layerIndex: layerIndex,
    );
    return true;
  }

  bool setBackendActiveLayerById(String layerId) {
    if (!_backendReady) {
      return false;
    }
    final int? index = _owner._backendCanvasLayerIndexForId(layerId);
    if (index == null) {
      return false;
    }
    return setBackendActiveLayerByIndex(layerIndex: index);
  }

  bool setBackendLayerOpacityByIndex({
    required int layerIndex,
    required double opacity,
  }) {
    if (!_backendReady) {
      return false;
    }
    _ffi.setLayerOpacity(
      handle: _owner._backendCanvasEngineHandle!,
      layerIndex: layerIndex,
      opacity: opacity.clamp(0.0, 1.0),
    );
    return true;
  }

  bool setBackendLayerClippingByIndex({
    required int layerIndex,
    required bool clippingMask,
  }) {
    if (!_backendReady) {
      return false;
    }
    _ffi.setLayerClippingMask(
      handle: _owner._backendCanvasEngineHandle!,
      layerIndex: layerIndex,
      clippingMask: clippingMask,
    );
    return true;
  }

  bool setBackendLayerBlendModeByIndex({
    required int layerIndex,
    required CanvasLayerBlendMode blendMode,
  }) {
    if (!_backendReady) {
      return false;
    }
    _ffi.setLayerBlendMode(
      handle: _owner._backendCanvasEngineHandle!,
      layerIndex: layerIndex,
      blendModeIndex: blendMode.index,
    );
    return true;
  }

  bool setBackendLayerOpacityById({
    required String layerId,
    required double opacity,
  }) {
    if (!_backendReady) {
      return false;
    }
    final int? index = _owner._backendCanvasLayerIndexForId(layerId);
    if (index == null) {
      return false;
    }
    return setBackendLayerOpacityByIndex(layerIndex: index, opacity: opacity);
  }

  bool setBackendLayerClippingById({
    required String layerId,
    required bool clippingMask,
  }) {
    if (!_backendReady) {
      return false;
    }
    final int? index = _owner._backendCanvasLayerIndexForId(layerId);
    if (index == null) {
      return false;
    }
    return setBackendLayerClippingByIndex(
      layerIndex: index,
      clippingMask: clippingMask,
    );
  }

  bool setBackendLayerBlendModeById({
    required String layerId,
    required CanvasLayerBlendMode blendMode,
  }) {
    if (!_backendReady) {
      return false;
    }
    final int? index = _owner._backendCanvasLayerIndexForId(layerId);
    if (index == null) {
      return false;
    }
    return setBackendLayerBlendModeByIndex(
      layerIndex: index,
      blendMode: blendMode,
    );
  }

  bool clearBackendLayerByIndex({required int layerIndex}) {
    if (!_backendReady) {
      return false;
    }
    _ffi.clearLayer(
      handle: _owner._backendCanvasEngineHandle!,
      layerIndex: layerIndex,
    );
    return true;
  }

  bool reorderBackendLayer({required int fromIndex, required int toIndex}) {
    if (!_backendReady) {
      return false;
    }
    _ffi.reorderLayer(
      handle: _owner._backendCanvasEngineHandle!,
      fromIndex: fromIndex,
      toIndex: toIndex,
    );
    return true;
  }

  bool applyAntialiasByIndex({required int layerIndex, required int level}) {
    if (!_backendReady) {
      return false;
    }
    return _ffi.applyAntialias(
      handle: _owner._backendCanvasEngineHandle!,
      layerIndex: layerIndex,
      level: level,
    );
  }

  bool applyAntialiasById({required String layerId, required int level}) {
    if (!_backendReady) {
      return false;
    }
    final int? layerIndex = _owner._backendCanvasLayerIndexForId(layerId);
    if (layerIndex == null) {
      return false;
    }
    return applyAntialiasByIndex(layerIndex: layerIndex, level: level);
  }

  bool undo() {
    if (!_backendReady) {
      return false;
    }
    _ffi.undo(handle: _owner._backendCanvasEngineHandle!);
    return true;
  }

  bool redo() {
    if (!_backendReady) {
      return false;
    }
    _ffi.redo(handle: _owner._backendCanvasEngineHandle!);
    return true;
  }

  bool pushPointsPacked({required Uint8List bytes, required int pointCount}) {
    if (!_backendReady) {
      return false;
    }
    _ffi.pushPointsPacked(
      handle: _owner._backendCanvasEngineHandle!,
      bytes: bytes,
      pointCount: pointCount,
    );
    return true;
  }

  bool beginSpray() {
    if (!_backendReady) {
      return false;
    }
    _ffi.beginSpray(handle: _owner._backendCanvasEngineHandle!);
    return true;
  }

  bool endSpray() {
    if (!_backendReady) {
      return false;
    }
    _ffi.endSpray(handle: _owner._backendCanvasEngineHandle!);
    return true;
  }

  bool drawSpray({
    required Float32List points,
    required int pointCount,
    required int colorArgb,
    required int brushShape,
    required bool erase,
    required int antialiasLevel,
    required double softness,
    required bool accumulate,
  }) {
    if (!_backendReady) {
      return false;
    }
    _ffi.drawSpray(
      handle: _owner._backendCanvasEngineHandle!,
      points: points,
      pointCount: pointCount,
      colorArgb: colorArgb,
      brushShape: brushShape,
      erase: erase,
      antialiasLevel: antialiasLevel,
      softness: softness,
      accumulate: accumulate,
    );
    return true;
  }

  Future<bool> bucketFill({
    required Offset position,
    required Color color,
    required bool contiguous,
    required bool sampleAllLayers,
    required List<Color>? swallowColors,
    required int tolerance,
    required int fillGap,
    required int antialiasLevel,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[bucket] backend entry supported=$_backendSupported ready=$_backendReady '
        'pos=$position',
      );
    }
    if (!_backendSupported) {
      await _owner._pushUndoSnapshot();
      _owner._controller.floodFill(
        position,
        color: color,
        contiguous: contiguous,
        sampleAllLayers: sampleAllLayers,
        swallowColors: swallowColors,
        tolerance: tolerance,
        fillGap: fillGap,
        antialiasLevel: antialiasLevel,
      );
      if (_owner.mounted) {
        _owner.setState(() {});
      }
      _owner._markDirty();
      if (kDebugMode) {
        debugPrint('[bucket] backend skipped: not supported');
      }
      return true;
    }

    if (!_backendReady) {
      if (kDebugMode) {
        debugPrint('[bucket] backend unavailable: not ready');
      }
      _owner._showBackendCanvasMessage('画布后端尚未准备好。');
      return false;
    }

    final int handle = _owner._backendCanvasEngineHandle!;
    final String? activeLayerId = _owner._controller.activeLayerId;
    final int? layerIndex = activeLayerId != null
        ? _owner._backendCanvasLayerIndexForId(activeLayerId)
        : null;
    if (layerIndex == null) {
      if (kDebugMode) {
        debugPrint(
          '[bucket] backend abort: layerIndex null '
          'activeLayerId=$activeLayerId',
        );
      }
      return false;
    }
    final Size engineSize =
        _owner._backendCanvasEngineSize ?? _owner._canvasSize;
    final int engineWidth = engineSize.width.round();
    final int engineHeight = engineSize.height.round();
    if (engineWidth <= 0 || engineHeight <= 0) {
      if (kDebugMode) {
        debugPrint(
          '[bucket] backend abort: invalid engineSize '
          '${engineSize.width}x${engineSize.height}',
        );
      }
      return false;
    }
    final Offset enginePos = _owner._backendToEngineSpace(position);
    final int startX = enginePos.dx.floor();
    final int startY = enginePos.dy.floor();
    if (startX < 0 ||
        startY < 0 ||
        startX >= engineWidth ||
        startY >= engineHeight) {
      if (kDebugMode) {
        debugPrint(
          '[bucket] backend abort: out of bounds '
          'start=($startX,$startY) engine=${engineWidth}x$engineHeight',
        );
      }
      return false;
    }
    final Uint8List? selectionMaskForBackend = _owner
        ._resolveSelectionMaskForBackend(engineWidth, engineHeight);
    final Uint32List? swallowColorsArgb =
        swallowColors != null && swallowColors.isNotEmpty
        ? Uint32List.fromList(
            swallowColors
                .map((Color color) => color.toARGB32())
                .toList(growable: false),
          )
        : null;
    final bool applied = _ffi.bucketFill(
      handle: handle,
      layerIndex: layerIndex,
      startX: startX,
      startY: startY,
      colorArgb: color.toARGB32(),
      contiguous: contiguous,
      sampleAllLayers: sampleAllLayers,
      tolerance: tolerance,
      fillGap: fillGap,
      antialiasLevel: antialiasLevel,
      swallowColors: swallowColorsArgb,
      selectionMask: selectionMaskForBackend,
    );
    if (kDebugMode) {
      debugPrint(
        '[bucket] backend result=$applied '
        'layerIndex=$layerIndex start=($startX,$startY) '
        'engine=${engineWidth}x$engineHeight '
        'selectionMask=${selectionMaskForBackend?.length ?? 0}',
      );
    }
    if (applied) {
      _owner._recordBackendHistoryAction(layerId: activeLayerId);
      if (_owner.mounted) {
        _owner.setState(() {});
      }
      _owner._markDirty();
    }
    return applied;
  }

  _LayerPixels? readLayerPixelsFromBackend(String layerId) {
    if (!_backendReady) {
      return null;
    }
    final int handle = _owner._backendCanvasEngineHandle!;
    final int? layerIndex = _owner._backendCanvasLayerIndexForId(layerId);
    if (layerIndex == null) {
      return null;
    }
    final Size engineSize =
        _owner._backendCanvasEngineSize ?? _owner._canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return null;
    }
    final Uint32List? pixels = _ffi.readLayer(
      handle: handle,
      layerIndex: layerIndex,
      width: width,
      height: height,
    );
    if (pixels == null || pixels.length != width * height) {
      return null;
    }
    return _LayerPixels(pixels: pixels, width: width, height: height);
  }

  bool writeLayerPixelsToBackend({
    required String layerId,
    required Uint32List pixels,
    bool recordUndo = true,
    bool recordHistory = true,
    bool markDirty = true,
  }) {
    if (!_backendReady) {
      return false;
    }
    final int handle = _owner._backendCanvasEngineHandle!;
    final int? layerIndex = _owner._backendCanvasLayerIndexForId(layerId);
    if (layerIndex == null) {
      return false;
    }
    final bool applied = _ffi.writeLayer(
      handle: handle,
      layerIndex: layerIndex,
      pixels: pixels,
      recordUndo: recordUndo,
    );
    if (!applied) {
      return false;
    }
    if (recordHistory) {
      _owner._recordBackendHistoryAction(layerId: layerId);
    }
    if (markDirty) {
      if (_owner.mounted) {
        _owner.setState(() {});
      }
      _owner._markDirty();
    }
    return true;
  }

  bool queueLayerPixelsToBackend({
    required String layerId,
    required Uint32List pixels,
    bool recordUndo = false,
  }) {
    if (!_backendReady) {
      return false;
    }
    final int handle = _owner._backendCanvasEngineHandle!;
    final int? layerIndex = _owner._backendCanvasLayerIndexForId(layerId);
    if (layerIndex == null) {
      return false;
    }
    return _ffi.writeLayerAsync(
      handle: handle,
      layerIndex: layerIndex,
      pixels: pixels,
      recordUndo: recordUndo,
    );
  }

  bool setBackendLayerVisible({
    required String layerId,
    required bool visible,
  }) {
    if (!_backendReady) {
      return false;
    }
    final int? layerIndex = _owner._backendCanvasLayerIndexForId(layerId);
    if (layerIndex == null) {
      return false;
    }
    _ffi.setLayerVisible(
      handle: _owner._backendCanvasEngineHandle!,
      layerIndex: layerIndex,
      visible: visible,
    );
    return true;
  }

  bool setBackendLayerVisibleByIndex({
    required int layerIndex,
    required bool visible,
  }) {
    if (!_backendReady) {
      return false;
    }
    _ffi.setLayerVisible(
      handle: _owner._backendCanvasEngineHandle!,
      layerIndex: layerIndex,
      visible: visible,
    );
    return true;
  }

  bool hasBackendLayer({required String layerId}) {
    if (!_backendReady) {
      return false;
    }
    return _owner._backendCanvasLayerIndexForId(layerId) != null;
  }

  Rect? getBackendLayerBoundsById({required String layerId}) {
    if (!_backendReady) {
      return null;
    }
    final int? layerIndex = _owner._backendCanvasLayerIndexForId(layerId);
    if (layerIndex == null) {
      return null;
    }
    return getBackendLayerBoundsByIndex(layerIndex);
  }

  Rect? getBackendLayerBoundsByIndex(int layerIndex) {
    if (!_backendReady) {
      return null;
    }
    final Int32List? bounds = _ffi.getLayerBounds(
      handle: _owner._backendCanvasEngineHandle!,
      layerIndex: layerIndex,
    );
    if (bounds == null || bounds.length < 4) {
      return null;
    }
    final double left = bounds[0].toDouble();
    final double top = bounds[1].toDouble();
    final double right = bounds[2].toDouble();
    final double bottom = bounds[3].toDouble();
    if (right <= left || bottom <= top) {
      return null;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  bool setLayerTransformPreviewByIndex({
    required int layerIndex,
    required Float32List matrix,
    required bool enabled,
    required bool bilinear,
  }) {
    if (!_backendReady) {
      return false;
    }
    return _ffi.setLayerTransformPreview(
      handle: _owner._backendCanvasEngineHandle!,
      layerIndex: layerIndex,
      matrix: matrix,
      enabled: enabled,
      bilinear: bilinear,
    );
  }

  bool setLayerTransformPreviewById({
    required String layerId,
    required Float32List matrix,
    required bool enabled,
    required bool bilinear,
  }) {
    if (!_backendReady) {
      return false;
    }
    final int? layerIndex = _owner._backendCanvasLayerIndexForId(layerId);
    if (layerIndex == null) {
      return false;
    }
    return setLayerTransformPreviewByIndex(
      layerIndex: layerIndex,
      matrix: matrix,
      enabled: enabled,
      bilinear: bilinear,
    );
  }

  bool applyLayerTransformByIndex({
    required int layerIndex,
    required Float32List matrix,
    required bool bilinear,
  }) {
    if (!_backendReady) {
      return false;
    }
    return _ffi.applyLayerTransform(
      handle: _owner._backendCanvasEngineHandle!,
      layerIndex: layerIndex,
      matrix: matrix,
      bilinear: bilinear,
    );
  }

  bool applyLayerTransformById({
    required String layerId,
    required Float32List matrix,
    required bool bilinear,
  }) {
    if (!_backendReady) {
      return false;
    }
    final int? layerIndex = _owner._backendCanvasLayerIndexForId(layerId);
    if (layerIndex == null) {
      return false;
    }
    return applyLayerTransformByIndex(
      layerIndex: layerIndex,
      matrix: matrix,
      bilinear: bilinear,
    );
  }

  bool translateLayerByIndex({
    required int layerIndex,
    required int deltaX,
    required int deltaY,
    bool recordHistory = true,
    bool markDirty = true,
  }) {
    if (!_backendReady) {
      return false;
    }
    final bool applied = _ffi.translateLayer(
      handle: _owner._backendCanvasEngineHandle!,
      layerIndex: layerIndex,
      deltaX: deltaX,
      deltaY: deltaY,
    );
    if (!applied) {
      return false;
    }
    if (recordHistory) {
      final List<CanvasLayerInfo> layers = _owner._controller.layers;
      if (layerIndex >= 0 && layerIndex < layers.length) {
        _owner._recordBackendHistoryAction(layerId: layers[layerIndex].id);
      }
    }
    if (markDirty) {
      if (_owner.mounted) {
        _owner.setState(() {});
      }
      _owner._markDirty();
    }
    return true;
  }

  bool translateLayerById({
    required String layerId,
    required int deltaX,
    required int deltaY,
    bool recordHistory = true,
    bool markDirty = true,
  }) {
    if (!_backendReady) {
      return false;
    }
    final int? layerIndex = _owner._backendCanvasLayerIndexForId(layerId);
    if (layerIndex == null) {
      return false;
    }
    return translateLayerByIndex(
      layerIndex: layerIndex,
      deltaX: deltaX,
      deltaY: deltaY,
      recordHistory: recordHistory,
      markDirty: markDirty,
    );
  }

  bool applyFilterToBackend({
    required String layerId,
    required int filterType,
    double param0 = 0.0,
    double param1 = 0.0,
    double param2 = 0.0,
    double param3 = 0.0,
    bool recordHistory = true,
    bool markDirty = true,
  }) {
    if (!_backendReady) {
      return false;
    }
    final int handle = _owner._backendCanvasEngineHandle!;
    final int? layerIndex = _owner._backendCanvasLayerIndexForId(layerId);
    if (layerIndex == null) {
      return false;
    }
    final bool applied = _ffi.applyFilter(
      handle: handle,
      layerIndex: layerIndex,
      filterType: filterType,
      param0: param0,
      param1: param1,
      param2: param2,
      param3: param3,
    );
    if (!applied) {
      return false;
    }
    if (recordHistory) {
      _owner._recordBackendHistoryAction(layerId: layerId);
    }
    if (markDirty) {
      if (_owner.mounted) {
        _owner.setState(() {});
      }
      _owner._markDirty();
    }
    return true;
  }

  Future<_LayerPreviewPixels?> readLayerPreviewPixels({
    required String layerId,
    required int maxHeight,
  }) async {
    if (!_backendReady) {
      return null;
    }
    final int handle = _owner._backendCanvasEngineHandle!;
    final int? layerIndex = _owner._backendCanvasLayerIndexForId(layerId);
    if (layerIndex == null) {
      return null;
    }
    final Size engineSize =
        _owner._backendCanvasEngineSize ?? _owner._canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return null;
    }
    final int targetHeight = math.min(maxHeight, height);
    final double scale = targetHeight / height;
    final int targetWidth = math.max(1, (width * scale).round());
    if (targetWidth <= 0 || targetHeight <= 0) {
      return null;
    }
    final Uint8List? rgba = _ffi.readLayerPreview(
      handle: handle,
      layerIndex: layerIndex,
      width: targetWidth,
      height: targetHeight,
    );
    if (rgba == null || rgba.length != targetWidth * targetHeight * 4) {
      return null;
    }
    return _LayerPreviewPixels(
      bytes: rgba,
      width: targetWidth,
      height: targetHeight,
    );
  }

  Future<Uint8List?> magicWandMask(
    Offset position, {
    bool sampleAllLayers = true,
    int tolerance = 0,
  }) async {
    if (!_backendSupported) {
      return _owner._controller.computeMagicWandMask(
        position,
        sampleAllLayers: sampleAllLayers,
        tolerance: tolerance,
      );
    }
    if (!_backendReady) {
      return null;
    }
    final int handle = _owner._backendCanvasEngineHandle!;
    final String? activeLayerId = _owner._controller.activeLayerId;
    final int? layerIndex = activeLayerId != null
        ? _owner._backendCanvasLayerIndexForId(activeLayerId)
        : null;
    if (layerIndex == null) {
      return null;
    }
    final Size engineSize =
        _owner._backendCanvasEngineSize ?? _owner._canvasSize;
    final int engineWidth = engineSize.width.round();
    final int engineHeight = engineSize.height.round();
    if (engineWidth <= 0 || engineHeight <= 0) {
      return null;
    }
    final Offset enginePos = _owner._backendToEngineSpace(position);
    final int startX = enginePos.dx.floor();
    final int startY = enginePos.dy.floor();
    if (startX < 0 ||
        startY < 0 ||
        startX >= engineWidth ||
        startY >= engineHeight) {
      return null;
    }
    final int maskLength = engineWidth * engineHeight;
    final Uint8List? selectionMaskForBackend = _owner
        ._resolveSelectionMaskForBackend(engineWidth, engineHeight);
    final Uint8List? mask = _ffi.magicWandMask(
      handle: handle,
      layerIndex: layerIndex,
      startX: startX,
      startY: startY,
      maskLength: maskLength,
      sampleAllLayers: sampleAllLayers,
      tolerance: tolerance,
      selectionMask: selectionMaskForBackend,
    );
    if (mask == null) {
      return null;
    }
    final int canvasWidth = _owner._controller.width;
    final int canvasHeight = _owner._controller.height;
    if (canvasWidth <= 0 || canvasHeight <= 0) {
      return null;
    }
    if (engineWidth == canvasWidth && engineHeight == canvasHeight) {
      return mask;
    }
    return _scaleSelectionMask(
      mask,
      engineWidth,
      engineHeight,
      canvasWidth,
      canvasHeight,
    );
  }

  void syncSelectionMask() {
    if (!_backendReady) {
      return;
    }
    final int handle = _owner._backendCanvasEngineHandle!;
    final Size engineSize =
        _owner._backendCanvasEngineSize ?? _owner._canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      _ffi.setSelectionMask(handle: handle);
      return;
    }
    final Uint8List? selectionMask = _owner._resolveSelectionMaskForBackend(
      width,
      height,
    );
    _ffi.setSelectionMask(handle: handle, selectionMask: selectionMask);
  }

  Uint8List _scaleSelectionMask(
    Uint8List mask,
    int srcWidth,
    int srcHeight,
    int targetWidth,
    int targetHeight,
  ) {
    if (srcWidth <= 0 ||
        srcHeight <= 0 ||
        targetWidth <= 0 ||
        targetHeight <= 0) {
      return Uint8List(0);
    }
    final Uint8List scaled = Uint8List(targetWidth * targetHeight);
    for (int y = 0; y < targetHeight; y++) {
      final int srcY = (y * srcHeight) ~/ targetHeight;
      final int dstRow = y * targetWidth;
      final int srcRow = srcY * srcWidth;
      for (int x = 0; x < targetWidth; x++) {
        final int srcX = (x * srcWidth) ~/ targetWidth;
        scaled[dstRow + x] = mask[srcRow + srcX];
      }
    }
    return scaled;
  }
}
