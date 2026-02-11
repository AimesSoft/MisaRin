import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int _kPointStrideBytes = 32;
const int _kViewFlagMirror = 1;
const int _kViewFlagBlackWhite = 2;

final class _EnginePointNative extends ffi.Struct {
  @ffi.Float()
  external double x;

  @ffi.Float()
  external double y;

  @ffi.Float()
  external double pressure;

  @ffi.Float()
  // ignore: unused_field
  external double _pad0;

  @ffi.Uint64()
  external int timestampUs;

  @ffi.Uint32()
  external int flags;

  @ffi.Uint32()
  external int pointerId;
}

typedef _EnginePushPointsNative =
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Pointer<_EnginePointNative> points,
      ffi.UintPtr len,
    );
typedef _EnginePushPointsDart =
    void Function(int handle, ffi.Pointer<_EnginePointNative> points, int len);

typedef _EngineGetInputQueueLenNative = ffi.Uint64 Function(ffi.Uint64 handle);
typedef _EngineGetInputQueueLenDart = int Function(int handle);

typedef _EngineSetActiveLayerNative =
    ffi.Void Function(ffi.Uint64 handle, ffi.Uint32 layerIndex);
typedef _EngineSetActiveLayerDart = void Function(int handle, int layerIndex);

typedef _EngineSetLayerOpacityNative =
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Float opacity,
    );
typedef _EngineSetLayerOpacityDart =
    void Function(int handle, int layerIndex, double opacity);

typedef _EngineSetLayerVisibleNative =
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Uint8 visible,
    );
typedef _EngineSetLayerVisibleDart =
    void Function(int handle, int layerIndex, int visible);

typedef _EngineSetLayerClippingMaskNative =
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Uint8 clippingMask,
    );
typedef _EngineSetLayerClippingMaskDart =
    void Function(int handle, int layerIndex, int clippingMask);

typedef _EngineSetLayerBlendModeNative =
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Uint32 blendModeIndex,
    );
typedef _EngineSetLayerBlendModeDart =
    void Function(int handle, int layerIndex, int blendModeIndex);

typedef _EngineReorderLayerNative =
    ffi.Void Function(ffi.Uint64 handle, ffi.Uint32 fromIndex, ffi.Uint32 toIndex);
typedef _EngineReorderLayerDart =
    void Function(int handle, int fromIndex, int toIndex);

typedef _EngineSetViewFlagsNative =
    ffi.Void Function(ffi.Uint64 handle, ffi.Uint32 viewFlags);
typedef _EngineSetViewFlagsDart = void Function(int handle, int viewFlags);

typedef _EngineClearLayerNative =
    ffi.Void Function(ffi.Uint64 handle, ffi.Uint32 layerIndex);
typedef _EngineClearLayerDart = void Function(int handle, int layerIndex);

typedef _EngineFillLayerNative =
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Uint32 colorArgb,
    );
typedef _EngineFillLayerDart =
    void Function(int handle, int layerIndex, int colorArgb);

typedef _EngineBucketFillNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Int32 startX,
      ffi.Int32 startY,
      ffi.Uint32 colorArgb,
      ffi.Uint8 contiguous,
      ffi.Uint8 sampleAllLayers,
      ffi.Uint32 tolerance,
      ffi.Uint32 fillGap,
      ffi.Uint32 antialiasLevel,
      ffi.Pointer<ffi.Uint32> swallowColors,
      ffi.UintPtr swallowColorsLen,
      ffi.Pointer<ffi.Uint8> selectionMask,
      ffi.UintPtr selectionMaskLen,
    );
typedef _EngineBucketFillDart =
    int Function(
      int handle,
      int layerIndex,
      int startX,
      int startY,
      int colorArgb,
      int contiguous,
      int sampleAllLayers,
      int tolerance,
      int fillGap,
      int antialiasLevel,
      ffi.Pointer<ffi.Uint32> swallowColors,
      int swallowColorsLen,
      ffi.Pointer<ffi.Uint8> selectionMask,
      int selectionMaskLen,
    );

typedef _EngineMagicWandMaskNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Int32 startX,
      ffi.Int32 startY,
      ffi.Uint8 sampleAllLayers,
      ffi.Uint32 tolerance,
      ffi.Pointer<ffi.Uint8> selectionMask,
      ffi.UintPtr selectionMaskLen,
      ffi.Pointer<ffi.Uint8> outMask,
      ffi.UintPtr outMaskLen,
    );
typedef _EngineMagicWandMaskDart =
    int Function(
      int handle,
      int layerIndex,
      int startX,
      int startY,
      int sampleAllLayers,
      int tolerance,
      ffi.Pointer<ffi.Uint8> selectionMask,
      int selectionMaskLen,
      ffi.Pointer<ffi.Uint8> outMask,
      int outMaskLen,
    );

typedef _EngineReadLayerNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Pointer<ffi.Uint32> outPixels,
      ffi.UintPtr outPixelsLen,
    );
typedef _EngineReadLayerDart =
    int Function(
      int handle,
      int layerIndex,
      ffi.Pointer<ffi.Uint32> outPixels,
      int outPixelsLen,
    );

typedef _EngineReadLayerPreviewNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Uint32 width,
      ffi.Uint32 height,
      ffi.Pointer<ffi.Uint8> outPixels,
      ffi.UintPtr outPixelsLen,
    );
typedef _EngineReadLayerPreviewDart =
    int Function(
      int handle,
      int layerIndex,
      int width,
      int height,
      ffi.Pointer<ffi.Uint8> outPixels,
      int outPixelsLen,
    );

typedef _EngineWriteLayerNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Pointer<ffi.Uint32> pixels,
      ffi.UintPtr pixelsLen,
      ffi.Uint8 recordUndo,
    );
typedef _EngineWriteLayerDart =
    int Function(
      int handle,
      int layerIndex,
      ffi.Pointer<ffi.Uint32> pixels,
      int pixelsLen,
      int recordUndo,
    );

typedef _EngineTranslateLayerNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Int32 deltaX,
      ffi.Int32 deltaY,
    );
typedef _EngineTranslateLayerDart =
    int Function(int handle, int layerIndex, int deltaX, int deltaY);

typedef _EngineSetLayerTransformPreviewNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Pointer<ffi.Float> matrix,
      ffi.UintPtr matrixLen,
      ffi.Uint8 enabled,
      ffi.Uint8 bilinear,
    );
typedef _EngineSetLayerTransformPreviewDart =
    int Function(
      int handle,
      int layerIndex,
      ffi.Pointer<ffi.Float> matrix,
      int matrixLen,
      int enabled,
      int bilinear,
    );

typedef _EngineApplyLayerTransformNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Pointer<ffi.Float> matrix,
      ffi.UintPtr matrixLen,
      ffi.Uint8 bilinear,
    );
typedef _EngineApplyLayerTransformDart =
    int Function(
      int handle,
      int layerIndex,
      ffi.Pointer<ffi.Float> matrix,
      int matrixLen,
      int bilinear,
    );

typedef _EngineGetLayerBoundsNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Pointer<ffi.Int32> outBounds,
      ffi.UintPtr outLen,
    );
typedef _EngineGetLayerBoundsDart =
    int Function(
      int handle,
      int layerIndex,
      ffi.Pointer<ffi.Int32> outBounds,
      int outLen,
    );

typedef _EngineSetSelectionMaskNative =
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Pointer<ffi.Uint8> selectionMask,
      ffi.UintPtr selectionMaskLen,
    );
typedef _EngineSetSelectionMaskDart =
    void Function(
      int handle,
      ffi.Pointer<ffi.Uint8> selectionMask,
      int selectionMaskLen,
    );

typedef _EngineResetCanvasNative =
    ffi.Void Function(ffi.Uint64 handle, ffi.Uint32 backgroundColorArgb);
typedef _EngineResetCanvasDart =
    void Function(int handle, int backgroundColorArgb);

typedef _EngineUndoNative = ffi.Void Function(ffi.Uint64 handle);
typedef _EngineUndoDart = void Function(int handle);

typedef _EngineRedoNative = ffi.Void Function(ffi.Uint64 handle);
typedef _EngineRedoDart = void Function(int handle);

typedef _EngineSetBrushNative =
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Uint32 colorArgb,
      ffi.Float baseRadius,
      ffi.Uint8 usePressure,
      ffi.Uint8 erase,
      ffi.Uint32 antialiasLevel,
      ffi.Uint32 brushShape,
      ffi.Uint8 randomRotation,
      ffi.Uint32 rotationSeed,
      ffi.Float spacing,
      ffi.Float hardness,
      ffi.Float flow,
      ffi.Float scatter,
      ffi.Float rotationJitter,
      ffi.Uint8 snapToPixel,
      ffi.Uint8 hollow,
      ffi.Float hollowRatio,
      ffi.Uint8 hollowEraseOccludedParts,
      ffi.Float streamlineStrength,
    );
typedef _EngineSetBrushDart =
    void Function(
      int handle,
      int colorArgb,
      double baseRadius,
      int usePressure,
      int erase,
      int antialiasLevel,
      int brushShape,
      int randomRotation,
      int rotationSeed,
      double spacing,
      double hardness,
      double flow,
      double scatter,
      double rotationJitter,
      int snapToPixel,
      int hollow,
      double hollowRatio,
      int hollowEraseOccludedParts,
      double streamlineStrength,
    );

typedef _EngineSprayBeginNative = ffi.Void Function(ffi.Uint64 handle);
typedef _EngineSprayBeginDart = void Function(int handle);

typedef _EngineSprayDrawNative =
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Pointer<ffi.Float> points,
      ffi.UintPtr pointCount,
      ffi.Uint32 colorArgb,
      ffi.Uint32 brushShape,
      ffi.Uint8 erase,
      ffi.Uint32 antialiasLevel,
      ffi.Float softness,
      ffi.Uint8 accumulate,
    );
typedef _EngineSprayDrawDart =
    void Function(
      int handle,
      ffi.Pointer<ffi.Float> points,
      int pointCount,
      int colorArgb,
      int brushShape,
      int erase,
      int antialiasLevel,
      double softness,
      int accumulate,
    );

