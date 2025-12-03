part of 'controller.dart';

void _controllerFlushDeferredStrokeCommands(
  BitmapCanvasController controller,
) {
  if (!controller._vectorDrawingEnabled) {
    controller._commitDeferredStrokeCommandsAsRaster();
    return;
  }
  if (controller._currentStrokePoints.isEmpty) {
    controller._deferredStrokeCommands.clear();
    return;
  }

  final List<Offset> points =
      List<Offset>.from(controller._currentStrokePoints);
  final List<double> radii =
      List<double>.from(controller._currentStrokeRadii);
  final Color color = controller._currentStrokeColor;
  final BrushShape shape = controller._currentBrushShape;
  final bool erase = controller._currentStrokeEraseMode;
  final int antialiasLevel = controller._currentStrokeAntialiasLevel;

  final PaintingDrawCommand vectorCommand = PaintingDrawCommand.vectorStroke(
    points: points,
    radii: radii,
    colorValue: color.value,
    shapeIndex: shape.index,
    erase: erase,
  );
  controller._committingStrokes.add(vectorCommand);

  controller._currentStrokePoints.clear();
  controller._currentStrokeRadii.clear();
  controller._deferredStrokeCommands.clear();

  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = double.negativeInfinity;
  double maxY = double.negativeInfinity;
  double maxRadius = 0.0;

  for (int i = 0; i < points.length; i++) {
    final Offset point = points[i];
    final double radius = (i < radii.length) ? radii[i] : 1.0;
    if (radius > maxRadius) {
      maxRadius = radius;
    }
    if (point.dx < minX) minX = point.dx;
    if (point.dx > maxX) maxX = point.dx;
    if (point.dy < minY) minY = point.dy;
    if (point.dy > maxY) maxY = point.dy;
  }

  final Rect dirtyRegion = Rect.fromLTRB(minX, minY, maxX, maxY)
      .inflate(maxRadius + 2.0);

  controller
      ._rasterizeVectorStroke(
        points,
        radii,
        color,
        shape,
        dirtyRegion,
        erase,
        antialiasLevel,
      )
      .then((_) {
        controller._committingStrokes.remove(vectorCommand);
        controller.notifyListeners();
      });
}

Future<void> _controllerRasterizeVectorStroke(
  BitmapCanvasController controller,
  List<Offset> points,
  List<double> radii,
  Color color,
  BrushShape shape,
  Rect bounds,
  bool erase,
  int antialiasLevel,
) async {
  final int width = bounds.width.ceil().clamp(1, controller._width);
  final int height = bounds.height.ceil().clamp(1, controller._height);
  final int left = bounds.left.floor().clamp(0, controller._width);
  final int top = bounds.top.floor().clamp(0, controller._height);
  final int safeWidth = math.min(width, controller._width - left);
  final int safeHeight = math.min(height, controller._height - top);

  if (safeWidth <= 0 || safeHeight <= 0) {
    return;
  }

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(
    recorder,
    Rect.fromLTWH(0, 0, safeWidth.toDouble(), safeHeight.toDouble()),
  );
  canvas.translate(-left.toDouble(), -top.toDouble());

  VectorStrokePainter.paint(
    canvas: canvas,
    points: points,
    radii: radii,
    color: color,
    shape: shape,
    antialiasLevel: antialiasLevel,
  );

  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(safeWidth, safeHeight);
  final ByteData? byteData =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);

  if (byteData == null) {
    image.dispose();
    picture.dispose();
    return;
  }

  final Uint8List pixels = byteData.buffer.asUint8List();
  image.dispose();
  picture.dispose();

  if (controller._isMultithreaded) {
    final TransferableTypedData transferablePixels =
        TransferableTypedData.fromList(<Uint8List>[pixels]);
    await controller._ensureWorkerSurfaceSynced();
    await controller._ensureWorkerSelectionMaskSynced();
    final PaintingWorkerPatch? patch = await controller
        ._ensurePaintingWorker()
        .mergePatch(
          PaintingMergePatchRequest(
            left: left,
            top: top,
            width: safeWidth,
            height: safeHeight,
            pixels: transferablePixels,
            erase: erase,
          ),
        );
    if (patch != null) {
      controller._applyWorkerPatch(patch);
      await controller._waitForNextFrame();
    }
  } else {
    final bool applied = controller._mergeVectorPatchOnMainThread(
      rgbaPixels: pixels,
      left: left,
      top: top,
      width: safeWidth,
      height: safeHeight,
      erase: erase,
    );
    if (applied) {
      await controller._waitForNextFrame();
    }
  }
}

