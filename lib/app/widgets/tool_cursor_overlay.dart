import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../../canvas/brush_shape_geometry.dart';
import '../../canvas/canvas_tools.dart';

class ToolCursorStyle {
  const ToolCursorStyle({
    required this.icon,
    required this.anchor,
    this.iconOffset = Offset.zero,
    this.hideSystemCursor = true,
  });

  final Widget icon;
  final Offset anchor;
  final Offset iconOffset;
  final bool hideSystemCursor;
}

class ToolCursorStyles {
  static ToolCursorStyle? styleFor(CanvasTool tool) => _styles[tool];

  static bool hasOverlay(CanvasTool tool) => _styles.containsKey(tool);

  static const double _defaultIconSize = 20;
  static const double crosshairSize = 11;
  static const List<Offset> _defaultOutlineOffsets = <Offset>[
    Offset(-0.75, 0),
    Offset(0.75, 0),
    Offset(0, -0.75),
    Offset(0, 0.75),
    Offset(-0.75, -0.75),
    Offset(0.75, -0.75),
    Offset(-0.75, 0.75),
    Offset(0.75, 0.75),
  ];

  static final Map<CanvasTool, ToolCursorStyle> _styles =
      <CanvasTool, ToolCursorStyle>{
        CanvasTool.eyedropper: ToolCursorStyle(
          anchor: const Offset(5, 17),
          iconOffset: const Offset(5, -2),
          icon: const _OutlinedToolCursorIcon(
            size: _defaultIconSize,
            icon: FluentIcons.eyedropper,
          ),
        ),
        CanvasTool.bucket: ToolCursorStyle(
          anchor: const Offset(8, 18),
          iconOffset: const Offset(5, -2),
          icon: const _OutlinedToolCursorIcon(
            size: _defaultIconSize,
            icon: FluentIcons.bucket_color,
            mirrorHorizontally: true,
          ),
        ),
        CanvasTool.layerAdjust: ToolCursorStyle(
          anchor: Offset.zero,
          iconOffset: const Offset(0, 0),
          icon: const _OutlinedToolCursorIcon(
            size: _defaultIconSize,
            icon: FluentIcons.move,
          ),
        ),
        CanvasTool.magicWand: ToolCursorStyle(
          anchor: Offset.zero,
          iconOffset: const Offset(-5.5, -5.5),
          icon: const _OutlinedToolCursorIcon(
            size: _defaultIconSize,
            icon: FluentIcons.auto_enhance_on,
            mirrorHorizontally: true,
          ),
        ),
      };

  static Widget _buildIcon({
    required IconData icon,
    required double size,
    required Color color,
    bool mirrorHorizontally = false,
  }) {
    Widget child = Icon(icon, size: size, color: color);
    if (mirrorHorizontally) {
      child = Transform.scale(
        scaleX: -1,
        scaleY: 1,
        alignment: Alignment.center,
        child: child,
      );
    }
    return child;
  }

  static Widget buildOutlinedIcon({
    required IconData icon,
    required double size,
    bool mirrorHorizontally = false,
    Color outlineColor = Colors.white,
    Color fillColor = Colors.black,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final Offset offset in _defaultOutlineOffsets)
            Transform.translate(
              offset: offset,
              child: _buildIcon(
                icon: icon,
                size: size,
                color: outlineColor,
                mirrorHorizontally: mirrorHorizontally,
              ),
            ),
          _buildIcon(
            icon: icon,
            size: size,
            color: fillColor,
            mirrorHorizontally: mirrorHorizontally,
          ),
        ],
      ),
    );
  }

  static Widget iconFor(CanvasTool tool, {required bool isDragging}) {
    final ToolCursorStyle? style = styleFor(tool);
    if (style == null) {
      return const SizedBox.shrink();
    }
    if (tool == CanvasTool.layerAdjust && isDragging) {
      return buildOutlinedIcon(
        icon: FluentIcons.hands_free,
        size: _defaultIconSize,
      );
    }
    return style.icon;
  }
}

