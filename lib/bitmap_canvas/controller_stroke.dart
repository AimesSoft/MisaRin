part of 'controller.dart';

void _strokeConfigureStylusPressure(
  BitmapCanvasController controller, {
  required bool enabled,
  required double minFactor,
  required double maxFactor,
  required double curve,
}) {
  controller._stylusPressureEnabled = enabled;
  final double clampedMin = minFactor.clamp(0.0, maxFactor);
  final double clampedMax = math.max(maxFactor, clampedMin + 0.01);
  final double clampedCurve = curve.clamp(0.1, 8.0);
  controller._stylusMinFactor = clampedMin;
  controller._stylusMaxFactor = clampedMax;
  controller._stylusCurve = clampedCurve;
}

void _strokeBegin(
  BitmapCanvasController controller,
  Offset position, {
  required Color color,
  required double radius,
  bool simulatePressure = false,
  bool useDevicePressure = false,
  double? pressure,
  double? pressureMin,
  double? pressureMax,
  StrokePressureProfile profile = StrokePressureProfile.auto,
  double? timestampMillis,
  int antialiasLevel = 0,
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
  controller._currentStrokeRadius = radius;
  final bool useSlimeEngine = !useDevicePressure;
  controller._currentStrokeUsesSlimeEngine = useSlimeEngine;
  controller._currentStrokeStylusPressureEnabled =
      useDevicePressure && controller._stylusPressureEnabled && !simulatePressure;
  controller._currentStylusMinFactor = controller._stylusMinFactor;
  controller._currentStylusMaxFactor =
      math.max(controller._stylusMaxFactor, controller._stylusMinFactor);
  controller._currentStylusCurve = controller._stylusCurve;
  controller._currentStylusSmoothedPressure = null;
  controller._currentStrokeAntialiasLevel = antialiasLevel.clamp(0, 3);
  controller._currentStrokeHasMoved = false;
  final double resolvedTimestamp = timestampMillis ?? 0.0;
  controller._currentStrokeLastTimestamp = resolvedTimestamp;
  if (useSlimeEngine) {
    controller._slimeStrokeEngine.startStroke(
      position: position,
      baseRadius: radius,
      timestampMillis: resolvedTimestamp,
      dynamicRadius: simulatePressure,
    );
    controller._currentStrokeLastRadius =
        controller._slimeStrokeEngine.surfaceRadius;
  } else if (controller._currentStrokeStylusPressureEnabled) {
    final double? normalized = _strokeNormalizeStylusPressure(
      controller,
      pressure,
      pressureMin,
      pressureMax,
    );
    if (normalized != null) {
      controller._currentStylusSmoothedPressure = normalized.clamp(0.0, 1.0);
      controller._currentStrokeLastRadius = _strokeRadiusFromNormalized(
        controller,
        controller._currentStylusSmoothedPressure!,
      );
    } else {
      controller._currentStrokeLastRadius = controller._currentStrokeRadius;
    }
  } else {
    controller._currentStrokeLastRadius = controller._currentStrokeRadius;
  }
  controller._currentStrokeColor = color;
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
  if (controller._currentStrokeUsesSlimeEngine) {
    final double sampleTimestamp = _strokeResolveSampleTimestamp(
      controller,
      timestampMillis,
      deltaTimeMillis,
    );
    final SlimeStrokeSample? sample = controller._slimeStrokeEngine.extend(
      position: position,
      timestampMillis: sampleTimestamp,
    );
    if (sample == null) {
      return;
    }
    if (sample.isBlob) {
      _strokeDrawPoint(controller, sample.blobCenter!, sample.blobRadius!);
      return;
    }
    controller._activeSurface.drawVariableLine(
      a: last,
      b: position,
      startRadius: sample.startRadius!,
      endRadius: sample.endRadius!,
      color: controller._currentStrokeColor,
      mask: controller._selectionMask,
      antialiasLevel: controller._currentStrokeAntialiasLevel,
      includeStartCap: sample.includeStartCap || firstSegment,
    );
    controller._markDirty(
      region: _strokeDirtyRectForVariableLine(
        last,
        position,
        sample.startRadius!,
        sample.endRadius!,
      ),
    );
    controller._currentStrokeHasMoved = true;
    controller._currentStrokeLastRadius = sample.endRadius!;
    return;
  }
  if (controller._currentStrokeStylusPressureEnabled) {
    _strokeResolveSampleTimestamp(
      controller,
      timestampMillis,
      deltaTimeMillis,
    );

    final double? normalized = _strokeNormalizeStylusPressure(
      controller,
      pressure,
      pressureMin,
      pressureMax,
    );
    double nextRadius = controller._currentStrokeRadius;
    if (normalized != null) {
      final double candidate = normalized.clamp(0.0, 1.0);
      final double smoothed = controller._currentStylusSmoothedPressure == null
          ? candidate
          : controller._currentStylusSmoothedPressure! +
              (candidate - controller._currentStylusSmoothedPressure!) *
                  BitmapCanvasController._kStylusSmoothing;
      controller._currentStylusSmoothedPressure = smoothed;
      nextRadius = _strokeRadiusFromNormalized(controller, smoothed);
    }
    final double previousRadius = controller._currentStrokeLastRadius.isFinite &&
            controller._currentStrokeLastRadius > 0.0
        ? controller._currentStrokeLastRadius
        : controller._currentStrokeRadius;
    final double segmentLength = (position - last).distance;
    final double blendedRadius = _strokeBlendRadiusForSegment(
      previousRadius: previousRadius,
      targetRadius: nextRadius,
      segmentLength: segmentLength,
    );
    final bool restartCaps = firstSegment ||
        _strokeNeedsRestartCaps(
          previousRadius,
          blendedRadius,
        );
    final double startRadius = restartCaps ? blendedRadius : previousRadius;
    final double endRadius = blendedRadius;
    controller._activeSurface.drawVariableLine(
      a: last,
      b: position,
      startRadius: startRadius,
      endRadius: endRadius,
      color: controller._currentStrokeColor,
      mask: controller._selectionMask,
      antialiasLevel: controller._currentStrokeAntialiasLevel,
      includeStartCap: restartCaps,
    );
    controller._markDirty(
      region: _strokeDirtyRectForVariableLine(
        last,
        position,
        startRadius,
        endRadius,
      ),
    );
    controller._currentStrokeHasMoved = true;
    controller._currentStrokeLastRadius = endRadius;
    return;
  }

  controller._activeSurface.drawLine(
    a: last,
    b: position,
    radius: controller._currentStrokeRadius,
    color: controller._currentStrokeColor,
    mask: controller._selectionMask,
    antialiasLevel: controller._currentStrokeAntialiasLevel,
    includeStartCap: firstSegment,
  );
  controller._markDirty(
    region:
        _strokeDirtyRectForLine(last, position, controller._currentStrokeRadius),
  );
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

  final bool slimeStroke = controller._currentStrokeUsesSlimeEngine;

  if (slimeStroke) {
    final SlimeTailResult? tail = controller._slimeStrokeEngine.finishStroke();
    if (tail != null) {
      if (tail.isLine) {
        controller._activeSurface.drawVariableLine(
          a: tail.start!,
          b: tail.end!,
          startRadius: tail.startRadius!,
          endRadius: tail.endRadius!,
          color: controller._currentStrokeColor,
          mask: controller._selectionMask,
          antialiasLevel: controller._currentStrokeAntialiasLevel,
          includeStartCap: false,
        );
        controller._markDirty(
          region: _strokeDirtyRectForVariableLine(
            tail.start!,
            tail.end!,
            tail.startRadius!,
            tail.endRadius!,
          ),
        );
      } else {
        _strokeDrawPoint(controller, tail.center!, tail.pointRadius!);
      }
    } else if (!hasPath) {
      _strokeDrawPoint(
        controller,
        tip,
        controller._slimeStrokeEngine.surfaceRadius > 0
            ? controller._slimeStrokeEngine.surfaceRadius
            : controller._currentStrokeRadius,
      );
    }
    controller._slimeStrokeEngine.reset();
    controller._currentStrokeUsesSlimeEngine = false;
  }

  if (controller._currentStrokeStylusPressureEnabled) {
    final double tipRadius = _strokeRadiusFromNormalized(controller, 0.0);
    if (hasPath) {
      final Offset prev =
          controller._currentStrokePoints[controller._currentStrokePoints.length - 2];
      final Offset direction = tip - prev;
      final double length = direction.distance;
      if (length > 0.001) {
        final Offset unit = direction / length;
        final double base = math.max(controller._currentStrokeRadius, 0.1);
        final double taperLength = math.min(base * 4.0, length * 2.0 + 1.5);
        final Offset extension = tip + unit * taperLength;
        final double startRadius = math.max(
          controller._currentStrokeLastRadius,
          tipRadius,
        );
        controller._activeSurface.drawVariableLine(
          a: tip,
          b: extension,
          startRadius: startRadius,
          endRadius: tipRadius,
          color: controller._currentStrokeColor,
          mask: controller._selectionMask,
          antialiasLevel: controller._currentStrokeAntialiasLevel,
          includeStartCap: true,
        );
        controller._markDirty(
          region: _strokeDirtyRectForVariableLine(
            tip,
            extension,
            startRadius,
            tipRadius,
          ),
        );
      } else {
        _strokeDrawPoint(controller, tip, tipRadius);
      }
    } else {
      _strokeDrawPoint(controller, tip, tipRadius);
    }
  }

  if (!controller._currentStrokeStylusPressureEnabled && !slimeStroke) {
    if (!hasPath) {
      _strokeDrawPoint(controller, tip, controller._currentStrokeRadius);
    }
  }

  controller._currentStrokePoints.clear();
  controller._currentStrokeRadius = 0;
  controller._currentStrokeLastRadius = 0;
  controller._currentStrokeStylusPressureEnabled = false;
  controller._currentStylusSmoothedPressure = null;
  controller._currentStrokeAntialiasLevel = 0;
  controller._currentStrokeHasMoved = false;
  controller._currentStrokeLastTimestamp = 0.0;
}

void _strokeSetPressureProfile(
  BitmapCanvasController controller,
  StrokePressureProfile profile,
) {
  controller._currentStrokeProfile = profile;
  controller._slimeStrokeEngine.setProfile(profile);
}

double _strokeResolveSampleTimestamp(
  BitmapCanvasController controller,
  double? timestampMillis,
  double? deltaTimeMillis,
) {
  final double base = controller._currentStrokeLastTimestamp;
  double resolved;
  if (timestampMillis != null && timestampMillis.isFinite) {
    resolved = timestampMillis;
  } else {
    final double delta = (deltaTimeMillis ?? 0.0).clamp(-5000.0, 5000.0);
    resolved = base + delta;
  }
  controller._currentStrokeLastTimestamp = resolved;
  return resolved;
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
  return normalized.clamp(0.0, 1.0);
}

double _strokeRadiusFromNormalized(
  BitmapCanvasController controller,
  double normalized,
) {
  final double clamped = normalized.clamp(0.0, 1.0);
  final double curved = math.pow(clamped, controller._currentStylusCurve).toDouble();
  final double minFactor = controller._currentStylusMinFactor.clamp(0.0, 10.0);
  final double maxFactor = math.max(
    controller._currentStylusMaxFactor,
    minFactor + 0.01,
  );
  final double? lerped = ui.lerpDouble(minFactor, maxFactor, curved);
  final double factor = (lerped ?? maxFactor).clamp(0.0, 20.0);
  final double radius = controller._currentStrokeRadius * factor;
  final double minimum = math.max(controller._currentStrokeRadius * 0.02, 0.08);
  final double maximum = math.max(controller._currentStrokeRadius * 4.0, minimum);
  return radius.clamp(minimum, maximum);
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

double _strokeBlendRadiusForSegment({
  required double previousRadius,
  required double targetRadius,
  required double segmentLength,
}) {
  if (!targetRadius.isFinite) {
    return previousRadius;
  }
  if (!previousRadius.isFinite || previousRadius <= 0.0) {
    return targetRadius;
  }
  if (!segmentLength.isFinite || segmentLength <= 0.0) {
    return previousRadius + (targetRadius - previousRadius) * 0.2;
  }
  final double denom = math.max(previousRadius + targetRadius, 0.0001);
  final double distanceRatio = (segmentLength / denom).clamp(0.0, 1.0);
  const double kMinBlend = 0.2;
  const double kMaxBlend = 0.85;
  final double blend = kMinBlend + (kMaxBlend - kMinBlend) * distanceRatio;
  return previousRadius + (targetRadius - previousRadius) * blend;
}

void _strokeDrawPoint(
  BitmapCanvasController controller,
  Offset position,
  double radius,
) {
  if (controller._activeLayer.locked) {
    return;
  }
  controller._activeSurface.drawCircle(
    center: position,
    radius: radius,
    color: controller._currentStrokeColor,
    mask: controller._selectionMask,
    antialiasLevel: controller._currentStrokeAntialiasLevel,
  );
  controller._markDirty(
    region: _strokeDirtyRectForCircle(position, radius),
  );
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
