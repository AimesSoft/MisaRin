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
  }) {
    _active = true;
    _joints
      ..clear()
      ..add(
        _SlimeJoint(
          position: position,
          timestamp: timestampMillis,
          radius: _surfaceRadius,
          visualRadius: _lastVisualRadius,
        ),
      );
    _baseRadius = math.max(baseRadius, 0.08);
    _surfaceRadius = _baseRadius * 0.7;
    _volume = _surfaceRadius * _surfaceRadius * math.pi;
    _stationaryMs = 0.0;
    _lastTimestamp = timestampMillis;
    _traveledDistance = 0.0;
    _lastVisualRadius = _visualizeRadius(_surfaceRadius, 0.0);
  }

  SlimeStrokeSample? extend({
    required Offset position,
    required double timestampMillis,
  }) {
    if (!_active) {
      return null;
    }
    final _SlimeJoint last = _joints.last;
    final Offset delta = position - last.position;
    final double distance = delta.distance;
    final double dt = _resolveDelta(timestampMillis);
    _lastTimestamp = timestampMillis;

    final double startProgress = _pathProgressFor(_traveledDistance);
    if (distance < _kMinMotion) {
      _stationaryMs = math.min(_stationaryMs + dt, _kMaxStationary);
      final double blobRadius =
          _visualizeRadius(_stationaryRadius(), startProgress);
      _lastVisualRadius = blobRadius;
      return SlimeStrokeSample.blob(center: position, radius: blobRadius);
    }

    // 真正移动，更新骨骼与体积
    _stationaryMs = math.max(0.0, _stationaryMs - dt * _kStationaryDecay);
    final double speed = distance / math.max(dt, 1.0);
    final double curvature = _computeCurvature(position);
    _traveledDistance += distance;

    final _SlimeProfileTuning tuning = _profileTuning();

    final double pathProgress =
        (_traveledDistance / (_baseRadius * 4.0)).clamp(0.0, 1.0);

    final double targetVolume = _baseCrossSection() *
        (1.0 + (_stationaryMs * _kStationaryGain)) /
        (1.0 + curvature * 0.35 * tuning.curvaturePenaltyScale);
    _volume = ui.lerpDouble(_volume, targetVolume, _kVolumeRelax)!;

    final double rawResponse = ((_kMinResponse +
            (_kMaxResponse - _kMinResponse) *
                (1.0 - math.exp(-distance / (_baseRadius * 0.8 + 0.001))))
        * tuning.responseBoost)
        .clamp(_kMinResponse * 0.6, _kMaxResponse * 1.2);
    final double response =
        ui.lerpDouble(0.25, rawResponse, pathProgress) ?? rawResponse;

    final double rawRelease =
        1.0 / (1.0 + speed * _kSpeedTension * tuning.speedTensionScale);
    final double release =
        ui.lerpDouble(1.0, rawRelease, pathProgress) ?? rawRelease;
    final double rawCurvatureLoss =
        1.0 /
        (1.0 + curvature * _kCurvaturePenalty * tuning.curvaturePenaltyScale);
    final double curvatureLoss =
        ui.lerpDouble(1.0, rawCurvatureLoss, pathProgress) ?? rawCurvatureLoss;

    final double area = _volume / math.max(distance * 0.95, _baseRadius * 0.45);
    double targetRadius = math.sqrt(area / math.pi) * release * curvatureLoss;
    targetRadius = targetRadius.clamp(_baseRadius * 0.28, _baseRadius * 3.1);

    final double previousRadius = _surfaceRadius;
    _surfaceRadius = previousRadius + (targetRadius - previousRadius) * response;
    final double previousVisualRadius =
        _visualizeRadius(previousRadius, startProgress);
    _traveledDistance += distance;
    final double endProgress = _pathProgressFor(_traveledDistance);
    final double currentVisualRadius =
        _visualizeRadius(_surfaceRadius, endProgress);
    final bool restartCaps =
        _needsRestartCaps(previousVisualRadius, currentVisualRadius);

    final Offset direction = delta / distance;
    _joints.add(
      _SlimeJoint(
        position: position,
        timestamp: timestampMillis,
        radius: _surfaceRadius,
        visualRadius: currentVisualRadius,
        tangent: direction,
      ),
    );
    final double startRadius = restartCaps ? currentVisualRadius : previousVisualRadius;
    final double endRadius = currentVisualRadius;
    _lastVisualRadius = endRadius;

    return SlimeStrokeSample.segment(
      startRadius: startRadius,
      endRadius: endRadius,
      includeStartCap: restartCaps,
    );
  }

  SlimeTailResult? finishStroke() {
    if (!_active || _joints.isEmpty) {
      return null;
    }
    final _SlimeJoint tip = _joints.last;
    final bool minimalTravel = _traveledDistance <= _baseRadius * 0.9;
    if (_joints.length == 1 || minimalTravel) {
      return SlimeTailResult.point(
        center: tip.position,
        radius: tip.visualRadius ?? tip.radius,
      );
    }
    final _SlimeJoint prev = _joints[_joints.length - 2];
    Offset tangent = tip.tangent ?? (tip.position - prev.position);
    if (tangent.distance <= 1e-4) {
      tangent = const Offset(0.0, -1.0);
    }
    tangent = tangent / tangent.distance;
    final double pathProgress = _pathProgressFor(_traveledDistance);
    if (pathProgress < 0.35) {
      return SlimeTailResult.point(
        center: tip.position,
        radius: tip.visualRadius ?? tip.radius,
      );
    }
    return null;
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

  double _baseCrossSection() =>
      (_baseRadius * _baseRadius * math.pi).clamp(0.02, 80.0);

  double _computeCurvature(Offset nextPoint) {
    if (_joints.length < 2) {
      return 0.0;
    }
    final Offset a = _joints[_joints.length - 1].position -
        _joints[_joints.length - 2].position;
    final Offset b = nextPoint - _joints[_joints.length - 1].position;
    final double lenA = a.distance;
    final double lenB = b.distance;
    if (lenA < 1e-3 || lenB < 1e-3) {
      return 0.0;
    }
    final double dot =
        ((a.dx * b.dx) + (a.dy * b.dy)) / (lenA * lenB);
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
    final double eased = math.pow(progress.clamp(0.0, 1.0), 0.7).toDouble();
    final double base = _baseRadius * 0.52;
    final double visual = base + (radius - base) * eased;
    return visual.clamp(_baseRadius * 0.4, _baseRadius * 3.2);
  }

  double _pathProgressFor(double distance) {
    final double denom = _baseRadius * 6.0;
    if (denom <= 0.0001) {
      return 0.0;
    }
    return (distance / denom).clamp(0.0, 1.0);
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
  });

  final double responseBoost;
  final double speedTensionScale;
  final double curvaturePenaltyScale;
  final double tailLengthScale;
}

