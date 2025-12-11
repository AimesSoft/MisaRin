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
import '../../canvas/perspective_guide.dart';
import '../models/canvas_view_info.dart';
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
  static const double _brushRadius = 8.0;
  static const Color _defaultBrushColor = Color(0xFF111111);

  ui.Image? _surface;
  bool _readyNotified = false;
  bool _isDirty = false;
  Offset? _lastPosition;
  Offset? _hoverPosition;
  double _scale = 1.0;
  Color _brushColor = _defaultBrushColor;
  Future<void> _strokeQueue = Future<void>.value();

  late final ValueNotifier<CanvasViewInfo> _viewInfoNotifier;

  @override
  void initState() {
    super.initState();
    _viewInfoNotifier = ValueNotifier<CanvasViewInfo>(_buildViewInfo());
    _initSurface();
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
    await _strokeQueue;
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
    _applyStrokePoint(_lastPosition!);
    _updateCursor(position, scale);
  }

  void _extendStroke(Offset position, double scale) {
    final Offset current = _toCanvasPosition(position, scale);
    final Offset? last = _lastPosition;
    _lastPosition = current;
    if (last == null) {
      _applyStrokePoint(current);
      return;
    }
    _drawLine(last, current);
    _updateCursor(position, scale);
  }

  void _endStroke() {
    _lastPosition = null;
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
    _refreshViewInfo(scale: scale);
  }

  Future<void> _applyStrokePoint(Offset position) {
    _strokeQueue = _strokeQueue.then((_) async {
      final ui.Image? base = _surface;
      if (base == null) {
        return;
      }
      final ui.Image next = await _GpuBrushRenderer.paint(
        base: base,
        position: position,
        radius: _brushRadius,
        color: _brushColor,
      );
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
    });
    return _strokeQueue;
  }

  Future<void> _drawLine(Offset from, Offset to) async {
    final double distance = (to - from).distance;
    final int steps = math.max(1, (distance / 2.2).round());
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final Offset point = Offset(
        ui.lerpDouble(from.dx, to.dx, t) ?? to.dx,
        ui.lerpDouble(from.dy, to.dy, t) ?? to.dy,
      );
      await _applyStrokePoint(point);
    }
  }

  double _computeScale(Size canvasSize, Size available) {
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
      scale: _scale,
      cursorPosition: _hoverPosition,
      pixelGridVisible: false,
      viewBlackWhiteEnabled: false,
      viewMirrorEnabled: false,
      perspectiveMode: PerspectiveGuideMode.off,
      perspectiveEnabled: false,
      perspectiveVisible: false,
    );
  }

  void _refreshViewInfo({double? scale}) {
    if (scale != null && (scale - _scale).abs() > 1e-6) {
      _scale = scale;
    }
    _viewInfoNotifier.value = _buildViewInfo();
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
          final double scale = _computeScale(
            canvasSize,
            Size(
              constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : canvasSize.width,
              constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : canvasSize.height,
            ),
          );
          _refreshViewInfo(scale: scale);
          final double displayWidth = canvasSize.width * scale;
          final double displayHeight = canvasSize.height * scale;
          final Offset origin = Offset(
            (constraints.maxWidth - displayWidth) / 2,
            (constraints.maxHeight - displayHeight) / 2,
          );
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
    return MouseRegion(
      onHover: (event) => _updateCursor(event.localPosition, scale),
      onExit: (_) => _updateCursor(null, scale),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _startStroke(details.localPosition, scale),
        onPanUpdate: (details) => _extendStroke(details.localPosition, scale),
        onPanEnd: (_) => _endStroke(),
        child: Listener(
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent &&
                signal.kind == PointerDeviceKind.mouse &&
                signal.scrollDelta.dy != 0) {
              // 阻止父级滚动，将滚动意图吞掉。
            }
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: FluentTheme.of(context).resources.controlStrokeColorDefault,
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
