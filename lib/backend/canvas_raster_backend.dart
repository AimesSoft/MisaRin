import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../bitmap_canvas/bitmap_blend_utils.dart' as blend_utils;
import '../bitmap_canvas/bitmap_canvas.dart';
import '../bitmap_canvas/bitmap_layer_state.dart';
import '../bitmap_canvas/raster_int_rect.dart';
import 'canvas_composite_worker.dart';
import 'rgba_utils.dart';

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
    bool multithreaded = false,
  }) : _width = width,
       _height = height,
       _multithreaded = multithreaded;

  final int _width;
  final int _height;
  final int tileSize;
  final bool _multithreaded;
  CanvasCompositeWorker? _worker;

  bool _compositeDirty = true;
  bool _compositeInitialized = false;
  bool _pendingFullSurface = false;
  Rect? _pendingDirtyBounds;
  final List<RasterIntRect> _pendingDirtyTiles = <RasterIntRect>[];
  final Set<int> _pendingDirtyTileKeys = <int>{};

  // New state for tracking layer dirtiness
  final Set<String> _pendingDirtyLayerIds = <String>{};
  bool _pendingAllLayersDirty = false;
  final Set<String> _workerKnownLayerIds = <String>{};

  Uint32List? _compositePixels;
  Uint8List? _clipMaskBuffer;

  bool get isCompositeDirty => _compositeDirty;
  Uint32List? get compositePixels => _compositePixels;
  int get width => _width;
  int get height => _height;

  void markDirty({Rect? region, String? layerId, bool pixelsDirty = true}) {
    _compositeDirty = true;
    if (pixelsDirty) {
      if (layerId != null) {
        _pendingDirtyLayerIds.add(layerId);
      } else {
        _pendingAllLayersDirty = true;
      }
    }

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
    if (_multithreaded) {
      await _compositeWithWorker(
        layers: layers,
        requiresFullSurface: requiresFullSurface,
        regions: regions,
        translatingLayerId: translatingLayerId,
      );
      return;
    }
    _ensureBuffers();
    final List<RasterIntRect> areas;
    if (requiresFullSurface) {
      areas = <RasterIntRect>[RasterIntRect(0, 0, _width, _height)];
    } else {
      if (regions == null || regions.isEmpty) {
        return;
      }
      areas = regions;
    }
    if (areas.isEmpty) {
      return;
    }

    final Uint32List composite = _compositePixels!;
    final Uint8List clipMask = _ensureClipMask();
    clipMask.fillRange(0, clipMask.length, 0);

    for (final RasterIntRect area in areas) {
      if (area.isEmpty) {
        continue;
      }
      for (int y = area.top; y < area.bottom; y++) {
        final int rowOffset = y * _width;
        for (int x = area.left; x < area.right; x++) {
          final int index = rowOffset + x;
          int color = 0;
          bool initialized = false;
          for (final BitmapLayerState layer in layers) {
            if (!layer.visible) {
              continue;
            }
            if (translatingLayerId != null && layer.id == translatingLayerId) {
              continue;
            }
            final double layerOpacity = _clampUnit(layer.opacity);
            if (layerOpacity <= 0) {
              if (!layer.clippingMask) {
                clipMask[index] = 0;
              }
              continue;
            }
            final int src = layer.surface.pixels[index];
            final int srcA = (src >> 24) & 0xff;
            if (srcA == 0) {
              if (!layer.clippingMask) {
                clipMask[index] = 0;
              }
              continue;
            }

            double totalOpacity = layerOpacity;
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

            final int effectiveColor = (effectiveA << 24) | (src & 0x00FFFFFF);
            if (!initialized) {
              color = effectiveColor;
              initialized = true;
            } else {
              color = blend_utils.blendWithMode(
                color,
                effectiveColor,
                layer.blendMode,
                index,
              );
            }
          }

          if (!initialized) {
            composite[index] = 0;
            continue;
          }

          composite[index] = color;
        }
      }
    }

    if (requiresFullSurface) {
      _compositeInitialized = true;
    }
  }

  Future<void> dispose() async {
    if (_worker != null) {
      await _worker!.dispose();
      _worker = null;
    }
  }

  Future<void> _compositeWithWorker({
    required List<BitmapLayerState> layers,
    required bool requiresFullSurface,
    List<RasterIntRect>? regions,
    String? translatingLayerId,
  }) async {
    final List<RasterIntRect> areas = requiresFullSurface
        ? <RasterIntRect>[RasterIntRect(0, 0, _width, _height)]
        : (regions ?? const <RasterIntRect>[]);

    _worker ??= CanvasCompositeWorker();

    // 1. Sync layers to worker
    for (final BitmapLayerState layer in layers) {
      if (!_workerKnownLayerIds.contains(layer.id)) {
        // New layer, sync full surface
        final Uint32List? pixels = layer.surface.isClean
            ? null
            : layer.surface.pixels;
        await _worker!.updateLayer(
          id: layer.id,
          width: _width,
          height: _height,
          pixels: pixels,
        );
        _workerKnownLayerIds.add(layer.id);
      } else if (_pendingAllLayersDirty ||
          _pendingDirtyLayerIds.contains(layer.id)) {
        // Dirty layer, sync patches
        if (areas.isNotEmpty) {
          for (final RasterIntRect area in areas) {
            await _worker!.updateLayer(
              id: layer.id,
              width: _width,
              height: _height,
              pixels: _copyLayerRegion(layer.surface, area),
              rect: area,
            );
          }
        }
      }
    }

    // Reset dirtiness
    _pendingDirtyLayerIds.clear();
    _pendingAllLayersDirty = false;

    if (areas.isEmpty) {
      return;
    }

    final List<CompositeRegionPayload> payloadRegions = _buildCompositeWork(
      areas,
      layers,
    );

    final List<CompositeRegionResult> results = await _worker!.composite(
      CompositeWorkPayload(
        width: _width,
        height: _height,
        regions: payloadRegions,
        requiresFullSurface: requiresFullSurface,
        translatingLayerId: translatingLayerId,
      ),
    );
    if (results.isEmpty) {
      return;
    }
    _ensureBuffers();
    final Uint32List composite = _compositePixels!;
    for (final CompositeRegionResult region in results) {
      _writeRegion(region.rect, region.pixels, composite);
    }
    if (requiresFullSurface) {
      _compositeInitialized = true;
    }
  }

  void _writeRegion(
    RasterIntRect rect,
    Uint32List pixels,
    Uint32List destination,
  ) {
    final int regionWidth = rect.width;
    final int regionHeight = rect.height;
    for (int row = 0; row < regionHeight; row++) {
      final int destOffset = (rect.top + row) * _width + rect.left;
      final int srcOffset = row * regionWidth;
      destination.setRange(
        destOffset,
        destOffset + regionWidth,
        pixels,
        srcOffset,
      );
    }
  }

  void completeCompositePass() {
    _compositeDirty = _pendingFullSurface || _pendingDirtyBounds != null;
  }

  Uint32List ensureCompositePixels() {
    _ensureBuffers();
    return _compositePixels!;
  }

  Uint8List _ensureClipMask() {
    return _clipMaskBuffer ??= Uint8List(_width * _height);
  }

  void resetClipMask() {
    _clipMaskBuffer = null;
  }

  List<CompositeRegionPayload> _buildCompositeWork(
    List<RasterIntRect> areas,
    List<BitmapLayerState> layers,
  ) {
    return <CompositeRegionPayload>[
      for (final RasterIntRect area in areas)
        CompositeRegionPayload(
          rect: area,
          layers: <CompositeRegionLayerRef>[
            for (final BitmapLayerState layer in layers)
              CompositeRegionLayerRef(
                id: layer.id,
                visible: layer.visible,
                opacity: layer.opacity,
                clippingMask: layer.clippingMask,
                blendModeIndex: layer.blendMode.index,
              ),
          ],
        ),
    ];
  }

  Uint32List _copyLayerRegion(BitmapSurface surface, RasterIntRect rect) {
    final int regionWidth = rect.width;
    final int regionHeight = rect.height;
    final Uint32List pixels = Uint32List(regionWidth * regionHeight);
    final Uint32List source = surface.pixels;
    for (int row = 0; row < regionHeight; row++) {
      final int srcOffset = (rect.top + row) * _width + rect.left;
      final int dstOffset = row * regionWidth;
      pixels.setRange(dstOffset, dstOffset + regionWidth, source, srcOffset);
    }
    return pixels;
  }

  Uint8List copyTileRgba(RasterIntRect rect) {
    final Uint32List pixels = ensureCompositePixels();
    final int tileWidth = rect.width;
    final int tileHeight = rect.height;
    final Uint8List rgba = Uint8List(tileWidth * tileHeight * 4);
    for (int row = 0; row < tileHeight; row++) {
      final int srcRow = (rect.top + row) * _width + rect.left;
      final int dstRow = row * tileWidth;
      for (int col = 0; col < tileWidth; col++) {
        final int argb = pixels[srcRow + col];
        final int offset = (dstRow + col) * 4;
        rgba[offset] = (argb >> 16) & 0xff;
        rgba[offset + 1] = (argb >> 8) & 0xff;
        rgba[offset + 2] = argb & 0xff;
        rgba[offset + 3] = (argb >> 24) & 0xff;
      }
    }
    premultiplyRgbaInPlace(rgba);
    return rgba;
  }

  Uint8List copySurfaceRgba() {
    final Uint32List pixels = ensureCompositePixels();
    final Uint8List rgba = Uint8List(pixels.length * 4);
    for (int i = 0; i < pixels.length; i++) {
      final int argb = pixels[i];
      final int offset = i * 4;
      rgba[offset] = (argb >> 16) & 0xff;
      rgba[offset + 1] = (argb >> 8) & 0xff;
      rgba[offset + 2] = argb & 0xff;
      rgba[offset + 3] = (argb >> 24) & 0xff;
    }
    premultiplyRgbaInPlace(rgba);
    return rgba;
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

  static double _clampUnit(double value) {
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
}
