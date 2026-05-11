part of 'controller.dart';

const double _kStylusAbsoluteMinRadius = 0.005;
const double _kSimulatedAbsoluteMinRadius = 0.01;
const double _kAbsoluteMaxStrokeRadius = 512.0;

double _strokeStampSpacing(double radius, double spacing) {
  double r = radius.isFinite ? radius.abs() : 0.0;
  double s = spacing.isFinite ? spacing : 0.15;
  s = s.clamp(0.01, 2.5);
  return math.max(r * 2.0 * s, 0.05);
}

double _strokeAdaptiveSpacingForSegment(
  double baseSpacing,
  Offset start,
  Offset end,
  double startRadius,
  double endRadius,
) {
  final double clampedBase =
      (baseSpacing.isFinite ? baseSpacing : 0.15).clamp(0.01, 2.5);
  final double length = (end - start).distance;
  if (!length.isFinite || length <= 0.0001) {
    return clampedBase;
  }
  final double maxRadius = math.max(
    math.max(startRadius.abs(), endRadius.abs()),
    0.25,
  );
  final double nominalCoverage = maxRadius * 2.0;
  if (!nominalCoverage.isFinite || nominalCoverage <= 0.0001) {
    return clampedBase;
  }
  final double jumpRatio = length / nominalCoverage;
  if (!jumpRatio.isFinite || jumpRatio <= 0.9) {
    return clampedBase;
  }
  final double reduction = 1.0 / math.pow(jumpRatio.clamp(1.0, 12.0), 1.15);
  final double reduced = (clampedBase * reduction).clamp(0.015, clampedBase);
  final double capT = ((jumpRatio - 1.8) / 6.0).clamp(0.0, 1.0);
  final double speedCap = ui.lerpDouble(clampedBase, 0.03, capT) ?? reduced;
  return math.min(reduced, speedCap).clamp(0.015, clampedBase);
}

Rect _strokeDirtyRectForVariableLine(
  Offset a,
  Offset b,
  double startRadius,
  double endRadius,
) {
  final double maxRadius = math.max(math.max(startRadius, endRadius), 0.5);
  return Rect.fromPoints(a, b).inflate(maxRadius + 1.5);
}

Rect _strokeDirtyRectForCircle(Offset center, double radius) {
  final double effectiveRadius = math.max(radius, 0.5);
  return Rect.fromCircle(center: center, radius: effectiveRadius + 1.5);
}

Rect _strokeDirtyRectForLine(Offset a, Offset b, double radius) {
  final double inflate = math.max(radius, 0.5) + 1.5;
  return Rect.fromPoints(a, b).inflate(inflate);
}

void _strokeConfigureStylusPressure(
  BitmapCanvasController controller, {
  required bool enabled,
  double? curve,
}) {
  controller._stylusPressureEnabled = enabled;
  if (curve != null) {
    controller._stylusCurve = curve.clamp(0.1, 8.0);
  }
}

void _strokeConfigureSharpTips(
  BitmapCanvasController controller, {
  required bool enabled,
}) {
  controller._strokePressureSimulator.setSharpTipsEnabled(enabled);
}

