part of 'painting_board.dart';

extension _PaintingBoardFilterPanelExtension on _PaintingBoardFilterMixin {
  void _openFilterPanel(_FilterPanelType type) async {
    final String? activeLayerId = _activeLayerId;
    final l10n = context.l10n;
    if (type == _FilterPanelType.scanPaperDrawing &&
        _controller.frame == null &&
        !_canUseRustCanvasEngine()) {
      _showFilterMessage(l10n.canvasNotReady);
      return;
    }
    if (activeLayerId == null) {
      _showFilterMessage(l10n.selectEditableLayerFirst);
      return;
    }
    _layerOpacityPreviewReset(this);
    final BitmapLayerState? layer = _layerById(activeLayerId);
    if (layer == null) {
      _showFilterMessage(l10n.cannotLocateLayer);
      return;
    }
    if (layer.locked) {
      _showFilterMessage(l10n.layerLockedNoFilter);
      return;
    }
    if (type == _FilterPanelType.binarize && layer.text != null) {
      _showFilterMessage(l10n.textLayerNoFilter);
      return;
    }
    if (type == _FilterPanelType.scanPaperDrawing) {
      await _controller.waitForPendingWorkerTasks();
    }
    final List<CanvasLayerData> snapshot = _controller.snapshotLayers();
    final int layerIndex = snapshot.indexWhere(
      (item) => item.id == activeLayerId,
    );
    if (layerIndex < 0) {
      _showFilterMessage(l10n.cannotLocateLayer);
      return;
    }
    if (type == _FilterPanelType.scanPaperDrawing) {
      final CanvasLayerData data = snapshot[layerIndex];
      final Uint8List? bitmap = data.bitmap;
      final bool hasBitmap =
          bitmap != null &&
          bitmap.isNotEmpty &&
          (data.bitmapWidth ?? 0) > 0 &&
          (data.bitmapHeight ?? 0) > 0;
      final bool hasFill =
          data.fillColor != null && data.fillColor!.alpha != 0;
      if (!hasBitmap && !hasFill && !_canUseRustCanvasEngine()) {
        _showFilterMessage(l10n.layerEmptyScanPaperDrawing);
        return;
      }
    }
    _removeFilterOverlay(restoreOriginal: false);

    _filterSession = _FilterSession(
      type: type,
      originalLayers: snapshot,
      activeLayerIndex: layerIndex,
      activeLayerId: activeLayerId,
    );
    _previewFilteredActiveLayerImage?.dispose();
    _previewFilteredActiveLayerImage = null;
    _previewFilteredImageType = null;
    _previewActiveLayerPixels = null;
    _previewHueSaturationUpdateScheduled = false;
    _previewHueSaturationUpdateInFlight = false;
    _previewHueSaturationUpdateToken++;
    _previewBlackWhiteUpdateScheduled = false;
    _previewBlackWhiteUpdateInFlight = false;
    _previewBlackWhiteUpdateToken++;
    _previewBinarizeUpdateScheduled = false;
    _previewBinarizeUpdateInFlight = false;
    _previewBinarizeUpdateToken++;

    if (_filterPanelOffset == Offset.zero) {
      final Offset workspaceOffset = _workspacePanelSpawnOffset(
        this,
        panelWidth: _kFilterPanelWidth,
        panelHeight: _kFilterPanelMinHeight,
      );
      _filterPanelOffset = _workspaceToOverlayOffset(this, workspaceOffset);
      _filterPanelOffsetIsOverlay = true;
    } else if (!_filterPanelOffsetIsOverlay) {
      _filterPanelOffset = _workspaceToOverlayOffset(this, _filterPanelOffset);
      _filterPanelOffsetIsOverlay = true;
    }

    // Initialize worker but don't use it for preview during drag
    if (type != _FilterPanelType.scanPaperDrawing) {
      _initializeFilterWorker();
    }

    // Generate GPU preview images
    setState(() => _filterLoading = true);
    try {
      await _generatePreviewImages();
    } catch (e) {
      debugPrint('Failed to generate preview images: $e');
    } finally {
      if (mounted) {
        setState(() => _filterLoading = false);
      }
    }

    _insertFilterOverlay();
  }

