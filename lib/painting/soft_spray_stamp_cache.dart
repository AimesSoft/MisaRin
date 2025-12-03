import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../bitmap_canvas/soft_brush_profile.dart';
import '../bitmap_canvas/soft_spray_stamp.dart';

class SoftSprayStampCache {
  SoftSprayStampCache._();

  static final SoftSprayStampCache instance = SoftSprayStampCache._();

  static const int _stampSize = 256;
  static const double _bucketSize = 0.05;

  final Map<int, SoftSprayStamp> _cache = <int, SoftSprayStamp>{};
  final Map<int, Future<SoftSprayStamp>> _pending = <int, Future<SoftSprayStamp>>{};
  ui.FragmentProgram? _program;
  bool _shaderUnavailable = false;

  SoftSprayStamp? resolve(double softness) {
    final int bucket = _bucketFor(softness);
    return _cache[bucket];
  }

  void ensure(double softness) {
    if (_shaderUnavailable) {
      return;
    }
    final int bucket = _bucketFor(softness);
    if (_cache.containsKey(bucket) || _pending.containsKey(bucket)) {
      return;
    }
    final double clamped = softness.clamp(0.0, 1.0);
    debugPrint('[SoftSpray] 生成 GPU 贴图任务 (bucket=$bucket, softness=${clamped.toStringAsFixed(2)})');
    _pending[bucket] = _generateStamp(clamped, bucket).catchError((Object error, StackTrace stackTrace) {
      debugPrint('Failed to generate soft spray stamp: $error');
      _shaderUnavailable = true;
      _pending.remove(bucket);
    });
  }

  int _bucketFor(double softness) =>
      (softness.clamp(0.0, 1.0) / _bucketSize).round();

  Future<SoftSprayStamp> _generateStamp(double softness, int bucket) async {
    final ui.FragmentProgram program = await _loadProgram();
    final ui.FragmentShader shader = program.fragmentShader();
    final double size = _stampSize.toDouble();
    final double innerFraction = softBrushInnerRadiusFraction(softness);
    final double extentMultiplier = softBrushExtentMultiplier(softness);
    final double innerRatio = innerFraction / math.max(1.0 + extentMultiplier, 1e-4);
    final double exponent = softBrushFalloffExponent(softness);
    shader.setFloat(0, size); // resolution.x
    shader.setFloat(1, size); // resolution.y
    shader.setFloat(2, innerRatio);
    shader.setFloat(3, exponent);

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    final ui.Paint paint = ui.Paint()..shader = shader;
    canvas.drawRect(ui.Rect.fromLTWH(0.0, 0.0, size, size), paint);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(_stampSize, _stampSize);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (byteData == null) {
      throw StateError('Failed to read GPU soft spray stamp bytes');
    }
    final Uint8List rgba = byteData.buffer.asUint8List();
    final Uint8List alpha = Uint8List(_stampSize * _stampSize);
    for (int i = 0, j = 0; i < rgba.length; i += 4, j++) {
      alpha[j] = rgba[i + 3];
    }
    final SoftSprayStamp stamp = SoftSprayStamp(
      size: _stampSize,
      alpha: alpha,
      outerRadiusScale: 1.0 + extentMultiplier,
    );
    _cache[bucket] = stamp;
    _pending.remove(bucket);
    debugPrint(
      '[SoftSpray] GPU 贴图已完成 (bucket=$bucket, size=$_stampSize, scale=${stamp.outerRadiusScale.toStringAsFixed(2)})',
    );
    return stamp;
  }

  Future<ui.FragmentProgram> _loadProgram() async {
    if (_program != null) {
      return _program!;
    }
    _program = await ui.FragmentProgram.fromAsset('shaders/soft_spray.glsl');
    return _program!;
  }
}
