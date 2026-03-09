import 'dart:typed_data';

Future<Uint8List> encodeWebpRgbaImpl({
  required Uint8List rgba,
  required int width,
  required int height,
  required bool lossless,
  required int quality,
}) {
  throw UnsupportedError('WebP export is not supported on this platform.');
}
