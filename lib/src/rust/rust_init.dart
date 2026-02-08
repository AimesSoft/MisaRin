import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:misa_rin/app/utils/web_log.dart';

import 'api/canvas_engine.dart' as rust_canvas_engine;
import 'frb_generated.dart';

Future<void>? _rustInitFuture;

class _WebSyncGuardHandler extends BaseHandler {
  @override
  S executeSync<S, E extends Object, WireSyncType>(
    SyncTask<S, E, WireSyncType> task,
  ) {
    final String name = task.constMeta.debugName;
    if (kIsWeb) {
      reportWebLog('FRB sync call on web: $name');
    }
    throw UnsupportedError('FRB sync call on web: $name');
  }
}

/// 确保 flutter_rust_bridge 在每个 isolate 内只初始化一次。
Future<void> ensureRustInitialized() async {
  try {
    _rustInitFuture ??= RustLib.init(
      handler: kIsWeb ? _WebSyncGuardHandler() : null,
    );
    await _rustInitFuture;
    if (kIsWeb) {
      await rust_canvas_engine.canvasEngineInit();
    }
  } catch (_) {
    _rustInitFuture = null;
    rethrow;
  }
}
