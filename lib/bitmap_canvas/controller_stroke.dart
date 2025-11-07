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
  controller._currentStrokeStylusPressureEnabled =
      useDevicePressure &&
      controller._stylusPressureEnabled &&
      !simulatePressure;
  controller._currentStylusMinFactor = controller._stylusMinFactor;
  controller._currentStylusMaxFactor = math.max(
    controller._stylusMaxFactor,
    controller._stylusMinFactor,
  );
  controller._currentStylusCurve = controller._stylusCurve;
  controller._currentStylusSmoothedPressure = null;
  controller._currentStrokeAntialiasLevel = antialiasLevel.clamp(0, 3);
  controller._currentStrokeHasMoved = false;
  final double resolvedTimestamp = timestampMillis ?? 0.0;
  controller._currentStrokeLastTimestamp = resolvedTimestamp;
  double? initialOverrideRadius;
  if (controller._currentStrokeStylusPressureEnabled) {
    final double? normalized = _strokeNormalizeStylusPressure(
      controller,
      pressure,
      pressureMin,
      pressureMax,
    );
    if (normalized != null) {
      final double clamped = normalized.clamp(0.0, 1.0);
      controller._currentStylusSmoothedPressure = clamped;
      initialOverrideRadius = _strokeRadiusFromNormalized(controller, clamped);
    }
  }
  controller._slimeStrokeEngine.startStroke(
    position: position,
    baseRadius: radius,
    timestampMillis: resolvedTimestamp,
    dynamicRadius: simulatePressure,
    initialOverrideRadius: initialOverrideRadius,
  );
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
  controller._currentStrokePoints.add(position);
  final double sampleTimestamp = _strokeResolveSampleTimestamp(
    controller,
    timestampMillis,
    deltaTimeMillis,
  );
  double? overrideRadius;
  if (controller._currentStrokeStylusPressureEnabled) {
    final double? normalized = _strokeNormalizeStylusPressure(
      controller,
      pressure,
      pressureMin,
      pressureMax,
    );
    if (normalized != null) {
      final double candidate = normalized.clamp(0.0, 1.0);
      final double smoothed = controller._currentStylusSmoothedPressure == null
          ? candidate
          : controller._currentStylusSmoothedPressure! +
                (candidate - controller._currentStylusSmoothedPressure!) *
                    BitmapCanvasController._kStylusSmoothing;
      controller._currentStylusSmoothedPressure = smoothed;
      overrideRadius = _strokeRadiusFromNormalized(controller, smoothed);
    } else if (controller._currentStylusSmoothedPressure != null) {
      overrideRadius = _strokeRadiusFromNormalized(
        controller,
        controller._currentStylusSmoothedPressure!,
      );
    }
  }

  final SlimeStrokeSample? sample = controller._slimeStrokeEngine.extend(
    position: position,
    timestampMillis: sampleTimestamp,
    overrideRadius: overrideRadius,
  );
  if (sample == null) {
    return;
  }
  if (sample.startCap != null) {
    _strokeRenderCap(controller, sample.startCap!);
  }
  _strokeRenderStrip(controller, sample.strip);
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

  final SlimeTailResult? tail = controller._slimeStrokeEngine.finishStroke();
  if (tail != null) {
    _strokeRenderCap(controller, tail.cap);
  } else if (!hasPath) {
    _strokeDrawPoint(controller, tip, controller._currentStrokeRadius);
  }

  controller._slimeStrokeEngine.reset();

  controller._currentStrokePoints.clear();
  controller._currentStrokeRadius = 0;
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
  final double curved = math
      .pow(clamped, controller._currentStylusCurve)
      .toDouble();
  final double minFactor = controller._currentStylusMinFactor.clamp(0.0, 10.0);
  final double maxFactor = math.max(
    controller._currentStylusMaxFactor,
    minFactor + 0.01,
  );
  final double? lerped = ui.lerpDouble(minFactor, maxFactor, curved);
  final double factor = (lerped ?? maxFactor).clamp(0.0, 20.0);
  final double radius = controller._currentStrokeRadius * factor;
  final double minimum = math.max(controller._currentStrokeRadius * 0.02, 0.08);
  final double maximum = math.max(
    controller._currentStrokeRadius * 4.0,
    minimum,
  );
  return radius.clamp(minimum, maximum);
}

void _strokeDrawPoint(
  BitmapCanvasController controller,
  Offset position,
  double radius,
) {
  if (controller._activeLayer.locked) {
    return;
  }
  _strokeRenderCap(
    controller,
    SlimeStrokeCap(center: position, radius: radius),
  );
}

void _strokeRenderStrip(
  BitmapCanvasController controller,
  SlimeStrokeStrip strip,
) {
  controller._activeSurface.fillStrip(
    polygon: strip.points,
    color: controller._currentStrokeColor,
    mask: controller._selectionMask,
    antialiasLevel: controller._currentStrokeAntialiasLevel,
  );
  controller._markDirty(region: _strokeDirtyRectForStrip(strip));
}

void _strokeRenderCap(BitmapCanvasController controller, SlimeStrokeCap cap) {
  controller._activeSurface.fillCap(
    center: cap.center,
    radius: cap.radius,
    color: controller._currentStrokeColor,
    mask: controller._selectionMask,
    antialiasLevel: controller._currentStrokeAntialiasLevel,
  );
  controller._markDirty(region: _strokeDirtyRectForCap(cap));
}

Rect _strokeDirtyRectForCircle(Offset center, double radius) {
  final double effectiveRadius = math.max(radius, 0.5);
  return Rect.fromCircle(center: center, radius: effectiveRadius + 1.5);
}

Rect _strokeDirtyRectForLine(Offset a, Offset b, double radius) {
  final double inflate = math.max(radius, 0.5) + 1.5;
  return Rect.fromPoints(a, b).inflate(inflate);
}

Rect _strokeDirtyRectForStrip(SlimeStrokeStrip strip) {
  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = -double.infinity;
  double maxY = -double.infinity;
  for (final Offset point in strip.points) {
    if (point.dx < minX) {
      minX = point.dx;
    }
    if (point.dx > maxX) {
      maxX = point.dx;
    }
    if (point.dy < minY) {
      minY = point.dy;
    }
    if (point.dy > maxY) {
      maxY = point.dy;
    }
  }
  if (!minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite) {
    return Rect.zero;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(1.5);
}

Rect _strokeDirtyRectForCap(SlimeStrokeCap cap) =>
    _strokeDirtyRectForCircle(cap.center, cap.radius);
