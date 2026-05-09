part of 'painting_board.dart';

extension _PaintingBoardInteractionLayerCurveExtension on _PaintingBoardInteractionMixin {
  CanvasLayerInfo? _activeLayerForAdjustment() {
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
      setState(() => _isDrawing = false);
      _resetPerspectiveLock();
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
    final CanvasLayerInfo? layer = _activeLayerForAdjustment();
    if (layer == null || layer.locked) {
      return;
    }
    if (_controller.isActiveLayerTransformPendingCleanup) {
      return;
    }
    _focusNode.requestFocus();
    _layerAdjustUsingBackendPreview = false;
    _layerAdjustBackendPreviewLayerId = null;
    _layerAdjustBackendSynced =
        _backend.isReady && _syncActiveLayerFromBackendForAdjust(layer);
    _controller.translateActiveLayer(0, 0);
    if (_backend.supportsLayerTransformPreview &&
        _controller.isActiveLayerTransforming) {
      if (!_startBackendLayerAdjustPreview(layer)) {
        _hideBackendLayerForAdjust(layer);
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
    if (_layerAdjustUsingBackendPreview) {
      _updateBackendLayerAdjustPreview(moveX, moveY);
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
      _clearBackendLayerAdjustPreview();
      if (_backend.supportsLayerTranslate) {
        _restoreBackendLayerAfterAdjust();
      }
      _layerAdjustBackendSynced = false;
      _controller.disposeActiveLayerTransformSession();
      return;
    }
    await _pushUndoSnapshot();
    _controller.commitActiveLayerTranslation();
    if (_backend.supportsLayerTranslate) {
      _applyBackendLayerTranslation(dx, dy);
      _clearBackendLayerAdjustPreview();
      _restoreBackendLayerAfterAdjust();
    }
    _layerAdjustBackendSynced = false;
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

  bool _startBackendLayerAdjustPreview(CanvasLayerInfo layer) {
    if (!_backend.supportsLayerTransformPreview) {
      return false;
    }
    final Float32List matrix = _buildLayerAdjustTransformMatrix(0, 0);
    final bool ok = _backend.setLayerTransformPreviewById(
      layerId: layer.id,
      matrix: matrix,
      enabled: true,
      bilinear: false,
    );
    if (ok) {
      _layerAdjustUsingBackendPreview = true;
      _layerAdjustBackendPreviewLayerId = layer.id;
    }
    return ok;
  }

  void _updateBackendLayerAdjustPreview(int dx, int dy) {
    if (!_layerAdjustUsingBackendPreview) {
      return;
    }
    final String? layerId = _layerAdjustBackendPreviewLayerId;
    if (!_backend.supportsLayerTransformPreview || layerId == null) {
      return;
    }
    final Float32List matrix = _buildLayerAdjustTransformMatrix(dx, dy);
    _backend.setLayerTransformPreviewById(
      layerId: layerId,
      matrix: matrix,
      enabled: true,
      bilinear: false,
    );
  }

  void _clearBackendLayerAdjustPreview() {
    if (!_layerAdjustUsingBackendPreview) {
      return;
    }
    final String? layerId = _layerAdjustBackendPreviewLayerId;
    if (_backend.supportsLayerTransformPreview && layerId != null) {
      final Float32List matrix = _buildLayerAdjustTransformMatrix(0, 0);
      _backend.setLayerTransformPreviewById(
        layerId: layerId,
        matrix: matrix,
        enabled: false,
        bilinear: false,
      );
    }
    _layerAdjustUsingBackendPreview = false;
    _layerAdjustBackendPreviewLayerId = null;
  }

  void _applyBackendLayerTranslation(int dx, int dy) {
    if (dx == 0 && dy == 0) {
      return;
    }
    if (!_backend.supportsLayerTranslate) {
      return;
    }
    final CanvasLayerInfo? layer = _activeLayerForAdjustment();
    if (layer == null) {
      return;
    }
    final Size engineSize = _backendCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return;
    }
    bool applied = false;
    final Size? surfaceSize = _controller.readLayerSurfaceSize(layer.id);
    final Uint32List? pixels = _controller.readLayerPixels(layer.id);
    if (!_controller.clipLayerOverflow &&
        _layerAdjustBackendSynced &&
        surfaceSize != null &&
        surfaceSize.width.round() == width &&
        surfaceSize.height.round() == height &&
        pixels != null &&
        pixels.length == width * height) {
      applied = _backend.writeLayerPixelsToBackend(
        layerId: layer.id,
        pixels: pixels,
        recordUndo: true,
      );
    } else {
      applied = _backend.translateLayerById(
        layerId: layer.id,
        deltaX: dx,
        deltaY: dy,
      );
    }
    if (!applied) {
      return;
    }
  }

  void _hideBackendLayerForAdjust(CanvasLayerInfo layer) {
    if (!_backend.isReady) {
      return;
    }
    if (!_backend.hasBackendLayer(layerId: layer.id)) {
      return;
    }
    _layerAdjustBackendHiddenLayerId = layer.id;
    _layerAdjustBackendHiddenVisible = layer.visible;
    _backend.setBackendLayerVisible(layerId: layer.id, visible: false);
  }

  void _restoreBackendLayerAfterAdjust() {
    final String? layerId = _layerAdjustBackendHiddenLayerId;
    if (layerId == null) {
      _layerAdjustBackendHiddenLayerId = null;
      return;
    }
    _backend.setBackendLayerVisible(
      layerId: layerId,
      visible: _layerAdjustBackendHiddenVisible,
    );
    _layerAdjustBackendHiddenLayerId = null;
    _layerAdjustBackendHiddenVisible = false;
  }

  bool _syncActiveLayerFromBackendForAdjust(CanvasLayerInfo layer) {
    return _syncLayerPixelsFromBackend(layer);
  }

  Future<void> _handleCurvePenPointerDown(Offset boardLocal) async {
    _resetPerspectiveLock();
    final Offset snapped = _maybeSnapToPerspective(
      boardLocal,
      anchor: _curveAnchor,
    );
    _focusNode.requestFocus();
    final bool insideCanvas = _isWithinCanvasBounds(snapped);
    if (_curveAnchor == null) {
      if (insideCanvas && !isPointInsideSelection(snapped)) {
        return;
      }
      if (insideCanvas) {
        if (!_backend.supportsInputQueue ||
            !_brushShapeSupportsBackend ||
            !_drawBackendStrokeFromPoints(
              points: <Offset>[snapped, snapped],
              initialTimestampMillis: 0.0,
              simulatePressure: _simulatePenPressure,
            )) {
          _showBackendCanvasMessage('曲线画笔需要画布后端支持。');
          return;
        }
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
    final _CanvasRasterEditSession edit = await _backend.beginRasterEdit(
      captureUndoOnFallback: false,
      warnIfFailed: true,
    );
    if (!edit.ok) {
      return;
    }
    setState(() {
      _curvePendingEnd = snapped;
      _curveDragOrigin = snapped;
      _curveDragDelta = Offset.zero;
      _isCurvePlacingSegment = true;
      _curvePreviewPath = _buildCurvePreviewPath();
    });
    await _prepareCurveRasterPreview(captureUndo: !edit.useBackend);
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
    final Offset? start = _curveAnchor;
    final Offset? end = _curvePendingEnd;
    if (start == null || end == null) {
      _cancelCurvePenSegment();
      return;
    }
    final Offset control = _computeCurveControlPoint(
      start,
      end,
      _curveDragDelta,
    );
    if (_backend.supportsInputQueue && _brushShapeSupportsBackend) {
      if (_curveRasterPreviewSnapshot != null) {
        _clearCurvePreviewOverlay();
      }
      final Offset strokeStart = _clampToCanvas(start);
      final List<Offset> samplePoints = _sampleQuadraticCurvePoints(
        strokeStart,
        control,
        _clampToCanvas(end),
      );
      final List<Offset> polyline = <Offset>[strokeStart, ...samplePoints];
      final bool backendOk = _drawBackendStrokeFromPoints(
        points: polyline,
        initialTimestampMillis: 0.0,
        simulatePressure: _simulatePenPressure,
        timelineStyle: _SyntheticStrokeTimelineStyle.fastCurve,
      );
      if (backendOk) {
        _disposeCurveRasterPreview(
          restoreLayer: false,
          clearPreviewImage: true,
        );
        setState(() {
          _curveAnchor = end;
          _curvePendingEnd = null;
          _curveDragOrigin = null;
          _curveDragDelta = Offset.zero;
          _curvePreviewPath = null;
          _isCurvePlacingSegment = false;
        });
        return;
      }
    }

    if (_curveRasterPreviewSnapshot != null) {
      _clearCurvePreviewOverlay();
    }
    final bool backendOk = _drawQuadraticCurve(start, control, end);
    _disposeCurveRasterPreview(restoreLayer: !backendOk, clearPreviewImage: true);
    if (!backendOk) {
      _showBackendCanvasMessage('画布后端尚未准备好。');
      _cancelCurvePenSegment();
      return;
    }
    _clearCurvePreviewRasterImage(notify: false);
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
    if (_backend.isReady && _brushShapeSupportsBackend) {
      _curveUndoCapturedForPreview = false;
      _curveRasterPreviewSnapshot = null;
      _curveRasterPreviewPixels = null;
      _curvePreviewDirtyRect = null;
      _clearCurvePreviewRasterImage(notify: false);
      return;
    }
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
      _curveRasterPreviewPixels = rgbaToPixels(
        snapshot.bitmap!,
        snapshot.bitmapWidth!,
        snapshot.bitmapHeight!,
      );
    } else {
      _curveRasterPreviewPixels = null;
    }
  }

  void _refreshCurveRasterPreview() {
    if (_backend.isReady && _brushShapeSupportsBackend) {
      _curvePreviewDirtyRect = null;
      return;
    }
    final bool useBackendCanvas = _backend.isReady;
    final CanvasLayerData? snapshot = _curveRasterPreviewSnapshot;
    final Offset? start = _curveAnchor;
    final Offset? end = _curvePendingEnd;
    if (snapshot == null || start == null || end == null) {
      _clearCurvePreviewOverlay();
      if (useBackendCanvas) {
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
    if (restoredRegion != null) {
      _controller.markLayerRegionDirty(snapshot.id, restoredRegion);
    }
    if (useBackendCanvas) {
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
    if (!_backend.isReady) {
      return;
    }
    if (_curvePreviewPath == null) {
      _clearCurvePreviewRasterImage();
      return;
    }
    final CanvasLayerInfo layer = _controller.activeLayer;
    if (!layer.visible) {
      _clearCurvePreviewRasterImage();
      return;
    }
    final Size? surfaceSize = _controller.readLayerSurfaceSize(layer.id);
    final int width = surfaceSize?.width.round() ?? 0;
    final int height = surfaceSize?.height.round() ?? 0;
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
    final Uint32List? pixels = _controller.readLayerPixels(layer.id);
    if (pixels == null || pixels.length != width * height) {
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
    _hideBackendLayerForVectorPreview(layer.id);
  }

  void _clearCurvePreviewRasterImage({bool notify = true}) {
    _curvePreviewRasterToken++;
    final bool hadImage = _curvePreviewRasterImage != null;
    _curvePreviewRasterImage?.dispose();
    _curvePreviewRasterImage = null;
    if (!_isBackendVectorPreviewActive) {
      _restoreBackendLayerAfterVectorPreview();
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

  bool _drawQuadraticCurve(Offset start, Offset control, Offset end) {
    const double initialTimestamp = 0.0;
    final Offset strokeStart = _clampToCanvas(start);
    final List<Offset> samplePoints = _sampleQuadraticCurvePoints(
      strokeStart,
      control,
      _clampToCanvas(end),
    );
    final List<Offset> polyline = <Offset>[strokeStart, ...samplePoints];
    if (!_backend.supportsInputQueue || !_brushShapeSupportsBackend) {
      return false;
    }
    final bool backendOk = _drawBackendStrokeFromPoints(
      points: polyline,
      initialTimestampMillis: initialTimestamp,
      simulatePressure: _simulatePenPressure,
    );
    if (!backendOk) {
      return false;
    }
    if (_brushRandomRotationEnabled) {
      _brushRandomRotationPreviewSeed = _brushRotationRandom.nextInt(1 << 31);
    }
    _markDirty();
    return true;
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
