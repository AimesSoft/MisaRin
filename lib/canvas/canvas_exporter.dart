import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../bitmap_canvas/bitmap_canvas.dart';
import 'blend_mode_math.dart';
import 'canvas_layer.dart';
import 'canvas_settings.dart';
import '../utils/webp_encoder.dart';

class CanvasExporter {
  Future<Uint8List> exportToRgba({
    required CanvasSettings settings,
    required List<CanvasLayerData> layers,
    bool applyEdgeSoftening = false,
    int edgeSofteningLevel = 2,
  }) async {
    final int width = settings.width.round();
    final int height = settings.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('画布尺寸必须大于 0');
    }

    final BitmapSurface composite = _compositeLayers(
      width: width,
      height: height,
      layers: layers,
    );

    if (applyEdgeSoftening) {
      _applyEdgeSofteningToPixels(
        composite.pixels,
        width,
        height,
        edgeSofteningLevel,
      );
    }

    return _surfaceToRgba(composite);
  }

  Future<Uint8List> exportToPng({
    required CanvasSettings settings,
    required List<CanvasLayerData> layers,
    int? maxDimension,
    ui.Size? outputSize,
    bool applyEdgeSoftening = false,
    int edgeSofteningLevel = 2,
  }) async {
    final _RenderedImage rendered = await _renderCompositeImage(
      settings: settings,
      layers: layers,
      maxDimension: maxDimension,
      outputSize: outputSize,
      applyEdgeSoftening: applyEdgeSoftening,
      edgeSofteningLevel: edgeSofteningLevel,
    );
    final ByteData? byteData = await rendered.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    rendered.image.dispose();
    if (byteData == null) {
      throw StateError('导出 PNG 时发生未知错误');
    }
    return byteData.buffer.asUint8List();
  }

  Future<Uint8List> exportToWebp({
    required CanvasSettings settings,
    required List<CanvasLayerData> layers,
    int? maxDimension,
    ui.Size? outputSize,
    bool applyEdgeSoftening = false,
    int edgeSofteningLevel = 2,
    bool lossless = false,
    int quality = 85,
  }) async {
    final _RenderedImage rendered = await _renderCompositeImage(
      settings: settings,
      layers: layers,
      maxDimension: maxDimension,
      outputSize: outputSize,
      applyEdgeSoftening: applyEdgeSoftening,
      edgeSofteningLevel: edgeSofteningLevel,
    );
    ByteData? byteData = await rendered.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    byteData ??= await rendered.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    rendered.image.dispose();
    if (byteData == null) {
      throw StateError('导出 WebP 时发生未知错误');
    }
    final Uint8List rgba = byteData.buffer.asUint8List();
    return encodeWebpRgba(
      rgba: rgba,
      width: rendered.width,
      height: rendered.height,
      lossless: lossless,
      quality: quality,
    );
  }

  Future<_RenderedImage> _renderCompositeImage({
    required CanvasSettings settings,
    required List<CanvasLayerData> layers,
    int? maxDimension,
    ui.Size? outputSize,
    bool applyEdgeSoftening = false,
    int edgeSofteningLevel = 2,
  }) async {
    final int baseWidth = settings.width.round();
    final int baseHeight = settings.height.round();
    if (baseWidth <= 0 || baseHeight <= 0) {
      throw ArgumentError('画布尺寸必须大于 0');
    }

    double scale = 1.0;
    ui.Size? targetSize = outputSize;
    if (targetSize != null) {
      if (targetSize.width <= 0 || targetSize.height <= 0) {
        throw ArgumentError('输出尺寸必须大于 0');
      }
      final double widthScale = targetSize.width / baseWidth;
      final double heightScale = targetSize.height / baseHeight;
      if ((widthScale - heightScale).abs() > 1e-4) {
        throw ArgumentError('输出尺寸必须与画布保持相同长宽比');
      }
      scale = widthScale;
    } else if (maxDimension != null && maxDimension > 0) {
      final double longestSide = baseWidth > baseHeight
          ? baseWidth.toDouble()
          : baseHeight.toDouble();
      if (longestSide > 0) {
        scale = maxDimension / longestSide;
      }
    }
    if (scale <= 0) {
      scale = 1.0;
    }

    final int outputWidth = targetSize != null
        ? targetSize.width.round().clamp(1, 100000)
        : (baseWidth * scale).round().clamp(1, 100000);
    final int outputHeight = targetSize != null
        ? targetSize.height.round().clamp(1, 100000)
        : (baseHeight * scale).round().clamp(1, 100000);

    final BitmapSurface composite = _compositeLayers(
      width: baseWidth,
      height: baseHeight,
      layers: layers,
    );

    if (applyEdgeSoftening) {
      _applyEdgeSofteningToPixels(
        composite.pixels,
        baseWidth,
        baseHeight,
        edgeSofteningLevel,
      );
    }

    final Uint8List rgba = _surfaceToRgba(composite);
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      rgba,
    );
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: baseWidth,
      height: baseHeight,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final ui.Codec codec = await descriptor.instantiateCodec();
    buffer.dispose();
    final ui.FrameInfo frame = await codec.getNextFrame();
    ui.Image image = frame.image;
    codec.dispose();

    if (outputWidth != baseWidth || outputHeight != baseHeight) {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, baseWidth.toDouble(), baseHeight.toDouble()),
        ui.Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.none,
      );
      final ui.Picture picture = recorder.endRecording();
      final ui.Image scaled = await picture.toImage(outputWidth, outputHeight);
      image.dispose();
      image = scaled;
    }

    return _RenderedImage(
      image: image,
      width: outputWidth,
      height: outputHeight,
    );
  }

  BitmapSurface _compositeLayers({
    required int width,
    required int height,
    required List<CanvasLayerData> layers,
  }) {
    final List<_PreparedLayer> prepared = <_PreparedLayer>[];
    for (final CanvasLayerData layer in layers) {
      if (!layer.visible) {
        continue;
      }
      prepared.add(
        _PreparedLayer(
          pixels: _buildLayerPixels(layer, width, height),
          opacity: _clampUnit(layer.opacity),
          clippingMask: layer.clippingMask,
          blendMode: layer.blendMode,
        ),
      );
    }

    final Uint32List composite = Uint32List(width * height);
    final Uint8List clipMask = Uint8List(width * height);

    for (int index = 0; index < composite.length; index++) {
      clipMask[index] = 0;
      int color = 0;
      bool initialized = false;
      for (final _PreparedLayer layer in prepared) {
        final double layerOpacity = layer.opacity;
        if (layerOpacity <= 0) {
          if (!layer.clippingMask) {
            clipMask[index] = 0;
          }
          continue;
        }
        final int src = layer.pixels[index];
        final int srcA = (src >> 24) & 0xff;
        if (!layer.clippingMask && srcA == 0) {
          clipMask[index] = 0;
        }
        if (srcA == 0) {
          continue;
        }

        double totalOpacity = layerOpacity;
        if (layer.clippingMask) {
          final int maskAlpha = clipMask[index];
          if (maskAlpha == 0) {
            continue;
          }
          totalOpacity *= maskAlpha / 255.0;
          if (totalOpacity <= 0) {
            continue;
          }
        }

        int effectiveA = (srcA * totalOpacity).round();
        if (effectiveA <= 0) {
          if (!layer.clippingMask) {
            clipMask[index] = 0;
          }
          continue;
        }
        effectiveA = effectiveA.clamp(0, 255);

        if (!layer.clippingMask) {
          clipMask[index] = effectiveA;
        }

        final int effectiveColor = (effectiveA << 24) | (src & 0x00FFFFFF);
        if (!initialized) {
          color = effectiveColor;
          initialized = true;
        } else {
          color = _blendWithMode(color, effectiveColor, layer.blendMode, index);
        }
      }
      composite[index] = initialized ? color : 0;
    }

    final BitmapSurface base = BitmapSurface(width: width, height: height);
    base.pixels.setAll(0, composite);
    return base;
  }

  Uint8List _surfaceToRgba(BitmapSurface surface) {
    final Uint8List rgba = Uint8List(surface.pixels.length * 4);
    for (int i = 0; i < surface.pixels.length; i++) {
      final int argb = surface.pixels[i];
      final int offset = i * 4;
      rgba[offset] = (argb >> 16) & 0xff;
      rgba[offset + 1] = (argb >> 8) & 0xff;
      rgba[offset + 2] = argb & 0xff;
      rgba[offset + 3] = (argb >> 24) & 0xff;
    }
    return rgba;
  }

  Future<Uint8List> exportToSvg({
    required CanvasSettings settings,
    required List<CanvasLayerData> layers,
    int maxColors = 8,
    double simplifyEpsilon = 1.2,
  }) async {
    final int width = settings.width.round();
    final int height = settings.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('画布尺寸必须大于 0');
    }
    if (maxColors <= 0) {
      throw ArgumentError('颜色数量必须大于 0');
    }

    final BitmapSurface composite = _compositeLayers(
      width: width,
      height: height,
      layers: layers,
    );
    final Uint8List rgba = _surfaceToRgba(composite);
    final List<_VectorColorPaths> shapes = _vectorizeRgba(
      rgba: rgba,
      width: width,
      height: height,
      maxColors: maxColors.clamp(1, 32) as int,
      simplifyEpsilon: simplifyEpsilon.clamp(0.0, 8.0) as double,
    );
    if (shapes.isEmpty) {
      throw StateError('当前画面为空，无法导出矢量图');
    }

    final StringBuffer buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="$width" height="$height" viewBox="0 0 $width $height">',
      );

    for (final _VectorColorPaths shape in shapes) {
      final ui.Color color = shape.color;
      final String fill =
          '#${color.red.toRadixString(16).padLeft(2, '0')}${color.green.toRadixString(16).padLeft(2, '0')}${color.blue.toRadixString(16).padLeft(2, '0')}';
      final double opacity = shape.opacity.clamp(0.0, 1.0);
      final StringBuffer pathData = StringBuffer();
      for (final List<ui.Offset> polygon in shape.polygons) {
        if (polygon.length < 3) {
          continue;
        }
        pathData.write('M');
        pathData.write(polygon.first.dx.toStringAsFixed(2));
        pathData.write(' ');
        pathData.write(polygon.first.dy.toStringAsFixed(2));
        for (int i = 1; i < polygon.length; i++) {
          final ui.Offset p = polygon[i];
          pathData.write(' L');
          pathData.write(p.dx.toStringAsFixed(2));
          pathData.write(' ');
          pathData.write(p.dy.toStringAsFixed(2));
        }
        pathData.write(' Z ');
      }
      if (pathData.isEmpty) {
        continue;
      }
      buffer.write('<path fill="$fill" fill-rule="evenodd"');
      if (opacity < 0.999) {
        buffer.write(' fill-opacity="${opacity.toStringAsFixed(3)}"');
      }
      buffer
        ..write(' d="')
        ..write(pathData.toString().trim())
        ..writeln('"/>');
    }

    buffer.write('</svg>');
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }
}

