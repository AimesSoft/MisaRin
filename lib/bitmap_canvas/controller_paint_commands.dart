part of 'controller.dart';

const bool _kDebugRustWgpuBrushTiles =
    bool.fromEnvironment(
      'MISA_RIN_DEBUG_RUST_WGPU_BRUSH_TILES',
      defaultValue: false,
    ) ||
    bool.fromEnvironment('MISA_RIN_DEBUG_GPU_BRUSH_TILES', defaultValue: false);

class _RustWgpuStrokeDrawData {
  const _RustWgpuStrokeDrawData({
    required this.points,
    required this.radii,
    required this.color,
    required this.brushShape,
    required this.erase,
    required this.antialiasLevel,
    required this.includeStart,
    required this.randomRotation,
    required this.smoothRotation,
    required this.rotationSeed,
    required this.rotationJitter,
    required this.spacing,
    required this.scatter,
    required this.softness,
    required this.snapToPixel,
    required this.screentoneEnabled,
    required this.screentoneSpacing,
    required this.screentoneDotSize,
    required this.screentoneRotation,
    required this.screentoneSoftness,
    required this.screentoneShape,
    required this.hollow,
    required this.hollowRatio,
    required this.eraseOccludedParts,
  });

  final List<Offset> points;
  final List<double> radii;
  final Color color;
  final BrushShape brushShape;
  final bool erase;
  final int antialiasLevel;
  final bool includeStart;
  final bool randomRotation;
  final bool smoothRotation;
  final int rotationSeed;
  final double rotationJitter;
  final double spacing;
  final double scatter;
  final double softness;
  final bool snapToPixel;
  final bool screentoneEnabled;
  final double screentoneSpacing;
  final double screentoneDotSize;
  final double screentoneRotation;
  final double screentoneSoftness;
  final BrushShape screentoneShape;
  final bool hollow;
  final double hollowRatio;
  final bool eraseOccludedParts;
}

_RustWgpuStrokeDrawData? _controllerRustWgpuStrokeFromCommand(
  PaintingDrawCommand command, {
  required bool hollow,
  required double hollowRatio,
  required bool eraseOccludedParts,
}) {
  final bool erase = command.erase;
  final int antialiasLevel = command.antialiasLevel.clamp(0, 9);

  switch (command.type) {
    case PaintingDrawCommandType.brushStamp:
      {
        final Offset? center = command.center;
        final double? radius = command.radius;
        final int? shapeIndex = command.shapeIndex;
        if (center == null || radius == null || shapeIndex == null) {
          return null;
        }
        final int clamped = shapeIndex.clamp(0, BrushShape.values.length - 1);
        return _RustWgpuStrokeDrawData(
          points: <Offset>[center],
          radii: <double>[radius.abs()],
          color: Color(command.color),
          brushShape: BrushShape.values[clamped],
          erase: erase,
          antialiasLevel: antialiasLevel,
          includeStart: true,
          randomRotation: command.randomRotation ?? false,
          smoothRotation: command.smoothRotation ?? false,
          rotationSeed: command.rotationSeed ?? 0,
          rotationJitter: command.rotationJitter ?? 1.0,
          spacing: command.spacing ?? 0.15,
          scatter: command.scatter ?? 0.0,
          softness: command.softness ?? 0.0,
          snapToPixel: command.snapToPixel ?? false,
          screentoneEnabled: command.screentoneEnabled ?? false,
          screentoneSpacing: command.screentoneSpacing ?? 10.0,
          screentoneDotSize: command.screentoneDotSize ?? 0.6,
          screentoneRotation: command.screentoneRotation ?? 45.0,
          screentoneSoftness: command.screentoneSoftness ?? 0.0,
          screentoneShape:
              BrushShape.values[(command.screentoneShapeIndex ?? 0).clamp(
                0,
                BrushShape.values.length - 1,
              )],
          hollow: hollow && !erase,
          hollowRatio: hollowRatio,
          eraseOccludedParts: hollow && !erase && eraseOccludedParts,
        );
      }
    case PaintingDrawCommandType.line:
      {
        final Offset? start = command.start;
        final Offset? end = command.end;
        final double? radius = command.radius;
        if (start == null || end == null || radius == null) {
          return null;
        }
        final double resolved = radius.abs();
        return _RustWgpuStrokeDrawData(
          points: <Offset>[start, end],
          radii: <double>[resolved, resolved],
          color: Color(command.color),
          brushShape: BrushShape.circle,
          erase: erase,
          antialiasLevel: antialiasLevel,
          includeStart: command.includeStartCap ?? true,
          randomRotation: command.randomRotation ?? false,
          smoothRotation: command.smoothRotation ?? false,
          rotationSeed: command.rotationSeed ?? 0,
          rotationJitter: command.rotationJitter ?? 1.0,
          spacing: command.spacing ?? 0.15,
          scatter: command.scatter ?? 0.0,
          softness: command.softness ?? 0.0,
          snapToPixel: command.snapToPixel ?? false,
          screentoneEnabled: command.screentoneEnabled ?? false,
          screentoneSpacing: command.screentoneSpacing ?? 10.0,
          screentoneDotSize: command.screentoneDotSize ?? 0.6,
          screentoneRotation: command.screentoneRotation ?? 45.0,
          screentoneSoftness: command.screentoneSoftness ?? 0.0,
          screentoneShape:
              BrushShape.values[(command.screentoneShapeIndex ?? 0).clamp(
                0,
                BrushShape.values.length - 1,
              )],
          hollow: hollow && !erase,
          hollowRatio: hollowRatio,
          eraseOccludedParts: hollow && !erase && eraseOccludedParts,
        );
      }
    case PaintingDrawCommandType.variableLine:
      {
        final Offset? start = command.start;
        final Offset? end = command.end;
        final double? startRadius = command.startRadius;
        final double? endRadius = command.endRadius;
        if (start == null ||
            end == null ||
            startRadius == null ||
            endRadius == null) {
          return null;
        }
        return _RustWgpuStrokeDrawData(
          points: <Offset>[start, end],
          radii: <double>[startRadius.abs(), endRadius.abs()],
          color: Color(command.color),
          brushShape: BrushShape.circle,
          erase: erase,
          antialiasLevel: antialiasLevel,
          includeStart: command.includeStartCap ?? true,
          randomRotation: command.randomRotation ?? false,
          smoothRotation: command.smoothRotation ?? false,
          rotationSeed: command.rotationSeed ?? 0,
          rotationJitter: command.rotationJitter ?? 1.0,
          spacing: command.spacing ?? 0.15,
          scatter: command.scatter ?? 0.0,
          softness: command.softness ?? 0.0,
          snapToPixel: command.snapToPixel ?? false,
          screentoneEnabled: command.screentoneEnabled ?? false,
          screentoneSpacing: command.screentoneSpacing ?? 10.0,
          screentoneDotSize: command.screentoneDotSize ?? 0.6,
          screentoneRotation: command.screentoneRotation ?? 45.0,
          screentoneSoftness: command.screentoneSoftness ?? 0.0,
          screentoneShape:
              BrushShape.values[(command.screentoneShapeIndex ?? 0).clamp(
                0,
                BrushShape.values.length - 1,
              )],
          hollow: hollow && !erase,
          hollowRatio: hollowRatio,
          eraseOccludedParts: hollow && !erase && eraseOccludedParts,
        );
      }
    case PaintingDrawCommandType.stampSegment:
      {
        final Offset? start = command.start;
        final Offset? end = command.end;
        final double? startRadius = command.startRadius;
        final double? endRadius = command.endRadius;
        final int? shapeIndex = command.shapeIndex;
        if (start == null ||
            end == null ||
            startRadius == null ||
            endRadius == null ||
            shapeIndex == null) {
          return null;
        }
        final int clamped = shapeIndex.clamp(0, BrushShape.values.length - 1);
        return _RustWgpuStrokeDrawData(
          points: <Offset>[start, end],
          radii: <double>[startRadius.abs(), endRadius.abs()],
          color: Color(command.color),
          brushShape: BrushShape.values[clamped],
          erase: erase,
          antialiasLevel: antialiasLevel,
          includeStart: command.includeStartCap ?? true,
          randomRotation: command.randomRotation ?? false,
          smoothRotation: command.smoothRotation ?? false,
          rotationSeed: command.rotationSeed ?? 0,
          rotationJitter: command.rotationJitter ?? 1.0,
          spacing: command.spacing ?? 0.15,
          scatter: command.scatter ?? 0.0,
          softness: command.softness ?? 0.0,
          snapToPixel: command.snapToPixel ?? false,
          screentoneEnabled: command.screentoneEnabled ?? false,
          screentoneSpacing: command.screentoneSpacing ?? 10.0,
          screentoneDotSize: command.screentoneDotSize ?? 0.6,
          screentoneRotation: command.screentoneRotation ?? 45.0,
          screentoneSoftness: command.screentoneSoftness ?? 0.0,
          screentoneShape:
              BrushShape.values[(command.screentoneShapeIndex ?? 0).clamp(
                0,
                BrushShape.values.length - 1,
              )],
          hollow: hollow && !erase,
          hollowRatio: hollowRatio,
          eraseOccludedParts: hollow && !erase && eraseOccludedParts,
        );
      }
    case PaintingDrawCommandType.vectorStroke:
      {
        final List<Offset>? points = command.points;
        final List<double>? radii = command.radii;
        final int? shapeIndex = command.shapeIndex;
        if (points == null || radii == null || shapeIndex == null) {
          return null;
        }
        final int clamped = shapeIndex.clamp(0, BrushShape.values.length - 1);
        final bool resolvedHollow = (command.hollow ?? false) && !erase;
        final bool resolvedEraseOccludedParts =
            resolvedHollow && (command.eraseOccludedParts ?? false);
        return _RustWgpuStrokeDrawData(
          points: List<Offset>.from(points),
          radii: List<double>.from(radii),
          color: Color(command.color),
          brushShape: BrushShape.values[clamped],
          erase: erase,
          antialiasLevel: antialiasLevel,
          includeStart: command.includeStartCap ?? true,
          randomRotation: command.randomRotation ?? false,
          smoothRotation: command.smoothRotation ?? false,
          rotationSeed: command.rotationSeed ?? 0,
          rotationJitter: command.rotationJitter ?? 1.0,
          spacing: command.spacing ?? 0.15,
          scatter: command.scatter ?? 0.0,
          softness: command.softness ?? 0.0,
          snapToPixel: command.snapToPixel ?? false,
          screentoneEnabled: command.screentoneEnabled ?? false,
          screentoneSpacing: command.screentoneSpacing ?? 10.0,
          screentoneDotSize: command.screentoneDotSize ?? 0.6,
          screentoneRotation: command.screentoneRotation ?? 45.0,
          screentoneSoftness: command.screentoneSoftness ?? 0.0,
          screentoneShape:
              BrushShape.values[(command.screentoneShapeIndex ?? 0).clamp(
                0,
                BrushShape.values.length - 1,
              )],
          hollow: resolvedHollow,
          hollowRatio: resolvedHollow ? (command.hollowRatio ?? 0.0) : 0.0,
          eraseOccludedParts: resolvedEraseOccludedParts,
        );
      }
    case PaintingDrawCommandType.filledPolygon:
      return null;
  }
}