class SlimeStrokeSample {
  const SlimeStrokeSample._({
    required this.isBlob,
    this.startRadius,
    this.endRadius,
    this.includeStartCap = false,
    this.blobCenter,
    this.blobRadius,
  });

  const SlimeStrokeSample.segment({
    required double startRadius,
    required double endRadius,
    required bool includeStartCap,
  }) : this._(
          isBlob: false,
          startRadius: startRadius,
          endRadius: endRadius,
          includeStartCap: includeStartCap,
        );

  const SlimeStrokeSample.blob({
    required Offset center,
    required double radius,
  }) : this._(
          isBlob: true,
          blobCenter: center,
          blobRadius: radius,
        );

  final bool isBlob;
  final double? startRadius;
  final double? endRadius;
  final bool includeStartCap;
  final Offset? blobCenter;
  final double? blobRadius;
}

class SlimeTailResult {
  const SlimeTailResult._({
    required this.isLine,
    this.start,
    this.end,
    this.startRadius,
    this.endRadius,
    this.center,
    this.pointRadius,
  });

  const SlimeTailResult.line({
    required Offset start,
    required Offset end,
    required double startRadius,
    required double endRadius,
  }) : this._(
          isLine: true,
          start: start,
          end: end,
          startRadius: startRadius,
          endRadius: endRadius,
        );

  const SlimeTailResult.point({
    required Offset center,
    required double radius,
  }) : this._(
          isLine: false,
          center: center,
          pointRadius: radius,
        );

  final bool isLine;
  final Offset? start;
  final Offset? end;
  final double? startRadius;
  final double? endRadius;
  final Offset? center;
  final double? pointRadius;
}

class _SlimeJoint {
  _SlimeJoint({
    required this.position,
    required this.timestamp,
    this.radius = 0.0,
    this.visualRadius,
    this.tangent,
  });

  final Offset position;
  final double timestamp;
  final double radius;
  final double? visualRadius;
  final Offset? tangent;
}
