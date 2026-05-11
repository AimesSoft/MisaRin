import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

import '../../bitmap_canvas/bitmap_canvas.dart';
import '../../brushes/brush_library.dart';
import '../../brushes/brush_preset.dart';
import '../../brushes/brush_shape_library.dart';
import '../../brushes/brush_shape_raster.dart';
import '../../canvas/brush_random_rotation.dart';
import '../../canvas/brush_shape_geometry.dart';
import '../../canvas/canvas_tools.dart';
import '../debug/brush_preset_timeline.dart';
import '../../src/rust/canvas_engine_ffi.dart' as rust_wgpu_engine;
import '../../src/rust/rust_cpu_brush_ffi.dart';
import '../../src/rust/rust_init.dart';

const double _kPreviewPadding = 4.0;
const double _kPreviewPressureMinFactor = 0.09; // Keep in sync with rust.
const int _kEnginePointStrideBytes = 32;
const int _kPointFlagDown = 1;
const int _kPointFlagMove = 2;
const int _kPointFlagUp = 4;
const bool _kPreviewLog = bool.fromEnvironment(
  'MISA_RIN_BRUSH_PREVIEW_LOG',
  defaultValue: false,
);

void _logPreview(String message) {
  if (_kPreviewLog) {
    debugPrint('[brush-preview] $message');
  }
}

class BrushPresetStrokePreview extends StatefulWidget {
  const BrushPresetStrokePreview({
    super.key,
    required this.preset,
    required this.height,
    required this.color,
  });

  final BrushPreset preset;
  final double height;
  final Color color;

  @override
  State<BrushPresetStrokePreview> createState() =>
      _BrushPresetStrokePreviewState();
}

class _BrushPresetStrokePreviewState extends State<BrushPresetStrokePreview> {
  ui.Image? _image;
  int _signature = 0;
  int _renderToken = 0;
  String? _pendingShapeId;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : widget.height * 3.0;
          final Size size = Size(width, widget.height);
          _ensurePreview(context, size);
          if (_image != null) {
            return RawImage(
              image: _image,
              width: size.width,
              height: size.height,
              fit: BoxFit.fill,
              filterQuality: widget.preset.snapToPixel
                  ? FilterQuality.none
                  : FilterQuality.high,
            );
          }
          return const SizedBox();
        },
      ),
    );
  }

  void _ensurePreview(BuildContext context, Size size) {
    final bool canRender = rust_wgpu_engine.CanvasEngineFfi.instance.canCreateEngine;
    if (!canRender) {
      return;
    }
    if (size.isEmpty) {
      return;
    }
    final double deviceScale =
        MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final double scale = deviceScale.clamp(1.0, 2.0);
    final int pixelWidth = (size.width * scale).round();
    final int pixelHeight = (size.height * scale).round();
    if (pixelWidth <= 0 || pixelHeight <= 0) {
      return;
    }
    final BrushPreset preset = widget.preset.sanitized();
    final BrushShapeLibrary shapeLibrary = BrushLibrary.instance.shapeLibrary;
    final String shapeId = preset.resolvedShapeId;
    final int nextSignature = Object.hashAll(<Object?>[
      pixelWidth,
      pixelHeight,
      preset.id,
      shapeId,
      preset.shape,
      preset.spacing,
      preset.hardness,
      preset.flow,
      preset.scatter,
      preset.randomRotation,
      preset.smoothRotation,
      preset.rotationJitter,
      preset.antialiasLevel,
      preset.hollowEnabled,
      preset.hollowRatio,
      preset.autoSharpTaper,
      preset.snapToPixel,
      preset.screentoneEnabled,
      preset.screentoneSpacing,
      preset.screentoneDotSize,
      preset.screentoneRotation,
      preset.screentoneSoftness,
      preset.screentoneShape,
      widget.color.value,
      scale,
    ]);
    if (!shapeLibrary.isBuiltInId(shapeId) &&
        shapeLibrary.getCachedRaster(shapeId) == null) {
      if (_pendingShapeId != shapeId) {
        _pendingShapeId = shapeId;
        shapeLibrary.loadRaster(shapeId).then((BrushShapeRaster? raster) {
          if (!mounted) {
            return;
          }
          if (_pendingShapeId == shapeId) {
            _pendingShapeId = null;
          }
          if (raster != null) {
            setState(() {
              _signature = 0;
            });
          }
        });
      }
      if (_image != null) {
        _image?.dispose();
        _image = null;
      }
      _signature = nextSignature;
      return;
    }
    if (nextSignature == _signature) {
      return;
    }
    _logPreview(
      'schedule id=${preset.id} size=${pixelWidth}x${pixelHeight} '
      'scale=$scale aa=${preset.antialiasLevel} snap=${preset.snapToPixel} '
      'hardness=${preset.hardness} flow=${preset.flow} shape=${preset.shape} '
      'wgpuSupported=${rust_wgpu_engine.CanvasEngineFfi.instance.canCreateEngine}',
    );
    _signature = nextSignature;
    if (BrushPresetTimeline.enabled) {
      BrushPresetTimeline.mark(
        'preview_schedule id=${preset.id} ${pixelWidth}x${pixelHeight} scale=$scale',
      );
    }
    final int token = ++_renderToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _renderPreview(token, preset, pixelWidth, pixelHeight, scale);
    });
  }

  Future<void> _renderPreview(
    int token,
    BrushPreset preset,
    int pixelWidth,
    int pixelHeight,
    double scale,
  ) async {
    if (!mounted || token != _renderToken) {
      return;
    }
    final Stopwatch? stopwatch = BrushPresetTimeline.enabled
        ? (Stopwatch()..start())
        : null;
    final ui.Image? image = await _buildPreviewImage(
      preset: preset,
      color: widget.color,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      scale: scale,
    );
    if (stopwatch != null) {
      BrushPresetTimeline.mark(
        'preview_done id=${preset.id} ${pixelWidth}x${pixelHeight} '
        't=${stopwatch.elapsedMilliseconds}ms image=${image != null}',
      );
    }
    _logPreview(
      'done id=${preset.id} image=${image != null} '
      'aa=${preset.antialiasLevel} snap=${preset.snapToPixel}',
    );
    if (!mounted || token != _renderToken) {
      image?.dispose();
      return;
    }
    if (image == null) {
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
    });
  }
}

class _PreviewStrokeSample {
  const _PreviewStrokeSample({
    required this.position,
    required this.radius,
  });

  final Offset position;
  final double radius;
}

