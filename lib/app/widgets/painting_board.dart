import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/animation.dart' show AnimationController;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    as material
    show ReorderableDragStartListener, ReorderableListView;
import 'package:flutter/services.dart'
    show
        FilteringTextInputFormatter,
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyEventResult,
        KeyRepeatEvent,
        KeyUpEvent,
        LogicalKeyboardKey,
        LogicalKeySet,
        TextInputFormatter,
        TextInputType,
        TextEditingValue,
        TextSelection;
import 'package:flutter/rendering.dart' show RenderBox, RenderProxyBox;
import 'package:flutter/scheduler.dart'
    show SingleTickerProviderStateMixin, TickerProvider;
import 'package:flutter/widgets.dart'
    show
        FocusNode,
        TextEditingController,
        WidgetsBinding,
        SingleChildRenderObjectWidget;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalMaterialLocalizations;

import '../../bitmap_canvas/bitmap_canvas.dart';
import '../../bitmap_canvas/controller.dart';
import '../../bitmap_canvas/stroke_pressure_profile.dart'
    show StrokePressureProfile;
import '../../canvas/blend_mode_utils.dart';
import '../../canvas/canvas_layer.dart';
import '../../canvas/canvas_settings.dart';
import '../../canvas/canvas_tools.dart';
import '../../canvas/canvas_viewport.dart';
import 'canvas_toolbar.dart';
import 'tool_cursor_overlay.dart';
import '../shortcuts/toolbar_shortcuts.dart';
import '../preferences/app_preferences.dart';
import '../utils/tablet_input_bridge.dart';
import 'layer_visibility_button.dart';

part 'painting_board_layers.dart';
part 'painting_board_colors.dart';
part 'painting_board_marching_ants.dart';
part 'painting_board_selection.dart';
part 'painting_board_shapes.dart';
part 'painting_board_clipboard.dart';
part 'painting_board_interactions.dart';
part 'painting_board_build.dart';
part 'painting_board_widgets.dart';

const double _toolButtonPadding = 16;
const double _toolbarButtonSize = CanvasToolbar.buttonSize;
const double _toolbarSpacing = CanvasToolbar.spacing;
const double _toolSettingsSpacing = 12;
const double _zoomStep = 1.1;
const double _defaultPenStrokeWidth = 3;
const double _sidePanelWidth = 240;
const double _sidePanelSpacing = 12;
const double _colorIndicatorSize = 56;
const double _colorIndicatorBorder = 3;
const int _recentColorCapacity = 5;
const double _initialViewportScaleFactor = 0.8;

enum CanvasRotation {
  clockwise90,
  counterClockwise90,
  clockwise180,
  counterClockwise180,
}

class CanvasRotationResult {
  const CanvasRotationResult({
    required this.layers,
    required this.width,
    required this.height,
  });

  final List<CanvasLayerData> layers;
  final int width;
  final int height;
}

class PaintingBoard extends StatefulWidget {
  const PaintingBoard({
    super.key,
    required this.settings,
    required this.onRequestExit,
    this.onDirtyChanged,
    this.initialLayers,
  });

  final CanvasSettings settings;
  final VoidCallback onRequestExit;
  final ValueChanged<bool>? onDirtyChanged;
  final List<CanvasLayerData>? initialLayers;

  @override
  State<PaintingBoard> createState() => PaintingBoardState();
}

abstract class _PaintingBoardBase extends State<PaintingBoard> {
  late BitmapCanvasController _controller;
  final FocusNode _focusNode = FocusNode();

