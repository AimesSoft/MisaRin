part of 'controller.dart';

void _layerManagerSetActiveLayer(BitmapCanvasController controller, String id) {
  final int index = controller._layers.indexWhere((layer) => layer.id == id);
  if (index < 0 || index == controller._activeIndex) {
    return;
  }
  controller._activeIndex = index;
  controller._resetWorkerSurfaceSync();
  controller._notify();
}

void _layerManagerUpdateVisibility(
  BitmapCanvasController controller,
  String id,
  bool visible,
) {
  final int index = controller._layers.indexWhere((layer) => layer.id == id);
  if (index < 0) {
    return;
  }
  controller._layers[index].visible = visible;
  if (!visible && controller._activeIndex == index) {
    controller._activeIndex = _findFallbackActiveIndex(
      controller,
      exclude: index,
    );
  }
  controller._markDirty(pixelsDirty: false);
}

void _layerManagerSetOpacity(
  BitmapCanvasController controller,
  String id,
  double opacity,
) {
  final int index = controller._layers.indexWhere((layer) => layer.id == id);
  if (index < 0) {
    return;
  }
  final double clamped = BitmapCanvasController._clampUnit(opacity);
  final BitmapLayerState layer = controller._layers[index];
  if ((layer.opacity - clamped).abs() < 1e-4) {
    return;
  }
  layer.opacity = clamped;
  controller._markDirty(pixelsDirty: false);
  controller._notify();
}

void _layerManagerSetLocked(
  BitmapCanvasController controller,
  String id,
  bool locked,
) {
  final int index = controller._layers.indexWhere((layer) => layer.id == id);
  if (index < 0) {
    return;
  }
  final BitmapLayerState layer = controller._layers[index];
  if (layer.locked == locked) {
    return;
  }
  layer.locked = locked;
  controller._notify();
}

void _layerManagerSetClippingMask(
  BitmapCanvasController controller,
  String id,
  bool clippingMask,
) {
  final int index = controller._layers.indexWhere((layer) => layer.id == id);
  if (index < 0) {
    return;
  }
  final BitmapLayerState layer = controller._layers[index];
  if (layer.clippingMask == clippingMask) {
    return;
  }
  layer.clippingMask = clippingMask;
  controller._markDirty(pixelsDirty: false);
  controller._notify();
}

void _layerManagerSetBlendMode(
  BitmapCanvasController controller,
  String id,
  CanvasLayerBlendMode mode,
) {
  final int index = controller._layers.indexWhere((layer) => layer.id == id);
  if (index < 0) {
    return;
  }
  final BitmapLayerState layer = controller._layers[index];
  if (layer.blendMode == mode) {
    return;
  }
  layer.blendMode = mode;
  controller._markDirty(pixelsDirty: false);
  controller._notify();
}

void _layerManagerRenameLayer(
  BitmapCanvasController controller,
  String id,
  String name,
) {
  final int index = controller._layers.indexWhere((layer) => layer.id == id);
  if (index < 0) {
    return;
  }
  controller._layers[index].name = name;
  controller._notify();
}

void _layerManagerAddLayer(
  BitmapCanvasController controller, {
  String? aboveLayerId,
  String? name,
}) {
  final BitmapLayerState layer = BitmapLayerState(
    id: _generateUniqueLayerId(controller),
    name: name ?? '图层 ${controller._layers.length + 1}',
    surface: controller._createLayerSurface(),
  );
  int insertIndex = controller._layers.length;
  if (aboveLayerId != null) {
    final int index = controller._layers.indexWhere(
      (candidate) => candidate.id == aboveLayerId,
    );
    if (index >= 0) {
      insertIndex = index + 1;
    }
  }
  controller._layers.insert(insertIndex, layer);
  controller._activeIndex = insertIndex;
  controller._resetWorkerSurfaceSync();
  controller._layerOverflowStores[layer.id] = _LayerOverflowStore();
  controller._markDirty(pixelsDirty: false);
}

bool _layerIdExists(BitmapCanvasController controller, String id) {
  for (final BitmapLayerState layer in controller._layers) {
    if (layer.id == id) {
      return true;
    }
  }
  return false;
}

String _generateUniqueLayerId(BitmapCanvasController controller) {
  String id = generateLayerId();
  while (_layerIdExists(controller, id)) {
    id = generateLayerId();
  }
  return id;
}

String _resolveUniqueLayerId(
  BitmapCanvasController controller,
  String preferredId,
) {
  if (!_layerIdExists(controller, preferredId)) {
    return preferredId;
  }
  return _generateUniqueLayerId(controller);
}

void _layerManagerRemoveLayer(BitmapCanvasController controller, String id) {
  if (controller._layers.length <= 1) {
    return;
  }
  final int index = controller._layers.indexWhere((layer) => layer.id == id);
  if (index < 0) {
    return;
  }
  controller._layers.removeAt(index);
  controller._layerOverflowStores.remove(id);
  controller._rustWgpuBrushSyncedRevisions.remove(id);
  unawaited(() async {
    try {
      await ensureRustInitialized();
      rust_wgpu_brush.rustWgpuRemoveLayer(layerId: id);
    } catch (_) {}
  }());
  if (controller._activeIndex >= controller._layers.length) {
    controller._activeIndex = controller._layers.length - 1;
  }
  controller._resetWorkerSurfaceSync();
  controller._markDirty(pixelsDirty: false);
}

void _layerManagerReorderLayer(
  BitmapCanvasController controller,
  int fromIndex,
  int toIndex,
) {
  if (fromIndex < 0 || fromIndex >= controller._layers.length) {
    return;
  }
  int target = toIndex;
  if (target > fromIndex) {
    target -= 1;
  }
  target = target.clamp(0, controller._layers.length - 1);
  final BitmapLayerState layer = controller._layers.removeAt(fromIndex);
  controller._layers.insert(target, layer);
  if (controller._activeIndex == fromIndex) {
    controller._activeIndex = target;
  } else if (fromIndex < controller._activeIndex &&
      target >= controller._activeIndex) {
    controller._activeIndex -= 1;
  } else if (fromIndex > controller._activeIndex &&
      target <= controller._activeIndex) {
    controller._activeIndex += 1;
  }
  controller._resetWorkerSurfaceSync();
  controller._markDirty(pixelsDirty: false);
}

bool _layerManagerMergeLayerDown(BitmapCanvasController controller, String id) {
  final List<BitmapLayerState> layers = controller._layers;
  final int index = layers.indexWhere((layer) => layer.id == id);
  if (index <= 0) {
    return false;
  }
  final BitmapLayerState upper = layers[index];
  if (upper.locked) {
    return false;
  }
  final BitmapLayerState lower = layers[index - 1];
  if (lower.locked) {
    return false;
  }
  final double opacity = upper.visible
      ? BitmapCanvasController._clampUnit(upper.opacity)
      : 0.0;
  final bool hasSurfaceContent = !BitmapCanvasController._isSurfaceEmpty(
    upper.surface,
  );
  final _LayerOverflowStore upperOverflow =
      controller._layerOverflowStores[upper.id] ?? _LayerOverflowStore();
  final bool hasOverflowContent = !upperOverflow.isEmpty;

  if (opacity > 0 && (hasSurfaceContent || hasOverflowContent)) {
    final _LayerOverflowStore lowerOverflow =
        controller._layerOverflowStores[lower.id] ?? _LayerOverflowStore();
    _mergeLayerIntoLower(
      controller,
      upper,
      lower,
      index,
      opacity,
      lowerOverflow,
      upperOverflow,
    );
    lower.surface.markDirty();
  }

  layers.removeAt(index);
  controller._layerOverflowStores.remove(upper.id);
  if (controller._activeIndex >= index) {
    if (controller._activeIndex == index) {
      controller._activeIndex = index - 1;
    } else {
      controller._activeIndex -= 1;
    }
  }
  controller._markDirty(layerId: lower.id, pixelsDirty: true);
  return true;
}

void _layerManagerClearAll(BitmapCanvasController controller) {
  for (int i = 0; i < controller._layers.length; i++) {
    final BitmapLayerState layer = controller._layers[i];
    if (layer.locked) {
      continue;
    }
    if (i == 0) {
      layer.surface.fill(controller._backgroundColor);
    } else {
      layer.surface.fill(const Color(0x00000000));
    }
  }
  controller._markDirty(pixelsDirty: true);
}

void _mergeLayerIntoLower(
  BitmapCanvasController controller,
  BitmapLayerState upper,
  BitmapLayerState lower,
  int upperIndex,
  double opacity,
  _LayerOverflowStore lowerOverflow,
  _LayerOverflowStore upperOverflow,
) {
  final bool hasClipping = upper.clippingMask;
  final _ClippingMaskInfo? clippingInfo = hasClipping
      ? _resolveClippingMaskInfo(controller, upperIndex)
      : null;
  if (hasClipping && clippingInfo == null) {
    return;
  }
  final bool needsBitmap =
      upper.surface.isTiled || lower.surface.isTiled;
  if (needsBitmap) {
    final bool rustBlend = RustCpuBlendFfi.instance.isSupported;
    if (rustBlend && lower.surface.isTiled) {
      if (upper.surface.isTiled) {
        if (clippingInfo == null) {
          _mergeTiledLayersNoMask(
            controller,
            upper,
            lower,
            opacity,
          );
        } else if (clippingInfo.layer.surface.isTiled) {
          _mergeTiledLayersWithMask(
            controller,
            upper,
            lower,
            clippingInfo,
            opacity,
          );
        } else {
          _mergeTiledLayersWithBitmapMask(
            controller,
            upper,
            lower,
            clippingInfo,
            opacity,
          );
        }
      } else {
        if (clippingInfo == null) {
          _mergeBitmapUpperIntoTiledLowerNoMask(
            controller,
            upper,
            lower,
            opacity,
          );
        } else if (clippingInfo.layer.surface.isTiled) {
          _mergeBitmapUpperIntoTiledLowerWithMask(
            controller,
            upper,
            lower,
            clippingInfo,
            opacity,
          );
        } else {
          _mergeBitmapUpperIntoTiledLowerWithBitmapMask(
            controller,
            upper,
            lower,
            clippingInfo,
            opacity,
          );
        }
      }
      _blendOverflowPixelsNoCanvas(
        controller,
        upperOverflow,
        lower,
        lowerOverflow,
        opacity,
        upper.blendMode,
        clippingInfo,
      );
      return;
    }
    if (rustBlend && upper.surface.isTiled && !lower.surface.isTiled) {
      if (clippingInfo == null) {
        _mergeTiledUpperIntoBitmapLowerNoMask(
          controller,
          upper,
          lower,
          opacity,
        );
        _blendOverflowPixels(
          controller,
          upperOverflow,
          lower,
          lowerOverflow,
          opacity,
          upper.blendMode,
          null,
        );
        return;
      }
      if (clippingInfo.layer.surface.isTiled) {
        _mergeTiledUpperIntoBitmapLowerWithMask(
          controller,
          upper,
          lower,
          clippingInfo,
          opacity,
        );
        _blendOverflowPixelsNoCanvas(
          controller,
          upperOverflow,
          lower,
          lowerOverflow,
          opacity,
          upper.blendMode,
          clippingInfo,
        );
        return;
      }
      _mergeTiledUpperIntoBitmapLowerWithBitmapMask(
        controller,
        upper,
        lower,
        clippingInfo,
        opacity,
      );
      _blendOverflowPixels(
        controller,
        upperOverflow,
        lower,
        lowerOverflow,
        opacity,
        upper.blendMode,
        clippingInfo,
      );
      return;
    }
    if (clippingInfo != null && clippingInfo.layer.surface.isTiled) {
      clippingInfo.layer.surface.withBitmapSurface(
        writeBack: false,
        action: (BitmapSurface maskSurface) {
          upper.surface.withBitmapSurface(
            writeBack: false,
            action: (BitmapSurface upperSurface) {
              lower.surface.withBitmapSurface(
                writeBack: true,
                action: (BitmapSurface lowerSurface) {
                  _blendOnCanvasPixels(
                    controller,
                    upperSurface.pixels,
                    lowerSurface.pixels,
                    opacity,
                    upper.blendMode,
                    clippingInfo,
                    srcPixelsPtr: upperSurface.pointerAddress,
                    dstPixelsPtr: lowerSurface.pointerAddress,
                    maskPtrOverride: maskSurface.pointerAddress,
                    maskLenOverride: maskSurface.pixels.length,
                    maskOpacityOverride: clippingInfo.opacity,
                  );
                  if (!upperOverflow.isEmpty) {
                    _blendOverflowPixels(
                      controller,
                      upperOverflow,
                      lower,
                      lowerOverflow,
                      opacity,
                      upper.blendMode,
                      clippingInfo,
                      canvasPtrOverride: lowerSurface.pointerAddress,
                      canvasLenOverride: lowerSurface.pixels.length,
                      maskPtrOverride: maskSurface.pointerAddress,
                      maskLenOverride: maskSurface.pixels.length,
                      maskOpacityOverride: clippingInfo.opacity,
                    );
                  }
                },
              );
            },
          );
        },
      );
    } else {
      upper.surface.withBitmapSurface(
        writeBack: false,
        action: (BitmapSurface upperSurface) {
          lower.surface.withBitmapSurface(
            writeBack: true,
            action: (BitmapSurface lowerSurface) {
              _blendOnCanvasPixels(
                controller,
                upperSurface.pixels,
                lowerSurface.pixels,
                opacity,
                upper.blendMode,
                clippingInfo,
                srcPixelsPtr: upperSurface.pointerAddress,
                dstPixelsPtr: lowerSurface.pointerAddress,
              );
              if (!upperOverflow.isEmpty) {
                _blendOverflowPixels(
                  controller,
                  upperOverflow,
                  lower,
                  lowerOverflow,
                  opacity,
                  upper.blendMode,
                  clippingInfo,
                  canvasPtrOverride: lowerSurface.pointerAddress,
                  canvasLenOverride: lowerSurface.pixels.length,
                );
              }
            },
          );
        },
      );
    }
    return;
  }

  _blendOnCanvasPixels(
    controller,
    upper.surface.pixels,
    lower.surface.pixels,
    opacity,
    upper.blendMode,
    clippingInfo,
    srcPixelsPtr: upper.surface.pointerAddress,
    dstPixelsPtr: lower.surface.pointerAddress,
  );
  if (!upperOverflow.isEmpty) {
    _blendOverflowPixels(
      controller,
      upperOverflow,
      lower,
      lowerOverflow,
      opacity,
      upper.blendMode,
      clippingInfo,
    );
  }
}

