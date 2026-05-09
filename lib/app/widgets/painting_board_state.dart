part of 'painting_board.dart';

class PaintingBoardState extends _PaintingBoardBase
    with
        TickerProviderStateMixin,
        _PaintingBoardLayerTransformMixin,
        _PaintingBoardLayerMixin,
        _PaintingBoardColorMixin,
        _PaintingBoardPaletteMixin,
        _PaintingBoardReferenceMixin,
        _PaintingBoardReferenceModelMixin,
        _PaintingBoardPerspectiveMixin,
        _PaintingBoardTextMixin,
        _PaintingBoardSelectionMixin,
        _PaintingBoardShapeMixin,
        _PaintingBoardClipboardMixin,
        _PaintingBoardInteractionMixin,
        _PaintingBoardFilterMixin,
        _PaintingBoardBuildMixin {
  bool _perfStressRunning = false;
  bool _perfStressCancelRequested = false;
  bool _perfStressTimingsAttached = false;
  Ticker? _perfStressTicker;
  final ListQueue<int> _perfStressPendingBatchMicros = ListQueue<int>();
  final List<double> _perfStressLatencySamplesMs = <double>[];
  final List<double> _perfStressUiBuildSamplesMs = <double>[];
  int? _perfStressLastFrameGeneration;
  bool? _menuSelectAllEnabled;
  bool? _menuClearSelectionEnabled;
  bool? _menuInvertSelectionEnabled;
  bool? _menuCutEnabled;
  bool? _menuCopyEnabled;
  bool? _menuPasteEnabled;
  bool? _menuMergeDownEnabled;
  StreamSubscription<TabletHoverSample>? _tabletHoverSubscription;

  int _layerSignature(CanvasLayerData layer) {
    return layer.id.hashCode;
  }

  int _layersSignature(List<CanvasLayerData>? layers) {
    if (layers == null || layers.isEmpty) {
      return 0;
    }
    final List<String> ids = <String>[
      for (final CanvasLayerData layer in layers) layer.id,
    ];
    ids.sort();
    int hash = 17;
    for (final String id in ids) {
      hash = 37 * hash + id.hashCode;
    }
    return hash;
  }

  bool _initialLayersEquivalent(
    List<CanvasLayerData>? a,
    List<CanvasLayerData>? b,
  ) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    if (a.length != b.length) {
      return false;
    }
    return _layersSignature(a) == _layersSignature(b);
  }

  @override
  void initState() {
    super.initState();
    _initializeCursorLocateOverlayAnimation();
    _viewInfoNotifier = ValueNotifier<CanvasViewInfo>(_buildViewInfo());
    initializeTextTool();
    initializeSelectionTicker(this);
    MobileBottomSheetController.activeCount.addListener(
      _handleMobileBottomSheetChanged,
    );
    _layerRenameFocusNode.addListener(_handleLayerRenameFocusChange);
    final AppPreferences prefs = AppPreferences.instance;
    _pixelGridVisible = prefs.pixelGridVisible;
    AppPreferences.pixelGridVisibleNotifier.addListener(
      _handlePixelGridPreferenceChanged,
    );
    _bucketSampleAllLayers = prefs.bucketSampleAllLayers;
    _bucketContiguous = prefs.bucketContiguous;
    _bucketSwallowColorLine = prefs.bucketSwallowColorLine;
    _bucketSwallowColorLineMode = prefs.bucketSwallowColorLineMode;
    _bucketTolerance = prefs.bucketTolerance;
    _bucketFillGap = prefs.bucketFillGap;
    _magicWandTolerance = prefs.magicWandTolerance;
    _brushToolsEraserMode = prefs.brushToolsEraserMode;
    _touchDrawingEnabled = prefs.touchDrawingEnabled;
    if (_kDebugPointerInput) {
      print(
        '[pointer] debug enabled platform=$defaultTargetPlatform '
        'touchDrawing=$_touchDrawingEnabled',
      );
    }
    _shapeFillEnabled = prefs.shapeToolFillEnabled;
    _layerAdjustCropOutside = prefs.layerAdjustCropOutside;
    _penStrokeSliderRange = prefs.penStrokeSliderRange;
    _sprayStrokeSliderRange = prefs.sprayStrokeSliderRange;
    _eraserStrokeSliderRange = prefs.eraserStrokeSliderRange;
    _penStrokeWidth = _penStrokeSliderRange.clamp(prefs.penStrokeWidth);
    _sprayStrokeWidth = _sprayStrokeSliderRange.clamp(prefs.sprayStrokeWidth);
    _eraserStrokeWidth = _eraserStrokeSliderRange.clamp(
      prefs.eraserStrokeWidth,
    );
    _sprayMode = prefs.sprayMode;
    _strokeStabilizerStrength = prefs.strokeStabilizerStrength;
    _streamlineStrength = prefs.streamlineStrength;
    _simulatePenPressure = prefs.simulatePenPressure;
    _penPressureProfile = prefs.penPressureProfile;
    _penAntialiasLevel = prefs.penAntialiasLevel.clamp(0, 9);
    _bucketAntialiasLevel = prefs.bucketAntialiasLevel.clamp(0, 9);
    _stylusPressureEnabled = prefs.stylusPressureEnabled;
    _stylusCurve = prefs.stylusPressureCurve;
    _autoSharpPeakEnabled = prefs.autoSharpPeakEnabled;
    _backendPressureSimulator.setSharpTipsEnabled(_autoSharpPeakEnabled);
    _brushShape = prefs.brushShape;
    _brushShapeId = _shapeIdForBrush(_brushShape);
    _brushRandomRotationEnabled = prefs.brushRandomRotationEnabled;
    _brushRandomRotationPreviewSeed = _brushRotationRandom.nextInt(1 << 31);
    _hollowStrokeEnabled = prefs.hollowStrokeEnabled;
    _hollowStrokeRatio = prefs.hollowStrokeRatio.clamp(0.0, 1.0);
    _hollowStrokeEraseOccludedParts = prefs.hollowStrokeEraseOccludedParts;
    _brushLibrary = BrushLibrary.instance;
    _brushLibrary!.addListener(_handleBrushLibraryChanged);
    _colorLineColor = prefs.colorLineColor;
    _primaryColor = prefs.primaryColor;
    _primaryHsv = HSVColor.fromColor(_primaryColor);
    _floatingColorPanelHeight = prefs.floatingColorPanelHeight;
    _sai2ColorPanelHeight = prefs.sai2ColorPanelHeight;
    _sai2ToolSectionRatio = prefs.sai2ToolPanelSplit.clamp(0.0, 1.0);
    _sai2LayerPanelWidthRatio = prefs.sai2LayerPanelWidthSplit.clamp(0.0, 1.0);
    _rememberColor(widget.settings.backgroundColor);
    _rememberColor(_primaryColor);
    initializePerspectiveGuide(widget.initialPerspectiveGuide);
    final List<CanvasLayerData> layers = _buildInitialLayers();
    final bool useBackendCanvas = _backend.isSupported;
    final bool enableRasterOutput = true;
    final CanvasBackend rasterBackend = CanvasBackendState.resolveRasterBackend(
      useBackendCanvas: useBackendCanvas,
    );
    if (kDebugMode) {
      debugPrint(
        '[canvas-backend] pref=${AppPreferences.instance.canvasBackend} '
        'state=${CanvasBackendState.backend} '
        'backendSupported=${_backend.isSupported} '
        'useBackendCanvas=$useBackendCanvas rasterBackend=$rasterBackend '
        'rasterOutput=$enableRasterOutput',
      );
    }
    _controller = createCanvasFacade(
      width: widget.settings.width.round(),
      height: widget.settings.height.round(),
      backgroundColor: widget.settings.backgroundColor,
      initialLayers: layers,
      creationLogic: widget.settings.creationLogic,
      enableRasterOutput: enableRasterOutput,
      backend: rasterBackend,
    );
    _controller.setLayerOverflowCropping(_layerAdjustCropOutside);
    if (_brushLibrary != null) {
      _applyBrushPreset(_brushLibrary!.selectedPreset, notify: false);
    }
    _applyStylusSettingsToController();
    _controller.addListener(_handleControllerChanged);
    _boardReadyNotified = _controller.frame != null;
    if (_boardReadyNotified) {
      widget.onReadyChanged?.call(true);
    }
    _resetHistory();
    _syncRasterizeMenuAvailability();
    _syncMenuAvailability();
    _notifyViewInfoChanged();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _pencilDoubleTapSubscription = TabletInputBridge
          .instance
          .pencilDoubleTapEvents
          .listen((_) {
            _handleApplePencilDoubleTap();
          });
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _tabletHoverSubscription = TabletInputBridge.instance.hoverEvents.listen(
        _handleTabletHover,
      );
    }
    BackendCanvasTimeline.mark(
      'paintingBoard: initState '
      'size=${widget.settings.width.round()}x${widget.settings.height.round()}',
    );
  }

  @override
  void dispose() {
    _perfStressCancelRequested = true;
    final Ticker? ticker = _perfStressTicker;
    if (ticker != null) {
      ticker.stop();
      ticker.dispose();
      _perfStressTicker = null;
    }
    if (_perfStressTimingsAttached) {
      SchedulerBinding.instance.removeTimingsCallback(_perfStressOnTimings);
      _perfStressTimingsAttached = false;
    }
    _perfStressPendingBatchMicros.clear();
    _perfStressLatencySamplesMs.clear();
    _perfStressUiBuildSamplesMs.clear();
    disposeTextTool();
    _removeFilterOverlay(restoreOriginal: false);
    _disposeReferenceCards();
    _disposeReferenceModelCards();
    disposeSelectionTicker();
    _controller.removeListener(_handleControllerChanged);
    unawaited(_controller.disposeController());
    _layerOpacityPreviewReset(this);
    _disposeLayerPreviewCache();
    _layerScrollController.dispose();
    _layerContextMenuController.dispose();
    _blendModeFlyoutController.dispose();
    _layerRenameFocusNode.removeListener(_handleLayerRenameFocusChange);
    _layerRenameController.dispose();
    _layerRenameFocusNode.dispose();
    _pendingLayoutTask = null;
    unawaited(_layoutWorker?.dispose());
    _focusNode.dispose();
    _sprayTicker?.dispose();
    _viewInfoNotifier.dispose();
    AppPreferences.pixelGridVisibleNotifier.removeListener(
      _handlePixelGridPreferenceChanged,
    );
    _brushLibrary?.removeListener(_handleBrushLibraryChanged);
    _curvePreviewRasterImage?.dispose();
    _curvePreviewRasterImage = null;
    _shapePreviewRasterImage?.dispose();
    _shapePreviewRasterImage = null;
    _restoreBackendLayerAfterVectorPreview();
    _backendLayerSnapshots.clear();
    _backendLayerSnapshotHandle = null;
    _pencilDoubleTapSubscription?.cancel();
    _pencilDoubleTapSubscription = null;
    _tabletHoverSubscription?.cancel();
    _tabletHoverSubscription = null;
    _disposeCursorLocateOverlayAnimation();
    MobileBottomSheetController.activeCount.removeListener(
      _handleMobileBottomSheetChanged,
    );
    super.dispose();
  }

  void _handleTabletHover(TabletHoverSample sample) {
    if (!mounted) {
      return;
    }
    if (!sample.inRange) {
      _clearToolCursorOverlay();
      return;
    }
    if (sample.inContact) {
      return;
    }
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final Offset local = box.globalToLocal(sample.position);
    _recordWorkspacePointer(local);
    _updateToolCursorOverlay(local, pointerKind: PointerDeviceKind.stylus);
    _updatePerspectiveHover(_toBoardLocal(local));
  }

  void _handleMobileBottomSheetChanged() {
    if (!mounted) {
      return;
    }
    _scheduleWorkspaceCardsOverlaySync();
  }

  void _perfStressOnTimings(List<ui.FrameTiming> timings) {
    if (!_perfStressRunning) {
      return;
    }
    for (final ui.FrameTiming timing in timings) {
      final double buildMs = timing.buildDuration.inMicroseconds / 1000.0;
      if (!buildMs.isFinite || buildMs < 0) {
        continue;
      }
      _perfStressUiBuildSamplesMs.add(buildMs);
    }
  }

  void _perfStressMaybeRecordFrame(CanvasFrame? frame) {
    if (!_perfStressRunning) {
      return;
    }
    if (frame == null) {
      return;
    }
    final int generation = frame.generation;
    final int? lastGeneration = _perfStressLastFrameGeneration;
    if (lastGeneration != null && lastGeneration == generation) {
      return;
    }
    _perfStressLastFrameGeneration = generation;
    if (_perfStressPendingBatchMicros.isEmpty) {
      return;
    }
    final int startMicros = _perfStressPendingBatchMicros.removeFirst();
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    final double elapsedMs = (nowMicros - startMicros) / 1000.0;
    if (elapsedMs.isNaN || elapsedMs.isInfinite || elapsedMs < 0) {
      return;
    }
    _perfStressLatencySamplesMs.add(elapsedMs);
  }

  Future<CanvasPerfStressReport> runCanvasPerfStressTest({
    Duration duration = const Duration(seconds: 10),
    int targetPointsPerSecond = 1000,
  }) async {
    if (_perfStressRunning) {
      throw StateError('Perf stress test already running.');
    }
    if (!isBoardReady) {
      throw StateError('Board not ready.');
    }
    if (!_backend.supportsInputQueue || _backendCanvasEngineHandle == null) {
      throw StateError('Perf stress test requires the Rust/WGPU canvas backend.');
    }

    _perfStressCancelRequested = false;
    _perfStressRunning = true;
    _perfStressPendingBatchMicros.clear();
    _perfStressLatencySamplesMs.clear();
    _perfStressUiBuildSamplesMs.clear();
    _perfStressLastFrameGeneration = _controller.frame?.generation;

    if (!_perfStressTimingsAttached) {
      SchedulerBinding.instance.addTimingsCallback(_perfStressOnTimings);
      _perfStressTimingsAttached = true;
    }

    final int width = widget.settings.width.round();
    final int height = widget.settings.height.round();
    final int layerCount = _layers.length;

    final List<String> editableLayers = <String>[
      for (int i = _layers.length - 1; i >= 0; i--)
        if (!_layers[i].locked) _layers[i].id,
    ];
    if (editableLayers.isEmpty) {
      throw StateError('No editable layers for perf stress test.');
    }

    final double w = width.toDouble();
    final double h = height.toDouble();
    const double margin = 8.0;
    final double cx = w / 2.0;
    final double cy = h / 2.0;
    final double ampX = math.max(1.0, cx - margin);
    final double ampY = math.max(1.0, cy - margin);

    final Stopwatch stopwatch = Stopwatch()..start();
    Duration actualDuration = Duration.zero;
    final Completer<void> done = Completer<void>();
    int pointsGenerated = 0;
    Duration lastElapsed = Duration.zero;
    final double startTimestampMs =
        DateTime.now().microsecondsSinceEpoch / 1000.0;

    void stopTicker() {
      final Ticker? ticker = _perfStressTicker;
      if (ticker == null) {
        return;
      }
      ticker.stop();
      ticker.dispose();
      _perfStressTicker = null;
    }

    try {
      _controller.setActiveLayer(editableLayers.first);
      _backend.setBackendActiveLayerById(editableLayers.first);

      double backlog = 0.0;
      const int maxPointsPerFrame = 96;

      _perfStressTicker = createTicker((elapsed) {
        if (_perfStressCancelRequested) {
          if (!done.isCompleted) {
            done.complete();
          }
          return;
        }
        if (elapsed >= duration) {
          if (!done.isCompleted) {
            done.complete();
          }
          return;
        }

        final Duration delta = elapsed - lastElapsed;
        lastElapsed = elapsed;
        final double dtSeconds = delta.inMicroseconds / 1e6;
        if (!dtSeconds.isFinite || dtSeconds <= 0) {
          return;
        }

        backlog += dtSeconds * targetPointsPerSecond;
        int pointsThisFrame = backlog.floor();
        backlog -= pointsThisFrame;
        if (pointsThisFrame <= 0) {
          return;
        }
        if (pointsThisFrame > maxPointsPerFrame) {
          pointsThisFrame = maxPointsPerFrame;
          backlog = 0.0;
        }

        final int batchStartMicros = DateTime.now().microsecondsSinceEpoch;
        final _BackendPointBuffer buffer = _BackendPointBuffer(
          initialCapacityPoints: math.max(2, pointsThisFrame),
        );

        final double elapsedSeconds = elapsed.inMicroseconds / 1e6;
        final double perPointDt = dtSeconds / pointsThisFrame;
        Offset? lastEnginePoint;
        int? lastTimestampUs;
        for (int i = 0; i < pointsThisFrame; i++) {
          final double t = elapsedSeconds + (i * perPointDt);
          double x =
              cx +
              ampX * math.sin(t * math.pi * 2.0 * 0.97) +
              ampX * 0.08 * math.sin(t * math.pi * 2.0 * 7.3);
          double y =
              cy +
              ampY * math.sin(t * math.pi * 2.0 * 1.31 + 1.0) +
              ampY * 0.08 * math.sin(t * math.pi * 2.0 * 6.1);
          x = x.clamp(0.0, w);
          y = y.clamp(0.0, h);
          final double timestampMs =
              startTimestampMs + (elapsed.inMicroseconds / 1000.0);
          final Offset enginePoint = _backendToEngineSpace(Offset(x, y));
          final int timestampUs = (timestampMs * 1000.0).round();
          lastEnginePoint = enginePoint;
          lastTimestampUs = timestampUs;
          final int flags = i == 0
              ? _kBackendPointFlagDown
              : (i == pointsThisFrame - 1
                    ? _kBackendPointFlagUp
                    : _kBackendPointFlagMove);
          buffer.add(
            x: enginePoint.dx,
            y: enginePoint.dy,
            pressure: 1.0,
            timestampUs: timestampUs,
            flags: flags,
            pointerId: 0,
          );
          pointsGenerated++;
        }
        if (pointsThisFrame == 1 && lastEnginePoint != null) {
          buffer.add(
            x: lastEnginePoint.dx,
            y: lastEnginePoint.dy,
            pressure: 1.0,
            timestampUs: (lastTimestampUs ?? 0) + 1000,
            flags: _kBackendPointFlagUp,
            pointerId: 0,
          );
        }
        final bool pushed = _backend.pushPointsPacked(
          bytes: buffer.bytes,
          pointCount: buffer.length,
        );
        if (pushed) {
          final int nowMicros = DateTime.now().microsecondsSinceEpoch;
          _perfStressLatencySamplesMs.add(
            (nowMicros - batchStartMicros) / 1000.0,
          );
          _markDirty();
        }
      });
      _perfStressTicker!.start();
      await done.future;
      stopwatch.stop();
      actualDuration = stopwatch.elapsed;
    } finally {
      if (stopwatch.isRunning) {
        stopwatch.stop();
        actualDuration = stopwatch.elapsed;
      }
      stopTicker();

      if (_perfStressTimingsAttached) {
        SchedulerBinding.instance.removeTimingsCallback(_perfStressOnTimings);
        _perfStressTimingsAttached = false;
      }
      _perfStressRunning = false;
    }

    final double seconds = actualDuration.inMicroseconds / 1e6;
    final double pps = seconds <= 0 ? 0 : pointsGenerated / seconds;

    final double latencyP50 = percentileMs(_perfStressLatencySamplesMs, 0.50);
    final double latencyP95 = percentileMs(_perfStressLatencySamplesMs, 0.95);
    final double uiBuildP95 = percentileMs(_perfStressUiBuildSamplesMs, 0.95);

    final CanvasPerfStressReport report = CanvasPerfStressReport(
      canvasWidth: width,
      canvasHeight: height,
      layerCount: layerCount,
      duration: actualDuration,
      pointsGenerated: pointsGenerated,
      pointsPerSecond: pps,
      presentLatencySampleCount: _perfStressLatencySamplesMs.length,
      presentLatencyP50Ms: latencyP50,
      presentLatencyP95Ms: latencyP95,
      uiBuildSampleCount: _perfStressUiBuildSamplesMs.length,
      uiBuildP95Ms: uiBuildP95,
    );
    debugPrint(report.toLogString());
    return report;
  }

  void addLayerAboveActiveLayer() {
    _handleAddLayer();
  }

  @override
  Future<bool> insertImageLayerFromBytes(
    Uint8List bytes, {
    String? name,
    int? svgRasterSizePx,
  }) async {
    if (!isBoardReady) {
      return false;
    }
    try {
      final bool backendSynced = _backend.isReady;
      if (!await _backend.syncAllLayerPixelsFromBackend(
        waitForPending: true,
        warnIfFailed: true,
      )) {
        return false;
      }
      final _ImportedImageData decoded = await _decodeExternalImage(
        bytes,
        svgRasterSizePx: svgRasterSizePx,
      );
      final int canvasWidth = widget.settings.width.round();
      final int canvasHeight = widget.settings.height.round();
      final int offsetX = ((canvasWidth - decoded.width) / 2).floor();
      final int offsetY = ((canvasHeight - decoded.height) / 2).floor();
      final String resolvedName = _normalizeImportedLayerName(name);
      final CanvasLayerData layerData = CanvasLayerData(
        id: generateLayerId(),
        name: resolvedName,
        bitmap: decoded.bytes,
        bitmapWidth: decoded.width,
        bitmapHeight: decoded.height,
        bitmapLeft: offsetX,
        bitmapTop: offsetY,
        cloneBitmap: false,
      );
      await _pushUndoSnapshot(backendPixelsSynced: backendSynced);
      _controller.insertLayerFromData(layerData, aboveLayerId: _activeLayerId);
      _controller.setActiveLayer(layerData.id);
      if (backendSynced) {
        _syncBackendCanvasLayersToEngine();
        await _backend.syncAllLayerPixelsToBackend(warnIfFailed: true);
      }
      setState(() {});
      _markDirty();
      return true;
    } catch (error, stackTrace) {
      debugPrint('Failed to insert image layer: $error\n$stackTrace');
      return false;
    }
  }

  String _normalizeImportedLayerName(String? raw) {
    final String? trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '导入图层';
    }
    return trimmed;
  }

  Future<_ImportedImageData> _decodeExternalImage(
    Uint8List bytes, {
    int? svgRasterSizePx,
  }) async {
    final DecodedUiImageFrame decodedFrame = await decodeBitmapOrSvgFrame(
      bytes,
      svgRasterSizePx: svgRasterSizePx,
    );
    final ui.Image image = decodedFrame.image;
    final ByteData? pixelData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (pixelData == null) {
      image.dispose();
      throw StateError('无法读取位图像素数据');
    }
    final Uint8List rgba = Uint8List.fromList(
      pixelData.buffer.asUint8List(
        pixelData.offsetInBytes,
        pixelData.lengthInBytes,
      ),
    );
    unpremultiplyRgbaInPlace(rgba);
    final _ImportedImageData result = _ImportedImageData(
      width: image.width,
      height: image.height,
      bytes: rgba,
    );
    image.dispose();
    return result;
  }

  void mergeActiveLayerDown() {
    final String? activeLayerId = _activeLayerId;
    if (activeLayerId == null) {
      return;
    }
    final CanvasLayerInfo? layer = _layerById(activeLayerId);
    if (layer == null) {
      return;
    }
    _handleMergeLayerDown(layer);
  }

  Future<void> binarizeActiveLayer() async {
    if (!isBoardReady) {
      _showBinarizeMessage('画布尚未准备好，无法二值化。');
      return;
    }
    final String? activeLayerId = _activeLayerId;
    if (activeLayerId == null) {
      _showBinarizeMessage('请先选择一个可编辑的图层。');
      return;
    }
    final CanvasLayerInfo? layer = _layerById(activeLayerId);
    if (layer == null) {
      _showBinarizeMessage('无法定位当前图层。');
      return;
    }
    if (layer.locked) {
      _showBinarizeMessage('当前图层已锁定，无法二值化。');
      return;
    }
    if (layer.text != null) {
      _showBinarizeMessage('当前图层是文字图层，请先栅格化或切换其他图层。');
      return;
    }

    await _controller.waitForPendingWorkerTasks();
    final List<CanvasLayerData> snapshot = _controller.snapshotLayers();
    final int index = snapshot.indexWhere((item) => item.id == activeLayerId);
    if (index < 0) {
      _showBinarizeMessage('无法定位当前图层。');
      return;
    }
    final CanvasLayerData data = snapshot[index];
    Uint8List? bitmap = data.bitmap != null
        ? Uint8List.fromList(data.bitmap!)
        : null;
    Color? fillColor = data.fillColor;
    if (bitmap == null && fillColor == null) {
      _showBinarizeMessage('当前图层为空，无法二值化。');
      return;
    }

    const int alphaThreshold = 128;
    bool bitmapModified = false;
    bool bitmapHasCoverage = false;
    if (bitmap != null) {
      for (int i = 0; i < bitmap.length; i += 4) {
        final int alpha = bitmap[i + 3];
        if (alpha == 0) {
          continue;
        }
        if (alpha >= alphaThreshold) {
          if (alpha != 255) {
            bitmap[i + 3] = 255;
            bitmapModified = true;
          }
          bitmapHasCoverage = true;
          continue;
        }
        if (bitmap[i] != 0 || bitmap[i + 1] != 0 || bitmap[i + 2] != 0) {
          bitmap[i] = 0;
          bitmap[i + 1] = 0;
          bitmap[i + 2] = 0;
        }
        if (alpha != 0) {
          bitmap[i + 3] = 0;
          bitmapModified = true;
        }
      }
      if (!bitmapHasCoverage) {
        bitmap = null;
        if (data.bitmap != null) {
          bitmapModified = true;
        }
      }
    }

    bool fillChanged = false;
    if (fillColor != null) {
      final int alpha = fillColor.alpha;
      if (alpha > 0 && alpha < 255) {
        final int nextAlpha = alpha >= alphaThreshold ? 255 : 0;
        if (nextAlpha != alpha) {
          fillColor = fillColor.withAlpha(nextAlpha);
          fillChanged = true;
        }
      }
    }

    if (!bitmapModified && !fillChanged) {
      _showBinarizeMessage('未检测到可处理的半透明像素。');
      return;
    }

    await _pushUndoSnapshot();
    final CanvasLayerData updated = CanvasLayerData(
      id: data.id,
      name: data.name,
      visible: data.visible,
      opacity: data.opacity,
      locked: data.locked,
      clippingMask: data.clippingMask,
      blendMode: data.blendMode,
      fillColor: fillColor,
      bitmap: bitmap,
      bitmapWidth: bitmap != null ? data.bitmapWidth : null,
      bitmapHeight: bitmap != null ? data.bitmapHeight : null,
      bitmapLeft: bitmap != null ? data.bitmapLeft : null,
      bitmapTop: bitmap != null ? data.bitmapTop : null,
      text: data.text,
      cloneBitmap: false,
    );
    _controller.replaceLayer(activeLayerId, updated);
    _controller.setActiveLayer(activeLayerId);
    setState(() {});
    _markDirty();
  }

  void _showBinarizeMessage(String message) {
    AppNotifications.show(
      context,
      message: message,
      severity: InfoBarSeverity.warning,
    );
  }

  void selectEntireCanvas() async {
    final int width = _controller.width;
    final int height = _controller.height;
    if (width <= 0 || height <= 0) {
      return;
    }
    final int length = width * height;
    final Uint8List mask = Uint8List(length)..fillRange(0, length, 1);
    final Path selectionPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    await _prepareSelectionUndo();
    setState(() {
      clearSelectionArtifacts();
      setSelectionState(path: selectionPath, mask: mask);
    });
    _updateSelectionAnimation();
    _finishSelectionUndo();
  }

  void clearSelection() {
    _clearSelection();
  }

  void invertSelection() async {
    final int width = _controller.width;
    final int height = _controller.height;
    if (width <= 0 || height <= 0) {
      return;
    }
    final int length = width * height;
    final Uint8List? currentMask = _selectionMask;
    final Uint8List inverted = Uint8List(length);
    if (currentMask == null) {
      inverted.fillRange(0, length, 1);
    } else {
      if (currentMask.length != length) {
        return;
      }
      for (int i = 0; i < length; i++) {
        inverted[i] = currentMask[i] == 0 ? 1 : 0;
      }
    }
    if (!_maskHasCoverage(inverted)) {
      await _prepareSelectionUndo();
      setState(() {
        clearSelectionArtifacts();
        setSelectionState(path: null, mask: null);
      });
      _updateSelectionAnimation();
      _finishSelectionUndo();
      return;
    }
    final Path? path = currentMask == null
        ? (Path()
            ..addRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble())))
        : _pathFromMask(inverted, width);
    await _prepareSelectionUndo();
    setState(() {
      clearSelectionArtifacts();
      setSelectionState(path: path, mask: inverted);
    });
    _updateSelectionAnimation();
    _finishSelectionUndo();
  }

  Future<CanvasResizeResult?> resizeImage(
    int width,
    int height,
    ImageResizeSampling sampling,
  ) async {
    if (width <= 0 || height <= 0) {
      debugPrint('resizeImage: invalid target=${width}x$height');
      return null;
    }
    _controller.commitActiveLayerTranslation();
    if (!await _backend.syncAllLayerPixelsFromBackend(
      waitForPending: true,
      warnIfFailed: true,
    )) {
      debugPrint('resizeImage: backend sync failed');
      return null;
    }
    final int sourceWidth = _controller.width;
    final int sourceHeight = _controller.height;
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      debugPrint('resizeImage: invalid source=${sourceWidth}x$sourceHeight');
      return null;
    }
    debugPrint(
      'resizeImage: source=${sourceWidth}x$sourceHeight '
      'target=${width}x$height sampling=$sampling '
      'backend=${_backend.isReady}',
    );
    final List<CanvasLayerData> layers = _controller.snapshotLayers();
    final List<CanvasLayerData> resizedLayers = <CanvasLayerData>[
      for (final CanvasLayerData layer in layers)
        _scaleLayerData(
          layer,
          sourceWidth,
          sourceHeight,
          width,
          height,
          sampling,
        ),
    ];
    return CanvasResizeResult(
      layers: resizedLayers,
      width: width,
      height: height,
    );
  }

  Future<CanvasResizeResult?> resizeCanvas(
    int width,
    int height,
    CanvasResizeAnchor anchor,
  ) async {
    if (width <= 0 || height <= 0) {
      debugPrint('resizeCanvas: invalid target=${width}x$height');
      return null;
    }
    _controller.commitActiveLayerTranslation();
    if (!await _backend.syncAllLayerPixelsFromBackend(
      waitForPending: true,
      warnIfFailed: true,
    )) {
      debugPrint('resizeCanvas: backend sync failed');
      return null;
    }
    final int sourceWidth = _controller.width;
    final int sourceHeight = _controller.height;
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      debugPrint('resizeCanvas: invalid source=${sourceWidth}x$sourceHeight');
      return null;
    }
    debugPrint(
      'resizeCanvas: source=${sourceWidth}x$sourceHeight '
      'target=${width}x$height anchor=$anchor '
      'backend=${_backend.isReady}',
    );
    final List<CanvasLayerData> layers = _controller.snapshotLayers();
    final List<CanvasLayerData> resizedLayers = <CanvasLayerData>[
      for (final CanvasLayerData layer in layers)
        _reframeLayerData(
          layer,
          sourceWidth,
          sourceHeight,
          width,
          height,
          anchor,
        ),
    ];
    return CanvasResizeResult(
      layers: resizedLayers,
      width: width,
      height: height,
    );
  }

  @override
  void didUpdateWidget(covariant PaintingBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      unawaited(_captureBackendLayerSnapshotIfNeeded());
    } else if (!oldWidget.isActive && widget.isActive) {
      _restoreBackendLayerSnapshotIfNeeded();
      _requestWorkspaceFocus();
    }
    final bool sizeChanged = widget.settings.size != oldWidget.settings.size;
    final bool backgroundChanged =
        widget.settings.backgroundColor != oldWidget.settings.backgroundColor;
    final bool logicChanged =
        widget.settings.creationLogic != oldWidget.settings.creationLogic;
    final bool layersChanged = !_initialLayersEquivalent(
      widget.initialLayers,
      oldWidget.initialLayers,
    );
    final int oldLayersSig = _layersSignature(oldWidget.initialLayers);
    final int newLayersSig = _layersSignature(widget.initialLayers);
    final bool shouldRecreate =
        sizeChanged || backgroundChanged || logicChanged;
    if (shouldRecreate) {
      debugPrint(
        'paintingBoard: recreate controller surfaceKey=${widget.surfaceKey} '
        'sizeChanged=$sizeChanged backgroundChanged=$backgroundChanged '
        'logicChanged=$logicChanged layersChanged=$layersChanged '
        'old=${oldWidget.settings.width.round()}x${oldWidget.settings.height.round()} '
        'new=${widget.settings.width.round()}x${widget.settings.height.round()} '
        'oldLayers=${oldWidget.initialLayers?.length ?? 0} '
        'newLayers=${widget.initialLayers?.length ?? 0} '
        'oldSig=$oldLayersSig newSig=$newLayersSig '
        'backendSupported=${_backend.isSupported}',
      );
      if (sizeChanged) {
        debugPrint(
          'paintingBoard: size changed '
          'old=${oldWidget.settings.width}x${oldWidget.settings.height} '
          'new=${widget.settings.width}x${widget.settings.height}',
        );
      }
      _controller.removeListener(_handleControllerChanged);
      unawaited(_controller.disposeController());
      final bool useBackendCanvas = _backend.isSupported;
      final bool enableRasterOutput = !useBackendCanvas;
      final CanvasBackend rasterBackend =
          CanvasBackendState.resolveRasterBackend(
            useBackendCanvas: useBackendCanvas,
          );
      _controller = createCanvasFacade(
        width: widget.settings.width.round(),
        height: widget.settings.height.round(),
        backgroundColor: widget.settings.backgroundColor,
        initialLayers: _buildInitialLayers(),
        creationLogic: widget.settings.creationLogic,
        enableRasterOutput: enableRasterOutput,
        backend: rasterBackend,
      );
      _applyStylusSettingsToController();
      _controller.addListener(_handleControllerChanged);
      _boardReadyNotified = _controller.frame != null;
      if (_boardReadyNotified) {
        widget.onReadyChanged?.call(true);
      }
      _resetHistory();
      _backendLayerSnapshots.clear();
      _backendLayerSnapshotDirty = false;
      _backendLayerSnapshotPendingRestore = false;
      _backendLayerSnapshotInFlight = false;
      _backendLayerSnapshotWidth = 0;
      _backendLayerSnapshotHeight = 0;
      _backendLayerSnapshotHandle = null;
      setState(() {
        if (sizeChanged) {
          _viewport.reset();
          _workspaceSize = Size.zero;
          _layoutBaseOffset = Offset.zero;
          _viewportInitialized = false;
        }
      });
      _notifyViewInfoChanged();
      _syncBackendCanvasLayersToEngine();
    }
    if (!shouldRecreate && layersChanged) {
      debugPrint(
        'paintingBoard: initialLayers changed (ignored) '
        'surfaceKey=${widget.surfaceKey} '
        'oldSig=$oldLayersSig newSig=$newLayersSig '
        'oldLayers=${oldWidget.initialLayers?.length ?? 0} '
        'newLayers=${widget.initialLayers?.length ?? 0}',
      );
    }
  }

  void _requestWorkspaceFocus() {
    if (!mounted || !widget.isActive || _isTextEditingActive) {
      return;
    }
    if (_focusNode.hasFocus) {
      return;
    }
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    final bool safeToRequest =
        phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks;
    if (safeToRequest) {
      _focusNode.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive || _isTextEditingActive) {
        return;
      }
      _focusNode.requestFocus();
    });
  }

  void _handleControllerChanged() {
    final CanvasFrame? frame = _controller.frame;
    _perfStressMaybeRecordFrame(frame);
    final int? awaitedGeneration = _layerOpacityPreviewAwaitedGeneration;
    if (awaitedGeneration != null &&
        frame != null &&
        frame.generation != awaitedGeneration) {
      if (_layerOpacityGestureActive) {
        _layerOpacityPreviewAwaitedGeneration = null;
      } else {
        _layerOpacityPreviewDeactivate(this, notifyListeners: true);
      }
    }
    _handleFilterApplyFrameProgress(frame);
    if (_maybeInitializeLayerTransformStateFromController()) {
      _scheduleReferenceModelTextureRefresh();
      _syncBackendCanvasLayersToEngine();
      return;
    }
    _syncRasterizeMenuAvailability();
    _syncMenuAvailability();
    _notifyBoardReadyIfNeeded();
    _scheduleReferenceModelTextureRefresh();
    _syncBackendCanvasLayersToEngine();
  }

  @override
  void _syncMenuAvailability() {
    final bool canSelectAll = this.canSelectAll;
    final bool canClearSelection = this.canClearSelection;
    final bool canInvertSelection = this.canInvertSelection;
    final bool canCut = this.canCut;
    final bool canCopy = this.canCopy;
    final bool canPaste = this.canPaste;
    final bool canMergeDown = canMergeActiveLayerDown;
    bool changed = false;
    if (_menuSelectAllEnabled != canSelectAll) {
      _menuSelectAllEnabled = canSelectAll;
      changed = true;
    }
    if (_menuClearSelectionEnabled != canClearSelection) {
      _menuClearSelectionEnabled = canClearSelection;
      changed = true;
    }
    if (_menuInvertSelectionEnabled != canInvertSelection) {
      _menuInvertSelectionEnabled = canInvertSelection;
      changed = true;
    }
    if (_menuCutEnabled != canCut) {
      _menuCutEnabled = canCut;
      changed = true;
    }
    if (_menuCopyEnabled != canCopy) {
      _menuCopyEnabled = canCopy;
      changed = true;
    }
    if (_menuPasteEnabled != canPaste) {
      _menuPasteEnabled = canPaste;
      changed = true;
    }
    if (_menuMergeDownEnabled != canMergeDown) {
      _menuMergeDownEnabled = canMergeDown;
      changed = true;
    }
    if (changed) {
      MenuActionDispatcher.instance.refresh();
    }
  }

  @override
  void _notifyBoardReadyIfNeeded() {
    if (_boardReadyNotified) {
      return;
    }
    final CanvasFrame? frame = _controller.frame;
    if (frame == null) {
      if (_backendCanvasEngineHandle == null) {
        return;
      }
      BackendCanvasTimeline.mark(
        'paintingBoard: board ready backendEngine=${_backendCanvasEngineHandle}',
      );
    } else {
      BackendCanvasTimeline.mark(
        'paintingBoard: board ready generation=${frame.generation}',
      );
    }
    _boardReadyNotified = true;
    widget.onReadyChanged?.call(true);
    _syncMenuAvailability();
  }

  WorkspaceOverlaySnapshot buildWorkspaceOverlaySnapshot() {
    return WorkspaceOverlaySnapshot(
      paletteCards: buildPaletteSnapshots(),
      referenceCards: buildReferenceSnapshots(),
    );
  }

  Future<void> restoreWorkspaceOverlaySnapshot(
    WorkspaceOverlaySnapshot snapshot,
  ) async {
    restorePaletteSnapshots(snapshot.paletteCards);
    await restoreReferenceSnapshots(snapshot.referenceCards);
  }

  ToolSettingsSnapshot buildToolSettingsSnapshot() {
    return ToolSettingsSnapshot(
      activeTool: _activeTool,
      primaryColor: _primaryColor.value,
      recentColors: _recentColors
          .map((color) => color.value)
          .toList(growable: false),
      colorLineColor: _colorLineColor.value,
      penStrokeWidth: _penStrokeWidth,
      sprayStrokeWidth: _sprayStrokeWidth,
      eraserStrokeWidth: _eraserStrokeWidth,
      sprayMode: _sprayMode,
      penStrokeSliderRange: _penStrokeSliderRange,
      sprayStrokeSliderRange: _sprayStrokeSliderRange,
      eraserStrokeSliderRange: _eraserStrokeSliderRange,
      brushPresetId:
          _activeBrushPreset?.id ?? _brushLibrary?.selectedId ?? 'pencil',
      strokeStabilizerStrength: _strokeStabilizerStrength,
      streamlineStrength: _streamlineStrength,
      stylusPressureEnabled: _stylusPressureEnabled,
      simulatePenPressure: _simulatePenPressure,
      penPressureProfile: _penPressureProfile,
      bucketAntialiasLevel: _bucketAntialiasLevel,
      bucketSampleAllLayers: _bucketSampleAllLayers,
      bucketContiguous: _bucketContiguous,
      bucketSwallowColorLine: _bucketSwallowColorLine,
      bucketSwallowColorLineMode: _bucketSwallowColorLineMode,
      bucketTolerance: _bucketTolerance,
      bucketFillGap: _bucketFillGap,
      magicWandTolerance: _magicWandTolerance,
      brushToolsEraserMode: _brushToolsEraserMode,
      layerAdjustCropOutside: _layerAdjustCropOutside,
      shapeFillEnabled: _shapeFillEnabled,
      selectionShape: _selectionShape,
      selectionAdditiveEnabled: _selectionAdditiveEnabled,
      shapeToolVariant: _shapeToolVariant,
      textFontSize: _textFontSize,
      textLineHeight: _textLineHeight,
      textLetterSpacing: _textLetterSpacing,
      textFontFamily: _textFontFamily,
      textAlign: _textAlign,
      textOrientation: _textOrientation,
      textAntialias: _textAntialias,
      textStrokeEnabled: _textStrokeEnabled,
      textStrokeWidth: _textStrokeWidth,
    );
  }

  void applyToolSettingsSnapshot(ToolSettingsSnapshot snapshot) {
    _setActiveTool(snapshot.activeTool);
    _updateShapeToolVariant(snapshot.shapeToolVariant);
    _updateShapeFillEnabled(snapshot.shapeFillEnabled);
    _updateSelectionShape(snapshot.selectionShape);
    _updateSelectionAdditiveEnabled(snapshot.selectionAdditiveEnabled);
    _updateTextFontSize(snapshot.textFontSize);
    _updateTextLineHeight(snapshot.textLineHeight);
    _updateTextLetterSpacing(snapshot.textLetterSpacing);
    _updateTextFontFamily(snapshot.textFontFamily);
    _updateTextAlign(snapshot.textAlign);
    _updateTextOrientation(snapshot.textOrientation);
    _updateTextAntialias(snapshot.textAntialias);
    _updateTextStrokeEnabled(snapshot.textStrokeEnabled);
    _updateTextStrokeWidth(snapshot.textStrokeWidth);
    _updatePenStrokeWidth(snapshot.penStrokeWidth);
    _updateSprayStrokeWidth(snapshot.sprayStrokeWidth);
    _updateEraserStrokeWidth(snapshot.eraserStrokeWidth);
    _updateSprayMode(snapshot.sprayMode);
    _updatePenStrokeSliderRange(snapshot.penStrokeSliderRange);
    _updateSprayStrokeSliderRange(snapshot.sprayStrokeSliderRange);
    _updateEraserStrokeSliderRange(snapshot.eraserStrokeSliderRange);
    _selectBrushPreset(snapshot.brushPresetId);
    _updateStrokeStabilizerStrength(snapshot.strokeStabilizerStrength);
    _updateStreamlineStrength(snapshot.streamlineStrength);
    _updateStylusPressureEnabled(snapshot.stylusPressureEnabled);
    _updatePenPressureSimulation(snapshot.simulatePenPressure);
    _updatePenPressureProfile(snapshot.penPressureProfile);
    _updateBucketAntialiasLevel(snapshot.bucketAntialiasLevel);
    _updateBucketSampleAllLayers(snapshot.bucketSampleAllLayers);
    _updateBucketContiguous(snapshot.bucketContiguous);
    _updateBucketSwallowColorLine(snapshot.bucketSwallowColorLine);
    _updateBucketSwallowColorLineMode(snapshot.bucketSwallowColorLineMode);
    _updateBucketTolerance(snapshot.bucketTolerance);
    _updateBucketFillGap(snapshot.bucketFillGap);
    _updateMagicWandTolerance(snapshot.magicWandTolerance);
    _updateBrushToolsEraserMode(snapshot.brushToolsEraserMode);
    _updateLayerAdjustCropOutside(snapshot.layerAdjustCropOutside);
    _setPrimaryColor(Color(snapshot.primaryColor), remember: false);
    setState(() {
      _recentColors
        ..clear()
        ..addAll(snapshot.recentColors.map((value) => Color(value)));
    });
    final Color targetColorLine = Color(snapshot.colorLineColor);
    if (_colorLineColor.value != targetColorLine.value) {
      setState(() => _colorLineColor = targetColorLine);
    }
  }

  void _handleBrushLibraryChanged() {
    final BrushLibrary? library = _brushLibrary;
    if (library == null) {
      return;
    }
    _applyBrushPreset(library.selectedPreset);
  }

  void _selectBrushPreset(String id) {
    final BrushLibrary? library = _brushLibrary;
    if (library == null) {
      return;
    }
    if (library.selectedId == id) {
      _applyBrushPreset(library.selectedPreset);
      return;
    }
    library.selectPreset(id);
  }

  Future<void> _openBrushPresetPicker() async {
    final BrushLibrary? library = _brushLibrary;
    if (library == null) {
      return;
    }
    final String selectedId = _activeBrushPreset?.id ?? library.selectedId;
    final String? nextId = await showBrushPresetPickerDialog(
      context,
      library: library,
      selectedId: selectedId,
    );
    if (!mounted || nextId == null) {
      return;
    }
    _selectBrushPreset(nextId);
  }

  void _applyBrushPreset(BrushPreset preset, {bool notify = true}) {
    final BrushPreset sanitized = preset.sanitized();
    final bool presetChanged = _activeBrushPreset?.id != sanitized.id;
    final bool randomRotationChanged =
        _brushRandomRotationEnabled != sanitized.randomRotation;
    final bool autoSharpChanged =
        _autoSharpPeakEnabled != sanitized.autoSharpTaper;
    final void Function() update = () {
      _activeBrushPreset = sanitized;
      _brushShape = sanitized.shape;
      _brushShapeId = sanitized.resolvedShapeId;
      _brushRandomRotationEnabled = sanitized.randomRotation;
      _brushSmoothRotationEnabled = sanitized.smoothRotation;
      if (sanitized.randomRotation &&
          (randomRotationChanged || presetChanged)) {
        _brushRandomRotationPreviewSeed = _brushRotationRandom.nextInt(1 << 31);
      }
      _brushSpacing = sanitized.spacing;
      _brushHardness = sanitized.hardness;
      _brushFlow = sanitized.flow;
      _brushScatter = sanitized.scatter;
      _brushRotationJitter = sanitized.rotationJitter;
      _brushSnapToPixel = sanitized.snapToPixel;
      _brushScreentoneEnabled = sanitized.screentoneEnabled;
      _brushScreentoneSpacing = sanitized.screentoneSpacing;
      _brushScreentoneDotSize = sanitized.screentoneDotSize;
      _brushScreentoneRotation = sanitized.screentoneRotation;
      _brushScreentoneSoftness = sanitized.screentoneSoftness;
      _brushScreentoneShape = sanitized.screentoneShape;
      _penAntialiasLevel = sanitized.antialiasLevel;
      _hollowStrokeEnabled = sanitized.hollowEnabled;
      _hollowStrokeRatio = sanitized.hollowRatio;
      _hollowStrokeEraseOccludedParts = sanitized.hollowEraseOccludedParts;
      _autoSharpPeakEnabled = sanitized.autoSharpTaper;
    };
    if (notify) {
      setState(update);
    } else {
      update();
    }
    _syncCustomBrushShape(sanitized);
    if (autoSharpChanged) {
      _backendPressureSimulator.setSharpTipsEnabled(_autoSharpPeakEnabled);
      _applyStylusSettingsToController();
    }
  }

  void _syncCustomBrushShape(BrushPreset preset) {
    final BrushLibrary library = _brushLibrary ?? BrushLibrary.instance;
    final BrushShapeLibrary shapes = library.shapeLibrary;
    final String shapeId = preset.resolvedShapeId;
    final bool builtIn = shapes.isBuiltInId(shapeId);
    if (builtIn) {
      _brushShapeRaster = null;
      _syncBackendBrushMask(force: true);
      if (_controller is BitmapCanvasController) {
        (_controller as BitmapCanvasController).setCustomBrushShape(
          shapeId: shapeId,
          raster: null,
        );
      }
      return;
    }
    shapes.loadRaster(shapeId).then((BrushShapeRaster? raster) {
      if (!mounted) {
        return;
      }
      if (_brushShapeId != shapeId) {
        return;
      }
      setState(() {
        _brushShapeRaster = raster;
      });
      _syncBackendBrushMask(force: true);
      if (_controller is BitmapCanvasController) {
        (_controller as BitmapCanvasController).setCustomBrushShape(
          shapeId: shapeId,
          raster: raster,
        );
      }
    });
  }

  Future<bool> undo() {
    return _PaintingBoardInteractionPointerImpl(this).undo();
  }

  Future<bool> redo() {
    return _PaintingBoardInteractionPointerImpl(this).redo();
  }

  bool zoomIn() {
    return _PaintingBoardInteractionPointerImpl(this).zoomIn();
  }

  bool zoomOut() {
    return _PaintingBoardInteractionPointerImpl(this).zoomOut();
  }
}

