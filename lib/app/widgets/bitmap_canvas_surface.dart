import 'package:flutter/widgets.dart';

import '../../bitmap_canvas/raster_frame.dart';

class BitmapCanvasSurface extends StatelessWidget {
  const BitmapCanvasSurface({super.key, required this.frame});

  final BitmapCanvasFrame? frame;

  @override
  Widget build(BuildContext context) {
    final BitmapCanvasFrame? current = frame;
    if (current == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: current.size.width,
      height: current.size.height,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BitmapCanvasTilePainter(current),
          isComplex: true,
        ),
      ),
    );
  }
}

class _BitmapCanvasTilePainter extends CustomPainter {
  _BitmapCanvasTilePainter(this.frame);

  final BitmapCanvasFrame frame;
  final Paint _paint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none; // Avoid sampling gaps between tiles.

  @override
  void paint(Canvas canvas, Size size) {
    for (final BitmapCanvasTile tile in frame.tiles) {
      canvas.drawImageRect(
        tile.image,
        tile.sourceRect,
        tile.destinationRect,
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BitmapCanvasTilePainter oldDelegate) {
    return oldDelegate.frame != frame;
  }
}
