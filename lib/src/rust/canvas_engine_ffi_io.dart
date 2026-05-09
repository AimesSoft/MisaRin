import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'rust_dylib.dart';

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

typedef _EngineCreateNative =
    ffi.Uint64 Function(ffi.Uint32 width, ffi.Uint32 height);
typedef _EngineCreateDart = int Function(int width, int height);

typedef _EngineDisposeNative = ffi.Void Function(ffi.Uint64 handle);
typedef _EngineDisposeDart = void Function(int handle);

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

typedef _EngineIsValidNative = ffi.Uint8 Function(ffi.Uint64 handle);
typedef _EngineIsValidDart = int Function(int handle);

typedef _EngineSetLogLevelNative = ffi.Void Function(ffi.Uint32 level);
typedef _EngineSetLogLevelDart = void Function(int level);

typedef _EngineRequestPresentNative = ffi.Void Function(ffi.Uint64 handle);
typedef _EngineRequestPresentDart = void Function(int handle);

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
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Uint32 fromIndex,
      ffi.Uint32 toIndex,
    );
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

typedef _EngineReadPresentPixelNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 x,
      ffi.Uint32 y,
      ffi.Pointer<ffi.Uint32> outArgb,
    );
typedef _EngineReadPresentPixelDart =
    int Function(int handle, int x, int y, ffi.Pointer<ffi.Uint32> outArgb);

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
typedef _EngineWriteLayerAsyncNative =
    ffi.Uint8 Function(
      ffi.Uint64 handle,
      ffi.Uint32 layerIndex,
      ffi.Pointer<ffi.Uint32> pixels,
      ffi.UintPtr pixelsLen,
      ffi.Uint8 recordUndo,
    );
typedef _EngineWriteLayerAsyncDart =
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
      ffi.Uint8 smoothRotation,
      ffi.Uint32 rotationSeed,
      ffi.Float spacing,
      ffi.Float hardness,
      ffi.Float flow,
      ffi.Float scatter,
      ffi.Float rotationJitter,
      ffi.Uint8 snapToPixel,
      ffi.Uint8 screentoneEnabled,
      ffi.Float screentoneSpacing,
      ffi.Float screentoneDotSize,
      ffi.Float screentoneRotation,
      ffi.Float screentoneSoftness,
      ffi.Uint32 screentoneShape,
      ffi.Uint8 hollow,
      ffi.Float hollowRatio,
      ffi.Uint8 hollowEraseOccludedParts,
      ffi.Float streamlineStrength,
      ffi.Uint32 smoothingMode,
      ffi.Float stabilizerStrength,
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
      int smoothRotation,
      int rotationSeed,
      double spacing,
      double hardness,
      double flow,
      double scatter,
      double rotationJitter,
      int snapToPixel,
      int screentoneEnabled,
      double screentoneSpacing,
      double screentoneDotSize,
      double screentoneRotation,
      double screentoneSoftness,
      int screentoneShape,
      int hollow,
      double hollowRatio,
      int hollowEraseOccludedParts,
      double streamlineStrength,
      int smoothingMode,
      double stabilizerStrength,
    );

typedef _EngineSetBrushMaskNative =
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Uint32 width,
      ffi.Uint32 height,
      ffi.Pointer<ffi.Uint8> mask,
      ffi.UintPtr maskLen,
    );
typedef _EngineSetBrushMaskDart =
    void Function(
      int handle,
      int width,
      int height,
      ffi.Pointer<ffi.Uint8> mask,
      int maskLen,
    );

typedef _EngineClearBrushMaskNative = ffi.Void Function(ffi.Uint64 handle);
typedef _EngineClearBrushMaskDart = void Function(int handle);

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

typedef _EngineLiquifyBeginNative = ffi.Void Function(ffi.Uint64 handle);
typedef _EngineLiquifyBeginDart = void Function(int handle);

