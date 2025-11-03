import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    as material
    show ReorderableDragStartListener, ReorderableListView;
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputFormatter, TextInputType,
        TextEditingValue, TextSelection;
import 'package:flutter/widgets.dart' show FocusNode, TextEditingController;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalMaterialLocalizations;

import '../../canvas/bucket_fill_engine.dart';
import '../../canvas/canvas_layer.dart';
import '../../canvas/canvas_viewport.dart';
import '../../canvas/canvas_settings.dart';
import '../../canvas/canvas_tools.dart';
import '../../canvas/stroke_painter.dart';
import '../../canvas/stroke_store.dart';
import 'canvas_toolbar.dart';
import '../shortcuts/toolbar_shortcuts.dart';
import 'layer_visibility_button.dart';

part 'painting_board_layers.dart';
part 'painting_board_colors.dart';
part 'painting_board_interactions.dart';
part 'painting_board_build.dart';
part 'painting_board_widgets.dart';

const double _toolButtonPadding = 16;
const double _toolbarButtonSize = 48;
const double _toolbarSpacing = 9;
const double _toolSettingsSpacing = 12;
const double _toolSettingsCardWidth = 320;
const double _toolSettingsCardHeight = _toolbarButtonSize;
const double _zoomStep = 1.1;
const double _defaultPenStrokeWidth = 3;
const double _sidePanelWidth = 240;
const double _sidePanelSpacing = 12;
const double _colorIndicatorSize = 56;
const double _colorIndicatorBorder = 3;
const int _recentColorCapacity = 5;
const double _initialViewportScaleFactor = 0.8;

class PaintingBoard extends StatefulWidget {
  const PaintingBoard({
    super.key,
    required this.settings,
    required this.onRequestExit,
    this.onDirtyChanged,
    this.initialLayers,
    this.bucketSampleAllLayers = false,
    this.bucketContiguous = true,
  });

  final CanvasSettings settings;
  final VoidCallback onRequestExit;
  final ValueChanged<bool>? onDirtyChanged;
  final List<CanvasLayerData>? initialLayers;
  final bool bucketSampleAllLayers;
  final bool bucketContiguous;

  @override
  State<PaintingBoard> createState() => PaintingBoardState();
}

abstract class _PaintingBoardBase extends State<PaintingBoard> {
  final StrokeStore _store = StrokeStore();
  final FocusNode _focusNode = FocusNode();
  late final StrokePictureCache _strokeCache;

  CanvasTool _activeTool = CanvasTool.pen;
  bool _isDrawing = false;
  bool _isDraggingBoard = false;
  bool _isDirty = false;
  bool _isScalingGesture = false;
  double _scaleGestureInitialScale = 1.0;
  int _currentStrokeVersion = 0;
  double _penStrokeWidth = _defaultPenStrokeWidth;
  bool _bucketSampleAllLayers = false;
  bool _bucketContiguous = true;

  final CanvasViewport _viewport = CanvasViewport();
  bool _viewportInitialized = false;
  Size _workspaceSize = Size.zero;
  Offset _layoutBaseOffset = Offset.zero;
  final ScrollController _layerScrollController = ScrollController();
  Color _primaryColor = const Color(0xFF000000);
  late HSVColor _primaryHsv;
  final List<Color> _recentColors = <Color>[];

  Size get _canvasSize => widget.settings.size;

  Size get _scaledBoardSize => Size(
    _canvasSize.width * _viewport.scale,
    _canvasSize.height * _viewport.scale,
  );

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
  bool get hasContent => _store.hasStrokes;
  bool get isDirty => _isDirty;
  bool get canUndo => _store.canUndo;
  bool get canRedo => _store.canRedo;
  bool get bucketSampleAllLayers => _bucketSampleAllLayers;
  bool get bucketContiguous => _bucketContiguous;

  List<CanvasLayerData> get _layers => _store.layers;
  String? get _activeLayerId => _store.activeLayerId;
  Color get _backgroundPreviewColor;

