part of 'painting_board.dart';

int _countUniqueColorsInRgba(Uint8List rgba) {
  if (rgba.isEmpty) {
    return 0;
  }
  final Set<int> colors = <int>{};
  for (int i = 0; i + 3 < rgba.length; i += 4) {
    final int alpha = rgba[i + 3];
    if (alpha == 0) {
      continue;
    }
    final int color = (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
    colors.add(color);
  }
  return colors.length;
}

int _countUniqueColorsForLayer(List<Object?> args) {
  final Uint8List? bitmap = args[0] as Uint8List?;
  final int? fillColor = args[1] as int?;
  return _buildColorHistogram(bitmap, fillColor).length;
}

Future<_ColorRangeComputeResult> _generateColorRangeResult(
  Uint8List? bitmap,
  Color? fillColor,
  int targetColors,
) async {
  final List<Object?> args = <Object?>[bitmap, fillColor?.value, targetColors];
  try {
    return await compute(_computeColorRangeReduction, args);
  } on UnsupportedError catch (_) {
    return _computeColorRangeReduction(args);
  }
}

_ColorRangeComputeResult _computeColorRangeReduction(List<Object?> args) {
  final Uint8List? bitmap = args[0] as Uint8List?;
  final int? fillColor = args[1] as int?;
  final int target = (args[2] as num?)?.toInt() ?? 1;
  return _applyColorRangeReduction(bitmap, fillColor, target);
}

_ColorRangeComputeResult _applyColorRangeReduction(
  Uint8List? bitmap,
  int? fillColor,
  int targetColors,
) {
  final Map<int, int> histogram = _buildColorHistogram(bitmap, fillColor);
  if (histogram.isEmpty) {
    return _ColorRangeComputeResult(
      bitmap: bitmap != null ? Uint8List.fromList(bitmap) : null,
      fillColor: fillColor,
    );
  }
  final int cappedTarget = math.max(
    1,
    math.min(targetColors, histogram.length),
  );
  if (cappedTarget >= histogram.length) {
    return _ColorRangeComputeResult(
      bitmap: bitmap != null ? Uint8List.fromList(bitmap) : null,
      fillColor: fillColor,
    );
  }
  final List<_ColorRangeBucket> buckets = <_ColorRangeBucket>[
    _ColorRangeBucket.fromHistogram(histogram),
  ];
  while (buckets.length < cappedTarget) {
    final int index = _colorRangeBucketToSplitIndex(buckets);
    if (index < 0) {
      break;
    }
    final _ColorRangeBucket bucket = buckets.removeAt(index);
    final List<_ColorRangeBucket> splits = bucket.split();
    if (splits.length != 2 || splits[0].isEmpty || splits[1].isEmpty) {
      buckets.add(bucket);
      break;
    }
    buckets.addAll(splits);
  }
  final List<int> palette = buckets
      .map((bucket) => bucket.averageColor)
      .toList(growable: false);
  final Map<int, int> quantizedColorMap = <int, int>{};
  final Map<int, int> quantizedWeights = <int, int>{};
  histogram.forEach((int color, int count) {
    final int quantKey = _quantizeColorInt(color);
    final int mapped = _findNearestPaletteColor(color, palette);
    final int existingWeight = quantizedWeights[quantKey] ?? -1;
    if (count > existingWeight) {
      quantizedColorMap[quantKey] = mapped;
      quantizedWeights[quantKey] = count;
    }
  });
  Uint8List? reducedBitmap = bitmap != null ? Uint8List.fromList(bitmap) : null;
  if (reducedBitmap != null) {
    for (int i = 0; i + 3 < reducedBitmap.length; i += 4) {
      final int alpha = reducedBitmap[i + 3];
      if (alpha == 0) {
        continue;
      }
      final int quantKey = _quantizeColor(
        reducedBitmap[i],
        reducedBitmap[i + 1],
        reducedBitmap[i + 2],
      );
      final int mapped =
          quantizedColorMap[quantKey] ??
          _findNearestPaletteColor(quantKey, palette);
      reducedBitmap[i] = (mapped >> 16) & 0xFF;
      reducedBitmap[i + 1] = (mapped >> 8) & 0xFF;
      reducedBitmap[i + 2] = mapped & 0xFF;
    }
  }
  int? mappedFill = fillColor;
  if (fillColor != null) {
    final int alpha = (fillColor >> 24) & 0xFF;
    if (alpha != 0) {
      final int quantKey = _quantizeColorInt(fillColor & 0xFFFFFF);
      final int mapped =
          quantizedColorMap[quantKey] ??
          _findNearestPaletteColor(quantKey, palette);
      mappedFill = (fillColor & 0xFF000000) | mapped;
    }
  }
  return _ColorRangeComputeResult(bitmap: reducedBitmap, fillColor: mappedFill);
}

int _quantizeColor(int r, int g, int b) {
  final int qr =
      (r ~/ _kColorRangeQuantizationStep) * _kColorRangeQuantizationStep;
  final int qg =
      (g ~/ _kColorRangeQuantizationStep) * _kColorRangeQuantizationStep;
  final int qb =
      (b ~/ _kColorRangeQuantizationStep) * _kColorRangeQuantizationStep;
  return (qr << 16) | (qg << 8) | qb;
}

int _quantizeColorInt(int color) {
  return _quantizeColor(
    (color >> 16) & 0xFF,
    (color >> 8) & 0xFF,
    color & 0xFF,
  );
}

class _ColorRangeHistogramBucket {
  _ColorRangeHistogramBucket();

  int count = 0;
  int sumR = 0;
  int sumG = 0;
  int sumB = 0;
}

Map<int, int> _buildColorHistogram(Uint8List? bitmap, int? fillColor) {
  final Map<int, _ColorRangeHistogramBucket> buckets =
      <int, _ColorRangeHistogramBucket>{};

  void addColor(int r, int g, int b) {
    final int qr =
        (r ~/ _kColorRangeQuantizationStep) * _kColorRangeQuantizationStep;
    final int qg =
        (g ~/ _kColorRangeQuantizationStep) * _kColorRangeQuantizationStep;
    final int qb =
        (b ~/ _kColorRangeQuantizationStep) * _kColorRangeQuantizationStep;
    final int key = (qr << 16) | (qg << 8) | qb;
    final _ColorRangeHistogramBucket bucket = buckets.putIfAbsent(
      key,
      _ColorRangeHistogramBucket.new,
    );
    bucket.count += 1;
    bucket.sumR += r;
    bucket.sumG += g;
    bucket.sumB += b;
  }

  if (bitmap != null) {
    for (int i = 0; i + 3 < bitmap.length; i += 4) {
      final int alpha = bitmap[i + 3];
      if (alpha < _kColorRangeAlphaThreshold) {
        continue;
      }
      addColor(bitmap[i], bitmap[i + 1], bitmap[i + 2]);
    }
  }
  if (fillColor != null) {
    final int alpha = (fillColor >> 24) & 0xFF;
    if (alpha >= _kColorRangeAlphaThreshold) {
      addColor(
        (fillColor >> 16) & 0xFF,
        (fillColor >> 8) & 0xFF,
        fillColor & 0xFF,
      );
    }
  }

  final Map<int, int> histogram = <int, int>{};
  buckets.forEach((_, _ColorRangeHistogramBucket bucket) {
    final int count = math.max(bucket.count, 1);
    final int r = (bucket.sumR / count).round().clamp(0, 255);
    final int g = (bucket.sumG / count).round().clamp(0, 255);
    final int b = (bucket.sumB / count).round().clamp(0, 255);
    final int color = (r << 16) | (g << 8) | b;
    histogram[color] = (histogram[color] ?? 0) + bucket.count;
  });

  if (histogram.length <= 1) {
    return histogram;
  }
  return _mergeSmallHistogramBuckets(histogram);
}

Map<int, int> _mergeSmallHistogramBuckets(Map<int, int> histogram) {
  final int total = histogram.values.fold<int>(0, (int acc, int value) {
    return acc + value;
  });
  if (total <= 0) {
    return histogram;
  }
  final int minCount = math.max(
    _kColorRangeMinBucketSize,
    (total * _kColorRangeSmallBucketFraction).round(),
  );
  if (minCount <= 1) {
    return histogram;
  }
  final List<MapEntry<int, int>> sorted = histogram.entries.toList()
    ..sort((MapEntry<int, int> a, MapEntry<int, int> b) {
      return b.value.compareTo(a.value);
    });
  final List<int> anchors = sorted
      .where((MapEntry<int, int> entry) => entry.value >= minCount)
      .map((MapEntry<int, int> entry) => entry.key)
      .toList();
  if (anchors.isEmpty) {
    return histogram;
  }
  final Map<int, int> merged = <int, int>{};
  for (final MapEntry<int, int> entry in sorted) {
    if (entry.value >= minCount) {
      merged[entry.key] = (merged[entry.key] ?? 0) + entry.value;
      continue;
    }
    final int nearest = _findNearestPaletteColor(entry.key, anchors);
    merged[nearest] = (merged[nearest] ?? 0) + entry.value;
  }
  return merged;
}

class _ColorRangeComputeResult {
  _ColorRangeComputeResult({this.bitmap, this.fillColor});

  final Uint8List? bitmap;
  final int? fillColor;
}

class _ScanPaperDrawingComputeResult {
  _ScanPaperDrawingComputeResult({
    this.bitmap,
    this.fillColor,
    required this.changed,
  });

  final Uint8List? bitmap;
  final int? fillColor;
  final bool changed;
}

class _ColorCountEntry {
  _ColorCountEntry({required this.color, required this.count});

  final int color;
  final int count;

  int get r => (color >> 16) & 0xFF;
  int get g => (color >> 8) & 0xFF;
  int get b => color & 0xFF;

  int component(int channel) {
    switch (channel) {
      case 0:
        return r;
      case 1:
        return g;
      default:
        return b;
    }
  }
}

class _ColorRangeBucket {
  _ColorRangeBucket(this.entries) {
    _recomputeBounds();
  }

  _ColorRangeBucket.fromHistogram(Map<int, int> histogram)
    : entries = histogram.entries
          .map(
            (entry) => _ColorCountEntry(color: entry.key, count: entry.value),
          )
          .toList() {
    _recomputeBounds();
  }

  final List<_ColorCountEntry> entries;
  int _minR = 0;
  int _maxR = 0;
  int _minG = 0;
  int _maxG = 0;
  int _minB = 0;
  int _maxB = 0;
  int totalCount = 0;

  bool get isEmpty => entries.isEmpty;

  int get maxRange =>
      math.max(_maxR - _minR, math.max(_maxG - _minG, _maxB - _minB));

  int get averageColor {
    if (entries.isEmpty || totalCount <= 0) {
      return 0;
    }
    int rSum = 0;
    int gSum = 0;
    int bSum = 0;
    for (final _ColorCountEntry entry in entries) {
      rSum += entry.r * entry.count;
      gSum += entry.g * entry.count;
      bSum += entry.b * entry.count;
    }
    final int r = (rSum / totalCount).round().clamp(0, 255).toInt();
    final int g = (gSum / totalCount).round().clamp(0, 255).toInt();
    final int b = (bSum / totalCount).round().clamp(0, 255).toInt();
    return (r << 16) | (g << 8) | b;
  }

  List<_ColorRangeBucket> split() {
    if (entries.length <= 1) {
      return <_ColorRangeBucket>[this];
    }
    final int channel = _dominantChannel();
    final List<_ColorCountEntry> sorted = List<_ColorCountEntry>.from(entries)
      ..sort((a, b) => a.component(channel).compareTo(b.component(channel)));
    final int medianTarget = totalCount ~/ 2;
    int running = 0;
    int splitIndex = 0;
    for (int i = 0; i < sorted.length; i++) {
      running += sorted[i].count;
      splitIndex = i;
      if (running >= medianTarget) {
        break;
      }
    }
    final List<_ColorCountEntry> first = sorted.sublist(0, splitIndex + 1);
    final List<_ColorCountEntry> second = sorted.sublist(
      splitIndex + 1,
      sorted.length,
    );
    if (first.isEmpty || second.isEmpty) {
      final int mid = sorted.length ~/ 2;
      return <_ColorRangeBucket>[
        _ColorRangeBucket(sorted.sublist(0, mid)),
        _ColorRangeBucket(sorted.sublist(mid)),
      ];
    }
    return <_ColorRangeBucket>[
      _ColorRangeBucket(first),
      _ColorRangeBucket(second),
    ];
  }

  int _dominantChannel() {
    final int rRange = _maxR - _minR;
    final int gRange = _maxG - _minG;
    final int bRange = _maxB - _minB;
    if (rRange >= gRange && rRange >= bRange) {
      return 0;
    }
    if (gRange >= rRange && gRange >= bRange) {
      return 1;
    }
    return 2;
  }

  void _recomputeBounds() {
    totalCount = 0;
    if (entries.isEmpty) {
      _minR = _minG = _minB = 0;
      _maxR = _maxG = _maxB = 0;
      return;
    }
    _minR = _minG = _minB = 255;
    _maxR = _maxG = _maxB = 0;
    for (final _ColorCountEntry entry in entries) {
      _minR = math.min(_minR, entry.r);
      _maxR = math.max(_maxR, entry.r);
      _minG = math.min(_minG, entry.g);
      _maxG = math.max(_maxG, entry.g);
      _minB = math.min(_minB, entry.b);
      _maxB = math.max(_maxB, entry.b);
      totalCount += entry.count;
    }
  }
}

int _colorRangeBucketToSplitIndex(List<_ColorRangeBucket> buckets) {
  int bestIndex = -1;
  int bestRange = -1;
  int bestCount = -1;
  for (int i = 0; i < buckets.length; i++) {
    final _ColorRangeBucket bucket = buckets[i];
    if (bucket.isEmpty || bucket.entries.length <= 1) {
      continue;
    }
    final int range = bucket.maxRange;
    if (range > bestRange ||
        (range == bestRange && bucket.totalCount > bestCount)) {
      bestRange = range;
      bestCount = bucket.totalCount;
      bestIndex = i;
    }
  }
  return bestIndex;
}

int _findNearestPaletteColor(int color, List<int> palette) {
  if (palette.isEmpty) {
    return color;
  }
  final int r = (color >> 16) & 0xFF;
  final int g = (color >> 8) & 0xFF;
  final int b = color & 0xFF;
  int bestColor = palette.first;
  int bestDistance = 0x7FFFFFFF;
  for (final int candidate in palette) {
    final int dr = r - ((candidate >> 16) & 0xFF);
    final int dg = g - ((candidate >> 8) & 0xFF);
    final int db = b - (candidate & 0xFF);
    final int distance = dr * dr + dg * dg + db * db;
    if (distance < bestDistance) {
      bestDistance = distance;
      bestColor = candidate;
      if (bestDistance == 0) {
        break;
      }
    }
  }
  return bestColor;
}

Future<Uint8List> _generateHueSaturationPreviewBytes(List<Object?> args) async {
  try {
    return await compute<List<Object?>, Uint8List>(
      _computeHueSaturationPreviewPixels,
      args,
    );
  } on UnsupportedError catch (_) {
    return _computeHueSaturationPreviewPixels(args);
  }
}