typedef _EngineSprayEndNative = ffi.Void Function(ffi.Uint64 handle);
typedef _EngineSprayEndDart = void Function(int handle);

typedef _EngineApplyFilterNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Uint32 filterType,
      ffi.Float param0,
      ffi.Float param1,
      ffi.Float param2,
      ffi.Float param3,
    );
typedef _EngineApplyFilterDart =
    int Function(
      int handle,
      int layerIndex,
      int filterType,
      double param0,
      double param1,
      double param2,
      double param3,
    );

typedef _EngineApplyAntialiasNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Uint32 level,
    );
typedef _EngineApplyAntialiasDart =
    int Function(
      int handle,
      int layerIndex,
      int level,
    );

typedef _EnginePollFrameReadyNative = ffi.Uint8 Function(ffi.Uint64 handle);
typedef _EnginePollFrameReadyDart = int Function(int handle);

typedef _EngineReadPresentNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Pointer<ffi.Uint8> outPixels,
      ffi.UintPtr outPixelsLen,
    );
typedef _EngineReadPresentDart =
    int Function(
      int handle,
      ffi.Pointer<ffi.Uint8> outPixels,
      int outPixelsLen,
    );

class CanvasEngineFfi {
  CanvasEngineFfi._() {
    try {
      _lib = _openLibrary();
      _pushPoints = _lib
          .lookupFunction<_EnginePushPointsNative, _EnginePushPointsDart>(
            'engine_push_points',
          );
      _getQueueLen = _lib
          .lookupFunction<
            _EngineGetInputQueueLenNative,
            _EngineGetInputQueueLenDart
          >('engine_get_input_queue_len');

      // Optional layer controls (not required for basic drawing).
      try {
        _setActiveLayer = _lib
            .lookupFunction<
              _EngineSetActiveLayerNative,
              _EngineSetActiveLayerDart
            >('engine_set_active_layer');
      } catch (_) {
        _setActiveLayer = null;
      }
      try {
        _setLayerOpacity = _lib
            .lookupFunction<
              _EngineSetLayerOpacityNative,
              _EngineSetLayerOpacityDart
            >('engine_set_layer_opacity');
      } catch (_) {
        _setLayerOpacity = null;
      }
      try {
        _setLayerVisible = _lib
            .lookupFunction<
              _EngineSetLayerVisibleNative,
              _EngineSetLayerVisibleDart
            >('engine_set_layer_visible');
      } catch (_) {
        _setLayerVisible = null;
      }
      try {
        _setLayerClippingMask = _lib
            .lookupFunction<
              _EngineSetLayerClippingMaskNative,
              _EngineSetLayerClippingMaskDart
            >('engine_set_layer_clipping_mask');
      } catch (_) {
        _setLayerClippingMask = null;
      }
      try {
        _setLayerBlendMode = _lib
            .lookupFunction<
              _EngineSetLayerBlendModeNative,
              _EngineSetLayerBlendModeDart
            >('engine_set_layer_blend_mode');
      } catch (_) {
        _setLayerBlendMode = null;
      }
      try {
        _reorderLayer = _lib
            .lookupFunction<
              _EngineReorderLayerNative,
              _EngineReorderLayerDart
            >('engine_reorder_layer');
      } catch (_) {
        _reorderLayer = null;
      }
      try {
        _setViewFlags = _lib
            .lookupFunction<_EngineSetViewFlagsNative, _EngineSetViewFlagsDart>(
              'engine_set_view_flags',
            );
      } catch (_) {
        _setViewFlags = null;
      }
      try {
        _clearLayer = _lib
            .lookupFunction<_EngineClearLayerNative, _EngineClearLayerDart>(
              'engine_clear_layer',
            );
      } catch (_) {
        _clearLayer = null;
      }
      try {
        _fillLayer = _lib
            .lookupFunction<_EngineFillLayerNative, _EngineFillLayerDart>(
              'engine_fill_layer',
            );
      } catch (_) {
        _fillLayer = null;
      }
      try {
        _bucketFill = _lib
            .lookupFunction<_EngineBucketFillNative, _EngineBucketFillDart>(
              'engine_bucket_fill',
            );
      } catch (_) {
        _bucketFill = null;
      }
      try {
        _magicWandMask = _lib
            .lookupFunction<
              _EngineMagicWandMaskNative,
              _EngineMagicWandMaskDart
            >('engine_magic_wand_mask');
      } catch (_) {
        _magicWandMask = null;
      }
      try {
        _readLayer = _lib
            .lookupFunction<_EngineReadLayerNative, _EngineReadLayerDart>(
              'engine_read_layer',
            );
      } catch (_) {
        _readLayer = null;
      }
      try {
        _readLayerPreview = _lib
            .lookupFunction<
              _EngineReadLayerPreviewNative,
              _EngineReadLayerPreviewDart
            >('engine_read_layer_preview');
      } catch (_) {
        _readLayerPreview = null;
      }
      try {
        _writeLayer = _lib
            .lookupFunction<_EngineWriteLayerNative, _EngineWriteLayerDart>(
              'engine_write_layer',
            );
      } catch (_) {
        _writeLayer = null;
      }
      try {
        _translateLayer = _lib
            .lookupFunction<
              _EngineTranslateLayerNative,
              _EngineTranslateLayerDart
            >('engine_translate_layer');
      } catch (_) {
        _translateLayer = null;
      }
      try {
        _setLayerTransformPreview = _lib
            .lookupFunction<
              _EngineSetLayerTransformPreviewNative,
              _EngineSetLayerTransformPreviewDart
            >('engine_set_layer_transform_preview');
      } catch (_) {
        _setLayerTransformPreview = null;
      }
      try {
        _applyLayerTransform = _lib
            .lookupFunction<
              _EngineApplyLayerTransformNative,
              _EngineApplyLayerTransformDart
            >('engine_apply_layer_transform');
      } catch (_) {
        _applyLayerTransform = null;
      }
      try {
        _getLayerBounds = _lib
            .lookupFunction<
              _EngineGetLayerBoundsNative,
              _EngineGetLayerBoundsDart
            >('engine_get_layer_bounds');
      } catch (_) {
        _getLayerBounds = null;
      }
      try {
        _setSelectionMask = _lib
            .lookupFunction<
              _EngineSetSelectionMaskNative,
              _EngineSetSelectionMaskDart
            >('engine_set_selection_mask');
      } catch (_) {
        _setSelectionMask = null;
      }
      try {
        _resetCanvas = _lib
            .lookupFunction<_EngineResetCanvasNative, _EngineResetCanvasDart>(
              'engine_reset_canvas',
            );
      } catch (_) {
        _resetCanvas = null;
      }

      // Optional undo/redo (Flow 7).
      try {
        _undo = _lib.lookupFunction<_EngineUndoNative, _EngineUndoDart>(
          'engine_undo',
        );
      } catch (_) {
        _undo = null;
      }
      try {
        _redo = _lib.lookupFunction<_EngineRedoNative, _EngineRedoDart>(
          'engine_redo',
        );
      } catch (_) {
        _redo = null;
      }

      // Optional brush settings (color/size/etc).
      try {
        _setBrush = _lib
            .lookupFunction<_EngineSetBrushNative, _EngineSetBrushDart>(
              'engine_set_brush',
            );
      } catch (_) {
        _setBrush = null;
      }
      try {
        _sprayBegin =
            _lib.lookupFunction<_EngineSprayBeginNative, _EngineSprayBeginDart>(
              'engine_spray_begin',
            );
      } catch (_) {
        _sprayBegin = null;
      }
      try {
        _sprayDraw =
            _lib.lookupFunction<_EngineSprayDrawNative, _EngineSprayDrawDart>(
              'engine_spray_draw',
            );
      } catch (_) {
        _sprayDraw = null;
      }
      try {
        _sprayEnd =
            _lib.lookupFunction<_EngineSprayEndNative, _EngineSprayEndDart>(
              'engine_spray_end',
            );
      } catch (_) {
        _sprayEnd = null;
      }
      try {
        _applyFilter = _lib
            .lookupFunction<_EngineApplyFilterNative, _EngineApplyFilterDart>(
              'engine_apply_filter',
            );
      } catch (_) {
        _applyFilter = null;
      }
      try {
        _applyAntialias = _lib
            .lookupFunction<
              _EngineApplyAntialiasNative,
              _EngineApplyAntialiasDart
            >('engine_apply_antialias');
      } catch (_) {
        _applyAntialias = null;
      }
      try {
        _pollFrameReady = _lib.lookupFunction<
          _EnginePollFrameReadyNative,
          _EnginePollFrameReadyDart
        >('engine_poll_frame_ready');
      } catch (_) {
        _pollFrameReady = null;
      }
      try {
        _readPresent = _lib.lookupFunction<
          _EngineReadPresentNative,
          _EngineReadPresentDart
        >('engine_read_present');
      } catch (_) {
        _readPresent = null;
      }
      isSupported = true;
    } catch (_) {
      isSupported = false;
    }
  }

