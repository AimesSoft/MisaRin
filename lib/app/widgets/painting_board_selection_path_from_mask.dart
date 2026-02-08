part of 'painting_board.dart';

Path? _selectionPathFromMask(Uint8List mask, int width) {
  if (mask.isEmpty) {
    return null;
  }
  if (width <= 0) {
    return null;
  }
  if (kIsWeb) {
    return null;
  }

  try {
    final Uint32List vertices = rust_selection_path.selectionPathVerticesFromMask(
      mask: mask,
      width: width,
    );
    return _selectionPathFromVertices(vertices);
  } catch (_) {
    return null;
  }
}

const int _kSelectionPathVertexSentinel = 0xFFFFFFFF;

Path? _selectionPathFromVertices(Uint32List vertices) {
  if (vertices.isEmpty) {
    return null;
  }

  final Path path = Path()..fillType = PathFillType.evenOdd;
  bool hasAnyContour = false;
  bool hasOpenContour = false;

  for (int i = 0; i + 1 < vertices.length; i += 2) {
    final int x = vertices[i];
    final int y = vertices[i + 1];

    if (x == _kSelectionPathVertexSentinel && y == _kSelectionPathVertexSentinel) {
      if (hasOpenContour) {
        path.close();
        hasOpenContour = false;
      }
      continue;
    }

    if (!hasOpenContour) {
      path.moveTo(x.toDouble(), y.toDouble());
      hasAnyContour = true;
      hasOpenContour = true;
    } else {
      path.lineTo(x.toDouble(), y.toDouble());
    }
  }

  if (hasOpenContour) {
    path.close();
  }

  return hasAnyContour ? path : null;
}

class _SelectionOverlayPainter extends CustomPainter {
  const _SelectionOverlayPainter({
    this.selectionPath,
    this.selectionPreviewPath,
    this.magicPreviewPath,
    required this.dashPhase,
    required this.viewportScale,
    this.showPreviewStroke = true,
    this.fillSelectionPath = false,
  });

  final Path? selectionPath;
  final Path? selectionPreviewPath;
  final Path? magicPreviewPath;
  final double dashPhase;
  final double viewportScale;
  final bool showPreviewStroke;
  final bool fillSelectionPath;

  static final Paint _selectionFillPaint = Paint()
    ..color = _kSelectionFillColor
    ..style = PaintingStyle.fill;
  static final Paint _previewFillPaint = Paint()
    ..color = _kSelectionPreviewFillColor
    ..style = PaintingStyle.fill;
  static final _MarchingAntsStroke _selectionStroke = _MarchingAntsStroke(
    dashLength: _kSelectionDashLength,
    dashGap: _kSelectionDashGap,
    strokeWidth: 1.0,
    lightColor: const Color(0xE6FFFFFF),
    darkColor: const Color(0xFF2B2B2B),
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (fillSelectionPath && selectionPath != null) {
      canvas.drawPath(selectionPath!, _selectionFillPaint);
    }
    if (magicPreviewPath != null) {
      canvas.drawPath(magicPreviewPath!, _previewFillPaint);
      _selectionStroke.paint(
        canvas,
        magicPreviewPath!,
        dashPhase,
        viewportScale: viewportScale,
      );
    }
    if (selectionPreviewPath != null) {
      canvas.drawPath(selectionPreviewPath!, _previewFillPaint);
      if (showPreviewStroke) {
        _selectionStroke.paint(
          canvas,
          selectionPreviewPath!,
          dashPhase,
          viewportScale: viewportScale,
        );
      }
    }
    if (selectionPath != null) {
      _selectionStroke.paint(
        canvas,
        selectionPath!,
        dashPhase,
        viewportScale: viewportScale,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionOverlayPainter oldDelegate) {
    return oldDelegate.selectionPath != selectionPath ||
        oldDelegate.selectionPreviewPath != selectionPreviewPath ||
        oldDelegate.magicPreviewPath != magicPreviewPath ||
        oldDelegate.dashPhase != dashPhase ||
        oldDelegate.viewportScale != viewportScale ||
        oldDelegate.showPreviewStroke != showPreviewStroke ||
        oldDelegate.fillSelectionPath != fillSelectionPath;
  }
}
