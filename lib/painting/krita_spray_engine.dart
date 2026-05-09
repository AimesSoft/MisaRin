import 'dart:math' as math;
import 'dart:ui';

import '../canvas/canvas_tools.dart';

typedef ClampToCanvas = Offset Function(Offset position);
typedef KritaSprayParticleCallback =
    void Function(
      Offset position,
      double radius,
      double opacityScale,
      Color baseColor,
    );

enum KritaRadialDistributionType { uniform, gaussian, cluster }

class KritaSprayEngineSettings {
  const KritaSprayEngineSettings({
    required this.diameter,
    this.scale = 1.0,
    this.aspectRatio = 1.0,
    this.rotation = 0.0,
    this.jitterMovement = true,
    this.jitterAmount = 0.15,
    this.radialDistribution = KritaRadialDistributionType.gaussian,
    this.radialCenterBiased = true,
    this.gaussianSigma = 0.35,
    this.particleMultiplier = 1.0,
    this.randomSize = true,
    this.minParticleScale = 0.012,
    this.maxParticleScale = 0.08,
    this.baseParticleScale = 0.04,
    this.minParticleRadius = 0.25,
    this.minParticleOpacity = 1.0,
    this.maxParticleOpacity = 1.0,
    this.shape = BrushShape.circle,
    this.minAntialiasLevel = 1,
  });

  final double diameter;
  final double scale;
  final double aspectRatio;
  final double rotation;
  final bool jitterMovement;
  final double jitterAmount;
  final KritaRadialDistributionType radialDistribution;
  final bool radialCenterBiased;
  final double gaussianSigma;
  final double particleMultiplier;
  final bool randomSize;
  final double minParticleScale;
  final double maxParticleScale;
  final double baseParticleScale;
  final double minParticleRadius;
  final double minParticleOpacity;
  final double maxParticleOpacity;
  final BrushShape shape;
  final int minAntialiasLevel;

  double radiusForPressure(double pressure) {
    final double clamped = pressure.clamp(0.05, 1.0);
    return math.max(
      0.5,
      (diameter / 2.0) * scale * (0.45 + clamped * 0.55),
    );
  }
}

/// Distributes spray particles using the same concepts as Krita's spray brush:
/// an elliptical area, configurable radial distributions, jitter and optional
/// color sampling.
class KritaSprayEngine {
  KritaSprayEngine({
    required ClampToCanvas clampToCanvas,
    KritaSprayEngineSettings? settings,
    math.Random? random,
  })  : _clampToCanvas = clampToCanvas,
        _settings = settings ??
            const KritaSprayEngineSettings(diameter: 120.0),
        _random = random ?? math.Random();

  final ClampToCanvas _clampToCanvas;
  final math.Random _random;
  KritaSprayEngineSettings _settings;
  double? _cachedGaussian;

  void updateSettings(KritaSprayEngineSettings value) {
    _settings = value;
  }

  int forEachParticle({
    required Offset center,
    required int particleBudget,
    required double pressure,
    required Color baseColor,
    required KritaSprayParticleCallback onParticle,
  }) {
    if (particleBudget <= 0) {
      return 0;
    }
    final double radius = _settings.radiusForPressure(pressure);
    final int particleCount = math.max(
      1,
      (particleBudget * _settings.particleMultiplier).round(),
    );
    final bool jitter = _settings.jitterMovement && _settings.jitterAmount > 0;
    final double jitterRadius =
        jitter ? radius * _settings.jitterAmount : 0.0;
    int emitted = 0;
    for (int i = 0; i < particleCount; i++) {
      final double angle = _random.nextDouble() * math.pi * 2.0;
      final double radial = _sampleRadial();
      final Offset offset = _transformOffset(
        angle: angle,
        radial: radial,
        radius: radius,
      );
      final Offset jitterOffset = jitter
          ? Offset(
              _randomRange(-jitterRadius, jitterRadius),
              _randomRange(-jitterRadius, jitterRadius),
            )
          : Offset.zero;
      final Offset position = _clampToCanvas(center + offset + jitterOffset);
      final double particleScale = _resolveParticleScale();
      final double particleRadius = math.max(
        _settings.minParticleRadius,
        radius * particleScale,
      );
      final double opacityScale = _resolveParticleOpacity();
      final double baseAlpha = baseColor.alpha / 255.0;
      final double finalAlpha = baseAlpha * opacityScale;
      if (finalAlpha <= 0.0) {
        continue;
      }
      onParticle(position, particleRadius, opacityScale, baseColor);
      emitted++;
    }
    return emitted;
  }

  Offset _transformOffset({
    required double angle,
    required double radial,
    required double radius,
  }) {
    final double distance = radial * radius;
    double dx = distance * math.cos(angle);
    double dy = distance * math.sin(angle);
    dy *= _settings.aspectRatio;
    if (_settings.rotation != 0.0) {
      final double sinR = math.sin(_settings.rotation);
      final double cosR = math.cos(_settings.rotation);
      final double rx = dx * cosR - dy * sinR;
      final double ry = dx * sinR + dy * cosR;
      dx = rx;
      dy = ry;
    }
    return Offset(dx, dy);
  }

  double _sampleRadial() {
    final double uniform = _random.nextDouble().clamp(1e-6, 1.0);
    switch (_settings.radialDistribution) {
      case KritaRadialDistributionType.gaussian:
        final double gaussian =
            _gaussianSample(_settings.gaussianSigma) * 0.5 + 0.5;
        final double clamped = gaussian.clamp(0.0, 1.0);
        return _settings.radialCenterBiased
            ? clamped
            : math.pow(clamped, 0.85).toDouble();
      case KritaRadialDistributionType.cluster:
        final double cluster = (uniform + _random.nextDouble()) * 0.5;
        return _settings.radialCenterBiased
            ? cluster * 0.8
            : math.pow(cluster, 1.2).toDouble();
      case KritaRadialDistributionType.uniform:
      default:
        final double sqrtSample = math.sqrt(uniform);
        return _settings.radialCenterBiased
            ? sqrtSample * 0.85
            : sqrtSample;
    }
  }

  double _gaussianSample(double sigma) {
    if (_cachedGaussian != null) {
      final double value = _cachedGaussian!;
      _cachedGaussian = null;
      return value * sigma;
    }
    final double u1 = _random.nextDouble().clamp(1e-12, 1.0);
    final double u2 = _random.nextDouble();
    final double mag = math.sqrt(-2.0 * math.log(u1));
    final double z0 = mag * math.cos(2 * math.pi * u2);
    final double z1 = mag * math.sin(2 * math.pi * u2);
    _cachedGaussian = z1;
    return z0 * sigma;
  }

  double _randomRange(double min, double max) {
    return _random.nextDouble() * (max - min) + min;
  }

  double _resolveParticleScale() {
    if (!_settings.randomSize) {
      return _settings.baseParticleScale;
    }
    final double value =
        _randomRange(_settings.minParticleScale, _settings.maxParticleScale);
    return value.clamp(0.001, 1.0);
  }

  double _resolveParticleOpacity() {
    final double minOpacity =
        _settings.minParticleOpacity.clamp(0.0, 1.0);
    final double maxOpacity =
        _settings.maxParticleOpacity.clamp(0.0, 1.0);
    if ((maxOpacity - minOpacity).abs() < 1e-4) {
      return maxOpacity;
    }
    final double value = _randomRange(minOpacity, maxOpacity);
    return value.clamp(0.0, 1.0);
  }

}
