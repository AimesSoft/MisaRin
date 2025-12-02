part of 'controller.dart';

void _fillSetSelectionMask(BitmapCanvasController controller, Uint8List? mask) {
  if (mask != null && mask.length != controller._width * controller._height) {
    throw ArgumentError('Selection mask size mismatch');
  }
  controller._selectionMask = mask;
  controller._paintingWorkerSelectionDirty = true;
}

void _fillFloodFill(
  BitmapCanvasController controller,
  Offset position, {
  required Color color,
  bool contiguous = true,
  bool sampleAllLayers = false,
  List<Color>? swallowColors,
  int tolerance = 0,
  int antialiasLevel = 0,
}) {
  if (controller._activeLayer.locked) {
    return;
  }
  final int x = position.dx.floor();
  final int y = position.dy.floor();
  if (x < 0 || x >= controller._width || y < 0 || y >= controller._height) {
    return;
  }
  if (!_fillSelectionAllowsInt(controller, x, y)) {
    return;
  }

  final bool shouldSwallow = swallowColors != null && swallowColors.isNotEmpty;
  final List<int>? swallowArgb = shouldSwallow
      ? swallowColors
            .map((color) => BitmapSurface.encodeColor(color))
            .toList(growable: false)
      : null;
  final int clampedTolerance = tolerance.clamp(0, 255);
  final int clampedAntialias = antialiasLevel.clamp(0, 3);
  final bool hasAntialias = clampedAntialias > 0;
  // Tolerance is now supported by worker, so we don't need to force mask fill for it alone.
  final bool requiresMaskFill = shouldSwallow || hasAntialias;
  final bool needsRegionMask = shouldSwallow || hasAntialias;

  Uint8List? regionMask;
  if (sampleAllLayers) {
    regionMask = _fillFloodFillAcrossLayers(
      controller,
      x,
      y,
      color,
      contiguous,
      tolerance: clampedTolerance,
      collectMask: needsRegionMask,
    );
    if (needsRegionMask && regionMask == null) {
      return;
    }
  } else {
    final Color baseColor = _fillColorAtSurface(
      controller,
      controller._activeSurface,
      x,
      y,
    );
    if (!requiresMaskFill) {
      if (controller.isMultithreaded) {
        controller._enqueueWorkerPatchFuture(
          controller._executeFloodFill(
            start: Offset(x.toDouble(), y.toDouble()),
            color: color,
            targetColor: baseColor,
            contiguous: contiguous,
            tolerance: clampedTolerance,
          ),
          onError: () {
            controller._activeSurface.floodFill(
              start: Offset(x.toDouble(), y.toDouble()),
              color: color,
              targetColor: baseColor,
              contiguous: contiguous,
              mask: controller._selectionMask,
            );
            controller._resetWorkerSurfaceSync();
            controller._markDirty(
              layerId: controller._activeLayer.id,
              pixelsDirty: true,
            );
          },
        );
      } else {
        controller._activeSurface.floodFill(
          start: Offset(x.toDouble(), y.toDouble()),
          color: color,
          targetColor: baseColor,
          contiguous: contiguous,
          mask: controller._selectionMask,
        );
        controller._markDirty(
          layerId: controller._activeLayer.id,
          pixelsDirty: true,
        );
      }
      return;
    }
    if (baseColor.value == color.value && !shouldSwallow) {
      return;
    }
    regionMask = _fillFloodFillSingleLayerWithMask(
      controller,
      x,
      y,
      color,
      baseColor,
      contiguous,
      tolerance: clampedTolerance,
    );
    if (regionMask == null) {
      return;
    }
  }

  if (shouldSwallow && regionMask != null && swallowArgb != null) {
    _fillSwallowColorLines(controller, regionMask, swallowArgb, color);
  }
  if (hasAntialias && regionMask != null) {
    _fillApplyAntialiasToMask(controller, regionMask, clampedAntialias);
  }
}

