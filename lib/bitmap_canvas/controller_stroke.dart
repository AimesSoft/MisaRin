part of 'controller.dart';

const double _kStylusAbsoluteMinRadius = 0.005;
const double _kSimulatedAbsoluteMinRadius = 0.01;
const double _kAbsoluteMaxStrokeRadius = 512.0;

double _strokeStampSpacing(double radius) {
  if (!radius.isFinite) {
    return 0.5;
  }
  return math.max(0.2, radius * 0.3);
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
  required double curve,
}) {
  controller._stylusPressureEnabled = enabled;
  controller._stylusCurve = curve.clamp(0.1, 8.0);
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
  bool erase = false,
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
  controller._currentStrokeAntialiasLevel = antialiasLevel.clamp(0, 3);
  controller._currentStrokeHasMoved = false;
  controller._currentBrushShape = brushShape;
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
    startRadius =
        stylusSeedRadius ??
        simulatedInitialRadius ??
        controller._currentStrokeRadius;
    controller._currentStrokeLastRadius = startRadius;
  } else {
    startRadius = controller._currentStrokeRadius;
    controller._currentStrokeLastRadius = controller._currentStrokeRadius;
  }
  controller._currentStrokeRadii.add(startRadius);

  controller._currentStrokeColor = color;
  controller._currentStrokeEraseMode = erase;
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
  final bool useCircularBrush =
      controller._currentBrushShape == BrushShape.circle;
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
        final Offset direction = dist > 0.001
            ? (p0 - p1) / dist
            : const Offset(-1, -1);
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
    final bool restartCaps =
        firstSegment ||
        _strokeNeedsRestartCaps(previousRadius, resolvedRadius) ||
        directionChanged;
    final double startRadius = restartCaps ? resolvedRadius : previousRadius;

    if (useCircularBrush) {
      controller._deferredStrokeCommands.add(
        PaintingDrawCommand.variableLine(
          start: last,
          end: position,
          startRadius: startRadius,
          endRadius: resolvedRadius,
          colorValue: controller._currentStrokeColor.value,
          antialiasLevel: controller._currentStrokeAntialiasLevel,
          includeStartCap: restartCaps,
          erase: controller._currentStrokeEraseMode,
        ),
      );
      controller._flushRealtimeStrokeCommands();
    } else {
      _strokeStampSegment(
        controller,
        last,
        position,
        startRadius: startRadius,
        endRadius: resolvedRadius,
        includeStart: restartCaps,
      );
    }
    controller._currentStrokeHasMoved = true;
    controller._currentStrokeLastRadius = resolvedRadius;
    return;
  }

  controller._currentStrokeRadii.add(controller._currentStrokeRadius);
  if (useCircularBrush) {
    controller._deferredStrokeCommands.add(
      PaintingDrawCommand.line(
        start: last,
        end: position,
        radius: controller._currentStrokeRadius,
        colorValue: controller._currentStrokeColor.value,
        antialiasLevel: controller._currentStrokeAntialiasLevel,
        includeStartCap: firstSegment,
        erase: controller._currentStrokeEraseMode,
      ),
    );
    controller._flushRealtimeStrokeCommands();
  } else {
    _strokeStampSegment(
      controller,
      last,
      position,
      startRadius: controller._currentStrokeRadius,
      endRadius: controller._currentStrokeRadius,
      includeStart: firstSegment,
    );
  }
  controller._currentStrokeHasMoved = true;
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
          final Offset direction = rawDist > 0.001
              ? rawDir / rawDist
              : (end - tip);
          final double dirMag = direction.distance;
          final Offset normDir = dirMag > 0.0001
              ? direction / dirMag
              : direction;

          if (normDir.distanceSquared > 0.0001) {
            final double targetDist = lastRadius - endRadius + 1.5;
            end = lastPoint + normDir * targetDist;
          }
        }

        // Append tail segment to vector stroke data
        controller._currentStrokePoints.add(end);
        controller._currentStrokeRadii.add(endRadius);
      } else if (tailInstruction.isPoint) {
        // Append tail point to vector stroke data
        controller._currentStrokePoints.add(tailInstruction.point!);
        controller._currentStrokeRadii.add(tailInstruction.pointRadius!);
      }
    }
  }

  if (!controller._currentStrokeStylusPressureEnabled &&
      !controller._strokePressureSimulator.isSimulatingStroke) {
    if (!hasPath) {
      _strokeDrawPoint(controller, tip, controller._currentStrokeRadius);
    }
  }

  controller._flushDeferredStrokeCommands();

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
  double radius,
) {
  if (controller._activeLayer.locked) {
    return;
  }
  final double resolvedRadius = math.max(radius.abs(), 0.01);
  final BrushShape brushShape = controller._currentBrushShape;
  final bool erase = controller._currentStrokeEraseMode;

  controller._deferredStrokeCommands.add(
    PaintingDrawCommand.brushStamp(
      center: position,
      radius: resolvedRadius,
      colorValue: controller._currentStrokeColor.value,
      shapeIndex: brushShape.index,
      antialiasLevel: controller._currentStrokeAntialiasLevel,
      erase: erase,
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
  controller._deferredStrokeCommands.add(
    PaintingDrawCommand.stampSegment(
      start: start,
      end: end,
      startRadius: startRadius,
      endRadius: endRadius,
      colorValue: controller._currentStrokeColor.value,
      shapeIndex: controller._currentBrushShape.index,
      antialiasLevel: controller._currentStrokeAntialiasLevel,
      includeStart: includeStart,
      erase: controller._currentStrokeEraseMode,
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
