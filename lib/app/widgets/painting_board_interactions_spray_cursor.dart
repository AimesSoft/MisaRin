part of 'painting_board.dart';

extension _PaintingBoardInteractionSprayCursorExtension on _PaintingBoardInteractionMixin {
  bool _isPrimaryPointer(PointerEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      if (kIsWeb) {
        if (event is PointerDownEvent || event is PointerMoveEvent) {
          if (event.down) {
            return true;
          }
        }
      }
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

  bool _isInsideToolArea(Offset workspacePosition) {
    if (_toolbarHitRegions.isNotEmpty) {
      for (final Rect region in _toolbarHitRegions) {
        if (region.contains(workspacePosition)) {
          return true;
        }
      }
      return false;
    }
    final Rect toolbarRect = Rect.fromLTWH(
      _toolButtonPadding,
      _toolButtonPadding,
      _toolbarLayout.width,
      _toolbarLayout.height,
    );
    final Rect toolSettingsRect = Rect.fromLTWH(
      _toolButtonPadding + _toolbarLayout.width + _toolSettingsSpacing,
      _toolButtonPadding,
      _toolSettingsCardSize.width,
      _toolSettingsCardSize.height,
    );
    final double indicatorTop =
        (_workspaceSize.height - _toolButtonPadding - _colorIndicatorSize)
            .clamp(0.0, double.infinity);
    final Rect colorIndicatorRect = Rect.fromLTWH(
      _toolButtonPadding,
      indicatorTop,
      _colorIndicatorSize,
      _colorIndicatorSize,
    );
    final double sidebarLeft =
        (_workspaceSize.width - _sidePanelWidth - _toolButtonPadding)
            .clamp(0.0, double.infinity)
            .toDouble();
    final Rect rightSidebarRect = Rect.fromLTWH(
      sidebarLeft,
      _toolButtonPadding,
      _sidePanelWidth,
      (_workspaceSize.height - 2 * _toolButtonPadding).clamp(
        0.0,
        double.infinity,
      ),
    );
    return toolbarRect.contains(workspacePosition) ||
        toolSettingsRect.contains(workspacePosition) ||
        rightSidebarRect.contains(workspacePosition) ||
        colorIndicatorRect.contains(workspacePosition);
  }

  bool _isWithinCanvas(Offset boardLocal) {
    return boardLocal.dx >= 0 &&
        boardLocal.dy >= 0 &&
        boardLocal.dx < _canvasSize.width &&
        boardLocal.dy < _canvasSize.height;
  }

  void _handleSprayTick(Duration elapsed) {
    if (!_isSpraying) {
      return;
    }
    if (_sprayMode == SprayMode.smudge) {
      return;
    }
    final Offset? position = _sprayBoardPosition;
    if (position == null) {
      return;
    }
    final Duration? previous = _sprayTickerTimestamp;
    _sprayTickerTimestamp = elapsed;
    if (previous == null) {
      return;
    }
    final Duration delta = elapsed - previous;
    if (delta <= Duration.zero) {
      return;
    }
    final double deltaSeconds = delta.inMicroseconds / 1000000.0;
    if (deltaSeconds <= 0.0) {
      return;
    }
    final double pressureScale = _sprayCurrentPressure.clamp(0.05, 1.0);
    final double emissionRate = _sprayEmissionRateForDiameter(
      _sprayStrokeWidth,
    );
    _sprayEmissionAccumulator += emissionRate * pressureScale * deltaSeconds;
    final int particleCount = _sprayEmissionAccumulator.floor();
    if (particleCount <= 0) {
      return;
    }
    _sprayEmissionAccumulator -= particleCount;
    _emitSprayParticles(position, particleCount);
  }

  double _sprayEmissionRateForDiameter(double diameter) {
    final double normalized = diameter.clamp(kSprayStrokeMin, kSprayStrokeMax);
    final double scaled = normalized * 0.25 + 40.0;
    return scaled.clamp(60.0, 600.0);
  }

  void _emitSprayParticles(Offset center, int count) {
    if (count <= 0) {
      return;
    }
    final KritaSprayEngine engine = _ensureKritaSprayEngine();
    final bool erase = _isBrushEraserEnabled;
    final Color color =
        _activeSprayColor ?? (erase ? const Color(0xFFFFFFFF) : _primaryColor);
    if (_rustSprayActive && _canUseRustCanvasEngine() && !engine.sampleInputColor) {
      final int? handle = _rustCanvasEngineHandle;
      if (handle == null) {
        return;
      }
      final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
      double sx = 1.0;
      double sy = 1.0;
      if (engineSize != _canvasSize &&
          _canvasSize.width > 0 &&
          _canvasSize.height > 0) {
        sx = engineSize.width / _canvasSize.width;
        sy = engineSize.height / _canvasSize.height;
      }
      final double scale = (sx.isFinite && sy.isFinite)
          ? ((sx + sy) / 2.0)
          : 1.0;
      final List<double> packed = <double>[];
      engine.forEachParticle(
        center: center,
        particleBudget: count,
        pressure: _sprayCurrentPressure,
        baseColor: color,
        onParticle: (position, particleRadius, opacityScale, baseColor) {
          if (opacityScale <= 0.0) {
            return;
          }
          final Offset enginePos = Offset(
            position.dx * sx,
            position.dy * sy,
          );
          packed.add(enginePos.dx);
          packed.add(enginePos.dy);
          packed.add(particleRadius * scale);
          packed.add(opacityScale);
        },
      );
      final int pointCount = packed.length ~/ 4;
      if (pointCount > 0) {
        CanvasEngineFfi.instance.drawSpray(
          handle: handle,
          points: Float32List.fromList(packed),
          pointCount: pointCount,
          colorArgb: color.value,
          brushShape: BrushShape.circle.index,
          erase: erase,
          antialiasLevel: _penAntialiasLevel,
          softness: 0.0,
          accumulate: true,
        );
        _rustSprayHasDrawn = true;
        _markDirty();
      }
      return;
    }
    engine.paintParticles(
      center: center,
      particleBudget: count,
      pressure: _sprayCurrentPressure,
      baseColor: color,
      erase: erase,
      antialiasLevel: _penAntialiasLevel,
    );
    _markDirty();
  }

  void _extendSoftSprayStroke(Offset boardLocal) {
    final double radius = _resolveSoftSprayRadius();
    final Offset? last = _softSprayLastPoint;
    final double spacing = _softSpraySpacingForRadius(radius);
    if (last == null) {
      _softSprayLastPoint = boardLocal;
      _stampSoftSprayBatch(
        <Offset>[boardLocal],
        radius,
        _sprayCurrentPressure,
      );
      _markDirty();
      return;
    }
    final Offset delta = boardLocal - last;
    final double distance = delta.distance;
    if (distance <= 1e-4) {
      _softSprayLastPoint = boardLocal;
      return;
    }
    final double totalDistance = _softSprayResidual + distance;
    if (totalDistance < spacing) {
      _softSprayResidual = totalDistance;
      _softSprayLastPoint = boardLocal;
      return;
    }
    final Offset direction = delta / distance;
    double cursor = spacing - _softSprayResidual;
    if (_softSprayResidual <= 1e-4) {
      cursor = spacing;
    }
    final List<Offset> stamps = <Offset>[];
    while (cursor <= distance) {
      final Offset sample = last + direction * cursor;
      stamps.add(sample);
      cursor += spacing;
    }
    _softSprayResidual = distance - (cursor - spacing);
    _softSprayLastPoint = boardLocal;
    stamps.add(boardLocal);
    _stampSoftSprayBatch(stamps, radius, _sprayCurrentPressure);
    _markDirty();
  }

  double _resolveSoftSprayRadius() {
    final double normalized = _sprayStrokeWidth.clamp(
      kSprayStrokeMin,
      kSprayStrokeMax,
    );
    return math.max(normalized * 0.5, 0.5);
  }

  void _stampSoftSprayBatch(
    List<Offset> positions,
    double radius,
    double pressure,
  ) {
    if (positions.isEmpty) {
      return;
    }
    final bool erase = _isBrushEraserEnabled;
    final Color baseColor =
        _activeSprayColor ?? (erase ? const Color(0xFFFFFFFF) : _primaryColor);
    final double opacityScale = (0.35 + pressure.clamp(0.0, 1.0) * 0.65).clamp(
      0.0,
      1.0,
    );
    if (opacityScale <= 0.0) {
      return;
    }
    if (_rustSprayActive && _canUseRustCanvasEngine()) {
      final int? handle = _rustCanvasEngineHandle;
      if (handle == null) {
        return;
      }
      final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
      double sx = 1.0;
      double sy = 1.0;
      if (engineSize != _canvasSize &&
          _canvasSize.width > 0 &&
          _canvasSize.height > 0) {
        sx = engineSize.width / _canvasSize.width;
        sy = engineSize.height / _canvasSize.height;
      }
      final double scale = (sx.isFinite && sy.isFinite)
          ? ((sx + sy) / 2.0)
          : 1.0;
      final int colorArgb = (0xFF000000 | (baseColor.value & 0x00FFFFFF));
      const int kMaxBatchPoints = 1024;
      int start = 0;
      while (start < positions.length) {
        final int end = math.min(start + kMaxBatchPoints, positions.length);
        final int batchCount = end - start;
        final Float32List packed = Float32List(batchCount * 4);
        int offset = 0;
        for (int i = start; i < end; i++) {
          final Offset position = positions[i];
          final Offset enginePos = Offset(position.dx * sx, position.dy * sy);
          packed[offset] = enginePos.dx;
          packed[offset + 1] = enginePos.dy;
          packed[offset + 2] = radius * scale;
          packed[offset + 3] = opacityScale;
          offset += 4;
        }
        CanvasEngineFfi.instance.drawSpray(
          handle: handle,
          points: packed,
          pointCount: batchCount,
          colorArgb: colorArgb,
          brushShape: BrushShape.circle.index,
          erase: erase,
          antialiasLevel: 3,
          softness: 1.0,
          accumulate: true,
        );
        _rustSprayHasDrawn = true;
        start = end;
      }
      return;
    }
    final Color color = baseColor.withOpacity(opacityScale);
    for (final Offset position in positions) {
      _controller.drawBrushStamp(
        center: position,
        radius: radius,
        color: color,
        brushShape: BrushShape.circle,
        antialiasLevel: 3,
        erase: erase,
        softness: 1.0,
      );
    }
  }

  double _softSpraySpacingForRadius(double radius) {
    final double scaled = radius * 0.28;
    return scaled.clamp(0.45, math.max(0.45, radius * 0.55));
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

    setState(() {
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
    });
  }

  Offset _sanitizeStrokePosition(
    Offset position, {
    bool isInitialSample = false,
    Offset? anchor,
    bool clampToCanvas = true,
  }) {
    final Offset clamped = clampToCanvas ? _clampToCanvas(position) : position;
    final bool supportsStrokeStabilizer =
        _effectiveActiveTool == CanvasTool.pen ||
        _effectiveActiveTool == CanvasTool.eraser ||
        _effectiveActiveTool == CanvasTool.perspectivePen;
    if (!supportsStrokeStabilizer) {
      if (isInitialSample) {
        _strokeStabilizer.reset();
      }
      return _maybeSnapToPerspective(clamped, anchor: anchor);
    }

    final bool enableStabilizer = _strokeStabilizerStrength > 0.0001;
    if (!enableStabilizer) {
      if (isInitialSample) {
        _strokeStabilizer.reset();
      }
      return _maybeSnapToPerspective(clamped, anchor: anchor);
    }

    if (isInitialSample) {
      _strokeStabilizer.reset();
      _strokeStabilizer.start(clamped);
      return _maybeSnapToPerspective(clamped, anchor: anchor);
    }
    final Offset filtered = _strokeStabilizer.filter(
      clamped,
      _strokeStabilizerStrength,
    );
    return _maybeSnapToPerspective(filtered, anchor: anchor);
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
    _notifyViewInfoChanged();
  }

  void _finishDragBoard() {
    if (!_isDraggingBoard) {
      return;
    }
    setState(() => _isDraggingBoard = false);
  }

  void _beginRotateBoard() {
    setState(() => _isRotatingBoard = true);
  }

  void _updateRotateBoard(Offset delta) {
    if (!_isRotatingBoard) {
      return;
    }
    _setViewportRotation(_viewport.rotation + delta.dx * 0.005);
  }

  void _finishRotateBoard() {
    if (!_isRotatingBoard) {
      return;
    }
    setState(() => _isRotatingBoard = false);
  }

  void _setViewportRotation(double value) {
    if (value.isNaN || value.isInfinite) {
      value = 0.0;
    } else {
      value %= math.pi * 2;
      if (value > math.pi) {
        value -= math.pi * 2;
      }
    }
    if ((_viewport.rotation - value).abs() < 0.0005) {
      return;
    }
    setState(() {
      _viewport.setRotation(value);
    });
    _notifyViewInfoChanged();
  }

  void _resetViewportRotation() {
    _setViewportRotation(0.0);
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
    if (color.alpha == 0) {
      _updateBrushToolsEraserMode(true);
      return;
    }
    if (_brushToolsEraserMode) {
      _updateBrushToolsEraserMode(false);
    }
    _setPrimaryColor(color.withAlpha(0xFF), remember: remember);
  }

  void _updateToolCursorOverlay(Offset workspacePosition) {
    final CanvasTool tool = _effectiveActiveTool;
    final bool overlayTool = ToolCursorStyles.hasOverlay(tool);
    final bool isPenLike =
        tool == CanvasTool.pen ||
        tool == CanvasTool.curvePen ||
        tool == CanvasTool.shape ||
        tool == CanvasTool.eraser ||
        tool == CanvasTool.spray;
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
    final Offset? previous = _lastWorkspacePointer;
    if (_isInsideToolArea(workspacePosition)) {
      _lastWorkspacePointer = null;
    } else {
      _lastWorkspacePointer = workspacePosition;
    }
    if (_lastWorkspacePointer != previous) {
      _notifyViewInfoChanged();
    }
  }
}