void _strokeBegin(
  BitmapCanvasController controller,
  Offset position, {
  required Color color,
  required double radius,
  bool simulatePressure = false,
  bool useDevicePressure = false,
  double stylusPressureBlend = 1.0,
  double? pressure,
  double? pressureMin,
  double? pressureMax,
  StrokePressureProfile profile = StrokePressureProfile.auto,
  double? timestampMillis,
  int antialiasLevel = 0,
  BrushShape brushShape = BrushShape.circle,
  bool enableNeedleTips = false,
  bool randomRotation = false,
  bool smoothRotation = false,
  int? rotationSeed,
  double spacing = 0.15,
  double hardness = 0.8,
  double flow = 1.0,
  double scatter = 0.0,
  double rotationJitter = 1.0,
  bool snapToPixel = false,
  bool screentoneEnabled = false,
  double screentoneSpacing = 10.0,
  double screentoneDotSize = 0.6,
  double screentoneRotation = 45.0,
  double screentoneSoftness = 0.0,
  BrushShape screentoneShape = BrushShape.circle,
  double streamlineStrength = 0.0,
  bool erase = false,
  bool hollow = false,
  double hollowRatio = 0.0,
  bool eraseOccludedParts = false,
}) {
  if (controller._activeLayer.locked) {
    return;
  }
  if (controller._selectionMask != null &&
      !controller._selectionAllows(position)) {
    return;
  }
  controller.setStrokePressureProfile(profile);
  controller._currentStrokePoints
    ..clear()
    ..add(position);
  controller._currentStrokeRadii.clear();
  controller._currentStrokePreviewPoints.clear();
  controller._currentStrokePreviewRadii.clear();
  // Will be populated after initial simulation calculation
  controller._deferredStrokeCommands.clear();
  controller._currentStrokeRadius = radius;
  final double effectiveStylusBlend =
      controller._currentStrokeStylusPressureEnabled
      ? stylusPressureBlend.clamp(0.0, 1.0)
      : 0.0;
  controller._currentStrokeStylusPressureEnabled =
      useDevicePressure && controller._stylusPressureEnabled;
  final bool needleTipsEnabled =
      enableNeedleTips &&
      simulatePressure &&
      !controller._currentStrokeStylusPressureEnabled;
  controller._currentStylusCurve = controller._stylusCurve;
  controller._currentStylusLastPressure = null;
  controller._currentStrokeAntialiasLevel = antialiasLevel.clamp(0, 9);
  controller._currentStrokeHasMoved = false;
  controller._currentBrushShape = brushShape;
  controller._currentStrokeRandomRotationEnabled = randomRotation;
  controller._currentStrokeSmoothRotationEnabled = smoothRotation;
  controller._currentStrokeRotationSeed = randomRotation
      ? (rotationSeed ?? math.Random().nextInt(1 << 31))
      : 0;
  final double resolvedTimestamp = timestampMillis ?? 0.0;
  final double? simulatedInitialRadius = controller._strokePressureSimulator
      .beginStroke(
        position: position,
        timestampMillis: resolvedTimestamp,
        baseRadius: radius,
        simulatePressure: simulatePressure,
        useDevicePressure: controller._currentStrokeStylusPressureEnabled,
        stylusPressureBlend: effectiveStylusBlend,
        needleTipsEnabled: needleTipsEnabled,
      );
  double? stylusSeedRadius;
  if (controller._currentStrokeStylusPressureEnabled) {
    final double? normalized = _strokeNormalizeStylusPressure(
      controller,
      pressure,
      pressureMin,
      pressureMax,
    );
    if (normalized != null) {
      controller._currentStylusLastPressure = normalized;
      stylusSeedRadius = controller._strokePressureSimulator.seedPressureSample(
        normalized,
      );
    }
  }
  
  // Determine starting radius based on simulation or stylus input
  final double startRadius;
  if (controller._strokePressureSimulator.isSimulatingStroke) {
    startRadius = stylusSeedRadius ??
        simulatedInitialRadius ??
        controller._currentStrokeRadius;
    controller._currentStrokeLastRadius = startRadius;
  } else {
    startRadius = controller._currentStrokeRadius;
    controller._currentStrokeLastRadius = controller._currentStrokeRadius;
  }
  controller._currentStrokeRadii.add(startRadius);
  
  final double flowValue = flow.isFinite ? flow.clamp(0.0, 1.0) : 1.0;
  final int flowAlpha = (color.alpha * flowValue).round().clamp(0, 255);
  controller._currentStrokeColor = color.withAlpha(flowAlpha);
  controller._currentStrokeEraseMode = erase;
  final bool resolvedHollow = hollow && !erase;
  controller._currentStrokeHollowEnabled = resolvedHollow;
  controller._currentStrokeHollowRatio =
      resolvedHollow ? hollowRatio.clamp(0.0, 1.0) : 0.0;
  controller._currentStrokeEraseOccludedParts =
      resolvedHollow && eraseOccludedParts;
  final double spacingValue = spacing.isFinite ? spacing : 0.15;
  controller._currentStrokeSpacing = spacingValue.clamp(0.01, 2.5);
  final double hardnessValue = hardness.isFinite ? hardness : 0.8;
  controller._currentStrokeSoftness = (1.0 - hardnessValue.clamp(0.0, 1.0))
      .clamp(0.0, 1.0);
  final double scatterValue = scatter.isFinite ? scatter : 0.0;
  controller._currentStrokeScatter = scatterValue.clamp(0.0, 1.0);
  final double rotationValue = rotationJitter.isFinite ? rotationJitter : 1.0;
  controller._currentStrokeRotationJitter = rotationValue.clamp(0.0, 1.0);
  controller._currentStrokeSnapToPixel = snapToPixel;
  controller._currentStrokeScreentoneEnabled = screentoneEnabled;
  controller._currentStrokeScreentoneSpacing =
      screentoneSpacing.isFinite ? screentoneSpacing.clamp(2.0, 200.0) : 10.0;
  controller._currentStrokeScreentoneDotSize =
      screentoneDotSize.isFinite ? screentoneDotSize.clamp(0.0, 1.0) : 0.6;
  controller._currentStrokeScreentoneRotation =
      screentoneRotation.isFinite ? screentoneRotation.clamp(-180.0, 180.0) : 45.0;
  controller._currentStrokeScreentoneSoftness =
      screentoneSoftness.isFinite ? screentoneSoftness.clamp(0.0, 1.0) : 0.0;
  controller._currentStrokeScreentoneShape = screentoneShape;
  final double streamlineValue =
      streamlineStrength.isFinite ? streamlineStrength.clamp(0.0, 1.0) : 0.0;
  controller._currentStrokeStreamlineStrength = streamlineValue;
  controller._currentStrokeDeferRaster =
      streamlineValue > 0.0001 && RustCpuBrushFfi.instance.supportsStreamline;
}