void _mergeTiledLayersNoMask(
  BitmapCanvasController controller,
  BitmapLayerState upper,
  BitmapLayerState lower,
  double opacity,
) {
  final TiledSurface upperTiled = upper.surface.tiledSurface!;
  final TiledSurface lowerTiled = lower.surface.tiledSurface!;
  final RasterIntRect? upperBounds = _surfaceContentBounds(
    controller,
    upper.surface,
  );
  if (upperBounds == null || upperBounds.isEmpty) {
    return;
  }
  final int tileSize = lowerTiled.tileSize;
  final int startTx = tileIndexForCoord(upperBounds.left, tileSize);
  final int endTx = tileIndexForCoord(upperBounds.right - 1, tileSize);
  final int startTy = tileIndexForCoord(upperBounds.top, tileSize);
  final int endTy = tileIndexForCoord(upperBounds.bottom - 1, tileSize);

  final Color? upperDefault = upperTiled.defaultFill;
  final int upperDefaultArgb =
      upperDefault == null ? 0 : BitmapSurface.encodeColor(upperDefault);
  BitmapSurface? defaultUpperSurface;
  if (upperDefaultArgb != 0) {
    defaultUpperSurface = BitmapSurface(
      width: tileSize,
      height: tileSize,
      fillColor: upperDefault,
    );
  }

  for (int ty = startTy; ty <= endTy; ty++) {
    for (int tx = startTx; tx <= endTx; tx++) {
      final RasterIntRect tileRect = tileBounds(tx, ty, tileSize);
      final int left = math.max(tileRect.left, upperBounds.left);
      final int top = math.max(tileRect.top, upperBounds.top);
      final int right = math.min(tileRect.right, upperBounds.right);
      final int bottom = math.min(tileRect.bottom, upperBounds.bottom);
      if (left >= right || top >= bottom) {
        continue;
      }
      BitmapSurface? srcSurface = upperTiled.getTile(tx, ty);
      if (srcSurface == null) {
        if (defaultUpperSurface == null) {
          continue;
        }
        srcSurface = defaultUpperSurface;
      }
      final BitmapSurface dstSurface =
          lowerTiled.getTile(tx, ty) ?? lowerTiled.ensureTile(tx, ty);
      final int localStartX = left - tileRect.left;
      final int localEndX = right - tileRect.left;
      final int localStartY = top - tileRect.top;
      final int localEndY = bottom - tileRect.top;
      final bool ok = RustCpuBlendFfi.instance.blendOnCanvas(
        srcPtr: srcSurface.pointerAddress,
        dstPtr: dstSurface.pointerAddress,
        pixelsLen: dstSurface.pixels.length,
        width: tileSize,
        height: tileSize,
        startX: localStartX,
        endX: localEndX,
        startY: localStartY,
        endY: localEndY,
        opacity: opacity,
        blendMode: upper.blendMode.index,
      );
      if (ok) {
        dstSurface.markDirty();
      }
    }
  }
  defaultUpperSurface?.dispose();
}

void _mergeTiledUpperIntoBitmapLowerNoMask(
  BitmapCanvasController controller,
  BitmapLayerState upper,
  BitmapLayerState lower,
  double opacity,
) {
  final TiledSurface upperTiled = upper.surface.tiledSurface!;
  final BitmapSurface? lowerBitmap = lower.surface.bitmapSurface;
  if (lowerBitmap == null) {
    return;
  }
  final RasterIntRect? upperBounds = _surfaceContentBounds(
    controller,
    upper.surface,
  );
  if (upperBounds == null || upperBounds.isEmpty) {
    return;
  }

  final int tileSize = upperTiled.tileSize;
  final int startTx = tileIndexForCoord(upperBounds.left, tileSize);
  final int endTx = tileIndexForCoord(upperBounds.right - 1, tileSize);
  final int startTy = tileIndexForCoord(upperBounds.top, tileSize);
  final int endTy = tileIndexForCoord(upperBounds.bottom - 1, tileSize);

  final Color? upperDefault = upperTiled.defaultFill;
  final int upperDefaultArgb =
      upperDefault == null ? 0 : BitmapSurface.encodeColor(upperDefault);
  BitmapSurface? defaultUpperSurface;
  if (upperDefaultArgb != 0) {
    defaultUpperSurface = BitmapSurface(
      width: tileSize,
      height: tileSize,
      fillColor: upperDefault,
    );
  }

  final BitmapSurface tempDest = BitmapSurface(
    width: tileSize,
    height: tileSize,
  );
  final Uint32List lowerPixels = lowerBitmap.pixels;
  final int lowerWidth = lowerBitmap.width;

  for (int ty = startTy; ty <= endTy; ty++) {
    for (int tx = startTx; tx <= endTx; tx++) {
      final RasterIntRect tileRect = tileBounds(tx, ty, tileSize);
      final int left = math.max(tileRect.left, upperBounds.left);
      final int top = math.max(tileRect.top, upperBounds.top);
      final int right = math.min(tileRect.right, upperBounds.right);
      final int bottom = math.min(tileRect.bottom, upperBounds.bottom);
      if (left >= right || top >= bottom) {
        continue;
      }
      BitmapSurface? srcSurface = upperTiled.getTile(tx, ty);
      if (srcSurface == null) {
        if (defaultUpperSurface == null) {
          continue;
        }
        srcSurface = defaultUpperSurface;
      }
      final int localStartX = left - tileRect.left;
      final int localEndX = right - tileRect.left;
      final int localStartY = top - tileRect.top;
      final int localEndY = bottom - tileRect.top;

      final RasterIntRect rect = RasterIntRect(left, top, right, bottom);
      for (int row = 0; row < rect.height; row++) {
        final int srcRow = (top + row) * lowerWidth + left;
        final int dstRow = (localStartY + row) * tileSize + localStartX;
        tempDest.pixels.setRange(
          dstRow,
          dstRow + rect.width,
          lowerPixels,
          srcRow,
        );
      }

      final bool ok = RustCpuBlendFfi.instance.blendOnCanvas(
        srcPtr: srcSurface.pointerAddress,
        dstPtr: tempDest.pointerAddress,
        pixelsLen: tempDest.pixels.length,
        width: tileSize,
        height: tileSize,
        startX: localStartX,
        endX: localEndX,
        startY: localStartY,
        endY: localEndY,
        opacity: opacity,
        blendMode: upper.blendMode.index,
      );
      if (ok) {
        for (int row = 0; row < rect.height; row++) {
          final int srcRow =
              (localStartY + row) * tileSize + localStartX;
          final int dstRow = (top + row) * lowerWidth + left;
          lowerPixels.setRange(
            dstRow,
            dstRow + rect.width,
            tempDest.pixels,
            srcRow,
          );
        }
      }
    }
  }

  tempDest.dispose();
  defaultUpperSurface?.dispose();
}

void _mergeBitmapUpperIntoTiledLowerNoMask(
  BitmapCanvasController controller,
  BitmapLayerState upper,
  BitmapLayerState lower,
  double opacity,
) {
  final BitmapSurface? upperBitmap = upper.surface.bitmapSurface;
  if (upperBitmap == null) {
    return;
  }
  final TiledSurface lowerTiled = lower.surface.tiledSurface!;
  final RasterIntRect? upperBounds = _surfaceContentBounds(
    controller,
    upper.surface,
  );
  if (upperBounds == null || upperBounds.isEmpty) {
    return;
  }

  final int tileSize = lowerTiled.tileSize;
  final int startTx = tileIndexForCoord(upperBounds.left, tileSize);
  final int endTx = tileIndexForCoord(upperBounds.right - 1, tileSize);
  final int startTy = tileIndexForCoord(upperBounds.top, tileSize);
  final int endTy = tileIndexForCoord(upperBounds.bottom - 1, tileSize);

  final BitmapSurface tempSrc = BitmapSurface(
    width: tileSize,
    height: tileSize,
  );
  final Uint32List upperPixels = upperBitmap.pixels;
  final int upperWidth = upperBitmap.width;

  for (int ty = startTy; ty <= endTy; ty++) {
    for (int tx = startTx; tx <= endTx; tx++) {
      final RasterIntRect tileRect = tileBounds(tx, ty, tileSize);
      final int left = math.max(tileRect.left, upperBounds.left);
      final int top = math.max(tileRect.top, upperBounds.top);
      final int right = math.min(tileRect.right, upperBounds.right);
      final int bottom = math.min(tileRect.bottom, upperBounds.bottom);
      if (left >= right || top >= bottom) {
        continue;
      }

      final RasterIntRect rect = RasterIntRect(left, top, right, bottom);
      final int localStartX = left - tileRect.left;
      final int localEndX = right - tileRect.left;
      final int localStartY = top - tileRect.top;
      final int localEndY = bottom - tileRect.top;
      for (int row = 0; row < rect.height; row++) {
        final int srcRow = (top + row) * upperWidth + left;
        final int dstRow = (localStartY + row) * tileSize + localStartX;
        tempSrc.pixels.setRange(
          dstRow,
          dstRow + rect.width,
          upperPixels,
          srcRow,
        );
      }

      final BitmapSurface dstSurface =
          lowerTiled.getTile(tx, ty) ?? lowerTiled.ensureTile(tx, ty);
      final bool ok = RustCpuBlendFfi.instance.blendOnCanvas(
        srcPtr: tempSrc.pointerAddress,
        dstPtr: dstSurface.pointerAddress,
        pixelsLen: dstSurface.pixels.length,
        width: tileSize,
        height: tileSize,
        startX: localStartX,
        endX: localEndX,
        startY: localStartY,
        endY: localEndY,
        opacity: opacity,
        blendMode: upper.blendMode.index,
      );
      if (ok) {
        dstSurface.markDirty();
      }
    }
  }

  tempSrc.dispose();
}

