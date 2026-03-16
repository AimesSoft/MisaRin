part of 'painting_board.dart';

mixin _PaintingBoardColorMixin on _PaintingBoardBase {
  List<Color>? _resolveBucketSwallowColors() {
    if (!_bucketSwallowColorLine) {
      return null;
    }
    switch (_bucketSwallowColorLineMode) {
      case BucketSwallowColorLineMode.all:
        return kColorLinePresets;
      case BucketSwallowColorLineMode.red:
        return <Color>[kColorLinePresets[0]];
      case BucketSwallowColorLineMode.green:
        return <Color>[kColorLinePresets[2]];
      case BucketSwallowColorLineMode.blue:
        return <Color>[kColorLinePresets[1]];
    }
  }

  Future<void> _pickColor({
    required String title,
    required Color initialColor,
    required ValueChanged<Color> onSelected,
    VoidCallback? onCleared,
  }) async {
    Color previewColor = initialColor;
    _ColorAdjustMode currentMode = _ColorAdjustMode.fluentBox;
    bool applied = false;
    final Color? result = await showResponsiveDialog<Color>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return ContentDialog(
          title: Text(title),
          content: StatefulBuilder(
            builder: (context, setState) {
              Widget buildModeChooser(_ColorAdjustMode mode) {
                final bool selected = currentMode == mode;
                return ToggleButton(
                  checked: selected,
                  onChanged: (value) {
                    if (!value) {
                      return;
                    }
                    setState(() => currentMode = mode);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(mode.label(context.l10n)),
                  ),
                );
              }

              Widget buildPickerBody() {
                switch (currentMode) {
                  case _ColorAdjustMode.fluentBox:
                    return _FluentColorPickerHost(
                      key: const ValueKey('fluentBox'),
                      color: previewColor,
                      spectrumShape: ColorSpectrumShape.box,
                      onChanged: (color) => setState(() {
                        previewColor = color;
                      }),
                    );
                  case _ColorAdjustMode.fluentRing:
                    return _FluentColorPickerHost(
                      key: const ValueKey('fluentRing'),
                      color: previewColor,
                      spectrumShape: ColorSpectrumShape.ring,
                      onChanged: (color) => setState(() {
                        previewColor = color;
                      }),
                    );
                  case _ColorAdjustMode.numericSliders:
                    return _ColorSliderEditor(
                      key: const ValueKey('numericSliders'),
                      color: previewColor,
                      onChanged: (color) => setState(() {
                        previewColor = color;
                      }),
                    );
                  case _ColorAdjustMode.boardPanel:
                    return _BoardPanelColorPicker(
                      key: const ValueKey('boardPanel'),
                      color: previewColor,
                      onChanged: (color) => setState(() {
                        previewColor = color;
                      }),
                    );
                }
              }

              return SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _ColorAdjustMode.values
                          .map(buildModeChooser)
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: buildPickerBody(),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            if (onCleared != null)
              Button(
                onPressed: () {
                  Navigator.of(context).pop();
                  onCleared();
                },
                child: Text(context.l10n.clearFill),
              ),
            Button(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (isMobileOrPhone(context)) {
                  onSelected(previewColor);
                  applied = true;
                }
                Navigator.of(context).pop(previewColor);
              },
              child: Text(context.l10n.confirm),
            ),
          ],
        );
      },
    );
    if (result != null && !applied) {
      onSelected(result);
    }
  }

  Future<void> _applyPaintBucket(Offset position) async {
    if (kDebugMode) {
      debugPrint('[bucket] apply position=$position');
      final String? activeLayerId = _controller.activeLayerId;
      if (activeLayerId != null && _backend.isReady) {
        final _LayerPixels? layer = _backend.readLayerPixelsFromBackend(
          activeLayerId,
        );
        if (layer != null) {
          final Offset enginePos = _backendToEngineSpace(position);
          final int x = enginePos.dx.floor();
          final int y = enginePos.dy.floor();
          if (x >= 0 && y >= 0 && x < layer.width && y < layer.height) {
            final int pixel = layer.pixels[y * layer.width + x];
            debugPrint(
              '[bucket] debug base=0x${pixel.toRadixString(16).padLeft(8, '0')} '
              'fill=0x${_primaryColor.value.toRadixString(16).padLeft(8, '0')} '
              'engine=${layer.width}x${layer.height} start=($x,$y)',
            );
          } else {
            debugPrint(
              '[bucket] debug start out of bounds engine=${layer.width}x${layer.height} '
              'start=($x,$y)',
            );
          }
        } else {
          debugPrint('[bucket] debug readLayerPixelsFromBackend failed');
        }
      }
    }
    if (!isPointInsideSelection(position)) {
      if (kDebugMode) {
        debugPrint('[bucket] blocked: outside selection');
      }
      return;
    }
    if (_isActiveLayerLocked()) {
      if (kDebugMode) {
        debugPrint('[bucket] blocked: active layer locked');
      }
      return;
    }
    final bool applied = await _backend.bucketFill(
      position: position,
      color: _primaryColor,
      contiguous: _bucketContiguous,
      sampleAllLayers: _bucketSampleAllLayers,
      swallowColors: _resolveBucketSwallowColors(),
      tolerance: _bucketTolerance,
      fillGap: _bucketFillGap,
      antialiasLevel: _bucketAntialiasLevel,
    );
    if (kDebugMode) {
      debugPrint('[bucket] backend applied=$applied');
    }
  }

  void _updatePrimaryFromSquare(Offset position, double width, double height) {
    final double safeWidth = width <= 0 ? 1 : width;
    final double safeHeight = height <= 0 ? 1 : height;
    final double x = position.dx.clamp(0.0, safeWidth);
    final double y = position.dy.clamp(0.0, safeHeight);
    final double saturation = (x / safeWidth).clamp(0.0, 1.0);
    final double value = (1 - y / safeHeight).clamp(0.0, 1.0);
    final HSVColor updated = _primaryHsv
        .withSaturation(saturation)
        .withValue(value);
    _applyPrimaryHsv(updated);
  }

  void _updatePrimaryHue(double dy, double height) {
    final double y = dy.clamp(0.0, height);
    final double hue = (y / height).clamp(0.0, 1.0) * 360.0;
    final HSVColor updated = _primaryHsv.withHue(hue);
    _applyPrimaryHsv(updated);
  }

  void _applyPrimaryHsv(HSVColor hsv, {bool remember = false}) {
    setState(() {
      _primaryHsv = hsv;
      _primaryColor = hsv.toColor();
      if (remember) {
        _rememberColor(_primaryColor);
      }
    });
    _persistPrimaryColor();
    _handlePrimaryColorChanged();
  }

  @override
  void _setPrimaryColor(Color color, {bool remember = true}) {
    setState(() {
      _primaryColor = color;
      _primaryHsv = HSVColor.fromColor(color);
      if (remember) {
        _rememberColor(color);
      }
    });
    _persistPrimaryColor();
    _handlePrimaryColorChanged();
  }

  void _persistPrimaryColor() {
    final AppPreferences prefs = AppPreferences.instance;
    if (prefs.primaryColor.value == _primaryColor.value) {
      return;
    }
    prefs.primaryColor = _primaryColor;
    unawaited(AppPreferences.save());
  }

  void _rememberCurrentPrimary() {
    if (_recentColors.isNotEmpty &&
        _recentColors.first.value == _primaryColor.value) {
      return;
    }
    setState(() {
      _rememberColor(_primaryColor);
    });
  }

  void _rememberColor(Color color) {
    _recentColors.removeWhere((c) => c.value == color.value);
    _recentColors.insert(0, color);
    if (_recentColors.length > _recentColorCapacity) {
      _recentColors.removeRange(_recentColorCapacity, _recentColors.length);
    }
  }

  void _ensureMobileRecentFallbackColors(int count) {
    if (_mobileRecentFallbackColors.length >= count) {
      return;
    }
    final Set<int> usedValues = <int>{
      ..._recentColors.map((color) => color.value),
      ..._mobileRecentFallbackColors.map((color) => color.value),
    };
    while (_mobileRecentFallbackColors.length < count) {
      final Color candidate = Color.fromARGB(
        255,
        _brushRotationRandom.nextInt(256),
        _brushRotationRandom.nextInt(256),
        _brushRotationRandom.nextInt(256),
      );
      if (usedValues.add(candidate.value)) {
        _mobileRecentFallbackColors.add(candidate);
      }
    }
  }

  List<Color> _resolveMobileRecentColors({int count = _recentColorCapacity}) {
    final List<Color> resolved = _recentColors.take(count).toList();
    if (resolved.length >= count) {
      return resolved;
    }
    _ensureMobileRecentFallbackColors(count);
    for (final Color fallback in _mobileRecentFallbackColors) {
      if (resolved.length >= count) {
        break;
      }
      if (!resolved.any((color) => color.value == fallback.value)) {
        resolved.add(fallback);
      }
    }
    while (resolved.length < count) {
      _ensureMobileRecentFallbackColors(_mobileRecentFallbackColors.length + 1);
      final Color fallback = _mobileRecentFallbackColors.last;
      if (!resolved.any((color) => color.value == fallback.value)) {
        resolved.add(fallback);
      }
    }
    return resolved;
  }

  void _selectRecentColor(Color color) {
    _setPrimaryColor(color);
  }

  void _handleSelectColorLineColor(Color color) {
    _setTextStrokeColor(color, syncPrimary: true);
  }

  Future<void> _handleEditPrimaryColor() async {
    if (isMobileOrPhone(context)) {
      await _showMobileColorPanel();
      return;
    }
    await _pickColor(
      title: context.l10n.adjustCurrentColor,
      initialColor: _primaryColor,
      onSelected: (color) => _setPrimaryColor(color),
    );
  }

  Future<void> _handleEditTextStrokeColor() async {
    await _pickColor(
      title: context.l10n.adjustStrokeColor,
      initialColor: _colorLineColor,
      onSelected: _setTextStrokeColor,
    );
  }

  void _setTextStrokeColor(Color color, {bool syncPrimary = false}) {
    final bool changed = _colorLineColor.value != color.value;
    if (changed) {
      setState(() => _colorLineColor = color);
      final AppPreferences prefs = AppPreferences.instance;
      prefs.colorLineColor = color;
      unawaited(AppPreferences.save());
      _handleTextStrokeColorChanged(color);
    }
    if (syncPrimary) {
      _setPrimaryColor(color);
    }
  }

  Future<void> _showMobileColorPanel() async {
    bool proMode = false;
    Color previewColor = _primaryColor;
    _ColorAdjustMode currentMode = _ColorAdjustMode.fluentBox;
    await showMobileBottomSheet<void>(
      context: context,
      rebuildListenable: _mobileUiRebuildListenable,
      heightFactor: 0.7,
      builder: (context) {
        final theme = FluentTheme.of(context);
        final l10n = context.l10n;
        final List<Color> recentColors = _resolveMobileRecentColors();
        return StatefulBuilder(
          builder: (context, setState) {
            Widget buildModeChooser(_ColorAdjustMode mode) {
              final bool selected = currentMode == mode;
              return ToggleButton(
                checked: selected,
                onChanged: (value) {
                  if (!value) {
                    return;
                  }
                  setState(() => currentMode = mode);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(mode.label(context.l10n)),
                ),
              );
            }

            Widget buildPickerBody() {
              switch (currentMode) {
                case _ColorAdjustMode.fluentBox:
                  return _FluentColorPickerHost(
                    key: const ValueKey('fluentBox'),
                    color: previewColor,
                    spectrumShape: ColorSpectrumShape.box,
                    onChanged: (color) {
                      setState(() => previewColor = color);
                      _setPrimaryColor(color, remember: false);
                    },
                  );
                case _ColorAdjustMode.fluentRing:
                  return _FluentColorPickerHost(
                    key: const ValueKey('fluentRing'),
                    color: previewColor,
                    spectrumShape: ColorSpectrumShape.ring,
                    onChanged: (color) {
                      setState(() => previewColor = color);
                      _setPrimaryColor(color, remember: false);
                    },
                  );
                case _ColorAdjustMode.numericSliders:
                  return _ColorSliderEditor(
                    key: const ValueKey('numericSliders'),
                    color: previewColor,
                    onChanged: (color) {
                      setState(() => previewColor = color);
                      _setPrimaryColor(color, remember: false);
                    },
                  );
                case _ColorAdjustMode.boardPanel:
                  return _BoardPanelColorPicker(
                    key: const ValueKey('boardPanel'),
                    color: previewColor,
                    onChanged: (color) {
                      setState(() => previewColor = color);
                      _setPrimaryColor(color, remember: false);
                    },
                  );
              }
            }

            Widget buildModeButton({
              required String label,
              required bool selected,
              required VoidCallback onPressed,
            }) {
              return Expanded(
                child: selected
                    ? FilledButton(onPressed: onPressed, child: Text(label))
                    : Button(onPressed: onPressed, child: Text(label)),
              );
            }

            final Widget content = proMode
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _ColorAdjustMode.values
                            .map(buildModeChooser)
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: buildPickerBody(),
                      ),
                    ],
                  )
                : _buildColorPanelContent(
                    theme,
                    recentColorsOverride: recentColors,
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    l10n.colorPickerTitle,
                    style: theme.typography.subtitle?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: content,
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      buildModeButton(
                        label: '普通模式',
                        selected: !proMode,
                        onPressed: () {
                          if (!proMode) {
                            return;
                          }
                          setState(() => proMode = false);
                        },
                      ),
                      const SizedBox(width: 12),
                      buildModeButton(
                        label: '专业模式',
                        selected: proMode,
                        onPressed: () {
                          if (proMode) {
                            return;
                          }
                          setState(() {
                            proMode = true;
                            previewColor = _primaryColor;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted) {
      return;
    }
    _rememberCurrentPrimary();
  }

  Widget _buildMobileRecentColors(
    FluentThemeData theme, {
    Axis axis = Axis.vertical,
  }) {
    final List<Color> colors = _resolveMobileRecentColors();
    if (colors.isEmpty) {
      return const SizedBox.shrink();
    }
    final Color borderColor = theme.resources.controlStrokeColorDefault;
    final Color previewBorder = Color.lerp(
      borderColor,
      Colors.transparent,
      0.35,
    )!;
    final bool horizontal = axis == Axis.horizontal;
    return Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(colors.length, (int index) {
        final Color color = colors[index];
        return Padding(
          padding: horizontal
              ? EdgeInsets.only(
                  right: index == colors.length - 1 ? 0 : 10,
                )
              : EdgeInsets.only(
                  bottom: index == colors.length - 1 ? 0 : 10,
                ),
          child: _RecentColorSwatch(
            color: color,
            selected: color.value == _primaryColor.value,
            borderColor: previewBorder,
            onTap: () => _selectRecentColor(color),
          ),
        );
      }),
    );
  }

  Widget? _buildColorPanelTrailing(FluentThemeData theme) {
    if (_recentColors.isEmpty) {
      return null;
    }
    final int count = math.min(5, _recentColors.length);
    final Color borderColor = theme.resources.controlStrokeColorDefault;
    final Color previewBorder = Color.lerp(
      borderColor,
      Colors.transparent,
      0.35,
    )!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(count, (int index) {
        final Color color = _recentColors[index];
        return Padding(
          padding: EdgeInsets.only(left: index == 0 ? 0 : 6),
          child: _InlineRecentColorSwatch(
            color: color,
            selected: color.value == _primaryColor.value,
            borderColor: previewBorder,
            onTap: () => _selectRecentColor(color),
          ),
        );
      }),
    );
  }

  Widget _buildColorLineSelector(FluentThemeData theme) {
    final Color borderColor = theme.resources.controlStrokeColorDefault;
    final Color previewBorder = Color.lerp(
      borderColor,
      Colors.transparent,
      0.35,
    )!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(context.l10n.colorLine, style: theme.typography.bodyStrong),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: kColorLinePresets
                .map((Color color) {
                  return _ColorLineSwatch(
                    color: color,
                    selected: color.value == _colorLineColor.value,
                    borderColor: previewBorder,
                    onTap: () => _handleSelectColorLineColor(color),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _buildColorPanelContent(
    FluentThemeData theme, {
    List<Color>? recentColorsOverride,
  }) {
    final Color borderColor = theme.resources.controlStrokeColorDefault;
    final Color previewBorder = Color.lerp(
      borderColor,
      Colors.transparent,
      0.35,
    )!;
    final List<Color> recentColors = recentColorsOverride ??
        (_recentColors.length > 5 ? _recentColors.sublist(5) : <Color>[]);
    return LayoutBuilder(
      builder: (context, constraints) {
        double sliderWidth = 24;
        const double spacing = 12;
        double squareSize = constraints.maxWidth - sliderWidth - spacing;
        if (squareSize <= 0) {
          squareSize = constraints.maxWidth;
          sliderWidth = 0;
        }

        final HSVColor hsv = _primaryHsv;

        Widget buildColorSquare({
          required double width,
          required double height,
        }) {
          return GestureDetector(
            onPanDown: (details) =>
                _updatePrimaryFromSquare(details.localPosition, width, height),
            onPanUpdate: (details) =>
                _updatePrimaryFromSquare(details.localPosition, width, height),
            onPanEnd: (_) => _rememberCurrentPrimary(),
            onPanCancel: _rememberCurrentPrimary,
            onTapUp: (_) => _rememberCurrentPrimary(),
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.white,
                                  HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00FFFFFF), Color(0xFF000000)],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: (hsv.saturation.clamp(0.0, 1.0)) * width - 8,
                    top: ((1 - hsv.value.clamp(0.0, 1.0)) * height) - 8,
                    child: _ColorPickerHandle(color: hsv.toColor()),
                  ),
                ],
              ),
            ),
          );
        }

        Widget buildHueSlider(double height) {
          const List<Color> hueColors = [
            Color(0xFFFF0000), // 0° Red
            Color(0xFFFFFF00), // 60° Yellow
            Color(0xFF00FF00), // 120° Green
            Color(0xFF00FFFF), // 180° Cyan
            Color(0xFF0000FF), // 240° Blue
            Color(0xFFFF00FF), // 300° Magenta
            Color(0xFFFF0000), // 360° Red
          ];
          final double handleY = (hsv.hue.clamp(0.0, 360.0) / 360.0) * height;
          return GestureDetector(
            onPanDown: (details) =>
                _updatePrimaryHue(details.localPosition.dy, height),
            onPanUpdate: (details) =>
                _updatePrimaryHue(details.localPosition.dy, height),
            onPanEnd: (_) => _rememberCurrentPrimary(),
            onPanCancel: _rememberCurrentPrimary,
            onTapUp: (_) => _rememberCurrentPrimary(),
            child: SizedBox(
              width: sliderWidth,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: hueColors,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: handleY - 8,
                    left: (sliderWidth - 32) / 2,
                    child: const _HueSliderHandle(),
                  ),
                ],
              ),
            ),
          );
        }

        Widget buildRecentColors(List<Color> colors) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors
                .map<Widget>(
                  (color) => _RecentColorSwatch(
                    color: color,
                    selected: color.value == _primaryColor.value,
                    borderColor: previewBorder,
                    onTap: () => _selectRecentColor(color),
                  ),
                )
                .toList(growable: false),
          );
        }

        Widget buildInteractiveArea({required bool expanded}) {
          final Widget layout = LayoutBuilder(
            builder: (context, areaConstraints) {
              final double resolvedHeight =
                  areaConstraints.maxHeight.isFinite &&
                      areaConstraints.maxHeight > 0
                  ? areaConstraints.maxHeight
                  : squareSize;
              final double colorHeight = resolvedHeight > 0
                  ? resolvedHeight
                  : squareSize;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: squareSize,
                    height: colorHeight,
                    child: buildColorSquare(
                      width: squareSize,
                      height: colorHeight,
                    ),
                  ),
                  if (sliderWidth > 0) ...[
                    const SizedBox(width: spacing),
                    SizedBox(
                      width: sliderWidth,
                      height: colorHeight,
                      child: buildHueSlider(colorHeight),
                    ),
                  ],
                ],
              );
            },
          );
          if (!expanded) {
            return layout;
          }
          return Expanded(child: layout);
        }

        final bool enforceHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: enforceHeight ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _buildColorLineSelector(theme),
            const SizedBox(height: 12),
            if (recentColors.isNotEmpty) ...[
              const SizedBox(height: 12),
              buildRecentColors(recentColors),
            ],
            const SizedBox(height: 16),
            buildInteractiveArea(expanded: enforceHeight),
          ],
        );
      },
    );
  }

  Widget _buildColorIndicator(FluentThemeData theme) {
    final bool isDark = theme.brightness.isDark;
    final Color borderColor = isDark
        ? const Color(0xFF373737)
        : const Color(0xFFD6D6D6);
    final Color background = isDark ? const Color(0xFF1B1B1F) : Colors.white;
    final l10n = context.l10n;
    final bool eraserActive = _brushToolsEraserMode;
    final bool cspLayout =
        widget.toolbarLayoutStyle == PaintingToolbarLayoutStyle.csp;
    return AppNotificationAnchor(
      child: HoverDetailTooltip(
        message: '${l10n.currentColor} ${_hexStringForColor(_primaryColor)}',
        detail: l10n.colorIndicatorDetail,
        child: _ColorIndicatorButton(
          color: _primaryColor,
          borderColor: borderColor,
          backgroundColor: background,
          isDark: isDark,
          eraserActive: eraserActive,
          framed: !cspLayout,
          onColorTap: () {
            if (eraserActive) {
              _updateBrushToolsEraserMode(false);
              return;
            }
            _handleEditPrimaryColor();
          },
          onEraserTap: () {
            if (!eraserActive) {
              _updateBrushToolsEraserMode(true);
            }
          },
        ),
      ),
    );
  }
}
