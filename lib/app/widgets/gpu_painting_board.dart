import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../../bitmap_canvas/stroke_dynamics.dart' show StrokePressureProfile;
import '../../canvas/canvas_layer.dart';
import '../../canvas/canvas_settings.dart';
import '../../canvas/canvas_tools.dart';
import '../../canvas/canvas_viewport.dart';
import '../../canvas/perspective_guide.dart';
import '../../canvas/text_renderer.dart' show CanvasTextOrientation;
import '../models/canvas_view_info.dart';
import '../preferences/app_preferences.dart' show AppPreferences;
import '../toolbars/layouts/layouts.dart';
import '../toolbars/widgets/canvas_toolbar.dart';
import '../toolbars/widgets/tool_settings_card.dart';
import 'canvas_board_client.dart';

class GpuPaintingBoard extends StatefulWidget {
  const GpuPaintingBoard({
    super.key,
    required this.settings,
    required this.onRequestExit,
    this.onDirtyChanged,
    this.onReadyChanged,
    this.toolbarLayoutStyle = PaintingToolbarLayoutStyle.floating,
  });

  final CanvasSettings settings;
  final VoidCallback onRequestExit;
  final ValueChanged<bool>? onDirtyChanged;
  final ValueChanged<bool>? onReadyChanged;
  final PaintingToolbarLayoutStyle toolbarLayoutStyle;

  @override
  State<GpuPaintingBoard> createState() => GpuPaintingBoardState();
}

