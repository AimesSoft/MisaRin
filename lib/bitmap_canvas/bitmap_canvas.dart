import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../brushes/brush_shape_raster.dart';
import '../canvas/canvas_tools.dart';
import '../src/rust/rust_cpu_brush_ffi.dart';
import 'bitmap_blend_utils.dart' as blend_utils;
import 'memory/native_memory_manager.dart';
import 'soft_brush_profile.dart';

const double _kSubpixelRadiusLimit = 0.6;
const double _kHalfPixel = 0.5;
const double _kSupersampleDiameterThreshold = 10.0;
const double _kSupersampleFineDiameter = 1.0;
const int _kMinIntegrationSlices = 6;
const int _kMaxIntegrationSlices = 20;
const double _kInvSqrt2 = 0.7071067811865476;
const List<Offset> _kTriangleUnitVertices = <Offset>[
  Offset(0.0, -1.0),
  Offset(0.866025404, 0.5),
  Offset(-0.866025404, 0.5),
];
const List<Offset> _kStarUnitVertices = <Offset>[
  Offset(0.0, -1.0),
  Offset(0.224513988, -0.309016994),
  Offset(0.951056516, -0.309016994),
  Offset(0.363271264, 0.118033989),
  Offset(0.587785252, 0.809016994),
  Offset(0.0, 0.381966011),
  Offset(-0.587785252, 0.809016994),
  Offset(-0.363271264, 0.118033989),
  Offset(-0.951056516, -0.309016994),
  Offset(-0.224513988, -0.309016994),
];

/// A lightweight bitmap surface that stores pixels in ARGB8888 format.
///
/// Backed by a native pixel buffer; call [dispose] when no longer needed.
class BitmapSurface {
  static bool _loggedRustCpuBrushUnsupported = false;

