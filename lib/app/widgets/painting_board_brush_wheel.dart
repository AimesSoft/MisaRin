part of 'painting_board.dart';

const double _kBrushPresetWheelOuterRadius = 168.0;
const double _kBrushPresetWheelInnerRadius = 52.0;
const double _kBrushPresetWheelEdgePadding = 18.0;

extension _PaintingBoardBrushWheelExtension on _PaintingBoardInteractionMixin {
  bool get _isBrushPresetWheelTool {
    return _activeTool == CanvasTool.pen;
  }

  bool _isBrushPresetWheelModifier(LogicalKeyboardKey key) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return key == LogicalKeyboardKey.meta ||
          key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight;
    }
    return key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight;
  }

  List<BrushPreset> get _brushPresetWheelPresets {
    return _brushLibrary?.presets ?? const <BrushPreset>[];
  }

  bool get _canShowBrushPresetWheel {
    return _isBrushPresetWheelTool &&
        !_isTextEditingActive &&
        !_layerTransformModeActive &&
        !_isDrawing &&
        _backendActivePointer == null &&
        _brushPresetWheelPresets.isNotEmpty;
  }

  int _brushPresetWheelSelectedIndex(List<BrushPreset> presets) {
    final String selectedId =
        _activeBrushPreset?.id ?? _brushLibrary?.selectedId ?? '';
    final int index = presets.indexWhere(
      (BrushPreset preset) => preset.id == selectedId,
    );
    return index < 0 ? 0 : index;
  }

  Offset _clampBrushPresetWheelCenter(Offset center) {
    final Size size = _workspaceSize;
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
      return center;
    }
    final double radius = math.min(
      _kBrushPresetWheelOuterRadius,
      math.max(96.0, math.min(size.width, size.height) * 0.42),
    );
    final double padding = radius + _kBrushPresetWheelEdgePadding;
    final double minX = math.min(padding, size.width / 2);
    final double maxX = math.max(size.width - padding, minX);
    final double minY = math.min(padding, size.height / 2);
    final double maxY = math.max(size.height - padding, minY);
    return Offset(center.dx.clamp(minX, maxX), center.dy.clamp(minY, maxY));
  }

  Offset _resolveBrushPresetWheelCenter() {
    final Offset? pointer = _lastWorkspacePointer;
    if (pointer != null &&
        !_isInsideToolArea(pointer) &&
        !_isInsideWorkspacePanelArea(pointer) &&
        _boardRect.contains(pointer)) {
      return _clampBrushPresetWheelCenter(pointer);
    }
    final Rect boardRect = _boardRect;
    if (!boardRect.isEmpty) {
      return _clampBrushPresetWheelCenter(boardRect.center);
    }
    return _clampBrushPresetWheelCenter(
      Offset(_workspaceSize.width / 2, _workspaceSize.height / 2),
    );
  }

  int? _brushPresetWheelIndexForPosition(
    Offset position,
    int presetCount, {
    Offset? centerOverride,
  }) {
    if (presetCount <= 0) {
      return null;
    }
    final Offset? center = centerOverride ?? _brushPresetWheelCenter;
    if (center == null) {
      return null;
    }
    final Offset delta = position - center;
    if (delta.distance < _kBrushPresetWheelInnerRadius * 0.65) {
      return _brushPresetWheelSelectedIndex(_brushPresetWheelPresets);
    }
    final double sweep = math.pi * 2 / presetCount;
    final double rawAngle = math.atan2(delta.dy, delta.dx);
    final double shifted = (rawAngle + math.pi / 2 + sweep / 2) % (math.pi * 2);
    return (shifted / sweep).floor().clamp(0, presetCount - 1);
  }

  void _beginBrushPresetWheel() {
    if (!_canShowBrushPresetWheel) {
      return;
    }
    final List<BrushPreset> presets = _brushPresetWheelPresets;
    final Offset center = _resolveBrushPresetWheelCenter();
    final Offset? pointer = _lastWorkspacePointer;
    final int selected = _brushPresetWheelSelectedIndex(presets);
    final int? hover = pointer == null
        ? selected
        : _brushPresetWheelIndexForPosition(
            pointer,
            presets.length,
            centerOverride: center,
          );
    setState(() {
      _brushPresetWheelActive = true;
      _brushPresetWheelCenter = center;
      _brushPresetWheelHoverIndex = hover ?? selected;
      _toolCursorPosition = null;
      _penCursorWorkspacePosition = null;
    });
  }

  void _updateBrushPresetWheelPointer(Offset position) {
    if (!_brushPresetWheelActive) {
      return;
    }
    final List<BrushPreset> presets = _brushPresetWheelPresets;
    final int? nextIndex = _brushPresetWheelIndexForPosition(
      position,
      presets.length,
    );
    if (nextIndex == null || nextIndex == _brushPresetWheelHoverIndex) {
      return;
    }
    setState(() => _brushPresetWheelHoverIndex = nextIndex);
  }

  void _nudgeBrushPresetWheelSelection(int direction) {
    if (!_brushPresetWheelActive || direction == 0) {
      return;
    }
    final int count = _brushPresetWheelPresets.length;
    if (count <= 0) {
      return;
    }
    final int current =
        _brushPresetWheelHoverIndex ??
        _brushPresetWheelSelectedIndex(_brushPresetWheelPresets);
    final int next = (current + direction) % count;
    setState(
      () => _brushPresetWheelHoverIndex = next < 0 ? next + count : next,
    );
  }

  void _finishBrushPresetWheel({required bool commit}) {
    if (!_brushPresetWheelActive) {
      return;
    }
    final List<BrushPreset> presets = _brushPresetWheelPresets;
    final int? index = _brushPresetWheelHoverIndex;
    setState(() {
      _brushPresetWheelActive = false;
      _brushPresetWheelCenter = null;
      _brushPresetWheelHoverIndex = null;
    });
    if (commit && index != null && index >= 0 && index < presets.length) {
      _selectBrushPreset(presets[index].id);
    }
    final Offset? pointer = _lastWorkspacePointer;
    if (pointer != null && _boardRect.contains(pointer)) {
      _updateToolCursorOverlay(pointer);
    }
  }

  Widget _buildBrushPresetWheelOverlay(FluentThemeData theme) {
    if (!_brushPresetWheelActive) {
      return const Positioned.fill(child: SizedBox.shrink());
    }
    final Offset? center = _brushPresetWheelCenter;
    final BrushLibrary? library = _brushLibrary;
    final List<BrushPreset> presets = _brushPresetWheelPresets;
    if (center == null || library == null || presets.isEmpty) {
      return const Positioned.fill(child: SizedBox.shrink());
    }
    final int selectedIndex = _brushPresetWheelSelectedIndex(presets);
    final int hoverIndex = (_brushPresetWheelHoverIndex ?? selectedIndex).clamp(
      0,
      presets.length - 1,
    );
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: _BrushPresetWheelOverlay(
          center: center,
          presets: presets,
          selectedIndex: selectedIndex,
          hoverIndex: hoverIndex,
          library: library,
          strokeColor: _primaryColor,
          theme: theme,
        ),
      ),
    );
  }
}

