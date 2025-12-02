import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../canvas/brush_shape_geometry.dart';
import '../canvas/canvas_tools.dart';

const double _kSubpixelRadiusLimit = 0.6;
const double _kHalfPixel = 0.5;
const double _kSupersampleDiameterThreshold = 10.0;
const double _kSupersampleFineDiameter = 1.0;
const int _kMinIntegrationSlices = 6;
const int _kMaxIntegrationSlices = 20;

/// A lightweight bitmap surface that stores pixels in ARGB8888 format
/// and exposes basic drawing primitives for future integration.
class BitmapSurface {
  BitmapSurface({required this.width, required this.height, Color? fillColor})
    : pixels = Uint32List(width * height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Surface dimensions must be positive');
    }
    if (fillColor != null) {
      fill(fillColor);
    }
  }

  final int width;
  final int height;
  final Uint32List pixels;
  bool _isClean = true;

  /// Returns true if the surface is guaranteed to be fully transparent (all zeros).
  bool get isClean => _isClean;

  /// Marks the surface as potentially containing non-transparent pixels.
  /// Should be called when modifying [pixels] directly from outside.
  void markDirty() {
    _isClean = false;
  }

  /// Clears the entire surface with [color].
  void fill(Color color) {
    final int encoded = encodeColor(color);
    for (int i = 0; i < pixels.length; i++) {
      pixels[i] = encoded;
    }
    _isClean = encoded == 0;
  }

  /// Returns the color at the given integer pixel position.
  Color pixelAt(int x, int y) {
    if (!_inBounds(x, y)) {
      throw RangeError('Pixel coordinates out of bounds: ($x, $y)');
    }
    return decodeColor(pixels[y * width + x]);
  }

  /// Draws a filled circle centered at [center] with radius [radius].
  void drawCircle({
    required Offset center,
    required double radius,
    required Color color,
    Uint8List? mask,
    int antialiasLevel = 0,
    bool erase = false,
    double softness = 0.0,
  }) {
    if (radius <= 0) {
      return;
    }
    final double softnessClamped = softness.clamp(0.0, 1.0);
    final double softnessRadius = softnessClamped > 0
        ? radius * (0.35 + softnessClamped * 1.65)
        : 0.0;
    final double extent = radius + softnessRadius + 1.5;
    final int minX = math.max(0, (center.dx - extent).floor());
    final int maxX = math.min(width - 1, (center.dx + extent).ceil());
    final int minY = math.max(0, (center.dy - extent).floor());
    final int maxY = math.min(height - 1, (center.dy + extent).ceil());
    final int level = antialiasLevel.clamp(0, 3);
    final double feather = _featherForLevel(level);
    final int baseColor = color.toARGB32();
    final int baseAlpha = (baseColor >> 24) & 0xff;
    final int baseRgb = baseColor & 0x00ffffff;

    for (int y = minY; y <= maxY; y++) {
      final double dy = y + 0.5 - center.dy;
      for (int x = minX; x <= maxX; x++) {
        final double dx = x + 0.5 - center.dx;
        final double distance = math.sqrt(dx * dx + dy * dy);
        final double coverage = softnessClamped <= 0.0
            ? _computePixelCoverage(
                dx: dx,
                dy: dy,
                distance: distance,
                radius: radius,
                feather: feather,
                antialiasLevel: level,
              )
            : _computeFeatheredCoverage(
                distance: distance,
                radius: radius,
                softness: softnessClamped,
              );
        if (coverage <= 0.0) {
          continue;
        }
        if (mask != null && mask[y * width + x] == 0) {
          continue;
        }
        if (coverage >= 0.999 && softnessClamped <= 0.0) {
          _blendPixelWithArgb(x, y, baseColor, erase: erase);
          continue;
        }
        final int adjustedAlpha = (baseAlpha * coverage).round().clamp(0, 255);
        if (adjustedAlpha == 0) {
          continue;
        }
        final int encoded = (adjustedAlpha << 24) | baseRgb;
        _blendPixelWithArgb(x, y, encoded, erase: erase);
      }
    }
  }

  /// Draws a line between [a] and [b] with a circular brush of [radius].
  void drawLine({
    required Offset a,
    required Offset b,
    required double radius,
    required Color color,
    Uint8List? mask,
    int antialiasLevel = 0,
    bool includeStartCap = true,
    bool erase = false,
  }) {
    _drawCapsuleSegment(
      a: a,
      b: b,
      startRadius: radius,
      endRadius: radius,
      color: color,
      mask: mask,
      antialiasLevel: antialiasLevel.clamp(0, 3),
      includeStartCap: includeStartCap,
      erase: erase,
    );
  }

  /// Draws a line between [a] and [b] gradually interpolating the brush radius.
  void drawVariableLine({
    required Offset a,
    required Offset b,
    required double startRadius,
    required double endRadius,
    required Color color,
    Uint8List? mask,
    int antialiasLevel = 0,
    bool includeStartCap = true,
    bool erase = false,
  }) {
    _drawCapsuleSegment(
      a: a,
      b: b,
      startRadius: startRadius,
      endRadius: endRadius,
      color: color,
      mask: mask,
      antialiasLevel: antialiasLevel.clamp(0, 3),
      includeStartCap: includeStartCap,
      erase: erase,
    );
  }

  /// Draws a stroke made of consecutive [points].
  void drawStroke({
    required List<Offset> points,
    required double radius,
    required Color color,
    Uint8List? mask,
    int antialiasLevel = 0,
    bool erase = false,
  }) {
    if (points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      drawCircle(
        center: points.first,
        radius: radius,
        color: color,
        mask: mask,
        antialiasLevel: antialiasLevel,
        erase: erase,
      );
      return;
    }
    bool includeStartCap = true;
    for (int i = 0; i < points.length - 1; i++) {
      drawLine(
        a: points[i],
        b: points[i + 1],
        radius: radius,
        color: color,
        mask: mask,
        antialiasLevel: antialiasLevel,
        includeStartCap: includeStartCap,
        erase: erase,
      );
      includeStartCap = false;
    }
  }

  void drawFilledPolygon({
    required List<Offset> vertices,
    required Color color,
    Uint8List? mask,
    int antialiasLevel = 0,
    bool erase = false,
  }) {
    if (vertices.length < 3) {
      return;
    }
    final List<Offset> sanitized = _sanitizePolygonVertices(vertices);
    if (sanitized.length < 3) {
      return;
    }
    double minX = sanitized.first.dx;
    double maxX = sanitized.first.dx;
    double minY = sanitized.first.dy;
    double maxY = sanitized.first.dy;
    for (final Offset vertex in sanitized) {
      if (vertex.dx < minX) {
        minX = vertex.dx;
      }
      if (vertex.dx > maxX) {
        maxX = vertex.dx;
      }
      if (vertex.dy < minY) {
        minY = vertex.dy;
      }
      if (vertex.dy > maxY) {
        maxY = vertex.dy;
      }
    }
    if (minX.isNaN || maxX.isNaN || minY.isNaN || maxY.isNaN) {
      return;
    }
    final int level = antialiasLevel.clamp(0, 3);
    final double padding = _featherForLevel(level) + 1.5;
    final Rect bounds = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(padding);
    final double longestSide = math.max(
      bounds.width.abs(),
      bounds.height.abs(),
    );
    final double radius = math.max(longestSide * 0.5, 0.01);
    _drawPolygonStamp(
      vertices: sanitized,
      bounds: bounds,
      radius: radius,
      color: color,
      mask: mask,
      antialiasLevel: level,
      erase: erase,
    );
  }

  void drawBrushStamp({
    required Offset center,
    required double radius,
    required Color color,
    required BrushShape shape,
    Uint8List? mask,
    int antialiasLevel = 0,
    bool erase = false,
    double softness = 0.0,
  }) {
    final int level = antialiasLevel.clamp(0, 3);
    if (shape == BrushShape.circle) {
      drawCircle(
        center: center,
        radius: radius,
        color: color,
        mask: mask,
        antialiasLevel: level,
        erase: erase,
        softness: softness,
      );
      return;
    }
    final double effectiveRadius = math.max(radius.abs(), 0.01);
    final List<Offset> vertices = BrushShapeGeometry.polygonFor(
      shape,
      center,
      effectiveRadius,
    );
    if (vertices.length < 3) {
      drawCircle(
        center: center,
        radius: effectiveRadius,
        color: color,
        mask: mask,
        antialiasLevel: level,
      );
      return;
    }
    final Rect bounds = BrushShapeGeometry.boundsFor(
      shape,
      center,
      effectiveRadius,
    ).inflate(_featherForLevel(level) + 1.5);
    _drawPolygonStamp(
      vertices: vertices,
      bounds: bounds,
      radius: effectiveRadius,
      color: color,
      mask: mask,
      antialiasLevel: level,
      erase: erase,
    );
  }

  double _featherForLevel(int level) {
    const List<double> feather = <double>[0.0, 0.7, 1.1, 1.6];
    return feather[level.clamp(0, feather.length - 1)];
  }

  List<Offset> _sanitizePolygonVertices(List<Offset> vertices) {
    if (vertices.isEmpty) {
      return const <Offset>[];
    }
    final List<Offset> sanitized = <Offset>[];
    Offset? previous;
    for (final Offset vertex in vertices) {
      if (previous != null &&
          (vertex.dx - previous.dx).abs() < 1e-4 &&
          (vertex.dy - previous.dy).abs() < 1e-4) {
        continue;
      }
      sanitized.add(vertex);
      previous = vertex;
    }
    if (sanitized.length >= 2) {
      final Offset first = sanitized.first;
      final Offset last = sanitized.last;
      if ((first.dx - last.dx).abs() < 1e-4 &&
          (first.dy - last.dy).abs() < 1e-4) {
        sanitized.removeLast();
      }
    }
    return sanitized;
  }

  void _drawPolygonStamp({
    required List<Offset> vertices,
    required Rect bounds,
    required double radius,
    required Color color,
    Uint8List? mask,
    required int antialiasLevel,
    bool erase = false,
  }) {
    if (vertices.length < 3) {
      return;
    }
    final double baseFeather = _featherForLevel(antialiasLevel);
    final double feather = antialiasLevel > 0
        ? math.max(baseFeather, 0.35)
        : 0.0;
    final Rect coverageBounds = bounds.inflate(feather + 1.5);
    final int minX = math.max(0, coverageBounds.left.floor());
    final int maxX = math.min(width - 1, coverageBounds.right.ceil());
    final int minY = math.max(0, coverageBounds.top.floor());
    final int maxY = math.min(height - 1, coverageBounds.bottom.ceil());
    if (minX > maxX || minY > maxY) {
      return;
    }
    int supersample = 1;
    double step = 1.0;
    double start = 0.0;
    double invSampleCount = 1.0;
    if (antialiasLevel > 0) {
      final bool requiresSupersampling = _needsSupersampling(
        radius,
        antialiasLevel,
      );
      final int adaptiveSamples = requiresSupersampling
          ? _supersampleFactor(radius).clamp(1, 6)
          : 1;
      final int desiredSamples = (antialiasLevel + 1) * 2;
      supersample = math.max(adaptiveSamples, desiredSamples).clamp(2, 6);
      step = 1.0 / supersample;
      start = -0.5 + step * 0.5;
      invSampleCount = 1.0 / (supersample * supersample);
    }
    final int baseAlpha = color.alpha;
    final int baseColor = color.toARGB32();
    final int baseRgb = baseColor & 0x00FFFFFF;
    for (int y = minY; y <= maxY; y++) {
      final double py = y + 0.5;
      final int rowIndex = y * width;
      for (int x = minX; x <= maxX; x++) {
        if (mask != null && mask[rowIndex + x] == 0) {
          continue;
        }
        double coverage;
        if (supersample <= 1) {
          coverage = _polygonCoverageAtPoint(
            px: x + 0.5,
            py: py,
            vertices: vertices,
            feather: feather,
          );
        } else {
          double accumulated = 0.0;
          for (int sy = 0; sy < supersample; sy++) {
            final double offsetY = start + sy * step;
            final double samplePy = py + offsetY;
            for (int sx = 0; sx < supersample; sx++) {
              final double offsetX = start + sx * step;
              final double samplePx = x + 0.5 + offsetX;
              accumulated += _polygonCoverageAtPoint(
                px: samplePx,
                py: samplePy,
                vertices: vertices,
                feather: feather,
              );
            }
          }
          coverage = accumulated * invSampleCount;
        }
        if (coverage <= 0.0) {
          continue;
        }
        if (coverage >= 0.999) {
          _blendPixelWithArgb(x, y, baseColor, erase: erase);
          continue;
        }
        final int adjustedAlpha = (baseAlpha * coverage).round().clamp(0, 255);
        if (adjustedAlpha == 0) {
          continue;
        }
        final int encoded = (adjustedAlpha << 24) | baseRgb;
        _blendPixelWithArgb(x, y, encoded, erase: erase);
      }
    }
  }

  double _polygonCoverageAtPoint({
    required double px,
    required double py,
    required List<Offset> vertices,
    required double feather,
  }) {
    final double signedDistance = _signedDistanceToPolygon(px, py, vertices);
    if (!signedDistance.isFinite) {
      return 0.0;
    }
    if (feather <= 0.0) {
      return signedDistance <= 0.0 ? 1.0 : 0.0;
    }
    if (signedDistance <= -feather) {
      return 1.0;
    }
    if (signedDistance >= feather) {
      return 0.0;
    }
    return (feather - signedDistance) / (2.0 * feather);
  }

  double _signedDistanceToPolygon(double px, double py, List<Offset> vertices) {
    final int count = vertices.length;
    if (count < 3) {
      return double.infinity;
    }
    double minDistSq = double.infinity;
    bool inside = false;
    for (int i = 0; i < count; i++) {
      final Offset a = vertices[i];
      final Offset b = vertices[(i + 1) % count];
      final double ax = a.dx;
      final double ay = a.dy;
      final double bx = b.dx;
      final double by = b.dy;
      final double abx = bx - ax;
      final double aby = by - ay;
      double proj = 0.0;
      final double denom = abx * abx + aby * aby;
      if (denom > 0.0) {
        proj = ((px - ax) * abx + (py - ay) * aby) / denom;
        if (proj < 0.0) {
          proj = 0.0;
        } else if (proj > 1.0) {
          proj = 1.0;
        }
      }
      final double closestX = ax + abx * proj;
      final double closestY = ay + aby * proj;
      final double dx = px - closestX;
      final double dy = py - closestY;
      final double distSq = dx * dx + dy * dy;
      if (distSq < minDistSq) {
        minDistSq = distSq;
      }
      if (((ay > py) != (by > py)) &&
          (px < (bx - ax) * (py - ay) / (by - ay) + ax)) {
        inside = !inside;
      }
    }
    final double distance = math.sqrt(math.max(minDistSq, 0.0));
    return inside ? -distance : distance;
  }

  void _drawCapsuleSegment({
    required Offset a,
    required Offset b,
    required double startRadius,
    required double endRadius,
    required Color color,
    Uint8List? mask,
    required int antialiasLevel,
    bool includeStartCap = true,
    bool erase = false,
  }) {
    final double maxRadius = math.max(math.max(startRadius, endRadius), 0.0);
    if (maxRadius <= 0.0) {
      return;
    }
    final double ax = a.dx;
    final double ay = a.dy;
    final double bx = b.dx;
    final double by = b.dy;
    final double abx = bx - ax;
    final double aby = by - ay;
    final double lenSq = abx * abx + aby * aby;
    if (lenSq <= 1e-6) {
      drawCircle(
        center: a,
        radius: maxRadius,
        color: color,
        mask: mask,
        antialiasLevel: antialiasLevel,
        erase: erase,
      );
      return;
    }
    final double invLenSq = 1.0 / lenSq;
    final double feather = _featherForLevel(antialiasLevel);
    final double expand = maxRadius + feather + 1.5;
    final int minX = math.max(0, (math.min(ax, bx) - expand).floor());
    final int maxX = math.min(width - 1, (math.max(ax, bx) + expand).ceil());
    final int minY = math.max(0, (math.min(ay, by) - expand).floor());
    final int maxY = math.min(height - 1, (math.max(ay, by) + expand).ceil());
    if (minX > maxX || minY > maxY) {
      return;
    }
    final bool variableRadius = (startRadius - endRadius).abs() > 1e-6;
    final double radiusDelta = endRadius - startRadius;
    final int baseAlpha = color.alpha;
    final int baseColor = color.toARGB32();
    final int baseRgb = baseColor & 0x00FFFFFF;
    for (int y = minY; y <= maxY; y++) {
      final double py = y + 0.5;
      final int rowIndex = y * width;
      for (int x = minX; x <= maxX; x++) {
        if (mask != null && mask[rowIndex + x] == 0) {
          continue;
        }
        final double px = x + 0.5;
        final _CapsuleCoverageSample centerSample = _capsuleCoverageSample(
          px: px,
          py: py,
          ax: ax,
          ay: ay,
          abx: abx,
          aby: aby,
          invLenSq: invLenSq,
          includeStartCap: includeStartCap,
          variableRadius: variableRadius,
          startRadius: startRadius,
          radiusDelta: radiusDelta,
          feather: feather,
          antialiasLevel: antialiasLevel,
        );
        double coverage = centerSample.coverage;
        if (coverage <= 0.0) {
          continue;
        }
        if (_needsSupersampling(centerSample.radius, antialiasLevel)) {
          coverage = _supersampleCapsuleCoverage(
            px: px,
            py: py,
            ax: ax,
            ay: ay,
            abx: abx,
            aby: aby,
            invLenSq: invLenSq,
            includeStartCap: includeStartCap,
            variableRadius: variableRadius,
            startRadius: startRadius,
            radiusDelta: radiusDelta,
            feather: feather,
            antialiasLevel: antialiasLevel,
            supersample: _supersampleFactor(centerSample.radius),
          );
          if (coverage <= 0.0) {
            continue;
          }
        }
        if (coverage >= 0.999) {
          _blendPixelWithArgb(x, y, baseColor, erase: erase);
          continue;
        }
        final int adjustedAlpha = (baseAlpha * coverage).round().clamp(0, 255);
        if (adjustedAlpha == 0) {
          continue;
        }
        final int encoded = (adjustedAlpha << 24) | baseRgb;
        _blendPixelWithArgb(x, y, encoded, erase: erase);
      }
    }
  }

  /// Performs a flood fill starting at [start] with [color].
  /// When [targetColor] is provided it will be used as the expected
  /// original color; otherwise the pixel at [start] decides the target.
  /// If [contiguous] is false, the entire surface matching the target color
  /// will be filled.
  void floodFill({
    required Offset start,
    required Color color,
    Color? targetColor,
    bool contiguous = true,
    Uint8List? mask,
  }) {
    final int sx = start.dx.floor();
    final int sy = start.dy.floor();
    if (!_inBounds(sx, sy)) {
      return;
    }
    if (mask != null && mask[sy * width + sx] == 0) {
      return;
    }
    final int replacement = encodeColor(color);
    final int baseColor = targetColor != null
        ? encodeColor(targetColor)
        : pixels[sy * width + sx];
    if (replacement == baseColor) {
      return;
    }

    if (!contiguous) {
      for (int i = 0; i < pixels.length; i++) {
        if (pixels[i] == baseColor && (mask == null || mask[i] != 0)) {
          pixels[i] = replacement;
        }
      }
      return;
    }

    final Queue<math.Point<int>> queue = Queue<math.Point<int>>();
    queue.add(math.Point<int>(sx, sy));
    while (queue.isNotEmpty) {
      final math.Point<int> current = queue.removeFirst();
      final int x = current.x;
      final int y = current.y;
      if (!_inBounds(x, y)) {
        continue;
      }
      final int index = y * width + x;
      if (pixels[index] != baseColor) {
        continue;
      }
      if (mask != null && mask[index] == 0) {
        continue;
      }
      pixels[index] = replacement;
      if (replacement != 0) {
        _isClean = false;
      }

      queue.add(math.Point<int>(x + 1, y));
      queue.add(math.Point<int>(x - 1, y));
      queue.add(math.Point<int>(x, y + 1));
      queue.add(math.Point<int>(x, y - 1));
    }
  }

  bool _inBounds(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;

  double _computePixelCoverage({
    required double dx,
    required double dy,
    required double distance,
    required double radius,
    required double feather,
    required int antialiasLevel,
  }) {
    if (radius <= 0.0) {
      return 0.0;
    }
    if (_needsSupersampling(radius, antialiasLevel)) {
      return _supersampleCircleCoverage(
        dx: dx,
        dy: dy,
        radius: radius,
        feather: feather,
        antialiasLevel: antialiasLevel,
      );
    }
    if (antialiasLevel > 0 && radius <= _kSubpixelRadiusLimit) {
      return _projectedPixelCoverage(dx: dx, dy: dy, radius: radius);
    }
    return _radialCoverage(distance, radius, feather, antialiasLevel);
  }

  double _computeFeatheredCoverage({
    required double distance,
    required double radius,
    required double softness,
  }) {
    if (radius <= 0.0) {
      return 0.0;
    }
    final double clampedSoftness = softness.clamp(0.0, 1.0);
    if (clampedSoftness <= 0.0) {
      return distance <= radius ? 1.0 : 0.0;
    }
    final double innerRadius = radius * (1.0 - 0.45 * clampedSoftness);
    if (distance <= innerRadius) {
      return 1.0;
    }
    final double outerRadius = radius + radius * (0.65 + 1.2 * clampedSoftness);
    if (distance >= outerRadius) {
      return 0.0;
    }
    final double normalized =
        ((distance - innerRadius) / (outerRadius - innerRadius)).clamp(
          0.0,
          1.0,
        );
    final double eased = 1.0 - normalized;
    return math.pow(eased, 2.2).toDouble();
  }

  double _projectedPixelCoverage({
    required double dx,
    required double dy,
    required double radius,
  }) {
    final double absDx = dx.abs();
    final double absDy = dy.abs();
    if (absDx >= radius + _kHalfPixel || absDy >= radius + _kHalfPixel) {
      return 0.0;
    }
    if (absDx + radius <= _kHalfPixel && absDy + radius <= _kHalfPixel) {
      final double area = math.pi * radius * radius;
      return area >= 1.0 ? 1.0 : area;
    }
    final double cx = -dx;
    final double cy = -dy;
    final double minX = math.max(-_kHalfPixel, cx - radius);
    final double maxX = math.min(_kHalfPixel, cx + radius);
    if (minX >= maxX) {
      return 0.0;
    }
    final double width = maxX - minX;
    final int slices = _integrationSlicesForRadius(radius);
    double area = 0.0;
    for (int i = 0; i < slices; i++) {
      final double start = minX + width * (i / slices);
      final double end = minX + width * ((i + 1) / slices);
      final double mid = (start + end) * 0.5;
      final double span = _verticalIntersectionLength(mid, cx, cy, radius);
      if (span <= 0.0) {
        continue;
      }
      area += span * (end - start);
    }
    return area.clamp(0.0, 1.0);
  }

  int _integrationSlicesForRadius(double radius) {
    final double scaled = (radius * 32.0).clamp(
      _kMinIntegrationSlices.toDouble(),
      _kMaxIntegrationSlices.toDouble(),
    );
    return scaled.round().clamp(_kMinIntegrationSlices, _kMaxIntegrationSlices);
  }

  double _verticalIntersectionLength(
    double sampleX,
    double cx,
    double cy,
    double radius,
  ) {
    final double dx = sampleX - cx;
    final double radSq = radius * radius;
    final double remainder = radSq - dx * dx;
    if (remainder <= 0.0) {
      return 0.0;
    }
    final double chord = math.sqrt(remainder);
    final double low = math.max(-_kHalfPixel, cy - chord);
    final double high = math.min(_kHalfPixel, cy + chord);
    final double span = high - low;
    return span > 0.0 ? span : 0.0;
  }

  double _radialCoverage(
    double distance,
    double radius,
    double feather,
    int antialiasLevel,
  ) {
    if (radius <= 0.0) {
      return 0.0;
    }
    if (antialiasLevel <= 0 || feather <= 0.0) {
      return distance <= radius ? 1.0 : 0.0;
    }
    final double innerRadius = math.max(radius - feather, 0.0);
    final double outerRadius = radius + feather;
    if (distance <= innerRadius) {
      return 1.0;
    }
    if (distance >= outerRadius || outerRadius <= innerRadius) {
      return 0.0;
    }
    return (outerRadius - distance) / (outerRadius - innerRadius);
  }

  bool _needsSupersampling(double radius, int antialiasLevel) {
    if (antialiasLevel <= 0 || radius <= 0.0) {
      return false;
    }
    final double diameter = radius * 2.0;
    if (diameter < _kSupersampleFineDiameter) {
      return true;
    }
    return diameter < _kSupersampleDiameterThreshold;
  }

  int _supersampleFactor(double radius) {
    final double diameter = radius * 2.0;
    if (diameter < _kSupersampleFineDiameter) {
      return 6;
    }
    if (diameter < _kSupersampleDiameterThreshold) {
      return 3;
    }
    return 1;
  }

  double _supersampleCircleCoverage({
    required double dx,
    required double dy,
    required double radius,
    required double feather,
    required int antialiasLevel,
  }) {
    final int samples = _supersampleFactor(radius).clamp(1, 6);
    if (samples <= 1) {
      return _radialCoverage(
        math.sqrt(dx * dx + dy * dy),
        radius,
        feather,
        antialiasLevel,
      );
    }
    final double step = 1.0 / samples;
    final double start = -0.5 + step * 0.5;
    double accumulated = 0.0;
    for (int sy = 0; sy < samples; sy++) {
      final double offsetY = start + sy * step;
      for (int sx = 0; sx < samples; sx++) {
        final double offsetX = start + sx * step;
        final double sampleDx = dx + offsetX;
        final double sampleDy = dy + offsetY;
        final double distance = math.sqrt(
          sampleDx * sampleDx + sampleDy * sampleDy,
        );
        accumulated += _radialCoverage(
          distance,
          radius,
          feather,
          antialiasLevel,
        );
      }
    }
    final double inv = 1.0 / (samples * samples);
    return accumulated * inv;
  }

  double _supersampleCapsuleCoverage({
    required double px,
    required double py,
    required double ax,
    required double ay,
    required double abx,
    required double aby,
    required double invLenSq,
    required bool includeStartCap,
    required bool variableRadius,
    required double startRadius,
    required double radiusDelta,
    required double feather,
    required int antialiasLevel,
    required int supersample,
  }) {
    if (supersample <= 1) {
      return _capsuleCoverageSample(
        px: px,
        py: py,
        ax: ax,
        ay: ay,
        abx: abx,
        aby: aby,
        invLenSq: invLenSq,
        includeStartCap: includeStartCap,
        variableRadius: variableRadius,
        startRadius: startRadius,
        radiusDelta: radiusDelta,
        feather: feather,
        antialiasLevel: antialiasLevel,
      ).coverage;
    }
    final double step = 1.0 / supersample;
    final double start = -0.5 + step * 0.5;
    double accumulated = 0.0;
    for (int sy = 0; sy < supersample; sy++) {
      final double offsetY = start + sy * step;
      final double samplePy = py + offsetY;
      for (int sx = 0; sx < supersample; sx++) {
        final double offsetX = start + sx * step;
        final double samplePx = px + offsetX;
        accumulated += _capsuleCoverageSample(
          px: samplePx,
          py: samplePy,
          ax: ax,
          ay: ay,
          abx: abx,
          aby: aby,
          invLenSq: invLenSq,
          includeStartCap: includeStartCap,
          variableRadius: variableRadius,
          startRadius: startRadius,
          radiusDelta: radiusDelta,
          feather: feather,
          antialiasLevel: antialiasLevel,
        ).coverage;
      }
    }
    final double inv = 1.0 / (supersample * supersample);
    return accumulated * inv;
  }

  _CapsuleCoverageSample _capsuleCoverageSample({
    required double px,
    required double py,
    required double ax,
    required double ay,
    required double abx,
    required double aby,
    required double invLenSq,
    required bool includeStartCap,
    required bool variableRadius,
    required double startRadius,
    required double radiusDelta,
    required double feather,
    required int antialiasLevel,
  }) {
    final double rawT = ((px - ax) * abx + (py - ay) * aby) * invLenSq;
    double t = rawT;
    if (t < 0.0) {
      if (!includeStartCap && t < -1e-6) {
        return _CapsuleCoverageSample.zero;
      }
      t = 0.0;
    } else if (t > 1.0) {
      t = 1.0;
    }
    final double closestX = ax + abx * t;
    final double closestY = ay + aby * t;
    final double dxp = px - closestX;
    final double dyp = py - closestY;
    final double distance = math.sqrt(dxp * dxp + dyp * dyp);
    double radius = variableRadius
        ? startRadius + radiusDelta * t
        : startRadius;
    radius = radius.abs();
    if (radius == 0.0 && feather == 0.0) {
      return _CapsuleCoverageSample.zero;
    }
    final double coverage = _computePixelCoverage(
      dx: dxp,
      dy: dyp,
      distance: distance,
      radius: radius,
      feather: feather,
      antialiasLevel: antialiasLevel,
    );
    if (coverage <= 0.0) {
      return _CapsuleCoverageSample.zero;
    }
    return _CapsuleCoverageSample(coverage, radius);
  }

  void blendPixel(int x, int y, Color color, {bool erase = false}) {
    _blendPixelWithArgb(x, y, color.toARGB32(), erase: erase);
  }

  void _blendPixelWithArgb(int x, int y, int src, {bool erase = false}) {
    if (!_inBounds(x, y)) {
      return;
    }
    final int index = y * width + x;
    final int dst = pixels[index];

    final int srcA = (src >> 24) & 0xff;
    if (srcA == 0) {
      return;
    }
    final int srcR = (src >> 16) & 0xff;
    final int srcG = (src >> 8) & 0xff;
    final int srcB = src & 0xff;

    final int dstA = (dst >> 24) & 0xff;
    final int dstR = (dst >> 16) & 0xff;
    final int dstG = (dst >> 8) & 0xff;
    final int dstB = dst & 0xff;

    final double srcAlpha = srcA / 255.0;
    final double dstAlpha = dstA / 255.0;

    if (erase) {
      if (dstAlpha <= 0.0) {
        return;
      }
      final double eraseAmount = srcAlpha.clamp(0.0, 1.0);
      if (eraseAmount <= 0.0) {
        return;
      }
      final double remainingAlpha = dstAlpha * (1 - eraseAmount);
      if (remainingAlpha <= 0.0001) {
        pixels[index] = 0;
        return;
      }
      final double scale = remainingAlpha / dstAlpha;
      final int eraseA = (remainingAlpha * 255.0).round().clamp(0, 255);
      final int eraseR = (dstR * scale).round().clamp(0, 255);
      final int eraseG = (dstG * scale).round().clamp(0, 255);
      final int eraseB = (dstB * scale).round().clamp(0, 255);
      pixels[index] = (eraseA << 24) | (eraseR << 16) | (eraseG << 8) | eraseB;
      return;
    }

    final double outAlpha = srcAlpha + dstAlpha * (1 - srcAlpha);

    int outA;
    int outR;
    int outG;
    int outB;
    if (outAlpha == 0) {
      outA = outR = outG = outB = 0;
    } else {
      outA = (outAlpha * 255.0).round().clamp(0, 255);
      outR = ((srcR * srcAlpha + dstR * dstAlpha * (1 - srcAlpha)) / outAlpha)
          .round()
          .clamp(0, 255);
      outG = ((srcG * srcAlpha + dstG * dstAlpha * (1 - srcAlpha)) / outAlpha)
          .round()
          .clamp(0, 255);
      outB = ((srcB * srcAlpha + dstB * dstAlpha * (1 - srcAlpha)) / outAlpha)
          .round()
          .clamp(0, 255);
    }

    pixels[index] = (outA << 24) | (outR << 16) | (outG << 8) | outB;
    if (outA != 0) {
      _isClean = false;
    }
  }

  static int encodeColor(Color color) => color.toARGB32();

  static Color decodeColor(int value) {
    final int a = (value >> 24) & 0xff;
    final int r = (value >> 16) & 0xff;
    final int g = (value >> 8) & 0xff;
    final int b = value & 0xff;
    return Color.fromARGB(a, r, g, b);
  }
}

