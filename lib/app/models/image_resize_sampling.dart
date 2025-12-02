enum ImageResizeSampling { nearest, bilinear }

extension ImageResizeSamplingTexts on ImageResizeSampling {
  String get label {
    switch (this) {
      case ImageResizeSampling.nearest:
        return '最邻近';
      case ImageResizeSampling.bilinear:
        return '双线性';
    }
  }

  String get description {
    switch (this) {
      case ImageResizeSampling.nearest:
        return '保持像素边缘硬度，适合像素风或图案缩放。';
      case ImageResizeSampling.bilinear:
        return '对像素进行平滑插值，适合需要柔和过渡的缩放。';
    }
  }
}
