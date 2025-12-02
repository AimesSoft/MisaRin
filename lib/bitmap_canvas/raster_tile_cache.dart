import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../backend/canvas_raster_backend.dart';
import 'raster_frame.dart';
import 'raster_int_rect.dart';

class RasterTileCache {
  RasterTileCache({
    required this.surfaceWidth,
    required this.surfaceHeight,
    required this.tileSize,
  });

  final int surfaceWidth;
  final int surfaceHeight;
  final int tileSize;

  final Map<int, BitmapCanvasTile> _tiles = HashMap<int, BitmapCanvasTile>();
  final List<ui.Image> _pendingDisposals = <ui.Image>[];
  int _generation = 0;

  BitmapCanvasFrame? _frame;

  BitmapCanvasFrame? get frame => _frame;

  List<ui.Image> takePendingDisposals() {
    if (_pendingDisposals.isEmpty) {
      return const <ui.Image>[];
    }
    final List<ui.Image> result = List<ui.Image>.from(_pendingDisposals);
    _pendingDisposals.clear();
    return result;
  }

  Future<BitmapCanvasFrame?> updateTiles({
    required CanvasRasterBackend backend,
    required List<RasterIntRect> dirtyRegions,
    required bool fullSurface,
  }) async {
    if (dirtyRegions.isEmpty && !fullSurface) {
      return _frame;
    }

    if (fullSurface) {
      for (final BitmapCanvasTile tile in _tiles.values) {
        _pendingDisposals.add(tile.image);
      }
      _tiles.clear();
    }

    final Iterable<RasterIntRect> targets = fullSurface
        ? backend.fullSurfaceTileRects()
        : dirtyRegions;
    if (targets.isEmpty) {
      return _frame;
    }

    final List<_PendingTile> uploads = <_PendingTile>[
      for (final RasterIntRect rect in targets)
        _PendingTile(rect: rect, bytes: backend.copyTileRgba(rect)),
    ];

    if (uploads.isEmpty) {
      return _frame;
    }

    final List<_DecodedTile> decodedTiles = await Future.wait(
      uploads.map((_PendingTile tile) async {
        final ui.Image image = await _decodeTile(
          tile.bytes,
          tile.rect.width,
          tile.rect.height,
        );
        return _DecodedTile(rect: tile.rect, image: image);
      }),
    );

    for (final _DecodedTile tile in decodedTiles) {
      final int key = _tileKeyForRect(tile.rect);
      final BitmapCanvasTile? previous = _tiles[key];
      if (previous != null) {
        _pendingDisposals.add(previous.image);
      }
      final BitmapCanvasTile updated = BitmapCanvasTile(
        rect: tile.rect,
        image: tile.image,
      );
      _tiles[key] = updated;
    }

    if (_tiles.isEmpty) {
      return _frame;
    }

    _generation++;
    _frame = BitmapCanvasFrame(
      tiles: UnmodifiableListView<BitmapCanvasTile>(
        _tiles.values.toList(growable: false),
      ),
      surfaceWidth: surfaceWidth,
      surfaceHeight: surfaceHeight,
      generation: _generation,
    );
    return _frame;
  }

  void dispose() {
    for (final BitmapCanvasTile tile in _tiles.values) {
      tile.image.dispose();
    }
    _tiles.clear();
    _frame = null;
    for (final ui.Image image in _pendingDisposals) {
      image.dispose();
    }
    _pendingDisposals.clear();
  }

  Future<ui.Image> _decodeTile(Uint8List bytes, int width, int height) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  int _tileKeyForRect(RasterIntRect rect) {
    final int x = rect.left ~/ tileSize;
    final int y = rect.top ~/ tileSize;
    return (y << 16) ^ x;
  }
}

class _PendingTile {
  const _PendingTile({required this.rect, required this.bytes});

  final RasterIntRect rect;
  final Uint8List bytes;
}

class _DecodedTile {
  const _DecodedTile({required this.rect, required this.image});

  final RasterIntRect rect;
  final ui.Image image;
}