  List<CanvasLayerData> _buildInitialLayers();

  Future<void> _pickColor({
    required String title,
    required Color initialColor,
    required ValueChanged<Color> onSelected,
    VoidCallback? onCleared,
  });

  void _rememberColor(Color color);
  Future<void> _applyPaintBucket(Offset position);

  void _setActiveTool(CanvasTool tool);

  void _handlePointerDown(PointerDownEvent event);
  void _handlePointerMove(PointerMoveEvent event);
  void _handlePointerUp(PointerUpEvent event);
  void _handlePointerCancel(PointerCancelEvent event);
  void _handlePointerSignal(PointerSignalEvent event);

  void _handleScaleStart(ScaleStartDetails details);
  void _handleScaleUpdate(ScaleUpdateDetails details);
  void _handleScaleEnd(ScaleEndDetails details);

  void _handleUndo();
  void _handleRedo();

  void _updatePenStrokeWidth(double value);
  void _updateBucketSampleAllLayers(bool value);
  void _updateBucketContiguous(bool value);

  void _handleAddLayer();
  void _handleRemoveLayer(String id);

  Widget _buildLayerPanelContent(FluentThemeData theme);
  Widget _buildColorPanelContent(FluentThemeData theme);
  Widget _buildColorIndicator(FluentThemeData theme);

  List<CanvasLayerData> snapshotLayers() => _store.snapshotLayers();

  void markSaved() {
    if (!_isDirty) {
      return;
    }
    _isDirty = false;
    widget.onDirtyChanged?.call(false);
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

  void _bumpCurrentStrokeVersion() {
    _currentStrokeVersion++;
  }

  void _syncStrokeCache() {
    _strokeCache.updateLogicalSize(_canvasSize);
    _strokeCache.sync(layers: _store.committedLayers());
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
        _PaintingBoardLayerMixin,
        _PaintingBoardColorMixin,
        _PaintingBoardInteractionMixin,
        _PaintingBoardBuildMixin {
  @override
  void initState() {
    super.initState();
    _bucketSampleAllLayers = widget.bucketSampleAllLayers;
    _bucketContiguous = widget.bucketContiguous;
    _primaryHsv = HSVColor.fromColor(_primaryColor);
    _rememberColor(widget.settings.backgroundColor);
    _rememberColor(_primaryColor);
    final List<CanvasLayerData> layers = _buildInitialLayers();
    _strokeCache = StrokePictureCache(logicalSize: _canvasSize);
    _store.initialize(layers);
    _syncStrokeCache();
  }

  @override
  void dispose() {
    _strokeCache.dispose();
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
      if (backgroundChanged && _layers.isNotEmpty) {
        final CanvasLayerData baseLayer = _layers.first;
        if (baseLayer.fillColor == oldWidget.settings.backgroundColor) {
          _store.setLayerFillColor(
            baseLayer.id,
            widget.settings.backgroundColor,
          );
        }
      }
      _syncStrokeCache();
      setState(() {
        if (sizeChanged) {
          _viewport.reset();
          _workspaceSize = Size.zero;
          _layoutBaseOffset = Offset.zero;
          _viewportInitialized = false;
        }
        _bumpCurrentStrokeVersion();
      });
    }

    final bool bucketSampleAllLayersChanged =
        widget.bucketSampleAllLayers != oldWidget.bucketSampleAllLayers;
    final bool bucketContiguousChanged =
        widget.bucketContiguous != oldWidget.bucketContiguous;
    if (bucketSampleAllLayersChanged || bucketContiguousChanged) {
      setState(() {
        if (bucketSampleAllLayersChanged) {
          _bucketSampleAllLayers = widget.bucketSampleAllLayers;
        }
        if (bucketContiguousChanged) {
          _bucketContiguous = widget.bucketContiguous;
        }
      });
    }
  }
}
