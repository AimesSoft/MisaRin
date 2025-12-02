import 'dart:isolate';
import 'dart:async';
import 'dart:typed_data';

import '../src/rust/api/blend_utils.dart' as rust_blend;
import '../bitmap_canvas/raster_int_rect.dart';
import '../canvas/canvas_layer.dart';

class CompositeRegionLayerRef {
  const CompositeRegionLayerRef({
    required this.id,
    required this.visible,
    required this.opacity,
    required this.clippingMask,
    required this.blendModeIndex,
  });

  final String id;
  final bool visible;
  final double opacity;
  final bool clippingMask;
  final int blendModeIndex;

  CanvasLayerBlendMode get blendMode =>
      CanvasLayerBlendMode.values[blendModeIndex];
}

class CompositeRegionPayload {
  const CompositeRegionPayload({required this.rect, required this.layers});

  final RasterIntRect rect;
  final List<CompositeRegionLayerRef> layers;
}

class CompositeWorkPayload {
  const CompositeWorkPayload({
    required this.width,
    required this.height,
    required this.regions,
    required this.requiresFullSurface,
    this.translatingLayerId,
  });

  final int width;
  final int height;
  final List<CompositeRegionPayload> regions;
  final bool requiresFullSurface;
  final String? translatingLayerId;
}

class CompositeRegionResult {
  const CompositeRegionResult({required this.rect, required this.pixels});

  final RasterIntRect rect;
  final Uint32List pixels;
}

class CanvasCompositeWorker {
  CanvasCompositeWorker()
    : _receivePort = ReceivePort(),
      _sendPortCompleter = Completer<SendPort>() {
    _subscription = _receivePort.listen(_handleMessage);
  }

  final ReceivePort _receivePort;
  final Completer<SendPort> _sendPortCompleter;
  late final StreamSubscription<Object?> _subscription;
  final Map<int, Completer<List<CompositeRegionResult>>> _pending =
      <int, Completer<List<CompositeRegionResult>>>{};
  Isolate? _isolate;
  SendPort? _sendPort;
  int _nextRequestId = 0;

  Future<void> _ensureStarted() async {
    if (_isolate != null) {
      return;
    }
    _isolate = await Isolate.spawn<SendPort>(
      _compositeWorkerMain,
      _receivePort.sendPort,
      debugName: 'CanvasCompositeWorker',
    );
    _sendPort = await _sendPortCompleter.future;
  }

  Future<void> updateLayer({
    required String id,
    required int width,
    required int height,
    Uint32List? pixels,
    RasterIntRect? rect,
  }) async {
    await _ensureStarted();
    final SendPort port = _sendPort!;
    final TransferableTypedData? buffer = pixels != null
        ? TransferableTypedData.fromList(<Uint8List>[
            Uint8List.view(pixels.buffer),
          ])
        : null;
    port.send(
      _CompositeWorkerRequest(
        id: -1, // No response needed for updates
        type: _CompositeWorkerRequestType.updateLayer,
        payload: <String, Object?>{
          'id': id,
          'width': width,
          'height': height,
          'pixels': buffer,
          'rect': rect,
        },
      ),
    );
  }

  Future<List<CompositeRegionResult>> composite(
    CompositeWorkPayload payload,
  ) async {
    await _ensureStarted();
    final SendPort port = _sendPort!;
    final Completer<List<CompositeRegionResult>> completer =
        Completer<List<CompositeRegionResult>>();
    final int requestId = _nextRequestId++;
    _pending[requestId] = completer;
    port.send(
      _CompositeWorkerRequest(
        id: requestId,
        type: _CompositeWorkerRequestType.composite,
        payload: payload,
      ),
    );
    return completer.future;
  }

  Future<void> dispose() async {
    if (_isolate != null) {
      _sendPort?.send(null);
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
    }
    await _subscription.cancel();
    _receivePort.close();
    for (final Completer<List<CompositeRegionResult>> completer
        in _pending.values) {
      completer.completeError(StateError('Composite worker disposed'));
    }
    _pending.clear();
  }

  void _handleMessage(Object? message) {
    if (message is SendPort) {
      if (!_sendPortCompleter.isCompleted) {
        _sendPortCompleter.complete(message);
      }
      return;
    }
    if (message is _CompositeWorkerResponse) {
      final Completer<List<CompositeRegionResult>>? completer = _pending.remove(
        message.id,
      );
      completer?.complete(message.regions);
      return;
    }
    if (message is _CompositeWorkerError) {
      final Completer<List<CompositeRegionResult>>? completer = _pending.remove(
        message.id,
      );
      completer?.completeError(
        Exception('Composite failed: ${message.error}\n${message.stackTrace}'),
      );
    }
  }
}