void _controllerFlushDeferredStrokeCommands(BitmapCanvasController controller) {
  PaintingDrawCommand? overlayCommand;
  const bool showCommitOverlay = true;
  if (controller._currentStrokePoints.isNotEmpty &&
      controller._currentStrokePoints.length ==
          controller._currentStrokeRadii.length) {
    final PaintingDrawCommand command = PaintingDrawCommand.vectorStroke(
      points: List<Offset>.from(controller._currentStrokePoints),
      radii: List<double>.from(controller._currentStrokeRadii),
      colorValue: controller._currentStrokeColor.value,
      shapeIndex: controller._currentBrushShape.index,
      antialiasLevel: controller._currentStrokeAntialiasLevel,
      erase: controller._currentStrokeEraseMode,
      hollow: controller._currentStrokeHollowEnabled,
      hollowRatio: controller._currentStrokeHollowRatio,
      eraseOccludedParts: controller._currentStrokeEraseOccludedParts,
      randomRotation: controller._currentStrokeRandomRotationEnabled,
      smoothRotation: controller._currentStrokeSmoothRotationEnabled,
      rotationSeed: controller._currentStrokeRotationSeed,
    );
    overlayCommand = command;
    if (showCommitOverlay) {
      controller._committingStrokes.add(command);
      controller._notify();
    }
  }

  if (overlayCommand != null) {
    final PaintingDrawCommand command = overlayCommand;
    final bool hollow =
        (command.hollow ?? false) &&
        !command.erase &&
        (command.hollowRatio ?? 0.0) > 0.0001;
    final bool eraseOccludedParts = command.eraseOccludedParts ?? false;

    if (!controller._activeLayer.surface.isTiled &&
        hollow &&
        !eraseOccludedParts) {
      controller._deferredStrokeCommands.clear();
      controller._currentStrokePoints.clear();
      controller._currentStrokeRadii.clear();

      unawaited(() async {
        try {
          await _controllerDrawStrokeOnRustWgpu(
            controller,
            layerId: controller._activeLayer.id,
            points: command.points ?? const <Offset>[],
            radii: command.radii ?? const <double>[],
            color: Color(command.color),
            brushShape: BrushShape.values[command.shapeIndex ?? 0],
            erase: command.erase,
            antialiasLevel: command.antialiasLevel,
            includeStart: command.includeStartCap ?? true,
            randomRotation: command.randomRotation ?? false,
            smoothRotation: command.smoothRotation ?? false,
            rotationSeed: command.rotationSeed ?? 0,
            rotationJitter: command.rotationJitter ?? 1.0,
            spacing: command.spacing ?? 0.15,
            scatter: command.scatter ?? 0.0,
            softness: command.softness ?? 0.0,
            snapToPixel: command.snapToPixel ?? false,
            screentoneEnabled: command.screentoneEnabled ?? false,
            screentoneSpacing: command.screentoneSpacing ?? 10.0,
            screentoneDotSize: command.screentoneDotSize ?? 0.6,
            screentoneRotation: command.screentoneRotation ?? 45.0,
            screentoneSoftness: command.screentoneSoftness ?? 0.0,
            screentoneShape:
                BrushShape.values[(command.screentoneShapeIndex ?? 0).clamp(
                  0,
                  BrushShape.values.length - 1,
                )],
            hollow: true,
            hollowRatio: command.hollowRatio ?? 0.0,
            eraseOccludedParts: false,
          );
        } finally {
          if (!showCommitOverlay) {
            return;
          }
          controller._removeCommitOverlay(command);
        }
      }());
      return;
    }
  }

  controller._commitDeferredStrokeCommandsAsRaster();
  if (overlayCommand != null && showCommitOverlay) {
    final PaintingDrawCommand command = overlayCommand;
    unawaited(
      controller._enqueueRustWgpuBrushTask<void>(() async {}).whenComplete(
        () {
          controller._removeCommitOverlay(command);
        },
      ),
    );
  }
}

