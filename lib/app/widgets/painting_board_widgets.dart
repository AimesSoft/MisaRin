part of 'painting_board.dart';

const Color _kVectorEraserPreviewColor = _kSelectionPreviewFillColor;

int _overlayStepForPoints(int count) {
  return 1;
}

void _paintStrokeOverlay({
  required Canvas canvas,
  required List<Offset> points,
  required List<double> radii,
  required Color color,
  required BrushShape shape,
  required int antialiasLevel,
  bool hollow = false,
  double hollowRatio = 0.0,
}) {
  if (points.isEmpty) {
    return;
  }
  final int clampedAntialias = antialiasLevel.clamp(0, 9);
  final Paint paint = Paint()
    ..color = color
    ..style = PaintingStyle.fill
    ..isAntiAlias = clampedAntialias > 0;

  final bool useHollow = hollow && hollowRatio > 0.0001;
  final Paint? clearPaint = useHollow
      ? (Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.fill
          ..isAntiAlias = clampedAntialias > 0)
      : null;
  final int step = _overlayStepForPoints(points.length);

  switch (shape) {
    case BrushShape.circle:
      _paintCircleStrokeOverlay(
        canvas,
        points,
        radii,
        paint,
        radiusScale: 1.0,
        step: step,
      );
      if (clearPaint != null) {
        _paintCircleStrokeOverlay(
          canvas,
          points,
          radii,
          clearPaint,
          radiusScale: hollowRatio.clamp(0.0, 1.0),
          step: step,
        );
      }
      return;
    case BrushShape.square:
      _paintSquareStrokeOverlay(
        canvas,
        points,
        radii,
        paint,
        radiusScale: 1.0,
        step: step,
      );
      if (clearPaint != null) {
        _paintSquareStrokeOverlay(
          canvas,
          points,
          radii,
          clearPaint,
          radiusScale: hollowRatio.clamp(0.0, 1.0),
          step: step,
        );
      }
      return;
    case BrushShape.triangle:
    case BrushShape.star:
      // 后端笔刷目前仅保证圆/方形；预览这里用圆形回退，避免 UI 报错。
      _paintCircleStrokeOverlay(
        canvas,
        points,
        radii,
        paint,
        radiusScale: 1.0,
        step: step,
      );
      if (clearPaint != null) {
        _paintCircleStrokeOverlay(
          canvas,
          points,
          radii,
          clearPaint,
          radiusScale: hollowRatio.clamp(0.0, 1.0),
          step: step,
        );
      }
      return;
  }
}

void _paintCircleStrokeOverlay(
  Canvas canvas,
  List<Offset> points,
  List<double> radii,
  Paint paint, {
  double radiusScale = 1.0,
  int step = 1,
}) {
  final int stride = math.max(1, step);
  for (int i = 0; i < points.length; i += stride) {
    final Offset p = points[i];
    final double r = (i < radii.length)
        ? radii[i]
        : (radii.isNotEmpty ? radii.last : 1.0);
    canvas.drawCircle(p, r * radiusScale, paint);
  }
  if (points.isNotEmpty && ((points.length - 1) % stride != 0)) {
    final Offset p = points.last;
    final double r = radii.isNotEmpty ? radii.last : 1.0;
    canvas.drawCircle(p, r * radiusScale, paint);
  }

  for (int i = 0; i < points.length - 1; i += stride) {
    final int j = math.min(i + stride, points.length - 1);
    final Offset p1 = points[i];
    final Offset p2 = points[j];
    final double rawR1 = (i < radii.length)
        ? radii[i]
        : (radii.isNotEmpty ? radii.last : 1.0);
    final double rawR2 = (j < radii.length) ? radii[j] : rawR1;
    final double r1 = rawR1 * radiusScale;
    final double r2 = rawR2 * radiusScale;

    final double dist = (p2 - p1).distance;
    if (dist < 0.5 || dist <= (r1 - r2).abs()) {
      continue;
    }

    final Offset direction = (p2 - p1) / dist;
    final double angle = direction.direction;

    final double sinAlpha = (r1 - r2) / dist;
    final double alpha = math.asin(sinAlpha.clamp(-1.0, 1.0));

    final double angle1 = angle + math.pi / 2 + alpha;
    final double angle2 = angle - math.pi / 2 - alpha;

    final Offset startL = p1 + Offset(math.cos(angle1), math.sin(angle1)) * r1;
    final Offset startR = p1 + Offset(math.cos(angle2), math.sin(angle2)) * r1;
    final Offset endL = p2 + Offset(math.cos(angle1), math.sin(angle1)) * r2;
    final Offset endR = p2 + Offset(math.cos(angle2), math.sin(angle2)) * r2;

    final Path segment = Path()
      ..moveTo(startL.dx, startL.dy)
      ..lineTo(endL.dx, endL.dy)
      ..lineTo(endR.dx, endR.dy)
      ..lineTo(startR.dx, startR.dy)
      ..close();

    canvas.drawPath(segment, paint);
  }
}

