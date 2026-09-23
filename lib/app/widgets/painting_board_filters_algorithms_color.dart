part of 'painting_board.dart';

Uint8List _computeHueSaturationPreviewPixels(List<Object?> args) {
  final Uint8List source = args[0] as Uint8List;
  final double hue = (args[1] as num).toDouble();
  final double saturation = (args[2] as num).toDouble();
  final double lightness = (args[3] as num).toDouble();
  final Uint8List pixels = Uint8List.fromList(source);
  _filterApplyHueSaturationToBitmap(pixels, hue, saturation, lightness);
  return pixels;
}

Future<Uint8List> _generateBlackWhitePreviewBytes(List<Object?> args) async {
  try {
    return await compute<List<Object?>, Uint8List>(
      _computeBlackWhitePreviewPixels,
      args,
    );
  } on UnsupportedError catch (_) {
    return _computeBlackWhitePreviewPixels(args);
  }
}

Uint8List _computeBlackWhitePreviewPixels(List<Object?> args) {
  final Uint8List source = args[0] as Uint8List;
  final double black = (args[1] as num).toDouble();
  final double white = (args[2] as num).toDouble();
  final double midTone = (args[3] as num).toDouble();
  final Uint8List pixels = Uint8List.fromList(source);
  _filterApplyBlackWhiteToBitmap(pixels, black, white, midTone);
  return pixels;
}

Future<Uint8List> _generateBinarizePreviewBytes(List<Object?> args) async {
  try {
    return await compute<List<Object?>, Uint8List>(
      _computeBinarizePreviewPixels,
      args,
    );
  } on UnsupportedError catch (_) {
    return _computeBinarizePreviewPixels(args);
  }
}

Uint8List _computeBinarizePreviewPixels(List<Object?> args) {
  final Uint8List source = args[0] as Uint8List;
  final double threshold = (args[1] as num).toDouble();
  final Uint8List pixels = Uint8List.fromList(source);
  _filterApplyBinarizeToBitmap(
    pixels,
    threshold.round().clamp(0, 255),
  );
  return pixels;
}

Future<Uint8List> _generateScanPaperDrawingPreviewBytes(
  List<Object?> args,
) async {
  try {
    return await compute<List<Object?>, Uint8List>(
      _computeScanPaperDrawingPreviewPixels,
      args,
    );
  } on UnsupportedError catch (_) {
    return _computeScanPaperDrawingPreviewPixels(args);
  }
}

Uint8List _computeScanPaperDrawingPreviewPixels(List<Object?> args) {
  final Uint8List source = args[0] as Uint8List;
  final double blackPoint = (args[1] as num).toDouble();
  final double whitePoint = (args[2] as num).toDouble();
  final double midTone = (args[3] as num).toDouble();
  final bool toneMappingEnabled =
      blackPoint.abs() > 1e-6 ||
      (whitePoint - 100.0).abs() > 1e-6 ||
      midTone.abs() > 1e-6;

  final double blackNorm = blackPoint.clamp(0.0, 100.0) / 100.0;
  final double whiteNorm = whitePoint.clamp(0.0, 100.0) / 100.0;
  final double safeWhite = math.max(
    blackNorm + (_kBlackWhiteMinRange / 100.0),
    whiteNorm,
  );
  final double invRange = 1.0 / math.max(0.0001, safeWhite - blackNorm);
  final double gamma = math.pow(2.0, midTone.clamp(-100.0, 100.0) / 100.0)
      .toDouble();

  final Uint8List pixels = Uint8List.fromList(source);
  for (int i = 0; i + 3 < pixels.length; i += 4) {
    final int alpha = pixels[i + 3];
    if (alpha == 0) {
      continue;
    }
    final int r = pixels[i];
    final int g = pixels[i + 1];
    final int b = pixels[i + 2];
    final int mapped = toneMappingEnabled
        ? _scanPaperDrawingMapRgbToArgbWithToneMapping(
            r,
            g,
            b,
            black: blackNorm,
            invRange: invRange,
            gamma: gamma,
          )
        : _scanPaperDrawingMapRgbToArgb(r, g, b);
    if (mapped == 0) {
      pixels[i] = 0;
      pixels[i + 1] = 0;
      pixels[i + 2] = 0;
      pixels[i + 3] = 0;
      continue;
    }
    pixels[i] = (mapped >> 16) & 0xFF;
    pixels[i + 1] = (mapped >> 8) & 0xFF;
    pixels[i + 2] = mapped & 0xFF;
    pixels[i + 3] = 255;
  }
  return pixels;
}

