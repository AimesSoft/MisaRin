import 'package:flutter/foundation.dart';

class BackendCanvasTimeline {
  const BackendCanvasTimeline._();

  static const String _envTimeline = String.fromEnvironment(
    'MISA_RIN_DEBUG_BACKEND_CANVAS_TIMELINE',
    defaultValue: '',
  );
  static const String _envInput = String.fromEnvironment(
    'MISA_RIN_DEBUG_BACKEND_CANVAS_INPUT',
    defaultValue: '',
  );
  static const String _envRustInput = String.fromEnvironment(
    'MISA_RIN_DEBUG_RUST_CANVAS_INPUT',
    defaultValue: '',
  );
  static final bool _enabled =
      _isTruthy(_envTimeline) ||
      _isTruthy(_envInput) ||
      _isTruthy(_envRustInput);

  static bool _isTruthy(String value) => value == '1' || value == 'true';

  static DateTime? _start;
  static DateTime? _last;

  static void start(String label) {
    if (!_enabled) {
      return;
    }
    reset();
    mark(label);
  }

  static void reset() {
    if (!_enabled) {
      return;
    }
    _start = null;
    _last = null;
  }

  static void mark(String label) {
    if (!_enabled) {
      return;
    }
    final DateTime now = DateTime.now();
    _start ??= now;
    final int fromStartMs = now.difference(_start!).inMilliseconds;
    final int fromLastMs =
        _last == null ? 0 : now.difference(_last!).inMilliseconds;
    debugPrint(
      '[backend_canvas_timeline] +${fromStartMs}ms (+${fromLastMs}ms) '
      '$label @ ${now.toIso8601String()}',
    );
    _last = now;
  }
}