void _paintSquareStrokeOverlay(
  Canvas canvas,
  List<Offset> points,
  List<double> radii,
  Paint paint, {
  double radiusScale = 1.0,
  int step = 1,
}) {
  if (points.isEmpty) {
    return;
  }

  void drawSquareAt(Offset center, double radius) {
    final double clamped = math.max(radius.abs(), 0.0);
    final double halfSide = clamped <= 0 ? 0.0 : clamped / math.sqrt2;
    final Rect rect = Rect.fromCenter(
      center: center,
      width: halfSide * 2,
      height: halfSide * 2,
    );
    canvas.drawRect(rect, paint);
  }

  double radiusAt(int index) {
    if (radii.isEmpty) {
      return 1.0;
    }
    if (index < 0) {
      return radii.first;
    }
    if (index >= radii.length) {
      return radii.last;
    }
    final double value = radii[index];
    if (value.isFinite && value >= 0) {
      return value;
    }
    return radii.last >= 0 ? radii.last : 1.0;
  }

  drawSquareAt(points.first, radiusAt(0) * radiusScale);

  final int stride = math.max(1, step);
  for (int i = 0; i < points.length - 1; i += stride) {
    final int j = math.min(i + stride, points.length - 1);
    final Offset p1 = points[i];
    final Offset p2 = points[j];
    final double r1 = radiusAt(i) * radiusScale;
    final double r2 = radiusAt(j) * radiusScale;

    final double dist = (p2 - p1).distance;
    if (dist <= 0.1) {
      continue;
    }

    final double maxRadius = math.max(r1, r2);
    final double stepSize = math.max(0.5, maxRadius * 0.25) * stride.toDouble();
    final int steps = (dist / stepSize).ceil();
    for (int s = 1; s <= steps; s++) {
      final double t = s / steps;
      final Offset pos = Offset.lerp(p1, p2, t)!;
      final double r = (ui.lerpDouble(r1, r2, t) ?? r2);
      drawSquareAt(pos, r);
    }
  }
  if ((points.length - 1) % stride != 0) {
    drawSquareAt(points.last, radiusAt(points.length - 1) * radiusScale);
  }
}

class UndoIntent extends Intent {
  const UndoIntent();
}

class RedoIntent extends Intent {
  const RedoIntent();
}

class SelectToolIntent extends Intent {
  const SelectToolIntent(this.tool);

  final CanvasTool tool;
}

class ExitBoardIntent extends Intent {
  const ExitBoardIntent();
}

class DeselectIntent extends Intent {
  const DeselectIntent();
}

class ResizeImageIntent extends Intent {
  const ResizeImageIntent();
}

class ResizeCanvasIntent extends Intent {
  const ResizeCanvasIntent();
}

class AdjustHueSaturationIntent extends Intent {
  const AdjustHueSaturationIntent();
}

class AdjustBrightnessContrastIntent extends Intent {
  const AdjustBrightnessContrastIntent();
}