class PenCursorOverlay extends StatelessWidget {
  const PenCursorOverlay({
    super.key,
    required this.position,
    required this.diameter,
    required this.shape,
  });

  final Offset position;
  final double diameter;
  final BrushShape shape;

  @override
  Widget build(BuildContext context) {
    final double clampedDiameter = diameter.isFinite && diameter > 0
        ? diameter
        : 1.0;
    final double radius = clampedDiameter / 2;
    final double outerRadius = radius + 1;
    final double side = (outerRadius * 2 + 2).ceilToDouble();

    return Positioned(
      left: position.dx - side / 2,
      top: position.dy - side / 2,
      child: IgnorePointer(
        ignoring: true,
        child: SizedBox(
          width: side,
          height: side,
          child: CustomPaint(
            painter: _PenCursorPainter(radius: radius, shape: shape),
            isComplex: false,
            willChange: false,
          ),
        ),
      ),
    );
  }
}

class _PenCursorPainter extends CustomPainter {
  const _PenCursorPainter({required this.radius, required this.shape});

  final double radius;
  final BrushShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);

    final Paint whiteStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = false;

    final Paint blackStroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = false;

    final double outerRadius = radius + 1;
    final double innerRadius = math.max(radius - 1, 0);

    if (outerRadius > 0) {
      final Path outline = BrushShapeGeometry.pathFor(
        shape,
        center,
        outerRadius,
      );
      canvas.drawPath(outline, whiteStroke);
    }
    if (radius > 0) {
      final Path outline = BrushShapeGeometry.pathFor(shape, center, radius);
      canvas.drawPath(outline, blackStroke);
    }
    if (innerRadius > 0) {
      final Path outline = BrushShapeGeometry.pathFor(
        shape,
        center,
        innerRadius,
      );
      canvas.drawPath(outline, whiteStroke);
    } else {
      final Paint centerDot = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill
        ..isAntiAlias = false;
      canvas.drawRect(
        Rect.fromCenter(center: center, width: 1, height: 1),
        centerDot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PenCursorPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.shape != shape;
}

class _OutlinedToolCursorIcon extends StatelessWidget {
  const _OutlinedToolCursorIcon({
    required this.icon,
    this.size = ToolCursorStyles._defaultIconSize,
    this.mirrorHorizontally = false,
  });

  final IconData icon;
  final double size;
  final bool mirrorHorizontally;

  @override
  Widget build(BuildContext context) {
    return ToolCursorStyles.buildOutlinedIcon(
      icon: icon,
      size: size,
      mirrorHorizontally: mirrorHorizontally,
    );
  }
}

class ToolCursorCrosshair extends StatelessWidget {
  const ToolCursorCrosshair({super.key});

  static const double size = ToolCursorStyles.crosshairSize;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ToolCursorCrosshairPainter()),
    );
  }
}

class _ToolCursorCrosshairPainter extends CustomPainter {
  const _ToolCursorCrosshairPainter();

  static const double _outlineWidth = 2.0;
  static const double _innerWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double arm = size.width / 2;

    void drawCross(Paint paint) {
      canvas.drawLine(
        Offset(center.dx, center.dy - arm),
        Offset(center.dx, center.dy + arm),
        paint,
      );
      canvas.drawLine(
        Offset(center.dx - arm, center.dy),
        Offset(center.dx + arm, center.dy),
        paint,
      );
    }

    final Paint outline = Paint()
      ..color = Colors.white
      ..strokeWidth = _outlineWidth
      ..strokeCap = StrokeCap.square;
    final Paint inner = Paint()
      ..color = Colors.black
      ..strokeWidth = _innerWidth
      ..strokeCap = StrokeCap.square;

    drawCross(outline);
    drawCross(inner);
  }

  @override
  bool shouldRepaint(covariant _ToolCursorCrosshairPainter oldDelegate) =>
      false;
}
