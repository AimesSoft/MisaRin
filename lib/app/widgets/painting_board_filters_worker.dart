part of 'painting_board.dart';

const int _kFilterTypeHueSaturation = 0;
const int _kFilterTypeBrightnessContrast = 1;
const int _kFilterTypeBlackWhite = 2;
const int _kFilterTypeGaussianBlur = 3;
const int _kFilterTypeLeakRemoval = 4;
const int _kFilterTypeLineNarrow = 5;
const int _kFilterTypeFillExpand = 6;
const int _kFilterTypeBinarize = 7;
const int _kFilterTypeScanPaperDrawing = 8;
const int _kFilterTypeInvert = 9;

Uint8List? _tryApplyRustCpuFilter({
  required int filterType,
  required Uint8List bitmap,
  required int width,
  required int height,
  double param0 = 0,
  double param1 = 0,
  double param2 = 0,
  double param3 = 0,
}) {
  final RustCpuFiltersFfi rust = RustCpuFiltersFfi.instance;
  if (!rust.supportsRgbaFilters) {
    return null;
  }
  return rust.applyFilterRgbaBytes(
    pixels: bitmap,
    width: width,
    height: height,
    filterType: filterType,
    param0: param0,
    param1: param1,
    param2: param2,
    param3: param3,
  );
}

