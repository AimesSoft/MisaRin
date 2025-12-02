part of 'painting_board.dart';

const Color _kVectorEraserPreviewColor = _kSelectionPreviewFillColor;

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

class AdjustGaussianBlurIntent extends Intent {
  const AdjustGaussianBlurIntent();
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

class ImportReferenceImageIntent extends Intent {
  const ImportReferenceImageIntent();
}

class _CheckboardBackground extends StatelessWidget {
  const _CheckboardBackground({
    required this.cellSize,
    required this.lightColor,
    required this.darkColor,
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
    final double step = cellSize <= 0 ? 12.0 : cellSize;
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

class _PreviewPathPainter extends CustomPainter {
  const _PreviewPathPainter({
    required this.path,
    required this.color,
    required this.strokeWidth,
    this.fill = false,
  });

  final Path path;
  final Color color;
  final double strokeWidth;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (fill) {
      final Paint fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth.clamp(kPenStrokeMin, kPenStrokeMax)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PreviewPathPainter oldDelegate) {
    return oldDelegate.path != path ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.fill != fill;
  }
}

class _ShapeFillOverlayPainter extends CustomPainter {
  const _ShapeFillOverlayPainter({required this.path, required this.color});

  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(_ShapeFillOverlayPainter oldDelegate) {
    return oldDelegate.path != path || oldDelegate.color != color;
  }
}

class _ActiveStrokeOverlayPainter extends CustomPainter {
  const _ActiveStrokeOverlayPainter({
    required this.points,
    required this.radii,
    required this.color,
    this.shape = BrushShape.circle,
    required this.committingStrokes,
    required this.activeStrokeIsEraser,
    this.eraserPreviewColor = _kVectorEraserPreviewColor,
    required this.antialiasLevel, // Added initialization
  });

  final List<Offset> points;
  final List<double> radii;
  final Color color;
  final BrushShape shape;
  final List<PaintingDrawCommand> committingStrokes;
  final int antialiasLevel; // Field declaration

  final bool activeStrokeIsEraser;
  final Color eraserPreviewColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw committing strokes (fading out/waiting for raster) first
    for (final PaintingDrawCommand command in committingStrokes) {
      if (command.points == null || command.radii == null) continue;
      final Color commandColor = command.erase
          ? eraserPreviewColor
          : Color(command.color);
      VectorStrokePainter.paint(
        canvas: canvas,
        points: command.points!,
        radii: command.radii!,
        color: commandColor,
        shape: BrushShape.values[command.shapeIndex ?? 0],
        antialiasLevel: command.antialiasLevel,
      );
    }

    // Draw active stroke on top
    if (points.isNotEmpty) {
      final Color activeColor = activeStrokeIsEraser
          ? eraserPreviewColor
          : color;
      VectorStrokePainter.paint(
        canvas: canvas,
        points: points,
        radii: radii,
        color: activeColor,
        shape: shape,
        antialiasLevel: antialiasLevel,
      );
    }
  }

  @override
  bool shouldRepaint(_ActiveStrokeOverlayPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.radii != radii ||
        oldDelegate.color != color ||
        oldDelegate.shape != shape ||
        oldDelegate.committingStrokes != committingStrokes ||
        oldDelegate.antialiasLevel != antialiasLevel ||
        oldDelegate.activeStrokeIsEraser != activeStrokeIsEraser ||
        oldDelegate.eraserPreviewColor != eraserPreviewColor;
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
