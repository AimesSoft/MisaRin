import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;

enum CanvasCreationLogic { singleThread, multiThread }

class CanvasSettings {
  const CanvasSettings._({
    required this.width,
    required this.height,
    required this.backgroundColor,
    required this.creationLogic,
  });

  factory CanvasSettings({
    required double width,
    required double height,
    required Color backgroundColor,
    CanvasCreationLogic creationLogic = CanvasCreationLogic.multiThread,
  }) {
    return CanvasSettings._(
      width: width,
      height: height,
      backgroundColor: backgroundColor,
      creationLogic: _resolveCreationLogic(creationLogic),
    );
  }

  final double width;
  final double height;
  final Color backgroundColor;
  final CanvasCreationLogic creationLogic;

  static bool get supportsMultithreadedCanvas => !kIsWeb;

  static CanvasCreationLogic _resolveCreationLogic(CanvasCreationLogic _) {
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
  }) {
    return CanvasSettings(
      width: width ?? this.width,
      height: height ?? this.height,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      creationLogic: _resolveCreationLogic(creationLogic ?? this.creationLogic),
    );
  }

  static const CanvasSettings defaults = CanvasSettings._(
    width: 1920,
    height: 1080,
    backgroundColor: Color(0xFFFFFFFF),
    creationLogic: CanvasCreationLogic.multiThread,
  );
}
