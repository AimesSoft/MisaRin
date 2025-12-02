import 'dart:collection';
import 'dart:ui' as ui;

import 'raster_int_rect.dart';

/// Immutable description of a raster tile that can be painted independently.
class BitmapCanvasTile {
  const BitmapCanvasTile({required this.rect, required this.image});

  final RasterIntRect rect;
  final ui.Image image;

  ui.Rect get destinationRect => ui.Rect.fromLTWH(
    rect.left.toDouble(),
    rect.top.toDouble(),
    rect.width.toDouble(),
    rect.height.toDouble(),
  );

  ui.Rect get sourceRect =>
      ui.Rect.fromLTWH(0, 0, rect.width.toDouble(), rect.height.toDouble());
}

/// Aggregates all tiles required to render a full bitmap surface.
class BitmapCanvasFrame {
  BitmapCanvasFrame({
    required this.tiles,
    required this.surfaceWidth,
    required this.surfaceHeight,
    required this.generation,
  });

  final UnmodifiableListView<BitmapCanvasTile> tiles;
  final int surfaceWidth;
  final int surfaceHeight;
  final int generation;

  ui.Size get size =>
      ui.Size(surfaceWidth.toDouble(), surfaceHeight.toDouble());
}
