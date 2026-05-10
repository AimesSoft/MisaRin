part of 'painting_board.dart';

abstract class _PaintingBoardBase extends _PaintingBoardBaseCore {
  late final _CanvasBackendFacade _backend = _CanvasBackendFacade(this);
  bool get canUndo => _useCombinedHistory
      ? _historyUndoStack.isNotEmpty
      : _undoStack.isNotEmpty;
  bool get canRedo => _useCombinedHistory
      ? _historyRedoStack.isNotEmpty
      : _redoStack.isNotEmpty;
  bool get hasSelection =>
      selectionMaskSnapshot != null ||
      selectionPathSnapshot != null ||
      selectionPreviewPath != null ||
      magicWandPreviewPath != null;
  bool get canSelectAll =>
      isBoardReady && _controller.width > 0 && _controller.height > 0;
  bool get canClearSelection => isBoardReady && hasSelection;
  bool get canInvertSelection => canSelectAll;
  bool get canCut => isBoardReady && _activeLayerId != null;
  bool get canCopy => canCut;
  bool get canPaste => isBoardReady && _activeLayerId != null;
  SelectionShape get selectionShape;
  ShapeToolVariant get shapeToolVariant;
  Path? get selectionPath;
  Path? get selectionPreviewPath;
  Path? get shapePreviewPath;
  Path? get magicWandPreviewPath;
  double get selectionDashPhase;
  bool isPointInsideSelection(Offset position);

  Uint8List? get selectionMaskSnapshot;
  Path? get selectionPathSnapshot;

  void setSelectionState({SelectionShape? shape, Path? path, Uint8List? mask});

  void clearSelectionArtifacts();
  void resetSelectionUndoFlag();
  Uint8List? _resolveSelectionMaskForBackend(int targetWidth, int targetHeight);

  UnmodifiableListView<CanvasLayerInfo> get _layers => _controller.layers;
  String? get _activeLayerId => _controller.activeLayerId;
  Color get _backgroundPreviewColor;

  List<CanvasLayerData> _buildInitialLayers();

  Future<void> _pickColor({
    required String title,
    required Color initialColor,
    required ValueChanged<Color> onSelected,
    VoidCallback? onCleared,
  });

  void _rememberColor(Color color);
  void _setPrimaryColor(Color color, {bool remember = true});
  Future<void> _applyPaintBucket(Offset position);
  bool _isActiveLayerLocked();
  Offset _backendToEngineSpace(Offset boardLocal);

  void _setActiveTool(CanvasTool tool);
  void _selectBrushPreset(String id);
  void _convertMagicWandPreviewToSelection();
  void _convertSelectionToMagicWandPreview();
  void _clearMagicWandPreview();
  void _resetSelectionPreview();
  void _resetPolygonState();
  void _handleMagicWandPointerDown(Offset position);
  void _handleSelectionPointerDown(Offset position, Duration timestamp);
  void _handleSelectionPointerMove(Offset position);
  void _handleSelectionPointerUp();
  void _handleSelectionPointerCancel();
  void _handleSelectionPenPointerDown(Offset position);
  void _handleSelectionPenPointerMove(Offset position);
  void _handleSelectionPenPointerUp();
  void _handleSelectionPenPointerCancel();
  void _handleSelectionHover(Offset position);
  void _clearSelectionHover();
  void _clearSelection();
  void _updateSelectionShape(SelectionShape shape);
  void _updateSelectionAdditiveEnabled(bool value);
  void _updateShapeToolVariant(ShapeToolVariant variant);
  void initializeSelectionTicker(TickerProvider provider);
  void disposeSelectionTicker();
  void _updateSelectionAnimation();
  void _syncMenuAvailability();

  void _handlePointerDown(PointerDownEvent event);
  void _handlePointerMove(PointerMoveEvent event);
  void _handlePointerUp(PointerUpEvent event);
  void _handlePointerCancel(PointerCancelEvent event);
  void _handlePointerHover(PointerHoverEvent event);
  void _handleWorkspacePointerExit();
  void _handlePointerSignal(PointerSignalEvent event);
  KeyEventResult _handleWorkspaceKeyEvent(FocusNode node, KeyEvent event);

  void _applyBackendBrushOverride(
    int handle, {
    bool? snapToPixelOverride,
    bool? usePressureOverride,
    double? streamlineStrengthOverride,
    int? smoothingModeOverride,
    double? stabilizerStrengthOverride,
  }) {
    if (!_backend.isReady) {
      return;
    }
    double radius =
        (_activeTool == CanvasTool.eraser
            ? _eraserStrokeWidth
            : _penStrokeWidth) /
        2;
    final Size engineSize = _backendCanvasEngineSize ?? _canvasSize;
    if (engineSize != _canvasSize &&
        _canvasSize.width > 0 &&
        _canvasSize.height > 0) {
      final double sx = engineSize.width / _canvasSize.width;
      final double sy = engineSize.height / _canvasSize.height;
      final double scale = (sx.isFinite && sy.isFinite)
          ? ((sx + sy) / 2.0)
          : 1.0;
      if (scale.isFinite && scale > 0) {
        radius *= scale;
      }
    }
    final bool erase = _isBrushEraserEnabled;
    final Color strokeColor = erase ? const Color(0xFFFFFFFF) : _primaryColor;
    final double stabilizer = mapStrokeStabilizerStrength(
      stabilizerStrengthOverride ?? _strokeStabilizerStrength,
    );
    final double streamline =
        (streamlineStrengthOverride ?? _streamlineStrength).clamp(0.0, 1.0);
    final int smoothingMode =
        smoothingModeOverride ?? (stabilizer > 0.0001 ? 3 : 1);
    final bool usePressure =
        usePressureOverride ??
        (_stylusPressureEnabled ||
            _simulatePenPressure ||
            _autoSharpPeakEnabled);
    CanvasBackendFacade.instance.setBrush(
      handle: handle,
      colorArgb: strokeColor.value,
      baseRadius: radius,
      usePressure: usePressure,
      erase: erase,
      antialiasLevel: _penAntialiasLevel,
      brushShape: _brushShape.index,
      randomRotation: _brushRandomRotationEnabled,
      smoothRotation: _brushSmoothRotationEnabled,
      rotationSeed: _brushRandomRotationPreviewSeed,
      spacing: _brushSpacing,
      hardness: _brushHardness,
      flow: _brushFlow,
      scatter: _brushScatter,
      rotationJitter: _brushRotationJitter,
      snapToPixel: snapToPixelOverride ?? _brushSnapToPixel,
      screentoneEnabled: _brushScreentoneEnabled,
      screentoneSpacing: _brushScreentoneSpacing,
      screentoneDotSize: _brushScreentoneDotSize,
      screentoneRotation: _brushScreentoneRotation,
      screentoneSoftness: _brushScreentoneSoftness,
      screentoneShape: _brushScreentoneShape.index,
      hollow: _hollowStrokeEnabled,
      hollowRatio: _hollowStrokeRatio,
      hollowEraseOccludedParts: _hollowStrokeEraseOccludedParts,
      streamlineStrength: streamline,
      smoothingMode: smoothingMode,
      stabilizerStrength: stabilizer,
    );
  }