List<_PreviewStrokeSample> _buildPreviewSamples({
  required BrushPreset preset,
  required int pixelWidth,
  required int pixelHeight,
  required double scale,
  required double spacing,
}) {
  final double padding = _kPreviewPadding * scale;
  final double width = pixelWidth - padding * 2.0;
  final double height = pixelHeight - padding * 2.0;
  if (width <= 0 || height <= 0) {
    return <_PreviewStrokeSample>[];
  }

  final Offset start = Offset(padding, padding + height * 0.65);
  final Offset control1 =
      Offset(padding + width * 0.3, padding + height * 0.1);
  final Offset control2 =
      Offset(padding + width * 0.65, padding + height * 0.9);
  final Offset end = Offset(padding + width, padding + height * 0.35);

  final ui.Path path = ui.Path()
    ..moveTo(start.dx, start.dy)
    ..cubicTo(
      control1.dx,
      control1.dy,
      control2.dx,
      control2.dy,
      end.dx,
      end.dy,
    );
  final ui.PathMetrics metrics = path.computeMetrics();
  final Iterator<ui.PathMetric> iterator = metrics.iterator;
  if (!iterator.moveNext()) {
    return <_PreviewStrokeSample>[];
  }
  final ui.PathMetric metric = iterator.current;

  final double baseRadius = math.max(2.2 * scale, height * 0.2);
  final double step = math.max(0.1 * scale, baseRadius * 2.0 * spacing);
  final double totalLength = metric.length;
  final int maxStamps = math.max(6, (totalLength / step).ceil());
  final List<_PreviewStrokeSample> samples = <_PreviewStrokeSample>[];
  for (int i = 0; i <= maxStamps; i++) {
    final double distance = math.min(totalLength, i * step);
    final ui.Tangent? tangent = metric.getTangentForOffset(distance);
    if (tangent == null) {
      continue;
    }
    double radius = baseRadius;
    if (preset.autoSharpTaper && totalLength > 0.0001) {
      final double t = distance / totalLength;
      radius *= (0.5 + 0.5 * math.sin(math.pi * t));
    }
    if (!radius.isFinite || radius <= 0.0) {
      continue;
    }
    samples.add(_PreviewStrokeSample(position: tangent.position, radius: radius));
  }
  return samples;
}

Float32List _encodePreviewSamples(List<_PreviewStrokeSample> samples) {
  final int count = samples.length;
  final Float32List data = Float32List(count * 3);
  int out = 0;
  for (final _PreviewStrokeSample sample in samples) {
    data[out++] = sample.position.dx;
    data[out++] = sample.position.dy;
    data[out++] = sample.radius;
  }
  return data;
}

TransferableTypedData _toTransferableFloat32(Float32List data) {
  return TransferableTypedData.fromList(<Uint8List>[
    Uint8List.view(
      data.buffer,
      data.offsetInBytes,
      data.lengthInBytes,
    ),
  ]);
}

List<_PreviewStrokeSample> _decodePreviewSamples(Float32List data) {
  final int count = data.length ~/ 3;
  final List<_PreviewStrokeSample> samples = <_PreviewStrokeSample>[];
  int index = 0;
  for (int i = 0; i < count; i++) {
    final double x = data[index++];
    final double y = data[index++];
    final double radius = data[index++];
    samples.add(_PreviewStrokeSample(position: Offset(x, y), radius: radius));
  }
  return samples;
}

double _maxSampleRadius(List<_PreviewStrokeSample> samples) {
  double maxRadius = 0.0;
  for (final _PreviewStrokeSample sample in samples) {
    final double r = sample.radius;
    if (r.isFinite && r > maxRadius) {
      maxRadius = r;
    }
  }
  return maxRadius;
}

double _pressureFromRadius(double radius, double baseRadius) {
  if (!radius.isFinite || !baseRadius.isFinite || baseRadius <= 0.0) {
    return 1.0;
  }
  final double normalized = radius / baseRadius;
  final double denom = 1.0 - _kPreviewPressureMinFactor;
  if (denom <= 0.0) {
    return 1.0;
  }
  final double pressure = (normalized - _kPreviewPressureMinFactor) / denom;
  return pressure.clamp(0.0, 1.0);
}

bool _rgbaHasNonZeroAlpha(Uint8List rgba) {
  for (int i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 0) {
      return true;
    }
  }
  return false;
}

Uint8List _encodeEnginePoints(
  List<_PreviewStrokeSample> samples,
  double baseRadius,
) {
  final int count = samples.length;
  final Uint8List bytes = Uint8List(count * _kEnginePointStrideBytes);
  final ByteData data = ByteData.view(bytes.buffer);
  int timestampUs = 0;
  for (int i = 0; i < count; i++) {
    final _PreviewStrokeSample sample = samples[i];
    final int offset = i * _kEnginePointStrideBytes;
    final double pressure = _pressureFromRadius(sample.radius, baseRadius);
    final bool isFirst = i == 0;
    final bool isLast = i == count - 1;
    int flags = 0;
    if (isFirst) {
      flags |= _kPointFlagDown;
    } else {
      flags |= _kPointFlagMove;
    }
    if (isLast) {
      flags |= _kPointFlagUp;
    }
    data.setFloat32(offset + 0, sample.position.dx, Endian.little);
    data.setFloat32(offset + 4, sample.position.dy, Endian.little);
    data.setFloat32(offset + 8, pressure, Endian.little);
    data.setFloat32(offset + 12, 0.0, Endian.little); // pad
    data.setUint64(offset + 16, timestampUs, Endian.little);
    data.setUint32(offset + 24, flags, Endian.little);
    data.setUint32(offset + 28, 0, Endian.little); // pointerId
    timestampUs += 16000;
  }
  return bytes;
}

Future<ui.Image?> _buildPreviewImage({
  required BrushPreset preset,
  required Color color,
  required int pixelWidth,
  required int pixelHeight,
  required double scale,
}) async {
  final bool canRender = rust_wgpu_engine.CanvasEngineFfi.instance.canCreateEngine;
  if (!canRender) {
    return null;
  }
  final double spacing = _effectiveSpacing(preset.spacing);
  final List<_PreviewStrokeSample> samples = _buildPreviewSamples(
    preset: preset,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    scale: scale,
    spacing: spacing,
  );
  if (samples.isEmpty) {
    return null;
  }

  final BrushShapeRaster? customShape = await _resolveCustomShape(preset);
  final int antialias = _effectiveAntialias(preset.antialiasLevel);
  final int rotationSeed = Object.hash(
    preset.id,
    preset.shape,
    pixelWidth,
    pixelHeight,
  );
  final Float32List sampleData = _encodePreviewSamples(samples);
  final _BrushPreviewWorkerResult? workerResult =
      await _BrushPreviewWorker.instance.request(
    _BrushPreviewRequest(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      colorArgb: color.value,
      hardness: preset.hardness,
      flow: preset.flow,
      spacing: spacing,
      scatter: preset.scatter,
      randomRotation: preset.randomRotation,
      smoothRotation: preset.smoothRotation,
      rotationJitter: preset.rotationJitter,
      antialias: antialias,
      snapToPixel: preset.snapToPixel,
      shapeIndex: preset.shape.index,
      screentoneEnabled: preset.screentoneEnabled,
      screentoneSpacing: preset.screentoneSpacing,
      screentoneDotSize: preset.screentoneDotSize,
      screentoneRotation: preset.screentoneRotation,
      screentoneSoftness: preset.screentoneSoftness,
      screentoneShapeIndex: preset.screentoneShape.index,
      hollowEnabled:
          preset.hollowEnabled && preset.hollowRatio > 0.0001,
      hollowRatio: preset.hollowRatio.clamp(0.0, 1.0),
      rotationSeed: rotationSeed,
      samples: _toTransferableFloat32(sampleData),
      customMask: customShape == null
          ? null
          : TransferableTypedData.fromList(<Uint8List>[
              Uint8List.fromList(customShape.packedMask),
            ]),
      customMaskWidth: customShape?.width ?? 0,
      customMaskHeight: customShape?.height ?? 0,
    ),
  );
  if (workerResult != null) {
    _logPreview(
      'result backend=${workerResult.backend ?? 'none'} '
      'size=${workerResult.width}x${workerResult.height}',
    );
    final Uint8List? rgba = workerResult.pixels;
    if (rgba != null && rgba.isNotEmpty) {
      return _decodeRgbaImage(rgba, workerResult.width, workerResult.height);
    }
    return null;
  }
  return null;
}