Future<void> _controllerDrawStrokeOnRustWgpu(
  BitmapCanvasController controller, {
  required String layerId,
  required List<Offset> points,
  required List<double> radii,
  required Color color,
  required BrushShape brushShape,
  required bool erase,
  required int antialiasLevel,
  required bool includeStart,
  required bool randomRotation,
  required bool smoothRotation,
  required int rotationSeed,
  required double rotationJitter,
  required double spacing,
  required double scatter,
  required double softness,
  required bool snapToPixel,
  required bool screentoneEnabled,
  required double screentoneSpacing,
  required double screentoneDotSize,
  required double screentoneRotation,
  required double screentoneSoftness,
  required BrushShape screentoneShape,
  bool eraseOccludedParts = false,
  bool hollow = false,
  double hollowRatio = 0.0,
}) async {
  if (points.isEmpty) {
    return;
  }
  if (points.length != radii.length) {
    throw StateError('Rust WGPU 笔触 points/radii 长度不一致');
  }

  await controller._enqueueRustWgpuBrushTask<void>(() async {
    final int layerIndex = controller._layers.indexWhere(
      (BitmapLayerState layer) => layer.id == layerId,
    );
    if (layerIndex < 0) {
      return;
    }
    final BitmapLayerState layer = controller._layers[layerIndex];
    if (layer.locked) {
      return;
    }

    final int canvasWidth = controller._width;
    final int canvasHeight = controller._height;
    final int aa = antialiasLevel.clamp(0, 9);
    final Uint8List? mask = controller._selectionMaskIsFull
        ? null
        : controller._selectionMask;

    Rect computeDirtyRect() {
      if (points.isEmpty) {
        return Rect.zero;
      }
      if (points.length == 1) {
        return _strokeDirtyRectForCircle(points[0], radii[0]);
      }
      Rect dirty = _strokeDirtyRectForVariableLine(
        points[0],
        points[1],
        radii[0],
        radii[1],
      );
      for (int i = 1; i < points.length - 1; i++) {
        dirty = BitmapCanvasController._unionRects(
          dirty,
          _strokeDirtyRectForVariableLine(
            points[i],
            points[i + 1],
            radii[i],
            radii[i + 1],
          ),
        );
      }
      return dirty;
    }

    final Rect dirty = computeDirtyRect();
    if (dirty.isEmpty) {
      return;
    }
    final Rect canvasRect = Rect.fromLTWH(
      0,
      0,
      canvasWidth.toDouble(),
      canvasHeight.toDouble(),
    );
    Rect clipped = dirty.intersect(canvasRect);
    if (clipped.isEmpty) {
      return;
    }
    if (mask != null) {
      RasterIntRect? selectionBounds = controller._selectionMaskBounds;
      selectionBounds ??= _controllerMaskBounds(
        mask,
        controller._width,
        controller._height,
      );
      if (selectionBounds == null) {
        return;
      }
      final Rect selectionRect = Rect.fromLTRB(
        selectionBounds.left.toDouble(),
        selectionBounds.top.toDouble(),
        selectionBounds.right.toDouble(),
        selectionBounds.bottom.toDouble(),
      );
      clipped = clipped.intersect(selectionRect);
      if (clipped.isEmpty) {
        return;
      }
    }

    final int outerLeft = clipped.left.floor().clamp(0, canvasWidth);
    final int outerTop = clipped.top.floor().clamp(0, canvasHeight);
    final int outerRight = clipped.right.ceil().clamp(0, canvasWidth);
    final int outerBottom = clipped.bottom.ceil().clamp(0, canvasHeight);
    final int copyW = outerRight - outerLeft;
    final int copyH = outerBottom - outerTop;
    if (copyW <= 0 || copyH <= 0) {
      return;
    }

    final BitmapSurface surface = layer.surface.bitmapSurface!;
    final Uint32List destination = surface.pixels;

    void drawStrokeOnSurface({
      required Color strokeColor,
      required List<double> strokeRadii,
      required bool eraseMode,
    }) {
      if (points.length == 1) {
        surface.drawBrushStamp(
          center: points[0],
          radius: strokeRadii[0],
          color: strokeColor,
          shape: brushShape,
          mask: mask,
          antialiasLevel: aa,
          erase: eraseMode,
          softness: softness,
          randomRotation: randomRotation,
          smoothRotation: smoothRotation,
          rotationSeed: rotationSeed,
          rotationJitter: rotationJitter,
          snapToPixel: snapToPixel,
          screentoneEnabled: screentoneEnabled,
          screentoneShape: screentoneShape,
          screentoneSpacing: screentoneSpacing,
          screentoneDotSize: screentoneDotSize,
          screentoneRotation: screentoneRotation,
          screentoneSoftness: screentoneSoftness,
        );
        return;
      }

      for (int i = 0; i < points.length - 1; i++) {
        final bool includeSegmentStart = i == 0 ? includeStart : false;
        _controllerApplyStampSegmentFallback(
          surface: surface,
          start: points[i],
          end: points[i + 1],
          startRadius: strokeRadii[i],
          endRadius: strokeRadii[i + 1],
          includeStart: includeSegmentStart,
          shape: brushShape,
          color: strokeColor,
          mask: mask,
          antialias: aa,
          erase: eraseMode,
          randomRotation: randomRotation,
          smoothRotation: smoothRotation,
          rotationSeed: rotationSeed,
          rotationJitter: rotationJitter,
          spacing: spacing,
          scatter: scatter,
          softness: softness,
          snapToPixel: snapToPixel,
          screentoneEnabled: screentoneEnabled,
          screentoneShape: screentoneShape,
          screentoneSpacing: screentoneSpacing,
          screentoneDotSize: screentoneDotSize,
          screentoneRotation: screentoneRotation,
          screentoneSoftness: screentoneSoftness,
        );
      }
    }

    final bool resolvedHollow = hollow && !erase && hollowRatio > 0.0001;
    final bool resolvedEraseOccludedParts =
        resolvedHollow && eraseOccludedParts;

    Uint32List? before;
    if (resolvedHollow && !resolvedEraseOccludedParts) {
      before = Uint32List(copyW * copyH);
      for (int row = 0; row < copyH; row++) {
        final int srcOffset = (outerTop + row) * canvasWidth + outerLeft;
        final int dstOffset = row * copyW;
        before.setRange(dstOffset, dstOffset + copyW, destination, srcOffset);
      }
    }

    drawStrokeOnSurface(
      strokeColor: color,
      strokeRadii: radii,
      eraseMode: erase,
    );

    if (!resolvedHollow) {
      surface.markDirty();
      controller._resetWorkerSurfaceSync();
      controller._markDirty(
        region: Rect.fromLTRB(
          outerLeft.toDouble(),
          outerTop.toDouble(),
          outerRight.toDouble(),
          outerBottom.toDouble(),
        ),
        layerId: layerId,
        pixelsDirty: true,
      );
      controller._rustWgpuBrushSyncedRevisions[layerId] = layer.revision;
      return;
    }

    final List<double> scaledRadii = radii
        .map((double radius) => radius * hollowRatio.clamp(0.0, 1.0))
        .toList(growable: false);

    if (resolvedEraseOccludedParts) {
      drawStrokeOnSurface(
        strokeColor: const Color(0xFFFFFFFF),
        strokeRadii: scaledRadii,
        eraseMode: true,
      );
      surface.markDirty();
      controller._resetWorkerSurfaceSync();
      controller._markDirty(
        region: Rect.fromLTRB(
          outerLeft.toDouble(),
          outerTop.toDouble(),
          outerRight.toDouble(),
          outerBottom.toDouble(),
        ),
        layerId: layerId,
        pixelsDirty: true,
      );
      controller._rustWgpuBrushSyncedRevisions[layerId] = layer.revision;
      return;
    }

    int lerpPremultiplied(int from, int to, double t) {
      final double clamped = t.clamp(0.0, 1.0);
      if (clamped <= 0.000001) {
        return from;
      }
      if (clamped >= 0.999999) {
        return to;
      }

      final int a0 = (from >> 24) & 0xff;
      final int r0 = (from >> 16) & 0xff;
      final int g0 = (from >> 8) & 0xff;
      final int b0 = from & 0xff;
      final int a1 = (to >> 24) & 0xff;
      final int r1 = (to >> 16) & 0xff;
      final int g1 = (to >> 8) & 0xff;
      final int b1 = to & 0xff;

      final double fa0 = a0 / 255.0;
      final double fa1 = a1 / 255.0;
      final double pr0 = (r0 / 255.0) * fa0;
      final double pg0 = (g0 / 255.0) * fa0;
      final double pb0 = (b0 / 255.0) * fa0;
      final double pr1 = (r1 / 255.0) * fa1;
      final double pg1 = (g1 / 255.0) * fa1;
      final double pb1 = (b1 / 255.0) * fa1;

      final double inv = 1.0 - clamped;
      final double fa = fa0 * inv + fa1 * clamped;
      final double pr = pr0 * inv + pr1 * clamped;
      final double pg = pg0 * inv + pg1 * clamped;
      final double pb = pb0 * inv + pb1 * clamped;

      if (fa <= 0.000001) {
        return 0;
      }
      final double invA = 1.0 / fa;
      final int outA = (fa * 255.0).round().clamp(0, 255);
      final int outR = ((pr * invA) * 255.0).round().clamp(0, 255);
      final int outG = ((pg * invA) * 255.0).round().clamp(0, 255);
      final int outB = ((pb * invA) * 255.0).round().clamp(0, 255);
      return (outA << 24) | (outR << 16) | (outG << 8) | outB;
    }

    final Uint32List outerAfter = Uint32List(copyW * copyH);
    for (int row = 0; row < copyH; row++) {
      final int srcOffset = (outerTop + row) * canvasWidth + outerLeft;
      final int dstOffset = row * copyW;
      outerAfter.setRange(dstOffset, dstOffset + copyW, destination, srcOffset);
    }

    drawStrokeOnSurface(
      strokeColor: const Color(0xFFFFFFFF),
      strokeRadii: scaledRadii,
      eraseMode: true,
    );

    final Uint32List beforeResolved = before ?? Uint32List(0);
    for (int y = outerTop; y < outerBottom; y++) {
      final int outerRow = (y - outerTop) * copyW;
      final int destRow = y * canvasWidth;
      for (int x = outerLeft; x < outerRight; x++) {
        final int outerIndex = outerRow + (x - outerLeft);
        final int destIndex = destRow + x;

        final int o = outerAfter[outerIndex];
        final int oa = (o >> 24) & 0xff;
        if (oa == 0) {
          continue;
        }
        final int e = destination[destIndex];
        final int ea = (e >> 24) & 0xff;
        if (ea >= oa) {
          continue;
        }

        final double coverage = (1.0 - (ea / oa)).clamp(0.0, 1.0);
        if (coverage <= 0.000001) {
          continue;
        }
        final int b = beforeResolved[outerIndex];
        destination[destIndex] = lerpPremultiplied(o, b, coverage);
      }
    }

    surface.markDirty();
    controller._resetWorkerSurfaceSync();
    controller._markDirty(
      region: Rect.fromLTRB(
        outerLeft.toDouble(),
        outerTop.toDouble(),
        outerRight.toDouble(),
        outerBottom.toDouble(),
      ),
      layerId: layerId,
      pixelsDirty: true,
    );
    controller._rustWgpuBrushSyncedRevisions[layerId] = layer.revision;
  });
}

void _controllerFlushRealtimeStrokeCommands(BitmapCanvasController controller) {
  if (controller._currentStrokeDeferRaster) {
    return;
  }
  if (controller._currentStrokeHollowEnabled &&
      !controller._currentStrokeEraseOccludedParts) {
    return;
  }
  if (controller._realtimeStrokeFlushScheduled) {
    return;
  }
  controller._realtimeStrokeFlushScheduled = true;
  final SchedulerBinding? scheduler = SchedulerBinding.instance;
  if (scheduler == null) {
    scheduleMicrotask(() {
      controller._realtimeStrokeFlushScheduled = false;
      controller._commitDeferredStrokeCommandsAsRaster(keepStrokeState: true);
    });
    return;
  }
  scheduler.scheduleFrameCallback((_) {
    controller._realtimeStrokeFlushScheduled = false;
    controller._commitDeferredStrokeCommandsAsRaster(keepStrokeState: true);
  });
  scheduler.ensureVisualUpdate();
}

Uint32List _controllerCopySurfaceRegion(
  Uint32List pixels,
  int surfaceWidth,
  RasterIntRect rect,
) {
  final int width = rect.width;
  final int height = rect.height;
  final Uint32List patch = Uint32List(width * height);
  for (int row = 0; row < height; row++) {
    final int srcRowStart = (rect.top + row) * surfaceWidth + rect.left;
    patch.setRange(row * width, (row + 1) * width, pixels, srcRowStart);
  }
  return patch;
}

void _controllerWriteSurfaceRegion(
  Uint32List pixels,
  int surfaceWidth,
  RasterIntRect rect,
  Uint32List patch,
) {
  final int width = rect.width;
  final int height = rect.height;
  for (int row = 0; row < height; row++) {
    final int dstRowStart = (rect.top + row) * surfaceWidth + rect.left;
    pixels.setRange(dstRowStart, dstRowStart + width, patch, row * width);
  }
}

Uint8List _controllerCopyMaskRegion(
  Uint8List mask,
  int surfaceWidth,
  RasterIntRect rect,
) {
  final int width = rect.width;
  final int height = rect.height;
  final Uint8List patch = Uint8List(width * height);
  for (int row = 0; row < height; row++) {
    final int srcRowStart = (rect.top + row) * surfaceWidth + rect.left;
    patch.setRange(row * width, (row + 1) * width, mask, srcRowStart);
  }
  return patch;
}

Uint8List _controllerCopyMaskTile(
  Uint8List mask,
  int surfaceWidth,
  int surfaceHeight,
  RasterIntRect tileRect,
  int tileSize,
) {
  final Uint8List tileMask = Uint8List(tileSize * tileSize);
  final int left = tileRect.left.clamp(0, surfaceWidth);
  final int top = tileRect.top.clamp(0, surfaceHeight);
  final int right = tileRect.right.clamp(0, surfaceWidth);
  final int bottom = tileRect.bottom.clamp(0, surfaceHeight);
  if (left >= right || top >= bottom) {
    return tileMask;
  }
  final int copyWidth = right - left;
  for (int row = top; row < bottom; row++) {
    final int srcRow = row * surfaceWidth + left;
    final int dstRow = (row - tileRect.top) * tileSize + (left - tileRect.left);
    tileMask.setRange(dstRow, dstRow + copyWidth, mask, srcRow);
  }
  return tileMask;
}