class _CanvasHistoryEntry {
  const _CanvasHistoryEntry({
    required this.layers,
    required this.backgroundColor,
    required this.activeLayerId,
    required this.selectionShape,
    this.selectionMask,
    this.selectionPath,
    this.backendPixelsSynced = false,
  });

  final List<CanvasLayerData> layers;
  final Color backgroundColor;
  final String? activeLayerId;
  final SelectionShape selectionShape;
  final Uint8List? selectionMask;
  final Path? selectionPath;
  final bool backendPixelsSynced;
}

StrokePressureProfile _penPressureProfile = StrokePressureProfile.auto;

void _layerOpacityPreviewReset(
  _PaintingBoardBase board, {
  bool notifyListeners = false,
}) {
  final bool hadPreview =
      board._layerOpacityPreviewActive ||
      board._layerOpacityPreviewLayerId != null ||
      board._layerOpacityPreviewValue != null;
  board._layerOpacityPreviewActive = false;
  board._layerOpacityPreviewLayerId = null;
  board._layerOpacityPreviewValue = null;
  board._layerOpacityPreviewRequestId++;
  board._layerOpacityPreviewAwaitedGeneration = null;
  board._layerOpacityPreviewCapturedSignature = null;
  board._layerOpacityPreviewHasVisibleLowerLayers = false;
  _layerOpacityPreviewDisposeImages(board);
  if (notifyListeners && hadPreview && board.mounted) {
    board.setState(() {});
  }
}