  static final CanvasEngineFfi instance = CanvasEngineFfi._();

  static ffi.DynamicLibrary _openLibrary() {
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('rust_lib_misa_rin.dll');
    }
    return ffi.DynamicLibrary.process();
  }

  late final ffi.DynamicLibrary _lib;
  late final _EnginePushPointsDart _pushPoints;
  late final _EngineGetInputQueueLenDart _getQueueLen;
  late final _EngineSetActiveLayerDart? _setActiveLayer;
  late final _EngineSetLayerOpacityDart? _setLayerOpacity;
  late final _EngineSetLayerVisibleDart? _setLayerVisible;
  late final _EngineSetLayerClippingMaskDart? _setLayerClippingMask;
  late final _EngineSetLayerBlendModeDart? _setLayerBlendMode;
  late final _EngineReorderLayerDart? _reorderLayer;
  late final _EngineSetViewFlagsDart? _setViewFlags;
  late final _EngineClearLayerDart? _clearLayer;
  late final _EngineFillLayerDart? _fillLayer;
  late final _EngineBucketFillDart? _bucketFill;
  late final _EngineMagicWandMaskDart? _magicWandMask;
  late final _EngineReadLayerDart? _readLayer;
  late final _EngineReadLayerPreviewDart? _readLayerPreview;
  late final _EngineWriteLayerDart? _writeLayer;
  late final _EngineTranslateLayerDart? _translateLayer;
  late final _EngineSetLayerTransformPreviewDart? _setLayerTransformPreview;
  late final _EngineApplyLayerTransformDart? _applyLayerTransform;
  late final _EngineGetLayerBoundsDart? _getLayerBounds;
  late final _EngineSetSelectionMaskDart? _setSelectionMask;
  late final _EngineResetCanvasDart? _resetCanvas;
  late final _EngineUndoDart? _undo;
  late final _EngineRedoDart? _redo;
  late final _EngineSetBrushDart? _setBrush;
  late final _EngineSprayBeginDart? _sprayBegin;
  late final _EngineSprayDrawDart? _sprayDraw;
  late final _EngineSprayEndDart? _sprayEnd;
  late final _EngineApplyFilterDart? _applyFilter;
  late final _EngineApplyAntialiasDart? _applyAntialias;
  late final _EnginePollFrameReadyDart? _pollFrameReady;
  late final _EngineReadPresentDart? _readPresent;

  ffi.Pointer<ffi.Uint8>? _staging;
  int _stagingCapacityBytes = 0;

  late final bool isSupported;

  void pushPointsPacked({
    required int handle,
    required Uint8List bytes,
    required int pointCount,
  }) {
    if (!isSupported || handle == 0 || pointCount <= 0) {
      return;
    }
    final int requiredBytes = pointCount * _kPointStrideBytes;
    if (bytes.length < requiredBytes) {
      throw RangeError.range(bytes.length, requiredBytes, null, 'bytes.length');
    }

    final ffi.Pointer<ffi.Uint8> ptr = _ensureStaging(requiredBytes);
    ptr.asTypedList(requiredBytes).setRange(0, requiredBytes, bytes, 0);
    _pushPoints(handle, ptr.cast<_EnginePointNative>(), pointCount);
  }

  int getInputQueueLen(int handle) {
    if (!isSupported || handle == 0) {
      return 0;
    }
    return _getQueueLen(handle);
  }

  void setActiveLayer({required int handle, required int layerIndex}) {
    final fn = _setActiveLayer;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle, layerIndex);
  }

  void setLayerOpacity({
    required int handle,
    required int layerIndex,
    required double opacity,
  }) {
    final fn = _setLayerOpacity;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle, layerIndex, opacity);
  }

  void setLayerVisible({
    required int handle,
    required int layerIndex,
    required bool visible,
  }) {
    final fn = _setLayerVisible;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle, layerIndex, visible ? 1 : 0);
  }

  void setLayerClippingMask({
    required int handle,
    required int layerIndex,
    required bool clippingMask,
  }) {
    final fn = _setLayerClippingMask;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle, layerIndex, clippingMask ? 1 : 0);
  }

  void setLayerBlendMode({
    required int handle,
    required int layerIndex,
    required int blendModeIndex,
  }) {
    final fn = _setLayerBlendMode;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle, layerIndex, blendModeIndex);
  }

  void reorderLayer({
    required int handle,
    required int fromIndex,
    required int toIndex,
  }) {
    final fn = _reorderLayer;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    if (fromIndex < 0 || toIndex < 0) {
      return;
    }
    fn(handle, fromIndex, toIndex);
  }

  void setViewFlags({
    required int handle,
    required bool mirror,
    required bool blackWhite,
  }) {
    final fn = _setViewFlags;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    int flags = 0;
    if (mirror) {
      flags |= _kViewFlagMirror;
    }
    if (blackWhite) {
      flags |= _kViewFlagBlackWhite;
    }
    fn(handle, flags);
  }

  void clearLayer({required int handle, required int layerIndex}) {
    final fn = _clearLayer;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle, layerIndex);
  }

  void fillLayer({
    required int handle,
    required int layerIndex,
    required int colorArgb,
  }) {
    final fn = _fillLayer;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle, layerIndex, colorArgb);
  }

  bool bucketFill({
    required int handle,
    required int layerIndex,
    required int startX,
    required int startY,
    required int colorArgb,
    bool contiguous = true,
    bool sampleAllLayers = false,
    int tolerance = 0,
    int fillGap = 0,
    int antialiasLevel = 0,
    Uint32List? swallowColors,
    Uint8List? selectionMask,
  }) {
    final fn = _bucketFill;
    if (!isSupported || fn == null || handle == 0) {
      return false;
    }
    final int clampedTolerance = tolerance.clamp(0, 255);
    final int clampedFillGap = fillGap.clamp(0, 64);
    final int clampedAntialias = antialiasLevel.clamp(0, 9);

    ffi.Pointer<ffi.Uint32> swallowPtr = ffi.nullptr;
    int swallowLen = 0;
    if (swallowColors != null && swallowColors.isNotEmpty) {
      swallowLen = swallowColors.length;
      swallowPtr = malloc.allocate<ffi.Uint32>(
        swallowLen * ffi.sizeOf<ffi.Uint32>(),
      );
      swallowPtr.asTypedList(swallowLen).setAll(0, swallowColors);
    }

    ffi.Pointer<ffi.Uint8> selectionPtr = ffi.nullptr;
    int selectionLen = 0;
    if (selectionMask != null && selectionMask.isNotEmpty) {
      selectionLen = selectionMask.length;
      selectionPtr = malloc.allocate<ffi.Uint8>(selectionLen);
      selectionPtr.asTypedList(selectionLen).setAll(0, selectionMask);
    }

    try {
      final int result = fn(
        handle,
        layerIndex,
        startX,
        startY,
        colorArgb,
        contiguous ? 1 : 0,
        sampleAllLayers ? 1 : 0,
        clampedTolerance,
        clampedFillGap,
        clampedAntialias,
        swallowPtr,
        swallowLen,
        selectionPtr,
        selectionLen,
      );
      return result != 0;
    } finally {
      if (swallowPtr != ffi.nullptr) {
        malloc.free(swallowPtr);
      }
      if (selectionPtr != ffi.nullptr) {
        malloc.free(selectionPtr);
      }
    }
  }

  Uint8List? magicWandMask({
    required int handle,
    required int layerIndex,
    required int startX,
    required int startY,
    required int maskLength,
    bool sampleAllLayers = true,
    int tolerance = 0,
    Uint8List? selectionMask,
  }) {
    final fn = _magicWandMask;
    if (!isSupported || fn == null || handle == 0) {
      return null;
    }
    if (maskLength <= 0) {
      return null;
    }
    final int clampedTolerance = tolerance.clamp(0, 255);

    ffi.Pointer<ffi.Uint8> selectionPtr = ffi.nullptr;
    int selectionLen = 0;
    final Uint8List? normalizedSelection =
        selectionMask != null && selectionMask.length == maskLength
        ? selectionMask
        : null;
    if (normalizedSelection != null && normalizedSelection.isNotEmpty) {
      selectionLen = normalizedSelection.length;
      selectionPtr = malloc.allocate<ffi.Uint8>(selectionLen);
      selectionPtr.asTypedList(selectionLen).setAll(0, normalizedSelection);
    }

    ffi.Pointer<ffi.Uint8> outPtr = ffi.nullptr;
    try {
      outPtr = malloc.allocate<ffi.Uint8>(maskLength);
      final int result = fn(
        handle,
        layerIndex,
        startX,
        startY,
        sampleAllLayers ? 1 : 0,
        clampedTolerance,
        selectionPtr,
        selectionLen,
        outPtr,
        maskLength,
      );
      if (result == 0) {
        return null;
      }
      return Uint8List.fromList(outPtr.asTypedList(maskLength));
    } finally {
      if (selectionPtr != ffi.nullptr) {
        malloc.free(selectionPtr);
      }
      if (outPtr != ffi.nullptr) {
        malloc.free(outPtr);
      }
    }
  }

  Uint32List? readLayer({
    required int handle,
    required int layerIndex,
    required int width,
    required int height,
  }) {
    final fn = _readLayer;
    if (!isSupported || fn == null || handle == 0) {
      return null;
    }
    if (width <= 0 || height <= 0) {
      return null;
    }
    final int pixelCount = width * height;
    if (pixelCount <= 0) {
      return null;
    }
    final ffi.Pointer<ffi.Uint32> outPtr = malloc.allocate<ffi.Uint32>(
      pixelCount * ffi.sizeOf<ffi.Uint32>(),
    );
    try {
      final int result = fn(handle, layerIndex, outPtr, pixelCount);
      if (result == 0) {
        return null;
      }
      return Uint32List.fromList(outPtr.asTypedList(pixelCount));
    } finally {
      malloc.free(outPtr);
    }
  }

  Uint8List? readLayerPreview({
    required int handle,
    required int layerIndex,
    required int width,
    required int height,
  }) {
    final fn = _readLayerPreview;
    if (!isSupported || fn == null || handle == 0) {
      return null;
    }
    if (width <= 0 || height <= 0) {
      return null;
    }
    final int byteCount = width * height * 4;
    if (byteCount <= 0) {
      return null;
    }
    final ffi.Pointer<ffi.Uint8> outPtr = malloc.allocate<ffi.Uint8>(byteCount);
    try {
      final int result = fn(handle, layerIndex, width, height, outPtr, byteCount);
      if (result == 0) {
        return null;
      }
      return Uint8List.fromList(outPtr.asTypedList(byteCount));
    } finally {
      malloc.free(outPtr);
    }
  }

  bool writeLayer({
    required int handle,
    required int layerIndex,
    required Uint32List pixels,
    bool recordUndo = true,
  }) {
    final fn = _writeLayer;
    if (!isSupported || fn == null || handle == 0) {
      return false;
    }
    if (pixels.isEmpty) {
      return false;
    }
    final ffi.Pointer<ffi.Uint32> ptr = malloc.allocate<ffi.Uint32>(
      pixels.length * ffi.sizeOf<ffi.Uint32>(),
    );
    ptr.asTypedList(pixels.length).setAll(0, pixels);
    try {
      final int result = fn(
        handle,
        layerIndex,
        ptr,
        pixels.length,
        recordUndo ? 1 : 0,
      );
      return result != 0;
    } finally {
      malloc.free(ptr);
    }
  }

  bool translateLayer({
    required int handle,
    required int layerIndex,
    required int deltaX,
    required int deltaY,
  }) {
    final fn = _translateLayer;
    if (!isSupported || fn == null || handle == 0) {
      return false;
    }
    if (deltaX == 0 && deltaY == 0) {
      return false;
    }
    final int result = fn(handle, layerIndex, deltaX, deltaY);
    return result != 0;
  }

  bool setLayerTransformPreview({
    required int handle,
    required int layerIndex,
    required Float32List matrix,
    bool enabled = true,
    bool bilinear = true,
  }) {
    final fn = _setLayerTransformPreview;
    if (!isSupported || fn == null || handle == 0) {
      return false;
    }
    if (matrix.length < 16) {
      return false;
    }
    final ffi.Pointer<ffi.Float> ptr = malloc.allocate<ffi.Float>(
      16 * ffi.sizeOf<ffi.Float>(),
    );
    ptr.asTypedList(16).setRange(0, 16, matrix);
    try {
      final int result = fn(
        handle,
        layerIndex,
        ptr,
        16,
        enabled ? 1 : 0,
        bilinear ? 1 : 0,
      );
      return result != 0;
    } finally {
      malloc.free(ptr);
    }
  }

  bool applyLayerTransform({
    required int handle,
    required int layerIndex,
    required Float32List matrix,
    bool bilinear = true,
  }) {
    final fn = _applyLayerTransform;
    if (!isSupported || fn == null || handle == 0) {
      return false;
    }
    if (matrix.length < 16) {
      return false;
    }
    final ffi.Pointer<ffi.Float> ptr = malloc.allocate<ffi.Float>(
      16 * ffi.sizeOf<ffi.Float>(),
    );
    ptr.asTypedList(16).setRange(0, 16, matrix);
    try {
      final int result = fn(handle, layerIndex, ptr, 16, bilinear ? 1 : 0);
      return result != 0;
    } finally {
      malloc.free(ptr);
    }
  }

  Int32List? getLayerBounds({required int handle, required int layerIndex}) {
    final fn = _getLayerBounds;
    if (!isSupported || fn == null || handle == 0) {
      return null;
    }
    final ffi.Pointer<ffi.Int32> ptr = malloc.allocate<ffi.Int32>(
      4 * ffi.sizeOf<ffi.Int32>(),
    );
    try {
      final int result = fn(handle, layerIndex, ptr, 4);
      if (result == 0) {
        return null;
      }
      return Int32List.fromList(ptr.asTypedList(4));
    } finally {
      malloc.free(ptr);
    }
  }

  void setSelectionMask({required int handle, Uint8List? selectionMask}) {
    final fn = _setSelectionMask;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }

    ffi.Pointer<ffi.Uint8> selectionPtr = ffi.nullptr;
    int selectionLen = 0;
    if (selectionMask != null && selectionMask.isNotEmpty) {
      selectionLen = selectionMask.length;
      selectionPtr = malloc.allocate<ffi.Uint8>(selectionLen);
      selectionPtr.asTypedList(selectionLen).setAll(0, selectionMask);
    }

    try {
      fn(handle, selectionPtr, selectionLen);
    } finally {
      if (selectionPtr != ffi.nullptr) {
        malloc.free(selectionPtr);
      }
    }
  }

  void resetCanvas({required int handle, required int backgroundColorArgb}) {
    final fn = _resetCanvas;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle, backgroundColorArgb);
  }

  void undo({required int handle}) {
    final fn = _undo;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle);
  }

  void redo({required int handle}) {
    final fn = _redo;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle);
  }

  bool pollFrameReady(int handle) {
    final fn = _pollFrameReady;
    if (!isSupported || fn == null || handle == 0) {
      return false;
    }
    return fn(handle) != 0;
  }

  Uint8List? readPresent({
    required int handle,
    required int width,
    required int height,
  }) {
    final fn = _readPresent;
    if (!isSupported || fn == null || handle == 0) {
      return null;
    }
    if (width <= 0 || height <= 0) {
      return null;
    }
    final int byteCount = width * height * 4;
    final ffi.Pointer<ffi.Uint8> outPtr = malloc.call<ffi.Uint8>(byteCount);
    try {
      final int ok = fn(handle, outPtr, byteCount);
      if (ok == 0) {
        return null;
      }
      final Uint8List bytes = Uint8List(byteCount);
      bytes.setAll(0, outPtr.asTypedList(byteCount));
      return bytes;
    } finally {
      malloc.free(outPtr);
    }
  }

  void setBrush({
    required int handle,
    required int colorArgb,
    required double baseRadius,
    bool usePressure = true,
    bool erase = false,
    int antialiasLevel = 1,
    int brushShape = 0,
    bool randomRotation = false,
    int rotationSeed = 0,
    double spacing = 0.15,
    double hardness = 0.8,
    double flow = 1.0,
    double scatter = 0.0,
    double rotationJitter = 1.0,
    bool snapToPixel = false,
    bool hollow = false,
    double hollowRatio = 0.0,
    bool hollowEraseOccludedParts = false,
    double streamlineStrength = 0.0,
  }) {
    final fn = _setBrush;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    double radius = baseRadius;
    if (!radius.isFinite) {
      radius = 0.0;
    }
    if (radius < 0.0) {
      radius = 0.0;
    }
    final int shape = brushShape < 0 ? 0 : brushShape;
    final int seed = rotationSeed & 0xffffffff;
    double spacingValue = spacing;
    if (!spacingValue.isFinite) {
      spacingValue = 0.15;
    }
    spacingValue = spacingValue.clamp(0.02, 2.5);
    double hardnessValue = hardness;
    if (!hardnessValue.isFinite) {
      hardnessValue = 0.8;
    }
    hardnessValue = hardnessValue.clamp(0.0, 1.0);
    double flowValue = flow;
    if (!flowValue.isFinite) {
      flowValue = 1.0;
    }
    flowValue = flowValue.clamp(0.0, 1.0);
    double scatterValue = scatter;
    if (!scatterValue.isFinite) {
      scatterValue = 0.0;
    }
    scatterValue = scatterValue.clamp(0.0, 1.0);
    double rotationValue = rotationJitter;
    if (!rotationValue.isFinite) {
      rotationValue = 1.0;
    }
    rotationValue = rotationValue.clamp(0.0, 1.0);
    double ratio = hollowRatio;
    if (!ratio.isFinite) {
      ratio = 0.0;
    }
    ratio = ratio.clamp(0.0, 1.0);
    double streamline = streamlineStrength;
    if (!streamline.isFinite) {
      streamline = 0.0;
    }
    streamline = streamline.clamp(0.0, 1.0);
    fn(
      handle,
      colorArgb,
      radius,
      usePressure ? 1 : 0,
      erase ? 1 : 0,
      antialiasLevel.clamp(0, 9),
      shape,
      randomRotation ? 1 : 0,
      seed,
      spacingValue,
      hardnessValue,
      flowValue,
      scatterValue,
      rotationValue,
      snapToPixel ? 1 : 0,
      hollow ? 1 : 0,
      ratio,
      hollowEraseOccludedParts ? 1 : 0,
      streamline,
    );
  }

  void beginSpray({required int handle}) {
    final fn = _sprayBegin;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle);
  }

  void drawSpray({
    required int handle,
    required Float32List points,
    required int pointCount,
    required int colorArgb,
    int brushShape = 0,
    bool erase = false,
    int antialiasLevel = 1,
    double softness = 0.0,
    bool accumulate = true,
  }) {
    final fn = _sprayDraw;
    if (!isSupported || fn == null || handle == 0 || pointCount <= 0) {
      return;
    }
    final int floatCount = pointCount * 4;
    if (points.length < floatCount) {
      return;
    }
    final ffi.Pointer<ffi.Float> ptr = malloc.allocate<ffi.Float>(
      floatCount * ffi.sizeOf<ffi.Float>(),
    );
    ptr.asTypedList(floatCount).setRange(0, floatCount, points, 0);
    try {
      fn(
        handle,
        ptr,
        pointCount,
        colorArgb,
        brushShape,
        erase ? 1 : 0,
        antialiasLevel.clamp(0, 9),
        softness.clamp(0.0, 1.0),
        accumulate ? 1 : 0,
      );
    } finally {
      malloc.free(ptr);
    }
  }

  void endSpray({required int handle}) {
    final fn = _sprayEnd;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle);
  }

  bool applyFilter({
    required int handle,
    required int layerIndex,
    required int filterType,
    double param0 = 0.0,
    double param1 = 0.0,
    double param2 = 0.0,
    double param3 = 0.0,
  }) {
    final fn = _applyFilter;
    if (!isSupported || fn == null || handle == 0) {
      return false;
    }
    final int result = fn(
      handle,
      layerIndex,
      filterType,
      param0,
      param1,
      param2,
      param3,
    );
    return result != 0;
  }

  bool applyAntialias({
    required int handle,
    required int layerIndex,
    required int level,
  }) {
    final fn = _applyAntialias;
    if (!isSupported || fn == null || handle == 0) {
      return false;
    }
    final int result = fn(handle, layerIndex, level);
    return result != 0;
  }

  ffi.Pointer<ffi.Uint8> _ensureStaging(int requiredBytes) {
    final ffi.Pointer<ffi.Uint8>? existing = _staging;
    if (existing != null && _stagingCapacityBytes >= requiredBytes) {
      return existing;
    }
    if (existing != null) {
      malloc.free(existing);
      _staging = null;
      _stagingCapacityBytes = 0;
    }
    final ffi.Pointer<ffi.Uint8> next = malloc.allocate<ffi.Uint8>(
      requiredBytes,
    );
    _staging = next;
    _stagingCapacityBytes = requiredBytes;
    return next;
  }
}
