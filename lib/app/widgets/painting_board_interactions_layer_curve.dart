part of 'painting_board.dart';

extension _PaintingBoardInteractionLayerCurveExtension on _PaintingBoardInteractionMixin {
  BitmapLayerState? _activeLayerForAdjustment() {
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

  bool _isCurveCancelModifierPressed() {
    final Set<LogicalKeyboardKey> keys =
        HardwareKeyboard.instance.logicalKeysPressed;
    final TargetPlatform platform = defaultTargetPlatform;
    if (platform == TargetPlatform.macOS) {
      return keys.contains(LogicalKeyboardKey.metaLeft) ||
          keys.contains(LogicalKeyboardKey.metaRight);
    }
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
  }

  bool _isAltKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.alt;
  }

  void _interruptForEyedropperOverride() {
    if (_isDrawing) {
      _finishStroke();
    }
    if (_isSpraying) {
      _finishSprayStroke();
    }
    if (_isLayerDragging) {
      _finishLayerAdjustDrag();
    }
    if (_activeTool == CanvasTool.curvePen) {
      _resetCurvePenState();
    }
  }

  Future<void> _beginLayerAdjustDrag(Offset boardLocal) async {
    final BitmapLayerState? layer = _activeLayerForAdjustment();
    if (layer == null || layer.locked) {
      return;
    }
    if (_controller.isActiveLayerTransformPendingCleanup) {
      return;
    }
    _focusNode.requestFocus();
    _layerAdjustUsingRustPreview = false;
    _layerAdjustRustPreviewLayerIndex = null;
    _layerAdjustRustSynced = _canUseRustCanvasEngine() &&
        await _syncActiveLayerFromRustForAdjust(layer);
    _controller.translateActiveLayer(0, 0);
    if (_canUseRustCanvasEngine() && _controller.isActiveLayerTransforming) {
      if (!await _startRustLayerAdjustPreview(layer)) {
        _hideRustLayerForAdjust(layer);
      }
    }
    _isLayerDragging = true;
    _layerDragStart = boardLocal;
    _layerDragAppliedDx = 0;
    _layerDragAppliedDy = 0;
  }

  void _updateLayerAdjustDrag(Offset boardLocal) {
    if (!_isLayerDragging) {
      return;
    }
    final Offset? start = _layerDragStart;
    if (start == null) {
      return;
    }
    final double dx = boardLocal.dx - start.dx;
    final double dy = boardLocal.dy - start.dy;
    final int moveX = dx.round();
    final int moveY = dy.round();
    if (moveX == _layerDragAppliedDx && moveY == _layerDragAppliedDy) {
      return;
    }
    _layerDragAppliedDx = moveX;
    _layerDragAppliedDy = moveY;
    _controller.translateActiveLayer(moveX, moveY);
    if (_layerAdjustUsingRustPreview) {
      _updateRustLayerAdjustPreview(moveX, moveY);
    }
    _markDirty();
  }

  Future<void> _finalizeLayerAdjustDrag() {
    final Future<void>? existing = _layerAdjustFinalizeTask;
    if (existing != null) {
      return existing;
    }
    final Future<void> task = _finalizeLayerAdjustDragImpl();
    _layerAdjustFinalizeTask = task;
    task.whenComplete(() {
      if (identical(_layerAdjustFinalizeTask, task)) {
        _layerAdjustFinalizeTask = null;
      }
    });
    return task;
  }

  Future<void> _finalizeLayerAdjustDragImpl() async {
    if (!_isLayerDragging) {
      return;
    }
    final int dx = _layerDragAppliedDx;
    final int dy = _layerDragAppliedDy;
    final bool moved = dx != 0 || dy != 0;
    _isLayerDragging = false;
    _layerDragStart = null;
    _layerDragAppliedDx = 0;
    _layerDragAppliedDy = 0;
    if (!moved) {
      _clearRustLayerAdjustPreview();
      if (_canUseRustCanvasEngine()) {
        _restoreRustLayerAfterAdjust();
      }
      _layerAdjustRustSynced = false;
      _controller.disposeActiveLayerTransformSession();
      return;
    }
    await _pushUndoSnapshot();
    _controller.commitActiveLayerTranslation();
    if (_canUseRustCanvasEngine()) {
      await _applyRustLayerTranslation(dx, dy);
      _clearRustLayerAdjustPreview();
      _restoreRustLayerAfterAdjust();
    }
    _layerAdjustRustSynced = false;
  }

