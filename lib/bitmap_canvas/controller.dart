import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../canvas/blend_mode_math.dart';
import '../canvas/canvas_layer.dart';
import 'bitmap_canvas.dart';
import 'slime_stroke_engine.dart';
import 'stroke_pressure_profile.dart';

part 'controller_active_transform.dart';
part 'controller_layer_management.dart';
part 'controller_stroke.dart';
part 'controller_fill.dart';
part 'controller_composite.dart';

class BitmapLayerState {
  BitmapLayerState({
    required this.id,
    required this.name,
    required this.surface,
    this.visible = true,
    this.opacity = 1.0,
    this.locked = false,
    this.clippingMask = false,
    this.blendMode = CanvasLayerBlendMode.normal,
  });

  final String id;
  String name;
  bool visible;
  double opacity;
  bool locked;
  bool clippingMask;
  CanvasLayerBlendMode blendMode;
  final BitmapSurface surface;
}

class BitmapCanvasController extends ChangeNotifier {
  BitmapCanvasController({
    required int width,
    required int height,
    required Color backgroundColor,
    List<CanvasLayerData>? initialLayers,
  }) : _width = width,
       _height = height,
       _backgroundColor = backgroundColor {
    if (initialLayers != null && initialLayers.isNotEmpty) {
      _loadFromCanvasLayers(this, initialLayers, backgroundColor);
    } else {
      _initializeDefaultLayers(this, backgroundColor);
    }
    _scheduleCompositeRefresh();
  }

  final int _width;
  final int _height;
  Color _backgroundColor;
  final List<BitmapLayerState> _layers = <BitmapLayerState>[];
  int _activeIndex = 0;

  final List<Offset> _currentStrokePoints = <Offset>[];
  double _currentStrokeRadius = 0;
  double _currentStrokeLastRadius = 0;
  bool _currentStrokeStylusPressureEnabled = false;
  double _currentStylusMinFactor = 0.1;
  double _currentStylusMaxFactor = 1.0;
  double _currentStylusCurve = 1.0;
  double? _currentStylusSmoothedPressure;
  static const double _kStylusSmoothing = 0.55;
  int _currentStrokeAntialiasLevel = 0;
  bool _currentStrokeHasMoved = false;
  final SlimeStrokeEngine _slimeStrokeEngine = SlimeStrokeEngine();
  double _currentStrokeLastTimestamp = 0.0;
  Color _currentStrokeColor = const Color(0xFF000000);
  bool _stylusPressureEnabled = true;
  double _stylusMinFactor = 0.18;
  double _stylusMaxFactor = 1.28;
  double _stylusCurve = 0.85;
  bool _currentStrokeUsesSlimeEngine = false;
  StrokePressureProfile _currentStrokeProfile = StrokePressureProfile.auto;

  static const int _kAntialiasCenterWeight = 4;
  static const List<int> _kAntialiasDx = <int>[-1, 0, 1, -1, 1, -1, 0, 1];
  static const List<int> _kAntialiasDy = <int>[-1, -1, -1, 0, 0, 1, 1, 1];
  static const List<int> _kAntialiasWeights = <int>[1, 2, 1, 2, 2, 1, 2, 1];
  static const Map<int, List<double>> _kAntialiasBlendProfiles =
      <int, List<double>>{
        0: <double>[0.25],
        1: <double>[0.35, 0.35],
        2: <double>[0.45, 0.5, 0.5],
        3: <double>[0.6, 0.65, 0.7, 0.75],
      };

  ui.Image? _cachedImage;
  bool _compositeDirty = true;
  bool _refreshScheduled = false;
  bool _pendingFullSurface = false;
  Rect? _pendingDirtyRect;
  bool _compositeInitialized = false;
  Uint32List? _compositePixels;
  Uint8List? _compositeRgba;
  Uint8List? _selectionMask;
  Uint8List? _clipMaskBuffer;
  Uint32List? _activeLayerTranslationSnapshot;
  String? _activeLayerTranslationId;
  int _activeLayerTranslationDx = 0;
  int _activeLayerTranslationDy = 0;
  ui.Image? _activeLayerTransformImage;
  bool _activeLayerTransformPreparing = false;
  Rect? _activeLayerTransformBounds;
  Rect? _activeLayerTransformDirtyRegion;
  bool _pendingActiveLayerTransformCleanup = false;

  UnmodifiableListView<BitmapLayerState> get layers =>
      UnmodifiableListView<BitmapLayerState>(_layers);