void _mergeTiledLayersWithBitmapMask(
  BitmapCanvasController controller,
  BitmapLayerState upper,
  BitmapLayerState lower,
  _ClippingMaskInfo clippingInfo,
  double opacity,
) {
  final TiledSurface upperTiled = upper.surface.tiledSurface!;
  final TiledSurface lowerTiled = lower.surface.tiledSurface!;
  final BitmapSurface? maskBitmap = clippingInfo.layer.surface.bitmapSurface;
  if (maskBitmap == null) {
    return;
  }
  final RasterIntRect? upperBounds = _surfaceContentBounds(
    controller,
    upper.surface,
  );
  if (upperBounds == null || upperBounds.isEmpty) {
    return;
  }
  final RasterIntRect? maskBounds = _surfaceContentBounds(
    controller,
    clippingInfo.layer.surface,
  );
  if (maskBounds == null || maskBounds.isEmpty) {
    return;
  }
  final int blendLeft = math.max(upperBounds.left, maskBounds.left);
  final int blendTop = math.max(upperBounds.top, maskBounds.top);
  final int blendRight = math.min(upperBounds.right, maskBounds.right);
  final int blendBottom = math.min(upperBounds.bottom, maskBounds.bottom);
  if (blendLeft >= blendRight || blendTop >= blendBottom) {
    return;
  }
  final RasterIntRect blendBounds =
      RasterIntRect(blendLeft, blendTop, blendRight, blendBottom);

  final int tileSize = lowerTiled.tileSize;
  final int startTx = tileIndexForCoord(blendBounds.left, tileSize);
  final int endTx = tileIndexForCoord(blendBounds.right - 1, tileSize);
  final int startTy = tileIndexForCoord(blendBounds.top, tileSize);
  final int endTy = tileIndexForCoord(blendBounds.bottom - 1, tileSize);

  final Color? upperDefault = upperTiled.defaultFill;
  final int upperDefaultArgb =
      upperDefault == null ? 0 : BitmapSurface.encodeColor(upperDefault);
  BitmapSurface? defaultUpperSurface;
  if (upperDefaultArgb != 0) {
    defaultUpperSurface = BitmapSurface(
      width: tileSize,
      height: tileSize,
      fillColor: upperDefault,
    );
  }

  final BitmapSurface tempMask = BitmapSurface(
    width: tileSize,
    height: tileSize,
  );
  final Uint32List maskPixels = maskBitmap.pixels;
  final int maskWidth = maskBitmap.width;

  for (int ty = startTy; ty <= endTy; ty++) {
    for (int tx = startTx; tx <= endTx; tx++) {
      final RasterIntRect tileRect = tileBounds(tx, ty, tileSize);
      final int left = math.max(tileRect.left, blendBounds.left);
      final int top = math.max(tileRect.top, blendBounds.top);
      final int right = math.min(tileRect.right, blendBounds.right);
      final int bottom = math.min(tileRect.bottom, blendBounds.bottom);
      if (left >= right || top >= bottom) {
        continue;
      }
      BitmapSurface? srcSurface = upperTiled.getTile(tx, ty);
      if (srcSurface == null) {
        if (defaultUpperSurface == null) {
          continue;
        }
        srcSurface = defaultUpperSurface;
      }
      final BitmapSurface dstSurface =
          lowerTiled.getTile(tx, ty) ?? lowerTiled.ensureTile(tx, ty);
      final int localStartX = left - tileRect.left;
      final int localEndX = right - tileRect.left;
      final int localStartY = top - tileRect.top;
      final int localEndY = bottom - tileRect.top;

      final bool fullTile = left == tileRect.left &&
          top == tileRect.top &&
          right == tileRect.right &&
          bottom == tileRect.bottom &&
          tileRect.width == tileSize &&
          tileRect.height == tileSize;
      if (!fullTile) {
        tempMask.pixels.fillRange(0, tempMask.pixels.length, 0);
      }
      final RasterIntRect rect = RasterIntRect(left, top, right, bottom);
      for (int row = 0; row < rect.height; row++) {
        final int srcRow = (top + row) * maskWidth + left;
        final int dstRow = (localStartY + row) * tileSize + localStartX;
        tempMask.pixels.setRange(
          dstRow,
          dstRow + rect.width,
          maskPixels,
          srcRow,
        );
      }

      final bool ok = RustCpuBlendFfi.instance.blendOnCanvas(
        srcPtr: srcSurface.pointerAddress,
        dstPtr: dstSurface.pointerAddress,
        pixelsLen: dstSurface.pixels.length,
        width: tileSize,
        height: tileSize,
        startX: localStartX,
        endX: localEndX,
        startY: localStartY,
        endY: localEndY,
        opacity: opacity,
        blendMode: upper.blendMode.index,
        maskPtr: tempMask.pointerAddress,
        maskLen: tempMask.pixels.length,
        maskOpacity: clippingInfo.opacity,
      );
      if (ok) {
        dstSurface.markDirty();
      }
    }
  }

  tempMask.dispose();
  defaultUpperSurface?.dispose();
}

void _mergeTiledUpperIntoBitmapLowerWithBitmapMask(
  BitmapCanvasController controller,
  BitmapLayerState upper,
  BitmapLayerState lower,
  _ClippingMaskInfo clippingInfo,
  double opacity,
) {
  final TiledSurface upperTiled = upper.surface.tiledSurface!;
  final BitmapSurface? lowerBitmap = lower.surface.bitmapSurface;
  final BitmapSurface? maskBitmap = clippingInfo.layer.surface.bitmapSurface;
  if (lowerBitmap == null || maskBitmap == null) {
    return;
  }
  final RasterIntRect? upperBounds = _surfaceContentBounds(
    controller,
    upper.surface,
  );
  if (upperBounds == null || upperBounds.isEmpty) {
    return;
  }
  final RasterIntRect? maskBounds = _surfaceContentBounds(
    controller,
    clippingInfo.layer.surface,
  );
  if (maskBounds == null || maskBounds.isEmpty) {
    return;
  }
  final int blendLeft = math.max(upperBounds.left, maskBounds.left);
  final int blendTop = math.max(upperBounds.top, maskBounds.top);
  final int blendRight = math.min(upperBounds.right, maskBounds.right);
  final int blendBottom = math.min(upperBounds.bottom, maskBounds.bottom);
  if (blendLeft >= blendRight || blendTop >= blendBottom) {
    return;
  }
  final RasterIntRect blendBounds =
      RasterIntRect(blendLeft, blendTop, blendRight, blendBottom);

  final int tileSize = upperTiled.tileSize;
  final int startTx = tileIndexForCoord(blendBounds.left, tileSize);
  final int endTx = tileIndexForCoord(blendBounds.right - 1, tileSize);
  final int startTy = tileIndexForCoord(blendBounds.top, tileSize);
  final int endTy = tileIndexForCoord(blendBounds.bottom - 1, tileSize);

  final Color? upperDefault = upperTiled.defaultFill;
  final int upperDefaultArgb =
      upperDefault == null ? 0 : BitmapSurface.encodeColor(upperDefault);
  BitmapSurface? defaultUpperSurface;
  if (upperDefaultArgb != 0) {
    defaultUpperSurface = BitmapSurface(
      width: tileSize,
      height: tileSize,
      fillColor: upperDefault,
    );
  }

  final BitmapSurface tempDest = BitmapSurface(
    width: tileSize,
    height: tileSize,
  );
  final BitmapSurface tempMask = BitmapSurface(
    width: tileSize,
    height: tileSize,
  );
  final Uint32List lowerPixels = lowerBitmap.pixels;
  final int lowerWidth = lowerBitmap.width;
  final Uint32List maskPixels = maskBitmap.pixels;
  final int maskWidth = maskBitmap.width;

  for (int ty = startTy; ty <= endTy; ty++) {
    for (int tx = startTx; tx <= endTx; tx++) {
      final RasterIntRect tileRect = tileBounds(tx, ty, tileSize);
      final int left = math.max(tileRect.left, blendBounds.left);
      final int top = math.max(tileRect.top, blendBounds.top);
      final int right = math.min(tileRect.right, blendBounds.right);
      final int bottom = math.min(tileRect.bottom, blendBounds.bottom);
      if (left >= right || top >= bottom) {
        continue;
      }
      BitmapSurface? srcSurface = upperTiled.getTile(tx, ty);
      if (srcSurface == null) {
        if (defaultUpperSurface == null) {
          continue;
        }
        srcSurface = defaultUpperSurface;
      }
      final int localStartX = left - tileRect.left;
      final int localEndX = right - tileRect.left;
      final int localStartY = top - tileRect.top;
      final int localEndY = bottom - tileRect.top;

      final RasterIntRect rect = RasterIntRect(left, top, right, bottom);
      for (int row = 0; row < rect.height; row++) {
        final int srcRow = (top + row) * lowerWidth + left;
        final int dstRow = (localStartY + row) * tileSize + localStartX;
        tempDest.pixels.setRange(
          dstRow,
          dstRow + rect.width,
          lowerPixels,
          srcRow,
        );
      }

      final bool fullTile = left == tileRect.left &&
          top == tileRect.top &&
          right == tileRect.right &&
          bottom == tileRect.bottom &&
          tileRect.width == tileSize &&
          tileRect.height == tileSize;
      if (!fullTile) {
        tempMask.pixels.fillRange(0, tempMask.pixels.length, 0);
      }
      for (int row = 0; row < rect.height; row++) {
        final int srcRow = (top + row) * maskWidth + left;
        final int dstRow = (localStartY + row) * tileSize + localStartX;
        tempMask.pixels.setRange(
          dstRow,
          dstRow + rect.width,
          maskPixels,
          srcRow,
        );
      }

      final bool ok = RustCpuBlendFfi.instance.blendOnCanvas(
        srcPtr: srcSurface.pointerAddress,
        dstPtr: tempDest.pointerAddress,
        pixelsLen: tempDest.pixels.length,
        width: tileSize,
        height: tileSize,
        startX: localStartX,
        endX: localEndX,
        startY: localStartY,
        endY: localEndY,
        opacity: opacity,
        blendMode: upper.blendMode.index,
        maskPtr: tempMask.pointerAddress,
        maskLen: tempMask.pixels.length,
        maskOpacity: clippingInfo.opacity,
      );
      if (ok) {
        for (int row = 0; row < rect.height; row++) {
          final int srcRow =
              (localStartY + row) * tileSize + localStartX;
          final int dstRow = (top + row) * lowerWidth + left;
          lowerPixels.setRange(
            dstRow,
            dstRow + rect.width,
            tempDest.pixels,
            srcRow,
          );
        }
      }
    }
  }

  tempDest.dispose();
  tempMask.dispose();
  defaultUpperSurface?.dispose();
}