  void _finishLayerAdjustDrag() {
    unawaited(_finalizeLayerAdjustDrag());
  }

  Float32List _buildLayerAdjustTransformMatrix(int dx, int dy) {
    final Float32List matrix = Float32List(16);
    matrix[0] = 1.0;
    matrix[5] = 1.0;
    matrix[10] = 1.0;
    matrix[15] = 1.0;
    matrix[12] = -dx.toDouble();
    matrix[13] = -dy.toDouble();
    return matrix;
  }

  Future<bool> _startRustLayerAdjustPreview(BitmapLayerState layer) async {
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
    final Float32List matrix = _buildLayerAdjustTransformMatrix(0, 0);
    final bool ok = await CanvasEngineFfi.instance.setLayerTransformPreview(
      handle: handle,
      layerIndex: layerIndex,
      matrix: matrix,
      enabled: true,
      bilinear: false,
    );
    if (ok) {
      _layerAdjustUsingRustPreview = true;
      _layerAdjustRustPreviewLayerIndex = layerIndex;
    }
    return ok;
  }

  void _updateRustLayerAdjustPreview(int dx, int dy) {
    if (!_layerAdjustUsingRustPreview) {
      return;
    }
    final int? handle = _rustCanvasEngineHandle;
    final int? layerIndex = _layerAdjustRustPreviewLayerIndex;
    if (!_canUseRustCanvasEngine() || handle == null || layerIndex == null) {
      return;
    }
    final Float32List matrix = _buildLayerAdjustTransformMatrix(dx, dy);
    unawaited(
      CanvasEngineFfi.instance.setLayerTransformPreview(
        handle: handle,
        layerIndex: layerIndex,
        matrix: matrix,
        enabled: true,
        bilinear: false,
      ),
    );
  }

  void _clearRustLayerAdjustPreview() {
    if (!_layerAdjustUsingRustPreview) {
      return;
    }
    final int? handle = _rustCanvasEngineHandle;
    final int? layerIndex = _layerAdjustRustPreviewLayerIndex;
    if (_canUseRustCanvasEngine() && handle != null && layerIndex != null) {
      final Float32List matrix = _buildLayerAdjustTransformMatrix(0, 0);
      unawaited(
        CanvasEngineFfi.instance.setLayerTransformPreview(
          handle: handle,
          layerIndex: layerIndex,
          matrix: matrix,
          enabled: false,
          bilinear: false,
        ),
      );
    }
    _layerAdjustUsingRustPreview = false;
    _layerAdjustRustPreviewLayerIndex = null;
  }