typedef _EngineLiquifyDrawNative =
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Float fromX,
      ffi.Float fromY,
      ffi.Float toX,
      ffi.Float toY,
      ffi.Float radius,
      ffi.Float strength,
      ffi.Float softness,
      ffi.Float mix,
    );
typedef _EngineLiquifyDrawDart =
    void Function(
      int handle,
      double fromX,
      double fromY,
      double toX,
      double toY,
      double radius,
      double strength,
      double softness,
      double mix,
    );

typedef _EngineLiquifyEndNative = ffi.Void Function(ffi.Uint64 handle);
typedef _EngineLiquifyEndDart = void Function(int handle);

typedef _EngineSmudgeBeginNative = ffi.Void Function(ffi.Uint64 handle);
typedef _EngineSmudgeBeginDart = void Function(int handle);

typedef _EngineSmudgeDrawNative =
    ffi.Void Function(
      ffi.Uint64 handle,
      ffi.Float fromX,
      ffi.Float fromY,
      ffi.Float toX,
      ffi.Float toY,
      ffi.Float radius,
      ffi.Float strength,
      ffi.Float softness,
    );
typedef _EngineSmudgeDrawDart =
    void Function(
      int handle,
      double fromX,
      double fromY,
      double toX,
      double toY,
      double radius,
      double strength,
      double softness,
    );

typedef _EngineSmudgeEndNative = ffi.Void Function(ffi.Uint64 handle);
typedef _EngineSmudgeEndDart = void Function(int handle);

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
    int Function(int handle, int layerIndex, int level);

typedef _EngineLogPopNative = ffi.Pointer<ffi.Char> Function();
typedef _EngineLogPopDart = ffi.Pointer<ffi.Char> Function();
typedef _EngineLogFreeNative = ffi.Void Function(ffi.Pointer<ffi.Char> ptr);
typedef _EngineLogFreeDart = void Function(ffi.Pointer<ffi.Char> ptr);