// ignore: unused_element
Future<ui.Image?> _buildPreviewImageOnMain({
  required BrushPreset preset,
  required Color color,
  required int pixelWidth,
  required int pixelHeight,
  required double scale,
}) async {
  final bool canRender = rust_wgpu_engine.CanvasEngineFfi.instance.canCreateEngine;
  if (!canRender) {
    return null;
  }
  if (pixelWidth <= 0 || pixelHeight <= 0) {
    return null;
  }
  final BitmapSurface surface = BitmapSurface(
    width: pixelWidth,
    height: pixelHeight,
    fillColor: const Color(0x00000000),
  );
  try {
    final Stopwatch? shapeTimer = BrushPresetTimeline.enabled
        ? (Stopwatch()..start())
        : null;
    final BrushShapeRaster? customShape = await _resolveCustomShape(preset);
    if (shapeTimer != null && shapeTimer.elapsedMilliseconds > 0) {
      BrushPresetTimeline.mark(
        'preview_shape id=${preset.resolvedShapeId} '
        't=${shapeTimer.elapsedMilliseconds}ms',
      );
    }
    final double spacing = _effectiveSpacing(preset.spacing);
    final List<_PreviewStrokeSample> samples = _buildPreviewSamples(
      preset: preset,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      scale: scale,
      spacing: spacing,
    );
    if (samples.isEmpty) {
      return null;
    }

    final double hardness = preset.hardness;
    final double flow = preset.flow;
    final double opacity = (0.25 + 0.75 * flow * (0.35 + 0.65 * hardness))
        .clamp(0.18, 1.0);
    final Color strokeColor = color.withOpacity(
      (color.opacity * opacity).clamp(0.0, 1.0),
    );
    final double softness = (1.0 - hardness).clamp(0.0, 1.0);
    final int antialias = _effectiveAntialias(preset.antialiasLevel);
    final int rotationSeed = Object.hash(
      preset.id,
      preset.shape,
      pixelWidth,
      pixelHeight,
    );

    _drawStrokeSegments(
      surface: surface,
      samples: samples,
      shape: preset.shape,
      scatter: preset.scatter,
      randomRotation: preset.randomRotation,
      smoothRotation: preset.smoothRotation,
      rotationJitter: preset.rotationJitter,
      snapToPixel: preset.snapToPixel,
      screentoneEnabled: preset.screentoneEnabled,
      screentoneSpacing: preset.screentoneSpacing,
      screentoneDotSize: preset.screentoneDotSize,
      screentoneRotation: preset.screentoneRotation,
      screentoneSoftness: preset.screentoneSoftness,
      screentoneShape: preset.screentoneShape,
      color: strokeColor,
      softness: softness,
      antialias: antialias,
      spacing: spacing,
      rotationSeed: rotationSeed,
      erase: false,
      radiusScale: 1.0,
      customShape: customShape,
    );

    final bool hollow =
        preset.hollowEnabled && preset.hollowRatio > 0.0001;
    if (hollow) {
      _drawStrokeSegments(
        surface: surface,
        samples: samples,
        shape: preset.shape,
        scatter: preset.scatter,
        randomRotation: preset.randomRotation,
        smoothRotation: preset.smoothRotation,
        rotationJitter: preset.rotationJitter,
        snapToPixel: preset.snapToPixel,
        screentoneEnabled: preset.screentoneEnabled,
        screentoneSpacing: preset.screentoneSpacing,
        screentoneDotSize: preset.screentoneDotSize,
        screentoneRotation: preset.screentoneRotation,
        screentoneSoftness: preset.screentoneSoftness,
        screentoneShape: preset.screentoneShape,
        color: strokeColor,
        softness: softness,
        antialias: antialias,
        spacing: spacing,
        rotationSeed: rotationSeed,
        erase: true,
        radiusScale: preset.hollowRatio.clamp(0.0, 1.0),
        customShape: customShape,
      );
    }

    if (_kPreviewLog) {
      final _AlphaStats stats = _computeAlphaStats(surface.pixels);
      debugPrint(
        '[brush-preview] alpha id=${preset.id} aa=$antialias '
        'nonZero=${stats.nonZero} partial=${stats.partial} '
        'min=${stats.min} max=${stats.max}',
      );
    }

    if (surface.isClean) {
      return null;
    }
    final Uint8List rgba = _argbToRgba(surface.pixels);
    return _decodeRgbaImage(rgba, pixelWidth, pixelHeight);
  } finally {
    surface.dispose();
  }
}

Future<BrushShapeRaster?> _resolveCustomShape(BrushPreset preset) async {
  final BrushShapeLibrary shapes = BrushLibrary.instance.shapeLibrary;
  final String shapeId = preset.resolvedShapeId;
  if (shapes.isBuiltInId(shapeId)) {
    return null;
  }
  return shapes.loadRaster(shapeId);
}

double _effectiveSpacing(double spacing) {
  double value = spacing.isFinite ? spacing : 0.15;
  return value.clamp(0.02, 2.5);
}

int _effectiveAntialias(int level) {
  return level.clamp(0, 9);
}

void _drawStrokeSegments({
  required BitmapSurface surface,
  required List<_PreviewStrokeSample> samples,
  required BrushShape shape,
  required double scatter,
  required bool randomRotation,
  required bool smoothRotation,
  required double rotationJitter,
  required bool snapToPixel,
  required bool screentoneEnabled,
  required double screentoneSpacing,
  required double screentoneDotSize,
  required double screentoneRotation,
  required double screentoneSoftness,
  required BrushShape screentoneShape,
  required Color color,
  required double softness,
  required int antialias,
  required double spacing,
  required int rotationSeed,
  required bool erase,
  required double radiusScale,
  BrushShapeRaster? customShape,
}) {
  if (samples.isEmpty) {
    return;
  }

  final _PreviewStrokeSample first = samples.first;
  _drawStampSegment(
    surface: surface,
    start: first.position,
    end: first.position,
    startRadius: first.radius * radiusScale,
    endRadius: first.radius * radiusScale,
    color: color,
    shape: shape,
    antialias: antialias,
    includeStart: true,
    erase: erase,
    randomRotation: randomRotation,
    smoothRotation: smoothRotation,
    rotationSeed: rotationSeed,
    rotationJitter: rotationJitter,
    spacing: spacing,
    scatter: scatter,
    softness: softness,
    snapToPixel: snapToPixel,
    screentoneEnabled: screentoneEnabled,
    screentoneSpacing: screentoneSpacing,
    screentoneDotSize: screentoneDotSize,
    screentoneRotation: screentoneRotation,
    screentoneSoftness: screentoneSoftness,
    screentoneShape: screentoneShape,
    customShape: customShape,
  );

  for (int i = 0; i < samples.length - 1; i++) {
    final _PreviewStrokeSample a = samples[i];
    final _PreviewStrokeSample b = samples[i + 1];
    _drawStampSegment(
      surface: surface,
      start: a.position,
      end: b.position,
      startRadius: a.radius * radiusScale,
      endRadius: b.radius * radiusScale,
      color: color,
      shape: shape,
      antialias: antialias,
      includeStart: false,
      erase: erase,
      randomRotation: randomRotation,
      smoothRotation: smoothRotation,
      rotationSeed: rotationSeed,
      rotationJitter: rotationJitter,
      spacing: spacing,
      scatter: scatter,
      softness: softness,
      snapToPixel: snapToPixel,
      screentoneEnabled: screentoneEnabled,
      screentoneSpacing: screentoneSpacing,
      screentoneDotSize: screentoneDotSize,
      screentoneRotation: screentoneRotation,
      screentoneSoftness: screentoneSoftness,
      screentoneShape: screentoneShape,
      customShape: customShape,
    );
  }
}

