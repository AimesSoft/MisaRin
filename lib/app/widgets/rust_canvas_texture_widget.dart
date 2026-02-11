import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

import 'package:misa_rin/src/rust/canvas_engine_ffi.dart';

import '../utils/tablet_input_bridge.dart';

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

const int _kPointStrideBytes = 32;
const int _kPointFlagDown = 1;
const int _kPointFlagMove = 2;
const int _kPointFlagUp = 4;
const int _initialLayerCount = 4;

final class _PackedPointBuffer {
  _PackedPointBuffer({int initialCapacityPoints = 256})
    : _bytes = Uint8List(initialCapacityPoints * _kPointStrideBytes) {
    _data = ByteData.view(_bytes.buffer);
  }

  Uint8List _bytes;
  late ByteData _data;
  int _len = 0;

  int get length => _len;

  Uint8List get bytes => _bytes;

  void clear() => _len = 0;

  void add({
    required double x,
    required double y,
    required double pressure,
    required int timestampUs,
    required int flags,
    required int pointerId,
  }) {
    _ensureCapacity(_len + 1);
    final int base = _len * _kPointStrideBytes;
    _data.setFloat32(base + 0, x, Endian.little);
    _data.setFloat32(base + 4, y, Endian.little);
    _data.setFloat32(base + 8, pressure, Endian.little);
    _data.setFloat32(base + 12, 0.0, Endian.little); // pad
    _data.setUint64(base + 16, timestampUs, Endian.little);
    _data.setUint32(base + 24, flags, Endian.little);
    _data.setUint32(base + 28, pointerId, Endian.little);
    _len++;
  }

  void _ensureCapacity(int neededPoints) {
    final int neededBytes = neededPoints * _kPointStrideBytes;
    if (_bytes.lengthInBytes >= neededBytes) {
      return;
    }
    int nextBytes = _bytes.lengthInBytes;
    while (nextBytes < neededBytes) {
      nextBytes = nextBytes * 2;
    }
    final Uint8List next = Uint8List(nextBytes);
    next.setRange(0, _len * _kPointStrideBytes, _bytes, 0);
    _bytes = next;
    _data = ByteData.view(_bytes.buffer);
  }
}

class RustCanvasTextureWidget extends StatefulWidget {
  const RustCanvasTextureWidget({
    super.key,
    this.canvasSize = const Size(512, 512),
    this.stylusCurve = 1.0,
  });

  final Size canvasSize;
  final double stylusCurve;

  @override
  State<RustCanvasTextureWidget> createState() =>
      _RustCanvasTextureWidgetState();
}

class _RustCanvasTextureWidgetState extends State<RustCanvasTextureWidget> {
  static const MethodChannel _channel = MethodChannel(
    'misarin/rust_canvas_texture',
  );
  static int _nextSurfaceId = 1;

  int? _textureId;
  int? _engineHandle;
  Object? _error;
  late final String _surfaceId;

  final _PackedPointBuffer _points = _PackedPointBuffer();
  bool _flushScheduled = false;
  int? _activeDrawingPointer;
  Size _viewSize = Size.zero;

  int _activeLayerIndex = 0;
  final List<bool> _layerVisible = List<bool>.filled(_initialLayerCount, false)
    ..[0] = true;
  final List<double> _layerOpacity = List<double>.filled(
    _initialLayerCount,
    1.0,
  );

  double _scale = 1.0;
  Offset _pan = Offset.zero;