  String? get activeLayerId =>
      _layers.isEmpty ? null : _layers[_activeIndex].id;

  ui.Image? get image => _cachedImage;
  Color get backgroundColor => _backgroundColor;
  int get width => _width;
  int get height => _height;
  Uint8List? get selectionMask => _selectionMask;
  bool get isActiveLayerTransforming => _activeLayerTranslationSnapshot != null;
  ui.Image? get activeLayerTransformImage => _activeLayerTransformImage;
  Offset get activeLayerTransformOffset => Offset(
    _activeLayerTranslationDx.toDouble(),
    _activeLayerTranslationDy.toDouble(),
  );
  double get activeLayerTransformOpacity => _activeLayer.opacity;
  CanvasLayerBlendMode get activeLayerTransformBlendMode =>
      _activeLayer.blendMode;
  bool get isActiveLayerTransformPendingCleanup =>
      _pendingActiveLayerTransformCleanup;

  bool get hasVisibleContent {
    for (int i = 0; i < _layers.length; i++) {
      final BitmapLayerState layer = _layers[i];
      if (i == 0) {
        continue;
      }
      if (layer.visible && !_isSurfaceEmpty(layer.surface)) {
        return true;
      }
    }
    return false;
  }

  void configureStylusPressure({
    required bool enabled,
    required double minFactor,
    required double maxFactor,
    required double curve,
  }) =>
      _strokeConfigureStylusPressure(
        this,
        enabled: enabled,
        minFactor: minFactor,
        maxFactor: maxFactor,
        curve: curve,
      );

  void setSelectionMask(Uint8List? mask) =>
      _fillSetSelectionMask(this, mask);