void _drawStampSegment({
  required BitmapSurface surface,
  required Offset start,
  required Offset end,
  required double startRadius,
  required double endRadius,
  required Color color,
  required BrushShape shape,
  required int antialias,
  required bool includeStart,
  required bool erase,
  required bool randomRotation,
  required bool smoothRotation,
  required int rotationSeed,
  required double rotationJitter,
  required double spacing,
  required double scatter,
  required double softness,
  required bool snapToPixel,
  required bool screentoneEnabled,
  required double screentoneSpacing,
  required double screentoneDotSize,
  required double screentoneRotation,
  required double screentoneSoftness,
  required BrushShape screentoneShape,
  BrushShapeRaster? customShape,
}) {
  if (customShape != null) {
    final Uint8List customMask = customShape.packedMask;
    final bool ok = RustCpuBrushFfi.instance.drawStampSegment(
      pixelsPtr: surface.pointerAddress,
      pixelsLen: surface.pixels.length,
      width: surface.width,
      height: surface.height,
      startX: start.dx,
      startY: start.dy,
      endX: end.dx,
      endY: end.dy,
      startRadius: startRadius,
      endRadius: endRadius,
      colorArgb: color.value,
      brushShape: shape.index,
      antialiasLevel: antialias,
      includeStart: includeStart,
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
      spacing: spacing,
      scatter: scatter,
      softness: softness,
      snapToPixel: snapToPixel,
      accumulate: true,
      customMask: customMask,
      customMaskWidth: customShape.width,
      customMaskHeight: customShape.height,
      selectionMask: null,
    );
    if (ok) {
      surface.markDirty();
      return;
    }
    _drawCustomStampSegment(
      surface: surface,
      shape: customShape,
      start: start,
      end: end,
      startRadius: startRadius,
      endRadius: endRadius,
      color: color,
      includeStart: includeStart,
      erase: erase,
      randomRotation: randomRotation,
      smoothRotation: smoothRotation,
      rotationSeed: rotationSeed,
      rotationJitter: rotationJitter,
      spacing: spacing,
      scatter: scatter,
      softness: softness,
      snapToPixel: snapToPixel,
      antialiasLevel: antialias,
      screentoneEnabled: screentoneEnabled,
      screentoneSpacing: screentoneSpacing,
      screentoneDotSize: screentoneDotSize,
      screentoneRotation: screentoneRotation,
      screentoneSoftness: screentoneSoftness,
      screentoneShape: screentoneShape,
    );
    return;
  }
  final bool ok = RustCpuBrushFfi.instance.drawStampSegment(
    pixelsPtr: surface.pointerAddress,
    pixelsLen: surface.pixels.length,
    width: surface.width,
    height: surface.height,
    startX: start.dx,
    startY: start.dy,
    endX: end.dx,
    endY: end.dy,
    startRadius: startRadius,
    endRadius: endRadius,
    colorArgb: color.value,
    brushShape: shape.index,
    antialiasLevel: antialias,
    includeStart: includeStart,
    erase: erase,
    randomRotation: randomRotation,
    smoothRotation: smoothRotation,
    rotationSeed: rotationSeed,
    rotationJitter: rotationJitter,
    spacing: spacing,
    scatter: scatter,
    softness: softness,
    snapToPixel: snapToPixel,
    screentoneEnabled: screentoneEnabled,
    screentoneSpacing: screentoneSpacing,
    screentoneDotSize: screentoneDotSize,
    screentoneRotation: screentoneRotation,
    screentoneSoftness: screentoneSoftness,
    screentoneShape: screentoneShape.index,
    accumulate: true,
    selectionMask: null,
  );
  if (ok) {
    surface.markDirty();
  }
}

void _drawCustomStampSegment({
  required BitmapSurface surface,
  required BrushShapeRaster shape,
  required Offset start,
  required Offset end,
  required double startRadius,
  required double endRadius,
  required Color color,
  required bool includeStart,
  required bool erase,
  required bool randomRotation,
  required bool smoothRotation,
  required int rotationSeed,
  required double rotationJitter,
  required double spacing,
  required double scatter,
  required double softness,
  required bool snapToPixel,
  required int antialiasLevel,
  required bool screentoneEnabled,
  required double screentoneSpacing,
  required double screentoneDotSize,
  required double screentoneRotation,
  required double screentoneSoftness,
  required BrushShape screentoneShape,
}) {
  final double distance = (end - start).distance;
  if (!distance.isFinite || distance <= 0.0001) {
    final double rotation = _customStampRotation(
      center: end,
      start: start,
      end: end,
      randomRotation: randomRotation,
      smoothRotation: smoothRotation,
      rotationSeed: rotationSeed,
      rotationJitter: rotationJitter,
    );
    surface.drawCustomBrushStamp(
      shape: shape,
      center: end,
      radius: endRadius,
      color: color,
      erase: erase,
      softness: softness,
      rotation: rotation,
      snapToPixel: snapToPixel,
      antialiasLevel: antialiasLevel,
      screentoneEnabled: screentoneEnabled,
      screentoneSpacing: screentoneSpacing,
      screentoneDotSize: screentoneDotSize,
      screentoneRotation: screentoneRotation,
      screentoneSoftness: screentoneSoftness,
      screentoneShape: screentoneShape,
    );
    return;
  }
  final double maxRadius = math.max(
    math.max(startRadius.abs(), endRadius.abs()),
    0.01,
  );
  final double step = _strokeStampSpacing(maxRadius, spacing);
  final int samples = math.max(1, (distance / step).ceil());
  final int startIndex = includeStart ? 0 : 1;
  for (int i = startIndex; i <= samples; i++) {
    final double t = samples == 0 ? 1.0 : (i / samples);
    final double radius = ui.lerpDouble(startRadius, endRadius, t) ?? endRadius;
    final double sampleX = ui.lerpDouble(start.dx, end.dx, t) ?? end.dx;
    final double sampleY = ui.lerpDouble(start.dy, end.dy, t) ?? end.dy;
    final Offset baseCenter = Offset(sampleX, sampleY);
    final double scatterRadius = maxRadius * scatter.clamp(0.0, 1.0) * 2.0;
    final Offset jitter = scatterRadius > 0
        ? brushScatterOffset(
            center: baseCenter,
            seed: rotationSeed,
            radius: scatterRadius,
            salt: i,
          )
        : Offset.zero;
    final Offset center = baseCenter + jitter;
    final double rotation = _customStampRotation(
      center: center,
      start: start,
      end: end,
      randomRotation: randomRotation,
      smoothRotation: smoothRotation,
      rotationSeed: rotationSeed,
      rotationJitter: rotationJitter,
    );
    surface.drawCustomBrushStamp(
      shape: shape,
      center: center,
      radius: radius,
      color: color,
      erase: erase,
      softness: softness,
      rotation: rotation,
      snapToPixel: snapToPixel,
      antialiasLevel: antialiasLevel,
      screentoneEnabled: screentoneEnabled,
      screentoneSpacing: screentoneSpacing,
      screentoneDotSize: screentoneDotSize,
      screentoneRotation: screentoneRotation,
      screentoneSoftness: screentoneSoftness,
      screentoneShape: screentoneShape,
    );
  }
}

