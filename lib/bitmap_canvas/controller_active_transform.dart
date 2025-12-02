part of 'controller.dart';

void _translateActiveLayer(BitmapCanvasController controller, int dx, int dy) {
  if (controller._pendingActiveLayerTransformCleanup) {
    return;
  }
  final BitmapLayerState layer = controller._activeLayer;
  if (layer.locked || controller._selectionMask != null) {
    return;
  }
  if (controller._activeLayerTranslationSnapshot == null) {
    _startActiveLayerTransformSession(controller, layer);
  }
  if (controller._activeLayerTranslationSnapshot == null) {
    return;
  }
  if (dx == controller._activeLayerTranslationDx &&
      dy == controller._activeLayerTranslationDy) {
    return;
  }
  controller._activeLayerTranslationDx = dx;
  controller._activeLayerTranslationDy = dy;
  _updateActiveLayerTransformDirtyRegion(controller);
  controller.notifyListeners();
}

void _commitActiveLayerTranslation(BitmapCanvasController controller) {
  if (controller._activeLayerTranslationSnapshot == null) {
    return;
  }
  final Rect? dirtyRegion = controller._activeLayerTransformDirtyRegion;
  final String? layerId = controller._activeLayerTranslationId;
  _applyActiveLayerTranslation(controller);
  controller._pendingActiveLayerTransformCleanup = true;
  if (dirtyRegion != null) {
    controller._markDirty(
      region: dirtyRegion,
      layerId: layerId,
      pixelsDirty: true,
    );
  } else {
    controller._markDirty(layerId: layerId, pixelsDirty: true);
  }
}

void _cancelActiveLayerTranslation(BitmapCanvasController controller) {
  if (controller._activeLayerTranslationSnapshot == null) {
    return;
  }
  final Rect? dirtyRegion = controller._activeLayerTransformDirtyRegion;
  final String? layerId = controller._activeLayerTranslationId;
  _restoreActiveLayerSnapshot(controller);
  controller._pendingActiveLayerTransformCleanup = true;
  if (dirtyRegion != null) {
    controller._markDirty(
      region: dirtyRegion,
      layerId: layerId,
      pixelsDirty: true,
    );
  } else {
    controller._markDirty(layerId: layerId, pixelsDirty: true);
  }
}

Uint32List _ensureTranslationSnapshot(
  BitmapCanvasController controller,
  String layerId,
  Uint32List pixels,
) {
  final Uint32List? existing = controller._activeLayerTranslationSnapshot;
  if (existing != null && controller._activeLayerTranslationId == layerId) {
    return existing;
  }
  final Uint32List snapshot = Uint32List.fromList(pixels);
  controller._activeLayerTranslationSnapshot = snapshot;
  controller._activeLayerTranslationId = layerId;
  controller._activeLayerTranslationDx = 0;
  controller._activeLayerTranslationDy = 0;
  return snapshot;
}

void _startActiveLayerTransformSession(
  BitmapCanvasController controller,
  BitmapLayerState layer,
) {
  if (controller._pendingActiveLayerTransformCleanup) {
    return;
  }
  if (controller._clipLayerOverflow) {
    _startClippedLayerTransformSession(controller, layer);
    return;
  }
  _startOverflowLayerTransformSession(controller, layer);
}

