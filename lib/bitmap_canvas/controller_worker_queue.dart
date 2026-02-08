part of 'controller.dart';

void _controllerEnqueuePaintingWorkerCommand(
  BitmapCanvasController controller,
  Rect region,
  PaintingDrawCommand command,
) {
  if (region.isEmpty) {
    return;
  }
  final _PendingWorkerDrawBatch batch = controller._pendingWorkerDrawBatch ??=
      _PendingWorkerDrawBatch(region);
  batch.add(region, command);
  final bool exceededCommandLimit =
      batch.commands.length >= BitmapCanvasController._kMaxWorkerBatchCommands;
  final double batchArea = batch.region.width * batch.region.height;
  final bool exceededAreaLimit =
      !batchArea.isFinite ||
      batchArea >= BitmapCanvasController._kMaxWorkerBatchPixels;
  if (exceededCommandLimit || exceededAreaLimit) {
    _controllerScheduleWorkerDrawFlush(controller, forceImmediate: true);
  } else {
    _controllerScheduleWorkerDrawFlush(controller);
  }
}

void _controllerScheduleWorkerDrawFlush(
  BitmapCanvasController controller, {
  bool forceImmediate = false,
}) {
  if (forceImmediate) {
    controller._pendingWorkerDrawScheduled = false;
    _controllerProcessPendingWorkerDrawCommands(controller);
    return;
  }
  if (controller._pendingWorkerDrawScheduled) {
    return;
  }
  controller._pendingWorkerDrawScheduled = true;
  scheduleMicrotask(() => _controllerProcessPendingWorkerDrawCommands(controller));
}

void _controllerProcessPendingWorkerDrawCommands(
  BitmapCanvasController controller,
) {
  controller._pendingWorkerDrawScheduled = false;
  final _PendingWorkerDrawBatch? batch = controller._pendingWorkerDrawBatch;
  if (batch == null || batch.commands.isEmpty) {
    controller._pendingWorkerDrawBatch = null;
    return;
  }
  controller._pendingWorkerDrawBatch = null;
  final Rect region = batch.region;
  final List<PaintingDrawCommand> commands =
      List<PaintingDrawCommand>.from(batch.commands);
  controller._enqueueWorkerPatchFuture(
    controller._executeWorkerDraw(region: region, commands: commands),
    onError: () =>
        controller._applyPaintingCommandsSynchronously(region, commands),
  );
}

void _controllerFlushPendingPaintingCommands(BitmapCanvasController controller) {
  if (controller._pendingWorkerDrawBatch == null ||
      controller._pendingWorkerDrawBatch!.commands.isEmpty) {
    controller._pendingWorkerDrawBatch = null;
    controller._pendingWorkerDrawScheduled = false;
    return;
  }
  _controllerProcessPendingWorkerDrawCommands(controller);
}

Future<void> _controllerWaitForPendingWorkerTasks(
  BitmapCanvasController controller,
) {
  _controllerFlushPendingPaintingCommands(controller);
  if (controller._paintingWorkerPendingTasks == 0) {
    return Future<void>.value();
  }
  final Completer<void> completer = Completer<void>();
  controller._paintingWorkerIdleWaiters.add(completer);
  return completer.future;
}

void _controllerNotifyWorkerIdle(BitmapCanvasController controller) {
  if (controller._paintingWorkerPendingTasks > 0) {
    return;
  }
  if (controller._pendingWorkerDrawBatch != null &&
      controller._pendingWorkerDrawBatch!.commands.isNotEmpty) {
    return;
  }
  if (controller._pendingWorkerDrawScheduled) {
    return;
  }
  if (controller._paintingWorkerIdleWaiters.isEmpty) {
    return;
  }
  for (final Completer<void> completer in
      controller._paintingWorkerIdleWaiters) {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }
  controller._paintingWorkerIdleWaiters.clear();
}

void _controllerCancelPendingWorkerTasks(BitmapCanvasController controller) {
  controller._pendingWorkerDrawBatch = null;
  controller._pendingWorkerDrawScheduled = false;
  controller._pendingWorkerPatches.clear();
  controller._paintingWorkerNextApplySequence =
      controller._paintingWorkerNextSequence;
  controller._paintingWorkerPendingTasks = 0;
  controller._paintingWorkerGeneration++;
  _controllerNotifyWorkerIdle(controller);
}

