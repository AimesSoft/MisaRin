import 'package:flutter/foundation.dart';

import 'frb_generated.dart';

Future<void>? _rustInitFuture;

/// 确保 flutter_rust_bridge 在每个 isolate 内只初始化一次。
Future<void> ensureRustInitialized() async {
  try {
    _rustInitFuture ??= RustLib.init();
    await _rustInitFuture;
  } catch (_) {
    _rustInitFuture = null;
    rethrow;
  }
}