void _controllerCommitDeferredStrokeCommandsAsRaster(
  BitmapCanvasController controller, {
  bool keepStrokeState = false,
}) {
  if (controller._deferredStrokeCommands.isEmpty) {
    if (!keepStrokeState) {
      controller._currentStrokePoints.clear();
      controller._currentStrokeRadii.clear();
    }
    return;
  }
  final List<PaintingDrawCommand> commands = List<PaintingDrawCommand>.from(
    controller._deferredStrokeCommands,
  );
  controller._deferredStrokeCommands.clear();
  final bool hollow = controller._currentStrokeHollowEnabled;
  final double hollowRatio = controller._currentStrokeHollowRatio;
  final bool eraseOccludedParts = controller._currentStrokeEraseOccludedParts;
  final BrushShapeRaster? customShape = controller.customBrushShapeRaster;
  final bool useCustomShape = customShape != null;

  if (controller._activeLayer.surface.isTiled) {
    Rect? union;
    for (final PaintingDrawCommand command in commands) {
      final Rect? bounds = controller._dirtyRectForCommand(command);
      if (bounds == null || bounds.isEmpty) {
        continue;
      }
      union = union == null ? bounds : _controllerUnionRects(union, bounds);
      if (controller._useWorkerForRaster) {
        controller._enqueuePaintingWorkerCommand(
          region: bounds,
          command: command,
        );
      }
    }
    if (union != null && !union.isEmpty && !controller._useWorkerForRaster) {
      controller._applyPaintingCommandsSynchronously(union, commands);
    }
    if (!keepStrokeState) {
      controller._currentStrokePoints.clear();
      controller._currentStrokeRadii.clear();
    }
    return;
  }

  for (final PaintingDrawCommand command in commands) {
    if (useCustomShape) {
      final Rect? bounds = controller._dirtyRectForCommand(command);
      if (bounds == null || bounds.isEmpty) {
        continue;
      }
      controller._applyPaintingCommandsSynchronously(
        bounds,
        <PaintingDrawCommand>[command],
      );
      continue;
    }
    final _RustWgpuStrokeDrawData? stroke =
        _controllerRustWgpuStrokeFromCommand(
          command,
          hollow: hollow,
          hollowRatio: hollowRatio,
          eraseOccludedParts: eraseOccludedParts,
        );
    if (stroke == null) {
      final Rect? bounds = controller._dirtyRectForCommand(command);
      if (bounds == null || bounds.isEmpty) {
        continue;
      }
      controller._applyPaintingCommandsSynchronously(
        bounds,
        <PaintingDrawCommand>[command],
      );
      continue;
    }
    unawaited(
      _controllerDrawStrokeOnRustWgpu(
        controller,
        layerId: controller._activeLayer.id,
        points: stroke.points,
        radii: stroke.radii,
        color: stroke.color,
        brushShape: stroke.brushShape,
        erase: stroke.erase,
        antialiasLevel: stroke.antialiasLevel,
        includeStart: stroke.includeStart,
        randomRotation: stroke.randomRotation,
        smoothRotation: stroke.smoothRotation,
        rotationSeed: stroke.rotationSeed,
        rotationJitter: stroke.rotationJitter,
        spacing: stroke.spacing,
        scatter: stroke.scatter,
        softness: stroke.softness,
        snapToPixel: stroke.snapToPixel,
        screentoneEnabled: stroke.screentoneEnabled,
        screentoneShape: stroke.screentoneShape,
        screentoneSpacing: stroke.screentoneSpacing,
        screentoneDotSize: stroke.screentoneDotSize,
        screentoneRotation: stroke.screentoneRotation,
        screentoneSoftness: stroke.screentoneSoftness,
        hollow: stroke.hollow,
        hollowRatio: stroke.hollowRatio,
        eraseOccludedParts: stroke.eraseOccludedParts,
      ),
    );
  }
  if (!keepStrokeState) {
    controller._currentStrokePoints.clear();
    controller._currentStrokeRadii.clear();
  }
}

void _controllerDispatchDirectPaintCommand(
  BitmapCanvasController controller,
  PaintingDrawCommand command,
) {
  final Rect? bounds = controller._dirtyRectForCommand(command);
  if (bounds == null || bounds.isEmpty) {
    return;
  }
  if (controller._activeLayer.surface.isTiled) {
    if (controller._useWorkerForRaster) {
      controller._enqueuePaintingWorkerCommand(
        region: bounds,
        command: command,
      );
    } else {
      controller._applyPaintingCommandsSynchronously(
        bounds,
        <PaintingDrawCommand>[command],
      );
    }
    return;
  }
  final _RustWgpuStrokeDrawData? stroke = _controllerRustWgpuStrokeFromCommand(
    command,
    hollow: false,
    hollowRatio: 0.0,
    eraseOccludedParts: false,
  );
  if (stroke == null) {
    controller._applyPaintingCommandsSynchronously(
      bounds,
      <PaintingDrawCommand>[command],
    );
    return;
  }
  unawaited(
    _controllerDrawStrokeOnRustWgpu(
      controller,
      layerId: controller._activeLayer.id,
      points: stroke.points,
      radii: stroke.radii,
      color: stroke.color,
      brushShape: stroke.brushShape,
      erase: stroke.erase,
      antialiasLevel: stroke.antialiasLevel,
      includeStart: stroke.includeStart,
      randomRotation: stroke.randomRotation,
      smoothRotation: stroke.smoothRotation,
      rotationSeed: stroke.rotationSeed,
      rotationJitter: stroke.rotationJitter,
      spacing: stroke.spacing,
      scatter: stroke.scatter,
      softness: stroke.softness,
      snapToPixel: stroke.snapToPixel,
      screentoneEnabled: stroke.screentoneEnabled,
      screentoneShape: stroke.screentoneShape,
      screentoneSpacing: stroke.screentoneSpacing,
      screentoneDotSize: stroke.screentoneDotSize,
      screentoneRotation: stroke.screentoneRotation,
      screentoneSoftness: stroke.screentoneSoftness,
      eraseOccludedParts: stroke.eraseOccludedParts,
      hollow: false,
      hollowRatio: 0.0,
    ),
  );
}

Rect? _controllerDirtyRectForCommand(
  BitmapCanvasController controller,
  PaintingDrawCommand command,
) {
  switch (command.type) {
    case PaintingDrawCommandType.brushStamp:
      final Offset? center = command.center;
      final double? radius = command.radius;
      if (center == null || radius == null) {
        return null;
      }
      final double softness = (command.softness ?? 0.0).clamp(0.0, 1.0);
      final double expandedRadius = softness > 0
          ? radius + radius * softBrushExtentMultiplier(softness)
          : radius;
      return _strokeDirtyRectForCircle(center, expandedRadius);
    case PaintingDrawCommandType.line:
      final Offset? start = command.start;
      final Offset? end = command.end;
      final double? radius = command.radius;
      if (start == null || end == null || radius == null) {
        return null;
      }
      return _strokeDirtyRectForLine(start, end, radius);
    case PaintingDrawCommandType.variableLine:
      final Offset? start = command.start;
      final Offset? end = command.end;
      final double? startRadius = command.startRadius;
      final double? endRadius = command.endRadius;
      if (start == null ||
          end == null ||
          startRadius == null ||
          endRadius == null) {
        return null;
      }
      return _strokeDirtyRectForVariableLine(
        start,
        end,
        startRadius,
        endRadius,
      );
    case PaintingDrawCommandType.stampSegment:
      final Offset? start = command.start;
      final Offset? end = command.end;
      final double? startRadius = command.startRadius;
      final double? endRadius = command.endRadius;
      if (start == null ||
          end == null ||
          startRadius == null ||
          endRadius == null) {
        return null;
      }
      return _strokeDirtyRectForVariableLine(
        start,
        end,
        startRadius,
        endRadius,
      );
    case PaintingDrawCommandType.vectorStroke:
      return null;
    case PaintingDrawCommandType.filledPolygon:
      final List<Offset>? polygon = command.points;
      if (polygon == null || polygon.length < 3) {
        return null;
      }
      double minX = polygon.first.dx;
      double maxX = polygon.first.dx;
      double minY = polygon.first.dy;
      double maxY = polygon.first.dy;
      for (final Offset point in polygon) {
        if (point.dx < minX) minX = point.dx;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dy > maxY) maxY = point.dy;
      }
      final double padding = 2.0 + command.antialiasLevel.clamp(0, 9) * 1.2;
      return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(padding);
  }
}

void _controllerApplyRustWgpuStrokeResult(
  BitmapCanvasController controller, {
  required String layerId,
  required rust_wgpu_brush.RustWgpuStrokeResult result,
}) {
  // Deprecated: Rust WGPU brush no longer returns pixel patches (Flow 5 hard ban).
  // Keep the symbol to avoid large refactors; call sites have been removed.
  // ignore: unused_local_variable
  final _ = result;
}

int _controllerUnpremultiplyChannel(int value, int alpha) {
  if (alpha <= 0) {
    return 0;
  }
  if (alpha >= 255) {
    return value;
  }
  final int result = ((value * 255) + (alpha >> 1)) ~/ alpha;
  if (result < 0) {
    return 0;
  }
  if (result > 255) {
    return 255;
  }
  return result;
}