void _startClippedLayerTransformSession(
  BitmapCanvasController controller,
  BitmapLayerState layer,
) {
  final Uint32List snapshot = _ensureTranslationSnapshot(
    controller,
    layer.id,
    layer.surface.pixels,
  );
  final int width = layer.surface.width;
  final int height = layer.surface.height;
  final Rect? bounds = _computePixelBounds(snapshot, width, height);
  final Rect fallbackBounds = Rect.fromLTWH(
    0,
    0,
    width.toDouble(),
    height.toDouble(),
  );
  controller._activeLayerTransformBounds = bounds ?? fallbackBounds;
  controller._activeLayerTransformDirtyRegion = bounds;
  controller._activeLayerTransformSnapshotWidth = width;
  controller._activeLayerTransformSnapshotHeight = height;
  controller._activeLayerTransformOriginX = 0;
  controller._activeLayerTransformOriginY = 0;
  layer.surface.pixels.fillRange(0, layer.surface.pixels.length, 0);
  if (bounds != null) {
    controller._markDirty(region: bounds, layerId: layer.id, pixelsDirty: true);
  } else {
    controller._markDirty(layerId: layer.id, pixelsDirty: true);
  }
  _prepareActiveLayerTransformPreview(controller, layer, snapshot);
}

void _startOverflowLayerTransformSession(
  BitmapCanvasController controller,
  BitmapLayerState layer,
) {
  final _LayerOverflowStore overflowStore =
      controller._layerOverflowStores[layer.id] ?? _LayerOverflowStore();
  final _LayerTransformSnapshot snapshot = _buildOverflowTransformSnapshot(
    controller,
    layer,
    overflowStore,
  );
  controller._activeLayerTranslationSnapshot = snapshot.pixels;
  controller._activeLayerTranslationId = layer.id;
  controller._activeLayerTranslationDx = 0;
  controller._activeLayerTranslationDy = 0;
  controller._activeLayerTransformSnapshotWidth = snapshot.width;
  controller._activeLayerTransformSnapshotHeight = snapshot.height;
  controller._activeLayerTransformOriginX = snapshot.originX;
  controller._activeLayerTransformOriginY = snapshot.originY;
  Rect? transformBounds = _computePixelBounds(
    layer.surface.pixels,
    controller._width,
    controller._height,
  );
  if (transformBounds == null) {
    final Rect? snapshotBounds = _computePixelBounds(
      snapshot.pixels,
      snapshot.width,
      snapshot.height,
    );
    if (snapshotBounds != null) {
      transformBounds = snapshotBounds.shift(
        Offset(snapshot.originX.toDouble(), snapshot.originY.toDouble()),
      );
    }
  }
  transformBounds ??= Rect.fromLTWH(
    snapshot.originX.toDouble(),
    snapshot.originY.toDouble(),
    snapshot.width.toDouble(),
    snapshot.height.toDouble(),
  );
  controller._activeLayerTransformBounds = transformBounds;
  controller._activeLayerTransformDirtyRegion = transformBounds;
  layer.surface.pixels.fillRange(0, layer.surface.pixels.length, 0);
  controller._markDirty(layerId: layer.id, pixelsDirty: true);
  _prepareActiveLayerTransformPreview(controller, layer, snapshot.pixels);
}

Rect? _computePixelBounds(Uint32List pixels, int width, int height) {
  int minX = width;
  int minY = height;
  int maxX = -1;
  int maxY = -1;
  for (int y = 0; y < height; y++) {
    final int rowOffset = y * width;
    for (int x = 0; x < width; x++) {
      final int argb = pixels[rowOffset + x];
      if ((argb >> 24) == 0) {
        continue;
      }
      if (x < minX) {
        minX = x;
      }
      if (x > maxX) {
        maxX = x;
      }
      if (y < minY) {
        minY = y;
      }
      if (y > maxY) {
        maxY = y;
      }
    }
  }
  if (maxX < minX || maxY < minY) {
    return null;
  }
  return Rect.fromLTRB(
    minX.toDouble(),
    minY.toDouble(),
    (maxX + 1).toDouble(),
    (maxY + 1).toDouble(),
  );
}