Future<Uint8List?> _fillComputeMagicWandMask(
  BitmapCanvasController controller,
  Offset position, {
  bool sampleAllLayers = true,
  int tolerance = 0,
}) async {
  final int x = position.dx.floor();
  final int y = position.dy.floor();
  if (x < 0 || x >= controller._width || y < 0 || y >= controller._height) {
    return null;
  }
  final Uint8List mask = Uint8List(controller._width * controller._height);
  if (sampleAllLayers) {
    controller._updateComposite(requiresFullSurface: true, region: null);
    final Uint32List? composite = controller._compositePixels;
    if (composite == null || composite.isEmpty) {
      return null;
    }
    if (controller.isMultithreaded) {
      final Uint32List copy = Uint32List.fromList(composite);
      return controller._executeSelectionMask(
        start: Offset(x.toDouble(), y.toDouble()),
        pixels: copy,
        tolerance: tolerance,
      );
    } else {
      final int target = composite[y * controller._width + x];
      final bool filled = _fillFloodFillMask(
        controller,
        pixels: composite,
        targetColor: target,
        mask: mask,
        startX: x,
        startY: y,
        width: controller._width,
        height: controller._height,
        tolerance: tolerance,
      );
      if (!filled) {
        return null;
      }
      return mask;
    }
  }

  final Uint32List pixels = controller._activeSurface.pixels;
  if (controller.isMultithreaded) {
    final Uint32List copy = Uint32List.fromList(pixels);
    return controller._executeSelectionMask(
      start: Offset(x.toDouble(), y.toDouble()),
      pixels: copy,
      tolerance: tolerance,
    );
  } else {
    final int target = pixels[y * controller._width + x];
    final bool filled = _fillFloodFillMask(
      controller,
      pixels: pixels,
      targetColor: target,
      mask: mask,
      startX: x,
      startY: y,
      width: controller._width,
      height: controller._height,
      tolerance: tolerance,
    );
    if (!filled) {
      return null;
    }
    return mask;
  }
}

Color _fillSampleColor(
  BitmapCanvasController controller,
  Offset position, {
  bool sampleAllLayers = true,
}) {
  final int x = position.dx.floor();
  final int y = position.dy.floor();
  if (x < 0 || x >= controller._width || y < 0 || y >= controller._height) {
    return const Color(0x00000000);
  }
  if (sampleAllLayers) {
    return _fillColorAtComposite(controller, position, preferRealtime: true);
  }
  return _fillColorAtSurface(controller, controller._activeSurface, x, y);
}

bool _fillSelectionAllows(BitmapCanvasController controller, Offset position) {
  final Uint8List? mask = controller._selectionMask;
  if (mask == null) {
    return true;
  }
  final int x = position.dx.floor();
  final int y = position.dy.floor();
  if (x < 0 || x >= controller._width || y < 0 || y >= controller._height) {
    return false;
  }
  return mask[y * controller._width + x] != 0;
}

bool _fillSelectionAllowsInt(BitmapCanvasController controller, int x, int y) {
  final Uint8List? mask = controller._selectionMask;
  if (mask == null) {
    return true;
  }
  if (x < 0 || x >= controller._width || y < 0 || y >= controller._height) {
    return false;
  }
  return mask[y * controller._width + x] != 0;
}

