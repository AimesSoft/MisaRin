part of 'painting_board.dart';

enum _HistoryActionKind { dart, rust }

abstract class _PaintingBoardBaseCore extends State<PaintingBoard> {
  late BitmapCanvasController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _boardReadyNotified = false;
  int? _rustCanvasEngineHandle;
  Size? _rustCanvasEngineSize;
  int _rustCanvasSyncedLayerCount = 0;
  final Map<String, Uint32List> _rustLayerSnapshots = <String, Uint32List>{};
  bool _rustLayerSnapshotDirty = false;
  bool _rustLayerSnapshotPendingRestore = false;
  bool _rustLayerSnapshotInFlight = false;
  int _rustLayerSnapshotWidth = 0;
  int _rustLayerSnapshotHeight = 0;
  int? _rustLayerSnapshotHandle;
  int? _rustPixelsSyncedHandle;

  CanvasTool _activeTool = CanvasTool.pen;
  bool _isDrawing = false;
  bool _isDraggingBoard = false;
  bool _isRotatingBoard = false;
  bool _isDirty = false;
  bool _isScalingGesture = false;
  bool _pixelGridVisible = false;
  bool _viewBlackWhiteOverlay = false;
  bool _viewMirrorOverlay = false;
  double _scaleGestureInitialScale = 1.0;
  double _penStrokeWidth = _defaultPenStrokeWidth;
  double _sprayStrokeWidth = _defaultSprayStrokeWidth;
  SprayMode _sprayMode = AppPreferences.defaultSprayMode;
  double _strokeStabilizerStrength =
      AppPreferences.defaultStrokeStabilizerStrength;
  double _streamlineStrength = AppPreferences.defaultStreamlineStrength;
  bool _simulatePenPressure = false;
  int _penAntialiasLevel = AppPreferences.defaultPenAntialiasLevel;
  int _bucketAntialiasLevel = AppPreferences.defaultBucketAntialiasLevel;
  bool _stylusPressureEnabled = AppPreferences.defaultStylusPressureEnabled;
  double _stylusCurve = AppPreferences.defaultStylusCurve;
  bool _autoSharpPeakEnabled = AppPreferences.defaultAutoSharpPeakEnabled;
  BrushShape _brushShape = AppPreferences.defaultBrushShape;
  bool _brushRandomRotationEnabled =
      AppPreferences.defaultBrushRandomRotationEnabled;
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
  bool _hollowStrokeEnabled = AppPreferences.defaultHollowStrokeEnabled;
  double _hollowStrokeRatio = AppPreferences.defaultHollowStrokeRatio;
  bool _hollowStrokeEraseOccludedParts =
      AppPreferences.defaultHollowStrokeEraseOccludedParts;
  PenStrokeSliderRange _penStrokeSliderRange =
      AppPreferences.defaultPenStrokeSliderRange;
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
  final Map<String, int> _rustLayerPreviewRevisions = <String, int>{};
  final Set<String> _rustLayerPreviewPending = <String>{};
  int _rustLayerPreviewSerial = 0;
  bool _rustLayerPreviewRefreshScheduled = false;
  bool _spacePanOverrideActive = false;
  bool _isLayerDragging = false;
  bool _layerAdjustRustSynced = false;
  bool _layerAdjustUsingRustPreview = false;
  int? _layerAdjustRustPreviewLayerIndex;
  int? _layerAdjustRustHiddenLayerIndex;
  bool _layerAdjustRustHiddenVisible = false;
  int? _layerTransformRustHiddenLayerIndex;
  bool _layerTransformRustHiddenVisible = false;
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
  String? _rustVectorPreviewHiddenLayerId;
  bool _rustVectorPreviewHiddenLayerVisible = false;
  int _rustVectorPreviewHideToken = 0;
  bool _isEyedropperSampling = false;
  bool _eyedropperOverrideActive = false;
  Offset? _lastEyedropperSample;
  Offset? _toolCursorPosition;
  Offset? _lastWorkspacePointer;
  Offset? _penCursorWorkspacePosition;
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
  bool _rustSprayActive = false;
  bool _rustSprayHasDrawn = false;
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
  Color _colorLineColor = AppPreferences.defaultColorLineColor;
  final List<_CanvasHistoryEntry> _undoStack = <_CanvasHistoryEntry>[];
  final List<_CanvasHistoryEntry> _redoStack = <_CanvasHistoryEntry>[];
  final List<_HistoryActionKind> _historyUndoStack = <_HistoryActionKind>[];
  final List<_HistoryActionKind> _historyRedoStack = <_HistoryActionKind>[];
  bool _historyLocked = false;
  int _historyLimit = AppPreferences.instance.historyLimit;
  final List<_PaletteCardEntry> _paletteCards = <_PaletteCardEntry>[];
  int _paletteCardSerial = 0;
  bool _referenceCardResizeInProgress = false;
  double? _floatingColorPanelHeight;
  double? _floatingColorPanelMeasuredHeight;
  double? _sai2ColorPanelHeight;
  double? _sai2ColorPanelMeasuredHeight;
  double _sai2ToolSectionRatio = AppPreferences.defaultSai2ToolPanelSplit;
  double _sai2LayerPanelWidthRatio = AppPreferences.defaultSai2LayerPanelSplit;

