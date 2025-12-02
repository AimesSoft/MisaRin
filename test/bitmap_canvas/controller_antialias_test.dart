import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misa_rin/bitmap_canvas/bitmap_canvas.dart';
import 'package:misa_rin/bitmap_canvas/controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BitmapCanvasController buildControllerWithDiagonalStroke() {
    final BitmapCanvasController controller = BitmapCanvasController(
      width: 3,
      height: 3,
      backgroundColor: Colors.white,
    );
    final BitmapLayerState layer = controller.layers.last;
    final Uint32List pixels = layer.surface.pixels;
    pixels.fillRange(0, pixels.length, 0);

    int index(int x, int y) => y * controller.width + x;
    void setPixel(int x, int y) {
      pixels[index(x, y)] = BitmapSurface.encodeColor(const Color(0xFF000000));
    }

    setPixel(0, 0);
    setPixel(1, 1);
    setPixel(2, 2);
    return controller;
  }

  test('antialias lowers opaque diagonal edge alpha', () {
    final controller = buildControllerWithDiagonalStroke();
    final BitmapLayerState layer = controller.layers.last;
    final Uint32List pixels = layer.surface.pixels;

    int index(int x, int y) => y * controller.width + x;
    int alphaAt(int x, int y) => (pixels[index(x, y)] >> 24) & 0xff;

    expect(alphaAt(0, 0), 255);

    final bool result = controller.applyAntialiasToActiveLayer(3);
    expect(result, isTrue);

    final int softenedAlpha = alphaAt(0, 0);
    expect(softenedAlpha, greaterThan(0));
    expect(softenedAlpha, lessThan(255));
  });

  test('antialias adds blended coverage to neighboring pixels', () {
    final controller = buildControllerWithDiagonalStroke();
    final BitmapLayerState layer = controller.layers.last;
    final Uint32List pixels = layer.surface.pixels;

    int index(int x, int y) => y * controller.width + x;
    int alphaAt(int x, int y) => (pixels[index(x, y)] >> 24) & 0xff;

    expect(alphaAt(1, 0), 0);

    controller.applyAntialiasToActiveLayer(3);

    final int blendedAlpha = alphaAt(1, 0);
    expect(blendedAlpha, greaterThan(0));
  });

  test('color edge antialias blends opaque neighboring colors', () {
    final BitmapCanvasController controller = BitmapCanvasController(
      width: 2,
      height: 1,
      backgroundColor: Colors.white,
    );
    final BitmapLayerState layer = controller.layers.last;
    final Uint32List pixels = layer.surface.pixels;
    pixels[0] = BitmapSurface.encodeColor(const Color(0xFFFF0000));
    pixels[1] = BitmapSurface.encodeColor(const Color(0xFF0000FF));

    controller.applyAntialiasToActiveLayer(3);

    final int left = pixels[0];
    final int right = pixels[1];

    final int leftRed = (left >> 16) & 0xff;
    final int leftBlue = left & 0xff;
    final int rightRed = (right >> 16) & 0xff;
    final int rightBlue = right & 0xff;

    expect(leftRed, lessThan(255));
    expect(leftBlue, greaterThan(0));
    expect(rightBlue, lessThan(255));
    expect(rightRed, greaterThan(0));
  });
}