void _mergeBitmapUpperIntoTiledLowerWithBitmapMask(
  BitmapCanvasController controller,
  BitmapLayerState upper,
  BitmapLayerState lower,
  _ClippingMaskInfo clippingInfo,
  double opacity,
) {
  final BitmapSurface? upperBitmap = upper.surface.bitmapSurface;
  final BitmapSurface? maskBitmap = clippingInfo.layer.surface.bitmapSurface;
  if (upperBitmap == null || maskBitmap == null) {
    return;
  }
  final TiledSurface lowerTiled = lower.surface.tiledSurface!;
  final RasterIntRect? upperBounds = _surfaceContentBounds(
    controller,
    upper.surface,
  );
  if (upperBounds == null || upperBounds.isEmpty) {
    return;
  }
  final RasterIntRect? maskBounds = _surfaceContentBounds(
    controller,
    clippingInfo.layer.surface,
  );
  if (maskBounds == null || maskBounds.isEmpty) {
    return;
  }
  final int blendLeft = math.max(upperBounds.left, maskBounds.left);
  final int blendTop = math.max(upperBounds.top, maskBounds.top);
  final int blendRight = math.min(upperBounds.right, maskBounds.right);
  final int blendBottom = math.min(upperBounds.bottom, maskBounds.bottom);
  if (blendLeft >= blendRight || blendTop >= blendBottom) {
    return;
  }
  final RasterIntRect blendBounds =
      RasterIntRect(blendLeft, blendTop, blendRight, blendBottom);

  final int tileSize = lowerTiled.tileSize;
  final int startTx = tileIndexForCoord(blendBounds.left, tileSize);
  final int endTx = tileIndexForCoord(blendBounds.right - 1, tileSize);
  final int startTy = tileIndexForCoord(blendBounds.top, tileSize);
  final int endTy = tileIndexForCoord(blendBounds.bottom - 1, tileSize);

  final BitmapSurface tempSrc = BitmapSurface(
    width: tileSize,
    height: tileSize,
  );
  final BitmapSurface tempMask = BitmapSurface(
    width: tileSize,
    height: tileSize,
  );
  final Uint32List upperPixels = upperBitmap.pixels;
  final int upperWidth = upperBitmap.width;
  final Uint32List maskPixels = maskBitmap.pixels;
  final int maskWidth = maskBitmap.width;

  for (int ty = startTy; ty <= endTy; ty++) {
    for (int tx = startTx; tx <= endTx; tx++) {
      final RasterIntRect tileRect = tileBounds(tx, ty, tileSize);
      final int left = math.max(tileRect.left, blendBounds.left);
      final int top = math.max(tileRect.top, blendBounds.top);
      final int right = math.min(tileRect.right, blendBounds.right);
      final int bottom = math.min(tileRect.bottom, blendBounds.bottom);
      if (left >= right || top >= bottom) {
        continue;
      }
      final int localStartX = left - tileRect.left;
      final int localEndX = right - tileRect.left;
      final int localStartY = top - tileRect.top;
      final int localEndY = bottom - tileRect.top;

      final RasterIntRect rect = RasterIntRect(left, top, right, bottom);
      for (int row = 0; row < rect.height; row++) {
        final int srcRow = (top + row) * upperWidth + left;
        final int dstRow = (localStartY + row) * tileSize + localStartX;
        tempSrc.pixels.setRange(
          dstRow,
          dstRow + rect.width,
          upperPixels,
          srcRow,
        );
      }

      final bool fullTile = left == tileRect.left &&
          top == tileRect.top &&
          right == tileRect.right &&
          bottom == tileRect.bottom &&
          tileRect.width == tileSize &&
          tileRect.height == tileSize;
      if (!fullTile) {
        tempMask.pixels.fillRange(0, tempMask.pixels.length, 0);
      }
      for (int row = 0; row < rect.height; row++) {
        final int srcRow = (top + row) * maskWidth + left;
        final int dstRow = (localStartY + row) * tileSize + localStartX;
        tempMask.pixels.setRange(
          dstRow,
          dstRow + rect.width,
          maskPixels,
          srcRow,
        );
      }

      final BitmapSurface dstSurface =
          lowerTiled.getTile(tx, ty) ?? lowerTiled.ensureTile(tx, ty);
      final bool ok = RustCpuBlendFfi.instance.blendOnCanvas(
        srcPtr: tempSrc.pointerAddress,
        dstPtr: dstSurface.pointerAddress,
        pixelsLen: dstSurface.pixels.length,
        width: tileSize,
        height: tileSize,
        startX: localStartX,
        endX: localEndX,
        startY: localStartY,
        endY: localEndY,
        opacity: opacity,
        blendMode: upper.blendMode.index,
        maskPtr: tempMask.pointerAddress,
        maskLen: tempMask.pixels.length,
        maskOpacity: clippingInfo.opacity,
      );
      if (ok) {
        dstSurface.markDirty();
      }
    }
  }

  tempSrc.dispose();
  tempMask.dispose();
}

void _mergeTiledUpperIntoBitmapLowerWithMask(
  BitmapCanvasController controller,
  BitmapLayerState upper,
  BitmapLayerState lower,
  _ClippingMaskInfo clippingInfo,
  double opacity,
) {
  final TiledSurface upperTiled = upper.surface.tiledSurface!;
  final TiledSurface maskTiled = clippingInfo.layer.surface.tiledSurface!;
  final BitmapSurface? lowerBitmap = lower.surface.bitmapSurface;
  if (lowerBitmap == null) {
    return;
  }
  final RasterIntRect? upperBounds = _surfaceContentBounds(
    controller,
    upper.surface,
  );
  if (upperBounds == null || upperBounds.isEmpty) {
    return;
  }
  final RasterIntRect? maskBounds = _surfaceContentBounds(
    controller,
    clippingInfo.layer.surface,
  );
  if (maskBounds == null || maskBounds.isEmpty) {
    return;
  }
  final int blendLeft = math.max(upperBounds.left, maskBounds.left);
  final int blendTop = math.max(upperBounds.top, maskBounds.top);
  final int blendRight = math.min(upperBounds.right, maskBounds.right);
  final int blendBottom = math.min(upperBounds.bottom, maskBounds.bottom);
  if (blendLeft >= blendRight || blendTop >= blendBottom) {
    return;
  }
  final RasterIntRect blendBounds =
      RasterIntRect(blendLeft, blendTop, blendRight, blendBottom);

  final int tileSize = upperTiled.tileSize;
  final int startTx = tileIndexForCoord(blendBounds.left, tileSize);
  final int endTx = tileIndexForCoord(blendBounds.right - 1, tileSize);
  final int startTy = tileIndexForCoord(blendBounds.top, tileSize);
  final int endTy = tileIndexForCoord(blendBounds.bottom - 1, tileSize);

  final Color? upperDefault = upperTiled.defaultFill;
  final int upperDefaultArgb =
      upperDefault == null ? 0 : BitmapSurface.encodeColor(upperDefault);
  BitmapSurface? defaultUpperSurface;
  if (upperDefaultArgb != 0) {
    defaultUpperSurface = BitmapSurface(
      width: tileSize,
      height: tileSize,
      fillColor: upperDefault,
    );
  }

  final Color? maskDefault = maskTiled.defaultFill;
  final int maskDefaultArgb =
      maskDefault == null ? 0 : BitmapSurface.encodeColor(maskDefault);
  BitmapSurface? defaultMaskSurface;
  if (maskDefaultArgb != 0) {
    defaultMaskSurface = BitmapSurface(
      width: tileSize,
      height: tileSize,
      fillColor: maskDefault,
    );
  }

  final BitmapSurface tempDest = BitmapSurface(
    width: tileSize,
    height: tileSize,
  );
  final Uint32List lowerPixels = lowerBitmap.pixels;
  final int lowerWidth = lowerBitmap.width;

  for (int ty = startTy; ty <= endTy; ty++) {
    for (int tx = startTx; tx <= endTx; tx++) {
      final RasterIntRect tileRect = tileBounds(tx, ty, tileSize);
      final int left = math.max(tileRect.left, blendBounds.left);
      final int top = math.max(tileRect.top, blendBounds.top);
      final int right = math.min(tileRect.right, blendBounds.right);
      final int bottom = math.min(tileRect.bottom, blendBounds.bottom);
      if (left >= right || top >= bottom) {
        continue;
      }
      BitmapSurface? srcSurface = upperTiled.getTile(tx, ty);
      if (srcSurface == null) {
        if (defaultUpperSurface == null) {
          continue;
        }
        srcSurface = defaultUpperSurface;
      }
      BitmapSurface? maskSurface = maskTiled.getTile(tx, ty);
      if (maskSurface == null) {
        if (defaultMaskSurface == null) {
          continue;
        }
        maskSurface = defaultMaskSurface;
      }
      final int localStartX = left - tileRect.left;
      final int localEndX = right - tileRect.left;
      final int localStartY = top - tileRect.top;
      final int localEndY = bottom - tileRect.top;

      final RasterIntRect rect = RasterIntRect(left, top, right, bottom);
      for (int row = 0; row < rect.height; row++) {
        final int srcRow = (top + row) * lowerWidth + left;
        final int dstRow = (localStartY + row) * tileSize + localStartX;
        tempDest.pixels.setRange(
          dstRow,
          dstRow + rect.width,
          lowerPixels,
          srcRow,
        );
      }

      final bool ok = RustCpuBlendFfi.instance.blendOnCanvas(
        srcPtr: srcSurface.pointerAddress,
        dstPtr: tempDest.pointerAddress,
        pixelsLen: tempDest.pixels.length,
        width: tileSize,
        height: tileSize,
        startX: localStartX,
        endX: localEndX,
        startY: localStartY,
        endY: localEndY,
        opacity: opacity,
        blendMode: upper.blendMode.index,
        maskPtr: maskSurface.pointerAddress,
        maskLen: maskSurface.pixels.length,
        maskOpacity: clippingInfo.opacity,
      );
      if (ok) {
        for (int row = 0; row < rect.height; row++) {
          final int srcRow =
              (localStartY + row) * tileSize + localStartX;
          final int dstRow = (top + row) * lowerWidth + left;
          lowerPixels.setRange(
            dstRow,
            dstRow + rect.width,
            tempDest.pixels,
            srcRow,
          );
        }
      }
    }
  }

  tempDest.dispose();
  defaultUpperSurface?.dispose();
  defaultMaskSurface?.dispose();
}