void _strokeExtend(
  BitmapCanvasController controller,
  Offset position, {
  double? deltaTimeMillis,
  double? timestampMillis,
  double? pressure,
  double? pressureMin,
  double? pressureMax,
}) {
  if (controller._currentStrokePoints.isEmpty) {
    return;
  }
  if (controller._activeLayer.locked) {
    return;
  }
  final Offset last = controller._currentStrokePoints.last;
  final bool firstSegment = !controller._currentStrokeHasMoved;
  controller._currentStrokePoints.add(position);
  double? stylusPressure;
  if (controller._currentStrokeStylusPressureEnabled) {
    final double? normalized = _strokeNormalizeStylusPressure(
      controller,
      pressure,
      pressureMin,
      pressureMax,
    );
    if (normalized != null) {
      stylusPressure = normalized;
      controller._currentStylusLastPressure = normalized;
    } else {
      stylusPressure = controller._currentStylusLastPressure;
    }
  }
  if (controller._strokePressureSimulator.isSimulatingStroke) {
    final double? nextRadius = controller._strokePressureSimulator
        .sampleNextRadius(
          lastPosition: last,
          position: position,
          timestampMillis: timestampMillis,
          deltaTimeMillis: deltaTimeMillis,
          normalizedPressure: stylusPressure,
        );
    if (nextRadius == null) {
      return;
    }
    final double resolvedRadius = _strokeResolveSimulatedRadius(
      controller,
      nextRadius,
      preferImmediate: controller._strokePressureSimulator.usesDevicePressure,
    );
    controller._currentStrokeRadii.add(resolvedRadius);
    
    // Anti-swallow logic for Sharp Start:
    if (controller._currentStrokePoints.length == 2) {
      final Offset p0 = controller._currentStrokePoints[0];
      final Offset p1 = controller._currentStrokePoints[1];
      final double r0 = controller._currentStrokeRadii[0];
      final double r1 = controller._currentStrokeRadii[1];
      
      final double dist = (p1 - p0).distance;
      if (dist + r0 < r1) {
        final Offset direction = dist > 0.001 ? (p0 - p1) / dist : const Offset(-1, -1);
        final double mag = direction.distance;
        final Offset normDir = mag > 0 ? direction / mag : direction;
        final double targetDist = r1 - r0 + 1.0;
        final Offset newP0 = p1 + normDir * targetDist;
        controller._currentStrokePoints[0] = newP0;
      }
    }

    final double previousRadius =
        controller._currentStrokeLastRadius.isFinite &&
            controller._currentStrokeLastRadius > 0.0
        ? controller._currentStrokeLastRadius
        : controller._currentStrokeRadius;
    
    final bool directionChanged = _strokeDirectionChanged(
      controller,
      last,
      position,
    );
    final bool restartCaps = firstSegment ||
        _strokeNeedsRestartCaps(previousRadius, resolvedRadius) ||
        directionChanged;
    final double startRadius = restartCaps ? resolvedRadius : previousRadius;
    
    _strokeStampSegment(
      controller,
      last,
      position,
      startRadius: startRadius,
      endRadius: resolvedRadius,
      includeStart: restartCaps,
    );
    controller._currentStrokeHasMoved = true;
    controller._currentStrokeLastRadius = resolvedRadius;
    _strokeUpdateStreamlinePreview(controller);
    return;
  }

  controller._currentStrokeRadii.add(controller._currentStrokeRadius);
  _strokeStampSegment(
    controller,
    last,
    position,
    startRadius: controller._currentStrokeRadius,
    endRadius: controller._currentStrokeRadius,
    includeStart: firstSegment,
  );
  controller._currentStrokeHasMoved = true;
  _strokeUpdateStreamlinePreview(controller);
}