  double _gestureStartScale = 1.0;
  Offset _gestureStartPan = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _surfaceId = 'rust_canvas_demo_${_nextSurfaceId++}';
    unawaited(_loadTextureInfo());
  }

  Future<void> _loadTextureInfo() async {
    if (!CanvasEngineFfi.instance.isSupported) {
      if (!mounted) {
        return;
      }
      setState(() {
        _textureId = null;
        _engineHandle = null;
        _error = null;
      });
      return;
    }
    try {
      final int width = widget.canvasSize.width.round().clamp(1, 16384);
      final int height = widget.canvasSize.height.round().clamp(1, 16384);
      final Map<dynamic, dynamic>? info = await _channel
          .invokeMethod<Map<dynamic, dynamic>>(
            'getTextureInfo',
            <String, Object?>{
              'surfaceId': _surfaceId,
              'width': width,
              'height': height,
              'layerCount': _layerVisible.length,
              'backgroundColorArgb': 0xFFFFFFFF,
            },
          );
      final int? textureId = (info?['textureId'] as num?)?.toInt();
      final int? engineHandle = (info?['engineHandle'] as num?)?.toInt();
      if (!mounted) {
        return;
      }
      setState(() {
        _textureId = textureId;
        _engineHandle = engineHandle;
        _error = (textureId == null || engineHandle == null)
            ? StateError('textureId/engineHandle == null: $info')
            : null;
      });
      final int? handle = _engineHandle;
      if (handle != null) {
        _applyLayerDefaults(handle);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _textureId = null;
        _engineHandle = null;
        _error = error;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_disposeSurface());
    super.dispose();
  }

  Future<void> _disposeSurface() async {
    try {
      await _channel.invokeMethod<void>('disposeTexture', <String, Object?>{
        'surfaceId': _surfaceId,
      });
    } catch (_) {}
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _gestureStartScale = _scale;
    _gestureStartPan = _pan;
    _gestureStartFocalPoint = details.focalPoint;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      return;
    }
    final double nextScale = (_gestureStartScale * details.scale).clamp(
      0.1,
      64.0,
    );
    final Offset nextPan =
        _gestureStartPan + (details.focalPoint - _gestureStartFocalPoint);
    setState(() {
      _scale = nextScale;
      _pan = nextPan;
    });
  }

  bool _canSendPoints() {
    return CanvasEngineFfi.instance.isSupported && _engineHandle != null;
  }

  bool _isDrawingPointer(PointerEvent event) {
    if (TabletInputBridge.instance.isTabletPointer(event)) {
      return true;
    }
    if (event.kind == PointerDeviceKind.mouse) {
      return (event.buttons & kPrimaryMouseButton) != 0;
    }
    return false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_canSendPoints() || !_isDrawingPointer(event)) {
      return;
    }
    _activeDrawingPointer = event.pointer;
    _enqueuePoint(event, _kPointFlagDown);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activeDrawingPointer != event.pointer) {
      return;
    }
    final dynamic dyn = event;
    try {
      final List<dynamic>? coalesced = dyn.coalescedEvents as List<dynamic>?;
      if (coalesced != null && coalesced.isNotEmpty) {
        for (final dynamic e in coalesced) {
          if (e is PointerEvent) {
            _enqueuePoint(e, _kPointFlagMove);
          }
        }
        return;
      }
    } catch (_) {}
    _enqueuePoint(event, _kPointFlagMove);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_activeDrawingPointer != event.pointer) {
      return;
    }
    _enqueuePoint(event, _kPointFlagUp);
    _activeDrawingPointer = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_activeDrawingPointer != event.pointer) {
      return;
    }
    _enqueuePoint(event, _kPointFlagUp);
    _activeDrawingPointer = null;
  }

  void _applyLayerDefaults(int handle) {
    if (!CanvasEngineFfi.instance.isSupported) {
      return;
    }
    CanvasEngineFfi.instance.setActiveLayer(
      handle: handle,
      layerIndex: _activeLayerIndex,
    );
    for (int i = 0; i < _layerVisible.length; i++) {
      CanvasEngineFfi.instance.setLayerVisible(
        handle: handle,
        layerIndex: i,
        visible: _layerVisible[i],
      );
      CanvasEngineFfi.instance.setLayerOpacity(
        handle: handle,
        layerIndex: i,
        opacity: _layerOpacity[i],
      );
    }
  }

  void _enqueuePoint(PointerEvent event, int flags) {
    final int? handle = _engineHandle;
    if (handle == null) {
      return;
    }
    if (_viewSize.isEmpty) {
      return;
    }
    final Offset canvasPos = _toCanvasSpace(event.localPosition, _viewSize);
    final double pressure = _normalizeStylusPressure(event) ?? 1.0;
    final int timestampUs = event.timeStamp.inMicroseconds;
    _points.add(
      x: canvasPos.dx,
      y: canvasPos.dy,
      pressure: pressure,
      timestampUs: timestampUs,
      flags: flags,
      pointerId: event.pointer,
    );
    _scheduleFlush();
  }

  double? _normalizeStylusPressure(PointerEvent event) {
    final double? pressure = TabletInputBridge.instance.pressureForEvent(event);
    if (pressure == null || !pressure.isFinite) {
      return null;
    }
    double lower = event.pressureMin;
    double upper = event.pressureMax;
    if (!lower.isFinite) {
      lower = 0.0;
    }
    if (!upper.isFinite || upper <= lower) {
      upper = lower + 1.0;
    }
    final double normalized = (pressure - lower) / (upper - lower);
    if (!normalized.isFinite) {
      return null;
    }
    final double curve = widget.stylusCurve.isFinite ? widget.stylusCurve : 1.0;
    final double curved =
        math.pow(normalized.clamp(0.0, 1.0), curve).toDouble();
    return curved.clamp(0.0, 1.0);
  }

  void _scheduleFlush() {
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _flushScheduled = false;
      if (!mounted) {
        _points.clear();
        return;
      }
      final int? handle = _engineHandle;
      if (handle == null) {
        _points.clear();
        return;
      }
      _flushToRust(handle);
    });
  }

  void _flushToRust(int handle) {
    final int count = _points.length;
    if (count == 0) {
      return;
    }
    CanvasEngineFfi.instance.pushPointsPacked(
      handle: handle,
      bytes: _points.bytes,
      pointCount: count,
    );
    _points.clear();
  }

  void _handleSelectLayer(int layerIndex) {
    final int? handle = _engineHandle;
    if (handle == null) {
      return;
    }
    if (layerIndex < 0 || layerIndex >= _layerVisible.length) {
      return;
    }
    setState(() => _activeLayerIndex = layerIndex);
    CanvasEngineFfi.instance.setActiveLayer(
      handle: handle,
      layerIndex: layerIndex,
    );
  }

  void _handleToggleLayerVisible(int layerIndex) {
    final int? handle = _engineHandle;
    if (handle == null) {
      return;
    }
    if (layerIndex < 0 || layerIndex >= _layerVisible.length) {
      return;
    }
    final bool next = !_layerVisible[layerIndex];
    setState(() => _layerVisible[layerIndex] = next);
    CanvasEngineFfi.instance.setLayerVisible(
      handle: handle,
      layerIndex: layerIndex,
      visible: next,
    );
  }

  void _handleSetActiveLayerOpacity(double opacity) {
    final int? handle = _engineHandle;
    if (handle == null) {
      return;
    }
    final int layerIndex = _activeLayerIndex;
    final double next = opacity.clamp(0.0, 1.0);
    setState(() => _layerOpacity[layerIndex] = next);
    CanvasEngineFfi.instance.setLayerOpacity(
      handle: handle,
      layerIndex: layerIndex,
      opacity: next,
    );
  }

  void _handleAddLayer() {
    final int? handle = _engineHandle;
    if (handle == null) {
      return;
    }
    final int topVisible = _layerVisible.lastIndexWhere((v) => v);
    final int nextIndex = topVisible == -1 ? 0 : (topVisible + 1);
    setState(() {
      while (_layerVisible.length <= nextIndex) {
        _layerVisible.add(false);
        _layerOpacity.add(1.0);
      }
      _layerVisible[nextIndex] = true;
      _layerOpacity[nextIndex] = 1.0;
      _activeLayerIndex = nextIndex;
    });
    CanvasEngineFfi.instance.clearLayer(handle: handle, layerIndex: nextIndex);
    CanvasEngineFfi.instance.setLayerVisible(
      handle: handle,
      layerIndex: nextIndex,
      visible: true,
    );
    CanvasEngineFfi.instance.setLayerOpacity(
      handle: handle,
      layerIndex: nextIndex,
      opacity: 1.0,
    );
    CanvasEngineFfi.instance.setActiveLayer(
      handle: handle,
      layerIndex: nextIndex,
    );
  }

  void _handleDeleteLayer() {
    final int? handle = _engineHandle;
    if (handle == null) {
      return;
    }
    final int layerIndex = _activeLayerIndex;
    final int visibleCount = _layerVisible.where((v) => v).length;
    if (visibleCount <= 1) {
      CanvasEngineFfi.instance.clearLayer(
        handle: handle,
        layerIndex: layerIndex,
      );
      return;
    }

    int? nextActive;
    for (int i = layerIndex - 1; i >= 0; i--) {
      if (_layerVisible[i]) {
        nextActive = i;
        break;
      }
    }
    if (nextActive == null) {
      for (int i = layerIndex + 1; i < _layerVisible.length; i++) {
        if (_layerVisible[i]) {
          nextActive = i;
          break;
        }
      }
    }

    setState(() {
      _layerVisible[layerIndex] = false;
      if (nextActive != null && nextActive >= 0) {
        _activeLayerIndex = nextActive;
      }
    });
    CanvasEngineFfi.instance.setLayerVisible(
      handle: handle,
      layerIndex: layerIndex,
      visible: false,
    );
    CanvasEngineFfi.instance.clearLayer(handle: handle, layerIndex: layerIndex);
    if (nextActive != null && nextActive >= 0) {
      CanvasEngineFfi.instance.setActiveLayer(
        handle: handle,
        layerIndex: nextActive,
      );
    }
  }

  Offset _toCanvasSpace(Offset localPos, Size viewSize) {
    final Offset viewCenter = viewSize.center(Offset.zero);
    final Offset canvasCenter = viewCenter + _pan;
    final Offset unscaled = (localPos - canvasCenter) / _scale;
    return unscaled +
        Offset(widget.canvasSize.width / 2.0, widget.canvasSize.height / 2.0);
  }

  void _handleUndo() {
    final int? handle = _engineHandle;
    if (handle == null) {
      return;
    }
    CanvasEngineFfi.instance.undo(handle: handle);
  }

  void _handleRedo() {
    final int? handle = _engineHandle;
    if (handle == null) {
      return;
    }
    CanvasEngineFfi.instance.redo(handle: handle);
  }

  @override
  Widget build(BuildContext context) {
    final int? textureId = _textureId;
    final Object? error = _error;

    if (error != null) {
      return ColoredBox(
        color: const Color(0xFF000000),
        child: Center(
          child: Text(
            'Rust texture init failed: $error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFFFFFF)),
          ),
        ),
      );
    }

    if (textureId == null) {
      return const ColoredBox(
        color: Color(0xFF000000),
        child: Center(
          child: Text(
            'Initializing Rust texture…',
            style: TextStyle(color: Color(0xFFFFFFFF)),
          ),
        ),
      );
    }

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewSize = constraints.biggest;
          return FocusableActionDetector(
            autofocus: true,
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                  _UndoIntent(),
              SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
                  _RedoIntent(),
              SingleActivator(LogicalKeyboardKey.keyY, meta: true):
                  _RedoIntent(),
            },
            actions: <Type, Action<Intent>>{
              _UndoIntent: CallbackAction<_UndoIntent>(
                onInvoke: (_) {
                  _handleUndo();
                  return null;
                },
              ),
              _RedoIntent: CallbackAction<_RedoIntent>(
                onInvoke: (_) {
                  _handleRedo();
                  return null;
                },
              ),
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onScaleStart: _handleScaleStart,
                    onScaleUpdate: _handleScaleUpdate,
                    child: Listener(
                      onPointerDown: _handlePointerDown,
                      onPointerMove: _handlePointerMove,
                      onPointerUp: _handlePointerUp,
                      onPointerCancel: _handlePointerCancel,
                      child: ColoredBox(
                        color: const Color(0xFF000000),
                        child: Center(
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..translateByDouble(_pan.dx, _pan.dy, 0, 1)
                              ..scaleByDouble(_scale, _scale, 1, 1),
                            child: SizedBox(
                              width: widget.canvasSize.width,
                              height: widget.canvasSize.height,
                              child: ColoredBox(
                                color: const Color(0xFFFFFFFF),
                                child: Texture(
                                  textureId: textureId,
                                  filterQuality: FilterQuality.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: SizedBox(
                    width: 180,
                    child: _LayerOverlayPanel(
                      activeLayerIndex: _activeLayerIndex,
                      layerVisible: _layerVisible,
                      layerOpacity: _layerOpacity,
                      onAddLayer: _handleAddLayer,
                      onDeleteLayer: _handleDeleteLayer,
                      onSelectLayer: _handleSelectLayer,
                      onToggleLayerVisible: _handleToggleLayerVisible,
                      onSetActiveLayerOpacity: _handleSetActiveLayerOpacity,
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _OverlayButton(label: '撤销', onPressed: _handleUndo),
                      const SizedBox(width: 8),
                      _OverlayButton(label: '恢复', onPressed: _handleRedo),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xAA202020),
          border: Border.all(color: const Color(0xFF404040)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12),
          ),
        ),
      ),
    );
  }
}

class _LayerOverlayPanel extends StatelessWidget {
  const _LayerOverlayPanel({
    required this.activeLayerIndex,
    required this.layerVisible,
    required this.layerOpacity,
    required this.onAddLayer,
    required this.onDeleteLayer,
    required this.onSelectLayer,
    required this.onToggleLayerVisible,
    required this.onSetActiveLayerOpacity,
  });

  final int activeLayerIndex;
  final List<bool> layerVisible;
  final List<double> layerOpacity;
  final VoidCallback onAddLayer;
  final VoidCallback onDeleteLayer;
  final ValueChanged<int> onSelectLayer;
  final ValueChanged<int> onToggleLayerVisible;
  final ValueChanged<double> onSetActiveLayerOpacity;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int idx = layerVisible.length - 1; idx >= 0; idx--) {
      final bool isActive = idx == activeLayerIndex;
      final bool visible = layerVisible[idx];
      rows.add(
        GestureDetector(
          onTap: () => onSelectLayer(idx),
          child: Container(
            width: 160,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF2B2B2B)
                  : const Color(0xAA202020),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF7A7A7A)
                    : const Color(0xFF404040),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '图层 ${idx + 1}',
                    style: TextStyle(
                      color: visible
                          ? const Color(0xFFFFFFFF)
                          : const Color(0xFF8A8A8A),
                      fontSize: 12,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => onToggleLayerVisible(idx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: visible
                          ? const Color(0xFF3A3A3A)
                          : const Color(0xFF1A1A1A),
                      border: Border.all(color: const Color(0xFF404040)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      visible ? '显' : '隐',
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      rows.add(const SizedBox(height: 6));
    }

    final double activeOpacity =
        (activeLayerIndex >= 0 && activeLayerIndex < layerOpacity.length)
        ? layerOpacity[activeLayerIndex]
        : 1.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xAA101010),
        border: Border.all(color: const Color(0xFF303030)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '图层',
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _OverlayButton(label: '新建', onPressed: onAddLayer),
                const SizedBox(width: 8),
                _OverlayButton(label: '删除', onPressed: onDeleteLayer),
              ],
            ),
            const SizedBox(height: 10),
            ...rows,
            const SizedBox(height: 6),
            const Text(
              '不透明度',
              style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OpacityButton(
                  label: '100%',
                  selected: (activeOpacity - 1.0).abs() < 0.001,
                  onPressed: () => onSetActiveLayerOpacity(1.0),
                ),
                _OpacityButton(
                  label: '75%',
                  selected: (activeOpacity - 0.75).abs() < 0.001,
                  onPressed: () => onSetActiveLayerOpacity(0.75),
                ),
                _OpacityButton(
                  label: '50%',
                  selected: (activeOpacity - 0.5).abs() < 0.001,
                  onPressed: () => onSetActiveLayerOpacity(0.5),
                ),
                _OpacityButton(
                  label: '25%',
                  selected: (activeOpacity - 0.25).abs() < 0.001,
                  onPressed: () => onSetActiveLayerOpacity(0.25),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OpacityButton extends StatelessWidget {
  const _OpacityButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2E5BFF) : const Color(0xFF2A2A2A),
          border: Border.all(color: const Color(0xFF404040)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 11),
          ),
        ),
      ),
    );
  }
}
