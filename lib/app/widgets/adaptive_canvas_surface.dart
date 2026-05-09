import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../canvas/canvas_frame.dart';
import '../../canvas/canvas_tools.dart';
import 'backend_canvas_surface.dart';

class AdaptiveCanvasSurface extends StatelessWidget {
  const AdaptiveCanvasSurface({
    super.key,
    required this.surfaceKey,
    required this.canvasSize,
    required this.frame,
    required this.enableDrawing,
    this.allowBackendCanvas = true,
    this.layerCount = 1,
    required this.brushColorArgb,
    required this.brushRadius,
    required this.erase,
    required this.brushShape,
    required this.brushRandomRotationEnabled,
    required this.brushSmoothRotationEnabled,
    required this.brushRotationSeed,
    required this.brushSpacing,
    required this.brushHardness,
    required this.brushFlow,
    required this.brushScatter,
    required this.brushRotationJitter,
    required this.brushSnapToPixel,
    required this.brushScreentoneEnabled,
    required this.brushScreentoneSpacing,
    required this.brushScreentoneDotSize,
    required this.brushScreentoneRotation,
    required this.brushScreentoneSoftness,
    required this.brushScreentoneShape,
    this.hollowStrokeEnabled = false,
    this.hollowStrokeRatio = 0.0,
    this.hollowStrokeEraseOccludedParts = false,
    this.antialiasLevel = 1,
    this.backgroundColorArgb = 0xFFFFFFFF,
    this.usePressure = true,
    this.stylusCurve = 1.0,
    this.streamlineStrength = 0.0,
    this.strokeStabilizerStrength = 0.0,
    this.onStrokeBegin,
    this.onEngineInfoChanged,
  });

  final String surfaceKey;
  final ui.Size canvasSize;
  final CanvasFrame? frame;
  final bool enableDrawing;
  final bool allowBackendCanvas;
  final int layerCount;
  final int brushColorArgb;
  final double brushRadius;
  final bool erase;
  final BrushShape brushShape;
  final bool brushRandomRotationEnabled;
  final bool brushSmoothRotationEnabled;
  final int brushRotationSeed;
  final double brushSpacing;
  final double brushHardness;
  final double brushFlow;
  final double brushScatter;
  final double brushRotationJitter;
  final bool brushSnapToPixel;
  final bool brushScreentoneEnabled;
  final double brushScreentoneSpacing;
  final double brushScreentoneDotSize;
  final double brushScreentoneRotation;
  final double brushScreentoneSoftness;
  final BrushShape brushScreentoneShape;
  final bool hollowStrokeEnabled;
  final double hollowStrokeRatio;
  final bool hollowStrokeEraseOccludedParts;
  final int antialiasLevel;
  final int backgroundColorArgb;
  final bool usePressure;
  final double stylusCurve;
  final double streamlineStrength;
  final double strokeStabilizerStrength;
  final VoidCallback? onStrokeBegin;
  final void Function(
    int? handle,
    ui.Size? engineSize,
    bool isNewEngine,
    int? textureId,
  )?
  onEngineInfoChanged;

  @override
  Widget build(BuildContext context) {
    return BackendCanvasSurface(
      surfaceKey: surfaceKey,
      canvasSize: canvasSize,
      enableDrawing: enableDrawing,
      layerCount: layerCount,
      brushColorArgb: brushColorArgb,
      brushRadius: brushRadius,
      erase: erase,
      brushShape: brushShape,
      brushRandomRotationEnabled: brushRandomRotationEnabled,
      brushSmoothRotationEnabled: brushSmoothRotationEnabled,
      brushRotationSeed: brushRotationSeed,
      brushSpacing: brushSpacing,
      brushHardness: brushHardness,
      brushFlow: brushFlow,
      brushScatter: brushScatter,
      brushRotationJitter: brushRotationJitter,
      brushSnapToPixel: brushSnapToPixel,
      brushScreentoneEnabled: brushScreentoneEnabled,
      brushScreentoneSpacing: brushScreentoneSpacing,
      brushScreentoneDotSize: brushScreentoneDotSize,
      brushScreentoneRotation: brushScreentoneRotation,
      brushScreentoneSoftness: brushScreentoneSoftness,
      brushScreentoneShape: brushScreentoneShape,
      hollowStrokeEnabled: hollowStrokeEnabled,
      hollowStrokeRatio: hollowStrokeRatio,
      hollowStrokeEraseOccludedParts: hollowStrokeEraseOccludedParts,
      antialiasLevel: antialiasLevel,
      backgroundColorArgb: backgroundColorArgb,
      usePressure: usePressure,
      stylusCurve: stylusCurve,
      streamlineStrength: streamlineStrength,
      strokeStabilizerStrength: strokeStabilizerStrength,
      onStrokeBegin: onStrokeBegin,
      onEngineInfoChanged: onEngineInfoChanged,
    );
  }
}
