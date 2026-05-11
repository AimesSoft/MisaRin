import 'dart:typed_data';

import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:misa_rin/utils/io_shim.dart';

class IosPhotoSaver {
  static Future<void> saveImageToPhotos(
    Uint8List bytes, {
    String? fileName,
  }) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Photo library is not available on this platform.');
    }
    final String? trimmed = fileName?.trim();
    final dynamic result = await ImageGallerySaver.saveImage(
      bytes,
      name: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    );
    if (result is Map) {
      final dynamic success = result['isSuccess'] ?? result['success'];
      if (success is bool && !success) {
        final String? error =
            result['errorMessage']?.toString() ?? result['error']?.toString();
        throw Exception(error ?? 'Failed to save image.');
      }
    }
  }
}
