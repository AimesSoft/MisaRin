part of 'painting_board.dart';

const double _kStylusSimulationBlend = 0.68;
const int _kBackendPointStrideBytes = 32;
const int _kBackendPointFlagDown = 1;
const int _kBackendPointFlagMove = 2;
const int _kBackendPointFlagUp = 4;
const double _kBackendPressureMinFactor = 0.09;
const double _kBackendPressureMaxFactor = 1.0;
final bool _kDebugBackendCanvasInput = bool.fromEnvironment(
  'MISA_RIN_DEBUG_RUST_CANVAS_INPUT',
  defaultValue: false,
);
final bool _kDebugPencilPredictionOverlay =
    kDebugMode ||
    bool.fromEnvironment(
      'MISA_RIN_DEBUG_PENCIL_PREDICTION',
      defaultValue: false,
    );
const bool _kEnableBridgeCoalescedForStroke = bool.fromEnvironment(
  'MISA_RIN_ENABLE_BRIDGE_COALESCED_FOR_STROKE',
  defaultValue: false,
);
const Duration _kCursorLocateDetectWindow = Duration(milliseconds: 480);
const Duration _kCursorLocateHoldDuration = Duration(milliseconds: 120);
const Duration _kCursorLocateExpandDuration = Duration(milliseconds: 110);
const Duration _kCursorLocateFadeDuration = Duration(milliseconds: 420);
const double _kCursorLocateTargetExtentRatio = 0.095;
const double _kCursorLocateMinExtent = 110.0;
const double _kCursorLocateMaxExtent = 260.0;
const double _kCursorLocateExtraExtentFactor = 0.55;
const double _kCursorLocateMinSegmentDistance = 3.0;
const double _kCursorLocateMinSpeedPxPerSec = 1600.0;
const int _kCursorLocateMinDirectionFlips = 3;
const Duration _kCursorLocateTriggerDebounce = Duration(milliseconds: 550);

final class _BackendPointBuffer {
  _BackendPointBuffer({int initialCapacityPoints = 256})
    : _bytes = Uint8List(initialCapacityPoints * _kBackendPointStrideBytes) {
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
    final int base = _len * _kBackendPointStrideBytes;
    _data.setFloat32(base + 0, x, Endian.little);
    _data.setFloat32(base + 4, y, Endian.little);
    _data.setFloat32(base + 8, pressure, Endian.little);
    _data.setFloat32(base + 12, 0.0, Endian.little);
    _data.setUint64(base + 16, timestampUs, Endian.little);
    _data.setUint32(base + 24, flags, Endian.little);
    _data.setUint32(base + 28, pointerId, Endian.little);
    _len++;
  }

  void updateAt(int index, {double? x, double? y, double? pressure}) {
    if (index < 0 || index >= _len) {
      return;
    }
    final int base = index * _kBackendPointStrideBytes;
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
    final int neededBytes = neededPoints * _kBackendPointStrideBytes;
    if (_bytes.lengthInBytes >= neededBytes) {
      return;
    }
    int nextBytes = _bytes.lengthInBytes;
    while (nextBytes < neededBytes) {
      nextBytes = nextBytes * 2;
    }
    final Uint8List next = Uint8List(nextBytes);
    next.setRange(0, _len * _kBackendPointStrideBytes, _bytes, 0);
    _bytes = next;
    _data = ByteData.view(_bytes.buffer);
  }
}

