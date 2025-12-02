import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// 自定义窗口拖拽区域，不依赖 Flutter 内建的双击识别，避免 300ms 的双击等待。
class WindowDragArea extends StatefulWidget {
  const WindowDragArea({
    super.key,
    required this.child,
    this.enableDoubleClickToMaximize = true,
    this.doubleClickInterval = const Duration(milliseconds: 250),
    this.canDragAtPosition,
  });

  final Widget child;
  final bool enableDoubleClickToMaximize;
  final Duration doubleClickInterval;
  final bool Function(Offset localPosition)? canDragAtPosition;

  @override
  State<WindowDragArea> createState() => _WindowDragAreaState();
}

class _WindowDragAreaState extends State<WindowDragArea> {
  static const double _dragThreshold = 2.0;

  Offset? _pointerDownPosition;
  DateTime? _lastTapAt;
  bool _dragStarted = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        (event.buttons & kPrimaryMouseButton) == 0) {
      _pointerDownPosition = null;
      _dragStarted = false;
      return;
    }
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      _pointerDownPosition = null;
      return;
    }
    final Offset localPosition = box.globalToLocal(event.position);
    if (widget.canDragAtPosition != null &&
        !widget.canDragAtPosition!(localPosition)) {
      _pointerDownPosition = null;
      _dragStarted = false;
      return;
    }
    _pointerDownPosition = event.position;
    _dragStarted = false;

    if (!widget.enableDoubleClickToMaximize) {
      return;
    }
    final DateTime now = DateTime.now();
    if (_lastTapAt != null &&
        now.difference(_lastTapAt!) <= widget.doubleClickInterval) {
      _lastTapAt = null;
      _toggleMaximize();
    } else {
      _lastTapAt = now;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_dragStarted || _pointerDownPosition == null || !event.down) {
      return;
    }
    final double distance = (event.position - _pointerDownPosition!).distance;
    if (distance >= _dragThreshold) {
      _dragStarted = true;
      unawaited(windowManager.startDragging());
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _pointerDownPosition = null;
    _dragStarted = false;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _pointerDownPosition = null;
    _dragStarted = false;
  }

  void _toggleMaximize() {
    unawaited(_toggleMaximizeAsync());
  }

  Future<void> _toggleMaximizeAsync() async {
    final bool isMaximized = await windowManager.isMaximized();
    if (isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }
}
