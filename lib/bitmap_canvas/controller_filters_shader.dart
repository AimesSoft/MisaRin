part of 'controller.dart';

/// Shader 加速版的图层边缘柔化；不再回退到 CPU 画布路径。
Future<bool> _controllerApplyAntialiasToActiveLayer(
  BitmapCanvasController controller,
  int level, {
  bool previewOnly = false,
}) async {
  final int clamped = level.clamp(0, 9);
  if (previewOnly) {
    return _canApplyAntialias(controller, clamped);
  }
  if (_shaderAntialiasSupported()) {
    final bool shaderApplied = await _shaderApplyAntialiasToActiveLayer(
      controller,
      clamped,
    );
    if (shaderApplied) {
      return true;
    }
  }
  return false;
}

bool _canApplyAntialias(BitmapCanvasController controller, int level) {
  if (controller._layers.isEmpty) {
    return false;
  }
  final BitmapLayerState layer = controller._activeLayer;
  if (layer.locked) {
    return false;
  }
  if (layer.surface.isTiled) {
    return false;
  }
  final List<double>? profile =
      BitmapCanvasController._kAntialiasBlendProfiles[level];
  if (profile == null ||
      profile.isEmpty ||
      profile.every((double f) => f <= 0)) {
    return false;
  }
  final Uint32List pixels = layer.surface.pixels;
  if (pixels.isEmpty || layer.surface.isClean) {
    return false;
  }
  return true;
}

bool _shaderAntialiasSupported() {
  return true;
}

Future<bool> _shaderApplyAntialiasToActiveLayer(
  BitmapCanvasController controller,
  int level,
) async {
  if (!_canApplyAntialias(controller, level)) {
    return false;
  }
  final BitmapLayerState layer = controller._activeLayer;
  try {
    final ui.Image? initial = await _shaderImageFromPixels(
      layer.surface.pixels,
      controller._width,
      controller._height,
    );
    if (initial == null) {
      return false;
    }

    ui.Image working = initial;
    final List<double> profile =
        BitmapCanvasController._kAntialiasBlendProfiles[level] ??
        const <double>[];
    for (final double factor in profile) {
      if (factor <= 0) {
        continue;
      }
      final ui.Image next = await _shaderRunAlphaPass(
        working,
        controller._width,
        controller._height,
        factor,
      );
      working.dispose();
      working = next;
    }

    final ui.Image smoothed = await _shaderRunEdgeSmoothPass(
      working,
      controller._width,
      controller._height,
    );
    working.dispose();

    final bool wroteBack = await _shaderWriteBackToLayer(smoothed, layer);
    smoothed.dispose();
    if (!wroteBack) {
      return false;
    }

    layer.surface.markDirty();
    controller._markDirty(layerId: layer.id, pixelsDirty: true);
    controller._notify();
    return true;
  } on Object catch (error, stack) {
    debugPrint('Shader antialias failed: $error\n$stack');
    return false;
  }
}

Future<ui.Image?> _shaderImageFromPixels(
  Uint32List pixels,
  int width,
  int height,
) async {
  if (width <= 0 || height <= 0 || pixels.isEmpty) {
    return null;
  }
  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
    Uint8List.view(pixels.buffer),
  );
  final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    rowBytes: width * 4,
    pixelFormat: ui.PixelFormat.bgra8888,
  );
  final ui.Codec codec = await descriptor.instantiateCodec();
  final ui.FrameInfo frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}

Future<ui.Image> _shaderRunAlphaPass(
  ui.Image input,
  int width,
  int height,
  double blendFactor,
) async {
  final ui.FragmentProgram program =
      await _ShaderAntialiasPrograms.alphaProgram;
  final ui.FragmentShader shader = program.fragmentShader()
    ..setFloat(0, width.toDouble())
    ..setFloat(1, height.toDouble())
    ..setFloat(2, blendFactor)
    ..setImageSampler(0, input);
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..shader = shader,
  );
  final ui.Picture picture = recorder.endRecording();
  final ui.Image output = await picture.toImage(width, height);
  picture.dispose();
  return output;
}

Future<ui.Image> _shaderRunEdgeSmoothPass(
  ui.Image input,
  int width,
  int height,
) async {
  final ui.FragmentProgram program = await _ShaderAntialiasPrograms.edgeProgram;
  final ui.FragmentShader shader = program.fragmentShader()
    ..setFloat(0, width.toDouble())
    ..setFloat(1, height.toDouble())
    ..setImageSampler(0, input);
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..shader = shader,
  );
  final ui.Picture picture = recorder.endRecording();
  final ui.Image output = await picture.toImage(width, height);
  picture.dispose();
  return output;
}

Future<bool> _shaderWriteBackToLayer(
  ui.Image image,
  BitmapLayerState layer,
) async {
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (data == null) {
    return false;
  }
  final Uint8List rgba = data.buffer.asUint8List();
  final Uint32List dest = layer.surface.pixels;
  if (rgba.length < dest.length * 4) {
    return false;
  }
  int byteIndex = 0;
  for (int i = 0; i < dest.length; i++) {
    final int r = rgba[byteIndex];
    final int g = rgba[byteIndex + 1];
    final int b = rgba[byteIndex + 2];
    final int a = rgba[byteIndex + 3];
    dest[i] = (a << 24) | (r << 16) | (g << 8) | b;
    byteIndex += 4;
  }
  return true;
}

class _ShaderAntialiasPrograms {
  static Future<ui.FragmentProgram> get alphaProgram => _alphaProgram ??=
      ui.FragmentProgram.fromAsset('shaders/antialias_alpha.frag');

  static Future<ui.FragmentProgram> get edgeProgram => _edgeProgram ??=
      ui.FragmentProgram.fromAsset('shaders/antialias_edge.frag');

  static Future<ui.FragmentProgram>? _alphaProgram;
  static Future<ui.FragmentProgram>? _edgeProgram;
}
