import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../bitmap_canvas/bitmap_blend_utils.dart' as blend_utils;
import '../bitmap_canvas/bitmap_canvas.dart';
import '../bitmap_canvas/bitmap_layer_state.dart';
import '../bitmap_canvas/raster_int_rect.dart';
import '../src/rust/api/gpu_composite.dart' as rust_gpu;
import '../src/rust/api/image_ops.dart' as rust_image_ops;
import '../src/rust/rust_init.dart';
import 'rgba_utils.dart';

const bool _kDebugGpuComposite = bool.fromEnvironment(
  'MISA_RIN_DEBUG_GPU_COMPOSITE',
  defaultValue: false,
);

class RasterCompositeWork {
  const RasterCompositeWork._({
    required this.hasWork,
    required this.requiresFullSurface,
    this.regions,
  });

  const RasterCompositeWork.noWork()
    : this._(hasWork: false, requiresFullSurface: false);

  const RasterCompositeWork.withWork({
    required bool requiresFullSurface,
    List<RasterIntRect>? regions,
  }) : this._(
         hasWork: true,
         requiresFullSurface: requiresFullSurface,
         regions: regions,
       );

  final bool hasWork;
  final bool requiresFullSurface;
  final List<RasterIntRect>? regions;
}

class CanvasRasterBackend {
  CanvasRasterBackend({
    required int width,
    required int height,
    this.tileSize = 256,
  }) : _width = width,
       _height = height {
    _backendInstanceCount++;
  }

  static final Uint32List _emptyPixels = Uint32List(0);
  static Future<void>? _gpuInitFuture;
  static Future<void> _gpuCompositeSerial = Future<void>.value();
  static int _gpuCompositeEpoch = 0;
  static int _backendInstanceCount = 0;

  int _width;
  int _height;
  final int tileSize;

  bool _disposed = false;

  bool _compositeDirty = true;
  bool _compositeInitialized = false;
  bool _pendingFullSurface = false;
  Rect? _pendingDirtyBounds;
  final List<RasterIntRect> _pendingDirtyTiles = <RasterIntRect>[];
  final Set<int> _pendingDirtyTileKeys = <int>{};

  Uint32List? _compositePixels;

  int _knownGpuCompositeEpoch = 0;
  bool _gpuLayerCacheInitialized = false;
  int _cachedLayerWidth = 0;
  int _cachedLayerHeight = 0;
  List<String>? _cachedLayerOrder;
  final Map<String, int> _cachedLayerRevisions = <String, int>{};

  bool get isCompositeDirty => _compositeDirty;
  Uint32List? get compositePixels => _compositePixels;
  int get width => _width;
  int get height => _height;

  static Future<void> initGpu() async {
    try {
      await _ensureGpuInitialized();
    } catch (e) {
      throw Exception('GPU初始化失败，无法运行: $e');
    }
  }

  static Future<void> prewarmGpuEngine() async {
    await initGpu();
    await _runGpuCompositeSerialized(() async {
      try {
        // Perform a dummy 1x1 composite to trigger shader compilation and pipeline setup.
        await rust_gpu.gpuCompositeLayers(
          layers: [],
          width: 1,
          height: 1,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('GPU engine prewarm failed: $e');
        }
      }
    });
  }

  static Future<void> _ensureGpuInitialized() {
    final Future<void>? existing = _gpuInitFuture;
    if (existing != null) {
      return existing;
    }
    final Future<void> future = () async {
      await ensureRustInitialized();
      if (!kIsWeb) {
        rust_gpu.gpuCompositorInit();
      }
    }();
    _gpuInitFuture = future;
    return future.catchError((Object error, StackTrace stackTrace) {
      _gpuInitFuture = null;
      return Future<void>.error(error, stackTrace);
    });
  }