bool _controllerMergeVectorPatchOnMainThread(
  BitmapCanvasController controller, {
  required Uint8List rgbaPixels,
  required int left,
  required int top,
  required int width,
  required int height,
  required bool erase,
  required bool eraseOccludedParts,
}) {
  if (width <= 0 || height <= 0 || rgbaPixels.isEmpty) {
    return false;
  }
  final int clampedLeft = math.max(0, math.min(left, controller._width));
  final int clampedTop = math.max(0, math.min(top, controller._height));
  final int clampedRight = math.max(
    0,
    math.min(left + width, controller._width),
  );
  final int clampedBottom = math.max(
    0,
    math.min(top + height, controller._height),
  );
  if (clampedRight <= clampedLeft || clampedBottom <= clampedTop) {
    return false;
  }

  final LayerSurface surface = controller._activeLayer.surface;
  final Uint8List? selectionMask = controller._selectionMaskIsFull
      ? null
      : controller._selectionMask;
  final bool selectionIsFull = controller._selectionMaskIsFull;
  final TiledSelectionMask? tiledMask = controller._selectionMaskTiled;
  final RasterIntRect? selectionBounds =
      (selectionMask != null && !selectionIsFull)
      ? controller._selectionMaskBounds
      : null;
  if (selectionMask != null && !selectionIsFull && selectionBounds == null) {
    return false;
  }
  if (surface.isTiled) {
    final TiledSurface tiled = surface.tiledSurface!;
    RasterIntRect patchRect = RasterIntRect(
      clampedLeft,
      clampedTop,
      clampedRight,
      clampedBottom,
    );
    if (selectionBounds != null) {
      final int left = math.max(patchRect.left, selectionBounds.left);
      final int top = math.max(patchRect.top, selectionBounds.top);
      final int right = math.min(patchRect.right, selectionBounds.right);
      final int bottom = math.min(patchRect.bottom, selectionBounds.bottom);
      if (left >= right || top >= bottom) {
        return false;
      }
      patchRect = RasterIntRect(left, top, right, bottom);
    }
    final Map<TileKey, Uint8List> cachedTileMasks =
        (selectionMask == null || selectionIsFull || tiledMask != null)
        ? const <TileKey, Uint8List>{}
        : <TileKey, Uint8List>{};
    bool anyChange = false;
    final int tileSize = tiled.tileSize;
    final int startTx = tileIndexForCoord(patchRect.left, tileSize);
    final int endTx = tileIndexForCoord(patchRect.right - 1, tileSize);
    final int startTy = tileIndexForCoord(patchRect.top, tileSize);
    final int endTy = tileIndexForCoord(patchRect.bottom - 1, tileSize);

    for (int ty = startTy; ty <= endTy; ty++) {
      for (int tx = startTx; tx <= endTx; tx++) {
        final RasterIntRect tileRect = tileBounds(tx, ty, tileSize);
        final int boundLeft = patchRect.left > tileRect.left
            ? patchRect.left
            : tileRect.left;
        final int boundTop = patchRect.top > tileRect.top
            ? patchRect.top
            : tileRect.top;
        final int boundRight = patchRect.right < tileRect.right
            ? patchRect.right
            : tileRect.right;
        final int boundBottom = patchRect.bottom < tileRect.bottom
            ? patchRect.bottom
            : tileRect.bottom;
        if (boundLeft >= boundRight || boundTop >= boundBottom) {
          continue;
        }
        final RasterIntRect localRect = RasterIntRect(
          boundLeft - tileRect.left,
          boundTop - tileRect.top,
          boundRight - tileRect.left,
          boundBottom - tileRect.top,
        );

        Uint8List? tileMask;
        if (selectionMask == null || selectionIsFull) {
          tileMask = null;
        } else if (tiledMask != null) {
          tileMask = tiledMask.tile(tx, ty);
          if (tileMask == null) {
            continue;
          }
        } else {
          final TileKey key = TileKey(tx, ty);
          tileMask = cachedTileMasks[key] ??= _controllerCopyMaskTile(
            selectionMask,
            controller._width,
            controller._height,
            tileRect,
            tileSize,
          );
          if (!_controllerMaskHasCoverage(tileMask)) {
            continue;
          }
        }

        BitmapSurface? tileSurface = tiled.getTile(tx, ty);
        Uint32List? destination = tileSurface?.pixels;
        bool tileChanged = false;
        final int localWidth = localRect.width;
        final int localHeight = localRect.height;
        final int patchX0 = boundLeft - left;

        for (int row = 0; row < localHeight; row++) {
          final int surfaceY = boundTop + row;
          final int patchY = surfaceY - top;
          if (patchY < 0 || patchY >= height) {
            continue;
          }
          final int rgbaRowOffset = (patchY * width + patchX0) * 4;
          final int localY = localRect.top + row;
          int destIndex = localY * tileSize + localRect.left;
          int maskIndex = destIndex;
          int rgbaIndex = rgbaRowOffset;
          for (int col = 0; col < localWidth; col++) {
            if (rgbaIndex + 3 >= rgbaPixels.length) {
              break;
            }
            if (tileMask != null && tileMask[maskIndex] == 0) {
              rgbaIndex += 4;
              destIndex++;
              maskIndex++;
              continue;
            }
            final int a = rgbaPixels[rgbaIndex + 3];
            if (a == 0) {
              rgbaIndex += 4;
              destIndex++;
              maskIndex++;
              continue;
            }

            if (tileSurface == null) {
              tileSurface = tiled.ensureTile(tx, ty);
              destination = tileSurface.pixels;
            }

            final int r = rgbaPixels[rgbaIndex];
            final int g = rgbaPixels[rgbaIndex + 1];
            final int b = rgbaPixels[rgbaIndex + 2];
            final int dstColor = destination![destIndex];
            final int dstA = (dstColor >> 24) & 0xff;
            final int dstR = (dstColor >> 16) & 0xff;
            final int dstG = (dstColor >> 8) & 0xff;
            final int dstB = dstColor & 0xff;

            if (erase) {
              final double alphaFactor = 1.0 - (a / 255.0);
              final int outA = (dstA * alphaFactor).round();
              destination[destIndex] =
                  (outA << 24) | (dstR << 16) | (dstG << 8) | dstB;
              tileChanged = true;
              anyChange = true;
              rgbaIndex += 4;
              destIndex++;
              maskIndex++;
              continue;
            }

            final int srcR = _controllerUnpremultiplyChannel(r, a);
            final int srcG = _controllerUnpremultiplyChannel(g, a);
            final int srcB = _controllerUnpremultiplyChannel(b, a);

            if (eraseOccludedParts) {
              destination[destIndex] =
                  (a << 24) |
                  (srcR.clamp(0, 255) << 16) |
                  (srcG.clamp(0, 255) << 8) |
                  srcB.clamp(0, 255);
              tileChanged = true;
              anyChange = true;
              rgbaIndex += 4;
              destIndex++;
              maskIndex++;
              continue;
            }

            final double srcAlpha = a / 255.0;
            final double dstAlpha = dstA / 255.0;
            final double invSrcAlpha = 1.0 - srcAlpha;
            final double outAlphaDouble = srcAlpha + dstAlpha * invSrcAlpha;
            if (outAlphaDouble <= 0.001) {
              rgbaIndex += 4;
              destIndex++;
              maskIndex++;
              continue;
            }
            final int outA = (outAlphaDouble * 255.0).round();
            final double outR =
                (srcR * srcAlpha + dstR * dstAlpha * invSrcAlpha) /
                outAlphaDouble;
            final double outG =
                (srcG * srcAlpha + dstG * dstAlpha * invSrcAlpha) /
                outAlphaDouble;
            final double outB =
                (srcB * srcAlpha + dstB * dstAlpha * invSrcAlpha) /
                outAlphaDouble;

            destination[destIndex] =
                (outA.clamp(0, 255) << 24) |
                (outR.round().clamp(0, 255) << 16) |
                (outG.round().clamp(0, 255) << 8) |
                outB.round().clamp(0, 255);
            tileChanged = true;
            anyChange = true;
            rgbaIndex += 4;
            destIndex++;
            maskIndex++;
          }
        }

        if (tileChanged && tileSurface != null) {
          tileSurface.markDirty();
        }
      }
    }

    if (!anyChange) {
      return false;
    }
    controller._resetWorkerSurfaceSync();
    final Rect dirtyRegion = Rect.fromLTRB(
      patchRect.left.toDouble(),
      patchRect.top.toDouble(),
      patchRect.right.toDouble(),
      patchRect.bottom.toDouble(),
    );
    controller._markDirty(
      region: dirtyRegion,
      layerId: controller._activeLayer.id,
      pixelsDirty: true,
    );
    return true;
  }

  final RasterIntRect patchRect = RasterIntRect(
    clampedLeft,
    clampedTop,
    clampedRight,
    clampedBottom,
  );
  RasterIntRect effectiveRect = patchRect;
  if (selectionBounds != null) {
    final int leftBound = math.max(patchRect.left, selectionBounds.left);
    final int topBound = math.max(patchRect.top, selectionBounds.top);
    final int rightBound = math.min(patchRect.right, selectionBounds.right);
    final int bottomBound = math.min(patchRect.bottom, selectionBounds.bottom);
    if (leftBound >= rightBound || topBound >= bottomBound) {
      return false;
    }
    effectiveRect = RasterIntRect(leftBound, topBound, rightBound, bottomBound);
  }

  final int rowStart = (effectiveRect.top - top).clamp(0, height);
  final int rowEnd = (effectiveRect.bottom - top).clamp(0, height);
  final int colStart = (effectiveRect.left - left).clamp(0, width);
  final int colEnd = (effectiveRect.right - left).clamp(0, width);
  if (rowStart >= rowEnd || colStart >= colEnd) {
    return false;
  }

  final bool anyChange = surface.withBitmapSurface(
    writeBack: true,
    action: (BitmapSurface bitmapSurface) {
      final Uint32List destination = bitmapSurface.pixels;
      bool changed = false;

      for (int y = rowStart; y < rowEnd; y++) {
        final int surfaceY = top + y;
        if (surfaceY < 0 || surfaceY >= controller._height) {
          continue;
        }
        final int surfaceRowOffset = surfaceY * controller._width;
        final int rgbaRowOffset = y * width * 4;

        for (int x = colStart; x < colEnd; x++) {
          final int surfaceX = left + x;
          if (surfaceX < 0 || surfaceX >= controller._width) {
            continue;
          }
          if (selectionMask != null &&
              selectionMask[surfaceRowOffset + surfaceX] == 0) {
            continue;
          }

          final int rgbaIndex = rgbaRowOffset + x * 4;
          if (rgbaIndex + 3 >= rgbaPixels.length) {
            continue;
          }
          final int a = rgbaPixels[rgbaIndex + 3];
          if (a == 0) {
            continue;
          }

          final int r = rgbaPixels[rgbaIndex];
          final int g = rgbaPixels[rgbaIndex + 1];
          final int b = rgbaPixels[rgbaIndex + 2];
          final int destIndex = surfaceRowOffset + surfaceX;
          final int dstColor = destination[destIndex];
          final int dstA = (dstColor >> 24) & 0xff;
          final int dstR = (dstColor >> 16) & 0xff;
          final int dstG = (dstColor >> 8) & 0xff;
          final int dstB = dstColor & 0xff;

          if (erase) {
            final double alphaFactor = 1.0 - (a / 255.0);
            final int outA = (dstA * alphaFactor).round();
            destination[destIndex] =
                (outA << 24) | (dstR << 16) | (dstG << 8) | dstB;
            changed = true;
            continue;
          }

          final int srcR = _controllerUnpremultiplyChannel(r, a);
          final int srcG = _controllerUnpremultiplyChannel(g, a);
          final int srcB = _controllerUnpremultiplyChannel(b, a);

          if (eraseOccludedParts) {
            destination[destIndex] =
                (a << 24) |
                (srcR.clamp(0, 255) << 16) |
                (srcG.clamp(0, 255) << 8) |
                srcB.clamp(0, 255);
            changed = true;
            continue;
          }

          final double srcAlpha = a / 255.0;
          final double dstAlpha = dstA / 255.0;
          final double invSrcAlpha = 1.0 - srcAlpha;
          final double outAlphaDouble = srcAlpha + dstAlpha * invSrcAlpha;
          if (outAlphaDouble <= 0.001) {
            continue;
          }
          final int outA = (outAlphaDouble * 255.0).round();
          final double outR =
              (srcR * srcAlpha + dstR * dstAlpha * invSrcAlpha) /
              outAlphaDouble;
          final double outG =
              (srcG * srcAlpha + dstG * dstAlpha * invSrcAlpha) /
              outAlphaDouble;
          final double outB =
              (srcB * srcAlpha + dstB * dstAlpha * invSrcAlpha) /
              outAlphaDouble;

          destination[destIndex] =
              (outA.clamp(0, 255) << 24) |
              (outR.round().clamp(0, 255) << 16) |
              (outG.round().clamp(0, 255) << 8) |
              outB.round().clamp(0, 255);
          changed = true;
        }
      }

      if (changed) {
        bitmapSurface.markDirty();
      }
      return changed;
    },
  );

  if (!anyChange) {
    return false;
  }

  controller._resetWorkerSurfaceSync();
  final Rect dirtyRegion = Rect.fromLTRB(
    effectiveRect.left.toDouble(),
    effectiveRect.top.toDouble(),
    effectiveRect.right.toDouble(),
    effectiveRect.bottom.toDouble(),
  );
  controller._markDirty(
    region: dirtyRegion,
    layerId: controller._activeLayer.id,
    pixelsDirty: true,
  );
  return true;
}

