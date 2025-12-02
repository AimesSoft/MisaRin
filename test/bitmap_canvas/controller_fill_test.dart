import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misa_rin/bitmap_canvas/bitmap_canvas.dart';
import 'package:misa_rin/bitmap_canvas/controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bucket fill uses composite colors for contiguous cross-layer fills',
    () {
      final BitmapCanvasController controller = BitmapCanvasController(
        width: 3,
        height: 1,
        backgroundColor: Colors.white,
      );
      final BitmapLayerState backgroundLayer = controller.layers.first;
      final Uint32List pixels = backgroundLayer.surface.pixels;
      pixels[0] = BitmapSurface.encodeColor(const Color(0xFFFF0000));
      pixels[1] = BitmapSurface.encodeColor(const Color(0xFF0000FF));
      pixels[2] = BitmapSurface.encodeColor(const Color(0xFFFF0000));

      controller.floodFill(
        const Offset(0, 0),
        color: const Color(0xFF00FF00),
        contiguous: true,
        sampleAllLayers: true,
      );

      final BitmapLayerState activeLayer = controller.layers.last;
      expect(activeLayer.surface.pixelAt(0, 0), const Color(0xFF00FF00));
      expect(activeLayer.surface.pixelAt(1, 0), const Color(0x00000000));
      expect(activeLayer.surface.pixelAt(2, 0), const Color(0x00000000));
    },
  );
}