class _RenderedImage {
  const _RenderedImage({
    required this.image,
    required this.width,
    required this.height,
  });

  final ui.Image image;
  final int width;
  final int height;
}

class _PreparedLayer {
  _PreparedLayer({
    required this.pixels,
    required this.opacity,
    required this.clippingMask,
    required this.blendMode,
  });

  final Uint32List pixels;
  final double opacity;
  final bool clippingMask;
  final CanvasLayerBlendMode blendMode;
}

Uint32List _buildLayerPixels(CanvasLayerData layer, int width, int height) {
  final Uint32List pixels = Uint32List(width * height);
  if (layer.bitmap != null &&
      layer.bitmapWidth != null &&
      layer.bitmapHeight != null) {
    final Uint8List bitmap = layer.bitmap!;
    final int srcWidth = layer.bitmapWidth!;
    final int srcHeight = layer.bitmapHeight!;
    final int offsetX = layer.bitmapLeft ?? 0;
    final int offsetY = layer.bitmapTop ?? 0;
    for (int y = 0; y < srcHeight; y++) {
      final int canvasY = y + offsetY;
      if (canvasY < 0 || canvasY >= height) {
        continue;
      }
      final int rowOffset = y * srcWidth;
      for (int x = 0; x < srcWidth; x++) {
        final int canvasX = x + offsetX;
        if (canvasX < 0 || canvasX >= width) {
          continue;
        }
        final int rgbaIndex = (rowOffset + x) * 4;
        final int a = bitmap[rgbaIndex + 3];
        if (a == 0) {
          continue;
        }
        final int r = bitmap[rgbaIndex];
        final int g = bitmap[rgbaIndex + 1];
        final int b = bitmap[rgbaIndex + 2];
        final int destIndex = canvasY * width + canvasX;
        pixels[destIndex] = (a << 24) | (r << 16) | (g << 8) | b;
      }
    }
  } else if (layer.fillColor != null) {
    final int encoded = _encodeColor(layer.fillColor!);
    for (int i = 0; i < pixels.length; i++) {
      pixels[i] = encoded;
    }
  }
  return pixels;
}