  void markDirty({Rect? region, String? layerId, bool pixelsDirty = true}) {
    _compositeDirty = true;

    if (region == null || _pendingFullSurface) {
      _pendingDirtyBounds = null;
      _pendingDirtyTiles.clear();
      _pendingDirtyTileKeys.clear();
      _pendingFullSurface = true;
      return;
    }
    final Rect clipped = Rect.fromLTWH(
      0,
      0,
      _width.toDouble(),
      _height.toDouble(),
    ).intersect(region);
    if (clipped.isEmpty) {
      return;
    }

    if (_pendingDirtyBounds == null) {
      _pendingDirtyBounds = clipped;
    } else {
      final Rect current = _pendingDirtyBounds!;
      _pendingDirtyBounds = Rect.fromLTRB(
        math.min(current.left, clipped.left),
        math.min(current.top, clipped.top),
        math.max(current.right, clipped.right),
        math.max(current.bottom, clipped.bottom),
      );
    }
    _enqueueDirtyTiles(clipped);
  }

  RasterCompositeWork dequeueCompositeWork() {
    if (!_compositeDirty) {
      return const RasterCompositeWork.noWork();
    }
    final bool requiresFullSurface =
        !_compositeInitialized ||
        _pendingFullSurface ||
        _pendingDirtyBounds == null;
    final List<RasterIntRect>? dirtyTiles = requiresFullSurface
        ? null
        : List<RasterIntRect>.from(_pendingDirtyTiles);
    _pendingDirtyBounds = null;
    _pendingDirtyTiles.clear();
    _pendingDirtyTileKeys.clear();
    _pendingFullSurface = false;
    return RasterCompositeWork.withWork(
      requiresFullSurface: requiresFullSurface,
      regions: dirtyTiles,
    );
  }

