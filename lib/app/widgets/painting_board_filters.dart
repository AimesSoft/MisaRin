part of 'painting_board.dart';

const double _kFilterPanelWidth = 320;
const double _kFilterPanelMinHeight = 180;
const double _kAntialiasPanelWidth = 280;
const double _kAntialiasPanelMinHeight = 140;
const double _kColorRangePanelWidth = 280;
const double _kColorRangePanelMinHeight = 150;
const int _kColorRangeMaxSelectableColors = 256;
const int _kColorRangeAlphaThreshold = 12;
const int _kColorRangeQuantizationStep = 8; // 5-bit per channel
const int _kColorRangeMinBucketSize = 3;
const double _kColorRangeSmallBucketFraction = 0.0005; // 0.05% coverage
const Duration _kColorRangePreviewDebounceDuration = Duration(
  milliseconds: 120,
);
const double _kGaussianBlurMaxRadius = 1000.0;
const double _kLeakRemovalMaxRadius = 20.0;
const double _kMorphologyMaxRadius = 20.0;
const double _kBlackWhiteMinRange = 1.0;
const double _kDefaultBinarizeAlphaThreshold = 128.0;
const int _kScanPaperWhiteMaxThreshold = 190;
const int _kScanPaperWhiteDeltaThreshold = 90;
const int _kScanPaperColorDistanceThresholdSq = 180 * 180;
const int _kScanPaperBlackDistanceThresholdSq = 320 * 320;
const ColorFilter _kViewBlackWhiteColorFilter = ColorFilter.matrix(<double>[
  0.299,
  0.587,
  0.114,
  0,
  0,
  0.299,
  0.587,
  0.114,
  0,
  0,
  0.299,
  0.587,
  0.114,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
]);
final Matrix4 _kViewMirrorTransform = Matrix4.diagonal3Values(-1, 1, 1);

enum _FilterPanelType {
  hueSaturation,
  brightnessContrast,
  blackWhite,
  binarize,
  scanPaperDrawing,
  gaussianBlur,
  leakRemoval,
  lineNarrow,
  fillExpand,
}

class _HueSaturationSettings {
  _HueSaturationSettings({
    this.hue = 0,
    this.saturation = 0,
    this.lightness = 0,
  });

  double hue;
  double saturation;
  double lightness;
}

class _BrightnessContrastSettings {
  _BrightnessContrastSettings({this.brightness = 0, this.contrast = 0});

  double brightness;
  double contrast;
}

class _GaussianBlurSettings {
  _GaussianBlurSettings({this.radius = 0});

  double radius;
}

class _LeakRemovalSettings {
  _LeakRemovalSettings({this.radius = 0});

  double radius;
}

class _MorphologySettings {
  _MorphologySettings({this.radius = 0});

  double radius;
}

class _BlackWhiteSettings {
  _BlackWhiteSettings({
    this.blackPoint = 0,
    this.whitePoint = 100,
    this.midTone = 0,
  });

  double blackPoint;
  double whitePoint;
  double midTone;
}

class _BinarizeSettings {
  _BinarizeSettings({this.alphaThreshold = _kDefaultBinarizeAlphaThreshold});

  double alphaThreshold;
}

class _FilterSession {
  _FilterSession({
    required this.type,
    required this.originalLayers,
    required this.activeLayerIndex,
    required this.activeLayerId,
  });

  final _FilterPanelType type;
  final List<CanvasLayerData> originalLayers;
  final int activeLayerIndex;
  final String activeLayerId;
  final _HueSaturationSettings hueSaturation = _HueSaturationSettings();
  final _BrightnessContrastSettings brightnessContrast =
      _BrightnessContrastSettings();
  final _BlackWhiteSettings blackWhite = _BlackWhiteSettings();
  final _BinarizeSettings binarize = _BinarizeSettings();
  final _GaussianBlurSettings gaussianBlur = _GaussianBlurSettings();
  final _LeakRemovalSettings leakRemoval = _LeakRemovalSettings();
  final _MorphologySettings lineNarrow = _MorphologySettings();
  final _MorphologySettings fillExpand = _MorphologySettings();
  CanvasLayerData? previewLayer;
}

class _ColorRangeSession {
  _ColorRangeSession({
    required this.layerId,
    required this.originalLayers,
    required this.activeLayerIndex,
  });

  final String layerId;
  final List<CanvasLayerData> originalLayers;
  final int activeLayerIndex;
  CanvasLayerData? previewLayer;
  Uint8List? rustBitmap;
  Uint32List? rustPixels;
  int rustWidth = 0;
  int rustHeight = 0;

