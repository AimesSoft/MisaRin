import 'dart:typed_data';

/// 对 RGBA8888 像素进行就地预乘，以满足 Flutter 对预乘 alpha 的要求。
void premultiplyRgbaInPlace(Uint8List pixels) {
  for (int i = 0; i < pixels.length; i += 4) {
    final int a = pixels[i + 3];
    if (a == 255) continue;
    if (a == 0) {
      pixels[i] = 0;
      pixels[i + 1] = 0;
      pixels[i + 2] = 0;
      continue;
    }
    // Fast approximation of (x * a) / 255: (x * a + 128) * 257 >> 16
    pixels[i] = (pixels[i] * a * 32897 + 8388608) >> 23;
    pixels[i + 1] = (pixels[i + 1] * a * 32897 + 8388608) >> 23;
    pixels[i + 2] = (pixels[i + 2] * a * 32897 + 8388608) >> 23;
  }
}

/// 对 BGRA8888 像素进行就地预乘（B,G,R,A），以满足 Flutter 对预乘 alpha 的要求。
void premultiplyBgraInPlace(Uint8List pixels) {
  for (int i = 0; i < pixels.length; i += 4) {
    final int a = pixels[i + 3];
    if (a == 255) continue;
    if (a == 0) {
      pixels[i] = 0;
      pixels[i + 1] = 0;
      pixels[i + 2] = 0;
      continue;
    }
    pixels[i] = (pixels[i] * a * 32897 + 8388608) >> 23;
    pixels[i + 1] = (pixels[i + 1] * a * 32897 + 8388608) >> 23;
    pixels[i + 2] = (pixels[i + 2] * a * 32897 + 8388608) >> 23;
  }
}

/// 将预乘 alpha 的 RGBA8888 像素还原为 straight alpha（未预乘）格式。
///
/// Flutter 的 `ui.Image.toByteData(format: rawRgba)` 返回的是预乘 alpha 的 RGBA，
/// 而本项目内部像素管线使用的是 straight alpha（RGB 未预乘）。
void unpremultiplyRgbaInPlace(Uint8List pixels) {
  for (int i = 0; i < pixels.length; i += 4) {
    final int alpha = pixels[i + 3];
    if (alpha == 0) {
      pixels[i] = 0;
      pixels[i + 1] = 0;
      pixels[i + 2] = 0;
      continue;
    }
    if (alpha == 255) {
      continue;
    }
    pixels[i] = ((pixels[i] * 255) + (alpha >> 1)) ~/ alpha;
    pixels[i + 1] = ((pixels[i + 1] * 255) + (alpha >> 1)) ~/ alpha;
    pixels[i + 2] = ((pixels[i + 2] * 255) + (alpha >> 1)) ~/ alpha;
  }
}

/// Convert ARGB8888 pixels (straight alpha) into premultiplied RGBA8888 bytes.
Uint8List argbToPremultipliedRgba(Uint32List pixels) {
  final Uint8List rgba = Uint8List(pixels.length * 4);
  int outIndex = 0;
  for (final int argb in pixels) {
    final int a = (argb >> 24) & 0xff;
    if (a == 255) {
      rgba[outIndex] = (argb >> 16) & 0xff;
      rgba[outIndex + 1] = (argb >> 8) & 0xff;
      rgba[outIndex + 2] = argb & 0xff;
      rgba[outIndex + 3] = 255;
    } else if (a == 0) {
      rgba[outIndex] = 0;
      rgba[outIndex + 1] = 0;
      rgba[outIndex + 2] = 0;
      rgba[outIndex + 3] = 0;
    } else {
      final int r = (argb >> 16) & 0xff;
      final int g = (argb >> 8) & 0xff;
      final int b = argb & 0xff;
      rgba[outIndex] = ((r * a + 127) ~/ 255);
      rgba[outIndex + 1] = ((g * a + 127) ~/ 255);
      rgba[outIndex + 2] = ((b * a + 127) ~/ 255);
      rgba[outIndex + 3] = a;
    }
    outIndex += 4;
  }
  return rgba;
}