void _controllerApplyPaintingCommandsSynchronously(
  BitmapCanvasController controller,
  Rect region,
  List<PaintingDrawCommand> commands,
) {
  if (commands.isEmpty) {
    return;
  }
  if (controller._activeLayer.surface.isTiled) {
    _controllerApplyPaintingCommandsSynchronouslyTiled(
      controller,
      region,
      commands,
    );
    return;
  }
  final BitmapSurface surface = controller._activeLayer.surface.bitmapSurface!;
  final Uint8List? mask = controller._selectionMaskIsFull
      ? null
      : controller._selectionMask;
  Rect effectiveRegion = region;
  if (mask != null) {
    RasterIntRect? selectionBounds = controller._selectionMaskBounds;
    selectionBounds ??= _controllerMaskBounds(
      mask,
      controller._width,
      controller._height,
    );
    if (selectionBounds == null) {
      return;
    }
    final Rect selectionRect = Rect.fromLTRB(
      selectionBounds.left.toDouble(),
      selectionBounds.top.toDouble(),
      selectionBounds.right.toDouble(),
      selectionBounds.bottom.toDouble(),
    );
    effectiveRegion = effectiveRegion.intersect(selectionRect);
    if (effectiveRegion.isEmpty) {
      return;
    }
  }
  final BrushShapeRaster? customShape = controller.customBrushShapeRaster;
  bool anyChange = false;
  for (final PaintingDrawCommand command in commands) {
    final Rect? bounds = controller._dirtyRectForCommand(command);
    if (bounds != null && !bounds.overlaps(effectiveRegion)) {
      continue;
    }
    final Color color = Color(command.color);
    final bool erase = command.erase;
    switch (command.type) {
      case PaintingDrawCommandType.brushStamp:
        final Offset? center = command.center;
        final double? radius = command.radius;
        final int? shapeIndex = command.shapeIndex;
        if (center == null || radius == null || shapeIndex == null) {
          continue;
        }
        final int screentoneShapeIndex = (command.screentoneShapeIndex ?? 0)
            .clamp(0, BrushShape.values.length - 1);
        final BrushShape screentoneShape =
            BrushShape.values[screentoneShapeIndex];
        final int clampedShape = shapeIndex.clamp(
          0,
          BrushShape.values.length - 1,
        );
        if (customShape != null) {
          final Uint8List customMask = customShape.packedMask;
          surface.drawBrushStamp(
            center: center,
            radius: radius,
            color: color,
            shape: BrushShape.values[clampedShape],
            mask: mask,
            antialiasLevel: command.antialiasLevel,
            erase: erase,
            softness: command.softness ?? 0.0,
            randomRotation: command.randomRotation ?? false,
            smoothRotation: command.smoothRotation ?? false,
            rotationSeed: command.rotationSeed ?? 0,
            rotationJitter: command.rotationJitter ?? 1.0,
            snapToPixel: command.snapToPixel ?? false,
            screentoneEnabled: command.screentoneEnabled ?? false,
            screentoneSpacing: command.screentoneSpacing ?? 10.0,
            screentoneDotSize: command.screentoneDotSize ?? 0.6,
            screentoneRotation: command.screentoneRotation ?? 45.0,
            screentoneSoftness: command.screentoneSoftness ?? 0.0,
            screentoneShape: screentoneShape,
            customMask: customMask,
            customMaskWidth: customShape.width,
            customMaskHeight: customShape.height,
          );
        } else {
          surface.drawBrushStamp(
            center: center,
            radius: radius,
            color: color,
            shape: BrushShape.values[clampedShape],
            mask: mask,
            antialiasLevel: command.antialiasLevel,
            erase: erase,
            softness: command.softness ?? 0.0,
            randomRotation: command.randomRotation ?? false,
            smoothRotation: command.smoothRotation ?? false,
            rotationSeed: command.rotationSeed ?? 0,
            rotationJitter: command.rotationJitter ?? 1.0,
            snapToPixel: command.snapToPixel ?? false,
            screentoneEnabled: command.screentoneEnabled ?? false,
            screentoneSpacing: command.screentoneSpacing ?? 10.0,
            screentoneDotSize: command.screentoneDotSize ?? 0.6,
            screentoneRotation: command.screentoneRotation ?? 45.0,
            screentoneSoftness: command.screentoneSoftness ?? 0.0,
            screentoneShape: screentoneShape,
          );
        }
        anyChange = true;
        break;
      case PaintingDrawCommandType.line:
        final Offset? start = command.start;
        final Offset? end = command.end;
        final double? radius = command.radius;
        if (start == null || end == null || radius == null) {
          continue;
        }
        final int screentoneShapeIndex = (command.screentoneShapeIndex ?? 0)
            .clamp(0, BrushShape.values.length - 1);
        final BrushShape screentoneShape =
            BrushShape.values[screentoneShapeIndex];
        surface.drawLine(
          a: start,
          b: end,
          radius: radius,
          color: color,
          mask: mask,
          antialiasLevel: command.antialiasLevel,
          includeStartCap: command.includeStartCap ?? true,
          erase: erase,
          screentoneEnabled: command.screentoneEnabled ?? false,
          screentoneSpacing: command.screentoneSpacing ?? 10.0,
          screentoneDotSize: command.screentoneDotSize ?? 0.6,
          screentoneRotation: command.screentoneRotation ?? 45.0,
          screentoneSoftness: command.screentoneSoftness ?? 0.0,
          screentoneShape: screentoneShape,
        );
        anyChange = true;
        break;
      case PaintingDrawCommandType.variableLine:
        final Offset? start = command.start;
        final Offset? end = command.end;
        final double? startRadius = command.startRadius;
        final double? endRadius = command.endRadius;
        if (start == null ||
            end == null ||
            startRadius == null ||
            endRadius == null) {
          continue;
        }
        final int screentoneShapeIndex = (command.screentoneShapeIndex ?? 0)
            .clamp(0, BrushShape.values.length - 1);
        final BrushShape screentoneShape =
            BrushShape.values[screentoneShapeIndex];
        surface.drawVariableLine(
          a: start,
          b: end,
          startRadius: startRadius,
          endRadius: endRadius,
          color: color,
          mask: mask,
          antialiasLevel: command.antialiasLevel,
          includeStartCap: command.includeStartCap ?? true,
          erase: erase,
          screentoneEnabled: command.screentoneEnabled ?? false,
          screentoneSpacing: command.screentoneSpacing ?? 10.0,
          screentoneDotSize: command.screentoneDotSize ?? 0.6,
          screentoneRotation: command.screentoneRotation ?? 45.0,
          screentoneSoftness: command.screentoneSoftness ?? 0.0,
          screentoneShape: screentoneShape,
        );
        anyChange = true;
        break;
      case PaintingDrawCommandType.stampSegment:
        final Offset? start = command.start;
        final Offset? end = command.end;
        final double? startRadius = command.startRadius;
        final double? endRadius = command.endRadius;
        final int? shapeIndex = command.shapeIndex;
        if (start == null ||
            end == null ||
            startRadius == null ||
            endRadius == null ||
            shapeIndex == null) {
          continue;
        }
        final int screentoneShapeIndex = (command.screentoneShapeIndex ?? 0)
            .clamp(0, BrushShape.values.length - 1);
        final BrushShape screentoneShape =
            BrushShape.values[screentoneShapeIndex];
        final int clampedShape = shapeIndex.clamp(
          0,
          BrushShape.values.length - 1,
        );
        _controllerApplyStampSegmentFallback(
          surface: surface,
          start: start,
          end: end,
          startRadius: startRadius,
          endRadius: endRadius,
          includeStart: command.includeStartCap ?? true,
          shape: BrushShape.values[clampedShape],
          color: color,
          mask: mask,
          antialias: command.antialiasLevel,
          erase: erase,
          randomRotation: command.randomRotation ?? false,
          smoothRotation: command.smoothRotation ?? false,
          rotationSeed: command.rotationSeed ?? 0,
          rotationJitter: command.rotationJitter ?? 1.0,
          spacing: command.spacing ?? 0.15,
          scatter: command.scatter ?? 0.0,
          softness: command.softness ?? 0.0,
          snapToPixel: command.snapToPixel ?? false,
          screentoneEnabled: command.screentoneEnabled ?? false,
          screentoneSpacing: command.screentoneSpacing ?? 10.0,
          screentoneDotSize: command.screentoneDotSize ?? 0.6,
          screentoneRotation: command.screentoneRotation ?? 45.0,
          screentoneSoftness: command.screentoneSoftness ?? 0.0,
          screentoneShape: screentoneShape,
          customShape: customShape,
        );
        anyChange = true;
        break;
      case PaintingDrawCommandType.vectorStroke:
        break;
      case PaintingDrawCommandType.filledPolygon:
        final List<Offset>? points = command.points;
        if (points == null || points.length < 3) {
          continue;
        }
        surface.drawFilledPolygon(
          vertices: points,
          color: color,
          mask: mask,
          antialiasLevel: command.antialiasLevel,
          erase: erase,
        );
        anyChange = true;
        break;
    }
  }
  if (!anyChange) {
    return;
  }
  controller._resetWorkerSurfaceSync();
  controller._markDirty(
    region: effectiveRegion,
    layerId: controller._activeLayer.id,
    pixelsDirty: true,
  );
}