  void _updatePenPressureSimulation(bool value);
  void _updatePenPressureProfile(StrokePressureProfile profile);
  void _updatePenAntialiasLevel(int value);
  void _updateAutoSharpPeakEnabled(bool value);

  void _handleScaleStart(ScaleStartDetails details);
  void _handleScaleUpdate(ScaleUpdateDetails details);
  void _handleScaleEnd(ScaleEndDetails details);

  void _handleUndo();
  void _handleRedo();
  Future<bool> cut();
  Future<bool> copy();
  Future<bool> paste();
  Future<bool> deleteSelection();

  void _updatePenStrokeWidth(double value);
  void _updateSprayStrokeWidth(double value);
  void _updateEraserStrokeWidth(double value);
  void _updateLiquifyStrokeWidth(double value);
  void _updateLiquifyStrength(double value);
  void _updateLiquifySoftness(double value);
  void _updateLiquifyMix(double value);
  void _updateSmudgeStrokeWidth(double value);
  void _updateSmudgeStrength(double value);
  void _updateSmudgeSoftness(double value);
  void _updateBucketSampleAllLayers(bool value);
  void _updateBucketContiguous(bool value);

  void _handleAddLayer();
  void _handleRemoveLayer(String id);

  Widget _buildLayerPanelContent(FluentThemeData theme);
  Widget _buildColorPanelContent(FluentThemeData theme);
  Widget? _buildColorPanelTrailing(FluentThemeData theme);
  Widget _buildColorIndicator(FluentThemeData theme);

  List<CanvasLayerData> snapshotLayers() => _controller.snapshotLayers();

  Future<List<CanvasLayerData>> snapshotLayersForExport() async {
    final bool ok = await _backend.syncAllLayerPixelsFromBackend(
      waitForPending: true,
      warnIfFailed: false,
    );
    if (!ok) {
      debugPrint('画布后端同步图层失败，导出将使用当前缓存数据。');
    }
    return _controller.snapshotLayers();
  }

  double? _normalizePointerPressureForBackend(PointerEvent event) {
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
    final double curve = _stylusCurve.isFinite ? _stylusCurve : 1.0;
    final double curved = math
        .pow(normalized.clamp(0.0, 1.0), curve)
        .toDouble();
    return curved.clamp(0.0, 1.0);
  }