  Future<void> composite({
    required List<BitmapLayerState> layers,
    required bool requiresFullSurface,
    List<RasterIntRect>? regions,
    String? translatingLayerId,
  }) async {
    _ensureBuffers();
    if (!requiresFullSurface && (regions == null || regions.isEmpty)) {
      return;
    }

    await initGpu();

    await _runGpuCompositeSerialized(() async {
      final List<BitmapLayerState> effectiveLayers = <BitmapLayerState>[];
      for (final BitmapLayerState layer in layers) {
        if (translatingLayerId != null && layer.id == translatingLayerId) {
          continue;
        }
        if (!layer.visible) {
          continue;
        }
        effectiveLayers.add(layer);
      }

      // Snapshot the layer revisions used for this composite pass.
      //
      // IMPORTANT: `gpuCompositeLayers` is async; while awaiting the Rust call,
      // other tasks (e.g. GPU brush strokes) can mutate layer pixels and bump
      // revisions. If we update `_cachedLayerRevisions` with the *latest*
      // revisions after the await, we may incorrectly treat the GPU compositor
      // cache as up-to-date and skip required uploads, leading to stale tiles
      // (visual "cuts" along tile boundaries).
      final List<int> revisionSnapshot = <int>[
        for (final BitmapLayerState layer in effectiveLayers) layer.revision,
      ];

      final List<String> layerOrder = effectiveLayers
          .map((BitmapLayerState layer) => layer.id)
          .toList(growable: false);

      final bool sameEpoch = _gpuLayerCacheInitialized &&
          _knownGpuCompositeEpoch == _gpuCompositeEpoch;
      final bool sameCanvasSize =
          _cachedLayerWidth == _width && _cachedLayerHeight == _height;
      final bool sameOrder = _listEquals(_cachedLayerOrder, layerOrder);

      final bool allowIncrementalPixels = sameEpoch && sameCanvasSize && sameOrder;

      final bool debugComposite = kDebugMode && _kDebugGpuComposite;
      final List<bool>? uploadFlags =
          debugComposite ? List<bool>.filled(effectiveLayers.length, false) : null;
      final List<int?>? cachedRevisionsAtDecision =
          debugComposite ? List<int?>.filled(effectiveLayers.length, null) : null;
      bool lastForceFullPixels = false;

      Future<Uint32List> runComposite({required bool forceFullPixels}) {
        lastForceFullPixels = forceFullPixels;
        final List<rust_gpu.GpuLayerData> gpuLayers = <rust_gpu.GpuLayerData>[];
        if (kDebugMode && _kDebugGpuComposite) {
          debugPrint(
            '[gpu-composite] size=${_width}x${_height} '
            'requiresFullSurface=$requiresFullSurface regions=${regions?.length ?? 0} '
            'layers=${effectiveLayers.length} '
            'sameEpoch=$sameEpoch sameCanvasSize=$sameCanvasSize sameOrder=$sameOrder '
            'allowIncremental=$allowIncrementalPixels forceFullPixels=$forceFullPixels',
          );
        }
        for (int i = 0; i < effectiveLayers.length; i++) {
          final BitmapLayerState layer = effectiveLayers[i];
          final int layerRevision = revisionSnapshot[i];
          final int? cachedRevision = _cachedLayerRevisions[layer.id];
          cachedRevisionsAtDecision?[i] = cachedRevision;
          final bool pixelsUnchanged =
              cachedRevision != null && cachedRevision == layerRevision;
          final Uint32List pixels = (!forceFullPixels &&
                  allowIncrementalPixels &&
                  pixelsUnchanged)
              ? _emptyPixels
              : layer.surface.pixels;
          uploadFlags?[i] = pixels.isNotEmpty;

          if (kDebugMode && _kDebugGpuComposite) {
            debugPrint(
              '  layer id=${layer.id} revSnapshot=$layerRevision cached=${cachedRevision ?? -1} '
              'upload=${pixels.isNotEmpty} pixelsLen=${pixels.length} '
              'opacity=${layer.opacity.toStringAsFixed(3)} blend=${layer.blendMode.index} '
              'clip=${layer.clippingMask} visible=${layer.visible}',
            );
          }

          gpuLayers.add(
            rust_gpu.GpuLayerData(
              pixels: pixels,
              opacity: layer.opacity,
              blendModeIndex: layer.blendMode.index,
              visible: true,
              clippingMask: layer.clippingMask,
            ),
          );
        }

        return rust_gpu.gpuCompositeLayers(
          layers: gpuLayers,
          width: _width,
          height: _height,
        );
      }

      Uint32List result;
      try {
        result = await runComposite(forceFullPixels: false);
      } catch (e) {
        if (_isGpuNeedsFullUploadError(e)) {
          if (kDebugMode && _kDebugGpuComposite) {
            debugPrint('[gpu-composite] needs full upload, retrying...');
          }
          _invalidateGpuLayerCache();
          result = await runComposite(forceFullPixels: true);
        } else {
          if (kDebugMode && _kDebugGpuComposite) {
            debugPrint('[gpu-composite] error: $e');
          }
          _invalidateGpuLayerCache();
          _gpuCompositeEpoch++;
          _knownGpuCompositeEpoch = _gpuCompositeEpoch;
          rethrow;
        }
      }

      final Uint32List composite = _compositePixels!;
      if (result.length != composite.length) {
        _invalidateGpuLayerCache();
        _gpuCompositeEpoch++;
        _knownGpuCompositeEpoch = _gpuCompositeEpoch;
        throw StateError(
          'GPU composite size mismatch: got ${result.length}, expected ${composite.length}',
        );
      }
      composite.setAll(0, result);

      _gpuCompositeEpoch++;
      _knownGpuCompositeEpoch = _gpuCompositeEpoch;
      _gpuLayerCacheInitialized = true;
      _cachedLayerWidth = _width;
      _cachedLayerHeight = _height;
      _cachedLayerOrder = layerOrder;
      for (int i = 0; i < effectiveLayers.length; i++) {
        final BitmapLayerState layer = effectiveLayers[i];
        _cachedLayerRevisions[layer.id] = revisionSnapshot[i];
      }

      if (kDebugMode && _kDebugGpuComposite) {
        for (int i = 0; i < effectiveLayers.length; i++) {
          final BitmapLayerState layer = effectiveLayers[i];
          final int before = revisionSnapshot[i];
          final int now = layer.revision;
          if (now != before) {
            final bool wasUploaded = uploadFlags?[i] ?? false;
            final int? cached = cachedRevisionsAtDecision?[i];
            debugPrint(
              '[gpu-composite] layer ${layer.id} revision changed during composite: '
              '$before -> $now (will be handled next pass)',
            );
            if (!lastForceFullPixels && allowIncrementalPixels && !wasUploaded) {
              debugPrint(
                '[gpu-composite] layer ${layer.id} used cached GPU pixels in this pass '
                '(upload=false cached=${cached ?? -1} snapshot=$before now=$now)',
              );
            }
          }
        }
      }

      if (requiresFullSurface) {
        _compositeInitialized = true;
      }
    });
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    _invalidateGpuLayerCache();
    _compositePixels = null;

    if (_backendInstanceCount > 0) {
      _backendInstanceCount--;
    }
    if (_backendInstanceCount != 0) {
      return;
    }

    final Future<void>? initFuture = _gpuInitFuture;
    if (initFuture == null) {
      return;
    }
    await _runGpuCompositeSerialized(() async {
      try {
        await initFuture;
        if (!kIsWeb) {
          rust_gpu.gpuCompositorDispose();
        }
      } catch (_) {}
    });
    _gpuInitFuture = null;
    _gpuCompositeEpoch = 0;
    _gpuCompositeSerial = Future<void>.value();
  }