void _controllerApplyPaintingCommandsSynchronouslyTiled(
  BitmapCanvasController controller,
  Rect region,
  List<PaintingDrawCommand> commands,
) {
  if (commands.isEmpty) {
    return;
  }
  final TiledSurface tiled = controller._activeLayer.surface.tiledSurface!;
  final Uint8List? selectionMask = controller._selectionMask;
  final bool selectionIsFull = controller._selectionMaskIsFull;
  final TiledSelectionMask? tiledMask = controller._selectionMaskTiled;
  final bool hasSelection = selectionMask != null && !selectionIsFull;
  final RasterIntRect? selectionBounds = hasSelection
      ? controller._selectionMaskBounds
      : null;
  if (hasSelection && selectionBounds == null) {
    return;
  }
  Rect effectiveRegion = region;
  if (selectionBounds != null) {
    final Rect selectionRect = Rect.fromLTRB(
      selectionBounds.left.toDouble(),
      selectionBounds.top.toDouble(),
      selectionBounds.right.toDouble(),
      selectionBounds.bottom.toDouble(),
    );
    effectiveRegion = effectiveRegion.intersect(selectionRect);
    if (effectiveRegion.isEmpty) {
      return;
    }
  }
  final Map<TileKey, Uint8List> cachedTileMasks =
      (selectionMask == null || selectionIsFull || tiledMask != null)
      ? const <TileKey, Uint8List>{}
      : <TileKey, Uint8List>{};
  final BrushShapeRaster? customShape = controller.customBrushShapeRaster;
  bool anyChange = false;

  bool applyCommandToTile({
    required BitmapSurface surface,
    required Offset tileOrigin,
    required Uint8List? mask,
    required PaintingDrawCommand command,
  }) {
    final Color color = Color(command.color);
    final bool erase = command.erase;
    switch (command.type) {
      case PaintingDrawCommandType.brushStamp:
        final Offset? center = command.center;
        final double? radius = command.radius;
        final int? shapeIndex = command.shapeIndex;
        if (center == null || radius == null || shapeIndex == null) {
          return false;
        }
        final int screentoneShapeIndex = (command.screentoneShapeIndex ?? 0)
            .clamp(0, BrushShape.values.length - 1);
        final BrushShape screentoneShape =
            BrushShape.values[screentoneShapeIndex];
        final Offset localCenter = center - tileOrigin;
        final int clampedShape = shapeIndex.clamp(
          0,
          BrushShape.values.length - 1,
        );
        if (customShape != null) {
          final Uint8List customMask = customShape.packedMask;
          surface.drawBrushStamp(
            center: localCenter,
            radius: radius,
            color: color,
            shape: BrushShape.values[clampedShape],
            mask: mask,
            antialiasLevel: command.antialiasLevel,
            erase: erase,
            softness: command.softness ?? 0.0,
            randomRotation: command.randomRotation ?? false,
            smoothRotation: command.smoothRotation ?? false,
            rotationSeed: command.rotationSeed ?? 0,
            rotationJitter: command.rotationJitter ?? 1.0,
            snapToPixel: command.snapToPixel ?? false,
            screentoneEnabled: command.screentoneEnabled ?? false,
            screentoneSpacing: command.screentoneSpacing ?? 10.0,
            screentoneDotSize: command.screentoneDotSize ?? 0.6,
            screentoneRotation: command.screentoneRotation ?? 45.0,
            screentoneSoftness: command.screentoneSoftness ?? 0.0,
            screentoneShape: screentoneShape,
            customMask: customMask,
            customMaskWidth: customShape.width,
            customMaskHeight: customShape.height,
          );
        } else {
          surface.drawBrushStamp(
            center: localCenter,
            radius: radius,
            color: color,
            shape: BrushShape.values[clampedShape],
            mask: mask,
            antialiasLevel: command.antialiasLevel,
            erase: erase,
            softness: command.softness ?? 0.0,
            randomRotation: command.randomRotation ?? false,
            smoothRotation: command.smoothRotation ?? false,
            rotationSeed: command.rotationSeed ?? 0,
            rotationJitter: command.rotationJitter ?? 1.0,
            snapToPixel: command.snapToPixel ?? false,
            screentoneEnabled: command.screentoneEnabled ?? false,
            screentoneSpacing: command.screentoneSpacing ?? 10.0,
            screentoneDotSize: command.screentoneDotSize ?? 0.6,
            screentoneRotation: command.screentoneRotation ?? 45.0,
            screentoneSoftness: command.screentoneSoftness ?? 0.0,
            screentoneShape: screentoneShape,
          );
        }
        return true;
      case PaintingDrawCommandType.line:
        final Offset? start = command.start;
        final Offset? end = command.end;
        final double? radius = command.radius;
        if (start == null || end == null || radius == null) {
          return false;
        }
        final int screentoneShapeIndex = (command.screentoneShapeIndex ?? 0)
            .clamp(0, BrushShape.values.length - 1);
        final BrushShape screentoneShape =
            BrushShape.values[screentoneShapeIndex];
        surface.drawLine(
          a: start - tileOrigin,
          b: end - tileOrigin,
          radius: radius,
          color: color,
          mask: mask,
          antialiasLevel: command.antialiasLevel,
          includeStartCap: command.includeStartCap ?? true,
          erase: erase,
          screentoneEnabled: command.screentoneEnabled ?? false,
          screentoneSpacing: command.screentoneSpacing ?? 10.0,
          screentoneDotSize: command.screentoneDotSize ?? 0.6,
          screentoneRotation: command.screentoneRotation ?? 45.0,
          screentoneSoftness: command.screentoneSoftness ?? 0.0,
          screentoneShape: screentoneShape,
        );
        return true;
      case PaintingDrawCommandType.variableLine:
        final Offset? start = command.start;
        final Offset? end = command.end;
        final double? startRadius = command.startRadius;
        final double? endRadius = command.endRadius;
        if (start == null ||
            end == null ||
            startRadius == null ||
            endRadius == null) {
          return false;
        }
        final int screentoneShapeIndex = (command.screentoneShapeIndex ?? 0)
            .clamp(0, BrushShape.values.length - 1);
        final BrushShape screentoneShape =
            BrushShape.values[screentoneShapeIndex];
        surface.drawVariableLine(
          a: start - tileOrigin,
          b: end - tileOrigin,
          startRadius: startRadius,
          endRadius: endRadius,
          color: color,
          mask: mask,
          antialiasLevel: command.antialiasLevel,
          includeStartCap: command.includeStartCap ?? true,
          erase: erase,
          screentoneEnabled: command.screentoneEnabled ?? false,
          screentoneSpacing: command.screentoneSpacing ?? 10.0,
          screentoneDotSize: command.screentoneDotSize ?? 0.6,
          screentoneRotation: command.screentoneRotation ?? 45.0,
          screentoneSoftness: command.screentoneSoftness ?? 0.0,
          screentoneShape: screentoneShape,
        );
        return true;
      case PaintingDrawCommandType.stampSegment:
        final Offset? start = command.start;
        final Offset? end = command.end;
        final double? startRadius = command.startRadius;
        final double? endRadius = command.endRadius;
        final int? shapeIndex = command.shapeIndex;
        if (start == null ||
            end == null ||
            startRadius == null ||
            endRadius == null ||
            shapeIndex == null) {
          return false;
        }
        final int screentoneShapeIndex = (command.screentoneShapeIndex ?? 0)
            .clamp(0, BrushShape.values.length - 1);
        final BrushShape screentoneShape =
            BrushShape.values[screentoneShapeIndex];
        final int clampedShape = shapeIndex.clamp(
          0,
          BrushShape.values.length - 1,
        );
        _controllerApplyStampSegmentFallback(
          surface: surface,
          start: start - tileOrigin,
          end: end - tileOrigin,
          startRadius: startRadius,
          endRadius: endRadius,
          includeStart: command.includeStartCap ?? true,
          shape: BrushShape.values[clampedShape],
          color: color,
          mask: mask,
          antialias: command.antialiasLevel,
          erase: erase,
          randomRotation: command.randomRotation ?? false,
          smoothRotation: command.smoothRotation ?? false,
          rotationSeed: command.rotationSeed ?? 0,
          rotationJitter: command.rotationJitter ?? 1.0,
          spacing: command.spacing ?? 0.15,
          scatter: command.scatter ?? 0.0,
          softness: command.softness ?? 0.0,
          snapToPixel: command.snapToPixel ?? false,
          screentoneEnabled: command.screentoneEnabled ?? false,
          screentoneSpacing: command.screentoneSpacing ?? 10.0,
          screentoneDotSize: command.screentoneDotSize ?? 0.6,
          screentoneRotation: command.screentoneRotation ?? 45.0,
          screentoneSoftness: command.screentoneSoftness ?? 0.0,
          screentoneShape: screentoneShape,
          customShape: customShape,
        );
        return true;
      case PaintingDrawCommandType.vectorStroke:
        return false;
      case PaintingDrawCommandType.filledPolygon:
        final List<Offset>? points = command.points;
        if (points == null || points.length < 3) {
          return false;
        }
        final List<Offset> localPoints = List<Offset>.generate(
          points.length,
          (int index) => points[index] - tileOrigin,
          growable: false,
        );
        surface.drawFilledPolygon(
          vertices: localPoints,
          color: color,
          mask: mask,
          antialiasLevel: command.antialiasLevel,
          erase: erase,
        );
        return true;
    }
  }

  for (final PaintingDrawCommand command in commands) {
    final Rect? bounds = controller._dirtyRectForCommand(command);
    if (bounds == null || bounds.isEmpty) {
      continue;
    }
    final RasterIntRect clipped = controller._clipRectToSurface(bounds);
    if (clipped.isEmpty) {
      continue;
    }
    if (!hasSelection) {
      for (final TileEntry entry in tiled.tilesInRect(
        clipped,
        createMissing: true,
      )) {
        final RasterIntRect tileRect = tileBounds(
          entry.key.tx,
          entry.key.ty,
          tiled.tileSize,
        );
        final Offset tileOrigin = Offset(
          tileRect.left.toDouble(),
          tileRect.top.toDouble(),
        );
        final BitmapSurface surface = entry.surface;
        if (applyCommandToTile(
          surface: surface,
          tileOrigin: tileOrigin,
          mask: null,
          command: command,
        )) {
          anyChange = true;
        }
      }
    } else {
      RasterIntRect effective = clipped;
      if (selectionBounds != null) {
        final int left = math.max(clipped.left, selectionBounds.left);
        final int top = math.max(clipped.top, selectionBounds.top);
        final int right = math.min(clipped.right, selectionBounds.right);
        final int bottom = math.min(clipped.bottom, selectionBounds.bottom);
        if (left >= right || top >= bottom) {
          continue;
        }
        effective = RasterIntRect(left, top, right, bottom);
      }
      final int tileSize = tiled.tileSize;
      final int startTx = tileIndexForCoord(effective.left, tileSize);
      final int endTx = tileIndexForCoord(effective.right - 1, tileSize);
      final int startTy = tileIndexForCoord(effective.top, tileSize);
      final int endTy = tileIndexForCoord(effective.bottom - 1, tileSize);
      for (int ty = startTy; ty <= endTy; ty++) {
        for (int tx = startTx; tx <= endTx; tx++) {
          final RasterIntRect tileRect = tileBounds(tx, ty, tileSize);
          final int left = effective.left > tileRect.left
              ? effective.left
              : tileRect.left;
          final int top = effective.top > tileRect.top
              ? effective.top
              : tileRect.top;
          final int right = effective.right < tileRect.right
              ? effective.right
              : tileRect.right;
          final int bottom = effective.bottom < tileRect.bottom
              ? effective.bottom
              : tileRect.bottom;
          if (left >= right || top >= bottom) {
            continue;
          }

          Uint8List? tileMask;
          if (tiledMask != null) {
            tileMask = tiledMask.tile(tx, ty);
            if (tileMask == null) {
              continue;
            }
          } else {
            final TileKey key = TileKey(tx, ty);
            tileMask = cachedTileMasks[key] ??= _controllerCopyMaskTile(
              selectionMask!,
              controller._width,
              controller._height,
              tileRect,
              tileSize,
            );
            if (!_controllerMaskHasCoverage(tileMask)) {
              continue;
            }
          }

          final BitmapSurface surface =
              tiled.getTile(tx, ty) ?? tiled.ensureTile(tx, ty);
          final Offset tileOrigin = Offset(
            tileRect.left.toDouble(),
            tileRect.top.toDouble(),
          );
          if (applyCommandToTile(
            surface: surface,
            tileOrigin: tileOrigin,
            mask: tileMask,
            command: command,
          )) {
            anyChange = true;
          }
        }
      }
    }
  }
  if (!anyChange) {
    return;
  }
  controller._resetWorkerSurfaceSync();
  controller._markDirty(
    region: effectiveRegion,
    layerId: controller._activeLayer.id,
    pixelsDirty: true,
  );
}

