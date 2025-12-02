import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show MenuSerializableShortcut, SingleActivator;

import '../models/workspace_layout.dart';
import 'menu_action_dispatcher.dart';

sealed class MenuEntry {
  const MenuEntry();
}

class MenuActionEntry extends MenuEntry {
  const MenuActionEntry({
    required this.label,
    required this.action,
    this.shortcut,
    this.checked = false,
  });

  final String label;
  final MenuAsyncAction? action;
  final MenuSerializableShortcut? shortcut;
  final bool checked;
}

class MenuSubmenuEntry extends MenuEntry {
  const MenuSubmenuEntry({required this.label, required this.entries});

  final String label;
  final List<MenuEntry> entries;
}

class MenuProvidedEntry extends MenuEntry {
  const MenuProvidedEntry(this.type);

  final MenuProvidedType type;
}

class MenuSeparatorEntry extends MenuEntry {
  const MenuSeparatorEntry();
}

enum MenuProvidedType {
  servicesSubmenu,
  hide,
  hideOthers,
  showAll,
  quit,
  minimizeWindow,
  zoomWindow,
  arrangeWindowsInFront,
}

class MenuDefinition {
  const MenuDefinition({required this.label, required this.entries});

  final String label;
  final List<MenuEntry> entries;
}

class MenuDefinitionBuilder {
  const MenuDefinitionBuilder._();

  static List<MenuDefinition> build(MenuActionHandler handler) {
    return <MenuDefinition?>[
      _applicationMenu(handler),
      _fileMenu(handler),
      _editMenu(handler),
      _imageMenu(handler),
      _layerMenu(handler),
      _selectionMenu(handler),
      _filterMenu(handler),
      _toolMenu(handler),
      _viewMenu(handler),
      _workspaceMenu(handler),
      _windowMenu(),
    ].whereType<MenuDefinition>().toList(growable: false);
  }

