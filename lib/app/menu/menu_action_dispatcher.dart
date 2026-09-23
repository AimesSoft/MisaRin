import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import '../models/workspace_layout.dart';
import '../../canvas/perspective_guide.dart';

typedef MenuAsyncAction = FutureOr<void> Function();
typedef MenuPaletteAction = FutureOr<void> Function(String paletteId);
typedef MenuWorkspaceLayoutAction =
    FutureOr<void> Function(WorkspaceLayoutPreference preference);
typedef MenuActionEnabledResolver = bool Function();

class MenuPaletteMenuEntry {
  const MenuPaletteMenuEntry({required this.id, required this.label});

  final String id;
  final String label;
}

class MenuActionHandler {
  const MenuActionHandler({
    this.newProject,
    this.open,
    this.closeAll,
    this.importImage,
    this.importImageFromClipboard,
    this.preferences,
    this.about,
    this.save,
    this.saveAs,
    this.export,
    this.undo,
    this.undoEnabled,
    this.redo,
    this.redoEnabled,
    this.zoomIn,
    this.zoomOut,
    this.rotateCanvas90Clockwise,
    this.rotateCanvas90CounterClockwise,
    this.rotateCanvas180Clockwise,
    this.rotateCanvas180CounterClockwise,
    this.flipCanvasHorizontal,
    this.flipCanvasVertical,
    this.cut,
    this.cutEnabled,
    this.copy,
    this.copyEnabled,
    this.paste,
    this.pasteEnabled,
    this.newLayer,
    this.generateArtText,
    this.generatePalette,
    this.generateGradientPalette,
    this.importPalette,
    this.selectPaletteFromMenu,
    this.paletteMenuEntries = const <MenuPaletteMenuEntry>[],
    this.resizeImage,
    this.resizeCanvas,
    this.mergeLayerDown,
    this.mergeLayerDownEnabled,
    this.rasterizeLayer,
    this.rasterizeLayerEnabled,
    this.binarizeLayer,
    this.layerFreeTransform,
    this.adjustHueSaturation,
    this.adjustBrightnessContrast,
    this.adjustBlackWhite,
    this.invertColors,
    this.scanPaperDrawing,
    this.colorRange,
    this.narrowLines,
    this.expandFill,
    this.selectAll,
    this.selectAllEnabled,
    this.clearSelection,
    this.clearSelectionEnabled,
    this.invertSelection,
    this.invertSelectionEnabled,
    this.showLayerAntialiasPanel,
    this.gaussianBlur,
    this.removeColorLeak,
    this.createReferenceImage,
    this.importReferenceImage,
    this.showSteveReferenceModel,
    this.showAlexReferenceModel,
    this.showCubeReferenceModel,
    this.importReferenceModel,
    this.workspaceLayoutPreference,
    this.switchWorkspaceLayout,
    this.resetWorkspaceLayout,
    this.togglePixelGrid,
    this.pixelGridVisible = false,
    this.toggleViewBlackWhite,
    this.viewBlackWhiteEnabled = false,
    this.toggleViewMirror,
    this.viewMirrorEnabled = false,
    this.toggleViewTiled,
    this.viewTiledEnabled = false,
    this.togglePerspectiveGuide,
    this.setPerspectiveOnePoint,
    this.setPerspectiveTwoPoint,
    this.setPerspectiveThreePoint,
    this.perspectiveMode = PerspectiveGuideMode.off,
    this.perspectiveVisible = false,
  });