void _prepareActiveLayerTransformPreview(
  BitmapCanvasController controller,
  BitmapLayerState layer,
  Uint32List snapshot,
) {
  if (controller._activeLayerTransformPreparing) {
    return;
  }
  final int snapshotWidth = controller._activeLayerTransformSnapshotWidth;
  final int snapshotHeight = controller._activeLayerTransformSnapshotHeight;
  if (snapshotWidth <= 0 || snapshotHeight <= 0) {
    return;
  }
  controller._activeLayerTransformPreparing = true;
  final Uint8List rgba = BitmapCanvasController._pixelsToRgba(snapshot);
  controller._activeLayerTransformImage?.dispose();
  ui.decodeImageFromPixels(
    rgba,
    snapshotWidth,
    snapshotHeight,
    ui.PixelFormat.rgba8888,
    (ui.Image image) {
      if (controller._activeLayerTranslationSnapshot == null ||
          controller._activeLayerTranslationId != layer.id) {
        controller._activeLayerTransformPreparing = false;
        image.dispose();
        return;
      }
      controller._activeLayerTransformImage?.dispose();
      controller._activeLayerTransformImage = image;
      controller._activeLayerTransformPreparing = false;
      controller.notifyListeners();
    },
  );
}

void _applyActiveLayerTranslation(BitmapCanvasController controller) {
  final Uint32List? snapshot = controller._activeLayerTranslationSnapshot;
  final String? id = controller._activeLayerTranslationId;
  if (snapshot == null || id == null) {
    return;
  }
  if (controller._clipLayerOverflow) {
    _applyClippedLayerTranslation(controller, snapshot, id);
  } else {
    _applyOverflowLayerTranslation(controller, snapshot, id);
  }
}

void _applyClippedLayerTranslation(
  BitmapCanvasController controller,
  Uint32List snapshot,
  String layerId,
) {
  final BitmapLayerState target = controller._layers.firstWhere(
    (layer) => layer.id == layerId,
    orElse: () => controller._activeLayer,
  );
  final Uint32List pixels = target.surface.pixels;
  final int width = target.surface.width;
  final int height = target.surface.height;
  final int dx = controller._activeLayerTranslationDx;
  final int dy = controller._activeLayerTranslationDy;
  pixels.fillRange(0, pixels.length, 0);
  for (int y = 0; y < height; y++) {
    final int srcY = y - dy;
    if (srcY < 0 || srcY >= height) {
      continue;
    }
    for (int x = 0; x < width; x++) {
      final int srcX = x - dx;
      if (srcX < 0 || srcX >= width) {
        continue;
      }
      final int srcIndex = srcY * width + srcX;
      final int destIndex = y * width + x;
      pixels[destIndex] = snapshot[srcIndex];
    }
  }
  controller._layerOverflowStores[layerId]?.clear();
  _resetActiveLayerTranslationState(controller);
}

void _applyOverflowLayerTranslation(
  BitmapCanvasController controller,
  Uint32List snapshot,
  String layerId,
) {
  final BitmapLayerState target = controller._layers.firstWhere(
    (layer) => layer.id == layerId,
    orElse: () => controller._activeLayer,
  );
  final int snapshotWidth = controller._activeLayerTransformSnapshotWidth;
  final int snapshotHeight = controller._activeLayerTransformSnapshotHeight;
  if (snapshotWidth <= 0 || snapshotHeight <= 0) {
    _resetActiveLayerTranslationState(controller);
    return;
  }
  final int originX = controller._activeLayerTransformOriginX;
  final int originY = controller._activeLayerTransformOriginY;
  final int dx = controller._activeLayerTranslationDx;
  final int dy = controller._activeLayerTranslationDy;
  final int canvasWidth = controller._width;
  final int canvasHeight = controller._height;
  final Uint32List pixels = target.surface.pixels;
  pixels.fillRange(0, pixels.length, 0);
  final _LayerOverflowBuilder overflowBuilder = _LayerOverflowBuilder();
  for (int sy = 0; sy < snapshotHeight; sy++) {
    final int canvasY = originY + sy + dy;
    final bool insideY = canvasY >= 0 && canvasY < canvasHeight;
    final int rowOffset = sy * snapshotWidth;
    for (int sx = 0; sx < snapshotWidth; sx++) {
      final int color = snapshot[rowOffset + sx];
      if ((color >> 24) == 0) {
        continue;
      }
      final int canvasX = originX + sx + dx;
      if (insideY && canvasX >= 0 && canvasX < canvasWidth) {
        final int destIndex = canvasY * canvasWidth + canvasX;
        pixels[destIndex] = color;
      } else {
        overflowBuilder.addPixel(canvasX, canvasY, color);
      }
    }
  }
  final _LayerOverflowStore overflowStore = overflowBuilder.build();
  if (!overflowStore.isEmpty) {
    controller._layerOverflowStores[layerId] = overflowStore;
  } else if (controller._layerOverflowStores.containsKey(layerId)) {
    controller._layerOverflowStores[layerId]!.clear();
  }
  _resetActiveLayerTranslationState(controller);
}