Uint8List? _fillFloodFillAcrossLayers(
  BitmapCanvasController controller,
  int startX,
  int startY,
  Color color,
  bool contiguous, {
  bool collectMask = false,
  int tolerance = 0,
}) {
  if (!_fillSelectionAllowsInt(controller, startX, startY)) {
    return null;
  }
  controller._updateComposite(requiresFullSurface: true, region: null);
  final Uint32List? compositePixels = controller._compositePixels;
  if (compositePixels == null || compositePixels.isEmpty) {
    return null;
  }
  final int index = startY * controller._width + startX;
  if (index < 0 || index >= compositePixels.length) {
    return null;
  }
  final int target = compositePixels[index];
  final int replacement = BitmapSurface.encodeColor(color);
  final Uint32List surfacePixels = controller._activeSurface.pixels;
  final Uint8List? selectionMask = controller._selectionMask;

  if (!contiguous) {
    final Uint8List? swallowMask = collectMask
        ? Uint8List(controller._width * controller._height)
        : null;
    int minX = controller._width;
    int minY = controller._height;
    int maxX = -1;
    int maxY = -1;
    bool changed = false;
    for (int i = 0; i < compositePixels.length; i++) {
      final int pixel = compositePixels[i];
      if (!_fillColorsWithinTolerance(pixel, target, tolerance)) {
        continue;
      }
      if (selectionMask != null && selectionMask[i] == 0) {
        continue;
      }
      if (surfacePixels[i] == replacement) {
        continue;
      }
      surfacePixels[i] = replacement;
      changed = true;
      if (swallowMask != null) {
        swallowMask[i] = 1;
      }
      final int px = i % controller._width;
      final int py = i ~/ controller._width;
      if (px < minX) {
        minX = px;
      }
      if (py < minY) {
        minY = py;
      }
      if (px > maxX) {
        maxX = px;
      }
      if (py > maxY) {
        maxY = py;
      }
    }
    if (changed) {
      controller._markDirty(
        region: Rect.fromLTRB(
          minX.toDouble(),
          minY.toDouble(),
          (maxX + 1).toDouble(),
          (maxY + 1).toDouble(),
        ),
        layerId: controller._activeLayer.id,
        pixelsDirty: true,
      );
    }
    if (swallowMask != null && changed) {
      return swallowMask;
    }
    return null;
  }
  final Uint8List contiguousMask = Uint8List(
    controller._width * controller._height,
  );
  final bool filled = _fillFloodFillMask(
    controller,
    pixels: compositePixels,
    targetColor: target,
    mask: contiguousMask,
    startX: startX,
    startY: startY,
    width: controller._width,
    height: controller._height,
    tolerance: tolerance,
  );
  if (!filled) {
    return null;
  }

  // Expand mask by 1 pixel to cover anti-aliased edges (only if tolerance > 0)
  Uint8List finalMask = contiguousMask;
  if (tolerance > 0) {
    finalMask = _fillExpandMask(
      contiguousMask,
      controller._width,
      controller._height,
      radius: 1,
    );
  }

  // When sampling across layers we must derive the contiguous region from
  // the composite; the active layer alone may not contain the sampled color.
  int minX = controller._width;
  int minY = controller._height;
  int maxX = -1;
  int maxY = -1;
  bool changed = false;
  for (int i = 0; i < finalMask.length; i++) {
    if (finalMask[i] == 0) {
      continue;
    }
    if (surfacePixels[i] == replacement) {
      continue;
    }
    surfacePixels[i] = replacement;
    changed = true;
    final int px = i % controller._width;
    final int py = i ~/ controller._width;
    if (px < minX) {
      minX = px;
    }
    if (py < minY) {
      minY = py;
    }
    if (px > maxX) {
      maxX = px;
    }
    if (py > maxY) {
      maxY = py;
    }
  }
  if (changed) {
    controller._markDirty(
      region: Rect.fromLTRB(
        minX.toDouble(),
        minY.toDouble(),
        (maxX + 1).toDouble(),
        (maxY + 1).toDouble(),
      ),
      layerId: controller._activeLayer.id,
      pixelsDirty: true,
    );
  }
  return collectMask ? finalMask : null;
}