enum _CompositeWorkerRequestType { updateLayer, composite }

class _CompositeWorkerState {
  final Map<String, Uint32List> layers = <String, Uint32List>{};
  final Map<String, _LayerDimensions> layerDimensions =
      <String, _LayerDimensions>{};
}

class _LayerDimensions {
  const _LayerDimensions(this.width, this.height);
  final int width;
  final int height;
}

@pragma('vm:entry-point')
void _compositeWorkerMain(SendPort replyPort) {
  final ReceivePort commandPort = ReceivePort();
  replyPort.send(commandPort.sendPort);
  final _CompositeWorkerState state = _CompositeWorkerState();

  commandPort.listen((Object? message) {
    if (message is _CompositeWorkerRequest) {
      try {
        if (message.type == _CompositeWorkerRequestType.updateLayer) {
          _handleUpdateLayer(state, message.payload as Map<String, Object?>);
        } else if (message.type == _CompositeWorkerRequestType.composite) {
          final List<CompositeRegionResult> regions = _runCompositeWork(
            state,
            message.payload as CompositeWorkPayload,
          );
          replyPort.send(_CompositeWorkerResponse(message.id, regions));
        }
      } catch (error, stackTrace) {
        if (message.id >= 0) {
          replyPort.send(
            _CompositeWorkerError(
              message.id,
              error.toString(),
              stackTrace.toString(),
            ),
          );
        }
      }
      return;
    }
    if (message == null) {
      commandPort.close();
    }
  });
}

void _handleUpdateLayer(
  _CompositeWorkerState state,
  Map<String, Object?> payload,
) {
  final String id = payload['id'] as String;
  final int width = payload['width'] as int;
  final int height = payload['height'] as int;
  final TransferableTypedData? pixelsData =
      payload['pixels'] as TransferableTypedData?;
  final RasterIntRect? rect = payload['rect'] as RasterIntRect?;

  if (pixelsData == null) {
    if (rect == null) {
      // Full initialization with empty buffer
      state.layers[id] = Uint32List(width * height);
      state.layerDimensions[id] = _LayerDimensions(width, height);
    }
    return;
  }

  final ByteBuffer buffer = pixelsData.materialize();
  final Uint32List incomingPixels = Uint32List.view(
    buffer,
    0,
    buffer.lengthInBytes ~/ Uint32List.bytesPerElement,
  );

  if (rect != null) {
    // Update partial region
    final Uint32List? existing = state.layers[id];
    if (existing == null) {
      return; // Layer not initialized, cannot update patch
    }
    final int regionWidth = rect.width;
    final int regionHeight = rect.height;
    for (int row = 0; row < regionHeight; row++) {
      final int dstOffset = (rect.top + row) * width + rect.left;
      final int srcOffset = row * regionWidth;
      existing.setRange(
        dstOffset,
        dstOffset + regionWidth,
        incomingPixels,
        srcOffset,
      );
    }
  } else {
    // Full update
    state.layers[id] = incomingPixels;
    state.layerDimensions[id] = _LayerDimensions(width, height);
  }
}

class _CompositeWorkerRequest {
  const _CompositeWorkerRequest({
    required this.id,
    required this.type,
    required this.payload,
  });

  final int id;
  final _CompositeWorkerRequestType type;
  final Object payload;
}

class _CompositeWorkerResponse {
  const _CompositeWorkerResponse(this.id, this.regions);

  final int id;
  final List<CompositeRegionResult> regions;
}

class _CompositeWorkerError {
  const _CompositeWorkerError(this.id, this.error, this.stackTrace);

  final int id;
  final String error;
  final String stackTrace;
}

