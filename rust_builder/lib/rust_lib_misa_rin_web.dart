import 'dart:async';
import 'dart:js_util' as js_util;

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

class RustLibMisaRinWeb {
  RustLibMisaRinWeb._();

  static final Map<String, _WebSurfaceEntry> _surfaces =
      <String, _WebSurfaceEntry>{};

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
        final int width = _readInt(args, 'width', 1).clamp(1, 16384);
        final int height = _readInt(args, 'height', 1).clamp(1, 16384);
        final int layerCount = _readInt(args, 'layerCount', 1).clamp(1, 4096);
        final int background =
            _readInt(args, 'backgroundColorArgb', 0xFFFFFFFF);
        final String surfaceId = _readString(args, 'surfaceId', 'default');
        final _WebSurfaceEntry? existing = _surfaces[surfaceId];

        if (!_hasWasmFunction('canvas_engine_create')) {
          return <String, Object?>{
            'textureId': null,
            'engineHandle': null,
            'width': width,
            'height': height,
            'isNewEngine': false,
          };
        }

        bool isNewEngine = false;
        _WebSurfaceEntry entry;
        if (existing == null) {
          final int handle = _createEngine(width, height);
          if (handle == 0) {
            return <String, Object?>{
              'textureId': null,
              'engineHandle': null,
              'width': width,
              'height': height,
              'isNewEngine': false,
            };
          }
          _attachPresent(handle, width, height);
          _resetCanvasWithLayers(handle, layerCount, background);
          entry = _WebSurfaceEntry(
            handle: handle,
            width: width,
            height: height,
            layerCount: layerCount,
            backgroundColorArgb: background,
          );
          _surfaces[surfaceId] = entry;
          isNewEngine = true;
        } else {
          entry = existing;
          final bool sizeChanged = entry.width != width || entry.height != height;
          final bool layerChanged = entry.layerCount != layerCount;
          final bool backgroundChanged =
              entry.backgroundColorArgb != background;

          if (sizeChanged || layerChanged) {
            final bool resized = _resizeCanvas(
              entry.handle,
              width,
              height,
              layerCount,
              background,
            );
            if (resized) {
              _attachPresent(entry.handle, width, height);
              entry
                ..width = width
                ..height = height
                ..layerCount = layerCount
                ..backgroundColorArgb = background;
            } else {
              _disposeEngine(entry.handle);
              final int handle = _createEngine(width, height);
              if (handle == 0) {
                _surfaces.remove(surfaceId);
                return <String, Object?>{
                  'textureId': null,
                  'engineHandle': null,
                  'width': width,
                  'height': height,
                  'isNewEngine': false,
                };
              }
              _attachPresent(handle, width, height);
              _resetCanvasWithLayers(handle, layerCount, background);
              entry = _WebSurfaceEntry(
                handle: handle,
                width: width,
                height: height,
                layerCount: layerCount,
                backgroundColorArgb: background,
              );
              _surfaces[surfaceId] = entry;
              isNewEngine = true;
            }
          } else if (backgroundChanged) {
            _resetCanvasWithLayers(entry.handle, layerCount, background);
            entry.backgroundColorArgb = background;
          }
        }

        return <String, Object?>{
          'textureId': null,
          'engineHandle': entry.handle,
          'width': entry.width,
          'height': entry.height,
          'isNewEngine': isNewEngine,
        };
      case 'disposeTexture':
        final Map<dynamic, dynamic>? args =
            call.arguments as Map<dynamic, dynamic>?;
        final String surfaceId = _readString(args, 'surfaceId', 'default');
        final _WebSurfaceEntry? entry = _surfaces.remove(surfaceId);
        if (entry != null) {
          _disposeEngine(entry.handle);
        }
        return null;
      default:
        throw PlatformException(
          code: 'unimplemented',
          message: 'Method ' + call.method.toString() + ' not implemented on web.',
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

  String _readString(Map<dynamic, dynamic>? args, String key, String fallback) {
    if (args == null) {
      return fallback;
    }
    final Object? value = args[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return fallback;
  }

  bool _hasWasmFunction(String name) {
    final Object? wasm = _wasmBindgen;
    if (wasm == null) {
      return false;
    }
    return js_util.hasProperty(wasm, name);
  }

  Object? get _wasmBindgen =>
      js_util.getProperty<Object?>(js_util.globalThis, 'wasm_bindgen');

  void _callVoid(String name, List<Object?> args) {
    final Object? wasm = _wasmBindgen;
    if (wasm == null) {
      return;
    }
    js_util.callMethod<Object?>(wasm, name, args);
  }

  bool _callBool(String name, List<Object?> args) {
    final Object? wasm = _wasmBindgen;
    if (wasm == null) {
      return false;
    }
    final Object? result = js_util.callMethod<Object?>(wasm, name, args);
    if (result is bool) {
      return result;
    }
    if (result is num) {
      return result != 0;
    }
    return false;
  }

  int _callInt(String name, List<Object?> args) {
    final Object? wasm = _wasmBindgen;
    if (wasm == null) {
      return 0;
    }
    final Object? result = js_util.callMethod<Object?>(wasm, name, args);
    if (result is num) {
      return result.toInt();
    }
    return 0;
  }

  int _createEngine(int width, int height) {
    return _callInt('canvas_engine_create', <Object?>[width, height]);
  }

  void _attachPresent(int handle, int width, int height) {
    _callVoid('canvas_engine_attach_present', <Object?>[
      handle.toDouble(),
      width,
      height,
    ]);
  }

  void _resetCanvasWithLayers(
    int handle,
    int layerCount,
    int backgroundColorArgb,
  ) {
    _callVoid('canvas_engine_reset_canvas_with_layers', <Object?>[
      handle.toDouble(),
      layerCount,
      backgroundColorArgb,
    ]);
  }

  bool _resizeCanvas(
    int handle,
    int width,
    int height,
    int layerCount,
    int backgroundColorArgb,
  ) {
    return _callBool('canvas_engine_resize_canvas', <Object?>[
      handle.toDouble(),
      width,
      height,
      layerCount,
      backgroundColorArgb,
    ]);
  }

  void _disposeEngine(int handle) {
    _callVoid('canvas_engine_dispose', <Object?>[handle.toDouble()]);
  }
}

class _WebSurfaceEntry {
  _WebSurfaceEntry({
    required this.handle,
    required this.width,
    required this.height,
    required this.layerCount,
    required this.backgroundColorArgb,
  });

  int handle;
  int width;
  int height;
  int layerCount;
  int backgroundColorArgb;
}