double _clampUnit(double value) {
  if (value <= 0) {
    return 0;
  }
  if (value >= 1) {
    return 1;
  }
  return value;
}

int _blendWithMode(
  int dst,
  int src,
  CanvasLayerBlendMode mode,
  int pixelIndex,
) {
  return CanvasBlendMath.blend(dst, src, mode, pixelIndex: pixelIndex);
}

int _encodeColor(ui.Color color) {
  return (color.alpha << 24) |
      (color.red << 16) |
      (color.green << 8) |
      color.blue;
}

// Edge softening for export (Retas style, non-destructive).

const int _kEdgeSofteningCenterWeight = 4;
const List<int> _kEdgeSofteningDx = <int>[-1, 0, 1, -1, 1, -1, 0, 1];
const List<int> _kEdgeSofteningDy = <int>[-1, -1, -1, 0, 0, 1, 1, 1];
const List<int> _kEdgeSofteningWeights = <int>[1, 2, 1, 2, 2, 1, 2, 1];
const Map<int, List<double>> _kEdgeSofteningProfiles = <int, List<double>>{
  0: <double>[0.25],
  1: <double>[0.35, 0.35],
  2: <double>[0.45, 0.5, 0.5],
  3: <double>[0.6, 0.65, 0.7, 0.75],
  4: <double>[0.6, 0.65, 0.7, 0.75, 0.8],
  5: <double>[0.65, 0.7, 0.75, 0.8, 0.85],
  6: <double>[0.7, 0.75, 0.8, 0.85, 0.9],
  7: <double>[0.7, 0.75, 0.8, 0.85, 0.9, 0.9],
  8: <double>[0.75, 0.8, 0.85, 0.9, 0.9, 0.9],
  9: <double>[0.8, 0.85, 0.9, 0.9, 0.9, 0.9],
};
const double _kEdgeSofteningDetectMin = 0.015;
const double _kEdgeSofteningDetectMax = 0.4;
const double _kEdgeSofteningStrength = 1.0;
const double _kEdgeSofteningGamma = 0.55;
const List<int> _kEdgeSofteningGaussianKernel5x5 = <int>[
  1, 4, 6, 4, 1, //
  4, 16, 24, 16, 4, //
  6, 24, 36, 24, 6, //
  4, 16, 24, 16, 4, //
  1, 4, 6, 4, 1,
];

