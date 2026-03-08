import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/svg.dart' as svg;

const int kDefaultSvgRasterSizePx = 1024;
const int kMinSvgRasterSizePx = 16;
const int kMaxSvgRasterSizePx = 16384;

class DecodedUiImageFrame {
  const DecodedUiImageFrame({
    required this.image,
    required this.isSvgRasterized,
  });

  final ui.Image image;
  final bool isSvgRasterized;
}

bool hasSvgExtension(String? value) {
  final String lower = value?.trim().toLowerCase() ?? '';
  if (lower.isEmpty) {
    return false;
  }
  return lower == 'svg' || lower == '.svg' || lower.endsWith('.svg');
}

int normalizeSvgRasterSize(
  int? rasterSizePx, {
  int fallback = kDefaultSvgRasterSizePx,
}) {
  final int base = rasterSizePx ?? fallback;
  return base.clamp(kMinSvgRasterSizePx, kMaxSvgRasterSizePx);
}

Future<DecodedUiImageFrame> decodeBitmapOrSvgFrame(
  Uint8List bytes, {
  int? svgRasterSizePx,
}) async {
  try {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    try {
      final ui.FrameInfo frame = await codec.getNextFrame();
      return DecodedUiImageFrame(image: frame.image, isSvgRasterized: false);
    } finally {
      codec.dispose();
    }
  } catch (bitmapError, bitmapStackTrace) {
    final ui.Image? svgImage = await tryDecodeSvgImage(
      bytes,
      rasterSizePx: svgRasterSizePx,
    );
    if (svgImage != null) {
      return DecodedUiImageFrame(image: svgImage, isSvgRasterized: true);
    }
    Error.throwWithStackTrace(bitmapError, bitmapStackTrace);
  }
}

Future<ui.Image?> tryDecodeSvgImage(
  Uint8List bytes, {
  int? rasterSizePx,
}) async {
  final int longestSide = normalizeSvgRasterSize(rasterSizePx);
  ui.Picture? recordedPicture;
  ui.Picture? sourcePicture;
  try {
    final svg.PictureInfo pictureInfo = await svg.vg.loadPicture(
      svg.SvgBytesLoader(bytes),
      null,
    );
    sourcePicture = pictureInfo.picture;
    final ({int width, int height, double scale}) target = _targetSizeFromSvg(
      pictureInfo.size,
      longestSide: longestSide,
    );
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    if (target.scale != 1.0) {
      canvas.scale(target.scale, target.scale);
    }
    canvas.drawPicture(sourcePicture);
    recordedPicture = recorder.endRecording();
    final ui.Image image = await recordedPicture.toImage(
      target.width,
      target.height,
    );
    return image;
  } catch (_) {
    return null;
  } finally {
    recordedPicture?.dispose();
    sourcePicture?.dispose();
  }
}

({int width, int height, double scale}) _targetSizeFromSvg(
  ui.Size sourceSize, {
  required int longestSide,
}) {
  final double sourceWidth = sourceSize.width;
  final double sourceHeight = sourceSize.height;
  if (!sourceWidth.isFinite ||
      !sourceHeight.isFinite ||
      sourceWidth <= 0 ||
      sourceHeight <= 0) {
    return (width: longestSide, height: longestSide, scale: 1.0);
  }
  final double sourceLongest = math.max(sourceWidth, sourceHeight);
  if (sourceLongest <= 0 || !sourceLongest.isFinite) {
    return (width: longestSide, height: longestSide, scale: 1.0);
  }
  final double scale = longestSide / sourceLongest;
  final int width = math.max(1, (sourceWidth * scale).round());
  final int height = math.max(1, (sourceHeight * scale).round());
  return (width: width, height: height, scale: scale);
}