class GpuPaintingBoardState extends State<GpuPaintingBoard>
    implements CanvasBoardClient {
  static const double _toolButtonPadding = 16;
  static const double _toolSettingsSpacing = 12;
  static const double _sidePanelWidth = 240;
  static const double _sidePanelSpacing = 12;
  static const double _colorIndicatorSize = 56;
  // GPU 画笔的柔化用高斯模糊模拟，低等级过强，因此提供更细的 0-30 档。
  static const int _maxBrushAntialiasLevel = 30;

  static const double _defaultBrushRadius = 8.0;
  static const Color _defaultBrushColor = Color(0xFF111111);

  ui.Image? _surface;
  bool _readyNotified = false;
  bool _isDirty = false;
  Offset? _lastPosition;
  Offset? _hoverPosition;
  Color _brushColor = _defaultBrushColor;
  double _brushRadius = _defaultBrushRadius;
  int _brushAntialiasLevel = AppPreferences.defaultPenAntialiasLevel * 10;
  BrushShape _brushShape = AppPreferences.defaultBrushShape;
  double _strokeStabilizerStrength =
      AppPreferences.defaultStrokeStabilizerStrength;
  bool _stylusPressureEnabled = AppPreferences.defaultStylusPressureEnabled;
  bool _simulatePenPressure = false;
  StrokePressureProfile _penPressureProfile = StrokePressureProfile.auto;
  bool _autoSharpPeakEnabled = AppPreferences.defaultAutoSharpPeakEnabled;
  bool _vectorDrawingEnabled = AppPreferences.defaultVectorDrawingEnabled;
  bool _vectorStrokeSmoothingEnabled =
      AppPreferences.defaultVectorStrokeSmoothingEnabled;
  bool _brushToolsEraserMode = AppPreferences.defaultBrushToolsEraserMode;
  CanvasTool _activeTool = CanvasTool.pen;
  final CanvasViewport _viewport = CanvasViewport();
  bool _viewportInitialized = false;
  Size _workspaceSize = Size.zero;
  bool _isDraggingBoard = false;
  double _scaleGestureInitialScale = 1.0;
  bool _isScalingGesture = false;
  Size _toolSettingsCardSize = Size.zero;
  final List<Offset> _pendingPoints = <Offset>[];
  Future<void>? _renderingTask;
  bool _isRenderingStroke = false;

  late final ValueNotifier<CanvasViewInfo> _viewInfoNotifier;
  late final Paint _brushPaint = Paint()
    ..color = _brushColor
    ..isAntiAlias = true
    ..blendMode = BlendMode.srcOver
    ..style = PaintingStyle.fill;

  @override
  void initState() {
    super.initState();
    _viewInfoNotifier = ValueNotifier<CanvasViewInfo>(_buildViewInfo());
    _refreshBrushPaint();
    _initSurface();
  }

  @override
  void didUpdateWidget(covariant GpuPaintingBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.size != widget.settings.size ||
        oldWidget.settings.backgroundColor !=
            widget.settings.backgroundColor) {
      _surface?.dispose();
      _surface = null;
      _viewport.reset();
      _viewportInitialized = false;
      _initSurface();
    }
  }

  @override
  void dispose() {
    _surface?.dispose();
    _viewInfoNotifier.dispose();
    super.dispose();
  }

  Future<void> _initSurface() async {
    final int width = widget.settings.width.round().clamp(1, 16000);
    final int height = widget.settings.height.round().clamp(1, 16000);
    final ui.Image blank = await _createBlankSurface(
      width,
      height,
      widget.settings.backgroundColor,
    );
    if (!mounted) {
      blank.dispose();
      return;
    }
    setState(() => _surface = blank);
    _notifyReady();
  }

  Future<ui.Image> _createBlankSurface(
    int width,
    int height,
    Color background,
  ) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = background,
    );
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(width, height);
    picture.dispose();
    return image;
  }

  void _notifyReady() {
    if (_readyNotified) {
      return;
    }
    _readyNotified = true;
    widget.onReadyChanged?.call(true);
  }

  @override
  bool get isBoardReady => _surface != null;

  @override
  ValueListenable<CanvasViewInfo> get viewInfoListenable => _viewInfoNotifier;

  @override
  Future<List<CanvasLayerData>> exportLayers() async {
    await _waitPendingStrokes();
    final ui.Image? surface = _surface;
    if (surface == null) {
      return const <CanvasLayerData>[];
    }
    final ByteData? data = await surface.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (data == null) {
      return const <CanvasLayerData>[];
    }
    final Uint8List rgba = Uint8List.fromList(data.buffer.asUint8List());
    return <CanvasLayerData>[
      CanvasLayerData(
        id: generateLayerId(),
        name: 'GPU 图层',
        bitmap: rgba,
        bitmapWidth: surface.width,
        bitmapHeight: surface.height,
      ),
    ];
  }

  @override
  PerspectiveGuideState snapshotPerspectiveGuide() {
    return PerspectiveGuideState.defaults(widget.settings.size);
  }

  @override
  Future<bool> undo() async => false;

  @override
  Future<bool> redo() async => false;

  @override
  bool get canUndo => false;

  @override
  bool get canRedo => false;

  @override
  void markSaved() {
    if (!_isDirty) {
      return;
    }
    _isDirty = false;
    widget.onDirtyChanged?.call(false);
  }

  void _startStroke(Offset position, double scale) {
    _lastPosition = _toCanvasPosition(position, scale);
    _queueStrokePoints(<Offset>[_lastPosition!]);
    _updateCursor(position, scale);
  }

  void _extendStroke(Offset position, double scale) {
    final Offset current = _toCanvasPosition(position, scale);
    final Offset? last = _lastPosition;
    _lastPosition = current;
    final List<Offset> points = <Offset>[
      if (last == null) current else ..._sampleLine(last, current),
    ];
    _queueStrokePoints(points);
    _updateCursor(position, scale);
  }

  void _endStroke() {
    _lastPosition = null;
  }

  List<Offset> _sampleLine(Offset from, Offset to) {
    final double distance = (to - from).distance;
    final int steps = math.max(1, (distance / 2.2).round());
    final List<Offset> points = <Offset>[];
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      points.add(
        Offset(
          ui.lerpDouble(from.dx, to.dx, t) ?? to.dx,
          ui.lerpDouble(from.dy, to.dy, t) ?? to.dy,
        ),
      );
    }
    return points;
  }

  void _queueStrokePoints(List<Offset> points) {
    if (points.isEmpty) {
      return;
    }
    _pendingPoints.addAll(points);
    _renderingTask ??= _processStrokeQueue();
  }

  Future<void> _waitPendingStrokes() async {
    if (_pendingPoints.isEmpty && _renderingTask == null) {
      return;
    }
    _renderingTask ??= _processStrokeQueue();
    await _renderingTask;
  }

  Future<void> _processStrokeQueue() async {
    if (_isRenderingStroke) {
      return;
    }
    _isRenderingStroke = true;
    try {
      while (_pendingPoints.isNotEmpty) {
        final List<Offset> batch = _pendingPoints.length > 96
            ? _pendingPoints.sublist(0, 96)
            : List<Offset>.from(_pendingPoints);
        _pendingPoints.removeRange(0, batch.length);
        await _renderBatch(batch);
      }
    } finally {
      _isRenderingStroke = false;
      _renderingTask = null;
    }
  }

  Future<void> _renderBatch(List<Offset> points) async {
    final ui.Image? base = _surface;
    if (base == null || points.isEmpty) {
      return;
    }
    _brushPaint.color = _brushColor;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawImage(base, Offset.zero, Paint());
    for (final Offset point in points) {
      canvas.drawCircle(point, _brushRadius, _brushPaint);
    }
    final ui.Picture picture = recorder.endRecording();
    final ui.Image next = await picture.toImage(base.width, base.height);
    picture.dispose();
    base.dispose();
    if (!mounted) {
      next.dispose();
      return;
    }
    setState(() {
      _surface = next;
      _isDirty = true;
    });
    widget.onDirtyChanged?.call(true);
  }

  Offset _toCanvasPosition(Offset localPosition, double scale) {
    final double x = localPosition.dx / scale;
    final double y = localPosition.dy / scale;
    final Size size = widget.settings.size;
    return Offset(
      x.clamp(0, math.max(1.0, size.width)),
      y.clamp(0, math.max(1.0, size.height)),
    );
  }

  void _updateCursor(Offset? localPosition, double scale) {
    _hoverPosition =
        localPosition == null ? null : _toCanvasPosition(localPosition, scale);
    _refreshViewInfo();
  }

  double _computeFitScale(Size canvasSize, Size available) {
    final double scale = math.min(
      available.width / canvasSize.width,
      available.height / canvasSize.height,
    );
    if (scale.isNaN || !scale.isFinite) {
      return 1.0;
    }
    return scale.clamp(0.05, 1.0);
  }

  CanvasViewInfo _buildViewInfo() {
    return CanvasViewInfo(
      canvasSize: widget.settings.size,
      scale: _viewport.scale,
      cursorPosition: _hoverPosition,
      pixelGridVisible: false,
      viewBlackWhiteEnabled: false,
      viewMirrorEnabled: false,
      perspectiveMode: PerspectiveGuideMode.off,
      perspectiveEnabled: false,
      perspectiveVisible: false,
    );
  }

  void _refreshViewInfo() {
    _viewInfoNotifier.value = _buildViewInfo();
  }

  void _refreshBrushPaint() {
    final int level = _brushAntialiasLevel.clamp(0, _maxBrushAntialiasLevel);
    _brushPaint.isAntiAlias = level > 0;
    final double softness = _softnessForAntialiasLevel(level);
    if (softness <= 0.001) {
      _brushPaint.maskFilter = null;
      return;
    }
    final double sigma = (_brushRadius * softness).clamp(0.0, 256.0);
    _brushPaint.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);
  }

  double _softnessForAntialiasLevel(int level) {
    final int clamped = level.clamp(0, _maxBrushAntialiasLevel);
    if (clamped <= 0) {
      return 0.0;
    }
    final double t = clamped / _maxBrushAntialiasLevel;
    // 让前几个等级只产生非常轻微的柔化（更接近 CPU 的 1 级体验）。
    return math.pow(t, 1.3).toDouble() * 0.9;
  }

  Offset _baseOriginForScale(double scale) {
    final Size canvasSize = widget.settings.size;
    final double displayWidth = canvasSize.width * scale;
    final double displayHeight = canvasSize.height * scale;
    if (_workspaceSize.isEmpty) {
      return Offset.zero;
    }
    final double dx = (_workspaceSize.width - displayWidth) / 2;
    final double dy = (_workspaceSize.height - displayHeight) / 2;
    return Offset(
      dx.isFinite ? dx : 0.0,
      dy.isFinite ? dy : 0.0,
    );
  }

  void _applyZoom(double targetScale, Offset workspaceFocalPoint) {
    if (_workspaceSize.isEmpty) {
      return;
    }
    final double currentScale = _viewport.scale;
    final double clamped = _viewport.clampScale(targetScale);
    if ((clamped - currentScale).abs() < 0.0005) {
      return;
    }
    final Offset currentBase = _baseOriginForScale(currentScale);
    final Offset currentOrigin = currentBase + _viewport.offset;
    final Offset canvasLocal =
        (workspaceFocalPoint - currentOrigin) / currentScale;

    final Offset newBase = _baseOriginForScale(clamped);
    final Offset newOrigin = workspaceFocalPoint - canvasLocal * clamped;
    final Offset newOffset = newOrigin - newBase;

    setState(() {
      _viewport.setScale(clamped);
      _viewport.setOffset(newOffset);
    });
    _refreshViewInfo();
  }

  void _handlePointerSignal(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent) {
      return;
    }
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final double scrollDelta = signal.scrollDelta.dy;
    if (scrollDelta == 0) {
      return;
    }
    final Offset focalPoint = box.globalToLocal(signal.position);
    const double sensitivity = 0.0015;
    final double targetScale =
        _viewport.scale * (1 - scrollDelta * sensitivity);
    _applyZoom(targetScale, focalPoint);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    final bool shouldScale =
        details.pointerCount == 0 || details.pointerCount > 1;
    _isScalingGesture = shouldScale;
    if (!shouldScale) {
      return;
    }
    _scaleGestureInitialScale = _viewport.scale;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final Offset focalPoint = box.globalToLocal(details.focalPoint);
    _applyZoom(_viewport.scale, focalPoint);
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (!_isScalingGesture) {
      return;
    }
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final Offset focalPoint = box.globalToLocal(details.focalPoint);
    final double targetScale = _scaleGestureInitialScale * details.scale;
    _applyZoom(targetScale, focalPoint);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _isScalingGesture = false;
  }

  void _handlePointerDown(PointerDownEvent event, double scale) {
    if (_activeTool == CanvasTool.hand) {
      setState(() => _isDraggingBoard = true);
      return;
    }
    if (event.buttons == kPrimaryButton || event.buttons == 0) {
      _startStroke(event.localPosition, scale);
    }
  }

  void _handlePointerMove(PointerMoveEvent event, double scale) {
    if (_activeTool == CanvasTool.hand) {
      if (!_isDraggingBoard) {
        return;
      }
      setState(() {
        _viewport.translate(event.delta);
      });
      _refreshViewInfo();
      return;
    }
    if (_lastPosition == null) {
      return;
    }
    _extendStroke(event.localPosition, scale);
  }

  void _handlePointerUp() {
    if (_activeTool == CanvasTool.hand) {
      if (_isDraggingBoard) {
        setState(() => _isDraggingBoard = false);
      }
      return;
    }
    _endStroke();
  }

  void _setActiveTool(CanvasTool tool) {
    switch (tool) {
      case CanvasTool.pen:
      case CanvasTool.hand:
        setState(() {
          _activeTool = tool;
          if (tool == CanvasTool.hand) {
            _lastPosition = null;
          }
        });
        return;
      default:
        // GPU 画布目前仅支持画笔/抓手，其他工具先回退到画笔。
        setState(() => _activeTool = CanvasTool.pen);
        return;
    }
  }

  void _handlePenStrokeWidthChanged(double value) {
    final double radius = (value * 0.5).clamp(0.5, 512.0);
    setState(() {
      _brushRadius = radius;
      _refreshBrushPaint();
    });
  }

  void _handleBrushAntialiasChanged(int level) {
    final int clamped = level.clamp(0, _maxBrushAntialiasLevel);
    if (clamped == _brushAntialiasLevel) {
      return;
    }
    setState(() {
      _brushAntialiasLevel = clamped;
      _refreshBrushPaint();
    });
  }

  void _handleBrushShapeChanged(BrushShape shape) {
    if (shape == _brushShape) {
      return;
    }
    setState(() => _brushShape = shape);
  }

  void _handleStrokeStabilizerChanged(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    if ((clamped - _strokeStabilizerStrength).abs() < 0.0001) {
      return;
    }
    setState(() => _strokeStabilizerStrength = clamped);
  }

  void _handleStylusPressureEnabledChanged(bool enabled) {
    if (enabled == _stylusPressureEnabled) {
      return;
    }
    setState(() => _stylusPressureEnabled = enabled);
  }

  void _handleSimulatePenPressureChanged(bool enabled) {
    if (enabled == _simulatePenPressure) {
      return;
    }
    setState(() => _simulatePenPressure = enabled);
  }

  void _handlePenPressureProfileChanged(StrokePressureProfile profile) {
    if (profile == _penPressureProfile) {
      return;
    }
    setState(() => _penPressureProfile = profile);
  }

  void _handleAutoSharpPeakChanged(bool enabled) {
    if (enabled == _autoSharpPeakEnabled) {
      return;
    }
    setState(() => _autoSharpPeakEnabled = enabled);
  }

  void _handleVectorDrawingEnabledChanged(bool enabled) {
    if (enabled == _vectorDrawingEnabled) {
      return;
    }
    setState(() => _vectorDrawingEnabled = enabled);
  }

  void _handleVectorStrokeSmoothingChanged(bool enabled) {
    if (enabled == _vectorStrokeSmoothingEnabled) {
      return;
    }
    setState(() => _vectorStrokeSmoothingEnabled = enabled);
  }

  void _handleBrushToolsEraserModeChanged(bool enabled) {
    if (enabled == _brushToolsEraserMode) {
      return;
    }
    setState(() => _brushToolsEraserMode = enabled);
  }

  CanvasToolbarLayout _resolveToolbarLayoutForStyle(
    PaintingToolbarLayoutStyle style,
    CanvasToolbarLayout base, {
    required bool includeHistoryButtons,
  }) {
    if (style != PaintingToolbarLayoutStyle.sai2) {
      return base;
    }
    const int targetColumns = 4;
    final double availableWidth = math.max(0, _sidePanelWidth - 32);
    final double totalSpacing = CanvasToolbar.spacing * (targetColumns - 1);
    final double maxExtent = targetColumns > 0
        ? (availableWidth - totalSpacing) / targetColumns
        : CanvasToolbar.buttonSize;
    final double buttonExtent = maxExtent.isFinite && maxExtent > 0
        ? maxExtent.clamp(36.0, CanvasToolbar.buttonSize)
        : CanvasToolbar.buttonSize;
    final int toolCount =
        CanvasToolbar.buttonCount +
        (includeHistoryButtons ? CanvasToolbar.historyButtonCount : 0);
    final int rows = math.max(1, (toolCount / targetColumns).ceil());
    final double width = targetColumns * buttonExtent + totalSpacing;
    final double height =
        rows * buttonExtent + (rows - 1) * CanvasToolbar.spacing;
    return CanvasToolbarLayout(
      columns: targetColumns,
      rows: rows,
      width: width,
      height: height,
      buttonExtent: buttonExtent,
      horizontalFlow: true,
      flowDirection: Axis.horizontal,
    );
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onRequestExit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final Size canvasSize = widget.settings.size;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Size available = Size(
            constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : canvasSize.width,
            constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : canvasSize.height,
          );
          _workspaceSize = available;
          final double fitScale = _computeFitScale(
            canvasSize,
            available,
          );
          if (!_viewportInitialized) {
            _viewport.setScale(fitScale);
            _viewportInitialized = true;
          }
          final double scale = _viewport.scale;
          _refreshViewInfo();
          final double displayWidth = canvasSize.width * scale;
          final double displayHeight = canvasSize.height * scale;
          final Offset baseOrigin = Offset(
            (available.width - displayWidth) / 2,
            (available.height - displayHeight) / 2,
          );
          final Offset origin = baseOrigin + _viewport.offset;
          final Widget canvasSurface = _buildCanvasSurface(
            displayWidth,
            displayHeight,
          );

          final double safeToolbarHeight =
              (available.height - 2 * _toolButtonPadding)
                  .clamp(0.0, double.infinity);
          const bool includeHistoryButtons = true;
          final int toolCount = CanvasToolbar.buttonCount +
              (includeHistoryButtons
                  ? CanvasToolbar.historyButtonCount
                  : 0);
          final CanvasToolbarLayout baseToolbarLayout =
              CanvasToolbar.layoutForAvailableHeight(
            safeToolbarHeight,
            toolCount: toolCount,
          );
          final CanvasToolbarLayout activeToolbarLayout =
              _resolveToolbarLayoutForStyle(
            widget.toolbarLayoutStyle,
            baseToolbarLayout,
            includeHistoryButtons: includeHistoryButtons,
          );

          final double toolSettingsLeft = _toolButtonPadding +
              activeToolbarLayout.width +
              _toolSettingsSpacing;
          final double sidebarLeft =
              (available.width - _sidePanelWidth - _toolButtonPadding)
                  .clamp(0.0, double.infinity);
          final double? toolSettingsMaxWidth = (() {
            final double computed =
                sidebarLeft - toolSettingsLeft - _toolSettingsSpacing;
            return computed.isFinite && computed > 0 ? computed : null;
          })();

          final Widget toolbarWidget = CanvasToolbar(
            activeTool: _activeTool,
            selectionShape: SelectionShape.rectangle,
            shapeToolVariant: ShapeToolVariant.rectangle,
            onToolSelected: _setActiveTool,
            onUndo: () {},
            onRedo: () {},
            canUndo: canUndo,
            canRedo: canRedo,
            layout: activeToolbarLayout,
            includeHistoryButtons: includeHistoryButtons,
          );

          final Widget toolSettingsCard = ToolSettingsCard(
            activeTool: _activeTool,
            penStrokeWidth: _brushRadius * 2.0,
            sprayStrokeWidth: _brushRadius * 2.0,
            sprayMode: SprayMode.smudge,
            penStrokeSliderRange:
                AppPreferences.instance.penStrokeSliderRange,
            onPenStrokeWidthChanged: _handlePenStrokeWidthChanged,
            onSprayStrokeWidthChanged: (_) {},
            onSprayModeChanged: (_) {},
            brushShape: _brushShape,
            onBrushShapeChanged: _handleBrushShapeChanged,
            strokeStabilizerStrength: _strokeStabilizerStrength,
            onStrokeStabilizerChanged: _handleStrokeStabilizerChanged,
            stylusPressureEnabled: _stylusPressureEnabled,
            onStylusPressureEnabledChanged:
                _handleStylusPressureEnabledChanged,
            simulatePenPressure: _simulatePenPressure,
            onSimulatePenPressureChanged:
                _handleSimulatePenPressureChanged,
            penPressureProfile: _penPressureProfile,
            onPenPressureProfileChanged:
                _handlePenPressureProfileChanged,
            brushAntialiasLevel: _brushAntialiasLevel,
            brushAntialiasMaxLevel: _maxBrushAntialiasLevel,
            onBrushAntialiasChanged: _handleBrushAntialiasChanged,
            autoSharpPeakEnabled: _autoSharpPeakEnabled,
            onAutoSharpPeakChanged: _handleAutoSharpPeakChanged,
            bucketSampleAllLayers: false,
            bucketContiguous: false,
            bucketSwallowColorLine: false,
            bucketAntialiasLevel: 0,
            bucketAntialiasMaxLevel: 3,
            onBucketSampleAllLayersChanged: (_) {},
            onBucketContiguousChanged: (_) {},
            onBucketSwallowColorLineChanged: (_) {},
            onBucketAntialiasChanged: (_) {},
            bucketTolerance: 0,
            onBucketToleranceChanged: (_) {},
            layerAdjustCropOutside: false,
            onLayerAdjustCropOutsideChanged: (_) {},
            selectionShape: SelectionShape.rectangle,
            onSelectionShapeChanged: (_) {},
            shapeToolVariant: ShapeToolVariant.rectangle,
            onShapeToolVariantChanged: (_) {},
            shapeFillEnabled: false,
            onShapeFillChanged: (_) {},
            onSizeChanged: (size) {
              if (size != _toolSettingsCardSize) {
                setState(() => _toolSettingsCardSize = size);
              }
            },
            magicWandTolerance: 0,
            onMagicWandToleranceChanged: (_) {},
            brushToolsEraserMode: _brushToolsEraserMode,
            onBrushToolsEraserModeChanged:
                _handleBrushToolsEraserModeChanged,
            vectorDrawingEnabled: _vectorDrawingEnabled,
            onVectorDrawingEnabledChanged:
                _handleVectorDrawingEnabledChanged,
            vectorStrokeSmoothingEnabled: _vectorStrokeSmoothingEnabled,
            onVectorStrokeSmoothingChanged:
                _handleVectorStrokeSmoothingChanged,
            strokeStabilizerMaxLevel: 30,
            textFontSize: 16,
            onTextFontSizeChanged: (_) {},
            textLineHeight: 1.0,
            onTextLineHeightChanged: (_) {},
            textLetterSpacing: 0.0,
            onTextLetterSpacingChanged: (_) {},
            textFontFamily: '',
            onTextFontFamilyChanged: (_) {},
            availableFontFamilies: const <String>[],
            fontsLoading: false,
            textAlign: TextAlign.left,
            onTextAlignChanged: (_) {},
            textOrientation: CanvasTextOrientation.horizontal,
            onTextOrientationChanged: (_) {},
            textAntialias: true,
            onTextAntialiasChanged: (_) {},
            textStrokeEnabled: false,
            onTextStrokeEnabledChanged: (_) {},
            textStrokeWidth: 1.0,
            onTextStrokeWidthChanged: (_) {},
            textStrokeColor: const Color(0xFF000000),
            onTextStrokeColorPressed: () {},
          );

          final Widget colorIndicator = SizedBox(
            width: _colorIndicatorSize,
            height: _colorIndicatorSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _brushColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: FluentTheme.of(context)
                      .resources
                      .controlStrokeColorDefault,
                ),
              ),
            ),
          );
          final ToolbarPanelData colorPanelData = ToolbarPanelData(
            title: '颜色',
            child: const Center(child: Text('GPU 画布暂不支持颜色面板')),
          );
          final ToolbarPanelData layerPanelData = ToolbarPanelData(
            title: '图层',
            child: const Center(child: Text('GPU 画布暂不支持图层面板')),
            expand: true,
          );
          final PaintingToolbarElements toolbarElements =
              PaintingToolbarElements(
            toolbar: toolbarWidget,
            toolSettings: toolSettingsCard,
            colorIndicator: colorIndicator,
            colorPanel: colorPanelData,
            layerPanel: layerPanelData,
            exitButton: null,
          );
          final PaintingToolbarMetrics toolbarMetrics = PaintingToolbarMetrics(
            toolbarLayout: activeToolbarLayout,
            toolSettingsSize: _toolSettingsCardSize,
            workspaceSize: available,
            toolButtonPadding: _toolButtonPadding,
            toolSettingsSpacing: _toolSettingsSpacing,
            sidePanelWidth: _sidePanelWidth,
            sidePanelSpacing: _sidePanelSpacing,
            colorIndicatorSize: _colorIndicatorSize,
            toolSettingsLeft: toolSettingsLeft,
            sidebarLeft: sidebarLeft,
            toolSettingsMaxWidth: toolSettingsMaxWidth,
            workspaceSplits: null,
          );
          final PaintingToolbarLayoutDelegate toolbarLayoutDelegate =
              widget.toolbarLayoutStyle == PaintingToolbarLayoutStyle.sai2
                  ? const Sai2ToolbarLayoutDelegate()
                  : const FloatingToolbarLayoutDelegate();
          final PaintingToolbarLayoutResult toolbarLayoutResult =
              toolbarLayoutDelegate.build(
            context,
            toolbarElements,
            toolbarMetrics,
          );
          return Container(
            color: FluentTheme.of(context).micaBackgroundColor,
            child: Stack(
              children: [
                Positioned(
                  left: origin.dx,
                  top: origin.dy,
                  width: displayWidth,
                  height: displayHeight,
                  child: _buildInputRegion(canvasSurface, scale),
                ),
                ...toolbarLayoutResult.widgets,
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: InfoBar(
                    title: const Text('GPU 画布（实验性）'),
                    content: const Text('当前仅提供基础画笔，功能正在逐步完善。'),
                    style: InfoBarThemeData(
                      decoration: (_) => BoxDecoration(
                        color: Colors.blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputRegion(Widget child, double scale) {
    final MouseCursor cursor = _activeTool == CanvasTool.hand
        ? (_isDraggingBoard
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab)
        : SystemMouseCursors.precise;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      onScaleEnd: _handleScaleEnd,
      child: MouseRegion(
        cursor: cursor,
        onHover: (event) => _updateCursor(event.localPosition, scale),
        onExit: (_) => _updateCursor(null, scale),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _handlePointerDown(event, scale),
          onPointerMove: (event) => _handlePointerMove(event, scale),
          onPointerUp: (_) => _handlePointerUp(),
          onPointerCancel: (_) => _handlePointerUp(),
          onPointerSignal: _handlePointerSignal,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: FluentTheme.of(context)
                    .resources
                    .controlStrokeColorDefault,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasSurface(double displayWidth, double displayHeight) {
    final ui.Image? surface = _surface;
    return SizedBox(
      width: displayWidth,
      height: displayHeight,
      child: surface == null
          ? const Center(child: ProgressRing())
          : RawImage(
              image: surface,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.none,
            ),
    );
  }
}

class _GpuBrushRenderer {
  static Future<ui.FragmentProgram>? _cached;

  static Future<ui.FragmentProgram> get program =>
      _cached ??= ui.FragmentProgram.fromAsset('shaders/gpu_brush.frag');

  static Future<ui.Image> paint({
    required ui.Image base,
    required Offset position,
    required double radius,
    required Color color,
  }) async {
    final ui.FragmentProgram program = await _GpuBrushRenderer.program;
    final ui.FragmentShader shader = program.fragmentShader()
      ..setFloat(0, base.width.toDouble())
      ..setFloat(1, base.height.toDouble())
      ..setFloat(2, position.dx)
      ..setFloat(3, position.dy)
      ..setFloat(4, radius)
      ..setFloat(5, color.red / 255.0)
      ..setFloat(6, color.green / 255.0)
      ..setFloat(7, color.blue / 255.0)
      ..setFloat(8, color.alpha / 255.0)
      ..setImageSampler(0, base);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
      Paint()..shader = shader,
    );
    final ui.Picture picture = recorder.endRecording();
    final ui.Image next = await picture.toImage(base.width, base.height);
    picture.dispose();
    return next;
  }
}
