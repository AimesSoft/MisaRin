part of 'painting_board.dart';

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
        border: Border.all(color: Colors.black.withOpacity(0.8), width: 2),
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
        border: Border.all(color: Colors.black.withOpacity(0.7), width: 2),
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
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ]
        : (showHover
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(
                      theme.brightness.isDark ? 0.25 : 0.12,
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
              color: Colors.black.withOpacity(0.18),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ]
        : (showHover
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(
                      theme.brightness.isDark ? 0.25 : 0.1,
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
    required this.eraserActive,
    required this.onColorTap,
    required this.onEraserTap,
    this.framed = true,
  });

  final Color color;
  final Color borderColor;
  final Color backgroundColor;
  final bool isDark;
  final bool eraserActive;
  final VoidCallback onColorTap;
  final VoidCallback onEraserTap;
  final bool framed;

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

  Widget _buildSwatch({
    required double size,
    required BorderRadius radius,
    required Color borderColor,
    required List<BoxShadow>? shadow,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: borderColor, width: 1),
              boxShadow: shadow,
            ),
            child: ClipRRect(borderRadius: radius, child: child),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color hoverOverlay = (widget.isDark ? Colors.white : Colors.black)
        .withOpacity(widget.isDark ? 0.08 : 0.05);
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
              color: Colors.black.withOpacity(widget.isDark ? 0.35 : 0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ]
        : null;
    const Color swatchBorder = Colors.black;
    final Color checkerLight = widget.isDark
        ? const Color(0xFF363636)
        : const Color(0xFFF5F5F5);
    final Color checkerDark = widget.isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFE0E0E0);
    final List<BoxShadow> frontShadow = [
      BoxShadow(
        color: Colors.black.withOpacity(widget.isDark ? 0.35 : 0.2),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];

    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: SizedBox(
        width: CanvasToolbar.buttonSize,
        height: CanvasToolbar.buttonSize,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: widget.framed
              ? BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border, width: 1.5),
                  boxShadow: shadows,
                )
              : null,
          padding: widget.framed ? const EdgeInsets.all(6) : EdgeInsets.zero,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double size = constraints.biggest.shortestSide;
              if (size <= 0) {
                return const SizedBox();
              }
              final double swatchSize = size * 2 / 3;
              final double offset = size - swatchSize;
              final BorderRadius radius = BorderRadius.circular(4);
              final bool eraserFront = widget.eraserActive;
              final Widget colorSwatch = Positioned(
                left: 0,
                top: 0,
                child: _buildSwatch(
                  size: swatchSize,
                  radius: radius,
                  borderColor: swatchBorder,
                  shadow: eraserFront ? null : frontShadow,
                  onTap: widget.onColorTap,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: widget.color),
                  ),
                ),
              );
              final Widget eraserSwatch = Positioned(
                left: offset,
                top: offset,
                child: _buildSwatch(
                  size: swatchSize,
                  radius: radius,
                  borderColor: swatchBorder,
                  shadow: eraserFront ? frontShadow : null,
                  onTap: widget.onEraserTap,
                  child: CustomPaint(
                    painter: _TwoByTwoCheckerPainter(
                      light: checkerLight,
                      dark: checkerDark,
                    ),
                  ),
                ),
              );
              return Stack(
                children: eraserFront
                    ? <Widget>[colorSwatch, eraserSwatch]
                    : <Widget>[eraserSwatch, colorSwatch],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TwoByTwoCheckerPainter extends CustomPainter {
  const _TwoByTwoCheckerPainter({
    required this.light,
    required this.dark,
  });

  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    final double cellWidth = size.width / 2;
    final double cellHeight = size.height / 2;
    final Paint lightPaint = Paint()..color = light;
    final Paint darkPaint = Paint()..color = dark;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cellWidth, cellHeight),
      lightPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(cellWidth, 0, cellWidth, cellHeight),
      darkPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, cellHeight, cellWidth, cellHeight),
      darkPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(cellWidth, cellHeight, cellWidth, cellHeight),
      lightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TwoByTwoCheckerPainter oldDelegate) {
    return oldDelegate.light != light || oldDelegate.dark != dark;
  }
}