class _BrushPresetWheelOverlay extends StatelessWidget {
  const _BrushPresetWheelOverlay({
    required this.center,
    required this.presets,
    required this.selectedIndex,
    required this.hoverIndex,
    required this.library,
    required this.strokeColor,
    required this.theme,
  });

  final Offset center;
  final List<BrushPreset> presets;
  final int selectedIndex;
  final int hoverIndex;
  final BrushLibrary library;
  final Color strokeColor;
  final FluentThemeData theme;

  @override
  Widget build(BuildContext context) {
    final double shortest = math.min(
      MediaQuery.sizeOf(context).width,
      MediaQuery.sizeOf(context).height,
    );
    final double radius = math.min(
      _kBrushPresetWheelOuterRadius,
      math.max(96.0, shortest * 0.42),
    );
    final double labelRadius = radius * 0.72;
    final bool compact = presets.length > 12;
    final Locale locale = Localizations.localeOf(context);
    final Color textColor = theme.brightness.isDark
        ? const Color(0xFFF4F4F6)
        : const Color(0xFF202124);
    final BrushPreset hoverPreset = presets[hoverIndex];
    final List<Widget> labels = <Widget>[];
    for (int i = 0; i < presets.length; i++) {
      final double angle = -math.pi / 2 + math.pi * 2 * i / presets.length;
      final Offset labelCenter =
          center + Offset(math.cos(angle), math.sin(angle)) * labelRadius;
      final String name = library.displayNameFor(presets[i], locale);
      final bool highlighted = i == hoverIndex;
      final bool selected = i == selectedIndex;
      labels.add(
        Positioned(
          left: labelCenter.dx - (compact ? 18.0 : 42.0),
          top: labelCenter.dy - (compact ? 18.0 : 22.0),
          width: compact ? 36.0 : 84.0,
          height: compact ? 36.0 : 44.0,
          child: _BrushPresetWheelLabel(
            name: name,
            compact: compact,
            highlighted: highlighted,
            selected: selected,
            textColor: textColor,
            accentColor: theme.accentColor.defaultBrushFor(theme.brightness),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _BrushPresetWheelPainter(
            count: presets.length,
            selectedIndex: selectedIndex,
            hoverIndex: hoverIndex,
            center: center,
            outerRadius: radius,
            innerRadius: _kBrushPresetWheelInnerRadius,
            accentColor: theme.accentColor.defaultBrushFor(theme.brightness),
            dark: theme.brightness.isDark,
          ),
        ),
        ...labels,
        Positioned(
          left: center.dx - radius * 0.44,
          top: center.dy - 34,
          width: radius * 0.88,
          height: 68,
          child: _BrushPresetWheelCenter(
            preset: hoverPreset,
            name: library.displayNameFor(hoverPreset, locale),
            strokeColor: strokeColor,
            textColor: textColor,
            dark: theme.brightness.isDark,
          ),
        ),
      ],
    );
  }
}

class _BrushPresetWheelLabel extends StatelessWidget {
  const _BrushPresetWheelLabel({
    required this.name,
    required this.compact,
    required this.highlighted,
    required this.selected,
    required this.textColor,
    required this.accentColor,
  });