void _strokeEnd(BitmapCanvasController controller) {
  if (controller._currentStrokePoints.isEmpty) {
    return;
  }
  final bool hasPath =
      controller._currentStrokeHasMoved &&
      controller._currentStrokePoints.length >= 2;
  final Offset tip = controller._currentStrokePoints.last;

  if (controller._strokePressureSimulator.isSimulatingStroke) {
    final Offset? previousPoint =
        hasPath && controller._currentStrokePoints.length >= 2
        ? controller
              ._currentStrokePoints[controller._currentStrokePoints.length - 2]
        : null;
    final SimulatedTailInstruction? tailInstruction = controller
        ._strokePressureSimulator
        .buildTail(
          hasPath: hasPath,
          tip: tip,
          previousPoint: previousPoint,
          baseRadius: controller._currentStrokeRadius,
          lastRadius: controller._currentStrokeLastRadius,
        );
    if (tailInstruction != null) {
      if (tailInstruction.isLine) {
        Offset end = tailInstruction.end!;
        final double endRadius = tailInstruction.endRadius!;
        
        // Anti-swallow logic for Sharp Tail:
        final Offset lastPoint = controller._currentStrokePoints.last;
        final double lastRadius = controller._currentStrokeRadii.last;
        final double dist = (end - lastPoint).distance;
        
        if (dist + endRadius < lastRadius) {
           final Offset rawDir = (end - lastPoint);
           final double rawDist = rawDir.distance;
           final Offset direction = rawDist > 0.001 ? rawDir / rawDist : (end - tip);
           final double dirMag = direction.distance;
           final Offset normDir = dirMag > 0.0001 ? direction / dirMag : direction;
           
           if (normDir.distanceSquared > 0.0001) {
              final double targetDist = lastRadius - endRadius + 1.5;
              end = lastPoint + normDir * targetDist;
           }
        }
        
        // Append tail segment to vector stroke data
        controller._currentStrokePoints.add(end);
        controller._currentStrokeRadii.add(endRadius);
        controller._deferredStrokeCommands.add(
          PaintingDrawCommand.stampSegment(
            start: lastPoint,
            end: end,
            startRadius: lastRadius,
            endRadius: endRadius,
            colorValue: controller._currentStrokeColor.value,
            shapeIndex: controller._currentBrushShape.index,
            randomRotation: controller._currentStrokeRandomRotationEnabled,
            smoothRotation: controller._currentStrokeSmoothRotationEnabled,
            rotationSeed: controller._currentStrokeRotationSeed,
            rotationJitter: controller._currentStrokeRotationJitter,
            spacing: _strokeAdaptiveSpacingForSegment(
              controller._currentStrokeSpacing,
              lastPoint,
              end,
              lastRadius,
              endRadius,
            ),
            scatter: controller._currentStrokeScatter,
            softness: controller._currentStrokeSoftness,
            snapToPixel: controller._currentStrokeSnapToPixel,
            antialiasLevel: controller._currentStrokeAntialiasLevel,
            includeStart: false,
            erase: controller._currentStrokeEraseMode,
            screentoneEnabled: controller._currentStrokeScreentoneEnabled,
            screentoneSpacing: controller._currentStrokeScreentoneSpacing,
            screentoneDotSize: controller._currentStrokeScreentoneDotSize,
            screentoneRotation: controller._currentStrokeScreentoneRotation,
            screentoneSoftness: controller._currentStrokeScreentoneSoftness,
            screentoneShapeIndex: controller._currentStrokeScreentoneShape.index,
          ),
        );
      } else if (tailInstruction.isPoint) {
        // Append tail point to vector stroke data
        final Offset tailPoint = tailInstruction.point!;
        final double tailRadius = tailInstruction.pointRadius!;
        controller._currentStrokePoints.add(tailPoint);
        controller._currentStrokeRadii.add(tailRadius);
        controller._deferredStrokeCommands.add(
          PaintingDrawCommand.brushStamp(
            center: tailPoint,
            radius: tailRadius,
            colorValue: controller._currentStrokeColor.value,
            shapeIndex: controller._currentBrushShape.index,
            randomRotation: controller._currentStrokeRandomRotationEnabled,
            smoothRotation: controller._currentStrokeSmoothRotationEnabled,
            rotationSeed: controller._currentStrokeRotationSeed,
            rotationJitter: controller._currentStrokeRotationJitter,
            snapToPixel: controller._currentStrokeSnapToPixel,
            antialiasLevel: controller._currentStrokeAntialiasLevel,
            softness: controller._currentStrokeSoftness,
            erase: controller._currentStrokeEraseMode,
            screentoneEnabled: controller._currentStrokeScreentoneEnabled,
            screentoneSpacing: controller._currentStrokeScreentoneSpacing,
            screentoneDotSize: controller._currentStrokeScreentoneDotSize,
            screentoneRotation: controller._currentStrokeScreentoneRotation,
            screentoneSoftness: controller._currentStrokeScreentoneSoftness,
            screentoneShapeIndex: controller._currentStrokeScreentoneShape.index,
          ),
        );
      }
    }
  }

  if (!controller._currentStrokeStylusPressureEnabled &&
      !controller._strokePressureSimulator.isSimulatingStroke) {
    if (!hasPath) {
      _strokeDrawPoint(controller, tip, controller._currentStrokeRadius);
    }
  }

  _strokeApplyStreamline(controller);
  controller._flushDeferredStrokeCommands();
  controller._currentStrokePreviewPoints.clear();
  controller._currentStrokePreviewRadii.clear();

  if (controller.isMultithreaded) {
    controller._flushPendingPaintingCommands();
  }
  controller._currentStrokeRadius = 0;
  controller._currentStrokeLastRadius = 0;
  controller._currentStrokeStylusPressureEnabled = false;
  controller._currentStylusLastPressure = null;
  controller._currentStrokeAntialiasLevel = 0;
  controller._currentStrokeHasMoved = false;
  controller._strokePressureSimulator.resetTracking();
  controller._currentStrokeEraseMode = false;
  controller._currentStrokeHollowEnabled = false;
  controller._currentStrokeHollowRatio = 0.0;
  controller._currentStrokeEraseOccludedParts = false;
  controller._currentStrokeRandomRotationEnabled = false;
  controller._currentStrokeSmoothRotationEnabled = false;
  controller._currentStrokeRotationSeed = 0;
  controller._currentStrokeScreentoneEnabled = false;
  controller._currentStrokeScreentoneSpacing = 10.0;
  controller._currentStrokeScreentoneDotSize = 0.6;
  controller._currentStrokeScreentoneRotation = 45.0;
  controller._currentStrokeScreentoneSoftness = 0.0;
  controller._currentStrokeScreentoneShape = BrushShape.circle;
  controller._currentStrokeSpacing = 0.15;
  controller._currentStrokeSoftness = 0.0;
  controller._currentStrokeScatter = 0.0;
  controller._currentStrokeRotationJitter = 1.0;
  controller._currentStrokeSnapToPixel = false;
  controller._currentStrokeStreamlineStrength = 0.0;
  controller._currentStrokeDeferRaster = false;
}

