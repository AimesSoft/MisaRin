import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../backend/canvas_raster_backend.dart';
import '../canvas/canvas_frame.dart';
import 'raster_frame.dart';
import 'raster_int_rect.dart';

import '../app/debug/backend_canvas_timeline.dart';

const bool _kDebugRasterTiles = bool.fromEnvironment(
  'MISA_RIN_DEBUG_RASTER_TILES',
  defaultValue: false,
);
const double _kFullSurfaceDirtyThreshold = 0.35;

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

  CanvasFrame? _frame;

  CanvasFrame? get frame => _frame;

  List<ui.Image> takePendingDisposals() {
    if (_pendingDisposals.isEmpty) {
      return const <ui.Image>[];
    }
    final List<ui.Image> result = List<ui.Image>.from(_pendingDisposals);
    _pendingDisposals.clear();
    return result;
  }

  Future<CanvasFrame?> updateTiles({
    required CanvasRasterBackend backend,
    required List<RasterIntRect> dirtyRegions,
    required bool fullSurface,
  }) async {
    bool forceFullSurface = fullSurface;
    if (!forceFullSurface && dirtyRegions.isNotEmpty) {
      final int surfacePixels = surfaceWidth * surfaceHeight;
      int dirtyPixels = 0;
      for (final RasterIntRect rect in dirtyRegions) {
        dirtyPixels += rect.width * rect.height;
        if (dirtyPixels >= surfacePixels) {
          break;
        }
      }
      if (surfacePixels > 0 &&
          dirtyPixels >= (surfacePixels * _kFullSurfaceDirtyThreshold)) {
        forceFullSurface = true;
      }
    }

    if (dirtyRegions.isEmpty && !forceFullSurface) {
      return _frame;
    }

    if (kDebugMode && _kDebugRasterTiles) {
      debugPrint(
        '[raster-tiles] updateTiles fullSurface=$forceFullSurface dirtyRegions=${dirtyRegions.length}',
      );
    }

    if (forceFullSurface) {
      for (final BitmapCanvasTile tile in _tiles.values) {
        _pendingDisposals.add(tile.image);
      }
      _tiles.clear();
    }

    final Iterable<RasterIntRect> targets = forceFullSurface
        ? backend.fullSurfaceTileRects()
        : dirtyRegions;
    if (targets.isEmpty) {
      return _frame;
    }

    if (kDebugMode && _kDebugRasterTiles) {
      int minLeft = 1 << 30;
      int minTop = 1 << 30;
      int maxRight = -1;
      int maxBottom = -1;
      int count = 0;
      for (final RasterIntRect rect in targets) {
        count++;
        minLeft = math.min(minLeft, rect.left);
        minTop = math.min(minTop, rect.top);
        maxRight = math.max(maxRight, rect.right);
        maxBottom = math.max(maxBottom, rect.bottom);
      }
      debugPrint(
        '[raster-tiles] targets=$count bounds=($minLeft,$minTop)-($maxRight,$maxBottom)',
      );
    }

    final Stopwatch sw = Stopwatch()..start();
    final bool useSurfaceBuffer = forceFullSurface && !backend.useTiledComposite;
    final int surfaceRowBytes = surfaceWidth * 4;
    Uint8List? surfaceRgba;
    final List<_PendingTile> uploads = <_PendingTile>[
      for (final RasterIntRect rect in targets)
        _PendingTile(
          rect: rect,
          bytes: useSurfaceBuffer ? null : backend.copyTileRgba(rect),
        ),
    ];
    if (useSurfaceBuffer) {
      surfaceRgba = backend.copySurfaceRgba();
    }
    final int copyTime = sw.elapsedMilliseconds;

    if (uploads.isEmpty) {
      return _frame;
    }

    final int startDecode = sw.elapsedMilliseconds;
    final List<_DecodedTile> decodedTiles = await Future.wait(
      uploads.map((_PendingTile tile) async {
        final Uint8List bytes;
        final int? rowBytes;
        if (useSurfaceBuffer) {
          bytes = _tileBytesViewFromSurface(
            surfaceRgba!,
            tile.rect,
            surfaceRowBytes,
          );
          rowBytes = surfaceRowBytes;
        } else {
          bytes = tile.bytes!;
          rowBytes = null;
        }
        final ui.Image image = await _decodeTile(
          bytes,
          tile.rect.width,
          tile.rect.height,
          rowBytes: rowBytes,
        );
        return _DecodedTile(rect: tile.rect, image: image);
      }),
    );
    final int decodeTime = sw.elapsedMilliseconds - startDecode;
    BackendCanvasTimeline.mark('tiles: copyPixels total took ${copyTime}ms, decodeImages total wait took ${decodeTime}ms');

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

  Future<ui.Image> _decodeTile(
    Uint8List bytes,
    int width,
    int height, {
    int? rowBytes,
  }) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
      rowBytes: rowBytes,
    );
    return completer.future;
  }

  Uint8List _tileBytesViewFromSurface(
    Uint8List surfaceRgba,
    RasterIntRect rect,
    int rowBytes,
  ) {
    final int byteOffset =
        ((rect.top * surfaceWidth) + rect.left) * 4;
    final int length =
        (rowBytes * (rect.height - 1)) + (rect.width * 4);
    return Uint8List.view(
      surfaceRgba.buffer,
      surfaceRgba.offsetInBytes + byteOffset,
      length,
    );
  }

  int _tileKeyForRect(RasterIntRect rect) {
    final int x = rect.left ~/ tileSize;
    final int y = rect.top ~/ tileSize;
    return (y << 16) ^ x;
  }
}

class _PendingTile {
  const _PendingTile({
    required this.rect,
    required this.bytes,
  });

  final RasterIntRect rect;
  final Uint8List? bytes;
}

class _DecodedTile {
  const _DecodedTile({
    required this.rect,
    required this.image,
  });

  final RasterIntRect rect;
  final ui.Image image;
}
