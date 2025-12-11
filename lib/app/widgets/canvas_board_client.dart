import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../canvas/canvas_layer.dart';
import '../../canvas/perspective_guide.dart';
import '../models/canvas_view_info.dart';

/// 画布控件对外暴露的最小接口，方便 CPU/GPU 不同实现之间切换。
abstract class CanvasBoardClient {
  bool get isBoardReady;

  ValueListenable<CanvasViewInfo> get viewInfoListenable;

  Future<List<CanvasLayerData>> exportLayers();

  PerspectiveGuideState snapshotPerspectiveGuide();

  void markSaved();

  Future<bool> undo();

  Future<bool> redo();

  bool get canUndo;

  bool get canRedo;
}
