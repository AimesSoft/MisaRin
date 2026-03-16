import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show MenuSerializableShortcut, SingleActivator;
import 'package:misa_rin/l10n/app_localizations.dart';

import '../models/workspace_layout.dart';
import 'menu_action_dispatcher.dart';
import '../../canvas/perspective_guide.dart';

sealed class MenuEntry {
  const MenuEntry();
}

class MenuActionEntry extends MenuEntry {
  const MenuActionEntry({
    required this.label,
    required this.action,
    this.shortcut,
    this.checked = false,
    this.enabled = true,
    this.enabledResolver,
  });

  final String label;
  final MenuAsyncAction? action;
  final MenuSerializableShortcut? shortcut;
  final bool checked;
  final bool enabled;
  final MenuActionEnabledResolver? enabledResolver;

  bool get isEnabled {
    final MenuActionEnabledResolver? resolver = enabledResolver;
    if (resolver != null) {
      return resolver();
    }
    return enabled;
  }
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

  static List<MenuDefinition> build(
    MenuActionHandler handler,
    AppLocalizations l10n,
  ) {
    return <MenuDefinition?>[
      _applicationMenu(handler, l10n),
      _fileMenu(handler, l10n),
      _editMenu(handler, l10n),
      _imageMenu(handler, l10n),
      _layerMenu(handler, l10n),
      _selectionMenu(handler, l10n),
      _filterMenu(handler, l10n),
      _toolMenu(handler, l10n),
      _viewMenu(handler, l10n),
      _workspaceMenu(handler, l10n),
      _windowMenu(l10n),
    ].whereType<MenuDefinition>().toList(growable: false);
  }

