import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../canvas/canvas_layer.dart';
import '../canvas/blend_mode_math.dart';

class BitmapCompositePayload {
  BitmapCompositePayload({
    required this.backgroundColor,
    required this.layers,
    required this.regionLeft,
    required this.regionTop,
    required this.regionWidth,
    required this.regionHeight,
  });

  final int backgroundColor;
  final List<BitmapCompositeLayerPayload> layers;
  final int regionLeft;
  final int regionTop;
  final int regionWidth;
  final int regionHeight;
}

class BitmapCompositeLayerPayload {
  BitmapCompositeLayerPayload({
    required this.pixelData,
    required this.opacity,
    required this.visible,
    required this.clippingMask,
    required this.blendModeIndex,
  });

  final TransferableTypedData pixelData;
  final double opacity;
  final bool visible;
  final bool clippingMask;
  final int blendModeIndex;
}

class BitmapCompositeResult {
  BitmapCompositeResult({
    required this.composite,
    required this.rgba,
    required this.regionLeft,
    required this.regionTop,
    required this.regionWidth,
    required this.regionHeight,
  });

  final Uint32List composite;
  final Uint8List rgba;
  final int regionLeft;
  final int regionTop;
  final int regionWidth;
  final int regionHeight;
}

class BitmapCompositor {
  Future<void> ensureInitialized() async {
    if (_sendPort != null) {
      return;
    }
    final ReceivePort port = ReceivePort();
    _mainSubscription = port.listen(_handleWorkerMessage);
    _worker = await Isolate.spawn(_compositorWorkerEntry, port.sendPort);
  }

  Future<BitmapCompositeResult> composite(BitmapCompositePayload payload) async {
    await ensureInitialized();
    await _awaitSendPort();
    final SendPort target = _sendPort!;
    _responsePort ??= ReceivePort();
    _responseSubscription ??=
        _responsePort!.listen(_handleResponseMessage);
    final Completer<BitmapCompositeResult> completer =
        Completer<BitmapCompositeResult>();
    final int requestId = _nextRequestId++;
    _pendingResponses[requestId] = completer;
    target.send(
      _WorkerCompositeRequest(
        payload,
        _responsePort!.sendPort,
        requestId,
      ),
    );
    return completer.future;
  }

  void _handleResponseMessage(dynamic message) {
    if (message is! _WorkerCompositeResponse) {
      return;
    }
    final Completer<BitmapCompositeResult>? completer =
        _pendingResponses.remove(message.requestId);
    if (completer == null) {
      return;
    }
    final ByteBuffer compositeData = message.composite.materialize();
    final ByteBuffer rgbaData = message.rgba.materialize();
    final Uint32List compositePixels = compositeData.asUint32List();
    final Uint8List rgbaPixels = rgbaData.asUint8List();
    completer.complete(
      BitmapCompositeResult(
        composite: compositePixels,
        rgba: rgbaPixels,
        regionLeft: message.regionLeft,
        regionTop: message.regionTop,
        regionWidth: message.regionWidth,
        regionHeight: message.regionHeight,
      ),
    );
  }

  void dispose() {
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _mainSubscription?.cancel();
    _mainSubscription = null;
    _responseSubscription?.cancel();
    _responseSubscription = null;
    _responsePort?.close();
    _responsePort = null;
    _pendingResponses.clear();
    _sendPort = null;
    _sendPortCompleter = null;
  }

  void _handleWorkerMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      _sendPortCompleter?.complete(message);
    }
  }

  Isolate? _worker;
  StreamSubscription<dynamic>? _mainSubscription;
  StreamSubscription<dynamic>? _responseSubscription;
  ReceivePort? _responsePort;
  final Map<int, Completer<BitmapCompositeResult>> _pendingResponses =
      <int, Completer<BitmapCompositeResult>>{};
  int _nextRequestId = 0;
  SendPort? _sendPort;
  Completer<SendPort>? _sendPortCompleter;

  Future<void> _awaitSendPort() {
    if (_sendPort != null) {
      return Future<void>.value();
    }
    _sendPortCompleter ??= Completer<SendPort>();
    return _sendPortCompleter!.future.then((_) {});
  }
}

class _WorkerCompositeRequest {
  const _WorkerCompositeRequest(this.payload, this.replyPort, this.requestId);

  final BitmapCompositePayload payload;
  final SendPort replyPort;
  final int requestId;
}

class _WorkerCompositeResponse {
  const _WorkerCompositeResponse({
    required this.composite,
    required this.rgba,
    required this.requestId,
    required this.regionLeft,
    required this.regionTop,
    required this.regionWidth,
    required this.regionHeight,
  });

  final TransferableTypedData composite;
  final TransferableTypedData rgba;
  final int requestId;
  final int regionLeft;
  final int regionTop;
  final int regionWidth;
  final int regionHeight;
}

void _compositorWorkerEntry(SendPort initialReplyTo) {
  final ReceivePort workerPort = ReceivePort();
  initialReplyTo.send(workerPort.sendPort);
  workerPort.listen((_handleMessage));
}