Future<void> _controllerEnsureWorkerSurfaceSynced(
  BitmapCanvasController controller,
) async {
  if (!controller._isMultithreaded) {
    return;
  }
  final CanvasPaintingWorker worker = controller._ensurePaintingWorker();
  final BitmapLayerState layer = controller._activeLayer;
  if (controller._paintingWorkerSyncedLayerId == layer.id &&
      controller._paintingWorkerSyncedRevision == layer.revision) {
    return;
  }
  final Uint32List snapshot = Uint32List.fromList(layer.surface.pixels);
  await worker.setSurface(
    width: controller._width,
    height: controller._height,
    pixels: snapshot,
  );
  controller._paintingWorkerSyncedLayerId = layer.id;
  controller._paintingWorkerSyncedRevision = layer.revision;
}

Future<void> _controllerEnsureWorkerSelectionMaskSynced(
  BitmapCanvasController controller,
) async {
  if (!controller._isMultithreaded ||
      !controller._paintingWorkerSelectionDirty) {
    return;
  }
  final CanvasPaintingWorker worker = controller._ensurePaintingWorker();
  await worker.updateSelectionMask(controller._selectionMask);
  controller._paintingWorkerSelectionDirty = false;
}

void _controllerResetWorkerSurfaceSync(BitmapCanvasController controller) {
  controller._paintingWorkerSyncedLayerId = null;
  controller._paintingWorkerSyncedRevision = -1;
  controller._paintingWorkerSelectionDirty = true;
}

void _controllerEnqueueWorkerPatchFuture(
  BitmapCanvasController controller,
  Future<PaintingWorkerPatch?> future, {
  VoidCallback? onError,
}) {
  final int sequence = controller._paintingWorkerNextSequence++;
  final int generation = controller._paintingWorkerGeneration;
  controller._paintingWorkerPendingTasks++;
  future
      .then((PaintingWorkerPatch? patch) {
        if (generation != controller._paintingWorkerGeneration ||
            sequence < controller._paintingWorkerNextApplySequence) {
          return;
        }
        if (patch == null) {
          onError?.call();
        }
        controller._pendingWorkerPatches[sequence] = patch;
        _controllerProcessPendingWorkerPatches(controller);
      })
      .catchError((Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'CanvasPaintingWorker',
            context: ErrorDescription('while running painting task'),
          ),
        );
        if (generation != controller._paintingWorkerGeneration ||
            sequence < controller._paintingWorkerNextApplySequence) {
          return;
        }
        onError?.call();
        controller._pendingWorkerPatches[sequence] = null;
        _controllerProcessPendingWorkerPatches(controller);
      })
      .whenComplete(() {
        if (generation == controller._paintingWorkerGeneration &&
            controller._paintingWorkerPendingTasks > 0) {
          controller._paintingWorkerPendingTasks--;
        }
        _controllerNotifyWorkerIdle(controller);
      });
}

void _controllerProcessPendingWorkerPatches(BitmapCanvasController controller) {
  while (controller._pendingWorkerPatches.containsKey(
    controller._paintingWorkerNextApplySequence,
  )) {
    final PaintingWorkerPatch? patch = controller._pendingWorkerPatches.remove(
      controller._paintingWorkerNextApplySequence,
    );
    if (patch != null) {
      controller._applyWorkerPatch(patch);
    }
    controller._paintingWorkerNextApplySequence++;
  }
}

void _controllerApplyWorkerPatch(
  BitmapCanvasController controller,
  PaintingWorkerPatch patch,
) {
  if (patch.width <= 0 || patch.height <= 0 || patch.pixels.isEmpty) {
    return;
  }
  final int effectiveLeft = math.max(0, math.min(patch.left, controller._width));
  final int effectiveTop = math.max(0, math.min(patch.top, controller._height));
  final int maxRight = math.min(effectiveLeft + patch.width, controller._width);
  final int maxBottom =
      math.min(effectiveTop + patch.height, controller._height);
  if (maxRight <= effectiveLeft || maxBottom <= effectiveTop) {
    return;
  }
  final BitmapSurface surface = controller._activeSurface;
  final Uint32List destination = surface.pixels;
  // Keep BitmapSurface.isClean in sync so filters that gate on coverage can run.
  final bool checkCoverage = surface.isClean;
  bool wroteCoverage = false;
  final int copyWidth = maxRight - effectiveLeft;
  final int copyHeight = maxBottom - effectiveTop;
  final int srcLeftOffset = effectiveLeft - patch.left;
  final int srcTopOffset = effectiveTop - patch.top;
  for (int row = 0; row < copyHeight; row++) {
    final int srcRow = srcTopOffset + row;
    final int destY = effectiveTop + row;
    final int srcOffset = srcRow * patch.width + srcLeftOffset;
    final int destOffset = destY * controller._width + effectiveLeft;
    if (checkCoverage && !wroteCoverage) {
      final int rowEnd = srcOffset + copyWidth;
      for (int i = srcOffset; i < rowEnd; i++) {
        if ((patch.pixels[i] & 0xff000000) != 0) {
          wroteCoverage = true;
          break;
        }
      }
    }
    destination.setRange(
      destOffset,
      destOffset + copyWidth,
      patch.pixels,
      srcOffset,
    );
  }
  if (wroteCoverage) {
    surface.markDirty();
  }
  final BitmapLayerState layer = controller._activeLayer;
  controller._paintingWorkerSyncedLayerId = layer.id;
  controller._paintingWorkerSyncedRevision = layer.revision + 1;
  final Rect dirtyRegion = Rect.fromLTWH(
    effectiveLeft.toDouble(),
    effectiveTop.toDouble(),
    copyWidth.toDouble(),
    copyHeight.toDouble(),
  );
  controller._markDirty(
    region: dirtyRegion,
    layerId: layer.id,
    pixelsDirty: true,
  );
}