class _CapsuleCoverageSample {
  const _CapsuleCoverageSample(this.coverage, this.radius);

  final double coverage;
  final double radius;

  static const _CapsuleCoverageSample zero = _CapsuleCoverageSample(0.0, 0.0);
}

/// High-level helper that orchestrates bitmap painting actions.
class BitmapPainter {
  BitmapPainter(this.surface);

  final BitmapSurface surface;

  void drawStroke({
    required List<Offset> points,
    required double radius,
    required Color color,
  }) {
    surface.drawStroke(points: points, radius: radius, color: color);
  }

  void floodFill({
    required Offset start,
    required Color color,
    bool contiguous = true,
  }) {
    surface.floodFill(start: start, color: color, contiguous: contiguous);
  }
}

/// Lightweight bitmap layer container for future layer stacking.
class BitmapLayer {
  BitmapLayer({required this.surface, this.visible = true, this.name = '图层'});

  final BitmapSurface surface;
  bool visible;
  String name;
}

/// Simple document structure holding multiple bitmap layers.
class BitmapDocument {
  BitmapDocument({required List<BitmapLayer> layers})
    : layers = List<BitmapLayer>.from(layers);

  final List<BitmapLayer> layers;

  BitmapSurface composite() {
    if (layers.isEmpty) {
      throw StateError('No layers available to composite');
    }
    final BitmapSurface baseSurface = BitmapSurface(
      width: layers.first.surface.width,
      height: layers.first.surface.height,
    );
    for (final BitmapLayer layer in layers) {
      if (!layer.visible) {
        continue;
      }
      final Uint32List src = layer.surface.pixels;
      final Uint32List dst = baseSurface.pixels;
      for (int i = 0; i < dst.length; i++) {
        final int color = src[i];
        if ((color >> 24) == 0) {
          continue;
        }
        final int x = i % baseSurface.width;
        final int y = i ~/ baseSurface.width;
        baseSurface.blendPixel(x, y, BitmapSurface.decodeColor(color));
      }
    }
    return baseSurface;
  }
}