class _FilterPreviewWorker {
  _FilterPreviewWorker({
    required _FilterPanelType type,
    required String layerId,
    required CanvasLayerData baseLayer,
    required int canvasWidth,
    required int canvasHeight,
    required ValueChanged<_FilterPreviewResult> onResult,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) : _type = type,
       _layerId = layerId,
       _canvasWidth = canvasWidth,
       _canvasHeight = canvasHeight,
       _onResult = onResult,
       _onError = onError {
    _start(baseLayer);
  }

  final _FilterPanelType _type;
  final String _layerId;
  final int _canvasWidth;
  final int _canvasHeight;
  final ValueChanged<_FilterPreviewResult> _onResult;
  final void Function(Object error, StackTrace stackTrace) _onError;

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  StreamSubscription<dynamic>? _subscription;
  final Completer<void> _readyCompleter = Completer<void>();
  bool _useMainThreadPreview = false;
  Uint8List? _baseBitmapSnapshot;
  int? _baseFillColorValue;
  int _baseBitmapWidth = 0;
  int _baseBitmapHeight = 0;
  bool _disposed = false;

  Future<void> _start(CanvasLayerData layer) async {
    final TransferableTypedData? bitmapData = layer.bitmap != null
        ? TransferableTypedData.fromList(<Uint8List>[layer.bitmap!])
        : null;
    int filterType;
    switch (_type) {
      case _FilterPanelType.hueSaturation:
        filterType = _kFilterTypeHueSaturation;
        break;
      case _FilterPanelType.brightnessContrast:
        filterType = _kFilterTypeBrightnessContrast;
        break;
      case _FilterPanelType.blackWhite:
        filterType = _kFilterTypeBlackWhite;
        break;
      case _FilterPanelType.scanPaperDrawing:
        filterType = _kFilterTypeScanPaperDrawing;
        break;
      case _FilterPanelType.binarize:
        filterType = _kFilterTypeBinarize;
        break;
      case _FilterPanelType.gaussianBlur:
        filterType = _kFilterTypeGaussianBlur;
        break;
      case _FilterPanelType.leakRemoval:
        filterType = _kFilterTypeLeakRemoval;
        break;
      case _FilterPanelType.lineNarrow:
        filterType = _kFilterTypeLineNarrow;
        break;
      case _FilterPanelType.fillExpand:
        filterType = _kFilterTypeFillExpand;
        break;
    }
    final Map<String, Object?> initData = <String, Object?>{
      'type': filterType,
      'layerId': _layerId,
      'layer': <String, Object?>{
        'bitmap': bitmapData,
        'bitmapWidth': layer.bitmapWidth,
        'bitmapHeight': layer.bitmapHeight,
        'bitmapLeft': layer.bitmapLeft,
        'bitmapTop': layer.bitmapTop,
        'fillColor': layer.fillColor?.value,
        'canvasWidth': _canvasWidth,
        'canvasHeight': _canvasHeight,
      },
    };
    final ReceivePort port = ReceivePort();
    _receivePort = port;
    _subscription = port.listen(
      (dynamic message) {
        if (message is SendPort) {
          _sendPort = message;
          if (!_readyCompleter.isCompleted) {
            _readyCompleter.complete();
          }
          return;
        }
        if (message is Map<String, Object?>) {
          final _FilterPreviewResult result = _FilterPreviewResult(
            token: message['token'] as int? ?? -1,
            layerId: message['layerId'] as String? ?? _layerId,
            bitmapData: message['bitmap'] as TransferableTypedData?,
            fillColor: message['fillColor'] as int?,
          );
          if (!_disposed) {
            _onResult(result);
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.completeError(error, stackTrace);
        }
        _onError(error, stackTrace);
      },
    );
    try {
      _isolate = await Isolate.spawn<List<Object?>>(
        _filterPreviewWorkerMain,
        <Object?>[port.sendPort, initData],
        debugName: 'FilterPreviewWorker',
        errorsAreFatal: false,
      );
    } on Object catch (error, stackTrace) {
      await _subscription?.cancel();
      _subscription = null;
      _receivePort = null;
      port.close();
      _isolate = null;
      debugPrint('Filter preview worker isolate unavailable: $error');
      _initializeSynchronousLayer(layer);
    }
  }

  void _initializeSynchronousLayer(CanvasLayerData layer) {
    _useMainThreadPreview = true;
    _baseBitmapSnapshot = layer.bitmap != null
        ? Uint8List.fromList(layer.bitmap!)
        : null;
    _baseFillColorValue = layer.fillColor?.value;
    _baseBitmapWidth = layer.bitmapWidth ?? _canvasWidth;
    _baseBitmapHeight = layer.bitmapHeight ?? _canvasHeight;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
  }

  Future<void> requestPreview({
    required int token,
    required _HueSaturationSettings hueSaturation,
    required _BrightnessContrastSettings brightnessContrast,
    required _BlackWhiteSettings blackWhite,
    required double blurRadius,
    required double leakRadius,
    required double morphRadius,
    required double binarizeThreshold,
  }) async {
    if (_disposed) {
      return;
    }
    try {
      await _readyCompleter.future;
    } catch (_) {
      return;
    }
    if (_useMainThreadPreview) {
      _runPreviewSynchronously(
        token: token,
        hueSaturation: hueSaturation,
        brightnessContrast: brightnessContrast,
        blackWhite: blackWhite,
        blurRadius: blurRadius,
        leakRadius: leakRadius,
        morphRadius: morphRadius,
        binarizeThreshold: binarizeThreshold,
      );
      return;
    }
    final SendPort? port = _sendPort;
    if (port == null) {
      return;
    }
    port.send(<String, Object?>{
      'kind': 'preview',
      'token': token,
      'hue': <double>[
        hueSaturation.hue,
        hueSaturation.saturation,
        hueSaturation.lightness,
      ],
      'brightness': <double>[
        brightnessContrast.brightness,
        brightnessContrast.contrast,
      ],
      'blackWhite': <double>[
        blackWhite.blackPoint,
        blackWhite.whitePoint,
        blackWhite.midTone,
      ],
      'blur': blurRadius,
      'leakRadius': leakRadius,
      'morph': morphRadius,
      'binarize': binarizeThreshold,
    });
  }

  void _runPreviewSynchronously({
    required int token,
    required _HueSaturationSettings hueSaturation,
    required _BrightnessContrastSettings brightnessContrast,
    required _BlackWhiteSettings blackWhite,
    required double blurRadius,
    required double leakRadius,
    required double morphRadius,
    required double binarizeThreshold,
  }) {
    Uint8List? bitmap;
    final Uint8List? source = _baseBitmapSnapshot;
    if (source != null) {
      bitmap = Uint8List.fromList(source);
      final int leakSteps = leakRadius.round().clamp(
        0,
        _kLeakRemovalMaxRadius.toInt(),
      );
      final int filterType = switch (_type) {
        _FilterPanelType.hueSaturation => _kFilterTypeHueSaturation,
        _FilterPanelType.brightnessContrast => _kFilterTypeBrightnessContrast,
        _FilterPanelType.blackWhite => _kFilterTypeBlackWhite,
        _FilterPanelType.binarize => _kFilterTypeBinarize,
        _FilterPanelType.gaussianBlur => _kFilterTypeGaussianBlur,
        _FilterPanelType.leakRemoval => _kFilterTypeLeakRemoval,
        _FilterPanelType.lineNarrow => _kFilterTypeLineNarrow,
        _FilterPanelType.fillExpand => _kFilterTypeFillExpand,
        _FilterPanelType.scanPaperDrawing => _kFilterTypeScanPaperDrawing,
      };
      final Uint8List? rustProcessed = _tryApplyRustCpuFilter(
        filterType: filterType,
        bitmap: bitmap,
        width: _baseBitmapWidth,
        height: _baseBitmapHeight,
        param0: switch (_type) {
          _FilterPanelType.hueSaturation => hueSaturation.hue,
          _FilterPanelType.brightnessContrast => brightnessContrast.brightness,
          _FilterPanelType.blackWhite => blackWhite.blackPoint,
          _FilterPanelType.binarize => binarizeThreshold,
          _FilterPanelType.gaussianBlur => blurRadius,
          _FilterPanelType.leakRemoval => leakSteps.toDouble(),
          _FilterPanelType.lineNarrow => morphRadius,
          _FilterPanelType.fillExpand => morphRadius,
          _FilterPanelType.scanPaperDrawing => blackWhite.blackPoint,
        },
        param1: switch (_type) {
          _FilterPanelType.hueSaturation => hueSaturation.saturation,
          _FilterPanelType.brightnessContrast => brightnessContrast.contrast,
          _FilterPanelType.blackWhite => blackWhite.whitePoint,
          _FilterPanelType.binarize => 0.0,
          _FilterPanelType.gaussianBlur => 0.0,
          _FilterPanelType.leakRemoval => 0.0,
          _FilterPanelType.lineNarrow => 0.0,
          _FilterPanelType.fillExpand => 0.0,
          _FilterPanelType.scanPaperDrawing => blackWhite.whitePoint,
        },
        param2: switch (_type) {
          _FilterPanelType.hueSaturation => hueSaturation.lightness,
          _FilterPanelType.brightnessContrast => 0.0,
          _FilterPanelType.blackWhite => blackWhite.midTone,
          _FilterPanelType.binarize => 0.0,
          _FilterPanelType.gaussianBlur => 0.0,
          _FilterPanelType.leakRemoval => 0.0,
          _FilterPanelType.lineNarrow => 0.0,
          _FilterPanelType.fillExpand => 0.0,
          _FilterPanelType.scanPaperDrawing => blackWhite.midTone,
        },
      );
      if (rustProcessed != null) {
        bitmap = rustProcessed;
      } else if (_type == _FilterPanelType.hueSaturation) {
        _filterApplyHueSaturationToBitmap(
          bitmap,
          hueSaturation.hue,
          hueSaturation.saturation,
          hueSaturation.lightness,
        );
      } else if (_type == _FilterPanelType.brightnessContrast) {
        _filterApplyBrightnessContrastToBitmap(
          bitmap,
          brightnessContrast.brightness,
          brightnessContrast.contrast,
        );
      } else if (_type == _FilterPanelType.blackWhite) {
        _filterApplyBlackWhiteToBitmap(
          bitmap,
          blackWhite.blackPoint,
          blackWhite.whitePoint,
          blackWhite.midTone,
        );
      } else if (_type == _FilterPanelType.binarize) {
        _filterApplyBinarizeToBitmap(
          bitmap,
          binarizeThreshold.round().clamp(0, 255),
        );
      } else if (_type == _FilterPanelType.gaussianBlur &&
          blurRadius > 0 &&
          _baseBitmapWidth > 0 &&
          _baseBitmapHeight > 0) {
        _filterApplyGaussianBlurToBitmap(
          bitmap,
          _baseBitmapWidth,
          _baseBitmapHeight,
          blurRadius,
        );
      } else if (_type == _FilterPanelType.leakRemoval &&
          leakSteps > 0 &&
          _baseBitmapWidth > 0 &&
          _baseBitmapHeight > 0) {
        _filterApplyLeakRemovalToBitmap(
          bitmap,
          _baseBitmapWidth,
          _baseBitmapHeight,
          leakSteps,
        );
      } else if (_type == _FilterPanelType.lineNarrow &&
          morphRadius > 0 &&
          _baseBitmapWidth > 0 &&
          _baseBitmapHeight > 0) {
        final int morphSteps = morphRadius
            .round()
            .clamp(1, _kMorphologyMaxRadius.toInt())
            .toInt();
        _filterApplyMorphologyToBitmap(
          bitmap,
          _baseBitmapWidth,
          _baseBitmapHeight,
          morphSteps,
          dilate: false,
        );
      } else if (_type == _FilterPanelType.fillExpand &&
          morphRadius > 0 &&
          _baseBitmapWidth > 0 &&
          _baseBitmapHeight > 0) {
        final int morphSteps = morphRadius
            .round()
            .clamp(1, _kMorphologyMaxRadius.toInt())
            .toInt();
        _filterApplyMorphologyToBitmap(
          bitmap,
          _baseBitmapWidth,
          _baseBitmapHeight,
          morphSteps,
          dilate: true,
        );
      }
      if (bitmap != null && !_filterBitmapHasVisiblePixels(bitmap)) {
        bitmap = null;
      }
    }
    int? adjustedFill = _baseFillColorValue;
    if (adjustedFill != null) {
      final Color baseColor = Color(adjustedFill);
      Color output = baseColor;
      if (_type == _FilterPanelType.hueSaturation) {
        output = _filterApplyHueSaturationToColor(
          baseColor,
          hueSaturation.hue,
          hueSaturation.saturation,
          hueSaturation.lightness,
        );
      } else if (_type == _FilterPanelType.brightnessContrast) {
        output = _filterApplyBrightnessContrastToColor(
          baseColor,
          brightnessContrast.brightness,
          brightnessContrast.contrast,
        );
      } else if (_type == _FilterPanelType.blackWhite) {
        output = _filterApplyBlackWhiteToColor(
          baseColor,
          blackWhite.blackPoint,
          blackWhite.whitePoint,
          blackWhite.midTone,
        );
      } else if (_type == _FilterPanelType.binarize) {
        output = _filterApplyBinarizeToColor(
          baseColor,
          binarizeThreshold.round().clamp(0, 255),
        );
      }
      adjustedFill = output.value;
    }
    final _FilterPreviewResult result = _FilterPreviewResult(
      token: token,
      layerId: _layerId,
      bitmapBytes: bitmap,
      fillColor: adjustedFill,
    );
    if (_disposed) {
      return;
    }
    scheduleMicrotask(() {
      if (!_disposed) {
        _onResult(result);
      }
    });
  }

  void discardPendingResult() {}

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final SendPort? port = _sendPort;
    port?.send(const <String, Object?>{'kind': 'dispose'});
    _subscription?.cancel();
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _sendPort = null;
    _baseBitmapSnapshot = null;
    _baseFillColorValue = null;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
  }
}

class _FilterPreviewResult {
  _FilterPreviewResult({
    required this.token,
    required this.layerId,
    TransferableTypedData? bitmapData,
    Uint8List? bitmapBytes,
    this.fillColor,
  }) : _bitmapData = bitmapData,
       _bytes = bitmapBytes;