  CanvasTool _activeTool = CanvasTool.pen;
  bool _isDrawing = false;
  bool _isDraggingBoard = false;
  bool _isDirty = false;
  bool _isScalingGesture = false;
  double _scaleGestureInitialScale = 1.0;
  double _penStrokeWidth = _defaultPenStrokeWidth;
  bool _simulatePenPressure = false;
  int _penAntialiasLevel = 0;
  bool _stylusPressureEnabled = AppPreferences.defaultStylusPressureEnabled;
  double _stylusMinFactor = AppPreferences.defaultStylusMinFactor;
  double _stylusMaxFactor = AppPreferences.defaultStylusMaxFactor;
  double _stylusCurve = AppPreferences.defaultStylusCurve;
  bool _bucketSampleAllLayers = false;
  bool _bucketContiguous = true;
  bool _layerOpacityGestureActive = false;
  String? _layerOpacityGestureLayerId;
  bool _spacePanOverrideActive = false;
  bool _isLayerDragging = false;
  Offset? _layerDragStart;
  int _layerDragAppliedDx = 0;
  int _layerDragAppliedDy = 0;
  Offset? _curveAnchor;
  Offset? _curvePendingEnd;
  Offset? _curveDragOrigin;
  Offset _curveDragDelta = Offset.zero;
  bool _isCurvePlacingSegment = false;
  Path? _curvePreviewPath;
  bool _isEyedropperSampling = false;
  bool _eyedropperOverrideActive = false;
  Offset? _lastEyedropperSample;
  Offset? _toolCursorPosition;
  Offset? _lastWorkspacePointer;
  Offset? _penCursorWorkspacePosition;
  Duration? _lastPenSampleTimestamp;
  bool _activeStrokeUsesStylus = false;
  double? _activeStylusPressureMin;
  double? _activeStylusPressureMax;
  Size _toolSettingsCardSize = const Size(320, _toolbarButtonSize);
  CanvasToolbarLayout _toolbarLayout = const CanvasToolbarLayout(
    columns: 1,
    rows: CanvasToolbar.buttonCount,
    width: CanvasToolbar.buttonSize,
    height:
        CanvasToolbar.buttonSize * CanvasToolbar.buttonCount +
        CanvasToolbar.spacing * (CanvasToolbar.buttonCount - 1),
  );

  final CanvasViewport _viewport = CanvasViewport();
  bool _viewportInitialized = false;
  Size _workspaceSize = Size.zero;
  Offset _layoutBaseOffset = Offset.zero;
  bool _workspaceMeasurementScheduled = false;
  final ScrollController _layerScrollController = ScrollController();
  Color _primaryColor = const Color(0xFF000000);
  late HSVColor _primaryHsv;
  final List<Color> _recentColors = <Color>[];
  final List<_CanvasHistoryEntry> _undoStack = <_CanvasHistoryEntry>[];
  final List<_CanvasHistoryEntry> _redoStack = <_CanvasHistoryEntry>[];
  bool _historyLocked = false;
  int _historyLimit = AppPreferences.instance.historyLimit;

  Size get _canvasSize => widget.settings.size;

  Size get _scaledBoardSize => Size(
    _canvasSize.width * _viewport.scale,
    _canvasSize.height * _viewport.scale,
  );

  bool _isWithinCanvasBounds(Offset position) {
    final Size size = _canvasSize;
    return position.dx >= 0 &&
        position.dy >= 0 &&
        position.dx <= size.width &&
        position.dy <= size.height;
  }

  void _applyStylusSettingsToController() {
    _controller.configureStylusPressure(
      enabled: _stylusPressureEnabled,
      minFactor: _stylusMinFactor,
      maxFactor: _stylusMaxFactor,
      curve: _stylusCurve,
    );
  }

  void _refreshStylusPreferencesIfNeeded() {
    final AppPreferences prefs = AppPreferences.instance;
    const double epsilon = 0.0001;
    final bool needsUpdate =
        _stylusPressureEnabled != prefs.stylusPressureEnabled ||
        (_stylusMinFactor - prefs.stylusPressureMinFactor).abs() > epsilon ||
        (_stylusMaxFactor - prefs.stylusPressureMaxFactor).abs() > epsilon ||
        (_stylusCurve - prefs.stylusPressureCurve).abs() > epsilon;
    if (!needsUpdate) {
      return;
    }
    _stylusPressureEnabled = prefs.stylusPressureEnabled;
    _stylusMinFactor = prefs.stylusPressureMinFactor;
    _stylusMaxFactor = prefs.stylusPressureMaxFactor;
    _stylusCurve = prefs.stylusPressureCurve;
    if (mounted) {
      _applyStylusSettingsToController();
    }
  }

  Offset _baseOffsetForScale(double scale) {
    final Size workspace = _workspaceSize;
    if (workspace.width <= 0 ||
        workspace.height <= 0 ||
        !workspace.width.isFinite ||
        !workspace.height.isFinite) {
      return Offset.zero;
    }

    final double scaledWidth = _canvasSize.width * scale;
    final double scaledHeight = _canvasSize.height * scale;

    final double rawLeft = (workspace.width - scaledWidth) / 2;
    final double rawTop = (workspace.height - scaledHeight) / 2;

    final double left = rawLeft.isFinite ? rawLeft : 0.0;
    final double top = rawTop.isFinite ? rawTop : 0.0;

    return Offset(left, top);
  }

