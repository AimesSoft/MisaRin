import 'dart:math' as math;
import 'dart:ui' show Offset;
import 'dart:ui' as ui show lerpDouble;

import 'stroke_pressure_profile.dart';

/// 骨骼+史莱姆的笔压模拟引擎。
///
/// Skeleton 记录锚点位置与时间，SlimeSkin 根据速度、曲率、停顿时间
/// 分配“体积”，再将骨骼包裹成连续的柔软外轮廓。
class SlimeStrokeEngine {
  bool _active = false;
  final List<_SlimeJoint> _joints = <_SlimeJoint>[];

  double _baseRadius = 1.0;
  double _surfaceRadius = 1.0;
  double _volume = 0.0;
  double _stationaryMs = 0.0;
  double? _lastTimestamp;
  StrokePressureProfile _profile = StrokePressureProfile.auto;
  double _traveledDistance = 0.0;
  double _lastVisualRadius = 0.0;
  double _smoothedSpeed = 0.0;
  bool _dynamicRadius = true;

  static const double _kMinMotion = 0.35;
  static const double _kStationaryGain = 0.0045;
  static const double _kStationaryDecay = 0.65;
  static const double _kMaxStationary = 2200.0;
  static const double _kMinResponse = 0.18;
  static const double _kMaxResponse = 0.78;
  static const double _kCurvaturePenalty = 1.35;
  static const double _kSpeedTension = 0.52;
  static const double _kVolumeRelax = 0.12;

  bool get isActive => _active;

  double get surfaceRadius => _surfaceRadius;

  void setProfile(StrokePressureProfile profile) {
    _profile = profile;
  }

  void startStroke({
    required Offset position,
    required double baseRadius,
    required double timestampMillis,
    required bool dynamicRadius,
    double? initialOverrideRadius,
  }) {
    _active = true;
    _baseRadius = math.max(baseRadius, 0.08);
    _dynamicRadius = dynamicRadius;
    _stationaryMs = 0.0;
    _lastTimestamp = timestampMillis;
    _traveledDistance = 0.0;
    _smoothedSpeed = 0.0;
    final double seedRadius = _initialSurfaceRadius(initialOverrideRadius);
    _surfaceRadius = seedRadius;
    _volume = _surfaceRadius * _surfaceRadius * math.pi;
    _lastVisualRadius = _visualizeRadius(_surfaceRadius, 0.0);
    _joints
      ..clear()
      ..add(
        _SlimeJoint(
          position: position,
          timestamp: timestampMillis,
          radius: _surfaceRadius,
          visualRadius: _lastVisualRadius,
          tangent: null,
          progress: 0.0,
          leftPoint: null,
          rightPoint: null,
        ),
      );
  }