  BitmapSurface({required this.width, required this.height, Color? fillColor}) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Surface dimensions must be positive');
    }

    _nativeBuffer = NativeMemoryManager.allocate(width * height);
    pixels = _nativeBuffer!.pixels;
    if (fillColor != null) {
      fill(fillColor);
    }
  }

  final int width;
  final int height;
  late final Uint32List pixels;
  PixelBufferHandle? _nativeBuffer;
  bool _isClean = true;

  int get pointerAddress => _nativeBuffer?.address ?? 0;

  void dispose() {
    _nativeBuffer?.dispose();
    _nativeBuffer = null;
  }

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
    bool screentoneEnabled = false,
    double screentoneSpacing = 10.0,
    double screentoneDotSize = 0.6,
    double screentoneRotation = 45.0,
    double screentoneSoftness = 0.0,
    BrushShape screentoneShape = BrushShape.circle,
  }) {
    if (radius <= 0) {
      return;
    }
    if (!_ensureRustCpuBrushSupported()) {
      return;
    }
    final bool ok = RustCpuBrushFfi.instance.drawStamp(
      pixelsPtr: pointerAddress,
      pixelsLen: pixels.length,
      width: width,
      height: height,
      centerX: center.dx,
      centerY: center.dy,
      radius: radius,
      colorArgb: color.toARGB32(),
      brushShape: BrushShape.circle.index,
      antialiasLevel: antialiasLevel.clamp(0, 9),
      softness: softness,
      erase: erase,
      randomRotation: false,
      smoothRotation: false,
      rotationSeed: 0,
      rotationJitter: 0.0,
      screentoneEnabled: screentoneEnabled,
      screentoneSpacing: screentoneSpacing,
      screentoneDotSize: screentoneDotSize,
      screentoneRotation: screentoneRotation,
      screentoneSoftness: screentoneSoftness,
      screentoneShape: screentoneShape.index,
      snapToPixel: false,
      selectionMask: mask,
    );
    if (ok) {
      _isClean = false;
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
    bool screentoneEnabled = false,
    double screentoneSpacing = 10.0,
    double screentoneDotSize = 0.6,
    double screentoneRotation = 45.0,
    double screentoneSoftness = 0.0,
    BrushShape screentoneShape = BrushShape.circle,
  }) {
    if (!_ensureRustCpuBrushSupported()) {
      return;
    }
    final bool ok = RustCpuBrushFfi.instance.drawCapsuleSegment(
      pixelsPtr: pointerAddress,
      pixelsLen: pixels.length,
      width: width,
      height: height,
      ax: a.dx,
      ay: a.dy,
      bx: b.dx,
      by: b.dy,
      startRadius: radius,
      endRadius: radius,
      colorArgb: color.toARGB32(),
      antialiasLevel: antialiasLevel.clamp(0, 9),
      includeStartCap: includeStartCap,
      erase: erase,
      screentoneEnabled: screentoneEnabled,
      screentoneSpacing: screentoneSpacing,
      screentoneDotSize: screentoneDotSize,
      screentoneRotation: screentoneRotation,
      screentoneSoftness: screentoneSoftness,
      screentoneShape: screentoneShape.index,
      selectionMask: mask,
    );
    if (ok) {
      _isClean = false;
    }
    return;
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
    bool screentoneEnabled = false,
    double screentoneSpacing = 10.0,
    double screentoneDotSize = 0.6,
    double screentoneRotation = 45.0,
    double screentoneSoftness = 0.0,
    BrushShape screentoneShape = BrushShape.circle,
  }) {
    if (!_ensureRustCpuBrushSupported()) {
      return;
    }
    final bool ok = RustCpuBrushFfi.instance.drawCapsuleSegment(
      pixelsPtr: pointerAddress,
      pixelsLen: pixels.length,
      width: width,
      height: height,
      ax: a.dx,
      ay: a.dy,
      bx: b.dx,
      by: b.dy,
      startRadius: startRadius,
      endRadius: endRadius,
      colorArgb: color.toARGB32(),
      antialiasLevel: antialiasLevel.clamp(0, 9),
      includeStartCap: includeStartCap,
      erase: erase,
      screentoneEnabled: screentoneEnabled,
      screentoneSpacing: screentoneSpacing,
      screentoneDotSize: screentoneDotSize,
      screentoneRotation: screentoneRotation,
      screentoneSoftness: screentoneSoftness,
      screentoneShape: screentoneShape.index,
      selectionMask: mask,
    );
    if (ok) {
      _isClean = false;
    }
    return;
  }

  /// Draws a stroke made of consecutive [points].
  void drawStroke({
    required List<Offset> points,
    required double radius,
    required Color color,
    Uint8List? mask,
    int antialiasLevel = 0,
    bool erase = false,
    bool screentoneEnabled = false,
    double screentoneSpacing = 10.0,
    double screentoneDotSize = 0.6,
    double screentoneRotation = 45.0,
    double screentoneSoftness = 0.0,
    BrushShape screentoneShape = BrushShape.circle,
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
        screentoneEnabled: screentoneEnabled,
        screentoneSpacing: screentoneSpacing,
        screentoneDotSize: screentoneDotSize,
        screentoneRotation: screentoneRotation,
        screentoneSoftness: screentoneSoftness,
        screentoneShape: screentoneShape,
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
        screentoneEnabled: screentoneEnabled,
        screentoneSpacing: screentoneSpacing,
        screentoneDotSize: screentoneDotSize,
        screentoneRotation: screentoneRotation,
        screentoneSoftness: screentoneSoftness,
        screentoneShape: screentoneShape,
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
    if (!_ensureRustCpuBrushSupported()) {
      return;
    }
    final Float32List packed = Float32List(sanitized.length * 2);
    for (int i = 0; i < sanitized.length; i++) {
      final Offset v = sanitized[i];
      packed[i * 2] = v.dx;
      packed[i * 2 + 1] = v.dy;
    }
    double minX = sanitized.first.dx;
    double maxX = sanitized.first.dx;
    double minY = sanitized.first.dy;
    double maxY = sanitized.first.dy;
    for (final Offset vertex in sanitized) {
      if (vertex.dx < minX) minX = vertex.dx;
      if (vertex.dx > maxX) maxX = vertex.dx;
      if (vertex.dy < minY) minY = vertex.dy;
      if (vertex.dy > maxY) maxY = vertex.dy;
    }
    if (minX.isNaN || maxX.isNaN || minY.isNaN || maxY.isNaN) {
      return;
    }
    final int level = antialiasLevel.clamp(0, 9);
    final double padding = _featherForLevel(level) + 1.5;
    final Rect bounds = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(padding);
    final double longestSide = math.max(
      bounds.width.abs(),
      bounds.height.abs(),
    );
    final double radius = math.max(longestSide * 0.5, 0.01);
    final bool ok = RustCpuBrushFfi.instance.fillPolygon(
      pixelsPtr: pointerAddress,
      pixelsLen: pixels.length,
      width: width,
      height: height,
      vertices: packed,
      radius: radius,
      colorArgb: color.toARGB32(),
      antialiasLevel: level,
      softness: 0.0,
      erase: erase,
      selectionMask: mask,
    );
    if (ok) {
      _isClean = false;
    }
    return;
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
    bool randomRotation = false,
    bool smoothRotation = false,
    int rotationSeed = 0,
    double rotationJitter = 1.0,
    bool snapToPixel = false,
    bool screentoneEnabled = false,
    double screentoneSpacing = 10.0,
    double screentoneDotSize = 0.6,
    double screentoneRotation = 45.0,
    double screentoneSoftness = 0.0,
    BrushShape screentoneShape = BrushShape.circle,
    Uint8List? customMask,
    int customMaskWidth = 0,
    int customMaskHeight = 0,
  }) {
    Offset resolvedCenter = center;
    double resolvedRadius = radius;
    if (snapToPixel) {
      resolvedCenter = Offset(
        resolvedCenter.dx.floorToDouble() + 0.5,
        resolvedCenter.dy.floorToDouble() + 0.5,
      );
      if (resolvedRadius.isFinite) {
        resolvedRadius = (resolvedRadius * 2.0).roundToDouble() / 2.0;
      }
    }
    if (!resolvedRadius.isFinite || resolvedRadius <= 0.0) {
      resolvedRadius = 0.01;
    }
    final int level = antialiasLevel.clamp(0, 9);
    if (!_ensureRustCpuBrushSupported()) {
      return;
    }
    final bool ok = RustCpuBrushFfi.instance.drawStamp(
      pixelsPtr: pointerAddress,
      pixelsLen: pixels.length,
      width: width,
      height: height,
      centerX: resolvedCenter.dx,
      centerY: resolvedCenter.dy,
      radius: resolvedRadius,
      colorArgb: color.toARGB32(),
      brushShape: shape.index,
      antialiasLevel: level,
      softness: softness,
      erase: erase,
      randomRotation: randomRotation,
      smoothRotation: smoothRotation,
      rotationSeed: rotationSeed,
      rotationJitter: rotationJitter,
      screentoneEnabled: screentoneEnabled,
      screentoneSpacing: screentoneSpacing,
      screentoneDotSize: screentoneDotSize,
      screentoneRotation: screentoneRotation,
      screentoneSoftness: screentoneSoftness,
      screentoneShape: screentoneShape.index,
      snapToPixel: snapToPixel,
      customMask: customMask,
      customMaskWidth: customMaskWidth,
      customMaskHeight: customMaskHeight,
      selectionMask: mask,
    );
    if (ok) {
      _isClean = false;
    }
    return;
  }

  void drawCustomBrushStamp({
    required BrushShapeRaster shape,
    required Offset center,
    required double radius,
    required Color color,
    required double rotation,
    Uint8List? mask,
    bool erase = false,
    double softness = 0.0,
    bool snapToPixel = false,
    int antialiasLevel = 0,
    bool screentoneEnabled = false,
    double screentoneSpacing = 10.0,
    double screentoneDotSize = 0.6,
    double screentoneRotation = 45.0,
    double screentoneSoftness = 0.0,
    BrushShape screentoneShape = BrushShape.circle,
  }) {
    Offset resolvedCenter = center;
    double resolvedRadius = radius;
    if (snapToPixel) {
      resolvedCenter = Offset(
        resolvedCenter.dx.floorToDouble() + 0.5,
        resolvedCenter.dy.floorToDouble() + 0.5,
      );
      if (resolvedRadius.isFinite) {
        resolvedRadius = (resolvedRadius * 2.0).roundToDouble() / 2.0;
      }
    }
    if (!resolvedRadius.isFinite || resolvedRadius <= 0.0) {
      return;
    }

    final double radiusValue = resolvedRadius.abs();
    final double shapeWidth = shape.width.toDouble();
    final double shapeHeight = shape.height.toDouble();
    final double maxShapeDim = math.max(shapeWidth, shapeHeight);
    if (maxShapeDim <= 0.0) {
      return;
    }
    // Preserve source tip aspect ratio: radius maps to the longer half-axis.
    final double halfWidth = radiusValue * (shapeWidth / maxShapeDim);
    final double halfHeight = radiusValue * (shapeHeight / maxShapeDim);
    final int left = (resolvedCenter.dx - halfWidth).floor();
    final int right = (resolvedCenter.dx + halfWidth).ceil();
    final int top = (resolvedCenter.dy - halfHeight).floor();
    final int bottom = (resolvedCenter.dy + halfHeight).ceil();
    if (right < 0 || bottom < 0 || left >= width || top >= height) {
      return;
    }

    final int startX = left.clamp(0, width - 1);
    final int endX = right.clamp(0, width - 1);
    final int startY = top.clamp(0, height - 1);
    final int endY = bottom.clamp(0, height - 1);

    final double softnessValue = softness.clamp(0.0, 1.0);
    final int aaLevel = antialiasLevel.clamp(0, 9);
    final double toneSpacing = screentoneSpacing.isFinite
        ? screentoneSpacing.clamp(2.0, 200.0)
        : 10.0;
    final double toneDotSize = screentoneDotSize.isFinite
        ? screentoneDotSize.clamp(0.0, 1.0)
        : 0.6;
    final double toneSoftness = screentoneSoftness.isFinite
        ? screentoneSoftness.clamp(0.0, 1.0)
        : 0.0;
    final double toneRadius = toneSpacing * 0.5 * toneDotSize;
    final double toneAngle =
        (screentoneRotation.isFinite ? screentoneRotation : 45.0).clamp(
          -180.0,
          180.0,
        ) *
        (math.pi / 180.0);
    final double toneSin = math.sin(toneAngle);
    final double toneCos = math.cos(toneAngle);
    final bool useScreentone = screentoneEnabled && toneRadius > 0.0;
    List<Offset>? toneVertices;
    if (useScreentone) {
      if (screentoneShape == BrushShape.triangle) {
        toneVertices = _scaleVertices(_kTriangleUnitVertices, toneRadius);
      } else if (screentoneShape == BrushShape.star) {
        toneVertices = _scaleVertices(_kStarUnitVertices, toneRadius);
      }
    }
    final double cosR = math.cos(rotation);
    final double sinR = math.sin(rotation);
    final double invHalfWidth = halfWidth <= 0.0 ? 0.0 : 1.0 / halfWidth;
    final double invHalfHeight = halfHeight <= 0.0 ? 0.0 : 1.0 / halfHeight;
    final int colorArgb = color.toARGB32();
    final int baseAlpha = (colorArgb >> 24) & 0xff;

    for (int y = startY; y <= endY; y++) {
      final int rowOffset = y * width;
      for (int x = startX; x <= endX; x++) {
        final int pixelIndex = rowOffset + x;
        if (mask != null && mask[pixelIndex] == 0) {
          continue;
        }
        final double dx = (x + 0.5) - resolvedCenter.dx;
        final double dy = (y + 0.5) - resolvedCenter.dy;
        final double rx = dx * cosR + dy * sinR;
        final double ry = -dx * sinR + dy * cosR;
        final double u = rx * invHalfWidth * 0.5 + 0.5;
        final double v = ry * invHalfHeight * 0.5 + 0.5;
        if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) {
          continue;
        }
        final double alphaBase = _sampleMask(
          shape.alpha,
          shape.width,
          shape.height,
          u,
          v,
        );
        if (alphaBase <= 0.0001) {
          continue;
        }
        double alpha = alphaBase;
        if (softnessValue > 0.0001) {
          final double alphaSoft = _sampleMask(
            shape.softAlpha,
            shape.width,
            shape.height,
            u,
            v,
          );
          alpha = alphaBase * (1.0 - softnessValue) + alphaSoft * softnessValue;
        }
        alpha = alpha.clamp(0.0, 1.0);
        if (useScreentone) {
          final double sampleX = x + 0.5;
          final double sampleY = y + 0.5;
          final double tone = _screentoneMaskAt(
            px: sampleX,
            py: sampleY,
            spacing: toneSpacing,
            dotRadius: toneRadius,
            rotSin: toneSin,
            rotCos: toneCos,
            softness: toneSoftness,
            shape: screentoneShape,
            antialiasLevel: aaLevel,
            polygonVertices: toneVertices,
          );
          if (tone <= 0.0001) {
            continue;
          }
          alpha *= tone;
        }
        if (alpha <= 0.0001) {
          continue;
        }
        if (erase) {
          final int dst = pixels[pixelIndex];
          final int dstA = (dst >> 24) & 0xff;
          final int outA = (dstA * (1.0 - alpha)).round().clamp(0, 255);
          pixels[pixelIndex] = (outA << 24) | (dst & 0x00ffffff);
        } else {
          final int srcA = (baseAlpha * alpha).round().clamp(0, 255);
          if (srcA <= 0) {
            continue;
          }
          final int src = (srcA << 24) | (colorArgb & 0x00ffffff);
          pixels[pixelIndex] = blend_utils.blendArgb(pixels[pixelIndex], src);
        }
      }
    }
    _isClean = false;
  }

  static double _sampleMask(
    Uint8List mask,
    int width,
    int height,
    double u,
    double v,
  ) {
    final double x = u * (width - 1);
    final double y = v * (height - 1);
    final int x0 = x.floor().clamp(0, width - 1);
    final int y0 = y.floor().clamp(0, height - 1);
    final int x1 = (x0 + 1).clamp(0, width - 1);
    final int y1 = (y0 + 1).clamp(0, height - 1);
    final double tx = x - x0;
    final double ty = y - y0;

    final int idx00 = y0 * width + x0;
    final int idx10 = y0 * width + x1;
    final int idx01 = y1 * width + x0;
    final int idx11 = y1 * width + x1;
    final double a00 = mask[idx00] / 255.0;
    final double a10 = mask[idx10] / 255.0;
    final double a01 = mask[idx01] / 255.0;
    final double a11 = mask[idx11] / 255.0;
    final double a0 = a00 + (a10 - a00) * tx;
    final double a1 = a01 + (a11 - a01) * tx;
    return a0 + (a1 - a0) * ty;
  }

  List<Offset> _scaleVertices(List<Offset> base, double scale) {
    return base
        .map((v) => Offset(v.dx * scale, v.dy * scale))
        .toList(growable: false);
  }

  double _signedDistanceBox(double px, double py, double halfSide) {
    final double dx = px.abs() - halfSide;
    final double dy = py.abs() - halfSide;
    final double ox = math.max(dx, 0.0);
    final double oy = math.max(dy, 0.0);
    final double outside = math.sqrt(ox * ox + oy * oy);
    final double inside = math.min(math.max(dx, dy), 0.0);
    return outside + inside;
  }

  double _screentoneMaskAt({
    required double px,
    required double py,
    required double spacing,
    required double dotRadius,
    required double rotSin,
    required double rotCos,
    required double softness,
    required BrushShape shape,
    required int antialiasLevel,
    List<Offset>? polygonVertices,
  }) {
    if (spacing <= 0.0 || dotRadius <= 0.0) {
      return 0.0;
    }
    final double rx = px * rotCos + py * rotSin;
    final double ry = -px * rotSin + py * rotCos;
    final double cellX = (rx / spacing).floorToDouble();
    final double cellY = (ry / spacing).floorToDouble();
    final double centerX = (cellX + 0.5) * spacing;
    final double centerY = (cellY + 0.5) * spacing;
    final double dx = rx - centerX;
    final double dy = ry - centerY;
    double dist;
    switch (shape) {
      case BrushShape.square:
        final double halfSide = dotRadius * _kInvSqrt2;
        dist = dotRadius + _signedDistanceBox(dx, dy, halfSide);
        break;
      case BrushShape.triangle:
        final List<Offset> verts =
            polygonVertices ??
            _scaleVertices(_kTriangleUnitVertices, dotRadius);
        dist = dotRadius + _signedDistanceToPolygon(dx, dy, verts);
        break;
      case BrushShape.star:
        final List<Offset> verts =
            polygonVertices ?? _scaleVertices(_kStarUnitVertices, dotRadius);
        dist = dotRadius + _signedDistanceToPolygon(dx, dy, verts);
        break;
      case BrushShape.circle:
        dist = math.sqrt(dx * dx + dy * dy);
        break;
    }
    final double aaFeather = _featherForLevel(antialiasLevel);
    final double edge = math.max(
      aaFeather,
      dotRadius * softness.clamp(0.0, 1.0),
    );
    if (edge <= 0.0) {
      return dist <= dotRadius ? 1.0 : 0.0;
    }
    final double inner = math.max(dotRadius - edge, 0.0);
    final double outer = dotRadius + edge;
    if (dist <= inner) {
      return 1.0;
    }
    if (dist >= outer) {
      return 0.0;
    }
    return (outer - dist) / (outer - inner);
  }

  static bool _ensureRustCpuBrushSupported() {
    if (RustCpuBrushFfi.instance.isSupported) {
      return true;
    }
    if (!_loggedRustCpuBrushUnsupported) {
      _loggedRustCpuBrushUnsupported = true;
      print(
        'RustCpuBrushFfi unsupported: rustCpu brush symbols not available '
        '(library missing or failed to load).',
      );
    }
    return false;
  }

  List<Offset> _rotateVertices(
    List<Offset> vertices,
    Offset center,
    double radians,
  ) {
    if (vertices.isEmpty || radians == 0.0) {
      return vertices;
    }
    final double sinR = math.sin(radians);
    final double cosR = math.cos(radians);
    return vertices
        .map((v) {
          final double dx = v.dx - center.dx;
          final double dy = v.dy - center.dy;
          return Offset(
            center.dx + dx * cosR - dy * sinR,
            center.dy + dx * sinR + dy * cosR,
          );
        })
        .toList(growable: false);
  }

  double _featherForLevel(int level) {
    const List<double> feather = <double>[
      0.0,
      0.7,
      1.1,
      1.6,
      1.9,
      2.2,
      2.5,
      2.8,
      3.1,
      3.4,
    ];
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
    double softness = 0.0,
    bool erase = false,
  }) {
    if (vertices.length < 3) {
      return;
    }
    final double baseFeather = _featherForLevel(antialiasLevel);
    final double soft = softness.clamp(0.0, 1.0);
    final double softnessFeather = radius * soft;
    final double feather = antialiasLevel > 0
        ? math.max(baseFeather, softnessFeather)
        : softnessFeather;
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
    int fillGap = 0,
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

    final int clampedFillGap = fillGap.clamp(0, 64);
    if (clampedFillGap > 0) {
      final Uint8List targetMask = Uint8List(width * height);
      for (int i = 0; i < pixels.length; i++) {
        if (mask != null && mask[i] == 0) {
          continue;
        }
        if (pixels[i] == baseColor) {
          targetMask[i] = 1;
        }
      }

      final int startIndex = sy * width + sx;
      if (targetMask[startIndex] == 0) {
        return;
      }

      final List<int> borderSeedsOriginal = <int>[];
      for (int x = 0; x < width; x++) {
        final int topIndex = x;
        if (topIndex < targetMask.length && targetMask[topIndex] == 1) {
          borderSeedsOriginal.add(topIndex);
        }
        final int bottomIndex = (height - 1) * width + x;
        if (bottomIndex >= 0 &&
            bottomIndex < targetMask.length &&
            targetMask[bottomIndex] == 1) {
          borderSeedsOriginal.add(bottomIndex);
        }
      }
      for (int y = 1; y < height - 1; y++) {
        final int leftIndex = y * width;
        if (leftIndex < targetMask.length && targetMask[leftIndex] == 1) {
          borderSeedsOriginal.add(leftIndex);
        }
        final int rightIndex = y * width + (width - 1);
        if (rightIndex >= 0 &&
            rightIndex < targetMask.length &&
            targetMask[rightIndex] == 1) {
          borderSeedsOriginal.add(rightIndex);
        }
      }

      Uint8List openMask8(Uint8List mask, int radius) {
        if (radius <= 0) {
          return mask;
        }
        final Uint8List buffer = Uint8List(mask.length);
        final List<int> queue = <int>[];

        void dilateFromMaskValue(
          Uint8List source,
          Uint8List out,
          int seedValue,
        ) {
          queue.clear();
          out.fillRange(0, out.length, 0);
          for (int i = 0; i < source.length; i++) {
            if (source[i] != seedValue) {
              continue;
            }
            out[i] = 1;
            queue.add(i);
          }
          if (queue.isEmpty) {
            return;
          }

          int head = 0;
          final int lastRowStart = (height - 1) * width;
          for (int step = 0; step < radius; step++) {
            final int levelEnd = queue.length;
            while (head < levelEnd) {
              final int index = queue[head++];
              final int x = index % width;
              final bool hasLeft = x > 0;
              final bool hasRight = x < width - 1;
              final bool hasUp = index >= width;
              final bool hasDown = index < lastRowStart;

              void tryAdd(int neighbor) {
                if (neighbor < 0 || neighbor >= out.length) {
                  return;
                }
                if (out[neighbor] != 0) {
                  return;
                }
                out[neighbor] = 1;
                queue.add(neighbor);
              }

              if (hasLeft) {
                tryAdd(index - 1);
              }
              if (hasRight) {
                tryAdd(index + 1);
              }
              if (hasUp) {
                tryAdd(index - width);
                if (hasLeft) {
                  tryAdd(index - width - 1);
                }
                if (hasRight) {
                  tryAdd(index - width + 1);
                }
              }
              if (hasDown) {
                tryAdd(index + width);
                if (hasLeft) {
                  tryAdd(index + width - 1);
                }
                if (hasRight) {
                  tryAdd(index + width + 1);
                }
              }
            }
          }
        }

        // Phase 1 (Erosion): erode by dilating the inverse and then inverting.
        dilateFromMaskValue(mask, buffer, 0);
        for (int i = 0; i < mask.length; i++) {
          mask[i] = buffer[i] == 0 ? 1 : 0;
        }

        // Phase 2 (Dilation): dilate eroded mask.
        dilateFromMaskValue(mask, buffer, 1);
        return buffer;
      }

      int? findNearestFillableStartIndex(Uint8List fillableMask) {
        if (fillableMask[startIndex] == 1) {
          return startIndex;
        }
        final Set<int> visited = <int>{startIndex};
        final List<int> queue = <int>[startIndex];
        int head = 0;
        final int maxDepth = clampedFillGap + 1;
        for (int depth = 0; depth <= maxDepth; depth++) {
          final int levelEnd = queue.length;
          while (head < levelEnd) {
            final int index = queue[head++];
            if (fillableMask[index] == 1) {
              return index;
            }
            final int x = index % width;
            final int y = index ~/ width;

            void tryNeighbor(int nx, int ny) {
              if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
                return;
              }
              final int neighbor = ny * width + nx;
              if (!visited.add(neighbor)) {
                return;
              }
              if (mask != null && mask[neighbor] == 0) {
                return;
              }
              if (pixels[neighbor] != baseColor) {
                return;
              }
              queue.add(neighbor);
            }

            tryNeighbor(x - 1, y);
            tryNeighbor(x + 1, y);
            tryNeighbor(x, y - 1);
            tryNeighbor(x, y + 1);
          }
          if (head >= queue.length) {
            break;
          }
        }
        return null;
      }

      // "Fill gap" should only prevent leaking through small openings.
      // Using the opened mask directly can delete thin enclosed regions (e.g. narrow curved bands),
      // so we:
      // 1) Compute an opened mask to sever narrow leak paths,
      // 2) Find the "outside" region on the opened mask (border-connected),
      // 3) Reconstruct the fill inside the original target mask while forbidding entry into "outside".
      final Uint8List openedTarget = openMask8(
        Uint8List.fromList(targetMask),
        clampedFillGap,
      );

      final List<int> outsideSeeds = <int>[];
      for (int x = 0; x < width; x++) {
        final int topIndex = x;
        if (topIndex < openedTarget.length && openedTarget[topIndex] == 1) {
          outsideSeeds.add(topIndex);
        }
        final int bottomIndex = (height - 1) * width + x;
        if (bottomIndex >= 0 &&
            bottomIndex < openedTarget.length &&
            openedTarget[bottomIndex] == 1) {
          outsideSeeds.add(bottomIndex);
        }
      }
      for (int y = 1; y < height - 1; y++) {
        final int leftIndex = y * width;
        if (leftIndex < openedTarget.length && openedTarget[leftIndex] == 1) {
          outsideSeeds.add(leftIndex);
        }
        final int rightIndex = y * width + (width - 1);
        if (rightIndex >= 0 &&
            rightIndex < openedTarget.length &&
            openedTarget[rightIndex] == 1) {
          outsideSeeds.add(rightIndex);
        }
      }

      void fillFromTargetMask(int seedIndex) {
        final List<int> stack = <int>[seedIndex];
        while (stack.isNotEmpty) {
          final int index = stack.removeLast();
          if (index < 0 || index >= targetMask.length) {
            continue;
          }
          if (targetMask[index] == 0) {
            continue;
          }
          targetMask[index] = 0;
          pixels[index] = replacement;
          if (replacement != 0) {
            _isClean = false;
          }
          final int x = index % width;
          final int y = index ~/ width;
          if (x > 0) {
            final int neighbor = index - 1;
            if (targetMask[neighbor] == 1) {
              stack.add(neighbor);
            }
          }
          if (x < width - 1) {
            final int neighbor = index + 1;
            if (targetMask[neighbor] == 1) {
              stack.add(neighbor);
            }
          }
          if (y > 0) {
            final int neighbor = index - width;
            if (targetMask[neighbor] == 1) {
              stack.add(neighbor);
            }
          }
          if (y < height - 1) {
            final int neighbor = index + width;
            if (targetMask[neighbor] == 1) {
              stack.add(neighbor);
            }
          }
        }
      }

      if (outsideSeeds.isEmpty) {
        if (borderSeedsOriginal.isEmpty) {
          fillFromTargetMask(startIndex);
          return;
        }

        final int? snappedStart = findNearestFillableStartIndex(openedTarget);
        if (snappedStart == null) {
          fillFromTargetMask(startIndex);
          return;
        }

        final List<int> stack = <int>[snappedStart];
        while (stack.isNotEmpty) {
          final int index = stack.removeLast();
          if (index < 0 || index >= openedTarget.length) {
            continue;
          }
          if (openedTarget[index] == 0) {
            continue;
          }
          openedTarget[index] = 0;
          if (targetMask[index] == 0) {
            continue;
          }
          targetMask[index] = 0;
          pixels[index] = replacement;
          if (replacement != 0) {
            _isClean = false;
          }
          final int x = index % width;
          final int y = index ~/ width;
          if (x > 0) {
            final int neighbor = index - 1;
            if (openedTarget[neighbor] == 1) {
              stack.add(neighbor);
            }
          }
          if (x < width - 1) {
            final int neighbor = index + 1;
            if (openedTarget[neighbor] == 1) {
              stack.add(neighbor);
            }
          }
          if (y > 0) {
            final int neighbor = index - width;
            if (openedTarget[neighbor] == 1) {
              stack.add(neighbor);
            }
          }
          if (y < height - 1) {
            final int neighbor = index + width;
            if (openedTarget[neighbor] == 1) {
              stack.add(neighbor);
            }
          }
        }
        return;
      }

      final Uint8List outsideOpen = Uint8List(openedTarget.length);
      final List<int> outsideQueue = List<int>.from(outsideSeeds);
      int outsideHead = 0;
      for (final int seed in outsideSeeds) {
        outsideOpen[seed] = 1;
      }
      while (outsideHead < outsideQueue.length) {
        final int index = outsideQueue[outsideHead++];
        final int x = index % width;
        final int y = index ~/ width;
        if (x > 0) {
          final int neighbor = index - 1;
          if (outsideOpen[neighbor] == 0 && openedTarget[neighbor] == 1) {
            outsideOpen[neighbor] = 1;
            outsideQueue.add(neighbor);
          }
        }
        if (x < width - 1) {
          final int neighbor = index + 1;
          if (outsideOpen[neighbor] == 0 && openedTarget[neighbor] == 1) {
            outsideOpen[neighbor] = 1;
            outsideQueue.add(neighbor);
          }
        }
        if (y > 0) {
          final int neighbor = index - width;
          if (outsideOpen[neighbor] == 0 && openedTarget[neighbor] == 1) {
            outsideOpen[neighbor] = 1;
            outsideQueue.add(neighbor);
          }
        }
        if (y < height - 1) {
          final int neighbor = index + width;
          if (outsideOpen[neighbor] == 0 && openedTarget[neighbor] == 1) {
            outsideOpen[neighbor] = 1;
            outsideQueue.add(neighbor);
          }
        }
      }

      final int? snappedStart = findNearestFillableStartIndex(openedTarget);
      if (snappedStart == null) {
        fillFromTargetMask(startIndex);
        return;
      }

      final Uint8List seedVisited = Uint8List(openedTarget.length);
      final List<int> seedQueue = <int>[snappedStart];
      seedVisited[snappedStart] = 1;
      int seedHead = 0;
      bool touchesOutside = outsideOpen[snappedStart] == 1;

      while (seedHead < seedQueue.length) {
        final int index = seedQueue[seedHead++];
        if (outsideOpen[index] == 1) {
          touchesOutside = true;
          break;
        }
        final int x = index % width;
        final int y = index ~/ width;
        if (x > 0) {
          final int neighbor = index - 1;
          if (seedVisited[neighbor] == 0 && openedTarget[neighbor] == 1) {
            seedVisited[neighbor] = 1;
            seedQueue.add(neighbor);
          }
        }
        if (x < width - 1) {
          final int neighbor = index + 1;
          if (seedVisited[neighbor] == 0 && openedTarget[neighbor] == 1) {
            seedVisited[neighbor] = 1;
            seedQueue.add(neighbor);
          }
        }
        if (y > 0) {
          final int neighbor = index - width;
          if (seedVisited[neighbor] == 0 && openedTarget[neighbor] == 1) {
            seedVisited[neighbor] = 1;
            seedQueue.add(neighbor);
          }
        }
        if (y < height - 1) {
          final int neighbor = index + width;
          if (seedVisited[neighbor] == 0 && openedTarget[neighbor] == 1) {
            seedVisited[neighbor] = 1;
            seedQueue.add(neighbor);
          }
        }
      }

      if (touchesOutside) {
        fillFromTargetMask(startIndex);
        return;
      }

      final List<int> queue = List<int>.from(seedQueue);
      int head = 0;
      for (final int index in queue) {
        if (targetMask[index] == 1 && outsideOpen[index] == 0) {
          targetMask[index] = 0;
          pixels[index] = replacement;
          if (replacement != 0) {
            _isClean = false;
          }
        }
      }
      while (head < queue.length) {
        final int index = queue[head++];
        final int x = index % width;
        final int y = index ~/ width;
        if (x > 0) {
          final int neighbor = index - 1;
          if (targetMask[neighbor] == 1 && outsideOpen[neighbor] == 0) {
            targetMask[neighbor] = 0;
            pixels[neighbor] = replacement;
            if (replacement != 0) {
              _isClean = false;
            }
            queue.add(neighbor);
          }
        }
        if (x < width - 1) {
          final int neighbor = index + 1;
          if (targetMask[neighbor] == 1 && outsideOpen[neighbor] == 0) {
            targetMask[neighbor] = 0;
            pixels[neighbor] = replacement;
            if (replacement != 0) {
              _isClean = false;
            }
            queue.add(neighbor);
          }
        }
        if (y > 0) {
          final int neighbor = index - width;
          if (targetMask[neighbor] == 1 && outsideOpen[neighbor] == 0) {
            targetMask[neighbor] = 0;
            pixels[neighbor] = replacement;
            if (replacement != 0) {
              _isClean = false;
            }
            queue.add(neighbor);
          }
        }
        if (y < height - 1) {
          final int neighbor = index + width;
          if (targetMask[neighbor] == 1 && outsideOpen[neighbor] == 0) {
            targetMask[neighbor] = 0;
            pixels[neighbor] = replacement;
            if (replacement != 0) {
              _isClean = false;
            }
            queue.add(neighbor);
          }
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
    final double innerRadius =
        radius * softBrushInnerRadiusFraction(clampedSoftness);
    if (distance <= innerRadius) {
      return 1.0;
    }
    final double outerRadius =
        radius + radius * softBrushExtentMultiplier(clampedSoftness);
    if (distance >= outerRadius) {
      return 0.0;
    }
    final double normalized =
        ((distance - innerRadius) / (outerRadius - innerRadius)).clamp(
          0.0,
          1.0,
        );
    final double eased = 1.0 - normalized;
    return math
        .pow(eased, softBrushFalloffExponent(clampedSoftness))
        .toDouble();
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

    if (erase) {
      if (dstA == 0) {
        return;
      }
      // srcA acts as erase amount (0..255)
      // remaining = dstA * (1 - srcA/255)
      //           = dstA * (255 - srcA) / 255
      final int invSrcA = 255 - srcA;
      // Approximation: (a * b) / 255 ~= (a * b * 257) >> 16
      final int remainingAlpha = (dstA * invSrcA * 257) >> 16;

      if (remainingAlpha == 0) {
        pixels[index] = 0;
        _isClean = false;
        return;
      }

      // Preserve original behavior: scale RGB by the same factor as Alpha
      // Original: scale = remainingAlpha / dstAlpha = (dstA * invSrcA / 255) / dstA = invSrcA / 255

      final int outR = (dstR * invSrcA * 257) >> 16;
      final int outG = (dstG * invSrcA * 257) >> 16;
      final int outB = (dstB * invSrcA * 257) >> 16;

      pixels[index] =
          (remainingAlpha << 24) | (outR << 16) | (outG << 8) | outB;
      _isClean = false;
      return;
    }

    // Normal Blend (Src over Dst)
    // outA = srcA + dstA * (1 - srcA/255)
    final int invSrcA = 255 - srcA;
    final int dstWeightedA = (dstA * invSrcA * 257) >> 16;
    final int outA = srcA + dstWeightedA;

    if (outA == 0) {
      pixels[index] = 0;
      return;
    }

    // outC = (srcC * srcA + dstC * dstWeightedA) / outA
    // We perform the division at the end.
    final int outR = (srcR * srcA + dstR * dstWeightedA) ~/ outA;
    final int outG = (srcG * srcA + dstG * dstWeightedA) ~/ outA;
    final int outB = (srcB * srcA + dstB * dstWeightedA) ~/ outA;

    pixels[index] =
        (outA << 24) |
        (outR.clamp(0, 255) << 16) |
        (outG.clamp(0, 255) << 8) |
        outB.clamp(0, 255);
    _isClean = false;
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
