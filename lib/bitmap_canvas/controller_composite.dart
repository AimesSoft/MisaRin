part of 'controller.dart';

void _compositeMarkDirty(
  BitmapCanvasController controller, {
  Rect? region,
}) {
  controller._compositeDirty = true;
  if (region == null || controller._pendingFullSurface) {
    controller._pendingDirtyBounds = null;
    controller._pendingDirtyTiles.clear();
    controller._pendingDirtyTileKeys.clear();
    controller._pendingFullSurface = true;
  } else {
    final Rect clipped = Rect.fromLTWH(
      0,
      0,
      controller._width.toDouble(),
      controller._height.toDouble(),
    ).intersect(region);
    if (clipped.isEmpty) {
      return;
    }
    if (controller._pendingDirtyBounds == null) {
      controller._pendingDirtyBounds = clipped;
    } else {
      final Rect current = controller._pendingDirtyBounds!;
      controller._pendingDirtyBounds = Rect.fromLTRB(
        math.min(current.left, clipped.left),
        math.min(current.top, clipped.top),
        math.max(current.right, clipped.right),
        math.max(current.bottom, clipped.bottom),
      );
    }
    _compositeEnqueueDirtyTiles(controller, clipped);
  }
  _compositeScheduleRefresh(controller);
}

void _compositeScheduleRefresh(BitmapCanvasController controller) {
  if (controller._refreshScheduled) {
    return;
  }
  controller._refreshScheduled = true;
  final SchedulerBinding? scheduler = SchedulerBinding.instance;
  if (scheduler == null) {
    scheduleMicrotask(() => _compositeProcessScheduled(controller));
  } else {
    scheduler.ensureVisualUpdate();
    scheduler.scheduleFrameCallback((_) {
      _compositeProcessScheduled(controller);
    });
  }
  controller.notifyListeners();
}

void _compositeProcessScheduled(BitmapCanvasController controller) {
  controller._refreshScheduled = false;
  _compositeProcessPending(controller);
}

void _compositeProcessPending(BitmapCanvasController controller) {
  if (!controller._compositeDirty) {
    return;
  }
  final Rect? dirtyBounds = controller._pendingDirtyBounds;
  final bool requiresFullSurface =
      !controller._compositeInitialized ||
      controller._pendingFullSurface ||
      dirtyBounds == null;
  final _IntRect region =
      _effectiveCompositeRegion(controller, dirtyBounds, requiresFullSurface);

  if (_tryDispatchBackgroundComposite(controller, region)) {
    return;
  }

  _processCompositeSynchronously(controller, requiresFullSurface);
}

bool _tryDispatchBackgroundComposite(
  BitmapCanvasController controller,
  _IntRect region,
) {
  if (!controller._backgroundCompositeEnabled) {
    return false;
  }
  if (controller._compositeProcessing) {
    return true;
  }
  if (region.isEmpty) {
    return false;
  }
  final BitmapCompositePayload? payload =
      _buildCompositePayload(controller, region);
  if (payload == null) {
    return false;
  }
  controller._pendingDirtyBounds = null;
  controller._pendingDirtyTiles.clear();
  controller._pendingDirtyTileKeys.clear();
  controller._pendingFullSurface = false;
  controller._compositeDirty = false;
  controller._compositeProcessing = true;
  controller._backgroundCompositor.composite(payload).then(
      (BitmapCompositeResult result) {
    _applyCompositeBuffers(
      controller,
      result,
    );
  }).catchError((Object error, StackTrace stackTrace) {
    controller._backgroundCompositeEnabled = false;
    controller._compositeProcessing = false;
    controller._compositeDirty = true;
    controller._pendingFullSurface = true;
    if (!controller._refreshScheduled) {
      _compositeScheduleRefresh(controller);
    }
  });
  return true;
}

void _processCompositeSynchronously(
  BitmapCanvasController controller,
  bool requiresFullSurface,
) {
  final List<_IntRect> dirtyTiles = requiresFullSurface
      ? const <_IntRect>[]
      : List<_IntRect>.from(controller._pendingDirtyTiles);

  controller._pendingDirtyBounds = null;
  controller._pendingDirtyTiles.clear();
  controller._pendingDirtyTileKeys.clear();
  controller._pendingFullSurface = false;

  _compositeUpdate(
    controller,
    requiresFullSurface: requiresFullSurface,
    regions: requiresFullSurface ? null : dirtyTiles,
  );

  final Uint8List rgba = controller._compositeRgba ??
      Uint8List(controller._width * controller._height * 4);
  controller._compositeInitialized = true;
  _finalizeCompositeImage(controller, rgba);
}