void _controllerScheduleTileImageDisposal(BitmapCanvasController controller) {
  if (controller._pendingTileDisposals.isEmpty ||
      controller._tileDisposalScheduled) {
    return;
  }
  controller._tileDisposalScheduled = true;
  final SchedulerBinding? scheduler = SchedulerBinding.instance;
  if (scheduler == null) {
    scheduleMicrotask(() => _controllerFlushTileImageDisposals(controller));
  } else {
    scheduler.addPostFrameCallback(
      (_) => _controllerFlushTileImageDisposals(controller),
    );
  }
}

void _controllerFlushTileImageDisposals(BitmapCanvasController controller) {
  for (final ui.Image image in controller._pendingTileDisposals) {
    image.dispose();
  }
  controller._pendingTileDisposals.clear();
  controller._tileDisposalScheduled = false;
}

void _controllerDisposePendingTileImages(BitmapCanvasController controller) {
  for (final ui.Image image in controller._pendingTileDisposals) {
    image.dispose();
  }
  controller._pendingTileDisposals.clear();
  controller._tileDisposalScheduled = false;
}

Future<PaintingWorkerPatch?> _controllerExecuteWorkerDraw(
  BitmapCanvasController controller, {
  required Rect region,
  required List<PaintingDrawCommand> commands,
}) async {
  if (commands.isEmpty) {
    return null;
  }
  final RasterIntRect bounds = _controllerClipRectToSurface(controller, region);
  if (bounds.isEmpty) {
    return null;
  }
  await controller._ensureWorkerSurfaceSynced();
  await controller._ensureWorkerSelectionMaskSynced();
  final PaintingWorkerPatch patch = await controller
      ._ensurePaintingWorker()
      .drawPatch(
        PaintingDrawRequest(
          left: bounds.left,
          top: bounds.top,
          width: bounds.width,
          height: bounds.height,
          commands: commands,
        ),
      );
  return patch;
}

Future<PaintingWorkerPatch?> _controllerExecuteFloodFill(
  BitmapCanvasController controller, {
  required Offset start,
  required Color color,
  Color? targetColor,
  bool contiguous = true,
  int tolerance = 0,
  int fillGap = 0,
  Uint32List? samplePixels,
  Uint32List? swallowColors,
  int antialiasLevel = 0,
}) async {
  TransferableTypedData? sampleData;
  if (samplePixels != null && samplePixels.isNotEmpty) {
    sampleData = TransferableTypedData.fromList(<Uint8List>[
      Uint8List.view(
        samplePixels.buffer,
        samplePixels.offsetInBytes,
        samplePixels.lengthInBytes,
      ),
    ]);
  }
  TransferableTypedData? swallowData;
  if (swallowColors != null && swallowColors.isNotEmpty) {
    swallowData = TransferableTypedData.fromList(<Uint8List>[
      Uint8List.view(
        swallowColors.buffer,
        swallowColors.offsetInBytes,
        swallowColors.lengthInBytes,
      ),
    ]);
  }
  await controller._ensureWorkerSurfaceSynced();
  await controller._ensureWorkerSelectionMaskSynced();
  final PaintingWorkerPatch patch = await controller
      ._ensurePaintingWorker()
      .floodFill(
        PaintingFloodFillRequest(
          width: controller._width,
          height: controller._height,
          pixels: null,
          samplePixels: sampleData,
          startX: start.dx.floor(),
          startY: start.dy.floor(),
          colorValue: color.value,
          targetColorValue: targetColor?.value,
          contiguous: contiguous,
          mask: null,
          tolerance: tolerance,
          fillGap: fillGap,
          swallowColors: swallowData,
          antialiasLevel: antialiasLevel,
        ),
      );
  return patch;
}

