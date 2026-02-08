part of 'painting_board.dart';

extension _PaintingBoardFilterPreviewExtension on _PaintingBoardFilterMixin {
  void _requestFilterPreview({bool immediate = false}) {
    // Only used for final apply now
    _applyFilterPreview();
  }

  void _applyFilterPreview() {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    if (_filterWorker == null) {
      _initializeFilterWorker();
    }
    _filterPreviewPendingChange = true;
    _tryDispatchFilterPreview();
  }

  void _tryDispatchFilterPreview() {
    if (!_filterPreviewPendingChange || _filterPreviewRequestInFlight) {
      return;
    }
    final _FilterSession? session = _filterSession;
    if (session == null) {
      _filterPreviewPendingChange = false;
      return;
    }

    final _FilterPreviewWorker? worker = _filterWorker;
    if (worker == null) {
      return;
    }
    _filterPreviewPendingChange = false;
    _filterPreviewRequestInFlight = true;
    final int token = ++_filterPreviewLastIssuedToken;
    final double morphRadius = switch (session.type) {
      _FilterPanelType.lineNarrow => session.lineNarrow.radius,
      _FilterPanelType.fillExpand => session.fillExpand.radius,
      _ => 0.0,
    };
    final double binarizeThreshold = session.binarize.alphaThreshold;
    unawaited(
      worker.requestPreview(
        token: token,
        hueSaturation: session.hueSaturation,
        brightnessContrast: session.brightnessContrast,
        blackWhite: session.blackWhite,
        blurRadius: session.gaussianBlur.radius,
        leakRadius: session.leakRemoval.radius,
        morphRadius: morphRadius,
        binarizeThreshold: binarizeThreshold,
      ),
    );
  }

  void _onFilterPreviewRequestComplete() {
    if (!_filterPreviewRequestInFlight) {
      return;
    }
    _filterPreviewRequestInFlight = false;
    if (_filterPreviewPendingChange) {
      _tryDispatchFilterPreview();
    }
  }

  Future<void> _confirmFilterChanges() async {
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    if (_isFilterSessionIdentity(session)) {
      if (session.type == _FilterPanelType.binarize) {
        _showFilterMessage(context.l10n.noTransparentPixelsFound);
      }
      _removeFilterOverlay();
      return;
    }

    if (_canUseRustCanvasEngine() && _supportsRustFilter(session.type)) {
      setState(() {
        _filterApplying = true;
      });
      _filterOverlayEntry?.markNeedsBuild();

      bool applied = false;
      try {
        applied = await _applyRustFilter(session);
      } catch (error, stackTrace) {
        debugPrint('Rust filter apply failed: $error');
        debugPrint('$stackTrace');
      }

      if (!mounted || _filterSession != session) {
        return;
      }
      if (!applied) {
        setState(() {
          _filterApplying = false;
        });
        _filterOverlayEntry?.markNeedsBuild();
        _showFilterMessage(context.l10n.filterApplyFailed);
        return;
      }
      _removeFilterOverlay(restoreOriginal: true);
      return;
    }

    setState(() {
      _filterApplying = true;
    });
    _filterOverlayEntry?.markNeedsBuild();

    final Completer<_FilterPreviewResult> completer =
        Completer<_FilterPreviewResult>();
    _filterApplyCompleter = completer;
    _requestFilterPreview(immediate: true);

    final _FilterPreviewResult result;
    try {
      result = await completer.future;
    } catch (error, stackTrace) {
      debugPrint('Filter apply failed: $error');
      _filterApplyCompleter = null;
      if (mounted) {
        setState(() {
          _filterApplying = false;
        });
        _filterOverlayEntry?.markNeedsBuild();
      }
      _showFilterMessage(context.l10n.filterApplyFailed);
      return;
    }
    _filterApplyCompleter = null;
    await _finalizeFilterApply(session, result);
  }

