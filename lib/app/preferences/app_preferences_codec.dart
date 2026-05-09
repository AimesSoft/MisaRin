part of 'app_preferences.dart';

int _clampHistoryLimit(int value) {
  if (value < _minHistoryLimit) {
    return _minHistoryLimit;
  }
  if (value > _maxHistoryLimit) {
    return _maxHistoryLimit;
  }
  return value;
}

int _clampNewCanvasDimension(int value) {
  if (value < _minNewCanvasDimension) {
    return _minNewCanvasDimension;
  }
  if (value > _maxNewCanvasDimension) {
    return _maxNewCanvasDimension;
  }
  return value;
}

int _decodeNewCanvasDimension(int value, int fallback) {
  if (value <= 0) {
    return fallback;
  }
  return _clampNewCanvasDimension(value);
}

int _clampToleranceValue(int value) {
  return value.clamp(0, 255).toInt();
}

int _clampFillGapValue(int value) {
  return value.clamp(0, 64).toInt();
}

int _clampAutoSaveCleanupThresholdMb(int value) {
  if (value <= 0) {
    return 0;
  }
  if (value < _minAutoSaveCleanupThresholdMb) {
    return _minAutoSaveCleanupThresholdMb;
  }
  if (value > _maxAutoSaveCleanupThresholdMb) {
    return _maxAutoSaveCleanupThresholdMb;
  }
  return value;
}

ThemeMode _decodeThemeMode(int value) {
  switch (value) {
    case 0:
      return ThemeMode.light;
    case 1:
      return ThemeMode.dark;
    case 2:
    default:
      return ThemeMode.system;
  }
}

int _encodeThemeMode(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 0;
    case ThemeMode.dark:
      return 1;
    case ThemeMode.system:
    default:
      return 2;
  }
}

Color _decodeColorLineColor(int value) {
  if (value >= 0 && value < kColorLinePresets.length) {
    return kColorLinePresets[value];
  }
  return _defaultColorLineColor;
}

int _encodeColorLineColor(Color color) {
  final int index = kColorLinePresets.indexWhere(
    (candidate) => candidate.value == color.value,
  );
  return index >= 0 ? index : 0;
}

WorkspaceLayoutPreference _decodeWorkspaceLayoutPreference(int value) {
  switch (value) {
    case 2:
      return WorkspaceLayoutPreference.csp;
    case 1:
      return WorkspaceLayoutPreference.sai2;
    case 0:
    default:
      return WorkspaceLayoutPreference.floating;
  }
}

int _encodeWorkspaceLayoutPreference(WorkspaceLayoutPreference value) {
  switch (value) {
    case WorkspaceLayoutPreference.csp:
      return 2;
    case WorkspaceLayoutPreference.sai2:
      return 1;
    case WorkspaceLayoutPreference.floating:
    default:
      return 0;
  }
}

CanvasBackend _decodeCanvasBackend(int value) {
  return CanvasBackendId.fromId(value);
}

int _encodeCanvasBackend(CanvasBackend backend) {
  return backend.id;
}

Locale? _decodeLocaleOverride(int value) {
  switch (value) {
    case 1:
      return const Locale('en');
    case 2:
      return const Locale('ja');
    case 3:
      return const Locale('ko');
    case 4:
      return const Locale('zh', 'CN');
    case 5:
      return const Locale('zh', 'TW');
    case 0:
    default:
      return null; // Follow system.
  }
}

int _encodeLocaleOverride(Locale? locale) {
  if (locale == null) {
    return 0;
  }
  final String languageCode = locale.languageCode.toLowerCase();
  final String? countryCode = locale.countryCode?.toUpperCase();
  if (languageCode == 'en') return 1;
  if (languageCode == 'ja') return 2;
  if (languageCode == 'ko') return 3;
  if (languageCode == 'zh' && countryCode == 'TW') return 5;
  if (languageCode == 'zh') return 4; // Default to Simplified for zh.
  return 0;
}

BucketSwallowColorLineMode _decodeBucketSwallowColorLineMode(int value) {
  if (value < 0 || value >= BucketSwallowColorLineMode.values.length) {
    return _defaultBucketSwallowColorLineMode;
  }
  return BucketSwallowColorLineMode.values[value];
}

int _encodeBucketSwallowColorLineMode(BucketSwallowColorLineMode mode) {
  final int index = mode.index;
  if (index < 0 || index > 0xff) {
    return _defaultBucketSwallowColorLineMode.index;
  }
  return index;
}

