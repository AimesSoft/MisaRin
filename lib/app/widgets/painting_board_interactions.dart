part of 'painting_board.dart';

const double _kStylusSimulationBlend = 0.68;

mixin _PaintingBoardInteractionMixin
    on
        _PaintingBoardBase,
        _PaintingBoardShapeMixin,
        _PaintingBoardReferenceMixin {
  void clear() {
    _pushUndoSnapshot();
    _controller.clear();
    _emitClean();
    setState(() {
      // No-op placeholder for repaint
    });
  }

  bool _isPrimaryPointer(PointerEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      if (event is PointerUpEvent || event is PointerCancelEvent) {
        return true;
      }
      return (event.buttons & kPrimaryMouseButton) != 0;
    }
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      if (event is PointerUpEvent || event is PointerCancelEvent) {
        return true;
      }
      if (event is PointerHoverEvent) {
        return true;
      }
      if (event is PointerDownEvent || event is PointerMoveEvent) {
        if (event.down) {
          return true;
        }
        if (event is PointerMoveEvent) {
          return (event.pressure > 0.0) ||
              (event.buttons & kPrimaryStylusButton) != 0;
        }
      }
      return event.down;
    }
    return false;
  }

  Rect get _toolbarRect => Rect.fromLTWH(
    _toolButtonPadding,
    _toolButtonPadding,
    _toolbarLayout.width,
    _toolbarLayout.height,
  );

  Rect get _toolSettingsRect => Rect.fromLTWH(
    _toolButtonPadding + _toolbarLayout.width + _toolSettingsSpacing,
    _toolButtonPadding,
    _toolSettingsCardSize.width,
    _toolSettingsCardSize.height,
  );

  Rect get _colorIndicatorRect {
    final double top =
        (_workspaceSize.height - _toolButtonPadding - _colorIndicatorSize)
            .clamp(0.0, double.infinity);
    return Rect.fromLTWH(
      _toolButtonPadding,
      top,
      _colorIndicatorSize,
      _colorIndicatorSize,
    );
  }

  Rect get _rightSidebarRect {
    final double left =
        (_workspaceSize.width - _sidePanelWidth - _toolButtonPadding)
            .clamp(0.0, double.infinity)
            .toDouble();
    return Rect.fromLTWH(
      left,
      _toolButtonPadding,
      _sidePanelWidth,
      (_workspaceSize.height - 2 * _toolButtonPadding).clamp(
        0.0,
        double.infinity,
      ),
    );
  }

  bool _isInsideToolArea(Offset workspacePosition) {
    return _toolbarRect.contains(workspacePosition) ||
        _toolSettingsRect.contains(workspacePosition) ||
        _rightSidebarRect.contains(workspacePosition) ||
        _colorIndicatorRect.contains(workspacePosition);
  }

  bool _isWithinCanvas(Offset boardLocal) {
    return boardLocal.dx >= 0 &&
        boardLocal.dy >= 0 &&
        boardLocal.dx < _canvasSize.width &&
        boardLocal.dy < _canvasSize.height;
  }

  void _setActiveTool(CanvasTool tool) {
    if (_activeTool == tool) {
      return;
    }
    if (_activeTool == CanvasTool.curvePen) {
      _resetCurvePenState(notify: false);
    }
    if (_activeTool == CanvasTool.layerAdjust && _isLayerDragging) {
      _finishLayerAdjustDrag();
    }
    if (_activeTool == CanvasTool.eyedropper && _isEyedropperSampling) {
      _finishEyedropperSample();
    }
    setState(() {
      if (_activeTool == CanvasTool.magicWand) {
        _convertMagicWandPreviewToSelection();
      }
      if (tool != CanvasTool.magicWand) {
        _clearMagicWandPreview();
      }
      if (tool != CanvasTool.selection) {
        _resetSelectionPreview();
        _resetPolygonState();
      }
      if (tool != CanvasTool.curvePen) {
        _curvePreviewPath = null;
      }
      if (tool != CanvasTool.shape) {
        _resetShapeDrawingState();
      }
      if (_activeTool == CanvasTool.eyedropper) {
        _isEyedropperSampling = false;
        _lastEyedropperSample = null;
      }
      _activeTool = tool;
      if (_cursorRequiresOverlay) {
        final Offset? pointer = _lastWorkspacePointer;
        if (pointer != null && _boardRect.contains(pointer)) {
          _toolCursorPosition = pointer;
        } else {
          _toolCursorPosition = null;
        }
      } else if (_penRequiresOverlay) {
        _toolCursorPosition = null;
        final Offset? pointer = _lastWorkspacePointer;
        if (pointer != null && _boardRect.contains(pointer)) {
          _penCursorWorkspacePosition = pointer;
        } else {
          _penCursorWorkspacePosition = null;
        }
      } else {
        _toolCursorPosition = null;
        _penCursorWorkspacePosition = null;
      }
    });
    _updateSelectionAnimation();
  }

  void _updatePenStrokeWidth(double value) {
    final double clamped = _penStrokeSliderRange.clamp(value);
    if ((_penStrokeWidth - clamped).abs() < 0.0005) {
      return;
    }
    setState(() => _penStrokeWidth = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.penStrokeWidth = clamped;
    unawaited(AppPreferences.save());
  }

  void _updateBrushShape(BrushShape shape) {
    if (_brushShape == shape) {
      return;
    }
    setState(() => _brushShape = shape);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.brushShape = shape;
    unawaited(AppPreferences.save());
  }

  void _updateStrokeStabilizerStrength(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    if ((_strokeStabilizerStrength - clamped).abs() < 0.0005) {
      return;
    }
    setState(() => _strokeStabilizerStrength = clamped);
    _strokeStabilizer.reset();
    final AppPreferences prefs = AppPreferences.instance;
    prefs.strokeStabilizerStrength = clamped;
    unawaited(AppPreferences.save());
  }

  @override
  void _updatePenPressureSimulation(bool value) {
    if (_simulatePenPressure == value) {
      return;
    }
    setState(() => _simulatePenPressure = value);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.simulatePenPressure = value;
    unawaited(AppPreferences.save());
  }

  void _updateStylusPressureEnabled(bool value) {
    if (_stylusPressureEnabled == value) {
      return;
    }
    setState(() => _stylusPressureEnabled = value);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.stylusPressureEnabled = value;
    unawaited(AppPreferences.save());
    _applyStylusSettingsToController();
  }

  @override
  void _updatePenPressureProfile(StrokePressureProfile profile) {
    if (_penPressureProfile == profile) {
      return;
    }
    setState(() => _penPressureProfile = profile);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.penPressureProfile = profile;
    unawaited(AppPreferences.save());
  }

  @override
  void _updatePenAntialiasLevel(int value) {
    final int clamped = value.clamp(0, 3);
    if (_penAntialiasLevel == clamped) {
      return;
    }
    setState(() => _penAntialiasLevel = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.penAntialiasLevel = clamped;
    unawaited(AppPreferences.save());
  }

  @override
  void _updateAutoSharpPeakEnabled(bool value) {
    if (_autoSharpPeakEnabled == value) {
      return;
    }
    setState(() => _autoSharpPeakEnabled = value);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.autoSharpPeakEnabled = value;
    unawaited(AppPreferences.save());
    _applyStylusSettingsToController();
  }

  void _updateBucketSampleAllLayers(bool value) {
    if (_bucketSampleAllLayers == value) {
      return;
    }
    setState(() => _bucketSampleAllLayers = value);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.bucketSampleAllLayers = value;
    unawaited(AppPreferences.save());
  }

  void _updateBucketContiguous(bool value) {
    if (_bucketContiguous == value) {
      return;
    }
    setState(() => _bucketContiguous = value);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.bucketContiguous = value;
    unawaited(AppPreferences.save());
  }

  void _updateBucketSwallowColorLine(bool value) {
    if (_bucketSwallowColorLine == value) {
      return;
    }
    setState(() => _bucketSwallowColorLine = value);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.bucketSwallowColorLine = value;
    unawaited(AppPreferences.save());
  }

  void _updateLayerAdjustCropOutside(bool value) {
    if (_layerAdjustCropOutside == value) {
      return;
    }
    setState(() => _layerAdjustCropOutside = value);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.layerAdjustCropOutside = value;
    unawaited(AppPreferences.save());
    _controller.setLayerOverflowCropping(value);
  }

  bool _isStylusEvent(PointerEvent event) {
    return TabletInputBridge.instance.isTabletPointer(event);
  }

  double? _stylusPressureValue(PointerEvent? event) {
    return TabletInputBridge.instance.pressureForEvent(event);
  }

  double? _stylusPressureBound(double? bound) {
    if (bound == null || !bound.isFinite) {
      return null;
    }
    return bound;
  }

  void _startStroke(
    Offset position,
    Duration timestamp,
    PointerEvent? rawEvent,
  ) {
    final Offset start = _sanitizeStrokePosition(
      position,
      isInitialSample: true,
    );
    _activeStrokeUsesStylus =
        rawEvent != null && _stylusPressureEnabled && _isStylusEvent(rawEvent);
    final bool combineStylusAndSimulation =
        _simulatePenPressure && _activeStrokeUsesStylus;
    final double stylusBlend = combineStylusAndSimulation
        ? _kStylusSimulationBlend
        : 1.0;
    final double? stylusPressure = _stylusPressureValue(rawEvent);
    if (_activeStrokeUsesStylus) {
      _activeStylusPressureMin = _stylusPressureBound(rawEvent?.pressureMin);
      _activeStylusPressureMax = _stylusPressureBound(rawEvent?.pressureMax);
    } else {
      _activeStylusPressureMin = null;
      _activeStylusPressureMax = null;
    }
    _lastStrokeBoardPosition = start;
    _lastStylusDirection = null;
    _lastStylusPressureValue = stylusPressure?.clamp(0.0, 1.0);
    _lastStylusPressureValue = stylusPressure?.clamp(0.0, 1.0);
    _pushUndoSnapshot();
    _lastPenSampleTimestamp = timestamp;
    setState(() => _isDrawing = true);
    _controller.beginStroke(
      start,
      color: _primaryColor,
      radius: _penStrokeWidth / 2,
      simulatePressure: _simulatePenPressure,
      useDevicePressure: _activeStrokeUsesStylus,
      stylusPressureBlend: stylusBlend,
      pressure: stylusPressure,
      pressureMin: _activeStylusPressureMin,
      pressureMax: _activeStylusPressureMax,
      profile: _penPressureProfile,
      timestampMillis: timestamp.inMicroseconds / 1000.0,
      antialiasLevel: _penAntialiasLevel,
      brushShape: _brushShape,
    );
    _markDirty();
  }

  void _appendPoint(
    Offset position,
    Duration timestamp,
    PointerEvent? rawEvent,
  ) {
    if (!_isDrawing) {
      return;
    }
    final double? deltaMillis = _registerPenSample(timestamp);
    final Offset clamped = _sanitizeStrokePosition(position);
    double? stylusPressure = _stylusPressureValue(rawEvent);
    if (_activeStrokeUsesStylus &&
        rawEvent != null &&
        _isStylusEvent(rawEvent)) {
      final double? candidateMin = _stylusPressureBound(rawEvent.pressureMin);
      final double? candidateMax = _stylusPressureBound(rawEvent.pressureMax);
      if (candidateMin != null) {
        _activeStylusPressureMin = candidateMin;
      }
      if (candidateMax != null) {
        _activeStylusPressureMax = candidateMax;
      }
    }
    final Offset? previousPoint = _lastStrokeBoardPosition;
    if (previousPoint != null) {
      final Offset delta = clamped - previousPoint;
      if (delta.distanceSquared > 1e-5) {
        _lastStylusDirection = delta / delta.distance;
      }
    }
    _lastStrokeBoardPosition = clamped;
    if (stylusPressure != null && stylusPressure.isFinite) {
      _lastStylusPressureValue = stylusPressure.clamp(0.0, 1.0);
    }
    _controller.extendStroke(
      clamped,
      deltaTimeMillis: deltaMillis,
      timestampMillis: timestamp.inMicroseconds / 1000.0,
      pressure: stylusPressure,
      pressureMin: _activeStylusPressureMin,
      pressureMax: _activeStylusPressureMax,
    );
  }

  void _appendStylusReleaseSample(
    Offset boardLocal,
    Duration timestamp,
    double? pressure,
  ) {
    if (!_activeStrokeUsesStylus) {
      return;
    }
    double targetPressure = (pressure ?? 0.0).clamp(0.0, 1.0);
    const double kMinPressure = 0.0001;
    if ((targetPressure <= kMinPressure || !targetPressure.isFinite) &&
        (_lastStylusPressureValue ?? 0.0) > kMinPressure) {
      targetPressure = _lastStylusPressureValue!.clamp(0.0, 1.0);
    } else if (targetPressure > kMinPressure) {
      _lastStylusPressureValue = targetPressure;
    }
    final double? deltaMillis = _registerPenSample(timestamp);
    _emitReleaseSamples(
      anchor: boardLocal,
      direction: _lastStylusDirection,
      timestampMillis: timestamp.inMicroseconds / 1000.0,
      initialDeltaMillis: deltaMillis,
      pressure: targetPressure,
      enableSharpPeak: _autoSharpPeakEnabled,
    );
    _lastStylusPressureValue = 0.0;
  }

  void _finishStroke([Duration? timestamp]) {
    if (!_isDrawing) {
      return;
    }
    if (timestamp != null) {
      _registerPenSample(timestamp);
    }
    _controller.endStroke();
    setState(() {
      _isDrawing = false;
    });
    _lastPenSampleTimestamp = null;
    _activeStrokeUsesStylus = false;
    _activeStylusPressureMin = null;
    _activeStylusPressureMax = null;
    _lastStylusPressureValue = null;
    _lastStrokeBoardPosition = null;
    _lastStylusDirection = null;
    _strokeStabilizer.reset();
  }

  void _emitReleaseSamples({
    required Offset anchor,
    Offset? direction,
    required double timestampMillis,
    double? initialDeltaMillis,
    required double pressure,
    required bool enableSharpPeak,
  }) {
    const int kTailSteps = 5;
    const double kTailDeltaMs = 6.0;
    final double clampedPressure = pressure.clamp(0.0, 1.0);

    final Offset dir = (direction != null && direction.distanceSquared > 1e-5)
        ? (direction / direction.distance)
        : Offset.zero;
    final double stepDistance = math.max(_penStrokeWidth * 0.35, 3.0);
    Offset currentPoint = anchor;

    _controller.extendStroke(
      currentPoint,
      deltaTimeMillis: initialDeltaMillis,
      timestampMillis: timestampMillis,
      pressure: clampedPressure,
      pressureMin: _activeStylusPressureMin,
      pressureMax: _activeStylusPressureMax,
    );

    if (!enableSharpPeak) {
      return;
    }

    double nextTimestamp = timestampMillis + (initialDeltaMillis ?? 0.0);
    if (clampedPressure <= 0.0001) {
      nextTimestamp += kTailDeltaMs;
      if (dir != Offset.zero) {
        currentPoint = currentPoint + dir * stepDistance;
      }
      _controller.extendStroke(
        currentPoint,
        deltaTimeMillis: kTailDeltaMs,
        timestampMillis: nextTimestamp,
        pressure: 0.0,
        pressureMin: _activeStylusPressureMin,
        pressureMax: _activeStylusPressureMax,
      );
      return;
    }

    for (int i = 0; i < kTailSteps; i++) {
      final double t = (i + 1) / (kTailSteps + 1);
      final double virtualPressure = (clampedPressure * (1.0 - t)).clamp(
        0.0,
        1.0,
      );
      if (virtualPressure <= 0.0001) {
        break;
      }
      nextTimestamp += kTailDeltaMs;
      if (dir != Offset.zero) {
        currentPoint = currentPoint + dir * stepDistance;
      }
      _controller.extendStroke(
        currentPoint,
        deltaTimeMillis: kTailDeltaMs,
        timestampMillis: nextTimestamp,
        pressure: virtualPressure,
        pressureMin: _activeStylusPressureMin,
        pressureMax: _activeStylusPressureMax,
      );
    }

    nextTimestamp += kTailDeltaMs;
    if (dir != Offset.zero) {
      currentPoint = currentPoint + dir * stepDistance;
    }
    _controller.extendStroke(
      currentPoint,
      deltaTimeMillis: kTailDeltaMs,
      timestampMillis: nextTimestamp,
      pressure: 0.0,
      pressureMin: _activeStylusPressureMin,
      pressureMax: _activeStylusPressureMax,
    );
  }

  Offset _sanitizeStrokePosition(
    Offset position, {
    bool isInitialSample = false,
  }) {
    final Offset clamped = _clampToCanvas(position);
    final bool enableStabilizer =
        _strokeStabilizerStrength > 0.0001 &&
        _effectiveActiveTool == CanvasTool.pen;
    if (!enableStabilizer) {
      if (isInitialSample) {
        _strokeStabilizer.reset();
      }
      return clamped;
    }
    if (isInitialSample) {
      _strokeStabilizer.start(clamped);
      return clamped;
    }
    return _strokeStabilizer.filter(clamped, _strokeStabilizerStrength);
  }

  double? _registerPenSample(Duration timestamp) {
    final Duration? previous = _lastPenSampleTimestamp;
    _lastPenSampleTimestamp = timestamp;
    if (previous == null) {
      return null;
    }
    final Duration delta = timestamp - previous;
    if (delta <= Duration.zero) {
      return null;
    }
    return delta.inMicroseconds / 1000.0;
  }

  void _beginDragBoard() {
    setState(() => _isDraggingBoard = true);
  }

  void _updateDragBoard(Offset delta) {
    if (!_isDraggingBoard) {
      return;
    }
    setState(() {
      _viewport.translate(delta);
    });
  }

  void _finishDragBoard() {
    if (!_isDraggingBoard) {
      return;
    }
    setState(() => _isDraggingBoard = false);
  }

  void _beginEyedropperSample(Offset boardLocal) {
    if (!_isWithinCanvas(boardLocal)) {
      return;
    }
    setState(() {
      _isEyedropperSampling = true;
      _lastEyedropperSample = boardLocal;
    });
    _applyEyedropperSample(boardLocal, remember: false);
  }

  void _updateEyedropperSample(Offset boardLocal) {
    if (!_isEyedropperSampling || !_isWithinCanvas(boardLocal)) {
      return;
    }
    final Offset? previous = _lastEyedropperSample;
    if (previous != null && (previous - boardLocal).distanceSquared < 1.0) {
      return;
    }
    _lastEyedropperSample = boardLocal;
    _applyEyedropperSample(boardLocal, remember: false);
  }

  void _finishEyedropperSample() {
    if (!_isEyedropperSampling) {
      return;
    }
    final Offset? sample = _lastEyedropperSample;
    if (sample != null) {
      _applyEyedropperSample(sample);
    }
    setState(() {
      _isEyedropperSampling = false;
      _lastEyedropperSample = null;
    });
  }

  void _cancelEyedropperSample() {
    if (!_isEyedropperSampling) {
      return;
    }
    setState(() {
      _isEyedropperSampling = false;
      _lastEyedropperSample = null;
    });
  }

  void _applyEyedropperSample(Offset boardLocal, {bool remember = true}) {
    final Color color = _controller.sampleColor(
      boardLocal,
      sampleAllLayers: true,
    );
    _setPrimaryColor(color, remember: remember);
  }

  void _updateToolCursorOverlay(Offset workspacePosition) {
    final CanvasTool tool = _effectiveActiveTool;
    final bool overlayTool = ToolCursorStyles.hasOverlay(tool);
    final bool isPenLike =
        tool == CanvasTool.pen ||
        tool == CanvasTool.curvePen ||
        tool == CanvasTool.shape;
    if (_isReferenceCardResizing) {
      if (_toolCursorPosition != null || _penCursorWorkspacePosition != null) {
        setState(() {
          _toolCursorPosition = null;
          _penCursorWorkspacePosition = null;
        });
      }
      return;
    }
    if (!overlayTool && !isPenLike) {
      if (_toolCursorPosition != null || _penCursorWorkspacePosition != null) {
        setState(() {
          _toolCursorPosition = null;
          _penCursorWorkspacePosition = null;
        });
      }
      return;
    }
    if (_isInsideToolArea(workspacePosition) ||
        _isInsideWorkspacePanelArea(workspacePosition)) {
      if (_toolCursorPosition != null || _penCursorWorkspacePosition != null) {
        setState(() {
          _toolCursorPosition = null;
          _penCursorWorkspacePosition = null;
        });
      }
      return;
    }
    final Rect boardRect = _boardRect;
    if (!boardRect.contains(workspacePosition)) {
      if (_toolCursorPosition != null || _penCursorWorkspacePosition != null) {
        setState(() {
          _toolCursorPosition = null;
          _penCursorWorkspacePosition = null;
        });
      }
      return;
    }
    if (overlayTool) {
      final Offset? current = _toolCursorPosition;
      if (current != null &&
          (current - workspacePosition).distanceSquared < 0.25) {
        return;
      }
      setState(() {
        _toolCursorPosition = workspacePosition;
        _penCursorWorkspacePosition = null;
      });
    } else if (isPenLike) {
      final Offset? current = _penCursorWorkspacePosition;
      if (current != null &&
          (current - workspacePosition).distanceSquared < 0.25) {
        return;
      }
      setState(() {
        _penCursorWorkspacePosition = workspacePosition;
        _toolCursorPosition = null;
      });
    }
  }

  void _clearToolCursorOverlay() {
    if (_toolCursorPosition == null && _penCursorWorkspacePosition == null) {
      return;
    }
    setState(() {
      _toolCursorPosition = null;
      _penCursorWorkspacePosition = null;
    });
  }

  void _recordWorkspacePointer(Offset workspacePosition) {
    if (_isInsideToolArea(workspacePosition)) {
      _lastWorkspacePointer = null;
    } else {
      _lastWorkspacePointer = workspacePosition;
    }
  }

  @override
  void _handleWorkspacePointerExit() {
    if (_effectiveActiveTool == CanvasTool.selection) {
      _clearSelectionHover();
    }
    _clearToolCursorOverlay();
    _lastWorkspacePointer = null;
  }

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
    if (_isLayerDragging) {
      _finishLayerAdjustDrag();
    }
    if (_activeTool == CanvasTool.curvePen) {
      _resetCurvePenState();
    }
  }

  void _beginLayerAdjustDrag(Offset boardLocal) {
    final BitmapLayerState? layer = _activeLayerForAdjustment();
    if (layer == null || layer.locked) {
      return;
    }
    if (_controller.isActiveLayerTransformPendingCleanup) {
      return;
    }
    _focusNode.requestFocus();
    _pushUndoSnapshot();
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
    _markDirty();
  }

  void _finishLayerAdjustDrag() {
    if (!_isLayerDragging) {
      return;
    }
    _controller.commitActiveLayerTranslation();
    _isLayerDragging = false;
    _layerDragStart = null;
    _layerDragAppliedDx = 0;
    _layerDragAppliedDy = 0;
  }

  void _handleCurvePenPointerDown(Offset boardLocal) {
    _focusNode.requestFocus();
    final bool insideCanvas = _isWithinCanvasBounds(boardLocal);
    if (_curveAnchor == null) {
      if (insideCanvas && !isPointInsideSelection(boardLocal)) {
        return;
      }
      if (insideCanvas) {
        _pushUndoSnapshot();
        _controller.beginStroke(
          boardLocal,
          color: _primaryColor,
          radius: _penStrokeWidth / 2,
          simulatePressure: _simulatePenPressure,
          profile: _penPressureProfile,
          antialiasLevel: _penAntialiasLevel,
          brushShape: _brushShape,
        );
        _controller.endStroke();
        _markDirty();
      }
      setState(() {
        _curveAnchor = boardLocal;
        _curvePreviewPath = null;
      });
      return;
    }
    if (_isCurvePlacingSegment) {
      return;
    }
    if (insideCanvas && !isPointInsideSelection(boardLocal)) {
      return;
    }
    setState(() {
      _curvePendingEnd = boardLocal;
      _curveDragOrigin = boardLocal;
      _curveDragDelta = Offset.zero;
      _isCurvePlacingSegment = true;
      _curvePreviewPath = _buildCurvePreviewPath();
    });
  }

  void _handleCurvePenPointerMove(Offset boardLocal) {
    if (!_isCurvePlacingSegment || _curveDragOrigin == null) {
      return;
    }
    setState(() {
      _curveDragDelta = boardLocal - _curveDragOrigin!;
      _curvePreviewPath = _buildCurvePreviewPath();
    });
  }

  void _handleCurvePenPointerUp() {
    if (!_isCurvePlacingSegment) {
      return;
    }
    final Offset? start = _curveAnchor;
    final Offset? end = _curvePendingEnd;
    if (start == null || end == null) {
      _cancelCurvePenSegment();
      return;
    }
    _pushUndoSnapshot();
    final Offset control = _computeCurveControlPoint(
      start,
      end,
      _curveDragDelta,
    );
    _drawQuadraticCurve(start, control, end);
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

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

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
    final Offset strokeStart = _clampToCanvas(start);
    _controller.beginStroke(
      strokeStart,
      color: _primaryColor,
      radius: _penStrokeWidth / 2,
      simulatePressure: simulatePressure,
      profile: _penPressureProfile,
      timestampMillis: initialTimestamp,
      antialiasLevel: _penAntialiasLevel,
      brushShape: _brushShape,
      enableNeedleTips: enableNeedleTips,
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

  void _handlePointerDown(PointerDownEvent event) {
    if (!_isPrimaryPointer(event)) {
      return;
    }
    if (_isScalingGesture) {
      return;
    }
    _recordWorkspacePointer(event.localPosition);
    _updateToolCursorOverlay(event.localPosition);
    final Offset pointer = event.localPosition;
    if (_isInsideToolArea(pointer) ||
        _isInsideWorkspacePanelArea(pointer)) {
      return;
    }
    final CanvasTool tool = _effectiveActiveTool;
    final Rect boardRect = _boardRect;
    final bool pointerInsideBoard = boardRect.contains(pointer);
    final bool toolCanStartOutsideCanvas =
        tool == CanvasTool.curvePen || tool == CanvasTool.selection;
    if (!pointerInsideBoard && !toolCanStartOutsideCanvas) {
      return;
    }
    final Offset boardLocal = _toBoardLocal(pointer);
    switch (tool) {
      case CanvasTool.layerAdjust:
        _beginLayerAdjustDrag(boardLocal);
        break;
      case CanvasTool.pen:
        _focusNode.requestFocus();
        if (!isPointInsideSelection(boardLocal)) {
          return;
        }
        _refreshStylusPreferencesIfNeeded();
        _startStroke(boardLocal, event.timeStamp, event);
        break;
      case CanvasTool.curvePen:
        if (_isCurveCancelModifierPressed() &&
            (_curveAnchor != null || _isCurvePlacingSegment)) {
          _resetCurvePenState();
          return;
        }
        _handleCurvePenPointerDown(boardLocal);
        break;
      case CanvasTool.shape:
        _focusNode.requestFocus();
        _beginShapeDrawing(boardLocal);
        break;
      case CanvasTool.bucket:
        _focusNode.requestFocus();
        if (!isPointInsideSelection(boardLocal)) {
          return;
        }
        unawaited(_applyPaintBucket(boardLocal));
        break;
      case CanvasTool.magicWand:
        _focusNode.requestFocus();
        _handleMagicWandPointerDown(boardLocal);
        break;
      case CanvasTool.eyedropper:
        _focusNode.requestFocus();
        _beginEyedropperSample(boardLocal);
        break;
      case CanvasTool.selection:
        _focusNode.requestFocus();
        _handleSelectionPointerDown(boardLocal, event.timeStamp);
        break;
      case CanvasTool.hand:
        _beginDragBoard();
        break;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isPrimaryPointer(event)) {
      return;
    }
    if (_isScalingGesture) {
      return;
    }
    _recordWorkspacePointer(event.localPosition);
    _updateToolCursorOverlay(event.localPosition);
    switch (_effectiveActiveTool) {
      case CanvasTool.pen:
        if (_isDrawing) {
          final Offset boardLocal = _toBoardLocal(event.localPosition);
          _appendPoint(boardLocal, event.timeStamp, event);
        }
        break;
      case CanvasTool.layerAdjust:
        final Offset boardLocal = _toBoardLocal(event.localPosition);
        _updateLayerAdjustDrag(boardLocal);
        break;
      case CanvasTool.curvePen:
        final Offset boardLocal = _toBoardLocal(event.localPosition);
        _handleCurvePenPointerMove(boardLocal);
        break;
      case CanvasTool.shape:
        if (_shapeDragStart != null) {
          final Offset boardLocal = _toBoardLocal(event.localPosition);
          _updateShapeDrawing(boardLocal);
        }
        break;
      case CanvasTool.bucket:
      case CanvasTool.magicWand:
        break;
      case CanvasTool.eyedropper:
        final Offset boardLocal = _toBoardLocal(event.localPosition);
        _updateEyedropperSample(boardLocal);
        break;
      case CanvasTool.selection:
        final Offset boardLocal = _toBoardLocal(event.localPosition);
        _handleSelectionPointerMove(boardLocal);
        break;
      case CanvasTool.hand:
        if (_isDraggingBoard) {
          _updateDragBoard(event.delta);
        }
        break;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    switch (_effectiveActiveTool) {
      case CanvasTool.pen:
        if (_isDrawing) {
          final Offset boardLocal = _toBoardLocal(event.localPosition);
          final double? releasePressure = _stylusPressureValue(event);
          if (_activeStrokeUsesStylus) {
            _appendStylusReleaseSample(
              boardLocal,
              event.timeStamp,
              releasePressure,
            );
            _finishStroke();
          } else {
            _finishStroke(event.timeStamp);
          }
        }
        break;
      case CanvasTool.layerAdjust:
        if (_isLayerDragging) {
          _finishLayerAdjustDrag();
        }
        break;
      case CanvasTool.curvePen:
        _handleCurvePenPointerUp();
        break;
      case CanvasTool.shape:
        _finishShapeDrawing();
        break;
      case CanvasTool.bucket:
      case CanvasTool.magicWand:
        break;
      case CanvasTool.eyedropper:
        _finishEyedropperSample();
        break;
      case CanvasTool.selection:
        _handleSelectionPointerUp();
        break;
      case CanvasTool.hand:
        if (_isDraggingBoard) {
          _finishDragBoard();
        }
        break;
      case CanvasTool.curvePen:
        _handleCurvePenPointerUp();
        break;
      case CanvasTool.layerAdjust:
        if (_isLayerDragging) {
          _finishLayerAdjustDrag();
        }
        break;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    switch (_effectiveActiveTool) {
      case CanvasTool.pen:
        if (_isDrawing) {
          _finishStroke(event.timeStamp);
        }
        break;
      case CanvasTool.layerAdjust:
        if (_isLayerDragging) {
          _finishLayerAdjustDrag();
        }
        break;
      case CanvasTool.eyedropper:
        _cancelEyedropperSample();
        break;
      case CanvasTool.curvePen:
        _cancelCurvePenSegment();
        break;
      case CanvasTool.shape:
        _cancelShapeDrawing();
        break;
      case CanvasTool.selection:
        _handleSelectionPointerCancel();
        break;
      case CanvasTool.hand:
        if (_isDraggingBoard) {
          _finishDragBoard();
        }
        break;
      case CanvasTool.bucket:
      case CanvasTool.magicWand:
        break;
    }
  }

  void _handlePointerHover(PointerHoverEvent event) {
    _recordWorkspacePointer(event.localPosition);
    _updateToolCursorOverlay(event.localPosition);
    if (_effectiveActiveTool != CanvasTool.selection) {
      return;
    }
    final Offset boardLocal = _toBoardLocal(event.localPosition);
    _handleSelectionHover(boardLocal);
  }

  @override
  KeyEventResult _handleWorkspaceKeyEvent(FocusNode node, KeyEvent event) {
    final LogicalKeyboardKey key = event.logicalKey;
    if (_isAltKey(key) && _activeTool != CanvasTool.eyedropper) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (_eyedropperOverrideActive) {
          return KeyEventResult.handled;
        }
        _interruptForEyedropperOverride();
        final Offset? pointer = _lastWorkspacePointer;
        setState(() {
          _eyedropperOverrideActive = true;
          if (pointer != null && _boardRect.contains(pointer)) {
            _toolCursorPosition = pointer;
          }
          _penCursorWorkspacePosition = null;
        });
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        if (!_eyedropperOverrideActive) {
          return KeyEventResult.handled;
        }
        _finishEyedropperSample();
        setState(() {
          _eyedropperOverrideActive = false;
          _toolCursorPosition = null;
          _penCursorWorkspacePosition = null;
        });
        final Offset? pointer = _lastWorkspacePointer;
        if (pointer != null && _boardRect.contains(pointer)) {
          _updateToolCursorOverlay(pointer);
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (key != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (_spacePanOverrideActive) {
        return KeyEventResult.handled;
      }
      setState(() {
        _spacePanOverrideActive = true;
        _penCursorWorkspacePosition = null;
      });
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      if (!_spacePanOverrideActive) {
        return KeyEventResult.handled;
      }
      if (_isDraggingBoard) {
        _finishDragBoard();
      }
      setState(() => _spacePanOverrideActive = false);
      final Offset? pointer = _lastWorkspacePointer;
      if (pointer != null && _boardRect.contains(pointer)) {
        _updateToolCursorOverlay(pointer);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _applyZoom(double targetScale, Offset workspaceFocalPoint) {
    if (_workspaceSize.isEmpty) {
      return;
    }
    final double currentScale = _viewport.scale;
    final double clamped = _viewport.clampScale(targetScale);
    if ((clamped - currentScale).abs() < 0.0005) {
      return;
    }
    final Offset currentBase = _baseOffsetForScale(currentScale);
    final Offset currentOrigin = currentBase + _viewport.offset;
    final Offset boardLocal =
        (workspaceFocalPoint - currentOrigin) / currentScale;

    final Offset newBase = _baseOffsetForScale(clamped);
    final Offset newOrigin = workspaceFocalPoint - boardLocal * clamped;
    final Offset newOffset = newOrigin - newBase;

    setState(() {
      _viewport.setScale(clamped);
      _viewport.setOffset(newOffset);
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final double scrollDelta = event.scrollDelta.dy;
    if (scrollDelta == 0) {
      return;
    }
    final Offset focalPoint = box.globalToLocal(event.position);
    const double sensitivity = 0.0015;
    final double targetScale =
        _viewport.scale * (1 - scrollDelta * sensitivity);
    _applyZoom(targetScale, focalPoint);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final bool shouldScale =
        details.pointerCount == 0 || details.pointerCount > 1;
    _isScalingGesture = shouldScale;
    if (!shouldScale) {
      return;
    }
    _scaleGestureInitialScale = _viewport.scale;
    final Offset focalPoint = box.globalToLocal(details.focalPoint);
    _applyZoom(_viewport.scale, focalPoint);
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (!_isScalingGesture) {
      return;
    }
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final Offset focalPoint = box.globalToLocal(details.focalPoint);
    final double targetScale = _scaleGestureInitialScale * details.scale;
    _applyZoom(targetScale, focalPoint);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _isScalingGesture = false;
  }

  void _handleUndo() {
    if (!undo()) {
      widget.onUndoFallback?.call();
    }
  }

  void _handleRedo() {
    if (!redo()) {
      widget.onRedoFallback?.call();
    }
  }

  bool undo() {
    _refreshHistoryLimit();
    if (_undoStack.isEmpty) {
      return false;
    }
    final _CanvasHistoryEntry previous = _undoStack.removeLast();
    _redoStack.add(_createHistoryEntry());
    _trimHistoryStacks();
    _applyHistoryEntry(previous);
    return true;
  }

  bool redo() {
    _refreshHistoryLimit();
    if (_redoStack.isEmpty) {
      return false;
    }
    final _CanvasHistoryEntry next = _redoStack.removeLast();
    _undoStack.add(_createHistoryEntry());
    _trimHistoryStacks();
    _applyHistoryEntry(next);
    return true;
  }

  bool zoomIn() {
    return _zoomByFactor(_zoomStep);
  }

  bool zoomOut() {
    return _zoomByFactor(1 / _zoomStep);
  }

  bool _zoomByFactor(double factor) {
    if (_workspaceSize.isEmpty) {
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        return false;
      }
      _workspaceSize = box.size;
    }
    final Offset focalPoint = _boardRect.center;
    _applyZoom(_viewport.scale * factor, focalPoint);
    return true;
  }
}

class _StrokeStabilizer {
  Offset? _filtered;

  void start(Offset position) {
    _filtered = position;
  }

  Offset filter(Offset position, double strength) {
    final double clampedStrength = strength.clamp(0.0, 1.0);
    final Offset? previous = _filtered;
    if (previous == null) {
      _filtered = position;
      return position;
    }
    final Offset delta = position - previous;
    final double distance = delta.distance;
    if (distance <= 1e-4) {
      return previous;
    }
    final double easedStrength = math.pow(clampedStrength, 0.82).toDouble();
    final double extendedStrength = math.pow(clampedStrength, 1.12).toDouble();
    final double followFloor = ui.lerpDouble(1.0, 0.08, easedStrength) ?? 1.0;
    final double catchupDistance =
        ui.lerpDouble(1.5, 48.0, extendedStrength) ?? 6.5;
    final double releaseFactor = math
        .pow((distance / catchupDistance).clamp(0.0, 1.0), 0.85)
        .toDouble();
    final double mix =
        ui.lerpDouble(followFloor, 1.0, releaseFactor) ?? followFloor;
    final Offset filtered = previous + delta * mix;
    _filtered = filtered;
    return filtered;
  }

  void reset() {
    _filtered = null;
  }
}
