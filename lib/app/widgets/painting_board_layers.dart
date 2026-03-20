part of 'painting_board.dart';

const int _layerPreviewRasterHeight = 128;
const double _layerPreviewDisplayHeight = 28;
const double _layerPreviewAspectRatio = 16 / 9;
const double _layerPreviewDisplayWidth =
    _layerPreviewDisplayHeight * _layerPreviewAspectRatio;

class _LayerContextAction {
  const _LayerContextAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
}

mixin _PaintingBoardLayerMixin
    on _PaintingBoardBase, _PaintingBoardLayerTransformMixin {
  final TextEditingController _layerRenameController = TextEditingController();
  final FocusNode _layerRenameFocusNode = FocusNode();
  String? _renamingLayerId;
  final FlyoutController _layerContextMenuController = FlyoutController();
  final FlyoutController _blendModeFlyoutController = FlyoutController();
  bool? _rasterizeMenuEnabled;
  // Layer operations are always supported by the Dart controller.
  // When the backend canvas is active, we additionally sync changes
  // via `_backendCanvasSet*` helpers (they are no-ops when backend is unavailable).
  bool get backendLayerSupported => true;

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
    final CanvasLayerInfo baseLayer = _layers.first;
    final Uint32List? pixels = _controller.readLayerPixels(baseLayer.id);
    if (pixels != null && pixels.isNotEmpty && (pixels[0] >> 24) != 0) {
      return BitmapSurface.decodeColor(pixels[0]);
    }
    return widget.settings.backgroundColor;
  }

  void _handleLayerVisibilityChanged(String id, bool visible) async {
    CanvasLayerInfo? target;
    for (final CanvasLayerInfo layer in _layers) {
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
    _backendCanvasSetLayerVisibleById(id, visible);
    setState(() {});
    _markDirty();
  }

  void _handleLayerSelected(String id) {
    if (_guardTransformInProgress(message: context.l10n.completeTransformFirst)) {
      return;
    }
    _layerOpacityPreviewReset(this);
    _controller.setActiveLayer(id);
    _backendCanvasSetActiveLayerById(id);
    setState(() {});
    _syncRasterizeMenuAvailability();
    _syncMenuAvailability();
  }

  void _handleLayerRenameFocusChange() {
    if (!_layerRenameFocusNode.hasFocus && _renamingLayerId != null) {
      _finalizeLayerRename();
    }
  }

  Future<void> _beginLayerRename(CanvasLayerInfo layer) async {
    if (layer.locked) {
      return;
    }

    final CanvasLayerInfo? target = _layerById(layer.id);
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

    final String? result = await showResponsiveDialog<String>(
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

    final CanvasLayerInfo? refreshed = _layerById(layer.id);
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
    CanvasLayerInfo? target;
    for (final CanvasLayerInfo layer in _layers) {
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
        _activeLayerId ?? (_layers.isEmpty ? null : _layers.last.id);
    _controller.addLayer(aboveLayerId: insertAbove);
    setState(() {});
    _markDirty();
    _syncBackendCanvasLayersToEngine();
  }

  void _handleRemoveLayer(String id) async {
    if (_layers.length <= 1) {
      return;
    }
    if (!await _backend.syncAllLayerPixelsFromBackend(
      waitForPending: true,
      warnIfFailed: true,
    )) {
      return;
    }
    final bool backendSynced = _backend.isReady;
    await _pushUndoSnapshot(backendPixelsSynced: backendSynced);
    _controller.removeLayer(id);
    setState(() {});
    _markDirty();
    _syncBackendCanvasLayersToEngine();
    await _backend.syncAllLayerPixelsToBackend(warnIfFailed: true);
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
    if (!await _backend.syncAllLayerPixelsFromBackend(
      waitForPending: true,
      warnIfFailed: true,
    )) {
      return;
    }
    final bool backendSynced = _backend.isReady;
    await _pushUndoSnapshot(backendPixelsSynced: backendSynced);
    _controller.reorderLayer(actualOldIndex, actualNewIndex);
    if (backendSynced) {
      _backend.reorderBackendLayer(
        fromIndex: actualOldIndex,
        toIndex: actualNewIndex,
      );
      final String? activeLayerId = _activeLayerId;
      if (activeLayerId != null) {
        _backendCanvasSetActiveLayerById(activeLayerId);
      }
    }
    setState(() {});
    _markDirty();
  }

  CanvasLayerInfo? _currentActiveLayer() {
    final String? activeId = _activeLayerId;
    if (activeId == null) {
      return null;
    }
    for (final CanvasLayerInfo layer in _layers) {
      if (layer.id == activeId) {
        return layer;
      }
    }
    return null;
  }

  Future<bool> rasterizeActiveTextLayer() async {
    final CanvasLayerInfo? layer = _currentActiveLayer();
    if (layer == null) {
      return false;
    }
    return _rasterizeTextLayer(layer);
  }

  bool get canRasterizeActiveLayer {
    final CanvasLayerInfo? layer = _currentActiveLayer();
    if (layer == null) {
      return false;
    }
    return layer.text != null && !layer.locked;
  }

  bool get canMergeActiveLayerDown {
    final CanvasLayerInfo? layer = _currentActiveLayer();
    if (layer == null) {
      return false;
    }
    return _canMergeLayerDown(layer);
  }

  Future<bool> _rasterizeTextLayer(CanvasLayerInfo layer) async {
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
    final CanvasLayerInfo? layer = _currentActiveLayer();
    if (layer == null) {
      return;
    }
    if (_layerOpacityGestureActive && _layerOpacityGestureLayerId == layer.id) {
      return;
    }
    _layerOpacityGestureActive = true;
    _layerOpacityGestureLayerId = layer.id;
    _layerOpacityUndoOriginalValue = layer.opacity;
    if (_backend.supportsAntialias) {
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
    if (_backend.supportsAntialias) {
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
    final CanvasLayerInfo? layer = _currentActiveLayer();
    if (layer == null) {
      return;
    }
    if (_backend.supportsAntialias) {
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
    final CanvasLayerInfo? layer = _layerById(layerId);
    if (layer == null) {
      return false;
    }
    final double clamped = value.clamp(0.0, 1.0);
    if ((layer.opacity - clamped).abs() < 1e-4) {
      return false;
    }
    _controller.setLayerOpacity(layerId, clamped);
    _backendCanvasSetLayerOpacityById(layerId, clamped);
    setState(() {});
    _markDirty();
    return true;
  }

  void _ensureLayerOpacityPreview(CanvasLayerInfo layer) {
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

  bool _hasVisibleLayersBelow(CanvasLayerInfo target) {
    for (final CanvasLayerInfo layer in _layers) {
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
    final List<CanvasCompositeLayer> compositeSnapshot =
        _controller.compositeLayers.toList();
    final List<CanvasLayerInfo> signatureSnapshot = _controller.layers.toList();
    _LayerPreviewImages previews;
    try {
      previews = await _captureLayerPreviewImages(
        controller: _controller,
        layers: compositeSnapshot,
        activeLayerId: layerId,
        useBackendCanvas: _backend.isSupported,
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
        _layerOpacityPreviewSignature(signatureSnapshot);
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

  void _applyLayerLockedState(CanvasLayerInfo layer, bool locked) async {
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
    final CanvasLayerInfo? layer = _currentActiveLayer();
    if (layer == null) {
      return;
    }
    _applyLayerLockedState(layer, locked);
  }

  void _handleLayerLockToggle(CanvasLayerInfo layer) {
    _applyLayerLockedState(layer, !layer.locked);
  }

  CanvasLayerInfo? _layerById(String id) {
    for (final CanvasLayerInfo candidate in _layers) {
      if (candidate.id == id) {
        return candidate;
      }
    }
    return null;
  }

  bool _canMergeLayerDown(CanvasLayerInfo layer) {
    if (layer.locked) {
      return false;
    }
    final int index = _layers.indexWhere(
      (candidate) => candidate.id == layer.id,
    );
    if (index <= 0) {
      return false;
    }
    final CanvasLayerInfo below = _layers[index - 1];
    return !below.locked;
  }

  void _handleMergeLayerDown(CanvasLayerInfo layer) async {
    if (!_canMergeLayerDown(layer)) {
      return;
    }
    final bool useBackendCanvas = _backend.isSupported;
    if (!useBackendCanvas) {
      await _pushUndoSnapshot();
      if (!_controller.mergeLayerDown(layer.id)) {
        return;
      }
      setState(() {});
      _markDirty();
      return;
    }
    if (!await _backend.syncAllLayerPixelsFromBackend(
      waitForPending: true,
      warnIfFailed: true,
      skipIfUnavailable: false,
    )) {
      return;
    }
    await _pushUndoSnapshot(backendPixelsSynced: true);
    if (!_controller.mergeLayerDown(layer.id)) {
      return;
    }
    _syncBackendCanvasLayersToEngine();
    await _backend.syncAllLayerPixelsToBackend(
      warnIfFailed: true,
      skipIfUnavailable: false,
    );
    setState(() {});
    _markDirty();
  }

  void _handleLayerClippingToggle(CanvasLayerInfo layer) async {
    if (layer.locked) {
      return;
    }
    final bool nextValue = !layer.clippingMask;
    await _pushUndoSnapshot();
    _controller.setLayerClippingMask(layer.id, nextValue);
    _backendCanvasSetLayerClippingById(layer.id, nextValue);
    setState(() {});
    _markDirty();
  }

  void _handleDuplicateLayer(CanvasLayerInfo layer) async {
    final bool backendReady = _backend.isReady;
    if (backendReady) {
      if (!await _backend.syncAllLayerPixelsFromBackend(
        waitForPending: true,
        warnIfFailed: true,
        skipIfUnavailable: false,
      )) {
        return;
      }
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
    await _pushUndoSnapshot(backendPixelsSynced: backendReady);
    _controller.insertLayerFromData(duplicate, aboveLayerId: layer.id);
    _controller.setActiveLayer(newId);
    setState(() {});
    _markDirty();
    _syncBackendCanvasLayersToEngine();
    if (backendReady) {
      await _backend.syncAllLayerPixelsToBackend(
        warnIfFailed: true,
        skipIfUnavailable: false,
      );
    }
  }

  void _showLayerContextMenu(CanvasLayerInfo layer, Offset position) {
    _handleLayerSelected(layer.id);
    if (isMobileOrPhone(context)) {
      _showLayerContextMenuSheet(layer);
      return;
    }
    _layerContextMenuController.showFlyout(
      position: position,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      builder: (context) {
        final CanvasLayerInfo? target = _layerById(layer.id);
        if (target == null) {
          return const SizedBox.shrink();
        }
        return MenuFlyout(items: _buildLayerContextMenuItems(target));
      },
    );
  }

  void _showLayerContextMenuSheet(CanvasLayerInfo layer) {
    showMobileBottomSheet<void>(
      context: context,
      heightFactor: 0.55,
      builder: (context) {
        final theme = FluentTheme.of(context);
        final CanvasLayerInfo? target = _layerById(layer.id);
        if (target == null) {
          return const SizedBox.shrink();
        }
        final List<_LayerContextAction> actions =
            _buildLayerContextActions(target);
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: actions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final _LayerContextAction action = actions[index];
            final Color? iconColor = action.enabled
                ? theme.resources.textFillColorPrimary
                : theme.resources.textFillColorDisabled;
            return ListTile(
              leading: Icon(action.icon, size: 18, color: iconColor),
              title: Text(
                action.label,
                style: TextStyle(
                  fontSize: 16,
                  color: action.enabled
                      ? theme.resources.textFillColorPrimary
                      : theme.resources.textFillColorDisabled,
                ),
              ),
              onPressed: action.enabled
                  ? () {
                      Navigator.of(context).pop();
                      action.onPressed();
                    }
                  : null,
            );
          },
        );
      },
    );
  }

  List<MenuFlyoutItemBase> _buildLayerContextMenuItems(CanvasLayerInfo layer) {
    final List<_LayerContextAction> actions =
        _buildLayerContextActions(layer);
    return actions
        .map(
          (action) => MenuFlyoutItem(
            leading: Icon(action.icon),
            text: Text(action.label),
            onPressed: action.enabled ? action.onPressed : null,
          ),
        )
        .toList(growable: false);
  }

  List<_LayerContextAction> _buildLayerContextActions(CanvasLayerInfo layer) {
    final bool canDelete = _layers.length > 1 && !layer.locked;
    final bool canMerge = _canMergeLayerDown(layer);
    final bool isLocked = layer.locked;
    final bool isVisible = layer.visible;
    final bool isClipping = layer.clippingMask;
    final l10n = context.l10n;

    final List<_LayerContextAction> actions = <_LayerContextAction>[
      _LayerContextAction(
        icon: isLocked ? FluentIcons.lock : FluentIcons.unlock,
        label: isLocked ? l10n.unlockLayer : l10n.lockLayer,
        enabled: true,
        onPressed: () => _handleLayerLockToggle(layer),
      ),
      _LayerContextAction(
        icon: FluentIcons.download,
        label: l10n.mergeDown,
        enabled: canMerge,
        onPressed: () => _handleMergeLayerDown(layer),
      ),
      _LayerContextAction(
        icon: FluentIcons.subtract_shape,
        label: isClipping ? l10n.releaseClippingMask : l10n.createClippingMask,
        enabled: !isLocked,
        onPressed: () => _handleLayerClippingToggle(layer),
      ),
      _LayerContextAction(
        icon: isVisible ? FluentIcons.hide3 : FluentIcons.view,
        label: isVisible ? l10n.hide : l10n.show,
        enabled: true,
        onPressed: () =>
            _handleLayerVisibilityChanged(layer.id, !layer.visible),
      ),
      _LayerContextAction(
        icon: FluentIcons.delete,
        label: l10n.delete,
        enabled: canDelete,
        onPressed: () => _handleRemoveLayer(layer.id),
      ),
      _LayerContextAction(
        icon: FluentIcons.copy,
        label: l10n.duplicate,
        enabled: true,
        onPressed: () => _handleDuplicateLayer(layer),
      ),
    ];
    if (layer.text != null) {
      actions.insert(
        0,
        _LayerContextAction(
          icon: FluentIcons.font,
          label: l10n.rasterizeTextLayer,
          enabled: !layer.locked,
          onPressed: () {
            unawaited(_rasterizeTextLayer(layer));
          },
        ),
      );
    }
    return actions;
  }

  void _updateActiveLayerClipping(bool clipping) async {
    final CanvasLayerInfo? layer = _currentActiveLayer();
    if (layer == null || layer.clippingMask == clipping) {
      return;
    }
    await _pushUndoSnapshot();
    _controller.setLayerClippingMask(layer.id, clipping);
    _backendCanvasSetLayerClippingById(layer.id, clipping);
    setState(() {});
  }

  void _updateActiveLayerBlendMode(CanvasLayerBlendMode mode) async {
    final CanvasLayerInfo? layer = _currentActiveLayer();
    if (layer == null || layer.blendMode == mode) {
      return;
    }
    await _pushUndoSnapshot();
    _controller.setLayerBlendMode(layer.id, mode);
    _backendCanvasSetLayerBlendModeById(layer.id, mode);
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
    final CanvasLayerInfo? layer = _currentActiveLayer();
    if (layer == null || layer.locked) {
      return false;
    }
    final int clamped = level.clamp(0, 9);
    if (_backend.supportsAntialias) {
      final String? layerId = _activeLayerId;
      if (layerId == null) {
        return false;
      }
      final bool applied = _backend.applyAntialiasById(
        layerId: layerId,
        level: clamped,
      );
      if (applied) {
        _recordBackendHistoryAction(layerId: layerId);
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
    CanvasLayerInfo? activeLayer,
  ) {
    return _buildLayerControlStripImpl(theme, activeLayer);
  }

  Map<String, bool> _computeLayerTileDimStates() {
    return _computeLayerTileDimStatesImpl();
  }

  void _pruneLayerPreviewCache(Iterable<CanvasLayerInfo> layers) {
    _pruneLayerPreviewCacheImpl(layers);
  }

  void _ensureLayerPreview(CanvasLayerInfo layer) {
    _ensureLayerPreviewImpl(layer);
  }

  ui.Image? _layerPreviewImage(String layerId) {
    return _layerPreviewImageImpl(layerId);
  }

  Future<void> _captureLayerPreviewThumbnail({
    required String layerId,
    required int revision,
    required int requestId,
  }) async {
    await _captureLayerPreviewThumbnailImpl(
      layerId: layerId,
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

  _LayerPreviewPixels? _buildLayerPreviewPixels(
    Uint32List pixels,
    int width,
    int height,
  ) {
    return _buildLayerPreviewPixelsImpl(pixels, width, height);
  }

  void _disposeLayerPreviewCache() {
    _disposeLayerPreviewCacheImpl();
  }

  Widget _buildLayerPanelContent(FluentThemeData theme) {
    return _buildLayerPanelContentImpl(theme);
  }
}