  const MenuActionHandler.empty()
    : newProject = null,
      open = null,
      closeAll = null,
      importImage = null,
      importImageFromClipboard = null,
      preferences = null,
      about = null,
      save = null,
      saveAs = null,
      export = null,
      undo = null,
      undoEnabled = null,
      redo = null,
      redoEnabled = null,
      zoomIn = null,
      zoomOut = null,
      rotateCanvas90Clockwise = null,
      rotateCanvas90CounterClockwise = null,
      rotateCanvas180Clockwise = null,
      rotateCanvas180CounterClockwise = null,
      flipCanvasHorizontal = null,
      flipCanvasVertical = null,
      cut = null,
      cutEnabled = null,
      copy = null,
      copyEnabled = null,
      paste = null,
      pasteEnabled = null,
      newLayer = null,
      generateArtText = null,
      generatePalette = null,
      generateGradientPalette = null,
      importPalette = null,
      selectPaletteFromMenu = null,
      resizeImage = null,
      resizeCanvas = null,
      mergeLayerDown = null,
      mergeLayerDownEnabled = null,
      rasterizeLayer = null,
      rasterizeLayerEnabled = null,
      binarizeLayer = null,
      layerFreeTransform = null,
      adjustHueSaturation = null,
      adjustBrightnessContrast = null,
      adjustBlackWhite = null,
      invertColors = null,
      scanPaperDrawing = null,
      colorRange = null,
      narrowLines = null,
      expandFill = null,
      selectAll = null,
      selectAllEnabled = null,
      clearSelection = null,
      clearSelectionEnabled = null,
      invertSelection = null,
      invertSelectionEnabled = null,
      showLayerAntialiasPanel = null,
      gaussianBlur = null,
      removeColorLeak = null,
      createReferenceImage = null,
      importReferenceImage = null,
      showSteveReferenceModel = null,
      showAlexReferenceModel = null,
      showCubeReferenceModel = null,
      importReferenceModel = null,
      paletteMenuEntries = const <MenuPaletteMenuEntry>[],
      workspaceLayoutPreference = null,
      switchWorkspaceLayout = null,
      resetWorkspaceLayout = null,
      togglePixelGrid = null,
      pixelGridVisible = false,
      toggleViewBlackWhite = null,
      viewBlackWhiteEnabled = false,
      toggleViewMirror = null,
      viewMirrorEnabled = false,
      toggleViewTiled = null,
      viewTiledEnabled = false,
      togglePerspectiveGuide = null,
      setPerspectiveOnePoint = null,
      setPerspectiveTwoPoint = null,
      setPerspectiveThreePoint = null,
      perspectiveMode = PerspectiveGuideMode.off,
      perspectiveVisible = false;

