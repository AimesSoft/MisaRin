import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../bitmap_canvas/bitmap_blend_utils.dart' as blend_utils;
import '../bitmap_canvas/bitmap_canvas.dart';
import '../bitmap_canvas/raster_int_rect.dart';
import '../bitmap_canvas/tile_math.dart';
import '../canvas/canvas_backend.dart';
import '../canvas/canvas_composite_layer.dart';
import 'rust_wgpu_composite.dart' as rust_wgpu_composite;
import '../src/rust/api/image_ops.dart' as rust_image_ops;
import '../src/rust/rust_init.dart';

const bool _kDebugRustWgpuComposite =
    bool.fromEnvironment(
      'MISA_RIN_DEBUG_RUST_WGPU_COMPOSITE',
      defaultValue: false,
    ) ||
    bool.fromEnvironment('MISA_RIN_DEBUG_GPU_COMPOSITE', defaultValue: false);

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
    this.backend = CanvasBackend.rustWgpu,
    this.useTiledComposite = false,
  }) : _width = width,
       _height = height {
    _backendInstanceCount++;
  }

  static final Uint32List _emptyPixels = Uint32List(0);
  static Future<void>? _rustWgpuInitFuture;
  static Future<void> _rustWgpuCompositeSerial = Future<void>.value();
  static int _rustWgpuCompositeEpoch = 0;
  static int _backendInstanceCount = 0;

  int _width;
  int _height;
  final int tileSize;
  final CanvasBackend backend;
  final bool useTiledComposite;

  bool _disposed = false;

  bool _compositeDirty = true;
  bool _compositeInitialized = false;
  bool _pendingFullSurface = false;
  Rect? _pendingDirtyBounds;
  final List<RasterIntRect> _pendingDirtyTiles = <RasterIntRect>[];
  final Set<int> _pendingDirtyTileKeys = <int>{};

  Uint32List? _compositePixels;
  final Map<int, Uint32List> _compositeTiles = <int, Uint32List>{};

  int _knownRustWgpuCompositeEpoch = 0;
  bool _rustWgpuLayerCacheInitialized = false;
  int _cachedLayerWidth = 0;
  int _cachedLayerHeight = 0;
  List<String>? _cachedLayerOrder;
  final Map<String, int> _cachedLayerRevisions = <String, int>{};

  bool get isCompositeDirty => _compositeDirty;
  Uint32List? get compositePixels => _compositePixels;
  int get width => _width;
  int get height => _height;

  Uint32List? compositePixelsSnapshot({bool rebuildIfTiled = false}) {
    if (!useTiledComposite) {
      return _compositePixels;
    }
    if (!rebuildIfTiled) {
      return null;
    }
    if (_width <= 0 || _height <= 0) {
      return Uint32List(0);
    }
    final Uint32List pixels = Uint32List(_width * _height);
    for (final RasterIntRect rect in fullSurfaceTileRects()) {
      final Uint32List? tilePixels = _compositeTiles[_tileKeyForRect(rect)];
      if (tilePixels == null || tilePixels.isEmpty) {
        continue;
      }
      final int tileWidth = rect.width;
      for (int row = 0; row < rect.height; row++) {
        final int dstRow = (rect.top + row) * _width + rect.left;
        final int srcRow = row * tileWidth;
        pixels.setRange(dstRow, dstRow + tileWidth, tilePixels, srcRow);
      }
    }
    return pixels;
  }

  static Future<void> initRustWgpu() async {
    try {
      await _ensureRustWgpuInitialized();
    } catch (e) {
      throw Exception('Rust WGPU 初始化失败，无法运行: $e');
    }
  }

  static Future<void> prewarmRustWgpuEngine() async {
    await initRustWgpu();
    await _runRustWgpuCompositeSerialized(() async {
      try {
        // Perform a dummy 1x1 composite to trigger shader compilation and pipeline setup.
        await rust_wgpu_composite.rustWgpuCompositeLayers(
          layers: [],
          width: 1,
          height: 1,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Rust WGPU engine prewarm failed: $e');
        }
      }
    });
  }

  static Future<void> _ensureRustWgpuInitialized() {
    final Future<void>? existing = _rustWgpuInitFuture;
    if (existing != null) {
      return existing;
    }
    final Future<void> future = () async {
      await ensureRustInitialized();
      rust_wgpu_composite.rustWgpuCompositorInit();
    }();
    _rustWgpuInitFuture = future;
    return future.catchError((Object error, StackTrace stackTrace) {
      _rustWgpuInitFuture = null;
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
    required List<CanvasCompositeLayer> layers,
    required bool requiresFullSurface,
    List<RasterIntRect>? regions,
    String? translatingLayerId,
  }) async {
    if (_disposed) {
      return;
    }
    if (useTiledComposite) {
      await _compositeTilesPass(
        layers: layers,
        requiresFullSurface: requiresFullSurface,
        regions: regions,
        translatingLayerId: translatingLayerId,
      );
      return;
    }
    _ensureBuffers();
    if (!requiresFullSurface && (regions == null || regions.isEmpty)) {
      return;
    }

    await initRustWgpu();

    await _runRustWgpuCompositeSerialized(() async {
      final List<CanvasCompositeLayer> effectiveLayers =
          <CanvasCompositeLayer>[];
      for (final CanvasCompositeLayer layer in layers) {
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
      // IMPORTANT: `rustWgpuCompositeLayers` is async; while awaiting the Rust call,
      // other tasks (e.g. Rust WGPU brush strokes) can mutate layer pixels and bump
      // revisions. If we update `_cachedLayerRevisions` with the *latest*
      // revisions after the await, we may incorrectly treat the Rust WGPU compositor
      // cache as up-to-date and skip required uploads, leading to stale tiles
      // (visual "cuts" along tile boundaries).
      final List<int> revisionSnapshot = <int>[
        for (final CanvasCompositeLayer layer in effectiveLayers)
          layer.revision,
      ];

      final List<String> layerOrder = effectiveLayers
          .map((CanvasCompositeLayer layer) => layer.id)
          .toList(growable: false);

      final bool sameEpoch =
          _rustWgpuLayerCacheInitialized &&
          _knownRustWgpuCompositeEpoch == _rustWgpuCompositeEpoch;
      final bool sameCanvasSize =
          _cachedLayerWidth == _width && _cachedLayerHeight == _height;
      final bool sameOrder = _listEquals(_cachedLayerOrder, layerOrder);

      final bool allowIncrementalPixels =
          sameEpoch && sameCanvasSize && sameOrder;

      final bool debugComposite = kDebugMode && _kDebugRustWgpuComposite;
      final List<bool>? uploadFlags = debugComposite
          ? List<bool>.filled(effectiveLayers.length, false)
          : null;
      final List<int?>? cachedRevisionsAtDecision = debugComposite
          ? List<int?>.filled(effectiveLayers.length, null)
          : null;
      bool lastForceFullPixels = false;

      Future<Uint32List> runComposite({required bool forceFullPixels}) {
        lastForceFullPixels = forceFullPixels;
        final List<rust_wgpu_composite.RustWgpuLayerData> rustWgpuLayers =
            <rust_wgpu_composite.RustWgpuLayerData>[];
        if (kDebugMode && _kDebugRustWgpuComposite) {
          debugPrint(
            '[rust-wgpu-composite] size=${_width}x${_height} '
            'requiresFullSurface=$requiresFullSurface regions=${regions?.length ?? 0} '
            'layers=${effectiveLayers.length} '
            'sameEpoch=$sameEpoch sameCanvasSize=$sameCanvasSize sameOrder=$sameOrder '
            'allowIncremental=$allowIncrementalPixels forceFullPixels=$forceFullPixels',
          );
        }
        for (int i = 0; i < effectiveLayers.length; i++) {
          final CanvasCompositeLayer layer = effectiveLayers[i];
          final int layerRevision = revisionSnapshot[i];
          final int? cachedRevision = _cachedLayerRevisions[layer.id];
          cachedRevisionsAtDecision?[i] = cachedRevision;
          final bool pixelsUnchanged =
              cachedRevision != null && cachedRevision == layerRevision;
          final Uint32List pixels =
              (!forceFullPixels && allowIncrementalPixels && pixelsUnchanged)
              ? _emptyPixels
              : layer.pixels;
          uploadFlags?[i] = pixels.isNotEmpty;

          if (kDebugMode && _kDebugRustWgpuComposite) {
            debugPrint(
              '  layer id=${layer.id} revSnapshot=$layerRevision cached=${cachedRevision ?? -1} '
              'upload=${pixels.isNotEmpty} pixelsLen=${pixels.length} '
              'opacity=${layer.opacity.toStringAsFixed(3)} blend=${layer.blendMode.index} '
              'clip=${layer.clippingMask} visible=${layer.visible}',
            );
          }

          rustWgpuLayers.add(
            rust_wgpu_composite.RustWgpuLayerData(
              pixels: pixels,
              opacity: layer.opacity,
              blendModeIndex: layer.blendMode.index,
              visible: true,
              clippingMask: layer.clippingMask,
            ),
          );
        }

        return rust_wgpu_composite.rustWgpuCompositeLayers(
          layers: rustWgpuLayers,
          width: _width,
          height: _height,
        );
      }

      Uint32List result;
      try {
        result = await runComposite(forceFullPixels: false);
      } catch (e) {
        if (_isRustWgpuNeedsFullUploadError(e)) {
          if (kDebugMode && _kDebugRustWgpuComposite) {
            debugPrint('[rust-wgpu-composite] needs full upload, retrying...');
          }
          _invalidateRustWgpuLayerCache();
          result = await runComposite(forceFullPixels: true);
        } else {
          if (kDebugMode && _kDebugRustWgpuComposite) {
            debugPrint('[rust-wgpu-composite] error: $e');
          }
          _invalidateRustWgpuLayerCache();
          _rustWgpuCompositeEpoch++;
          _knownRustWgpuCompositeEpoch = _rustWgpuCompositeEpoch;
          rethrow;
        }
      }

      if (_disposed) {
        return;
      }
      Uint32List? composite = _compositePixels;
      if (composite == null) {
        if (kDebugMode) {
          debugPrint(
            '[rust-wgpu-composite] composite buffer cleared; skipping',
          );
        }
        _invalidateRustWgpuLayerCache();
        _rustWgpuCompositeEpoch++;
        _knownRustWgpuCompositeEpoch = _rustWgpuCompositeEpoch;
        return;
      }
      if (result.length != composite.length) {
        _invalidateRustWgpuLayerCache();
        _rustWgpuCompositeEpoch++;
        _knownRustWgpuCompositeEpoch = _rustWgpuCompositeEpoch;
        throw StateError(
          'Rust WGPU composite size mismatch: got ${result.length}, expected ${composite.length}',
        );
      }
      composite.setAll(0, result);

      _rustWgpuCompositeEpoch++;
      _knownRustWgpuCompositeEpoch = _rustWgpuCompositeEpoch;
      _rustWgpuLayerCacheInitialized = true;
      _cachedLayerWidth = _width;
      _cachedLayerHeight = _height;
      _cachedLayerOrder = layerOrder;
      for (int i = 0; i < effectiveLayers.length; i++) {
        final CanvasCompositeLayer layer = effectiveLayers[i];
        _cachedLayerRevisions[layer.id] = revisionSnapshot[i];
      }

      if (kDebugMode && _kDebugRustWgpuComposite) {
        for (int i = 0; i < effectiveLayers.length; i++) {
          final CanvasCompositeLayer layer = effectiveLayers[i];
          final int before = revisionSnapshot[i];
          final int now = layer.revision;
          if (now != before) {
            final bool wasUploaded = uploadFlags?[i] ?? false;
            final int? cached = cachedRevisionsAtDecision?[i];
            debugPrint(
              '[rust-wgpu-composite] layer ${layer.id} revision changed during composite: '
              '$before -> $now (will be handled next pass)',
            );
            if (!lastForceFullPixels &&
                allowIncrementalPixels &&
                !wasUploaded) {
              debugPrint(
                '[rust-wgpu-composite] layer ${layer.id} used cached pixels in this pass '
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

  Future<void> _compositeTilesPass({
    required List<CanvasCompositeLayer> layers,
    required bool requiresFullSurface,
    List<RasterIntRect>? regions,
    String? translatingLayerId,
  }) async {
    if (!requiresFullSurface && (regions == null || regions.isEmpty)) {
      return;
    }

    await initRustWgpu();

    final List<RasterIntRect> targetTiles = requiresFullSurface
        ? fullSurfaceTileRects()
        : List<RasterIntRect>.from(regions ?? const <RasterIntRect>[]);
    if (targetTiles.isEmpty) {
      return;
    }

    await _runRustWgpuCompositeSerialized(() async {
      final List<CanvasCompositeLayer> effectiveLayers =
          <CanvasCompositeLayer>[];
      for (final CanvasCompositeLayer layer in layers) {
        if (translatingLayerId != null && layer.id == translatingLayerId) {
          continue;
        }
        if (!layer.visible) {
          continue;
        }
        effectiveLayers.add(layer);
      }

      for (final RasterIntRect rect in targetTiles) {
        if (rect.isEmpty) {
          continue;
        }
        final Uint32List result = await _runTileComposite(
          layers: effectiveLayers,
          rect: rect,
        );
        _compositeTiles[_tileKeyForRect(rect)] = result;
      }

      if (requiresFullSurface) {
        _compositeInitialized = true;
      }
    });
  }

  Future<Uint32List> _runTileComposite({
    required List<CanvasCompositeLayer> layers,
    required RasterIntRect rect,
  }) async {
    if (layers.isEmpty) {
      return Uint32List(rect.width * rect.height);
    }
    final int width = rect.width;
    final int height = rect.height;
    final List<rust_wgpu_composite.RustWgpuLayerData> rustLayers =
        <rust_wgpu_composite.RustWgpuLayerData>[];
    for (final CanvasCompositeLayer layer in layers) {
      final Uint32List pixels = layer.readRect(rect);
      rustLayers.add(
        rust_wgpu_composite.RustWgpuLayerData(
          pixels: pixels,
          opacity: layer.opacity,
          blendModeIndex: layer.blendMode.index,
          visible: true,
          clippingMask: layer.clippingMask,
        ),
      );
    }
    return rust_wgpu_composite.rustWgpuCompositeLayers(
      layers: rustLayers,
      width: width,
      height: height,
    );
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (kDebugMode) {
      debugPrint(
        '[raster_backend] dispose backend=$backend size=${_width}x${_height} '
        'compositeInitialized=$_compositeInitialized instanceCount=$_backendInstanceCount',
      );
    }

    _invalidateRustWgpuLayerCache();
    _compositePixels = null;
    _compositeTiles.clear();

    if (_backendInstanceCount > 0) {
      _backendInstanceCount--;
    }
    if (_backendInstanceCount != 0) {
      return;
    }

    final Future<void>? initFuture = _rustWgpuInitFuture;
    if (initFuture == null) {
      return;
    }
    await _runRustWgpuCompositeSerialized(() async {
      try {
        await initFuture;
        rust_wgpu_composite.rustWgpuCompositorDispose();
      } catch (_) {}
    });
    _rustWgpuInitFuture = null;
    _rustWgpuCompositeEpoch = 0;
    _rustWgpuCompositeSerial = Future<void>.value();
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
    if (useTiledComposite) {
      final Uint32List? tilePixels = _compositeTiles[_tileKeyForRect(rect)];
      if (tilePixels == null) {
        return Uint8List(rect.width * rect.height * 4);
      }
      return rust_image_ops.convertPixelsToRgba(pixels: tilePixels);
    }
    final Uint32List pixels = ensureCompositePixels();
    final int tileWidth = rect.width;
    final int tileHeight = rect.height;
    final int surfaceWidth = _width;

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

    return rust_image_ops.convertPixelsToRgba(pixels: tilePixels);
  }

  Uint8List copySurfaceRgba() {
    if (!useTiledComposite) {
      final Uint32List pixels = ensureCompositePixels();
      return rust_image_ops.convertPixelsToRgba(pixels: pixels);
    }
    final int totalPixels = _width * _height;
    final Uint8List rgba = Uint8List(totalPixels * 4);
    for (final RasterIntRect rect in fullSurfaceTileRects()) {
      final Uint32List? tilePixels = _compositeTiles[_tileKeyForRect(rect)];
      if (tilePixels == null || tilePixels.isEmpty) {
        continue;
      }
      final Uint8List tileRgba = rust_image_ops.convertPixelsToRgba(
        pixels: tilePixels,
      );
      final int tileWidth = rect.width;
      final int rowBytes = tileWidth * 4;
      for (int row = 0; row < rect.height; row++) {
        final int dstRow = (rect.top + row) * _width + rect.left;
        final int dstOffset = dstRow * 4;
        final int srcOffset = row * rowBytes;
        rgba.setRange(dstOffset, dstOffset + rowBytes, tileRgba, srcOffset);
      }
    }
    return rgba;
  }

  Uint32List readCompositeRect(RasterIntRect rect) {
    if (rect.isEmpty) {
      return Uint32List(0);
    }
    final int rectWidth = rect.width;
    final int rectHeight = rect.height;
    final Uint32List buffer = Uint32List(rectWidth * rectHeight);
    if (!useTiledComposite) {
      final Uint32List? pixels = _compositePixels;
      if (pixels == null || pixels.isEmpty) {
        return buffer;
      }
      for (int row = 0; row < rectHeight; row++) {
        final int srcRow = (rect.top + row) * _width + rect.left;
        final int dstRow = row * rectWidth;
        buffer.setRange(dstRow, dstRow + rectWidth, pixels, srcRow);
      }
      return buffer;
    }

    final int startTx = tileIndexForCoord(rect.left, tileSize);
    final int endTx = tileIndexForCoord(rect.right - 1, tileSize);
    final int startTy = tileIndexForCoord(rect.top, tileSize);
    final int endTy = tileIndexForCoord(rect.bottom - 1, tileSize);

    for (int ty = startTy; ty <= endTy; ty++) {
      for (int tx = startTx; tx <= endTx; tx++) {
        final int tileLeft = tx * tileSize;
        final int tileTop = ty * tileSize;
        final int tileRight = math.min(tileLeft + tileSize, _width);
        final int tileBottom = math.min(tileTop + tileSize, _height);
        final int left = rect.left > tileLeft ? rect.left : tileLeft;
        final int top = rect.top > tileTop ? rect.top : tileTop;
        final int right = rect.right < tileRight ? rect.right : tileRight;
        final int bottom = rect.bottom < tileBottom ? rect.bottom : tileBottom;
        if (left >= right || top >= bottom) {
          continue;
        }
        final Uint32List? tilePixels = _compositeTiles[_tileKey(tx, ty)];
        if (tilePixels == null || tilePixels.isEmpty) {
          continue;
        }
        final int tileWidth = tileRight - tileLeft;
        final int copyWidth = right - left;
        final int copyHeight = bottom - top;
        for (int row = 0; row < copyHeight; row++) {
          final int srcRow =
              (top - tileTop + row) * tileWidth + (left - tileLeft);
          final int dstRow =
              (top - rect.top + row) * rectWidth + (left - rect.left);
          buffer.setRange(dstRow, dstRow + copyWidth, tilePixels, srcRow);
        }
      }
    }
    return buffer;
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
    List<CanvasCompositeLayer> layers, {
    String? translatingLayerId,
    bool preferRealtime = false,
  }) {
    final int x = position.dx.floor();
    final int y = position.dy.floor();
    if (x < 0 || x >= _width || y < 0 || y >= _height) {
      return const Color(0x00000000);
    }
    final int index = y * _width + x;
    if (!preferRealtime) {
      if (useTiledComposite) {
        final int tx = tileIndexForCoord(x, tileSize);
        final int ty = tileIndexForCoord(y, tileSize);
        final int tileLeft = tx * tileSize;
        final int tileTop = ty * tileSize;
        final int tileRight = math.min(tileLeft + tileSize, _width);
        final int tileBottom = math.min(tileTop + tileSize, _height);
        final RasterIntRect tileRect = RasterIntRect(
          tileLeft,
          tileTop,
          tileRight,
          tileBottom,
        );
        final Uint32List? tilePixels =
            _compositeTiles[_tileKeyForRect(tileRect)];
        if (tilePixels != null && tilePixels.isNotEmpty) {
          final int localX = x - tileRect.left;
          final int localY = y - tileRect.top;
          if (localX >= 0 &&
              localY >= 0 &&
              localX < tileRect.width &&
              localY < tileRect.height) {
            final int localIndex = localY * tileRect.width + localX;
            if (localIndex >= 0 && localIndex < tilePixels.length) {
              return BitmapSurface.decodeColor(tilePixels[localIndex]);
            }
          }
        }
      } else {
        final Uint32List? pixels = _compositePixels;
        if (pixels != null && pixels.length > index) {
          return BitmapSurface.decodeColor(pixels[index]);
        }
      }
    }
    int? color;
    final RasterIntRect pixelRect = RasterIntRect(x, y, x + 1, y + 1);
    for (final CanvasCompositeLayer layer in layers) {
      if (!layer.visible) {
        continue;
      }
      if (translatingLayerId != null && layer.id == translatingLayerId) {
        continue;
      }
      final Uint32List sample = layer.readRect(pixelRect);
      final int src = sample.isEmpty ? 0 : sample[0];
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
    final int leftTile = tileIndexForCoord(clipped.left, tileSize);
    final int rightTile = tileIndexForCoord(clipped.right - 1, tileSize);
    final int topTile = tileIndexForCoord(clipped.top, tileSize);
    final int bottomTile = tileIndexForCoord(clipped.bottom - 1, tileSize);

    for (int ty = topTile; ty <= bottomTile; ty++) {
      for (int tx = leftTile; tx <= rightTile; tx++) {
        final int key = _tileKey(tx, ty);
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

  int _tileKey(int tx, int ty) => (tx << 32) ^ (ty & 0xffffffff);

  int _tileKeyForRect(RasterIntRect rect) {
    final int tx = tileIndexForCoord(rect.left, tileSize);
    final int ty = tileIndexForCoord(rect.top, tileSize);
    return _tileKey(tx, ty);
  }

  static Future<T> _runRustWgpuCompositeSerialized<T>(
    Future<T> Function() action,
  ) async {
    final Future<void> prev = _rustWgpuCompositeSerial;
    final Future<void> prevOk = prev.catchError((_) {});
    final Completer<void> gate = Completer<void>();
    _rustWgpuCompositeSerial = prevOk.whenComplete(() => gate.future);

    await prevOk;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  static bool _isRustWgpuNeedsFullUploadError(Object error) {
    return error.toString().contains('GPU_COMPOSITOR_NEEDS_FULL_UPLOAD');
  }

  void _invalidateRustWgpuLayerCache() {
    _rustWgpuLayerCacheInitialized = false;
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