void _controllerFlushRealtimeStrokeCommands(
  BitmapCanvasController controller,
) {
  if (controller._vectorDrawingEnabled) {
    return;
  }
  controller._commitDeferredStrokeCommandsAsRaster(keepStrokeState: true);
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
  if (controller._useWorkerForRaster) {
    for (final PaintingDrawCommand command in commands) {
      final Rect? bounds = controller._dirtyRectForCommand(command);
      if (bounds == null || bounds.isEmpty) {
        continue;
      }
      controller._enqueuePaintingWorkerCommand(
        region: bounds,
        command: command,
      );
    }
  } else {
    Rect? region;
    for (final PaintingDrawCommand command in commands) {
      final Rect? bounds = controller._dirtyRectForCommand(command);
      if (bounds == null || bounds.isEmpty) {
        continue;
      }
      region = region == null
          ? bounds
          : Rect.fromLTRB(
              math.min(region.left, bounds.left),
              math.min(region.top, bounds.top),
              math.max(region.right, bounds.right),
              math.max(region.bottom, bounds.bottom),
            );
    }
    if (region != null) {
      controller._applyPaintingCommandsSynchronously(region, commands);
    }
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
  if (controller._useWorkerForRaster) {
    controller._enqueuePaintingWorkerCommand(region: bounds, command: command);
    return;
  }
  controller._applyPaintingCommandsSynchronously(
    bounds,
    <PaintingDrawCommand>[command],
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
      final double padding = 2.0 + command.antialiasLevel.clamp(0, 3) * 1.2;
      return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(padding);
    case PaintingDrawCommandType.softSprayStamp:
      final Offset? center = command.center;
      final double? radius = command.radius;
      final double outerScale =
          command.softSprayStamp?.outerRadiusScale ??
          command.stampOuterScale ??
          1.0;
      if (center == null || radius == null) {
        return null;
      }
      final double outerRadius = radius * outerScale;
      return Rect.fromCircle(
        center: center,
        radius: outerRadius,
      ).inflate(2.0);
  }
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
}) {
  if (width <= 0 || height <= 0 || rgbaPixels.isEmpty) {
    return false;
  }
  final int clampedLeft = math.max(0, math.min(left, controller._width));
  final int clampedTop = math.max(0, math.min(top, controller._height));
  final int clampedRight =
      math.max(0, math.min(left + width, controller._width));
  final int clampedBottom =
      math.max(0, math.min(top + height, controller._height));
  if (clampedRight <= clampedLeft || clampedBottom <= clampedTop) {
    return false;
  }

  final Uint32List destination = controller._activeSurface.pixels;
  final Uint8List? mask = controller._selectionMask;
  bool anyChange = false;

  for (int y = 0; y < height; y++) {
    final int surfaceY = top + y;
    if (surfaceY < 0 || surfaceY >= controller._height) {
      continue;
    }
    final int surfaceRowOffset = surfaceY * controller._width;
    final int rgbaRowOffset = y * width * 4;

    for (int x = 0; x < width; x++) {
      final int surfaceX = left + x;
      if (surfaceX < 0 || surfaceX >= controller._width) {
        continue;
      }
      if (mask != null && mask[surfaceRowOffset + surfaceX] == 0) {
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
        anyChange = true;
        continue;
      }

      final int srcR = _controllerUnpremultiplyChannel(r, a);
      final int srcG = _controllerUnpremultiplyChannel(g, a);
      final int srcB = _controllerUnpremultiplyChannel(b, a);

      final double srcAlpha = a / 255.0;
      final double dstAlpha = dstA / 255.0;
      final double invSrcAlpha = 1.0 - srcAlpha;
      final double outAlphaDouble = srcAlpha + dstAlpha * invSrcAlpha;
      if (outAlphaDouble <= 0.001) {
        continue;
      }
      final int outA = (outAlphaDouble * 255.0).round();
      final double outR =
          (srcR * srcAlpha + dstR * dstAlpha * invSrcAlpha) / outAlphaDouble;
      final double outG =
          (srcG * srcAlpha + dstG * dstAlpha * invSrcAlpha) / outAlphaDouble;
      final double outB =
          (srcB * srcAlpha + dstB * dstAlpha * invSrcAlpha) / outAlphaDouble;

      destination[destIndex] =
          (outA.clamp(0, 255) << 24) |
          (outR.round().clamp(0, 255) << 16) |
          (outG.round().clamp(0, 255) << 8) |
          outB.round().clamp(0, 255);
      anyChange = true;
    }
  }

  if (!anyChange) {
    return false;
  }

  controller._resetWorkerSurfaceSync();
  controller._activeLayer.revision += 1;
  final Rect dirtyRegion = Rect.fromLTRB(
    clampedLeft.toDouble(),
    clampedTop.toDouble(),
    clampedRight.toDouble(),
    clampedBottom.toDouble(),
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
  final BitmapSurface surface = controller._activeSurface;
  final Uint8List? mask = controller._selectionMask;
  bool anyChange = false;
  for (final PaintingDrawCommand command in commands) {
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
        final int clampedShape = shapeIndex.clamp(
          0,
          BrushShape.values.length - 1,
        );
        surface.drawBrushStamp(
          center: center,
          radius: radius,
          color: color,
          shape: BrushShape.values[clampedShape],
          mask: mask,
          antialiasLevel: command.antialiasLevel,
          erase: erase,
          softness: command.softness ?? 0.0,
        );
        anyChange = true;
        break;
      case PaintingDrawCommandType.line:
        final Offset? start = command.start;
        final Offset? end = command.end;
        final double? radius = command.radius;
        if (start == null || end == null || radius == null) {
          continue;
        }
        surface.drawLine(
          a: start,
          b: end,
          radius: radius,
          color: color,
          mask: mask,
          antialiasLevel: command.antialiasLevel,
          includeStartCap: command.includeStartCap ?? true,
          erase: erase,
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
    case PaintingDrawCommandType.softSprayStamp:
      final Offset? center = command.center;
      final double? radius = command.radius;
      final SoftSprayStamp? stamp = command.softSprayStamp ??
          _commandSoftSprayStampFromPayload(command);
      if (center == null || radius == null || stamp == null) {
        continue;
      }
      _controllerDrawSoftSprayStamp(
        controller,
        center: center,
        radius: radius,
        color: color,
        stamp: stamp,
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
  controller._activeLayer.revision += 1;
  controller._markDirty(
    region: region,
    layerId: controller._activeLayer.id,
    pixelsDirty: true,
  );
}

SoftSprayStamp? _commandSoftSprayStampFromPayload(
  PaintingDrawCommand command,
) {
  final Uint8List? alpha = command.stampAlpha;
  final int? size = command.stampSize;
  final double? scale = command.stampOuterScale;
  if (alpha == null || size == null || scale == null) {
    return null;
  }
  return SoftSprayStamp(
    size: size,
    alpha: alpha,
    outerRadiusScale: scale,
  );
}

void _controllerDrawSoftSprayStamp(
  BitmapCanvasController controller, {
  required Offset center,
  required double radius,
  required Color color,
  required SoftSprayStamp stamp,
  bool erase = false,
}) {
  if (controller._layers.isEmpty || controller._activeLayer.locked) {
    return;
  }
  final double outerRadius = radius * stamp.outerRadiusScale;
  final Rect dirtyRegion =
      Rect.fromCircle(center: center, radius: outerRadius).inflate(2.0);
  controller._activeSurface.drawSoftSprayStamp(
        center: center,
        radius: radius,
        color: color,
        stamp: stamp,
        mask: controller._selectionMask,
        erase: erase,
      );
  controller._resetWorkerSurfaceSync();
  controller._activeLayer.revision += 1;
  controller._markDirty(
    region: dirtyRegion,
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
}) {
  final double distance = (end - start).distance;
  if (!distance.isFinite || distance <= 0.0001) {
    surface.drawBrushStamp(
      center: end,
      radius: endRadius,
      color: color,
      shape: shape,
      mask: mask,
      antialiasLevel: antialias,
      erase: erase,
    );
    return;
  }
  final double maxRadius = math.max(
    math.max(startRadius.abs(), endRadius.abs()),
    0.01,
  );
  final double spacing = _strokeStampSpacing(maxRadius);
  final int samples = math.max(1, (distance / spacing).ceil());
  final int startIndex = includeStart ? 0 : 1;
  for (int i = startIndex; i <= samples; i++) {
    final double t = samples == 0 ? 1.0 : (i / samples);
    final double radius = ui.lerpDouble(startRadius, endRadius, t) ?? endRadius;
    final double sampleX = ui.lerpDouble(start.dx, end.dx, t) ?? end.dx;
    final double sampleY = ui.lerpDouble(start.dy, end.dy, t) ?? end.dy;
    surface.drawBrushStamp(
      center: Offset(sampleX, sampleY),
      radius: radius,
      color: color,
      shape: shape,
      mask: mask,
      antialiasLevel: antialias,
      erase: erase,
    );
  }
}