  SlimeStrokeSample? extend({
    required Offset position,
    required double timestampMillis,
    double? overrideRadius,
  }) {
    if (!_active || _joints.isEmpty) {
      return null;
    }
    final _SlimeJoint last = _joints.last;
    final Offset delta = position - last.position;
    final double distance = delta.distance;
    final double dt = _resolveDelta(timestampMillis);
    _lastTimestamp = timestampMillis;

    final double startProgress = _pathProgressFor(_traveledDistance);
    final double? forcedRadius = _clampOverrideRadius(overrideRadius);

    if (distance < _kMinMotion) {
      _stationaryMs = math.min(_stationaryMs + dt, _kMaxStationary);
      double nextRadius;
      if (_dynamicRadius) {
        final double swellTarget = math.max(
          _surfaceRadius,
          _stationaryRadius(),
        );
        _surfaceRadius =
            ui.lerpDouble(_surfaceRadius, swellTarget, 0.35) ?? swellTarget;
        nextRadius = _surfaceRadius;
        _volume = math.max(_volume, _surfaceRadius * _surfaceRadius * math.pi);
      } else {
        nextRadius = forcedRadius ?? _baseRadius;
        _surfaceRadius = nextRadius;
        _volume = nextRadius * nextRadius * math.pi;
      }
      final double visual = _visualizeRadius(nextRadius, startProgress);
      _lastVisualRadius = visual;
      _updateLastJointGeometry(
        radius: nextRadius,
        visualRadius: visual,
        progress: startProgress,
      );
      return null;
    }

    // 真正移动，更新骨骼与体积
    _stationaryMs = math.max(0.0, _stationaryMs - dt * _kStationaryDecay);
    double speed = distance / math.max(dt, 1.0);
    final double leadInThreshold = _baseRadius * 1.6;
    final double pendingDistance = _traveledDistance + distance;
    final double leadIn = math.min(leadInThreshold, pendingDistance);
    if (leadIn < leadInThreshold) {
      final double blend = (leadIn / leadInThreshold).clamp(0.0, 1.0);
      speed = speed * blend;
    } else {
      final double releaseBlend =
          ((_traveledDistance - leadInThreshold) / leadInThreshold).clamp(
            0.0,
            1.0,
          );
      speed = ui.lerpDouble(speed, _smoothedSpeed, releaseBlend) ?? speed;
    }
    _smoothedSpeed += (speed - _smoothedSpeed) * 0.35;
    final double curvature = _computeCurvature(position);

    _traveledDistance = pendingDistance;
    final _SlimeProfileTuning tuning = _profileTuning();
    final double pathProgress = (_traveledDistance / (_baseRadius * 4.0)).clamp(
      0.0,
      1.0,
    );

    final double targetVolume = _dynamicRadius
        ? _baseCrossSection() *
              (1.0 + (_stationaryMs * _kStationaryGain)) /
              (1.0 + curvature * 0.35 * tuning.curvaturePenaltyScale)
        : _crossSectionForRadius(forcedRadius ?? _baseRadius);
    _volume = ui.lerpDouble(
      _volume,
      targetVolume,
      _dynamicRadius ? _kVolumeRelax : 1.0,
    )!;

    final double rawResponse =
        ((_kMinResponse +
                    (_kMaxResponse - _kMinResponse) *
                        (1.0 -
                            math.exp(
                              -distance / (_baseRadius * 0.8 + 0.001),
                            ))) *
                tuning.responseBoost)
            .clamp(_kMinResponse * 0.6, _kMaxResponse * 1.2);
    final double response = _dynamicRadius
        ? ui.lerpDouble(0.25, rawResponse, pathProgress) ?? rawResponse
        : 1.0;

    final double rawRelease = _dynamicRadius
        ? 1.0 / (1.0 + speed * _kSpeedTension * tuning.speedTensionScale)
        : 1.0;
    final double release = _dynamicRadius
        ? ui.lerpDouble(1.0, rawRelease, pathProgress) ?? rawRelease
        : 1.0;
    final double rawCurvatureLoss = _dynamicRadius
        ? 1.0 /
              (1.0 +
                  curvature * _kCurvaturePenalty * tuning.curvaturePenaltyScale)
        : 1.0;
    final double curvatureLoss = _dynamicRadius
        ? ui.lerpDouble(1.0, rawCurvatureLoss, pathProgress) ?? rawCurvatureLoss
        : 1.0;

    final double area = _volume / math.max(distance * 0.95, _baseRadius * 0.45);
    double targetRadius = _dynamicRadius
        ? math.sqrt(area / math.pi) * release * curvatureLoss
        : (forcedRadius ?? _baseRadius);
    final double maxClamp = _dynamicRadius
        ? _baseRadius * 3.1
        : _baseRadius * 4.0;
    targetRadius = targetRadius.clamp(_baseRadius * 0.28, maxClamp);

    final double previousRadius = _surfaceRadius;
    _surfaceRadius =
        previousRadius + (targetRadius - previousRadius) * response;
    final double previousVisualRadius = _visualizeRadius(
      previousRadius,
      startProgress,
    );
    final double endProgress = _pathProgressFor(_traveledDistance);
    final double currentVisualRadius = _visualizeRadius(
      _surfaceRadius,
      endProgress,
    );
    final bool restartCaps = _needsRestartCaps(
      previousVisualRadius,
      currentVisualRadius,
    );

    final Offset direction = _normalizeOr(delta, const Offset(0.0, -1.0));
    _updateLastJointGeometry(
      radius: previousRadius,
      visualRadius: restartCaps ? currentVisualRadius : previousVisualRadius,
      tangent: direction,
      progress: startProgress,
    );
    final _SlimeJoint startJoint = _joints.last;
    final _SlimeJoint endJoint = _SlimeJoint(
      position: position,
      timestamp: timestampMillis,
      radius: _surfaceRadius,
      visualRadius: currentVisualRadius,
      tangent: direction,
      progress: endProgress,
    );
    final SlimeStrokeStrip strip = _buildStrip(startJoint, endJoint);
    _joints.add(endJoint);
    final bool firstSegment = _joints.length <= 2;
    final bool needStartCap = firstSegment || restartCaps;
    final SlimeStrokeCap? startCap = needStartCap
        ? SlimeStrokeCap(
            center: startJoint.position,
            radius: _visualRadiusOrFallback(startJoint),
          )
        : null;

    _lastVisualRadius = currentVisualRadius;

    return SlimeStrokeSample.strip(strip: strip, startCap: startCap);
  }

