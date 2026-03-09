import 'package:flutter/foundation.dart';

class BackendCanvasLog {
  const BackendCanvasLog._();

  static const String _env = String.fromEnvironment(
    'MISA_RIN_DEBUG_BACKEND_CANVAS',
    defaultValue: '',
  );
  static final bool _enabled = _env == '1' || _env == 'true';

  static bool get enabled => _enabled;

  static void info(String message) {
    if (!_enabled) {
      return;
    }
    // Use print to avoid debugPrint throttling in noisy sessions.
    print('[backend_canvas] $message');
  }

  static void warn(String message) {
    if (!_enabled) {
      return;
    }
    print('[backend_canvas][warn] $message');
  }
}