  void completeCompositePass() {
    _compositeDirty = _pendingFullSurface || _pendingDirtyBounds != null;
    // Clean up old cache entries that weren't updated?
    // Or maybe just keep them until next dirty?
    // Actually, we should probably clear the cache for tiles that are dirtied but not yet updated.
    // But here we just updated them.
  }

  Uint32List ensureCompositePixels() {
    _ensureBuffers();
    return _compositePixels!;
  }

  void resetClipMask() {}

  Uint8List copyTileRgba(RasterIntRect rect) {
    final Uint32List pixels = ensureCompositePixels();
    final int tileWidth = rect.width;
    final int tileHeight = rect.height;
    final int surfaceWidth = _width;
    
    // Extract the tile pixels into a flat Uint32List for Rust processing
    final Uint32List tilePixels = Uint32List(tileWidth * tileHeight);
    for (int row = 0; row < tileHeight; row++) {
      final int srcRowStart = (rect.top + row) * surfaceWidth + rect.left;
      tilePixels.setRange(
        row * tileWidth,
        (row + 1) * tileWidth,
        pixels,
        srcRowStart,
      );
    }
    
    // The Rust side now handles both conversion to RGBA and Premultiply in one high-speed pass.
    return kIsWeb
        ? argbToPremultipliedRgba(tilePixels)
        : rust_image_ops.convertPixelsToRgba(pixels: tilePixels);
  }

  Uint8List copySurfaceRgba() {
    final Uint32List pixels = ensureCompositePixels();
    // The Rust side now handles both conversion to RGBA and Premultiply in one high-speed pass.
    return kIsWeb
        ? argbToPremultipliedRgba(pixels)
        : rust_image_ops.convertPixelsToRgba(pixels: pixels);
  }

  List<RasterIntRect> fullSurfaceTileRects() {
    final List<RasterIntRect> tiles = <RasterIntRect>[];
    final int horizontalTiles = (_width + tileSize - 1) ~/ tileSize;
    final int verticalTiles = (_height + tileSize - 1) ~/ tileSize;
    for (int ty = 0; ty < verticalTiles; ty++) {
      for (int tx = 0; tx < horizontalTiles; tx++) {
        final int left = tx * tileSize;
        final int top = ty * tileSize;
        final int right = math.min(left + tileSize, _width);
        final int bottom = math.min(top + tileSize, _height);
        tiles.add(RasterIntRect(left, top, right, bottom));
      }
    }
    return tiles;
  }