  bool _drawBackendStrokeFromPoints({
    required List<Offset> points,
    required double initialTimestampMillis,
    bool simulatePressure = false,
    _SyntheticStrokeTimelineStyle timelineStyle =
        _SyntheticStrokeTimelineStyle.natural,
    PointerEvent? rawEvent,
  }) {
    if (!_backend.supportsInputQueue) {
      return false;
    }
    if (points.length < 2) {
      return false;
    }
    final List<Offset> clamped = <Offset>[
      for (final Offset point in points) _clampToCanvas(point),
    ];
    if (clamped.length < 2) {
      return false;
    }

    final _BackendPointBuffer buffer = _BackendPointBuffer(
      initialCapacityPoints: clamped.length + 8,
    );
    final _BackendPressureSimulator simulator = _BackendPressureSimulator();
    simulator.setProfile(_penPressureProfile);
    simulator.setSharpTipsEnabled(_autoSharpPeakEnabled);

    final bool useStylus =
        rawEvent != null &&
        _stylusPressureEnabled &&
        TabletInputBridge.instance.isTabletPointer(rawEvent);
    final double? stylusPressure = useStylus && rawEvent != null
        ? _normalizePointerPressureForBackend(rawEvent)
        : null;
    final double stylusBlend = useStylus && simulatePressure
        ? _kStylusSimulationBlend
        : 1.0;

    final Offset startBoard = clamped.first;
    final Offset startEngine = _backendToEngineSpace(startBoard);
    final double initialTimestamp = initialTimestampMillis.isFinite
        ? initialTimestampMillis
        : 0.0;
    final double? initialPressure = simulator.beginStroke(
      position: startEngine,
      timestampMillis: initialTimestamp,
      simulatePressure: simulatePressure,
      useDevicePressure: useStylus,
      stylusPressureBlend: stylusBlend,
      stylusPressure: stylusPressure,
    );
    double startPressure = (initialPressure ?? stylusPressure ?? 1.0).clamp(
      0.0,
      1.0,
    );
    final int pointerId = rawEvent?.pointer ?? 0;
    buffer.add(
      x: startEngine.dx,
      y: startEngine.dy,
      pressure: startPressure,
      timestampUs: (initialTimestamp * 1000.0).round(),
      flags: _kBackendPointFlagDown,
      pointerId: pointerId,
    );

    final List<Offset> remaining = clamped.sublist(1);
    final List<_SyntheticStrokeSample> samples = _buildSyntheticStrokeSamples(
      remaining,
      startBoard,
    );
    if (samples.isEmpty) {
      if (startPressure <= 0.0001) {
        startPressure = (stylusPressure ?? 1.0).clamp(0.0, 1.0);
      }
      final Offset endEngine = _backendToEngineSpace(clamped.last);
      final double endPressure = startPressure;
      buffer.add(
        x: endEngine.dx,
        y: endEngine.dy,
        pressure: endPressure,
        timestampUs: ((initialTimestamp + _syntheticStrokeMinDeltaMs) * 1000.0)
            .round(),
        flags: _kBackendPointFlagUp,
        pointerId: pointerId,
      );
    } else {
      final double totalDistance = _syntheticStrokeTotalDistance(samples);
      int index = 0;
      final int lastIndex = samples.length - 1;
      _emitSyntheticStrokeTimeline(
        samples,
        totalDistance: totalDistance,
        initialTimestamp: initialTimestamp,
        style: timelineStyle,
        onSample: (sample, timestamp, _) {
          final Offset enginePos = _backendToEngineSpace(sample.point);
          final double? simulated = simulator.samplePressure(
            position: enginePos,
            timestampMillis: timestamp,
            stylusPressure: stylusPressure,
          );
          double pressure = (simulated ?? stylusPressure ?? 1.0).clamp(
            0.0,
            1.0,
          );
          final bool isLast = index == lastIndex;
          if (isLast && _autoSharpPeakEnabled && simulator.isSimulatingStroke) {
            pressure = 0.0;
          }
          buffer.add(
            x: enginePos.dx,
            y: enginePos.dy,
            pressure: pressure,
            timestampUs: (timestamp * 1000.0).round(),
            flags: isLast ? _kBackendPointFlagUp : _kBackendPointFlagMove,
            pointerId: pointerId,
          );
          index += 1;
        },
      );
    }

    final bool pushed = _backend.pushPointsPacked(
      bytes: buffer.bytes,
      pointCount: buffer.length,
    );
    if (!pushed) {
      return false;
    }
    _recordBackendHistoryAction(layerId: _activeLayerId, deferPreview: true);
    if (mounted) {
      setState(() {});
    }
    if (_brushRandomRotationEnabled) {
      _brushRandomRotationPreviewSeed = _brushRotationRandom.nextInt(1 << 31);
    }
    _markDirty();
    return true;
  }

  Future<CanvasRotationResult?> rotateCanvas(CanvasRotation rotation) async {
    final int width = _controller.width;
    final int height = _controller.height;
    if (width <= 0 || height <= 0) {
      return null;
    }
    _controller.commitActiveLayerTranslation();
    if (!await _backend.syncAllLayerPixelsFromBackend(
      waitForPending: true,
      warnIfFailed: true,
    )) {
      debugPrint('rotateCanvas: backend sync failed');
      return null;
    }
    final List<CanvasLayerData> original = snapshotLayers();
    if (original.isEmpty) {
      return CanvasRotationResult(
        layers: const <CanvasLayerData>[],
        width: width,
        height: height,
      );
    }
    final String? activeLayerId = _controller.activeLayerId;
    final int activeIndex = activeLayerId == null
        ? -1
        : original.indexWhere(
            (CanvasLayerData layer) => layer.id == activeLayerId,
          );
    if (activeIndex < 0) {
      return CanvasRotationResult(
        layers: original,
        width: width,
        height: height,
      );
    }
    final List<CanvasLayerData> rotated = List<CanvasLayerData>.from(original);
    rotated[activeIndex] = _rotateLayerData(
      original[activeIndex],
      rotation,
      width,
      height,
    );
    setSelectionState(path: null, mask: null);
    clearSelectionArtifacts();
    resetSelectionUndoFlag();
    _controller.loadLayers(rotated, _controller.backgroundColor);
    if (activeLayerId != null) {
      _controller.setActiveLayer(activeLayerId);
    }
    _resetHistory();
    setState(() {});
    _syncBackendCanvasLayersToEngine();
    await _backend.syncAllLayerPixelsToBackend(warnIfFailed: true);
    return CanvasRotationResult(layers: rotated, width: width, height: height);
  }

  Future<CanvasRotationResult?> flipCanvas(CanvasFlip flip) async {
    final int width = _controller.width;
    final int height = _controller.height;
    if (width <= 0 || height <= 0) {
      return null;
    }
    _controller.commitActiveLayerTranslation();
    if (!await _backend.syncAllLayerPixelsFromBackend(
      waitForPending: true,
      warnIfFailed: true,
    )) {
      debugPrint('flipCanvas: backend sync failed');
      return null;
    }
    final List<CanvasLayerData> original = snapshotLayers();
    if (original.isEmpty) {
      return CanvasRotationResult(
        layers: const <CanvasLayerData>[],
        width: width,
        height: height,
      );
    }
    final String? activeLayerId = _controller.activeLayerId;
    final int activeIndex = activeLayerId == null
        ? -1
        : original.indexWhere(
            (CanvasLayerData layer) => layer.id == activeLayerId,
          );
    if (activeIndex < 0) {
      return CanvasRotationResult(
        layers: original,
        width: width,
        height: height,
      );
    }
    final List<CanvasLayerData> flipped = List<CanvasLayerData>.from(original);
    flipped[activeIndex] = _flipLayerData(
      original[activeIndex],
      flip,
      width,
      height,
    );
    setSelectionState(path: null, mask: null);
    clearSelectionArtifacts();
    resetSelectionUndoFlag();
    _controller.loadLayers(flipped, _controller.backgroundColor);
    if (activeLayerId != null) {
      _controller.setActiveLayer(activeLayerId);
    }
    _resetHistory();
    setState(() {});
    _syncBackendCanvasLayersToEngine();
    await _backend.syncAllLayerPixelsToBackend(warnIfFailed: true);
    return CanvasRotationResult(layers: flipped, width: width, height: height);
  }