  bool get usesRust =>
      rustPixels != null && rustWidth > 0 && rustHeight > 0;
}

mixin _PaintingBoardFilterMixin
    on _PaintingBoardBase, _PaintingBoardLayerMixin {
  OverlayEntry? _filterOverlayEntry;
  _FilterSession? _filterSession;
  Offset _filterPanelOffset = Offset.zero;
  bool _filterPanelOffsetIsOverlay = false;
  _FilterPreviewWorker? _filterWorker;
  int _filterPreviewLastIssuedToken = 0;
  bool _filterPreviewRequestInFlight = false;
  bool _filterPreviewPendingChange = false;
  static const Duration _filterPreviewDebounceDuration = Duration(
    milliseconds: 50,
  );
  Timer? _filterPreviewDebounceTimer;
  bool _antialiasCardVisible = false;
  Offset _antialiasCardOffset = Offset.zero;
  Size? _antialiasCardSize;
  int _antialiasCardLevel = 2;
  bool _colorRangeCardVisible = false;
  Offset _colorRangeCardOffset = Offset.zero;
  Size? _colorRangeCardSize;
  int _colorRangeTotalColors = 0;
  int _colorRangeSelectedColors = 0;
  bool _colorRangeLoading = false;
  _ColorRangeSession? _colorRangeSession;
  bool _colorRangePreviewScheduled = false;
  bool _colorRangePreviewInFlight = false;
  int _colorRangePreviewToken = 0;
  Timer? _colorRangePreviewDebounceTimer;
  bool _colorRangeApplying = false;

  bool _filterLoading = false;
  ui.Image? _previewBackground;
  ui.Image? _previewActiveLayerImage;
  ui.Image? _previewFilteredActiveLayerImage;
  _FilterPanelType? _previewFilteredImageType;
  ui.Image? _previewForeground;
  Uint8List? _previewActiveLayerPixels;
  bool _previewHueSaturationUpdateScheduled = false;
  bool _previewHueSaturationUpdateInFlight = false;
  int _previewHueSaturationUpdateToken = 0;
  bool _previewBlackWhiteUpdateScheduled = false;
  bool _previewBlackWhiteUpdateInFlight = false;
  int _previewBlackWhiteUpdateToken = 0;
  bool _previewBinarizeUpdateScheduled = false;
  bool _previewBinarizeUpdateInFlight = false;
  int _previewBinarizeUpdateToken = 0;
  bool _filterApplying = false;
  Completer<_FilterPreviewResult>? _filterApplyCompleter;
  bool _filterAwaitingFrameSwap = false;
  int? _filterAwaitedFrameGeneration;
  String? _filterRustHiddenLayerId;
  bool _filterRustHiddenLayerVisible = false;
  int _filterRustHideToken = 0;

  void showHueSaturationAdjustments() {
    this._openFilterPanel(_FilterPanelType.hueSaturation);
  }

  void showBrightnessContrastAdjustments() {
    this._openFilterPanel(_FilterPanelType.brightnessContrast);
  }

  void showBlackWhiteAdjustments() {
    this._openFilterPanel(_FilterPanelType.blackWhite);
  }

  void showBinarizeAdjustments() {
    this._openFilterPanel(_FilterPanelType.binarize);
  }

  void showScanPaperDrawingAdjustments() {
    this._openFilterPanel(_FilterPanelType.scanPaperDrawing);
  }

  void showGaussianBlurAdjustments() {
    this._openFilterPanel(_FilterPanelType.gaussianBlur);
  }

  void showLeakRemovalAdjustments() {
    this._openFilterPanel(_FilterPanelType.leakRemoval);
  }

  void showLineNarrowAdjustments() {
    this._openFilterPanel(_FilterPanelType.lineNarrow);
  }

  void showFillExpandAdjustments() {
    this._openFilterPanel(_FilterPanelType.fillExpand);
  }

  void _showFilterMessage(String message) {
    AppNotifications.show(
      context,
      message: message,
      severity: InfoBarSeverity.warning,
    );
  }

  void _removeFilterOverlay({bool restoreOriginal = true}) {
    this._removeFilterOverlayInternal(restoreOriginal: restoreOriginal);
  }

  void _handleFilterApplyFrameProgress(BitmapCanvasFrame? frame) {
    this._handleFilterApplyFrameProgressInternal(frame);
  }

  bool _shouldUseRustFilterPreview(_FilterSession session) {
    if (!_canUseRustCanvasEngine()) {
      return false;
    }
    return session.type == _FilterPanelType.hueSaturation ||
        session.type == _FilterPanelType.brightnessContrast ||
        session.type == _FilterPanelType.blackWhite ||
        session.type == _FilterPanelType.binarize ||
        session.type == _FilterPanelType.scanPaperDrawing ||
        session.type == _FilterPanelType.gaussianBlur;
  }

  void _enableRustFilterPreviewIfNeeded(_FilterSession session) {
    if (!_shouldUseRustFilterPreview(session) ||
        _previewActiveLayerImage == null) {
      _restoreRustLayerAfterFilterPreview();
      return;
    }
    _hideRustLayerForFilterPreview(session.activeLayerId);
  }

  void _hideRustLayerForFilterPreview(String layerId) {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    if (_filterRustHiddenLayerId == layerId) {
      return;
    }
    _restoreRustLayerAfterFilterPreview();
    final int token = ++_filterRustHideToken;
    // Defer hiding until the next frame so the preview overlay is ready,
    // avoiding a visible flash.
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (!mounted || token != _filterRustHideToken) {
        return;
      }
      final _FilterSession? session = _filterSession;
      if (session == null ||
          session.activeLayerId != layerId ||
          !_shouldUseRustFilterPreview(session) ||
          _previewActiveLayerImage == null) {
        return;
      }
      final BitmapLayerState? layer = _layerById(layerId);
      if (layer == null || !layer.visible) {
        return;
      }
      final int? index = _rustCanvasLayerIndexForId(layerId);
      if (index == null) {
        return;
      }
      _filterRustHiddenLayerId = layerId;
      _filterRustHiddenLayerVisible = layer.visible;
      CanvasEngineFfi.instance.setLayerVisible(
        handle: _rustCanvasEngineHandle!,
        layerIndex: index,
        visible: false,
      );
    });
  }

  void _restoreRustLayerAfterFilterPreview() {
    _filterRustHideToken++;
    final String? layerId = _filterRustHiddenLayerId;
    if (layerId == null) {
      return;
    }
    if (_canUseRustCanvasEngine()) {
      final int? index = _rustCanvasLayerIndexForId(layerId);
      if (index != null) {
        CanvasEngineFfi.instance.setLayerVisible(
          handle: _rustCanvasEngineHandle!,
          layerIndex: index,
          visible: _filterRustHiddenLayerVisible,
        );
      }
    }
    _filterRustHiddenLayerId = null;
    _filterRustHiddenLayerVisible = false;
  }

  Future<void> invertActiveLayerColors() async {
    final l10n = context.l10n;
    if (_controller.frame == null && !_canUseRustCanvasEngine()) {
      _showFilterMessage(l10n.canvasNotReadyInvert);
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
      _showFilterMessage(l10n.layerLockedInvert);
      return;
    }

    if (_canUseRustCanvasEngine()) {
      final int? handle = _rustCanvasEngineHandle;
      final int? layerIndex = _rustCanvasLayerIndexForId(activeLayerId);
      if (handle == null || layerIndex == null) {
        _showFilterMessage(l10n.cannotLocateLayer);
        return;
      }
      final bool applied = await CanvasEngineFfi.instance.applyFilter(
        handle: handle,
        layerIndex: layerIndex,
        filterType: _kFilterTypeInvert,
      );
      if (!applied) {
        _showFilterMessage(l10n.filterApplyFailed);
        return;
      }
      _recordRustHistoryAction(layerId: activeLayerId);
      if (mounted) {
        setState(() {});
      }
      _markDirty();
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
    if (data.bitmap == null && data.fillColor == null) {
      _showFilterMessage(l10n.layerEmptyInvert);
      return;
    }

    Uint8List? bitmap = data.bitmap != null
        ? Uint8List.fromList(data.bitmap!)
        : null;
    Color? fillColor = data.fillColor;
    bool bitmapModified = false;
    if (bitmap != null) {
      bool hasCoverage = false;
      for (int i = 0; i < bitmap.length; i += 4) {
        final int alpha = bitmap[i + 3];
        if (alpha == 0) {
          continue;
        }
        hasCoverage = true;
        bitmap[i] = 255 - bitmap[i];
        bitmap[i + 1] = 255 - bitmap[i + 1];
        bitmap[i + 2] = 255 - bitmap[i + 2];
      }
      if (hasCoverage) {
        bitmapModified = true;
      } else {
        bitmap = null;
      }
    }

    bool fillChanged = false;
    if (fillColor != null) {
      final Color inverted = Color.fromARGB(
        fillColor.alpha,
        255 - fillColor.red,
        255 - fillColor.green,
        255 - fillColor.blue,
      );
      if (inverted != fillColor) {
        fillColor = inverted;
        fillChanged = true;
      }
    }

    if (!bitmapModified && !fillChanged) {
      _showFilterMessage(l10n.noPixelsToInvert);
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

  void showLayerAntialiasPanel() {
    if (!_ensureAntialiasLayerReady()) {
      return;
    }
    setState(() {
      if (_antialiasCardOffset == Offset.zero) {
        _antialiasCardOffset = _initialAntialiasCardOffset();
      } else {
        _antialiasCardOffset = _clampAntialiasCardOffset(
          _antialiasCardOffset,
          _antialiasCardSize,
        );
      }
      _antialiasCardVisible = true;
    });
  }

  void hideLayerAntialiasPanel() {
    if (!_antialiasCardVisible) {
      return;
    }
    setState(() {
      _antialiasCardVisible = false;
    });
  }

  void _handleAntialiasLevelChanged(int level) {
    final int clamped = level.clamp(0, 9);
    if (_antialiasCardLevel == clamped) {
      return;
    }
    setState(() {
      _antialiasCardLevel = clamped;
    });
  }

  void _applyAntialiasFromCard() async {
    if (!_ensureAntialiasLayerReady()) {
      return;
    }
    final bool applied = await applyLayerAntialiasLevel(_antialiasCardLevel);
    if (!applied) {
      _showFilterMessage('无法对当前图层应用边缘柔化，图层可能为空或已锁定。');
      return;
    }
    setState(() {
      _antialiasCardVisible = false;
    });
  }

  void _updateAntialiasCardOffset(Offset delta) {
    if (!_antialiasCardVisible) {
      return;
    }
    setState(() {
      _antialiasCardOffset = _clampAntialiasCardOffset(
        _antialiasCardOffset + delta,
        _antialiasCardSize,
      );
    });
  }

  void _handleAntialiasCardSizeChanged(Size size) {
    if (_antialiasCardSize == size) {
      return;
    }
    setState(() {
      _antialiasCardSize = size;
      _antialiasCardOffset = _clampAntialiasCardOffset(
        _antialiasCardOffset,
        size,
      );
    });
  }

  bool _isInsideAntialiasCardArea(Offset workspacePosition) {
    if (!_antialiasCardVisible) {
      return false;
    }
    final Size size =
        _antialiasCardSize ??
        const Size(_kAntialiasPanelWidth, _kAntialiasPanelMinHeight);
    final Rect rect = Rect.fromLTWH(
      _antialiasCardOffset.dx,
      _antialiasCardOffset.dy,
      size.width,
      size.height,
    );
    return rect.contains(workspacePosition);
  }

  bool _ensureAntialiasLayerReady() {
    final BitmapLayerState? layer = _currentActiveLayer();
    if (layer == null) {
      _showFilterMessage('请先选择一个可编辑的图层。');
      return false;
    }
    if (layer.locked) {
      _showFilterMessage('当前图层已锁定，无法应用边缘柔化。');
      return false;
    }
    return true;
  }

  Offset _initialAntialiasCardOffset() {
    return _workspacePanelSpawnOffset(
      this,
      panelWidth: _kAntialiasPanelWidth,
      panelHeight: _kAntialiasPanelMinHeight,
    );
  }

  Offset _clampAntialiasCardOffset(Offset value, Size? size) {
    if (_workspaceSize.isEmpty) {
      return value;
    }
    final double width = size?.width ?? _kAntialiasPanelWidth;
    final double height = size?.height ?? _kAntialiasPanelMinHeight;
    const double margin = 12.0;
    final double minX = margin;
    final double minY = margin;
    final double maxX = math.max(minX, _workspaceSize.width - width - margin);
    final double maxY = math.max(minY, _workspaceSize.height - height - margin);
    return Offset(value.dx.clamp(minX, maxX), value.dy.clamp(minY, maxY));
  }

  Future<void> showColorRangeCard() async {
    if (!isBoardReady) {
      _showFilterMessage('画布尚未准备好，无法统计色彩范围。');
      return;
    }
    final String? activeLayerId = _activeLayerId;
    if (activeLayerId == null) {
      _showFilterMessage('请先选择一个可编辑的图层。');
      return;
    }
    final BitmapLayerState? layer = _layerById(activeLayerId);
    if (layer == null) {
      _showFilterMessage('无法定位当前图层。');
      return;
    }
    if (layer.locked) {
      _showFilterMessage('当前图层已锁定，无法设置色彩范围。');
      return;
    }
    if (_colorRangeLoading) {
      setState(() {
        _colorRangeCardVisible = true;
      });
      return;
    }
    await _controller.waitForPendingWorkerTasks();
    final List<CanvasLayerData> snapshot = _controller.snapshotLayers();
    final int layerIndex = snapshot.indexWhere(
      (item) => item.id == activeLayerId,
    );
    if (layerIndex < 0) {
      _showFilterMessage('无法定位当前图层。');
      return;
    }
    final CanvasLayerData activeLayer = snapshot[layerIndex];
    final bool useRust = _canUseRustCanvasEngine();
    Uint8List? rustBitmap;
    Uint32List? rustPixels;
    int rustWidth = 0;
    int rustHeight = 0;
    if (useRust) {
      final int? handle = _rustCanvasEngineHandle;
      final int? rustLayerIndex = _rustCanvasLayerIndexForId(activeLayerId);
      final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
      final int width = engineSize.width.round();
      final int height = engineSize.height.round();
      if (handle != null && rustLayerIndex != null && width > 0 && height > 0) {
        final Uint32List? sourcePixels = await CanvasEngineFfi.instance.readLayer(
          handle: handle,
          layerIndex: rustLayerIndex,
          width: width,
          height: height,
        );
        if (sourcePixels != null && sourcePixels.length == width * height) {
          rustPixels = sourcePixels;
          rustBitmap = this._argbPixelsToRgba(sourcePixels);
          rustWidth = width;
          rustHeight = height;
        }
      }
      if (rustPixels == null) {
        _showFilterMessage('画布尚未准备好，无法设置色彩范围。');
        return;
      }
    }
    final bool hasBitmap = useRust
        ? rustBitmap != null &&
            rustBitmap.isNotEmpty &&
            rustWidth > 0 &&
            rustHeight > 0
        : activeLayer.bitmap != null &&
            activeLayer.bitmap!.isNotEmpty &&
            (activeLayer.bitmapWidth ?? 0) > 0 &&
            (activeLayer.bitmapHeight ?? 0) > 0;
    final Color? fillColor = activeLayer.fillColor;
    final bool hasFill = !useRust && fillColor != null && fillColor.alpha != 0;
    if (!hasBitmap && !hasFill) {
      _showFilterMessage('当前图层为空，无法设置色彩范围。');
      return;
    }
    _teardownColorRangeSession();
    final _ColorRangeSession session = _ColorRangeSession(
      layerId: activeLayerId,
      originalLayers: snapshot,
      activeLayerIndex: layerIndex,
    );
    if (useRust) {
      session
        ..rustBitmap = rustBitmap
        ..rustPixels = rustPixels
        ..rustWidth = rustWidth
        ..rustHeight = rustHeight;
    }
    _colorRangeSession = session;
    _colorRangePreviewToken++;
    _colorRangePreviewScheduled = false;
    _colorRangePreviewInFlight = false;
    _colorRangePreviewDebounceTimer?.cancel();
    _colorRangePreviewDebounceTimer = null;
    _colorRangeApplying = false;
    Offset nextOffset = _colorRangeCardOffset;
    if (nextOffset == Offset.zero) {
      nextOffset = _initialColorRangeCardOffset();
    } else {
      nextOffset = _clampColorRangeCardOffset(
        _colorRangeCardOffset,
        _colorRangeCardSize,
      );
    }
    setState(() {
      _colorRangeCardOffset = nextOffset;
      _colorRangeCardVisible = true;
      _colorRangeLoading = true;
    });
    final int count = useRust
        ? await _computeLayerColorCountFromPixels(rustBitmap, null)
        : await _computeLayerColorCount(activeLayer);
    if (!mounted || _colorRangeSession?.layerId != activeLayerId) {
      return;
    }
    if (count <= 0) {
      setState(() {
        _colorRangeLoading = false;
        _colorRangeCardVisible = false;
      });
      _showFilterMessage('当前图层没有可处理的颜色。');
      _teardownColorRangeSession(restoreOriginal: false);
      return;
    }
    final int maxSelectable = math.min(
      _kColorRangeMaxSelectableColors,
      math.max(1, count),
    );
    setState(() {
      _colorRangeTotalColors = count;
      final int previous = _colorRangeSelectedColors;
      _colorRangeSelectedColors = previous > 0
          ? previous.clamp(1, maxSelectable)
          : maxSelectable;
      _colorRangeLoading = false;
    });
    _scheduleColorRangePreview(immediate: true);
  }

  void hideColorRangeCard() {
    _cancelColorRangeEditing();
  }

  void _updateColorRangeCardOffset(Offset delta) {
    if (!_colorRangeCardVisible) {
      return;
    }
    setState(() {
      _colorRangeCardOffset = _clampColorRangeCardOffset(
        _colorRangeCardOffset + delta,
        _colorRangeCardSize,
      );
    });
  }

  void _handleColorRangeCardSizeChanged(Size size) {
    if (_colorRangeCardSize == size) {
      return;
    }
    setState(() {
      _colorRangeCardSize = size;
      _colorRangeCardOffset = _clampColorRangeCardOffset(
        _colorRangeCardOffset,
        size,
      );
    });
  }

  void _updateColorRangeSelection(double value) {
    if (!_colorRangeCardVisible || _colorRangeSession == null) {
      return;
    }
    if (_colorRangeLoading || _colorRangeApplying) {
      return;
    }
    final int maxColors = _colorRangeMaxSelectable();
    final int clamped = value.round().clamp(1, maxColors);
    if (clamped == _colorRangeSelectedColors) {
      return;
    }
    setState(() {
      _colorRangeSelectedColors = clamped;
    });
    _scheduleColorRangePreview();
  }

  int _colorRangeMaxSelectable() {
    final int total = math.max(1, _colorRangeTotalColors);
    return math.min(_kColorRangeMaxSelectableColors, total);
  }

  void _resetColorRangeSelection() {
    if (_colorRangeSession == null || !_colorRangeCardVisible) {
      return;
    }
    final int target = _colorRangeMaxSelectable();
    if (_colorRangeSelectedColors == target && !_colorRangePreviewInFlight) {
      _scheduleColorRangePreview(immediate: true);
      return;
    }
    setState(() {
      _colorRangeSelectedColors = target;
    });
    _scheduleColorRangePreview(immediate: true);
  }

  void _scheduleColorRangePreview({bool immediate = false}) {
    if (_colorRangeSession == null ||
        !_colorRangeCardVisible ||
        _colorRangeLoading) {
      return;
    }
    _colorRangePreviewScheduled = true;
    _colorRangePreviewDebounceTimer?.cancel();
    if (immediate) {
      unawaited(_runColorRangePreview());
      return;
    }
    _colorRangePreviewDebounceTimer = Timer(
      _kColorRangePreviewDebounceDuration,
      () => unawaited(_runColorRangePreview()),
    );
  }

  Future<void> _runColorRangePreview() async {
    _colorRangePreviewDebounceTimer?.cancel();
    _colorRangePreviewDebounceTimer = null;
    if (_colorRangePreviewInFlight) {
      _colorRangePreviewScheduled = true;
      return;
    }
    final _ColorRangeSession? session = _colorRangeSession;
    if (session == null || !_colorRangeCardVisible) {
      _colorRangePreviewScheduled = false;
      return;
    }
    _colorRangePreviewScheduled = false;
    final int availableColors = math.max(1, _colorRangeTotalColors);
    final int targetColors = math.max(
      1,
      math.min(_colorRangeSelectedColors, _colorRangeMaxSelectable()),
    );
    if (targetColors >= availableColors) {
      _restoreColorRangePreviewToOriginal(session);
      if (mounted) {
        setState(() {});
      }
      return;
    }
    final int token = ++_colorRangePreviewToken;
    setState(() {
      _colorRangePreviewInFlight = true;
    });
    final bool useRust = session.usesRust && _canUseRustCanvasEngine();
    final CanvasLayerData baseLayer =
        session.originalLayers[session.activeLayerIndex];
    final Uint8List? baseBitmap =
        useRust ? session.rustBitmap : baseLayer.bitmap;
    final Color? baseFillColor = useRust ? null : baseLayer.fillColor;
    try {
      final _ColorRangeComputeResult result = await _generateColorRangeResult(
        baseBitmap,
        baseFillColor,
        targetColors,
      );
      if (!mounted ||
          token != _colorRangePreviewToken ||
          _colorRangeSession?.layerId != session.layerId) {
        return;
      }
      if (useRust) {
        final Uint8List? reduced = result.bitmap;
        final int? handle = _rustCanvasEngineHandle;
        final int? layerIndex = _rustCanvasLayerIndexForId(session.layerId);
        if (reduced != null &&
            handle != null &&
            layerIndex != null) {
          final bool applied = await CanvasEngineFfi.instance.writeLayer(
            handle: handle,
            layerIndex: layerIndex,
            pixels: this._rgbaToArgbPixels(reduced),
            recordUndo: false,
          );
          if (applied) {
            session.previewLayer ??=
                session.originalLayers[session.activeLayerIndex];
          }
        }
      } else {
        final CanvasLayerData adjusted = _buildColorRangeAdjustedLayer(
          baseLayer,
          result,
        );
        session.previewLayer = adjusted;
        _controller.replaceLayer(session.layerId, adjusted);
        _controller.setActiveLayer(session.layerId);
        setState(() {});
      }
    } catch (error, stackTrace) {
      debugPrint('Color range preview failed: $error\n$stackTrace');
      if (mounted) {
        _showFilterMessage('生成色彩范围预览失败，请重试。');
      }
    } finally {
      if (mounted) {
        setState(() {
          _colorRangePreviewInFlight = false;
        });
      } else {
        _colorRangePreviewInFlight = false;
      }
    }
    if (_colorRangePreviewScheduled) {
      unawaited(_runColorRangePreview());
    }
  }

  Future<void> _applyColorRangeSelection() async {
    final _ColorRangeSession? session = _colorRangeSession;
    if (session == null || _colorRangeLoading || !_colorRangeCardVisible) {
      return;
    }
    if (_colorRangeApplying) {
      return;
    }
    _colorRangePreviewDebounceTimer?.cancel();
    _colorRangePreviewDebounceTimer = null;
    _colorRangePreviewScheduled = false;
    _colorRangePreviewToken++;
    final int availableColors = math.max(1, _colorRangeTotalColors);
    final int targetColors = math.max(
      1,
      math.min(_colorRangeSelectedColors, _colorRangeMaxSelectable()),
    );
    final bool useRust = session.usesRust && _canUseRustCanvasEngine();
    if (targetColors >= availableColors) {
      _showFilterMessage('目标颜色数量不少于当前颜色数量，图层保持不变。');
      hideColorRangeCard();
      return;
    }
    setState(() {
      _colorRangeApplying = true;
    });
    try {
      // 确保撤销基于应用前的原始图层状态，而非预览态。
      _restoreColorRangePreviewToOriginal(session);
      if (useRust) {
        final Uint8List? baseBitmap = session.rustBitmap;
        final _ColorRangeComputeResult result = await _generateColorRangeResult(
          baseBitmap,
          null,
          targetColors,
        );
        if (!mounted) {
          return;
        }
        final Uint8List? reduced = result.bitmap;
        final int? handle = _rustCanvasEngineHandle;
        final int? layerIndex = _rustCanvasLayerIndexForId(session.layerId);
        final bool applied = reduced != null &&
            handle != null &&
            layerIndex != null
            ? await CanvasEngineFfi.instance.writeLayer(
                handle: handle,
                layerIndex: layerIndex,
                pixels: this._rgbaToArgbPixels(reduced),
                recordUndo: true,
              )
            : false;
        if (!applied) {
          throw StateError('Apply rust color range failed.');
        }
        _recordRustHistoryAction(layerId: session.layerId);
        _markDirty();
        setState(() {
          _colorRangeApplying = false;
          _colorRangeCardVisible = false;
        });
        _teardownColorRangeSession(restoreOriginal: false);
        return;
      }
      final List<CanvasLayerData> currentLayers = _controller.snapshotLayers();
      final int currentIndex = currentLayers.indexWhere(
        (CanvasLayerData item) => item.id == session.layerId,
      );
      if (currentIndex < 0) {
        throw StateError('无法定位当前图层。');
      }
      final CanvasLayerData baseLayer = currentLayers[currentIndex];
      final _ColorRangeComputeResult result = await _generateColorRangeResult(
        baseLayer.bitmap,
        baseLayer.fillColor,
        targetColors,
      );
      if (!mounted) {
        return;
      }
      await _pushUndoSnapshot();
      final CanvasLayerData adjusted = _buildColorRangeAdjustedLayer(
        baseLayer,
        result,
      );
      _controller.replaceLayer(session.layerId, adjusted);
      _controller.setActiveLayer(session.layerId);
      _markDirty();
      setState(() {
        _colorRangeApplying = false;
        _colorRangeCardVisible = false;
      });
      _teardownColorRangeSession(restoreOriginal: false);
    } catch (error, stackTrace) {
      debugPrint('Apply color range failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _colorRangeApplying = false;
        });
        _showFilterMessage('应用色彩范围失败，请重试。');
      }
    }
  }

  void _cancelColorRangeEditing() {
    _teardownColorRangeSession();
    if (mounted) {
      setState(() {
        _colorRangeCardVisible = false;
        _colorRangeLoading = false;
        _colorRangeApplying = false;
      });
    }
  }

  void _teardownColorRangeSession({bool restoreOriginal = true}) {
    _colorRangePreviewDebounceTimer?.cancel();
    _colorRangePreviewDebounceTimer = null;
    _colorRangePreviewScheduled = false;
    _colorRangePreviewToken++;
    final _ColorRangeSession? session = _colorRangeSession;
    if (restoreOriginal && session != null) {
      _restoreColorRangePreviewToOriginal(session);
    }
    _colorRangeSession = null;
    _colorRangePreviewInFlight = false;
  }

  void _restoreColorRangePreviewToOriginal(_ColorRangeSession session) {
    if (session.previewLayer == null) {
      return;
    }
    if (session.usesRust && _canUseRustCanvasEngine()) {
      final int? handle = _rustCanvasEngineHandle;
      final int? layerIndex = _rustCanvasLayerIndexForId(session.layerId);
      final Uint32List? pixels = session.rustPixels;
      if (handle != null && layerIndex != null && pixels != null) {
        unawaited(
          CanvasEngineFfi.instance.writeLayer(
            handle: handle,
            layerIndex: layerIndex,
            pixels: pixels,
            recordUndo: false,
          ),
        );
      }
      session.previewLayer = null;
      if (mounted) {
        setState(() {});
      }
      return;
    }
    final CanvasLayerData original =
        session.originalLayers[session.activeLayerIndex];
    _controller.replaceLayer(session.layerId, original);
    _controller.setActiveLayer(session.layerId);
    session.previewLayer = null;
    if (mounted) {
      setState(() {});
    }
  }

  bool _isInsideColorRangeCardArea(Offset workspacePosition) {
    if (!_colorRangeCardVisible) {
      return false;
    }
    final Size size =
        _colorRangeCardSize ??
        const Size(_kColorRangePanelWidth, _kColorRangePanelMinHeight);
    final Rect rect = Rect.fromLTWH(
      _colorRangeCardOffset.dx,
      _colorRangeCardOffset.dy,
      size.width,
      size.height,
    );
    return rect.contains(workspacePosition);
  }

  Offset _initialColorRangeCardOffset() {
    return _workspacePanelSpawnOffset(
      this,
      panelWidth: _kColorRangePanelWidth,
      panelHeight: _kColorRangePanelMinHeight,
      additionalDy: _antialiasCardVisible ? 32 : 0,
    );
  }

  Offset _clampColorRangeCardOffset(Offset value, Size? size) {
    if (_workspaceSize.isEmpty) {
      return value;
    }
    final double width = size?.width ?? _kColorRangePanelWidth;
    final double height = size?.height ?? _kColorRangePanelMinHeight;
    const double margin = 12.0;
    final double minX = margin;
    final double minY = margin;
    final double maxX = math.max(minX, _workspaceSize.width - width - margin);
    final double maxY = math.max(minY, _workspaceSize.height - height - margin);
    return Offset(value.dx.clamp(minX, maxX), value.dy.clamp(minY, maxY));
  }

  Future<int> _computeLayerColorCount(CanvasLayerData layer) async {
    final Uint8List? bitmap = layer.bitmap;
    final int? fillColor = layer.fillColor?.value;
    final bool hasFill = fillColor != null && ((fillColor >> 24) & 0xFF) != 0;
    if ((bitmap == null || bitmap.isEmpty) && !hasFill) {
      return 0;
    }
    try {
      return await compute(_countUniqueColorsForLayer, <Object?>[
        bitmap,
        fillColor,
      ]);
    } catch (_) {
      return _countUniqueColorsForLayer(<Object?>[bitmap, fillColor]);
    }
  }

  Future<int> _computeLayerColorCountFromPixels(
    Uint8List? bitmap,
    int? fillColor,
  ) async {
    final bool hasFill = fillColor != null && ((fillColor >> 24) & 0xFF) != 0;
    if ((bitmap == null || bitmap.isEmpty) && !hasFill) {
      return 0;
    }
    try {
      return await compute(_countUniqueColorsForLayer, <Object?>[
        bitmap,
        fillColor,
      ]);
    } catch (_) {
      return _countUniqueColorsForLayer(<Object?>[bitmap, fillColor]);
    }
  }
}
