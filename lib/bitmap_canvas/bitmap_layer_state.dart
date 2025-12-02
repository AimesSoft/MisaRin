import '../canvas/canvas_layer.dart';
import 'bitmap_canvas.dart';

/// 在画布控制器与渲染后端之间共享的图层状态模型。
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
  int revision = 0;
}