class _ColorHexPreview extends StatelessWidget {
  const _ColorHexPreview({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final bool isDark = theme.brightness.isDark;
    final String hex = _hexStringForColor(color);
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.18)
                    : Colors.black.withOpacity(0.08),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(decoration: BoxDecoration(color: color)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.currentColor, style: theme.typography.bodyStrong),
                const SizedBox(height: 2),
                Text(hex, style: theme.typography.caption),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: '${l10n.menuCopy} $hex',
              child: IconButton(
                icon: const Icon(FluentIcons.copy),
                onPressed: () => _copyHex(context, hex),
                style: ButtonStyle(
                  padding: WidgetStateProperty.all<EdgeInsets>(
                    const EdgeInsets.all(6),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyHex(BuildContext context, String hex) {
    Clipboard.setData(ClipboardData(text: hex));
    AppNotifications.show(
      context,
      message: context.l10n.copiedHex(hex),
      severity: InfoBarSeverity.success,
      duration: const Duration(seconds: 2),
    );
  }
}

class _FluentColorPickerHost extends StatelessWidget {
  const _FluentColorPickerHost({
    super.key,
    required this.color,
    required this.onChanged,
    required this.spectrumShape,
  });

  final Color color;
  final ValueChanged<Color> onChanged;
  final ColorSpectrumShape spectrumShape;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ColorPicker(
          color: color,
          onChanged: onChanged,
          colorSpectrumShape: spectrumShape,
          isMoreButtonVisible: false,
          isColorChannelTextInputVisible: false,
          isHexInputVisible: false,
          isColorSliderVisible: true,
          isAlphaEnabled: false,
          isAlphaSliderVisible: false,
          isAlphaTextInputVisible: false,
        ),
        const SizedBox(height: 16),
        _ColorHexPreview(color: color),
      ],
    );
  }
}

enum _ColorAdjustMode { fluentBox, fluentRing, numericSliders, boardPanel }

extension _ColorAdjustModeLabel on _ColorAdjustMode {
  String label(AppLocalizations l10n) {
    switch (this) {
      case _ColorAdjustMode.fluentBox:
        return l10n.hsvBoxSpectrum;
      case _ColorAdjustMode.fluentRing:
        return l10n.hueRingSpectrum;
      case _ColorAdjustMode.numericSliders:
        return l10n.rgbHsvSliders;
      case _ColorAdjustMode.boardPanel:
        return l10n.boardPanelPicker;
    }
  }
}

class _ColorSliderEditor extends StatelessWidget {
  const _ColorSliderEditor({
    super.key,
    required this.color,
    required this.onChanged,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final HSVColor hsv = HSVColor.fromColor(color);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.rgb, style: theme.typography.bodyStrong),
        const SizedBox(height: 4),
        _buildSliderRow(
          context,
          label: l10n.red,
          value: color.red.toDouble(),
          min: 0,
          max: 255,
          divisions: 255,
          displayValue: color.red.toString(),
          onChanged: (value) => onChanged(color.withRed(value.round())),
        ),
        _buildSliderRow(
          context,
          label: l10n.green,
          value: color.green.toDouble(),
          min: 0,
          max: 255,
          divisions: 255,
          displayValue: color.green.toString(),
          onChanged: (value) => onChanged(color.withGreen(value.round())),
        ),
        _buildSliderRow(
          context,
          label: l10n.blue,
          value: color.blue.toDouble(),
          min: 0,
          max: 255,
          divisions: 255,
          displayValue: color.blue.toString(),
          onChanged: (value) => onChanged(color.withBlue(value.round())),
        ),
        const SizedBox(height: 12),
        Text(l10n.hsv, style: theme.typography.bodyStrong),
        const SizedBox(height: 4),
        _buildSliderRow(
          context,
          label: l10n.hue,
          value: hsv.hue.clamp(0, 360),
          min: 0,
          max: 360,
          divisions: 360,
          displayValue: hsv.hue.round().toString(),
          onChanged: (value) => onChanged(hsv.withHue(value).toColor()),
        ),
        _buildSliderRow(
          context,
          label: l10n.saturation,
          value: hsv.saturation.clamp(0, 1),
          min: 0,
          max: 1,
          divisions: 100,
          displayValue: '${(hsv.saturation * 100).round()}%',
          onChanged: (value) =>
              onChanged(hsv.withSaturation(value.clamp(0.0, 1.0)).toColor()),
        ),
        _buildSliderRow(
          context,
          label: l10n.value,
          value: hsv.value.clamp(0, 1),
          min: 0,
          max: 1,
          divisions: 100,
          displayValue: '${(hsv.value * 100).round()}%',
          onChanged: (value) =>
              onChanged(hsv.withValue(value.clamp(0.0, 1.0)).toColor()),
        ),
        const SizedBox(height: 16),
        _ColorHexPreview(color: color),
      ],
    );
  }

  Widget _buildSliderRow(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String? displayValue,
    int? divisions,
  }) {
    final FluentThemeData theme = FluentTheme.of(context);
    final String resolvedDisplay = displayValue ?? value.toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.typography.body),
              Text(resolvedDisplay, style: theme.typography.caption),
            ],
          ),
          Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value.clamp(min, max),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _BoardPanelColorPicker extends StatefulWidget {
  const _BoardPanelColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<_BoardPanelColorPicker> createState() => _BoardPanelColorPickerState();
}