  void _updateToolSettingsCardSize(Size size) {
    final double width = size.width.isFinite && size.width > 0
        ? size.width
        : _toolSettingsCardSize.width;
    final double height = size.height.isFinite && size.height > 0
        ? size.height
        : _toolSettingsCardSize.height;
    if ((width - _toolSettingsCardSize.width).abs() < 0.5 &&
        (height - _toolSettingsCardSize.height).abs() < 0.5) {
      return;
    }
    _toolSettingsCardSize = Size(width, height);
  }

  void _scheduleWorkspaceMeasurement(BuildContext context) {
    if (_workspaceMeasurementScheduled) {
      return;
    }
    _workspaceMeasurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _workspaceMeasurementScheduled = false;
      if (!mounted) {
        return;
      }
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        return;
      }
      final Size size = box.size;
      if (size.width <= 0 ||
          size.height <= 0 ||
          !size.width.isFinite ||
          !size.height.isFinite) {
        return;
      }
      final bool widthChanged = (size.width - _workspaceSize.width).abs() > 0.5;
      final bool heightChanged =
          (size.height - _workspaceSize.height).abs() > 0.5;
      if (!widthChanged && !heightChanged) {
        return;
      }
      setState(() {
        _workspaceSize = size;
        if (!_viewportInitialized) {
          // 仍需初始化视口，下一帧会根据新尺寸完成初始化
        }
      });
    });
  }

  Rect get _boardRect {
    final Offset position = _layoutBaseOffset + _viewport.offset;
    final Size size = _scaledBoardSize;
    return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  }

  Offset _toBoardLocal(Offset workspacePosition) {
    final Rect boardRect = _boardRect;
    return (workspacePosition - boardRect.topLeft) / _viewport.scale;
  }

  CanvasTool get activeTool => _activeTool;
  CanvasTool get _effectiveActiveTool {
    if (_eyedropperOverrideActive) {
      return CanvasTool.eyedropper;
    }
    if (_spacePanOverrideActive) {
      return CanvasTool.hand;
    }
    return _activeTool;
  }

  bool get _cursorRequiresOverlay =>
      ToolCursorStyles.hasOverlay(_effectiveActiveTool);

  bool get _penRequiresOverlay =>
      _effectiveActiveTool == CanvasTool.pen ||
      _effectiveActiveTool == CanvasTool.curvePen ||
      _effectiveActiveTool == CanvasTool.shape;

  bool get hasContent => _controller.hasVisibleContent;
  bool get isDirty => _isDirty;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  SelectionShape get selectionShape;
  ShapeToolVariant get shapeToolVariant;
  Path? get selectionPath;
  Path? get selectionPreviewPath;
  Path? get shapePreviewPath;
  Path? get magicWandPreviewPath;
  double get selectionDashPhase;
  bool isPointInsideSelection(Offset position);

  Uint8List? get selectionMaskSnapshot;
  Path? get selectionPathSnapshot;

  void setSelectionState({SelectionShape? shape, Path? path, Uint8List? mask});

  void clearSelectionArtifacts();
  void resetSelectionUndoFlag();

  UnmodifiableListView<BitmapLayerState> get _layers => _controller.layers;
  String? get _activeLayerId => _controller.activeLayerId;
  Color get _backgroundPreviewColor;

  List<CanvasLayerData> _buildInitialLayers();

  Future<void> _pickColor({
    required String title,
    required Color initialColor,
    required ValueChanged<Color> onSelected,
    VoidCallback? onCleared,
  });

  void _rememberColor(Color color);
  void _setPrimaryColor(Color color, {bool remember = true});
  Future<void> _applyPaintBucket(Offset position);

  void _setActiveTool(CanvasTool tool);
  void _convertMagicWandPreviewToSelection();
  void _clearMagicWandPreview();
  void _resetSelectionPreview();
  void _resetPolygonState();
  void _handleMagicWandPointerDown(Offset position);
  void _handleSelectionPointerDown(Offset position, Duration timestamp);
  void _handleSelectionPointerMove(Offset position);
  void _handleSelectionPointerUp();
  void _handleSelectionPointerCancel();
  void _handleSelectionHover(Offset position);
  void _clearSelectionHover();
  void _clearSelection();
  void _updateSelectionShape(SelectionShape shape);
  void _updateShapeToolVariant(ShapeToolVariant variant);
  void initializeSelectionTicker(TickerProvider provider);
  void disposeSelectionTicker();
  void _updateSelectionAnimation();

  void _handlePointerDown(PointerDownEvent event);
  void _handlePointerMove(PointerMoveEvent event);
  void _handlePointerUp(PointerUpEvent event);
  void _handlePointerCancel(PointerCancelEvent event);
  void _handlePointerHover(PointerHoverEvent event);
  void _handleWorkspacePointerExit();
  void _handlePointerSignal(PointerSignalEvent event);
  KeyEventResult _handleWorkspaceKeyEvent(FocusNode node, KeyEvent event);

  void _updatePenPressureSimulation(bool value);
  void _updatePenPressureProfile(StrokePressureProfile profile);
  void _updatePenAntialiasLevel(int value);

  void _handleScaleStart(ScaleStartDetails details);
  void _handleScaleUpdate(ScaleUpdateDetails details);
  void _handleScaleEnd(ScaleEndDetails details);

  void _handleUndo();
  void _handleRedo();
  bool cut();
  bool copy();
  bool paste();

  void _updatePenStrokeWidth(double value);
  void _updateBucketSampleAllLayers(bool value);
  void _updateBucketContiguous(bool value);

  void _handleAddLayer();
  void _handleRemoveLayer(String id);

  Widget _buildLayerPanelContent(FluentThemeData theme);
  Widget _buildColorPanelContent(FluentThemeData theme);
  Widget? _buildColorPanelTrailing(FluentThemeData theme);
  Widget _buildColorIndicator(FluentThemeData theme);

  List<CanvasLayerData> snapshotLayers() => _controller.snapshotLayers();

  CanvasRotationResult? rotateCanvas(CanvasRotation rotation) {
    final int width = _controller.width;
    final int height = _controller.height;
    if (width <= 0 || height <= 0) {
      return null;
    }
    _controller.commitActiveLayerTranslation();
    final List<CanvasLayerData> original = snapshotLayers();
    if (original.isEmpty) {
      return CanvasRotationResult(
        layers: const <CanvasLayerData>[],
        width: width,
        height: height,
      );
    }
    final List<CanvasLayerData> rotated = <CanvasLayerData>[
      for (final CanvasLayerData layer in original)
        _rotateLayerData(layer, rotation),
    ];
    setSelectionState(path: null, mask: null);
    clearSelectionArtifacts();
    resetSelectionUndoFlag();
    final bool swaps = _rotationSwapsDimensions(rotation);
    if (!swaps) {
      _controller.loadLayers(rotated, _controller.backgroundColor);
      _resetHistory();
      setState(() {});
    }
    return CanvasRotationResult(
      layers: rotated,
      width: swaps ? height : width,
      height: swaps ? width : height,
    );
  }

  void markSaved() {
    if (!_isDirty) {
      return;
    }
    _isDirty = false;
    widget.onDirtyChanged?.call(false);
  }

  CanvasLayerData _rotateLayerData(
    CanvasLayerData layer,
    CanvasRotation rotation,
  ) {
    final Uint8List? bitmap = layer.bitmap;
    final int? bitmapWidth = layer.bitmapWidth;
    final int? bitmapHeight = layer.bitmapHeight;
    if (bitmap != null && bitmapWidth != null && bitmapHeight != null) {
      final bool swaps = _rotationSwapsDimensions(rotation);
      final int targetWidth = swaps ? bitmapHeight : bitmapWidth;
      final int targetHeight = swaps ? bitmapWidth : bitmapHeight;
      final Uint8List rotated = _rotateBitmapRgba(
        bitmap,
        bitmapWidth,
        bitmapHeight,
        rotation,
      );
      return CanvasLayerData(
        id: layer.id,
        name: layer.name,
        visible: layer.visible,
        opacity: layer.opacity,
        locked: layer.locked,
        clippingMask: layer.clippingMask,
        blendMode: layer.blendMode,
        bitmap: rotated,
        bitmapWidth: targetWidth,
        bitmapHeight: targetHeight,
        fillColor: layer.fillColor,
      );
    }

    return CanvasLayerData(
      id: layer.id,
      name: layer.name,
      visible: layer.visible,
      opacity: layer.opacity,
      locked: layer.locked,
      clippingMask: layer.clippingMask,
      blendMode: layer.blendMode,
      fillColor: layer.fillColor,
    );
  }

  static bool _rotationSwapsDimensions(CanvasRotation rotation) {
    return rotation == CanvasRotation.clockwise90 ||
        rotation == CanvasRotation.counterClockwise90;
  }

  static Uint8List _rotateBitmapRgba(
    Uint8List source,
    int width,
    int height,
    CanvasRotation rotation,
  ) {
    if (source.length != width * height * 4) {
      return Uint8List.fromList(source);
    }
    final bool swaps = _rotationSwapsDimensions(rotation);
    final int targetWidth = swaps ? height : width;
    final int targetHeight = swaps ? width : height;
    final Uint8List output = Uint8List(targetWidth * targetHeight * 4);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int srcIndex = (y * width + x) * 4;
        late int destX;
        late int destY;
        switch (rotation) {
          case CanvasRotation.clockwise90:
            destX = height - 1 - y;
            destY = x;
            break;
          case CanvasRotation.counterClockwise90:
            destX = y;
            destY = width - 1 - x;
            break;
          case CanvasRotation.clockwise180:
          case CanvasRotation.counterClockwise180:
            destX = width - 1 - x;
            destY = height - 1 - y;
            break;
        }
        final int destIndex = (destY * targetWidth + destX) * 4;
        output[destIndex] = source[srcIndex];
        output[destIndex + 1] = source[srcIndex + 1];
        output[destIndex + 2] = source[srcIndex + 2];
        output[destIndex + 3] = source[srcIndex + 3];
      }
    }
    return output;
  }

  void _markDirty() {
    if (_isDirty) {
      return;
    }
    _isDirty = true;
    widget.onDirtyChanged?.call(true);
  }

  void _emitClean() {
    if (!_isDirty) {
      return;
    }
    _isDirty = false;
    widget.onDirtyChanged?.call(false);
  }

  void _resetHistory() {
    _undoStack.clear();
    _redoStack.clear();
    _historyLocked = false;
    _historyLimit = AppPreferences.instance.historyLimit;
  }

  void _pushUndoSnapshot() {
    _refreshHistoryLimit();
    if (_historyLocked) {
      return;
    }
    final _CanvasHistoryEntry entry = _createHistoryEntry();
    _undoStack.add(entry);
    _trimHistoryStacks();
    _redoStack.clear();
  }

  _CanvasHistoryEntry _createHistoryEntry() {
    return _CanvasHistoryEntry(
      layers: _controller.snapshotLayers(),
      backgroundColor: _controller.backgroundColor,
      activeLayerId: _controller.activeLayerId,
      selectionShape: selectionShape,
      selectionMask: selectionMaskSnapshot != null
          ? Uint8List.fromList(selectionMaskSnapshot!)
          : null,
      selectionPath: selectionPathSnapshot != null
          ? (Path()..addPath(selectionPathSnapshot!, Offset.zero))
          : null,
    );
  }

  void _applyHistoryEntry(_CanvasHistoryEntry entry) {
    _historyLocked = true;
    try {
      _controller.loadLayers(entry.layers, entry.backgroundColor);
      final String? activeId = entry.activeLayerId;
      if (activeId != null) {
        _controller.setActiveLayer(activeId);
      }
      setSelectionState(
        shape: entry.selectionShape,
        path: entry.selectionPath != null
            ? (Path()..addPath(entry.selectionPath!, Offset.zero))
            : null,
        mask: entry.selectionMask != null
            ? Uint8List.fromList(entry.selectionMask!)
            : null,
      );
      clearSelectionArtifacts();
    } finally {
      _historyLocked = false;
    }
    setState(() {});
    _focusNode.requestFocus();
    _markDirty();
    resetSelectionUndoFlag();
    _updateSelectionAnimation();
  }

  void _refreshHistoryLimit() {
    final int nextLimit = AppPreferences.instance.historyLimit;
    if (_historyLimit == nextLimit) {
      return;
    }
    _historyLimit = nextLimit;
    _trimHistoryStacks();
  }

  void _trimHistoryStacks() {
    while (_undoStack.length > _historyLimit) {
      _undoStack.removeAt(0);
    }
    while (_redoStack.length > _historyLimit) {
      _redoStack.removeAt(0);
    }
  }

  void _initializeViewportIfNeeded() {
    if (_viewportInitialized) {
      return;
    }

    final Size workspaceSize = _workspaceSize;
    if (workspaceSize.width <= 0 ||
        workspaceSize.height <= 0 ||
        !workspaceSize.width.isFinite ||
        !workspaceSize.height.isFinite) {
      return;
    }

    final Size canvasSize = _canvasSize;
    if (canvasSize.width <= 0 ||
        canvasSize.height <= 0 ||
        !canvasSize.width.isFinite ||
        !canvasSize.height.isFinite) {
      _viewportInitialized = true;
      return;
    }

    final double widthScale = workspaceSize.width / canvasSize.width;
    final double heightScale = workspaceSize.height / canvasSize.height;
    final double baseScale = widthScale < heightScale
        ? widthScale
        : heightScale;

    double targetScale = baseScale * _initialViewportScaleFactor;
    if (!targetScale.isFinite || targetScale <= 0) {
      targetScale = baseScale.isFinite && baseScale > 0 ? baseScale : 1.0;
    }

    if (targetScale > baseScale && baseScale.isFinite && baseScale > 0) {
      targetScale = baseScale;
    }

    _viewport.setScale(targetScale);
    _viewport.setOffset(Offset.zero);
    _viewportInitialized = true;
  }
}