  Future<_LayerPreviewImages> _captureRustLayerPreviewImages(
    _FilterSession session,
  ) async {
    if (!_canUseRustCanvasEngine()) {
      return const _LayerPreviewImages();
    }
    final int? handle = _rustCanvasEngineHandle;
    if (handle == null) {
      return const _LayerPreviewImages();
    }
    final int? layerIndex = _rustCanvasLayerIndexForId(session.activeLayerId);
    if (layerIndex == null) {
      return const _LayerPreviewImages();
    }
    final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return const _LayerPreviewImages();
    }
    final Uint32List? sourcePixels = await CanvasEngineFfi.instance.readLayer(
      handle: handle,
      layerIndex: layerIndex,
      width: width,
      height: height,
    );
    if (sourcePixels == null || sourcePixels.length != width * height) {
      return const _LayerPreviewImages();
    }
    final Uint8List rgba = this._argbPixelsToRgba(sourcePixels);
    final ui.Image active = await _decodeImage(rgba, width, height);
    return _LayerPreviewImages(active: active);
  }

  Future<void> _generatePreviewImages() async {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    final bool useRustPreview = _shouldUseRustFilterPreview(session);
    final _LayerPreviewImages previews = useRustPreview
        ? await _captureRustLayerPreviewImages(session)
        : await _captureLayerPreviewImages(
            controller: _controller,
            layers: _layers.toList(),
            activeLayerId: session.activeLayerId,
          );
    _previewBackground?.dispose();
    _previewActiveLayerImage?.dispose();
    _previewForeground?.dispose();
    _previewBackground = previews.background;
    _previewActiveLayerImage = previews.active;
    _previewForeground = previews.foreground;
    _previewFilteredActiveLayerImage?.dispose();
    _previewFilteredActiveLayerImage = null;
    _previewFilteredImageType = null;
    _previewActiveLayerPixels = null;
    if (_previewActiveLayerImage != null) {
      await _prepareActiveLayerPreviewPixels();
    }
    _previewHueSaturationUpdateToken++;
    _previewHueSaturationUpdateScheduled = false;
    _previewHueSaturationUpdateInFlight = false;
    _previewBlackWhiteUpdateToken++;
    _previewBlackWhiteUpdateScheduled = false;
    _previewBlackWhiteUpdateInFlight = false;
    _previewBinarizeUpdateToken++;
    _previewBinarizeUpdateScheduled = false;
    _previewBinarizeUpdateInFlight = false;
    if (session.type == _FilterPanelType.hueSaturation) {
      _scheduleHueSaturationPreviewImageUpdate();
    } else if (session.type == _FilterPanelType.blackWhite ||
        session.type == _FilterPanelType.scanPaperDrawing) {
      _scheduleBlackWhitePreviewImageUpdate();
    } else if (session.type == _FilterPanelType.binarize) {
      _scheduleBinarizePreviewImageUpdate();
    }
    if (useRustPreview) {
      _enableRustFilterPreviewIfNeeded(session);
    } else {
      _restoreRustLayerAfterFilterPreview();
    }
  }

  Future<void> _prepareActiveLayerPreviewPixels() async {
    final ui.Image? image = _previewActiveLayerImage;
    if (image == null) {
      _previewActiveLayerPixels = null;
      return;
    }
    try {
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        _previewActiveLayerPixels = null;
        return;
      }
      _previewActiveLayerPixels = Uint8List.fromList(
        byteData.buffer.asUint8List(),
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to prepare preview pixels: $error');
      _previewActiveLayerPixels = null;
    }
  }

  void _scheduleHueSaturationPreviewImageUpdate() {
    if (_filterSession?.type != _FilterPanelType.hueSaturation) {
      return;
    }
    if (_previewActiveLayerPixels == null || _previewActiveLayerImage == null) {
      return;
    }
    _previewHueSaturationUpdateScheduled = true;
    if (!_previewHueSaturationUpdateInFlight) {
      unawaited(_runHueSaturationPreviewImageUpdate());
    }
  }

  Future<void> _runHueSaturationPreviewImageUpdate() async {
    if (_previewHueSaturationUpdateInFlight) {
      return;
    }
    _previewHueSaturationUpdateInFlight = true;
    while (_previewHueSaturationUpdateScheduled) {
      _previewHueSaturationUpdateScheduled = false;
      final _FilterSession? session = _filterSession;
      final ui.Image? baseImage = _previewActiveLayerImage;
      final Uint8List? source = _previewActiveLayerPixels;
      if (session == null ||
          session.type != _FilterPanelType.hueSaturation ||
          baseImage == null ||
          source == null) {
        break;
      }
      final _HueSaturationSettings settings = session.hueSaturation;
      final bool isIdentity =
          settings.hue == 0 &&
          settings.saturation == 0 &&
          settings.lightness == 0;
      if (isIdentity) {
        if (_previewFilteredActiveLayerImage != null) {
          setState(() {
            _previewFilteredActiveLayerImage?.dispose();
            _previewFilteredActiveLayerImage = null;
            _previewFilteredImageType = null;
          });
        }
        continue;
      }
      final int token = ++_previewHueSaturationUpdateToken;
      final List<Object?> args = <Object?>[
        source,
        settings.hue,
        settings.saturation,
        settings.lightness,
      ];
      Uint8List processed;
      try {
        processed = await _generateHueSaturationPreviewBytes(args);
      } catch (error, stackTrace) {
        debugPrint('Failed to compute hue preview: $error');
        break;
      }
      if (!mounted || token != _previewHueSaturationUpdateToken) {
        break;
      }
      final ui.Image image = await _decodeImage(
        processed,
        baseImage.width,
        baseImage.height,
      );
      if (!mounted || token != _previewHueSaturationUpdateToken) {
        image.dispose();
        break;
      }
      if (!mounted) {
        image.dispose();
        break;
      }
      setState(() {
        _previewFilteredActiveLayerImage?.dispose();
        _previewFilteredActiveLayerImage = image;
        _previewFilteredImageType = _FilterPanelType.hueSaturation;
      });
    }
    _previewHueSaturationUpdateInFlight = false;
    if (_previewHueSaturationUpdateScheduled) {
      unawaited(_runHueSaturationPreviewImageUpdate());
    }
  }

  void _scheduleBlackWhitePreviewImageUpdate() {
    final _FilterPanelType? type = _filterSession?.type;
    if (type != _FilterPanelType.blackWhite &&
        type != _FilterPanelType.scanPaperDrawing) {
      return;
    }
    if (_previewActiveLayerPixels == null || _previewActiveLayerImage == null) {
      return;
    }
    _previewBlackWhiteUpdateScheduled = true;
    if (!_previewBlackWhiteUpdateInFlight) {
      unawaited(_runBlackWhitePreviewImageUpdate());
    }
  }

  Future<void> _runBlackWhitePreviewImageUpdate() async {
    if (_previewBlackWhiteUpdateInFlight) {
      return;
    }
    _previewBlackWhiteUpdateInFlight = true;
    while (_previewBlackWhiteUpdateScheduled) {
      _previewBlackWhiteUpdateScheduled = false;
      final _FilterSession? session = _filterSession;
      final ui.Image? baseImage = _previewActiveLayerImage;
      final Uint8List? source = _previewActiveLayerPixels;
      if (session == null ||
          (session.type != _FilterPanelType.blackWhite &&
              session.type != _FilterPanelType.scanPaperDrawing) ||
          baseImage == null ||
          source == null) {
        break;
      }
      final _BlackWhiteSettings settings = session.blackWhite;
      final int token = ++_previewBlackWhiteUpdateToken;
      final List<Object?> args = <Object?>[
        source,
        settings.blackPoint,
        settings.whitePoint,
        settings.midTone,
      ];
      Uint8List processed;
      try {
        processed = session.type == _FilterPanelType.scanPaperDrawing
            ? await _generateScanPaperDrawingPreviewBytes(args)
            : await _generateBlackWhitePreviewBytes(args);
      } catch (error) {
        debugPrint(
          session.type == _FilterPanelType.scanPaperDrawing
              ? 'Failed to compute scan paper drawing preview: $error'
              : 'Failed to compute black & white preview: $error',
        );
        break;
      }
      if (!mounted || token != _previewBlackWhiteUpdateToken) {
        break;
      }
      final ui.Image image = await _decodeImage(
        processed,
        baseImage.width,
        baseImage.height,
      );
      if (!mounted || token != _previewBlackWhiteUpdateToken) {
        image.dispose();
        break;
      }
      setState(() {
        _previewFilteredActiveLayerImage?.dispose();
        _previewFilteredActiveLayerImage = image;
        _previewFilteredImageType = session.type;
      });
    }
    _previewBlackWhiteUpdateInFlight = false;
    if (_previewBlackWhiteUpdateScheduled) {
      unawaited(_runBlackWhitePreviewImageUpdate());
    }
  }

  void _scheduleBinarizePreviewImageUpdate() {
    if (_filterSession?.type != _FilterPanelType.binarize) {
      return;
    }
    if (_previewActiveLayerPixels == null || _previewActiveLayerImage == null) {
      return;
    }
    _previewBinarizeUpdateScheduled = true;
    if (!_previewBinarizeUpdateInFlight) {
      unawaited(_runBinarizePreviewImageUpdate());
    }
  }

  Future<void> _runBinarizePreviewImageUpdate() async {
    if (_previewBinarizeUpdateInFlight) {
      return;
    }
    _previewBinarizeUpdateInFlight = true;
    while (_previewBinarizeUpdateScheduled) {
      _previewBinarizeUpdateScheduled = false;
      final _FilterSession? session = _filterSession;
      final ui.Image? baseImage = _previewActiveLayerImage;
      final Uint8List? source = _previewActiveLayerPixels;
      if (session == null ||
          session.type != _FilterPanelType.binarize ||
          baseImage == null ||
          source == null) {
        break;
      }
      final double threshold = session.binarize.alphaThreshold;
      final int token = ++_previewBinarizeUpdateToken;
      final List<Object?> args = <Object?>[source, threshold];
      Uint8List processed;
      try {
        processed = await _generateBinarizePreviewBytes(args);
      } catch (error) {
        debugPrint('Failed to compute binarize preview: $error');
        break;
      }
      if (!mounted || token != _previewBinarizeUpdateToken) {
        break;
      }
      final ui.Image image = await _decodeImage(
        processed,
        baseImage.width,
        baseImage.height,
      );
      if (!mounted || token != _previewBinarizeUpdateToken) {
        image.dispose();
        break;
      }
      setState(() {
        _previewFilteredActiveLayerImage?.dispose();
        _previewFilteredActiveLayerImage = image;
        _previewFilteredImageType = _FilterPanelType.binarize;
      });
    }
    _previewBinarizeUpdateInFlight = false;
    if (_previewBinarizeUpdateScheduled) {
      unawaited(_runBinarizePreviewImageUpdate());
    }
  }

  List<double>? _calculateCurrentFilterMatrix() {
    final _FilterSession? session = _filterSession;
    if (session == null) return null;

    if (session.type == _FilterPanelType.hueSaturation) {
      final double hue = session.hueSaturation.hue;
      final double saturation = session.hueSaturation.saturation;
      if (hue == 0 && saturation == 0) return null;

      if (saturation == 0) {
        return ColorFilterGenerator.hue(hue);
      }
      return null; // Handled via chaining in build
    } else if (session.type == _FilterPanelType.brightnessContrast) {
      final double brightness = session.brightnessContrast.brightness;
      final double contrast = session.brightnessContrast.contrast;
      if (brightness == 0 && contrast == 0) return null;
      return ColorFilterGenerator.brightnessContrast(brightness, contrast);
    }
    return null;
  }


  void _insertFilterOverlay() {
    final OverlayState? overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    final Size size = MediaQuery.sizeOf(context);
    if (_filterPanelOffset == Offset.zero) {
      _filterPanelOffset = Offset(
        math.max(16, size.width - _kFilterPanelWidth - 32),
        math.max(16, size.height * 0.2),
      );
      _filterPanelOffsetIsOverlay = true;
    }
    _filterOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final _FilterSession? session = _filterSession;
        if (session == null) {
          return const SizedBox.shrink();
        }
        final Size bounds = MediaQuery.sizeOf(overlayContext);
        final double clampedX = _filterPanelOffset.dx.clamp(
          16.0,
          math.max(16.0, bounds.width - _kFilterPanelWidth - 16.0),
        );
        final double clampedY = _filterPanelOffset.dy.clamp(
          16.0,
          math.max(16.0, bounds.height - _kFilterPanelMinHeight - 16.0),
        );
        _filterPanelOffset = Offset(clampedX, clampedY);
        final String panelTitle;
        final Widget panelBody;
        final l10n = context.l10n;
        switch (session.type) {
          case _FilterPanelType.hueSaturation:
            panelTitle = l10n.hueSaturation;
            panelBody = _HueSaturationControls(
              settings: session.hueSaturation,
              onHueChanged: (value) => _updateHueSaturation(hue: value),
              onSaturationChanged: (value) =>
                  _updateHueSaturation(saturation: value),
              onLightnessChanged: (value) =>
                  _updateHueSaturation(lightness: value),
            );
            break;
          case _FilterPanelType.brightnessContrast:
            panelTitle = l10n.brightnessContrast;
            panelBody = _BrightnessContrastControls(
              settings: session.brightnessContrast,
              onBrightnessChanged: (value) =>
                  _updateBrightnessContrast(brightness: value),
              onContrastChanged: (value) =>
                  _updateBrightnessContrast(contrast: value),
            );
            break;
          case _FilterPanelType.blackWhite:
            panelTitle = l10n.blackAndWhite;
            panelBody = _BlackWhiteControls(
              settings: session.blackWhite,
              onBlackPointChanged: (value) =>
                  _updateBlackWhite(blackPoint: value),
              onWhitePointChanged: (value) =>
                  _updateBlackWhite(whitePoint: value),
              onMidToneChanged: (value) => _updateBlackWhite(midTone: value),
            );
            break;
          case _FilterPanelType.binarize:
            panelTitle = l10n.binarize;
            panelBody = _BinarizeControls(
              threshold: session.binarize.alphaThreshold,
              onThresholdChanged: _updateBinarizeThreshold,
            );
            break;
          case _FilterPanelType.scanPaperDrawing:
            panelTitle = l10n.menuScanPaperDrawing;
            panelBody = _BlackWhiteControls(
              settings: session.blackWhite,
              onBlackPointChanged: (value) =>
                  _updateBlackWhite(blackPoint: value),
              onWhitePointChanged: (value) =>
                  _updateBlackWhite(whitePoint: value),
              onMidToneChanged: (value) => _updateBlackWhite(midTone: value),
            );
            break;
          case _FilterPanelType.gaussianBlur:
            panelTitle = l10n.gaussianBlur;
            panelBody = _GaussianBlurControls(
              radius: session.gaussianBlur.radius,
              onRadiusChanged: _updateGaussianBlur,
            );
            break;
          case _FilterPanelType.leakRemoval:
            panelTitle = l10n.leakRemoval;
            panelBody = _LeakRemovalControls(
              radius: session.leakRemoval.radius,
              onRadiusChanged: _updateLeakRemovalRadius,
            );
            break;
          case _FilterPanelType.lineNarrow:
            panelTitle = l10n.lineNarrow;
            panelBody = _MorphologyControls(
              label: l10n.narrowRadius,
              radius: session.lineNarrow.radius,
              maxRadius: _kMorphologyMaxRadius,
              onRadiusChanged: _updateLineNarrow,
            );
            break;
          case _FilterPanelType.fillExpand:
            panelTitle = l10n.fillExpand;
            panelBody = _MorphologyControls(
              label: l10n.expandRadius,
              radius: session.fillExpand.radius,
              maxRadius: _kMorphologyMaxRadius,
              onRadiusChanged: _updateFillExpand,
            );
            break;
        }

        if (_filterLoading) {
          return Positioned(
            left: _filterPanelOffset.dx,
            top: _filterPanelOffset.dy,
            child: const SizedBox(
              width: _kFilterPanelWidth,
              height: 100,
              child: Center(child: ProgressRing()),
            ),
          );
        }

        return Positioned(
          left: _filterPanelOffset.dx,
          top: _filterPanelOffset.dy,
          child: WorkspaceFloatingPanel(
            width: _kFilterPanelWidth,
            minHeight: _kFilterPanelMinHeight,
            title: panelTitle,
            onClose: () => _removeFilterOverlay(),
            onDragUpdate: _handleFilterPanelDrag,
            headerPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            bodyPadding: const EdgeInsets.symmetric(horizontal: 16),
            footerPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            bodySpacing: 0,
            footerSpacing: 12,
            child: panelBody,
            footer: Row(
              children: [
                Button(
                  onPressed: _resetFilterSettings,
                  child: Text(l10n.reset),
                ),
                const Spacer(),
                Button(
                  onPressed: () => _removeFilterOverlay(),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _filterApplying
                      ? null
                      : (session.type == _FilterPanelType.scanPaperDrawing
                            ? _confirmScanPaperDrawingChanges
                            : _confirmFilterChanges),
                  child: _filterApplying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : Text(
                          session.type == _FilterPanelType.scanPaperDrawing
                              ? l10n.menuScanPaperDrawing
                              : l10n.apply,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
    overlay.insert(_filterOverlayEntry!);
  }

  void _initializeFilterWorker() {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    final CanvasLayerData baseLayer =
        session.originalLayers[session.activeLayerIndex];
    _filterWorker?.dispose();
    _filterWorker = _FilterPreviewWorker(
      type: session.type,
      layerId: session.activeLayerId,
      baseLayer: baseLayer,
      canvasWidth: _controller.width,
      canvasHeight: _controller.height,
      onResult: _handleFilterPreviewResult,
      onError: _handleFilterWorkerError,
    );
  }

  void _handleFilterPanelDrag(Offset delta) {
    _filterPanelOffset = Offset(
      _filterPanelOffset.dx + delta.dx,
      _filterPanelOffset.dy + delta.dy,
    );
    _filterPanelOffsetIsOverlay = true;
    _filterOverlayEntry?.markNeedsBuild();
  }

  void _resetFilterSettings() {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    session.hueSaturation
      ..hue = 0
      ..saturation = 0
      ..lightness = 0;
    session.brightnessContrast
      ..brightness = 0
      ..contrast = 0;
    session.blackWhite
      ..blackPoint = 0
      ..whitePoint = 100
      ..midTone = 0;
    session.binarize.alphaThreshold = _kDefaultBinarizeAlphaThreshold;
    session.gaussianBlur.radius = 0;
    session.leakRemoval.radius = 0;
    session.lineNarrow.radius = 0;
    session.fillExpand.radius = 0;
    setState(() {});
    _filterOverlayEntry?.markNeedsBuild();
    _scheduleHueSaturationPreviewImageUpdate();
    _scheduleBlackWhitePreviewImageUpdate();
    _scheduleBinarizePreviewImageUpdate();
  }

  void _updateHueSaturation({
    double? hue,
    double? saturation,
    double? lightness,
  }) {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    session.hueSaturation
      ..hue = hue ?? session.hueSaturation.hue
      ..saturation = saturation ?? session.hueSaturation.saturation
      ..lightness = lightness ?? session.hueSaturation.lightness;
    setState(() {});
    _filterOverlayEntry?.markNeedsBuild();
    _scheduleHueSaturationPreviewImageUpdate();
  }

  void _updateBrightnessContrast({double? brightness, double? contrast}) {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    session.brightnessContrast
      ..brightness = brightness ?? session.brightnessContrast.brightness
      ..contrast = contrast ?? session.brightnessContrast.contrast;
    setState(() {});
    _filterOverlayEntry?.markNeedsBuild();
  }

  void _updateBlackWhite({
    double? blackPoint,
    double? whitePoint,
    double? midTone,
  }) {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    final double nextBlack = (blackPoint ?? session.blackWhite.blackPoint)
        .clamp(0.0, 100.0);
    double nextWhite = (whitePoint ?? session.blackWhite.whitePoint).clamp(
      0.0,
      100.0,
    );
    if (nextWhite <= nextBlack + _kBlackWhiteMinRange) {
      nextWhite = math.min(100.0, nextBlack + _kBlackWhiteMinRange);
    }
    session.blackWhite
      ..blackPoint = nextBlack
      ..whitePoint = nextWhite
      ..midTone = (midTone ?? session.blackWhite.midTone).clamp(-100.0, 100.0);
    setState(() {});
    _filterOverlayEntry?.markNeedsBuild();
    _scheduleBlackWhitePreviewImageUpdate();
  }

  void _updateBinarizeThreshold(double threshold) {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    session.binarize.alphaThreshold = threshold.clamp(0.0, 255.0);
    setState(() {});
    _filterOverlayEntry?.markNeedsBuild();
    _scheduleBinarizePreviewImageUpdate();
  }

  void _updateGaussianBlur(double radius) {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    session.gaussianBlur.radius = radius.clamp(0.0, _kGaussianBlurMaxRadius);
    setState(() {});
    _filterOverlayEntry?.markNeedsBuild();
  }

  void _updateLeakRemovalRadius(double radius) {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    session.leakRemoval.radius = radius.clamp(0.0, _kLeakRemovalMaxRadius);
    setState(() {});
    _filterOverlayEntry?.markNeedsBuild();
  }

  void _updateLineNarrow(double radius) {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    session.lineNarrow.radius = radius.clamp(0.0, _kMorphologyMaxRadius);
    setState(() {});
    _filterOverlayEntry?.markNeedsBuild();
  }

  void _updateFillExpand(double radius) {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    session.fillExpand.radius = radius.clamp(0.0, _kMorphologyMaxRadius);
    setState(() {});
    _filterOverlayEntry?.markNeedsBuild();
  }

}