void _strokeCancel(BitmapCanvasController controller) {
  controller._currentStrokePoints.clear();
  controller._currentStrokeRadii.clear();
  controller._currentStrokePreviewPoints.clear();
  controller._currentStrokePreviewRadii.clear();
  controller._deferredStrokeCommands.clear();
  controller._currentStrokeRadius = 0;
  controller._currentStrokeLastRadius = 0;
  controller._currentStrokeStylusPressureEnabled = false;
  controller._currentStylusLastPressure = null;
  controller._currentStrokeAntialiasLevel = 0;
  controller._currentStrokeHasMoved = false;
  controller._strokePressureSimulator.resetTracking();
  controller._currentStrokeEraseMode = false;
  controller._currentStrokeHollowEnabled = false;
  controller._currentStrokeHollowRatio = 0.0;
  controller._currentStrokeEraseOccludedParts = false;
  controller._currentStrokeRandomRotationEnabled = false;
  controller._currentStrokeSmoothRotationEnabled = false;
  controller._currentStrokeRotationSeed = 0;
  controller._currentStrokeScreentoneEnabled = false;
  controller._currentStrokeScreentoneSpacing = 10.0;
  controller._currentStrokeScreentoneDotSize = 0.6;
  controller._currentStrokeScreentoneRotation = 45.0;
  controller._currentStrokeScreentoneSoftness = 0.0;
  controller._currentStrokeScreentoneShape = BrushShape.circle;
  controller._currentStrokeSpacing = 0.15;
  controller._currentStrokeSoftness = 0.0;
  controller._currentStrokeScatter = 0.0;
  controller._currentStrokeRotationJitter = 1.0;
  controller._currentStrokeSnapToPixel = false;
  controller._currentStrokeStreamlineStrength = 0.0;
  controller._currentStrokeDeferRaster = false;
}

