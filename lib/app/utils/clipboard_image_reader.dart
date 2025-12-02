import 'dart:async';
import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

class ClipboardImageData {
  const ClipboardImageData({required this.bytes, this.fileName});

  final Uint8List bytes;
  final String? fileName;
}

class ClipboardImageReader {
  const ClipboardImageReader._();

  static Future<ClipboardImageData?> readImage() async {
    try {
      final Uint8List? bytes = await Pasteboard.image;
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      return ClipboardImageData(bytes: bytes, fileName: _buildFileName(bytes));
    } catch (_) {
      return null;
    }
  }

  static String _buildFileName(Uint8List bytes) {
    return '剪贴板图像.${_extensionFromBytes(bytes)}';
  }

  static String _extensionFromBytes(Uint8List bytes) {
    if (_matches(bytes, const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ])) {
      return 'png';
    }
    if (_matches(bytes, const [0xFF, 0xD8, 0xFF])) {
      return 'jpg';
    }
    if (_matches(bytes, const [0x47, 0x49, 0x46, 0x38])) {
      return 'gif';
    }
    if (_matches(bytes, const [0x42, 0x4D])) {
      return 'bmp';
    }
    if (bytes.length >= 12 &&
        _matches(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
        _matches(bytes, const [0x57, 0x45, 0x42, 0x50], offset: 8)) {
      return 'webp';
    }
    return 'png';
  }

  static bool _matches(Uint8List bytes, List<int> signature, {int offset = 0}) {
    if (bytes.length < signature.length + offset) {
      return false;
    }
    for (int i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) {
        return false;
      }
    }
    return true;
  }
}
