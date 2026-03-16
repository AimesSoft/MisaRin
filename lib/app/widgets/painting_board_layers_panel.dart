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
    final bool isEnabled = !isLocked && backendLayerSupported;
    final TextStyle baseStyle =
        theme.typography.body ?? const TextStyle(fontSize: 14);
    final Color textColor = isEnabled
        ? (baseStyle.color ?? theme.resources.textFillColorPrimary)
        : theme.resources.textFillColorDisabled;
    return FlyoutTarget(
      controller: _blendModeFlyoutController,
      child: Button(
        style: const ButtonStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        onPressed: isEnabled ? () => _toggleBlendModeFlyout(mode) : null,
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
                color: isEnabled
                    ? theme.resources.textFillColorSecondary
                    : theme.resources.textFillColorDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanelDividerImpl(FluentThemeData theme) {
    final Color dividerColor = theme.resources.controlStrokeColorDefault
        .withOpacity(0.35);
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
    final Color selectionColor = cursorColor.withOpacity(0.35);
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

  Widget _buildLayerActionTooltip({
    required String message,
    required Widget child,
    String? detail,
  }) {
    return HoverDetailTooltip(message: message, detail: detail, child: child);
  }

  Widget? _buildLayerControlStripImpl(
    FluentThemeData theme,
    CanvasLayerInfo? activeLayer,
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

    Color _historyIconColor(bool enabled) {
      final Color baseColor =
          theme.typography.body?.color ??
          theme.typography.bodyStrong?.color ??
          (theme.brightness.isDark ? Colors.white : const Color(0xFF1F1F1F));
      if (enabled) {
        return baseColor;
      }
      return baseColor.withOpacity(theme.brightness.isDark ? 0.5 : 0.35);
    }

    Widget buildHistoryButton({
      required IconData icon,
      required String label,
      required bool enabled,
      required VoidCallback onPressed,
    }) {
      final Color color = _historyIconColor(enabled);
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
      final l10n = context.l10n;
      final TargetPlatform platform = resolvedTargetPlatform();
      final String undoShortcut = ToolbarShortcuts.labelForPlatform(
        ToolbarAction.undo,
        platform,
      );
      final String redoShortcut = ToolbarShortcuts.labelForPlatform(
        ToolbarAction.redo,
        platform,
      );
      final String undoLabel = undoShortcut.isEmpty
          ? l10n.undo
          : l10n.undoShortcut(undoShortcut);
      final String redoLabel = redoShortcut.isEmpty
          ? l10n.redo
          : l10n.redoShortcut(redoShortcut);
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
      final l10n = context.l10n;
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
            Text(l10n.opacityPercent(opacityPercent), style: labelStyle),
            const SizedBox(height: 8),
            slider,
          ],
        );
      }
      return Row(
        children: [
          SizedBox(width: 52, child: Text(l10n.opacity, style: labelStyle)),
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
      final l10n = context.l10n;
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
        label: l10n.lockLayer,
        value: activeLayer.locked,
        onChanged: _updateActiveLayerLocked,
      );
      final Widget clipCheckbox = buildLabeledCheckbox(
        label: l10n.clippingMask,
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
            Text(context.l10n.blendMode, style: labelStyle),
            const SizedBox(height: 8),
            dropdown,
          ],
        );
      }
      return Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(context.l10n.blendMode, style: labelStyle),
          ),
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
    CanvasLayerInfo? clippingOwner;
    for (final CanvasLayerInfo layer in _layers) {
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

  void _pruneLayerPreviewCacheImpl(Iterable<CanvasLayerInfo> layers) {
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
      _backendLayerPreviewRevisions.remove(id);
      _backendLayerPreviewPending.remove(id);
    }
  }

  void _ensureLayerPreviewImpl(CanvasLayerInfo layer) {
    final _LayerPreviewCacheEntry? entry = _layerPreviewCache[layer.id];
    final int revision = _layerPreviewRevisionForLayer(layer);
    if (entry != null && entry.revision == revision) {
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
        revision: revision,
        requestId: requestId,
      ),
    );
  }

  ui.Image? _layerPreviewImageImpl(String layerId) {
    return _layerPreviewCache[layerId]?.image;
  }

  Future<void> _captureLayerPreviewThumbnailImpl({
    required String layerId,
    required int revision,
    required int requestId,
  }) async {
    _LayerPreviewPixels? pixels = await _backend.readLayerPreviewPixels(
      layerId: layerId,
      maxHeight: _layerPreviewRasterHeight,
    );
    if (pixels == null) {
      final Size? surfaceSize = _controller.readLayerSurfaceSize(layerId);
      final Uint32List? layerPixels = _controller.readLayerPixels(layerId);
      if (surfaceSize != null && layerPixels != null) {
        pixels = _buildLayerPreviewPixels(
          layerPixels,
          surfaceSize.width.round(),
          surfaceSize.height.round(),
        );
      }
    }
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

  int _layerPreviewRevisionForLayer(CanvasLayerInfo layer) {
    if (!_backend.isReady) {
      return layer.revision;
    }
    return _backendLayerPreviewRevisions[layer.id] ?? 0;
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

  _LayerPreviewPixels? _buildLayerPreviewPixelsImpl(
    Uint32List pixels,
    int width,
    int height,
  ) {
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
        final int argb = pixels[rowBase + sourceX];
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
    _backendLayerPreviewRevisions.clear();
    _backendLayerPreviewPending.clear();
  }

  Widget _buildLayerPanelContentImpl(FluentThemeData theme) {
    final bool isSai2Layout =
        widget.toolbarLayoutStyle == PaintingToolbarLayoutStyle.sai2;
    final bool isMobile = isMobileOrPhone(context);
    final double controlSize = isMobile ? 28 : 24;
    final double controlIconSize = isMobile ? 16 : 14;
    final double actionIconSize = isMobile ? 18 : 14;
    final EdgeInsets actionButtonPadding = EdgeInsets.all(isMobile ? 6 : 4);
    final double sidebarWidth = isMobile ? 32 : 28;
    final double sidebarSpacing = isMobile ? 8 : 6;
    final double buttonSpacing = isMobile ? 6 : 4;
    final double rowSpacing = isMobile ? 8 : 6;
    final double contentSpacing = isMobile ? 10 : 8;
    final double itemSpacing = isMobile ? 10 : 8;
    final double clippingIndent = isMobile ? 22 : 18;
    final EdgeInsets tilePadding = EdgeInsets.symmetric(
      horizontal: isMobile ? 14 : 12,
      vertical: isMobile ? 12 : 10,
    );
    final double nameTextScale = isMobile ? 1.15 : 1.0;
    final List<CanvasLayerInfo> orderedLayers = _layers
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

    CanvasLayerInfo? activeLayer;
    if (activeLayerId != null) {
      for (final CanvasLayerInfo candidate in _layers) {
        if (candidate.id == activeLayerId) {
          activeLayer = candidate;
          break;
        }
      }
    }
    final Widget? layerControls = _buildLayerControlStrip(theme, activeLayer);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool hasBoundedHeight = constraints.hasBoundedHeight;
        final Widget listView = material.ReorderableListView.builder(
          scrollController: _layerScrollController,
          padding: EdgeInsets.zero,
          buildDefaultDragHandles: false,
          dragStartBehavior: DragStartBehavior.down,
          proxyDecorator: (child, index, animation) => child,
          itemCount: orderedLayers.length,
          onReorder: _handleLayerReorder,
          physics: hasBoundedHeight
              ? null
              : const NeverScrollableScrollPhysics(),
          shrinkWrap: !hasBoundedHeight,
          itemBuilder: (context, index) {
            final CanvasLayerInfo layer = orderedLayers[index];
            final bool isActive = layer.id == activeLayerId;
            final bool tileDimmed =
                layerTileDimStates[layer.id] ?? !layer.visible;
            final double contentOpacity = tileDimmed ? 0.45 : 1.0;
            final bool isTextLayer = layer.text != null;
            final bool isDark = theme.brightness.isDark;
            final Color accent = theme.accentColor.defaultBrushFor(
              theme.brightness,
            );
            final Color activeOverlay = isDark
                ? theme.resources.subtleFillColorSecondary
                : accent.withValues(alpha: accent.a * 0.12);
            final Color background = isActive
                ? Color.alphaBlend(activeOverlay, tileBaseColor)
                : tileBaseColor;
            final Color borderColor =
                theme.resources.controlStrokeColorSecondary;
            final Color baseTileBorder = Color.lerp(
              borderColor,
              Colors.transparent,
              0.6,
            )!;
            final Color tileBorder = isActive
                ? Color.lerp(baseTileBorder, accent, isDark ? 0.45 : 0.75) ??
                      baseTileBorder
                : baseTileBorder;

            final bool layerLocked = layer.locked;
            final bool canMergeDown = _canMergeLayerDown(layer);
            final bool layerClipping = layer.clippingMask;
            final bool showTileButtons = !isSai2Layout;
            final l10n = context.l10n;
            _ensureLayerPreview(layer);
            final ui.Image? layerPreview = _layerPreviewImage(layer.id);
            final String lockTooltip = layerLocked
                ? l10n.unlockLayer
                : l10n.lockLayer;
            final String lockDetail = layerLocked
                ? l10n.unlockLayerDesc
                : l10n.lockLayerDesc;
            final String clippingTooltip = layerClipping
                ? l10n.releaseClippingMask
                : l10n.createClippingMask;
            final String clippingDetail = layerClipping
                ? l10n.clippingMaskDescOn
                : l10n.clippingMaskDescOff;

            final Widget visibilityButton = LayerVisibilityButton(
              visible: layer.visible,
              onChanged: backendLayerSupported
                  ? (value) => _handleLayerVisibilityChanged(layer.id, value)
                  : null,
              size: controlSize,
              iconSize: controlIconSize,
            );
            Widget leadingButtons = visibilityButton;
            if (isSai2Layout) {
              leadingButtons = _LayerSidebarButtons(
                primary: visibilityButton,
                secondary: _LayerClippingToggleButton(
                  active: layerClipping,
                  enabled: !layerLocked,
                  onPressed: () => _handleLayerClippingToggle(layer),
                  size: controlSize,
                  iconSize: controlIconSize,
                ),
                width: sidebarWidth,
                spacing: sidebarSpacing,
              );
            }

            Widget? lockButton;
            Widget? clippingButton;
            if (showTileButtons) {
              lockButton = _buildLayerActionTooltip(
                message: lockTooltip,
                detail: lockDetail,
                child: IconButton(
                  icon: Icon(
                    layerLocked ? FluentIcons.lock : FluentIcons.unlock,
                    size: actionIconSize,
                  ),
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all<EdgeInsets>(
                      actionButtonPadding,
                    ),
                  ),
                  onPressed: () => _handleLayerLockToggle(layer),
                ),
              );
              final Color clippingActiveBackground = Color.alphaBlend(
                (theme.brightness.isDark ? Colors.white : Colors.black)
                    .withOpacity(theme.brightness.isDark ? 0.18 : 0.08),
                background,
              );
              clippingButton = _buildLayerActionTooltip(
                message: clippingTooltip,
                detail: clippingDetail,
                child: IconButton(
                  icon: Icon(FluentIcons.subtract_shape, size: actionIconSize),
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all<EdgeInsets>(
                      actionButtonPadding,
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
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
            final Widget deleteButton = _buildLayerActionTooltip(
              message: l10n.deleteLayerTitle,
              detail: l10n.deleteLayerDesc,
              child: IconButton(
                icon: Icon(FluentIcons.delete, size: actionIconSize),
                style: ButtonStyle(
                  padding: WidgetStateProperty.all<EdgeInsets>(
                    actionButtonPadding,
                  ),
                ),
                onPressed: canDelete
                    ? () => _handleRemoveLayer(layer.id)
                    : null,
              ),
            );
            Widget? trailingWidget;
            if (isSai2Layout) {
              final Widget lockToggleButton = _buildLayerActionTooltip(
                message: lockTooltip,
                detail: lockDetail,
                child: IconButton(
                  icon: Icon(
                    layerLocked ? FluentIcons.lock : FluentIcons.unlock,
                    size: actionIconSize,
                  ),
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all<EdgeInsets>(
                      actionButtonPadding,
                    ),
                  ),
                  onPressed: () => _handleLayerLockToggle(layer),
                ),
              );
              trailingWidget = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  deleteButton,
                  SizedBox(height: buttonSpacing),
                  lockToggleButton,
                ],
              );
            } else {
              final List<Widget> topRowButtons = <Widget>[];
              void addTopButton(Widget widget) {
                if (topRowButtons.isNotEmpty) {
                  topRowButtons.add(SizedBox(width: buttonSpacing));
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
                String? detail,
              }) {
                return _buildLayerActionTooltip(
                  message: tooltip,
                  detail: detail,
                  child: child,
                );
              }

              final Widget mergeButton = wrapIconButton(
                tooltip: l10n.mergeDown,
                detail: l10n.mergeDownDesc,
                child: IconButton(
                  icon: Icon(FluentIcons.download, size: actionIconSize),
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all<EdgeInsets>(
                      actionButtonPadding,
                    ),
                  ),
                  onPressed: canMergeDown
                      ? () => _handleMergeLayerDown(layer)
                      : null,
                ),
              );
              final Widget duplicateButton = wrapIconButton(
                tooltip: l10n.duplicateLayer,
                detail: l10n.duplicateLayerDesc,
                child: IconButton(
                  icon: Icon(FluentIcons.copy, size: actionIconSize),
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all<EdgeInsets>(
                      actionButtonPadding,
                    ),
                  ),
                  onPressed: () => _handleDuplicateLayer(layer),
                ),
              );
              final Widget placeholderButton = wrapIconButton(
                tooltip: l10n.more,
                detail: null,
                child: Builder(
                  builder: (context) {
                    return IconButton(
                      icon: Icon(FluentIcons.more, size: actionIconSize),
                      style: ButtonStyle(
                        padding: WidgetStateProperty.all<EdgeInsets>(
                          actionButtonPadding,
                        ),
                      ),
                      onPressed: backendLayerSupported
                          ? () {
                              final RenderBox? box =
                                  context.findRenderObject() as RenderBox?;
                              final Offset position = box == null
                                  ? Offset.zero
                                  : box.localToGlobal(
                                      box.size.center(Offset.zero),
                                    );
                              _showLayerContextMenu(layer, position);
                            }
                          : null,
                    );
                  },
                ),
              );

              trailingWidget = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: topRowButtons),
                  SizedBox(height: rowSpacing),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      mergeButton,
                      SizedBox(width: buttonSpacing),
                      duplicateButton,
                      SizedBox(width: buttonSpacing),
                      placeholderButton,
                    ],
                  ),
                ],
              );
            }
            return KeyedSubtree(
              key: ValueKey(layer.id),
              child: material.ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: layer.clippingMask ? clippingIndent : 0,
                    bottom: index == orderedLayers.length - 1 ? 0 : itemSpacing,
                  ),
                  child: _LayerTile(
                    padding: tilePadding,
                    onTapDown: (_) => _handleLayerSelected(layer.id),
                    onSecondaryTapDown: backendLayerSupported
                        ? (details) => _showLayerContextMenu(
                            layer,
                            details.globalPosition,
                          )
                        : null,
                    backgroundColor: background,
                    borderColor: tileBorder,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            leadingButtons,
                            SizedBox(width: contentSpacing),
                            Expanded(
                              child: Opacity(
                                opacity: contentOpacity,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLayerNameRow(
                                      theme: theme,
                                      layer: layer,
                                      isActive: isActive,
                                      isRenaming:
                                          !layerLocked &&
                                          _renamingLayerId == layer.id,
                                      isLocked: layerLocked,
                                      isTextLayer: isTextLayer,
                                      textScale: nameTextScale,
                                    ),
                                    SizedBox(height: rowSpacing),
                                    _LayerPreviewThumbnail(
                                      image: layerPreview,
                                      theme: theme,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (trailingWidget != null) ...[
                              SizedBox(width: contentSpacing),
                              trailingWidget!,
                            ],
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
              ),
            );
          },
        );

        final Widget listContent = Localizations.override(
          context: context,
          delegates: const [GlobalMaterialLocalizations.delegate],
          child: listView,
        );
        final Widget listHost = hasBoundedHeight
            ? Scrollbar(controller: _layerScrollController, child: listContent)
            : listContent;

        final Widget listContainer = FlyoutTarget(
          controller: _layerContextMenuController,
          child: listHost,
        );

        return Column(
          mainAxisSize: hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
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
            if (hasBoundedHeight)
              Expanded(child: listContainer)
            else
              listContainer,
          ],
        );
      },
    );
  }

  Widget _buildLayerNameRow({
    required FluentThemeData theme,
    required CanvasLayerInfo layer,
    required bool isActive,
    required bool isRenaming,
    required bool isLocked,
    required bool isTextLayer,
    double textScale = 1.0,
  }) {
    Widget name = _LayerNameView(
      layer: layer,
      theme: theme,
      isActive: isActive,
      isRenaming: isRenaming,
      isLocked: isLocked,
      textScale: textScale,
      buildEditor: (style) => _buildInlineLayerRenameField(
        theme,
        isActive: isActive,
        layerId: layer.id,
        styleOverride: style,
      ),
      onRequestRename: isLocked
          ? null
          : () {
              _handleLayerSelected(layer.id);
              unawaited(_beginLayerRename(layer));
            },
    );
    if (!isTextLayer) {
      return name;
    }
    final Color iconColor = theme.resources.textFillColorSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(FluentIcons.font, size: 12, color: iconColor),
        const SizedBox(width: 6),
        Expanded(child: name),
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
  _LayerPreviewCacheEntry({
    required this.requestId,
    this.revision = -1,
    this.image,
  });

  int requestId;
  int revision;
  ui.Image? image;

  void dispose() {
    image?.dispose();
    image = null;
  }
}
