part of 'controller.dart';

void _compositeMarkDirty(
  BitmapCanvasController controller, {
  Rect? region,
  String? layerId,
  bool pixelsDirty = true,
}) {
  controller._rasterBackend.markDirty(
    region: region,
    layerId: layerId,
    pixelsDirty: pixelsDirty,
  );
  _compositeScheduleRefresh(controller);
}

void _compositeScheduleRefresh(BitmapCanvasController controller) {
  if (controller._refreshScheduled) {
    return;
  }
  controller._refreshScheduled = true;
  scheduleMicrotask(() => _compositeProcessScheduled(controller));
  SchedulerBinding.instance.ensureVisualUpdate();
  controller.notifyListeners();
}

void _compositeProcessScheduled(BitmapCanvasController controller) {
  controller._refreshScheduled = false;
  if (controller._compositeProcessing) {
    return;
  }
  controller._compositeProcessing = true;
  unawaited(_compositeProcessPending(controller));
}

Future<void> _compositeProcessPending(BitmapCanvasController controller) async {
  try {
    final RasterCompositeWork work = controller._rasterBackend
        .dequeueCompositeWork();
    if (!work.hasWork) {
      return;
    }

    await _compositeUpdate(
      controller,
      requiresFullSurface: work.requiresFullSurface,
      regions: work.regions,
    );

    final List<RasterIntRect> dirtyRegions = work.requiresFullSurface
        ? controller._rasterBackend.fullSurfaceTileRects()
        : (work.regions ?? const <RasterIntRect>[]);
    final BitmapCanvasFrame? frame = await controller._tileCache.updateTiles(
      backend: controller._rasterBackend,
      dirtyRegions: dirtyRegions,
      fullSurface: work.requiresFullSurface,
    );
    if (frame != null) {
      controller._currentFrame = frame;
    }

    if (controller._nextFrameCompleter != null &&
        !controller._nextFrameCompleter!.isCompleted) {
      controller._nextFrameCompleter!.complete();
      controller._nextFrameCompleter = null;
    }

    final List<ui.Image> pendingDisposals = controller._tileCache
        .takePendingDisposals();
    if (pendingDisposals.isNotEmpty) {
      controller._pendingTileDisposals.addAll(pendingDisposals);
      controller._scheduleTileImageDisposal();
    }
    if (controller._pendingActiveLayerTransformCleanup) {
      controller._pendingActiveLayerTransformCleanup = false;
      _resetActiveLayerTranslationState(controller);
    }
    controller._rasterBackend.completeCompositePass();
    controller.notifyListeners();
  } finally {
    controller._compositeProcessing = false;
    if (controller._rasterBackend.isCompositeDirty &&
        !controller._refreshScheduled) {
      _compositeScheduleRefresh(controller);
    }
  }
}

Future<void> _compositeUpdate(
  BitmapCanvasController controller, {
  required bool requiresFullSurface,
  List<RasterIntRect>? regions,
}) {
  return controller._rasterBackend.composite(
    layers: controller._layers,
    requiresFullSurface: requiresFullSurface,
    regions: regions,
    translatingLayerId: controller._translatingLayerIdForComposite,
  );
}
