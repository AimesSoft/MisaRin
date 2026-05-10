enum CanvasTool {
  layerAdjust,
  pen(supportsBrushPreset: true),
  perspectivePen(supportsBrushPreset: true),
  spray,
  smudge,
  liquify,
  curvePen(supportsBrushPreset: true),
  shape(supportsBrushPreset: true),
  eraser(supportsBrushPreset: true),
  bucket,
  magicWand,
  eyedropper,
  selection,
  selectionPen,
  text,
  hand,
  rotate;

  const CanvasTool({this.supportsBrushPreset = false});

  final bool supportsBrushPreset;
}

enum SprayMode { smudge, splatter }

enum SelectionShape { rectangle, ellipse, polygon }

enum ShapeToolVariant { rectangle, ellipse, triangle, line }

enum BrushShape { circle, triangle, square, star }