void _layerOpacityPreviewDeactivate(
  _PaintingBoardBase board, {
  bool notifyListeners = false,
}) {
  final bool hadPreview =
      board._layerOpacityPreviewActive ||
      board._layerOpacityPreviewValue != null ||
      board._layerOpacityPreviewAwaitedGeneration != null;
  board._layerOpacityPreviewActive = false;
  board._layerOpacityPreviewValue = null;
  board._layerOpacityPreviewAwaitedGeneration = null;
  board._layerOpacityPreviewHasVisibleLowerLayers = false;
  if (notifyListeners && hadPreview && board.mounted) {
    board.setState(() {});
  }
}

void _layerOpacityPreviewDisposeImages(_PaintingBoardBase board) {
  board._layerOpacityPreviewBackground?.dispose();
  board._layerOpacityPreviewBackground = null;
  board._layerOpacityPreviewActiveLayerImage?.dispose();
  board._layerOpacityPreviewActiveLayerImage = null;
  board._layerOpacityPreviewForeground?.dispose();
  board._layerOpacityPreviewForeground = null;
}

int _layerOpacityPreviewSignature(Iterable<CanvasLayerInfo> layers) {
  int hash = layers.length;
  int index = 1;
  for (final CanvasLayerInfo layer in layers) {
    hash = 37 * hash + layer.revision;
    hash = 37 * hash + layer.id.hashCode;
    hash = 37 * hash + index;
    hash = 37 * hash + (layer.visible ? 1 : 0);
    hash = 37 * hash + (layer.clippingMask ? 1 : 0);
    hash = 37 * hash + layer.blendMode.index;
    hash = 37 * hash + (layer.opacity * 1000).round();
    index++;
  }
  return hash;
}