SprayMode _decodeSprayMode(int value) {
  switch (value) {
    case 1:
      return SprayMode.splatter;
    case 0:
    default:
      return SprayMode.smudge;
  }
}

int _encodeSprayMode(SprayMode mode) {
  switch (mode) {
    case SprayMode.splatter:
      return 1;
    case SprayMode.smudge:
    default:
      return 0;
  }
}

double? _decodePanelExtent(int low, int high) {
  final int raw = (low & 0xff) | ((high & 0xff) << 8);
  if (raw <= 0) {
    return null;
  }
  return raw.toDouble();
}

int _encodePanelExtent(double? value) {
  if (value == null || value.isNaN || value <= 0) {
    return 0;
  }
  final double clamped = value.clamp(0.0, 65535.0);
  return clamped.round().clamp(0, 0xFFFF);
}

double _decodeRatioByte(int value) {
  final int clamped = value.clamp(0, 255);
  return clamped / 255.0;
}

int _encodeRatioByte(double value) {
  final double clamped = value.clamp(0.0, 1.0);
  return (clamped * 255).round().clamp(0, 255);
}

double _decodePenStrokeWidthLegacy(int value) {
  final double clamped = value.clamp(1, 60).toDouble();
  return clamped.clamp(kPenStrokeMin, kPenStrokeMax);
}

double _decodePenStrokeWidthV10(int value) {
  final int clamped = value.clamp(0, 0xffff);
  if (clamped <= 0) {
    return kPenStrokeMin;
  }
  if (clamped >= 0xffff) {
    return kPenStrokeMax;
  }
  final double t = clamped / 65535.0;
  final double ratio = kPenStrokeMax / kPenStrokeMin;
  return kPenStrokeMin * math.pow(ratio, t);
}

int _encodePenStrokeWidth(double value) {
  final double clamped = value.clamp(kPenStrokeMin, kPenStrokeMax);
  if (clamped <= kPenStrokeMin) {
    return 0;
  }
  if (clamped >= kPenStrokeMax) {
    return 0xffff;
  }
  final double numerator = math.log(clamped / kPenStrokeMin);
  final double denominator = math.log(kPenStrokeMax / kPenStrokeMin);
  final double normalized = denominator == 0 ? 0.0 : (numerator / denominator);
  return (normalized * 65535.0).round().clamp(0, 0xffff);
}

double _clampSprayStrokeWidth(double value) {
  if (!value.isFinite) {
    return _defaultSprayStrokeWidth;
  }
  return value.clamp(kSprayStrokeMin, kSprayStrokeMax);
}

double _decodeSprayStrokeWidth(int value) {
  final int resolved = value.clamp(
    kSprayStrokeMin.round(),
    kSprayStrokeMax.round(),
  );
  return resolved.toDouble();
}

int _encodeSprayStrokeWidth(double value) {
  final double clamped = _clampSprayStrokeWidth(value);
  return clamped.round().clamp(
    kSprayStrokeMin.round(),
    kSprayStrokeMax.round(),
  );
}

double _clampEraserStrokeWidth(double value) {
  if (!value.isFinite) {
    return _defaultEraserStrokeWidth;
  }
  return value.clamp(kEraserStrokeMin, kEraserStrokeMax);
}

double _decodeEraserStrokeWidth(int value) {
  final int resolved = value.clamp(
    kEraserStrokeMin.round(),
    kEraserStrokeMax.round(),
  );
  return resolved.toDouble();
}

int _encodeEraserStrokeWidth(double value) {
  final double clamped = _clampEraserStrokeWidth(value);
  return clamped.round().clamp(
    kEraserStrokeMin.round(),
    kEraserStrokeMax.round(),
  );
}

double _clampLiquifyStrokeWidth(double value) {
  if (!value.isFinite) {
    return _defaultLiquifyStrokeWidth;
  }
  return value.clamp(8.0, 500.0);
}

double _decodeLiquifyStrokeWidth(int value) {
  if (value <= 0) {
    return _defaultLiquifyStrokeWidth;
  }
  return value.clamp(8, 500).toDouble();
}

int _encodeLiquifyStrokeWidth(double value) {
  final double clamped = _clampLiquifyStrokeWidth(value);
  return clamped.round().clamp(8, 500);
}

double _clampLiquifyRatio(double value, double fallback) {
  if (!value.isFinite) {
    return fallback;
  }
  return value.clamp(0.0, 1.0);
}