  final int token;
  final String layerId;
  final int? fillColor;
  TransferableTypedData? _bitmapData;
  Uint8List? _bytes;

  Uint8List? get bitmapBytes {
    if (_bytes != null) {
      return _bytes;
    }
    final TransferableTypedData? data = _bitmapData;
    if (data == null) {
      return null;
    }
    _bitmapData = null;
    _bytes = data.materialize().asUint8List();
    return _bytes;
  }
}

@pragma('vm:entry-point')
void _filterPreviewWorkerMain(List<Object?> initialMessage) {
  final SendPort parent = initialMessage[0] as SendPort;
  final Map<String, Object?> initData =
      (initialMessage[1] as Map<String, Object?>?) ?? const <String, Object?>{};
  final int type = initData['type'] as int? ?? _kFilterTypeHueSaturation;
  final String layerId = initData['layerId'] as String? ?? '';
  final Map<String, Object?> layer =
      (initData['layer'] as Map<String, Object?>?) ?? const <String, Object?>{};
  final TransferableTypedData? bitmapData =
      layer['bitmap'] as TransferableTypedData?;
  final Uint8List? baseBitmap = bitmapData != null
      ? bitmapData.materialize().asUint8List()
      : null;
  final int? fillColorValue = layer['fillColor'] as int?;
  final int canvasWidth = layer['canvasWidth'] as int? ?? 0;
  final int canvasHeight = layer['canvasHeight'] as int? ?? 0;
  final int bitmapWidth = layer['bitmapWidth'] as int? ?? canvasWidth;
  final int bitmapHeight = layer['bitmapHeight'] as int? ?? canvasHeight;
  final ReceivePort port = ReceivePort();
  parent.send(port.sendPort);
  port.listen((dynamic message) {
    if (message is! Map<String, Object?>) {
      return;
    }
    final String kind = message['kind'] as String? ?? '';
    if (kind == 'dispose') {
      port.close();
      return;
    }
    if (kind != 'preview') {
      return;
    }
    final int token = message['token'] as int? ?? -1;
    final List<dynamic>? rawHue = message['hue'] as List<dynamic>?;
    final List<dynamic>? rawBrightness =
        message['brightness'] as List<dynamic>?;
    final List<dynamic>? rawBlackWhite =
        message['blackWhite'] as List<dynamic>?;
    final double hueDelta = _filterReadListValue(rawHue, 0);
    final double saturationPercent = _filterReadListValue(rawHue, 1);
    final double lightnessPercent = _filterReadListValue(rawHue, 2);
    final double brightnessPercent = _filterReadListValue(rawBrightness, 0);
    final double contrastPercent = _filterReadListValue(rawBrightness, 1);
    final double blackPoint = _filterReadListValue(rawBlackWhite, 0);
    final double whitePoint = _filterReadListValue(rawBlackWhite, 1);
    final double midTone = _filterReadListValue(rawBlackWhite, 2);
    final double blurRadius = (message['blur'] is num)
        ? (message['blur'] as num).toDouble()
        : 0.0;
    final double leakRadius = (message['leakRadius'] is num)
        ? (message['leakRadius'] as num).toDouble()
        : 0.0;
    final double morphRadius = (message['morph'] is num)
        ? (message['morph'] as num).toDouble()
        : 0.0;
    final double binarizeThreshold = (message['binarize'] is num)
        ? (message['binarize'] as num).toDouble()
        : _kDefaultBinarizeAlphaThreshold;

    Uint8List? bitmap;
    if (baseBitmap != null) {
      bitmap = Uint8List.fromList(baseBitmap);
      final int leakSteps = leakRadius.round().clamp(
        0,
        _kLeakRemovalMaxRadius.toInt(),
      );
      final Uint8List? rustProcessed = _tryApplyRustCpuFilter(
        filterType: type,
        bitmap: bitmap,
        width: bitmapWidth,
        height: bitmapHeight,
        param0: switch (type) {
          _kFilterTypeHueSaturation => hueDelta,
          _kFilterTypeBrightnessContrast => brightnessPercent,
          _kFilterTypeBlackWhite => blackPoint,
          _kFilterTypeBinarize => binarizeThreshold,
          _kFilterTypeGaussianBlur => blurRadius,
          _kFilterTypeLeakRemoval => leakSteps.toDouble(),
          _kFilterTypeLineNarrow => morphRadius,
          _kFilterTypeFillExpand => morphRadius,
          _kFilterTypeScanPaperDrawing => blackPoint,
          _kFilterTypeInvert => 0.0,
          _ => 0.0,
        },
        param1: switch (type) {
          _kFilterTypeHueSaturation => saturationPercent,
          _kFilterTypeBrightnessContrast => contrastPercent,
          _kFilterTypeBlackWhite => whitePoint,
          _kFilterTypeBinarize => 0.0,
          _kFilterTypeGaussianBlur => 0.0,
          _kFilterTypeLeakRemoval => 0.0,
          _kFilterTypeLineNarrow => 0.0,
          _kFilterTypeFillExpand => 0.0,
          _kFilterTypeScanPaperDrawing => whitePoint,
          _kFilterTypeInvert => 0.0,
          _ => 0.0,
        },
        param2: switch (type) {
          _kFilterTypeHueSaturation => lightnessPercent,
          _kFilterTypeBrightnessContrast => 0.0,
          _kFilterTypeBlackWhite => midTone,
          _kFilterTypeBinarize => 0.0,
          _kFilterTypeGaussianBlur => 0.0,
          _kFilterTypeLeakRemoval => 0.0,
          _kFilterTypeLineNarrow => 0.0,
          _kFilterTypeFillExpand => 0.0,
          _kFilterTypeScanPaperDrawing => midTone,
          _kFilterTypeInvert => 0.0,
          _ => 0.0,
        },
      );
      if (rustProcessed != null) {
        bitmap = rustProcessed;
      } else if (type == _kFilterTypeHueSaturation) {
        _filterApplyHueSaturationToBitmap(
          bitmap,
          hueDelta,
          saturationPercent,
          lightnessPercent,
        );
      } else if (type == _kFilterTypeBrightnessContrast) {
        _filterApplyBrightnessContrastToBitmap(
          bitmap,
          brightnessPercent,
          contrastPercent,
        );
      } else if (type == _kFilterTypeBlackWhite) {
        _filterApplyBlackWhiteToBitmap(bitmap, blackPoint, whitePoint, midTone);
      } else if (type == _kFilterTypeBinarize) {
        _filterApplyBinarizeToBitmap(
          bitmap,
          binarizeThreshold.round().clamp(0, 255),
        );
      } else if (type == _kFilterTypeGaussianBlur &&
          blurRadius > 0 &&
          bitmapWidth > 0 &&
          bitmapHeight > 0) {
        _filterApplyGaussianBlurToBitmap(
          bitmap,
          bitmapWidth,
          bitmapHeight,
          blurRadius,
        );
      } else if (type == _kFilterTypeLeakRemoval &&
          leakSteps > 0 &&
          bitmapWidth > 0 &&
          bitmapHeight > 0) {
        _filterApplyLeakRemovalToBitmap(
          bitmap,
          bitmapWidth,
          bitmapHeight,
          leakSteps,
        );
      } else if (type == _kFilterTypeLineNarrow &&
          morphRadius > 0 &&
          bitmapWidth > 0 &&
          bitmapHeight > 0) {
        final int morphSteps = morphRadius
            .round()
            .clamp(1, _kMorphologyMaxRadius.toInt())
            .toInt();
        _filterApplyMorphologyToBitmap(
          bitmap,
          bitmapWidth,
          bitmapHeight,
          morphSteps,
          dilate: false,
        );
      } else if (type == _kFilterTypeFillExpand &&
          morphRadius > 0 &&
          bitmapWidth > 0 &&
          bitmapHeight > 0) {
        final int morphSteps = morphRadius
            .round()
            .clamp(1, _kMorphologyMaxRadius.toInt())
            .toInt();
        _filterApplyMorphologyToBitmap(
          bitmap,
          bitmapWidth,
          bitmapHeight,
          morphSteps,
          dilate: true,
        );
      }
      if (!_filterBitmapHasVisiblePixels(bitmap)) {
        bitmap = null;
      }
    }

    int? adjustedFill = fillColorValue;
    if (fillColorValue != null) {
      final Color source = Color(fillColorValue);
      Color adjusted = source;
      if (type == _kFilterTypeHueSaturation) {
        adjusted = _filterApplyHueSaturationToColor(
          source,
          hueDelta,
          saturationPercent,
          lightnessPercent,
        );
      } else if (type == _kFilterTypeBrightnessContrast) {
        adjusted = _filterApplyBrightnessContrastToColor(
          source,
          brightnessPercent,
          contrastPercent,
        );
      } else if (type == _kFilterTypeBlackWhite) {
        adjusted = _filterApplyBlackWhiteToColor(
          source,
          blackPoint,
          whitePoint,
          midTone,
        );
      } else if (type == _kFilterTypeBinarize) {
        adjusted = _filterApplyBinarizeToColor(
          source,
          binarizeThreshold.round().clamp(0, 255),
        );
      }
      adjustedFill = adjusted.value;
    }

    parent.send(<String, Object?>{
      'token': token,
      'layerId': layerId,
      'bitmap': bitmap != null
          ? TransferableTypedData.fromList(<Uint8List>[bitmap])
          : null,
      'fillColor': adjustedFill,
    });
  });
}

double _filterReadListValue(List<dynamic>? values, int index) {
  if (values == null || index < 0 || index >= values.length) {
    return 0.0;
  }
  final Object value = values[index];
  if (value is num) {
    return value.toDouble();
  }
  return 0.0;
}
