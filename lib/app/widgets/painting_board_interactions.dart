part of 'painting_board.dart';

const double _kStylusSimulationBlend = 0.68;
const int _kRustPointStrideBytes = 32;
const int _kRustPointFlagDown = 1;
const int _kRustPointFlagMove = 2;
const int _kRustPointFlagUp = 4;
const int _kWebPointerLogLimit = 120;
const int _kUint32Mod = 0x100000000;
const double _kRustPressureMinFactor = 0.09;
const double _kRustPressureMaxFactor = 1.0;
const bool _kDebugRustCanvasInput = bool.fromEnvironment(
  'MISA_RIN_DEBUG_RUST_CANVAS_INPUT',
  defaultValue: false,
);

int _webPointerLogCount = 0;
bool _webLoggedRustMove = false;
int _webEnqueueLogCount = 0;

void _webPointerLog(String message) {
  if (!kIsWeb || _webPointerLogCount >= _kWebPointerLogLimit) {
    return;
  }
  _webPointerLogCount += 1;
  reportWebLog('[pointer] $message');
}

void _webEnqueueLog(String message) {
  if (!kIsWeb || _webEnqueueLogCount >= 10) {
    return;
  }
  _webEnqueueLogCount += 1;
  reportWebLog('[enqueue] $message');
}

void _writeUint64LE(ByteData data, int offset, int value) {
  if (value < 0) {
    value = 0;
  }
  final int hi = value ~/ _kUint32Mod;
  final int lo = value - hi * _kUint32Mod;
  data.setUint32(offset, lo, Endian.little);
  data.setUint32(offset + 4, hi, Endian.little);
}

final class _RustPointBuffer {
  _RustPointBuffer({int initialCapacityPoints = 256})
    : _bytes = Uint8List(initialCapacityPoints * _kRustPointStrideBytes) {
    _data = ByteData.view(_bytes.buffer);
  }

  Uint8List _bytes;
  late ByteData _data;
  int _len = 0;

  int get length => _len;

  Uint8List get bytes => _bytes;

  void clear() => _len = 0;

  void add({
    required double x,
    required double y,
    required double pressure,
    required int timestampUs,
    required int flags,
    required int pointerId,
  }) {
    _ensureCapacity(_len + 1);
    final int base = _len * _kRustPointStrideBytes;
    _data.setFloat32(base + 0, x, Endian.little);
    _data.setFloat32(base + 4, y, Endian.little);
    _data.setFloat32(base + 8, pressure, Endian.little);
    _data.setFloat32(base + 12, 0.0, Endian.little);
    _writeUint64LE(_data, base + 16, timestampUs);
    _data.setUint32(base + 24, flags, Endian.little);
    _data.setUint32(base + 28, pointerId, Endian.little);
    _len++;
  }

  void updateAt(
    int index, {
    double? x,
    double? y,
    double? pressure,
  }) {
    if (index < 0 || index >= _len) {
      return;
    }
    final int base = index * _kRustPointStrideBytes;
    if (x != null) {
      _data.setFloat32(base + 0, x, Endian.little);
    }
    if (y != null) {
      _data.setFloat32(base + 4, y, Endian.little);
    }
    if (pressure != null) {
      _data.setFloat32(base + 8, pressure, Endian.little);
    }
  }

  void _ensureCapacity(int neededPoints) {
    final int neededBytes = neededPoints * _kRustPointStrideBytes;
    if (_bytes.lengthInBytes >= neededBytes) {
      return;
    }
    int nextBytes = _bytes.lengthInBytes;
    while (nextBytes < neededBytes) {
      nextBytes = nextBytes * 2;
    }
    final Uint8List next = Uint8List(nextBytes);
    next.setRange(0, _len * _kRustPointStrideBytes, _bytes, 0);
    _bytes = next;
    _data = ByteData.view(_bytes.buffer);
  }
}

final class _RustPressureSimulator {
  _RustPressureSimulator()
    : _strokeDynamics = StrokeDynamics(
        profile: StrokePressureProfile.auto,
        minRadiusFactor: _kRustPressureMinFactor,
        maxRadiusFactor: _kRustPressureMaxFactor,
      );

  final StrokeDynamics _strokeDynamics;
  final StrokeSampleSeries _strokeSamples = StrokeSampleSeries();
  final VelocitySmoother _velocitySmoother = VelocitySmoother();

  StrokePressureProfile _profile = StrokePressureProfile.auto;
  bool _simulatingStroke = false;
  bool _dynamicsEnabled = false;
  bool _usesDevicePressure = false;
  bool _sharpTipsEnabled = true;
  double _stylusPressureBlend = 1.0;

  bool get isSimulatingStroke => _simulatingStroke;

  void setSharpTipsEnabled(bool enabled) {
    _sharpTipsEnabled = enabled;
  }

  void resetTracking() {
    _strokeSamples.clear();
    _velocitySmoother.reset();
    _simulatingStroke = false;
    _dynamicsEnabled = false;
    _usesDevicePressure = false;
    _stylusPressureBlend = 1.0;
  }

  void setProfile(StrokePressureProfile profile) {
    if (_profile == profile) {
      return;
    }
    _profile = profile;
    _strokeDynamics.configure(profile: profile);
  }