double _customStampRotation({
  required Offset center,
  required Offset start,
  required Offset end,
  required bool randomRotation,
  required bool smoothRotation,
  required int rotationSeed,
  required double rotationJitter,
}) {
  double rotation = 0.0;
  if (smoothRotation) {
    final Offset delta = end - start;
    if (delta.distanceSquared > 0.0001) {
      rotation = math.atan2(delta.dy, delta.dx);
    }
  }
  if (randomRotation) {
    rotation += brushRandomRotationRadians(center: center, seed: rotationSeed) *
        rotationJitter;
  }
  return rotation;
}

double _strokeStampSpacing(double radius, double spacing) {
  double r = radius.isFinite ? radius.abs() : 0.0;
  double s = spacing.isFinite ? spacing : 0.15;
  s = s.clamp(0.02, 2.5);
  return math.max(r * 2.0 * s, 0.1);
}

class _AlphaStats {
  const _AlphaStats({
    required this.nonZero,
    required this.partial,
    required this.min,
    required this.max,
  });

  final int nonZero;
  final int partial;
  final int min;
  final int max;
}

_AlphaStats _computeAlphaStats(Uint32List pixels) {
  int nonZero = 0;
  int partial = 0;
  int minAlpha = 255;
  int maxAlpha = 0;
  for (final int argb in pixels) {
    final int alpha = (argb >> 24) & 0xff;
    if (alpha == 0) {
      continue;
    }
    nonZero += 1;
    if (alpha < minAlpha) {
      minAlpha = alpha;
    }
    if (alpha > maxAlpha) {
      maxAlpha = alpha;
    }
    if (alpha < 255) {
      partial += 1;
    }
  }
  if (nonZero == 0) {
    minAlpha = 0;
    maxAlpha = 0;
  }
  return _AlphaStats(
    nonZero: nonZero,
    partial: partial,
    min: minAlpha,
    max: maxAlpha,
  );
}

