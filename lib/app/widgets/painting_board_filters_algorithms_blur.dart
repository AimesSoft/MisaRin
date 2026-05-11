part of 'painting_board.dart';

double _gaussianBlurSigmaForRadius(double radius) {
  final double clampedRadius = radius.clamp(0.0, _kGaussianBlurMaxRadius);
  if (clampedRadius <= 0) {
    return 0;
  }
  return math.max(0.1, clampedRadius * 0.5);
}

Future<Uint8List> _generateGaussianBlurPreviewBytes(List<Object?> args) async {
  final int width = (args[1] as num).toInt();
  final int height = (args[2] as num).toInt();
  if (width > 0 && height > 0 && width * height <= 65536) {
    return _computeGaussianBlurPreviewPixels(args);
  }
  try {
    return await compute<List<Object?>, Uint8List>(
      _computeGaussianBlurPreviewPixels,
      args,
    );
  } on UnsupportedError catch (_) {
    return _computeGaussianBlurPreviewPixels(args);
  }
}

Uint8List _computeGaussianBlurPreviewPixels(List<Object?> args) {
  final Uint8List source = args[0] as Uint8List;
  final int width = (args[1] as num).toInt();
  final int height = (args[2] as num).toInt();
  final double radius = (args[3] as num).toDouble();
  final Uint8List pixels = Uint8List.fromList(source);
  _filterApplyGaussianBlurToBitmap(pixels, width, height, radius);
  return pixels;
}

void _filterApplyGaussianBlurToBitmap(
  Uint8List bitmap,
  int width,
  int height,
  double radius,
) {
  if (bitmap.isEmpty || width <= 0 || height <= 0) {
    return;
  }
  final double sigma = _gaussianBlurSigmaForRadius(radius);
  if (sigma <= 0) {
    return;
  }
  // 使用预乘 alpha 防止在透明区域被卷积时产生黑边。
  _filterPremultiplyAlpha(bitmap);
  // Approximate a gaussian blur with three fast box blur passes so very large
  // radii (e.g. 1000px) stay responsive during preview.
  final List<int> boxSizes = _filterComputeBoxSizes(sigma, 3);
  final Uint8List scratch = Uint8List(bitmap.length);
  for (final int boxSize in boxSizes) {
    final int passRadius = math.max(0, (boxSize - 1) >> 1);
    if (passRadius <= 0) {
      continue;
    }
    _filterBoxBlurPass(
      source: bitmap,
      destination: scratch,
      width: width,
      height: height,
      radius: passRadius,
      horizontal: true,
    );
    _filterBoxBlurPass(
      source: scratch,
      destination: bitmap,
      width: width,
      height: height,
      radius: passRadius,
      horizontal: false,
    );
  }
  _filterUnpremultiplyAlpha(bitmap);
}