  Future<void> _applyRustLayerTranslation(int dx, int dy) async {
    if (dx == 0 && dy == 0) {
      return;
    }
    final int? handle = _rustCanvasEngineHandle;
    if (!_canUseRustCanvasEngine() || handle == null) {
      return;
    }
    final BitmapLayerState? layer = _activeLayerForAdjustment();
    if (layer == null) {
      return;
    }
    final int? layerIndex = _rustCanvasLayerIndexForId(layer.id);
    if (layerIndex == null) {
      return;
    }
    final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return;
    }
    bool applied = false;
    if (!_controller.clipLayerOverflow &&
        _layerAdjustRustSynced &&
        layer.surface.width == width &&
        layer.surface.height == height &&
        layer.surface.pixels.length == width * height) {
      applied = await CanvasEngineFfi.instance.writeLayer(
        handle: handle,
        layerIndex: layerIndex,
        pixels: layer.surface.pixels,
        recordUndo: true,
      );
    } else {
      applied = await CanvasEngineFfi.instance.translateLayer(
        handle: handle,
        layerIndex: layerIndex,
        deltaX: dx,
        deltaY: dy,
      );
    }
    if (applied) {
      _recordRustHistoryAction(layerId: layer.id);
      if (mounted) {
        setState(() {});
      }
      _markDirty();
    }
  }

  void _hideRustLayerForAdjust(BitmapLayerState layer) {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    final int? handle = _rustCanvasEngineHandle;
    if (handle == null) {
      return;
    }
    final int? layerIndex = _rustCanvasLayerIndexForId(layer.id);
    if (layerIndex == null) {
      return;
    }
    _layerAdjustRustHiddenLayerIndex = layerIndex;
    _layerAdjustRustHiddenVisible = layer.visible;
    CanvasEngineFfi.instance.setLayerVisible(
      handle: handle,
      layerIndex: layerIndex,
      visible: false,
    );
  }

  void _restoreRustLayerAfterAdjust() {
    final int? handle = _rustCanvasEngineHandle;
    final int? layerIndex = _layerAdjustRustHiddenLayerIndex;
    if (handle == null || layerIndex == null) {
      _layerAdjustRustHiddenLayerIndex = null;
      return;
    }
    CanvasEngineFfi.instance.setLayerVisible(
      handle: handle,
      layerIndex: layerIndex,
      visible: _layerAdjustRustHiddenVisible,
    );
    _layerAdjustRustHiddenLayerIndex = null;
    _layerAdjustRustHiddenVisible = false;
  }

  Future<bool> _syncActiveLayerFromRustForAdjust(BitmapLayerState layer) async {
    return _syncLayerPixelsFromRust(layer);
  }

  Future<void> _handleCurvePenPointerDown(Offset boardLocal) async {
    _resetPerspectiveLock();
    final Offset snapped = _maybeSnapToPerspective(
      boardLocal,
      anchor: _curveAnchor,
    );
    _focusNode.requestFocus();
    final bool insideCanvas = _isWithinCanvasBounds(snapped);
    final bool useRustCanvas = _canUseRustCanvasEngine();
    if (_curveAnchor == null) {
      if (insideCanvas && !isPointInsideSelection(snapped)) {
        return;
      }
      if (insideCanvas) {
        if (useRustCanvas && !await _syncActiveLayerPixelsFromRust()) {
          _showRustCanvasMessage('Rust 画布同步图层失败。');
          return;
        }
        if (!useRustCanvas) {
          await _pushUndoSnapshot();
        }
        final bool erase = _isBrushEraserEnabled;
        final Color strokeColor = erase
            ? const Color(0xFFFFFFFF)
            : _primaryColor;
        _controller.beginStroke(
          snapped,
          color: strokeColor,
          radius: _penStrokeWidth / 2,
          simulatePressure: _simulatePenPressure,
          profile: _penPressureProfile,
          antialiasLevel: _penAntialiasLevel,
          brushShape: _brushShape,
          randomRotation: _brushRandomRotationEnabled,
          rotationSeed: _brushRandomRotationPreviewSeed,
          spacing: _brushSpacing,
          hardness: _brushHardness,
          flow: _brushFlow,
          scatter: _brushScatter,
          rotationJitter: _brushRotationJitter,
          snapToPixel: _brushSnapToPixel,
          erase: erase,
          hollow: _hollowStrokeEnabled && !erase,
          hollowRatio: _hollowStrokeRatio,
          eraseOccludedParts: _hollowStrokeEraseOccludedParts,
        );
        _controller.endStroke();
        if (_brushRandomRotationEnabled) {
          _brushRandomRotationPreviewSeed =
              _brushRotationRandom.nextInt(1 << 31);
        }
        if (useRustCanvas) {
          await _controller.waitForPendingWorkerTasks();
          if (!await _commitActiveLayerToRust()) {
            _showRustCanvasMessage('Rust 画布写入图层失败。');
          }
        }
        _markDirty();
      }
      setState(() {
        _curveAnchor = snapped;
        _curvePreviewPath = null;
      });
      return;
    }
    if (_isCurvePlacingSegment) {
      return;
    }
    if (insideCanvas && !isPointInsideSelection(snapped)) {
      return;
    }
    if (useRustCanvas && !await _syncActiveLayerPixelsFromRust()) {
      _showRustCanvasMessage('Rust 画布同步图层失败。');
      return;
    }
    setState(() {
      _curvePendingEnd = snapped;
      _curveDragOrigin = snapped;
      _curveDragDelta = Offset.zero;
      _isCurvePlacingSegment = true;
      _curvePreviewPath = _buildCurvePreviewPath();
    });
    await _prepareCurveRasterPreview(captureUndo: !useRustCanvas);
    _refreshCurveRasterPreview();
  }

  void _handleCurvePenPointerMove(Offset boardLocal) {
    if (!_isCurvePlacingSegment || _curveDragOrigin == null) {
      return;
    }
    final Offset snapped = _maybeSnapToPerspective(
      boardLocal,
      anchor: _curveAnchor ?? _curveDragOrigin,
    );
    setState(() {
      _curveDragDelta = snapped - _curveDragOrigin!;
      _curvePreviewPath = _buildCurvePreviewPath();
    });
    _refreshCurveRasterPreview();
  }

  Future<void> _handleCurvePenPointerUp() async {
    _resetPerspectiveLock();
    if (!_isCurvePlacingSegment) {
      return;
    }
    final bool useRustCanvas = _canUseRustCanvasEngine();
    final Offset? start = _curveAnchor;
    final Offset? end = _curvePendingEnd;
    if (start == null || end == null) {
      _cancelCurvePenSegment();
      return;
    }
    if (!_curveUndoCapturedForPreview && !useRustCanvas) {
      await _pushUndoSnapshot();
    }
    final Offset control = _computeCurveControlPoint(
      start,
      end,
      _curveDragDelta,
    );
    if (useRustCanvas && !await _syncActiveLayerPixelsFromRust()) {
      _showRustCanvasMessage('Rust 画布同步图层失败。');
      _cancelCurvePenSegment();
      return;
    }
    if (_curveRasterPreviewSnapshot != null) {
      _clearCurvePreviewOverlay();
    }
    _controller.runSynchronousRasterization(() {
      _drawQuadraticCurve(start, control, end);
    });
    _disposeCurveRasterPreview(
      restoreLayer: false,
      clearPreviewImage: !useRustCanvas,
    );
    if (useRustCanvas) {
      await _controller.waitForPendingWorkerTasks();
      if (!await _commitActiveLayerToRust()) {
        _showRustCanvasMessage('Rust 画布写入图层失败。');
      }
      _clearCurvePreviewRasterImage(notify: false);
    }
    setState(() {
      _curveAnchor = end;
      _curvePendingEnd = null;
      _curveDragOrigin = null;
      _curveDragDelta = Offset.zero;
      _curvePreviewPath = null;
      _isCurvePlacingSegment = false;
    });
  }

  void _cancelCurvePenSegment() {
    if (!_isCurvePlacingSegment) {
      return;
    }
    _disposeCurveRasterPreview(restoreLayer: true);
    setState(() {
      _curvePendingEnd = null;
      _curveDragOrigin = null;
      _curveDragDelta = Offset.zero;
      _curvePreviewPath = null;
      _isCurvePlacingSegment = false;
    });
  }

  void _resetCurvePenState({bool notify = true}) {
    void apply() {
      _curveAnchor = null;
      _curvePendingEnd = null;
      _curveDragOrigin = null;
      _curveDragDelta = Offset.zero;
      _curvePreviewPath = null;
      _isCurvePlacingSegment = false;
    }

    _disposeCurveRasterPreview(restoreLayer: true);
    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  Future<void> _prepareCurveRasterPreview({bool captureUndo = true}) async {
    if (_curveUndoCapturedForPreview) {
      return;
    }
    if (captureUndo) {
      await _pushUndoSnapshot();
    } else {
      _clearCurvePreviewRasterImage(notify: false);
    }
    _curveUndoCapturedForPreview = true;
    final String? activeLayerId = _controller.activeLayerId;
    if (activeLayerId == null) {
      return;
    }
    _curveRasterPreviewSnapshot = _controller.buildClipboardLayer(
      activeLayerId,
    );
    final CanvasLayerData? snapshot = _curveRasterPreviewSnapshot;
    if (snapshot != null &&
        snapshot.bitmap != null &&
        snapshot.bitmapWidth != null &&
        snapshot.bitmapHeight != null) {
      _curveRasterPreviewPixels = BitmapCanvasController.rgbaToPixels(
        snapshot.bitmap!,
        snapshot.bitmapWidth!,
        snapshot.bitmapHeight!,
      );
    } else {
      _curveRasterPreviewPixels = null;
    }
  }

  void _refreshCurveRasterPreview() {
    final bool useRustCanvas = _canUseRustCanvasEngine();
    final CanvasLayerData? snapshot = _curveRasterPreviewSnapshot;
    final Offset? start = _curveAnchor;
    final Offset? end = _curvePendingEnd;
    if (snapshot == null || start == null || end == null) {
      _clearCurvePreviewOverlay();
      if (useRustCanvas) {
        _clearCurvePreviewRasterImage();
      }
      return;
    }
    final Rect? previous = _curvePreviewDirtyRect;
    Rect? restoredRegion;
    if (previous != null) {
      restoredRegion = _controller.restoreLayerRegion(
        snapshot,
        previous,
        pixelCache: _curveRasterPreviewPixels,
        markDirty: false,
      );
    }
    final Rect? dirty = _curvePreviewDirtyRectForCurrentPath();
    if (dirty == null) {
      _curvePreviewDirtyRect = null;
      if (restoredRegion != null) {
        _controller.markLayerRegionDirty(snapshot.id, restoredRegion);
      }
      return;
    }
    final Offset control = _computeCurveControlPoint(
      start,
      end,
      _curveDragDelta,
    );
    _curvePreviewDirtyRect = dirty;
    _controller.runSynchronousRasterization(() {
      _drawQuadraticCurve(start, control, end);
    });
    if (restoredRegion != null) {
      _controller.markLayerRegionDirty(snapshot.id, restoredRegion);
    }
    if (useRustCanvas) {
      unawaited(_updateCurvePreviewRasterImage());
    }
  }

  void _disposeCurveRasterPreview({
    required bool restoreLayer,
    bool clearPreviewImage = true,
  }) {
    final CanvasLayerData? snapshot = _curveRasterPreviewSnapshot;
    if (snapshot != null && restoreLayer) {
      _clearCurvePreviewOverlay();
    }
    _curveRasterPreviewSnapshot = null;
    _curveUndoCapturedForPreview = false;
    _curvePreviewDirtyRect = null;
    _curveRasterPreviewPixels = null;
    if (clearPreviewImage) {
      _clearCurvePreviewRasterImage(notify: false);
    }
  }

  void _clearCurvePreviewOverlay() {
    final CanvasLayerData? snapshot = _curveRasterPreviewSnapshot;
    final Rect? dirty = _curvePreviewDirtyRect;
    if (snapshot == null || dirty == null) {
      _curvePreviewDirtyRect = null;
      return;
    }
    _controller.restoreLayerRegion(
      snapshot,
      dirty,
      pixelCache: _curveRasterPreviewPixels,
    );
    _curvePreviewDirtyRect = null;
  }

  Future<void> _updateCurvePreviewRasterImage() async {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    if (_curvePreviewPath == null) {
      _clearCurvePreviewRasterImage();
      return;
    }
    final BitmapLayerState layer = _controller.activeLayer;
    if (!layer.visible) {
      _clearCurvePreviewRasterImage();
      return;
    }
    final int width = layer.surface.width;
    final int height = layer.surface.height;
    if (width <= 0 || height <= 0) {
      _clearCurvePreviewRasterImage();
      return;
    }
    final int token = ++_curvePreviewRasterToken;
    await _controller.waitForPendingWorkerTasks();
    if (!mounted ||
        token != _curvePreviewRasterToken ||
        _curvePreviewPath == null) {
      return;
    }
    final Uint32List pixels = layer.surface.pixels;
    if (pixels.length != width * height) {
      _clearCurvePreviewRasterImage();
      return;
    }
    final Uint8List rgba = _argbPixelsToRgbaForPreview(pixels);
    final ui.Image image = await _decodeImage(rgba, width, height);
    if (!mounted ||
        token != _curvePreviewRasterToken ||
        _curvePreviewPath == null) {
      image.dispose();
      return;
    }
    _curvePreviewRasterImage?.dispose();
    _curvePreviewRasterImage = image;
    setState(() {});
    _hideRustLayerForVectorPreview(layer.id);
  }

  void _clearCurvePreviewRasterImage({bool notify = true}) {
    _curvePreviewRasterToken++;
    final bool hadImage = _curvePreviewRasterImage != null;
    _curvePreviewRasterImage?.dispose();
    _curvePreviewRasterImage = null;
    if (!_isRustVectorPreviewActive) {
      _restoreRustLayerAfterVectorPreview();
    }
    if (notify && hadImage && mounted) {
      setState(() {});
    }
  }

  Rect? _curvePreviewDirtyRectForCurrentPath() {
    final Path? path = _curvePreviewPath;
    if (path == null) {
      return null;
    }
    final Rect bounds = path.getBounds();
    return bounds.inflate(_curvePreviewPadding);
  }

  double get _curvePreviewPadding => math.max(_penStrokeWidth * 0.5, 0.5) + 4.0;

  Path? _buildCurvePreviewPath() {
    final Offset? start = _curveAnchor;
    final Offset? end = _curvePendingEnd;
    if (start == null || end == null) {
      return null;
    }
    final Offset control = _computeCurveControlPoint(
      start,
      end,
      _curveDragDelta,
    );
    final Path path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    return path;
  }

  Offset _computeCurveControlPoint(Offset start, Offset end, Offset dragDelta) {
    if (dragDelta.distanceSquared < 1e-6) {
      return Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    }
    return end - dragDelta;
  }

  void _drawQuadraticCurve(Offset start, Offset control, Offset end) {
    const double initialTimestamp = 0.0;
    final bool simulatePressure = _simulatePenPressure;
    final bool enableNeedleTips =
        simulatePressure &&
        _penPressureProfile == StrokePressureProfile.taperCenter;
    final bool erase = _isBrushEraserEnabled;
    final Color strokeColor = erase ? const Color(0xFFFFFFFF) : _primaryColor;
    final bool hollow = _hollowStrokeEnabled && !erase;
    final Offset strokeStart = _clampToCanvas(start);
    _controller.beginStroke(
      strokeStart,
      color: strokeColor,
      radius: _penStrokeWidth / 2,
      simulatePressure: simulatePressure,
      profile: _penPressureProfile,
      timestampMillis: initialTimestamp,
      antialiasLevel: _penAntialiasLevel,
      brushShape: _brushShape,
      enableNeedleTips: enableNeedleTips,
      randomRotation: _brushRandomRotationEnabled,
      rotationSeed: _brushRandomRotationPreviewSeed,
      spacing: _brushSpacing,
      hardness: _brushHardness,
      flow: _brushFlow,
      scatter: _brushScatter,
      rotationJitter: _brushRotationJitter,
      snapToPixel: _brushSnapToPixel,
      erase: erase,
      hollow: hollow,
      hollowRatio: _hollowStrokeRatio,
      eraseOccludedParts: _hollowStrokeEraseOccludedParts,
    );
    final List<Offset> samplePoints = _sampleQuadraticCurvePoints(
      strokeStart,
      control,
      _clampToCanvas(end),
    );
    final List<Offset> polyline = <Offset>[strokeStart, ...samplePoints];
    if (simulatePressure) {
      final List<_SyntheticStrokeSample> samples = _buildSyntheticStrokeSamples(
        polyline.length > 1 ? polyline.sublist(1) : const <Offset>[],
        polyline.first,
      );
      final double totalDistance = _syntheticStrokeTotalDistance(samples);
      _simulateStrokeWithSyntheticTimeline(
        samples,
        totalDistance: totalDistance,
        initialTimestamp: initialTimestamp,
        style: _SyntheticStrokeTimelineStyle.fastCurve,
      );
    } else {
      for (int i = 1; i < polyline.length; i++) {
        final Offset point = polyline[i];
        _controller.extendStroke(point);
      }
    }
    _controller.endStroke();
    if (_brushRandomRotationEnabled) {
      _brushRandomRotationPreviewSeed = _brushRotationRandom.nextInt(1 << 31);
    }
    _markDirty();
  }

  List<Offset> _sampleQuadraticCurvePoints(
    Offset start,
    Offset control,
    Offset end,
  ) {
    final Path path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    final List<Offset> samples = <Offset>[];
    for (final ui.PathMetric metric in path.computeMetrics()) {
      final double length = metric.length;
      if (length <= 0.0) {
        continue;
      }
      double distance = _curveStrokeSampleSpacing;
      while (distance < length) {
        final ui.Tangent? tangent = metric.getTangentForOffset(distance);
        if (tangent != null) {
          samples.add(_clampToCanvas(tangent.position));
        }
        final double progress = (distance / length).clamp(0.0, 1.0);
        distance += _curveSampleSpacing(progress);
      }
      final ui.Tangent? endPoint = metric.getTangentForOffset(length);
      if (endPoint != null) {
        final Offset clamped = _clampToCanvas(endPoint.position);
        if (samples.isEmpty || (samples.last - clamped).distance > 0.01) {
          samples.add(clamped);
        }
      }
    }
    return samples;
  }

  double _curveSampleSpacing(double progress) {
    final double normalized = progress.clamp(0.0, 1.0);
    final double sine = math.sin(normalized * math.pi).abs();
    final double eased = math.pow(sine, 0.72).toDouble().clamp(0.0, 1.0);
    final double scale = ui.lerpDouble(0.52, 2.35, eased) ?? 1.0;
    return (_curveStrokeSampleSpacing * scale).clamp(
      _curveStrokeSampleSpacing * 0.48,
      _curveStrokeSampleSpacing * 2.6,
    );
  }

}