void _strokeUpdateStreamlinePreview(BitmapCanvasController controller) {
  if (!controller._currentStrokeDeferRaster) {
    controller._currentStrokePreviewPoints.clear();
    controller._currentStrokePreviewRadii.clear();
    return;
  }
  final double strength = controller._currentStrokeStreamlineStrength;
  if (strength <= 0.0001 ||
      !strength.isFinite ||
      !RustCpuBrushFfi.instance.supportsStreamline) {
    controller._currentStrokePreviewPoints.clear();
    controller._currentStrokePreviewRadii.clear();
    return;
  }
  final int count = controller._currentStrokePoints.length;
  if (count < 2 || controller._currentStrokeRadii.length != count) {
    controller._currentStrokePreviewPoints.clear();
    controller._currentStrokePreviewRadii.clear();
    return;
  }

  final Float32List samples = Float32List(count * 3);
  for (int i = 0; i < count; i++) {
    final Offset p = controller._currentStrokePoints[i];
    samples[i * 3] = p.dx;
    samples[i * 3 + 1] = p.dy;
    samples[i * 3 + 2] = controller._currentStrokeRadii[i];
  }

  final bool ok = RustCpuBrushFfi.instance.applyStreamline(
    samples: samples,
    strength: strength,
  );
  if (!ok) {
    controller._currentStrokePreviewPoints.clear();
    controller._currentStrokePreviewRadii.clear();
    return;
  }

  controller._currentStrokePreviewPoints
    ..clear()
    ..addAll(
      List<Offset>.generate(
        count,
        (i) => Offset(samples[i * 3], samples[i * 3 + 1]),
      ),
    );
  controller._currentStrokePreviewRadii
    ..clear()
    ..addAll(
      List<double>.generate(count, (i) => samples[i * 3 + 2]),
    );
}

bool _strokeApplyStreamline(BitmapCanvasController controller) {
  if (!controller._currentStrokeDeferRaster) {
    return false;
  }
  final double strength = controller._currentStrokeStreamlineStrength;
  if (strength <= 0.0001 || !strength.isFinite) {
    return false;
  }
  if (!RustCpuBrushFfi.instance.supportsStreamline) {
    return false;
  }
  final int count = controller._currentStrokePoints.length;
  if (count < 2 || controller._currentStrokeRadii.length != count) {
    return false;
  }

  final Float32List samples = Float32List(count * 3);
  for (int i = 0; i < count; i++) {
    final Offset p = controller._currentStrokePoints[i];
    samples[i * 3] = p.dx;
    samples[i * 3 + 1] = p.dy;
    samples[i * 3 + 2] = controller._currentStrokeRadii[i];
  }

  final bool ok =
      RustCpuBrushFfi.instance.applyStreamline(samples: samples, strength: strength);
  if (!ok) {
    return false;
  }

  controller._currentStrokePoints
    ..clear()
    ..addAll(
      List<Offset>.generate(
        count,
        (i) => Offset(samples[i * 3], samples[i * 3 + 1]),
      ),
    );
  controller._currentStrokeRadii
    ..clear()
    ..addAll(
      List<double>.generate(count, (i) => samples[i * 3 + 2]),
    );

  controller._deferredStrokeCommands.clear();
  if (count == 1) {
    controller._deferredStrokeCommands.add(
      PaintingDrawCommand.brushStamp(
        center: controller._currentStrokePoints.first,
        radius: controller._currentStrokeRadii.first,
        colorValue: controller._currentStrokeColor.value,
        shapeIndex: controller._currentBrushShape.index,
        randomRotation: controller._currentStrokeRandomRotationEnabled,
        smoothRotation: controller._currentStrokeSmoothRotationEnabled,
        rotationSeed: controller._currentStrokeRotationSeed,
        rotationJitter: controller._currentStrokeRotationJitter,
        snapToPixel: controller._currentStrokeSnapToPixel,
        antialiasLevel: controller._currentStrokeAntialiasLevel,
        softness: controller._currentStrokeSoftness,
        erase: controller._currentStrokeEraseMode,
        screentoneEnabled: controller._currentStrokeScreentoneEnabled,
        screentoneSpacing: controller._currentStrokeScreentoneSpacing,
        screentoneDotSize: controller._currentStrokeScreentoneDotSize,
        screentoneRotation: controller._currentStrokeScreentoneRotation,
        screentoneSoftness: controller._currentStrokeScreentoneSoftness,
        screentoneShapeIndex: controller._currentStrokeScreentoneShape.index,
      ),
    );
    return true;
  }

  for (int i = 1; i < count; i++) {
    final Offset segmentStart = controller._currentStrokePoints[i - 1];
    final Offset segmentEnd = controller._currentStrokePoints[i];
    final double segmentStartRadius = controller._currentStrokeRadii[i - 1];
    final double segmentEndRadius = controller._currentStrokeRadii[i];
    controller._deferredStrokeCommands.add(
      PaintingDrawCommand.stampSegment(
        start: segmentStart,
        end: segmentEnd,
        startRadius: segmentStartRadius,
        endRadius: segmentEndRadius,
        colorValue: controller._currentStrokeColor.value,
        shapeIndex: controller._currentBrushShape.index,
        randomRotation: controller._currentStrokeRandomRotationEnabled,
        smoothRotation: controller._currentStrokeSmoothRotationEnabled,
        rotationSeed: controller._currentStrokeRotationSeed,
        rotationJitter: controller._currentStrokeRotationJitter,
        spacing: _strokeAdaptiveSpacingForSegment(
          controller._currentStrokeSpacing,
          segmentStart,
          segmentEnd,
          segmentStartRadius,
          segmentEndRadius,
        ),
        scatter: controller._currentStrokeScatter,
        softness: controller._currentStrokeSoftness,
        snapToPixel: controller._currentStrokeSnapToPixel,
        antialiasLevel: controller._currentStrokeAntialiasLevel,
        includeStart: i == 1,
        erase: controller._currentStrokeEraseMode,
        screentoneEnabled: controller._currentStrokeScreentoneEnabled,
        screentoneSpacing: controller._currentStrokeScreentoneSpacing,
        screentoneDotSize: controller._currentStrokeScreentoneDotSize,
        screentoneRotation: controller._currentStrokeScreentoneRotation,
        screentoneSoftness: controller._currentStrokeScreentoneSoftness,
        screentoneShapeIndex: controller._currentStrokeScreentoneShape.index,
      ),
    );
  }
  return true;
}