List<CompositeRegionResult> _runCompositeWork(
  _CompositeWorkerState state,
  CompositeWorkPayload payload,
) {
  if (payload.regions.isEmpty) {
    return const <CompositeRegionResult>[];
  }
  final int surfaceWidth = payload.width;
  final List<CompositeRegionResult> results = <CompositeRegionResult>[];

  for (final CompositeRegionPayload region in payload.regions) {
    final RasterIntRect area = region.rect;
    final int areaWidth = area.width;
    final int areaHeight = area.height;
    if (areaWidth <= 0 || areaHeight <= 0) {
      continue;
    }

    // Collect layer data for this region
    final List<Uint32List> layersPixels = [];
    final List<double> layersOpacity = [];
    final List<rust_blend.BlendMode> layersBlendMode = [];

    for (final CompositeRegionLayerRef layer in region.layers) {
      if (!layer.visible) {
        continue;
      }
      if (payload.translatingLayerId != null &&
          layer.id == payload.translatingLayerId) {
        continue;
      }

      final Uint32List? layerBuffer = state.layers[layer.id];
      if (layerBuffer == null) {
        continue;
      }

      final double opacity = _clampUnit(layer.opacity);
      if (opacity <= 0) {
        continue;
      }

      // Extract pixels for the region
      // TODO: Optimization - If we could pass the full buffer + stride/offset to Rust,
      // we'd save this copy. But for now, this is the safest "drop-in" replacement.
      final Uint32List regionPixels = Uint32List(areaWidth * areaHeight);
      for (int row = 0; row < areaHeight; row++) {
        final int srcRowStart = (area.top + row) * surfaceWidth + area.left;
        final int dstRowStart = row * areaWidth;
        // Bulk copy the row
        regionPixels.setRange(
          dstRowStart,
          dstRowStart + areaWidth,
          layerBuffer,
          srcRowStart,
        );
      }

      layersPixels.add(regionPixels);
      layersOpacity.add(opacity);

      // Map Dart BlendMode enum to Rust BlendMode enum
      layersBlendMode.add(_mapBlendMode(layer.blendMode));
    }

    if (layersPixels.isEmpty) {
      // Empty region
      results.add(
        CompositeRegionResult(
          rect: area,
          pixels: Uint32List(areaWidth * areaHeight),
        ),
      );
      continue;
    }

    // Call Rust to blend
    final Uint32List composite = rust_blend.compositeRegion(
      width: areaWidth,
      height: areaHeight,
      layersPixels: layersPixels,
      layersOpacity: layersOpacity,
      layersBlendMode: layersBlendMode,
    );

    results.add(CompositeRegionResult(rect: area, pixels: composite));
  }
  return results;
}

rust_blend.BlendMode _mapBlendMode(CanvasLayerBlendMode mode) {
  switch (mode) {
    case CanvasLayerBlendMode.normal:
      return rust_blend.BlendMode.normal;
    case CanvasLayerBlendMode.multiply:
      return rust_blend.BlendMode.multiply;
    case CanvasLayerBlendMode.dissolve:
      return rust_blend.BlendMode.dissolve;
    case CanvasLayerBlendMode.darken:
      return rust_blend.BlendMode.darken;
    case CanvasLayerBlendMode.colorBurn:
      return rust_blend.BlendMode.colorBurn;
    case CanvasLayerBlendMode.linearBurn:
      return rust_blend.BlendMode.linearBurn;
    case CanvasLayerBlendMode.darkerColor:
      return rust_blend.BlendMode.darkerColor;
    case CanvasLayerBlendMode.lighten:
      return rust_blend.BlendMode.lighten;
    case CanvasLayerBlendMode.screen:
      return rust_blend.BlendMode.screen;
    case CanvasLayerBlendMode.colorDodge:
      return rust_blend.BlendMode.colorDodge;
    case CanvasLayerBlendMode.linearDodge:
      return rust_blend.BlendMode.linearDodge;
    case CanvasLayerBlendMode.lighterColor:
      return rust_blend.BlendMode.lighterColor;
    case CanvasLayerBlendMode.overlay:
      return rust_blend.BlendMode.overlay;
    case CanvasLayerBlendMode.softLight:
      return rust_blend.BlendMode.softLight;
    case CanvasLayerBlendMode.hardLight:
      return rust_blend.BlendMode.hardLight;
    case CanvasLayerBlendMode.vividLight:
      return rust_blend.BlendMode.vividLight;
    case CanvasLayerBlendMode.linearLight:
      return rust_blend.BlendMode.linearLight;
    case CanvasLayerBlendMode.pinLight:
      return rust_blend.BlendMode.pinLight;
    case CanvasLayerBlendMode.hardMix:
      return rust_blend.BlendMode.hardMix;
    case CanvasLayerBlendMode.difference:
      return rust_blend.BlendMode.difference;
    case CanvasLayerBlendMode.exclusion:
      return rust_blend.BlendMode.exclusion;
    case CanvasLayerBlendMode.subtract:
      return rust_blend.BlendMode.subtract;
    case CanvasLayerBlendMode.divide:
      return rust_blend.BlendMode.divide;
    case CanvasLayerBlendMode.hue:
      return rust_blend.BlendMode.hue;
    case CanvasLayerBlendMode.saturation:
      return rust_blend.BlendMode.saturation;
    case CanvasLayerBlendMode.color:
      return rust_blend.BlendMode.color;
    case CanvasLayerBlendMode.luminosity:
      return rust_blend.BlendMode.luminosity;
  }
}

double _clampUnit(double value) {
  if (value.isNaN) {
    return 0.0;
  }
  if (value < 0) {
    return 0.0;
  }
  if (value > 1) {
    return 1.0;
  }
  return value;
}