class ShowColorRangeIntent extends Intent {
  const ShowColorRangeIntent();
}

class AdjustBlackWhiteIntent extends Intent {
  const AdjustBlackWhiteIntent();
}

class AdjustBinarizeIntent extends Intent {
  const AdjustBinarizeIntent();
}

class AdjustScanPaperDrawingIntent extends Intent {
  const AdjustScanPaperDrawingIntent();
}

class InvertColorsIntent extends Intent {
  const InvertColorsIntent();
}

class AdjustGaussianBlurIntent extends Intent {
  const AdjustGaussianBlurIntent();
}

class NarrowLinesIntent extends Intent {
  const NarrowLinesIntent();
}

class ExpandFillIntent extends Intent {
  const ExpandFillIntent();
}

class RemoveColorLeakIntent extends Intent {
  const RemoveColorLeakIntent();
}

class ShowLayerAntialiasIntent extends Intent {
  const ShowLayerAntialiasIntent();
}

class LayerFreeTransformIntent extends Intent {
  const LayerFreeTransformIntent();
}

class CutIntent extends Intent {
  const CutIntent();
}

class CopyIntent extends Intent {
  const CopyIntent();
}

class PasteIntent extends Intent {
  const PasteIntent();
}

class DeleteSelectionIntent extends Intent {
  const DeleteSelectionIntent();
}

class ImportReferenceImageIntent extends Intent {
  const ImportReferenceImageIntent();
}

class ToggleViewBlackWhiteIntent extends Intent {
  const ToggleViewBlackWhiteIntent();
}

class TogglePixelGridIntent extends Intent {
  const TogglePixelGridIntent();
}

class ToggleViewMirrorIntent extends Intent {
  const ToggleViewMirrorIntent();
}

class _CheckboardBackground extends StatelessWidget {
  const _CheckboardBackground({
    this.cellSize = 16.0,
    this.lightColor = const Color(0xFFF9F9F9),
    this.darkColor = const ui.Color.fromARGB(255, 211, 211, 211),
  });

  final double cellSize;
  final Color lightColor;
  final Color darkColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckboardPainter(
        cellSize: cellSize,
        lightColor: lightColor,
        darkColor: darkColor,
      ),
    );
  }
}

class _CheckboardPainter extends CustomPainter {
  const _CheckboardPainter({
    required this.cellSize,
    required this.lightColor,
    required this.darkColor,
  });

  final double cellSize;
  final Color lightColor;
  final Color darkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint lightPaint = Paint()
      ..color = lightColor
      ..isAntiAlias = false;
    final Paint darkPaint = Paint()
      ..color = darkColor
      ..isAntiAlias = false;
    double step = cellSize <= 0 ? 12.0 : cellSize;
    if (size.width > 0 && size.height > 0) {
      final double minSide = math.min(size.width, size.height);
      if (minSide > 0 && step >= minSide) {
        step = math.max(1.0, minSide / 2.0);
      }
    }
    final int horizontalCount = (size.width / step).ceil();
    final int verticalCount = (size.height / step).ceil();

