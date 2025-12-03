import 'dart:typed_data';

/// Immutable representation of a precomputed soft spray stamp.
class SoftSprayStamp {
  const SoftSprayStamp({
    required this.size,
    required this.alpha,
    required this.outerRadiusScale,
  });

  /// Side length of the square texture that stores alpha coverage.
  final int size;

  /// Row-major alpha channel (0-255) extracted from the GPU rendered stamp.
  final Uint8List alpha;

  /// Ratio between the logical brush radius and the rendered outer radius.
  final double outerRadiusScale;

  int _index(int x, int y) => y * size + x;

  /// Returns a normalized coverage by bilinearly sampling the alpha map.
  double sample(double x, double y) {
    if (x < 0 || y < 0 || x > size - 1 || y > size - 1) {
      return 0.0;
    }
    final int x0 = x.floor().clamp(0, size - 1);
    final int y0 = y.floor().clamp(0, size - 1);
    final int x1 = (x0 + 1).clamp(0, size - 1);
    final int y1 = (y0 + 1).clamp(0, size - 1);
    final double tx = x - x0;
    final double ty = y - y0;
    final double a00 = alpha[_index(x0, y0)].toDouble();
    final double a10 = alpha[_index(x1, y0)].toDouble();
    final double a01 = alpha[_index(x0, y1)].toDouble();
    final double a11 = alpha[_index(x1, y1)].toDouble();
    final double top = ui_lerpDouble(a00, a10, tx);
    final double bottom = ui_lerpDouble(a01, a11, tx);
    final double blended = ui_lerpDouble(top, bottom, ty);
    return (blended / 255.0).clamp(0.0, 1.0);
  }
}

double ui_lerpDouble(double a, double b, double t) => a + (b - a) * t;