void _filterApplyMorphologyToBitmap(
  Uint8List bitmap,
  int width,
  int height,
  int radius, {
  required bool dilate,
}) {
  if (bitmap.isEmpty || width <= 0 || height <= 0) {
    return;
  }
  final int clampedRadius = radius
      .clamp(1, _kMorphologyMaxRadius.toInt())
      .toInt();
  final Uint8List? luminanceMask = _filterBuildLuminanceMaskIfFullyOpaque(
    bitmap,
    width,
    height,
  );
  final bool preserveAlpha = luminanceMask != null;
  final Uint8List scratch = Uint8List(bitmap.length);
  Uint8List src = bitmap;
  Uint8List dest = scratch;

  for (int iteration = 0; iteration < clampedRadius; iteration++) {
    for (int y = 0; y < height; y++) {
      final int rowOffset = y * width;
      for (int x = 0; x < width; x++) {
        final int pixelIndex = rowOffset + x;
        int bestOffset = (pixelIndex << 2);
        int bestAlpha = luminanceMask != null
            ? luminanceMask[pixelIndex]
            : src[bestOffset + 3];

        for (int dy = -1; dy <= 1; dy++) {
          final int ny = y + dy;
          if (ny < 0 || ny >= height) {
            continue;
          }
          final int neighborRow = ny * width;
          for (int dx = -1; dx <= 1; dx++) {
            final int nx = x + dx;
            if (nx < 0 || nx >= width) {
              continue;
            }
            final int neighborIndex = neighborRow + nx;
            final int neighborOffset = (neighborIndex << 2);
            final int neighborAlpha = luminanceMask != null
                ? luminanceMask[neighborIndex]
                : src[neighborOffset + 3];
            if (dilate) {
              if (neighborAlpha > bestAlpha) {
                bestAlpha = neighborAlpha;
                bestOffset = neighborOffset;
              }
            } else {
              if (neighborAlpha < bestAlpha) {
                bestAlpha = neighborAlpha;
                bestOffset = neighborOffset;
              }
            }
          }
        }

        final int outOffset = ((rowOffset + x) << 2);
        if (bestAlpha == 0) {
          dest[outOffset] = preserveAlpha ? src[outOffset] : 0;
          dest[outOffset + 1] = preserveAlpha ? src[outOffset + 1] : 0;
          dest[outOffset + 2] = preserveAlpha ? src[outOffset + 2] : 0;
          dest[outOffset + 3] = preserveAlpha ? src[outOffset + 3] : 0;
        } else {
          dest[outOffset] = src[bestOffset];
          dest[outOffset + 1] = src[bestOffset + 1];
          dest[outOffset + 2] = src[bestOffset + 2];
          dest[outOffset + 3] = preserveAlpha ? src[outOffset + 3] : bestAlpha;
        }
      }
    }
    final Uint8List swap = src;
    src = dest;
    dest = swap;
  }

  if (!identical(src, bitmap)) {
    bitmap.setAll(0, src);
  }
}

/// 当图层完全不透明时，基于亮度构造“线稿掩码”，让线条收窄在无透明度的色稿上也能生效。
/// 返回 null 表示存在透明像素或图像过于明亮（没有可视的线稿）。
Uint8List? _filterBuildLuminanceMaskIfFullyOpaque(
  Uint8List bitmap,
  int width,
  int height,
) {
  final int pixelCount = width * height;
  final Uint8List mask = Uint8List(pixelCount);
  bool fullyOpaque = true;
  bool hasCoverage = false;
  for (int i = 0, offset = 0; i < pixelCount; i++, offset += 4) {
    final int alpha = bitmap[offset + 3];
    if (alpha != 255) {
      fullyOpaque = false;
      break;
    }
    // ITU-R BT.601 加权亮度，再取反得到线稿“覆盖度”。
    final int r = bitmap[offset];
    final int g = bitmap[offset + 1];
    final int b = bitmap[offset + 2];
    final int luma = ((r * 299 + g * 587 + b * 114) / 1000).round();
    final int coverage = (255 - luma).clamp(0, 255).toInt();
    if (coverage > 0) {
      hasCoverage = true;
    }
    mask[i] = coverage;
  }
  if (!fullyOpaque || !hasCoverage) {
    return null;
  }
  return mask;
}

