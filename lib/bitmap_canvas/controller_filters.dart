part of 'controller.dart';

bool _controllerRunAntialiasPass(
  BitmapCanvasController _,
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

      int totalWeight = BitmapCanvasController._kAntialiasCenterWeight;
      int weightedAlpha =
          alpha * BitmapCanvasController._kAntialiasCenterWeight;
      int weightedPremulR =
          centerR * alpha * BitmapCanvasController._kAntialiasCenterWeight;
      int weightedPremulG =
          centerG * alpha * BitmapCanvasController._kAntialiasCenterWeight;
      int weightedPremulB =
          centerB * alpha * BitmapCanvasController._kAntialiasCenterWeight;

      for (int i = 0; i < BitmapCanvasController._kAntialiasDx.length; i++) {
        final int nx = x + BitmapCanvasController._kAntialiasDx[i];
        final int ny = y + BitmapCanvasController._kAntialiasDy[i];
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
          continue;
        }
        final int neighbor = src[ny * width + nx];
        final int neighborAlpha = (neighbor >> 24) & 0xff;
        final int weight = BitmapCanvasController._kAntialiasWeights[i];
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

      final int newAlpha = (alpha + (deltaAlpha * factor).round()).clamp(
        0,
        255,
      );
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

bool _controllerRunEdgeAwareColorSmoothPass(
  BitmapCanvasController _,
  Uint32List src,
  Uint32List dest,
  Uint32List blurBuffer,
  int width,
  int height,
) {
  _controllerComputeGaussianBlur(src, blurBuffer, width, height);
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

      final double gradient = _controllerComputeEdgeGradient(
        src,
        width,
        height,
        x,
        y,
      );
      final double weight = _controllerEdgeSmoothWeight(gradient);
      if (weight <= 0) {
        dest[index] = baseColor;
        continue;
      }
      final int blurred = blurBuffer[index];
      final int newColor = _controllerLerpArgb(baseColor, blurred, weight);
      dest[index] = newColor;
      if (newColor != baseColor) {
        modified = true;
      }
    }
  }
  return modified;
}

double _controllerComputeEdgeGradient(
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
  final double centerLuma = _controllerComputeLuma(center);
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
    final double diff = (centerLuma - _controllerComputeLuma(neighbor)).abs();
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

double _controllerEdgeSmoothWeight(double gradient) {
  if (gradient <= BitmapCanvasController._kEdgeDetectMin) {
    return 0;
  }
  final double normalized =
      ((gradient - BitmapCanvasController._kEdgeDetectMin) /
              (BitmapCanvasController._kEdgeDetectMax -
                  BitmapCanvasController._kEdgeDetectMin))
          .clamp(0.0, 1.0);
  return math.pow(normalized, BitmapCanvasController._kEdgeSmoothGamma) *
      BitmapCanvasController._kEdgeSmoothStrength;
}

void _controllerComputeGaussianBlur(
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
          final int weight =
              BitmapCanvasController._kGaussianKernel5x5[kernelIndex++];
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

double _controllerComputeLuma(int color) {
  final int alpha = (color >> 24) & 0xff;
  if (alpha == 0) {
    return 0;
  }
  final int r = (color >> 16) & 0xff;
  final int g = (color >> 8) & 0xff;
  final int b = color & 0xff;
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
}

int _controllerLerpArgb(int a, int b, double t) {
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

bool _controllerApplyAntialiasToActiveLayer(
  BitmapCanvasController controller,
  int level, {
  bool previewOnly = false,
}) {
  if (controller._layers.isEmpty) {
    return false;
  }
  final BitmapLayerState layer = controller._activeLayer;
  if (layer.locked) {
    return false;
  }
  final List<double> profile = List<double>.from(
    BitmapCanvasController._kAntialiasBlendProfiles[level.clamp(0, 3)] ??
        const <double>[0.25],
  );
  if (profile.isEmpty) {
    return false;
  }
  final Uint32List pixels = layer.surface.pixels;
  if (pixels.isEmpty) {
    return false;
  }
  final Uint32List temp = Uint32List(pixels.length);
  Uint32List src = pixels;
  Uint32List dest = temp;
  bool anyChange = false;
  for (final double factor in profile) {
    if (factor <= 0) {
      continue;
    }
    final bool alphaChanged = _controllerRunAntialiasPass(
      controller,
      src,
      dest,
      controller._width,
      controller._height,
      factor,
    );
    if (!alphaChanged) {
      continue;
    }
    if (previewOnly) {
      return true;
    }
    anyChange = true;
    final Uint32List swap = src;
    src = dest;
    dest = swap;
  }

  final Uint32List blurBuffer = Uint32List(pixels.length);
  final bool colorChanged = _controllerRunEdgeAwareColorSmoothPass(
    controller,
    src,
    dest,
    blurBuffer,
    controller._width,
    controller._height,
  );
  if (colorChanged) {
    if (previewOnly) {
      return true;
    }
    anyChange = true;
    final Uint32List swap = src;
    src = dest;
    dest = swap;
  }
  if (!anyChange) {
    return false;
  }
  if (previewOnly) {
    return true;
  }
  if (!identical(src, pixels)) {
    pixels.setAll(0, src);
  }
  layer.surface.markDirty();
  controller._markDirty(layerId: layer.id, pixelsDirty: true);
  controller.notifyListeners();
  return true;
}