void _restoreOverflowLayerSnapshot(
  BitmapCanvasController controller,
  Uint32List snapshot,
  String layerId,
) {
  final BitmapLayerState target = controller._layers.firstWhere(
    (layer) => layer.id == layerId,
    orElse: () => controller._activeLayer,
  );
  final int snapshotWidth = controller._activeLayerTransformSnapshotWidth;
  final int snapshotHeight = controller._activeLayerTransformSnapshotHeight;
  if (snapshotWidth <= 0 || snapshotHeight <= 0) {
    _resetActiveLayerTranslationState(controller);
    return;
  }
  final int originX = controller._activeLayerTransformOriginX;
  final int originY = controller._activeLayerTransformOriginY;
  final int canvasWidth = controller._width;
  final int canvasHeight = controller._height;
  final Uint32List pixels = target.surface.pixels;
  pixels.fillRange(0, pixels.length, 0);
  for (int sy = 0; sy < snapshotHeight; sy++) {
    final int canvasY = originY + sy;
    if (canvasY < 0 || canvasY >= canvasHeight) {
      continue;
    }
    final int rowOffset = sy * snapshotWidth;
    for (int sx = 0; sx < snapshotWidth; sx++) {
      final int canvasX = originX + sx;
      if (canvasX < 0 || canvasX >= canvasWidth) {
        continue;
      }
      final int color = snapshot[rowOffset + sx];
      if ((color >> 24) == 0) {
        continue;
      }
      final int destIndex = canvasY * canvasWidth + canvasX;
      pixels[destIndex] = color;
    }
  }
  _resetActiveLayerTranslationState(controller);
}

_LayerTransformSnapshot _buildOverflowTransformSnapshot(
  BitmapCanvasController controller,
  BitmapLayerState layer,
  _LayerOverflowStore store,
) {
  int minX = 0;
  int minY = 0;
  int maxX = controller._width;
  int maxY = controller._height;
  if (!store.isEmpty) {
    minX = math.min(minX, store.minX);
    minY = math.min(minY, store.minY);
    maxX = math.max(maxX, store.maxX);
    maxY = math.max(maxY, store.maxY);
  }
  final int snapshotWidth = math.max(1, maxX - minX);
  final int snapshotHeight = math.max(1, maxY - minY);
  final Uint32List pixels = Uint32List(snapshotWidth * snapshotHeight);
  final int overlapLeft = math.max(0, minX);
  final int overlapRight = math.min(controller._width, maxX);
  final int overlapTop = math.max(0, minY);
  final int overlapBottom = math.min(controller._height, maxY);
  final Uint32List srcPixels = layer.surface.pixels;
  for (int y = overlapTop; y < overlapBottom; y++) {
    final int sy = y - minY;
    final int destinationOffset = sy * snapshotWidth;
    final int startX = overlapLeft - minX;
    final int srcOffset = y * controller._width + overlapLeft;
    final int length = overlapRight - overlapLeft;
    pixels.setRange(
      destinationOffset + startX,
      destinationOffset + startX + length,
      srcPixels,
      srcOffset,
    );
  }
  store.forEachSegment((int rowY, _LayerOverflowSegment segment) {
    final int sy = rowY - minY;
    if (sy < 0 || sy >= snapshotHeight) {
      return;
    }
    final int rowOffset = sy * snapshotWidth;
    final int segmentStart = segment.startX - minX;
    final int segmentEnd = segmentStart + segment.length;
    if (segmentEnd <= 0 || segmentStart >= snapshotWidth) {
      return;
    }
    final int copyStart = math.max(0, segmentStart);
    final int skip = copyStart - segmentStart;
    final int copyEnd = math.min(snapshotWidth, segmentEnd);
    final int copyLength = copyEnd - copyStart;
    if (copyLength <= 0) {
      return;
    }
    pixels.setRange(
      rowOffset + copyStart,
      rowOffset + copyStart + copyLength,
      segment.pixels,
      skip,
    );
  });
  return _LayerTransformSnapshot(
    pixels: pixels,
    width: snapshotWidth,
    height: snapshotHeight,
    originX: minX,
    originY: minY,
  );
}

