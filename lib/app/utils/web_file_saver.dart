import 'package:flutter/foundation.dart';

import 'web_file_saver_stub.dart'
    if (dart.library.html) 'web_file_saver_web.dart'
    as saver_impl;

/// 提供基于浏览器下载能力的文件保存工具。
class WebFileSaver {
  static bool get supported => kIsWeb;

  static Future<void> saveBytes({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) {
    if (!supported) {
      throw UnsupportedError('WebFileSaver 仅可在 Web 环境调用');
    }
    return saver_impl.saveBytes(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
  }
}