double _decodeStylusFactor(
  int value, {
  required double lower,
  required double upper,
}) {
  final double clamped = value.clamp(0, 255).toDouble();
  final double t = clamped / 255.0;
  return lower + (upper - lower) * t;
}

int _encodeStylusFactor(
  double value, {
  required double lower,
  required double upper,
}) {
  final double clamped = value.clamp(lower, upper);
  if (upper <= lower) {
    return 0;
  }
  final double normalized = (clamped - lower) / (upper - lower);
  return (normalized * 255.0).round().clamp(0, 255);
}

double _clampStylusFactor(
  double value, {
  required double lower,
  required double upper,
}) {
  final double clamped = value.clamp(lower, upper);
  if (!clamped.isFinite) {
    return lower;
  }
  return clamped;
}

StrokePressureProfile _decodePressureProfile(int value) {
  switch (value) {
    case 0:
      return StrokePressureProfile.taperEnds;
    case 1:
      return StrokePressureProfile.taperCenter;
    case 2:
    default:
      return StrokePressureProfile.auto;
  }
}

int _encodePressureProfile(StrokePressureProfile profile) {
  switch (profile) {
    case StrokePressureProfile.taperEnds:
      return 0;
    case StrokePressureProfile.taperCenter:
      return 1;
    case StrokePressureProfile.auto:
      return 2;
  }
}

int _decodeAntialiasLevel(int value) {
  if (value < 0) {
    return 0;
  }
  if (value > 9) {
    return 9;
  }
  return value;
}

int _encodeAntialiasLevel(int value) {
  if (value < 0) {
    return 0;
  }
  if (value > 9) {
    return 9;
  }
  return value;
}

PenStrokeSliderRange _decodePenStrokeSliderRange(int value) {
  switch (value) {
    case 0:
      return PenStrokeSliderRange.compact;
    case 1:
      return PenStrokeSliderRange.medium;
    case 2:
      return PenStrokeSliderRange.full;
    case 3:
      return PenStrokeSliderRange.huge;
    default:
      return PenStrokeSliderRange.full;
  }
}

int _encodePenStrokeSliderRange(PenStrokeSliderRange range) {
  switch (range) {
    case PenStrokeSliderRange.compact:
      return 0;
    case PenStrokeSliderRange.medium:
      return 1;
    case PenStrokeSliderRange.full:
      return 2;
    case PenStrokeSliderRange.huge:
      return 3;
    default:
      return 2;
  }
}

PenStrokeSliderRange _decodeOptionalStrokeSliderRange(
  int value,
  PenStrokeSliderRange fallback,
) {
  if (value <= 0) {
    return fallback;
  }
  return _decodePenStrokeSliderRange(value - 1);
}

int _encodeOptionalStrokeSliderRange(
  PenStrokeSliderRange value,
  PenStrokeSliderRange fallback,
) {
  if (value == fallback) {
    return 0;
  }
  return _encodePenStrokeSliderRange(value) + 1;
}

double _decodeStrokeStabilizerStrength(int value) {
  final int clamped = value.clamp(0, 255);
  return clamped / 255.0;
}

int _encodeStrokeStabilizerStrength(double value) {
  final double clamped = _clampStrokeStabilizerStrength(value);
  return (clamped * 255.0).round().clamp(0, 255);
}

double _decodeStreamlineStrength(int value) {
  final int clamped = value.clamp(0, 255);
  return clamped / 255.0;
}

int _encodeStreamlineStrength(double value) {
  final double clamped = _clampStreamlineStrength(value);
  return (clamped * 255.0).round().clamp(0, 255);
}

BrushShape _decodeBrushShape(int value) {
  switch (value) {
    case 1:
      return BrushShape.triangle;
    case 2:
      return BrushShape.square;
    case 3:
      return BrushShape.star;
    case 0:
    default:
      return BrushShape.circle;
  }
}

int _encodeBrushShape(BrushShape shape) {
  switch (shape) {
    case BrushShape.circle:
      return 0;
    case BrushShape.triangle:
      return 1;
    case BrushShape.square:
      return 2;
    case BrushShape.star:
      return 3;
  }
}

double _clampStrokeStabilizerStrength(double value) {
  if (!value.isFinite) {
    return _defaultStrokeStabilizerStrength;
  }
  return value.clamp(_strokeStabilizerLowerBound, _strokeStabilizerUpperBound);
}

double _clampStreamlineStrength(double value) {
  if (!value.isFinite) {
    return _defaultStreamlineStrength;
  }
  return value.clamp(_strokeStabilizerLowerBound, _strokeStabilizerUpperBound);
}