void _filterApplyHueSaturationToBitmap(
  Uint8List bitmap,
  double hueDelta,
  double saturationPercent,
  double lightnessPercent,
) {
  for (int i = 0; i < bitmap.length; i += 4) {
    final int alpha = bitmap[i + 3];
    if (alpha == 0) {
      continue;
    }
    final Color source = Color.fromARGB(
      alpha,
      bitmap[i],
      bitmap[i + 1],
      bitmap[i + 2],
    );
    final Color adjusted = _filterApplyHueSaturationToColor(
      source,
      hueDelta,
      saturationPercent,
      lightnessPercent,
    );
    bitmap[i] = adjusted.red;
    bitmap[i + 1] = adjusted.green;
    bitmap[i + 2] = adjusted.blue;
    bitmap[i + 3] = adjusted.alpha;
  }
}

void _filterApplyBrightnessContrastToBitmap(
  Uint8List bitmap,
  double brightnessPercent,
  double contrastPercent,
) {
  final double brightnessOffset = brightnessPercent / 100.0 * 255.0;
  final double contrastFactor = math.max(0.0, 1.0 + contrastPercent / 100.0);
  for (int i = 0; i < bitmap.length; i += 4) {
    final int alpha = bitmap[i + 3];
    if (alpha == 0) {
      continue;
    }
    bitmap[i] = _filterApplyBrightnessContrastChannel(
      bitmap[i],
      brightnessOffset,
      contrastFactor,
    );
    bitmap[i + 1] = _filterApplyBrightnessContrastChannel(
      bitmap[i + 1],
      brightnessOffset,
      contrastFactor,
    );
    bitmap[i + 2] = _filterApplyBrightnessContrastChannel(
      bitmap[i + 2],
      brightnessOffset,
      contrastFactor,
    );
  }
}

Color _filterApplyHueSaturationToColor(
  Color color,
  double hueDelta,
  double saturationPercent,
  double lightnessPercent,
) {
  final HSVColor hsv = HSVColor.fromColor(color);
  double hue = (hsv.hue + hueDelta) % 360.0;
  if (hue < 0) {
    hue += 360.0;
  }
  final double saturation = (hsv.saturation + saturationPercent / 100.0).clamp(
    0.0,
    1.0,
  );
  final double value = (hsv.value + lightnessPercent / 100.0).clamp(0.0, 1.0);
  return HSVColor.fromAHSV(hsv.alpha, hue, saturation, value).toColor();
}

Color _filterApplyBrightnessContrastToColor(
  Color color,
  double brightnessPercent,
  double contrastPercent,
) {
  final double brightnessOffset = brightnessPercent / 100.0 * 255.0;
  final double contrastFactor = math.max(0.0, 1.0 + contrastPercent / 100.0);
  final int r = _filterApplyBrightnessContrastChannel(
    color.red,
    brightnessOffset,
    contrastFactor,
  );
  final int g = _filterApplyBrightnessContrastChannel(
    color.green,
    brightnessOffset,
    contrastFactor,
  );
  final int b = _filterApplyBrightnessContrastChannel(
    color.blue,
    brightnessOffset,
    contrastFactor,
  );
  return Color.fromARGB(color.alpha, r, g, b);
}

int _filterApplyBrightnessContrastChannel(
  int channel,
  double brightnessOffset,
  double contrastFactor,
) {
  final double adjusted =
      ((channel - 128) * contrastFactor + 128 + brightnessOffset).clamp(
        0.0,
        255.0,
      );
  return adjusted.round();
}

