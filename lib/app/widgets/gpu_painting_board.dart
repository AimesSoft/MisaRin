import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../../canvas/canvas_layer.dart';
import '../../canvas/canvas_settings.dart';
import '../../canvas/canvas_tools.dart';
import '../../canvas/canvas_viewport.dart';
import '../../canvas/perspective_guide.dart';
import '../models/canvas_view_info.dart';
import '../toolbars/widgets/hand_tool_button.dart';
import '../toolbars/widgets/pen_tool_button.dart';
import 'canvas_board_client.dart';

class GpuPaintingBoard extends StatefulWidget {
  const GpuPaintingBoard({
    super.key,
    required this.settings,
    required this.onRequestExit,
    this.onDirtyChanged,
    this.onReadyChanged,
  });

  final CanvasSettings settings;
  final VoidCallback onRequestExit;
  final ValueChanged<bool>? onDirtyChanged;
  final ValueChanged<bool>? onReadyChanged;

  @override
  State<GpuPaintingBoard> createState() => GpuPaintingBoardState();
}

class GpuPaintingBoardState extends State<GpuPaintingBoard>
    implements CanvasBoardClient {
  static const double _defaultBrushRadius = 8.0;
  static const double _defaultBrushSoftness = 0.5;
  static const Color _defaultBrushColor = Color(0xFF111111);

  ui.Image? _surface;
  bool _readyNotified = false;
  bool _isDirty = false;
  Offset? _lastPosition;
  Offset? _hoverPosition;
  Color _brushColor = _defaultBrushColor;
  double _brushRadius = _defaultBrushRadius;
  double _brushSoftness = _defaultBrushSoftness;
  CanvasTool _activeTool = CanvasTool.pen;
  final CanvasViewport _viewport = CanvasViewport();
  bool _viewportInitialized = false;
  Size _workspaceSize = Size.zero;
  bool _isDraggingBoard = false;
  double _scaleGestureInitialScale = 1.0;
  bool _isScalingGesture = false;
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
    final double softness = _brushSoftness.clamp(0.0, 1.0);
    if (softness <= 0.001) {
      _brushPaint.maskFilter = null;
      return;
    }
    final double sigma = (_brushRadius * softness).clamp(0.0, 256.0);
    _brushPaint.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);
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
                Positioned(
                  left: 16,
                  top: 16,
                  child: _buildToolOverlay(),
                ),
                Positioned(
                  left: 16,
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

  Widget _buildToolOverlay() {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color panelColor =
        theme.micaBackgroundColor.withOpacity(0.9);
    final TextStyle labelStyle =
        theme.typography.bodyStrong ?? const TextStyle(fontSize: 14);
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.resources.controlStrokeColorDefault,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PenToolButton(
                isSelected: _activeTool == CanvasTool.pen,
                onPressed: () {
                  if (_activeTool != CanvasTool.pen) {
                    setState(() => _activeTool = CanvasTool.pen);
                  }
                },
              ),
              const SizedBox(width: 8),
              HandToolButton(
                isSelected: _activeTool == CanvasTool.hand,
                onPressed: () {
                  if (_activeTool != CanvasTool.hand) {
                    setState(() {
                      _activeTool = CanvasTool.hand;
                      _lastPosition = null;
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('粗细', style: labelStyle),
          Slider(
            value: _brushRadius,
            min: 1.0,
            max: 64.0,
            onChanged: _activeTool == CanvasTool.pen
                ? (value) {
                    setState(() {
                      _brushRadius = value.clamp(1.0, 64.0);
                      _refreshBrushPaint();
                    });
                  }
                : null,
          ),
          Text(
            _brushRadius.toStringAsFixed(1),
            style: theme.typography.caption,
          ),
          const SizedBox(height: 8),
          Text('边缘柔化', style: labelStyle),
          Slider(
            value: _brushSoftness,
            min: 0.0,
            max: 1.0,
            onChanged: _activeTool == CanvasTool.pen
                ? (value) {
                    setState(() {
                      _brushSoftness = value.clamp(0.0, 1.0);
                      _refreshBrushPaint();
                    });
                  }
                : null,
          ),
          Text(
            '${(_brushSoftness * 100).round()}%',
            style: theme.typography.caption,
          ),
        ],
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
