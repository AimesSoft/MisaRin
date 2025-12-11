import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;

enum CanvasCreationLogic { singleThread, multiThread }

/// 渲染后端：CPU（位图画布）或 GPU（实验性着色器画布）。
enum CanvasRenderBackend { cpu, gpu }

class CanvasSettings {
  const CanvasSettings._({
    required this.width,
    required this.height,
    required this.backgroundColor,
    required this.creationLogic,
    required this.renderBackend,
  });

  factory CanvasSettings({
    required double width,
    required double height,
    required Color backgroundColor,
    CanvasCreationLogic creationLogic = CanvasCreationLogic.multiThread,
    CanvasRenderBackend renderBackend = CanvasRenderBackend.cpu,
  }) {
    return CanvasSettings._(
      width: width,
      height: height,
      backgroundColor: backgroundColor,
      creationLogic: _resolveCreationLogic(creationLogic),
      renderBackend: renderBackend,
    );
  }

  final double width;
  final double height;
  final Color backgroundColor;
  final CanvasCreationLogic creationLogic;
  final CanvasRenderBackend renderBackend;

  static bool get supportsMultithreadedCanvas => !kIsWeb;

  static CanvasCreationLogic _resolveCreationLogic(
    CanvasCreationLogic _,
  ) {
    if (!supportsMultithreadedCanvas) {
      return CanvasCreationLogic.singleThread;
    }
    return CanvasCreationLogic.multiThread;
  }

  Size get size => Size(width, height);

  CanvasSettings copyWith({
    double? width,
    double? height,
    Color? backgroundColor,
    CanvasCreationLogic? creationLogic,
    CanvasRenderBackend? renderBackend,
  }) {
    return CanvasSettings(
      width: width ?? this.width,
      height: height ?? this.height,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      creationLogic:
          _resolveCreationLogic(creationLogic ?? this.creationLogic),
      renderBackend: renderBackend ?? this.renderBackend,
    );
  }

  static const CanvasSettings defaults = CanvasSettings._(
    width: 1920,
    height: 1080,
    backgroundColor: Color(0xFFFFFFFF),
    creationLogic: CanvasCreationLogic.multiThread,
    renderBackend: CanvasRenderBackend.cpu,
  );
}