  double? beginStroke({
    required Offset position,
    required double timestampMillis,
    required bool simulatePressure,
    required bool useDevicePressure,
    required double stylusPressureBlend,
    double? stylusPressure,
  }) {
    _strokeSamples.clear();
    _velocitySmoother.reset();
    _strokeSamples.add(position, timestampMillis);
    _velocitySmoother.addSample(position, timestampMillis);

    _dynamicsEnabled = simulatePressure;
    _usesDevicePressure = useDevicePressure;
    _stylusPressureBlend = stylusPressureBlend.clamp(0.0, 1.0);
    _simulatingStroke = _dynamicsEnabled || _sharpTipsEnabled;

    if (!_simulatingStroke) {
      return null;
    }

    _strokeDynamics.start(1.0, profile: _profile);

    if (!_dynamicsEnabled) {
      final double base = _normalizePressure(stylusPressure) ?? 1.0;
      final double initialPressure = _sharpTipsEnabled ? 0.0 : base;
      return initialPressure;
    }

    double initialPressure = _radiusToPressure(_strokeDynamics.initialRadius());
    if (_usesDevicePressure && stylusPressure != null) {
      final double? seeded = _seedPressureSample(stylusPressure);
      if (seeded != null) {
        initialPressure = seeded;
      }
    }
    return initialPressure;
  }

  double? samplePressure({
    required Offset position,
    required double timestampMillis,
    double? stylusPressure,
  }) {
    if (!_simulatingStroke) {
      return null;
    }
    final StrokeSample sample = _strokeSamples.add(position, timestampMillis);
    final double normalizedSpeed =
        _velocitySmoother.addSample(position, timestampMillis);

    if (!_dynamicsEnabled) {
      final double base = _normalizePressure(stylusPressure) ?? 1.0;
      double pressure = base;
      if (_sharpTipsEnabled) {
        const int rampSamples = 5;
        final int index = _strokeSamples.length - 1;
        if (index < rampSamples) {
          final double t = index / rampSamples;
          pressure = base * t;
        }
      }
      return pressure.clamp(0.0, 1.0);
    }

    final StrokeSampleMetrics? metrics =
        _profile == StrokePressureProfile.auto
            ? StrokeSampleMetrics(
                sampleIndex: _strokeSamples.length - 1,
                normalizedSpeed: normalizedSpeed,
                stationaryDuration: sample.stationaryDuration,
                totalDistance: _strokeSamples.totalDistance,
                totalTime: _strokeSamples.totalTime,
              )
            : null;
    final double? intensityOverride =
        _usesDevicePressure ? _stylusPressureToIntensity(stylusPressure) : null;
    final double effectiveBlend =
        intensityOverride != null ? _stylusPressureBlend : 0.0;
    final double radius = _strokeDynamics.sample(
      distance: sample.distance,
      deltaTimeMillis: sample.deltaTime,
      metrics: metrics,
      intensityOverride: intensityOverride,
      speedSignal: normalizedSpeed,
      intensityBlend: effectiveBlend,
    );
    return _radiusToPressure(radius);
  }

  double _radiusToPressure(double radius) {
    final double minRadius = _strokeDynamics.minRadius;
    final double maxRadius = _strokeDynamics.maxRadius;
    final double span = maxRadius - minRadius;
    if (span <= 0.0001) {
      return 1.0;
    }
    return ((radius - minRadius) / span).clamp(0.0, 1.0);
  }

  double? _seedPressureSample(double pressure) {
    final double? intensity = _stylusPressureToIntensity(pressure);
    if (intensity == null) {
      return null;
    }
    final double radius = _strokeDynamics.sample(
      distance: 0.0,
      intensityOverride: intensity,
      speedSignal: 0.0,
      intensityBlend: _stylusPressureBlend,
    );
    return _radiusToPressure(radius);
  }

  double? _stylusPressureToIntensity(double? pressure) {
    if (pressure == null || !pressure.isFinite) {
      return null;
    }
    return (1.0 - pressure.clamp(0.0, 1.0)).clamp(0.0, 1.0);
  }

  double? _normalizePressure(double? pressure) {
    if (pressure == null || !pressure.isFinite) {
      return null;
    }
    return pressure.clamp(0.0, 1.0);
  }
}