void _applyEdgeSofteningToPixels(
  Uint32List pixels,
  int width,
  int height,
  int level,
) {
  if (pixels.isEmpty || width <= 0 || height <= 0) {
    return;
  }
  final List<double> profile =
      _kEdgeSofteningProfiles[level.clamp(0, 9)] ?? const <double>[];
  if (profile.isEmpty) {
    return;
  }
  final Uint32List temp = Uint32List(pixels.length);
  Uint32List src = pixels;
  Uint32List dest = temp;
  bool modified = false;

  for (final double factor in profile) {
    if (factor <= 0) {
      continue;
    }
    final bool alphaChanged = _runEdgeSofteningAlphaPass(
      src,
      dest,
      width,
      height,
      factor,
    );
    if (!alphaChanged) {
      continue;
    }
    modified = true;
    final Uint32List swap = src;
    src = dest;
    dest = swap;
  }

  final Uint32List blurBuffer = Uint32List(pixels.length);
  final bool colorChanged = _runEdgeAwareColorSmoothPass(
    src,
    dest,
    blurBuffer,
    width,
    height,
  );
  if (colorChanged) {
    modified = true;
    final Uint32List swap = src;
    src = dest;
    dest = swap;
  }

  if (modified && !identical(src, pixels)) {
    pixels.setAll(0, src);
  }
}

