part of 'painting_board.dart';

extension _PaintingBoardInteractionStrokeExtension on _PaintingBoardInteractionMixin {
  void _updateBucketSwallowColorLine(bool value) {
    if (_bucketSwallowColorLine == value) {
      return;
    }
    setState(() => _bucketSwallowColorLine = value);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.bucketSwallowColorLine = value;
    unawaited(AppPreferences.save());
  }

  void _updateBucketSwallowColorLineMode(BucketSwallowColorLineMode mode) {
    if (_bucketSwallowColorLineMode == mode) {
      return;
    }
    setState(() => _bucketSwallowColorLineMode = mode);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.bucketSwallowColorLineMode = mode;
    unawaited(AppPreferences.save());
  }

  void _updateBucketTolerance(int value) {
    final int clamped = value.clamp(0, 255).toInt();
    if (_bucketTolerance == clamped) {
      return;
    }
    setState(() => _bucketTolerance = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.bucketTolerance = clamped;
    unawaited(AppPreferences.save());
  }

  void _updateBucketFillGap(int value) {
    final int clamped = value.clamp(0, 64).toInt();
    if (_bucketFillGap == clamped) {
      return;
    }
    setState(() => _bucketFillGap = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.bucketFillGap = clamped;
    unawaited(AppPreferences.save());
  }

  void _updateMagicWandTolerance(int value) {
    final int clamped = value.clamp(0, 255).toInt();
    if (_magicWandTolerance == clamped) {
      return;
    }
    setState(() => _magicWandTolerance = clamped);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.magicWandTolerance = clamped;
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

  Future<void> _commitPerspectivePenStroke(
    Offset boardLocal,
    Duration timestamp, {
    PointerEvent? rawEvent,
  }) async {
    final Offset? anchor = _perspectivePenAnchor;
    final Offset? snapped = _perspectivePenSnappedTarget;
    if (anchor == null || snapped == null) {
      return;
    }
    final bool backendOk =
        _backend.supportsInputQueue &&
        _brushShapeSupportsBackend &&
        _drawBackendStrokeFromPoints(
          points: <Offset>[anchor, snapped],
          initialTimestampMillis: timestamp.inMicroseconds / 1000.0,
          simulatePressure: _simulatePenPressure,
          rawEvent: rawEvent,
        );
    _clearPerspectivePenPreview();
    if (backendOk) {
      return;
    }
    _showBackendCanvasMessage('透视画笔需要画布后端支持。');
  }

  double _resolveSprayPressure(PointerEvent? event) {
    final double? stylusPressure = _stylusPressureValue(event);
    if (stylusPressure == null || !stylusPressure.isFinite) {
      return 1.0;
    }
    return stylusPressure.clamp(0.0, 1.0);
  }

  /// Builds a Krita-style spray configuration using the current stroke width
  /// and anti-alias settings. This mirrors Krita's spray brush defaults
  /// (`plugins/paintops/spray`) but tweaks a few constants so the Flutter
  /// rasterizer produces similar densities.
  KritaSprayEngineSettings _buildKritaSpraySettings() {
    final double clampedDiameter = _sprayStrokeWidth.clamp(
      kSprayStrokeMin,
      kSprayStrokeMax,
    );
    return KritaSprayEngineSettings(
      diameter: clampedDiameter,
      scale: 1.0,
      aspectRatio: 1.0,
      rotation: 0.0,
      jitterMovement: true,
      jitterAmount: 0.2,
      radialDistribution: KritaRadialDistributionType.gaussian,
      radialCenterBiased: true,
      gaussianSigma: 0.35,
      particleMultiplier: 1.0,
      randomSize: true,
      minParticleScale: 0.014,
      maxParticleScale: 0.086,
      baseParticleScale: 0.05,
      minParticleRadius: 0.32,
      minParticleOpacity: 1.0,
      maxParticleOpacity: 1.0,
      shape: BrushShape.circle,
      minAntialiasLevel: _penAntialiasLevel.clamp(0, 9),
    );
  }

  KritaSprayEngine _ensureKritaSprayEngine() {
    final KritaSprayEngine engine = _kritaSprayEngine ??= KritaSprayEngine(
      clampToCanvas: (offset) => offset,
      random: _syntheticStrokeRandom,
    );
    engine.updateSettings(_buildKritaSpraySettings());
    return engine;
  }

  void _ensureSprayTicker() {
    if (_sprayTicker != null) {
      return;
    }
    _sprayTicker = createTicker(_handleSprayTick);
  }

  Future<void> _startSprayStroke(Offset boardLocal, PointerEvent event) async {
    if (!isPointInsideSelection(boardLocal)) {
      return;
    }
    _focusNode.requestFocus();
    if (!_backend.supportsSpray) {
      _showBackendCanvasMessage('喷枪需要画布后端支持。');
      return;
    }
    if (!_backend.beginSpray()) {
      _showBackendCanvasMessage('画布后端尚未准备好。');
      return;
    }
    _backendSprayActive = true;
    _backendSprayHasDrawn = false;
    _sprayBoardPosition = boardLocal;
    _sprayCurrentPressure = _resolveSprayPressure(event);
    _sprayEmissionAccumulator = 0.0;
    _sprayTickerTimestamp = null;
    _activeSprayColor = _isBrushEraserEnabled
        ? const Color(0xFFFFFFFF)
        : _primaryColor;
    if (_sprayMode == SprayMode.smudge) {
      _softSprayLastPoint = boardLocal;
      _softSprayResidual = 0.0;
      _stampSoftSprayBatch(
        <Offset>[boardLocal],
        _resolveSoftSprayRadius(),
        _sprayCurrentPressure,
      );
      _markDirty();
    } else {
      _ensureKritaSprayEngine();
      _ensureSprayTicker();
      _sprayTicker?.start();
    }
    setState(() {
      _isSpraying = true;
    });
  }

  void _updateSprayStroke(Offset boardLocal, PointerEvent event) {
    if (!_isSpraying) {
      return;
    }
    _sprayBoardPosition = boardLocal;
    _sprayCurrentPressure = _resolveSprayPressure(event);
    if (_sprayMode == SprayMode.smudge) {
      _extendSoftSprayStroke(boardLocal);
    }
  }

  void _finishSprayStroke() {
    if (!_isSpraying) {
      return;
    }
    _sprayTicker?.stop();
    if (_backendSprayActive) {
      _backend.endSpray();
      if (_backendSprayHasDrawn) {
        _recordBackendHistoryAction(
          layerId: _activeLayerId,
          deferPreview: true,
        );
        if (mounted) {
          setState(() {});
        }
      }
      _backendSprayActive = false;
      _backendSprayHasDrawn = false;
    }
    setState(() {
      _isSpraying = false;
    });
    _sprayBoardPosition = null;
    _kritaSprayEngine = null;
    _activeSprayColor = null;
    _sprayTickerTimestamp = null;
    _sprayEmissionAccumulator = 0.0;
    _softSprayLastPoint = null;
    _softSprayResidual = 0.0;
  }
}