final class _BackendPressureSimulator {
  _BackendPressureSimulator()
    : _strokeDynamics = StrokeDynamics(
        profile: StrokePressureProfile.auto,
        minRadiusFactor: _kBackendPressureMinFactor,
        maxRadiusFactor: _kBackendPressureMaxFactor,
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
    final double normalizedSpeed = _velocitySmoother.addSample(
      position,
      timestampMillis,
    );

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

    final StrokeSampleMetrics? metrics = _profile == StrokePressureProfile.auto
        ? StrokeSampleMetrics(
            sampleIndex: _strokeSamples.length - 1,
            normalizedSpeed: normalizedSpeed,
            stationaryDuration: sample.stationaryDuration,
            totalDistance: _strokeSamples.totalDistance,
            totalTime: _strokeSamples.totalTime,
          )
        : null;
    final double? intensityOverride = _usesDevicePressure
        ? _stylusPressureToIntensity(stylusPressure)
        : null;
    final double effectiveBlend = intensityOverride != null
        ? _stylusPressureBlend
        : 0.0;
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

class _CursorMotionSample {
  const _CursorMotionSample(this.position, this.timestampUs);

  final Offset position;
  final int timestampUs;
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
  final _BackendPointBuffer _backendPoints = _BackendPointBuffer();
  final _BackendPressureSimulator _backendPressureSimulator =
      _BackendPressureSimulator();
  bool _backendFlushScheduled = false;
  bool _backendRasterOutputSuppressed = false;
  int? _backendActivePointer;
  bool _backendActiveStrokeUsesPressure = true;
  bool _backendSimulatePressure = false;
  bool _backendUseStylusPressure = false;
  Offset? _backendLastEnginePoint;
  Offset? _backendLastMovementUnit;
  double _backendLastMovementDistance = 0.0;
  double? _backendLastStylusPressure;
  double _backendLastResolvedPressure = 1.0;
  bool _backendWaitingForFirstMove = false;
  Offset? _backendStrokeStartPoint;
  double _backendStrokeStartPressure = 1.0;
  int _backendStrokeStartIndex = 0;
  bool _backendLatencyPending = false;
  bool _backendLatencyFrameScheduled = false;
  final List<Offset> _backendPredictedPoints = <Offset>[];
  final List<double> _backendPredictedRadii = <double>[];
  int _backendPredictedOverlayRevision = 0;
  bool _backendPredictedOverlayFrameScheduled = false;
  int _debugPredictedOverlayFrames = 0;
  int _debugPredictedOverlayPoints = 0;
  int _debugPredictedOverlayBackendFrames = 0;
  DateTime? _debugPredictedOverlayLogAt;
  final List<_CursorMotionSample> _cursorLocateSamples =
      <_CursorMotionSample>[];
  AnimationController? _cursorLocateController;
  Timer? _cursorLocateCollapseTimer;
  int _lastCursorLocateTriggerUs = 0;

  bool get _showBackendPredictedOverlay =>
      _backendPredictedPoints.isNotEmpty &&
      _backendPredictedPoints.length == _backendPredictedRadii.length;

  double get _cursorLocateOverlayProgress {
    final AnimationController? controller = _cursorLocateController;
    if (controller == null || !controller.value.isFinite) {
      return 0.0;
    }
    return Curves.easeOutCubic.transform(controller.value.clamp(0.0, 1.0));
  }

  double _cursorLocateTargetExtent() {
    final double shortestSide = _workspaceSize.shortestSide;
    if (!shortestSide.isFinite || shortestSide <= 0) {
      return 140.0;
    }
    final double target = shortestSide * _kCursorLocateTargetExtentRatio;
    return target.clamp(_kCursorLocateMinExtent, _kCursorLocateMaxExtent);
  }

  double _cursorLocateScaledExtent(double baseExtent) {
    final double base = (baseExtent.isFinite && baseExtent > 0)
        ? baseExtent
        : 1.0;
    final double progress = _cursorLocateOverlayProgress;
    if (progress <= 0.0) {
      return base;
    }
    final double targetExtent = _cursorLocateTargetExtent();
    final double desiredExtent = math.max(
      targetExtent,
      base + targetExtent * _kCursorLocateExtraExtentFactor,
    );
    return ui.lerpDouble(base, desiredExtent, progress) ?? desiredExtent;
  }

  double _cursorLocateScaleForExtent(double baseExtent) {
    final double base = (baseExtent.isFinite && baseExtent > 0)
        ? baseExtent
        : 1.0;
    return _cursorLocateScaledExtent(base) / base;
  }

  void _initializeCursorLocateOverlayAnimation() {
    final AnimationController controller = AnimationController(
      vsync: this,
      duration: _kCursorLocateExpandDuration,
      reverseDuration: _kCursorLocateFadeDuration,
      value: 0.0,
    )..addListener(_handleCursorLocateOverlayTick);
    _cursorLocateController = controller;
  }

  void _disposeCursorLocateOverlayAnimation() {
    _cursorLocateCollapseTimer?.cancel();
    _cursorLocateCollapseTimer = null;
    _cursorLocateSamples.clear();
    final AnimationController? controller = _cursorLocateController;
    if (controller == null) {
      return;
    }
    controller.removeListener(_handleCursorLocateOverlayTick);
    controller.dispose();
    _cursorLocateController = null;
  }

  void _handleCursorLocateOverlayTick() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _updateCursorLocateFromMouseMotion(
    Offset workspacePosition, {
    Duration? timestamp,
  }) {
    final AnimationController? controller = _cursorLocateController;
    if (controller == null) {
      return;
    }
    final int nowUs =
        timestamp?.inMicroseconds ?? DateTime.now().microsecondsSinceEpoch;
    _cursorLocateSamples.add(_CursorMotionSample(workspacePosition, nowUs));
    final int minUs = nowUs - _kCursorLocateDetectWindow.inMicroseconds;
    while (_cursorLocateSamples.length > 2 &&
        _cursorLocateSamples.first.timestampUs < minUs) {
      _cursorLocateSamples.removeAt(0);
    }
    if (_cursorLocateSamples.length < 4) {
      return;
    }

    double distanceSum = 0.0;
    int directionFlips = 0;
    Offset? previousDirection;
    for (int i = 1; i < _cursorLocateSamples.length; i++) {
      final Offset delta =
          _cursorLocateSamples[i].position -
          _cursorLocateSamples[i - 1].position;
      final double distance = delta.distance;
      if (!distance.isFinite || distance < _kCursorLocateMinSegmentDistance) {
        continue;
      }
      distanceSum += distance;
      final Offset direction = Offset(delta.dx / distance, delta.dy / distance);
      if (previousDirection != null) {
        final double dot =
            previousDirection.dx * direction.dx +
            previousDirection.dy * direction.dy;
        if (dot < -0.52) {
          directionFlips += 1;
        }
      }
      previousDirection = direction;
    }
    if (directionFlips < _kCursorLocateMinDirectionFlips) {
      return;
    }
    final int durationUs =
        _cursorLocateSamples.last.timestampUs -
        _cursorLocateSamples.first.timestampUs;
    if (durationUs <= 0) {
      return;
    }
    final double speedPxPerSec =
        distanceSum / (durationUs / Duration.microsecondsPerSecond);
    if (!speedPxPerSec.isFinite ||
        speedPxPerSec < _kCursorLocateMinSpeedPxPerSec) {
      return;
    }
    if ((nowUs - _lastCursorLocateTriggerUs) <
        _kCursorLocateTriggerDebounce.inMicroseconds) {
      return;
    }
    _lastCursorLocateTriggerUs = nowUs;
    _triggerCursorLocatePulse();
  }

  void _triggerCursorLocatePulse() {
    final AnimationController? controller = _cursorLocateController;
    if (controller == null) {
      return;
    }
    _cursorLocateCollapseTimer?.cancel();
    controller.animateTo(1.0, curve: Curves.easeOutCubic);
    _cursorLocateCollapseTimer = Timer(_kCursorLocateHoldDuration, () {
      final AnimationController? active = _cursorLocateController;
      if (active == null) {
        return;
      }
      active.reverse();
    });
  }

  void _scheduleBackendPredictedOverlayRepaint() {
    if (_backendPredictedOverlayFrameScheduled) {
      return;
    }
    _backendPredictedOverlayFrameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _backendPredictedOverlayFrameScheduled = false;
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  void _debugRecordPredictedOverlaySample({
    required int predictedPoints,
    required bool backendStrokeActive,
  }) {
    if (!_kDebugPencilPredictionOverlay || !kDebugMode) {
      return;
    }
    _debugPredictedOverlayFrames += 1;
    _debugPredictedOverlayPoints += predictedPoints;
    if (backendStrokeActive) {
      _debugPredictedOverlayBackendFrames += 1;
    }
    final DateTime now = DateTime.now();
    final DateTime? lastAt = _debugPredictedOverlayLogAt;
    if (lastAt != null && now.difference(lastAt).inMilliseconds < 1000) {
      return;
    }
    _debugPredictedOverlayLogAt = now;
    _debugPredictedOverlayFrames = 0;
    _debugPredictedOverlayPoints = 0;
    _debugPredictedOverlayBackendFrames = 0;
  }

  void _suppressRasterOutputForBackendStroke() {
    if (_backendRasterOutputSuppressed) {
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }
    if (!_backend.isSupported || !_controller.rasterOutputEnabled) {
      return;
    }
    _controller.setRasterOutputEnabled(false);
    _backendRasterOutputSuppressed = true;
  }

  void _restoreRasterOutputAfterBackendStroke() {
    if (!_backendRasterOutputSuppressed) {
      return;
    }
    _backendRasterOutputSuppressed = false;
    _controller.setRasterOutputEnabled(true);
  }

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
    if (_brushPresetWheelActive) {
      _finishBrushPresetWheel(commit: false);
    }
    final bool shouldCommitText =
        tool != CanvasTool.text && _isTextEditingActive;
    if (_guardTransformInProgress(
      message: context.l10n.completeTransformFirst,
    )) {
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
    if (_activeTool == CanvasTool.smudge && _isSmudging) {
      _finishSmudgeStroke();
    }
    if (_activeTool == CanvasTool.liquify && _isLiquifying) {
      _finishLiquifyStroke();
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
    _backendPredictedPoints.clear();
    _backendPredictedRadii.clear();
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
      if (tool != CanvasTool.eraser) {
        _applePencilLastNonEraserTool = tool;
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
    final double clamped = _sprayStrokeSliderRange.clamp(value).roundToDouble();
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

  void _updateEraserStrokeWidth(double value) {
    final double clamped = _eraserStrokeSliderRange
        .clamp(value)
        .roundToDouble();
    if ((_eraserStrokeWidth - clamped).abs() < 0.0005) {
      return;
    }
    setState(() => _eraserStrokeWidth = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.eraserStrokeWidth = clamped;
    unawaited(AppPreferences.save());
  }

  void _updateLiquifyStrokeWidth(double value) {
    final double clamped = value.clamp(8.0, 500.0).roundToDouble();
    if ((_liquifyStrokeWidth - clamped).abs() < 0.0005) {
      return;
    }
    setState(() => _liquifyStrokeWidth = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.liquifyStrokeWidth = clamped;
    unawaited(AppPreferences.save());
  }

  void _updateLiquifyStrength(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    if ((_liquifyStrength - clamped).abs() < 0.0005) {
      return;
    }
    setState(() => _liquifyStrength = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.liquifyStrength = clamped;
    unawaited(AppPreferences.save());
  }

  void _updateLiquifySoftness(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    if ((_liquifySoftness - clamped).abs() < 0.0005) {
      return;
    }
    setState(() => _liquifySoftness = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.liquifySoftness = clamped;
    unawaited(AppPreferences.save());
  }

  void _updateLiquifyMix(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    if ((_liquifyMix - clamped).abs() < 0.0005) {
      return;
    }
    setState(() => _liquifyMix = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.liquifyMix = clamped;
    unawaited(AppPreferences.save());
  }

  @override
  void _updateSmudgeStrokeWidth(double value) {
    final double clamped = value.clamp(8.0, 500.0).roundToDouble();
    if ((_smudgeStrokeWidth - clamped).abs() < 0.0005) {
      return;
    }
    setState(() => _smudgeStrokeWidth = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.smudgeStrokeWidth = clamped;
    unawaited(AppPreferences.save());
  }

  @override
  void _updateSmudgeStrength(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    if ((_smudgeStrength - clamped).abs() < 0.0005) {
      return;
    }
    setState(() => _smudgeStrength = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.smudgeStrength = clamped;
    unawaited(AppPreferences.save());
  }

  @override
  void _updateSmudgeSoftness(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    if ((_smudgeSoftness - clamped).abs() < 0.0005) {
      return;
    }
    setState(() => _smudgeSoftness = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.smudgeSoftness = clamped;
    unawaited(AppPreferences.save());
  }

  void _updatePenStrokeSliderRange(PenStrokeSliderRange range) {
    if (_penStrokeSliderRange == range) {
      return;
    }
    final double clamped = range.clamp(_penStrokeWidth);
    setState(() {
      _penStrokeSliderRange = range;
      _penStrokeWidth = clamped;
    });
    final AppPreferences prefs = AppPreferences.instance;
    prefs.penStrokeSliderRange = range;
    prefs.penStrokeWidth = clamped;
    unawaited(AppPreferences.save());
  }

  void _updateSprayStrokeSliderRange(PenStrokeSliderRange range) {
    if (_sprayStrokeSliderRange == range) {
      return;
    }
    final double clamped = range.clamp(_sprayStrokeWidth).roundToDouble();
    setState(() {
      _sprayStrokeSliderRange = range;
      _sprayStrokeWidth = clamped;
    });
    if (_sprayMode == SprayMode.splatter) {
      _kritaSprayEngine?.updateSettings(_buildKritaSpraySettings());
    }
    final AppPreferences prefs = AppPreferences.instance;
    prefs.sprayStrokeSliderRange = range;
    prefs.sprayStrokeWidth = clamped;
    unawaited(AppPreferences.save());
  }

  void _updateEraserStrokeSliderRange(PenStrokeSliderRange range) {
    if (_eraserStrokeSliderRange == range) {
      return;
    }
    final double clamped = range.clamp(_eraserStrokeWidth).roundToDouble();
    setState(() {
      _eraserStrokeSliderRange = range;
      _eraserStrokeWidth = clamped;
    });
    final AppPreferences prefs = AppPreferences.instance;
    prefs.eraserStrokeSliderRange = range;
    prefs.eraserStrokeWidth = clamped;
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
    _backendPressureSimulator.setSharpTipsEnabled(value);
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
    if (_backendPredictedPoints.isNotEmpty ||
        _backendPredictedRadii.isNotEmpty) {
      _backendPredictedPoints.clear();
      _backendPredictedRadii.clear();
      _scheduleBackendPredictedOverlayRepaint();
    }
  }

  bool _isActiveLayerLocked() => _isActiveLayerLockedImpl();

  Offset _backendToEngineSpace(Offset boardLocal) =>
      _backendToEngineSpaceImpl(boardLocal);

  void _handlePointerDown(PointerDownEvent event) async {
    await _handlePointerDownImpl(event);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _handlePointerMoveImpl(event);
  }

  void _handlePointerUp(PointerUpEvent event) async {
    await _handlePointerUpImpl(event);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _handlePointerCancelImpl(event);
  }

  void _handlePointerHover(PointerHoverEvent event) {
    _handlePointerHoverImpl(event);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    _handlePointerSignalImpl(event);
  }

  @override
  KeyEventResult _handleWorkspaceKeyEvent(FocusNode node, KeyEvent event) {
    return _handleWorkspaceKeyEventImpl(node, event);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _handleScaleStartImpl(details);
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    _handleScaleUpdateImpl(details);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _handleScaleEndImpl(details);
  }

  void _handleUndo() {
    _handleUndoImpl();
  }

  void _handleRedo() {
    _handleRedoImpl();
  }
}