  final MenuAsyncAction? newProject;
  final MenuAsyncAction? open;
  final MenuAsyncAction? closeAll;
  final MenuAsyncAction? importImage;
  final MenuAsyncAction? importImageFromClipboard;
  final MenuAsyncAction? preferences;
  final MenuAsyncAction? about;
  final MenuAsyncAction? save;
  final MenuAsyncAction? saveAs;
  final MenuAsyncAction? export;
  final MenuAsyncAction? undo;
  final MenuActionEnabledResolver? undoEnabled;
  final MenuAsyncAction? redo;
  final MenuActionEnabledResolver? redoEnabled;
  final MenuAsyncAction? zoomIn;
  final MenuAsyncAction? zoomOut;
  final MenuAsyncAction? rotateCanvas90Clockwise;
  final MenuAsyncAction? rotateCanvas90CounterClockwise;
  final MenuAsyncAction? rotateCanvas180Clockwise;
  final MenuAsyncAction? rotateCanvas180CounterClockwise;
  final MenuAsyncAction? flipCanvasHorizontal;
  final MenuAsyncAction? flipCanvasVertical;
  final MenuAsyncAction? cut;
  final MenuActionEnabledResolver? cutEnabled;
  final MenuAsyncAction? copy;
  final MenuActionEnabledResolver? copyEnabled;
  final MenuAsyncAction? paste;
  final MenuActionEnabledResolver? pasteEnabled;
  final MenuAsyncAction? newLayer;
  final MenuAsyncAction? generateArtText;
  final MenuAsyncAction? generatePalette;
  final MenuAsyncAction? generateGradientPalette;
  final MenuAsyncAction? importPalette;
  final MenuPaletteAction? selectPaletteFromMenu;
  final List<MenuPaletteMenuEntry> paletteMenuEntries;
  final MenuAsyncAction? resizeImage;
  final MenuAsyncAction? resizeCanvas;
  final MenuAsyncAction? mergeLayerDown;
  final MenuActionEnabledResolver? mergeLayerDownEnabled;
  final MenuAsyncAction? rasterizeLayer;
  final MenuActionEnabledResolver? rasterizeLayerEnabled;
  final MenuAsyncAction? binarizeLayer;
  final MenuAsyncAction? layerFreeTransform;
  final MenuAsyncAction? adjustHueSaturation;
  final MenuAsyncAction? adjustBrightnessContrast;
  final MenuAsyncAction? adjustBlackWhite;
  final MenuAsyncAction? invertColors;
  final MenuAsyncAction? scanPaperDrawing;
  final MenuAsyncAction? colorRange;
  final MenuAsyncAction? narrowLines;
  final MenuAsyncAction? expandFill;
  final MenuAsyncAction? selectAll;
  final MenuActionEnabledResolver? selectAllEnabled;
  final MenuAsyncAction? clearSelection;
  final MenuActionEnabledResolver? clearSelectionEnabled;
  final MenuAsyncAction? invertSelection;
  final MenuActionEnabledResolver? invertSelectionEnabled;
  final MenuAsyncAction? showLayerAntialiasPanel;
  final MenuAsyncAction? gaussianBlur;
  final MenuAsyncAction? removeColorLeak;
  final MenuAsyncAction? createReferenceImage;
  final MenuAsyncAction? importReferenceImage;
  final MenuAsyncAction? showSteveReferenceModel;
  final MenuAsyncAction? showAlexReferenceModel;
  final MenuAsyncAction? showCubeReferenceModel;
  final MenuAsyncAction? importReferenceModel;
  final WorkspaceLayoutPreference? workspaceLayoutPreference;
  final MenuWorkspaceLayoutAction? switchWorkspaceLayout;
  final MenuAsyncAction? resetWorkspaceLayout;
  final MenuAsyncAction? togglePixelGrid;
  final bool pixelGridVisible;
  final MenuAsyncAction? toggleViewBlackWhite;
  final bool viewBlackWhiteEnabled;
  final MenuAsyncAction? toggleViewMirror;
  final bool viewMirrorEnabled;
  final MenuAsyncAction? toggleViewTiled;
  final bool viewTiledEnabled;
  final MenuAsyncAction? togglePerspectiveGuide;
  final MenuAsyncAction? setPerspectiveOnePoint;
  final MenuAsyncAction? setPerspectiveTwoPoint;
  final MenuAsyncAction? setPerspectiveThreePoint;
  final PerspectiveGuideMode perspectiveMode;
  final bool perspectiveVisible;
}

class MenuActionDispatcher extends ChangeNotifier {
  MenuActionDispatcher._();

  static final MenuActionDispatcher instance = MenuActionDispatcher._();

  final LinkedHashMap<Object, MenuActionHandler> _handlers =
      LinkedHashMap<Object, MenuActionHandler>();
  bool _notifyScheduled = false;

  MenuActionHandler get current => _handlers.isEmpty
      ? const MenuActionHandler.empty()
      : _handlers.values.last;

  void register(Object token, MenuActionHandler handler) {
    _handlers[token] = handler;
    _scheduleNotify();
  }

  void unregister(Object token) {
    final removed = _handlers.remove(token);
    if (removed != null) {
      _scheduleNotify();
    }
  }

  void _scheduleNotify() {
    final WidgetsBinding binding = WidgetsBinding.instance;
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    binding.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  void refresh() {
    _scheduleNotify();
  }
}

class MenuActionBinding extends StatefulWidget {
  const MenuActionBinding({
    super.key,
    required this.handler,
    required this.child,
  });

  final MenuActionHandler handler;
  final Widget child;

  @override
  State<MenuActionBinding> createState() => _MenuActionBindingState();
}

class _MenuActionBindingState extends State<MenuActionBinding> {
  final Object _token = Object();

  @override
  void initState() {
    super.initState();
    MenuActionDispatcher.instance.register(_token, widget.handler);
  }

  @override
  void didUpdateWidget(MenuActionBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.handler, widget.handler)) {
      MenuActionDispatcher.instance.register(_token, widget.handler);
    }
  }

  @override
  void dispose() {
    MenuActionDispatcher.instance.unregister(_token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