  void markSaved() {
    if (!_isDirty) {
      return;
    }
    _isDirty = false;
    widget.onDirtyChanged?.call(false);
  }

  CanvasLayerData _rotateLayerData(
    CanvasLayerData layer,
    CanvasRotation rotation,
    int canvasWidth,
    int canvasHeight,
  ) {
    final Uint8List? bitmap = layer.bitmap;
    final int? bitmapWidth = layer.bitmapWidth;
    final int? bitmapHeight = layer.bitmapHeight;
    if (bitmap != null && bitmapWidth != null && bitmapHeight != null) {
      final bool swaps = _rotationSwapsDimensions(rotation);
      final int targetWidth = swaps ? bitmapHeight : bitmapWidth;
      final int targetHeight = swaps ? bitmapWidth : bitmapHeight;
      final int left = layer.bitmapLeft ?? 0;
      final int top = layer.bitmapTop ?? 0;
      late int nextLeft;
      late int nextTop;
      switch (rotation) {
        case CanvasRotation.clockwise90:
          nextLeft = canvasHeight - top - bitmapHeight;
          nextTop = left;
          break;
        case CanvasRotation.counterClockwise90:
          nextLeft = top;
          nextTop = canvasWidth - left - bitmapWidth;
          break;
        case CanvasRotation.clockwise180:
        case CanvasRotation.counterClockwise180:
          nextLeft = canvasWidth - left - bitmapWidth;
          nextTop = canvasHeight - top - bitmapHeight;
          break;
      }
      final Uint8List rotated = _rotateBitmapRgba(
        bitmap,
        bitmapWidth,
        bitmapHeight,
        rotation,
      );
      return CanvasLayerData(
        id: layer.id,
        name: layer.name,
        visible: layer.visible,
        opacity: layer.opacity,
        locked: layer.locked,
        clippingMask: layer.clippingMask,
        blendMode: layer.blendMode,
        bitmap: rotated,
        bitmapWidth: targetWidth,
        bitmapHeight: targetHeight,
        bitmapLeft: nextLeft,
        bitmapTop: nextTop,
        fillColor: layer.fillColor,
      );
    }

    return CanvasLayerData(
      id: layer.id,
      name: layer.name,
      visible: layer.visible,
      opacity: layer.opacity,
      locked: layer.locked,
      clippingMask: layer.clippingMask,
      blendMode: layer.blendMode,
      fillColor: layer.fillColor,
    );
  }

  CanvasLayerData _flipLayerData(
    CanvasLayerData layer,
    CanvasFlip flip,
    int canvasWidth,
    int canvasHeight,
  ) {
    final Uint8List? bitmap = layer.bitmap;
    final int? bitmapWidth = layer.bitmapWidth;
    final int? bitmapHeight = layer.bitmapHeight;
    if (bitmap != null && bitmapWidth != null && bitmapHeight != null) {
      final Uint8List flipped = _flipBitmapRgba(
        bitmap,
        bitmapWidth,
        bitmapHeight,
        flip,
      );
      final int left = layer.bitmapLeft ?? 0;
      final int top = layer.bitmapTop ?? 0;
      final int nextLeft = flip == CanvasFlip.horizontal
          ? canvasWidth - left - bitmapWidth
          : left;
      final int nextTop = flip == CanvasFlip.vertical
          ? canvasHeight - top - bitmapHeight
          : top;
      return CanvasLayerData(
        id: layer.id,
        name: layer.name,
        visible: layer.visible,
        opacity: layer.opacity,
        locked: layer.locked,
        clippingMask: layer.clippingMask,
        blendMode: layer.blendMode,
        bitmap: flipped,
        bitmapWidth: bitmapWidth,
        bitmapHeight: bitmapHeight,
        bitmapLeft: nextLeft,
        bitmapTop: nextTop,
        fillColor: layer.fillColor,
      );
    }

    return CanvasLayerData(
      id: layer.id,
      name: layer.name,
      visible: layer.visible,
      opacity: layer.opacity,
      locked: layer.locked,
      clippingMask: layer.clippingMask,
      blendMode: layer.blendMode,
      fillColor: layer.fillColor,
    );
  }

  static bool _rotationSwapsDimensions(CanvasRotation rotation) {
    return rotation == CanvasRotation.clockwise90 ||
        rotation == CanvasRotation.counterClockwise90;
  }