Uint8List? _fillFloodFillSingleLayerWithMask(
  BitmapCanvasController controller,
  int startX,
  int startY,
  Color fillColor,
  Color baseColor,
  bool contiguous, {
  int tolerance = 0,
}) {
  final Uint32List pixels = controller._activeSurface.pixels;
  final Uint8List? selectionMask = controller._selectionMask;
  final int width = controller._width;
  final int height = controller._height;
  final int replacement = BitmapSurface.encodeColor(fillColor);
  final int target = BitmapSurface.encodeColor(baseColor);
  final Uint8List mask = Uint8List(width * height);

  if (!contiguous) {
    int minX = width;
    int minY = height;
    int maxX = -1;
    int maxY = -1;
    bool changed = false;
    for (int i = 0; i < pixels.length; i++) {
      if (selectionMask != null && selectionMask[i] == 0) {
        continue;
      }
      if (!_fillColorsWithinTolerance(pixels[i], target, tolerance)) {
        continue;
      }
      pixels[i] = replacement;
      mask[i] = 1;
      changed = true;
      final int px = i % width;
      final int py = i ~/ width;
      if (px < minX) {
        minX = px;
      }
      if (py < minY) {
        minY = py;
      }
      if (px > maxX) {
        maxX = px;
      }
      if (py > maxY) {
        maxY = py;
      }
    }
    if (!changed) {
      return null;
    }
    controller._markDirty(
      region: Rect.fromLTRB(
        minX.toDouble(),
        minY.toDouble(),
        (maxX + 1).toDouble(),
        (maxY + 1).toDouble(),
      ),
      layerId: controller._activeLayer.id,
      pixelsDirty: true,
    );
    return mask;
  }

  final bool filled = _fillFloodFillMask(
    controller,
    pixels: pixels,
    targetColor: target,
    mask: mask,
    startX: startX,
    startY: startY,
    width: width,
    height: height,
    tolerance: tolerance,
  );
  if (!filled) {
    return null;
  }

  // Expand mask by 1 pixel to cover anti-aliased edges (only if tolerance > 0)
  Uint8List finalMask = mask;
  if (tolerance > 0) {
    finalMask = _fillExpandMask(mask, width, height, radius: 1);
  }

  int minX = width;
  int minY = height;
  int maxX = -1;
  int maxY = -1;
  bool changed = false;
  for (int i = 0; i < finalMask.length; i++) {
    if (finalMask[i] == 0) {
      continue;
    }
    if (pixels[i] == replacement) {
      continue;
    }
    pixels[i] = replacement;
    changed = true;
    final int px = i % width;
    final int py = i ~/ width;
    if (px < minX) {
      minX = px;
    }
    if (py < minY) {
      minY = py;
    }
    if (px > maxX) {
      maxX = px;
    }
    if (py > maxY) {
      maxY = py;
    }
  }
  if (changed) {
    controller._markDirty(
      region: Rect.fromLTRB(
        minX.toDouble(),
        minY.toDouble(),
        (maxX + 1).toDouble(),
        (maxY + 1).toDouble(),
      ),
      layerId: controller._activeLayer.id,
      pixelsDirty: true,
    );
    return finalMask;
  }
  return null;
}

void _fillSwallowColorLines(
  BitmapCanvasController controller,
  Uint8List regionMask,
  List<int> swallowArgb,
  Color fillColor,
) {
  if (regionMask.isEmpty || swallowArgb.isEmpty) {
    return;
  }
  final Set<int> swallowSet = swallowArgb.toSet();
  final Uint8List? selectionMask = controller._selectionMask;
  final Uint32List pixels = controller._activeSurface.pixels;
  final int width = controller._width;
  final int height = controller._height;
  final int fillArgb = BitmapSurface.encodeColor(fillColor);

  bool changed = false;
  int minX = width;
  int minY = height;
  int maxX = -1;
  int maxY = -1;
  final Uint8List visited = Uint8List(regionMask.length);

  void floodColorLine(int startIndex, int targetColor) {
    final Queue<int> queue = Queue<int>()..add(startIndex);
    visited[startIndex] = 1;
    while (queue.isNotEmpty) {
      final int index = queue.removeFirst();
      if (pixels[index] != targetColor) {
        continue;
      }
      if (selectionMask != null && selectionMask[index] == 0) {
        continue;
      }
      if (pixels[index] == fillArgb) {
        continue;
      }
      pixels[index] = fillArgb;
      changed = true;
      final int px = index % width;
      final int py = index ~/ width;
      if (px < minX) {
        minX = px;
      }
      if (py < minY) {
        minY = py;
      }
      if (px > maxX) {
        maxX = px;
      }
      if (py > maxY) {
        maxY = py;
      }

      void enqueue(int nx, int ny) {
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
          return;
        }
        final int neighborIndex = ny * width + nx;
        if (visited[neighborIndex] != 0) {
          return;
        }
        if (selectionMask != null && selectionMask[neighborIndex] == 0) {
          return;
        }
        if (pixels[neighborIndex] != targetColor) {
          return;
        }
        visited[neighborIndex] = 1;
        queue.add(neighborIndex);
      }

      enqueue(px + 1, py);
      enqueue(px - 1, py);
      enqueue(px, py + 1);
      enqueue(px, py - 1);
    }
  }

  int index = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++, index++) {
      if (regionMask[index] == 0) {
        continue;
      }

      void tryNeighbor(int nx, int ny) {
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
          return;
        }
        final int neighborIndex = ny * width + nx;
        if (visited[neighborIndex] != 0) {
          return;
        }
        final int neighborColor = pixels[neighborIndex];
        if (!swallowSet.contains(neighborColor) || neighborColor == fillArgb) {
          return;
        }
        floodColorLine(neighborIndex, neighborColor);
      }

      tryNeighbor(x + 1, y);
      tryNeighbor(x - 1, y);
      tryNeighbor(x, y + 1);
      tryNeighbor(x, y - 1);
    }
  }

  if (changed) {
    controller._markDirty(
      region: Rect.fromLTRB(
        minX.toDouble(),
        minY.toDouble(),
        (maxX + 1).toDouble(),
        (maxY + 1).toDouble(),
      ),
      layerId: controller._activeLayer.id,
      pixelsDirty: true,
    );
  }
}