  Future<bool> insertImageLayerFromBytes(Uint8List bytes, {String? name});

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

  BitmapLayerState? _activeLayerStateForRustSync() {
    final String? activeId = _controller.activeLayerId;
    if (activeId == null) {
      return null;
    }
    for (final BitmapLayerState layer in _controller.layers) {
      if (layer.id == activeId) {
        return layer;
      }
    }
    return null;
  }

  Future<bool> _syncLayerPixelsFromRust(BitmapLayerState layer) async {
    if (!_canUseRustCanvasEngine()) {
      return false;
    }
    final int? handle = _rustCanvasEngineHandle;
    if (handle == null) {
      return false;
    }
    final int? layerIndex = _rustCanvasLayerIndexForId(layer.id);
    if (layerIndex == null) {
      return false;
    }
    final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return false;
    }
    if (layer.surface.width != width || layer.surface.height != height) {
      return false;
    }
    final Uint32List? pixels = await CanvasEngineFfi.instance.readLayer(
      handle: handle,
      layerIndex: layerIndex,
      width: width,
      height: height,
    );
    if (pixels == null || pixels.length != layer.surface.pixels.length) {
      return false;
    }
    layer.surface.pixels.setAll(0, pixels);
    layer.surface.markDirty();
    return true;
  }

  Future<bool> _syncActiveLayerPixelsFromRust() async {
    final BitmapLayerState? layer = _activeLayerStateForRustSync();
    if (layer == null) {
      return false;
    }
    return _syncLayerPixelsFromRust(layer);
  }

  Future<bool> _syncAllLayerPixelsFromRust() async {
    if (!_canUseRustCanvasEngine()) {
      return false;
    }
    final List<BitmapLayerState> layers = _controller.layers;
    if (layers.isEmpty) {
      return true;
    }
    bool allOk = true;
    for (final BitmapLayerState layer in layers) {
      if (!await _syncLayerPixelsFromRust(layer)) {
        allOk = false;
      }
    }
    return allOk;
  }

  Future<bool> _commitActiveLayerToRust({bool recordUndo = true}) async {
    if (!_canUseRustCanvasEngine()) {
      return false;
    }
    final int? handle = _rustCanvasEngineHandle;
    if (handle == null) {
      return false;
    }
    final BitmapLayerState? layer = _activeLayerStateForRustSync();
    if (layer == null) {
      return false;
    }
    final int? layerIndex = _rustCanvasLayerIndexForId(layer.id);
    if (layerIndex == null) {
      return false;
    }
    final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return false;
    }
    if (layer.surface.width != width || layer.surface.height != height) {
      return false;
    }
    if (layer.surface.pixels.length != width * height) {
      return false;
    }
    final bool applied = await CanvasEngineFfi.instance.writeLayer(
      handle: handle,
      layerIndex: layerIndex,
      pixels: layer.surface.pixels,
      recordUndo: recordUndo,
    );
    if (applied) {
      _recordRustHistoryAction(layerId: layer.id);
      if (mounted) {
        setState(() {});
      }
      _markDirty();
    }
    return applied;
  }

  Future<bool> _syncAllLayerPixelsToRust({bool recordUndo = false}) async {
    if (!_canUseRustCanvasEngine()) {
      return false;
    }
    final int? handle = _rustCanvasEngineHandle;
    if (handle == null) {
      return false;
    }
    final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return false;
    }
    final List<BitmapLayerState> layers = _controller.layers;
    bool allOk = true;
    for (int i = 0; i < layers.length; i++) {
      final BitmapLayerState layer = layers[i];
      if (layer.surface.width != width || layer.surface.height != height) {
        allOk = false;
        continue;
      }
      if (layer.surface.pixels.length != width * height) {
        allOk = false;
        continue;
      }
      final bool applied = await CanvasEngineFfi.instance.writeLayer(
        handle: handle,
        layerIndex: i,
        pixels: layer.surface.pixels,
        recordUndo: recordUndo,
      );
      if (!applied) {
        allOk = false;
        continue;
      }
      _bumpRustLayerPreviewRevision(layer.id);
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

  void _simulateStrokeWithSyntheticTimeline(
    List<_SyntheticStrokeSample> samples, {
    required double totalDistance,
    required double initialTimestamp,
    _SyntheticStrokeTimelineStyle style = _SyntheticStrokeTimelineStyle.natural,
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
      _controller.extendStroke(
        samples[i].point,
        deltaTimeMillis: deltaTime,
        timestampMillis: timestamp,
      );
    }
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
        phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks;
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

  void _handleRustCanvasEngineInfoChanged(
    int? handle,
    Size? engineSize,
    bool isNewEngine,
  ) {
    final bool handleChanged = _rustCanvasEngineHandle != handle;
    final bool sizeChanged = _rustCanvasEngineSize != engineSize;
    final bool engineReset = handleChanged || sizeChanged || isNewEngine;
    if ((handleChanged || isNewEngine) && handle != null) {
      final String sizeText = engineSize == null
          ? 'null'
          : '${engineSize.width.round()}x${engineSize.height.round()}';
      RustCanvasTimeline.mark(
        'paintingBoard: rust engine handle=$handle '
        'size=$sizeText newEngine=$isNewEngine',
      );
    }
    if (engineReset) {
      final String sizeText = engineSize == null
          ? 'null'
          : '${engineSize.width.round()}x${engineSize.height.round()}';
      debugPrint(
        'paintingBoard: rust engine info handle=$handle '
        'size=$sizeText newEngine=$isNewEngine',
      );
    }
    if (engineReset) {
      _rustCanvasSyncedLayerCount = 0;
      _rustPixelsSyncedHandle = null;
      _purgeRustHistoryActions();
      _rustLayerSnapshotDirty = false;
      if (_rustLayerSnapshots.isNotEmpty) {
        _rustLayerSnapshotPendingRestore = true;
      }
      _rustLayerPreviewRevisions.clear();
      _rustLayerPreviewPending.clear();
      _rustLayerPreviewSerial = 0;
      _rustLayerPreviewRefreshScheduled = false;
    }
    _rustCanvasEngineHandle = handle;
    _rustCanvasEngineSize = engineSize;
    _syncRustCanvasLayersToEngine();
    _syncRustCanvasViewFlags();
    _restoreRustLayerSnapshotIfNeeded();
    _syncRustCanvasPixelsIfNeeded();
    _notifyBoardReadyIfNeeded();
  }

  int? _rustCanvasLayerIndexForId(String layerId) {
    final int index = _controller.layers.indexWhere(
      (BitmapLayerState layer) => layer.id == layerId,
    );
    if (index < 0) {
      return null;
    }
    return index;
  }

  bool _canUseRustCanvasEngine() {
    return CanvasEngineFfi.instance.isSupported && _rustCanvasEngineHandle != null;
  }

  bool get _isRustVectorPreviewActive =>
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

  void _hideRustLayerForVectorPreview(String layerId) {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    if (_rustVectorPreviewHiddenLayerId == layerId) {
      return;
    }
    _restoreRustLayerAfterVectorPreview();
    final int token = ++_rustVectorPreviewHideToken;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (!mounted || token != _rustVectorPreviewHideToken) {
        return;
      }
      if (!_isRustVectorPreviewActive) {
        return;
      }
      final BitmapLayerState layer = _controller.activeLayer;
      if (layer.id != layerId || !layer.visible) {
        return;
      }
      final int? index = _rustCanvasLayerIndexForId(layerId);
      if (index == null) {
        return;
      }
      _rustVectorPreviewHiddenLayerId = layerId;
      _rustVectorPreviewHiddenLayerVisible = layer.visible;
      CanvasEngineFfi.instance.setLayerVisible(
        handle: _rustCanvasEngineHandle!,
        layerIndex: index,
        visible: false,
      );
    });
  }

  void _restoreRustLayerAfterVectorPreview() {
    _rustVectorPreviewHideToken++;
    final String? layerId = _rustVectorPreviewHiddenLayerId;
    if (layerId == null) {
      return;
    }
    if (_canUseRustCanvasEngine()) {
      final int? index = _rustCanvasLayerIndexForId(layerId);
      if (index != null) {
        CanvasEngineFfi.instance.setLayerVisible(
          handle: _rustCanvasEngineHandle!,
          layerIndex: index,
          visible: _rustVectorPreviewHiddenLayerVisible,
        );
      }
    }
    _rustVectorPreviewHiddenLayerId = null;
    _rustVectorPreviewHiddenLayerVisible = false;
  }

  bool get _useCombinedHistory => true;

  void _recordDartHistoryAction() {
    _recordHistoryAction(_HistoryActionKind.dart);
  }

  void _recordRustHistoryAction({
    String? layerId,
    bool deferPreview = false,
  }) {
    _rustLayerSnapshotDirty = true;
    _recordHistoryAction(_HistoryActionKind.rust);
    if (layerId == null) {
      return;
    }
    if (deferPreview) {
      _scheduleRustLayerPreviewRefresh(layerId);
    } else {
      _bumpRustLayerPreviewRevision(layerId);
    }
  }

  void _bumpRustLayerPreviewRevision(String layerId) {
    _rustLayerPreviewSerial += 1;
    _rustLayerPreviewRevisions[layerId] = _rustLayerPreviewSerial;
  }

  void _scheduleRustLayerPreviewRefresh(String layerId) {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    _rustLayerPreviewPending.add(layerId);
    if (_rustLayerPreviewRefreshScheduled) {
      return;
    }
    _rustLayerPreviewRefreshScheduled = true;
    unawaited(_runRustLayerPreviewRefresh());
  }

  Future<void> _runRustLayerPreviewRefresh() async {
    while (mounted && _rustLayerPreviewPending.isNotEmpty) {
      final int? handle = _rustCanvasEngineHandle;
      if (!_canUseRustCanvasEngine() || handle == null) {
        _rustLayerPreviewPending.clear();
        break;
      }
      final int queued = await CanvasEngineFfi.instance.getInputQueueLen(handle);
      if (queued > 0) {
        await Future.delayed(const Duration(milliseconds: 16));
        continue;
      }
      await Future.delayed(const Duration(milliseconds: 16));
      final List<String> pending = _rustLayerPreviewPending.toList(growable: false);
      _rustLayerPreviewPending.clear();
      for (final String layerId in pending) {
        _bumpRustLayerPreviewRevision(layerId);
      }
      if (mounted) {
        setState(() {});
      }
    }
    _rustLayerPreviewRefreshScheduled = false;
  }

  void _recordHistoryAction(_HistoryActionKind action) {
    if (!_useCombinedHistory) {
      return;
    }
    _historyUndoStack.add(action);
    _historyRedoStack.clear();
    _redoStack.clear();
    _trimHistoryActionStacks();
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
    return action;
  }

  _HistoryActionKind? _commitHistoryRedoAction() {
    if (!_useCombinedHistory || _historyRedoStack.isEmpty) {
      return null;
    }
    final _HistoryActionKind action = _historyRedoStack.removeLast();
    _historyUndoStack.add(action);
    _trimHistoryActionStacks();
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

  void _purgeRustHistoryActions() {
    if (!_useCombinedHistory) {
      return;
    }
    _historyUndoStack.removeWhere(
      (_HistoryActionKind action) => action == _HistoryActionKind.rust,
    );
    _historyRedoStack.removeWhere(
      (_HistoryActionKind action) => action == _HistoryActionKind.rust,
    );
  }

  void _syncRustCanvasViewFlags() {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    final int handle = _rustCanvasEngineHandle!;
    CanvasEngineFfi.instance.setViewFlags(
      handle: handle,
      mirror: _viewMirrorOverlay,
      blackWhite: _viewBlackWhiteOverlay,
    );
  }

  void _syncRustCanvasPixelsIfNeeded() {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    if (_rustLayerSnapshotPendingRestore) {
      return;
    }
    if (_rustLayerSnapshotDirty) {
      return;
    }
    if (_rustLayerSnapshots.isNotEmpty) {
      return;
    }
    final int handle = _rustCanvasEngineHandle!;
    if (_rustPixelsSyncedHandle == handle) {
      return;
    }
    unawaited(
      _syncAllLayerPixelsToRust().then((ok) {
        if (ok) {
          _rustPixelsSyncedHandle = handle;
        }
      }),
    );
  }

  Future<void> _captureRustLayerSnapshotIfNeeded() async {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    if (!_rustLayerSnapshotDirty || _rustLayerSnapshotInFlight) {
      return;
    }
    final int handle = _rustCanvasEngineHandle!;
    final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return;
    }
    _rustLayerSnapshotInFlight = true;
    bool allOk = true;
    final Map<String, Uint32List> next = <String, Uint32List>{};
    final List<BitmapLayerState> layers = _controller.layers;
    for (int i = 0; i < layers.length; i++) {
      final Uint32List? pixels = await CanvasEngineFfi.instance.readLayer(
        handle: handle,
        layerIndex: i,
        width: width,
        height: height,
      );
      if (pixels == null) {
        allOk = false;
        continue;
      }
      next[layers[i].id] = pixels;
    }
    if (next.isNotEmpty) {
      _rustLayerSnapshots
        ..clear()
        ..addAll(next);
      _rustLayerSnapshotWidth = width;
      _rustLayerSnapshotHeight = height;
      _rustLayerSnapshotHandle = handle;
      _rustLayerSnapshotPendingRestore = true;
      if (allOk) {
        _rustLayerSnapshotDirty = false;
      }
    }
    _rustLayerSnapshotInFlight = false;
    if (mounted && widget.isActive) {
      _restoreRustLayerSnapshotIfNeeded();
    }
  }

  void _restoreRustLayerSnapshotIfNeeded() {
    if (!_rustLayerSnapshotPendingRestore) {
      return;
    }
    if (_rustLayerSnapshotInFlight) {
      return;
    }
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    if (_rustLayerSnapshots.isEmpty) {
      _rustLayerSnapshotPendingRestore = false;
      _rustLayerSnapshotHandle = null;
      return;
    }
    final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width != _rustLayerSnapshotWidth || height != _rustLayerSnapshotHeight) {
      _rustLayerSnapshots.clear();
      _rustLayerSnapshotPendingRestore = false;
      _rustLayerSnapshotDirty = false;
      _rustLayerSnapshotHandle = null;
      return;
    }
    final int handle = _rustCanvasEngineHandle!;
    final List<BitmapLayerState> layers = _controller.layers;
    for (int i = 0; i < layers.length; i++) {
      final Uint32List? pixels = _rustLayerSnapshots[layers[i].id];
      if (pixels == null) {
        continue;
      }
      unawaited(
        CanvasEngineFfi.instance.writeLayer(
          handle: handle,
          layerIndex: i,
          pixels: pixels,
          recordUndo: false,
        ),
      );
      _bumpRustLayerPreviewRevision(layers[i].id);
    }
    _rustLayerSnapshotPendingRestore = false;
    _rustLayerSnapshotHandle = handle;
  }

  void _showRustCanvasMessage(String message) {
    if (!mounted) {
      return;
    }
    AppNotifications.show(
      context,
      message: message,
      severity: InfoBarSeverity.warning,
    );
  }

  void _syncRustCanvasLayersToEngine() {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    final int handle = _rustCanvasEngineHandle!;
    final List<BitmapLayerState> layers = _controller.layers;
    final int currentCount = layers.length;
    final int? hiddenAdjustIndex = _layerAdjustRustHiddenLayerIndex;
    final int? hiddenTransformIndex = _layerTransformRustHiddenLayerIndex;
    for (int i = 0; i < currentCount; i++) {
      final BitmapLayerState layer = layers[i];
      final bool hideForAdjust =
          (hiddenAdjustIndex != null && hiddenAdjustIndex == i) ||
          (hiddenTransformIndex != null && hiddenTransformIndex == i);
      CanvasEngineFfi.instance.setLayerVisible(
        handle: handle,
        layerIndex: i,
        visible: hideForAdjust ? false : layer.visible,
      );
      CanvasEngineFfi.instance.setLayerOpacity(
        handle: handle,
        layerIndex: i,
        opacity: layer.opacity.clamp(0.0, 1.0),
      );
      CanvasEngineFfi.instance.setLayerClippingMask(
        handle: handle,
        layerIndex: i,
        clippingMask: layer.clippingMask,
      );
      CanvasEngineFfi.instance.setLayerBlendMode(
        handle: handle,
        layerIndex: i,
        blendModeIndex: layer.blendMode.index,
      );
    }
    for (int i = currentCount; i < _rustCanvasSyncedLayerCount; i++) {
      CanvasEngineFfi.instance.setLayerVisible(
        handle: handle,
        layerIndex: i,
        visible: false,
      );
      CanvasEngineFfi.instance.setLayerOpacity(
        handle: handle,
        layerIndex: i,
        opacity: 1.0,
      );
      CanvasEngineFfi.instance.setLayerClippingMask(
        handle: handle,
        layerIndex: i,
        clippingMask: false,
      );
      CanvasEngineFfi.instance.setLayerBlendMode(
        handle: handle,
        layerIndex: i,
        blendModeIndex: CanvasLayerBlendMode.normal.index,
      );
      CanvasEngineFfi.instance.clearLayer(handle: handle, layerIndex: i);
    }
    _rustCanvasSyncedLayerCount = currentCount;

    final String? activeLayerId = _controller.activeLayerId;
    int? activeIndex =
        activeLayerId != null ? _rustCanvasLayerIndexForId(activeLayerId) : null;
    if (activeIndex == null && layers.isNotEmpty) {
      activeIndex = layers.length - 1;
      final String fallbackLayerId = layers[activeIndex].id;
      if (fallbackLayerId != activeLayerId) {
        _controller.setActiveLayer(fallbackLayerId);
      }
    }
    if (activeIndex != null) {
      CanvasEngineFfi.instance.setActiveLayer(handle: handle, layerIndex: activeIndex);
    }
  }

  void _rustCanvasSetActiveLayerById(String layerId) {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    final int? index = _rustCanvasLayerIndexForId(layerId);
    if (index == null) {
      return;
    }
    CanvasEngineFfi.instance.setActiveLayer(
      handle: _rustCanvasEngineHandle!,
      layerIndex: index,
    );
  }

  void _rustCanvasSetLayerVisibleById(String layerId, bool visible) {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    final int? index = _rustCanvasLayerIndexForId(layerId);
    if (index == null) {
      return;
    }
    CanvasEngineFfi.instance.setLayerVisible(
      handle: _rustCanvasEngineHandle!,
      layerIndex: index,
      visible: visible,
    );
  }

  void _rustCanvasSetLayerClippingById(String layerId, bool clippingMask) {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    final int? index = _rustCanvasLayerIndexForId(layerId);
    if (index == null) {
      return;
    }
    CanvasEngineFfi.instance.setLayerClippingMask(
      handle: _rustCanvasEngineHandle!,
      layerIndex: index,
      clippingMask: clippingMask,
    );
  }

  void _rustCanvasSetLayerOpacityById(String layerId, double opacity) {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    final int? index = _rustCanvasLayerIndexForId(layerId);
    if (index == null) {
      return;
    }
    CanvasEngineFfi.instance.setLayerOpacity(
      handle: _rustCanvasEngineHandle!,
      layerIndex: index,
      opacity: opacity.clamp(0.0, 1.0),
    );
  }

  void _rustCanvasSetLayerBlendModeById(
    String layerId,
    CanvasLayerBlendMode blendMode,
  ) {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    final int? index = _rustCanvasLayerIndexForId(layerId);
    if (index == null) {
      return;
    }
    CanvasEngineFfi.instance.setLayerBlendMode(
      handle: _rustCanvasEngineHandle!,
      layerIndex: index,
      blendModeIndex: blendMode.index,
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

  bool get hasContent => _controller.hasVisibleContent;
  bool get isDirty => _isDirty;
}