bool _runEdgeSofteningAlphaPass(
  Uint32List src,
  Uint32List dest,
  int width,
  int height,
  double blendFactor,
) {
  dest.setAll(0, src);
  if (blendFactor <= 0) {
    return false;
  }
  final double factor = blendFactor.clamp(0.0, 1.0);
  bool modified = false;
  for (int y = 0; y < height; y++) {
    final int rowOffset = y * width;
    for (int x = 0; x < width; x++) {
      final int index = rowOffset + x;
      final int center = src[index];
      final int alpha = (center >> 24) & 0xff;
      final int centerR = (center >> 16) & 0xff;
      final int centerG = (center >> 8) & 0xff;
      final int centerB = center & 0xff;

      int totalWeight = _kEdgeSofteningCenterWeight;
      int weightedAlpha = alpha * _kEdgeSofteningCenterWeight;
      int weightedPremulR = centerR * alpha * _kEdgeSofteningCenterWeight;
      int weightedPremulG = centerG * alpha * _kEdgeSofteningCenterWeight;
      int weightedPremulB = centerB * alpha * _kEdgeSofteningCenterWeight;

      for (int i = 0; i < _kEdgeSofteningDx.length; i++) {
        final int nx = x + _kEdgeSofteningDx[i];
        final int ny = y + _kEdgeSofteningDy[i];
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
          continue;
        }
        final int neighbor = src[ny * width + nx];
        final int neighborAlpha = (neighbor >> 24) & 0xff;
        final int weight = _kEdgeSofteningWeights[i];
        totalWeight += weight;
        if (neighborAlpha == 0) {
          continue;
        }
        weightedAlpha += neighborAlpha * weight;
        weightedPremulR += ((neighbor >> 16) & 0xff) * neighborAlpha * weight;
        weightedPremulG += ((neighbor >> 8) & 0xff) * neighborAlpha * weight;
        weightedPremulB += (neighbor & 0xff) * neighborAlpha * weight;
      }

      if (totalWeight <= 0) {
        continue;
      }

      final int candidateAlpha = (weightedAlpha ~/ totalWeight).clamp(0, 255);
      final int deltaAlpha = candidateAlpha - alpha;
      if (deltaAlpha == 0) {
        continue;
      }

      final int newAlpha =
          (alpha + (deltaAlpha * factor).round()).clamp(0, 255);
      if (newAlpha == alpha) {
        continue;
      }

      int newR = centerR;
      int newG = centerG;
      int newB = centerB;
      if (deltaAlpha > 0) {
        final int boundedWeightedAlpha = math.max(weightedAlpha, 1);
        newR = (weightedPremulR ~/ boundedWeightedAlpha).clamp(0, 255);
        newG = (weightedPremulG ~/ boundedWeightedAlpha).clamp(0, 255);
        newB = (weightedPremulB ~/ boundedWeightedAlpha).clamp(0, 255);
      }

      dest[index] = (newAlpha << 24) | (newR << 16) | (newG << 8) | newB;
      modified = true;
    }
  }
  return modified;
}

bool _runEdgeAwareColorSmoothPass(
  Uint32List src,
  Uint32List dest,
  Uint32List blurBuffer,
  int width,
  int height,
) {
  _computeGaussianBlur(src, blurBuffer, width, height);
  bool modified = false;
  for (int y = 0; y < height; y++) {
    final int rowOffset = y * width;
    for (int x = 0; x < width; x++) {
      final int index = rowOffset + x;
      final int baseColor = src[index];
      final int alpha = (baseColor >> 24) & 0xff;
      if (alpha == 0) {
        dest[index] = baseColor;
        continue;
      }

      final double gradient = _computeEdgeGradient(src, width, height, x, y);
      final double weight = _edgeSmoothWeight(gradient);
      if (weight <= 0) {
        dest[index] = baseColor;
        continue;
      }
      final int blurred = blurBuffer[index];
      final int newColor = _lerpArgb(baseColor, blurred, weight);
      dest[index] = newColor;
      if (newColor != baseColor) {
        modified = true;
      }
    }
  }
  return modified;
}

double _computeEdgeGradient(
  Uint32List src,
  int width,
  int height,
  int x,
  int y,
) {
  final int index = y * width + x;
  final int center = src[index];
  final int alpha = (center >> 24) & 0xff;
  if (alpha == 0) {
    return 0;
  }
  final double centerLuma = _computeLuma(center);
  double maxDiff = 0;

  void accumulate(int nx, int ny) {
    if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
      return;
    }
    final int neighbor = src[ny * width + nx];
    final int neighborAlpha = (neighbor >> 24) & 0xff;
    if (neighborAlpha == 0) {
      return;
    }
    final double diff = (centerLuma - _computeLuma(neighbor)).abs();
    if (diff > maxDiff) {
      maxDiff = diff;
    }
  }

  accumulate(x - 1, y);
  accumulate(x + 1, y);
  accumulate(x, y - 1);
  accumulate(x, y + 1);
  accumulate(x - 1, y - 1);
  accumulate(x + 1, y - 1);
  accumulate(x - 1, y + 1);
  accumulate(x + 1, y + 1);
  return maxDiff;
}

double _edgeSmoothWeight(double gradient) {
  if (gradient <= _kEdgeSofteningDetectMin) {
    return 0;
  }
  final double normalized = ((gradient - _kEdgeSofteningDetectMin) /
          (_kEdgeSofteningDetectMax - _kEdgeSofteningDetectMin))
      .clamp(0.0, 1.0);
  return math.pow(normalized, _kEdgeSofteningGamma) *
      _kEdgeSofteningStrength;
}