void _applyCompositeBuffers(
  BitmapCanvasController controller,
  BitmapCompositeResult result,
) {
  final bool fullSurface =
      result.regionLeft == 0 &&
      result.regionTop == 0 &&
      result.regionWidth == controller._width &&
      result.regionHeight == controller._height;

  if (fullSurface) {
    controller._compositePixels = result.composite;
    controller._compositeRgba = result.rgba;
  } else {
    controller._compositePixels ??=
        Uint32List(controller._width * controller._height);
    controller._compositeRgba ??=
        Uint8List(controller._width * controller._height * 4);
    _blitCompositeRegion(
      controller._compositePixels!,
      controller._compositeRgba!,
      result.composite,
      result.rgba,
      controller._width,
      result.regionLeft,
      result.regionTop,
      result.regionWidth,
      result.regionHeight,
    );
  }

  controller._compositeProcessing = false;
  controller._compositeInitialized = true;
  _finalizeCompositeImage(controller, controller._compositeRgba!);
}

void _finalizeCompositeImage(
  BitmapCanvasController controller,
  Uint8List rgba,
) {
  ui.decodeImageFromPixels(
    rgba,
    controller._width,
    controller._height,
    ui.PixelFormat.rgba8888,
    (ui.Image image) {
      controller._cachedImage?.dispose();
      controller._cachedImage = image;
      if (controller._pendingActiveLayerTransformCleanup) {
        controller._pendingActiveLayerTransformCleanup = false;
        _resetActiveLayerTranslationState(controller);
      }
      controller._compositeDirty =
          controller._pendingFullSurface ||
          controller._pendingDirtyBounds != null;
      controller.notifyListeners();
      if (controller._compositeDirty && !controller._refreshScheduled) {
        _compositeScheduleRefresh(controller);
      }
    },
  );
}

BitmapCompositePayload? _buildCompositePayload(
  BitmapCanvasController controller,
  _IntRect region,
) {
  if (controller._layers.isEmpty) {
    return null;
  }
  final String? translatingLayerId =
      controller._activeLayerTranslationSnapshot != null &&
              !controller._pendingActiveLayerTransformCleanup
          ? controller._activeLayerTranslationId
          : null;
  final List<BitmapCompositeLayerPayload> layers =
      <BitmapCompositeLayerPayload>[];
  for (final BitmapLayerState layer in controller._layers) {
    if (translatingLayerId != null && layer.id == translatingLayerId) {
      continue;
    }
    Uint8List bytes;
    if (region.left == 0 &&
        region.top == 0 &&
        region.width == controller._width &&
        region.height == controller._height) {
      bytes = layer.surface.pixels.buffer.asUint8List();
    } else {
      final Uint32List subset = _copySurfaceRegion(layer.surface, region);
      bytes = subset.buffer.asUint8List();
    }
    layers.add(
      BitmapCompositeLayerPayload(
        pixelData: TransferableTypedData.fromList(<Uint8List>[bytes]),
        opacity: layer.opacity,
        visible: layer.visible,
        clippingMask: layer.clippingMask,
        blendModeIndex: layer.blendMode.index,
      ),
    );
  }
  if (layers.isEmpty) {
    return null;
  }
  return BitmapCompositePayload(
    backgroundColor: controller._backgroundColor.value,
    layers: layers,
    regionLeft: region.left,
    regionTop: region.top,
    regionWidth: region.width,
    regionHeight: region.height,
  );
}

_IntRect _effectiveCompositeRegion(
  BitmapCanvasController controller,
  Rect? dirtyBounds,
  bool requiresFullSurface,
) {
  if (requiresFullSurface || dirtyBounds == null) {
    return _IntRect(0, 0, controller._width, controller._height);
  }
  final Rect expanded = dirtyBounds.inflate(2).intersect(
        Rect.fromLTWH(
          0,
          0,
          controller._width.toDouble(),
          controller._height.toDouble(),
        ),
      );
  if (expanded.isEmpty) {
    return _IntRect(0, 0, controller._width, controller._height);
  }
  return _rectToIntRect(expanded, controller._width, controller._height);
}