void _handleMessage(dynamic message) {
  if (message is! _WorkerCompositeRequest) {
    return;
  }
  final BitmapCompositePayload payload = message.payload;
  final BitmapCompositeResult result = _computeComposite(payload);
  final TransferableTypedData compositeData = TransferableTypedData.fromList(
    <Uint8List>[result.composite.buffer.asUint8List()],
  );
  final TransferableTypedData rgbaData =
      TransferableTypedData.fromList(<Uint8List>[result.rgba]);
  message.replyPort.send(
    _WorkerCompositeResponse(
      composite: compositeData,
      rgba: rgbaData,
      requestId: message.requestId,
      regionLeft: payload.regionLeft,
      regionTop: payload.regionTop,
      regionWidth: payload.regionWidth,
      regionHeight: payload.regionHeight,
    ),
  );
}

BitmapCompositeResult _computeComposite(BitmapCompositePayload payload) {
  final int width = payload.regionWidth;
  final int height = payload.regionHeight;
  final int length = width * height;
  final Uint32List composite = Uint32List(length);
  final Uint8List rgba = Uint8List(length * 4);
  final Uint8List clipMask = Uint8List(length);
  final List<_WorkerLayerData> layers = <_WorkerLayerData>[
    for (final BitmapCompositeLayerPayload layer in payload.layers)
      _WorkerLayerData(
        pixels: layer.pixelData.materialize().asUint32List(),
        opacity: layer.opacity,
        visible: layer.visible,
        clippingMask: layer.clippingMask,
        blendMode: CanvasLayerBlendMode.values[layer.blendModeIndex],
      ),
  ];

  for (int index = 0; index < length; index++) {
    int color = payload.backgroundColor;
    bool initialized = false;
    for (final _WorkerLayerData layer in layers) {
      if (!layer.visible) {
        continue;
      }
      final int src = layer.pixels[index];
      final int srcA = (src >> 24) & 0xff;
      if (srcA == 0) {
        if (!layer.clippingMask) {
          clipMask[index] = 0;
        }
        continue;
      }
      double totalOpacity = _clampUnit(layer.opacity);
      if (totalOpacity <= 0) {
        if (!layer.clippingMask) {
          clipMask[index] = 0;
        }
        continue;
      }
      if (layer.clippingMask) {
        final int maskAlpha = clipMask[index];
        if (maskAlpha == 0) {
          continue;
        }
        totalOpacity *= maskAlpha / 255.0;
        if (totalOpacity <= 0) {
          continue;
        }
      }
      int effectiveA = (srcA * totalOpacity).round();
      if (effectiveA <= 0) {
        if (!layer.clippingMask) {
          clipMask[index] = 0;
        }
        continue;
      }
      effectiveA = effectiveA.clamp(0, 255);
      if (!layer.clippingMask) {
        clipMask[index] = effectiveA;
      }
      final int effectiveColor =
          (effectiveA << 24) | (src & 0x00FFFFFF);
      if (!initialized) {
        color = effectiveColor;
        initialized = true;
      } else {
        color = CanvasBlendMath.blend(
          color,
          effectiveColor,
          layer.blendMode,
          pixelIndex: index,
        );
      }
    }

    composite[index] = color;
    final int rgbaOffset = index * 4;
    final int alpha = (color >> 24) & 0xff;
    if (alpha == 0) {
      rgba[rgbaOffset] = 0;
      rgba[rgbaOffset + 1] = 0;
      rgba[rgbaOffset + 2] = 0;
      rgba[rgbaOffset + 3] = 0;
    } else if (alpha == 255) {
      rgba[rgbaOffset] = (color >> 16) & 0xff;
      rgba[rgbaOffset + 1] = (color >> 8) & 0xff;
      rgba[rgbaOffset + 2] = color & 0xff;
      rgba[rgbaOffset + 3] = 255;
    } else {
      final int red = (color >> 16) & 0xff;
      final int green = (color >> 8) & 0xff;
      final int blue = color & 0xff;
      rgba[rgbaOffset] = _unPremultiply(red, alpha);
      rgba[rgbaOffset + 1] = _unPremultiply(green, alpha);
      rgba[rgbaOffset + 2] = _unPremultiply(blue, alpha);
      rgba[rgbaOffset + 3] = alpha;
    }
  }

  return BitmapCompositeResult(
    composite: composite,
    rgba: rgba,
    regionLeft: payload.regionLeft,
    regionTop: payload.regionTop,
    regionWidth: payload.regionWidth,
    regionHeight: payload.regionHeight,
  );
}

int _unPremultiply(int channel, int alpha) {
  if (alpha <= 0) {
    return 0;
  }
  if (alpha >= 255) {
    return _clampToByte(channel);
  }
  final double value = (channel * 255) / alpha;
  return _clampToByte(value.round());
}

double _clampUnit(double value) {
  if (value <= 0) {
    return 0;
  }
  if (value >= 1) {
    return 1;
  }
  return value;
}

int _clampToByte(int value) {
  if (value <= 0) {
    return 0;
  }
  if (value >= 255) {
    return 255;
  }
  return value;
}

class _WorkerLayerData {
  _WorkerLayerData({
    required this.pixels,
    required this.opacity,
    required this.visible,
    required this.clippingMask,
    required this.blendMode,
  });

  final Uint32List pixels;
  final double opacity;
  final bool visible;
  final bool clippingMask;
  final CanvasLayerBlendMode blendMode;
}