void _mergeBitmapUpperIntoTiledLowerWithMask(
  BitmapCanvasController controller,
  BitmapLayerState upper,
  BitmapLayerState lower,
  _ClippingMaskInfo clippingInfo,
  double opacity,
) {
  final BitmapSurface? upperBitmap = upper.surface.bitmapSurface;
  if (upperBitmap == null) {
    return;
  }
  final TiledSurface lowerTiled = lower.surface.tiledSurface!;
  final TiledSurface maskTiled = clippingInfo.layer.surface.tiledSurface!;
  final RasterIntRect? upperBounds = _surfaceContentBounds(
    controller,
    upper.surface,
  );
  if (upperBounds == null || upperBounds.isEmpty) {
    return;
  }
  final RasterIntRect? maskBounds = _surfaceContentBounds(
    controller,
    clippingInfo.layer.surface,
  );
  if (maskBounds == null || maskBounds.isEmpty) {
    return;
  }
  final int blendLeft = math.max(upperBounds.left, maskBounds.left);
  final int blendTop = math.max(upperBounds.top, maskBounds.top);
  final int blendRight = math.min(upperBounds.right, maskBounds.right);
  final int blendBottom = math.min(upperBounds.bottom, maskBounds.bottom);
  if (blendLeft >= blendRight || blendTop >= blendBottom) {
    return;
  }
  final RasterIntRect blendBounds =
      RasterIntRect(blendLeft, blendTop, blendRight, blendBottom);

  final int tileSize = lowerTiled.tileSize;
  final int startTx = tileIndexForCoord(blendBounds.left, tileSize);
  final int endTx = tileIndexForCoord(blendBounds.right - 1, tileSize);
  final int startTy = tileIndexForCoord(blendBounds.top, tileSize);
  final int endTy = tileIndexForCoord(blendBounds.bottom - 1, tileSize);

  final Color? maskDefault = maskTiled.defaultFill;
  final int maskDefaultArgb =
      maskDefault == null ? 0 : BitmapSurface.encodeColor(maskDefault);
  BitmapSurface? defaultMaskSurface;
  if (maskDefaultArgb != 0) {
    defaultMaskSurface = BitmapSurface(
      width: tileSize,
      height: tileSize,
      fillColor: maskDefault,
    );
  }

  final BitmapSurface tempSrc = BitmapSurface(
    width: tileSize,
    height: tileSize,
  );
  final Uint32List upperPixels = upperBitmap.pixels;
  final int upperWidth = upperBitmap.width;

  for (int ty = startTy; ty <= endTy; ty++) {
    for (int tx = startTx; tx <= endTx; tx++) {
      final RasterIntRect tileRect = tileBounds(tx, ty, tileSize);
      final int left = math.max(tileRect.left, blendBounds.left);
      final int top = math.max(tileRect.top, blendBounds.top);
      final int right = math.min(tileRect.right, blendBounds.right);
      final int bottom = math.min(tileRect.bottom, blendBounds.bottom);
      if (left >= right || top >= bottom) {
        continue;
      }
      BitmapSurface? maskSurface = maskTiled.getTile(tx, ty);
      if (maskSurface == null) {
        if (defaultMaskSurface == null) {
          continue;
        }
        maskSurface = defaultMaskSurface;
      }
      final int localStartX = left - tileRect.left;
      final int localEndX = right - tileRect.left;
      final int localStartY = top - tileRect.top;
      final int localEndY = bottom - tileRect.top;

      final RasterIntRect rect = RasterIntRect(left, top, right, bottom);
      for (int row = 0; row < rect.height; row++) {
        final int srcRow = (top + row) * upperWidth + left;
        final int dstRow = (localStartY + row) * tileSize + localStartX;
        tempSrc.pixels.setRange(
          dstRow,
          dstRow + rect.width,
          upperPixels,
          srcRow,
        );
      }

      final BitmapSurface dstSurface =
          lowerTiled.getTile(tx, ty) ?? lowerTiled.ensureTile(tx, ty);
      final bool ok = RustCpuBlendFfi.instance.blendOnCanvas(
        srcPtr: tempSrc.pointerAddress,
        dstPtr: dstSurface.pointerAddress,
        pixelsLen: dstSurface.pixels.length,
        width: tileSize,
        height: tileSize,
        startX: localStartX,
        endX: localEndX,
        startY: localStartY,
        endY: localEndY,
        opacity: opacity,
        blendMode: upper.blendMode.index,
        maskPtr: maskSurface.pointerAddress,
        maskLen: maskSurface.pixels.length,
        maskOpacity: clippingInfo.opacity,
      );
      if (ok) {
        dstSurface.markDirty();
      }
    }
  }

  tempSrc.dispose();
  defaultMaskSurface?.dispose();
}

void _mergeTiledLayersWithMask(
  BitmapCanvasController controller,
  BitmapLayerState upper,
  BitmapLayerState lower,
  _ClippingMaskInfo clippingInfo,
  double opacity,
) {
  final TiledSurface upperTiled = upper.surface.tiledSurface!;
  final TiledSurface lowerTiled = lower.surface.tiledSurface!;
  final TiledSurface maskTiled = clippingInfo.layer.surface.tiledSurface!;

  final RasterIntRect? upperBounds = _surfaceContentBounds(
    controller,
    upper.surface,
  );
  if (upperBounds == null || upperBounds.isEmpty) {
    return;
  }
  final RasterIntRect? maskBounds = _surfaceContentBounds(
    controller,
    clippingInfo.layer.surface,
  );
  if (maskBounds == null || maskBounds.isEmpty) {
    return;
  }
  final int blendLeft = math.max(upperBounds.left, maskBounds.left);
  final int blendTop = math.max(upperBounds.top, maskBounds.top);
  final int blendRight = math.min(upperBounds.right, maskBounds.right);
  final int blendBottom = math.min(upperBounds.bottom, maskBounds.bottom);
  if (blendLeft >= blendRight || blendTop >= blendBottom) {
    return;
  }
  final RasterIntRect blendBounds =
      RasterIntRect(blendLeft, blendTop, blendRight, blendBottom);

  final int tileSize = lowerTiled.tileSize;
  final int startTx = tileIndexForCoord(blendBounds.left, tileSize);
  final int endTx = tileIndexForCoord(blendBounds.right - 1, tileSize);
  final int startTy = tileIndexForCoord(blendBounds.top, tileSize);
  final int endTy = tileIndexForCoord(blendBounds.bottom - 1, tileSize);

  final Color? upperDefault = upperTiled.defaultFill;
  final int upperDefaultArgb =
      upperDefault == null ? 0 : BitmapSurface.encodeColor(upperDefault);
  BitmapSurface? defaultUpperSurface;
  if (upperDefaultArgb != 0) {
    defaultUpperSurface = BitmapSurface(
      width: tileSize,
      height: tileSize,
      fillColor: upperDefault,
    );
  }

  final Color? maskDefault = maskTiled.defaultFill;
  final int maskDefaultArgb =
      maskDefault == null ? 0 : BitmapSurface.encodeColor(maskDefault);
  BitmapSurface? defaultMaskSurface;
  if (maskDefaultArgb != 0) {
    defaultMaskSurface = BitmapSurface(
      width: tileSize,
      height: tileSize,
      fillColor: maskDefault,
    );
  }

  for (int ty = startTy; ty <= endTy; ty++) {
    for (int tx = startTx; tx <= endTx; tx++) {
      final RasterIntRect tileRect = tileBounds(tx, ty, tileSize);
      final int left = math.max(tileRect.left, blendBounds.left);
      final int top = math.max(tileRect.top, blendBounds.top);
      final int right = math.min(tileRect.right, blendBounds.right);
      final int bottom = math.min(tileRect.bottom, blendBounds.bottom);
      if (left >= right || top >= bottom) {
        continue;
      }
      BitmapSurface? srcSurface = upperTiled.getTile(tx, ty);
      if (srcSurface == null) {
        if (defaultUpperSurface == null) {
          continue;
        }
        srcSurface = defaultUpperSurface;
      }
      BitmapSurface? maskSurface = maskTiled.getTile(tx, ty);
      if (maskSurface == null) {
        if (defaultMaskSurface == null) {
          continue;
        }
        maskSurface = defaultMaskSurface;
      }
      final BitmapSurface dstSurface =
          lowerTiled.getTile(tx, ty) ?? lowerTiled.ensureTile(tx, ty);
      final int localStartX = left - tileRect.left;
      final int localEndX = right - tileRect.left;
      final int localStartY = top - tileRect.top;
      final int localEndY = bottom - tileRect.top;
      final bool ok = RustCpuBlendFfi.instance.blendOnCanvas(
        srcPtr: srcSurface.pointerAddress,
        dstPtr: dstSurface.pointerAddress,
        pixelsLen: dstSurface.pixels.length,
        width: tileSize,
        height: tileSize,
        startX: localStartX,
        endX: localEndX,
        startY: localStartY,
        endY: localEndY,
        opacity: opacity,
        blendMode: upper.blendMode.index,
        maskPtr: maskSurface.pointerAddress,
        maskLen: maskSurface.pixels.length,
        maskOpacity: clippingInfo.opacity,
      );
      if (ok) {
        dstSurface.markDirty();
      }
    }
  }
  defaultUpperSurface?.dispose();
  defaultMaskSurface?.dispose();
}


void _blendOnCanvasPixels(
  BitmapCanvasController controller,
  Uint32List srcPixels,
  Uint32List dstPixels,
  double opacity,
  CanvasLayerBlendMode blendMode,
  _ClippingMaskInfo? clippingInfo, {
  int? srcPixelsPtr,
  int? dstPixelsPtr,
  int? maskPtrOverride,
  int? maskLenOverride,
  double? maskOpacityOverride,
}) {
  final int srcPtr = srcPixelsPtr ?? 0;
  final int dstPtr = dstPixelsPtr ?? 0;
  if (srcPtr == 0 || dstPtr == 0 || !RustCpuBlendFfi.instance.isSupported) {
    return;
  }
  final Rect? bounds = _computePixelBounds(
    srcPixels,
    controller._width,
    controller._height,
    pixelsPtr: srcPtr,
  );
  if (bounds == null) {
    return;
  }
  final int startX = math.max(0, bounds.left.floor());
  final int endX = math.min(controller._width, bounds.right.ceil());
  final int startY = math.max(0, bounds.top.floor());
  final int endY = math.min(controller._height, bounds.bottom.ceil());
  if (startX >= endX || startY >= endY) {
    return;
  }
  int maskPtr = 0;
  int maskLen = 0;
  double maskOpacity = 0;
  if (clippingInfo != null) {
    maskPtr = clippingInfo.layer.surface.pointerAddress;
    if (maskPtr != 0) {
      maskLen = clippingInfo.layer.surface.pixelCount;
      maskOpacity = clippingInfo.opacity;
    }
  }
  if (maskPtrOverride != null) {
    maskPtr = maskPtrOverride;
    maskLen = maskLenOverride ?? maskLen;
    maskOpacity = maskOpacityOverride ?? maskOpacity;
  }
  if (clippingInfo != null && maskPtr == 0) {
    return;
  }
  RustCpuBlendFfi.instance.blendOnCanvas(
    srcPtr: srcPtr,
    dstPtr: dstPtr,
    pixelsLen: srcPixels.length,
    width: controller._width,
    height: controller._height,
    startX: startX,
    endX: endX,
    startY: startY,
    endY: endY,
    opacity: opacity,
    blendMode: blendMode.index,
    maskPtr: maskPtr,
    maskLen: maskLen,
    maskOpacity: maskOpacity,
  );
  return;
}

int _overflowKey(int x, int y) {
  final int hi = x.toSigned(32);
  final int lo = y & 0xffffffff;
  return (hi << 32) | lo;
}

int _overflowKeyX(int key) => (key >> 32).toSigned(32);

int _overflowKeyY(int key) => (key & 0xffffffff).toSigned(32);

int _overflowPixelIndex(int x, int y, int width) {
  final int value = y * width + x;
  return value & 0xffffffff;
}

int _colorWithOpacity(int src, double alpha) {
  final double clamped =
      alpha.isFinite ? _controllerClampUnit(alpha) : 0.0;
  final int a = (clamped * 255.0).round();
  if (a <= 0) {
    return 0;
  }
  final int clampedA = a >= 255 ? 255 : a;
  return (clampedA << 24) | (src & 0x00ffffff);
}

