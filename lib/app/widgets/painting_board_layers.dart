part of 'painting_board.dart';

const int _layerPreviewRasterHeight = 128;
const double _layerPreviewDisplayHeight = 28;
const double _layerPreviewAspectRatio = 16 / 9;
const double _layerPreviewDisplayWidth =
    _layerPreviewDisplayHeight * _layerPreviewAspectRatio;

mixin _PaintingBoardLayerMixin
    on _PaintingBoardBase, _PaintingBoardLayerTransformMixin {
  final TextEditingController _layerRenameController = TextEditingController();
  final FocusNode _layerRenameFocusNode = FocusNode();
  String? _renamingLayerId;
  final FlyoutController _layerContextMenuController = FlyoutController();
  final FlyoutController _blendModeFlyoutController = FlyoutController();
  bool? _rasterizeMenuEnabled;
  bool get rustLayerSupported => CanvasEngineFfi.instance.isSupported;

  List<CanvasLayerData> _buildInitialLayers() {
    final List<CanvasLayerData>? provided = widget.initialLayers;
    if (provided != null && provided.isNotEmpty) {
      return List<CanvasLayerData>.from(provided);
    }
    final int width = widget.settings.width.round();
    final int height = widget.settings.height.round();
    final Color background = widget.settings.backgroundColor;
    return <CanvasLayerData>[
      CanvasLayerData(id: generateLayerId(), name: '背景', fillColor: background),
      CanvasLayerData(
        id: generateLayerId(),
        name: '图层 2',
        bitmap: Uint8List(width * height * 4),
        bitmapWidth: width,
        bitmapHeight: height,
      ),
    ];
  }

  Color get _backgroundPreviewColor {
    if (_layers.isEmpty) {
      return widget.settings.backgroundColor;
    }
    final BitmapLayerState baseLayer = _layers.first;
    final Uint32List pixels = baseLayer.surface.pixels;
    if (pixels.isNotEmpty && (pixels[0] >> 24) != 0) {
      return BitmapSurface.decodeColor(pixels[0]);
    }
    return widget.settings.backgroundColor;
  }

  void _handleLayerVisibilityChanged(String id, bool visible) async {
    BitmapLayerState? target;
    for (final BitmapLayerState layer in _layers) {
      if (layer.id == id) {
        target = layer;
        break;
      }
    }
    if (target != null && target.visible == visible) {
      return;
    }
    await _pushUndoSnapshot();
    _controller.updateLayerVisibility(id, visible);
    _rustCanvasSetLayerVisibleById(id, visible);
    setState(() {});
    _markDirty();
  }

  void _handleLayerSelected(String id) {
    if (_guardTransformInProgress(message: context.l10n.completeTransformFirst)) {
      return;
    }
    _layerOpacityPreviewReset(this);
    _controller.setActiveLayer(id);
    _rustCanvasSetActiveLayerById(id);
    setState(() {});
    _syncRasterizeMenuAvailability();
  }

  void _handleLayerRenameFocusChange() {
    if (!_layerRenameFocusNode.hasFocus && _renamingLayerId != null) {
      _finalizeLayerRename();
    }
  }

  Future<void> _beginLayerRename(BitmapLayerState layer) async {
    if (layer.locked) {
      return;
    }

    final BitmapLayerState? target = _layerById(layer.id);
    if (target == null || target.locked) {
      return;
    }

    final TextEditingController controller = TextEditingController(
      text: target.name,
    );
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    String? errorText;

    final String? result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return StatefulBuilder(
          builder: (context, setState) {
            void submit() {
              final String trimmed = controller.text.trim();
              if (trimmed.isEmpty) {
                setState(() => errorText = l10n.nameCannotBeEmpty);
                return;
              }
              Navigator.of(dialogContext).pop(trimmed);
            }

            return MisarinDialog(
              title: Text(l10n.rename),
              contentWidth: 360,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextBox(
                    controller: controller,
                    autofocus: true,
                    onChanged: (_) {
                      if (errorText != null) {
                        setState(() => errorText = null);
                      }
                    },
                    onSubmitted: (_) => submit(),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Color(0xFFD13438)),
                    ),
                  ],
                ],
              ),
              actions: [
                Button(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton(onPressed: submit, child: Text(l10n.rename)),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (!mounted) {
      return;
    }
    final String nextName = result?.trim() ?? '';
    if (nextName.isEmpty) {
      return;
    }

    final BitmapLayerState? refreshed = _layerById(layer.id);
    if (refreshed == null || refreshed.locked || refreshed.name == nextName) {
      return;
    }

    await _pushUndoSnapshot();
    _controller.renameLayer(layer.id, nextName);
    setState(() {});
    _markDirty();
  }

  void _finalizeLayerRename({bool cancel = false}) async {
    final String? targetId = _renamingLayerId;
    if (targetId == null) {
      return;
    }
    final String nextName = _layerRenameController.text.trim();
    setState(() {
      _renamingLayerId = null;
    });
    if (cancel || nextName.isEmpty) {
      return;
    }
    BitmapLayerState? target;
    for (final BitmapLayerState layer in _layers) {
      if (layer.id == targetId) {
        target = layer;
        break;
      }
    }
    if (target == null || target.name == nextName) {
      return;
    }
    await _pushUndoSnapshot();
    _controller.renameLayer(target.id, nextName);
    setState(() {});
    _markDirty();
  }

  void _handleAddLayer() async {
    await _pushUndoSnapshot();
    final String? insertAbove =
        _canUseRustCanvasEngine()
            ? (_layers.isEmpty ? null : _layers.last.id)
            : _activeLayerId;
    _controller.addLayer(aboveLayerId: insertAbove);
    setState(() {});
    _markDirty();
    _syncRustCanvasLayersToEngine();
  }

  void _handleRemoveLayer(String id) async {
    if (_layers.length <= 1) {
      return;
    }
    if (_canUseRustCanvasEngine()) {
      await _controller.waitForPendingWorkerTasks();
      if (!await _syncAllLayerPixelsFromRust()) {
        _showRustCanvasMessage('Rust 画布同步图层失败。');
        return;
      }
    }
    await _pushUndoSnapshot(rustPixelsSynced: _canUseRustCanvasEngine());
    _controller.removeLayer(id);
    setState(() {});
    _markDirty();
    _syncRustCanvasLayersToEngine();
    if (_canUseRustCanvasEngine()) {
      if (!await _syncAllLayerPixelsToRust()) {
        _showRustCanvasMessage('Rust 画布写入图层失败。');
      }
    }
  }

  Widget _buildAddLayerButton() {
    return Button(
      onPressed: _handleAddLayer,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.add, size: 14),
          const SizedBox(width: 6),
          Text(context.l10n.newLayer),
        ],
      ),
    );
  }

  void _handleLayerReorder(int oldIndex, int newIndex) async {
    final int length = _layers.length;
    if (length <= 1) {
      return;
    }
    if (oldIndex < 0 || oldIndex >= length || newIndex < 0) {
      return;
    }
    int targetIndex = newIndex;
    if (targetIndex > length) {
      targetIndex = length;
    }
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    targetIndex = targetIndex.clamp(0, length - 1);
    final int actualOldIndex = length - 1 - oldIndex;
    int actualNewIndex = length - 1 - targetIndex;
    if (actualNewIndex > actualOldIndex) {
      actualNewIndex += 1;
    }
    if (actualOldIndex == actualNewIndex) {
      return;
    }
    if (_canUseRustCanvasEngine()) {
      await _controller.waitForPendingWorkerTasks();
      if (!await _syncAllLayerPixelsFromRust()) {
        _showRustCanvasMessage('Rust 画布同步图层失败。');
        return;
      }
    }
    await _pushUndoSnapshot(rustPixelsSynced: _canUseRustCanvasEngine());
    _controller.reorderLayer(actualOldIndex, actualNewIndex);
    if (_canUseRustCanvasEngine()) {
      CanvasEngineFfi.instance.reorderLayer(
        handle: _rustCanvasEngineHandle!,
        fromIndex: actualOldIndex,
        toIndex: actualNewIndex,
      );
      final String? activeLayerId = _activeLayerId;
      if (activeLayerId != null) {
        _rustCanvasSetActiveLayerById(activeLayerId);
      }
    }
    setState(() {});
    _markDirty();
  }

  BitmapLayerState? _currentActiveLayer() {
    final String? activeId = _activeLayerId;
    if (activeId == null) {
      return null;
    }
    for (final BitmapLayerState layer in _layers) {
      if (layer.id == activeId) {
        return layer;
      }
    }
    return null;
  }

  Future<bool> rasterizeActiveTextLayer() async {
    final BitmapLayerState? layer = _currentActiveLayer();
    if (layer == null) {
      return false;
    }
    return _rasterizeTextLayer(layer);
  }

  bool get canRasterizeActiveLayer {
    final BitmapLayerState? layer = _currentActiveLayer();
    if (layer == null) {
      return false;
    }
    return layer.text != null && !layer.locked;
  }

  Future<bool> _rasterizeTextLayer(BitmapLayerState layer) async {
    if (layer.text == null || layer.locked) {
      return false;
    }
    await _pushUndoSnapshot();
    _controller.rasterizeTextLayer(layer.id);
    setState(() {});
    _markDirty();
    _syncRasterizeMenuAvailability();
    return true;
  }

  void _syncRasterizeMenuAvailability() {
    final bool next = canRasterizeActiveLayer;
    if (_rasterizeMenuEnabled == next) {
      return;
    }
    _rasterizeMenuEnabled = next;
    MenuActionDispatcher.instance.refresh();
  }

  void _handleLayerOpacityChangeStart(double _) {
    final BitmapLayerState? layer = _currentActiveLayer();
    if (layer == null) {
      return;
    }
    if (_layerOpacityGestureActive && _layerOpacityGestureLayerId == layer.id) {
      return;
    }
    _layerOpacityGestureActive = true;
    _layerOpacityGestureLayerId = layer.id;
    _layerOpacityUndoOriginalValue = layer.opacity;
    if (_canUseRustCanvasEngine()) {
      _layerOpacityPreviewReset(this);
      return;
    }
    _ensureLayerOpacityPreview(layer);
  }

  void _handleLayerOpacityChangeEnd(double value) {
    _layerOpacityGestureActive = false;
    final String? targetLayerId = _layerOpacityGestureLayerId;
    final double? originalValue = _layerOpacityUndoOriginalValue;
    _layerOpacityGestureLayerId = null;
    _layerOpacityUndoOriginalValue = null;
    final double clampedValue = value.clamp(0.0, 1.0);
    final bool applied = _applyLayerOpacityValue(targetLayerId, clampedValue);
    if (_canUseRustCanvasEngine()) {
      if (targetLayerId != null && originalValue != null) {
        unawaited(_commitLayerOpacityUndoSnapshot(targetLayerId, originalValue));
      }
      return;
    }
    final bool shouldHoldPreview =
        applied &&
        targetLayerId != null &&
        _layerOpacityPreviewActive &&
        _layerOpacityPreviewLayerId == targetLayerId &&
        _layerOpacityPreviewActiveLayerImage != null;
    if (shouldHoldPreview) {
      _layerOpacityPreviewAwaitedGeneration =
          _controller.frame?.generation ?? -1;
      if (_layerOpacityPreviewValue == null ||
          (_layerOpacityPreviewValue! - clampedValue).abs() >= 1e-4) {
        setState(() {
          _layerOpacityPreviewValue = clampedValue;
        });
      }
    } else {
      _layerOpacityPreviewDeactivate(this, notifyListeners: true);
    }
    if (targetLayerId != null && originalValue != null) {
      unawaited(_commitLayerOpacityUndoSnapshot(targetLayerId, originalValue));
    }
  }

  void _handleLayerOpacityChanged(double value) {
    final BitmapLayerState? layer = _currentActiveLayer();
    if (layer == null) {
      return;
    }
    if (_canUseRustCanvasEngine()) {
      if (!_layerOpacityGestureActive || _layerOpacityGestureLayerId != layer.id) {
        _layerOpacityGestureActive = true;
        _layerOpacityGestureLayerId = layer.id;
        _layerOpacityUndoOriginalValue = layer.opacity;
      }
      _applyLayerOpacityValue(layer.id, value);
      return;
    }
    _ensureLayerOpacityPreview(layer);
    final double clamped = value.clamp(0.0, 1.0);
    if (_layerOpacityPreviewValue == null ||
        (_layerOpacityPreviewValue! - clamped).abs() >= 1e-4) {
      setState(() {
        _layerOpacityPreviewValue = clamped;
      });
    }
  }

  bool _applyLayerOpacityValue(String? layerId, double value) {
    if (layerId == null) {
      return false;
    }
    final BitmapLayerState? layer = _layerById(layerId);
    if (layer == null) {
      return false;
    }
    final double clamped = value.clamp(0.0, 1.0);
    if ((layer.opacity - clamped).abs() < 1e-4) {
      return false;
    }
    _controller.setLayerOpacity(layerId, clamped);
    _rustCanvasSetLayerOpacityById(layerId, clamped);
    setState(() {});
    _markDirty();
    return true;
  }

  void _ensureLayerOpacityPreview(BitmapLayerState layer) {
    bool needsImages =
        _layerOpacityPreviewLayerId != layer.id ||
            _layerOpacityPreviewActiveLayerImage == null;
    if (!needsImages) {
      final int currentSignature = _layerOpacityPreviewSignature(_layers);
      needsImages = _layerOpacityPreviewCapturedSignature == null ||
          _layerOpacityPreviewCapturedSignature != currentSignature;
    }
    _layerOpacityPreviewLayerId = layer.id;
    _layerOpacityPreviewHasVisibleLowerLayers = _hasVisibleLayersBelow(layer);
    if (!_layerOpacityPreviewActive) {
      _layerOpacityPreviewActive = true;
    }
    _layerOpacityPreviewValue ??= layer.opacity.clamp(0.0, 1.0);
    setState(() {});
    if (needsImages) {
      final int requestId = ++_layerOpacityPreviewRequestId;
      unawaited(_loadLayerOpacityPreviewImages(layer.id, requestId));
    }
  }

  bool _hasVisibleLayersBelow(BitmapLayerState target) {
    for (final BitmapLayerState layer in _layers) {
      if (layer.id == target.id) {
        break;
      }
      if (layer.visible && layer.opacity > 1e-4) {
        return true;
      }
    }
    return false;
  }

  Future<void> _loadLayerOpacityPreviewImages(
    String layerId,
    int requestId,
  ) async {
    final List<BitmapLayerState> snapshot = _layers.toList();
    _LayerPreviewImages previews;
    try {
      previews = await _captureLayerPreviewImages(
        controller: _controller,
        layers: snapshot,
        activeLayerId: layerId,
        captureActiveLayerAtFullOpacity: true,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to capture opacity preview: $error');
      debugPrint('$stackTrace');
      return;
    }
    if (!mounted ||
        requestId != _layerOpacityPreviewRequestId ||
        _layerOpacityPreviewLayerId != layerId) {
      previews.dispose();
      return;
    }
    _layerOpacityPreviewDisposeImages(this);
    _layerOpacityPreviewBackground = previews.background;
    _layerOpacityPreviewActiveLayerImage = previews.active;
    _layerOpacityPreviewForeground = previews.foreground;
    _layerOpacityPreviewCapturedSignature =
        _layerOpacityPreviewSignature(snapshot);
    setState(() {});
  }

  Future<void> _commitLayerOpacityUndoSnapshot(
    String layerId,
    double originalOpacity,
  ) async {
    try {
      final _CanvasHistoryEntry base = await _createHistoryEntry();
      final List<CanvasLayerData> layers =
          List<CanvasLayerData>.from(base.layers);
      final int index = layers.indexWhere((layer) => layer.id == layerId);
      if (index < 0) {
        return;
      }
      layers[index] = layers[index].copyWith(
        opacity: originalOpacity,
        cloneBitmap: false,
      );
      await _pushUndoSnapshot(
        entry: _CanvasHistoryEntry(
          layers: layers,
          backgroundColor: base.backgroundColor,
          activeLayerId: base.activeLayerId,
          selectionShape: base.selectionShape,
          selectionMask: base.selectionMask,
          selectionPath: base.selectionPath != null
              ? (Path()..addPath(base.selectionPath!, Offset.zero))
              : null,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to capture opacity undo snapshot: $error');
      debugPrint('$stackTrace');
    }
  }

  void _applyLayerLockedState(BitmapLayerState layer, bool locked) async {
    if (layer.locked == locked) {
      return;
    }
    if (locked && _renamingLayerId == layer.id) {
      _finalizeLayerRename(cancel: true);
    }
    await _pushUndoSnapshot();
    _controller.setLayerLocked(layer.id, locked);
    setState(() {});
  }

  void _updateActiveLayerLocked(bool locked) {
    final BitmapLayerState? layer = _currentActiveLayer();
    if (layer == null) {
      return;
    }
    _applyLayerLockedState(layer, locked);
  }

  void _handleLayerLockToggle(BitmapLayerState layer) {
    _applyLayerLockedState(layer, !layer.locked);
  }

  BitmapLayerState? _layerById(String id) {
    for (final BitmapLayerState candidate in _layers) {
      if (candidate.id == id) {
        return candidate;
      }
    }
    return null;
  }

  bool _canMergeLayerDown(BitmapLayerState layer) {
    if (layer.locked) {
      return false;
    }
    final int index = _layers.indexWhere(
      (candidate) => candidate.id == layer.id,
    );
    if (index <= 0) {
      return false;
    }
    final BitmapLayerState below = _layers[index - 1];
    return !below.locked;
  }

  void _handleMergeLayerDown(BitmapLayerState layer) async {
    if (!_canMergeLayerDown(layer)) {
      return;
    }
    if (!_canUseRustCanvasEngine()) {
      _showRustCanvasMessage('Rust 画布尚未准备好。');
      return;
    }
    await _controller.waitForPendingWorkerTasks();
    if (!await _syncAllLayerPixelsFromRust()) {
      _showRustCanvasMessage('Rust 画布同步图层失败。');
      return;
    }
    await _pushUndoSnapshot(rustPixelsSynced: true);
    if (!_controller.mergeLayerDown(layer.id)) {
      return;
    }
    _syncRustCanvasLayersToEngine();
    if (!await _syncAllLayerPixelsToRust()) {
      _showRustCanvasMessage('Rust 画布写入图层失败。');
    }
    setState(() {});
    _markDirty();
  }

  void _handleLayerClippingToggle(BitmapLayerState layer) async {
    if (layer.locked) {
      return;
    }
    final bool nextValue = !layer.clippingMask;
    await _pushUndoSnapshot();
    _controller.setLayerClippingMask(layer.id, nextValue);
    _rustCanvasSetLayerClippingById(layer.id, nextValue);
    setState(() {});
    _markDirty();
  }

  void _handleDuplicateLayer(BitmapLayerState layer) async {
    if (_canUseRustCanvasEngine()) {
      _showRustCanvasMessage('Rust 画布目前暂不支持复制图层。');
      return;
    }
    final CanvasLayerData? snapshot = _controller.buildClipboardLayer(layer.id);
    if (snapshot == null) {
      return;
    }
    final String newId = generateLayerId();
    final String nextName = layer.name.isEmpty
        ? context.l10n.duplicateLayer
        : context.l10n.layerCopyName(layer.name);
    final CanvasLayerData duplicate = snapshot.copyWith(
      id: newId,
      name: nextName,
      visible: true,
      locked: false,
      clippingMask: layer.clippingMask,
    );
    await _pushUndoSnapshot();
    _controller.insertLayerFromData(duplicate, aboveLayerId: layer.id);
    _controller.setActiveLayer(newId);
    setState(() {});
    _markDirty();
  }

  void _showLayerContextMenu(BitmapLayerState layer, Offset position) {
    _handleLayerSelected(layer.id);
    _layerContextMenuController.showFlyout(
      position: position,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      builder: (context) {
        final BitmapLayerState? target = _layerById(layer.id);
        if (target == null) {
          return const SizedBox.shrink();
        }
        return MenuFlyout(items: _buildLayerContextMenuItems(target));
      },
    );
  }

  List<MenuFlyoutItemBase> _buildLayerContextMenuItems(BitmapLayerState layer) {
    final bool canDelete = _layers.length > 1 && !layer.locked;
    final bool canMerge = _canMergeLayerDown(layer);
    final bool isLocked = layer.locked;
    final bool isVisible = layer.visible;
    final bool isClipping = layer.clippingMask;
    final l10n = context.l10n;

    final List<MenuFlyoutItemBase> items = <MenuFlyoutItemBase>[
      MenuFlyoutItem(
        leading: Icon(isLocked ? FluentIcons.lock : FluentIcons.unlock),
        text: Text(isLocked ? l10n.unlockLayer : l10n.lockLayer),
        onPressed: () => _handleLayerLockToggle(layer),
      ),
      MenuFlyoutItem(
        leading: const Icon(FluentIcons.download),
        text: Text(l10n.mergeDown),
        onPressed: canMerge ? () => _handleMergeLayerDown(layer) : null,
      ),
      MenuFlyoutItem(
        leading: Icon(
          isClipping ? FluentIcons.subtract_shape : FluentIcons.subtract_shape,
        ),
        text: Text(isClipping ? l10n.releaseClippingMask : l10n.createClippingMask),
        onPressed: isLocked ? null : () => _handleLayerClippingToggle(layer),
      ),
      MenuFlyoutItem(
        leading: Icon(isVisible ? FluentIcons.hide3 : FluentIcons.view),
        text: Text(isVisible ? l10n.hide : l10n.show),
        onPressed: () =>
            _handleLayerVisibilityChanged(layer.id, !layer.visible),
      ),
      MenuFlyoutItem(
        leading: const Icon(FluentIcons.delete),
        text: Text(l10n.delete),
        onPressed: canDelete ? () => _handleRemoveLayer(layer.id) : null,
      ),
      MenuFlyoutItem(
        leading: const Icon(FluentIcons.copy),
        text: Text(l10n.duplicate),
        onPressed: () => _handleDuplicateLayer(layer),
      ),
    ];
    if (layer.text != null) {
      items.insert(
        0,
        MenuFlyoutItem(
          leading: const Icon(FluentIcons.font),
          text: Text(l10n.rasterizeTextLayer),
          onPressed: layer.locked
              ? null
              : () async {
                  await _rasterizeTextLayer(layer);
                },
        ),
      );
    }
    return items;
  }

  void _updateActiveLayerClipping(bool clipping) async {
    final BitmapLayerState? layer = _currentActiveLayer();
    if (layer == null || layer.clippingMask == clipping) {
      return;
    }
    await _pushUndoSnapshot();
    _controller.setLayerClippingMask(layer.id, clipping);
    _rustCanvasSetLayerClippingById(layer.id, clipping);
    setState(() {});
  }

  void _updateActiveLayerBlendMode(CanvasLayerBlendMode mode) async {
    final BitmapLayerState? layer = _currentActiveLayer();
    if (layer == null || layer.blendMode == mode) {
      return;
    }
    await _pushUndoSnapshot();
    _controller.setLayerBlendMode(layer.id, mode);
    _rustCanvasSetLayerBlendModeById(layer.id, mode);
    setState(() {});
  }

  void _toggleBlendModeFlyout(CanvasLayerBlendMode selected) {
    _toggleBlendModeFlyoutImpl(selected);
  }

  Widget _buildBlendModeDropdown({
    required FluentThemeData theme,
    required CanvasLayerBlendMode mode,
    required bool isLocked,
  }) {
    return _buildBlendModeDropdownImpl(
      theme: theme,
      mode: mode,
      isLocked: isLocked,
    );
  }

  Future<bool> applyLayerAntialiasLevel(int level) async {
    final BitmapLayerState? layer = _currentActiveLayer();
    if (layer == null || layer.locked) {
      return false;
    }
    final int clamped = level.clamp(0, 9);
    if (_canUseRustCanvasEngine()) {
      final int? handle = _rustCanvasEngineHandle;
      final String? layerId = _activeLayerId;
      if (handle == null || layerId == null) {
        return false;
      }
      final int? index = _rustCanvasLayerIndexForId(layerId);
      if (index == null) {
        return false;
      }
      final bool applied = await CanvasEngineFfi.instance.applyAntialias(
        handle: handle,
        layerIndex: index,
        level: clamped,
      );
      if (applied) {
        _recordRustHistoryAction(layerId: layerId);
        setState(() {});
        _markDirty();
      }
      return applied;
    }
    if (!await _controller.applyAntialiasToActiveLayer(
      clamped,
      previewOnly: true,
    )) {
      return false;
    }
    await _pushUndoSnapshot();
    await _controller.applyAntialiasToActiveLayer(clamped);
    setState(() {});
    _markDirty();
    return true;
  }

  Widget _buildPanelDivider(FluentThemeData theme) {
    return _buildPanelDividerImpl(theme);
  }

  Widget _buildInlineLayerRenameField(
    FluentThemeData theme, {
    required bool isActive,
    required String layerId,
    TextStyle? styleOverride,
  }) {
    return _buildInlineLayerRenameFieldImpl(
      theme,
      isActive: isActive,
      layerId: layerId,
      styleOverride: styleOverride,
    );
  }

  Widget? _buildLayerControlStrip(
    FluentThemeData theme,
    BitmapLayerState? activeLayer,
  ) {
    return _buildLayerControlStripImpl(theme, activeLayer);
  }

  Map<String, bool> _computeLayerTileDimStates() {
    return _computeLayerTileDimStatesImpl();
  }

  void _pruneLayerPreviewCache(Iterable<BitmapLayerState> layers) {
    _pruneLayerPreviewCacheImpl(layers);
  }

  void _ensureLayerPreview(BitmapLayerState layer) {
    _ensureLayerPreviewImpl(layer);
  }

  ui.Image? _layerPreviewImage(String layerId) {
    return _layerPreviewImageImpl(layerId);
  }

  Future<void> _captureLayerPreviewThumbnail({
    required String layerId,
    required BitmapSurface surface,
    required int revision,
    required int requestId,
  }) async {
    await _captureLayerPreviewThumbnailImpl(
      layerId: layerId,
      surface: surface,
      revision: revision,
      requestId: requestId,
    );
  }

  void _applyLayerPreviewResult({
    required String layerId,
    required int revision,
    required int requestId,
    ui.Image? image,
  }) {
    _applyLayerPreviewResultImpl(
      layerId: layerId,
      revision: revision,
      requestId: requestId,
      image: image,
    );
  }

  _LayerPreviewPixels? _buildLayerPreviewPixels(BitmapSurface surface) {
    return _buildLayerPreviewPixelsImpl(surface);
  }

  void _disposeLayerPreviewCache() {
    _disposeLayerPreviewCacheImpl();
  }

  Widget _buildLayerPanelContent(FluentThemeData theme) {
    return _buildLayerPanelContentImpl(theme);
  }
}