  SlimeTailResult? finishStroke() {
    if (!_active || _joints.isEmpty) {
      return null;
    }
    final _SlimeJoint tip = _joints.last;
    final double radius = math.max(_visualRadiusOrFallback(tip), 0.08);
    return SlimeTailResult.cap(
      cap: SlimeStrokeCap(center: tip.position, radius: radius),
    );
  }

  void reset() {
    _active = false;
    _joints.clear();
    _stationaryMs = 0.0;
    _volume = 0.0;
    _surfaceRadius = 0.0;
    _lastTimestamp = null;
    _traveledDistance = 0.0;
    _lastVisualRadius = 0.0;
  }

  double _resolveDelta(double timestampMillis) {
    if (_lastTimestamp == null) {
      return 16.0;
    }
    return (timestampMillis - _lastTimestamp!).clamp(2.0, 160.0);
  }

  double _stationaryRadius() {
    final double boost = (_stationaryMs / 140.0).clamp(0.0, 3.2);
    final double radius = _baseRadius * (0.65 + boost * 0.35);
    return radius.clamp(_baseRadius * 0.4, _baseRadius * 3.0);
  }

  double? _clampOverrideRadius(double? candidate) {
    if (candidate == null || !candidate.isFinite) {
      return null;
    }
    final double minRadius = math.max(_baseRadius * 0.05, 0.04);
    final double maxRadius = math.max(_baseRadius * 4.5, minRadius + 0.01);
    return candidate.clamp(minRadius, maxRadius);
  }

  double _initialSurfaceRadius(double? override) {
    final double seed;
    if (_dynamicRadius) {
      seed = override ?? (_baseRadius * 0.7);
    } else {
      seed = override ?? _baseRadius;
    }
    return math.max(seed, 0.08);
  }

  double _baseCrossSection() =>
      (_baseRadius * _baseRadius * math.pi).clamp(0.02, 80.0);

  double _crossSectionForRadius(double radius) {
    final double clamped = math.max(radius, 0.04);
    return (clamped * clamped * math.pi).clamp(0.02, 80.0);
  }

  double _computeCurvature(Offset nextPoint) {
    if (_joints.length < 2) {
      return 0.0;
    }
    final Offset a =
        _joints[_joints.length - 1].position -
        _joints[_joints.length - 2].position;
    final Offset b = nextPoint - _joints[_joints.length - 1].position;
    final double lenA = a.distance;
    final double lenB = b.distance;
    if (lenA < 1e-3 || lenB < 1e-3) {
      return 0.0;
    }
    final double dot = ((a.dx * b.dx) + (a.dy * b.dy)) / (lenA * lenB);
    final double angle = math.acos(dot.clamp(-1.0, 1.0));
    return (angle / math.pi).clamp(0.0, 1.0);
  }

  bool _needsRestartCaps(double previous, double next) {
    if (!previous.isFinite || !next.isFinite) {
      return true;
    }
    if (next <= previous) {
      return false;
    }
    if (_traveledDistance < _baseRadius * 0.6) {
      return false;
    }
    return next >= previous * 1.45;
  }

  double _visualizeRadius(double radius, double progress) {
    if (!_dynamicRadius) {
      return radius;
    }
    final _SlimeProfileTuning tuning = _profileTuning();
    final double clampedProgress = progress.clamp(0.0, 1.0);
    final double eased = math.pow(clampedProgress, 0.7).toDouble();
    double shaped = eased;
    if (tuning.centerNarrowing > 0) {
      final double symmetric = (clampedProgress - 0.5).abs() * 2.0;
      final double edgeWeight = math
          .pow(symmetric.clamp(0.0, 1.0), tuning.centerExponent)
          .toDouble();
      final double centerMin = (1.0 - tuning.centerNarrowing).clamp(0.0, 1.0);
      final double shape = centerMin + (1.0 - centerMin) * edgeWeight;

      final double normalizedSpeed = (_smoothedSpeed / (_baseRadius * 0.8))
          .clamp(0.0, 1.0);
      final double speedWeight = math.pow(normalizedSpeed, 0.55).toDouble();
      final double taperFactor = (1.0 - clampedProgress).abs();
      final double blend = (speedWeight * taperFactor).clamp(0.0, 1.0);

      shaped = ui.lerpDouble(shaped, shaped * shape, blend) ?? shaped;
    }
    final double base = _baseRadius * 0.52;
    final double visual = base + (radius - base) * shaped;
    return visual.clamp(_baseRadius * 0.4, _baseRadius * 3.2);
  }