void _filterApplyLeakRemovalToBitmap(
  Uint8List bitmap,
  int width,
  int height,
  int radius,
) {
  if (bitmap.isEmpty || width <= 0 || height <= 0) {
    return;
  }
  final int clampedRadius = radius.clamp(0, _kLeakRemovalMaxRadius.toInt());
  if (clampedRadius <= 0) {
    return;
  }
  // 全不透明图层使用亮度掩码推导覆盖度，避免因缺少透明度信息而无法检测针眼。
  final Uint8List? luminanceMask = _filterBuildLuminanceMaskIfFullyOpaque(
    bitmap,
    width,
    height,
  );
  final bool useLuminanceMask = luminanceMask != null;
  final int pixelCount = width * height;
  final Uint8List holeMask = Uint8List(pixelCount);
  bool hasTransparent = false;
  for (int index = 0, offset = 0; index < pixelCount; index++, offset += 4) {
    final int coverage = useLuminanceMask
        ? luminanceMask![index]
        : bitmap[offset + 3];
    if (coverage == 0) {
      holeMask[index] = 1;
      hasTransparent = true;
    }
  }
  if (!hasTransparent) {
    return;
  }
  _filterMarkLeakBackground(holeMask, width, height);
  bool hasHole = false;
  for (final int value in holeMask) {
    if (value == 1) {
      hasHole = true;
      break;
    }
  }
  if (!hasHole) {
    return;
  }
  final int maxComponentExtent = clampedRadius * 2 + 1;
  final int maxComponentPixels = maxComponentExtent * maxComponentExtent;
  final ListQueue<int> queue = ListQueue<int>();
  final List<int> componentPixels = <int>[];
  final List<int> seeds = <int>[];
  final Set<int> seedSet = <int>{};

  for (int start = 0; start < pixelCount; start++) {
    if (holeMask[start] != 1) {
      continue;
    }
    queue.clear();
    componentPixels.clear();
    seeds.clear();
    seedSet.clear();
    queue.add(start);
    holeMask[start] = 2;
    bool touchesOpaque = false;
    bool componentTooLarge = false;
    int minX = start % width;
    int maxX = minX;
    int minY = start ~/ width;
    int maxY = minY;

    while (queue.isNotEmpty) {
      final int index = queue.removeFirst();
      final int y = index ~/ width;
      final int x = index - y * width;

      if (componentTooLarge) {
        holeMask[index] = 0;
      } else {
        componentPixels.add(index);
        if (x < minX) {
          minX = x;
        }
        if (x > maxX) {
          maxX = x;
        }
        if (y < minY) {
          minY = y;
        }
        if (y > maxY) {
          maxY = y;
        }
      }

      if (x > 0) {
        final int left = index - 1;
        if (holeMask[left] == 1) {
          holeMask[left] = 2;
          queue.add(left);
        }
      }
      if (x + 1 < width) {
        final int right = index + 1;
        if (holeMask[right] == 1) {
          holeMask[right] = 2;
          queue.add(right);
        }
      }
      if (y > 0) {
        final int up = index - width;
        if (holeMask[up] == 1) {
          holeMask[up] = 2;
          queue.add(up);
        }
      }
      if (y + 1 < height) {
        final int down = index + width;
        if (holeMask[down] == 1) {
          holeMask[down] = 2;
          queue.add(down);
        }
      }

      if (componentTooLarge) {
        continue;
      }

      for (int dy = -1; dy <= 1; dy++) {
        final int ny = y + dy;
        if (ny < 0 || ny >= height) {
          continue;
        }
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) {
            continue;
          }
          final int nx = x + dx;
          if (nx < 0 || nx >= width) {
            continue;
          }
          final int neighborIndex = ny * width + nx;
          if (holeMask[neighborIndex] == 2) {
            continue;
          }
          final int neighborOffset = neighborIndex << 2;
          final int neighborCoverage = useLuminanceMask
              ? luminanceMask![neighborIndex]
              : bitmap[neighborOffset + 3];
          if (neighborCoverage == 0) {
            continue;
          }
          touchesOpaque = true;
          if (seedSet.add(neighborIndex)) {
            seeds.add(neighborIndex);
          }
        }
      }

      final int componentWidth = maxX - minX + 1;
      final int componentHeight = maxY - minY + 1;
      if (componentPixels.length > maxComponentPixels ||
          componentWidth > maxComponentExtent ||
          componentHeight > maxComponentExtent) {
        componentTooLarge = true;
        touchesOpaque = false;
        for (final int visitedIndex in componentPixels) {
          holeMask[visitedIndex] = 0;
        }
        componentPixels.clear();
        seeds.clear();
        seedSet.clear();
      }
    }

    if (componentTooLarge) {
      continue;
    }
    if (componentPixels.isEmpty || seeds.isEmpty || !touchesOpaque) {
      _filterClearLeakComponent(componentPixels, holeMask);
      continue;
    }
    if (!_filterIsLeakComponentWithinRadius(
      componentPixels,
      width,
      height,
      clampedRadius,
      holeMask,
    )) {
      _filterClearLeakComponent(componentPixels, holeMask);
      continue;
    }
    _filterFillLeakComponent(
      bitmap: bitmap,
      width: width,
      height: height,
      holeMask: holeMask,
      seeds: seeds,
    );
    _filterClearLeakComponent(componentPixels, holeMask);
  }
}

