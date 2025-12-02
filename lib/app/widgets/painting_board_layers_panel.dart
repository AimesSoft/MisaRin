part of 'painting_board.dart';

extension _PaintingBoardLayerPanelDelegate on _PaintingBoardLayerMixin {
  void _toggleBlendModeFlyoutImpl(CanvasLayerBlendMode selected) {
    if (_blendModeFlyoutController.isOpen) {
      _blendModeFlyoutController.close();
      return;
    }
    _blendModeFlyoutController.showFlyout(
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      placementMode: FlyoutPlacementMode.bottomLeft,
      additionalOffset: 0,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      builder: (context) {
        return MenuFlyout(
          items: kCanvasBlendModeDisplayOrder
              .map(
                (CanvasLayerBlendMode mode) => MenuFlyoutItem(
                  selected: mode == selected,
                  text: Text(mode.label),
                  onPressed: () {
                    if (mode != selected) {
                      _updateActiveLayerBlendMode(mode);
                    }
                  },
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  Widget _buildBlendModeDropdownImpl({
    required FluentThemeData theme,
    required CanvasLayerBlendMode mode,
    required bool isLocked,
  }) {
    final TextStyle baseStyle =
        theme.typography.body ?? const TextStyle(fontSize: 14);
    final Color textColor = isLocked
        ? theme.resources.textFillColorDisabled
        : baseStyle.color ?? theme.resources.textFillColorPrimary;
    return FlyoutTarget(
      controller: _blendModeFlyoutController,
      child: Button(
        style: const ButtonStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        onPressed: isLocked ? null : () => _toggleBlendModeFlyout(mode),
        child: Container(
          padding: const EdgeInsetsDirectional.only(start: 11, end: 15),
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text(
                  mode.label,
                  style: baseStyle.copyWith(color: textColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                FluentIcons.chevron_down,
                size: 8,
                color: isLocked
                    ? theme.resources.textFillColorDisabled
                    : theme.resources.textFillColorSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanelDividerImpl(FluentThemeData theme) {
    final Color dividerColor = theme.resources.controlStrokeColorDefault
        .withValues(alpha: 0.35);
    return SizedBox(
      height: 1,
      child: DecoratedBox(decoration: BoxDecoration(color: dividerColor)),
    );
  }

  Widget _buildInlineLayerRenameFieldImpl(
    FluentThemeData theme, {
    required bool isActive,
    required String layerId,
    TextStyle? styleOverride,
  }) {
    final TextStyle style =
        styleOverride ??
        (isActive ? theme.typography.bodyStrong : theme.typography.body) ??
        const TextStyle(fontSize: 14);
    final double fontSize = style.fontSize ?? 14;
    final double lineHeight = (style.height ?? 1.0) * fontSize;
    final Color cursorColor = theme.accentColor.defaultBrushFor(
      theme.brightness,
    );
    final Color selectionColor = cursorColor.withValues(alpha: 0.35);
    return SizedBox(
      height: lineHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: EditableText(
          key: ValueKey<String>('layer-rename-$layerId'),
          controller: _layerRenameController,
          focusNode: _layerRenameFocusNode,
          style: style,
          cursorColor: cursorColor,
          backgroundCursorColor: Colors.transparent,
          selectionColor: selectionColor,
          maxLines: 1,
          autofocus: true,
          cursorWidth: 1.3,
          cursorRadius: const Radius.circular(1.5),
          onSubmitted: (_) => _finalizeLayerRename(),
          onEditingComplete: _finalizeLayerRename,
          onTapOutside: (_) => _finalizeLayerRename(),
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.text,
          strutStyle: StrutStyle(
            forceStrutHeight: true,
            height: 1.0,
            fontSize: fontSize,
          ),
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        ),
      ),
    );
  }

  Widget? _buildLayerControlStripImpl(
    FluentThemeData theme,
    BitmapLayerState? activeLayer,
  ) {
    if (activeLayer == null) {
      return null;
    }
    final bool isSai2Layout =
        widget.toolbarLayoutStyle == PaintingToolbarLayoutStyle.sai2;
    final bool showHistoryButtons = true;

    double clampedOpacity = activeLayer.opacity.clamp(0.0, 1.0).toDouble();
    if (_layerOpacityPreviewActive &&
        _layerOpacityPreviewLayerId == activeLayer.id &&
        _layerOpacityPreviewValue != null) {
      clampedOpacity = _layerOpacityPreviewValue!.clamp(0.0, 1.0);
    }
    final int opacityPercent = (clampedOpacity * 100).round();
    final TextStyle labelStyle =
        theme.typography.caption ??
        theme.typography.body?.copyWith(fontSize: 12) ??
        const TextStyle(fontSize: 12);

    Color historyIconColor(bool enabled) {
      final Color baseColor =
          theme.typography.body?.color ??
          theme.typography.bodyStrong?.color ??
          (theme.brightness.isDark ? Colors.white : const Color(0xFF1F1F1F));
      if (enabled) {
        return baseColor;
      }
      return baseColor.withValues(alpha: theme.brightness.isDark ? 0.5 : 0.35);
    }

    Widget buildHistoryButton({
      required IconData icon,
      required String label,
      required bool enabled,
      required VoidCallback onPressed,
    }) {
      final Color color = historyIconColor(enabled);
      return Tooltip(
        message: label,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(icon, size: 16, color: color),
            ),
          ),
        ),
      );
    }

    Widget historyRow() {
      final String undoShortcut = ToolbarShortcuts.labelForPlatform(
        ToolbarAction.undo,
        defaultTargetPlatform,
      );
      final String redoShortcut = ToolbarShortcuts.labelForPlatform(
        ToolbarAction.redo,
        defaultTargetPlatform,
      );
      final String undoLabel = undoShortcut.isEmpty
          ? '撤销'
          : '撤销 ($undoShortcut)';
      final String redoLabel = redoShortcut.isEmpty
          ? '恢复'
          : '恢复 ($redoShortcut)';
      return Row(
        children: [
          buildHistoryButton(
            icon: FluentIcons.undo,
            label: undoLabel,
            enabled: canUndo,
            onPressed: _handleUndo,
          ),
          const SizedBox(width: 8),
          buildHistoryButton(
            icon: FluentIcons.redo,
            label: redoLabel,
            enabled: canRedo,
            onPressed: _handleRedo,
          ),
        ],
      );
    }

    Widget opacityRow() {
      final bool locked = activeLayer.locked;
      final Slider slider = Slider(
        value: clampedOpacity,
        min: 0,
        max: 1,
        divisions: 100,
        onChangeStart: locked ? null : _handleLayerOpacityChangeStart,
        onChanged: locked ? null : _handleLayerOpacityChanged,
        onChangeEnd: locked ? null : _handleLayerOpacityChangeEnd,
      );
      if (isSai2Layout) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('不透明度 $opacityPercent%', style: labelStyle),
            const SizedBox(height: 8),
            slider,
          ],
        );
      }
      return Row(
        children: [
          SizedBox(width: 52, child: Text('不透明度', style: labelStyle)),
          const SizedBox(width: 8),
          Expanded(child: slider),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              '$opacityPercent%',
              textAlign: TextAlign.end,
              style: theme.typography.bodyStrong,
            ),
          ),
        ],
      );
    }

    Widget toggleRow() {
      Widget buildLabeledCheckbox({
        required String label,
        required bool value,
        ValueChanged<bool>? onChanged,
      }) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(width: 6),
            Checkbox(
              checked: value,
              content: const SizedBox.shrink(),
              onChanged: onChanged == null
                  ? null
                  : (checked) => onChanged(checked ?? value),
            ),
          ],
        );
      }

      final Widget lockCheckbox = buildLabeledCheckbox(
        label: '锁定图层',
        value: activeLayer.locked,
        onChanged: _updateActiveLayerLocked,
      );
      final Widget clipCheckbox = buildLabeledCheckbox(
        label: '剪贴蒙版',
        value: activeLayer.clippingMask,
        onChanged: activeLayer.locked ? null : _updateActiveLayerClipping,
      );
      if (isSai2Layout) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [lockCheckbox, const SizedBox(height: 8), clipCheckbox],
        );
      }
      return Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [lockCheckbox, clipCheckbox],
      );
    }

    Widget blendRow() {
      final Widget dropdown = _buildBlendModeDropdown(
        theme: theme,
        mode: activeLayer.blendMode,
        isLocked: activeLayer.locked,
      );
      if (isSai2Layout) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('混合模式', style: labelStyle),
            const SizedBox(height: 8),
            dropdown,
          ],
        );
      }
      return Row(
        children: [
          SizedBox(width: 52, child: Text('混合模式', style: labelStyle)),
          const SizedBox(width: 8),
          Expanded(child: dropdown),
        ],
      );
    }

    final List<Widget> controls = <Widget>[];
    if (showHistoryButtons) {
      controls
        ..add(historyRow())
        ..add(const SizedBox(height: 6));
    }
    if (!isSai2Layout) {
      controls
        ..add(_buildAddLayerButton())
        ..add(const SizedBox(height: 6));
    }
    controls
      ..add(opacityRow())
      ..add(const SizedBox(height: 6))
      ..add(toggleRow())
      ..add(const SizedBox(height: 6))
      ..add(blendRow());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: controls,
    );
  }

  Map<String, bool> _computeLayerTileDimStatesImpl() {
    final Map<String, bool> dimStates = <String, bool>{};
    BitmapLayerState? clippingOwner;
    for (final BitmapLayerState layer in _layers) {
      if (!layer.clippingMask) {
        clippingOwner = layer;
        dimStates[layer.id] = !layer.visible;
        continue;
      }
      final bool ownerDimmed = clippingOwner == null
          ? true
          : (dimStates[clippingOwner.id] ?? !clippingOwner.visible);
      dimStates[layer.id] = !layer.visible || ownerDimmed;
    }
    return dimStates;
  }

  void _pruneLayerPreviewCacheImpl(Iterable<BitmapLayerState> layers) {
    if (_layerPreviewCache.isEmpty) {
      return;
    }
    final Set<String> liveIds = layers.map((layer) => layer.id).toSet();
    final List<String> stale = <String>[];
    for (final String id in _layerPreviewCache.keys) {
      if (!liveIds.contains(id)) {
        stale.add(id);
      }
    }
    if (stale.isEmpty) {
      return;
    }
    for (final String id in stale) {
      final _LayerPreviewCacheEntry? entry = _layerPreviewCache.remove(id);
      entry?.dispose();
    }
  }

  void _ensureLayerPreviewImpl(BitmapLayerState layer) {
    final _LayerPreviewCacheEntry? entry = _layerPreviewCache[layer.id];
    if (entry != null && entry.revision == layer.revision) {
      return;
    }
    final int requestId = ++_layerPreviewRequestSerial;
    final _LayerPreviewCacheEntry target =
        entry ?? _LayerPreviewCacheEntry(requestId: requestId);
    target.requestId = requestId;
    _layerPreviewCache[layer.id] = target;
    unawaited(
      _captureLayerPreviewThumbnail(
        layerId: layer.id,
        surface: layer.surface,
        revision: layer.revision,
        requestId: requestId,
      ),
    );
  }

  ui.Image? _layerPreviewImageImpl(String layerId) {
    return _layerPreviewCache[layerId]?.image;
  }

  Future<void> _captureLayerPreviewThumbnailImpl({
    required String layerId,
    required BitmapSurface surface,
    required int revision,
    required int requestId,
  }) async {
    final _LayerPreviewPixels? pixels = _buildLayerPreviewPixels(surface);
    ui.Image? image;
    if (pixels != null) {
      try {
        image = await _decodeImage(pixels.bytes, pixels.width, pixels.height);
      } catch (error, stackTrace) {
        debugPrint('Failed to build layer preview for $layerId: $error');
        debugPrint('$stackTrace');
        image = null;
      }
    }
    _applyLayerPreviewResult(
      layerId: layerId,
      revision: revision,
      requestId: requestId,
      image: image,
    );
  }

  void _applyLayerPreviewResultImpl({
    required String layerId,
    required int revision,
    required int requestId,
    ui.Image? image,
  }) {
    if (!mounted) {
      image?.dispose();
      return;
    }
    final _LayerPreviewCacheEntry? entry = _layerPreviewCache[layerId];
    if (entry == null || entry.requestId != requestId) {
      image?.dispose();
      return;
    }
    final ui.Image? previous = entry.image;
    final bool changed = previous != image || entry.revision != revision;
    entry
      ..image = image
      ..revision = revision;
    if (!changed) {
      return;
    }
    setState(() {});
    if (previous != null && previous != image) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  _LayerPreviewPixels? _buildLayerPreviewPixelsImpl(BitmapSurface surface) {
    final int width = surface.width;
    final int height = surface.height;
    if (width <= 0 || height <= 0) {
      return null;
    }
    final int targetHeight = math.min(_layerPreviewRasterHeight, height);
    final double scale = targetHeight / height;
    final int targetWidth = math.max(1, (width * scale).round());
    if (targetWidth <= 0 || targetHeight <= 0) {
      return null;
    }
    final Uint8List rgba = Uint8List(targetWidth * targetHeight * 4);
    final double stepX = width / targetWidth;
    final double stepY = height / targetHeight;
    int dest = 0;
    for (int y = 0; y < targetHeight; y++) {
      final int sourceY = (y * stepY).floor().clamp(0, height - 1);
      final int rowBase = sourceY * width;
      for (int x = 0; x < targetWidth; x++) {
        final int sourceX = (x * stepX).floor().clamp(0, width - 1);
        final int argb = surface.pixels[rowBase + sourceX];
        rgba[dest++] = (argb >> 16) & 0xFF;
        rgba[dest++] = (argb >> 8) & 0xFF;
        rgba[dest++] = argb & 0xFF;
        rgba[dest++] = (argb >> 24) & 0xFF;
      }
    }
    return _LayerPreviewPixels(
      bytes: rgba,
      width: targetWidth,
      height: targetHeight,
    );
  }

  void _disposeLayerPreviewCacheImpl() {
    if (_layerPreviewCache.isEmpty) {
      return;
    }
    for (final _LayerPreviewCacheEntry entry in _layerPreviewCache.values) {
      entry.dispose();
    }
    _layerPreviewCache.clear();
  }

  Widget _buildLayerPanelContentImpl(FluentThemeData theme) {
    final bool isSai2Layout =
        widget.toolbarLayoutStyle == PaintingToolbarLayoutStyle.sai2;
    final List<BitmapLayerState> orderedLayers = _layers
        .toList(growable: false)
        .reversed
        .toList(growable: false);
    _pruneLayerPreviewCache(_layers);
    final Map<String, bool> layerTileDimStates = _computeLayerTileDimStates();
    final String? activeLayerId = _activeLayerId;
    final Color fallbackCardColor = theme.brightness.isDark
        ? const Color(0xFF1F1F1F)
        : Colors.white;
    Color tileBaseColor = theme.cardColor;
    if (tileBaseColor.alpha != 0xFF) {
      tileBaseColor = fallbackCardColor;
    }

    BitmapLayerState? activeLayer;
    if (activeLayerId != null) {
      for (final BitmapLayerState candidate in _layers) {
        if (candidate.id == activeLayerId) {
          activeLayer = candidate;
          break;
        }
      }
    }
    final Widget? layerControls = _buildLayerControlStrip(theme, activeLayer);

    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        if (isSai2Layout) ...[
          _buildPanelDivider(theme),
          const SizedBox(height: 6),
        ] else
          const SizedBox(height: 6),
        if (layerControls != null) ...[
          layerControls,
          const SizedBox(height: 6),
          _buildPanelDivider(theme),
          const SizedBox(height: 6),
        ],
        Expanded(
          child: FlyoutTarget(
            controller: _layerContextMenuController,
            child: Scrollbar(
              controller: _layerScrollController,
              child: Localizations.override(
                context: context,
                delegates: const [GlobalMaterialLocalizations.delegate],
                child: material.ReorderableListView.builder(
                  scrollController: _layerScrollController,
                  padding: EdgeInsets.zero,
                  buildDefaultDragHandles: false,
                  dragStartBehavior: DragStartBehavior.down,
                  proxyDecorator: (child, index, animation) => child,
                  itemCount: orderedLayers.length,
                  onReorder: _handleLayerReorder,
                  itemBuilder: (context, index) {
                    final BitmapLayerState layer = orderedLayers[index];
                    final bool isActive = layer.id == activeLayerId;
                    final bool tileDimmed =
                        layerTileDimStates[layer.id] ?? !layer.visible;
                    final double contentOpacity = tileDimmed ? 0.45 : 1.0;
                    final Color background = isActive
                        ? Color.alphaBlend(
                            theme.resources.subtleFillColorSecondary,
                            tileBaseColor,
                          )
                        : tileBaseColor;
                    final Color borderColor =
                        theme.resources.controlStrokeColorSecondary;
                    final Color tileBorder = Color.lerp(
                      borderColor,
                      Colors.transparent,
                      0.6,
                    )!;

                    final bool layerLocked = layer.locked;
                    final bool canMergeDown = _canMergeLayerDown(layer);
                    final bool layerClipping = layer.clippingMask;
                    final bool showTileButtons = !isSai2Layout;
                    _ensureLayerPreview(layer);
                    final ui.Image? layerPreview = _layerPreviewImage(layer.id);

                    final Widget visibilityButton = LayerVisibilityButton(
                      visible: layer.visible,
                      onChanged: (value) =>
                          _handleLayerVisibilityChanged(layer.id, value),
                    );
                    Widget leadingButtons = visibilityButton;
                    if (isSai2Layout) {
                      leadingButtons = _LayerSidebarButtons(
                        primary: visibilityButton,
                        secondary: _LayerClippingToggleButton(
                          active: layerClipping,
                          enabled: !layerLocked,
                          onPressed: () => _handleLayerClippingToggle(layer),
                        ),
                      );
                    }

                    Widget? lockButton;
                    Widget? clippingButton;
                    if (showTileButtons) {
                      lockButton = Tooltip(
                        message: layerLocked ? '解锁图层' : '锁定图层',
                        child: IconButton(
                          icon: Icon(
                            layerLocked ? FluentIcons.lock : FluentIcons.unlock,
                          ),
                          onPressed: () => _handleLayerLockToggle(layer),
                        ),
                      );
                      final Color clippingActiveBackground = Color.alphaBlend(
                        (theme.brightness.isDark ? Colors.white : Colors.black)
                            .withValues(
                              alpha: theme.brightness.isDark ? 0.18 : 0.08,
                            ),
                        background,
                      );
                      clippingButton = Tooltip(
                        message: layerClipping ? '取消剪贴蒙版' : '创建剪贴蒙版',
                        child: IconButton(
                          icon: const Icon(FluentIcons.subtract_shape),
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (layerClipping) {
                                return clippingActiveBackground;
                              }
                              if (states.contains(WidgetState.disabled)) {
                                return theme.resources.controlFillColorDisabled;
                              }
                              return null;
                            }),
                          ),
                          onPressed: layerLocked
                              ? null
                              : () => _handleLayerClippingToggle(layer),
                        ),
                      );
                    }

                    final bool canDelete = _layers.length > 1 && !layerLocked;
                    final Widget deleteButton = IconButton(
                      icon: const Icon(FluentIcons.delete),
                      onPressed: canDelete
                          ? () => _handleRemoveLayer(layer.id)
                          : null,
                    );
                    Widget? trailingWidget;
                    if (isSai2Layout) {
                      final Widget lockToggleButton = Tooltip(
                        message: layerLocked ? '解锁图层' : '锁定图层',
                        child: IconButton(
                          icon: Icon(
                            layerLocked ? FluentIcons.lock : FluentIcons.unlock,
                          ),
                          onPressed: () => _handleLayerLockToggle(layer),
                        ),
                      );
                      trailingWidget = Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          deleteButton,
                          const SizedBox(height: 4),
                          lockToggleButton,
                        ],
                      );
                    } else {
                      final List<Widget> topRowButtons = <Widget>[];
                      void addTopButton(Widget widget) {
                        if (topRowButtons.isNotEmpty) {
                          topRowButtons.add(const SizedBox(width: 4));
                        }
                        topRowButtons.add(widget);
                      }

                      if (clippingButton != null) {
                        addTopButton(clippingButton);
                      }
                      if (lockButton != null) {
                        addTopButton(lockButton);
                      }
                      addTopButton(deleteButton);

                      Widget wrapIconButton({
                        required Widget child,
                        required String tooltip,
                      }) {
                        return Tooltip(message: tooltip, child: child);
                      }

                      final Widget mergeButton = wrapIconButton(
                        tooltip: '向下合并',
                        child: IconButton(
                          icon: const Icon(FluentIcons.download),
                          onPressed: canMergeDown
                              ? () => _handleMergeLayerDown(layer)
                              : null,
                        ),
                      );
                      final Widget duplicateButton = wrapIconButton(
                        tooltip: '复制图层',
                        child: IconButton(
                          icon: const Icon(FluentIcons.copy),
                          onPressed: () => _handleDuplicateLayer(layer),
                        ),
                      );
                      final Widget placeholderButton = wrapIconButton(
                        tooltip: '更多',
                        child: const IconButton(
                          icon: Icon(FluentIcons.more),
                          onPressed: null,
                        ),
                      );

                      trailingWidget = Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: topRowButtons,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              mergeButton,
                              const SizedBox(width: 4),
                              duplicateButton,
                              const SizedBox(width: 4),
                              placeholderButton,
                            ],
                          ),
                        ],
                      );
                    }
                    return material.ReorderableDragStartListener(
                      key: ValueKey(layer.id),
                      index: index,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: layer.clippingMask ? 18 : 0,
                          bottom: index == orderedLayers.length - 1 ? 0 : 8,
                        ),
                        child: _LayerTile(
                          onTapDown: (_) => _handleLayerSelected(layer.id),
                          onSecondaryTapDown: (details) =>
                              _showLayerContextMenu(
                                layer,
                                details.globalPosition,
                              ),
                          backgroundColor: background,
                          borderColor: tileBorder,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  leadingButtons,
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Opacity(
                                      opacity: contentOpacity,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _LayerNameView(
                                            layer: layer,
                                            theme: theme,
                                            isActive: isActive,
                                            isRenaming:
                                                !layerLocked &&
                                                _renamingLayerId == layer.id,
                                            isLocked: layerLocked,
                                            buildEditor: (style) =>
                                                _buildInlineLayerRenameField(
                                                  theme,
                                                  isActive: isActive,
                                                  layerId: layer.id,
                                                  styleOverride: style,
                                                ),
                                            onRequestRename: layerLocked
                                                ? null
                                                : () {
                                                    _handleLayerSelected(
                                                      layer.id,
                                                    );
                                                    _beginLayerRename(layer);
                                                  },
                                          ),
                                          const SizedBox(height: 6),
                                          _LayerPreviewThumbnail(
                                            image: layerPreview,
                                            theme: theme,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ...[const SizedBox(width: 8), trailingWidget],
                                ],
                              ),
                              if (layer.clippingMask)
                                Positioned(
                                  left: -10,
                                  top: 6,
                                  bottom: 6,
                                  child: _ClippingMaskIndicator(
                                    color: theme.accentColor.defaultBrushFor(
                                      theme.brightness,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LayerPreviewPixels {
  const _LayerPreviewPixels({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

class _LayerPreviewCacheEntry {
  _LayerPreviewCacheEntry({required this.requestId, this.revision = 0});

  int requestId;
  int revision;
  ui.Image? image;

  void dispose() {
    image?.dispose();
    image = null;
  }
}