void _blendOverflowPixelsNoCanvas(
  BitmapCanvasController controller,
  _LayerOverflowStore upperOverflow,
  BitmapLayerState lower,
  _LayerOverflowStore lowerOverflow,
  double opacity,
  CanvasLayerBlendMode blendMode,
  _ClippingMaskInfo? clippingInfo,
) {
  if (upperOverflow.isEmpty) {
    return;
  }
  final double clampedOpacity =
      opacity.isFinite ? _controllerClampUnit(opacity) : 0.0;
  if (clampedOpacity <= 0) {
    return;
  }
  final Map<int, int> lowerMap = <int, int>{};
  if (!lowerOverflow.isEmpty) {
    lowerOverflow.forEachSegment((int rowY, _LayerOverflowSegment segment) {
      for (int i = 0; i < segment.length; i++) {
        final int color = segment.pixels[i];
        if ((color >> 24) == 0) {
          continue;
        }
        final int key = _overflowKey(segment.startX + i, rowY);
        lowerMap[key] = color;
      }
    });
  }

  final double maskOpacity = clippingInfo == null
      ? 0
      : (clippingInfo.opacity.isFinite
            ? _controllerClampUnit(clippingInfo.opacity)
            : 0.0);
  final bool useMask = clippingInfo != null && maskOpacity > 0;
  final Map<int, int> maskMap = <int, int>{};
  if (clippingInfo != null && maskOpacity > 0 && !clippingInfo.overflow.isEmpty) {
    clippingInfo.overflow
        .forEachSegment((int rowY, _LayerOverflowSegment segment) {
      for (int i = 0; i < segment.length; i++) {
        final int color = segment.pixels[i];
        if ((color >> 24) == 0) {
          continue;
        }
        final int key = _overflowKey(segment.startX + i, rowY);
        maskMap[key] = color;
      }
    });
  }

  upperOverflow.forEachSegment((int rowY, _LayerOverflowSegment segment) {
    for (int i = 0; i < segment.length; i++) {
      final int srcColor = segment.pixels[i];
      final int srcA = (srcColor >> 24) & 0xff;
      if (srcA == 0) {
        continue;
      }
      double effectiveAlpha = (srcA / 255.0) * clampedOpacity;
      if (effectiveAlpha <= 0) {
        continue;
      }
      final int x = segment.startX + i;
      final int y = rowY;
      if (useMask) {
        final int key = _overflowKey(x, y);
        final int maskColor = maskMap[key] ?? 0;
        final int maskA = (maskColor >> 24) & 0xff;
        if (maskA == 0) {
          continue;
        }
        final double maskAlpha = (maskA / 255.0) * maskOpacity;
        if (maskAlpha <= 0) {
          continue;
        }
        effectiveAlpha *= maskAlpha;
        if (effectiveAlpha <= 0) {
          continue;
        }
      }
      final int effectiveColor = _colorWithOpacity(srcColor, effectiveAlpha);
      if (effectiveColor == 0) {
        continue;
      }
      final int key = _overflowKey(x, y);
      final int dstColor = lowerMap[key] ?? 0;
      final int pixelIndex = _overflowPixelIndex(x, y, controller._width);
      final int blended = blend_utils.blendWithMode(
        dstColor,
        effectiveColor,
        blendMode,
        pixelIndex,
      );
      if ((blended >> 24) == 0) {
        lowerMap.remove(key);
      } else {
        lowerMap[key] = blended;
      }
    }
  });

  if (lowerMap.isEmpty) {
    controller._layerOverflowStores.remove(lower.id);
    return;
  }
  final Map<int, List<int>> rows = <int, List<int>>{};
  lowerMap.forEach((int key, int color) {
    final int y = _overflowKeyY(key);
    rows.putIfAbsent(y, () => <int>[]).add(key);
  });
  final List<int> ys = rows.keys.toList()..sort();
  final _LayerOverflowBuilder builder = _LayerOverflowBuilder();
  for (final int y in ys) {
    final List<int> keys = rows[y]!
      ..sort((int a, int b) => _overflowKeyX(a).compareTo(_overflowKeyX(b)));
    for (final int key in keys) {
      builder.addPixel(_overflowKeyX(key), y, lowerMap[key]!);
    }
  }
  final _LayerOverflowStore mergedStore = builder.build();
  if (mergedStore.isEmpty) {
    controller._layerOverflowStores.remove(lower.id);
  } else {
    controller._layerOverflowStores[lower.id] = mergedStore;
  }
}

void _blendOverflowPixels(
  BitmapCanvasController controller,
  _LayerOverflowStore upperOverflow,
  BitmapLayerState lower,
  _LayerOverflowStore lowerOverflow,
  double opacity,
  CanvasLayerBlendMode blendMode,
  _ClippingMaskInfo? clippingInfo, {
  int? canvasPtrOverride,
  int? canvasLenOverride,
  int? maskPtrOverride,
  int? maskLenOverride,
  double? maskOpacityOverride,
}) {
  if (upperOverflow.isEmpty) {
    return;
  }
  final int canvasPtr = canvasPtrOverride ?? lower.surface.pointerAddress;
  final int maskPtr = maskPtrOverride ??
      (clippingInfo == null ? 0 : clippingInfo.layer.surface.pointerAddress);
  if (canvasPtr == 0 ||
      !RustCpuBlendFfi.instance.isSupported ||
      (clippingInfo != null && maskPtr == 0)) {
    return;
  }
  final int upperCount = _countOverflowPixels(upperOverflow);
  if (upperCount <= 0) {
    return;
  }
  CpuBuffer<Int32List>? upperX;
  CpuBuffer<Int32List>? upperY;
  CpuBuffer<Uint32List>? upperColor;
  CpuBuffer<Int32List>? lowerX;
  CpuBuffer<Int32List>? lowerY;
  CpuBuffer<Uint32List>? lowerColor;
  CpuBuffer<Int32List>? maskOverflowX;
  CpuBuffer<Int32List>? maskOverflowY;
  CpuBuffer<Uint32List>? maskOverflowColor;
  CpuBuffer<Int32List>? outX;
  CpuBuffer<Int32List>? outY;
  CpuBuffer<Uint32List>? outColor;
  CpuBuffer<Uint64List>? outCountPtr;
  try {
    upperX = allocateInt32(upperCount);
    upperY = allocateInt32(upperCount);
    upperColor = allocateUint32(upperCount);
    _fillOverflowArrays(
      upperOverflow,
      upperX.list,
      upperY.list,
      upperColor.list,
    );
    final int lowerCount = _countOverflowPixels(lowerOverflow);
    if (lowerCount > 0) {
      lowerX = allocateInt32(lowerCount);
      lowerY = allocateInt32(lowerCount);
      lowerColor = allocateUint32(lowerCount);
      _fillOverflowArrays(
        lowerOverflow,
        lowerX.list,
        lowerY.list,
        lowerColor.list,
      );
    }
    int maskLen = 0;
    double maskOpacity = 0;
    int maskOverflowCount = 0;
    if (clippingInfo != null) {
      maskLen = maskLenOverride ?? clippingInfo.layer.surface.pixelCount;
      maskOpacity = maskOpacityOverride ?? clippingInfo.opacity;
      maskOverflowCount = _countOverflowPixels(clippingInfo.overflow);
      if (maskOverflowCount > 0) {
        maskOverflowX = allocateInt32(maskOverflowCount);
        maskOverflowY = allocateInt32(maskOverflowCount);
        maskOverflowColor = allocateUint32(maskOverflowCount);
        _fillOverflowArrays(
          clippingInfo.overflow,
          maskOverflowX.list,
          maskOverflowY.list,
          maskOverflowColor.list,
        );
      }
    }
    final int outCapacity = upperCount + lowerCount;
    outX = allocateInt32(outCapacity);
    outY = allocateInt32(outCapacity);
    outColor = allocateUint32(outCapacity);
    outCountPtr = allocateUint64(1);
    final bool ok = RustCpuBlendFfi.instance.blendOverflow(
      canvasPtr: canvasPtr,
      canvasLen: canvasLenOverride ?? lower.surface.pixelCount,
      width: controller._width,
      height: controller._height,
      upperXPtr: upperX.address,
      upperYPtr: upperY.address,
      upperColorPtr: upperColor.address,
      upperLen: upperCount,
      lowerXPtr: lowerX?.address ?? 0,
      lowerYPtr: lowerY?.address ?? 0,
      lowerColorPtr: lowerColor?.address ?? 0,
      lowerLen: lowerCount,
      opacity: opacity,
      blendMode: blendMode.index,
      maskPtr: maskPtr,
      maskLen: maskLen,
      maskOpacity: maskOpacity,
      maskOverflowXPtr: maskOverflowX?.address ?? 0,
      maskOverflowYPtr: maskOverflowY?.address ?? 0,
      maskOverflowColorPtr: maskOverflowColor?.address ?? 0,
      maskOverflowLen: maskOverflowCount,
      outXPtr: outX.address,
      outYPtr: outY.address,
      outColorPtr: outColor.address,
      outCapacity: outCapacity,
      outCountPtr: outCountPtr.address,
    );
    if (ok) {
      final int count =
          outCountPtr.list.isNotEmpty ? outCountPtr.list[0] : 0;
      final _LayerOverflowBuilder overflowBuilder = _LayerOverflowBuilder();
      if (count > 0) {
        final Int32List xs = outX.list;
        final Int32List ys = outY.list;
        final Uint32List colors = outColor.list;
        for (int i = 0; i < count; i++) {
          overflowBuilder.addPixel(xs[i], ys[i], colors[i]);
        }
      }
      final _LayerOverflowStore mergedStore = overflowBuilder.build();
      if (mergedStore.isEmpty) {
        controller._layerOverflowStores.remove(lower.id);
      } else {
        controller._layerOverflowStores[lower.id] = mergedStore;
      }
    }
  } finally {
    upperX?.dispose();
    upperY?.dispose();
    upperColor?.dispose();
    lowerX?.dispose();
    lowerY?.dispose();
    lowerColor?.dispose();
    maskOverflowX?.dispose();
    maskOverflowY?.dispose();
    maskOverflowColor?.dispose();
    outX?.dispose();
    outY?.dispose();
    outColor?.dispose();
    outCountPtr?.dispose();
  }
  return;
}

class _ClippingMaskInfo {
  _ClippingMaskInfo({
    required this.layer,
    required this.opacity,
    required this.overflow,
  });

  final BitmapLayerState layer;
  final double opacity;
  final _LayerOverflowStore overflow;
}

_ClippingMaskInfo? _resolveClippingMaskInfo(
  BitmapCanvasController controller,
  int startIndex,
) {
  for (int i = startIndex - 1; i >= 0; i--) {
    final BitmapLayerState candidate = controller._layers[i];
    if (candidate.clippingMask) {
      continue;
    }
    if (!candidate.visible) {
      return null;
    }
    final double opacity = BitmapCanvasController._clampUnit(candidate.opacity);
    if (opacity <= 0) {
      return null;
    }
    final _LayerOverflowStore overflow =
        controller._layerOverflowStores[candidate.id] ?? _LayerOverflowStore();
    return _ClippingMaskInfo(
      layer: candidate,
      opacity: opacity,
      overflow: overflow,
    );
  }
  return null;
}

int _findFallbackActiveIndex(
  BitmapCanvasController controller, {
  int? exclude,
}) {
  for (int i = controller._layers.length - 1; i >= 0; i--) {
    if (i == exclude) {
      continue;
    }
    if (controller._layers[i].visible) {
      return i;
    }
  }
  return math.max(
    0,
    math.min(controller._layers.length - 1, controller._activeIndex),
  );
}