  static MenuDefinition? _applicationMenu(MenuActionHandler handler) {
    final List<MenuEntry> entries = <MenuEntry>[];

    _addSection(entries, <MenuEntry>[
      if (handler.about != null)
        MenuActionEntry(label: '关于 Misa Rin', action: handler.about),
    ]);

    _addSection(entries, <MenuEntry>[
      if (handler.preferences != null)
        MenuActionEntry(
          label: '偏好设置…',
          action: handler.preferences,
          shortcut: const SingleActivator(LogicalKeyboardKey.comma, meta: true),
        ),
    ]);

    _addSection(entries, const <MenuEntry>[
      MenuProvidedEntry(MenuProvidedType.servicesSubmenu),
    ]);

    _addSection(entries, const <MenuEntry>[
      MenuProvidedEntry(MenuProvidedType.hide),
      MenuProvidedEntry(MenuProvidedType.hideOthers),
      MenuProvidedEntry(MenuProvidedType.showAll),
    ]);

    _addSection(entries, const <MenuEntry>[
      MenuProvidedEntry(MenuProvidedType.quit),
    ]);

    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: 'Misa Rin', entries: entries);
  }

  static MenuDefinition? _fileMenu(MenuActionHandler handler) {
    final List<MenuEntry> entries = <MenuEntry>[];

    _addSection(entries, <MenuEntry>[
      if (handler.newProject != null)
        MenuActionEntry(
          label: '新建…',
          action: handler.newProject,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
        ),
      if (handler.open != null)
        MenuActionEntry(
          label: '打开…',
          action: handler.open,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
        ),
      if (handler.importImage != null)
        MenuActionEntry(
          label: '导入图像…',
          action: handler.importImage,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyI, meta: true),
        ),
      if (handler.importImageFromClipboard != null)
        MenuActionEntry(
          label: '从剪贴板导入图像',
          action: handler.importImageFromClipboard,
        ),
    ]);

    _addSection(entries, <MenuEntry>[
      if (handler.save != null)
        MenuActionEntry(
          label: '保存',
          action: handler.save,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
        ),
      if (handler.saveAs != null)
        MenuActionEntry(
          label: '另存为…',
          action: handler.saveAs,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyS,
            meta: true,
            shift: true,
          ),
        ),
      if (handler.export != null)
        MenuActionEntry(
          label: '导出…',
          action: handler.export,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyE,
            meta: true,
            shift: true,
          ),
        ),
    ]);

    _addSection(entries, <MenuEntry>[
      if (handler.closeAll != null)
        MenuActionEntry(
          label: '关闭全部',
          action: handler.closeAll,
          shortcut: const SingleActivator(LogicalKeyboardKey.escape),
        ),
    ]);

    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: '文件', entries: entries);
  }

  static MenuDefinition? _editMenu(MenuActionHandler handler) {
    final List<MenuEntry> entries = <MenuEntry>[];

    _addSection(entries, <MenuEntry>[
      if (handler.undo != null)
        MenuActionEntry(
          label: '撤销',
          action: handler.undo,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
        ),
      if (handler.redo != null)
        MenuActionEntry(
          label: '恢复',
          action: handler.redo,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ),
        ),
    ]);

    _addSection(entries, <MenuEntry>[
      if (handler.cut != null)
        MenuActionEntry(
          label: '剪切',
          action: handler.cut,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
        ),
      if (handler.copy != null)
        MenuActionEntry(
          label: '复制',
          action: handler.copy,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
        ),
      if (handler.paste != null)
        MenuActionEntry(
          label: '粘贴',
          action: handler.paste,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
        ),
    ]);

    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: '编辑', entries: entries);
  }

  static MenuDefinition? _imageMenu(MenuActionHandler handler) {
    final List<MenuEntry> entries = <MenuEntry>[];

    final List<MenuEntry> transformEntries = <MenuEntry>[
      if (handler.rotateCanvas90Clockwise != null)
        MenuActionEntry(
          label: '顺时针 90 度',
          action: handler.rotateCanvas90Clockwise,
        ),
      if (handler.rotateCanvas90CounterClockwise != null)
        MenuActionEntry(
          label: '逆时针 90 度',
          action: handler.rotateCanvas90CounterClockwise,
        ),
      if (handler.rotateCanvas180Clockwise != null)
        MenuActionEntry(
          label: '顺时针 180 度',
          action: handler.rotateCanvas180Clockwise,
        ),
      if (handler.rotateCanvas180CounterClockwise != null)
        MenuActionEntry(
          label: '逆时针 180 度',
          action: handler.rotateCanvas180CounterClockwise,
        ),
    ];
    if (transformEntries.isNotEmpty) {
      entries.add(MenuSubmenuEntry(label: '图像变换', entries: transformEntries));
    }

    _addSection(entries, <MenuEntry>[
      if (handler.resizeImage != null)
        MenuActionEntry(
          label: '图像大小…',
          action: handler.resizeImage,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyI,
            meta: true,
            alt: true,
          ),
        ),
      if (handler.resizeCanvas != null)
        MenuActionEntry(
          label: '画布大小…',
          action: handler.resizeCanvas,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyC,
            meta: true,
            alt: true,
          ),
        ),
    ]);

    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: '图像', entries: entries);
  }

  static MenuDefinition? _layerMenu(MenuActionHandler handler) {
    final List<MenuEntry> entries = <MenuEntry>[];

    final List<MenuEntry> newEntries = <MenuEntry>[
      if (handler.newLayer != null)
        MenuActionEntry(
          label: '图层…',
          action: handler.newLayer,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyN,
            meta: true,
            shift: true,
          ),
        ),
    ];
    if (newEntries.isNotEmpty) {
      entries.add(MenuSubmenuEntry(label: '新建', entries: newEntries));
    }

    if (handler.mergeLayerDown != null) {
      entries.add(
        MenuActionEntry(label: '向下合并', action: handler.mergeLayerDown),
      );
    }

    if (handler.layerFreeTransform != null) {
      entries.add(
        MenuActionEntry(
          label: '变换',
          action: handler.layerFreeTransform,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyT, meta: true),
        ),
      );
    }

    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: '图层', entries: entries);
  }

  static MenuDefinition? _selectionMenu(MenuActionHandler handler) {
    final List<MenuEntry> entries = <MenuEntry>[
      if (handler.selectAll != null)
        MenuActionEntry(
          label: '全选',
          action: handler.selectAll,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
        ),
      if (handler.invertSelection != null)
        MenuActionEntry(
          label: '反选',
          action: handler.invertSelection,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyI,
            meta: true,
            shift: true,
          ),
        ),
    ];
    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: '选择', entries: entries);
  }

  static MenuDefinition? _toolMenu(MenuActionHandler handler) {
    final List<MenuEntry> paletteEntries = <MenuEntry>[
      if (handler.generatePalette != null)
        MenuActionEntry(label: '取色当前画布生成调色盘…', action: handler.generatePalette),
      if (handler.generateGradientPalette != null)
        MenuActionEntry(
          label: '使用当前颜色生成渐变调色盘',
          action: handler.generateGradientPalette,
        ),
      if (handler.importPalette != null)
        MenuActionEntry(label: '导入调色盘…', action: handler.importPalette),
    ];

    if (handler.paletteMenuEntries.isNotEmpty &&
        handler.selectPaletteFromMenu != null) {
      final MenuPaletteAction selectAction = handler.selectPaletteFromMenu!;
      paletteEntries.addAll(
        handler.paletteMenuEntries.map(
          (entry) => MenuActionEntry(
            label: entry.label,
            action: () => selectAction(entry.id),
          ),
        ),
      );
    }

    final List<MenuEntry> entries = <MenuEntry>[];
    if (paletteEntries.isNotEmpty) {
      entries.add(MenuSubmenuEntry(label: '调色盘', entries: paletteEntries));
    }
    final List<MenuEntry> referenceEntries = <MenuEntry>[
      if (handler.createReferenceImage != null)
        MenuActionEntry(
          label: '创建参考图像',
          action: handler.createReferenceImage,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyR,
            meta: true,
            shift: true,
          ),
        ),
      if (handler.importReferenceImage != null)
        MenuActionEntry(
          label: '导入参考图像…',
          action: handler.importReferenceImage,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyR,
            meta: true,
            alt: true,
          ),
        ),
    ];
    if (referenceEntries.isNotEmpty) {
      entries.add(MenuSubmenuEntry(label: '参考图像', entries: referenceEntries));
    }
    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: '工具', entries: entries);
  }

  static MenuDefinition? _viewMenu(MenuActionHandler handler) {
    final List<MenuEntry> entries = <MenuEntry>[
      if (handler.zoomIn != null)
        MenuActionEntry(
          label: '放大',
          action: handler.zoomIn,
          shortcut: const SingleActivator(LogicalKeyboardKey.equal, meta: true),
        ),
      if (handler.zoomOut != null)
        MenuActionEntry(
          label: '缩小',
          action: handler.zoomOut,
          shortcut: const SingleActivator(LogicalKeyboardKey.minus, meta: true),
        ),
    ];
    if (handler.togglePixelGrid != null) {
      if (entries.isNotEmpty) {
        entries.add(const MenuSeparatorEntry());
      }
      entries.add(
        MenuActionEntry(
          label: handler.pixelGridVisible ? '隐藏网格' : '显示网格',
          action: handler.togglePixelGrid,
          checked: handler.pixelGridVisible,
        ),
      );
    }
    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: '视图', entries: entries);
  }

  static MenuDefinition? _workspaceMenu(MenuActionHandler handler) {
    final MenuWorkspaceLayoutAction? switchLayout =
        handler.switchWorkspaceLayout;
    if (switchLayout == null) {
      return null;
    }
    final WorkspaceLayoutPreference? current =
        handler.workspaceLayoutPreference;
    final List<MenuEntry> entries = <MenuEntry>[
      MenuActionEntry(
        label: '默认',
        action: () => switchLayout(WorkspaceLayoutPreference.floating),
        checked: current == WorkspaceLayoutPreference.floating,
      ),
      MenuActionEntry(
        label: 'SAI2',
        action: () => switchLayout(WorkspaceLayoutPreference.sai2),
        checked: current == WorkspaceLayoutPreference.sai2,
      ),
    ];
    return MenuDefinition(
      label: '工作区',
      entries: <MenuEntry>[
        MenuSubmenuEntry(label: '切换工作区', entries: entries),
        if (handler.resetWorkspaceLayout != null) ...[
          const MenuSeparatorEntry(),
          MenuActionEntry(label: '复位工作区', action: handler.resetWorkspaceLayout),
        ],
      ],
    );
  }

  static MenuDefinition? _filterMenu(MenuActionHandler handler) {
    final List<MenuEntry> entries = <MenuEntry>[
      if (handler.showLayerAntialiasPanel != null)
        MenuActionEntry(
          label: '抗锯齿…',
          action: handler.showLayerAntialiasPanel,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyA,
            meta: true,
            alt: true,
          ),
        ),
      if (handler.gaussianBlur != null)
        MenuActionEntry(
          label: '高斯模糊…',
          action: handler.gaussianBlur,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyG,
            meta: true,
            alt: true,
          ),
        ),
      if (handler.adjustHueSaturation != null)
        MenuActionEntry(
          label: '色相/饱和度…',
          action: handler.adjustHueSaturation,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyU, meta: true),
        ),
      if (handler.adjustBrightnessContrast != null)
        MenuActionEntry(
          label: '亮度/对比度…',
          action: handler.adjustBrightnessContrast,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyM, meta: true),
        ),
    ];
    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: '滤镜', entries: entries);
  }

  static MenuDefinition _windowMenu() {
    return const MenuDefinition(
      label: '窗口',
      entries: <MenuEntry>[
        MenuProvidedEntry(MenuProvidedType.minimizeWindow),
        MenuProvidedEntry(MenuProvidedType.zoomWindow),
        MenuProvidedEntry(MenuProvidedType.arrangeWindowsInFront),
      ],
    );
  }

  static void _addSection(List<MenuEntry> entries, List<MenuEntry> section) {
    if (section.isEmpty) {
      return;
    }
    if (entries.isNotEmpty) {
      entries.add(const MenuSeparatorEntry());
    }
    entries.addAll(section);
  }
}