void _filterApplyBlackWhiteToBitmap(
  Uint8List bitmap,
  double blackPoint,
  double whitePoint,
  double midTone,
) {
  final double black = blackPoint.clamp(0.0, 100.0) / 100.0;
  final double white = whitePoint.clamp(0.0, 100.0) / 100.0;
  final double safeWhite = math.max(
    black + (_kBlackWhiteMinRange / 100.0),
    white,
  );
  final double invRange = 1.0 / math.max(0.0001, safeWhite - black);
  final double gamma = math.pow(2.0, midTone / 100.0).toDouble();
  for (int i = 0; i < bitmap.length; i += 4) {
    final int alpha = bitmap[i + 3];
    if (alpha == 0) {
      continue;
    }
    final double luminance =
        (bitmap[i] * 0.299 + bitmap[i + 1] * 0.587 + bitmap[i + 2] * 0.114) /
        255.0;
    double normalized = ((luminance - black) * invRange).clamp(0.0, 1.0);
    normalized = math.pow(normalized, gamma).clamp(0.0, 1.0).toDouble();
    final int gray = _filterRoundChannel(normalized * 255.0);
    bitmap[i] = gray;
    bitmap[i + 1] = gray;
    bitmap[i + 2] = gray;
    bitmap[i + 3] = alpha;
  }
}

Color _filterApplyBlackWhiteToColor(
  Color color,
  double blackPoint,
  double whitePoint,
  double midTone,
) {
  final double black = blackPoint.clamp(0.0, 100.0) / 100.0;
  final double white = whitePoint.clamp(0.0, 100.0) / 100.0;
  final double safeWhite = math.max(
    black + (_kBlackWhiteMinRange / 100.0),
    white,
  );
  final double invRange = 1.0 / math.max(0.0001, safeWhite - black);
  final double gamma = math.pow(2.0, midTone / 100.0).toDouble();
  final double luminance =
      (color.red * 0.299 + color.green * 0.587 + color.blue * 0.114) / 255.0;
  double normalized = ((luminance - black) * invRange).clamp(0.0, 1.0);
  normalized = math.pow(normalized, gamma).clamp(0.0, 1.0).toDouble();
  final int gray = _filterRoundChannel(normalized * 255.0);
  return Color.fromARGB(color.alpha, gray, gray, gray);
}

void _filterApplyBinarizeToBitmap(Uint8List bitmap, int threshold) {
  final int clamped = threshold.clamp(0, 255);
  for (int i = 0; i < bitmap.length; i += 4) {
    final int alpha = bitmap[i + 3];
    if (alpha == 0) {
      continue;
    }
    if (alpha >= clamped) {
      if (alpha != 255) {
        bitmap[i + 3] = 255;
      }
      continue;
    }
    if (bitmap[i] != 0 || bitmap[i + 1] != 0 || bitmap[i + 2] != 0) {
      bitmap[i] = 0;
      bitmap[i + 1] = 0;
      bitmap[i + 2] = 0;
    }
    if (alpha != 0) {
      bitmap[i + 3] = 0;
    }
  }
}

Color _filterApplyBinarizeToColor(Color color, int threshold) {
  final int clamped = threshold.clamp(0, 255);
  if (color.alpha == 0 || color.alpha == 255) {
    return color;
  }
  final int nextAlpha = color.alpha >= clamped ? 255 : 0;
  if (nextAlpha == color.alpha) {
    return color;
  }
  return color.withAlpha(nextAlpha);
}

bool _filterBitmapHasVisiblePixels(Uint8List bitmap) {
  for (int i = 3; i < bitmap.length; i += 4) {
    if (bitmap[i] != 0) {
      return true;
    }
  }
  return false;
}

bool _filterBitmapEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

Future<_ScanPaperDrawingComputeResult> _generateScanPaperDrawingResult(
  Uint8List? bitmap,
  Color? fillColor, {
  double blackPoint = 0,
  double whitePoint = 100,
  double midTone = 0,
}) async {
  final List<Object?> args = <Object?>[
    bitmap,
    fillColor?.value,
    blackPoint,
    whitePoint,
    midTone,
  ];
  try {
    return await compute(_computeScanPaperDrawing, args);
  } on UnsupportedError catch (_) {
    return _computeScanPaperDrawing(args);
  }
}