void _filterMarkLeakBackground(Uint8List holeMask, int width, int height) {
  if (width <= 0 || height <= 0) {
    return;
  }
  final int pixelCount = width * height;
  final Uint32List queue = Uint32List(pixelCount);
  int head = 0;
  int tail = 0;

  void tryEnqueue(int index) {
    if (index < 0 || index >= pixelCount) {
      return;
    }
    if (holeMask[index] != 1) {
      return;
    }
    holeMask[index] = 0;
    queue[tail++] = index;
  }

  for (int x = 0; x < width; x++) {
    tryEnqueue(x);
    if (height > 1) {
      tryEnqueue((height - 1) * width + x);
    }
  }
  for (int y = 1; y < height - 1; y++) {
    tryEnqueue(y * width);
    if (width > 1) {
      tryEnqueue(y * width + (width - 1));
    }
  }

  while (head < tail) {
    final int index = queue[head++];
    final int row = index ~/ width;
    final int col = index - row * width;
    if (row > 0) {
      final int up = index - width;
      if (holeMask[up] == 1) {
        holeMask[up] = 0;
        queue[tail++] = up;
      }
    }
    if (row + 1 < height) {
      final int down = index + width;
      if (holeMask[down] == 1) {
        holeMask[down] = 0;
        queue[tail++] = down;
      }
    }
    if (col > 0) {
      final int left = index - 1;
      if (holeMask[left] == 1) {
        holeMask[left] = 0;
        queue[tail++] = left;
      }
    }
    if (col + 1 < width) {
      final int right = index + 1;
      if (holeMask[right] == 1) {
        holeMask[right] = 0;
        queue[tail++] = right;
      }
    }
  }
}

void _filterClearLeakComponent(List<int> componentPixels, Uint8List holeMask) {
  for (final int index in componentPixels) {
    holeMask[index] = 0;
  }
}

bool _filterIsLeakComponentWithinRadius(
  List<int> componentPixels,
  int width,
  int height,
  int maxRadius,
  Uint8List holeMask,
) {
  if (componentPixels.isEmpty || maxRadius <= 0) {
    return false;
  }
  final ListQueue<_LeakDistanceNode> queue = ListQueue<_LeakDistanceNode>();
  for (final int index in componentPixels) {
    if (_filterIsLeakBoundaryIndex(index, width, height, holeMask)) {
      queue.add(_LeakDistanceNode(index, 0));
      holeMask[index] = 3;
    }
  }
  if (queue.isEmpty) {
    for (final int index in componentPixels) {
      if (holeMask[index] == 3) {
        holeMask[index] = 2;
      }
    }
    return false;
  }
  int visitedCount = 0;
  int maxDistance = 0;
  while (queue.isNotEmpty) {
    final _LeakDistanceNode node = queue.removeFirst();
    visitedCount++;
    if (node.distance > maxDistance) {
      maxDistance = node.distance;
      if (maxDistance > maxRadius) {
        for (final int index in componentPixels) {
          if (holeMask[index] == 3) {
            holeMask[index] = 2;
          }
        }
        return false;
      }
    }
    final int index = node.index;
    final int y = index ~/ width;
    final int x = index - y * width;
    if (x > 0) {
      final int left = index - 1;
      if (holeMask[left] == 2) {
        holeMask[left] = 3;
        queue.add(_LeakDistanceNode(left, node.distance + 1));
      }
    }
    if (x + 1 < width) {
      final int right = index + 1;
      if (holeMask[right] == 2) {
        holeMask[right] = 3;
        queue.add(_LeakDistanceNode(right, node.distance + 1));
      }
    }
    if (y > 0) {
      final int up = index - width;
      if (holeMask[up] == 2) {
        holeMask[up] = 3;
        queue.add(_LeakDistanceNode(up, node.distance + 1));
      }
    }
    if (y + 1 < height) {
      final int down = index + width;
      if (holeMask[down] == 2) {
        holeMask[down] = 3;
        queue.add(_LeakDistanceNode(down, node.distance + 1));
      }
    }
  }
  final bool fullyCovered = visitedCount == componentPixels.length;
  for (final int index in componentPixels) {
    if (holeMask[index] == 3) {
      holeMask[index] = 2;
    }
  }
  return fullyCovered;
}

