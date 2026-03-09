import 'dart:typed_data';

import 'package:swipelab_webp/swipelab_webp.dart';

Future<Uint8List> encodeWebpRgbaImpl({
  required Uint8List rgba,
  required int width,
  required int height,
  required bool lossless,
  required int quality,
}) async {
  if (lossless) {
    final Uint8List? encoded = WebPEncoder.encodeRgbaLossless(
      rgba: rgba,
      width: width,
      height: height,
    );
    if (encoded == null) {
      throw StateError('WebP 无损编码失败');
    }
    return encoded;
  }
  final Uint8List? encoded = WebPEncoder.encodeRgba(
    rgba: rgba,
    width: width,
    height: height,
    quality: quality.clamp(1, 100).toDouble(),
  );
  if (encoded == null) {
    throw StateError('WebP 有损编码失败');
  }
  return encoded;
}
