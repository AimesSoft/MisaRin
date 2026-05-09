import 'dart:typed_data';
import 'dart:ui';

import '../../bitmap_canvas/stroke_dynamics.dart' show StrokePressureProfile;
import '../../canvas/canvas_tools.dart'
    show CanvasTool, SelectionShape, ShapeToolVariant, SprayMode;
import '../../canvas/text_renderer.dart' show CanvasTextOrientation;
import '../preferences/app_preferences.dart'
    show BucketSwallowColorLineMode, PenStrokeSliderRange;

class PaletteCardSnapshot {
  const PaletteCardSnapshot({
    required this.title,
    required this.colors,
    required this.offset,
    this.size,
  });

  final String title;
  final List<int> colors;
  final Offset offset;
  final Size? size;
}

class ReferenceCardSnapshot {
  const ReferenceCardSnapshot({
    required this.imageBytes,
    required this.bodySize,
    required this.panelSize,
    required this.offset,
    this.size,
    this.pixelBytes,
  });

  final Uint8List imageBytes;
  final Uint8List? pixelBytes;
  final Size bodySize;
  final Size panelSize;
  final Offset offset;
  final Size? size;
}

class WorkspaceOverlaySnapshot {
  const WorkspaceOverlaySnapshot({
    this.paletteCards = const <PaletteCardSnapshot>[],
    this.referenceCards = const <ReferenceCardSnapshot>[],
  });

  final List<PaletteCardSnapshot> paletteCards;
  final List<ReferenceCardSnapshot> referenceCards;

  bool get isEmpty => paletteCards.isEmpty && referenceCards.isEmpty;
}

class ToolSettingsSnapshot {
  const ToolSettingsSnapshot({
    required this.activeTool,
    required this.primaryColor,
    required this.recentColors,
    required this.colorLineColor,
    required this.penStrokeWidth,
    required this.sprayStrokeWidth,
    required this.eraserStrokeWidth,
    required this.liquifyStrokeWidth,
    required this.liquifyStrength,
    required this.liquifySoftness,
    required this.liquifyMix,
    required this.sprayMode,
    required this.penStrokeSliderRange,
    required this.sprayStrokeSliderRange,
    required this.eraserStrokeSliderRange,
    required this.brushPresetId,
    required this.strokeStabilizerStrength,
    required this.streamlineStrength,
    required this.stylusPressureEnabled,
    required this.simulatePenPressure,
    required this.penPressureProfile,
    required this.bucketAntialiasLevel,
    required this.bucketSampleAllLayers,
    required this.bucketContiguous,
    required this.bucketSwallowColorLine,
    required this.bucketSwallowColorLineMode,
    required this.bucketTolerance,
    required this.bucketFillGap,
    required this.magicWandTolerance,
    required this.brushToolsEraserMode,
    required this.layerAdjustCropOutside,
    required this.shapeFillEnabled,
    required this.selectionShape,
    required this.selectionAdditiveEnabled,
    required this.shapeToolVariant,
    required this.textFontSize,
    required this.textLineHeight,
    required this.textLetterSpacing,
    required this.textFontFamily,
    required this.textAlign,
    required this.textOrientation,
    required this.textAntialias,
    required this.textStrokeEnabled,
    required this.textStrokeWidth,
  });

  final CanvasTool activeTool;
  final int primaryColor;
  final List<int> recentColors;
  final int colorLineColor;
  final double penStrokeWidth;
  final double sprayStrokeWidth;
  final double eraserStrokeWidth;
  final double liquifyStrokeWidth;
  final double liquifyStrength;
  final double liquifySoftness;
  final double liquifyMix;
  final SprayMode sprayMode;
  final PenStrokeSliderRange penStrokeSliderRange;
  final PenStrokeSliderRange sprayStrokeSliderRange;
  final PenStrokeSliderRange eraserStrokeSliderRange;
  final String brushPresetId;
  final double strokeStabilizerStrength;
  final double streamlineStrength;
  final bool stylusPressureEnabled;
  final bool simulatePenPressure;
  final StrokePressureProfile penPressureProfile;
  final int bucketAntialiasLevel;
  final bool bucketSampleAllLayers;
  final bool bucketContiguous;
  final bool bucketSwallowColorLine;
  final BucketSwallowColorLineMode bucketSwallowColorLineMode;
  final int bucketTolerance;
  final int bucketFillGap;
  final int magicWandTolerance;
  final bool brushToolsEraserMode;
  final bool layerAdjustCropOutside;
  final bool shapeFillEnabled;
  final SelectionShape selectionShape;
  final bool selectionAdditiveEnabled;
  final ShapeToolVariant shapeToolVariant;
  final double textFontSize;
  final double textLineHeight;
  final double textLetterSpacing;
  final String textFontFamily;
  final TextAlign textAlign;
  final CanvasTextOrientation textOrientation;
  final bool textAntialias;
  final bool textStrokeEnabled;
  final double textStrokeWidth;
}