    for (int y = 0; y < verticalCount; y++) {
      final bool oddRow = y.isOdd;
      for (int x = 0; x < horizontalCount; x++) {
        final bool useDark = oddRow ? x.isEven : x.isOdd;
        final Rect rect = Rect.fromLTWH(x * step, y * step, step, step);
        canvas.drawRect(rect, useDark ? darkPaint : lightPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckboardPainter oldDelegate) {
    return oldDelegate.cellSize != cellSize ||
        oldDelegate.lightColor != lightColor ||
        oldDelegate.darkColor != darkColor;
  }
}

// 网格线力求保持恒定屏幕像素宽度，同时根据缩放自动调节网格步长。
const double _kPixelGridScreenStrokeWidth = 1.0;
const double _kPixelGridTargetScreenSpacing = 24.0;
const int _kPixelGridMaxStep = 256;

int _resolvePixelGridStep(double scale) {
  if (scale <= 0.0 || scale.isNaN) {
    return 1;
  }
  final double desiredCanvasSpacing = _kPixelGridTargetScreenSpacing / scale;
  if (desiredCanvasSpacing <= 1.0) {
    return 1;
  }
  final double log2 = math.log(desiredCanvasSpacing) / math.ln2;
  final int powerOfTwo = math.pow(2, log2.floor()).toInt();
  return powerOfTwo.clamp(1, _kPixelGridMaxStep);
}

class _PixelGridPainter extends CustomPainter {
  const _PixelGridPainter({
    required this.pixelWidth,
    required this.pixelHeight,
    required this.color,
    required this.scale,
  });

  final int pixelWidth;
  final int pixelHeight;
  final Color color;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (pixelWidth <= 1 && pixelHeight <= 1) {
      return;
    }
    final double resolvedScale = scale.abs() < 0.0001 ? 1.0 : scale.abs();
    final int step = _resolvePixelGridStep(resolvedScale);
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kPixelGridScreenStrokeWidth / resolvedScale
      ..isAntiAlias = false;
    final double maxX = size.width;
    final double maxY = size.height;
    if (pixelWidth > 1) {
      for (int x = step; x < pixelWidth; x += step) {
        final double dx = x.toDouble();
        canvas.drawLine(Offset(dx, 0), Offset(dx, maxY), paint);
      }
    }
    if (pixelHeight > 1) {
      for (int y = step; y < pixelHeight; y += step) {
        final double dy = y.toDouble();
        canvas.drawLine(Offset(0, dy), Offset(maxX, dy), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PixelGridPainter oldDelegate) {
    return oldDelegate.pixelWidth != pixelWidth ||
        oldDelegate.pixelHeight != pixelHeight ||
        oldDelegate.color != color ||
        oldDelegate.scale != scale;
  }
}

class _ActiveStrokeOverlayPainter extends CustomPainter {
  const _ActiveStrokeOverlayPainter({
    required this.points,
    required this.radii,
    required this.color,
    this.shape = BrushShape.circle,
    required this.randomRotationEnabled,
    required this.rotationSeed,
    required this.committingStrokes,
    required this.commitOverlayOpacityFor,
    required this.commitOverlayFadeVersion,
    this.antialiasLevel = 1,
    this.hollowStrokeEnabled = false,
    this.hollowStrokeRatio = 0.0,
    required this.activeStrokeIsEraser,
    this.eraserPreviewColor = _kVectorEraserPreviewColor,
  });

  final List<Offset> points;
  final List<double> radii;
  final Color color;
  final BrushShape shape;
  final bool randomRotationEnabled;
  final int rotationSeed;
  final List<PaintingDrawCommand> committingStrokes;
  final double Function(PaintingDrawCommand) commitOverlayOpacityFor;
  final int commitOverlayFadeVersion;
  final int antialiasLevel;
  final bool hollowStrokeEnabled;
  final double hollowStrokeRatio;
  final bool activeStrokeIsEraser;
  final Color eraserPreviewColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw committing strokes (fading out/waiting for raster) first
    for (final PaintingDrawCommand command in committingStrokes) {
      if (command.points == null || command.radii == null) continue;
      final double opacity = commitOverlayOpacityFor(command);
      if (opacity <= 0.0) {
        continue;
      }
      final Color baseColor = command.erase
          ? eraserPreviewColor
          : Color(command.color);
      final int alpha =
          (baseColor.alpha * opacity).round().clamp(0, 255) as int;
      final Color commandColor = alpha == baseColor.alpha
          ? baseColor
          : baseColor.withAlpha(alpha);
      final bool commandHollow = (command.hollow ?? false) && !command.erase;
      _paintStrokeOverlay(
        canvas: canvas,
        points: command.points!,
        radii: command.radii!,
        color: commandColor,
        shape: BrushShape.values[command.shapeIndex ?? 0],
        antialiasLevel: command.antialiasLevel,
        hollow: commandHollow,
        hollowRatio: command.hollowRatio ?? 0.0,
      );
    }

    // Draw active stroke on top
    if (points.isNotEmpty) {
      final Color activeColor = activeStrokeIsEraser
          ? eraserPreviewColor
          : color;
      final bool activeHollow = hollowStrokeEnabled && !activeStrokeIsEraser;
      _paintStrokeOverlay(
        canvas: canvas,
        points: points,
        radii: radii,
        color: activeColor,
        shape: shape,
        antialiasLevel: antialiasLevel,
        hollow: activeHollow,
        hollowRatio: hollowStrokeRatio,
      );
    }
  }

  @override
  bool shouldRepaint(_ActiveStrokeOverlayPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.radii != radii ||
        oldDelegate.color != color ||
        oldDelegate.shape != shape ||
        oldDelegate.randomRotationEnabled != randomRotationEnabled ||
        oldDelegate.rotationSeed != rotationSeed ||
        oldDelegate.committingStrokes != committingStrokes ||
        oldDelegate.commitOverlayFadeVersion != commitOverlayFadeVersion ||
        oldDelegate.antialiasLevel != antialiasLevel ||
        oldDelegate.hollowStrokeEnabled != hollowStrokeEnabled ||
        oldDelegate.hollowStrokeRatio != hollowStrokeRatio ||
        oldDelegate.activeStrokeIsEraser != activeStrokeIsEraser ||
        oldDelegate.eraserPreviewColor != eraserPreviewColor;
  }
}

class _PredictedStrokeOverlayPainter extends CustomPainter {
  const _PredictedStrokeOverlayPainter({
    required this.points,
    required this.radii,
    required this.revision,
    required this.color,
    required this.shape,
    required this.antialiasLevel,
  });

  final List<Offset> points;
  final List<double> radii;
  final int revision;
  final Color color;
  final BrushShape shape;
  final int antialiasLevel;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || points.length != radii.length) {
      return;
    }
    _paintStrokeOverlay(
      canvas: canvas,
      points: points,
      radii: radii,
      color: color,
      shape: shape,
      antialiasLevel: antialiasLevel,
    );
  }

  @override
  bool shouldRepaint(_PredictedStrokeOverlayPainter oldDelegate) {
    return oldDelegate.revision != revision ||
        oldDelegate.points != points ||
        oldDelegate.radii != radii ||
        oldDelegate.color != color ||
        oldDelegate.shape != shape ||
        oldDelegate.antialiasLevel != antialiasLevel;
  }
}

class _PathPreviewPainter extends CustomPainter {
  const _PathPreviewPainter({
    required this.path,
    required this.strokeColor,
    required this.strokeWidth,
    this.fillColor,
    this.fill = false,
    this.antialiasLevel = 1,
  });

  final Path path;
  final Color strokeColor;
  final double strokeWidth;
  final Color? fillColor;
  final bool fill;
  final int antialiasLevel;

  @override
  void paint(Canvas canvas, Size size) {
    final bool aa = antialiasLevel > 0;
    if (fill && fillColor != null) {
      final Paint fillPaint = Paint()
        ..color = fillColor!
        ..style = PaintingStyle.fill
        ..isAntiAlias = aa;
      canvas.drawPath(path, fillPaint);
    }
    final double width = strokeWidth.isFinite
        ? strokeWidth.clamp(0.1, 4096.0)
        : 1.0;
    final Paint strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = aa;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(_PathPreviewPainter oldDelegate) {
    return oldDelegate.path != path ||
        oldDelegate.strokeColor != strokeColor ||
        (oldDelegate.strokeWidth - strokeWidth).abs() > 1e-6 ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.fill != fill ||
        oldDelegate.antialiasLevel != antialiasLevel;
  }
}

class _BucketOptionTile extends StatelessWidget {
  const _BucketOptionTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: theme.typography.bodyStrong,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(width: 8),
        ToggleSwitch(checked: value, onChanged: onChanged),
      ],
    );
  }
}
