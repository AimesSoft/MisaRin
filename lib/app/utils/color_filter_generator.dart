import 'dart:math' as math;

class ColorFilterGenerator {
  static List<double> hue(double value) {
    final double angle = (value * math.pi) / 180.0;
    final double cosVal = math.cos(angle);
    final double sinVal = math.sin(angle);
    final double lumR = 0.213;
    final double lumG = 0.715;
    final double lumB = 0.072;

    return <double>[
      lumR + cosVal * (1 - lumR) + sinVal * (-lumR),
      lumG + cosVal * (-lumG) + sinVal * (-lumG),
      lumB + cosVal * (-lumB) + sinVal * (1 - lumB),
      0,
      0,
      lumR + cosVal * (-lumR) + sinVal * 0.143,
      lumG + cosVal * (1 - lumG) + sinVal * 0.140,
      lumB + cosVal * (-lumB) + sinVal * (-0.283),
      0,
      0,
      lumR + cosVal * (-lumR) + sinVal * (-(1 - lumR)),
      lumG + cosVal * (-lumG) + sinVal * lumG,
      lumB + cosVal * (1 - lumB) + sinVal * lumB,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  static List<double> saturation(double value) {
    final double x = 1 + ((value > 0) ? 3 * value / 100 : value / 100);
    final double lumR = 0.3086;
    final double lumG = 0.6094;
    final double lumB = 0.0820;

    final double oneMinusSat = 1.0 - x;
    return <double>[
      (oneMinusSat * lumR) + x,
      oneMinusSat * lumG,
      oneMinusSat * lumB,
      0,
      0,
      oneMinusSat * lumR,
      (oneMinusSat * lumG) + x,
      oneMinusSat * lumB,
      0,
      0,
      oneMinusSat * lumR,
      oneMinusSat * lumG,
      (oneMinusSat * lumB) + x,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  static List<double> brightness(double value) {
    final double offset = value * 255 / 100; // Assuming value is -100 to 100
    return <double>[
      1,
      0,
      0,
      0,
      offset,
      0,
      1,
      0,
      0,
      offset,
      0,
      0,
      1,
      0,
      offset,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  static List<double> contrast(double value) {
    final double scale = value >= 0
        ? (1.0 + value / 100.0)
        : (1.0 + value / 200.0);
    // Using a simpler scale factor logic similar to standard implementations or user provided one.
    // User provided implementation:
    // brightnessOffset = brightnessPercent / 100.0 * 255.0;
    // contrastFactor = math.max(0.0, 1.0 + contrastPercent / 100.0);

    // Matrix implementation for contrast:
    final double t = (1.0 - scale) * 128.0;
    return <double>[
      scale,
      0,
      0,
      0,
      t,
      0,
      scale,
      0,
      0,
      t,
      0,
      0,
      scale,
      0,
      t,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  // For combining brightness and contrast which are often applied together in the user's logic
  // But since we have matrix multiplication, we can just multiply them or provide a specialized one.
  // User's logic: ((channel - 128) * contrastFactor + 128 + brightnessOffset)
  // = channel * contrastFactor - 128*contrastFactor + 128 + brightnessOffset
  // = channel * contrastFactor + (128 * (1 - contrastFactor) + brightnessOffset)
  static List<double> brightnessContrast(double brightness, double contrast) {
    final double brightnessOffset = brightness / 100.0 * 255.0;
    final double contrastFactor = math.max(0.0, 1.0 + contrast / 100.0);
    final double t = 128 * (1 - contrastFactor) + brightnessOffset;

    return <double>[
      contrastFactor,
      0,
      0,
      0,
      t,
      0,
      contrastFactor,
      0,
      0,
      t,
      0,
      0,
      contrastFactor,
      0,
      t,
      0,
      0,
      0,
      1,
      0,
    ];
  }
}
