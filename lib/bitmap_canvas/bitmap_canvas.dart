import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

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

  /// Clears the entire surface with [color].
  void fill(Color color) {
    final int encoded = encodeColor(color);
    for (int i = 0; i < pixels.length; i++) {
      pixels[i] = encoded;
    }
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
  }) {
    _drawCircleInternal(
      center: center,
      radius: radius,
      color: color,
      mask: mask,
      antialiasLevel: antialiasLevel.clamp(0, 3),
    );
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
    );
  }

  /// Fills a convex strip defined by [polygon] points in winding order.
  void fillStrip({
    required Iterable<Offset> polygon,
    required Color color,
    Uint8List? mask,
    int antialiasLevel = 0,
  }) {
    final List<Offset> points = List<Offset>.from(polygon);
    if (points.length < 3) {
      return;
    }
    _fillConvexPolygon(
      points: points,
      color: color,
      mask: mask,
      antialiasLevel: antialiasLevel.clamp(0, 3),
    );
  }

  /// Fills a circular cap, sharing the same implementation as [drawCircle].
  void fillCap({
    required Offset center,
    required double radius,
    required Color color,
    Uint8List? mask,
    int antialiasLevel = 0,
  }) {
    _drawCircleInternal(
      center: center,
      radius: radius,
      color: color,
      mask: mask,
      antialiasLevel: antialiasLevel.clamp(0, 3),
    );
  }

  /// Draws a stroke made of consecutive [points].
  void drawStroke({
    required List<Offset> points,
    required double radius,
    required Color color,
    Uint8List? mask,
    int antialiasLevel = 0,
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
      );
      includeStartCap = false;
    }
  }

  void _drawCircleInternal({
    required Offset center,
    required double radius,
    required Color color,
    Uint8List? mask,
    required int antialiasLevel,
  }) {
    if (radius <= 0) {
      return;
    }
    final int minX = math.max(0, (center.dx - radius - 1).floor());
    final int maxX = math.min(width - 1, (center.dx + radius + 1).ceil());
    final int minY = math.max(0, (center.dy - radius - 1).floor());
    final int maxY = math.min(height - 1, (center.dy + radius + 1).ceil());
    final double radiusSq = radius * radius;

    for (int y = minY; y <= maxY; y++) {
      final double dy = y + 0.5 - center.dy;
      final int rowIndex = y * width;
      for (int x = minX; x <= maxX; x++) {
        if (mask != null && mask[rowIndex + x] == 0) {
          continue;
        }
        final double dx = x + 0.5 - center.dx;
        final double distanceSq = dx * dx + dy * dy;
        if (antialiasLevel == 0) {
          if (distanceSq <= radiusSq) {
            blendPixel(x, y, color);
          }
          continue;
        }
        final double distance = math.sqrt(distanceSq);
        final double feather = _featherForLevel(antialiasLevel);
        final double innerRadius = math.max(radius - feather, 0.0);
        final double outerRadius = radius + feather;
        double coverage;
        if (distance <= innerRadius) {
          coverage = 1.0;
        } else if (distance >= outerRadius || outerRadius <= innerRadius) {
          coverage = 0.0;
        } else {
          coverage = (outerRadius - distance) / (outerRadius - innerRadius);
        }
        if (coverage <= 0.0) {
          continue;
        }
        if (coverage >= 0.999) {
          blendPixel(x, y, color);
        } else {
          final int baseAlpha = color.alpha;
          final int adjustedAlpha = (baseAlpha * coverage).round().clamp(
            0,
            255,
          );
          if (adjustedAlpha == 0) {
            continue;
          }
          blendPixel(x, y, color.withAlpha(adjustedAlpha));
        }
      }
    }
  }

  void _fillConvexPolygon({
    required List<Offset> points,
    required Color color,
    Uint8List? mask,
    required int antialiasLevel,
  }) {
    final List<_PolygonEdge> edges = _buildPolygonEdges(points);
    if (edges.length < 3) {
      return;
    }
    double minX = points.first.dx;
    double maxX = points.first.dx;
    double minY = points.first.dy;
    double maxY = points.first.dy;
    for (int i = 1; i < points.length; i++) {
      final Offset p = points[i];
      if (p.dx < minX) {
        minX = p.dx;
      }
      if (p.dx > maxX) {
        maxX = p.dx;
      }
      if (p.dy < minY) {
        minY = p.dy;
      }
      if (p.dy > maxY) {
        maxY = p.dy;
      }
    }
    final double feather = _featherForLevel(antialiasLevel);
    final double expand = feather + 1.5;
    final int minXi = math.max(0, (minX - expand).floor());
    final int maxXi = math.min(width - 1, (maxX + expand).ceil());
    final int minYi = math.max(0, (minY - expand).floor());
    final int maxYi = math.min(height - 1, (maxY + expand).ceil());
    final int baseAlpha = color.alpha;
    for (int y = minYi; y <= maxYi; y++) {
      final double py = y + 0.5;
      final int rowIndex = y * width;
      for (int x = minXi; x <= maxXi; x++) {
        if (mask != null && mask[rowIndex + x] == 0) {
          continue;
        }
        final double px = x + 0.5;
        double minDistance = double.infinity;
        bool inside = true;
        for (final _PolygonEdge edge in edges) {
          final double d = edge.signedDistance(px, py);
          if (d < 0) {
            inside = false;
            break;
          }
          if (d < minDistance) {
            minDistance = d;
          }
        }
        if (!inside) {
          continue;
        }
        double coverage = 1.0;
        if (antialiasLevel > 0 && feather > 0) {
          coverage = (minDistance / feather).clamp(0.0, 1.0);
        }
        if (coverage >= 0.999) {
          blendPixel(x, y, color);
        } else {
          final int adjustedAlpha = (baseAlpha * coverage).round().clamp(
            0,
            255,
          );
          if (adjustedAlpha == 0) {
            continue;
          }
          blendPixel(x, y, color.withAlpha(adjustedAlpha));
        }
      }
    }
  }

  double _featherForLevel(int level) {
    const List<double> feather = <double>[0.0, 0.7, 1.1, 1.6];
    return feather[level.clamp(0, feather.length - 1)];
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
    for (int y = minY; y <= maxY; y++) {
      final double py = y + 0.5;
      final int rowIndex = y * width;
      for (int x = minX; x <= maxX; x++) {
        if (mask != null && mask[rowIndex + x] == 0) {
          continue;
        }
        final double px = x + 0.5;
        final double rawT = ((px - ax) * abx + (py - ay) * aby) * invLenSq;
        double t = rawT;
        if (t < 0.0) {
          if (!includeStartCap && t < -1e-6) {
            continue;
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
          continue;
        }
        double coverage;
        if (antialiasLevel == 0) {
          if (distance <= radius) {
            coverage = 1.0;
          } else {
            continue;
          }
        } else {
          final double innerRadius = math.max(radius - feather, 0.0);
          final double outerRadius = radius + feather;
          if (distance <= innerRadius) {
            coverage = 1.0;
          } else if (distance >= outerRadius || outerRadius <= innerRadius) {
            continue;
          } else {
            coverage = (outerRadius - distance) / (outerRadius - innerRadius);
          }
        }
        if (coverage >= 0.999) {
          blendPixel(x, y, color);
        } else {
          final int adjustedAlpha = (baseAlpha * coverage).round().clamp(
            0,
            255,
          );
          if (adjustedAlpha == 0) {
            continue;
          }
          blendPixel(x, y, color.withAlpha(adjustedAlpha));
        }
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

      queue.add(math.Point<int>(x + 1, y));
      queue.add(math.Point<int>(x - 1, y));
      queue.add(math.Point<int>(x, y + 1));
      queue.add(math.Point<int>(x, y - 1));
    }
  }

  bool _inBounds(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;

  void blendPixel(int x, int y, Color color) {
    if (!_inBounds(x, y)) {
      return;
    }
    final int index = y * width + x;
    final int dst = pixels[index];
    final int src = encodeColor(color);

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

List<_PolygonEdge> _buildPolygonEdges(List<Offset> points) {
  final List<_PolygonEdge> edges = <_PolygonEdge>[];
  if (points.length < 2) {
    return edges;
  }
  for (int i = 0; i < points.length; i++) {
    final Offset a = points[i];
    final Offset b = points[(i + 1) % points.length];
    final double nx = -(b.dy - a.dy);
    final double ny = b.dx - a.dx;
    final double length = math.sqrt(nx * nx + ny * ny);
    if (length <= 1e-6) {
      continue;
    }
    final double inv = 1.0 / length;
    final double nnx = nx * inv;
    final double nny = ny * inv;
    final double constant = -(nnx * a.dx + nny * a.dy);
    edges.add(_PolygonEdge(nnx, nny, constant));
  }
  return edges;
}

class _PolygonEdge {
  const _PolygonEdge(this.nx, this.ny, this.constant);

  final double nx;
  final double ny;
  final double constant;

  double signedDistance(double px, double py) => nx * px + ny * py + constant;
}