  Future<bool> _applyRustFilter(_FilterSession session) async {
    final int? handle = _rustCanvasEngineHandle;
    if (!_canUseRustCanvasEngine() || handle == null) {
      return false;
    }
    final int? layerIndex = _rustCanvasLayerIndexForId(session.activeLayerId);
    if (layerIndex == null) {
      return false;
    }
    bool applied = false;
    switch (session.type) {
      case _FilterPanelType.hueSaturation:
        applied = await CanvasEngineFfi.instance.applyFilter(
          handle: handle,
          layerIndex: layerIndex,
          filterType: _kFilterTypeHueSaturation,
          param0: session.hueSaturation.hue,
          param1: session.hueSaturation.saturation,
          param2: session.hueSaturation.lightness,
        );
        break;
      case _FilterPanelType.brightnessContrast:
        applied = await CanvasEngineFfi.instance.applyFilter(
          handle: handle,
          layerIndex: layerIndex,
          filterType: _kFilterTypeBrightnessContrast,
          param0: session.brightnessContrast.brightness,
          param1: session.brightnessContrast.contrast,
        );
        break;
      case _FilterPanelType.blackWhite:
        applied = await CanvasEngineFfi.instance.applyFilter(
          handle: handle,
          layerIndex: layerIndex,
          filterType: _kFilterTypeBlackWhite,
          param0: session.blackWhite.blackPoint,
          param1: session.blackWhite.whitePoint,
          param2: session.blackWhite.midTone,
        );
        break;
      case _FilterPanelType.binarize:
        applied = await CanvasEngineFfi.instance.applyFilter(
          handle: handle,
          layerIndex: layerIndex,
          filterType: _kFilterTypeBinarize,
          param0: session.binarize.alphaThreshold,
        );
        break;
      case _FilterPanelType.gaussianBlur:
        applied = await CanvasEngineFfi.instance.applyFilter(
          handle: handle,
          layerIndex: layerIndex,
          filterType: _kFilterTypeGaussianBlur,
          param0: session.gaussianBlur.radius,
        );
        break;
      case _FilterPanelType.leakRemoval:
        applied = await CanvasEngineFfi.instance.applyFilter(
          handle: handle,
          layerIndex: layerIndex,
          filterType: _kFilterTypeLeakRemoval,
          param0: session.leakRemoval.radius,
        );
        break;
      case _FilterPanelType.lineNarrow:
        applied = await CanvasEngineFfi.instance.applyFilter(
          handle: handle,
          layerIndex: layerIndex,
          filterType: _kFilterTypeLineNarrow,
          param0: session.lineNarrow.radius,
        );
        break;
      case _FilterPanelType.fillExpand:
        applied = await CanvasEngineFfi.instance.applyFilter(
          handle: handle,
          layerIndex: layerIndex,
          filterType: _kFilterTypeFillExpand,
          param0: session.fillExpand.radius,
        );
        break;
      case _FilterPanelType.scanPaperDrawing:
        applied = await CanvasEngineFfi.instance.applyFilter(
          handle: handle,
          layerIndex: layerIndex,
          filterType: _kFilterTypeScanPaperDrawing,
          param0: session.blackWhite.blackPoint,
          param1: session.blackWhite.whitePoint,
          param2: session.blackWhite.midTone,
        );
        break;
    }
    if (applied) {
      _recordRustHistoryAction(layerId: session.activeLayerId);
      if (mounted) {
        setState(() {});
      }
      _markDirty();
    }
    return applied;
  }

  bool _supportsRustFilter(_FilterPanelType type) {
    switch (type) {
      case _FilterPanelType.hueSaturation:
      case _FilterPanelType.brightnessContrast:
      case _FilterPanelType.blackWhite:
      case _FilterPanelType.binarize:
      case _FilterPanelType.gaussianBlur:
      case _FilterPanelType.leakRemoval:
      case _FilterPanelType.lineNarrow:
      case _FilterPanelType.fillExpand:
      case _FilterPanelType.scanPaperDrawing:
        return true;
    }
  }

  Uint8List _argbPixelsToRgba(Uint32List pixels) {
    final Uint8List rgba = Uint8List(pixels.length * 4);
    for (int i = 0; i < pixels.length; i++) {
      final int argb = pixels[i];
      final int offset = i * 4;
      rgba[offset] = (argb >> 16) & 0xff;
      rgba[offset + 1] = (argb >> 8) & 0xff;
      rgba[offset + 2] = argb & 0xff;
      rgba[offset + 3] = (argb >> 24) & 0xff;
    }
    return rgba;
  }

  Uint32List _rgbaToArgbPixels(Uint8List rgba) {
    final int length = rgba.length ~/ 4;
    final Uint32List pixels = Uint32List(length);
    for (int i = 0; i < length; i++) {
      final int offset = i * 4;
      final int r = rgba[offset];
      final int g = rgba[offset + 1];
      final int b = rgba[offset + 2];
      final int a = rgba[offset + 3];
      pixels[i] = (a << 24) | (r << 16) | (g << 8) | b;
    }
    return pixels;
  }

