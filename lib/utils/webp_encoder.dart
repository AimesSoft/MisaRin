import 'dart:typed_data';

import 'webp_encoder_stub.dart'
    if (dart.library.io) 'webp_encoder_io.dart';

Future<Uint8List> encodeWebpRgba({
  required Uint8List rgba,
  required int width,
  required int height,
  required bool lossless,
  required int quality,
}) {
  return encodeWebpRgbaImpl(
    rgba: rgba,
    width: width,
    height: height,
    lossless: lossless,
    quality: quality,
  );
}