Future<Uint8List?> _controllerExecuteSelectionMask(
  BitmapCanvasController controller, {
  required Offset start,
  required Uint32List pixels,
  int tolerance = 0,
}) async {
  final TransferableTypedData pixelData = TransferableTypedData.fromList(
    <Uint8List>[Uint8List.view(pixels.buffer)],
  );
  final Uint8List mask = await controller._ensurePaintingWorker()
      .computeSelectionMask(
        PaintingSelectionMaskRequest(
          width: controller._width,
          height: controller._height,
          pixels: pixelData,
          startX: start.dx.floor(),
          startY: start.dy.floor(),
          tolerance: tolerance,
        ),
      );
  return mask;
}

RasterIntRect _controllerClipRectToSurface(
  BitmapCanvasController controller,
  Rect rect,
) =>
    controller._rasterBackend.clipRectToSurface(rect);

bool _controllerIsSurfaceEmpty(BitmapSurface surface) {
  for (final int pixel in surface.pixels) {
    if ((pixel >> 24) != 0) {
      return false;
    }
  }
  return true;
}

Uint8List _controllerSurfaceToRgba(BitmapSurface surface) {
  final Uint8List rgba = Uint8List(surface.pixels.length * 4);
  for (int i = 0; i < surface.pixels.length; i++) {
    final int argb = surface.pixels[i];
    final int offset = i * 4;
    rgba[offset] = (argb >> 16) & 0xff;
    rgba[offset + 1] = (argb >> 8) & 0xff;
    rgba[offset + 2] = argb & 0xff;
    rgba[offset + 3] = (argb >> 24) & 0xff;
  }
  return rgba;
}

Uint32List _controllerRgbaToPixels(Uint8List rgba, int width, int height) {
  final int length = width * height;
  final Uint32List pixels = Uint32List(length);
  for (int i = 0; i < length; i++) {
    final int offset = i * 4;
    final int r = rgba[offset];
    final int g = rgba[offset + 1];
    final int b = rgba[offset + 2];
    final int a = rgba[offset + 3];
    pixels[i] = (a << 24) | (r << 16) | (g << 8) | b;
  }
  return pixels;
}

Uint8List _controllerPixelsToRgba(Uint32List pixels) {
  return kIsWeb
      ? argbToPremultipliedRgba(pixels)
      : rust_image_ops.convertPixelsToRgba(pixels: pixels);
}

Rect _controllerUnionRects(Rect a, Rect b) {
  return Rect.fromLTRB(
    math.min(a.left, b.left),
    math.min(a.top, b.top),
    math.max(a.right, b.right),
    math.max(a.bottom, b.bottom),
  );
}

Uint8List _controllerSurfaceToMaskedRgba(
  BitmapSurface surface,
  Uint8List mask,
) {
  final Uint32List pixels = surface.pixels;
  final Uint8List rgba = Uint8List(pixels.length * 4);
  for (int i = 0; i < pixels.length; i++) {
    if (mask[i] == 0) {
      continue;
    }
    final int argb = pixels[i];
    final int offset = i * 4;
    rgba[offset] = (argb >> 16) & 0xff;
    rgba[offset + 1] = (argb >> 8) & 0xff;
    rgba[offset + 2] = argb & 0xff;
    rgba[offset + 3] = (argb >> 24) & 0xff;
  }
  return rgba;
}

bool _controllerMaskHasCoverage(Uint8List mask) {
  for (final int value in mask) {
    if (value != 0) {
      return true;
    }
  }
  return false;
}

double _controllerClampUnit(double value) {
  if (value <= 0) {
    return 0;
  }
  if (value >= 1) {
    return 1;
  }
  return value;
}

Future<ui.Image> _controllerDecodeRgbaImage(
  Uint8List bytes,
  int width,
  int height,
) {
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

class _PendingWorkerDrawBatch {
  _PendingWorkerDrawBatch(Rect region) : region = region;

  Rect region;
  final List<PaintingDrawCommand> commands = <PaintingDrawCommand>[];

  void add(Rect rect, PaintingDrawCommand command) {
    commands.add(command);
    region = Rect.fromLTRB(
      math.min(region.left, rect.left),
      math.min(region.top, rect.top),
      math.max(region.right, rect.right),
      math.max(region.bottom, rect.bottom),
    );
  }
}