  static MenuDefinition? _applicationMenu(
    MenuActionHandler handler,
    AppLocalizations l10n,
  ) {
    final List<MenuEntry> entries = <MenuEntry>[];

    _addSection(entries, <MenuEntry>[
      if (handler.preferences != null)
        MenuActionEntry(
          label: l10n.menuPreferences,
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

  static MenuDefinition? _fileMenu(
    MenuActionHandler handler,
    AppLocalizations l10n,
  ) {
    final List<MenuEntry> entries = <MenuEntry>[];

    _addSection(entries, <MenuEntry>[
      if (handler.newProject != null)
        MenuActionEntry(
          label: l10n.menuNewEllipsis,
          action: handler.newProject,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
        ),
      if (handler.open != null)
        MenuActionEntry(
          label: l10n.menuOpenEllipsis,
          action: handler.open,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
        ),
      if (handler.importImage != null)
        MenuActionEntry(
          label: l10n.menuImportImageEllipsis,
          action: handler.importImage,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyI, meta: true),
        ),
      if (handler.importImageFromClipboard != null)
        MenuActionEntry(
          label: l10n.menuImportImageFromClipboard,
          action: handler.importImageFromClipboard,
        ),
    ]);

    _addSection(entries, <MenuEntry>[
      if (handler.save != null)
        MenuActionEntry(
          label: l10n.menuSave,
          action: handler.save,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
        ),
      if (handler.saveAs != null)
        MenuActionEntry(
          label: l10n.menuSaveAsEllipsis,
          action: handler.saveAs,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyS,
            meta: true,
            shift: true,
          ),
        ),
      if (handler.export != null)
        MenuActionEntry(
          label: l10n.menuExportEllipsis,
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
          label: l10n.menuCloseAll,
          action: handler.closeAll,
          shortcut: const SingleActivator(LogicalKeyboardKey.escape),
        ),
    ]);

    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: l10n.menuFile, entries: entries);
  }

  static MenuDefinition? _editMenu(
    MenuActionHandler handler,
    AppLocalizations l10n,
  ) {
    final List<MenuEntry> entries = <MenuEntry>[];

    _addSection(entries, <MenuEntry>[
      if (handler.undo != null)
        MenuActionEntry(
          label: l10n.menuUndo,
          action: handler.undo,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
          enabledResolver: handler.undoEnabled,
        ),
      if (handler.redo != null)
        MenuActionEntry(
          label: l10n.menuRedo,
          action: handler.redo,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ),
          enabledResolver: handler.redoEnabled,
        ),
    ]);

    _addSection(entries, <MenuEntry>[
      if (handler.cut != null)
        MenuActionEntry(
          label: l10n.menuCut,
          action: handler.cut,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
          enabledResolver: handler.cutEnabled,
        ),
      if (handler.copy != null)
        MenuActionEntry(
          label: l10n.menuCopy,
          action: handler.copy,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
          enabledResolver: handler.copyEnabled,
        ),
      if (handler.paste != null)
        MenuActionEntry(
          label: l10n.menuPaste,
          action: handler.paste,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
          enabledResolver: handler.pasteEnabled,
        ),
    ]);

    _addSection(entries, <MenuEntry>[
      if (handler.layerFreeTransform != null)
        MenuActionEntry(
          label: l10n.freeTransformTitle,
          action: handler.layerFreeTransform,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyT, meta: true),
        ),
    ]);

    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: l10n.menuEdit, entries: entries);
  }

  static MenuDefinition? _imageMenu(
    MenuActionHandler handler,
    AppLocalizations l10n,
  ) {
    final List<MenuEntry> entries = <MenuEntry>[];

    final List<MenuEntry> transformEntries = <MenuEntry>[
      if (handler.rotateCanvas90Clockwise != null)
        MenuActionEntry(
          label: l10n.menuRotate90CW,
          action: handler.rotateCanvas90Clockwise,
        ),
      if (handler.rotateCanvas90CounterClockwise != null)
        MenuActionEntry(
          label: l10n.menuRotate90CCW,
          action: handler.rotateCanvas90CounterClockwise,
        ),
      if (handler.rotateCanvas180Clockwise != null)
        MenuActionEntry(
          label: l10n.menuRotate180CW,
          action: handler.rotateCanvas180Clockwise,
        ),
      if (handler.rotateCanvas180CounterClockwise != null)
        MenuActionEntry(
          label: l10n.menuRotate180CCW,
          action: handler.rotateCanvas180CounterClockwise,
        ),
      if (handler.flipCanvasHorizontal != null)
        MenuActionEntry(
          label: l10n.menuFlipHorizontal,
          action: handler.flipCanvasHorizontal,
        ),
      if (handler.flipCanvasVertical != null)
        MenuActionEntry(
          label: l10n.menuFlipVertical,
          action: handler.flipCanvasVertical,
        ),
    ];
    if (transformEntries.isNotEmpty) {
      entries.add(
        MenuSubmenuEntry(
          label: l10n.menuImageTransform,
          entries: transformEntries,
        ),
      );
    }

    _addSection(entries, <MenuEntry>[
      if (handler.resizeImage != null)
        MenuActionEntry(
          label: l10n.menuImageSizeEllipsis,
          action: handler.resizeImage,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyI,
            meta: true,
            alt: true,
          ),
        ),
      if (handler.resizeCanvas != null)
        MenuActionEntry(
          label: l10n.menuCanvasSizeEllipsis,
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
    return MenuDefinition(label: l10n.menuImage, entries: entries);
  }

  static MenuDefinition? _layerMenu(
    MenuActionHandler handler,
    AppLocalizations l10n,
  ) {
    final List<MenuEntry> entries = <MenuEntry>[];

    final List<MenuEntry> newEntries = <MenuEntry>[
      if (handler.newLayer != null)
        MenuActionEntry(
          label: l10n.menuNewLayerEllipsis,
          action: handler.newLayer,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyN,
            meta: true,
            shift: true,
          ),
        ),
    ];
    if (newEntries.isNotEmpty) {
      entries.add(
        MenuSubmenuEntry(label: l10n.menuNewSubmenu, entries: newEntries),
      );
    }

    if (handler.mergeLayerDown != null) {
      entries.add(
        MenuActionEntry(
          label: l10n.menuMergeDown,
          action: handler.mergeLayerDown,
          enabledResolver: handler.mergeLayerDownEnabled,
        ),
      );
    }

    if (handler.rasterizeLayer != null) {
      entries.add(
        MenuActionEntry(
          label: l10n.menuRasterize,
          action: handler.rasterizeLayer,
          enabledResolver: handler.rasterizeLayerEnabled,
        ),
      );
    }

    if (handler.layerFreeTransform != null) {
      entries.add(
        MenuActionEntry(
          label: l10n.menuTransform,
          action: handler.layerFreeTransform,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyT, meta: true),
        ),
      );
    }

    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: l10n.menuLayer, entries: entries);
  }

  static MenuDefinition? _selectionMenu(
    MenuActionHandler handler,
    AppLocalizations l10n,
  ) {
    final List<MenuEntry> entries = <MenuEntry>[
      if (handler.selectAll != null)
        MenuActionEntry(
          label: l10n.menuSelectAll,
          action: handler.selectAll,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
          enabledResolver: handler.selectAllEnabled,
        ),
      if (handler.clearSelection != null)
        MenuActionEntry(
          label: l10n.menuDeselect,
          action: handler.clearSelection,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyD, meta: true),
          enabledResolver: handler.clearSelectionEnabled,
        ),
      if (handler.invertSelection != null)
        MenuActionEntry(
          label: l10n.menuInvertSelection,
          action: handler.invertSelection,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyI,
            meta: true,
            shift: true,
          ),
          enabledResolver: handler.invertSelectionEnabled,
        ),
    ];
    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: l10n.menuSelection, entries: entries);
  }

  static MenuDefinition? _toolMenu(
    MenuActionHandler handler,
    AppLocalizations l10n,
  ) {
    final List<MenuEntry> paletteEntries = <MenuEntry>[
      if (handler.generatePalette != null)
        MenuActionEntry(
          label: l10n.menuGeneratePaletteFromCanvasEllipsis,
          action: handler.generatePalette,
        ),
      if (handler.generateGradientPalette != null)
        MenuActionEntry(
          label: l10n.menuGenerateGradientPalette,
          action: handler.generateGradientPalette,
        ),
      if (handler.importPalette != null)
        MenuActionEntry(
          label: l10n.menuImportPaletteEllipsis,
          action: handler.importPalette,
        ),
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
      entries.add(
        MenuSubmenuEntry(label: l10n.menuPalette, entries: paletteEntries),
      );
    }
    final List<MenuEntry> referenceEntries = <MenuEntry>[
      if (handler.createReferenceImage != null)
        MenuActionEntry(
          label: l10n.menuCreateReferenceImage,
          action: handler.createReferenceImage,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyR,
            meta: true,
            shift: true,
          ),
        ),
      if (handler.importReferenceImage != null)
        MenuActionEntry(
          label: l10n.menuImportReferenceImageEllipsis,
          action: handler.importReferenceImage,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyR,
            meta: true,
            alt: true,
          ),
        ),
    ];
    if (referenceEntries.isNotEmpty) {
      entries.add(
        MenuSubmenuEntry(
          label: l10n.menuReferenceImage,
          entries: referenceEntries,
        ),
      );
    }
    final List<MenuEntry> referenceModelEntries = <MenuEntry>[
      if (handler.showSteveReferenceModel != null)
        MenuActionEntry(
          label: l10n.menuReferenceModelSteve,
          action: handler.showSteveReferenceModel,
        ),
      if (handler.showAlexReferenceModel != null)
        MenuActionEntry(
          label: l10n.menuReferenceModelAlex,
          action: handler.showAlexReferenceModel,
        ),
      if (handler.showCubeReferenceModel != null)
        MenuActionEntry(
          label: l10n.menuReferenceModelCube,
          action: handler.showCubeReferenceModel,
        ),
      if (handler.importReferenceModel != null)
        MenuActionEntry(
          label: l10n.menuImportReferenceModelEllipsis,
          action: handler.importReferenceModel,
        ),
    ];
    if (referenceModelEntries.isNotEmpty) {
      entries.add(
        MenuSubmenuEntry(
          label: l10n.menuReferenceModel,
          entries: referenceModelEntries,
        ),
      );
    }
    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: l10n.menuTool, entries: entries);
  }

  static MenuDefinition? _viewMenu(
    MenuActionHandler handler,
    AppLocalizations l10n,
  ) {
    final List<MenuEntry> entries = <MenuEntry>[
      if (handler.zoomIn != null)
        MenuActionEntry(
          label: l10n.menuZoomIn,
          action: handler.zoomIn,
          shortcut: const SingleActivator(LogicalKeyboardKey.equal, meta: true),
        ),
      if (handler.zoomOut != null)
        MenuActionEntry(
          label: l10n.menuZoomOut,
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
          label: handler.pixelGridVisible
              ? l10n.menuHideGrid
              : l10n.menuShowGrid,
          action: handler.togglePixelGrid,
          checked: handler.pixelGridVisible,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyQ),
        ),
      );
    }
    if (handler.toggleViewBlackWhite != null) {
      if (entries.isNotEmpty) {
        entries.add(const MenuSeparatorEntry());
      }
      entries.add(
        MenuActionEntry(
          label: handler.viewBlackWhiteEnabled
              ? l10n.menuDisableBlackWhite
              : l10n.menuBlackWhite,
          action: handler.toggleViewBlackWhite,
          checked: handler.viewBlackWhiteEnabled,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyK),
        ),
      );
    }
    if (handler.toggleViewMirror != null) {
      if (entries.isNotEmpty) {
        entries.add(const MenuSeparatorEntry());
      }
      entries.add(
        MenuActionEntry(
          label: handler.viewMirrorEnabled
              ? l10n.menuDisableMirror
              : l10n.menuMirrorPreview,
          action: handler.toggleViewMirror,
          checked: handler.viewMirrorEnabled,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyF),
        ),
      );
    }
    if (handler.toggleViewTiled != null) {
      if (entries.isNotEmpty) {
        entries.add(const MenuSeparatorEntry());
      }
      entries.add(
        MenuActionEntry(
          label: handler.viewTiledEnabled
              ? l10n.menuDisableTiledPreview
              : l10n.menuTiledPreview,
          action: handler.toggleViewTiled,
          checked: handler.viewTiledEnabled,
        ),
      );
    }
    if (handler.togglePerspectiveGuide != null) {
      if (entries.isNotEmpty) {
        entries.add(const MenuSeparatorEntry());
      }
      entries.add(
        MenuActionEntry(
          label: handler.perspectiveVisible
              ? l10n.menuHidePerspectiveGuide
              : l10n.menuShowPerspectiveGuide,
          action: handler.togglePerspectiveGuide,
          checked: handler.perspectiveVisible,
        ),
      );
      entries.add(
        MenuSubmenuEntry(
          label: l10n.menuPerspectiveMode,
          entries: <MenuEntry>[
            MenuActionEntry(
              label: l10n.menuPerspective1Point,
              action: handler.setPerspectiveOnePoint,
              checked: handler.perspectiveMode == PerspectiveGuideMode.onePoint,
            ),
            MenuActionEntry(
              label: l10n.menuPerspective2Point,
              action: handler.setPerspectiveTwoPoint,
              checked: handler.perspectiveMode == PerspectiveGuideMode.twoPoint,
            ),
            MenuActionEntry(
              label: l10n.menuPerspective3Point,
              action: handler.setPerspectiveThreePoint,
              checked:
                  handler.perspectiveMode == PerspectiveGuideMode.threePoint,
            ),
          ],
        ),
      );
    }
    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: l10n.menuView, entries: entries);
  }

  static MenuDefinition? _workspaceMenu(
    MenuActionHandler handler,
    AppLocalizations l10n,
  ) {
    final MenuWorkspaceLayoutAction? switchLayout =
        handler.switchWorkspaceLayout;
    if (switchLayout == null) {
      return null;
    }
    final WorkspaceLayoutPreference? current =
        handler.workspaceLayoutPreference;
    final List<MenuEntry> entries = <MenuEntry>[
      MenuActionEntry(
        label: l10n.menuWorkspaceDefault,
        action: () => switchLayout(WorkspaceLayoutPreference.floating),
        checked: current == WorkspaceLayoutPreference.floating,
      ),
      MenuActionEntry(
        label: l10n.menuWorkspaceSai2,
        action: () => switchLayout(WorkspaceLayoutPreference.sai2),
        checked: current == WorkspaceLayoutPreference.sai2,
      ),
      MenuActionEntry(
        label: l10n.menuWorkspaceCsp,
        action: () => switchLayout(WorkspaceLayoutPreference.csp),
        checked: current == WorkspaceLayoutPreference.csp,
      ),
    ];
    return MenuDefinition(
      label: l10n.menuWorkspace,
      entries: <MenuEntry>[
        MenuSubmenuEntry(label: l10n.menuSwitchWorkspace, entries: entries),
        if (handler.resetWorkspaceLayout != null) ...[
          const MenuSeparatorEntry(),
          MenuActionEntry(
            label: l10n.menuResetWorkspace,
            action: handler.resetWorkspaceLayout,
          ),
        ],
      ],
    );
  }

  static MenuDefinition? _filterMenu(
    MenuActionHandler handler,
    AppLocalizations l10n,
  ) {
    final List<MenuEntry> entries = <MenuEntry>[
      if (handler.showLayerAntialiasPanel != null)
        MenuActionEntry(
          label: l10n.menuEdgeSofteningEllipsis,
          action: handler.showLayerAntialiasPanel,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyA,
            meta: true,
            alt: true,
          ),
        ),
      if (handler.narrowLines != null)
        MenuActionEntry(
          label: l10n.menuNarrowLinesEllipsis,
          action: handler.narrowLines,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyN,
            meta: true,
            alt: true,
          ),
        ),
      if (handler.expandFill != null)
        MenuActionEntry(
          label: l10n.menuExpandFillEllipsis,
          action: handler.expandFill,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyE,
            meta: true,
            alt: true,
          ),
        ),
      if (handler.gaussianBlur != null)
        MenuActionEntry(
          label: l10n.menuGaussianBlurEllipsis,
          action: handler.gaussianBlur,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyG,
            meta: true,
            alt: true,
          ),
        ),
      if (handler.removeColorLeak != null)
        MenuActionEntry(
          label: l10n.menuRemoveColorLeakEllipsis,
          action: handler.removeColorLeak,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyL,
            meta: true,
            alt: true,
          ),
        ),
      if (handler.adjustHueSaturation != null)
        MenuActionEntry(
          label: l10n.menuHueSaturationEllipsis,
          action: handler.adjustHueSaturation,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyU, meta: true),
        ),
      if (handler.adjustBrightnessContrast != null)
        MenuActionEntry(
          label: l10n.menuBrightnessContrastEllipsis,
          action: handler.adjustBrightnessContrast,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyM, meta: true),
        ),
      if (handler.colorRange != null)
        MenuActionEntry(
          label: l10n.menuColorRangeEllipsis,
          action: handler.colorRange,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyR,
            meta: true,
            alt: true,
            shift: true,
          ),
        ),
      if (handler.adjustBlackWhite != null)
        MenuActionEntry(
          label: l10n.menuBlackWhiteEllipsis,
          action: handler.adjustBlackWhite,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyK,
            meta: true,
            alt: true,
          ),
        ),
      if (handler.binarizeLayer != null)
        MenuActionEntry(
          label: l10n.menuBinarizeEllipsis,
          action: handler.binarizeLayer,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyB,
            meta: true,
            alt: true,
          ),
        ),
      if (handler.scanPaperDrawing != null)
        MenuActionEntry(
          label: l10n.menuScanPaperDrawingEllipsis,
          action: handler.scanPaperDrawing,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyP,
            meta: true,
            alt: true,
          ),
        ),
      if (handler.invertColors != null)
        MenuActionEntry(
          label: l10n.menuInvertColors,
          action: handler.invertColors,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyI,
            meta: true,
            alt: true,
            shift: true,
          ),
        ),
    ];
    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: l10n.menuFilter, entries: entries);
  }

  static MenuDefinition _windowMenu(AppLocalizations l10n) {
    return MenuDefinition(
      label: l10n.menuWindow,
      entries: const <MenuEntry>[
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