_IntRect _rectToIntRect(Rect rect, int canvasWidth, int canvasHeight) {
  final int safeWidth = math.max(1, canvasWidth);
  final int safeHeight = math.max(1, canvasHeight);
  final int left = math.max(0, math.min(safeWidth - 1, rect.left.floor()));
  final int top = math.max(0, math.min(safeHeight - 1, rect.top.floor()));
  final int right = math.max(left + 1, math.min(safeWidth, rect.right.ceil()));
  final int bottom = math.max(top + 1, math.min(safeHeight, rect.bottom.ceil()));
  return _IntRect(left, top, right, bottom);
}

Uint32List _copySurfaceRegion(BitmapSurface surface, _IntRect region) {
  final int regionWidth = region.width;
  final int regionHeight = region.height;
  if (regionWidth <= 0 || regionHeight <= 0) {
    return Uint32List(0);
  }
  final Uint32List subset = Uint32List(regionWidth * regionHeight);
  final Uint32List pixels = surface.pixels;
  final int stride = surface.width;
  int writeOffset = 0;
  for (int y = region.top; y < region.bottom; y++) {
    final int srcOffset = y * stride + region.left;
    subset.setRange(
      writeOffset,
      writeOffset + regionWidth,
      pixels,
      srcOffset,
    );
    writeOffset += regionWidth;
  }
  return subset;
}

void _blitCompositeRegion(
  Uint32List targetComposite,
  Uint8List targetRgba,
  Uint32List sourceComposite,
  Uint8List sourceRgba,
  int canvasWidth,
  int regionLeft,
  int regionTop,
  int regionWidth,
  int regionHeight,
) {
  if (regionWidth <= 0 || regionHeight <= 0) {
    return;
  }
  for (int row = 0; row < regionHeight; row++) {
    final int dstIndex = (regionTop + row) * canvasWidth + regionLeft;
    final int srcIndex = row * regionWidth;
    targetComposite.setRange(
      dstIndex,
      dstIndex + regionWidth,
      sourceComposite,
      srcIndex,
    );
    final int dstRgbaOffset = dstIndex * 4;
    final int srcRgbaOffset = srcIndex * 4;
    targetRgba.setRange(
      dstRgbaOffset,
      dstRgbaOffset + regionWidth * 4,
      sourceRgba,
      srcRgbaOffset,
    );
  }
}

void _compositeUpdate(
  BitmapCanvasController controller, {
  required bool requiresFullSurface,
  List<_IntRect>? regions,
}) {
  _compositeEnsureBuffers(controller);
  final List<_IntRect> areas;
  if (requiresFullSurface) {
    areas = <_IntRect>[_IntRect(0, 0, controller._width, controller._height)];
  } else {
    if (regions == null || regions.isEmpty) {
      return;
    }
    areas = regions;
  }
  if (areas.isEmpty) {
    return;
  }

  final Uint32List composite = controller._compositePixels!;
  final Uint8List rgba = controller._compositeRgba!;
  final List<BitmapLayerState> layers = controller._layers;
  final int width = controller._width;
  final Uint8List clipMask = _compositeEnsureClipMask(controller);
  clipMask.fillRange(0, clipMask.length, 0);

  final String? translatingLayerId =
      controller._activeLayerTranslationSnapshot != null &&
              !controller._pendingActiveLayerTransformCleanup
          ? controller._activeLayerTranslationId
          : null;

  for (final _IntRect area in areas) {
    if (area.isEmpty) {
      continue;
    }
    for (int y = area.top; y < area.bottom; y++) {
      final int rowOffset = y * width;
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
          final double layerOpacity =
              BitmapCanvasController._clampUnit(layer.opacity);
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
            color = BitmapCanvasController._blendWithMode(
              color,
              effectiveColor,
              layer.blendMode,
              index,
            );
          }
        }

        if (!initialized) {
          composite[index] = 0;
          final int rgbaOffset = index * 4;
          rgba[rgbaOffset] = 0;
          rgba[rgbaOffset + 1] = 0;
          rgba[rgbaOffset + 2] = 0;
          rgba[rgbaOffset + 3] = 0;
          continue;
        }

        composite[index] = color;
        final int rgbaOffset = index * 4;
        final int alpha = (color >> 24) & 0xff;
        if (alpha == 0) {
          rgba[rgbaOffset] = 0;
          rgba[rgbaOffset + 1] = 0;
          rgba[rgbaOffset + 2] = 0;
          rgba[rgbaOffset + 3] = 0;
        } else if (alpha == 255) {
          rgba[rgbaOffset] = (color >> 16) & 0xff;
          rgba[rgbaOffset + 1] = (color >> 8) & 0xff;
          rgba[rgbaOffset + 2] = color & 0xff;
          rgba[rgbaOffset + 3] = 255;
        } else {
          final int red = (color >> 16) & 0xff;
          final int green = (color >> 8) & 0xff;
          final int blue = color & 0xff;
          rgba[rgbaOffset] = _premultiplyChannel(red, alpha);
          rgba[rgbaOffset + 1] = _premultiplyChannel(green, alpha);
          rgba[rgbaOffset + 2] = _premultiplyChannel(blue, alpha);
          rgba[rgbaOffset + 3] = alpha;
        }
      }
    }
  }

  if (requiresFullSurface) {
    controller._compositeInitialized = true;
  }
}

