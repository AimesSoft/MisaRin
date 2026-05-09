import 'dart:ui';

abstract class CanvasToolHost {
  Color sampleColor(Offset position, {bool sampleAllLayers = true});
}