void _fillApplyAntialiasToMask(
  BitmapCanvasController controller,
  Uint8List regionMask,
  int level,
) {
  if (regionMask.isEmpty || level <= 0) {
    return;
  }
  final List<double>? profile =
      BitmapCanvasController._kAntialiasBlendProfiles[level];
  if (profile == null || profile.isEmpty) {
    return;
  }
  final Uint32List pixels = controller._activeSurface.pixels;
  if (pixels.isEmpty) {
    return;
  }
  final Uint8List expandedMask = _fillExpandMask(
    regionMask,
    controller._width,
    controller._height,
  );
  final Uint32List temp = Uint32List(pixels.length);
  Uint32List src = pixels;
  Uint32List dest = temp;
  bool anyChange = false;
  for (final double factor in profile) {
    if (factor <= 0) {
      continue;
    }
    final bool changed = _fillRunMaskedAntialiasPass(
      controller,
      src,
      dest,
      expandedMask,
      blendFactor: factor,
    );
    if (!changed) {
      continue;
    }
    anyChange = true;
    final Uint32List swap = src;
    src = dest;
    dest = swap;
  }
  if (!anyChange) {
    return;
  }
  if (!identical(src, pixels)) {
    pixels.setAll(0, src);
  }
  final Rect? bounds = _fillMaskBounds(controller, expandedMask);
  controller._markDirty(
    region: bounds,
    layerId: controller._activeLayer.id,
    pixelsDirty: true,
  );
}

bool _fillRunMaskedAntialiasPass(
  BitmapCanvasController controller,
  Uint32List src,
  Uint32List dest,
  Uint8List mask, {
  required double blendFactor,
}) {
  final bool changed = controller._runAntialiasPass(
    src,
    dest,
    controller._width,
    controller._height,
    blendFactor,
  );
  if (!changed) {
    return false;
  }
  bool maskChanged = false;
  final int limit = math.min(mask.length, src.length);
  for (int i = 0; i < limit; i++) {
    if (mask[i] == 0) {
      dest[i] = src[i];
      continue;
    }
    if (!maskChanged && dest[i] != src[i]) {
      maskChanged = true;
    }
  }
  return maskChanged;
}