void _compositeEnsureBuffers(BitmapCanvasController controller) {
  controller._compositePixels ??=
      Uint32List(controller._width * controller._height);
  controller._compositeRgba ??=
      Uint8List(controller._width * controller._height * 4);
}

Uint8List _compositeEnsureClipMask(BitmapCanvasController controller) {
  return controller._clipMaskBuffer ??=
      Uint8List(controller._width * controller._height);
}

_IntRect _compositeClipRectToSurface(
  BitmapCanvasController controller,
  Rect rect,
) {
  final double effectiveLeft = rect.left;
  final double effectiveTop = rect.top;
  final double effectiveRight = rect.right;
  final double effectiveBottom = rect.bottom;
  final int left = math.max(0, effectiveLeft.floor());
  final int top = math.max(0, effectiveTop.floor());
  final int right = math.min(controller._width, effectiveRight.ceil());
  final int bottom = math.min(controller._height, effectiveBottom.ceil());
  if (left >= right || top >= bottom) {
    return const _IntRect(0, 0, 0, 0);
  }
  return _IntRect(left, top, right, bottom);
}

void _compositeEnqueueDirtyTiles(
  BitmapCanvasController controller,
  Rect region,
) {
  final _IntRect clipped = _compositeClipRectToSurface(controller, region);
  if (clipped.isEmpty) {
    return;
  }
  const int tileSize = BitmapCanvasController._kCompositeTileSize;
  final int leftTile = clipped.left ~/ tileSize;
  final int rightTile = (clipped.right - 1) ~/ tileSize;
  final int topTile = clipped.top ~/ tileSize;
  final int bottomTile = (clipped.bottom - 1) ~/ tileSize;

  for (int ty = topTile; ty <= bottomTile; ty++) {
    for (int tx = leftTile; tx <= rightTile; tx++) {
      final int key = (ty << 20) | tx;
      if (!controller._pendingDirtyTileKeys.add(key)) {
        continue;
      }
      final int tileLeft = tx * tileSize;
      final int tileTop = ty * tileSize;
      final int tileRight = math.min(tileLeft + tileSize, controller._width);
      final int tileBottom = math.min(tileTop + tileSize, controller._height);
      controller._pendingDirtyTiles
          .add(_IntRect(tileLeft, tileTop, tileRight, tileBottom));
    }
  }
}

int _premultiplyChannel(int channel, int alpha) {
  return (channel * alpha + 127) ~/ 255;
}

Color _compositeColorAtComposite(
  BitmapCanvasController controller,
  Offset position,
) {
  final int x = position.dx.floor();
  final int y = position.dy.floor();
  if (x < 0 || x >= controller._width || y < 0 || y >= controller._height) {
    return const Color(0x00000000);
  }
  final int index = y * controller._width + x;
  final Uint32List? compositePixels = controller._compositePixels;
  if (compositePixels != null && compositePixels.length > index) {
    return BitmapSurface.decodeColor(compositePixels[index]);
  }
  int? color;
  for (final BitmapLayerState layer in controller._layers) {
    if (!layer.visible) {
      continue;
    }
    if (controller._activeLayerTranslationSnapshot != null &&
        !controller._pendingActiveLayerTransformCleanup &&
        layer.id == controller._activeLayerTranslationId) {
      continue;
    }
    final int src = layer.surface.pixels[index];
    if (color == null) {
      color = src;
    } else {
      color = BitmapCanvasController._blendArgb(color, src);
    }
  }
  return BitmapSurface.decodeColor(color ?? 0);
}