bool _filterIsLeakBoundaryIndex(
  int index,
  int width,
  int height,
  Uint8List holeMask,
) {
  final int y = index ~/ width;
  final int x = index - y * width;
  if (x == 0 || x == width - 1 || y == 0 || y == height - 1) {
    return true;
  }
  if (holeMask[index - 1] != 2) {
    return true;
  }
  if (holeMask[index + 1] != 2) {
    return true;
  }
  if (holeMask[index - width] != 2) {
    return true;
  }
  if (holeMask[index + width] != 2) {
    return true;
  }
  return false;
}

void _filterFillLeakComponent({
  required Uint8List bitmap,
  required int width,
  required int height,
  required Uint8List holeMask,
  required List<int> seeds,
}) {
  if (seeds.isEmpty) {
    return;
  }
  List<int> frontier = List<int>.from(seeds);
  List<int> nextFrontier = <int>[];
  while (frontier.isNotEmpty) {
    nextFrontier.clear();
    for (final int sourceIndex in frontier) {
      final int srcOffset = sourceIndex << 2;
      final int alpha = bitmap[srcOffset + 3];
      if (alpha == 0) {
        continue;
      }
      final int sy = sourceIndex ~/ width;
      final int sx = sourceIndex - sy * width;
      for (int dy = -1; dy <= 1; dy++) {
        final int ny = sy + dy;
        if (ny < 0 || ny >= height) {
          continue;
        }
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) {
            continue;
          }
          final int nx = sx + dx;
          if (nx < 0 || nx >= width) {
            continue;
          }
          final int neighborIndex = ny * width + nx;
          if (holeMask[neighborIndex] != 2) {
            continue;
          }
          final int destOffset = neighborIndex << 2;
          bitmap[destOffset] = bitmap[srcOffset];
          bitmap[destOffset + 1] = bitmap[srcOffset + 1];
          bitmap[destOffset + 2] = bitmap[srcOffset + 2];
          bitmap[destOffset + 3] = alpha;
          holeMask[neighborIndex] = 0;
          nextFrontier.add(neighborIndex);
        }
      }
    }
    final List<int> temp = frontier;
    frontier = nextFrontier;
    nextFrontier = temp;
  }
}

class _LeakDistanceNode {
  const _LeakDistanceNode(this.index, this.distance);

  final int index;
  final int distance;
}

List<int> _filterComputeBoxSizes(double sigma, int boxCount) {
  final double idealWidth = math.sqrt((12 * sigma * sigma / boxCount) + 1);
  int lowerWidth = idealWidth.floor();
  if (lowerWidth.isEven) {
    lowerWidth = math.max(1, lowerWidth - 1);
  }
  if (lowerWidth < 1) {
    lowerWidth = 1;
  }
  final int upperWidth = lowerWidth + 2;
  final double mIdeal =
      (12 * sigma * sigma -
          boxCount * lowerWidth * lowerWidth -
          4 * boxCount * lowerWidth -
          3 * boxCount) /
      (-4 * lowerWidth - 4);
  final int m = mIdeal.round();
  final int clampedM = m.clamp(0, boxCount).toInt();
  return List<int>.generate(
    boxCount,
    (int i) => i < clampedM ? lowerWidth : upperWidth,
  );
}