void _layerManagerClearRegion(
  BitmapCanvasController controller,
  String id, {
  Uint8List? mask,
}) {
  final int index = controller._layers.indexWhere((layer) => layer.id == id);
  if (index < 0) {
    return;
  }
  final BitmapLayerState layer = controller._layers[index];
  final int replacement = index == 0
      ? BitmapSurface.encodeColor(controller._backgroundColor)
      : 0;
  final bool isFullSelection =
      mask != null &&
      identical(mask, controller._selectionMask) &&
      controller._selectionMaskIsFull;
  if (mask == null || isFullSelection) {
    layer.surface.fill(BitmapSurface.decodeColor(replacement));
    controller._markDirty(layerId: id, pixelsDirty: true);
    return;
  }
  if (mask.length != controller._width * controller._height) {
    throw ArgumentError('Selection mask size mismatch');
  }
  RasterIntRect? maskBounds;
  if (identical(mask, controller._selectionMask)) {
    maskBounds = controller._selectionMaskBounds;
  }
  maskBounds ??= _controllerMaskBounds(
    mask,
    controller._width,
    controller._height,
  );
  if (maskBounds == null || maskBounds.isEmpty) {
    return;
  }
  int minX = controller._width;
  int minY = controller._height;
  int maxX = -1;
  int maxY = -1;
  void applyMask(BitmapSurface surface) {
    final Uint32List pixels = surface.pixels;
    for (int y = maskBounds!.top; y < maskBounds.bottom; y++) {
      final int rowOffset = y * controller._width;
      for (int x = maskBounds.left; x < maskBounds.right; x++) {
        final int indexInMask = rowOffset + x;
        if (mask[indexInMask] == 0) {
          continue;
        }
        pixels[indexInMask] = replacement;
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
    if (replacement != 0) {
      surface.markDirty();
    }
  }

  if (layer.surface.isTiled) {
    final TiledSurface tiled = layer.surface.tiledSurface!;
    final int defaultArgb = tiled.defaultFill == null
        ? 0
        : BitmapSurface.encodeColor(tiled.defaultFill!);
    final bool createMissing = replacement != defaultArgb;
    bool anyChange = false;
    for (final TileEntry entry
        in tiled.tilesInRect(maskBounds, createMissing: createMissing)) {
      final Uint32List pixels = entry.surface.pixels;
      final RasterIntRect local = entry.localRect;
      final RasterIntRect global = entry.globalRect;
      bool tileChanged = false;
      for (int row = 0; row < local.height; row++) {
        final int globalY = global.top + row;
        final int maskRowOffset = globalY * controller._width + global.left;
        final int tileRowOffset =
            (local.top + row) * tiled.tileSize + local.left;
        for (int col = 0; col < local.width; col++) {
          final int maskIndex = maskRowOffset + col;
          if (mask[maskIndex] == 0) {
            continue;
          }
          final int pixelIndex = tileRowOffset + col;
          if (pixels[pixelIndex] == replacement) {
            continue;
          }
          pixels[pixelIndex] = replacement;
          tileChanged = true;
          anyChange = true;
          final int globalX = global.left + col;
          if (globalX < minX) {
            minX = globalX;
          }
          if (globalX > maxX) {
            maxX = globalX;
          }
          if (globalY < minY) {
            minY = globalY;
          }
          if (globalY > maxY) {
            maxY = globalY;
          }
        }
      }
      if (tileChanged && replacement != 0) {
        entry.surface.markDirty();
      }
    }
    if (!anyChange) {
      return;
    }
  } else {
    applyMask(layer.surface.bitmapSurface!);
  }
  if (maxX < minX || maxY < minY) {
    return;
  }
  controller._markDirty(
    region: Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    ),
    layerId: id,
    pixelsDirty: true,
  );
}

String _layerManagerInsertFromData(
  BitmapCanvasController controller,
  CanvasLayerData data, {
  String? aboveLayerId,
}) {
  final LayerSurface surface = controller._createLayerSurface();
  _LayerOverflowStore overflowStore = _LayerOverflowStore();
  if (data.rawPixels != null || data.bitmap != null) {
    overflowStore = _applyBitmapToSurface(controller, surface, data);
  } else if (data.fillColor != null) {
    surface.fill(data.fillColor!);
  } else {
    surface.fill(const Color(0x00000000));
  }
  CanvasTextData? textData = data.text;
  Rect? textBounds;
  if (textData != null) {
    textData = _alignTextDataToBitmap(
      textData,
      bitmapLeft: data.bitmapLeft,
      bitmapTop: data.bitmapTop,
    );
    textBounds = controller._textRenderer.layout(textData).bounds;
  }
  final BitmapLayerState layer = BitmapLayerState(
    id: data.id,
    name: data.name,
    surface: surface,
    visible: true,
    opacity: data.opacity,
    locked: false,
    clippingMask: false,
    blendMode: data.blendMode,
    text: textData,
    textBounds: textBounds,
  );
  int insertIndex = controller._layers.length;
  if (aboveLayerId != null) {
    final int index = controller._layers.indexWhere(
      (candidate) => candidate.id == aboveLayerId,
    );
    if (index >= 0) {
      insertIndex = index + 1;
    }
  }
  controller._layers.insert(insertIndex, layer);
  controller._activeIndex = insertIndex;
  controller._layerOverflowStores[layer.id] = overflowStore;
  controller._markDirty(pixelsDirty: false);
  return layer.id;
}

void _layerManagerReplaceLayer(
  BitmapCanvasController controller,
  String id,
  CanvasLayerData data,
) {
  final int index = controller._layers.indexWhere((layer) => layer.id == id);
  if (index < 0) {
    return;
  }
  final BitmapLayerState layer = controller._layers[index];
  layer
    ..name = data.name
    ..visible = data.visible
    ..opacity = data.opacity
    ..locked = data.locked
    ..clippingMask = data.clippingMask
    ..blendMode = data.blendMode;
  layer.surface.fill(const Color(0x00000000));
  _LayerOverflowStore overflowStore = _LayerOverflowStore();
  if (data.rawPixels != null || data.bitmap != null) {
    overflowStore = _applyBitmapToSurface(controller, layer.surface, data);
  } else if (data.fillColor != null) {
    layer.surface.fill(data.fillColor!);
    if (index == 0) {
      controller._backgroundColor = data.fillColor!;
    }
  } else {
    layer.surface.fill(const Color(0x00000000));
  }
  CanvasTextData? textData = data.text;
  Rect? textBounds;
  if (textData != null) {
    textData = _alignTextDataToBitmap(
      textData,
      bitmapLeft: data.bitmapLeft,
      bitmapTop: data.bitmapTop,
    );
    textBounds = controller._textRenderer.layout(textData).bounds;
  }
  layer.text = textData;
  layer.textBounds = textBounds;
  controller._layerOverflowStores[layer.id] = overflowStore;
  controller._resetWorkerSurfaceSync();
  controller._markDirty(layerId: id, pixelsDirty: true);
}

void _layerManagerLoadLayers(
  BitmapCanvasController controller,
  List<CanvasLayerData> layers,
  Color backgroundColor,
) {
  controller._cancelPendingWorkerTasks();
  controller._layers.clear();
  controller._rasterBackend.resetClipMask();
  _loadFromCanvasLayers(controller, layers, backgroundColor);
  controller._resetWorkerSurfaceSync();
  controller._markDirty(pixelsDirty: true);
}

RasterIntRect? _surfaceContentBounds(
  BitmapCanvasController controller,
  LayerSurface surface,
) {
  if (surface.isTiled) {
    final RasterIntRect? bounds = surface.tiledSurface?.contentBounds();
    if (bounds == null || bounds.isEmpty) {
      return null;
    }
    final int left = math.max(0, bounds.left);
    final int top = math.max(0, bounds.top);
    final int right = math.min(controller._width, bounds.right);
    final int bottom = math.min(controller._height, bounds.bottom);
    if (left >= right || top >= bottom) {
      return null;
    }
    return RasterIntRect(left, top, right, bottom);
  }
  final Rect? pixelBounds = _computePixelBounds(
    surface.pixels,
    controller._width,
    controller._height,
    pixelsPtr: surface.pointerAddress,
  );
  if (pixelBounds == null) {
    return null;
  }
  final int left = math.max(0, pixelBounds.left.floor());
  final int top = math.max(0, pixelBounds.top.floor());
  final int right = math.min(controller._width, pixelBounds.right.ceil());
  final int bottom = math.min(controller._height, pixelBounds.bottom.ceil());
  if (left >= right || top >= bottom) {
    return null;
  }
  return RasterIntRect(left, top, right, bottom);
}

List<CanvasLayerData> _layerManagerSnapshotLayers(
  BitmapCanvasController controller,
) {
  final List<CanvasLayerData> result = <CanvasLayerData>[];
  for (int i = 0; i < controller._layers.length; i++) {
    final BitmapLayerState layer = controller._layers[i];
    final _LayerOverflowStore overflowStore =
        controller._layerOverflowStores[layer.id] ?? _LayerOverflowStore();
    final bool hasOverflow = !overflowStore.isEmpty;
    Uint32List? rawPixels;
    int? bitmapWidth;
    int? bitmapHeight;
    int? bitmapLeft;
    int? bitmapTop;
    RasterIntRect? surfaceBounds;
    if (!hasOverflow) {
      surfaceBounds = _surfaceContentBounds(controller, layer.surface);
    }
    final bool hasSurface = surfaceBounds != null;
    if (hasSurface || hasOverflow) {
      if (!hasOverflow) {
        final RasterIntRect bounds = surfaceBounds!;
        rawPixels = layer.surface.readRect(bounds);
        bitmapWidth = bounds.width;
        bitmapHeight = bounds.height;
        bitmapLeft = bounds.left;
        bitmapTop = bounds.top;
      } else {
        final _LayerTransformSnapshot snapshot = _buildOverflowTransformSnapshot(
          controller,
          layer,
          overflowStore,
        );
        rawPixels = snapshot.pixels;
        bitmapWidth = snapshot.width;
        bitmapHeight = snapshot.height;
        bitmapLeft = snapshot.originX;
        bitmapTop = snapshot.originY;
      }
    }
    result.add(
      CanvasLayerData(
        id: layer.id,
        name: layer.name,
        visible: layer.visible,
        opacity: layer.opacity,
        locked: layer.locked,
        clippingMask: layer.clippingMask,
        blendMode: layer.blendMode,
        fillColor: i == 0 ? controller._backgroundColor : null,
        bitmap: null,
        rawPixels: rawPixels,
        bitmapWidth: bitmapWidth,
        bitmapHeight: bitmapHeight,
        bitmapLeft: bitmapLeft,
        bitmapTop: bitmapTop,
        text: layer.text,
        cloneRawPixels: false,
      ),
    );
  }
  return result;
}

CanvasLayerData? _layerManagerBuildClipboardLayer(
  BitmapCanvasController controller,
  String id, {
  Uint8List? mask,
}) {
  final int index = controller._layers.indexWhere((layer) => layer.id == id);
  if (index < 0) {
    return null;
  }
  final BitmapLayerState layer = controller._layers[index];
  Uint8List? effectiveMask;
  RasterIntRect? maskBounds;
  Uint8List? resolvedMask = mask;
  if (resolvedMask != null &&
      identical(resolvedMask, controller._selectionMask) &&
      controller._selectionMaskIsFull) {
    resolvedMask = null;
  }
  if (resolvedMask != null) {
    if (resolvedMask.length != controller._width * controller._height) {
      throw ArgumentError('Selection mask size mismatch');
    }
    if (identical(resolvedMask, controller._selectionMask)) {
      maskBounds = controller._selectionMaskBounds;
    }
    maskBounds ??= _controllerMaskBounds(
      resolvedMask,
      controller._width,
      controller._height,
    );
    if (maskBounds == null || maskBounds.isEmpty) {
      return null;
    }
    effectiveMask = Uint8List.fromList(resolvedMask);
  }
  Uint8List? bitmap;
  int bitmapWidth = controller._width;
  int bitmapHeight = controller._height;
  int bitmapLeft = 0;
  int bitmapTop = 0;
  if (effectiveMask == null) {
    final _LayerOverflowStore overflowStore =
        controller._layerOverflowStores[layer.id] ?? _LayerOverflowStore();
    if (!overflowStore.isEmpty) {
      final _LayerTransformSnapshot snapshot = _buildOverflowTransformSnapshot(
        controller,
        layer,
        overflowStore,
      );
      bitmap = BitmapCanvasController._pixelsToRgba(snapshot.pixels);
      bitmapWidth = snapshot.width;
      bitmapHeight = snapshot.height;
      bitmapLeft = snapshot.originX;
      bitmapTop = snapshot.originY;
    } else {
      final RasterIntRect? bounds =
          _surfaceContentBounds(controller, layer.surface);
      if (bounds != null) {
        final Uint32List pixels = layer.surface.readRect(bounds);
        bitmap = BitmapCanvasController._pixelsToRgba(pixels);
        bitmapWidth = bounds.width;
        bitmapHeight = bounds.height;
        bitmapLeft = bounds.left;
        bitmapTop = bounds.top;
      }
    }
  } else {
    final RasterIntRect bounds = maskBounds!;
    final int boundsWidth = bounds.width;
    final int boundsHeight = bounds.height;
    final Uint32List pixels = layer.surface.readRect(bounds);
    final Uint8List rgba = Uint8List(boundsWidth * boundsHeight * 4);
    for (int row = 0; row < boundsHeight; row++) {
      final int globalY = bounds.top + row;
      final int maskRowOffset = globalY * controller._width + bounds.left;
      final int srcRowOffset = row * boundsWidth;
      for (int col = 0; col < boundsWidth; col++) {
        if (effectiveMask[maskRowOffset + col] == 0) {
          continue;
        }
        final int argb = pixels[srcRowOffset + col];
        final int offset = (srcRowOffset + col) * 4;
        rgba[offset] = (argb >> 16) & 0xff;
        rgba[offset + 1] = (argb >> 8) & 0xff;
        rgba[offset + 2] = argb & 0xff;
        rgba[offset + 3] = (argb >> 24) & 0xff;
      }
    }
    bitmap = rgba;
    bitmapWidth = boundsWidth;
    bitmapHeight = boundsHeight;
    bitmapLeft = bounds.left;
    bitmapTop = bounds.top;
  }
  if (bitmap == null && layer.text == null) {
    return null;
  }
  return CanvasLayerData(
    id: layer.id,
    name: layer.name,
    visible: true,
    opacity: layer.opacity,
    locked: false,
    clippingMask: false,
    blendMode: layer.blendMode,
    fillColor: null,
    bitmap: bitmap,
    bitmapWidth: bitmapWidth,
    bitmapHeight: bitmapHeight,
    bitmapLeft: bitmapLeft,
    bitmapTop: bitmapTop,
    text: effectiveMask == null ? layer.text : null,
  );
}

void _initializeDefaultLayers(
  BitmapCanvasController controller,
  Color backgroundColor,
) {
  final LayerSurface background =
      controller._createLayerSurface(fillColor: backgroundColor);
  final LayerSurface paintSurface = controller._createLayerSurface();
  final String backgroundId = _generateUniqueLayerId(controller);
  controller._layers
    ..add(
      BitmapLayerState(id: backgroundId, name: '背景', surface: background),
    )
    ..add(
      BitmapLayerState(
        id: _generateUniqueLayerId(controller),
        name: '图层 2',
        surface: paintSurface,
      ),
    );
  for (final BitmapLayerState layer in controller._layers) {
    controller._layerOverflowStores[layer.id] = _LayerOverflowStore();
  }
  controller._activeIndex = controller._layers.length - 1;
}

CanvasTextData _alignTextDataToBitmap(
  CanvasTextData data, {
  int? bitmapLeft,
  int? bitmapTop,
}) {
  if (bitmapLeft == null || bitmapTop == null) {
    return data;
  }
  final bool needsUpdate =
      data.origin.dx != bitmapLeft.toDouble() ||
      data.origin.dy != bitmapTop.toDouble();
  if (!needsUpdate) {
    return data;
  }
  return data.copyWith(
    origin: Offset(bitmapLeft.toDouble(), bitmapTop.toDouble()),
  );
}

void _loadFromCanvasLayers(
  BitmapCanvasController controller,
  List<CanvasLayerData> layers,
  Color backgroundColor,
) {
  controller._backgroundColor = backgroundColor;
  if (layers.isEmpty) {
    _initializeDefaultLayers(controller, backgroundColor);
    return;
  }
  for (final CanvasLayerData layer in layers) {
    final String resolvedLayerId = _resolveUniqueLayerId(controller, layer.id);
    if (resolvedLayerId != layer.id) {
      debugPrint(
        'Duplicate layer id detected while loading layers: '
        '${layer.id} -> $resolvedLayerId',
      );
    }
    final LayerSurface surface = controller._createLayerSurface();
    _LayerOverflowStore overflowStore = _LayerOverflowStore();
    if (layer.rawPixels != null || layer.bitmap != null) {
      overflowStore = _applyBitmapToSurface(controller, surface, layer);
    } else if (layer.fillColor != null) {
      surface.fill(layer.fillColor!);
    }
    CanvasTextData? textData = layer.text;
    Rect? textBounds;
    if (textData != null) {
      textData = _alignTextDataToBitmap(
        textData,
        bitmapLeft: layer.bitmapLeft,
        bitmapTop: layer.bitmapTop,
      );
      textBounds = controller._textRenderer.layout(textData).bounds;
    }
    controller._layers.add(
      BitmapLayerState(
        id: resolvedLayerId,
        name: layer.name,
        visible: layer.visible,
        opacity: layer.opacity,
        locked: layer.locked,
        clippingMask: layer.clippingMask,
        blendMode: layer.blendMode,
        surface: surface,
        text: textData,
        textBounds: textBounds,
      ),
    );
    controller._layerOverflowStores[resolvedLayerId] = overflowStore;
    if (layer == layers.first && layer.fillColor != null) {
      controller._backgroundColor = layer.fillColor!;
    }
  }
  controller._activeIndex = controller._layers.length - 1;
}

_LayerOverflowStore _applyBitmapToSurface(
  BitmapCanvasController controller,
  LayerSurface surface,
  CanvasLayerData data,
) {
  final Uint32List? rawPixels = data.rawPixels;
  if (rawPixels != null) {
    return _applyRawPixelsToSurface(controller, surface, data, rawPixels);
  }
  return _applyRgbaBitmapToSurface(controller, surface, data);
}

_LayerOverflowStore _applyRawPixelsToSurface(
  BitmapCanvasController controller,
  LayerSurface surface,
  CanvasLayerData data,
  Uint32List rawPixels,
) {
  if (rawPixels.isEmpty) {
    return _LayerOverflowStore();
  }
  final int canvasWidth = controller._width;
  final int canvasHeight = controller._height;
  final int srcWidth = data.bitmapWidth ?? canvasWidth;
  final int srcHeight = data.bitmapHeight ?? canvasHeight;
  final int offsetX = data.bitmapLeft ?? 0;
  final int offsetY = data.bitmapTop ?? 0;
  if (offsetX == 0 &&
      offsetY == 0 &&
      srcWidth == canvasWidth &&
      srcHeight == canvasHeight &&
      rawPixels.length == canvasWidth * canvasHeight) {
    surface.writeRect(
      RasterIntRect(0, 0, canvasWidth, canvasHeight),
      rawPixels,
    );
    return _LayerOverflowStore();
  }

  final int startX = math.max(0, offsetX);
  final int startY = math.max(0, offsetY);
  final int endX = math.min(canvasWidth, offsetX + srcWidth);
  final int endY = math.min(canvasHeight, offsetY + srcHeight);
  final _LayerOverflowBuilder builder = _LayerOverflowBuilder();
  if (startX < endX && startY < endY) {
    final RasterIntRect rect = RasterIntRect(startX, startY, endX, endY);
    final Uint32List patch = Uint32List(rect.width * rect.height);
    for (int y = startY; y < endY; y++) {
      final int rowOffset = (y - offsetY) * srcWidth;
      if (rowOffset >= rawPixels.length) {
        break;
      }
      final int rowEnd = rowOffset + srcWidth;
      final int safeRowEnd = math.min(rowEnd, rawPixels.length);
      final int available = safeRowEnd - rowOffset;
      final int rowStart = startX - offsetX;
      if (available <= 0 || rowStart >= available) {
        continue;
      }
      final int copyWidth =
          math.min(rect.width, available - rowStart);
      final int dstRow = (y - startY) * rect.width;
      final int srcRow = rowOffset + rowStart;
      patch.setRange(
        dstRow,
        dstRow + copyWidth,
        rawPixels,
        srcRow,
      );
    }
    surface.writeRect(rect, patch);
  }
  if (offsetX >= 0 &&
      offsetY >= 0 &&
      offsetX + srcWidth <= canvasWidth &&
      offsetY + srcHeight <= canvasHeight) {
    return _LayerOverflowStore();
  }
  for (int y = 0; y < srcHeight; y++) {
    final int canvasY = offsetY + y;
    final int rowOffset = y * srcWidth;
    if (rowOffset >= rawPixels.length) {
      break;
    }
    final int rowEnd = rowOffset + srcWidth;
    final int safeRowEnd = math.min(rowEnd, rawPixels.length);
    for (int x = 0; x < safeRowEnd - rowOffset; x++) {
      final int canvasX = offsetX + x;
      if (canvasX >= 0 &&
          canvasX < canvasWidth &&
          canvasY >= 0 &&
          canvasY < canvasHeight) {
        continue;
      }
      final int color = rawPixels[rowOffset + x];
      if ((color >> 24) == 0) {
        continue;
      }
      builder.addPixel(canvasX, canvasY, color);
    }
  }
  return builder.build();
}

_LayerOverflowStore _applyRgbaBitmapToSurface(
  BitmapCanvasController controller,
  LayerSurface surface,
  CanvasLayerData data,
) {
  final Uint8List bitmap = data.bitmap!;
  final int canvasWidth = controller._width;
  final int canvasHeight = controller._height;
  final int srcWidth = data.bitmapWidth ?? canvasWidth;
  final int srcHeight = data.bitmapHeight ?? canvasHeight;
  final int offsetX = data.bitmapLeft ?? 0;
  final int offsetY = data.bitmapTop ?? 0;
  final int startX = math.max(0, offsetX);
  final int startY = math.max(0, offsetY);
  final int endX = math.min(canvasWidth, offsetX + srcWidth);
  final int endY = math.min(canvasHeight, offsetY + srcHeight);
  final _LayerOverflowBuilder builder = _LayerOverflowBuilder();

  if (startX < endX && startY < endY) {
    final RasterIntRect rect = RasterIntRect(startX, startY, endX, endY);
    final Uint32List patch = Uint32List(rect.width * rect.height);
    for (int y = startY; y < endY; y++) {
      final int srcRow = (y - offsetY) * srcWidth * 4;
      final int dstRow = (y - startY) * rect.width;
      for (int x = startX; x < endX; x++) {
        final int srcOffset = srcRow + (x - offsetX) * 4;
        if (srcOffset + 3 >= bitmap.length) {
          break;
        }
        final int a = bitmap[srcOffset + 3];
        if (a == 0) {
          continue;
        }
        final int r = bitmap[srcOffset];
        final int g = bitmap[srcOffset + 1];
        final int b = bitmap[srcOffset + 2];
        patch[dstRow + (x - startX)] =
            (a << 24) | (r << 16) | (g << 8) | b;
      }
    }
    surface.writeRect(rect, patch);
  }
  if (offsetX >= 0 &&
      offsetY >= 0 &&
      offsetX + srcWidth <= canvasWidth &&
      offsetY + srcHeight <= canvasHeight) {
    return _LayerOverflowStore();
  }

  for (int y = 0; y < srcHeight; y++) {
    final int canvasY = offsetY + y;
    final int rowOffset = y * srcWidth * 4;
    if (rowOffset >= bitmap.length) {
      break;
    }
    for (int x = 0; x < srcWidth; x++) {
      final int canvasX = offsetX + x;
      if (canvasX >= 0 &&
          canvasX < canvasWidth &&
          canvasY >= 0 &&
          canvasY < canvasHeight) {
        continue;
      }
      final int srcOffset = rowOffset + x * 4;
      if (srcOffset + 3 >= bitmap.length) {
        break;
      }
      final int a = bitmap[srcOffset + 3];
      if (a == 0) {
        continue;
      }
      final int r = bitmap[srcOffset];
      final int g = bitmap[srcOffset + 1];
      final int b = bitmap[srcOffset + 2];
      final int color = (a << 24) | (r << 16) | (g << 8) | b;
      builder.addPixel(canvasX, canvasY, color);
    }
  }
  return builder.build();
}