  Future<void> _confirmScanPaperDrawingChanges() async {
    final _FilterSession? session = _filterSession;
    if (session == null || session.type != _FilterPanelType.scanPaperDrawing) {
      return;
    }

    final l10n = context.l10n;
    if (_canUseRustCanvasEngine() && _supportsRustFilter(session.type)) {
      setState(() {
        _filterApplying = true;
      });
      _filterOverlayEntry?.markNeedsBuild();

      bool applied = false;
      try {
        applied = await _applyRustFilter(session);
      } catch (error, stackTrace) {
        debugPrint('Rust scan paper drawing apply failed: $error');
        debugPrint('$stackTrace');
      }

      if (!mounted || _filterSession != session) {
        return;
      }
      if (!applied) {
        setState(() {
          _filterApplying = false;
        });
        _filterOverlayEntry?.markNeedsBuild();
        _showFilterMessage(l10n.filterApplyFailed);
        return;
      }
      _removeFilterOverlay(restoreOriginal: true);
      return;
    }

    final CanvasLayerData data =
        session.originalLayers[session.activeLayerIndex];
    final Uint8List? bitmap = data.bitmap;
    final bool hasBitmap =
        bitmap != null &&
        bitmap.isNotEmpty &&
        (data.bitmapWidth ?? 0) > 0 &&
        (data.bitmapHeight ?? 0) > 0;
    final bool hasFill = data.fillColor != null && data.fillColor!.alpha != 0;
    if (!hasBitmap && !hasFill) {
      _showFilterMessage(l10n.layerEmptyScanPaperDrawing);
      _removeFilterOverlay();
      return;
    }

    setState(() {
      _filterApplying = true;
    });
    _filterOverlayEntry?.markNeedsBuild();

    final _ScanPaperDrawingComputeResult result;
    try {
      result = await _generateScanPaperDrawingResult(
        bitmap,
        data.fillColor,
        blackPoint: session.blackWhite.blackPoint,
        whitePoint: session.blackWhite.whitePoint,
        midTone: session.blackWhite.midTone,
      );
    } catch (error, stackTrace) {
      debugPrint('Scan paper drawing apply failed: $error');
      debugPrint('$stackTrace');
      if (!mounted || _filterSession != session) {
        return;
      }
      setState(() {
        _filterApplying = false;
      });
      _filterOverlayEntry?.markNeedsBuild();
      _showFilterMessage(l10n.filterApplyFailed);
      return;
    }

    if (!result.changed) {
      if (!mounted || _filterSession != session) {
        return;
      }
      setState(() {
        _filterApplying = false;
      });
      _filterOverlayEntry?.markNeedsBuild();
      _showFilterMessage(l10n.scanPaperDrawingNoChanges);
      return;
    }

    if (!mounted || _filterSession != session) {
      return;
    }

    await _pushUndoSnapshot();
    final int? awaitedGeneration = _controller.frame?.generation;
    final CanvasLayerData updated = CanvasLayerData(
      id: data.id,
      name: data.name,
      visible: data.visible,
      opacity: data.opacity,
      locked: data.locked,
      clippingMask: data.clippingMask,
      blendMode: data.blendMode,
      fillColor: result.fillColor != null ? Color(result.fillColor!) : null,
      bitmap: result.bitmap,
      bitmapWidth: result.bitmap != null ? data.bitmapWidth : null,
      bitmapHeight: result.bitmap != null ? data.bitmapHeight : null,
      bitmapLeft: result.bitmap != null ? data.bitmapLeft : null,
      bitmapTop: result.bitmap != null ? data.bitmapTop : null,
      text: data.text,
      cloneBitmap: false,
    );
    _controller.replaceLayer(session.activeLayerId, updated);
    _controller.setActiveLayer(session.activeLayerId);
    _markDirty();
    setState(() {});
    _scheduleFilterOverlayRemovalAfterApply(awaitedGeneration);
  }

  Future<void> _finalizeFilterApply(
    _FilterSession session,
    _FilterPreviewResult result,
  ) async {
    final CanvasLayerData original =
        session.originalLayers[session.activeLayerIndex];
    final CanvasLayerData adjusted = _buildAdjustedLayerFromResult(
      original,
      result,
    );
    await _pushUndoSnapshot();
    final int? awaitedGeneration = _controller.frame?.generation;
    _controller.replaceLayer(session.activeLayerId, adjusted);
    _controller.setActiveLayer(session.activeLayerId);
    _markDirty();
    setState(() {});
    _scheduleFilterOverlayRemovalAfterApply(awaitedGeneration);
  }