class CanvasEngineFfi {
  CanvasEngineFfi._() {
    try {
      _lib = _openLibrary();
      try {
        _createEngine = _lib
            .lookupFunction<_EngineCreateNative, _EngineCreateDart>(
              'engine_create',
            );
      } catch (_) {
        _createEngine = null;
      }
      try {
        _disposeEngine = _lib
            .lookupFunction<_EngineDisposeNative, _EngineDisposeDart>(
              'engine_dispose',
            );
      } catch (_) {
        _disposeEngine = null;
      }
      _pushPoints = _lib
          .lookupFunction<_EnginePushPointsNative, _EnginePushPointsDart>(
            'engine_push_points',
          );
      _getQueueLen = _lib
          .lookupFunction<
            _EngineGetInputQueueLenNative,
            _EngineGetInputQueueLenDart
          >('engine_get_input_queue_len');
      try {
        _setLogLevel = _lib
            .lookupFunction<_EngineSetLogLevelNative, _EngineSetLogLevelDart>(
              'engine_set_log_level',
            );
      } catch (_) {
        _setLogLevel = null;
      }
      try {
        _requestPresent = _lib
            .lookupFunction<
              _EngineRequestPresentNative,
              _EngineRequestPresentDart
            >('engine_request_present');
      } catch (_) {
        _requestPresent = null;
      }
      try {
        _isValid = _lib
            .lookupFunction<_EngineIsValidNative, _EngineIsValidDart>(
              'engine_is_valid',
            );
      } catch (_) {
        _isValid = null;
      }

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
            .lookupFunction<_EngineReorderLayerNative, _EngineReorderLayerDart>(
              'engine_reorder_layer',
            );
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
        _readPresentPixel = _lib
            .lookupFunction<
              _EngineReadPresentPixelNative,
              _EngineReadPresentPixelDart
            >('engine_read_present_pixel');
      } catch (_) {
        _readPresentPixel = null;
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
        _writeLayerAsync = _lib
            .lookupFunction<
              _EngineWriteLayerAsyncNative,
              _EngineWriteLayerAsyncDart
            >('engine_write_layer_async');
      } catch (_) {
        _writeLayerAsync = null;
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
        _setBrushMask = _lib
            .lookupFunction<_EngineSetBrushMaskNative, _EngineSetBrushMaskDart>(
              'engine_set_brush_mask',
            );
      } catch (_) {
        _setBrushMask = null;
      }
      try {
        _clearBrushMask = _lib
            .lookupFunction<
              _EngineClearBrushMaskNative,
              _EngineClearBrushMaskDart
            >('engine_clear_brush_mask');
      } catch (_) {
        _clearBrushMask = null;
      }
      try {
        _sprayBegin = _lib
            .lookupFunction<_EngineSprayBeginNative, _EngineSprayBeginDart>(
              'engine_spray_begin',
            );
      } catch (_) {
        _sprayBegin = null;
      }
      try {
        _sprayDraw = _lib
            .lookupFunction<_EngineSprayDrawNative, _EngineSprayDrawDart>(
              'engine_spray_draw',
            );
      } catch (_) {
        _sprayDraw = null;
      }
      try {
        _sprayEnd = _lib
            .lookupFunction<_EngineSprayEndNative, _EngineSprayEndDart>(
              'engine_spray_end',
            );
      } catch (_) {
        _sprayEnd = null;
      }
      try {
        _liquifyBegin = _lib
            .lookupFunction<_EngineLiquifyBeginNative, _EngineLiquifyBeginDart>(
              'engine_liquify_begin',
            );
      } catch (_) {
        _liquifyBegin = null;
      }
      try {
        _liquifyDraw = _lib
            .lookupFunction<_EngineLiquifyDrawNative, _EngineLiquifyDrawDart>(
              'engine_liquify_draw',
            );
      } catch (_) {
        _liquifyDraw = null;
      }
      try {
        _liquifyEnd = _lib
            .lookupFunction<_EngineLiquifyEndNative, _EngineLiquifyEndDart>(
              'engine_liquify_end',
            );
      } catch (_) {
        _liquifyEnd = null;
      }
      try {
        _smudgeBegin = _lib
            .lookupFunction<_EngineSmudgeBeginNative, _EngineSmudgeBeginDart>(
              'engine_smudge_begin',
            );
      } catch (_) {
        _smudgeBegin = null;
      }
      try {
        _smudgeDraw = _lib
            .lookupFunction<_EngineSmudgeDrawNative, _EngineSmudgeDrawDart>(
              'engine_smudge_draw',
            );
      } catch (_) {
        _smudgeDraw = null;
      }
      try {
        _smudgeEnd = _lib
            .lookupFunction<_EngineSmudgeEndNative, _EngineSmudgeEndDart>(
              'engine_smudge_end',
            );
      } catch (_) {
        _smudgeEnd = null;
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
        _logPop = _lib.lookupFunction<_EngineLogPopNative, _EngineLogPopDart>(
          'engine_log_pop',
        );
        _logFree = _lib
            .lookupFunction<_EngineLogFreeNative, _EngineLogFreeDart>(
              'engine_log_free',
            );
      } catch (_) {
        _logPop = null;
        _logFree = null;
      }
      isSupported = true;
    } catch (_) {
      isSupported = false;
    }
  }

  static final CanvasEngineFfi instance = CanvasEngineFfi._();

  static ffi.DynamicLibrary _openLibrary() {
    return RustDynamicLibrary.open();
  }

  late final ffi.DynamicLibrary _lib;
  late final _EngineCreateDart? _createEngine;
  late final _EngineDisposeDart? _disposeEngine;
  late final _EnginePushPointsDart _pushPoints;
  late final _EngineGetInputQueueLenDart _getQueueLen;
  late final _EngineSetLogLevelDart? _setLogLevel;
  late final _EngineRequestPresentDart? _requestPresent;
  late final _EngineIsValidDart? _isValid;
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
  late final _EngineReadPresentPixelDart? _readPresentPixel;
  late final _EngineWriteLayerDart? _writeLayer;
  late final _EngineWriteLayerAsyncDart? _writeLayerAsync;
  late final _EngineTranslateLayerDart? _translateLayer;
  late final _EngineSetLayerTransformPreviewDart? _setLayerTransformPreview;
  late final _EngineApplyLayerTransformDart? _applyLayerTransform;
  late final _EngineGetLayerBoundsDart? _getLayerBounds;
  late final _EngineSetSelectionMaskDart? _setSelectionMask;
  late final _EngineResetCanvasDart? _resetCanvas;
  late final _EngineUndoDart? _undo;
  late final _EngineRedoDart? _redo;
  late final _EngineSetBrushDart? _setBrush;
  late final _EngineSetBrushMaskDart? _setBrushMask;
  late final _EngineClearBrushMaskDart? _clearBrushMask;
  late final _EngineSprayBeginDart? _sprayBegin;
  late final _EngineSprayDrawDart? _sprayDraw;
  late final _EngineSprayEndDart? _sprayEnd;
  late final _EngineLiquifyBeginDart? _liquifyBegin;
  late final _EngineLiquifyDrawDart? _liquifyDraw;
  late final _EngineLiquifyEndDart? _liquifyEnd;
  late final _EngineSmudgeBeginDart? _smudgeBegin;
  late final _EngineSmudgeDrawDart? _smudgeDraw;
  late final _EngineSmudgeEndDart? _smudgeEnd;
  late final _EngineApplyFilterDart? _applyFilter;
  late final _EngineApplyAntialiasDart? _applyAntialias;
  late final _EngineLogPopDart? _logPop;
  late final _EngineLogFreeDart? _logFree;

  ffi.Pointer<ffi.Uint8>? _staging;
  int _stagingCapacityBytes = 0;

  late final bool isSupported;

  bool get canCreateEngine =>
      isSupported && _createEngine != null && _disposeEngine != null;

  bool get supportsSmudge =>
      isSupported &&
      _smudgeBegin != null &&
      _smudgeDraw != null &&
      _smudgeEnd != null;

  int createEngine({required int width, required int height}) {
    final fn = _createEngine;
    if (!isSupported || fn == null || width <= 0 || height <= 0) {
      return 0;
    }
    return fn(width, height);
  }

  void disposeEngine({required int handle}) {
    final fn = _disposeEngine;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle);
  }

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

  void setLogLevel(int level) {
    final fn = _setLogLevel;
    if (!isSupported || fn == null) {
      return;
    }
    fn(level);
  }

  void requestPresent({required int handle}) {
    final fn = _requestPresent;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle);
  }

  String? popLogLine() {
    final fn = _logPop;
    final free = _logFree;
    if (!isSupported || fn == null || free == null) {
      return null;
    }
    final ffi.Pointer<ffi.Char> ptr = fn();
    if (ptr == ffi.nullptr) {
      return null;
    }
    final String line = ptr.cast<Utf8>().toDartString();
    free(ptr);
    return line;
  }

  List<String> drainLogs({int maxLines = 200}) {
    final List<String> lines = <String>[];
    for (int i = 0; i < maxLines; i++) {
      final String? line = popLogLine();
      if (line == null) {
        break;
      }
      lines.add(line);
    }
    return lines;
  }

  bool isHandleValid(int handle) {
    if (!isSupported || handle == 0) {
      return false;
    }
    final fn = _isValid;
    if (fn == null) {
      return false;
    }
    return fn(handle) != 0;
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
      final int result = fn(
        handle,
        layerIndex,
        width,
        height,
        outPtr,
        byteCount,
      );
      if (result == 0) {
        return null;
      }
      return Uint8List.fromList(outPtr.asTypedList(byteCount));
    } finally {
      malloc.free(outPtr);
    }
  }

  int? readPresentPixel({required int handle, required int x, required int y}) {
    final fn = _readPresentPixel;
    if (!isSupported || fn == null || handle == 0 || x < 0 || y < 0) {
      return null;
    }
    final ffi.Pointer<ffi.Uint32> outPtr = malloc.allocate<ffi.Uint32>(
      ffi.sizeOf<ffi.Uint32>(),
    );
    try {
      final int result = fn(handle, x, y, outPtr);
      if (result == 0) {
        return null;
      }
      return outPtr.value;
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

  bool writeLayerAsync({
    required int handle,
    required int layerIndex,
    required Uint32List pixels,
    bool recordUndo = true,
  }) {
    final fn = _writeLayerAsync ?? _writeLayer;
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

  void setBrush({
    required int handle,
    required int colorArgb,
    required double baseRadius,
    bool usePressure = true,
    bool erase = false,
    int antialiasLevel = 1,
    int brushShape = 0,
    bool randomRotation = false,
    bool smoothRotation = false,
    int rotationSeed = 0,
    double spacing = 0.15,
    double hardness = 0.8,
    double flow = 1.0,
    double scatter = 0.0,
    double rotationJitter = 1.0,
    bool snapToPixel = false,
    bool screentoneEnabled = false,
    double screentoneSpacing = 10.0,
    double screentoneDotSize = 0.6,
    double screentoneRotation = 45.0,
    double screentoneSoftness = 0.0,
    int screentoneShape = 0,
    bool hollow = false,
    double hollowRatio = 0.0,
    bool hollowEraseOccludedParts = false,
    double streamlineStrength = 0.0,
    int smoothingMode = 1,
    double stabilizerStrength = 0.0,
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
    double screentoneSpacingValue = screentoneSpacing;
    if (!screentoneSpacingValue.isFinite) {
      screentoneSpacingValue = 10.0;
    }
    screentoneSpacingValue = screentoneSpacingValue.clamp(2.0, 200.0);
    double screentoneDotSizeValue = screentoneDotSize;
    if (!screentoneDotSizeValue.isFinite) {
      screentoneDotSizeValue = 0.6;
    }
    screentoneDotSizeValue = screentoneDotSizeValue.clamp(0.0, 1.0);
    double screentoneRotationValue = screentoneRotation;
    if (!screentoneRotationValue.isFinite) {
      screentoneRotationValue = 45.0;
    }
    screentoneRotationValue = screentoneRotationValue.clamp(-180.0, 180.0);
    double screentoneSoftnessValue = screentoneSoftness;
    if (!screentoneSoftnessValue.isFinite) {
      screentoneSoftnessValue = 0.0;
    }
    screentoneSoftnessValue = screentoneSoftnessValue.clamp(0.0, 1.0);
    int screentoneShapeValue = screentoneShape;
    if (screentoneShapeValue < 0) {
      screentoneShapeValue = 0;
    } else if (screentoneShapeValue > 3) {
      screentoneShapeValue = 3;
    }
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
    int smoothing = smoothingMode;
    if (smoothing < 0) {
      smoothing = 0;
    }
    if (smoothing > 3) {
      smoothing = 3;
    }
    double stabilizer = stabilizerStrength;
    if (!stabilizer.isFinite) {
      stabilizer = 0.0;
    }
    stabilizer = stabilizer.clamp(0.0, 1.0);
    fn(
      handle,
      colorArgb,
      radius,
      usePressure ? 1 : 0,
      erase ? 1 : 0,
      antialiasLevel.clamp(0, 9),
      shape,
      randomRotation ? 1 : 0,
      smoothRotation ? 1 : 0,
      seed,
      spacingValue,
      hardnessValue,
      flowValue,
      scatterValue,
      rotationValue,
      snapToPixel ? 1 : 0,
      screentoneEnabled ? 1 : 0,
      screentoneSpacingValue,
      screentoneDotSizeValue,
      screentoneRotationValue,
      screentoneSoftnessValue,
      screentoneShapeValue,
      hollow ? 1 : 0,
      ratio,
      hollowEraseOccludedParts ? 1 : 0,
      streamline,
      smoothing,
      stabilizer,
    );
  }

  void setBrushMask({
    required int handle,
    required int width,
    required int height,
    required Uint8List mask,
  }) {
    final fn = _setBrushMask;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    if (width <= 0 || height <= 0 || mask.isEmpty) {
      clearBrushMask(handle: handle);
      return;
    }
    final int expectedLen = width * height * 2;
    if (mask.length != expectedLen) {
      clearBrushMask(handle: handle);
      return;
    }
    final int maskLen = mask.length;
    final ffi.Pointer<ffi.Uint8> ptr = malloc.allocate<ffi.Uint8>(maskLen);
    ptr.asTypedList(maskLen).setAll(0, mask);
    try {
      fn(handle, width, height, ptr, maskLen);
    } finally {
      malloc.free(ptr);
    }
  }

  void clearBrushMask({required int handle}) {
    final fn = _clearBrushMask;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle);
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

  void beginLiquify({required int handle}) {
    final fn = _liquifyBegin;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle);
  }

  void drawLiquify({
    required int handle,
    required double fromX,
    required double fromY,
    required double toX,
    required double toY,
    required double radius,
    required double strength,
    required double softness,
    required double mix,
  }) {
    final fn = _liquifyDraw;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    double safeRadius = radius;
    if (!safeRadius.isFinite) {
      safeRadius = 1.0;
    }
    safeRadius = safeRadius.clamp(1.0, 4096.0);
    double safeStrength = strength;
    if (!safeStrength.isFinite) {
      safeStrength = 0.0;
    }
    safeStrength = safeStrength.clamp(0.0, 1.0);
    double safeSoftness = softness;
    if (!safeSoftness.isFinite) {
      safeSoftness = 0.65;
    }
    safeSoftness = safeSoftness.clamp(0.0, 1.0);
    double safeMix = mix;
    if (!safeMix.isFinite) {
      safeMix = 0.0;
    }
    safeMix = safeMix.clamp(0.0, 1.0);
    fn(
      handle,
      fromX.isFinite ? fromX : 0.0,
      fromY.isFinite ? fromY : 0.0,
      toX.isFinite ? toX : 0.0,
      toY.isFinite ? toY : 0.0,
      safeRadius,
      safeStrength,
      safeSoftness,
      safeMix,
    );
  }

  void endLiquify({required int handle}) {
    final fn = _liquifyEnd;
    if (!isSupported || fn == null || handle == 0) {
      return;
    }
    fn(handle);
  }

  void beginSmudge({required int handle}) {
    final fn = _smudgeBegin;
    if (!supportsSmudge || fn == null || handle == 0) {
      return;
    }
    fn(handle);
  }

  void drawSmudge({
    required int handle,
    required double fromX,
    required double fromY,
    required double toX,
    required double toY,
    required double radius,
    required double strength,
    required double softness,
  }) {
    final fn = _smudgeDraw;
    if (!supportsSmudge || fn == null || handle == 0) {
      return;
    }
    double safeRadius = radius;
    if (!safeRadius.isFinite) {
      safeRadius = 1.0;
    }
    safeRadius = safeRadius.clamp(1.0, 4096.0);
    double safeStrength = strength;
    if (!safeStrength.isFinite) {
      safeStrength = 0.0;
    }
    safeStrength = safeStrength.clamp(0.0, 1.0);
    double safeSoftness = softness;
    if (!safeSoftness.isFinite) {
      safeSoftness = 0.78;
    }
    safeSoftness = safeSoftness.clamp(0.0, 1.0);
    fn(
      handle,
      fromX.isFinite ? fromX : 0.0,
      fromY.isFinite ? fromY : 0.0,
      toX.isFinite ? toX : 0.0,
      toY.isFinite ? toY : 0.0,
      safeRadius,
      safeStrength,
      safeSoftness,
    );
  }

  void endSmudge({required int handle}) {
    final fn = _smudgeEnd;
    if (!supportsSmudge || fn == null || handle == 0) {
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