  bool _runAntialiasPass(
    Uint32List src,
    Uint32List dest,
    int width,
    int height,
    double blendFactor,
  ) {
    dest.setAll(0, src);
    if (blendFactor <= 0) {
      return false;
    }
    final double factor = blendFactor.clamp(0.0, 1.0);
    bool modified = false;
    for (int y = 0; y < height; y++) {
      final int rowOffset = y * width;
      for (int x = 0; x < width; x++) {
        final int index = rowOffset + x;
        final int center = src[index];
        final int alpha = (center >> 24) & 0xff;

        int totalWeight = _kAntialiasCenterWeight;
        int weightedAlpha = alpha * _kAntialiasCenterWeight;
        int weightedPremulR =
            ((center >> 16) & 0xff) * alpha * _kAntialiasCenterWeight;
        int weightedPremulG =
            ((center >> 8) & 0xff) * alpha * _kAntialiasCenterWeight;
        int weightedPremulB = (center & 0xff) * alpha * _kAntialiasCenterWeight;

        for (int i = 0; i < _kAntialiasDx.length; i++) {
          final int nx = x + _kAntialiasDx[i];
          final int ny = y + _kAntialiasDy[i];
          if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
            continue;
          }
          final int neighbor = src[ny * width + nx];
          final int neighborAlpha = (neighbor >> 24) & 0xff;
          final int weight = _kAntialiasWeights[i];
          totalWeight += weight;
          if (neighborAlpha == 0) {
            continue;
          }
          weightedAlpha += neighborAlpha * weight;
          weightedPremulR += ((neighbor >> 16) & 0xff) * neighborAlpha * weight;
          weightedPremulG += ((neighbor >> 8) & 0xff) * neighborAlpha * weight;
          weightedPremulB += (neighbor & 0xff) * neighborAlpha * weight;
        }

        if (totalWeight <= 0) {
          continue;
        }

        final int candidateAlpha = (weightedAlpha ~/ totalWeight).clamp(0, 255);
        if (candidateAlpha <= alpha) {
          continue;
        }

        final int newAlpha =
            (alpha + ((candidateAlpha - alpha) * factor).round()).clamp(
              alpha + 1,
              255,
            );
        if (newAlpha <= alpha) {
          continue;
        }

        final int boundedWeightedAlpha = math.max(weightedAlpha, 1);
        final int neighborColorR = (weightedPremulR ~/ boundedWeightedAlpha)
            .clamp(0, 255);
        final int neighborColorG = (weightedPremulG ~/ boundedWeightedAlpha)
            .clamp(0, 255);
        final int neighborColorB = (weightedPremulB ~/ boundedWeightedAlpha)
            .clamp(0, 255);

        final int newR = neighborColorR;
        final int newG = neighborColorG;
        final int newB = neighborColorB;

        dest[index] = (newAlpha << 24) | (newR << 16) | (newG << 8) | newB;
        modified = true;
      }
    }
    return modified;
  }

  void translateActiveLayer(int dx, int dy) =>
      _translateActiveLayer(this, dx, dy);

  void commitActiveLayerTranslation() =>
      _commitActiveLayerTranslation(this);

  void cancelActiveLayerTranslation() =>
      _cancelActiveLayerTranslation(this);

  Future<void> disposeController() async {
    _cachedImage?.dispose();
    _cachedImage = null;
    _disposeActiveLayerTransformImage(this);
    _activeLayerTransformPreparing = false;
  }

  void setActiveLayer(String id) =>
      _layerManagerSetActiveLayer(this, id);

  void updateLayerVisibility(String id, bool visible) =>
      _layerManagerUpdateVisibility(this, id, visible);

  void setLayerOpacity(String id, double opacity) =>
      _layerManagerSetOpacity(this, id, opacity);

  void setLayerLocked(String id, bool locked) =>
      _layerManagerSetLocked(this, id, locked);

  void setLayerClippingMask(String id, bool clippingMask) =>
      _layerManagerSetClippingMask(this, id, clippingMask);

  void setLayerBlendMode(String id, CanvasLayerBlendMode mode) =>
      _layerManagerSetBlendMode(this, id, mode);

  void renameLayer(String id, String name) =>
      _layerManagerRenameLayer(this, id, name);

  void addLayer({String? aboveLayerId, String? name}) =>
      _layerManagerAddLayer(this, aboveLayerId: aboveLayerId, name: name);

  void removeLayer(String id) => _layerManagerRemoveLayer(this, id);

  void reorderLayer(int fromIndex, int toIndex) =>
      _layerManagerReorderLayer(this, fromIndex, toIndex);

  void clear() => _layerManagerClearAll(this);

  void beginStroke(
    Offset position, {
    required Color color,
    required double radius,
    bool simulatePressure = false,
    bool useDevicePressure = false,
    double? pressure,
    double? pressureMin,
    double? pressureMax,
    StrokePressureProfile profile = StrokePressureProfile.auto,
    double? timestampMillis,
    int antialiasLevel = 0,
  }) =>
      _strokeBegin(
        this,
        position,
        color: color,
        radius: radius,
        simulatePressure: simulatePressure,
        useDevicePressure: useDevicePressure,
        pressure: pressure,
        pressureMin: pressureMin,
        pressureMax: pressureMax,
        profile: profile,
        timestampMillis: timestampMillis,
        antialiasLevel: antialiasLevel,
      );

  void extendStroke(
    Offset position, {
    double? deltaTimeMillis,
    double? timestampMillis,
    double? pressure,
    double? pressureMin,
    double? pressureMax,
  }) =>
      _strokeExtend(
        this,
        position,
        deltaTimeMillis: deltaTimeMillis,
        timestampMillis: timestampMillis,
        pressure: pressure,
        pressureMin: pressureMin,
        pressureMax: pressureMax,
      );

  void endStroke() => _strokeEnd(this);

  bool applyAntialiasToActiveLayer(int level, {bool previewOnly = false}) {
    if (_layers.isEmpty) {
      return false;
    }
    final BitmapLayerState layer = _activeLayer;
    if (layer.locked) {
      return false;
    }
    final List<double> profile = List<double>.from(
      _kAntialiasBlendProfiles[level.clamp(0, 3)] ?? const <double>[0.25],
    );
    if (profile.isEmpty) {
      return false;
    }
    final Uint32List pixels = layer.surface.pixels;
    if (pixels.isEmpty) {
      return false;
    }
    final Uint32List temp = Uint32List(pixels.length);
    Uint32List src = pixels;
    Uint32List dest = temp;
    bool anyChange = false;
    for (final double factor in profile) {
      if (factor <= 0) {
        continue;
      }
      final bool changed = _runAntialiasPass(
        src,
        dest,
        _width,
        _height,
        factor,
      );
      if (!changed) {
        continue;
      }
      if (previewOnly) {
        return true;
      }
      anyChange = true;
      final Uint32List swap = src;
      src = dest;
      dest = swap;
    }
    if (!anyChange) {
      return false;
    }
    if (previewOnly) {
      return true;
    }
    if (!identical(src, pixels)) {
      pixels.setAll(0, src);
    }
    _markDirty();
    notifyListeners();
    return true;
  }

  void setStrokePressureProfile(StrokePressureProfile profile) =>
      _strokeSetPressureProfile(this, profile);

  double? _normalizeStylusPressure(
    double? pressure,
    double? pressureMin,
    double? pressureMax,
  ) =>
      _strokeNormalizeStylusPressure(
        this,
        pressure,
        pressureMin,
        pressureMax,
      );

  double _stylusRadiusFromNormalized(double normalized) =>
      _strokeRadiusFromNormalized(this, normalized);

  bool _selectionAllows(Offset position) =>
      _fillSelectionAllows(this, position);

  bool _selectionAllowsInt(int x, int y) =>
      _fillSelectionAllowsInt(this, x, y);

  void floodFill(
    Offset position, {
    required Color color,
    bool contiguous = true,
    bool sampleAllLayers = false,
  }) =>
      _fillFloodFill(
        this,
        position,
        color: color,
        contiguous: contiguous,
        sampleAllLayers: sampleAllLayers,
      );

  Uint8List? computeMagicWandMask(
    Offset position, {
    bool sampleAllLayers = true,
  }) =>
      _fillComputeMagicWandMask(
        this,
        position,
        sampleAllLayers: sampleAllLayers,
      );

  List<CanvasLayerData> snapshotLayers() =>
      _layerManagerSnapshotLayers(this);

  CanvasLayerData? buildClipboardLayer(String id, {Uint8List? mask}) =>
      _layerManagerBuildClipboardLayer(this, id, mask: mask);

  void clearLayerRegion(String id, {Uint8List? mask}) =>
      _layerManagerClearRegion(this, id, mask: mask);

  String insertLayerFromData(CanvasLayerData data, {String? aboveLayerId}) =>
      _layerManagerInsertFromData(this, data, aboveLayerId: aboveLayerId);

  void loadLayers(List<CanvasLayerData> layers, Color backgroundColor) =>
      _layerManagerLoadLayers(this, layers, backgroundColor);

  void _updateComposite({required bool requiresFullSurface, Rect? region}) =>
      _compositeUpdate(
        this,
        requiresFullSurface: requiresFullSurface,
        region: region,
      );

  void _drawPoint(Offset position, double radius) =>
      _strokeDrawPoint(this, position, radius);

  Rect _dirtyRectForVariableLine(
    Offset a,
    Offset b,
    double startRadius,
    double endRadius,
  ) =>
      _strokeDirtyRectForVariableLine(a, b, startRadius, endRadius);

  void _markDirty({Rect? region}) =>
      _compositeMarkDirty(this, region: region);

  void _scheduleCompositeRefresh() =>
      _compositeScheduleRefresh(this);

  BitmapLayerState get _activeLayer => _layers[_activeIndex];

  BitmapSurface get _activeSurface => _activeLayer.surface;

  static bool _isSurfaceEmpty(BitmapSurface surface) {
    for (final int pixel in surface.pixels) {
      if ((pixel >> 24) != 0) {
        return false;
      }
    }
    return true;
  }

  Color _colorAtComposite(Offset position) =>
      _fillColorAtComposite(this, position);

  Color sampleColor(Offset position, {bool sampleAllLayers = true}) =>
      _fillSampleColor(this, position, sampleAllLayers: sampleAllLayers);


  Color _colorAtSurface(BitmapSurface surface, int x, int y) =>
      _fillColorAtSurface(this, surface, x, y);

  static Uint8List _surfaceToRgba(BitmapSurface surface) {
    final Uint8List rgba = Uint8List(surface.pixels.length * 4);
    for (int i = 0; i < surface.pixels.length; i++) {
      final int argb = surface.pixels[i];
      final int offset = i * 4;
      rgba[offset] = (argb >> 16) & 0xff;
      rgba[offset + 1] = (argb >> 8) & 0xff;
      rgba[offset + 2] = argb & 0xff;
      rgba[offset + 3] = (argb >> 24) & 0xff;
    }
    return rgba;
  }

  static Uint8List _pixelsToRgba(Uint32List pixels) {
    final Uint8List rgba = Uint8List(pixels.length * 4);
    for (int i = 0; i < pixels.length; i++) {
      final int argb = pixels[i];
      final int offset = i * 4;
      rgba[offset] = (argb >> 16) & 0xff;
      rgba[offset + 1] = (argb >> 8) & 0xff;
      rgba[offset + 2] = argb & 0xff;
      rgba[offset + 3] = (argb >> 24) & 0xff;
    }
    return rgba;
  }

  static Rect _unionRects(Rect a, Rect b) {
    return Rect.fromLTRB(
      math.min(a.left, b.left),
      math.min(a.top, b.top),
      math.max(a.right, b.right),
      math.max(a.bottom, b.bottom),
    );
  }

  static Uint8List _surfaceToMaskedRgba(BitmapSurface surface, Uint8List mask) {
    final Uint32List pixels = surface.pixels;
    final Uint8List rgba = Uint8List(pixels.length * 4);
    for (int i = 0; i < pixels.length; i++) {
      if (mask[i] == 0) {
        continue;
      }
      final int argb = pixels[i];
      final int offset = i * 4;
      rgba[offset] = (argb >> 16) & 0xff;
      rgba[offset + 1] = (argb >> 8) & 0xff;
      rgba[offset + 2] = argb & 0xff;
      rgba[offset + 3] = (argb >> 24) & 0xff;
    }
    return rgba;
  }

  static bool _maskHasCoverage(Uint8List mask) {
    for (final int value in mask) {
      if (value != 0) {
        return true;
      }
    }
    return false;
  }

  static void _writeRgbaToSurface(BitmapSurface surface, Uint8List rgba) {
    final Uint32List pixels = surface.pixels;
    for (int i = 0; i < pixels.length; i++) {
      final int offset = i * 4;
      final int r = rgba[offset];
      final int g = rgba[offset + 1];
      final int b = rgba[offset + 2];
      final int a = rgba[offset + 3];
      pixels[i] = (a << 24) | (r << 16) | (g << 8) | b;
    }
  }

  void _ensureCompositeBuffers() => _compositeEnsureBuffers(this);

  Uint8List _ensureClipMask() => _compositeEnsureClipMask(this);

  static double _clampUnit(double value) {
    if (value <= 0) {
      return 0;
    }
    if (value >= 1) {
      return 1;
    }
    return value;
  }

  _IntRect _clipRectToSurface(Rect rect) =>
      _compositeClipRectToSurface(this, rect);

  Rect _dirtyRectForCircle(Offset center, double radius) =>
      _strokeDirtyRectForCircle(center, radius);

  Rect _dirtyRectForLine(Offset a, Offset b, double radius) =>
      _strokeDirtyRectForLine(a, b, radius);

  static int _blendArgb(int dst, int src) {
    final int srcA = (src >> 24) & 0xff;
    if (srcA == 0) {
      return dst;
    }
    if (srcA == 255) {
      return src;
    }

    final int dstA = (dst >> 24) & 0xff;
    final int invSrcA = 255 - srcA;
    final int outA = srcA + _mul255(dstA, invSrcA);
    if (outA == 0) {
      return 0;
    }

    final int srcR = (src >> 16) & 0xff;
    final int srcG = (src >> 8) & 0xff;
    final int srcB = src & 0xff;
    final int dstR = (dst >> 16) & 0xff;
    final int dstG = (dst >> 8) & 0xff;
    final int dstB = dst & 0xff;

    final int srcPremR = _mul255(srcR, srcA);
    final int srcPremG = _mul255(srcG, srcA);
    final int srcPremB = _mul255(srcB, srcA);
    final int dstPremR = _mul255(dstR, dstA);
    final int dstPremG = _mul255(dstG, dstA);
    final int dstPremB = _mul255(dstB, dstA);

    final int outPremR = srcPremR + _mul255(dstPremR, invSrcA);
    final int outPremG = srcPremG + _mul255(dstPremG, invSrcA);
    final int outPremB = srcPremB + _mul255(dstPremB, invSrcA);

    final int outR = _clampToByte(((outPremR * 255) + (outA >> 1)) ~/ outA);
    final int outG = _clampToByte(((outPremG * 255) + (outA >> 1)) ~/ outA);
    final int outB = _clampToByte(((outPremB * 255) + (outA >> 1)) ~/ outA);

    return (outA << 24) | (outR << 16) | (outG << 8) | outB;
  }

  static int _blendWithMode(
    int dst,
    int src,
    CanvasLayerBlendMode mode,
    int pixelIndex,
  ) {
    return CanvasBlendMath.blend(dst, src, mode, pixelIndex: pixelIndex);
  }

  static int _mul255(int channel, int alpha) {
    return (channel * alpha + 127) ~/ 255;
  }

  static int _clampToByte(int value) {
    if (value <= 0) {
      return 0;
    }
    if (value >= 255) {
      return 255;
    }
    return value;
  }
}

class _IntRect {
  const _IntRect(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;

  bool get isEmpty => left >= right || top >= bottom;
}
