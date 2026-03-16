part of 'painting_board.dart';

final bool _kDebugPointerInput = bool.fromEnvironment(
  'MISA_RIN_DEBUG_POINTER_INPUT',
  defaultValue: false,
);

int _pointerLogLastEpochMs = 0;
int _pointerLogLastPointer = -1;
PointerDeviceKind? _pointerLogLastKind;

void _debugPointerInput(String message) {
  if (!_kDebugPointerInput) {
    return;
  }
  // Use print so logs still appear even when debugPrint is throttled/disabled.
  print('[pointer] $message');
}

void _debugPointerEvent(String phase, PointerEvent event) {
  if (!_kDebugPointerInput) {
    return;
  }
  final int now = DateTime.now().millisecondsSinceEpoch;
  if (phase == 'move') {
    final bool shouldLog =
        (now - _pointerLogLastEpochMs) > 200 ||
        _pointerLogLastPointer != event.pointer ||
        _pointerLogLastKind != event.kind;
    if (!shouldLog) {
      return;
    }
    _pointerLogLastEpochMs = now;
    _pointerLogLastPointer = event.pointer;
    _pointerLogLastKind = event.kind;
  }
  _debugPointerInput(
    '$phase id=${event.pointer} kind=${event.kind} '
    'down=${event.down} buttons=${event.buttons} '
    'pressure=${event.pressure} pos=${event.localPosition}',
  );
}