  static Uint8List _rotateBitmapRgba(
    Uint8List source,
    int width,
    int height,
    CanvasRotation rotation,
  ) {
    if (source.length != width * height * 4) {
      return Uint8List.fromList(source);
    }
    final bool swaps = _rotationSwapsDimensions(rotation);
    final int targetWidth = swaps ? height : width;
    final int targetHeight = swaps ? width : height;
    final Uint8List output = Uint8List(targetWidth * targetHeight * 4);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int srcIndex = (y * width + x) * 4;
        late int destX;
        late int destY;
        switch (rotation) {
          case CanvasRotation.clockwise90:
            destX = height - 1 - y;
            destY = x;
            break;
          case CanvasRotation.counterClockwise90:
            destX = y;
            destY = width - 1 - x;
            break;
          case CanvasRotation.clockwise180:
          case CanvasRotation.counterClockwise180:
            destX = width - 1 - x;
            destY = height - 1 - y;
            break;
        }
        final int destIndex = (destY * targetWidth + destX) * 4;
        output[destIndex] = source[srcIndex];
        output[destIndex + 1] = source[srcIndex + 1];
        output[destIndex + 2] = source[srcIndex + 2];
        output[destIndex + 3] = source[srcIndex + 3];
      }
    }
    return output;
  }

  static Uint8List _flipBitmapRgba(
    Uint8List source,
    int width,
    int height,
    CanvasFlip flip,
  ) {
    if (source.length != width * height * 4) {
      return Uint8List.fromList(source);
    }
    final Uint8List output = Uint8List(width * height * 4);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int srcIndex = (y * width + x) * 4;
        final int destX = flip == CanvasFlip.horizontal ? width - 1 - x : x;
        final int destY = flip == CanvasFlip.vertical ? height - 1 - y : y;
        final int destIndex = (destY * width + destX) * 4;
        output[destIndex] = source[srcIndex];
        output[destIndex + 1] = source[srcIndex + 1];
        output[destIndex + 2] = source[srcIndex + 2];
        output[destIndex + 3] = source[srcIndex + 3];
      }
    }
    return output;
  }

  CanvasLayerData _scaleLayerData(
    CanvasLayerData layer,
    int sourceCanvasWidth,
    int sourceCanvasHeight,
    int targetWidth,
    int targetHeight,
    ImageResizeSampling sampling,
  ) {
    final Uint8List? bitmap = layer.bitmap;
    final int? bitmapWidth = layer.bitmapWidth;
    final int? bitmapHeight = layer.bitmapHeight;
    if (bitmap == null || bitmapWidth == null || bitmapHeight == null) {
      return layer;
    }
    final double scaleX = targetWidth / sourceCanvasWidth;
    final double scaleY = targetHeight / sourceCanvasHeight;
    final int scaledWidth = math.max(1, (bitmapWidth * scaleX).round());
    final int scaledHeight = math.max(1, (bitmapHeight * scaleY).round());
    final int scaledLeft = (scaleX == 0)
        ? 0
        : ((layer.bitmapLeft ?? 0) * scaleX).round();
    final int scaledTop = (scaleY == 0)
        ? 0
        : ((layer.bitmapTop ?? 0) * scaleY).round();
    final Uint8List scaledBitmap = _scaleBitmapRgba(
      bitmap,
      bitmapWidth,
      bitmapHeight,
      scaledWidth,
      scaledHeight,
      sampling,
    );
    if (!_hasVisiblePixels(scaledBitmap)) {
      return layer.copyWith(clearBitmap: true);
    }
    return layer.copyWith(
      bitmap: scaledBitmap,
      bitmapWidth: scaledWidth,
      bitmapHeight: scaledHeight,
      bitmapLeft: scaledLeft,
      bitmapTop: scaledTop,
    );
  }

  CanvasLayerData _reframeLayerData(
    CanvasLayerData layer,
    int sourceCanvasWidth,
    int sourceCanvasHeight,
    int targetWidth,
    int targetHeight,
    CanvasResizeAnchor anchor,
  ) {
    final Uint8List? bitmap = layer.bitmap;
    final int? bitmapWidth = layer.bitmapWidth;
    final int? bitmapHeight = layer.bitmapHeight;
    final int offsetX = _anchorOffsetValue(
      sourceCanvasWidth,
      targetWidth,
      _horizontalAnchorFactor(anchor),
    );
    final int offsetY = _anchorOffsetValue(
      sourceCanvasHeight,
      targetHeight,
      _verticalAnchorFactor(anchor),
    );
    if (bitmap == null || bitmapWidth == null || bitmapHeight == null) {
      if (layer.bitmapLeft == null && layer.bitmapTop == null) {
        return layer;
      }
      return layer.copyWith(
        bitmapLeft: layer.bitmapLeft == null
            ? null
            : layer.bitmapLeft! + offsetX,
        bitmapTop: layer.bitmapTop == null ? null : layer.bitmapTop! + offsetY,
      );
    }
    int newLeft = (layer.bitmapLeft ?? 0) + offsetX;
    int newTop = (layer.bitmapTop ?? 0) + offsetY;
    int visibleWidth = bitmapWidth;
    int visibleHeight = bitmapHeight;
    int cropLeft = 0;
    int cropTop = 0;
    if (newLeft < 0) {
      cropLeft = -newLeft;
      visibleWidth -= cropLeft;
      newLeft = 0;
    }
    if (newTop < 0) {
      cropTop = -newTop;
      visibleHeight -= cropTop;
      newTop = 0;
    }
    final int rightOverflow = newLeft + visibleWidth - targetWidth;
    if (rightOverflow > 0) {
      visibleWidth -= rightOverflow;
    }
    final int bottomOverflow = newTop + visibleHeight - targetHeight;
    if (bottomOverflow > 0) {
      visibleHeight -= bottomOverflow;
    }
    if (visibleWidth <= 0 || visibleHeight <= 0) {
      return layer.copyWith(clearBitmap: true);
    }
    Uint8List nextBitmap = bitmap;
    if (cropLeft != 0 ||
        cropTop != 0 ||
        visibleWidth != bitmapWidth ||
        visibleHeight != bitmapHeight) {
      nextBitmap = _cropBitmapRgba(
        bitmap,
        bitmapWidth,
        bitmapHeight,
        cropLeft,
        cropTop,
        visibleWidth,
        visibleHeight,
      );
    }
    if (!_hasVisiblePixels(nextBitmap)) {
      return layer.copyWith(clearBitmap: true);
    }
    return layer.copyWith(
      bitmap: nextBitmap,
      bitmapWidth: visibleWidth,
      bitmapHeight: visibleHeight,
      bitmapLeft: newLeft,
      bitmapTop: newTop,
    );
  }

  int _anchorOffsetValue(int sourceSize, int targetSize, double factor) {
    final double delta = (targetSize - sourceSize) * factor;
    return delta.round();
  }

  double _horizontalAnchorFactor(CanvasResizeAnchor anchor) {
    switch (anchor) {
      case CanvasResizeAnchor.topLeft:
      case CanvasResizeAnchor.centerLeft:
      case CanvasResizeAnchor.bottomLeft:
        return 0;
      case CanvasResizeAnchor.topCenter:
      case CanvasResizeAnchor.center:
      case CanvasResizeAnchor.bottomCenter:
        return 0.5;
      case CanvasResizeAnchor.topRight:
      case CanvasResizeAnchor.centerRight:
      case CanvasResizeAnchor.bottomRight:
        return 1.0;
    }
  }

  double _verticalAnchorFactor(CanvasResizeAnchor anchor) {
    switch (anchor) {
      case CanvasResizeAnchor.topLeft:
      case CanvasResizeAnchor.topCenter:
      case CanvasResizeAnchor.topRight:
        return 0;
      case CanvasResizeAnchor.centerLeft:
      case CanvasResizeAnchor.center:
      case CanvasResizeAnchor.centerRight:
        return 0.5;
      case CanvasResizeAnchor.bottomLeft:
      case CanvasResizeAnchor.bottomCenter:
      case CanvasResizeAnchor.bottomRight:
        return 1.0;
    }
  }

  Uint8List _scaleBitmapRgba(
    Uint8List source,
    int sourceWidth,
    int sourceHeight,
    int targetWidth,
    int targetHeight,
    ImageResizeSampling sampling,
  ) {
    if (sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        targetWidth <= 0 ||
        targetHeight <= 0) {
      return Uint8List(0);
    }
    switch (sampling) {
      case ImageResizeSampling.nearest:
        return _scaleBitmapNearest(
          source,
          sourceWidth,
          sourceHeight,
          targetWidth,
          targetHeight,
        );
      case ImageResizeSampling.bilinear:
        return _scaleBitmapBilinear(
          source,
          sourceWidth,
          sourceHeight,
          targetWidth,
          targetHeight,
        );
    }
  }

  Uint8List _scaleBitmapNearest(
    Uint8List source,
    int sourceWidth,
    int sourceHeight,
    int targetWidth,
    int targetHeight,
  ) {
    final Uint8List output = Uint8List(targetWidth * targetHeight * 4);
    final double scaleX = sourceWidth / targetWidth;
    final double scaleY = sourceHeight / targetHeight;
    int destIndex = 0;
    for (int y = 0; y < targetHeight; y++) {
      final int srcY = math.min(sourceHeight - 1, (y * scaleY).floor());
      for (int x = 0; x < targetWidth; x++) {
        final int srcX = math.min(sourceWidth - 1, (x * scaleX).floor());
        final int srcIndex = (srcY * sourceWidth + srcX) * 4;
        output[destIndex] = source[srcIndex];
        output[destIndex + 1] = source[srcIndex + 1];
        output[destIndex + 2] = source[srcIndex + 2];
        output[destIndex + 3] = source[srcIndex + 3];
        destIndex += 4;
      }
    }
    return output;
  }

  Uint8List _scaleBitmapBilinear(
    Uint8List source,
    int sourceWidth,
    int sourceHeight,
    int targetWidth,
    int targetHeight,
  ) {
    final Uint8List output = Uint8List(targetWidth * targetHeight * 4);
    final double scaleX = sourceWidth / targetWidth;
    final double scaleY = sourceHeight / targetHeight;
    int destIndex = 0;
    for (int y = 0; y < targetHeight; y++) {
      final double rawY = (y + 0.5) * scaleY - 0.5;
      double clampedY = rawY;
      if (clampedY < 0) {
        clampedY = 0;
      } else if (clampedY > sourceHeight - 1) {
        clampedY = (sourceHeight - 1).toDouble();
      }
      final int y0 = clampedY.floor();
      final int y1 = math.min(y0 + 1, sourceHeight - 1);
      final double wy = clampedY - y0;
      final double wy0 = 1 - wy;
      final double wy1 = wy;
      for (int x = 0; x < targetWidth; x++) {
        final double rawX = (x + 0.5) * scaleX - 0.5;
        double clampedX = rawX;
        if (clampedX < 0) {
          clampedX = 0;
        } else if (clampedX > sourceWidth - 1) {
          clampedX = (sourceWidth - 1).toDouble();
        }
        final int x0 = clampedX.floor();
        final int x1 = math.min(x0 + 1, sourceWidth - 1);
        final double wx = clampedX - x0;
        final double wx0 = 1 - wx;
        final double wx1 = wx;
        final double w00 = wx0 * wy0;
        final double w01 = wx1 * wy0;
        final double w10 = wx0 * wy1;
        final double w11 = wx1 * wy1;
        final int index00 = (y0 * sourceWidth + x0) * 4;
        final int index01 = (y0 * sourceWidth + x1) * 4;
        final int index10 = (y1 * sourceWidth + x0) * 4;
        final int index11 = (y1 * sourceWidth + x1) * 4;
        final double red =
            source[index00] * w00 +
            source[index01] * w01 +
            source[index10] * w10 +
            source[index11] * w11;
        final double green =
            source[index00 + 1] * w00 +
            source[index01 + 1] * w01 +
            source[index10 + 1] * w10 +
            source[index11 + 1] * w11;
        final double blue =
            source[index00 + 2] * w00 +
            source[index01 + 2] * w01 +
            source[index10 + 2] * w10 +
            source[index11 + 2] * w11;
        final double alpha =
            source[index00 + 3] * w00 +
            source[index01 + 3] * w01 +
            source[index10 + 3] * w10 +
            source[index11 + 3] * w11;
        output[destIndex] = _clampChannel(red);
        output[destIndex + 1] = _clampChannel(green);
        output[destIndex + 2] = _clampChannel(blue);
        output[destIndex + 3] = _clampChannel(alpha);
        destIndex += 4;
      }
    }
    return output;
  }

  int _clampChannel(double value) {
    if (value <= 0) {
      return 0;
    }
    if (value >= 255) {
      return 255;
    }
    return value.round();
  }

  Uint8List _cropBitmapRgba(
    Uint8List source,
    int sourceWidth,
    int sourceHeight,
    int left,
    int top,
    int width,
    int height,
  ) {
    if (width <= 0 || height <= 0) {
      return Uint8List(0);
    }
    final Uint8List output = Uint8List(width * height * 4);
    for (int row = 0; row < height; row++) {
      final int srcY = top + row;
      if (srcY < 0 || srcY >= sourceHeight) {
        continue;
      }
      final int srcStart = ((srcY * sourceWidth) + left) * 4;
      final int destStart = row * width * 4;
      output.setRange(destStart, destStart + width * 4, source, srcStart);
    }
    return output;
  }

  bool _hasVisiblePixels(Uint8List bitmap) {
    for (int i = 3; i < bitmap.length; i += 4) {
      if (bitmap[i] != 0) {
        return true;
      }
    }
    return false;
  }

  void _emitClean() {
    if (!_isDirty) {
      return;
    }
    _isDirty = false;
    widget.onDirtyChanged?.call(false);
  }

  void _resetHistory() {
    _undoStack.clear();
    _redoStack.clear();
    _historyUndoStack.clear();
    _historyRedoStack.clear();
    _historyLocked = false;
    _historyLimit = AppPreferences.instance.historyLimit;
    _syncHistoryMenuAvailability();
  }

  Future<void> _pushUndoSnapshot({
    _CanvasHistoryEntry? entry,
    bool backendPixelsSynced = false,
  }) async {
    _refreshHistoryLimit();
    if (_historyLocked) {
      return;
    }
    final _CanvasHistoryEntry snapshot =
        entry ??
        await _createHistoryEntry(backendPixelsSynced: backendPixelsSynced);
    _undoStack.add(snapshot);
    _trimHistoryStacks();
    _redoStack.clear();
    _recordDartHistoryAction();
  }

  Future<_CanvasHistoryEntry> _createHistoryEntry({
    bool backendPixelsSynced = false,
  }) async {
    await _controller.waitForPendingWorkerTasks();
    return _CanvasHistoryEntry(
      layers: _controller.snapshotLayers(),
      backgroundColor: _controller.backgroundColor,
      activeLayerId: _controller.activeLayerId,
      selectionShape: selectionShape,
      selectionMask: selectionMaskSnapshot != null
          ? Uint8List.fromList(selectionMaskSnapshot!)
          : null,
      selectionPath: selectionPathSnapshot != null
          ? (Path()..addPath(selectionPathSnapshot!, Offset.zero))
          : null,
      backendPixelsSynced: backendPixelsSynced,
    );
  }

  Future<void> _applyHistoryEntry(_CanvasHistoryEntry entry) async {
    await _controller.waitForPendingWorkerTasks();
    _historyLocked = true;
    try {
      _controller.loadLayers(entry.layers, entry.backgroundColor);
      final String? activeId = entry.activeLayerId;
      if (activeId != null) {
        _controller.setActiveLayer(activeId);
      }
      setSelectionState(
        shape: entry.selectionShape,
        path: entry.selectionPath != null
            ? (Path()..addPath(entry.selectionPath!, Offset.zero))
            : null,
        mask: entry.selectionMask != null
            ? Uint8List.fromList(entry.selectionMask!)
            : null,
      );
      clearSelectionArtifacts();
    } finally {
      _historyLocked = false;
    }
    setState(() {});
    _focusNode.requestFocus();
    _markDirty();
    resetSelectionUndoFlag();
    _updateSelectionAnimation();
    _syncBackendCanvasLayersToEngine();
    if (entry.backendPixelsSynced) {
      await _backend.syncAllLayerPixelsToBackend();
    } else {
      await _backend.syncAllLayerPixelsFromBackend();
    }
  }

  void _refreshHistoryLimit() {
    final int nextLimit = AppPreferences.instance.historyLimit;
    if (_historyLimit == nextLimit) {
      return;
    }
    _historyLimit = nextLimit;
    _trimHistoryStacks();
  }

  void _trimHistoryStacks() {
    while (_undoStack.length > _historyLimit) {
      _undoStack.removeAt(0);
    }
    while (_redoStack.length > _historyLimit) {
      _redoStack.removeAt(0);
    }
    _trimHistoryActionStacks();
  }

  void _handleFloatingColorPanelMeasured(double height) {
    if (!height.isFinite || height <= 0) {
      return;
    }
    final double? current = _floatingColorPanelMeasuredHeight;
    if (current != null && (current - height).abs() < 0.5) {
      return;
    }
    setState(() => _floatingColorPanelMeasuredHeight = height);
  }

  void _handleSai2ColorPanelMeasured(double height) {
    if (!height.isFinite || height <= 0) {
      return;
    }
    final double? current = _sai2ColorPanelMeasuredHeight;
    if (current != null && (current - height).abs() < 0.5) {
      return;
    }
    setState(() => _sai2ColorPanelMeasuredHeight = height);
  }

  void _setFloatingColorPanelHeight(double? value) {
    double? sanitized = value;
    if (sanitized != null && (!sanitized.isFinite || sanitized <= 0)) {
      sanitized = null;
    }
    if (_floatingColorPanelHeight == sanitized) {
      return;
    }
    setState(() => _floatingColorPanelHeight = sanitized);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.floatingColorPanelHeight = sanitized;
    unawaited(AppPreferences.save());
  }

  void _setSai2ColorPanelHeight(double? value) {
    double? sanitized = value;
    if (sanitized != null && (!sanitized.isFinite || sanitized <= 0)) {
      sanitized = null;
    }
    if (_sai2ColorPanelHeight == sanitized) {
      return;
    }
    setState(() => _sai2ColorPanelHeight = sanitized);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.sai2ColorPanelHeight = sanitized;
    unawaited(AppPreferences.save());
  }

  void _setSai2ToolSectionRatio(double value) {
    final double normalized = value.clamp(0.0, 1.0);
    if ((_sai2ToolSectionRatio - normalized).abs() < 0.0001) {
      return;
    }
    setState(() => _sai2ToolSectionRatio = normalized);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.sai2ToolPanelSplit = normalized;
    unawaited(AppPreferences.save());
  }

  void _setSai2LayerPanelWidthRatio(double value) {
    final double normalized = value.clamp(0.0, 1.0);
    if ((_sai2LayerPanelWidthRatio - normalized).abs() < 0.0001) {
      return;
    }
    setState(() => _sai2LayerPanelWidthRatio = normalized);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.sai2LayerPanelWidthSplit = normalized;
    unawaited(AppPreferences.save());
  }

  void resetWorkspaceLayout() {
    final AppPreferences prefs = AppPreferences.instance;
    setState(() {
      _floatingColorPanelHeight = null;
      _sai2ColorPanelHeight = null;
      _sai2ToolSectionRatio = AppPreferences.defaultSai2ToolPanelSplit;
      _sai2LayerPanelWidthRatio = AppPreferences.defaultSai2LayerPanelSplit;
    });
    prefs.floatingColorPanelHeight = null;
    prefs.sai2ColorPanelHeight = null;
    prefs.sai2ToolPanelSplit = AppPreferences.defaultSai2ToolPanelSplit;
    prefs.sai2LayerPanelWidthSplit = AppPreferences.defaultSai2LayerPanelSplit;
    unawaited(AppPreferences.save());
  }

  bool _resetViewportToProjectDefault() {
    _viewport.reset();
    _viewportInitialized = false;

    final Size workspaceSize = _workspaceSize;
    final Size canvasSize = _canvasSize;
    final bool hasValidWorkspace =
        workspaceSize.width > 0 &&
        workspaceSize.height > 0 &&
        workspaceSize.width.isFinite &&
        workspaceSize.height.isFinite;
    final bool hasValidCanvas =
        canvasSize.width > 0 &&
        canvasSize.height > 0 &&
        canvasSize.width.isFinite &&
        canvasSize.height.isFinite;

    if (!hasValidWorkspace || !hasValidCanvas) {
      return false;
    }

    _initializeViewportIfNeeded();
    return true;
  }

  void _initializeViewportIfNeeded() {
    if (_viewportInitialized) {
      return;
    }

    final Size workspaceSize = _workspaceSize;
    if (workspaceSize.width <= 0 ||
        workspaceSize.height <= 0 ||
        !workspaceSize.width.isFinite ||
        !workspaceSize.height.isFinite) {
      return;
    }

    final Size canvasSize = _canvasSize;
    if (canvasSize.width <= 0 ||
        canvasSize.height <= 0 ||
        !canvasSize.width.isFinite ||
        !canvasSize.height.isFinite) {
      _viewportInitialized = true;
      return;
    }

    final double widthScale = workspaceSize.width / canvasSize.width;
    final double heightScale = workspaceSize.height / canvasSize.height;
    final double baseScale = widthScale < heightScale
        ? widthScale
        : heightScale;

    double targetScale = baseScale * _initialViewportScaleFactor;
    if (!targetScale.isFinite || targetScale <= 0) {
      targetScale = baseScale.isFinite && baseScale > 0 ? baseScale : 1.0;
    }

    if (targetScale > baseScale && baseScale.isFinite && baseScale > 0) {
      targetScale = baseScale;
    }

    _viewport.setScale(targetScale);
    _viewport.setOffset(Offset.zero);
    _viewportInitialized = true;
    _notifyViewInfoChanged();
  }

  bool get isPixelGridVisible => _pixelGridVisible;
  bool get isViewBlackWhiteEnabled => _viewBlackWhiteOverlay;
  bool get isViewMirrorEnabled => _viewMirrorOverlay;
  bool get isViewTiledEnabled => _viewTiledCanvas;
  bool get isPerspectiveGuideEnabled => _perspectiveEnabled;
  bool get isPerspectiveGuideVisible => _perspectiveVisible;
  PerspectiveGuideMode get perspectiveGuideMode => _perspectiveMode;

  bool get isBoardReady => _controller.frame != null || _backend.isReady;

  void _handlePixelGridPreferenceChanged() {
    if (!mounted) {
      return;
    }
    final bool visible = AppPreferences.pixelGridVisibleNotifier.value;
    if (visible == _pixelGridVisible) {
      return;
    }
    setState(() {
      _pixelGridVisible = visible;
    });
    _notifyViewInfoChanged();
  }

  void togglePixelGridVisibility() {
    final AppPreferences prefs = AppPreferences.instance;
    final bool nextVisible = !prefs.pixelGridVisible;
    prefs.updatePixelGridVisible(nextVisible);
    unawaited(AppPreferences.save());
  }

  void toggleViewBlackWhiteOverlay() {
    setState(() {
      _viewBlackWhiteOverlay = !_viewBlackWhiteOverlay;
    });
    _syncBackendCanvasViewFlags();
    _notifyViewInfoChanged();
  }

  void toggleViewMirrorOverlay() {
    setState(() {
      _viewMirrorOverlay = !_viewMirrorOverlay;
    });
    _syncBackendCanvasViewFlags();
    _notifyViewInfoChanged();
  }

  void toggleViewTiledCanvas() {
    setState(() {
      _viewTiledCanvas = !_viewTiledCanvas;
    });
    _notifyViewInfoChanged();
  }

  void togglePerspectiveGuideVisibility() {
    togglePerspectiveGuide();
  }

  void setPerspectiveGuideMode(PerspectiveGuideMode mode) {
    setPerspectiveMode(mode);
  }

  @protected
  void _scheduleWorkspaceCardsOverlaySync() {}
}