class _BoardPanelColorPickerState extends State<_BoardPanelColorPicker> {
  late HSVColor _currentHsv;

  @override
  void initState() {
    super.initState();
    _currentHsv = HSVColor.fromColor(widget.color);
  }

  @override
  void didUpdateWidget(covariant _BoardPanelColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color.value != widget.color.value) {
      _currentHsv = HSVColor.fromColor(widget.color);
    }
  }

  @override
  Widget build(BuildContext context) {
    const double spacing = 12;
    final Color displayColor = _currentHsv.toColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            double sliderWidth = 24;
            double availableWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 320;
            double squareSize = availableWidth - sliderWidth - spacing;
            if (squareSize <= 0) {
              squareSize = availableWidth;
              sliderWidth = 0;
            }
            final double colorHeight = squareSize > 0
                ? squareSize
                : availableWidth;

            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: colorHeight),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: squareSize,
                    height: colorHeight,
                    child: _buildColorSquare(squareSize, colorHeight),
                  ),
                  if (sliderWidth > 0) ...[
                    const SizedBox(width: spacing),
                    SizedBox(
                      width: sliderWidth,
                      height: colorHeight,
                      child: _buildHueSlider(colorHeight),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _ColorHexPreview(color: displayColor),
      ],
    );
  }

  Widget _buildColorSquare(double width, double height) {
    final HSVColor hsv = _currentHsv;
    return GestureDetector(
      onPanDown: (details) =>
          _updateFromSquare(details.localPosition, width, height),
      onPanUpdate: (details) =>
          _updateFromSquare(details.localPosition, width, height),
      onTapUp: (_) => _updateFromSquare(
        Offset(
          hsv.saturation.clamp(0.0, 1.0) * width,
          (1 - hsv.value.clamp(0.0, 1.0)) * height,
        ),
        width,
        height,
      ),
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
              left: hsv.saturation.clamp(0.0, 1.0) * width - 8,
              top: (1 - hsv.value.clamp(0.0, 1.0)) * height - 8,
              child: _ColorPickerHandle(color: hsv.toColor()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHueSlider(double height) {
    const List<Color> hueColors = [
      Color(0xFFFF0000),
      Color(0xFFFFFF00),
      Color(0xFF00FF00),
      Color(0xFF00FFFF),
      Color(0xFF0000FF),
      Color(0xFFFF00FF),
      Color(0xFFFF0000),
    ];
    final double handleY = (_currentHsv.hue.clamp(0.0, 360.0) / 360.0) * height;
    return GestureDetector(
      onPanDown: (details) => _updateHue(details.localPosition.dy, height),
      onPanUpdate: (details) => _updateHue(details.localPosition.dy, height),
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
            left: -4,
            right: -4,
            child: const _HueSliderHandle(),
          ),
        ],
      ),
    );
  }

  void _updateFromSquare(Offset position, double width, double height) {
    final double safeWidth = width <= 0 ? 1 : width;
    final double safeHeight = height <= 0 ? 1 : height;
    final double x = position.dx.clamp(0.0, safeWidth);
    final double y = position.dy.clamp(0.0, safeHeight);
    final double saturation = (x / safeWidth).clamp(0.0, 1.0);
    final double value = (1 - y / safeHeight).clamp(0.0, 1.0);
    _setColor(_currentHsv.withSaturation(saturation).withValue(value));
  }

  void _updateHue(double dy, double height) {
    final double y = dy.clamp(0.0, height);
    final double hue = (y / height).clamp(0.0, 1.0) * 360.0;
    _setColor(_currentHsv.withHue(hue));
  }

  void _setColor(HSVColor hsv) {
    setState(() {
      _currentHsv = hsv;
    });
    widget.onChanged(hsv.toColor());
  }
}