class _LayerTransformSnapshot {
  const _LayerTransformSnapshot({
    required this.pixels,
    required this.width,
    required this.height,
    required this.originX,
    required this.originY,
  });

  final Uint32List pixels;
  final int width;
  final int height;
  final int originX;
  final int originY;
}

class _LayerOverflowSegment {
  _LayerOverflowSegment(this.startX, this.pixels);

  final int startX;
  final Uint32List pixels;

  int get length => pixels.length;
}

class _LayerOverflowStore {
  final SplayTreeMap<int, List<_LayerOverflowSegment>> _rows =
      SplayTreeMap<int, List<_LayerOverflowSegment>>();
  bool _hasBounds = false;
  int minX = 0;
  int maxX = 0;
  int minY = 0;
  int maxY = 0;

  bool get isEmpty => _rows.isEmpty;

  void addRow(int y, List<_LayerOverflowSegment> segments) {
    if (segments.isEmpty) {
      _rows.remove(y);
      return;
    }
    _rows[y] = segments;
    if (!_hasBounds) {
      minX = segments.first.startX;
      maxX = segments.first.startX + segments.first.length;
      minY = y;
      maxY = y + 1;
      _hasBounds = true;
    } else {
      minY = math.min(minY, y);
      maxY = math.max(maxY, y + 1);
    }
    for (final _LayerOverflowSegment segment in segments) {
      if (!_hasBounds) {
        minX = segment.startX;
        maxX = segment.startX + segment.length;
        _hasBounds = true;
      } else {
        minX = math.min(minX, segment.startX);
        maxX = math.max(maxX, segment.startX + segment.length);
      }
    }
  }

  void clear() {
    _rows.clear();
    _hasBounds = false;
    minX = 0;
    maxX = 0;
    minY = 0;
    maxY = 0;
  }

  void forEachSegment(
    void Function(int rowY, _LayerOverflowSegment segment) visitor,
  ) {
    _rows.forEach((int y, List<_LayerOverflowSegment> segments) {
      for (final _LayerOverflowSegment segment in segments) {
        visitor(y, segment);
      }
    });
  }
}

class _LayerOverflowBuilder {
  final Map<int, _OverflowRowBuilder> _rows = <int, _OverflowRowBuilder>{};

  void addPixel(int x, int y, int color) {
    if ((color >> 24) == 0) {
      return;
    }
    final _OverflowRowBuilder builder = _rows.putIfAbsent(
      y,
      () => _OverflowRowBuilder(),
    );
    builder.addPixel(x, color);
  }

