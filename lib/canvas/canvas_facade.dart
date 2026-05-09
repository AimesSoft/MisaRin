import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../backend/canvas_painting_worker.dart';
import 'canvas_backend.dart';
import 'canvas_frame.dart';
import 'canvas_layer.dart';
import 'canvas_layer_info.dart';
import 'canvas_composite_layer.dart';
import 'canvas_tool_host.dart';
import 'canvas_tools.dart';
import 'text_renderer.dart';

abstract class CanvasFacade extends Listenable implements CanvasToolHost {
  int get width;
  int get height;
  Color get backgroundColor;

  UnmodifiableListView<CanvasLayerInfo> get layers;
  UnmodifiableListView<CanvasCompositeLayer> get compositeLayers;
  CanvasLayerInfo get activeLayer;
  String? get activeLayerId;
  CanvasBackend get rasterBackend;

  int get activeStrokeRotationSeed;
  CanvasFrame? get frame;

  List<Offset> get activeStrokePoints;
  List<double> get activeStrokeRadii;
  List<PaintingDrawCommand> get committingStrokes;
  int get commitOverlayFadeVersion;
  double commitOverlayOpacityFor(PaintingDrawCommand command);
  bool get rasterOutputEnabled;
  void setRasterOutputEnabled(bool enabled);
  bool get activeStrokeSnapToPixel;
  Color get activeStrokeColor;
  BrushShape get activeStrokeShape;
  bool get activeStrokeEraseMode;
  int get activeStrokeAntialiasLevel;
  bool get activeStrokeHollowEnabled;
  double get activeStrokeHollowRatio;
  bool get activeStrokeRandomRotationEnabled;

  Image? get activeLayerTransformImage;
  Offset get activeLayerTransformOffset;
  Offset get activeLayerTransformOrigin;
  Rect? get activeLayerTransformBounds;
  double get activeLayerTransformOpacity;
  CanvasLayerBlendMode get activeLayerTransformBlendMode;

  bool get clipLayerOverflow;
  bool get hasVisibleContent;
  bool get isActiveLayerTransforming;
  bool get isActiveLayerTransformPendingCleanup;

  void configureStylusPressure({
    required bool enabled,
    double? curve,
  });

  void configureSharpTips({required bool enabled});

  Future<Uint8List?> computeMagicWandMask(
    Offset position, {
    bool sampleAllLayers = true,
    int tolerance = 0,
  });

  void clear();

  void setLayerOverflowCropping(bool enabled);
  void translateActiveLayer(int dx, int dy);
  void commitActiveLayerTranslation();
  void cancelActiveLayerTranslation();
  void disposeActiveLayerTransformSession();

  void setActiveLayer(String id);
  void updateLayerVisibility(String id, bool visible);
  void setLayerOpacity(String id, double opacity);
  void setLayerLocked(String id, bool locked);
  void setLayerClippingMask(String id, bool clippingMask);
  void setLayerBlendMode(String id, CanvasLayerBlendMode mode);
  void renameLayer(String id, String name);
  void addLayer({String? aboveLayerId, String? name});
  Future<String> createTextLayer(CanvasTextData data);
  Future<void> updateTextLayer(String id, CanvasTextData data);
  void rasterizeTextLayer(String id);
  void removeLayer(String id);
  void reorderLayer(int fromIndex, int toIndex);
  bool mergeLayerDown(String id);

  void loadLayers(List<CanvasLayerData> layers, Color backgroundColor);
  List<CanvasLayerData> snapshotLayers();
  CanvasLayerData? buildClipboardLayer(String id, {Uint8List? mask});
  void clearLayerRegion(String id, {Uint8List? mask});
  String insertLayerFromData(CanvasLayerData data, {String? aboveLayerId});
  void replaceLayer(String id, CanvasLayerData data);

  Rect? restoreLayerRegion(
    CanvasLayerData snapshot,
    Rect region, {
    Uint32List? pixelCache,
    bool markDirty = true,
  });

  void markLayerRegionDirty(String id, Rect region);

  Future<Image> snapshotImage();
  Future<void> waitForPendingWorkerTasks();
  Future<void> disposeController();
  void notifyListeners();

  Future<bool> applyAntialiasToActiveLayer(
    int level, {
    bool previewOnly = false,
  });

  void setSelectionMask(Uint8List? mask);

  Color sampleColor(Offset position, {bool sampleAllLayers = true});

  Uint32List? readLayerPixels(String id);
  Size? readLayerSurfaceSize(String id);
  bool writeLayerPixels(
    String id,
    Uint32List pixels, {
    bool markDirty = true,
  });
}