  void _scheduleFilterOverlayRemovalAfterApply(int? awaitedGeneration) {
    if (awaitedGeneration == null) {
      _removeFilterOverlay(restoreOriginal: false);
      return;
    }
    _filterAwaitedFrameGeneration = awaitedGeneration;
    _filterAwaitingFrameSwap = true;
    _tryFinalizeFilterApplyAfterFrameChange();
  }

  void _tryFinalizeFilterApplyAfterFrameChange([BitmapCanvasFrame? frame]) {
    if (!_filterAwaitingFrameSwap) {
      return;
    }
    frame ??= _controller.frame;
    if (frame == null) {
      return;
    }
    final int? awaitedGeneration = _filterAwaitedFrameGeneration;
    if (awaitedGeneration == null || frame.generation != awaitedGeneration) {
      _filterAwaitingFrameSwap = false;
      _filterAwaitedFrameGeneration = null;
      _removeFilterOverlay(restoreOriginal: false);
    }
  }

  void _handleFilterApplyFrameProgressInternal(BitmapCanvasFrame? frame) {
    _tryFinalizeFilterApplyAfterFrameChange(frame);
  }

  bool _isFilterSessionIdentity(_FilterSession session) {
    final bool allowRust =
        _canUseRustCanvasEngine() && _supportsRustFilter(session.type);
    switch (session.type) {
      case _FilterPanelType.hueSaturation:
        final _HueSaturationSettings settings = session.hueSaturation;
        return settings.hue == 0 &&
            settings.saturation == 0 &&
            settings.lightness == 0;
      case _FilterPanelType.brightnessContrast:
        final _BrightnessContrastSettings settings = session.brightnessContrast;
        return settings.brightness == 0 && settings.contrast == 0;
      case _FilterPanelType.blackWhite:
        final CanvasLayerData layer =
            session.originalLayers[session.activeLayerIndex];
        final bool hasBitmap =
            layer.bitmap != null &&
            (layer.bitmapWidth ?? 0) > 0 &&
            (layer.bitmapHeight ?? 0) > 0;
        final bool hasFill = layer.fillColor != null;
        return !hasBitmap && !hasFill && !allowRust;
      case _FilterPanelType.scanPaperDrawing:
        final CanvasLayerData layer =
            session.originalLayers[session.activeLayerIndex];
        final bool hasBitmap =
            layer.bitmap != null &&
            (layer.bitmapWidth ?? 0) > 0 &&
            (layer.bitmapHeight ?? 0) > 0;
        final bool hasFill = layer.fillColor != null;
        return !hasBitmap && !hasFill;
      case _FilterPanelType.binarize:
        if (allowRust) {
          return false;
        }
        final CanvasLayerData layer =
            session.originalLayers[session.activeLayerIndex];
        final Uint8List? bitmap = layer.bitmap;
        bool hasPartialAlpha = false;
        if (bitmap != null) {
          for (int i = 3; i < bitmap.length; i += 4) {
            final int alpha = bitmap[i];
            if (alpha != 0 && alpha != 255) {
              hasPartialAlpha = true;
              break;
            }
          }
        }
        if (!hasPartialAlpha && layer.fillColor != null) {
          final int alpha = layer.fillColor!.alpha;
          if (alpha != 0 && alpha != 255) {
            hasPartialAlpha = true;
          }
        }
        final bool hasContent =
            (bitmap != null &&
                (layer.bitmapWidth ?? 0) > 0 &&
                (layer.bitmapHeight ?? 0) > 0) ||
            layer.fillColor != null;
        return !hasContent || !hasPartialAlpha;
      case _FilterPanelType.gaussianBlur:
        final double radius = session.gaussianBlur.radius;
        final CanvasLayerData layer =
            session.originalLayers[session.activeLayerIndex];
        final bool hasBitmap =
            layer.bitmap != null &&
            (layer.bitmapWidth ?? 0) > 0 &&
            (layer.bitmapHeight ?? 0) > 0;
        return radius <= 0 || (!hasBitmap && !allowRust);
      case _FilterPanelType.leakRemoval:
        final double radius = session.leakRemoval.radius;
        final CanvasLayerData layer =
            session.originalLayers[session.activeLayerIndex];
        final bool hasBitmap =
            layer.bitmap != null &&
            (layer.bitmapWidth ?? 0) > 0 &&
            (layer.bitmapHeight ?? 0) > 0;
        return radius <= 0 || (!hasBitmap && !allowRust);
      case _FilterPanelType.lineNarrow:
      case _FilterPanelType.fillExpand:
        final double radius = session.type == _FilterPanelType.lineNarrow
            ? session.lineNarrow.radius
            : session.fillExpand.radius;
        final CanvasLayerData layer =
            session.originalLayers[session.activeLayerIndex];
        final bool hasBitmap =
            layer.bitmap != null &&
            (layer.bitmapWidth ?? 0) > 0 &&
            (layer.bitmapHeight ?? 0) > 0;
        return radius <= 0 || (!hasBitmap && !allowRust);
    }
  }

