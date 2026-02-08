part of 'controller.dart';

void _fillSetSelectionMask(BitmapCanvasController controller, Uint8List? mask) {
  if (mask != null && mask.length != controller._width * controller._height) {
    throw ArgumentError('Selection mask size mismatch');
  }
  controller._selectionMask = mask;
  controller._paintingWorkerSelectionDirty = true;
}

BitmapLayerState? _fillFindSingleVisibleLayerForComposite(
  BitmapCanvasController controller,
) {
  final String? translatingLayerId = controller._translatingLayerIdForComposite;
  BitmapLayerState? candidate;
  for (final BitmapLayerState layer in controller._layers) {
    if (!layer.visible) {
      continue;
    }
    if (translatingLayerId != null && layer.id == translatingLayerId) {
      continue;
    }
    if (candidate != null) {
      return null;
    }
    candidate = layer;
  }
  return candidate;
}

Uint32List _fillBuildSingleLayerCompositePixels(BitmapLayerState layer) {
  final Uint32List source = layer.surface.pixels;
  final Uint32List composite = Uint32List(source.length);
  if (composite.isEmpty) {
    return composite;
  }

  if (layer.clippingMask) {
    return composite;
  }

  final double opacity = BitmapCanvasController._clampUnit(layer.opacity);
  if (opacity <= 0) {
    return composite;
  }
  if (opacity >= 1.0) {
    composite.setAll(0, source);
    return composite;
  }

  for (int i = 0; i < source.length; i++) {
    final int src = source[i];
    final int srcA = (src >> 24) & 0xff;
    if (srcA == 0) {
      continue;
    }
    int effectiveA = (srcA * opacity).round();
    if (effectiveA <= 0) {
      continue;
    }
    effectiveA = effectiveA.clamp(0, 255);
    composite[i] = (effectiveA << 24) | (src & 0x00FFFFFF);
  }
  return composite;
}

bool _fillAllPixelsMatchColor(Uint32List pixels, int color) {
  final int length = pixels.length;
  for (int i = 0; i < length; i++) {
    if (pixels[i] != color) {
      return false;
    }
  }
  return true;
}