extension _PaintingBoardInteractionPointerImpl
    on _PaintingBoardInteractionMixin {
  void _clearPendingTouchStroke() {
    _pendingTouchStrokePointer = null;
    _pendingTouchStrokeStart = null;
    _pendingTouchStrokeTimestamp = null;
    _pendingTouchStrokeEvent = null;
  }

  bool _isTouchBrushTool(CanvasTool tool) {
    return tool == CanvasTool.pen || tool == CanvasTool.eraser;
  }

  bool _shouldDeferTouchBrushStroke(CanvasTool tool) {
    if (!_isTouchBrushTool(tool)) {
      return false;
    }
    if (_touchIgnoreUntilAllUp) {
      return false;
    }
    if (_activeTouchPointers.length != 1) {
      return false;
    }
    return true;
  }

  bool _maybeStartPendingTouchStroke(PointerMoveEvent event) {
    if (_pendingTouchStrokePointer == null ||
        _pendingTouchStrokePointer != event.pointer) {
      return false;
    }
    if (_touchIgnoreUntilAllUp || _activeTouchPointers.length != 1) {
      _clearPendingTouchStroke();
      return true;
    }
    final CanvasTool tool = _effectiveActiveTool;
    if (!_isTouchBrushTool(tool)) {
      _clearPendingTouchStroke();
      return true;
    }
    final PointerDownEvent? downEvent = _pendingTouchStrokeEvent;
    final Offset? start = _pendingTouchStrokeStart;
    final Duration? startTimestamp = _pendingTouchStrokeTimestamp;
    _clearPendingTouchStroke();
    if (downEvent == null || start == null || startTimestamp == null) {
      return true;
    }
    if (!isPointInsideSelection(start)) {
      return true;
    }
    final bool useBackendCanvas =
        _backend.isSupported && _brushShapeSupportsBackend;
    if (useBackendCanvas) {
      if (!_canStartBackendStroke()) {
        _showBackendCanvasMessage('画布后端尚未准备好。');
        return true;
      }
      _focusNode.requestFocus();
      _beginBackendStroke(downEvent);
      return false;
    }
    if (!_canStartBitmapStroke()) {
      return true;
    }
    _focusNode.requestFocus();
    _enqueueCpuStrokeEvent(
      type: _CpuStrokeEventType.down,
      boardLocal: start,
      timestamp: startTimestamp,
      event: downEvent,
    );
    _enqueueCpuStrokeEvent(
      type: _CpuStrokeEventType.move,
      boardLocal: _toBoardLocal(event.localPosition),
      timestamp: event.timeStamp,
      event: event,
    );
    return true;
  }

  Future<void> _handlePointerDownImpl(PointerDownEvent event) async {
    _debugPointerEvent('down', event);
    _trackStylusContact(event);
    final bool isStylus = _isStylusEvent(event);
    final bool isTouch = event.kind == PointerDeviceKind.touch && !isStylus;
    _debugPointerInput(
      'down flags stylus=$isStylus touch=$isTouch '
      'touchDrawing=$_touchDrawingEnabled',
    );
    if (isTouch) {
      _activeTouchPointers.add(event.pointer);
      _primaryTouchPointer ??= event.pointer;
      if (_activeTouchPointers.length > 1) {
        _touchIgnoreUntilAllUp = true;
        _primaryTouchPointer = null;
        _clearPendingTouchStroke();
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          _cancelActiveGestureDrawing(box, event.position);
        }
        _debugPointerInput('down ignored: multi-touch active');
        return;
      }
      if (_touchIgnoreUntilAllUp) {
        _debugPointerInput('down ignored: touch ignore until all up');
        return;
      }
    }
    final bool isPrimary = _isPrimaryPointer(event);
    _debugPointerInput('down primary=$isPrimary');
    if (isTouch &&
        _primaryTouchPointer != null &&
        event.pointer != _primaryTouchPointer) {
      _debugPointerInput('down ignored: non-primary touch pointer');
      return;
    }
    if (_isScalingGesture) {
      _debugPointerInput('down ignored: scaling gesture active');
      return;
    }
    if (_layerTransformApplying) {
      _debugPointerInput('down ignored: layer transform applying');
      return;
    }
    _recordWorkspacePointer(event.localPosition);
    _updateToolCursorOverlay(event.localPosition);
    final Offset pointer = event.localPosition;
    if (_isInsideToolArea(pointer) || _isInsideWorkspacePanelArea(pointer)) {
      _debugPointerInput('down ignored: inside tool/panel area');
      return;
    }
    final Offset boardLocal = _toBoardLocal(pointer);
    final double? perspectiveHitRadius =
        isTouch ? _perspectiveHandleHitRadius() : null;
    final double? perspectiveScreenRadius =
        isTouch ? _perspectiveHandleScreenRadius() : null;
    if (isTouch && !isPrimary) {
      if (_handlePerspectivePointerDown(
        boardLocal,
        hitRadius: perspectiveHitRadius,
        workspacePosition: pointer,
        screenRadius: perspectiveScreenRadius,
      )) {
        _debugPointerInput('down handled: perspective (touch secondary)');
        return;
      }
      _debugPointerInput('down ignored: touch secondary not primary');
      return;
    }
    if (!isPrimary) {
      _debugPointerInput('down ignored: not primary pointer');
      return;
    }
    final CanvasTool tool = _effectiveActiveTool;
    final Set<LogicalKeyboardKey> pressedKeys =
        HardwareKeyboard.instance.logicalKeysPressed;
    final bool shiftPressed =
        pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
        pressedKeys.contains(LogicalKeyboardKey.shiftRight) ||
        pressedKeys.contains(LogicalKeyboardKey.shift);
    final bool preferNearestPerspectiveHandle =
        _perspectiveVisible &&
        _perspectiveMode != PerspectiveGuideMode.off &&
        tool == CanvasTool.hand &&
        shiftPressed;
    if (_handlePerspectivePointerDown(
      boardLocal,
      allowNearest: preferNearestPerspectiveHandle,
      hitRadius: perspectiveHitRadius,
      workspacePosition: isTouch ? pointer : null,
      screenRadius: perspectiveScreenRadius,
    )) {
      _debugPointerInput('down handled: perspective');
      return;
    }
    final bool pointerInsideBoard = _isWithinCanvasBounds(boardLocal);
    if (_kDebugBackendCanvasInput &&
        (tool == CanvasTool.pen || tool == CanvasTool.eraser)) {
      debugPrint(
        '[backend_canvas] down id=${event.pointer} kind=${event.kind} '
        'down=${event.down} buttons=${event.buttons} '
        'pos=${event.localPosition} pressure=${event.pressure}',
      );
      debugPrint(
        '[backend_canvas] pen/eraser down tool=$tool '
        'pointerInsideBoard=$pointerInsideBoard '
        'backendSupported=${_backend.isSupported} '
        'backendReady=${_backend.isReady} '
        'handle=$_backendCanvasEngineHandle '
        'inputQueue=${_backend.supportsInputQueue} '
        'strokeStream=${_backend.supportsStrokeStream}',
      );
    }
    if (_layerTransformModeActive) {
      _handleLayerTransformPointerDown(boardLocal);
      _debugPointerInput('down handled: layer transform mode');
      return;
    }
    final bool toolCanStartOutsideCanvas =
        tool == CanvasTool.curvePen ||
        tool == CanvasTool.selection ||
        tool == CanvasTool.selectionPen ||
        tool == CanvasTool.spray ||
        tool == CanvasTool.pen ||
        tool == CanvasTool.eraser ||
        tool == CanvasTool.perspectivePen;
    if (!pointerInsideBoard && !toolCanStartOutsideCanvas) {
      _debugPointerInput(
        'down ignored: outside board tool=$tool inside=$pointerInsideBoard',
      );
      return;
    }
    if (_shouldBlockToolOnTextLayer(tool)) {
      _showTextToolConflictWarning();
      _debugPointerInput('down ignored: text tool conflict');
      return;
    }
    if (_isTextEditingActive) {
      _debugPointerInput('down ignored: text editing active');
      return;
    }
    if (isTouch && _shouldDeferTouchBrushStroke(tool)) {
      _pendingTouchStrokePointer = event.pointer;
      _pendingTouchStrokeStart = boardLocal;
      _pendingTouchStrokeTimestamp = event.timeStamp;
      _pendingTouchStrokeEvent = event;
      _debugPointerInput('down deferred: pending touch stroke');
      return;
    }
    switch (tool) {
      case CanvasTool.layerAdjust:
        await _beginLayerAdjustDrag(boardLocal);
        break;
      case CanvasTool.pen:
      case CanvasTool.eraser:
        _focusNode.requestFocus();
        final bool useBackendCanvas =
            _backend.isSupported && _brushShapeSupportsBackend;
        if (!useBackendCanvas) {
          if (!_canStartBitmapStroke()) {
            _debugPointerInput('down ignored: cannot start bitmap stroke');
            return;
          }
          if (!isPointInsideSelection(boardLocal)) {
            _debugPointerInput('down ignored: outside selection');
            return;
          }
          if (shiftPressed) {
            final Offset? anchor = _lastBrushLineAnchor;
            if (anchor != null) {
              final bool? snapToPixelOverride = _brushSnapToPixel
                  ? false
                  : null;
              if (_useCpuStrokeQueue) {
                _enqueueCpuStrokeEvent(
                  type: _CpuStrokeEventType.down,
                  boardLocal: anchor,
                  timestamp: event.timeStamp,
                  event: event,
                  snapToPixelOverride: snapToPixelOverride,
                );
                _enqueueCpuStrokeEvent(
                  type: _CpuStrokeEventType.move,
                  boardLocal: boardLocal,
                  timestamp: event.timeStamp,
                  event: event,
                );
                _enqueueCpuStrokeEvent(
                  type: _CpuStrokeEventType.up,
                  boardLocal: boardLocal,
                  timestamp: event.timeStamp,
                  event: event,
                );
                return;
              }
              await _startStroke(
                anchor,
                event.timeStamp,
                event,
                snapToPixelOverride: snapToPixelOverride,
              );
              _appendPoint(boardLocal, event.timeStamp, event);
              _finishStroke(event.timeStamp);
              return;
            }
          }
          if (_useCpuStrokeQueue) {
            _enqueueCpuStrokeEvent(
              type: _CpuStrokeEventType.down,
              boardLocal: boardLocal,
              timestamp: event.timeStamp,
              event: event,
            );
            _debugPointerInput('down queued: cpu stroke');
            return;
          }
          await _startStroke(boardLocal, event.timeStamp, event);
          _debugPointerInput('down handled: cpu stroke start');
          return;
        }
        if (!_canStartBackendStroke()) {
          _showBackendCanvasMessage('画布后端尚未准备好。');
          _debugPointerInput('down ignored: backend not ready');
          return;
        }
        if (!isPointInsideSelection(boardLocal)) {
          _debugPointerInput('down ignored: outside selection (backend)');
          return;
        }
        if (shiftPressed) {
          final Offset? anchor = _lastBrushLineAnchor;
          if (anchor != null &&
              _drawBackendStraightLine(
                start: anchor,
                end: boardLocal,
                event: event,
                snapToPixelOverride: _brushSnapToPixel ? false : null,
              )) {
            _lastBrushLineAnchor = _clampToCanvas(boardLocal);
            return;
          }
        }
        _beginBackendStroke(event);
        _debugPointerInput('down handled: backend stroke start');
        break;
      case CanvasTool.perspectivePen:
        _focusNode.requestFocus();
        if (_perspectiveMode == PerspectiveGuideMode.off ||
            !_perspectiveVisible) {
          AppNotifications.show(
            context,
            message: context.l10n.enablePerspectiveGuideFirst,
            severity: InfoBarSeverity.warning,
          );
          _clearPerspectivePenPreview();
          return;
        }
        if (!isPointInsideSelection(boardLocal)) {
          return;
        }
        if (_perspectivePenAnchor == null) {
          _setPerspectivePenAnchor(boardLocal);
          return;
        }
        _updatePerspectivePenPreview(boardLocal);
        if (!_perspectivePenPreviewValid) {
          AppNotifications.show(
            context,
            message: context.l10n.lineNotAlignedWithPerspective,
            severity: InfoBarSeverity.warning,
          );
          return;
        }
        await _commitPerspectivePenStroke(
          boardLocal,
          event.timeStamp,
          rawEvent: event,
        );
        break;
      case CanvasTool.curvePen:
        if (_isCurveCancelModifierPressed() &&
            (_curveAnchor != null || _isCurvePlacingSegment)) {
          _resetCurvePenState();
          return;
        }
        await _handleCurvePenPointerDown(boardLocal);
        break;
      case CanvasTool.shape:
        _focusNode.requestFocus();
        await _beginShapeDrawing(boardLocal);
        break;
      case CanvasTool.spray:
        _focusNode.requestFocus();
        if (!isPointInsideSelection(boardLocal)) {
          return;
        }
        await _startSprayStroke(boardLocal, event);
        break;
      case CanvasTool.bucket:
        _focusNode.requestFocus();
        final bool selectionOk = isPointInsideSelection(boardLocal);
        if (kDebugMode) {
          debugPrint(
            '[bucket] down kind=${event.kind} down=${event.down} '
            'buttons=${event.buttons} local=${event.localPosition} '
            'boardLocal=$boardLocal insideBoard=$pointerInsideBoard '
            'selectionOk=$selectionOk locked=${_isActiveLayerLocked()} '
            'backendReady=${_backend.isReady} backendSupported=${_backend.isSupported}',
          );
        }
        if (!selectionOk) {
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
      case CanvasTool.selectionPen:
        _focusNode.requestFocus();
        _handleSelectionPenPointerDown(boardLocal);
        break;
      case CanvasTool.text:
        _focusNode.requestFocus();
        if (!pointerInsideBoard) {
          return;
        }
        final CanvasLayerInfo? targetLayer = _hitTestTextLayer(boardLocal);
        if (targetLayer != null) {
          await _beginEditExistingTextLayer(targetLayer);
        } else {
          _beginNewTextSession(boardLocal);
        }
        break;
      case CanvasTool.hand:
        _beginDragBoard();
        break;
      case CanvasTool.rotate:
        _beginRotateBoard();
        break;
    }
  }

  void _handlePointerMoveImpl(PointerMoveEvent event) {
    _debugPointerEvent('move', event);
    _trackStylusContact(event);
    final bool isStylus = _isStylusEvent(event);
    if (event.kind == PointerDeviceKind.touch && !isStylus) {
      if (_touchIgnoreUntilAllUp) {
        return;
      }
      if (_primaryTouchPointer != null &&
          event.pointer != _primaryTouchPointer) {
        return;
      }
      if (_maybeStartPendingTouchStroke(event)) {
        return;
      }
    }
    if (_isScalingGesture) {
      return;
    }
    if (_layerTransformApplying) {
      return;
    }
    _recordWorkspacePointer(event.localPosition);
    _updateToolCursorOverlay(event.localPosition);
    if (_isDraggingPerspectiveHandle) {
      final Offset boardLocal = _toBoardLocal(event.localPosition);
      _handlePerspectivePointerMove(boardLocal);
      return;
    }
    final bool backendStrokeActive = _backendActivePointer == event.pointer;
    if (!_isPrimaryPointer(event) && !backendStrokeActive) {
      return;
    }
    if (_layerTransformModeActive) {
      final Offset boardLocal = _toBoardLocal(event.localPosition);
      _handleLayerTransformPointerMove(boardLocal);
      return;
    }
    switch (_effectiveActiveTool) {
      case CanvasTool.pen:
      case CanvasTool.eraser:
        final List<TabletStylusPoint> predictedEvents = TabletInputBridge
            .instance
            .predictedSamplesForEvent(event);
        if (backendStrokeActive) {
          final Offset? overlayAnchor = _lastStrokeBoardPosition;
          final double? overlayAnchorPressure = _backendLastStylusPressure;
          final dynamic dyn = event;
          final List<TabletStylusPoint> overlayCoalescedEvents =
              <TabletStylusPoint>[];
          bool enqueuedCoalesced = false;
          try {
            final List<dynamic>? coalesced =
                dyn.coalescedEvents as List<dynamic>?;
            if (coalesced != null && coalesced.isNotEmpty) {
              for (final dynamic e in coalesced) {
                if (e is PointerEvent) {
                  _enqueueBackendPoint(e, _kBackendPointFlagMove);
                  overlayCoalescedEvents.add(
                    TabletStylusPoint(
                      position: e.position,
                      pressure: _stylusPressureValue(e),
                    ),
                  );
                }
              }
              enqueuedCoalesced = true;
            }
          } catch (_) {}
          if (!enqueuedCoalesced) {
            if (_kEnableBridgeCoalescedForStroke) {
              final List<TabletStylusPoint> coalescedFromBridge =
                  TabletInputBridge.instance.coalescedSamplesForEvent(event);
              if (coalescedFromBridge.isNotEmpty) {
                for (final TabletStylusPoint sample in coalescedFromBridge) {
                  _enqueueBackendPointFromStylusSample(
                    event,
                    sample,
                    _kBackendPointFlagMove,
                  );
                  overlayCoalescedEvents.add(sample);
                }
              } else {
                _enqueueBackendPoint(event, _kBackendPointFlagMove);
                overlayCoalescedEvents.add(
                  TabletStylusPoint(
                    position: event.position,
                    pressure: _stylusPressureValue(event),
                  ),
                );
              }
            } else {
              _enqueueBackendPoint(event, _kBackendPointFlagMove);
              overlayCoalescedEvents.add(
                TabletStylusPoint(
                  position: event.position,
                  pressure: _stylusPressureValue(event),
                ),
              );
            }
          }
          if (predictedEvents.isNotEmpty || overlayCoalescedEvents.isNotEmpty) {
            _updateBackendPredictedOverlay(
              event,
              predictedEvents,
              coalescedEvents: overlayCoalescedEvents,
              anchorOverride: overlayAnchor,
              pressureOverride: overlayAnchorPressure,
            );
            _debugRecordPredictedOverlaySample(
              predictedPoints:
                  predictedEvents.length + overlayCoalescedEvents.length,
              backendStrokeActive: true,
            );
          } else {
            _clearBackendPredictedOverlay();
          }
          break;
        }
        if (_useCpuStrokeQueue) {
          final dynamic dyn = event;
          bool enqueuedCpuCoalesced = false;
          try {
            final List<dynamic>? coalesced =
                dyn.coalescedEvents as List<dynamic>?;
            if (coalesced != null && coalesced.isNotEmpty) {
              for (final dynamic e in coalesced) {
                if (e is PointerEvent) {
                  if (!e.down && !_isDrawing && _cpuStrokeQueue.isEmpty) {
                    continue;
                  }
                  final Offset boardLocal = _toBoardLocal(e.localPosition);
                  _enqueueCpuStrokeEvent(
                    type: _CpuStrokeEventType.move,
                    boardLocal: boardLocal,
                    timestamp: e.timeStamp,
                    event: e,
                  );
                }
              }
              enqueuedCpuCoalesced = true;
            }
          } catch (_) {}
          if (!enqueuedCpuCoalesced &&
              (event.down || _isDrawing || _cpuStrokeQueue.isNotEmpty)) {
            final Offset boardLocal = _toBoardLocal(event.localPosition);
            _enqueueCpuStrokeEvent(
              type: _CpuStrokeEventType.move,
              boardLocal: boardLocal,
              timestamp: event.timeStamp,
              event: event,
            );
          }
          if (predictedEvents.isNotEmpty &&
              (event.down || _isDrawing || _cpuStrokeQueue.isNotEmpty)) {
            _updateBackendPredictedOverlay(
              event,
              predictedEvents,
              requireBackendPointer: false,
              anchorOverride: _toBoardLocal(event.localPosition),
              pressureOverride: _stylusPressureValue(event),
            );
            _debugRecordPredictedOverlaySample(
              predictedPoints: predictedEvents.length,
              backendStrokeActive: false,
            );
          } else {
            _clearBackendPredictedOverlay();
          }
          break;
        }
        _clearBackendPredictedOverlay();
        if (_isDrawing) {
          final Offset boardLocal = _toBoardLocal(event.localPosition);
          _appendPoint(boardLocal, event.timeStamp, event);
        }
        break;
      case CanvasTool.perspectivePen:
        if (_perspectivePenAnchor != null) {
          final Offset boardLocal = _toBoardLocal(event.localPosition);
          _updatePerspectivePenPreview(boardLocal);
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
      case CanvasTool.selectionPen:
        final Offset boardLocal = _toBoardLocal(event.localPosition);
        _handleSelectionPenPointerMove(boardLocal);
        break;
      case CanvasTool.hand:
        if (_isDraggingBoard) {
          _updateDragBoard(event.delta);
        }
        break;
      case CanvasTool.rotate:
        if (_isRotatingBoard) {
          _updateRotateBoard(event.delta);
        }
        break;
      case CanvasTool.spray:
        if (_isSpraying) {
          final Offset boardLocal = _toBoardLocal(event.localPosition);
          _updateSprayStroke(boardLocal, event);
        }
        break;
      case CanvasTool.text:
        break;
    }
  }

  Future<void> _handlePointerUpImpl(PointerUpEvent event) async {
    _debugPointerEvent('up', event);
    _trackStylusContact(event);
    final bool wasIgnoring = _touchIgnoreUntilAllUp;
    final bool isStylus = _isStylusEvent(event);
    if (event.kind == PointerDeviceKind.touch && !isStylus) {
      _activeTouchPointers.remove(event.pointer);
      if (_activeTouchPointers.isEmpty) {
        _touchIgnoreUntilAllUp = false;
        _primaryTouchPointer = null;
      }
      if (wasIgnoring) {
        return;
      }
      if (_pendingTouchStrokePointer == event.pointer) {
        final PointerDownEvent? downEvent = _pendingTouchStrokeEvent;
        final Offset? start = _pendingTouchStrokeStart;
        final Duration? startTimestamp = _pendingTouchStrokeTimestamp;
        _clearPendingTouchStroke();
        if (downEvent == null || start == null || startTimestamp == null) {
          return;
        }
        final CanvasTool tool = _effectiveActiveTool;
        if (!_isTouchBrushTool(tool)) {
          return;
        }
        if (!isPointInsideSelection(start)) {
          return;
        }
        final bool useBackendCanvas =
            _backend.isSupported && _brushShapeSupportsBackend;
        _focusNode.requestFocus();
        if (useBackendCanvas) {
          if (!_canStartBackendStroke()) {
            _showBackendCanvasMessage('画布后端尚未准备好。');
            return;
          }
          _beginBackendStroke(downEvent);
          _endBackendStroke(event);
          return;
        }
        if (_useCpuStrokeQueue) {
          _enqueueCpuStrokeEvent(
            type: _CpuStrokeEventType.down,
            boardLocal: start,
            timestamp: startTimestamp,
            event: downEvent,
          );
          _enqueueCpuStrokeEvent(
            type: _CpuStrokeEventType.up,
            boardLocal: start,
            timestamp: event.timeStamp,
            event: event,
          );
          return;
        }
        await _startStroke(start, startTimestamp, downEvent);
        _finishStroke(event.timeStamp);
        return;
      }
    }
    if (_layerTransformModeActive) {
      _handleLayerTransformPointerUp();
      return;
    }
    if (_isDraggingPerspectiveHandle) {
      _handlePerspectivePointerUp();
      return;
    }
    switch (_effectiveActiveTool) {
      case CanvasTool.pen:
      case CanvasTool.eraser:
        if (_backendActivePointer != event.pointer) {
          _clearBackendPredictedOverlay();
        }
        if (_backendActivePointer == event.pointer) {
          _endBackendStroke(event);
          break;
        }
        if (_useCpuStrokeQueue) {
          final Offset boardLocal = _toBoardLocal(event.localPosition);
          _enqueueCpuStrokeEvent(
            type: _CpuStrokeEventType.up,
            boardLocal: boardLocal,
            timestamp: event.timeStamp,
            event: event,
          );
          break;
        }
        if (_isDrawing) {
          final Offset boardLocal = _toBoardLocal(event.localPosition);
          final double? releasePressure = _stylusPressureValue(event);
          if (_activeStrokeUsesStylus) {
            _appendStylusReleaseSample(
              boardLocal,
              event.timeStamp,
              releasePressure,
            );
          }
          if (_activeStrokeUsesStylus) {
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
        await _handleCurvePenPointerUp();
        break;
      case CanvasTool.shape:
        await _finishShapeDrawing();
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
      case CanvasTool.selectionPen:
        _handleSelectionPenPointerUp();
        break;
      case CanvasTool.hand:
        if (_isDraggingBoard) {
          _finishDragBoard();
        }
        break;
      case CanvasTool.rotate:
        if (_isRotatingBoard) {
          _finishRotateBoard();
        }
        break;
      case CanvasTool.spray:
        if (_isSpraying) {
          _finishSprayStroke();
        }
        break;
      case CanvasTool.text:
        break;
      case CanvasTool.perspectivePen:
        break;
    }
  }

  void _handlePointerCancelImpl(PointerCancelEvent event) {
    _debugPointerEvent('cancel', event);
    _trackStylusContact(event);
    final bool wasIgnoring = _touchIgnoreUntilAllUp;
    final bool isStylus = _isStylusEvent(event);
    if (event.kind == PointerDeviceKind.touch && !isStylus) {
      _activeTouchPointers.remove(event.pointer);
      if (_activeTouchPointers.isEmpty) {
        _touchIgnoreUntilAllUp = false;
        _primaryTouchPointer = null;
      }
      if (wasIgnoring) {
        return;
      }
      if (_pendingTouchStrokePointer == event.pointer) {
        _clearPendingTouchStroke();
        return;
      }
    }
    if (_layerTransformModeActive) {
      _handleLayerTransformPointerCancel();
      return;
    }
    if (_isDraggingPerspectiveHandle) {
      _handlePerspectivePointerUp();
      return;
    }
    switch (_effectiveActiveTool) {
      case CanvasTool.pen:
      case CanvasTool.eraser:
        if (_backendActivePointer != event.pointer) {
          _clearBackendPredictedOverlay();
        }
        if (_backendActivePointer == event.pointer) {
          _endBackendStroke(event);
          break;
        }
        if (_useCpuStrokeQueue) {
          final Offset boardLocal = _toBoardLocal(event.localPosition);
          _enqueueCpuStrokeEvent(
            type: _CpuStrokeEventType.cancel,
            boardLocal: boardLocal,
            timestamp: event.timeStamp,
            event: event,
          );
          break;
        }
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
      case CanvasTool.selectionPen:
        _handleSelectionPenPointerCancel();
        break;
      case CanvasTool.hand:
        if (_isDraggingBoard) {
          _finishDragBoard();
        }
        break;
      case CanvasTool.rotate:
        if (_isRotatingBoard) {
          _finishRotateBoard();
        }
        break;
      case CanvasTool.spray:
        if (_isSpraying) {
          _finishSprayStroke();
        }
        break;
      case CanvasTool.bucket:
      case CanvasTool.magicWand:
        break;
      case CanvasTool.text:
        break;
      case CanvasTool.perspectivePen:
        _clearPerspectivePenPreview();
        break;
    }
  }

  void _handlePointerHoverImpl(PointerHoverEvent event) {
    _recordWorkspacePointer(event.localPosition);
    _updateToolCursorOverlay(event.localPosition);
    final Offset boardLocal = _toBoardLocal(event.localPosition);
    _updatePerspectiveHover(boardLocal);
    if (_layerTransformModeActive) {
      _updateLayerTransformHover(boardLocal);
      return;
    }
    final CanvasTool tool = _effectiveActiveTool;
    if (tool == CanvasTool.perspectivePen) {
      if (_perspectivePenAnchor != null) {
        _updatePerspectivePenPreview(boardLocal);
      }
      _clearTextHoverHighlight();
      return;
    }
    if (tool == CanvasTool.selection) {
      _handleSelectionHover(boardLocal);
      return;
    }
    if (tool == CanvasTool.text) {
      if (_isTextEditingActive) {
        _clearTextHoverHighlight();
        return;
      }
      final Rect boardRect = _boardRect;
      if (!boardRect.contains(event.localPosition)) {
        _clearTextHoverHighlight();
        return;
      }
      final Offset boardLocal = _toBoardLocal(event.localPosition);
      _handleTextHover(boardLocal);
      return;
    }
    _clearTextHoverHighlight();
  }

  KeyEventResult _handleWorkspaceKeyEventImpl(FocusNode node, KeyEvent event) {
    if (_isTextEditingActive) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (_layerTransformModeActive) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (key == LogicalKeyboardKey.escape) {
          _cancelLayerFreeTransform();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) {
          unawaited(_confirmLayerFreeTransform());
          return KeyEventResult.handled;
        }
      }
    }
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
        _scheduleWorkspaceCardsOverlaySync();
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
        _scheduleWorkspaceCardsOverlaySync();
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
      _scheduleWorkspaceCardsOverlaySync();
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
      _scheduleWorkspaceCardsOverlaySync();
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
    _notifyViewInfoChanged();
  }

  void _handlePointerSignalImpl(PointerSignalEvent event) {
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

  void _handleScaleStartImpl(ScaleStartDetails details) {
    if (_isDraggingPerspectiveHandle) {
      _isScalingGesture = false;
      return;
    }
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
    if (details.pointerCount > 1) {
      _touchIgnoreUntilAllUp = true;
      _primaryTouchPointer = null;
      _clearPendingTouchStroke();
    }
    _cancelActiveGestureDrawing(box, details.focalPoint);
    _scaleGestureStartEpochMs = DateTime.now().millisecondsSinceEpoch;
    _scaleGestureMaxPointerCount = details.pointerCount;
    _scaleGestureAccumulatedFocalDistance = 0.0;
    _scaleGestureMaxScaleDelta = 0.0;
    _scaleGestureMaxRotationDelta = 0.0;
    _scaleGestureInitialScale = _viewport.scale;
    _scaleGestureInitialRotation = _viewport.rotation;
    final Offset focalPoint = box.globalToLocal(details.focalPoint);
    _scaleGestureAnchorBoardLocal = _toBoardLocal(focalPoint);
  }

  void _cancelActiveGestureDrawing(RenderBox box, Offset globalFocalPoint) {
    if (_backendActivePointer != null) {
      Offset local = box.globalToLocal(globalFocalPoint);
      final Offset? lastBoard = _lastStrokeBoardPosition;
      if (lastBoard != null) {
        final Rect boardRect = _boardRect;
        Offset relative = lastBoard * _viewport.scale;
        final double rotation = _viewport.rotation;
        if (rotation != 0) {
          final Offset center = boardRect.size.center(Offset.zero);
          final double dx = relative.dx - center.dx;
          final double dy = relative.dy - center.dy;
          final double cosA = math.cos(rotation);
          final double sinA = math.sin(rotation);
          relative = Offset(
            dx * cosA - dy * sinA + center.dx,
            dx * sinA + dy * cosA + center.dy,
          );
        }
        local = boardRect.topLeft + relative;
      }
      _endBackendStroke(
        PointerCancelEvent(
          pointer: _backendActivePointer!,
          position: local,
          kind: PointerDeviceKind.touch,
          timeStamp: Duration(
            milliseconds: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
    }
    if (_isDrawing) {
      _controller.cancelStroke();
      setState(() {
        _isDrawing = false;
        if (_brushRandomRotationEnabled) {
          _brushRandomRotationPreviewSeed = _brushRotationRandom.nextInt(1 << 31);
        }
      });
      _resetPerspectiveLock();
      _lastPenSampleTimestamp = null;
      _activeStrokeUsesStylus = false;
      _activeStylusPressureMin = null;
      _activeStylusPressureMax = null;
      _lastStylusPressureValue = null;
      _lastStrokeBoardPosition = null;
      _lastStylusDirection = null;
      _strokeStabilizer.reset();
    }
    if (_cpuStrokeQueue.isNotEmpty) {
      _cpuStrokeQueue.clear();
    }
    if (_isSpraying) {
      _finishSprayStroke();
    }
    _clearBackendPredictedOverlay();
  }

  void _handleScaleUpdateImpl(ScaleUpdateDetails details) {
    if (_isDraggingPerspectiveHandle) {
      return;
    }
    if (!_isScalingGesture) {
      return;
    }
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final Offset focalPoint = box.globalToLocal(details.focalPoint);
    final Offset? anchorBoardLocal = _scaleGestureAnchorBoardLocal;
    if (anchorBoardLocal == null) {
      return;
    }
    if (details.pointerCount > _scaleGestureMaxPointerCount) {
      _scaleGestureMaxPointerCount = details.pointerCount;
    }
    _scaleGestureAccumulatedFocalDistance += details.focalPointDelta.distance;
    _scaleGestureMaxScaleDelta = math.max(
      _scaleGestureMaxScaleDelta,
      (details.scale - 1.0).abs(),
    );
    _scaleGestureMaxRotationDelta = math.max(
      _scaleGestureMaxRotationDelta,
      details.rotation.abs(),
    );
    final double targetScale = _viewport.clampScale(
      _scaleGestureInitialScale * details.scale,
    );
    double targetRotation = _scaleGestureInitialRotation + details.rotation;
    if (targetRotation.isNaN || targetRotation.isInfinite) {
      targetRotation = _viewport.rotation;
    }

    final Offset base = _baseOffsetForScale(targetScale);
    final Offset scaledPoint = anchorBoardLocal * targetScale;
    final Offset center = Offset(
      _canvasSize.width * targetScale / 2,
      _canvasSize.height * targetScale / 2,
    );
    final double dx = scaledPoint.dx - center.dx;
    final double dy = scaledPoint.dy - center.dy;
    final double cosA = math.cos(targetRotation);
    final double sinA = math.sin(targetRotation);
    final Offset rotatedPoint = Offset(
      dx * cosA - dy * sinA + center.dx,
      dx * sinA + dy * cosA + center.dy,
    );
    final Offset targetTopLeft = focalPoint - rotatedPoint;
    final Offset targetOffset = targetTopLeft - base;

    setState(() {
      _viewport.setScale(targetScale);
      _viewport.setRotation(targetRotation);
      _viewport.setOffset(targetOffset);
    });
    _notifyViewInfoChanged();
  }

  void _handleScaleEndImpl(ScaleEndDetails details) {
    if (_isDraggingPerspectiveHandle) {
      _isScalingGesture = false;
      return;
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int elapsedMs = _scaleGestureStartEpochMs > 0
        ? (now - _scaleGestureStartEpochMs)
        : 0;
    final bool isTwoFingerGesture = _scaleGestureMaxPointerCount >= 2;

    final bool tapLikeTwoFinger =
        isTwoFingerGesture &&
        elapsedMs <= 320 &&
        _scaleGestureAccumulatedFocalDistance <= 26.0 &&
        _scaleGestureMaxScaleDelta <= 0.08 &&
        _scaleGestureMaxRotationDelta <= 0.20;

    final Offset v = details.velocity.pixelsPerSecond;
    final double velocity = v.distance;
    final bool quickTwoFingerSwipe =
        isTwoFingerGesture &&
        !tapLikeTwoFinger &&
        _scaleGestureAccumulatedFocalDistance >= 120.0 &&
        velocity >= 1800.0;

    if (tapLikeTwoFinger) {
      if (now - _twoFingerLastTapEpochMs <= 360) {
        _twoFingerLastTapEpochMs = 0;
        _handleUndo();
      } else {
        _twoFingerLastTapEpochMs = now;
      }
    }

    if (quickTwoFingerSwipe) {
      bool viewInfoNotified = false;
      setState(() {
        viewInfoNotified = _resetViewportToProjectDefault();
      });
      if (!viewInfoNotified) {
        _notifyViewInfoChanged();
      }
    }

    _isScalingGesture = false;
    _scaleGestureAnchorBoardLocal = null;
    _scaleGestureStartEpochMs = 0;
    _scaleGestureMaxPointerCount = 0;
    _scaleGestureAccumulatedFocalDistance = 0.0;
    _scaleGestureMaxScaleDelta = 0.0;
    _scaleGestureMaxRotationDelta = 0.0;
    if (_activeTouchPointers.isEmpty) {
      _touchIgnoreUntilAllUp = false;
      _primaryTouchPointer = null;
    }
  }

  void _handleUndoImpl() {
    if (_isTextEditingActive) {
      unawaited(_cancelTextEditingSession());
    }
    unawaited(_performUndo());
  }

  Future<void> _performUndo() async {
    if (!await undo()) {
      widget.onUndoFallback?.call();
    }
  }

  void _handleRedoImpl() {
    if (_isTextEditingActive) {
      unawaited(_cancelTextEditingSession());
    }
    unawaited(_performRedo());
  }

  Future<void> _performRedo() async {
    if (!await redo()) {
      widget.onRedoFallback?.call();
    }
  }

  void _refreshBackendLayerPreviewsAfterHistoryChange() {
    if (!_backend.isReady) {
      return;
    }
    for (final CanvasLayerInfo layer in _controller.layers) {
      if (_backend.supportsInputQueue) {
        _scheduleBackendLayerPreviewRefresh(layer.id);
      } else {
        _bumpBackendLayerPreviewRevision(layer.id);
      }
    }
  }

  Future<bool> undo() async {
    _refreshHistoryLimit();
    if (_useCombinedHistory) {
      final _HistoryActionKind? action = _peekHistoryUndoAction();
      if (action == _HistoryActionKind.backend) {
        if (!_backend.undo()) {
          return false;
        }
        _commitHistoryUndoAction();
        _refreshBackendLayerPreviewsAfterHistoryChange();
        _markDirty();
        setState(() {});
        return true;
      }
      if (action == _HistoryActionKind.dart) {
        if (_undoStack.isEmpty) {
          return false;
        }
        final _CanvasHistoryEntry previous = _undoStack.removeLast();
        _redoStack.add(
          await _createHistoryEntry(
            backendPixelsSynced: previous.backendPixelsSynced,
          ),
        );
        _commitHistoryUndoAction();
        _trimHistoryStacks();
        await _applyHistoryEntry(previous);
        return true;
      }
    }
    if (_undoStack.isEmpty) {
      return false;
    }
    final _CanvasHistoryEntry previous = _undoStack.removeLast();
    _redoStack.add(
      await _createHistoryEntry(
        backendPixelsSynced: previous.backendPixelsSynced,
      ),
    );
    _trimHistoryStacks();
    await _applyHistoryEntry(previous);
    return true;
  }

  Future<bool> redo() async {
    _refreshHistoryLimit();
    if (_useCombinedHistory) {
      final _HistoryActionKind? action = _peekHistoryRedoAction();
      if (action == _HistoryActionKind.backend) {
        if (!_backend.redo()) {
          return false;
        }
        _commitHistoryRedoAction();
        _refreshBackendLayerPreviewsAfterHistoryChange();
        _markDirty();
        setState(() {});
        return true;
      }
      if (action == _HistoryActionKind.dart) {
        if (_redoStack.isEmpty) {
          return false;
        }
        final _CanvasHistoryEntry next = _redoStack.removeLast();
        _undoStack.add(
          await _createHistoryEntry(
            backendPixelsSynced: next.backendPixelsSynced,
          ),
        );
        _commitHistoryRedoAction();
        _trimHistoryStacks();
        await _applyHistoryEntry(next);
        return true;
      }
    }
    if (_redoStack.isEmpty) {
      return false;
    }
    final _CanvasHistoryEntry next = _redoStack.removeLast();
    _undoStack.add(
      await _createHistoryEntry(backendPixelsSynced: next.backendPixelsSynced),
    );
    _trimHistoryStacks();
    await _applyHistoryEntry(next);
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
