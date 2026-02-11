import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

class RustLibMisaRinWeb {
  RustLibMisaRinWeb._();

  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'misarin/rust_canvas_texture',
      const StandardMethodCodec(),
      registrar.messenger,
    );
    final RustLibMisaRinWeb instance = RustLibMisaRinWeb._();
    channel.setMethodCallHandler(instance._handleMethodCall);
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'getTextureInfo':
        final Map<dynamic, dynamic>? args =
            call.arguments as Map<dynamic, dynamic>?;
        final int width = _readInt(args, 'width', 1);
        final int height = _readInt(args, 'height', 1);
        return <String, Object?>{
          'textureId': null,
          'engineHandle': null,
          'width': width,
          'height': height,
          'isNewEngine': false,
        };
      case 'disposeTexture':
        return null;
      default:
        throw PlatformException(
          code: 'unimplemented',
          message: 'Method ${call.method} not implemented on web.',
        );
    }
  }

  int _readInt(Map<dynamic, dynamic>? args, String key, int fallback) {
    if (args == null) {
      return fallback;
    }
    final Object? value = args[key];
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return fallback;
  }
}
