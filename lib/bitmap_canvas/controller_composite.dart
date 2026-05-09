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
  if (!controller._rasterOutputEnabled) {
    return;
  }
  if (kIsWeb) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int elapsed = now - controller._lastWebCompositeMs;
    if (elapsed < BitmapCanvasController._kWebCompositeMinIntervalMs) {
      if (controller._refreshScheduled) {
        return;
      }
      controller._refreshScheduled = true;
      controller._webCompositeTimer?.cancel();
      controller._webCompositeTimer = Timer(
        Duration(
          milliseconds:
              BitmapCanvasController._kWebCompositeMinIntervalMs - elapsed,
        ),
        () {
          controller._refreshScheduled = false;
          controller._lastWebCompositeMs =
              DateTime.now().millisecondsSinceEpoch;
          _compositeProcessScheduled(controller);
        },
      );
      SchedulerBinding.instance?.ensureVisualUpdate();
      controller._notify();
      return;
    }
    controller._lastWebCompositeMs = now;
  }
  if (controller._refreshScheduled) {
    return;
  }
  controller._refreshScheduled = true;
  final SchedulerBinding? scheduler = SchedulerBinding.instance;
  if (scheduler == null) {
    scheduleMicrotask(() => _compositeProcessScheduled(controller));
    controller._notify();
    return;
  }
  scheduler.scheduleFrameCallback(
    (_) => _compositeProcessScheduled(controller),
  );
  scheduler.ensureVisualUpdate();
  controller._notify();
}

void _compositeProcessScheduled(BitmapCanvasController controller) {
  controller._refreshScheduled = false;
  if (!controller._rasterOutputEnabled) {
    return;
  }
  if (controller._compositeProcessing) {
    return;
  }
  controller._compositeProcessing = true;
  unawaited(_compositeProcessPending(controller));
}

Future<void> _compositeProcessPending(BitmapCanvasController controller) async {
  try {
    if (!controller._rasterOutputEnabled) {
      return;
    }
    final Stopwatch sw = Stopwatch()..start();
    final RasterCompositeWork work = controller._rasterBackend
        .dequeueCompositeWork();
    if (!work.hasWork) {
      return;
    }

    final int startComposite = sw.elapsedMilliseconds;
    await _compositeUpdate(
      controller,
      requiresFullSurface: work.requiresFullSurface,
      regions: work.regions,
    );
    final int compositeDone = sw.elapsedMilliseconds;
    const String backendLabel = 'rustWgpu';
    BackendCanvasTimeline.mark(
      'composite: $backendLabel composite took ${compositeDone - startComposite}ms',
    );

    final List<RasterIntRect> dirtyRegions = work.requiresFullSurface
        ? controller._rasterBackend.fullSurfaceTileRects()
        : (work.regions ?? const <RasterIntRect>[]);

    final int startTiles = sw.elapsedMilliseconds;
    final CanvasFrame? frame = await controller._tileCache.updateTiles(
      backend: controller._rasterBackend,
      dirtyRegions: dirtyRegions,
      fullSurface: work.requiresFullSurface,
    );
    final int tilesDone = sw.elapsedMilliseconds;
    BackendCanvasTimeline.mark(
      'composite: Tile update took ${tilesDone - startTiles}ms (count: ${dirtyRegions.length})',
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
    controller._notify();
    BackendCanvasTimeline.mark(
      'composite: Total pass took ${sw.elapsedMilliseconds}ms',
    );
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
    layers: controller._layers.cast<CanvasCompositeLayer>(),
    requiresFullSurface: requiresFullSurface,
    regions: regions,
    translatingLayerId: controller._translatingLayerIdForComposite,
  );
}