  double _pathProgressFor(double distance) {
    final double denom = _baseRadius * 6.0;
    if (denom <= 0.0001) {
      return 0.0;
    }
    return (distance / denom).clamp(0.0, 1.0);
  }

  void _updateLastJointGeometry({
    double? radius,
    double? visualRadius,
    Offset? tangent,
    double? progress,
  }) {
    if (_joints.isEmpty) {
      return;
    }
    final int index = _joints.length - 1;
    final _SlimeJoint joint = _joints[index];
    _joints[index] = _SlimeJoint(
      position: joint.position,
      timestamp: joint.timestamp,
      radius: radius ?? joint.radius,
      visualRadius: visualRadius ?? joint.visualRadius,
      tangent: tangent ?? joint.tangent,
      progress: progress ?? joint.progress,
    );
  }

  _SlimeProfileTuning _profileTuning() {
    switch (_profile) {
      case StrokePressureProfile.taperEnds:
        return const _SlimeProfileTuning(
          responseBoost: 0.82,
          speedTensionScale: 1.35,
          curvaturePenaltyScale: 0.9,
          tailLengthScale: 1.1,
        );
      case StrokePressureProfile.taperCenter:
        return const _SlimeProfileTuning(
          responseBoost: 1.05,
          speedTensionScale: 0.7,
          curvaturePenaltyScale: 1.25,
          tailLengthScale: 0.85,
          centerNarrowing: 0.45,
          centerExponent: 0.8,
        );
      case StrokePressureProfile.auto:
        return const _SlimeProfileTuning();
    }
  }
}

class _SlimeProfileTuning {
  const _SlimeProfileTuning({
    this.responseBoost = 1.0,
    this.speedTensionScale = 1.0,
    this.curvaturePenaltyScale = 1.0,
    this.tailLengthScale = 1.0,
    this.centerNarrowing = 0.0,
    this.centerExponent = 1.0,
  });

  final double responseBoost;
  final double speedTensionScale;
  final double curvaturePenaltyScale;
  final double tailLengthScale;
  final double centerNarrowing;
  final double centerExponent;
}

class SlimeStrokeSample {
  const SlimeStrokeSample.strip({required this.strip, this.startCap});

  final SlimeStrokeStrip strip;
  final SlimeStrokeCap? startCap;
}

class SlimeTailResult {
  const SlimeTailResult.cap({required this.cap});

  final SlimeStrokeCap cap;
}

class SlimeStrokeStrip {
  const SlimeStrokeStrip({
    required this.startLeft,
    required this.endLeft,
    required this.endRight,
    required this.startRight,
  });

  final Offset startLeft;
  final Offset endLeft;
  final Offset endRight;
  final Offset startRight;

  Iterable<Offset> get points => <Offset>[
    startLeft,
    startRight,
    endRight,
    endLeft,
  ];
}

class SlimeStrokeCap {
  const SlimeStrokeCap({required this.center, required this.radius});

  final Offset center;
  final double radius;
}

class _SlimeJoint {
  _SlimeJoint({
    required this.position,
    required this.timestamp,
    required this.radius,
    this.visualRadius,
    this.tangent,
    required this.progress,
    this.leftPoint,
    this.rightPoint,
  });

  final Offset position;
  final double timestamp;
  final double radius;
  final double? visualRadius;
  final Offset? tangent;
  final double progress;
  final Offset? leftPoint;
  final Offset? rightPoint;
}

SlimeStrokeStrip _buildStrip(_SlimeJoint start, _SlimeJoint end) {
  final Offset direction = end.position - start.position;
  final Offset fallback = start.tangent ?? const Offset(0.0, -1.0);
  final Offset tangent = _normalizeOr(direction, fallback);
  final Offset normal = _perpendicularLeft(tangent);
  final double startRadius = _visualRadiusOrFallback(start);
  final double endRadius = _visualRadiusOrFallback(end);
  return SlimeStrokeStrip(
    startLeft: start.position + normal * startRadius,
    endLeft: end.position + normal * endRadius,
    endRight: end.position - normal * endRadius,
    startRight: start.position - normal * startRadius,
  );
}

Offset _perpendicularLeft(Offset vector) => Offset(-vector.dy, vector.dx);

Offset _normalizeOr(Offset vector, Offset fallback) {
  final double length = vector.distance;
  if (length <= 1e-5) {
    return fallback;
  }
  return Offset(vector.dx / length, vector.dy / length);
}

double _visualRadiusOrFallback(_SlimeJoint joint) =>
    (joint.visualRadius ?? joint.radius).abs();