void _computeGaussianBlur(
  Uint32List src,
  Uint32List dest,
  int width,
  int height,
) {
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      double weightedAlpha = 0;
      double weightedR = 0;
      double weightedG = 0;
      double weightedB = 0;
      double totalWeight = 0;
      int kernelIndex = 0;
      for (int ky = -2; ky <= 2; ky++) {
        final int ny = (y + ky).clamp(0, height - 1);
        final int rowOffset = ny * width;
        for (int kx = -2; kx <= 2; kx++) {
          final int nx = (x + kx).clamp(0, width - 1);
          final int weight = _kEdgeSofteningGaussianKernel5x5[kernelIndex++];
          final int sample = src[rowOffset + nx];
          final int alpha = (sample >> 24) & 0xff;
          if (alpha == 0) {
            continue;
          }
          totalWeight += weight;
          weightedAlpha += alpha * weight;
          weightedR += ((sample >> 16) & 0xff) * alpha * weight;
          weightedG += ((sample >> 8) & 0xff) * alpha * weight;
          weightedB += (sample & 0xff) * alpha * weight;
        }
      }
      if (totalWeight == 0) {
        dest[y * width + x] = src[y * width + x];
        continue;
      }
      final double normalizedAlpha = weightedAlpha / totalWeight;
      final double premulAlpha = math.max(weightedAlpha, 1.0);
      final int outAlpha = normalizedAlpha.round().clamp(0, 255);
      final int outR = (weightedR / premulAlpha).round().clamp(0, 255);
      final int outG = (weightedG / premulAlpha).round().clamp(0, 255);
      final int outB = (weightedB / premulAlpha).round().clamp(0, 255);
      dest[y * width + x] =
          (outAlpha << 24) | (outR << 16) | (outG << 8) | outB;
    }
  }
}

double _computeLuma(int color) {
  final int alpha = (color >> 24) & 0xff;
  if (alpha == 0) {
    return 0;
  }
  final int r = (color >> 16) & 0xff;
  final int g = (color >> 8) & 0xff;
  final int b = color & 0xff;
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
}

int _lerpArgb(int a, int b, double t) {
  final double clampedT = t.clamp(0.0, 1.0);
  int lerpChannel(int ca, int cb) =>
      (ca + ((cb - ca) * clampedT).round()).clamp(0, 255);

  final int aA = (a >> 24) & 0xff;
  final int aR = (a >> 16) & 0xff;
  final int aG = (a >> 8) & 0xff;
  final int aB = a & 0xff;

  final int bA = (b >> 24) & 0xff;
  final int bR = (b >> 16) & 0xff;
  final int bG = (b >> 8) & 0xff;
  final int bB = b & 0xff;

  final int outA = lerpChannel(aA, bA);
  final int outR = lerpChannel(aR, bR);
  final int outG = lerpChannel(aG, bG);
  final int outB = lerpChannel(aB, bB);
  return (outA << 24) | (outR << 16) | (outG << 8) | outB;
}

class _PaletteBucket {
  int count = 0;
  int sumR = 0;
  int sumG = 0;
  int sumB = 0;
}

class _VectorColorPaths {
  _VectorColorPaths({
    required this.color,
    required this.opacity,
    required this.polygons,
  });

  final ui.Color color;
  final double opacity;
  final List<List<ui.Offset>> polygons;
}

class _Edge {
  _Edge(this.start, this.end);
  final int start;
  final int end;
}

List<_VectorColorPaths> _vectorizeRgba({
  required Uint8List rgba,
  required int width,
  required int height,
  required int maxColors,
  required double simplifyEpsilon,
}) {
  if (rgba.isEmpty || width <= 0 || height <= 0) {
    return <_VectorColorPaths>[];
  }
  final List<ui.Color> palette = _extractPalette(rgba, maxColors);
  if (palette.isEmpty) {
    return <_VectorColorPaths>[];
  }

  final int pixelCount = width * height;
  final Uint8List labels = Uint8List(pixelCount);
  const int invalidLabel = 0xff;
  for (int i = 0; i < labels.length; i++) {
    labels[i] = invalidLabel;
  }

  final List<int> counts = List<int>.filled(palette.length, 0);
  final List<int> alphaSum = List<int>.filled(palette.length, 0);

  for (int i = 0, p = 0; i < rgba.length; i += 4, p++) {
    final int a = rgba[i + 3];
    if (a == 0) {
      continue;
    }
    int bestIndex = -1;
    int bestScore = 1 << 30;
    for (int c = 0; c < palette.length; c++) {
      final ui.Color color = palette[c];
      final int dr = rgba[i] - color.red;
      final int dg = rgba[i + 1] - color.green;
      final int db = rgba[i + 2] - color.blue;
      final int score = dr * dr + dg * dg + db * db;
      if (score < bestScore) {
        bestScore = score;
        bestIndex = c;
      }
    }
    if (bestIndex >= 0) {
      labels[p] = bestIndex;
      counts[bestIndex] += 1;
      alphaSum[bestIndex] += a;
    }
  }

  final List<_VectorColorPaths> shapes = <_VectorColorPaths>[];
  for (int c = 0; c < palette.length; c++) {
    if (counts[c] == 0) {
      continue;
    }
    final Uint8List mask = Uint8List(pixelCount);
    for (int i = 0; i < pixelCount; i++) {
      if (labels[i] == c) {
        mask[i] = 1;
      }
    }
    final List<List<ui.Offset>> polygons = _maskToPolygons(
      mask: mask,
      width: width,
      height: height,
      simplifyEpsilon: simplifyEpsilon,
    );
    if (polygons.isEmpty) {
      continue;
    }
    final double opacity =
        (alphaSum[c] / (counts[c] * 255.0)).clamp(0.0, 1.0);
    shapes.add(
      _VectorColorPaths(
        color: palette[c].withAlpha(255),
        opacity: opacity,
        polygons: polygons,
      ),
    );
  }
  return shapes;
}