class PaintingBoardState extends _PaintingBoardBase
    with
        SingleTickerProviderStateMixin,
        _PaintingBoardLayerMixin,
        _PaintingBoardColorMixin,
        _PaintingBoardSelectionMixin,
        _PaintingBoardShapeMixin,
        _PaintingBoardClipboardMixin,
        _PaintingBoardInteractionMixin,
        _PaintingBoardBuildMixin {
  @override
  void initState() {
    super.initState();
    initializeSelectionTicker(this);
    final AppPreferences prefs = AppPreferences.instance;
    _bucketSampleAllLayers = prefs.bucketSampleAllLayers;
    _bucketContiguous = prefs.bucketContiguous;
    _penStrokeWidth = prefs.penStrokeWidth.clamp(
      _ToolSettingsCard._minPenStrokeWidth,
      _ToolSettingsCard._maxPenStrokeWidth,
    );
    _simulatePenPressure = prefs.simulatePenPressure;
    _penPressureProfile = prefs.penPressureProfile;
    _penAntialiasLevel = prefs.penAntialiasLevel.clamp(0, 3);
    _stylusPressureEnabled = prefs.stylusPressureEnabled;
    _stylusMinFactor = prefs.stylusPressureMinFactor;
    _stylusMaxFactor = prefs.stylusPressureMaxFactor;
    _stylusCurve = prefs.stylusPressureCurve;
    _primaryHsv = HSVColor.fromColor(_primaryColor);
    _rememberColor(widget.settings.backgroundColor);
    _rememberColor(_primaryColor);
    final List<CanvasLayerData> layers = _buildInitialLayers();
    _controller = BitmapCanvasController(
      width: widget.settings.width.round(),
      height: widget.settings.height.round(),
      backgroundColor: widget.settings.backgroundColor,
      initialLayers: layers,
    );
    _applyStylusSettingsToController();
    _controller.addListener(_handleControllerChanged);
    _resetHistory();
  }

  @override
  void dispose() {
    disposeSelectionTicker();
    _controller.removeListener(_handleControllerChanged);
    unawaited(_controller.disposeController());
    _layerScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PaintingBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool sizeChanged = widget.settings.size != oldWidget.settings.size;
    final bool backgroundChanged =
        widget.settings.backgroundColor != oldWidget.settings.backgroundColor;
    if (sizeChanged || backgroundChanged) {
      _controller.removeListener(_handleControllerChanged);
      unawaited(_controller.disposeController());
      _controller = BitmapCanvasController(
        width: widget.settings.width.round(),
        height: widget.settings.height.round(),
        backgroundColor: widget.settings.backgroundColor,
        initialLayers: _buildInitialLayers(),
      );
      _applyStylusSettingsToController();
      _controller.addListener(_handleControllerChanged);
      _resetHistory();
      setState(() {
        if (sizeChanged) {
          _viewport.reset();
          _workspaceSize = Size.zero;
          _layoutBaseOffset = Offset.zero;
          _viewportInitialized = false;
        }
      });
    }
  }

  void _handleControllerChanged() {
    setState(() {});
  }
}

class _CanvasHistoryEntry {
  const _CanvasHistoryEntry({
    required this.layers,
    required this.backgroundColor,
    required this.activeLayerId,
    required this.selectionShape,
    this.selectionMask,
    this.selectionPath,
  });

  final List<CanvasLayerData> layers;
  final Color backgroundColor;
  final String? activeLayerId;
  final SelectionShape selectionShape;
  final Uint8List? selectionMask;
  final Path? selectionPath;
}

StrokePressureProfile _penPressureProfile = StrokePressureProfile.auto;
