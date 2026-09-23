part of 'painting_board.dart';

extension _PaintingBoardInteractionBackendImpl
    on _PaintingBoardInteractionMixin {
  bool _isBackendDrawingPointer(PointerEvent event) {
    if (_isStylusEvent(event)) {
      return true;
    }
    if (event.kind == PointerDeviceKind.touch) {
      return _touchDrawingEnabled;
    }
    if (event.kind == PointerDeviceKind.mouse) {
      if (event.buttons == 0) {
        return event.down;
      }
      return (event.buttons & kPrimaryMouseButton) != 0;
    }
    if (event.kind == PointerDeviceKind.unknown) {
      if (event.buttons == 0) {
        return event.down;
      }
      return (event.buttons & kPrimaryMouseButton) != 0 ||
          (event.buttons & kPrimaryStylusButton) != 0;
    }
    return false;
  }

  bool _isActiveLayerLockedImpl() {
    final String? activeId = _controller.activeLayerId;
    if (activeId == null) {
      return false;
    }
    for (final CanvasLayerInfo layer in _controller.layers) {
      if (layer.id == activeId) {
        return layer.locked;
      }
    }
    return false;
  }

  bool _canStartBackendStroke() {
    if (!_backend.supportsStrokeStream) {
      return false;
    }
    if (_layerTransformModeActive ||
        _isLayerFreeTransformActive ||
        _controller.isActiveLayerTransforming) {
      return false;
    }
    if (_isActiveLayerLocked()) {
      return false;
    }
    return true;
  }

  Offset _backendToEngineSpaceImpl(Offset boardLocal) {
    final Size engineSize = _backendCanvasEngineSize ?? _canvasSize;
    if (engineSize == _canvasSize ||
        _canvasSize.width <= 0 ||
        _canvasSize.height <= 0) {
      return boardLocal;
    }
    final double sx = engineSize.width / _canvasSize.width;
    final double sy = engineSize.height / _canvasSize.height;
    return Offset(boardLocal.dx * sx, boardLocal.dy * sy);
  }

  Offset _sanitizeBackendStrokePosition(
    Offset boardLocal, {
    required bool isInitialSample,
  }) {
    final Offset sanitized = _sanitizeStrokePosition(
      boardLocal,
      isInitialSample: isInitialSample,
      anchor: _lastStrokeBoardPosition,
      clampToCanvas: false,
      applyStabilizer: false,
    );
    _lastStrokeBoardPosition = sanitized;
    return sanitized;
  }

  double? _normalizePointerPressure(PointerEvent event) {
    final double? pressure = _stylusPressureValue(event);
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

  double _resolveBackendPressure({
    required PointerEvent event,
    required Offset enginePos,
    required bool isInitialSample,
    double? stylusPressureOverride,
  }) {
    if (!_backendActiveStrokeUsesPressure) {
      return 1.0;
    }
    final bool isUpEvent =
        event is PointerUpEvent || event is PointerCancelEvent;
    double? stylusPressure = _backendUseStylusPressure
        ? (stylusPressureOverride ?? _normalizePointerPressure(event))
        : null;
    if (_backendUseStylusPressure) {
      if (!isUpEvent && stylusPressure != null) {
        _backendLastStylusPressure = stylusPressure;
      } else if (isUpEvent) {
        stylusPressure = _backendLastStylusPressure ?? stylusPressure;
      }
    }
    final bool shouldSimulate =
        _backendSimulatePressure || _autoSharpPeakEnabled;
    if (!shouldSimulate) {
      return stylusPressure ?? 1.0;
    }
    final double timestampMillis = event.timeStamp.inMicroseconds / 1000.0;
    if (isInitialSample) {
      _backendPressureSimulator.setProfile(_penPressureProfile);
      _backendPressureSimulator.setSharpTipsEnabled(_autoSharpPeakEnabled);
      final double stylusBlend =
          _backendUseStylusPressure && _backendSimulatePressure
          ? _kStylusSimulationBlend
          : 1.0;
      final double? initialPressure = _backendPressureSimulator.beginStroke(
        position: enginePos,
        timestampMillis: timestampMillis,
        simulatePressure: _backendSimulatePressure,
        useDevicePressure: _backendUseStylusPressure,
        stylusPressureBlend: stylusBlend,
        stylusPressure: stylusPressure,
      );
      return initialPressure ?? stylusPressure ?? 1.0;
    }
    final double? simulated = _backendPressureSimulator.samplePressure(
      position: enginePos,
      timestampMillis: timestampMillis,
      stylusPressure: stylusPressure,
    );
    return simulated ?? stylusPressure ?? 1.0;
  }

  void _appendBackendPoint({
    required Offset enginePos,
    required double pressure,
    required int timestampUs,
    required int flags,
    required int pointerId,
  }) {
    final Offset? previous = _backendLastEnginePoint;
    if (previous != null) {
      final Offset delta = enginePos - previous;
      final double distance = delta.distance;
      if (distance.isFinite && distance > 0.001) {
        _backendLastMovementUnit = delta / distance;
        _backendLastMovementDistance = distance;
      }
    }
    _backendLastResolvedPressure = pressure;
    _backendLastEnginePoint = enginePos;
    _backendPoints.add(
      x: enginePos.dx,
      y: enginePos.dy,
      pressure: pressure,
      timestampUs: timestampUs,
      flags: flags,
      pointerId: pointerId,
    );
  }

  double _backendRadiusFromPressure(double pressure, double baseRadius) {
    final double base = baseRadius.isFinite ? math.max(baseRadius, 0.0) : 0.0;
    if (base <= 0.0) {
      return 0.0;
    }
    final double clamped = pressure.isFinite ? pressure.clamp(0.0, 1.0) : 0.0;
    return base *
        (_kBackendPressureMinFactor +
            (1.0 - _kBackendPressureMinFactor) * clamped);
  }

  Offset? _computeBackendSharpTail({
    required Offset tip,
    required Offset? previousPoint,
    required double baseRadius,
  }) {
    Offset? unit;
    double length = 0.0;
    if (previousPoint != null) {
      final Offset direction = tip - previousPoint;
      length = direction.distance;
      if (length.isFinite && length > 0.001) {
        unit = direction / length;
      }
    }
    unit ??= _backendLastMovementUnit;
    if (unit == null) {
      return null;
    }
    final double base = math.max(baseRadius, 0.1);
    final double movement = length > 0.001
        ? length
        : _backendLastMovementDistance;
    final double taperMax = base * 6.5;
    final double taperDynamic = movement * 2.4 + 2.0;
    final double taperLength = math.min(taperMax, taperDynamic);
    return tip + unit * taperLength;
  }

  void _maybeEmitBackendSharpStart({
    required Offset currentPos,
    required double currentPressure,
    required int timestampUs,
    required int pointerId,
  }) {
    if (!_backendWaitingForFirstMove) {
      return;
    }
    _backendWaitingForFirstMove = false;
    if (!_autoSharpPeakEnabled ||
        !_backendPressureSimulator.isSimulatingStroke) {
      return;
    }
    final Offset? startPos = _backendStrokeStartPoint;
    if (startPos == null) {
      return;
    }
    final double baseWidth = _activeTool == CanvasTool.eraser
        ? _eraserStrokeWidth
        : _penStrokeWidth;
    final double baseRadius = (baseWidth / 2).clamp(0.0, 4096.0).toDouble();
    final Offset deltaToCurrent = currentPos - startPos;
    final double distToCurrent = deltaToCurrent.distance;
    if (!distToCurrent.isFinite || distToCurrent <= 0.001) {
      return;
    }
    final double startPressure = _backendStrokeStartPressure.clamp(0.0, 1.0);
    final double r0 = _backendRadiusFromPressure(startPressure, baseRadius);
    final double r1 = _backendRadiusFromPressure(
      currentPressure.clamp(0.0, 1.0),
      baseRadius,
    );
    if (distToCurrent + r0 >= r1) {
      return;
    }
    final Offset? headPoint = _computeBackendSharpTail(
      tip: startPos,
      previousPoint: currentPos,
      baseRadius: baseRadius,
    );
    if (headPoint == null ||
        _backendStrokeStartIndex >= _backendPoints.length) {
      return;
    }
    _backendPoints.updateAt(
      _backendStrokeStartIndex,
      x: headPoint.dx,
      y: headPoint.dy,
      pressure: 0.0,
    );
    _backendLastEnginePoint = headPoint;
    _backendLastResolvedPressure = 0.0;
    final Offset delta = startPos - headPoint;
    final double dist = delta.distance;
    if (dist.isFinite && dist > 0.5 && startPressure > 0.001) {
      final double spacing = math.max(baseRadius * 0.35, 0.75);
      final int segments = math
          .max(2, (dist / spacing).ceil())
          .clamp(2, 10)
          .toInt();
      for (int i = 1; i < segments; i++) {
        final double t = i / segments;
        final double eased = math.pow(t, 1.6).toDouble();
        final double midPressure = (startPressure * eased).clamp(0.0, 1.0);
        if (midPressure <= 0.001) {
          continue;
        }
        final Offset midPoint = headPoint + delta * t;
        _appendBackendPoint(
          enginePos: midPoint,
          pressure: midPressure,
          timestampUs: timestampUs,
          flags: _kBackendPointFlagMove,
          pointerId: pointerId,
        );
      }
    }
    _appendBackendPoint(
      enginePos: startPos,
      pressure: startPressure,
      timestampUs: timestampUs,
      flags: _kBackendPointFlagMove,
      pointerId: pointerId,
    );
  }

  void _enqueueBackendPoint(
    PointerEvent event,
    int flags, {
    bool isInitialSample = false,
  }) {
    final int? handle = _backendCanvasEngineHandle;
    if (!_backend.supportsInputQueue || handle == null) {
      return;
    }
    final Offset boardLocal = _toBoardLocal(event.localPosition);
    final Offset sanitized = _sanitizeBackendStrokePosition(
      boardLocal,
      isInitialSample: isInitialSample,
    );
    final Offset enginePos = _backendToEngineSpace(sanitized);
    final double pressure = _resolveBackendPressure(
      event: event,
      enginePos: enginePos,
      isInitialSample: isInitialSample,
    );
    final int timestampUs = event.timeStamp.inMicroseconds;
    if (flags == _kBackendPointFlagMove) {
      _maybeEmitBackendSharpStart(
        currentPos: enginePos,
        currentPressure: pressure,
        timestampUs: timestampUs,
        pointerId: event.pointer,
      );
    }
    if (flags == _kBackendPointFlagDown) {
      _backendStrokeStartPoint = enginePos;
      _backendStrokeStartPressure = pressure;
      _backendStrokeStartIndex = _backendPoints.length;
    }
    _appendBackendPoint(
      enginePos: enginePos,
      pressure: pressure,
      timestampUs: timestampUs,
      flags: flags,
      pointerId: event.pointer,
    );
    if (_kDebugBackendCanvasInput &&
        (flags == _kBackendPointFlagDown || flags == _kBackendPointFlagUp)) {
      final int queued = _backend.getInputQueueLen(handle: handle) ?? 0;
      debugPrint(
        '[backend_canvas] enqueue flags=$flags points=${_backendPoints.length} '
        'queued=$queued streamline=${_streamlineStrength.toStringAsFixed(3)}',
      );
    }
    _scheduleBackendFlush();
  }

  void _enqueueBackendPointFromStylusSample(
    PointerEvent anchorEvent,
    TabletStylusPoint sample,
    int flags, {
    bool isInitialSample = false,
  }) {
    final int? handle = _backendCanvasEngineHandle;
    if (!_backend.supportsInputQueue || handle == null) {
      return;
    }
    final Offset localPosition =
        anchorEvent.localPosition + (sample.position - anchorEvent.position);
    final Offset boardLocal = _toBoardLocal(localPosition);
    final Offset sanitized = _sanitizeBackendStrokePosition(
      boardLocal,
      isInitialSample: isInitialSample,
    );
    final Offset enginePos = _backendToEngineSpace(sanitized);
    final double pressure = _resolveBackendPressure(
      event: anchorEvent,
      enginePos: enginePos,
      isInitialSample: isInitialSample,
      stylusPressureOverride: sample.pressure,
    );
    final int timestampUs = anchorEvent.timeStamp.inMicroseconds;
    if (flags == _kBackendPointFlagMove) {
      _maybeEmitBackendSharpStart(
        currentPos: enginePos,
        currentPressure: pressure,
        timestampUs: timestampUs,
        pointerId: anchorEvent.pointer,
      );
    }
    if (flags == _kBackendPointFlagDown) {
      _backendStrokeStartPoint = enginePos;
      _backendStrokeStartPressure = pressure;
      _backendStrokeStartIndex = _backendPoints.length;
    }
    _appendBackendPoint(
      enginePos: enginePos,
      pressure: pressure,
      timestampUs: timestampUs,
      flags: flags,
      pointerId: anchorEvent.pointer,
    );
    _scheduleBackendFlush();
  }

  void _scheduleBackendFlush() {
    if (_backendWaitingForFirstMove && _backendPoints.length <= 1) {
      if (_kDebugBackendCanvasInput && _backendPoints.length == 1) {
        debugPrint(
          '[backend_canvas] flush skipped: waiting first move '
          'streamline=${_streamlineStrength.toStringAsFixed(3)}',
        );
      }
      return;
    }
    if (_backendFlushScheduled) {
      return;
    }
    _backendFlushScheduled = true;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      scheduleMicrotask(() {
        _backendFlushScheduled = false;
        if (!mounted) {
          _backendPoints.clear();
          return;
        }
        final int? handle = _backendCanvasEngineHandle;
        if (!_backend.supportsInputQueue || handle == null) {
          _backendPoints.clear();
          return;
        }
        _flushBackendPoints(handle);
      });
      return;
    }
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _backendFlushScheduled = false;
      if (!mounted) {
        _backendPoints.clear();
        return;
      }
      final int? handle = _backendCanvasEngineHandle;
      if (!_backend.supportsInputQueue || handle == null) {
        _backendPoints.clear();
        return;
      }
      _flushBackendPoints(handle);
    });
  }

  void _flushBackendPoints(int handle) {
    final int count = _backendPoints.length;
    if (count == 0) {
      return;
    }
    if (_kDebugBackendCanvasInput) {
      final int queued = _backend.getInputQueueLen(handle: handle) ?? 0;
      debugPrint(
        '[backend_canvas] flush points=$count queued_before=$queued '
        'streamline=${_streamlineStrength.toStringAsFixed(3)}',
      );
    }
    final bool pushed = _backend.pushPointsPacked(
      bytes: _backendPoints.bytes,
      pointCount: count,
    );
    _backendPoints.clear();
    if (_kDebugBackendCanvasInput) {
      final int queuedAfter = _backend.getInputQueueLen(handle: handle) ?? 0;
      debugPrint(
        '[backend_canvas] flush done pushed=$pushed queued_after=$queuedAfter '
        'streamline=${_streamlineStrength.toStringAsFixed(3)}',
      );
    }
  }

  void _clearBackendPredictedOverlay({bool scheduleRepaint = true}) {
    if (_backendPredictedPoints.isEmpty && _backendPredictedRadii.isEmpty) {
      return;
    }
    _backendPredictedPoints.clear();
    _backendPredictedRadii.clear();
    _backendPredictedOverlayRevision += 1;
    if (scheduleRepaint) {
      _scheduleBackendPredictedOverlayRepaint();
    }
  }

  void _updateBackendPredictedOverlay(
    PointerEvent sourceEvent,
    List<TabletStylusPoint> predictedEvents, {
    List<TabletStylusPoint>? coalescedEvents,
    bool requireBackendPointer = true,
    Offset? anchorOverride,
    double? pressureOverride,
  }) {
    final List<TabletStylusPoint> trailingEvents =
        coalescedEvents ?? const <TabletStylusPoint>[];
    if ((requireBackendPointer &&
            _backendActivePointer != sourceEvent.pointer) ||
        (predictedEvents.isEmpty && trailingEvents.isEmpty)) {
      _clearBackendPredictedOverlay();
      return;
    }

    final List<TabletStylusPoint> drawEvents = <TabletStylusPoint>[];
    if (trailingEvents.isNotEmpty) {
      final int start = trailingEvents.length > 10
          ? trailingEvents.length - 10
          : 0;
      drawEvents.addAll(trailingEvents.sublist(start));
    }
    drawEvents.addAll(predictedEvents);

    final double baseWidth = _activeTool == CanvasTool.eraser
        ? _eraserStrokeWidth
        : _penStrokeWidth;
    final double baseRadius = (baseWidth / 2).clamp(0.1, 4096.0).toDouble();
    final List<Offset> nextPoints = <Offset>[];
    final List<double> nextRadii = <double>[];
    final bool hasPredictedPressure = drawEvents.any(
      (TabletStylusPoint point) => point.pressure != null,
    );
    final bool usePressureForPreview =
        _backendActiveStrokeUsesPressure ||
        _backendUseStylusPressure ||
        pressureOverride != null ||
        hasPredictedPressure;

    Offset? anchor = anchorOverride ?? _lastStrokeBoardPosition;
    if (anchor != null) {
      final double anchorPressure =
          (pressureOverride ?? _backendLastResolvedPressure).isFinite
          ? (pressureOverride ?? _backendLastResolvedPressure).clamp(0.0, 1.0)
          : (_backendLastResolvedPressure.isFinite
                ? _backendLastResolvedPressure.clamp(0.0, 1.0)
                : 1.0);
      final double anchorRadius = usePressureForPreview
          ? _backendRadiusFromPressure(anchorPressure, baseRadius)
          : baseRadius;
      nextPoints.add(anchor);
      nextRadii.add(math.max(anchorRadius, 0.12));
    }

    for (int i = 0; i < drawEvents.length; i++) {
      final TabletStylusPoint sample = drawEvents[i];
      final Offset localPosition =
          sourceEvent.localPosition + (sample.position - sourceEvent.position);
      final Offset boardLocal = _toBoardLocal(localPosition);
      final Offset sanitized = _sanitizeStrokePosition(
        boardLocal,
        anchor: anchor,
        clampToCanvas: true,
        applyStabilizer: false,
      );
      if (anchor != null && (sanitized - anchor).distanceSquared <= 0.0025) {
        continue;
      }
      final double predictedPressure =
          sample.pressure ??
          pressureOverride ??
          _backendLastStylusPressure ??
          _backendLastResolvedPressure;
      final double resolvedPressure = predictedPressure.isFinite
          ? predictedPressure.clamp(0.0, 1.0)
          : 1.0;
      final double radius = usePressureForPreview
          ? _backendRadiusFromPressure(resolvedPressure, baseRadius)
          : baseRadius;
      nextPoints.add(sanitized);
      nextRadii.add(math.max(radius, 0.12));
      anchor = sanitized;
    }

    if (nextPoints.length < 2 || nextPoints.length != nextRadii.length) {
      _clearBackendPredictedOverlay();
      return;
    }

    _backendPredictedPoints
      ..clear()
      ..addAll(nextPoints);
    _backendPredictedRadii
      ..clear()
      ..addAll(nextRadii);
    _backendPredictedOverlayRevision += 1;
    _scheduleBackendPredictedOverlayRepaint();
  }

  void _recordBackendStrokeLatency() {
    StrokeLatencyMonitor.instance.recordStrokeStart();
    _backendLatencyPending = true;
    _scheduleBackendLatencyFrame();
  }

  void _scheduleBackendLatencyFrame() {
    if (!_backendLatencyPending || _backendLatencyFrameScheduled) {
      return;
    }
    _backendLatencyFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _backendLatencyFrameScheduled = false;
      if (!_backendLatencyPending) {
        return;
      }
      StrokeLatencyMonitor.instance.recordFramePresented();
      _backendLatencyPending = false;
    });
  }

  void _beginBackendStroke(PointerDownEvent event) {
    if (!_isBackendDrawingPointer(event)) {
      if (_kDebugPointerInput) {
        print(
          '[pointer] backend stroke blocked: id=${event.pointer} '
          'kind=${event.kind} down=${event.down} buttons=${event.buttons}',
        );
      }
      return;
    }
    _suppressRasterOutputForBackendStroke();
    if (_kDebugBackendCanvasInput) {
      debugPrint(
        '[backend_canvas] begin backend stroke '
        'id=${event.pointer} kind=${event.kind} down=${event.down} '
        'buttons=${event.buttons} pos=${event.localPosition} '
        'pressure=${event.pressure} handle=$_backendCanvasEngineHandle '
        'inputQueue=${_backend.supportsInputQueue}',
      );
    }
    _resetPerspectiveLock();
    _lastStrokeBoardPosition = null;
    _backendLastEnginePoint = null;
    _backendLastMovementUnit = null;
    _backendLastMovementDistance = 0.0;
    _backendLastStylusPressure = null;
    _backendLastResolvedPressure = 1.0;
    _backendWaitingForFirstMove = _autoSharpPeakEnabled;
    _backendStrokeStartPoint = null;
    _backendStrokeStartPressure = 1.0;
    _backendStrokeStartIndex = 0;
    _clearBackendPredictedOverlay(scheduleRepaint: false);
    final bool supportsPressure = _isStylusEvent(event);
    _backendPressureSimulator.resetTracking();
    _backendSimulatePressure = _simulatePenPressure;
    _backendUseStylusPressure = _stylusPressureEnabled && supportsPressure;
    _backendActiveStrokeUsesPressure =
        _backendUseStylusPressure ||
        _backendSimulatePressure ||
        _autoSharpPeakEnabled;
    _backendPressureSimulator.setSharpTipsEnabled(_autoSharpPeakEnabled);
    _backendActivePointer = event.pointer;
    _recordBackendStrokeLatency();
    _enqueueBackendPoint(event, _kBackendPointFlagDown, isInitialSample: true);
    _markDirty();
  }

  void _endBackendStroke(PointerEvent event) {
    if (_kDebugBackendCanvasInput) {
      debugPrint(
        '[backend_canvas] end backend stroke '
        'id=${event.pointer} kind=${event.kind} down=${event.down} '
        'buttons=${event.buttons} pos=${event.localPosition} '
        'pressure=${event.pressure} handle=$_backendCanvasEngineHandle',
      );
    }
    final bool hadActiveStroke = _backendActivePointer != null;
    final int? handle = _backendCanvasEngineHandle;
    final bool canRecordHistory =
        hadActiveStroke && _backend.supportsStrokeStream;
    if (_backend.supportsInputQueue && handle != null) {
      _backendWaitingForFirstMove = false;
      final Offset boardLocal = _toBoardLocal(event.localPosition);
      final Offset sanitized = _sanitizeBackendStrokePosition(
        boardLocal,
        isInitialSample: false,
      );
      _lastBrushLineAnchor = sanitized;
      final Offset enginePos = _backendToEngineSpace(sanitized);
      final double pressure = _resolveBackendPressure(
        event: event,
        enginePos: enginePos,
        isInitialSample: false,
      );
      final int timestampUs = event.timeStamp.inMicroseconds;
      final double startPressure = _backendLastResolvedPressure.isFinite
          ? _backendLastResolvedPressure
          : pressure;
      final bool wantsSharpTail =
          _autoSharpPeakEnabled && _backendPressureSimulator.isSimulatingStroke;
      if (wantsSharpTail) {
        final Offset? previousPoint = _backendLastEnginePoint;
        final double baseWidth = _activeTool == CanvasTool.eraser
            ? _eraserStrokeWidth
            : _penStrokeWidth;
        final double baseRadius = (baseWidth / 2).clamp(0.0, 4096.0).toDouble();
        Offset? tailPoint = _computeBackendSharpTail(
          tip: enginePos,
          previousPoint: previousPoint,
          baseRadius: baseRadius,
        );
        final double lastRadius = _backendRadiusFromPressure(
          startPressure,
          baseRadius,
        );
        final double endRadius = _backendRadiusFromPressure(0.0, baseRadius);
        if (tailPoint == null &&
            _backendLastMovementUnit != null &&
            lastRadius > endRadius) {
          final double targetDist = lastRadius - endRadius + 1.5;
          tailPoint = enginePos + _backendLastMovementUnit! * targetDist;
        } else if (tailPoint != null && lastRadius > endRadius) {
          final Offset delta = tailPoint - enginePos;
          final double dist = delta.distance;
          if (dist.isFinite && dist > 0.001 && dist + endRadius < lastRadius) {
            final double targetDist = lastRadius - endRadius + 1.5;
            tailPoint = enginePos + (delta / dist) * targetDist;
          }
        }
        if (tailPoint != null) {
          final double tailPressure = startPressure.clamp(0.0, 1.0);
          _appendBackendPoint(
            enginePos: enginePos,
            pressure: tailPressure,
            timestampUs: timestampUs,
            flags: _kBackendPointFlagMove,
            pointerId: event.pointer,
          );
          final Offset delta = tailPoint - enginePos;
          final double dist = delta.distance;
          if (dist.isFinite && dist > 0.5 && tailPressure > 0.001) {
            final double spacing = math.max(baseRadius * 0.35, 0.75);
            final int segments = math
                .max(2, (dist / spacing).ceil())
                .clamp(2, 10)
                .toInt();
            for (int i = 1; i < segments; i++) {
              final double t = i / segments;
              final double eased = math.pow(1.0 - t, 1.6).toDouble();
              final double midPressure = (tailPressure * eased).clamp(0.0, 1.0);
              if (midPressure <= 0.001) {
                continue;
              }
              final Offset midPoint = enginePos + delta * t;
              _appendBackendPoint(
                enginePos: midPoint,
                pressure: midPressure,
                timestampUs: timestampUs,
                flags: _kBackendPointFlagMove,
                pointerId: event.pointer,
              );
            }
          }
          _appendBackendPoint(
            enginePos: tailPoint,
            pressure: 0.0,
            timestampUs: timestampUs,
            flags: _kBackendPointFlagUp,
            pointerId: event.pointer,
          );
        } else {
          _appendBackendPoint(
            enginePos: enginePos,
            pressure: 0.0,
            timestampUs: timestampUs,
            flags: _kBackendPointFlagUp,
            pointerId: event.pointer,
          );
        }
      } else {
        _appendBackendPoint(
          enginePos: enginePos,
          pressure: pressure,
          timestampUs: timestampUs,
          flags: _kBackendPointFlagUp,
          pointerId: event.pointer,
        );
      }
      _scheduleBackendFlush();
      if (canRecordHistory) {
        _recordBackendHistoryAction(
          layerId: _activeLayerId,
          deferPreview: true,
        );
        if (mounted) {
          setState(() {});
        }
      }
    }
    _clearBackendPredictedOverlay();
    _backendActivePointer = null;
    _backendActiveStrokeUsesPressure = true;
    _backendSimulatePressure = false;
    _backendUseStylusPressure = false;
    _backendPressureSimulator.resetTracking();
    _backendLastEnginePoint = null;
    _backendLastMovementUnit = null;
    _backendLastMovementDistance = 0.0;
    _backendLastStylusPressure = null;
    _backendLastResolvedPressure = 1.0;
    _backendWaitingForFirstMove = false;
    _backendStrokeStartPoint = null;
    _backendStrokeStartPressure = 1.0;
    _backendStrokeStartIndex = 0;
    _lastStrokeBoardPosition = null;
    _strokeStabilizer.reset();
    _resetPerspectiveLock();
    _restoreRasterOutputAfterBackendStroke();
  }

  bool _drawBackendStraightLine({
    required Offset start,
    required Offset end,
    required PointerDownEvent event,
    bool? snapToPixelOverride,
  }) {
    final int? handle = _backendCanvasEngineHandle;
    if (!_backend.supportsInputQueue || handle == null) {
      return false;
    }
    final bool shouldOverrideSnap =
        snapToPixelOverride != null && snapToPixelOverride != _brushSnapToPixel;
    if (shouldOverrideSnap) {
      _applyBackendBrushOverride(
        handle,
        snapToPixelOverride: snapToPixelOverride,
      );
    }
    final Offset startClamped = _clampToCanvas(start);
    final Offset endClamped = _clampToCanvas(end);
    final Offset startEngine = _backendToEngineSpace(startClamped);
    final Offset endEngine = _backendToEngineSpace(endClamped);
    final int startTimestampUs = event.timeStamp.inMicroseconds;
    final int endTimestampUs = startTimestampUs + 1000;
    final double pressure = (_normalizePointerPressure(event) ?? 1.0).clamp(
      0.0,
      1.0,
    );

    _backendLastEnginePoint = null;
    _backendLastMovementUnit = null;
    _backendLastMovementDistance = 0.0;
    _backendLastStylusPressure = null;
    _backendLastResolvedPressure = 1.0;
    _backendWaitingForFirstMove = false;
    _backendStrokeStartPoint = null;
    _backendStrokeStartPressure = 1.0;
    _backendStrokeStartIndex = 0;

    try {
      _recordBackendStrokeLatency();
      _appendBackendPoint(
        enginePos: startEngine,
        pressure: pressure,
        timestampUs: startTimestampUs,
        flags: _kBackendPointFlagDown,
        pointerId: event.pointer,
      );
      _appendBackendPoint(
        enginePos: endEngine,
        pressure: pressure,
        timestampUs: endTimestampUs,
        flags: _kBackendPointFlagUp,
        pointerId: event.pointer,
      );
      _scheduleBackendFlush();
      _recordBackendHistoryAction(layerId: _activeLayerId, deferPreview: true);
      if (mounted) {
        setState(() {});
      }
      _markDirty();
      _resetPerspectiveLock();
      return true;
    } finally {
      if (shouldOverrideSnap) {
        _applyBackendBrushOverride(
          handle,
          snapToPixelOverride: _brushSnapToPixel,
        );
      }
    }
  }
}