  RasterIntRect clipRectToSurface(Rect rect) {
    final double effectiveLeft = rect.left;
    final double effectiveTop = rect.top;
    final double effectiveRight = rect.right;
    final double effectiveBottom = rect.bottom;
    final int left = math.max(0, effectiveLeft.floor());
    final int top = math.max(0, effectiveTop.floor());
    final int right = math.min(_width, effectiveRight.ceil());
    final int bottom = math.min(_height, effectiveBottom.ceil());
    if (left >= right || top >= bottom) {
      return const RasterIntRect(0, 0, 0, 0);
    }
    return RasterIntRect(left, top, right, bottom);
  }

  Color colorAtComposite(
    Offset position,
    List<BitmapLayerState> layers, {
    String? translatingLayerId,
    bool preferRealtime = false,
  }) {
    final int x = position.dx.floor();
    final int y = position.dy.floor();
    if (x < 0 || x >= _width || y < 0 || y >= _height) {
      return const Color(0x00000000);
    }
    final int index = y * _width + x;
    final Uint32List? pixels = preferRealtime ? null : _compositePixels;
    if (pixels != null && pixels.length > index) {
      return BitmapSurface.decodeColor(pixels[index]);
    }
    int? color;
    for (final BitmapLayerState layer in layers) {
      if (!layer.visible) {
        continue;
      }
      if (translatingLayerId != null && layer.id == translatingLayerId) {
        continue;
      }
      final int src = layer.surface.pixels[index];
      if (color == null) {
        color = src;
      } else {
        color = blend_utils.blendArgb(color, src);
      }
    }
    return BitmapSurface.decodeColor(color ?? 0);
  }

  void _ensureBuffers() {
    _compositePixels ??= Uint32List(_width * _height);
  }

  void _enqueueDirtyTiles(Rect region) {
    final RasterIntRect clipped = clipRectToSurface(region);
    if (clipped.isEmpty) {
      return;
    }
    final int leftTile = clipped.left ~/ tileSize;
    final int rightTile = (clipped.right - 1) ~/ tileSize;
    final int topTile = clipped.top ~/ tileSize;
    final int bottomTile = (clipped.bottom - 1) ~/ tileSize;

    for (int ty = topTile; ty <= bottomTile; ty++) {
      for (int tx = leftTile; tx <= rightTile; tx++) {
        final int key = (ty << 20) | tx;
        if (!_pendingDirtyTileKeys.add(key)) {
          continue;
        }
        final int tileLeft = tx * tileSize;
        final int tileTop = ty * tileSize;
        final int tileRight = math.min(tileLeft + tileSize, _width);
        final int tileBottom = math.min(tileTop + tileSize, _height);
        _pendingDirtyTiles.add(
          RasterIntRect(tileLeft, tileTop, tileRight, tileBottom),
        );
      }
    }
  }

  static Future<T> _runGpuCompositeSerialized<T>(Future<T> Function() action) async {
    final Future<void> prev = _gpuCompositeSerial;
    final Future<void> prevOk = prev.catchError((_) {});
    final Completer<void> gate = Completer<void>();
    _gpuCompositeSerial = prevOk.whenComplete(() => gate.future);

    await prevOk;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  static bool _isGpuNeedsFullUploadError(Object error) {
    return error.toString().contains('GPU_COMPOSITOR_NEEDS_FULL_UPLOAD');
  }

  void _invalidateGpuLayerCache() {
    _gpuLayerCacheInitialized = false;
    _cachedLayerWidth = 0;
    _cachedLayerHeight = 0;
    _cachedLayerOrder = null;
    _cachedLayerRevisions.clear();
  }

  static bool _listEquals(List<String>? a, List<String>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    final int length = a.length;
    if (b.length != length) {
      return false;
    }
    for (int i = 0; i < length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