List<ui.Color> _extractPalette(Uint8List rgba, int maxColors) {
  if (rgba.isEmpty || maxColors <= 0) {
    return <ui.Color>[];
  }
  const int step = 16; // 4-bit quantization per channel
  final Map<int, _PaletteBucket> buckets = <int, _PaletteBucket>{};
  for (int i = 0; i < rgba.length; i += 4) {
    final int a = rgba[i + 3];
    if (a == 0) {
      continue;
    }
    final int r = rgba[i];
    final int g = rgba[i + 1];
    final int b = rgba[i + 2];
    final int qr = (r ~/ step) * step;
    final int qg = (g ~/ step) * step;
    final int qb = (b ~/ step) * step;
    final int key = (qr << 16) | (qg << 8) | qb;
    final _PaletteBucket bucket = buckets.putIfAbsent(
      key,
      () => _PaletteBucket(),
    );
    bucket.count += 1;
    bucket.sumR += r;
    bucket.sumG += g;
    bucket.sumB += b;
  }

  final List<MapEntry<int, _PaletteBucket>> sorted = buckets.entries.toList()
    ..sort(
      (a, b) => b.value.count.compareTo(a.value.count),
    );
  final int take = math.min(maxColors, sorted.length);
  final List<ui.Color> palette = <ui.Color>[];
  for (int i = 0; i < take; i++) {
    final _PaletteBucket bucket = sorted[i].value;
    final int count = math.max(bucket.count, 1);
    final int r = (bucket.sumR / count).round().clamp(0, 255);
    final int g = (bucket.sumG / count).round().clamp(0, 255);
    final int b = (bucket.sumB / count).round().clamp(0, 255);
    palette.add(ui.Color.fromARGB(255, r, g, b));
  }
  return palette;
}

List<List<ui.Offset>> _maskToPolygons({
  required Uint8List mask,
  required int width,
  required int height,
  required double simplifyEpsilon,
}) {
  // Use a stride-based key instead of bit shifting to avoid 32-bit truncation
  // on Web (JS bitwise ops are limited to 32 bits).
  final int pointStride = width + 1;
  final List<_Edge> edges = <_Edge>[];
  for (int y = 0; y < height; y++) {
    final int rowOffset = y * width;
    for (int x = 0; x < width; x++) {
      if (mask[rowOffset + x] == 0) {
        continue;
      }
      final bool topEmpty = y == 0 || mask[rowOffset + x - width] == 0;
      final bool bottomEmpty =
          y == height - 1 || mask[rowOffset + x + width] == 0;
      final bool leftEmpty = x == 0 || mask[rowOffset + x - 1] == 0;
      final bool rightEmpty =
          x == width - 1 || mask[rowOffset + x + 1] == 0;

      if (topEmpty) {
        edges.add(
          _Edge(
            _encodePoint(x, y, pointStride),
            _encodePoint(x + 1, y, pointStride),
          ),
        );
      }
      if (rightEmpty) {
        edges.add(
          _Edge(
            _encodePoint(x + 1, y, pointStride),
            _encodePoint(x + 1, y + 1, pointStride),
          ),
        );
      }
      if (bottomEmpty) {
        edges.add(
          _Edge(
            _encodePoint(x + 1, y + 1, pointStride),
            _encodePoint(x, y + 1, pointStride),
          ),
        );
      }
      if (leftEmpty) {
        edges.add(
          _Edge(
            _encodePoint(x, y + 1, pointStride),
            _encodePoint(x, y, pointStride),
          ),
        );
      }
    }
  }

  if (edges.isEmpty) {
    return <List<ui.Offset>>[];
  }

  final Map<int, List<int>> edgesFrom = <int, List<int>>{};
  for (int i = 0; i < edges.length; i++) {
    edgesFrom.putIfAbsent(edges[i].start, () => <int>[]).add(i);
  }

  final List<bool> used = List<bool>.filled(edges.length, false);
  final List<List<ui.Offset>> polygons = <List<ui.Offset>>[];

  for (int i = 0; i < edges.length; i++) {
    if (used[i]) {
      continue;
    }
    final List<ui.Offset> points = <ui.Offset>[];
    int currentEdgeIndex = i;
    final int startKey = edges[i].start;
    bool closed = false;

    while (true) {
      final _Edge edge = edges[currentEdgeIndex];
      used[currentEdgeIndex] = true;
      if (points.isEmpty) {
        points.add(_decodePoint(edge.start, pointStride));
      }
      points.add(_decodePoint(edge.end, pointStride));

      if (edge.end == startKey) {
        closed = true;
        break;
      }

      final List<int>? candidates = edgesFrom[edge.end];
      int? nextEdgeIndex;
      if (candidates != null) {
        while (candidates.isNotEmpty) {
          final int candidate = candidates.removeLast();
          if (!used[candidate]) {
            nextEdgeIndex = candidate;
            break;
          }
        }
      }
      if (nextEdgeIndex == null) {
        break;
      }
      currentEdgeIndex = nextEdgeIndex;
    }

    if (points.length < 3 || !closed) {
      continue;
    }
    if (points.first != points.last) {
      points.add(points.first);
    }

    final List<ui.Offset> simplified = _simplifyPolygon(
      points,
      simplifyEpsilon,
    );
    if (simplified.length < 3) {
      continue;
    }
    final double area = _polygonArea(simplified).abs();
    if (area < 0.5) {
      continue;
    }
    polygons.add(simplified);
  }

  return polygons;
}