void _controllerApplyStampSegmentFallback({
  required BitmapSurface surface,
  required Offset start,
  required Offset end,
  required double startRadius,
  required double endRadius,
  required bool includeStart,
  required BrushShape shape,
  required Color color,
  required Uint8List? mask,
  required int antialias,
  required bool erase,
  bool randomRotation = false,
  bool smoothRotation = false,
  int rotationSeed = 0,
  double rotationJitter = 1.0,
  double spacing = 0.15,
  double scatter = 0.0,
  double softness = 0.0,
  bool snapToPixel = false,
  bool screentoneEnabled = false,
  double screentoneSpacing = 10.0,
  double screentoneDotSize = 0.6,
  double screentoneRotation = 45.0,
  double screentoneSoftness = 0.0,
  BrushShape screentoneShape = BrushShape.circle,
  BrushShapeRaster? customShape,
}) {
  final Uint8List? customMask = customShape?.packedMask;
  final int customMaskWidth = customShape?.width ?? 0;
  final int customMaskHeight = customShape?.height ?? 0;
  if (RustCpuBrushFfi.instance.drawStampSegment(
    pixelsPtr: surface.pointerAddress,
    pixelsLen: surface.pixels.length,
    width: surface.width,
    height: surface.height,
    startX: start.dx,
    startY: start.dy,
    endX: end.dx,
    endY: end.dy,
    startRadius: startRadius,
    endRadius: endRadius,
    colorArgb: color.value,
    brushShape: shape.index,
    antialiasLevel: antialias,
    includeStart: includeStart,
    erase: erase,
    randomRotation: randomRotation,
    smoothRotation: smoothRotation,
    rotationSeed: rotationSeed,
    rotationJitter: rotationJitter,
    screentoneEnabled: screentoneEnabled,
    screentoneSpacing: screentoneSpacing,
    screentoneDotSize: screentoneDotSize,
    screentoneRotation: screentoneRotation,
    screentoneSoftness: screentoneSoftness,
    screentoneShape: screentoneShape.index,
    spacing: spacing,
    scatter: scatter,
    softness: softness,
    snapToPixel: snapToPixel,
    accumulate: true,
    customMask: customMask,
    customMaskWidth: customMaskWidth,
    customMaskHeight: customMaskHeight,
    selectionMask: mask,
  )) {
    surface.markDirty();
    return;
  }
  final double distance = (end - start).distance;
  if (!distance.isFinite || distance <= 0.0001) {
    if (customShape != null) {
      final double rotation = _customStampRotation(
        center: end,
        start: start,
        end: end,
        randomRotation: randomRotation,
        smoothRotation: smoothRotation,
        rotationSeed: rotationSeed,
        rotationJitter: rotationJitter,
      );
      surface.drawCustomBrushStamp(
        shape: customShape,
        center: end,
        radius: endRadius,
        color: color,
        erase: erase,
        softness: softness,
        rotation: rotation,
        snapToPixel: snapToPixel,
        mask: mask,
        antialiasLevel: antialias,
        screentoneEnabled: screentoneEnabled,
        screentoneSpacing: screentoneSpacing,
        screentoneDotSize: screentoneDotSize,
        screentoneRotation: screentoneRotation,
        screentoneSoftness: screentoneSoftness,
        screentoneShape: screentoneShape,
      );
    } else {
      surface.drawBrushStamp(
        center: end,
        radius: endRadius,
        color: color,
        shape: shape,
        mask: mask,
        antialiasLevel: antialias,
        erase: erase,
        softness: softness,
        randomRotation: randomRotation,
        smoothRotation: smoothRotation,
        rotationSeed: rotationSeed,
        rotationJitter: rotationJitter,
        snapToPixel: snapToPixel,
        screentoneEnabled: screentoneEnabled,
        screentoneSpacing: screentoneSpacing,
        screentoneDotSize: screentoneDotSize,
        screentoneRotation: screentoneRotation,
        screentoneSoftness: screentoneSoftness,
        screentoneShape: screentoneShape,
      );
    }
    return;
  }
  final double maxRadius = math.max(
    math.max(startRadius.abs(), endRadius.abs()),
    0.01,
  );
  final double step = _strokeStampSpacing(maxRadius, spacing);
  final int samples = math.max(1, (distance / step).ceil());
  final int startIndex = includeStart ? 0 : 1;
  for (int i = startIndex; i <= samples; i++) {
    final double t = samples == 0 ? 1.0 : (i / samples);
    final double radius = ui.lerpDouble(startRadius, endRadius, t) ?? endRadius;
    final double sampleX = ui.lerpDouble(start.dx, end.dx, t) ?? end.dx;
    final double sampleY = ui.lerpDouble(start.dy, end.dy, t) ?? end.dy;
    final Offset baseCenter = Offset(sampleX, sampleY);
    final double scatterRadius = maxRadius * scatter.clamp(0.0, 1.0) * 2.0;
    final Offset jitter = scatterRadius > 0
        ? brushScatterOffset(
            center: baseCenter,
            seed: rotationSeed,
            radius: scatterRadius,
            salt: i,
          )
        : Offset.zero;
    final Offset center = baseCenter + jitter;
    if (customShape != null) {
      final double rotation = _customStampRotation(
        center: center,
        start: start,
        end: end,
        randomRotation: randomRotation,
        smoothRotation: smoothRotation,
        rotationSeed: rotationSeed,
        rotationJitter: rotationJitter,
      );
      surface.drawCustomBrushStamp(
        shape: customShape,
        center: center,
        radius: radius,
        color: color,
        erase: erase,
        softness: softness,
        rotation: rotation,
        snapToPixel: snapToPixel,
        mask: mask,
        antialiasLevel: antialias,
        screentoneEnabled: screentoneEnabled,
        screentoneSpacing: screentoneSpacing,
        screentoneDotSize: screentoneDotSize,
        screentoneRotation: screentoneRotation,
        screentoneSoftness: screentoneSoftness,
        screentoneShape: screentoneShape,
      );
    } else {
      surface.drawBrushStamp(
        center: center,
        radius: radius,
        color: color,
        shape: shape,
        mask: mask,
        antialiasLevel: antialias,
        erase: erase,
        softness: softness,
        randomRotation: randomRotation,
        smoothRotation: smoothRotation,
        rotationSeed: rotationSeed,
        rotationJitter: rotationJitter,
        snapToPixel: snapToPixel,
        screentoneEnabled: screentoneEnabled,
        screentoneSpacing: screentoneSpacing,
        screentoneDotSize: screentoneDotSize,
        screentoneRotation: screentoneRotation,
        screentoneSoftness: screentoneSoftness,
        screentoneShape: screentoneShape,
      );
    }
  }
}

double _customStampRotation({
  required Offset center,
  required Offset start,
  required Offset end,
  required bool randomRotation,
  required bool smoothRotation,
  required int rotationSeed,
  required double rotationJitter,
}) {
  double rotation = 0.0;
  if (smoothRotation) {
    final Offset delta = end - start;
    if (delta.distanceSquared > 0.0001) {
      rotation = math.atan2(delta.dy, delta.dx);
    }
  }
  if (randomRotation) {
    rotation +=
        brushRandomRotationRadians(center: center, seed: rotationSeed) *
        rotationJitter;
  }
  return rotation;
}