void _fillFloodFill(
  BitmapCanvasController controller,
  Offset position, {
  required Color color,
  bool contiguous = true,
  bool sampleAllLayers = false,
  List<Color>? swallowColors,
  int tolerance = 0,
  int fillGap = 0,
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

  final int clampedTolerance = tolerance.clamp(0, 255);
  final int clampedFillGap = fillGap.clamp(0, 64);
  final int clampedAntialias = antialiasLevel.clamp(0, 9);
  final Uint8List? selectionMask = controller._selectionMask;
  final Uint32List? swallowColorsU32 =
      swallowColors != null && swallowColors.isNotEmpty
      ? Uint32List.fromList(
          swallowColors
              .map((it) => BitmapSurface.encodeColor(it))
              .toList(growable: false),
        )
      : null;
  Uint32List? samplePixels;
  if (sampleAllLayers) {
    final BitmapLayerState? singleVisibleLayer =
        _fillFindSingleVisibleLayerForComposite(controller);
    if (singleVisibleLayer != null) {
      final double layerOpacity = BitmapCanvasController._clampUnit(
        singleVisibleLayer.opacity,
      );
      if (!singleVisibleLayer.clippingMask && layerOpacity >= 1.0) {
        if (!identical(singleVisibleLayer, controller._activeLayer)) {
          samplePixels = singleVisibleLayer.surface.pixels;
        }
      } else {
        final Uint32List resolvedSamplePixels =
            _fillBuildSingleLayerCompositePixels(singleVisibleLayer);
        if (resolvedSamplePixels.isEmpty) {
          return;
        }
        samplePixels = resolvedSamplePixels;
      }
    } else {
      controller._updateComposite(requiresFullSurface: true, region: null);
      final Uint32List? compositePixels = controller._compositePixels;
      final bool compositeReady =
          compositePixels != null &&
          compositePixels.isNotEmpty &&
          !controller._rasterBackend.isCompositeDirty;
      final Uint32List resolvedSamplePixels = compositeReady
          ? compositePixels
          : _fillBuildCompositePixelsFallback(controller);
      if (resolvedSamplePixels.isEmpty) {
        return;
      }
      samplePixels = resolvedSamplePixels;
    }
  }

  final BitmapSurface surface = controller._activeSurface;
  final String layerId = controller._activeLayer.id;
  final int generation = controller._paintingWorkerGeneration;
  final int colorValue = BitmapSurface.encodeColor(color);
  final int width = controller._width;
  final int height = controller._height;
  if (kIsWeb) {
    controller._enqueueWorkerPatchFuture(
      rust_bucket_fill
          .floodFillPatch(
            width: width,
            height: height,
            pixels: surface.pixels,
            samplePixels: samplePixels,
            startX: x,
            startY: y,
            colorValue: colorValue,
            targetColorValue: null,
            contiguous: contiguous,
            tolerance: clampedTolerance,
            fillGap: clampedFillGap,
            selectionMask: selectionMask,
            swallowColors: swallowColorsU32,
            antialiasLevel: clampedAntialias,
          )
          .then<PaintingWorkerPatch?>((patch) {
            if (generation != controller._paintingWorkerGeneration) {
              return null;
            }
            if (patch.width <= 0 || patch.height <= 0) {
              return null;
            }
            final int left = patch.left;
            final int top = patch.top;
            final int patchWidth = patch.width;
            final int patchHeight = patch.height;
            final Uint32List destPixels = surface.pixels;
            final Uint32List srcPixels = patch.pixels;
            final int surfaceWidth = width;
            int srcIndex = 0;
            for (int dy = 0; dy < patchHeight; dy++) {
              int destIndex = (top + dy) * surfaceWidth + left;
              final int rowEnd = destIndex + patchWidth;
              for (; destIndex < rowEnd; destIndex++) {
                destPixels[destIndex] = srcPixels[srcIndex++];
              }
            }
            if (surface.isClean && (colorValue & 0xff000000) != 0) {
              surface.markDirty();
            }
            controller._markDirty(
              region: Rect.fromLTWH(
                left.toDouble(),
                top.toDouble(),
                patchWidth.toDouble(),
                patchHeight.toDouble(),
              ),
              layerId: layerId,
              pixelsDirty: true,
            );
            return null;
          }),
    );
    return;
  }
  final int ptrAddress = surface.pointerAddress;
  if (ptrAddress == 0) {
    return;
  }
  controller._enqueueWorkerPatchFuture(
    rust_bucket_fill
        .floodFillInPlace(
          ptr: BigInt.from(ptrAddress),
          width: width,
          height: height,
          samplePixels: samplePixels,
          startX: x,
          startY: y,
          colorValue: colorValue,
          targetColorValue: null,
          contiguous: contiguous,
          tolerance: clampedTolerance,
          fillGap: clampedFillGap,
          selectionMask: selectionMask,
          swallowColors: swallowColorsU32,
          antialiasLevel: clampedAntialias,
        )
        .then<PaintingWorkerPatch?>((rect) {
          if (generation != controller._paintingWorkerGeneration) {
            return null;
          }
          if (rect.width <= 0 || rect.height <= 0) {
            return null;
          }
          if (surface.isClean && (colorValue & 0xff000000) != 0) {
            surface.markDirty();
          }
          controller._markDirty(
            region: Rect.fromLTWH(
              rect.left.toDouble(),
              rect.top.toDouble(),
              rect.width.toDouble(),
              rect.height.toDouble(),
            ),
            layerId: layerId,
            pixelsDirty: true,
          );
          return null;
        }),
  );
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
  int fillGap = 0,
}) {
  if (!_fillSelectionAllowsInt(controller, startX, startY)) {
    return null;
  }
  controller._updateComposite(requiresFullSurface: true, region: null);
  Uint32List? compositePixels = controller._compositePixels;
  if (compositePixels == null || compositePixels.isEmpty) {
    compositePixels = _fillBuildCompositePixelsFallback(controller);
  }
  if (compositePixels == null || compositePixels.isEmpty) {
    return null;
  }
  final int index = startY * controller._width + startX;
  if (index < 0 || index >= compositePixels.length) {
    return null;
  }
  final int target = compositePixels[index];
  final int replacement = BitmapSurface.encodeColor(color);
  final BitmapSurface surface = controller._activeSurface;
  final Uint32List surfacePixels = surface.pixels;
  final Uint8List? selectionMask = controller._selectionMask;

  if (selectionMask == null &&
      compositePixels.length == controller._width * controller._height &&
      _fillAllPixelsMatchColor(compositePixels, target)) {
    surfacePixels.fillRange(0, surfacePixels.length, replacement);
    if (surface.isClean && (replacement & 0xff000000) != 0) {
      surface.markDirty();
    }
    controller._markDirty(
      region: Rect.fromLTWH(
        0,
        0,
        controller._width.toDouble(),
        controller._height.toDouble(),
      ),
      layerId: controller._activeLayer.id,
      pixelsDirty: true,
    );
    if (!collectMask) {
      return null;
    }
    final Uint8List mask = Uint8List(controller._width * controller._height);
    mask.fillRange(0, mask.length, 1);
    return mask;
  }

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
    fillGap: fillGap,
  );
  if (!filled) {
    return null;
  }

  // Expand mask by 1 pixel to cover anti-aliased edges.
  // When fillGap is enabled we avoid this extra expansion to prevent bleeding
  // into line art now that the fill no longer keeps an inner safety margin.
  Uint8List finalMask = contiguousMask;
  if (tolerance > 0 && fillGap <= 0) {
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

Uint32List _fillBuildCompositePixelsFallback(
  BitmapCanvasController controller,
) {
  final int width = controller._width;
  final int height = controller._height;
  final Uint32List composite = Uint32List(width * height);
  final Uint8List clipMask = Uint8List(width * height);
  clipMask.fillRange(0, clipMask.length, 0);
  final String? translatingLayerId = controller._translatingLayerIdForComposite;

  for (int y = 0; y < height; y++) {
    final int rowOffset = y * width;
    for (int x = 0; x < width; x++) {
      final int index = rowOffset + x;
      int color = 0;
      bool initialized = false;

      for (final BitmapLayerState layer in controller._layers) {
        if (!layer.visible) {
          continue;
        }
        if (translatingLayerId != null && layer.id == translatingLayerId) {
          continue;
        }
        final double layerOpacity = BitmapCanvasController._clampUnit(
          layer.opacity,
        );
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

      composite[index] = initialized ? color : 0;
    }
  }

  return composite;
}

Uint8List? _fillFloodFillSingleLayerWithMask(
  BitmapCanvasController controller,
  int startX,
  int startY,
  Color fillColor,
  Color baseColor,
  bool contiguous, {
  int tolerance = 0,
  int fillGap = 0,
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
    fillGap: fillGap,
  );
  if (!filled) {
    return null;
  }

  // Expand mask by 1 pixel to cover anti-aliased edges.
  // When fillGap is enabled we avoid this extra expansion to prevent bleeding
  // into line art now that the fill no longer keeps an inner safety margin.
  Uint8List finalMask = mask;
  if (tolerance > 0 && fillGap <= 0) {
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
  int fillGap = 0,
}) {
  if (pixels.isEmpty || mask.isEmpty || width <= 0 || height <= 0) {
    return false;
  }
  final int startIndex = startY * width + startX;
  if (startX < 0 ||
      startX >= width ||
      startY < 0 ||
      startY >= height ||
      startIndex < 0 ||
      startIndex >= pixels.length) {
    return false;
  }

  final Uint8List? selectionMask = controller._selectionMask;
  if (selectionMask != null && selectionMask[startIndex] == 0) {
    return false;
  }

  final int clampedFillGap = fillGap.clamp(0, 64);
  if (clampedFillGap > 0) {
    final Uint8List targetMask = Uint8List(pixels.length);
    for (int i = 0; i < pixels.length; i++) {
      if (selectionMask != null && selectionMask[i] == 0) {
        continue;
      }
      if (_fillColorsWithinTolerance(pixels[i], targetColor, tolerance)) {
        targetMask[i] = 1;
      }
    }
    if (targetMask[startIndex] == 0) {
      return false;
    }

    // "Fill gap" should only prevent leaking through small openings.
    // Using the opened mask directly can delete thin enclosed regions (e.g. narrow curved bands),
    // so we:
    // 1) Compute an opened mask to sever narrow leak paths,
    // 2) Find the "outside" region on the opened mask (border-connected),
    // 3) Reconstruct the fill inside the original target mask while forbidding entry into "outside".

    final Uint8List openedTarget = _fillOpenMask8(
      Uint8List.fromList(targetMask),
      width,
      height,
      radius: clampedFillGap,
    );

    final List<int> outsideSeeds = <int>[];
    for (int x = 0; x < width; x++) {
      final int topIndex = x;
      if (topIndex < openedTarget.length && openedTarget[topIndex] == 1) {
        outsideSeeds.add(topIndex);
      }
      final int bottomIndex = (height - 1) * width + x;
      if (bottomIndex >= 0 &&
          bottomIndex < openedTarget.length &&
          openedTarget[bottomIndex] == 1) {
        outsideSeeds.add(bottomIndex);
      }
    }
    for (int y = 1; y < height - 1; y++) {
      final int leftIndex = y * width;
      if (leftIndex < openedTarget.length && openedTarget[leftIndex] == 1) {
        outsideSeeds.add(leftIndex);
      }
      final int rightIndex = y * width + (width - 1);
      if (rightIndex >= 0 &&
          rightIndex < openedTarget.length &&
          openedTarget[rightIndex] == 1) {
        outsideSeeds.add(rightIndex);
      }
    }

    // No border-connected target region → there is no "outside" to leak into.
    if (outsideSeeds.isEmpty) {
      final List<int> queue = <int>[startIndex];
      int head = 0;
      mask[startIndex] = 1;
      final Uint8List visited = Uint8List(pixels.length);
      visited[startIndex] = 1;
      int processed = 1;
      while (head < queue.length) {
        final int index = queue[head++];
        final int x = index % width;
        final int y = index ~/ width;
        if (x > 0) {
          final int neighbor = index - 1;
          if (visited[neighbor] == 0 && targetMask[neighbor] == 1) {
            visited[neighbor] = 1;
            mask[neighbor] = 1;
            queue.add(neighbor);
            processed += 1;
          }
        }
        if (x < width - 1) {
          final int neighbor = index + 1;
          if (visited[neighbor] == 0 && targetMask[neighbor] == 1) {
            visited[neighbor] = 1;
            mask[neighbor] = 1;
            queue.add(neighbor);
            processed += 1;
          }
        }
        if (y > 0) {
          final int neighbor = index - width;
          if (visited[neighbor] == 0 && targetMask[neighbor] == 1) {
            visited[neighbor] = 1;
            mask[neighbor] = 1;
            queue.add(neighbor);
            processed += 1;
          }
        }
        if (y < height - 1) {
          final int neighbor = index + width;
          if (visited[neighbor] == 0 && targetMask[neighbor] == 1) {
            visited[neighbor] = 1;
            mask[neighbor] = 1;
            queue.add(neighbor);
            processed += 1;
          }
        }
      }
      return processed > 0;
    }

    final Uint8List outsideOpen = Uint8List(pixels.length);
    final List<int> outsideQueue = List<int>.from(outsideSeeds);
    int outsideHead = 0;
    for (final int seed in outsideSeeds) {
      outsideOpen[seed] = 1;
    }
    while (outsideHead < outsideQueue.length) {
      final int index = outsideQueue[outsideHead++];
      final int x = index % width;
      final int y = index ~/ width;
      if (x > 0) {
        final int neighbor = index - 1;
        if (outsideOpen[neighbor] == 0 && openedTarget[neighbor] == 1) {
          outsideOpen[neighbor] = 1;
          outsideQueue.add(neighbor);
        }
      }
      if (x < width - 1) {
        final int neighbor = index + 1;
        if (outsideOpen[neighbor] == 0 && openedTarget[neighbor] == 1) {
          outsideOpen[neighbor] = 1;
          outsideQueue.add(neighbor);
        }
      }
      if (y > 0) {
        final int neighbor = index - width;
        if (outsideOpen[neighbor] == 0 && openedTarget[neighbor] == 1) {
          outsideOpen[neighbor] = 1;
          outsideQueue.add(neighbor);
        }
      }
      if (y < height - 1) {
        final int neighbor = index + width;
        if (outsideOpen[neighbor] == 0 && openedTarget[neighbor] == 1) {
          outsideOpen[neighbor] = 1;
          outsideQueue.add(neighbor);
        }
      }
    }

    int effectiveStart = startIndex;
    if (openedTarget[effectiveStart] == 0) {
      final int? snapped = _fillFindNearestFillableStartIndex(
        startIndex: startIndex,
        fillable: openedTarget,
        pixels: pixels,
        targetColor: targetColor,
        width: width,
        height: height,
        tolerance: tolerance,
        selectionMask: selectionMask,
        maxDepth: clampedFillGap + 1,
      );
      if (snapped == null) {
        // Opening removed the whole local region; no gap closing can be applied safely.
        final List<int> queue = <int>[startIndex];
        int head = 0;
        mask[startIndex] = 1;
        final Uint8List visited = Uint8List(pixels.length);
        visited[startIndex] = 1;
        int processed = 1;
        while (head < queue.length) {
          final int index = queue[head++];
          final int x = index % width;
          final int y = index ~/ width;
          if (x > 0) {
            final int neighbor = index - 1;
            if (visited[neighbor] == 0 && targetMask[neighbor] == 1) {
              visited[neighbor] = 1;
              mask[neighbor] = 1;
              queue.add(neighbor);
              processed += 1;
            }
          }
          if (x < width - 1) {
            final int neighbor = index + 1;
            if (visited[neighbor] == 0 && targetMask[neighbor] == 1) {
              visited[neighbor] = 1;
              mask[neighbor] = 1;
              queue.add(neighbor);
              processed += 1;
            }
          }
          if (y > 0) {
            final int neighbor = index - width;
            if (visited[neighbor] == 0 && targetMask[neighbor] == 1) {
              visited[neighbor] = 1;
              mask[neighbor] = 1;
              queue.add(neighbor);
              processed += 1;
            }
          }
          if (y < height - 1) {
            final int neighbor = index + width;
            if (visited[neighbor] == 0 && targetMask[neighbor] == 1) {
              visited[neighbor] = 1;
              mask[neighbor] = 1;
              queue.add(neighbor);
              processed += 1;
            }
          }
        }
        return processed > 0;
      }
      effectiveStart = snapped;
    }

    final Uint8List seedVisited = Uint8List(pixels.length);
    final List<int> seedQueue = <int>[effectiveStart];
    seedVisited[effectiveStart] = 1;
    int seedHead = 0;
    bool touchesOutside = outsideOpen[effectiveStart] == 1;
    while (seedHead < seedQueue.length) {
      final int index = seedQueue[seedHead++];
      if (outsideOpen[index] == 1) {
        touchesOutside = true;
        break;
      }
      final int x = index % width;
      final int y = index ~/ width;
      if (x > 0) {
        final int neighbor = index - 1;
        if (seedVisited[neighbor] == 0 && openedTarget[neighbor] == 1) {
          seedVisited[neighbor] = 1;
          seedQueue.add(neighbor);
        }
      }
      if (x < width - 1) {
        final int neighbor = index + 1;
        if (seedVisited[neighbor] == 0 && openedTarget[neighbor] == 1) {
          seedVisited[neighbor] = 1;
          seedQueue.add(neighbor);
        }
      }
      if (y > 0) {
        final int neighbor = index - width;
        if (seedVisited[neighbor] == 0 && openedTarget[neighbor] == 1) {
          seedVisited[neighbor] = 1;
          seedQueue.add(neighbor);
        }
      }
      if (y < height - 1) {
        final int neighbor = index + width;
        if (seedVisited[neighbor] == 0 && openedTarget[neighbor] == 1) {
          seedVisited[neighbor] = 1;
          seedQueue.add(neighbor);
        }
      }
    }

    if (touchesOutside) {
      // Gap is larger than the chosen radius; fall back to standard flood fill.
      final List<int> queue = <int>[startIndex];
      int head = 0;
      mask[startIndex] = 1;
      final Uint8List visited = Uint8List(pixels.length);
      visited[startIndex] = 1;
      int processed = 1;
      while (head < queue.length) {
        final int index = queue[head++];
        final int x = index % width;
        final int y = index ~/ width;
        if (x > 0) {
          final int neighbor = index - 1;
          if (visited[neighbor] == 0 && targetMask[neighbor] == 1) {
            visited[neighbor] = 1;
            mask[neighbor] = 1;
            queue.add(neighbor);
            processed += 1;
          }
        }
        if (x < width - 1) {
          final int neighbor = index + 1;
          if (visited[neighbor] == 0 && targetMask[neighbor] == 1) {
            visited[neighbor] = 1;
            mask[neighbor] = 1;
            queue.add(neighbor);
            processed += 1;
          }
        }
        if (y > 0) {
          final int neighbor = index - width;
          if (visited[neighbor] == 0 && targetMask[neighbor] == 1) {
            visited[neighbor] = 1;
            mask[neighbor] = 1;
            queue.add(neighbor);
            processed += 1;
          }
        }
        if (y < height - 1) {
          final int neighbor = index + width;
          if (visited[neighbor] == 0 && targetMask[neighbor] == 1) {
            visited[neighbor] = 1;
            mask[neighbor] = 1;
            queue.add(neighbor);
            processed += 1;
          }
        }
      }
      return processed > 0;
    }

    final List<int> queue = List<int>.from(seedQueue);
    int head = 0;
    int processed = 0;
    for (final int index in queue) {
      if (targetMask[index] == 1 &&
          outsideOpen[index] == 0 &&
          mask[index] == 0) {
        mask[index] = 1;
        processed += 1;
      }
    }
    while (head < queue.length) {
      final int index = queue[head++];
      final int x = index % width;
      final int y = index ~/ width;
      if (x > 0) {
        final int neighbor = index - 1;
        if (mask[neighbor] == 0 &&
            targetMask[neighbor] == 1 &&
            outsideOpen[neighbor] == 0) {
          mask[neighbor] = 1;
          queue.add(neighbor);
          processed += 1;
        }
      }
      if (x < width - 1) {
        final int neighbor = index + 1;
        if (mask[neighbor] == 0 &&
            targetMask[neighbor] == 1 &&
            outsideOpen[neighbor] == 0) {
          mask[neighbor] = 1;
          queue.add(neighbor);
          processed += 1;
        }
      }
      if (y > 0) {
        final int neighbor = index - width;
        if (mask[neighbor] == 0 &&
            targetMask[neighbor] == 1 &&
            outsideOpen[neighbor] == 0) {
          mask[neighbor] = 1;
          queue.add(neighbor);
          processed += 1;
        }
      }
      if (y < height - 1) {
        final int neighbor = index + width;
        if (mask[neighbor] == 0 &&
            targetMask[neighbor] == 1 &&
            outsideOpen[neighbor] == 0) {
          mask[neighbor] = 1;
          queue.add(neighbor);
          processed += 1;
        }
      }
    }
    return processed > 0;
  }

  final Uint8List visited = Uint8List(pixels.length);
  final List<int> queue = <int>[];
  int head = 0;
  int processed = 0;

  void enqueueIndex(int index) {
    if (index < 0 || index >= pixels.length) {
      return;
    }
    if (visited[index] != 0) {
      return;
    }
    visited[index] = 1;
    if (selectionMask != null && selectionMask[index] == 0) {
      return;
    }
    if (!_fillColorsWithinTolerance(pixels[index], targetColor, tolerance)) {
      return;
    }
    mask[index] = 1;
    queue.add(index);
    processed += 1;
  }

  enqueueIndex(startIndex);

  while (head < queue.length) {
    final int index = queue[head++];
    final int x = index % width;
    final int y = index ~/ width;
    if (x > 0) {
      enqueueIndex(index - 1);
    }
    if (x < width - 1) {
      enqueueIndex(index + 1);
    }
    if (y > 0) {
      enqueueIndex(index - width);
    }
    if (y < height - 1) {
      enqueueIndex(index + width);
    }
  }

  return processed > 0;
}

Uint8List _fillOpenMask8(
  Uint8List mask,
  int width,
  int height, {
  required int radius,
}) {
  if (mask.isEmpty || width <= 0 || height <= 0 || radius <= 0) {
    return mask;
  }
  final int length = mask.length;
  final Uint8List buffer = Uint8List(length);
  final List<int> queue = <int>[];

  void dilateFromMaskValue(Uint8List source, Uint8List out, int seedValue) {
    queue.clear();
    out.fillRange(0, out.length, 0);
    for (int i = 0; i < source.length; i++) {
      if (source[i] != seedValue) {
        continue;
      }
      out[i] = 1;
      queue.add(i);
    }
    if (queue.isEmpty) {
      return;
    }
    int head = 0;
    final int lastRowStart = (height - 1) * width;
    for (int step = 0; step < radius; step++) {
      final int levelEnd = queue.length;
      while (head < levelEnd) {
        final int index = queue[head++];
        final int x = index % width;
        final bool hasLeft = x > 0;
        final bool hasRight = x < width - 1;
        final bool hasUp = index >= width;
        final bool hasDown = index < lastRowStart;

        void tryAdd(int neighbor) {
          if (neighbor < 0 || neighbor >= out.length) {
            return;
          }
          if (out[neighbor] != 0) {
            return;
          }
          out[neighbor] = 1;
          queue.add(neighbor);
        }

        if (hasLeft) {
          tryAdd(index - 1);
        }
        if (hasRight) {
          tryAdd(index + 1);
        }
        if (hasUp) {
          tryAdd(index - width);
          if (hasLeft) {
            tryAdd(index - width - 1);
          }
          if (hasRight) {
            tryAdd(index - width + 1);
          }
        }
        if (hasDown) {
          tryAdd(index + width);
          if (hasLeft) {
            tryAdd(index + width - 1);
          }
          if (hasRight) {
            tryAdd(index + width + 1);
          }
        }
      }
    }
  }

  // Phase 1 (Erosion): erode by dilating the inverse and then inverting.
  dilateFromMaskValue(mask, buffer, 0);
  for (int i = 0; i < length; i++) {
    mask[i] = buffer[i] == 0 ? 1 : 0;
  }

  // Phase 2 (Dilation): dilate eroded mask.
  dilateFromMaskValue(mask, buffer, 1);
  return buffer;
}

int? _fillFindNearestFillableStartIndex({
  required int startIndex,
  required Uint8List fillable,
  required Uint32List pixels,
  required int targetColor,
  required int width,
  required int height,
  required int tolerance,
  required Uint8List? selectionMask,
  required int maxDepth,
}) {
  if (startIndex < 0 || startIndex >= fillable.length) {
    return null;
  }
  if (fillable[startIndex] == 1) {
    return startIndex;
  }

  final Set<int> visited = <int>{startIndex};
  final List<int> queue = <int>[startIndex];
  int head = 0;

  for (int depth = 0; depth <= maxDepth; depth++) {
    final int levelEnd = queue.length;
    while (head < levelEnd) {
      final int index = queue[head++];
      if (fillable[index] == 1) {
        return index;
      }

      final int x = index % width;
      final int y = index ~/ width;

      void tryNeighbor(int nx, int ny) {
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
          return;
        }
        final int neighbor = ny * width + nx;
        if (!visited.add(neighbor)) {
          return;
        }
        if (selectionMask != null && selectionMask[neighbor] == 0) {
          return;
        }
        if (!_fillColorsWithinTolerance(
          pixels[neighbor],
          targetColor,
          tolerance,
        )) {
          return;
        }
        queue.add(neighbor);
      }

      tryNeighbor(x - 1, y);
      tryNeighbor(x + 1, y);
      tryNeighbor(x, y - 1);
      tryNeighbor(x, y + 1);
    }
    if (head >= queue.length) {
      break;
    }
  }
  return null;
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