int _scanPaperDrawingMapRgbToArgb(int r, int g, int b) {
  final int maxChannel = math.max(r, math.max(g, b));
  final int minChannel = math.min(r, math.min(g, b));
  final int delta = maxChannel - minChannel;
  if (maxChannel >= _kScanPaperWhiteMaxThreshold &&
      delta <= _kScanPaperWhiteDeltaThreshold) {
    return 0;
  }

  final int r2 = r * r;
  final int g2 = g * g;
  final int b2 = b * b;
  final int dr = 255 - r;
  final int dg = 255 - g;
  final int db = 255 - b;

  final int distRed = dr * dr + g2 + b2;
  final int distGreen = r2 + dg * dg + b2;
  final int distBlue = r2 + g2 + db * db;
  int minDist = distRed;
  int mapped = 0xFFFF0000;
  if (distGreen < minDist) {
    minDist = distGreen;
    mapped = 0xFF00FF00;
  }
  if (distBlue < minDist) {
    minDist = distBlue;
    mapped = 0xFF0000FF;
  }
  if (minDist <= _kScanPaperColorDistanceThresholdSq) {
    return mapped;
  }

  final int distBlack = r2 + g2 + b2;
  if (distBlack <= _kScanPaperBlackDistanceThresholdSq) {
    return 0xFF000000;
  }
  return 0;
}

int _scanPaperDrawingMapRgbToArgbWithToneMapping(
  int r,
  int g,
  int b, {
  required double black,
  required double invRange,
  required double gamma,
}) {
  final int maxChannel = math.max(r, math.max(g, b));
  final int minChannel = math.min(r, math.min(g, b));
  final int delta = maxChannel - minChannel;

  final double luminance = (r * 0.299 + g * 0.587 + b * 0.114) / 255.0;
  double normalized = ((luminance - black) * invRange).clamp(0.0, 1.0);
  normalized = math.pow(normalized, gamma).clamp(0.0, 1.0).toDouble();
  final int gray = (normalized * 255.0).round().clamp(0, 255).toInt();
  if (gray >= _kScanPaperWhiteMaxThreshold &&
      delta <= _kScanPaperWhiteDeltaThreshold) {
    return 0;
  }

  final int r2 = r * r;
  final int g2 = g * g;
  final int b2 = b * b;
  final int dr = 255 - r;
  final int dg = 255 - g;
  final int db = 255 - b;

  final int distRed = dr * dr + g2 + b2;
  final int distGreen = r2 + dg * dg + b2;
  final int distBlue = r2 + g2 + db * db;
  int minDist = distRed;
  int mapped = 0xFFFF0000;
  if (distGreen < minDist) {
    minDist = distGreen;
    mapped = 0xFF00FF00;
  }
  if (distBlue < minDist) {
    minDist = distBlue;
    mapped = 0xFF0000FF;
  }
  if (minDist <= _kScanPaperColorDistanceThresholdSq) {
    return mapped;
  }

  final int distBlack = r2 + g2 + b2;
  if (distBlack <= _kScanPaperBlackDistanceThresholdSq) {
    return 0xFF000000;
  }
  return 0;
}

