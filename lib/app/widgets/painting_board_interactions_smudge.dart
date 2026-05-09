part of 'painting_board.dart';

extension _PaintingBoardInteractionSmudgeExtension
    on _PaintingBoardInteractionMixin {
  double _resolveSmudgeRadius() {
    double radius = (_smudgeStrokeWidth / 2.0).clamp(4.0, 250.0).toDouble();
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
    return radius.clamp(4.0, 4096.0).toDouble();
  }

  Future<void> _startSmudgeStroke(Offset boardLocal, PointerEvent event) async {
    if (!isPointInsideSelection(boardLocal)) {
      return;
    }
    _focusNode.requestFocus();
    if (!_isBackendDrawingPointer(event)) {
      return;
    }
    if (!_backend.supportsSmudge) {
      _showBackendCanvasMessage('涂抹工具需要画布后端支持。');
      return;
    }
    if (_isActiveLayerLocked()) {
      _showBackendCanvasMessage('当前图层已锁定。');
      return;
    }
    if (!_backend.beginSmudge()) {
      _showBackendCanvasMessage('画布后端尚未准备好。');
      return;
    }
    final Offset clamped = _clampToCanvas(boardLocal);
    final Offset enginePoint = _backendToEngineSpace(clamped);
    _isSmudging = true;
    _backendSmudgeHasDrawn = false;
    _smudgeLastEnginePoint = enginePoint;
    _smudgeResidual = 0.0;
    _drawSmudgeSegment(enginePoint, enginePoint, event);
    setState(() {
      _penCursorWorkspacePosition = event.localPosition;
    });
  }

  void _updateSmudgeStroke(Offset boardLocal, PointerEvent event) {
    if (!_isSmudging) {
      return;
    }
    final Offset clamped = _clampToCanvas(boardLocal);
    final Offset nextEnginePoint = _backendToEngineSpace(clamped);
    final Offset? previous = _smudgeLastEnginePoint;
    _penCursorWorkspacePosition = event.localPosition;
    if (previous == null) {
      _smudgeLastEnginePoint = nextEnginePoint;
      return;
    }
    final Offset delta = nextEnginePoint - previous;
    final double distance = delta.distance;
    if (!distance.isFinite || distance <= 0.001) {
      return;
    }
    final double radius = _resolveSmudgeRadius();
    final double spacing = math.max(0.5, radius * 0.07);
    final double available = _smudgeResidual + distance;
    if (available < spacing) {
      _smudgeResidual = available;
      _smudgeLastEnginePoint = nextEnginePoint;
      return;
    }
    final int steps = math.max(1, (available / spacing).floor());
    final Offset unit = delta / distance;
    double cursorDistance = spacing - _smudgeResidual;
    Offset segmentStart = previous;
    for (int i = 0; i < steps && cursorDistance <= distance + 0.001; i++) {
      final Offset segmentEnd = previous + unit * cursorDistance;
      _drawSmudgeSegment(segmentStart, segmentEnd, event);
      segmentStart = segmentEnd;
      cursorDistance += spacing;
    }
    _smudgeResidual = (available - steps * spacing).clamp(0.0, spacing);
    _smudgeLastEnginePoint = nextEnginePoint;
    _markDirty();
  }

  void _drawSmudgeSegment(Offset from, Offset to, PointerEvent? event) {
    final double pressure = _resolveSprayPressure(event).clamp(0.0, 1.0);
    final double pressureScale = 0.25 + pressure * 0.75;
    final double strength = (_smudgeStrength * pressureScale).clamp(0.0, 1.0);
    if (strength <= 0.0001) {
      return;
    }
    if (_backend.drawSmudge(
      from: from,
      to: to,
      radius: _resolveSmudgeRadius(),
      strength: strength,
      softness: _smudgeSoftness,
    )) {
      _backendSmudgeHasDrawn = true;
      _markDirty();
    }
  }

  void _finishSmudgeStroke() {
    if (!_isSmudging) {
      return;
    }
    _backend.endSmudge();
    if (_backendSmudgeHasDrawn) {
      _recordBackendHistoryAction(layerId: _activeLayerId, deferPreview: true);
      if (mounted) {
        setState(() {});
      }
    } else {
      setState(() {});
    }
    _isSmudging = false;
    _backendSmudgeHasDrawn = false;
    _smudgeLastEnginePoint = null;
    _smudgeResidual = 0.0;
  }
}
