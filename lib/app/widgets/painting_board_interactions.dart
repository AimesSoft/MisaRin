part of 'painting_board.dart';

mixin _PaintingBoardInteractionMixin on _PaintingBoardBase {
  void clear() {
    _store.clear();
    _emitClean();
    _syncStrokeCache();
    setState(() {
      _bumpCurrentStrokeVersion();
    });
  }

  bool _isPrimaryPointer(PointerEvent event) {
    return event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kPrimaryMouseButton) != 0;
  }

  Rect get _toolbarRect => Rect.fromLTWH(
        _toolButtonPadding,
        _toolButtonPadding,
        _toolbarButtonSize,
        _toolbarButtonSize * 6 + _toolbarSpacing * 5,
      );

  Rect get _toolSettingsRect => Rect.fromLTWH(
        _toolButtonPadding + _toolbarButtonSize + _toolSettingsSpacing,
        _toolButtonPadding,
        _toolSettingsCardWidth,
        _toolSettingsCardHeight,
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
      (_workspaceSize.height - 2 * _toolButtonPadding)
          .clamp(0.0, double.infinity),
    );
  }

  bool _isInsideToolArea(Offset workspacePosition) {
    return _toolbarRect.contains(workspacePosition) ||
        _toolSettingsRect.contains(workspacePosition) ||
        _rightSidebarRect.contains(workspacePosition) ||
        _colorIndicatorRect.contains(workspacePosition);
  }

  void _setActiveTool(CanvasTool tool) {
    if (_activeTool == tool) {
      return;
    }
    setState(() => _activeTool = tool);
  }

  void _updatePenStrokeWidth(double value) {
    final double clamped = value.clamp(1.0, 60.0);
    if ((_penStrokeWidth - clamped).abs() < 0.01) {
      return;
    }
    setState(() => _penStrokeWidth = clamped);
  }

  void _updateBucketSampleAllLayers(bool value) {
    if (_bucketSampleAllLayers == value) {
      return;
    }
    setState(() => _bucketSampleAllLayers = value);
    _markDirty();
  }

  void _updateBucketContiguous(bool value) {
    if (_bucketContiguous == value) {
      return;
    }
    setState(() => _bucketContiguous = value);
    _markDirty();
  }

  void _startStroke(Offset position) {
    setState(() {
      _isDrawing = true;
      _store.startStroke(
        position,
        color: _primaryColor,
        width: _penStrokeWidth,
      );
      _bumpCurrentStrokeVersion();
    });
    _markDirty();
  }

  void _appendPoint(Offset position) {
    if (!_isDrawing) {
      return;
    }
    setState(() {
      _store.appendPoint(position);
      _bumpCurrentStrokeVersion();
    });
  }

  void _finishStroke() {
    if (!_isDrawing) {
      return;
    }
    _store.finishStroke();
    _syncStrokeCache();
    setState(() {
      _isDrawing = false;
      _bumpCurrentStrokeVersion();
    });
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

  void _handlePointerDown(PointerDownEvent event) {
    if (!_isPrimaryPointer(event)) {
      return;
    }
    if (_isScalingGesture) {
      return;
    }
    final Offset pointer = event.localPosition;
    if (_isInsideToolArea(pointer)) {
      return;
    }
    final Rect boardRect = _boardRect;
    if (!boardRect.contains(pointer)) {
      return;
    }
    final Offset boardLocal = _toBoardLocal(pointer);
    if (_activeTool == CanvasTool.pen) {
      _focusNode.requestFocus();
      _startStroke(boardLocal);
    } else if (_activeTool == CanvasTool.bucket) {
      _focusNode.requestFocus();
      unawaited(_applyPaintBucket(boardLocal));
    } else {
      _beginDragBoard();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isPrimaryPointer(event)) {
      return;
    }
    if (_isScalingGesture) {
      return;
    }
    if (_isDrawing && _activeTool == CanvasTool.pen) {
      final Offset boardLocal = _toBoardLocal(event.localPosition);
      _appendPoint(boardLocal);
    } else if (_isDraggingBoard && _activeTool == CanvasTool.hand) {
      _updateDragBoard(event.delta);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_isDrawing && _activeTool == CanvasTool.pen) {
      _finishStroke();
    }
    if (_isDraggingBoard && _activeTool == CanvasTool.hand) {
      _finishDragBoard();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_isDrawing && _activeTool == CanvasTool.pen) {
      _finishStroke();
    }
    if (_isDraggingBoard && _activeTool == CanvasTool.hand) {
      _finishDragBoard();
    }
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
    final Size currentScaledSize = Size(
      _canvasSize.width * currentScale,
      _canvasSize.height * currentScale,
    );
    final Offset currentBase = Offset(
      (_workspaceSize.width - currentScaledSize.width) / 2,
      (_workspaceSize.height - currentScaledSize.height) / 2,
    );
    final Offset currentOrigin = currentBase + _viewport.offset;
    final Offset boardLocal =
        (workspaceFocalPoint - currentOrigin) / currentScale;

    final Size newScaledSize = Size(
      _canvasSize.width * clamped,
      _canvasSize.height * clamped,
    );
    final Offset newBase = Offset(
      (_workspaceSize.width - newScaledSize.width) / 2,
      (_workspaceSize.height - newScaledSize.height) / 2,
    );
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
    undo();
  }

  void _handleRedo() {
    redo();
  }

  bool undo() {
    final bool undone = _store.undo();
    if (!undone) {
      return false;
    }
    _syncStrokeCache();
    setState(() {
      _isDrawing = false;
      _bumpCurrentStrokeVersion();
    });
    if (!_store.hasStrokes) {
      _emitClean();
    } else {
      _markDirty();
    }
    return true;
  }

  bool redo() {
    final bool redone = _store.redo();
    if (!redone) {
      return false;
    }
    _syncStrokeCache();
    setState(() {
      _bumpCurrentStrokeVersion();
    });
    _markDirty();
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
    final Offset focalPoint = Offset(
      _workspaceSize.width / 2,
      _workspaceSize.height / 2,
    );
    _applyZoom(_viewport.scale * factor, focalPoint);
    return true;
  }
}
