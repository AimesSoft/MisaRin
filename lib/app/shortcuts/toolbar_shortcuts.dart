import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum ToolbarAction {
  exit,
  layerAdjustTool,
  freeTransform,
  penTool,
  perspectivePenTool,
  sprayTool,
  smudgeTool,
  liquifyTool,
  curvePenTool,
  shapeTool,
  eraserTool,
  bucketTool,
  magicWandTool,
  eyedropperTool,
  selectionTool,
  selectionPenTool,
  textTool,
  handTool,
  rotateTool,
  undo,
  redo,
  resizeImage,
  resizeCanvas,
  adjustHueSaturation,
  adjustBrightnessContrast,
  colorRange,
  adjustBlackWhite,
  binarize,
  scanPaperDrawing,
  invertColors,
  narrowLines,
  expandFill,
  gaussianBlur,
  removeColorLeak,
  layerAntialiasPanel,
  deselect,
  importReferenceImage,
  viewBlackWhiteOverlay,
  togglePixelGrid,
  viewMirrorOverlay,
}

class ShortcutInfo {
  const ShortcutInfo({
    required this.shortcuts,
    required this.primaryLabel,
    String? macLabel,
  }) : macLabel = macLabel ?? primaryLabel;

  final List<LogicalKeySet> shortcuts;
  final String primaryLabel;
  final String macLabel;

  String labelForPlatform(TargetPlatform platform) {
    if (platform == TargetPlatform.macOS) {
      return macLabel;
    }
    return primaryLabel;
  }
}

class ToolbarShortcuts {
  const ToolbarShortcuts._();

  static final Map<ToolbarAction, ShortcutInfo> _shortcuts = {
    ToolbarAction.exit: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.escape)],
      primaryLabel: 'Esc',
    ),
    ToolbarAction.layerAdjustTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyV)],
      primaryLabel: 'V',
    ),
    ToolbarAction.freeTransform: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyT),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyT),
      ],
      primaryLabel: 'Ctrl+T',
      macLabel: 'Command+T',
    ),
    ToolbarAction.bucketTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyG)],
      primaryLabel: 'G',
    ),
    ToolbarAction.penTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyB)],
      primaryLabel: 'B',
    ),
    ToolbarAction.perspectivePenTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyY)],
      primaryLabel: 'Y',
    ),
    ToolbarAction.sprayTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyJ)],
      primaryLabel: 'J',
    ),
    ToolbarAction.smudgeTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyU)],
      primaryLabel: 'U',
    ),
    ToolbarAction.liquifyTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyL)],
      primaryLabel: 'L',
    ),
    ToolbarAction.curvePenTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyP)],
      primaryLabel: 'P',
    ),
    ToolbarAction.shapeTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyR)],
      primaryLabel: 'R',
    ),
    ToolbarAction.eraserTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyE)],
      primaryLabel: 'E',
    ),
    ToolbarAction.magicWandTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyW)],
      primaryLabel: 'W',
    ),
    ToolbarAction.eyedropperTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyI)],
      primaryLabel: 'I',
    ),
    ToolbarAction.selectionTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyM)],
      primaryLabel: 'M',
    ),
    ToolbarAction.selectionPenTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyS)],
      primaryLabel: 'S',
    ),
    ToolbarAction.textTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyT)],
      primaryLabel: 'T',
    ),
    ToolbarAction.handTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyH)],
      primaryLabel: 'H',
    ),
    ToolbarAction.rotateTool: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyO)],
      primaryLabel: 'O',
    ),
    ToolbarAction.undo: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyZ),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyZ),
      ],
      primaryLabel: 'Ctrl+Z',
      macLabel: 'Command+Z',
    ),
    ToolbarAction.redo: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyZ,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyZ,
        ),
      ],
      primaryLabel: 'Ctrl+Shift+Z',
      macLabel: 'Command+Shift+Z',
    ),
    ToolbarAction.resizeImage: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyI,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyI,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+I',
      macLabel: 'Command+Option+I',
    ),
    ToolbarAction.resizeCanvas: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyC,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyC,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+C',
      macLabel: 'Command+Option+C',
    ),
    ToolbarAction.adjustHueSaturation: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyU),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyU),
      ],
      primaryLabel: 'Ctrl+U',
      macLabel: 'Command+U',
    ),
    ToolbarAction.adjustBrightnessContrast: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyM),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyM),
      ],
      primaryLabel: 'Ctrl+M',
      macLabel: 'Command+M',
    ),
    ToolbarAction.colorRange: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyR,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyR,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+Shift+R',
      macLabel: 'Command+Option+Shift+R',
    ),
    ToolbarAction.adjustBlackWhite: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyK,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyK,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+K',
      macLabel: 'Command+Option+K',
    ),
    ToolbarAction.binarize: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyB,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyB,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+B',
      macLabel: 'Command+Option+B',
    ),
    ToolbarAction.scanPaperDrawing: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyP,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyP,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+P',
      macLabel: 'Command+Option+P',
    ),
    ToolbarAction.invertColors: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyI,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyI,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+Shift+I',
      macLabel: 'Command+Option+Shift+I',
    ),
    ToolbarAction.narrowLines: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyN,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyN,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+N',
      macLabel: 'Command+Option+N',
    ),
    ToolbarAction.expandFill: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyE,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyE,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+E',
      macLabel: 'Command+Option+E',
    ),
    ToolbarAction.gaussianBlur: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyG,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyG,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+G',
      macLabel: 'Command+Option+G',
    ),
    ToolbarAction.removeColorLeak: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyL,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyL,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+L',
      macLabel: 'Command+Option+L',
    ),
    ToolbarAction.layerAntialiasPanel: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyA,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyA,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+A',
      macLabel: 'Command+Option+A',
    ),
    ToolbarAction.deselect: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyD),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyD),
      ],
      primaryLabel: 'Ctrl+D',
      macLabel: 'Command+D',
    ),
    ToolbarAction.importReferenceImage: ShortcutInfo(
      shortcuts: <LogicalKeySet>[
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyR,
        ),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.keyR,
        ),
      ],
      primaryLabel: 'Ctrl+Alt+R',
      macLabel: 'Command+Option+R',
    ),
    ToolbarAction.viewBlackWhiteOverlay: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyK)],
      primaryLabel: 'K',
    ),
    ToolbarAction.togglePixelGrid: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyQ)],
      primaryLabel: 'Q',
    ),
    ToolbarAction.viewMirrorOverlay: ShortcutInfo(
      shortcuts: <LogicalKeySet>[LogicalKeySet(LogicalKeyboardKey.keyF)],
      primaryLabel: 'F',
    ),
  };

  static ShortcutInfo of(ToolbarAction action) {
    return _shortcuts[action]!;
  }

  static String labelForPlatform(
    ToolbarAction action,
    TargetPlatform platform,
  ) {
    return of(action).labelForPlatform(platform);
  }
}