_ScanPaperDrawingComputeResult _computeScanPaperDrawing(List<Object?> args) {
  final Uint8List? bitmap = args[0] as Uint8List?;
  final int? fillColor = args[1] as int?;
  final double blackPoint = (args.length > 2 && args[2] is num)
      ? (args[2] as num).toDouble()
      : 0.0;
  final double whitePoint = (args.length > 3 && args[3] is num)
      ? (args[3] as num).toDouble()
      : 100.0;
  final double midTone = (args.length > 4 && args[4] is num)
      ? (args[4] as num).toDouble()
      : 0.0;
  final bool toneMappingEnabled =
      blackPoint.abs() > 1e-6 ||
      (whitePoint - 100.0).abs() > 1e-6 ||
      midTone.abs() > 1e-6;

  final double blackNorm = blackPoint.clamp(0.0, 100.0) / 100.0;
  final double whiteNorm = whitePoint.clamp(0.0, 100.0) / 100.0;
  final double safeWhite = math.max(
    blackNorm + (_kBlackWhiteMinRange / 100.0),
    whiteNorm,
  );
  final double invRange = 1.0 / math.max(0.0001, safeWhite - blackNorm);
  final double gamma = math.pow(2.0, midTone.clamp(-100.0, 100.0) / 100.0)
      .toDouble();

  Uint8List? processed = bitmap != null ? Uint8List.fromList(bitmap) : null;
  bool changed = false;
  bool hadVisiblePixels = false;

  if (processed != null) {
    final Uint8List? rustProcessed = _tryApplyRustCpuFilter(
      filterType: _kFilterTypeScanPaperDrawing,
      bitmap: processed,
      width: processed.length ~/ 4,
      height: 1,
      param0: blackPoint,
      param1: whitePoint,
      param2: midTone,
    );
    if (rustProcessed != null) {
      processed = rustProcessed;
      hadVisiblePixels = _filterBitmapHasVisiblePixels(processed);
      if (bitmap != null && !_filterBitmapEquals(processed, bitmap)) {
        changed = true;
      }
      if (!hadVisiblePixels) {
        processed = null;
        if (bitmap != null && _filterBitmapHasVisiblePixels(bitmap)) {
          changed = true;
        }
      }
    } else {
      for (int i = 0; i + 3 < processed.length; i += 4) {
        final int alpha = processed[i + 3];
        if (alpha == 0) {
          continue;
        }
        hadVisiblePixels = true;
        final int r = processed[i];
        final int g = processed[i + 1];
        final int b = processed[i + 2];
        final int mapped = toneMappingEnabled
            ? _scanPaperDrawingMapRgbToArgbWithToneMapping(
                r,
                g,
                b,
                black: blackNorm,
                invRange: invRange,
                gamma: gamma,
              )
            : _scanPaperDrawingMapRgbToArgb(r, g, b);
        if (mapped == 0) {
          if (alpha != 0) {
            changed = true;
          }
          processed[i] = 0;
          processed[i + 1] = 0;
          processed[i + 2] = 0;
          processed[i + 3] = 0;
          continue;
        }
        final int targetR = (mapped >> 16) & 0xFF;
        final int targetG = (mapped >> 8) & 0xFF;
        final int targetB = mapped & 0xFF;
        if (alpha != 255 || r != targetR || g != targetG || b != targetB) {
          changed = true;
        }
        processed[i] = targetR;
        processed[i + 1] = targetG;
        processed[i + 2] = targetB;
        processed[i + 3] = 255;
      }
      if (!_filterBitmapHasVisiblePixels(processed)) {
        processed = null;
        if (hadVisiblePixels) {
          changed = true;
        }
      }
    }
  }

  int? processedFill;
  if (fillColor != null) {
    final int alpha = (fillColor >> 24) & 0xFF;
    if (alpha != 0) {
      final int r = (fillColor >> 16) & 0xFF;
      final int g = (fillColor >> 8) & 0xFF;
      final int b = fillColor & 0xFF;
      final int mapped = toneMappingEnabled
          ? _scanPaperDrawingMapRgbToArgbWithToneMapping(
              r,
              g,
              b,
              black: blackNorm,
              invRange: invRange,
              gamma: gamma,
            )
          : _scanPaperDrawingMapRgbToArgb(r, g, b);
      if (mapped == 0) {
        processedFill = null;
        changed = true;
      } else {
        processedFill = mapped;
        if (mapped != fillColor) {
          changed = true;
        }
      }
    } else {
      processedFill = fillColor;
    }
  }

  return _ScanPaperDrawingComputeResult(
    bitmap: processed,
    fillColor: processedFill,
    changed: changed,
  );
}