void _strokeSetPressureProfile(
  BitmapCanvasController controller,
  StrokePressureProfile profile,
) {
  controller._strokePressureSimulator.setProfile(profile);
}

double? _strokeNormalizeStylusPressure(
  BitmapCanvasController controller,
  double? pressure,
  double? pressureMin,
  double? pressureMax,
) {
  if (pressure == null || !pressure.isFinite) {
    return null;
  }
  double lower = pressureMin ?? 0.0;
  double upper = pressureMax ?? 1.0;
  if (!lower.isFinite) {
    lower = 0.0;
  }
  if (!upper.isFinite || upper <= lower) {
    upper = lower + 1.0;
  }
  final double normalized = (pressure - lower) / (upper - lower);
  if (!normalized.isFinite) {
    return null;
  }
  final double curved = math
      .pow(normalized.clamp(0.0, 1.0), controller._currentStylusCurve)
      .toDouble();
  return curved.clamp(0.0, 1.0);
}

bool _strokeNeedsRestartCaps(double previousRadius, double nextRadius) {
  if (!previousRadius.isFinite || !nextRadius.isFinite) {
    return false;
  }
  if (nextRadius <= previousRadius) {
    return false;
  }
  const double kMinimalCoverage = 0.18;
  const double kGrowthRatioThreshold = 1.5;
  if (previousRadius <= kMinimalCoverage) {
    return (nextRadius - previousRadius) > 0.04;
  }
  return nextRadius >= previousRadius * kGrowthRatioThreshold;
}

double _strokeResolveSimulatedRadius(
  BitmapCanvasController controller,
  double candidate, {
  bool preferImmediate = false,
}) {
  final bool stylusActive = controller._currentStrokeStylusPressureEnabled;
  final double baseRadius = controller._currentStrokeRadius.isFinite
      ? controller._currentStrokeRadius.abs()
      : 0.0;
  final double minFactor = stylusActive ? 0.01 : 0.12;
  final double minClamp = stylusActive
      ? _kStylusAbsoluteMinRadius
      : _kSimulatedAbsoluteMinRadius;
  final double minimum = math.max(baseRadius * minFactor, minClamp);
  final double maxFactor = stylusActive ? 5.0 : 4.5;
  final double maximum = math.min(
    math.max(baseRadius * maxFactor, minimum + 0.005),
    _kAbsoluteMaxStrokeRadius,
  );
  double sanitized = candidate.isFinite ? candidate.abs() : baseRadius;
  sanitized = sanitized.clamp(minimum, maximum);
  final double previous = controller._currentStrokeLastRadius;
  if (previous.isFinite && previous > 0.0) {
    final double smoothing = preferImmediate
        ? 1.0
        : BitmapCanvasController._kStylusSmoothing;
    final double smoothed = previous + (sanitized - previous) * smoothing;
    return smoothed.clamp(minimum, maximum);
  }
  return sanitized;
}

bool _strokeSegmentShouldSnapToPoint(double length, double radius) {
  if (!length.isFinite || !radius.isFinite) {
    return false;
  }
  if (length <= 1e-4) {
    return true;
  }
  const double kShortSegmentRatio = 0.35;
  return length <= radius * kShortSegmentRatio;
}

