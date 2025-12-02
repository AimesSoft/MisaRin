part of 'painting_board.dart';

class _ClippingMaskIndicator extends StatelessWidget {
  const _ClippingMaskIndicator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _LayerTile extends StatefulWidget {
  const _LayerTile({
    required this.child,
    required this.backgroundColor,
    required this.borderColor,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onTap, // onTap can be null
    this.behavior = HitTestBehavior.opaque, // Default value for behavior
  });

  final Widget child;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onTapDown;
  final GestureTapDownCallback? onSecondaryTapDown;
  final HitTestBehavior behavior;

  @override
  State<_LayerTile> createState() => _LayerTileState();
}

class _LayerTileState extends State<_LayerTile> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final bool isDark = theme.brightness.isDark;
    final Color hoverOverlay = (isDark ? Colors.white : Colors.black)
        .withValues(alpha: isDark ? 0.08 : 0.05);
    final Color background = _hovered
        ? Color.alphaBlend(hoverOverlay, widget.backgroundColor)
        : widget.backgroundColor;
    final Color border = _hovered
        ? Color.lerp(
                widget.borderColor,
                theme.resources.controlStrokeColorDefault,
                0.35,
              ) ??
              widget.borderColor
        : widget.borderColor;
    final List<BoxShadow>? shadows = _hovered
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ]
        : null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        onTapDown: widget.onTapDown,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
            boxShadow: shadows,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _LayerNameView extends StatelessWidget {
  const _LayerNameView({
    required this.layer,
    required this.theme,
    required this.isActive,
    required this.isRenaming,
    required this.isLocked,
    required this.buildEditor,
    this.onRequestRename,
  });

  final BitmapLayerState layer;
  final FluentThemeData theme;
  final bool isActive;
  final bool isRenaming;
  final bool isLocked;
  final Widget Function(TextStyle? effectiveStyle) buildEditor;
  final VoidCallback? onRequestRename;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = isActive
        ? theme.typography.bodyStrong
        : theme.typography.body;
    final Widget text = Text(
      layer.name,
      style: style,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      softWrap: false,
    );
    final Widget display = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: onRequestRename,
      child: text,
    );
    if (!isRenaming || isLocked) {
      return display;
    }
    final double width = _measureWidth(context, style, layer.name) + 6;
    final double clampedWidth = width.clamp(32.0, 400.0).toDouble();
    return SizedBox(
      width: clampedWidth,
      child: Align(alignment: Alignment.centerLeft, child: buildEditor(style)),
    );
  }

  double _measureWidth(BuildContext context, TextStyle? style, String text) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}

class _LayerSidebarButtons extends StatelessWidget {
  const _LayerSidebarButtons({required this.primary, required this.secondary});

  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [primary, const SizedBox(height: 6), secondary],
      ),
    );
  }
}

class _LayerClippingToggleButton extends StatelessWidget {
  const _LayerClippingToggleButton({
    required this.active,
    required this.enabled,
    required this.onPressed,
  });

  final bool active;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final Color borderColor = theme.resources.controlStrokeColorDefault;
    final Color baseBackground =
        Color.lerp(
          borderColor.withValues(alpha: borderColor.a * 0.1),
          accent,
          0.05,
        ) ??
        borderColor.withValues(alpha: 0.1);
    final Color background = active
        ? Color.alphaBlend(
            accent.withValues(alpha: theme.brightness.isDark ? 0.35 : 0.18),
            baseBackground,
          )
        : baseBackground;
    final Color iconColor = !enabled
        ? theme.resources.textFillColorDisabled
        : (active
              ? accent
              : theme.resources.textFillColorSecondary.withValues(alpha: 0.85));

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.55,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: background,
              border: Border.all(
                color: borderColor.withValues(alpha: borderColor.a * 0.6),
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(
                FluentIcons.subtract_shape,
                size: 14,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LayerPreviewThumbnail extends StatelessWidget {
  const _LayerPreviewThumbnail({required this.image, required this.theme});

  final ui.Image? image;
  final FluentThemeData theme;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(6);
    final Widget checkerBackground = CustomPaint(
      painter: _TransparencyGridPainter(
        light: theme.brightness.isDark
            ? const Color(0xFF363636)
            : const Color(0xFFF5F5F5),
        dark: theme.brightness.isDark
            ? const Color(0xFF2A2A2A)
            : const Color(0xFFE0E0E0),
      ),
    );
    final Widget imageWidget = image == null
        ? Center(
            child: Icon(
              FluentIcons.picture,
              size: 12,
              color: theme.resources.textFillColorTertiary,
            ),
          )
        : RawImage(
            image: image,
            alignment: Alignment.center,
            filterQuality: ui.FilterQuality.none,
          );
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: _layerPreviewDisplayWidth,
        height: _layerPreviewDisplayHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            checkerBackground,
            if (image == null)
              imageWidget
            else
              Center(
                child: SizedBox(
                  width: _scaledPreviewWidth(image!),
                  height: _layerPreviewDisplayHeight,
                  child: ClipRect(child: imageWidget),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TransparencyGridPainter extends CustomPainter {
  const _TransparencyGridPainter({required this.light, required this.dark});

  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    const double cellSize = 4;
    final Paint lightPaint = Paint()..color = light;
    final Paint darkPaint = Paint()..color = dark;
    bool darkRow = false;
    for (double y = 0; y < size.height; y += cellSize) {
      bool darkCell = darkRow;
      final double nextY = math.min(size.height, y + cellSize);
      for (double x = 0; x < size.width; x += cellSize) {
        final double nextX = math.min(size.width, x + cellSize);
        canvas.drawRect(
          Rect.fromLTRB(x, y, nextX, nextY),
          darkCell ? darkPaint : lightPaint,
        );
        darkCell = !darkCell;
      }
      darkRow = !darkRow;
    }
  }

  @override
  bool shouldRepaint(covariant _TransparencyGridPainter oldDelegate) {
    return oldDelegate.light != light || oldDelegate.dark != dark;
  }
}

double _scaledPreviewWidth(ui.Image image) {
  final double height = _layerPreviewDisplayHeight;
  final double sourceHeight = image.height.toDouble().clamp(1, double.infinity);
  final double aspect = image.width.toDouble() / sourceHeight;
  return aspect * height;
}