void _filterBoxBlurPass({
  required Uint8List source,
  required Uint8List destination,
  required int width,
  required int height,
  required int radius,
  required bool horizontal,
}) {
  if (radius <= 0) {
    destination.setRange(0, source.length, source);
    return;
  }
  final int kernelSize = radius * 2 + 1;
  if (horizontal) {
    for (int y = 0; y < height; y++) {
      final int rowOffset = y * width;
      double sumR = 0;
      double sumG = 0;
      double sumB = 0;
      double sumA = 0;
      for (int k = -radius; k <= radius; k++) {
        final int sampleX = _filterClampIndex(k, width);
        final int sampleIndex = ((rowOffset + sampleX) << 2);
        sumR += source[sampleIndex];
        sumG += source[sampleIndex + 1];
        sumB += source[sampleIndex + 2];
        sumA += source[sampleIndex + 3];
      }
      for (int x = 0; x < width; x++) {
        final int destIndex = ((rowOffset + x) << 2);
        destination[destIndex] = _filterRoundChannel(sumR / kernelSize);
        destination[destIndex + 1] = _filterRoundChannel(sumG / kernelSize);
        destination[destIndex + 2] = _filterRoundChannel(sumB / kernelSize);
        destination[destIndex + 3] = _filterRoundChannel(sumA / kernelSize);
        final int removeX = x - radius;
        final int addX = x + radius + 1;
        final int removeIndex =
            ((rowOffset + _filterClampIndex(removeX, width)) << 2);
        final int addIndex =
            ((rowOffset + _filterClampIndex(addX, width)) << 2);
        sumR += source[addIndex] - source[removeIndex];
        sumG += source[addIndex + 1] - source[removeIndex + 1];
        sumB += source[addIndex + 2] - source[removeIndex + 2];
        sumA += source[addIndex + 3] - source[removeIndex + 3];
      }
    }
    return;
  }
  for (int x = 0; x < width; x++) {
    double sumR = 0;
    double sumG = 0;
    double sumB = 0;
    double sumA = 0;
    for (int k = -radius; k <= radius; k++) {
      final int sampleY = _filterClampIndex(k, height);
      final int sampleIndex = (((sampleY * width) + x) << 2);
      sumR += source[sampleIndex];
      sumG += source[sampleIndex + 1];
      sumB += source[sampleIndex + 2];
      sumA += source[sampleIndex + 3];
    }
    for (int y = 0; y < height; y++) {
      final int destIndex = (((y * width) + x) << 2);
      destination[destIndex] = _filterRoundChannel(sumR / kernelSize);
      destination[destIndex + 1] = _filterRoundChannel(sumG / kernelSize);
      destination[destIndex + 2] = _filterRoundChannel(sumB / kernelSize);
      destination[destIndex + 3] = _filterRoundChannel(sumA / kernelSize);
      final int removeY = y - radius;
      final int addY = y + radius + 1;
      final int removeIndex =
          (((_filterClampIndex(removeY, height) * width) + x) << 2);
      final int addIndex =
          (((_filterClampIndex(addY, height) * width) + x) << 2);
      sumR += source[addIndex] - source[removeIndex];
      sumG += source[addIndex + 1] - source[removeIndex + 1];
      sumB += source[addIndex + 2] - source[removeIndex + 2];
      sumA += source[addIndex + 3] - source[removeIndex + 3];
    }
  }
}

void _filterPremultiplyAlpha(Uint8List bitmap) {
  for (int i = 0; i < bitmap.length; i += 4) {
    final int alpha = bitmap[i + 3];
    if (alpha == 0) {
      bitmap[i] = 0;
      bitmap[i + 1] = 0;
      bitmap[i + 2] = 0;
      continue;
    }
    bitmap[i] = _filterMultiplyChannelByAlpha(bitmap[i], alpha);
    bitmap[i + 1] = _filterMultiplyChannelByAlpha(bitmap[i + 1], alpha);
    bitmap[i + 2] = _filterMultiplyChannelByAlpha(bitmap[i + 2], alpha);
  }
}

void _filterUnpremultiplyAlpha(Uint8List bitmap) {
  for (int i = 0; i < bitmap.length; i += 4) {
    final int alpha = bitmap[i + 3];
    if (alpha == 0) {
      bitmap[i] = 0;
      bitmap[i + 1] = 0;
      bitmap[i + 2] = 0;
      continue;
    }
    bitmap[i] = _filterUnmultiplyChannelByAlpha(bitmap[i], alpha);
    bitmap[i + 1] = _filterUnmultiplyChannelByAlpha(bitmap[i + 1], alpha);
    bitmap[i + 2] = _filterUnmultiplyChannelByAlpha(bitmap[i + 2], alpha);
  }
}

int _filterMultiplyChannelByAlpha(int channel, int alpha) {
  return ((channel * alpha) + 127) ~/ 255;
}

int _filterUnmultiplyChannelByAlpha(int channel, int alpha) {
  final int value = ((channel * 255) + (alpha >> 1)) ~/ alpha;
  if (value < 0) {
    return 0;
  }
  if (value > 255) {
    return 255;
  }
  return value;
}