mixin _PaintingBoardInteractionMixin
    on
        _PaintingBoardBase,
        _PaintingBoardLayerTransformMixin,
        _PaintingBoardShapeMixin,
        _PaintingBoardReferenceMixin,
        _PaintingBoardPerspectiveMixin,
        _PaintingBoardTextMixin,
        TickerProvider {
  final _RustPointBuffer _rustPoints = _RustPointBuffer();
  final _RustPressureSimulator _rustPressureSimulator =
      _RustPressureSimulator();
  bool _rustFlushScheduled = false;
  int? _rustActivePointer;
  bool _rustActiveStrokeUsesPressure = true;
  bool _rustSimulatePressure = false;
  bool _rustUseStylusPressure = false;
  Offset? _rustLastEnginePoint;
  Offset? _rustLastMovementUnit;
  double _rustLastMovementDistance = 0.0;
  double? _rustLastStylusPressure;
  double _rustLastResolvedPressure = 1.0;
  bool _rustWaitingForFirstMove = false;
  Offset? _rustStrokeStartPoint;
  double _rustStrokeStartPressure = 1.0;
  int _rustStrokeStartIndex = 0;

  void clear() async {
    if (_isTextEditingActive) {
      await _cancelTextEditingSession();
    }
    await _pushUndoSnapshot();
    _controller.clear();
    _emitClean();
    setState(() {
      // No-op placeholder for repaint
    });
  }

  void _setActiveTool(CanvasTool tool) {
    final bool shouldCommitText =
        tool != CanvasTool.text && _isTextEditingActive;
    if (_guardTransformInProgress(message: context.l10n.completeTransformFirst)) {
      return;
    }
    if (shouldCommitText) {
      unawaited(_commitTextEditingSession());
    }
    if (_activeTool == tool) {
      return;
    }
    if (_activeTool == CanvasTool.spray && _isSpraying) {
      _finishSprayStroke();
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
    if (_activeTool == CanvasTool.selectionPen) {
      _handleSelectionPenPointerCancel();
    }
    if (tool != CanvasTool.text) {
      _clearTextHoverHighlight();
    }
    if (tool != CanvasTool.perspectivePen) {
      _clearPerspectivePenPreview();
    }
    setState(() {
      if (_activeTool == CanvasTool.magicWand) {
        _convertMagicWandPreviewToSelection();
      } else if (tool != CanvasTool.magicWand) {
        _clearMagicWandPreview();
      }
      if (tool == CanvasTool.magicWand) {
        _convertSelectionToMagicWandPreview();
      }
      final bool nextIsSelectionTool =
          tool == CanvasTool.selection || tool == CanvasTool.selectionPen;
      final bool currentIsSelectionTool =
          _activeTool == CanvasTool.selection ||
          _activeTool == CanvasTool.selectionPen;
      if (!nextIsSelectionTool || currentIsSelectionTool) {
        _resetSelectionPreview();
        _resetPolygonState();
      }
      if (tool != CanvasTool.curvePen) {
        _curvePreviewPath = null;
      }
      if (tool != CanvasTool.shape) {
        _disposeShapeRasterPreview(restoreLayer: true);
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
    _scheduleWorkspaceCardsOverlaySync();
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

  void _updateSprayStrokeWidth(double value) {
    final double clamped = value.clamp(kSprayStrokeMin, kSprayStrokeMax);
    if ((_sprayStrokeWidth - clamped).abs() < 0.0005) {
      return;
    }
    setState(() => _sprayStrokeWidth = clamped);
    if (_sprayMode == SprayMode.splatter) {
      _kritaSprayEngine?.updateSettings(_buildKritaSpraySettings());
    }
    final AppPreferences prefs = AppPreferences.instance;
    prefs.sprayStrokeWidth = clamped;
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
    final int clamped = value.clamp(0, 9);
    if (_penAntialiasLevel == clamped) {
      return;
    }
    setState(() => _penAntialiasLevel = clamped);
    if (_sprayMode == SprayMode.splatter) {
      _kritaSprayEngine?.updateSettings(_buildKritaSpraySettings());
    }
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
    _rustPressureSimulator.setSharpTipsEnabled(value);
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



  @override
  void _handleWorkspacePointerExit() {
    if (_effectiveActiveTool == CanvasTool.selection) {
      _clearSelectionHover();
    }
    _clearTextHoverHighlight();
    if (_effectiveActiveTool != CanvasTool.perspectivePen) {
      _clearPerspectivePenPreview();
    }
    _clearToolCursorOverlay();
    _clearLayerTransformCursorIndicator();
    _clearPerspectiveHover();
    if (_lastWorkspacePointer != null) {
      _lastWorkspacePointer = null;
      _notifyViewInfoChanged();
    }
  }

  bool _isRustDrawingPointer(PointerEvent event) {
    if (_isStylusEvent(event)) {
      return true;
    }
    if (event.kind == PointerDeviceKind.mouse) {
      if (kIsWeb) {
        if (event is PointerDownEvent || event is PointerMoveEvent) {
          if (event.down) {
            return true;
          }
        }
      }
      return (event.buttons & kPrimaryMouseButton) != 0;
    }
    return false;
  }

  bool _isActiveLayerLocked() {
    final String? activeId = _controller.activeLayerId;
    if (activeId == null) {
      return false;
    }
    for (final BitmapLayerState layer in _controller.layers) {
      if (layer.id == activeId) {
        return layer.locked;
      }
    }
    return false;
  }

  bool _canStartRustStroke({required bool pointerInsideBoard}) {
    if (!pointerInsideBoard) {
      _webPointerLog('rust stroke blocked: outside board');
      return false;
    }
    if (!_canUseRustCanvasEngine()) {
      _webPointerLog(
        'rust stroke blocked: engine not ready handle=$_rustCanvasEngineHandle '
        'supported=${CanvasEngineFfi.instance.isSupported}',
      );
      return false;
    }
    if (_layerTransformModeActive ||
        _isLayerFreeTransformActive ||
        _controller.isActiveLayerTransforming) {
      _webPointerLog('rust stroke blocked: layer transform active');
      return false;
    }
    if (_isActiveLayerLocked()) {
      _webPointerLog('rust stroke blocked: active layer locked');
      return false;
    }
    return true;
  }

  Offset _rustToEngineSpace(Offset boardLocal) {
    final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
    if (engineSize == _canvasSize ||
        _canvasSize.width <= 0 ||
        _canvasSize.height <= 0) {
      return boardLocal;
    }
    final double sx = engineSize.width / _canvasSize.width;
    final double sy = engineSize.height / _canvasSize.height;
    return Offset(boardLocal.dx * sx, boardLocal.dy * sy);
  }

  Offset _sanitizeRustStrokePosition(
    Offset boardLocal, {
    required bool isInitialSample,
  }) {
    final Offset sanitized = _sanitizeStrokePosition(
      boardLocal,
      isInitialSample: isInitialSample,
      anchor: _lastStrokeBoardPosition,
      clampToCanvas: false,
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
    final double curved =
        math.pow(normalized.clamp(0.0, 1.0), curve).toDouble();
    return curved.clamp(0.0, 1.0);
  }

  double _resolveRustPressure({
    required PointerEvent event,
    required Offset enginePos,
    required bool isInitialSample,
  }) {
    if (!_rustActiveStrokeUsesPressure) {
      return 1.0;
    }
    final bool isUpEvent = event is PointerUpEvent || event is PointerCancelEvent;
    double? stylusPressure =
        _rustUseStylusPressure ? _normalizePointerPressure(event) : null;
    if (_rustUseStylusPressure) {
      if (!isUpEvent && stylusPressure != null) {
        _rustLastStylusPressure = stylusPressure;
      } else if (isUpEvent) {
        stylusPressure = _rustLastStylusPressure ?? stylusPressure;
      }
    }
    final bool shouldSimulate = _rustSimulatePressure || _autoSharpPeakEnabled;
    if (!shouldSimulate) {
      return stylusPressure ?? 1.0;
    }
    final double timestampMillis = event.timeStamp.inMicroseconds / 1000.0;
    if (isInitialSample) {
      _rustPressureSimulator.setProfile(_penPressureProfile);
      _rustPressureSimulator.setSharpTipsEnabled(_autoSharpPeakEnabled);
      final double stylusBlend =
          _rustUseStylusPressure && _rustSimulatePressure
              ? _kStylusSimulationBlend
              : 1.0;
      final double? initialPressure = _rustPressureSimulator.beginStroke(
        position: enginePos,
        timestampMillis: timestampMillis,
        simulatePressure: _rustSimulatePressure,
        useDevicePressure: _rustUseStylusPressure,
        stylusPressureBlend: stylusBlend,
        stylusPressure: stylusPressure,
      );
      return initialPressure ?? stylusPressure ?? 1.0;
    }
    final double? simulated = _rustPressureSimulator.samplePressure(
      position: enginePos,
      timestampMillis: timestampMillis,
      stylusPressure: stylusPressure,
    );
    return simulated ?? stylusPressure ?? 1.0;
  }

  void _appendRustPoint({
    required Offset enginePos,
    required double pressure,
    required int timestampUs,
    required int flags,
    required int pointerId,
  }) {
    final Offset? previous = _rustLastEnginePoint;
    if (previous != null) {
      final Offset delta = enginePos - previous;
      final double distance = delta.distance;
      if (distance.isFinite && distance > 0.001) {
        _rustLastMovementUnit = delta / distance;
        _rustLastMovementDistance = distance;
      }
    }
    _rustLastResolvedPressure = pressure;
    _rustLastEnginePoint = enginePos;
    _rustPoints.add(
      x: enginePos.dx,
      y: enginePos.dy,
      pressure: pressure,
      timestampUs: timestampUs,
      flags: flags,
      pointerId: pointerId,
    );
  }

  double _rustRadiusFromPressure(double pressure, double baseRadius) {
    final double base = baseRadius.isFinite ? math.max(baseRadius, 0.0) : 0.0;
    if (base <= 0.0) {
      return 0.0;
    }
    final double clamped =
        pressure.isFinite ? pressure.clamp(0.0, 1.0) : 0.0;
    return base *
        (_kRustPressureMinFactor +
            (1.0 - _kRustPressureMinFactor) * clamped);
  }

  Offset? _computeRustSharpTail({
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
    unit ??= _rustLastMovementUnit;
    if (unit == null) {
      return null;
    }
    final double base = math.max(baseRadius, 0.1);
    final double movement =
        length > 0.001 ? length : _rustLastMovementDistance;
    final double taperMax = base * 6.5;
    final double taperDynamic = movement * 2.4 + 2.0;
    final double taperLength = math.min(taperMax, taperDynamic);
    return tip + unit * taperLength;
  }

  void _maybeEmitRustSharpStart({
    required Offset currentPos,
    required double currentPressure,
    required int timestampUs,
    required int pointerId,
  }) {
    if (!_rustWaitingForFirstMove) {
      return;
    }
    _rustWaitingForFirstMove = false;
    if (!_autoSharpPeakEnabled || !_rustPressureSimulator.isSimulatingStroke) {
      return;
    }
    final Offset? startPos = _rustStrokeStartPoint;
    if (startPos == null) {
      return;
    }
    final double baseRadius =
        (_penStrokeWidth / 2).clamp(0.0, 4096.0).toDouble();
    final Offset deltaToCurrent = currentPos - startPos;
    final double distToCurrent = deltaToCurrent.distance;
    if (!distToCurrent.isFinite || distToCurrent <= 0.001) {
      return;
    }
    final double startPressure = _rustStrokeStartPressure.clamp(0.0, 1.0);
    final double r0 = _rustRadiusFromPressure(startPressure, baseRadius);
    final double r1 =
        _rustRadiusFromPressure(currentPressure.clamp(0.0, 1.0), baseRadius);
    if (distToCurrent + r0 >= r1) {
      return;
    }
    final Offset? headPoint = _computeRustSharpTail(
      tip: startPos,
      previousPoint: currentPos,
      baseRadius: baseRadius,
    );
    if (headPoint == null || _rustStrokeStartIndex >= _rustPoints.length) {
      return;
    }
    _rustPoints.updateAt(
      _rustStrokeStartIndex,
      x: headPoint.dx,
      y: headPoint.dy,
      pressure: 0.0,
    );
    _rustLastEnginePoint = headPoint;
    _rustLastResolvedPressure = 0.0;
    final Offset delta = startPos - headPoint;
    final double dist = delta.distance;
    if (dist.isFinite && dist > 0.5 && startPressure > 0.001) {
      final double spacing = math.max(baseRadius * 0.35, 0.75);
      final int segments =
          math.max(2, (dist / spacing).ceil()).clamp(2, 10).toInt();
      for (int i = 1; i < segments; i++) {
        final double t = i / segments;
        final double eased = math.pow(t, 1.6).toDouble();
        final double midPressure = (startPressure * eased).clamp(0.0, 1.0);
        if (midPressure <= 0.001) {
          continue;
        }
        final Offset midPoint = headPoint + delta * t;
        _appendRustPoint(
          enginePos: midPoint,
          pressure: midPressure,
          timestampUs: timestampUs,
          flags: _kRustPointFlagMove,
          pointerId: pointerId,
        );
      }
    }
    _appendRustPoint(
      enginePos: startPos,
      pressure: startPressure,
      timestampUs: timestampUs,
      flags: _kRustPointFlagMove,
      pointerId: pointerId,
    );
  }

  void _enqueueRustPoint(
    PointerEvent event,
    int flags, {
    bool isInitialSample = false,
  }) {
    try {
      _webEnqueueLog(
        'enter flags=$flags handle=$_rustCanvasEngineHandle points=${_rustPoints.length}',
      );
      final int? handle = _rustCanvasEngineHandle;
      if (!_canUseRustCanvasEngine() || handle == null) {
        _webPointerLog(
          'enqueue rust point skipped: engine not ready handle=$handle '
          'supported=${CanvasEngineFfi.instance.isSupported}',
        );
        return;
      }
      final Offset boardLocal = _toBoardLocal(event.localPosition);
      final Offset sanitized = _sanitizeRustStrokePosition(
        boardLocal,
        isInitialSample: isInitialSample,
      );
      final Offset enginePos = _rustToEngineSpace(sanitized);
      final double pressure = _resolveRustPressure(
        event: event,
        enginePos: enginePos,
        isInitialSample: isInitialSample,
      );
      final int timestampUs = event.timeStamp.inMicroseconds;
      if (flags == _kRustPointFlagMove) {
        _maybeEmitRustSharpStart(
          currentPos: enginePos,
          currentPressure: pressure,
          timestampUs: timestampUs,
          pointerId: event.pointer,
        );
      }
      if (flags == _kRustPointFlagDown) {
        _rustStrokeStartPoint = enginePos;
        _rustStrokeStartPressure = pressure;
        _rustStrokeStartIndex = _rustPoints.length;
      }
      _appendRustPoint(
        enginePos: enginePos,
        pressure: pressure,
        timestampUs: timestampUs,
        flags: flags,
        pointerId: event.pointer,
      );
      if (flags == _kRustPointFlagDown || flags == _kRustPointFlagUp) {
        _webPointerLog(
          'enqueue rust point flags=$flags len=${_rustPoints.length}',
        );
      }
      if (_kDebugRustCanvasInput &&
          (flags == _kRustPointFlagDown || flags == _kRustPointFlagUp)) {
        unawaited(
          CanvasEngineFfi.instance.getInputQueueLen(handle).then((queued) {
            debugPrint(
              '[rust_canvas] enqueue flags=$flags points=${_rustPoints.length} '
              'queued=$queued streamline=${_streamlineStrength.toStringAsFixed(3)}',
            );
          }),
        );
      }
      _scheduleRustFlush();
    } catch (error, stackTrace) {
      _webPointerLog('enqueue rust point error $error');
      reportWebLog('enqueue rust point error $error\n$stackTrace');
    }
  }

  void _scheduleRustFlush() {
    if (kIsWeb) {
      final int? handle = _rustCanvasEngineHandle;
      if (!_canUseRustCanvasEngine() || handle == null) {
        _webPointerLog(
          'rust flush aborted: engine not ready handle=$handle '
          'supported=${CanvasEngineFfi.instance.isSupported}',
        );
        _rustPoints.clear();
        return;
      }
      _webPointerLog('rust flush immediate(web) handle=$handle points=${_rustPoints.length}');
      _flushRustPoints(handle);
      return;
    }
    if (_rustWaitingForFirstMove && _rustPoints.length <= 1) {
      if (_rustPoints.length == 1) {
        _webPointerLog('rust flush skipped: waiting first move');
      }
      if (_kDebugRustCanvasInput && _rustPoints.length == 1) {
        debugPrint(
          '[rust_canvas] flush skipped: waiting first move '
          'streamline=${_streamlineStrength.toStringAsFixed(3)}',
        );
      }
      return;
    }
    if (_rustFlushScheduled) {
      _webPointerLog('rust flush skipped: already scheduled');
      return;
    }
    _rustFlushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _rustFlushScheduled = false;
      if (!mounted) {
        _webPointerLog('rust flush aborted: not mounted');
        _rustPoints.clear();
        return;
      }
      final int? handle = _rustCanvasEngineHandle;
      if (!_canUseRustCanvasEngine() || handle == null) {
        _webPointerLog(
          'rust flush aborted: engine not ready handle=$handle '
          'supported=${CanvasEngineFfi.instance.isSupported}',
        );
        _rustPoints.clear();
        return;
      }
      _webPointerLog('rust flush run handle=$handle points=${_rustPoints.length}');
      _flushRustPoints(handle);
    });
  }

  void _flushRustPoints(int handle) {
    final int count = _rustPoints.length;
    if (count == 0) {
      _webPointerLog('rust flush noop: empty');
      return;
    }
    _webPointerLog('rust flush send count=$count handle=$handle');
    if (_kDebugRustCanvasInput) {
      unawaited(
        CanvasEngineFfi.instance.getInputQueueLen(handle).then((queued) {
          debugPrint(
            '[rust_canvas] flush points=$count queued_before=$queued '
            'streamline=${_streamlineStrength.toStringAsFixed(3)}',
          );
        }),
      );
    }
    CanvasEngineFfi.instance.pushPointsPacked(
      handle: handle,
      bytes: _rustPoints.bytes,
      pointCount: count,
    );
    CanvasEngineFfi.instance.requestFrame(handle: handle);
    _rustPoints.clear();
  }

  void _beginRustStroke(PointerDownEvent event) {
    _webPointerLog(
      'begin rust stroke pointer=${event.pointer} kind=${event.kind} '
      'pressure=${event.pressure}',
    );
    if (!_isRustDrawingPointer(event)) {
      _webPointerLog('begin rust stroke ignored: not drawing pointer');
      return;
    }
    _resetPerspectiveLock();
    _lastStrokeBoardPosition = null;
    _rustLastEnginePoint = null;
    _rustLastMovementUnit = null;
    _rustLastMovementDistance = 0.0;
    _rustLastStylusPressure = null;
    _rustLastResolvedPressure = 1.0;
    _rustWaitingForFirstMove = _autoSharpPeakEnabled;
    _rustStrokeStartPoint = null;
    _rustStrokeStartPressure = 1.0;
    _rustStrokeStartIndex = 0;
    final bool supportsPressure = _isStylusEvent(event);
    _rustPressureSimulator.resetTracking();
    _rustSimulatePressure = _simulatePenPressure;
    _rustUseStylusPressure = _stylusPressureEnabled && supportsPressure;
    _rustActiveStrokeUsesPressure =
        _rustUseStylusPressure || _rustSimulatePressure || _autoSharpPeakEnabled;
    _rustPressureSimulator.setSharpTipsEnabled(_autoSharpPeakEnabled);
    _rustActivePointer = event.pointer;
    _webLoggedRustMove = false;
    try {
      _enqueueRustPoint(event, _kRustPointFlagDown, isInitialSample: true);
      _webPointerLog('begin rust stroke enqueued down');
    } catch (error, stackTrace) {
      _webPointerLog('begin rust stroke enqueue error $error');
      reportWebLog('begin rust stroke enqueue error $error\n$stackTrace');
    }
    _markDirty();
  }

  void _endRustStroke(PointerEvent event) {
    _webPointerLog(
      'end rust stroke pointer=${event.pointer} kind=${event.kind} '
      'pos=${event.localPosition}',
    );
    final bool hadActiveStroke = _rustActivePointer != null;
    final int? handle = _rustCanvasEngineHandle;
    final bool canRecordHistory = hadActiveStroke && _canUseRustCanvasEngine();
    if (_canUseRustCanvasEngine() && handle != null) {
      _rustWaitingForFirstMove = false;
      final Offset boardLocal = _toBoardLocal(event.localPosition);
      final Offset sanitized = _sanitizeRustStrokePosition(
        boardLocal,
        isInitialSample: false,
      );
      _lastBrushLineAnchor = sanitized;
      final Offset enginePos = _rustToEngineSpace(sanitized);
      final double pressure = _resolveRustPressure(
        event: event,
        enginePos: enginePos,
        isInitialSample: false,
      );
      final int timestampUs = event.timeStamp.inMicroseconds;
      final double startPressure = _rustLastResolvedPressure.isFinite
          ? _rustLastResolvedPressure
          : pressure;
      final bool wantsSharpTail =
          _autoSharpPeakEnabled && _rustPressureSimulator.isSimulatingStroke;
      if (wantsSharpTail) {
        final Offset? previousPoint = _rustLastEnginePoint;
        final double baseRadius =
            (_penStrokeWidth / 2).clamp(0.0, 4096.0).toDouble();
        Offset? tailPoint = _computeRustSharpTail(
          tip: enginePos,
          previousPoint: previousPoint,
          baseRadius: baseRadius,
        );
        final double lastRadius =
            _rustRadiusFromPressure(startPressure, baseRadius);
        final double endRadius = _rustRadiusFromPressure(0.0, baseRadius);
        if (tailPoint == null &&
            _rustLastMovementUnit != null &&
            lastRadius > endRadius) {
          final double targetDist = lastRadius - endRadius + 1.5;
          tailPoint = enginePos + _rustLastMovementUnit! * targetDist;
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
          _appendRustPoint(
            enginePos: enginePos,
            pressure: tailPressure,
            timestampUs: timestampUs,
            flags: _kRustPointFlagMove,
            pointerId: event.pointer,
          );
          final Offset delta = tailPoint - enginePos;
          final double dist = delta.distance;
          if (dist.isFinite && dist > 0.5 && tailPressure > 0.001) {
            final double spacing = math.max(baseRadius * 0.35, 0.75);
            final int segments =
                math.max(2, (dist / spacing).ceil()).clamp(2, 10).toInt();
            for (int i = 1; i < segments; i++) {
              final double t = i / segments;
              final double eased = math.pow(1.0 - t, 1.6).toDouble();
              final double midPressure =
                  (tailPressure * eased).clamp(0.0, 1.0);
              if (midPressure <= 0.001) {
                continue;
              }
              final Offset midPoint = enginePos + delta * t;
              _appendRustPoint(
                enginePos: midPoint,
                pressure: midPressure,
                timestampUs: timestampUs,
                flags: _kRustPointFlagMove,
                pointerId: event.pointer,
              );
            }
          }
          _appendRustPoint(
            enginePos: tailPoint,
            pressure: 0.0,
            timestampUs: timestampUs,
            flags: _kRustPointFlagUp,
            pointerId: event.pointer,
          );
        } else {
          _appendRustPoint(
            enginePos: enginePos,
            pressure: 0.0,
            timestampUs: timestampUs,
            flags: _kRustPointFlagUp,
            pointerId: event.pointer,
          );
        }
      } else {
        _appendRustPoint(
          enginePos: enginePos,
          pressure: pressure,
          timestampUs: timestampUs,
          flags: _kRustPointFlagUp,
          pointerId: event.pointer,
        );
      }
      _scheduleRustFlush();
      if (canRecordHistory) {
        _recordRustHistoryAction(
          layerId: _activeLayerId,
          deferPreview: true,
        );
        if (mounted) {
          setState(() {});
        }
      }
    }
    _rustActivePointer = null;
    _rustActiveStrokeUsesPressure = true;
    _rustSimulatePressure = false;
    _rustUseStylusPressure = false;
    _rustPressureSimulator.resetTracking();
    _rustLastEnginePoint = null;
    _rustLastMovementUnit = null;
    _rustLastMovementDistance = 0.0;
    _rustLastStylusPressure = null;
    _rustLastResolvedPressure = 1.0;
    _rustWaitingForFirstMove = false;
    _rustStrokeStartPoint = null;
    _rustStrokeStartPressure = 1.0;
    _rustStrokeStartIndex = 0;
    _lastStrokeBoardPosition = null;
    _strokeStabilizer.reset();
    _resetPerspectiveLock();
  }

  bool _drawRustStraightLine({
    required Offset start,
    required Offset end,
    required PointerDownEvent event,
  }) {
    final int? handle = _rustCanvasEngineHandle;
    if (!_canUseRustCanvasEngine() || handle == null) {
      return false;
    }
    final Offset startClamped = _clampToCanvas(start);
    final Offset endClamped = _clampToCanvas(end);
    final Offset startEngine = _rustToEngineSpace(startClamped);
    final Offset endEngine = _rustToEngineSpace(endClamped);
    final int startTimestampUs = event.timeStamp.inMicroseconds;
    final int endTimestampUs = startTimestampUs + 1000;
    final double pressure =
        (_normalizePointerPressure(event) ?? 1.0).clamp(0.0, 1.0);

    _rustLastEnginePoint = null;
    _rustLastMovementUnit = null;
    _rustLastMovementDistance = 0.0;
    _rustLastStylusPressure = null;
    _rustLastResolvedPressure = 1.0;
    _rustWaitingForFirstMove = false;
    _rustStrokeStartPoint = null;
    _rustStrokeStartPressure = 1.0;
    _rustStrokeStartIndex = 0;

    _appendRustPoint(
      enginePos: startEngine,
      pressure: pressure,
      timestampUs: startTimestampUs,
      flags: _kRustPointFlagDown,
      pointerId: event.pointer,
    );
    _appendRustPoint(
      enginePos: endEngine,
      pressure: pressure,
      timestampUs: endTimestampUs,
      flags: _kRustPointFlagUp,
      pointerId: event.pointer,
    );
    _scheduleRustFlush();
    _recordRustHistoryAction(
      layerId: _activeLayerId,
      deferPreview: true,
    );
    if (mounted) {
      setState(() {});
    }
    _markDirty();
    _resetPerspectiveLock();
    return true;
  }

  void _handlePointerDown(PointerDownEvent event) async {
    _webPointerLog(
      'down enter kind=${event.kind} buttons=${event.buttons} down=${event.down} '
      'pos=${event.localPosition}',
    );
    if (!_isPrimaryPointer(event)) {
      _webPointerLog(
        'down ignore: not primary kind=${event.kind} buttons=${event.buttons} down=${event.down}',
      );
      return;
    }
    if (_isScalingGesture) {
      _webPointerLog('down ignore: scaling gesture');
      return;
    }
    if (_layerTransformApplying) {
      _webPointerLog('down ignore: layer transform applying');
      return;
    }
    _recordWorkspacePointer(event.localPosition);
    _updateToolCursorOverlay(event.localPosition);
    final Offset pointer = event.localPosition;
    if (_isInsideToolArea(pointer) || _isInsideWorkspacePanelArea(pointer)) {
      _webPointerLog('down ignore: inside tool/workspace area');
      return;
    }
    final CanvasTool tool = _effectiveActiveTool;
    final Rect boardRect = _boardRect;
    final Offset boardLocal = _toBoardLocal(pointer);
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
    )) {
      return;
    }
    final bool pointerInsideBoard = boardRect.contains(pointer);
    final bool toolCanStartOutsideCanvas =
        tool == CanvasTool.curvePen ||
        tool == CanvasTool.selection ||
        tool == CanvasTool.selectionPen ||
        tool == CanvasTool.spray ||
        tool == CanvasTool.pen ||
        tool == CanvasTool.eraser ||
        tool == CanvasTool.perspectivePen;
    if (!pointerInsideBoard && !toolCanStartOutsideCanvas) {
      _webPointerLog('down ignore: outside board tool=$tool');
      return;
    }
    if (_shouldBlockToolOnTextLayer(tool)) {
      _webPointerLog('down ignore: text layer conflict');
      _showTextToolConflictWarning();
      return;
    }
    if (_isTextEditingActive) {
      _webPointerLog('down ignore: text editing active');
      return;
    }
    if (_layerTransformModeActive) {
      _webPointerLog('down ignore: layer transform mode active');
      if (pointerInsideBoard) {
        _handleLayerTransformPointerDown(boardLocal);
      }
      return;
    }
    switch (tool) {
      case CanvasTool.layerAdjust:
        await _beginLayerAdjustDrag(boardLocal);
        break;
      case CanvasTool.pen:
      case CanvasTool.eraser:
        _focusNode.requestFocus();
        if (!_canStartRustStroke(pointerInsideBoard: pointerInsideBoard)) {
          return;
        }
        if (!isPointInsideSelection(boardLocal)) {
          _webPointerLog('down ignore: outside selection');
          return;
        }
        if (shiftPressed) {
          final Offset? anchor = _lastBrushLineAnchor;
          if (anchor != null &&
              _drawRustStraightLine(
                start: anchor,
                end: boardLocal,
                event: event,
              )) {
            _lastBrushLineAnchor = _clampToCanvas(boardLocal);
            return;
          }
        }
        _beginRustStroke(event);
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
      case CanvasTool.selectionPen:
        _focusNode.requestFocus();
        _handleSelectionPenPointerDown(boardLocal);
        break;
      case CanvasTool.text:
        _focusNode.requestFocus();
        if (!pointerInsideBoard) {
          return;
        }
        final BitmapLayerState? targetLayer = _hitTestTextLayer(boardLocal);
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

  void _handlePointerMove(PointerMoveEvent event) {
    final bool rustStrokeActive = _rustActivePointer == event.pointer;
    if (!_isPrimaryPointer(event) && !rustStrokeActive) {
      return;
    }
    if (rustStrokeActive && !_webLoggedRustMove) {
      _webLoggedRustMove = true;
      _webPointerLog(
        'move rust active pointer=${event.pointer} pos=${event.localPosition}',
      );
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
    if (_layerTransformModeActive) {
      final Offset boardLocal = _toBoardLocal(event.localPosition);
      _handleLayerTransformPointerMove(boardLocal);
      return;
    }
    switch (_effectiveActiveTool) {
      case CanvasTool.pen:
      case CanvasTool.eraser:
        if (rustStrokeActive) {
          final dynamic dyn = event;
          try {
            final List<dynamic>? coalesced =
                dyn.coalescedEvents as List<dynamic>?;
            if (coalesced != null && coalesced.isNotEmpty) {
              for (final dynamic e in coalesced) {
                if (e is PointerEvent) {
                  _enqueueRustPoint(e, _kRustPointFlagMove);
                }
              }
              break;
            }
          } catch (_) {}
          _enqueueRustPoint(event, _kRustPointFlagMove);
          break;
        }
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

  void _handlePointerUp(PointerUpEvent event) async {
    _webPointerLog(
      'up enter kind=${event.kind} buttons=${event.buttons} down=${event.down} '
      'pos=${event.localPosition}',
    );
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
        if (_rustActivePointer == event.pointer) {
          _endRustStroke(event);
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

  void _handlePointerCancel(PointerCancelEvent event) {
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
        if (_rustActivePointer == event.pointer) {
          _endRustStroke(event);
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

  void _handlePointerHover(PointerHoverEvent event) {
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

  @override
  KeyEventResult _handleWorkspaceKeyEvent(FocusNode node, KeyEvent event) {
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

  void _handleRedo() {
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

  Future<bool> undo() async {
    _refreshHistoryLimit();
    if (_useCombinedHistory) {
      final _HistoryActionKind? action = _peekHistoryUndoAction();
      if (action == _HistoryActionKind.rust) {
        final int? handle = _rustCanvasEngineHandle;
        if (!_canUseRustCanvasEngine() || handle == null) {
          return false;
        }
        CanvasEngineFfi.instance.undo(handle: handle);
        _commitHistoryUndoAction();
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
            rustPixelsSynced: previous.rustPixelsSynced,
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
      await _createHistoryEntry(rustPixelsSynced: previous.rustPixelsSynced),
    );
    _trimHistoryStacks();
    await _applyHistoryEntry(previous);
    return true;
  }

  Future<bool> redo() async {
    _refreshHistoryLimit();
    if (_useCombinedHistory) {
      final _HistoryActionKind? action = _peekHistoryRedoAction();
      if (action == _HistoryActionKind.rust) {
        final int? handle = _rustCanvasEngineHandle;
        if (!_canUseRustCanvasEngine() || handle == null) {
          return false;
        }
        CanvasEngineFfi.instance.redo(handle: handle);
        _commitHistoryRedoAction();
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
          await _createHistoryEntry(rustPixelsSynced: next.rustPixelsSynced),
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
      await _createHistoryEntry(rustPixelsSynced: next.rustPixelsSynced),
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