Uint8List _argbToRgba(Uint32List pixels) {
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

Future<ui.Image> _decodeRgbaImage(
  Uint8List bytes,
  int width,
  int height,
) {
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

class _BrushPreviewRequest {
  const _BrushPreviewRequest({
    required this.pixelWidth,
    required this.pixelHeight,
    required this.colorArgb,
    required this.hardness,
    required this.flow,
    required this.spacing,
    required this.scatter,
    required this.randomRotation,
    required this.smoothRotation,
    required this.rotationJitter,
    required this.antialias,
    required this.snapToPixel,
    required this.shapeIndex,
    required this.screentoneEnabled,
    required this.screentoneSpacing,
    required this.screentoneDotSize,
    required this.screentoneRotation,
    required this.screentoneSoftness,
    required this.screentoneShapeIndex,
    required this.hollowEnabled,
    required this.hollowRatio,
    required this.rotationSeed,
    required this.samples,
    this.customMask,
    required this.customMaskWidth,
    required this.customMaskHeight,
  });

  final int pixelWidth;
  final int pixelHeight;
  final int colorArgb;
  final double hardness;
  final double flow;
  final double spacing;
  final double scatter;
  final bool randomRotation;
  final bool smoothRotation;
  final double rotationJitter;
  final int antialias;
  final bool snapToPixel;
  final int shapeIndex;
  final bool screentoneEnabled;
  final double screentoneSpacing;
  final double screentoneDotSize;
  final double screentoneRotation;
  final double screentoneSoftness;
  final int screentoneShapeIndex;
  final bool hollowEnabled;
  final double hollowRatio;
  final int rotationSeed;
  final TransferableTypedData samples;
  final TransferableTypedData? customMask;
  final int customMaskWidth;
  final int customMaskHeight;

  Map<String, Object?> toJson() => <String, Object?>{
    'pixelWidth': pixelWidth,
    'pixelHeight': pixelHeight,
    'colorArgb': colorArgb,
    'hardness': hardness,
    'flow': flow,
    'spacing': spacing,
    'scatter': scatter,
    'randomRotation': randomRotation,
    'smoothRotation': smoothRotation,
    'rotationJitter': rotationJitter,
    'antialias': antialias,
    'snapToPixel': snapToPixel,
    'shapeIndex': shapeIndex,
    'screentoneEnabled': screentoneEnabled,
    'screentoneSpacing': screentoneSpacing,
    'screentoneDotSize': screentoneDotSize,
    'screentoneRotation': screentoneRotation,
    'screentoneSoftness': screentoneSoftness,
    'screentoneShapeIndex': screentoneShapeIndex,
    'hollowEnabled': hollowEnabled,
    'hollowRatio': hollowRatio,
    'rotationSeed': rotationSeed,
    'samples': samples,
    'customMask': customMask,
    'customMaskWidth': customMaskWidth,
    'customMaskHeight': customMaskHeight,
  };
}

class _BrushPreviewWorkerResult {
  const _BrushPreviewWorkerResult({
    required this.width,
    required this.height,
    this.pixels,
    this.backend,
  });

  final int width;
  final int height;
  final Uint8List? pixels;
  final String? backend;
}

class _QueuedPreviewRequest {
  _QueuedPreviewRequest(this.request, this.completer);

  final _BrushPreviewRequest request;
  final Completer<_BrushPreviewWorkerResult?> completer;
}

class _BrushPreviewWorker {
  _BrushPreviewWorker._()
    : _receivePort = ReceivePort(),
      _pending = <int, Completer<_BrushPreviewWorkerResult?>>{} {
    _subscription = _receivePort.listen(
      _handleMessage,
      onError: (Object error, StackTrace stackTrace) {
        _resetWorker();
        _failPending();
        _failQueued();
      },
    );
  }

  static final _BrushPreviewWorker instance = _BrushPreviewWorker._();

  final ReceivePort _receivePort;
  final Map<int, Completer<_BrushPreviewWorkerResult?>> _pending;
  final List<_QueuedPreviewRequest> _queued = <_QueuedPreviewRequest>[];
  late final StreamSubscription<Object?> _subscription;
  Isolate? _isolate;
  SendPort? _sendPort;
  int _nextRequestId = 0;
  bool _starting = false;
  Timer? _startTimeout;

  static const Duration _kStartTimeout = Duration(milliseconds: 2000);

  Future<void> _ensureStarted() async {
    if (_sendPort != null || _starting) {
      return;
    }
    _starting = true;
    if (_isolate == null) {
      try {
        _isolate = await Isolate.spawn<SendPort>(
          _brushPreviewWorkerMain,
          _receivePort.sendPort,
          debugName: 'BrushPreviewWorker',
          errorsAreFatal: false,
        );
      } on Object {
        _resetWorker();
        _starting = false;
        return;
      }
    }
    _startTimeout?.cancel();
    _startTimeout = Timer(_kStartTimeout, () {
      if (_sendPort == null) {
        _resetWorker();
        _failQueued();
      }
    });
    _starting = false;
  }

  Future<_BrushPreviewWorkerResult?> request(_BrushPreviewRequest request) async {
    _ensureStarted();
    final SendPort? port = _sendPort;
    final int id = _nextRequestId++;
    final Completer<_BrushPreviewWorkerResult?> completer =
        Completer<_BrushPreviewWorkerResult?>();
    if (port == null) {
      _queueRequest(request, completer);
      return completer.future;
    }
    _pending[id] = completer;
    port.send(<String, Object?>{'id': id, 'payload': request.toJson()});
    return completer.future;
  }

  void _handleMessage(Object? message) {
    if (message is SendPort) {
      _sendPort = message;
      _startTimeout?.cancel();
      _flushQueued();
      return;
    }
    if (message is! Map<String, Object?>) {
      return;
    }
    final int id = message['id'] as int? ?? -1;
    final Completer<_BrushPreviewWorkerResult?>? completer = _pending.remove(id);
    if (completer == null) {
      return;
    }
    final Object? data = message['data'];
    if (data is Map<String, Object?>) {
      final int width = data['width'] as int? ?? 0;
      final int height = data['height'] as int? ?? 0;
      final String? backend = data['backend'] as String?;
      Uint8List? pixels;
      final TransferableTypedData? pixelData =
          data['pixels'] as TransferableTypedData?;
      if (pixelData != null) {
        pixels = pixelData.materialize().asUint8List();
      }
      completer.complete(
        _BrushPreviewWorkerResult(
          width: width,
          height: height,
          pixels: pixels,
          backend: backend,
        ),
      );
      return;
    }
    if (data is Error || data is Exception) {
      completer.complete(null);
      return;
    }
    completer.complete(null);
  }

  Future<void> dispose() async {
    final Isolate? isolate = _isolate;
    if (isolate != null) {
      _sendPort?.send(null);
      isolate.kill(priority: Isolate.immediate);
      _isolate = null;
    }
    await _subscription.cancel();
    _receivePort.close();
    _failPending();
    _failQueued();
  }

  void _resetWorker() {
    final Isolate? isolate = _isolate;
    if (isolate != null) {
      isolate.kill(priority: Isolate.immediate);
    }
    _isolate = null;
    _sendPort = null;
    _starting = false;
    _startTimeout?.cancel();
  }

  void _queueRequest(
    _BrushPreviewRequest request,
    Completer<_BrushPreviewWorkerResult?> completer,
  ) {
    for (final _QueuedPreviewRequest queued in _queued) {
      if (!queued.completer.isCompleted) {
        queued.completer.complete(null);
      }
    }
    _queued
      ..clear()
      ..add(_QueuedPreviewRequest(request, completer));
  }

  void _flushQueued() {
    final SendPort? port = _sendPort;
    if (port == null || _queued.isEmpty) {
      return;
    }
    final List<_QueuedPreviewRequest> queued = List<_QueuedPreviewRequest>.from(
      _queued,
      growable: false,
    );
    _queued.clear();
    for (final _QueuedPreviewRequest item in queued) {
      final int id = _nextRequestId++;
      _pending[id] = item.completer;
      port.send(<String, Object?>{'id': id, 'payload': item.request.toJson()});
    }
  }

  void _failPending() {
    for (final Completer<_BrushPreviewWorkerResult?> pending
        in _pending.values) {
      if (!pending.isCompleted) {
        pending.complete(null);
      }
    }
    _pending.clear();
  }

  void _failQueued() {
    for (final _QueuedPreviewRequest queued in _queued) {
      if (!queued.completer.isCompleted) {
        queued.completer.complete(null);
      }
    }
    _queued.clear();
  }
}

@pragma('vm:entry-point')
void _brushPreviewWorkerMain(SendPort initialReplyTo) {
  final ReceivePort port = ReceivePort();
  initialReplyTo.send(port.sendPort);
  bool busy = false;
  bool shutdownRequested = false;
  Object? queuedMessage;
  int? queuedId;

  void cancelQueued() {
    final int? id = queuedId;
    if (id != null) {
      initialReplyTo.send(<String, Object?>{'id': id, 'data': null});
    }
    queuedMessage = null;
    queuedId = null;
  }

  int? extractId(Object? message) {
    if (message is Map<String, Object?>) {
      final Object? id = message['id'];
      if (id is int) {
        return id;
      }
    }
    return null;
  }

  Future<void> processMessage(Object? message) async {
    Object? current = message;
    while (current != null) {
      if (shutdownRequested) {
        _WgpuPreviewEngine.instance.dispose();
        port.close();
        busy = false;
        return;
      }
      if (current is! Map<String, Object?>) {
        // Ignore malformed message.
      } else {
        final int id = current['id'] as int? ?? -1;
        final Object? payload = current['payload'];
        if (payload is! Map<String, Object?>) {
          initialReplyTo.send(<String, Object?>{'id': id, 'data': null});
        } else {
          try {
            final Object? result = await _brushPreviewWorkerHandlePayload(
              payload,
            );
            initialReplyTo.send(<String, Object?>{'id': id, 'data': result});
          } catch (error, stackTrace) {
            initialReplyTo.send(<String, Object?>{
              'id': id,
              'data': StateError('$error\n$stackTrace'),
            });
          }
        }
      }
      if (shutdownRequested) {
        _WgpuPreviewEngine.instance.dispose();
        port.close();
        busy = false;
        return;
      }
      if (queuedMessage == null) {
        busy = false;
        return;
      }
      current = queuedMessage;
      queuedMessage = null;
      queuedId = null;
    }
    busy = false;
  }

  port.listen((Object? message) {
    if (message == null) {
      shutdownRequested = true;
      cancelQueued();
      if (!busy) {
        _WgpuPreviewEngine.instance.dispose();
        port.close();
      }
      return;
    }
    if (busy) {
      if (queuedMessage != null) {
        cancelQueued();
      }
      queuedMessage = message;
      queuedId = extractId(message);
      return;
    }
    busy = true;
    unawaited(processMessage(message));
  });
}

Future<Object?> _brushPreviewWorkerHandlePayload(
  Map<String, Object?> payload,
) async {
  await ensureRustInitialized();
  final int width = payload['pixelWidth'] as int? ?? 0;
  final int height = payload['pixelHeight'] as int? ?? 0;
  final TransferableTypedData? sampleData =
      payload['samples'] as TransferableTypedData?;
  if (width <= 0 || height <= 0 || sampleData == null) {
    return <String, Object?>{
      'width': width,
      'height': height,
      'pixels': null,
      'backend': 'none',
    };
  }
  final ByteBuffer buffer = sampleData.materialize();
  final Float32List sampleList = buffer.asFloat32List();
  final List<_PreviewStrokeSample> samples =
      _decodePreviewSamples(sampleList);
  if (samples.isEmpty) {
    return <String, Object?>{
      'width': width,
      'height': height,
      'pixels': null,
      'backend': 'none',
    };
  }
  final TransferableTypedData? customMaskData =
      payload['customMask'] as TransferableTypedData?;
  final int customMaskWidth = payload['customMaskWidth'] as int? ?? 0;
  final int customMaskHeight = payload['customMaskHeight'] as int? ?? 0;
  final Uint8List? customMaskBytes =
      customMaskData?.materialize().asUint8List();

  final int colorArgb = payload['colorArgb'] as int? ?? 0;
  final double hardness =
      (payload['hardness'] as double? ?? 0.8).clamp(0.0, 1.0);
  final double flow =
      (payload['flow'] as double? ?? 1.0).clamp(0.0, 1.0);
  final double spacing = payload['spacing'] as double? ?? 0.15;
  final double scatter = payload['scatter'] as double? ?? 0.0;
  final bool randomRotation = payload['randomRotation'] as bool? ?? false;
  final bool smoothRotation = payload['smoothRotation'] as bool? ?? false;
  final double rotationJitter =
      payload['rotationJitter'] as double? ?? 0.0;
  final int antialias = payload['antialias'] as int? ?? 0;
  final bool snapToPixel = payload['snapToPixel'] as bool? ?? false;
  final int shapeIndex = payload['shapeIndex'] as int? ?? 0;
  final bool screentoneEnabled =
      payload['screentoneEnabled'] as bool? ?? false;
  final double screentoneSpacing =
      payload['screentoneSpacing'] as double? ?? 10.0;
  final double screentoneDotSize =
      payload['screentoneDotSize'] as double? ?? 0.6;
  final double screentoneRotation =
      payload['screentoneRotation'] as double? ?? 45.0;
  final double screentoneSoftness =
      payload['screentoneSoftness'] as double? ?? 0.0;
  final int screentoneShapeIndex =
      payload['screentoneShapeIndex'] as int? ?? 0;
  final bool hollowEnabled = payload['hollowEnabled'] as bool? ?? false;
  final double hollowRatio = payload['hollowRatio'] as double? ?? 0.0;
  final int rotationSeed = payload['rotationSeed'] as int? ?? 0;

  final Uint8List? wgpuPixels = await _WgpuPreviewEngine.instance.render(
    width: width,
    height: height,
    samples: samples,
    colorArgb: colorArgb,
    hardness: hardness,
    flow: flow,
    spacing: spacing,
    scatter: scatter,
    randomRotation: randomRotation,
    smoothRotation: smoothRotation,
    rotationJitter: rotationJitter,
    antialias: antialias,
    snapToPixel: snapToPixel,
    shapeIndex: shapeIndex,
    screentoneEnabled: screentoneEnabled,
    screentoneSpacing: screentoneSpacing,
    screentoneDotSize: screentoneDotSize,
    screentoneRotation: screentoneRotation,
    screentoneSoftness: screentoneSoftness,
    screentoneShapeIndex: screentoneShapeIndex,
    hollowEnabled: hollowEnabled,
    hollowRatio: hollowRatio,
    rotationSeed: rotationSeed,
    customMask: customMaskBytes,
    customMaskWidth: customMaskWidth,
    customMaskHeight: customMaskHeight,
  );
  if (wgpuPixels != null &&
      wgpuPixels.isNotEmpty &&
      _rgbaHasNonZeroAlpha(wgpuPixels)) {
    _logPreview('worker wgpu ok bytes=${wgpuPixels.length}');
    return <String, Object?>{
      'width': width,
      'height': height,
      'pixels': TransferableTypedData.fromList(<Uint8List>[wgpuPixels]),
      'backend': 'wgpu',
    };
  }
  if (wgpuPixels == null) {
    _logPreview('worker wgpu null -> no preview');
  } else if (wgpuPixels.isEmpty) {
    _logPreview('worker wgpu empty -> no preview');
  } else {
    _logPreview('worker wgpu transparent -> no preview');
  }
  return <String, Object?>{
    'width': width,
    'height': height,
    'pixels': null,
    'backend': 'none',
  };
}

BrushShapeRaster? _decodeCustomMaskRaster(
  TransferableTypedData? data,
  int width,
  int height,
) {
  if (data == null || width <= 0 || height <= 0) {
    return null;
  }
  final Uint8List packed = data.materialize().asUint8List();
  return _decodeCustomMaskRasterFromBytes(packed, width, height);
}

BrushShapeRaster? _decodeCustomMaskRasterFromBytes(
  Uint8List? packed,
  int width,
  int height,
) {
  if (packed == null || width <= 0 || height <= 0) {
    return null;
  }
  final int count = width * height;
  if (count <= 0 || packed.length < count * 2) {
    return null;
  }
  final Uint8List alpha = Uint8List(count);
  final Uint8List softAlpha = Uint8List(count);
  int index = 0;
  for (int i = 0; i < count; i++) {
    alpha[i] = packed[index++];
    softAlpha[i] = packed[index++];
  }
  return BrushShapeRaster(
    id: 'preview_custom',
    width: width,
    height: height,
    alpha: alpha,
    softAlpha: softAlpha,
  );
}

class _WgpuPreviewEngine {
  _WgpuPreviewEngine._();

  static final _WgpuPreviewEngine instance = _WgpuPreviewEngine._();

  final rust_wgpu_engine.CanvasEngineFfi _ffi =
      rust_wgpu_engine.CanvasEngineFfi.instance;
  int _handle = 0;
  int _width = 0;
  int _height = 0;
  int _maskSignature = 0;
  bool _maskInitialized = false;
  bool _disabled = false;

  bool get _canUse => !_disabled && _ffi.canCreateEngine;

  void dispose() {
    if (_handle != 0) {
      _ffi.disposeEngine(handle: _handle);
      _handle = 0;
    }
    _maskSignature = 0;
    _maskInitialized = false;
    _width = 0;
    _height = 0;
  }

  bool _ensureEngine(int width, int height) {
    if (!_canUse || width <= 0 || height <= 0) {
      _logPreview('wgpu engine unavailable');
      return false;
    }
    if (_handle != 0 && (_width != width || _height != height)) {
      _ffi.disposeEngine(handle: _handle);
      _handle = 0;
      _maskSignature = 0;
      _maskInitialized = false;
    }
    if (_handle == 0) {
      final int handle = _ffi.createEngine(width: width, height: height);
      if (handle == 0) {
        _disabled = true;
        _logPreview('wgpu engine create failed size=${width}x$height');
        return false;
      }
      _handle = handle;
      _width = width;
      _height = height;
    }
    return true;
  }

  void _syncCustomMask(
    Uint8List? mask,
    int width,
    int height,
  ) {
    if (_handle == 0) {
      return;
    }
    if (mask == null || mask.isEmpty || width <= 0 || height <= 0) {
      if (_maskInitialized) {
        _ffi.clearBrushMask(handle: _handle);
        _maskSignature = 0;
        _maskInitialized = false;
      }
      return;
    }
    final int signature = Object.hash(
      width,
      height,
      mask.length,
      mask.first,
      mask.last,
    );
    if (_maskInitialized && signature == _maskSignature) {
      return;
    }
    _maskSignature = signature;
    _maskInitialized = true;
    _ffi.setBrushMask(
      handle: _handle,
      width: width,
      height: height,
      mask: mask,
    );
  }

  Future<Uint8List?> render({
    required int width,
    required int height,
    required List<_PreviewStrokeSample> samples,
    required int colorArgb,
    required double hardness,
    required double flow,
    required double spacing,
    required double scatter,
    required bool randomRotation,
    required bool smoothRotation,
    required double rotationJitter,
    required int antialias,
    required bool snapToPixel,
    required int shapeIndex,
    required bool screentoneEnabled,
    required double screentoneSpacing,
    required double screentoneDotSize,
    required double screentoneRotation,
    required double screentoneSoftness,
    required int screentoneShapeIndex,
    required bool hollowEnabled,
    required double hollowRatio,
    required int rotationSeed,
    Uint8List? customMask,
    required int customMaskWidth,
    required int customMaskHeight,
  }) async {
    if (!_ensureEngine(width, height)) {
      return null;
    }
    if (samples.isEmpty) {
      return null;
    }
    _ffi.clearLayer(handle: _handle, layerIndex: 0);
    _syncCustomMask(customMask, customMaskWidth, customMaskHeight);

    final double baseRadius = _maxSampleRadius(samples);
    if (!baseRadius.isFinite || baseRadius <= 0.0) {
      return null;
    }
    _ffi.setBrush(
      handle: _handle,
      colorArgb: colorArgb,
      baseRadius: baseRadius,
      usePressure: true,
      erase: false,
      antialiasLevel: antialias,
      brushShape: shapeIndex,
      randomRotation: randomRotation,
      smoothRotation: smoothRotation,
      rotationSeed: rotationSeed,
      spacing: spacing,
      hardness: hardness,
      flow: flow,
      scatter: scatter,
      rotationJitter: rotationJitter,
      snapToPixel: snapToPixel,
      screentoneEnabled: screentoneEnabled,
      screentoneSpacing: screentoneSpacing,
      screentoneDotSize: screentoneDotSize,
      screentoneRotation: screentoneRotation,
      screentoneSoftness: screentoneSoftness,
      screentoneShape: screentoneShapeIndex,
      hollow: hollowEnabled,
      hollowRatio: hollowRatio,
      hollowEraseOccludedParts: false,
      streamlineStrength: 0.0,
      smoothingMode: 1,
      stabilizerStrength: 0.0,
    );

    final Uint8List points = _encodeEnginePoints(samples, baseRadius);
    _ffi.pushPointsPacked(
      handle: _handle,
      bytes: points,
      pointCount: samples.length,
    );
    Uint8List? pixels = _ffi.readLayerPreview(
      handle: _handle,
      layerIndex: 0,
      width: width,
      height: height,
    );
    if (pixels != null && pixels.isNotEmpty && !_rgbaHasNonZeroAlpha(pixels)) {
      _logPreview('wgpu readback transparent, retry');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      pixels = _ffi.readLayerPreview(
        handle: _handle,
        layerIndex: 0,
        width: width,
        height: height,
      );
    }
    return pixels;
  }
}

BrushShape _resolveBrushShape(int index) {
  if (index < 0 || index >= BrushShape.values.length) {
    return BrushShape.circle;
  }
  return BrushShape.values[index];
}

class _BrushPresetStrokeFallbackPainter extends CustomPainter {
  _BrushPresetStrokeFallbackPainter({
    required BrushPreset preset,
    required this.color,
  })  : shape = preset.shape,
        spacing = _sanitizeDouble(preset.spacing, 0.15, 0.02, 2.5),
        hardness = _sanitizeDouble(preset.hardness, 0.8, 0.0, 1.0),
        flow = _sanitizeDouble(preset.flow, 1.0, 0.0, 1.0),
        scatter = _sanitizeDouble(preset.scatter, 0.0, 0.0, 1.0),
        randomRotation = preset.randomRotation,
        smoothRotation = preset.smoothRotation,
        rotationJitter = _sanitizeDouble(preset.rotationJitter, 1.0, 0.0, 1.0),
        antialiasLevel = preset.antialiasLevel.clamp(0, 9),
        hollowEnabled = preset.hollowEnabled,
        hollowRatio = _sanitizeDouble(preset.hollowRatio, 0.0, 0.0, 1.0),
        autoSharpTaper = preset.autoSharpTaper,
        snapToPixel = preset.snapToPixel;

  final Color color;
  final BrushShape shape;
  final double spacing;
  final double hardness;
  final double flow;
  final double scatter;
  final bool randomRotation;
  final bool smoothRotation;
  final double rotationJitter;
  final int antialiasLevel;
  final bool hollowEnabled;
  final double hollowRatio;
  final bool autoSharpTaper;
  final bool snapToPixel;

  static double _sanitizeDouble(
    double value,
    double fallback,
    double min,
    double max,
  ) {
    if (!value.isFinite) {
      return fallback;
    }
    return value.clamp(min, max);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final double padding = _kPreviewPadding;
    final double width = size.width - padding * 2;
    final double height = size.height - padding * 2;
    if (width <= 0 || height <= 0) {
      return;
    }

    final Offset start = Offset(padding, padding + height * 0.65);
    final Offset control1 =
        Offset(padding + width * 0.3, padding + height * 0.1);
    final Offset control2 =
        Offset(padding + width * 0.65, padding + height * 0.9);
    final Offset end = Offset(padding + width, padding + height * 0.35);

    final ui.Path path = ui.Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        end.dx,
        end.dy,
      );
    final ui.PathMetrics metrics = path.computeMetrics();
    final Iterator<ui.PathMetric> iterator = metrics.iterator;
    if (!iterator.moveNext()) {
      return;
    }
    final ui.PathMetric metric = iterator.current;

    final double baseRadius = math.max(2.2, height * 0.2);
    final double step = math.max(0.1, baseRadius * 2.0 * spacing);
    final double totalLength = metric.length;
    final int maxStamps = math.max(6, (totalLength / step).ceil());

    final double opacity = (0.25 + 0.75 * flow * (0.35 + 0.65 * hardness))
        .clamp(0.18, 1.0);
    final Color strokeColor = color.withOpacity(
      (color.opacity * opacity).clamp(0.0, 1.0),
    );
    final Paint paint = Paint()
      ..color = strokeColor
      ..style = hollowEnabled ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = hollowEnabled
          ? math.max(1.0, baseRadius * (1.0 - hollowRatio).clamp(0.2, 0.9))
          : 1.0
      ..isAntiAlias = antialiasLevel > 0;

    for (int i = 0; i <= maxStamps; i++) {
      final double distance = math.min(totalLength, i * step);
      final ui.Tangent? tangent = metric.getTangentForOffset(distance);
      if (tangent == null) {
        continue;
      }
      double radius = baseRadius;
      if (autoSharpTaper) {
        final double t = distance / totalLength;
        radius *= (0.5 + 0.5 * math.sin(math.pi * t));
      }
      if (!radius.isFinite || radius <= 0.0) {
        continue;
      }

      Offset position = tangent.position;
      if (scatter > 0.0) {
        final double scatterRadius = radius * 2.0 * scatter;
        if (scatterRadius > 0.0001) {
          final double u = _noise(i + 3);
          final double v = _noise(i + 7);
          final double dist = math.sqrt(u) * scatterRadius;
          final double angle = v * math.pi * 2.0;
          position = position.translate(
            math.cos(angle) * dist,
            math.sin(angle) * dist,
          );
        }
      }
      if (snapToPixel) {
        position = Offset(
          position.dx.floor() + 0.5,
          position.dy.floor() + 0.5,
        );
        radius = (radius * 2.0).round() * 0.5;
        if (radius <= 0.0) {
          continue;
        }
      }

      double rotation = 0.0;
      if (shape != BrushShape.circle && smoothRotation) {
        rotation = math.atan2(tangent.vector.dy, tangent.vector.dx);
      }
      if (randomRotation && shape != BrushShape.circle) {
        rotation += _noise(i + 11) * math.pi * 2.0 * rotationJitter;
      }

      canvas.save();
      canvas.translate(position.dx, position.dy);
      if (rotation != 0.0) {
        canvas.rotate(rotation);
      }
      final ui.Path stamp = BrushShapeGeometry.pathFor(
        shape,
        Offset.zero,
        radius,
      );
      canvas.drawPath(stamp, paint);
      canvas.restore();
    }
  }

  double _noise(int seed) {
    final double value = math.sin(seed * 12.9898 + 78.233) * 43758.5453;
    return value - value.floor();
  }

  @override
  bool shouldRepaint(covariant _BrushPresetStrokeFallbackPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.shape != shape ||
        oldDelegate.spacing != spacing ||
        oldDelegate.hardness != hardness ||
        oldDelegate.flow != flow ||
        oldDelegate.scatter != scatter ||
        oldDelegate.randomRotation != randomRotation ||
        oldDelegate.smoothRotation != smoothRotation ||
        oldDelegate.rotationJitter != rotationJitter ||
        oldDelegate.antialiasLevel != antialiasLevel ||
        oldDelegate.hollowEnabled != hollowEnabled ||
        oldDelegate.hollowRatio != hollowRatio ||
        oldDelegate.autoSharpTaper != autoSharpTaper ||
        oldDelegate.snapToPixel != snapToPixel;
  }
}
