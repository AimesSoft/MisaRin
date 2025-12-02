part of 'painting_board.dart';

mixin _PaintingBoardColorMixin on _PaintingBoardBase {
  @override
  Future<void> _pickColor({
    required String title,
    required Color initialColor,
    required ValueChanged<Color> onSelected,
    VoidCallback? onCleared,
  }) async {
    Color previewColor = initialColor;
    final Color? result = await showDialog<Color>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return ContentDialog(
          title: Text(title),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                width: 320,
                child: ColorPicker(
                  color: previewColor,
                  onChanged: (Color color) {
                    setState(() => previewColor = color);
                  },
                  isMoreButtonVisible: false,
                  isColorChannelTextInputVisible: false,
                  isHexInputVisible: true,
                  isAlphaTextInputVisible: false,
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
                child: const Text('清除填充'),
              ),
            Button(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(previewColor),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (result != null) {
      onSelected(result);
    }
  }

  @override
  Future<void> _applyPaintBucket(Offset position) async {
    if (!isPointInsideSelection(position)) {
      return;
    }
    await _pushUndoSnapshot();
    _controller.floodFill(
      position,
      color: _primaryColor,
      contiguous: _bucketContiguous,
      sampleAllLayers: _bucketSampleAllLayers,
      swallowColors: _bucketSwallowColorLine ? kColorLinePresets : null,
      tolerance: _bucketTolerance,
      antialiasLevel: _bucketAntialiasLevel,
    );
    setState(() {});
    _markDirty();
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
  }

  void _persistPrimaryColor() {
    final AppPreferences prefs = AppPreferences.instance;
    if (prefs.primaryColor.toARGB32() == _primaryColor.toARGB32()) {
      return;
    }
    prefs.primaryColor = _primaryColor;
    unawaited(AppPreferences.save());
  }

  void _rememberCurrentPrimary() {
    if (_recentColors.isNotEmpty &&
        _recentColors.first.toARGB32() == _primaryColor.toARGB32()) {
      return;
    }
    setState(() {
      _rememberColor(_primaryColor);
    });
  }

  @override
  void _rememberColor(Color color) {
    _recentColors.removeWhere((c) => c.toARGB32() == color.toARGB32());
    _recentColors.insert(0, color);
    if (_recentColors.length > _recentColorCapacity) {
      _recentColors.removeRange(_recentColorCapacity, _recentColors.length);
    }
  }

  void _selectRecentColor(Color color) {
    _setPrimaryColor(color);
  }

  void _handleSelectColorLineColor(Color color) {
    final bool changed = _colorLineColor.toARGB32() != color.toARGB32();
    if (changed) {
      setState(() => _colorLineColor = color);
      final AppPreferences prefs = AppPreferences.instance;
      prefs.colorLineColor = color;
      unawaited(AppPreferences.save());
    }
    _setPrimaryColor(color);
  }

  Future<void> _handleEditPrimaryColor() async {
    await _pickColor(
      title: '调整当前颜色',
      initialColor: _primaryColor,
      onSelected: (color) => _setPrimaryColor(color),
    );
  }

  @override
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
            selected: color.toARGB32() == _primaryColor.toARGB32(),
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
        Text('色线', style: theme.typography.bodyStrong),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: kColorLinePresets
                .map((Color color) {
                  return _ColorLineSwatch(
                    color: color,
                    selected: color.toARGB32() == _colorLineColor.toARGB32(),
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

  @override
  Widget _buildColorPanelContent(FluentThemeData theme) {
    final Color borderColor = theme.resources.controlStrokeColorDefault;
    final Color previewBorder = Color.lerp(
      borderColor,
      Colors.transparent,
      0.35,
    )!;
    final List<Color> overflowRecent = _recentColors.length > 5
        ? _recentColors.sublist(5)
        : <Color>[];
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

        Widget buildRecentColors() {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: overflowRecent
                .map<Widget>(
                  (color) => _RecentColorSwatch(
                    color: color,
                    selected: color.toARGB32() == _primaryColor.toARGB32(),
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
            if (overflowRecent.isNotEmpty) ...[
              const SizedBox(height: 12),
              buildRecentColors(),
            ],
            const SizedBox(height: 16),
            buildInteractiveArea(expanded: enforceHeight),
          ],
        );
      },
    );
  }

  @override
  Widget _buildColorIndicator(FluentThemeData theme) {
    final bool isDark = theme.brightness.isDark;
    final Color borderColor = isDark
        ? const Color(0xFF373737)
        : const Color(0xFFD6D6D6);
    final Color background = isDark ? const Color(0xFF1B1B1F) : Colors.white;
    return AppNotificationAnchor(
      child: Tooltip(
        message: '当前颜色 ${_hexStringForColor(_primaryColor)}',
        child: _ColorIndicatorButton(
          color: _primaryColor,
          borderColor: borderColor,
          backgroundColor: background,
          isDark: isDark,
          onTap: _handleEditPrimaryColor,
        ),
      ),
    );
  }
}

class _ColorPickerHandle extends StatelessWidget {
  const _ColorPickerHandle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.8),
          width: 2,
        ),
        color: color,
      ),
    );
  }
}