Rect? _fillMaskBounds(BitmapCanvasController controller, Uint8List mask) {
  if (mask.isEmpty) {
    return null;
  }
  int minX = controller._width;
  int minY = controller._height;
  int maxX = -1;
  int maxY = -1;
  int index = 0;
  for (int y = 0; y < controller._height; y++) {
    for (int x = 0; x < controller._width; x++, index++) {
      if (index >= mask.length) {
        break;
      }
      if (mask[index] == 0) {
        continue;
      }
      if (x < minX) {
        minX = x;
      }
      if (y < minY) {
        minY = y;
      }
      if (x > maxX) {
        maxX = x;
      }
      if (y > maxY) {
        maxY = y;
      }
    }
    if (index >= mask.length) {
      break;
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

Uint8List _fillExpandMask(
  Uint8List mask,
  int width,
  int height, {
  int radius = 1,
}) {
  if (mask.isEmpty || width <= 0 || height <= 0 || radius <= 0) {
    return mask;
  }
  final Uint8List expanded = Uint8List(mask.length);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int index = y * width + x;
      if (index >= mask.length) {
        break;
      }
      if (mask[index] == 0) {
        continue;
      }
      final int minX = math.max(0, x - radius);
      final int maxX = math.min(width - 1, x + radius);
      final int minY = math.max(0, y - radius);
      final int maxY = math.min(height - 1, y + radius);
      for (int ny = minY; ny <= maxY; ny++) {
        for (int nx = minX; nx <= maxX; nx++) {
          final int expandedIndex = ny * width + nx;
          if (expandedIndex < expanded.length) {
            expanded[expandedIndex] = 1;
          }
        }
      }
    }
  }
  return expanded;
}

bool _fillFloodFillMask(
  BitmapCanvasController controller, {
  required Uint32List pixels,
  required int targetColor,
  required Uint8List mask,
  required int startX,
  required int startY,
  required int width,
  required int height,
  int tolerance = 0,
}) {
  if (pixels.isEmpty || mask.isEmpty) {
    return false;
  }
  final Queue<int> queue = Queue<int>();
  final Set<int> visited = <int>{};
  int processed = 0;

  bool shouldInclude(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      return false;
    }
    final int index = y * width + x;
    if (visited.contains(index)) {
      return false;
    }
    visited.add(index);
    if (controller._selectionMask != null &&
        controller._selectionMask![index] == 0) {
      return false;
    }
    return _fillColorsWithinTolerance(pixels[index], targetColor, tolerance);
  }

  void enqueue(int x, int y) {
    if (!shouldInclude(x, y)) {
      return;
    }
    final int index = y * width + x;
    mask[index] = 1;
    queue.add(index);
  }

  enqueue(startX, startY);

  while (queue.isNotEmpty) {
    final int index = queue.removeFirst();
    processed += 1;
    final int x = index % width;
    final int y = index ~/ width;
    enqueue(x + 1, y);
    enqueue(x - 1, y);
    enqueue(x, y + 1);
    enqueue(x, y - 1);
  }

  return processed > 0;
}

bool _fillColorsWithinTolerance(int candidate, int target, int tolerance) {
  if (tolerance <= 0) {
    return candidate == target;
  }
  final int ca = (candidate >> 24) & 0xff;
  final int cr = (candidate >> 16) & 0xff;
  final int cg = (candidate >> 8) & 0xff;
  final int cb = candidate & 0xff;
  final int ta = (target >> 24) & 0xff;
  final int tr = (target >> 16) & 0xff;
  final int tg = (target >> 8) & 0xff;
  final int tb = target & 0xff;
  final int diffA = (ca - ta).abs();
  final int diffR = (cr - tr).abs();
  final int diffG = (cg - tg).abs();
  final int diffB = (cb - tb).abs();
  final int maxRgb = math.max(math.max(diffR, diffG), diffB);
  final int maxDiff = math.max(maxRgb, diffA);
  return maxDiff <= tolerance;
}

Color _fillColorAtComposite(
  BitmapCanvasController controller,
  Offset position, {
  bool preferRealtime = false,
}) {
  return controller._rasterBackend.colorAtComposite(
    position,
    controller._layers,
    translatingLayerId: controller._translatingLayerIdForComposite,
    preferRealtime: preferRealtime,
  );
}

Color _fillColorAtSurface(
  BitmapCanvasController controller,
  BitmapSurface surface,
  int x,
  int y,
) {
  final Uint32List pixels = surface.pixels;
  final int index = y * controller._width + x;
  if (index < 0 || index >= pixels.length) {
    return const Color(0x00000000);
  }
  return BitmapSurface.decodeColor(pixels[index]);
}