int _encodePoint(int x, int y, int stride) => y * stride + x;

ui.Offset _decodePoint(int key, int stride) {
  final int y = key ~/ stride;
  final int x = key - y * stride;
  return ui.Offset(x.toDouble(), y.toDouble());
}

double _polygonArea(List<ui.Offset> points) {
  if (points.length < 3) {
    return 0;
  }
  final bool closed = points.first == points.last;
  final int limit = closed ? points.length - 1 : points.length;
  double area = 0;
  for (int i = 0; i < limit; i++) {
    final ui.Offset p1 = points[i];
    final ui.Offset p2 = points[(i + 1) % limit];
    area += p1.dx * p2.dy - p2.dx * p1.dy;
  }
  return area * 0.5;
}

List<ui.Offset> _simplifyPolygon(List<ui.Offset> points, double epsilon) {
  if (points.length <= 3 || epsilon <= 0) {
    return points;
  }
  final bool closed = points.first == points.last;
  final List<ui.Offset> work = closed
      ? List<ui.Offset>.from(points)
      : <ui.Offset>[...points, points.first];

  List<ui.Offset> rdp(List<ui.Offset> pts) {
    if (pts.length <= 2) {
      return pts;
    }
    double maxDist = 0;
    int index = 0;
    for (int i = 1; i < pts.length - 1; i++) {
      final double d = _pointToSegmentDistance(pts[i], pts.first, pts.last);
      if (d > maxDist) {
        maxDist = d;
        index = i;
      }
    }
    if (maxDist > epsilon) {
      final List<ui.Offset> left = rdp(pts.sublist(0, index + 1));
      final List<ui.Offset> right = rdp(pts.sublist(index, pts.length));
      return <ui.Offset>[
        ...left.sublist(0, left.length - 1),
        ...right,
      ];
    }
    return <ui.Offset>[pts.first, pts.last];
  }

  final List<ui.Offset> simplified = rdp(work);
  if (simplified.isEmpty) {
    return simplified;
  }
  if (simplified.first != simplified.last) {
    simplified.add(simplified.first);
  }
  return simplified;
}

double _pointToSegmentDistance(
  ui.Offset p,
  ui.Offset a,
  ui.Offset b,
) {
  final double dx = b.dx - a.dx;
  final double dy = b.dy - a.dy;
  if (dx == 0 && dy == 0) {
    return (p - a).distance;
  }
  final double t = (((p.dx - a.dx) * dx) + ((p.dy - a.dy) * dy)) /
      (dx * dx + dy * dy);
  final double clampedT = t.clamp(0.0, 1.0);
  final double projX = a.dx + clampedT * dx;
  final double projY = a.dy + clampedT * dy;
  final double ox = p.dx - projX;
  final double oy = p.dy - projY;
  return math.sqrt(ox * ox + oy * oy);
}