class _HueSliderHandle extends StatelessWidget {
  const _HueSliderHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 16,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.7),
          width: 2,
        ),
        color: Colors.white,
      ),
    );
  }
}

class _RecentColorSwatch extends StatefulWidget {
  const _RecentColorSwatch({
    required this.color,
    required this.selected,
    required this.borderColor,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  State<_RecentColorSwatch> createState() => _RecentColorSwatchState();
}

class _RecentColorSwatchState extends State<_RecentColorSwatch> {
  bool _hovered = false;

  void _setHover(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color highlight = theme.accentColor.defaultBrushFor(theme.brightness);
    final bool showHover = _hovered && !widget.selected;
    final double size = showHover ? 34 : 32;
    final Color borderColor = widget.selected
        ? highlight
        : (showHover
              ? Color.lerp(widget.borderColor, highlight, 0.35)!
              : widget.borderColor);
    final double borderWidth = widget.selected ? 2 : (showHover ? 1.8 : 1.5);
    final List<BoxShadow>? shadows = widget.selected
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ]
        : (showHover
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.brightness.isDark ? 0.25 : 0.12,
                    ),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: widget.color,
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: shadows,
          ),
        ),
      ),
    );
  }
}

class _InlineRecentColorSwatch extends StatefulWidget {
  const _InlineRecentColorSwatch({
    required this.color,
    required this.selected,
    required this.borderColor,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  State<_InlineRecentColorSwatch> createState() =>
      _InlineRecentColorSwatchState();
}

class _InlineRecentColorSwatchState extends State<_InlineRecentColorSwatch> {
  bool _hovered = false;

  void _setHover(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color highlight = theme.accentColor.defaultBrushFor(theme.brightness);
    final bool showHover = _hovered && !widget.selected;
    final double size = showHover ? 24 : 22;
    final Color borderColor = widget.selected
        ? highlight
        : (showHover
              ? Color.lerp(widget.borderColor, highlight, 0.3)!
              : widget.borderColor);
    final double borderWidth = widget.selected ? 2 : (showHover ? 1.5 : 1.2);
    final List<BoxShadow>? shadows = widget.selected
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ]
        : (showHover
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.brightness.isDark ? 0.25 : 0.1,
                    ),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: widget.color,
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: shadows,
          ),
        ),
      ),
    );
  }
}

class _ColorLineSwatch extends StatelessWidget {
  const _ColorLineSwatch({
    required this.color,
    required this.selected,
    required this.borderColor,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _InlineRecentColorSwatch(
      color: color,
      selected: selected,
      borderColor: borderColor,
      onTap: onTap,
    );
  }
}

class _ColorIndicatorButton extends StatefulWidget {
  const _ColorIndicatorButton({
    required this.color,
    required this.borderColor,
    required this.backgroundColor,
    required this.isDark,
    required this.onTap,
  });

  final Color color;
  final Color borderColor;
  final Color backgroundColor;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_ColorIndicatorButton> createState() => _ColorIndicatorButtonState();
}

class _ColorIndicatorButtonState extends State<_ColorIndicatorButton> {
  bool _hovered = false;

  void _setHover(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    final Color hoverOverlay = (widget.isDark ? Colors.white : Colors.black)
        .withValues(alpha: widget.isDark ? 0.08 : 0.05);
    final Color background = _hovered
        ? Color.alphaBlend(hoverOverlay, widget.backgroundColor)
        : widget.backgroundColor;
    final Color border = _hovered
        ? Color.lerp(
                widget.borderColor,
                widget.isDark ? Colors.white : Colors.black,
                widget.isDark ? 0.25 : 0.15,
              ) ??
              widget.borderColor
        : widget.borderColor;
    final List<BoxShadow>? shadows = _hovered
        ? [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: widget.isDark ? 0.35 : 0.12,
              ),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ]
        : null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: CanvasToolbar.buttonSize,
          height: CanvasToolbar.buttonSize,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border, width: 1.5),
            boxShadow: shadows,
          ),
          padding: const EdgeInsets.all(6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox.expand(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.color,
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