  _LayerOverflowStore build() {
    if (_rows.isEmpty) {
      return _LayerOverflowStore();
    }
    final _LayerOverflowStore store = _LayerOverflowStore();
    final List<int> rowKeys = _rows.keys.toList()..sort();
    for (final int y in rowKeys) {
      final _OverflowRowBuilder builder = _rows[y]!;
      final List<_LayerOverflowSegment> segments = builder.build();
      if (segments.isEmpty) {
        continue;
      }
      store.addRow(y, segments);
    }
    return store;
  }
}

class _OverflowRowBuilder {
  final List<_LayerOverflowSegment> _segments = <_LayerOverflowSegment>[];
  int? _currentStart;
  final List<int> _buffer = <int>[];

  void addPixel(int x, int color) {
    if (_currentStart == null) {
      _currentStart = x;
      _buffer.add(color);
      return;
    }
    final int expected = _currentStart! + _buffer.length;
    if (x == expected) {
      _buffer.add(color);
      return;
    }
    _flush();
    _currentStart = x;
    _buffer.add(color);
  }

  List<_LayerOverflowSegment> build() {
    _flush();
    return _segments;
  }

  void _flush() {
    if (_currentStart == null || _buffer.isEmpty) {
      _buffer.clear();
      _currentStart = null;
      return;
    }
    _segments.add(
      _LayerOverflowSegment(_currentStart!, Uint32List.fromList(_buffer)),
    );
    _buffer.clear();
    _currentStart = null;
  }
}

void _restoreActiveLayerSnapshot(BitmapCanvasController controller) {
  final Uint32List? snapshot = controller._activeLayerTranslationSnapshot;
  final String? id = controller._activeLayerTranslationId;
  if (snapshot == null || id == null) {
    return;
  }
  if (controller._clipLayerOverflow) {
    final BitmapLayerState target = controller._layers.firstWhere(
      (layer) => layer.id == id,
      orElse: () => controller._activeLayer,
    );
    target.surface.pixels.setAll(0, snapshot);
    _resetActiveLayerTranslationState(controller);
    return;
  }
  _restoreOverflowLayerSnapshot(controller, snapshot, id);
}

void _disposeActiveLayerTransformSession(BitmapCanvasController controller) {
  if (controller._activeLayerTranslationSnapshot == null) {
    return;
  }
  controller._pendingActiveLayerTransformCleanup = true;
  controller._markDirty(
    layerId: controller._activeLayerTranslationId,
    pixelsDirty: true,
  );
}

void _updateActiveLayerTransformDirtyRegion(BitmapCanvasController controller) {
  final Rect? baseBounds = controller._activeLayerTransformBounds;
  if (baseBounds == null) {
    return;
  }
  final Rect current = baseBounds.shift(
    Offset(
      controller._activeLayerTranslationDx.toDouble(),
      controller._activeLayerTranslationDy.toDouble(),
    ),
  );
  final Rect? existing = controller._activeLayerTransformDirtyRegion;
  if (existing == null) {
    controller._activeLayerTransformDirtyRegion = current;
  } else {
    controller._activeLayerTransformDirtyRegion =
        BitmapCanvasController._unionRects(existing, current);
  }
}

void _resetActiveLayerTranslationState(BitmapCanvasController controller) {
  controller._activeLayerTranslationSnapshot = null;
  controller._activeLayerTranslationId = null;
  controller._activeLayerTranslationDx = 0;
  controller._activeLayerTranslationDy = 0;
  controller._activeLayerTransformSnapshotWidth = 0;
  controller._activeLayerTransformSnapshotHeight = 0;
  controller._activeLayerTransformOriginX = 0;
  controller._activeLayerTransformOriginY = 0;
  controller._activeLayerTransformPreparing = false;
  controller._activeLayerTransformBounds = null;
  controller._activeLayerTransformDirtyRegion = null;
  _disposeActiveLayerTransformImage(controller);
}

void _disposeActiveLayerTransformImage(BitmapCanvasController controller) {
  controller._activeLayerTransformImage?.dispose();
  controller._activeLayerTransformImage = null;
}