  final String name;
  final bool compact;
  final bool highlighted;
  final bool selected;
  final Color textColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final Color background = highlighted
        ? accentColor.withValues(alpha: 0.92)
        : selected
        ? accentColor.withValues(alpha: 0.38)
        : const Color(0xAA202328);
    final Color foreground = highlighted ? Colors.white : textColor;
    if (compact) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(
            color: highlighted
                ? Colors.white
                : Colors.white.withValues(alpha: 0.18),
            width: highlighted ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            name.isEmpty ? '' : name.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: highlighted
              ? Colors.white
              : Colors.white.withValues(alpha: 0.14),
          width: highlighted ? 1.5 : 1,
        ),
        boxShadow: [
          if (highlighted)
            BoxShadow(
              color: accentColor.withValues(alpha: 0.32),
              blurRadius: 14,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Center(
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              height: 1.1,
              fontWeight: highlighted || selected
                  ? FontWeight.w600
                  : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _BrushPresetWheelCenter extends StatelessWidget {
  const _BrushPresetWheelCenter({
    required this.preset,
    required this.name,
    required this.strokeColor,
    required this.textColor,
    required this.dark,
  });

  final BrushPreset preset;
  final String name;
  final Color strokeColor;
  final Color textColor;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xEA17191F) : const Color(0xEEF8F8FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.16),
            blurRadius: 18,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: BrushPresetStrokePreview(
                  preset: preset,
                  height: 28,
                  color: strokeColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                height: 1.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrushPresetWheelPainter extends CustomPainter {
  const _BrushPresetWheelPainter({
    required this.count,
    required this.selectedIndex,
    required this.hoverIndex,
    required this.center,
    required this.outerRadius,
    required this.innerRadius,
    required this.accentColor,
    required this.dark,
  });

  final int count;
  final int selectedIndex;
  final int hoverIndex;
  final Offset center;
  final double outerRadius;
  final double innerRadius;
  final Color accentColor;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0) {
      return;
    }
    final Paint fill = Paint()..style = PaintingStyle.fill;
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: dark ? 0.13 : 0.32);
    final Paint outerStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black.withValues(alpha: dark ? 0.55 : 0.2);
    final Rect outer = Rect.fromCircle(center: center, radius: outerRadius);
    final Rect inner = Rect.fromCircle(center: center, radius: innerRadius);
    final double sweep = math.pi * 2 / count;
    for (int i = 0; i < count; i++) {
      final bool highlighted = i == hoverIndex;
      final bool selected = i == selectedIndex;
      final double start = -math.pi / 2 - sweep / 2 + sweep * i;
      final Path segment = Path()
        ..arcTo(outer, start, sweep, false)
        ..arcTo(inner, start + sweep, -sweep, false)
        ..close();
      fill.color = highlighted
          ? accentColor.withValues(alpha: 0.72)
          : selected
          ? accentColor.withValues(alpha: 0.36)
          : (dark ? const Color(0xD91B1D24) : const Color(0xD9FFFFFF));
      canvas.drawPath(segment, fill);
      canvas.drawPath(segment, stroke);
    }
    canvas.drawCircle(center, outerRadius, outerStroke);
    fill.color = dark ? const Color(0xF01B1D24) : const Color(0xF5FFFFFF);
    canvas.drawCircle(center, innerRadius + 1, fill);
    canvas.drawCircle(center, innerRadius + 1, stroke);
  }

  @override
  bool shouldRepaint(covariant _BrushPresetWheelPainter oldDelegate) {
    return oldDelegate.count != count ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.hoverIndex != hoverIndex ||
        oldDelegate.center != center ||
        oldDelegate.outerRadius != outerRadius ||
        oldDelegate.innerRadius != innerRadius ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.dark != dark;
  }
}