  void _handleFilterPreviewResult(_FilterPreviewResult result) {
    if (!mounted) {
      return;
    }
    if (result.token != _filterPreviewLastIssuedToken) {
      return;
    }
    final _FilterSession? session = _filterSession;
    if (session == null) {
      return;
    }
    if (result.layerId != session.activeLayerId) {
      return;
    }
    final Completer<_FilterPreviewResult>? completer = _filterApplyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
      _onFilterPreviewRequestComplete();
      return;
    }
    final CanvasLayerData original =
        session.originalLayers[session.activeLayerIndex];
    final CanvasLayerData adjusted = _buildAdjustedLayerFromResult(
      original,
      result,
    );
    session.previewLayer = adjusted;
    _controller.replaceLayer(session.activeLayerId, adjusted);
    _controller.setActiveLayer(session.activeLayerId);
    setState(() {});
    _onFilterPreviewRequestComplete();
  }

  void _handleFilterWorkerError(Object error, StackTrace stackTrace) {
    debugPrint('Filter preview worker error: $error');
    final Completer<_FilterPreviewResult>? completer = _filterApplyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
    _onFilterPreviewRequestComplete();
  }

  void _restoreFilterPreviewToOriginal(_FilterSession session) {
    if (session.previewLayer == null) {
      return;
    }
    final bool shouldNotify = mounted;
    final CanvasLayerData original =
        session.originalLayers[session.activeLayerIndex];
    _controller.replaceLayer(session.activeLayerId, original);
    _controller.setActiveLayer(session.activeLayerId);
    session.previewLayer = null;
    if (shouldNotify) {
      setState(() {});
    }
  }

  void _cancelFilterPreviewTasks() {
    _filterPreviewLastIssuedToken++;
    _filterWorker?.discardPendingResult();
    _filterPreviewPendingChange = false;
    _filterPreviewRequestInFlight = false;
    _filterPreviewDebounceTimer?.cancel();
    _filterPreviewDebounceTimer = null;
  }

  void _removeFilterOverlayInternal({bool restoreOriginal = true}) {
    _filterOverlayEntry?.remove();
    _filterOverlayEntry = null;
    _cancelFilterPreviewTasks();
    _restoreRustLayerAfterFilterPreview();
    final _FilterSession? session = _filterSession;
    if (restoreOriginal && session != null) {
      _restoreFilterPreviewToOriginal(session);
    }
    _filterWorker?.dispose();
    _filterWorker = null;
    _filterSession = null;
    if (_filterApplyCompleter != null && !_filterApplyCompleter!.isCompleted) {
      _filterApplyCompleter!.completeError(StateError('滤镜面板已关闭，操作被取消。'));
    }
    _filterApplyCompleter = null;
    _filterAwaitingFrameSwap = false;
    _filterAwaitedFrameGeneration = null;

    _previewBackground?.dispose();
    _previewBackground = null;
    _previewActiveLayerImage?.dispose();
    _previewActiveLayerImage = null;
    _previewFilteredActiveLayerImage?.dispose();
    _previewFilteredActiveLayerImage = null;
    _previewFilteredImageType = null;
    _previewForeground?.dispose();
    _previewForeground = null;
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
    _filterLoading = false;
    _filterApplying = false;

    if (_filterPanelOffset == Offset.zero) {
      _filterPanelOffsetIsOverlay = false;
    }
  }

  CanvasLayerData _buildAdjustedLayerFromResult(
    CanvasLayerData original,
    _FilterPreviewResult result,
  ) {
    final Uint8List? bitmap = result.bitmapBytes;
    final int? fillValue = result.fillColor;
    Color? fillColor = original.fillColor;
    if (fillValue != null) {
      fillColor = Color(fillValue);
    }
    final bool hasBitmap = bitmap != null;
    return CanvasLayerData(
      id: original.id,
      name: original.name,
      visible: original.visible,
      opacity: original.opacity,
      locked: original.locked,
      clippingMask: original.clippingMask,
      blendMode: original.blendMode,
      fillColor: fillColor,
      bitmap: bitmap,
      bitmapWidth: hasBitmap ? original.bitmapWidth : null,
      bitmapHeight: hasBitmap ? original.bitmapHeight : null,
      bitmapLeft: hasBitmap ? original.bitmapLeft : null,
      bitmapTop: hasBitmap ? original.bitmapTop : null,
      cloneBitmap: false,
    );
  }

  CanvasLayerData _buildColorRangeAdjustedLayer(
    CanvasLayerData original,
    _ColorRangeComputeResult result,
  ) {
    final Uint8List? bitmap = result.bitmap ?? original.bitmap;
    final int? fillValue = result.fillColor;
    Color? fillColor = original.fillColor;
    if (fillValue != null) {
      fillColor = Color(fillValue);
    }
    final bool hasBitmap = bitmap != null;
    return CanvasLayerData(
      id: original.id,
      name: original.name,
      visible: original.visible,
      opacity: original.opacity,
      locked: original.locked,
      clippingMask: original.clippingMask,
      blendMode: original.blendMode,
      fillColor: fillColor,
      bitmap: bitmap,
      bitmapWidth: hasBitmap ? original.bitmapWidth : null,
      bitmapHeight: hasBitmap ? original.bitmapHeight : null,
      bitmapLeft: hasBitmap ? original.bitmapLeft : null,
      bitmapTop: hasBitmap ? original.bitmapTop : null,
      text: original.text,
      cloneBitmap: false,
    );
  }

  Future<void> scanPaperDrawing() async {
    final l10n = context.l10n;
    if (_controller.frame == null && !_canUseRustCanvasEngine()) {
      _showFilterMessage(l10n.canvasNotReady);
      return;
    }
    final String? activeLayerId = _activeLayerId;
    if (activeLayerId == null) {
      _showFilterMessage(l10n.selectEditableLayerFirst);
      return;
    }
    final BitmapLayerState? layer = _layerById(activeLayerId);
    if (layer == null) {
      _showFilterMessage(l10n.cannotLocateLayer);
      return;
    }
    if (layer.locked) {
      _showFilterMessage(l10n.layerLockedNoFilter);
      return;
    }

    await _controller.waitForPendingWorkerTasks();
    final List<CanvasLayerData> snapshot = _controller.snapshotLayers();
    final int index = snapshot.indexWhere((item) => item.id == activeLayerId);
    if (index < 0) {
      _showFilterMessage(l10n.cannotLocateLayer);
      return;
    }
    final CanvasLayerData data = snapshot[index];
    final Uint8List? bitmap = data.bitmap;
    final bool hasBitmap =
        bitmap != null &&
        bitmap.isNotEmpty &&
        (data.bitmapWidth ?? 0) > 0 &&
        (data.bitmapHeight ?? 0) > 0;
    final bool hasFill = data.fillColor != null && data.fillColor!.alpha != 0;
    if (!hasBitmap && !hasFill) {
      _showFilterMessage(l10n.layerEmptyScanPaperDrawing);
      return;
    }

    final _ScanPaperDrawingComputeResult result;
    try {
      result = await _generateScanPaperDrawingResult(bitmap, data.fillColor);
    } catch (error, stackTrace) {
      debugPrint('Scan paper drawing apply failed: $error');
      debugPrint('$stackTrace');
      _showFilterMessage(l10n.filterApplyFailed);
      return;
    }

    if (!result.changed) {
      _showFilterMessage(l10n.scanPaperDrawingNoChanges);
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
      fillColor: result.fillColor != null ? Color(result.fillColor!) : null,
      bitmap: result.bitmap,
      bitmapWidth: result.bitmap != null ? data.bitmapWidth : null,
      bitmapHeight: result.bitmap != null ? data.bitmapHeight : null,
      bitmapLeft: result.bitmap != null ? data.bitmapLeft : null,
      bitmapTop: result.bitmap != null ? data.bitmapTop : null,
      text: data.text,
      cloneBitmap: false,
    );
    _controller.replaceLayer(activeLayerId, updated);
    _controller.setActiveLayer(activeLayerId);
    setState(() {});
    _markDirty();
  }

}