void _strokeDrawPoint(
  BitmapCanvasController controller,
  Offset position,
  double radius, {
  bool markDirty = true,
}) {
  if (controller._activeLayer.locked) {
    return;
  }
  final double resolvedRadius = math.max(radius.abs(), 0.01);
  final BrushShape brushShape = controller._currentBrushShape;
  final bool erase = controller._currentStrokeEraseMode;
  final double scatterRadius =
      resolvedRadius * 2.0 * controller._currentStrokeScatter;
  final Offset jitter = scatterRadius > 0
      ? brushScatterOffset(
          center: position,
          seed: controller._currentStrokeRotationSeed,
          radius: scatterRadius,
          salt: controller._currentStrokePoints.length,
        )
      : Offset.zero;

  controller._deferredStrokeCommands.add(
    PaintingDrawCommand.brushStamp(
      center: position + jitter,
      radius: resolvedRadius,
      colorValue: controller._currentStrokeColor.value,
      shapeIndex: brushShape.index,
      randomRotation: controller._currentStrokeRandomRotationEnabled,
      smoothRotation: controller._currentStrokeSmoothRotationEnabled,
      rotationSeed: controller._currentStrokeRotationSeed,
      rotationJitter: controller._currentStrokeRotationJitter,
      snapToPixel: controller._currentStrokeSnapToPixel,
      antialiasLevel: controller._currentStrokeAntialiasLevel,
      softness: controller._currentStrokeSoftness,
      erase: erase,
      screentoneEnabled: controller._currentStrokeScreentoneEnabled,
      screentoneSpacing: controller._currentStrokeScreentoneSpacing,
      screentoneDotSize: controller._currentStrokeScreentoneDotSize,
      screentoneRotation: controller._currentStrokeScreentoneRotation,
      screentoneSoftness: controller._currentStrokeScreentoneSoftness,
      screentoneShapeIndex: controller._currentStrokeScreentoneShape.index,
    ),
  );
  controller._flushRealtimeStrokeCommands();
}

void _strokeStampSegment(
  BitmapCanvasController controller,
  Offset start,
  Offset end, {
  required double startRadius,
  required double endRadius,
  required bool includeStart,
}) {
  final double spacing = _strokeAdaptiveSpacingForSegment(
    controller._currentStrokeSpacing,
    start,
    end,
    startRadius,
    endRadius,
  );
  controller._deferredStrokeCommands.add(
    PaintingDrawCommand.stampSegment(
      start: start,
      end: end,
      startRadius: startRadius,
      endRadius: endRadius,
      colorValue: controller._currentStrokeColor.value,
      shapeIndex: controller._currentBrushShape.index,
      randomRotation: controller._currentStrokeRandomRotationEnabled,
      smoothRotation: controller._currentStrokeSmoothRotationEnabled,
      rotationSeed: controller._currentStrokeRotationSeed,
      rotationJitter: controller._currentStrokeRotationJitter,
      spacing: spacing,
      scatter: controller._currentStrokeScatter,
      softness: controller._currentStrokeSoftness,
      snapToPixel: controller._currentStrokeSnapToPixel,
      antialiasLevel: controller._currentStrokeAntialiasLevel,
      includeStart: includeStart,
      erase: controller._currentStrokeEraseMode,
      screentoneEnabled: controller._currentStrokeScreentoneEnabled,
      screentoneSpacing: controller._currentStrokeScreentoneSpacing,
      screentoneDotSize: controller._currentStrokeScreentoneDotSize,
      screentoneRotation: controller._currentStrokeScreentoneRotation,
      screentoneSoftness: controller._currentStrokeScreentoneSoftness,
      screentoneShapeIndex: controller._currentStrokeScreentoneShape.index,
    ),
  );
  controller._flushRealtimeStrokeCommands();
}

bool _strokeDirectionChanged(
  BitmapCanvasController controller,
  Offset last,
  Offset current,
) {
  if (controller._currentStrokePoints.length < 3) {
    return false;
  }
  // _currentStrokePoints contains [..., prev, last, current] (current was just added)
  // Wait, _strokeExtend adds 'position' (current) to _currentStrokePoints BEFORE calling this check?
  // Yes, "controller._currentStrokePoints.add(position);" happens at the top of _strokeExtend.
  // So points: ..., previous, last, current.
  // The function args passed are 'last' (the point before current) and 'position' (current).
  // We need the point before 'last'.
  
  final int count = controller._currentStrokePoints.length;
  // [..., p2, p1, p0]
  // current = p0
  // last = p1
  // previous = p2
  // We need index count - 3.
  
  final Offset previous = controller._currentStrokePoints[count - 3];
  final Offset v1 = last - previous;
  final Offset v2 = current - last;
  
  if (v1.distanceSquared < 0.0001 || v2.distanceSquared < 0.0001) {
    return false;
  }
  
  final double dot = v1.dx * v2.dx + v1.dy * v2.dy;
  final double mag = math.sqrt(v1.distanceSquared * v2.distanceSquared);
  // cos(theta) = dot / mag
  // If theta > 20 degrees (0.35 rad), cos(theta) < cos(0.35) ~= 0.94
  return (dot / mag) < 0.94;
}
