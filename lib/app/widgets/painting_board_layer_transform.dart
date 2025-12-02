part of 'painting_board.dart';

const double _kLayerTransformPanelWidth = 280;
const double _kLayerTransformPanelMinHeight = 108;
const double _kLayerTransformHandleVisualSize = 12;
const double _kLayerTransformHandleHitSize = 24;
const double _kLayerTransformRotationHandleDistance = 36;
const double _kLayerTransformRotationHandleRadius = 6;
const double _kLayerTransformMinScale = 0.02;
const double _kLayerTransformMaxScale = 64;

enum _LayerTransformHandle {
  translate,
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
  rotation,
}

class _LayerTransformStateModel {
  _LayerTransformStateModel({
    required ui.Image image,
    required Rect bounds,
    required Offset imageOrigin,
  }) : image = image,
       bounds = bounds,
       imageOrigin = imageOrigin,
       fullImageSize = Size(
         image.width.toDouble().clamp(1.0, double.infinity),
         image.height.toDouble().clamp(1.0, double.infinity),
       ),
       imageSize = Size(
         bounds.width.clamp(1.0, double.infinity),
         bounds.height.clamp(1.0, double.infinity),
       ),
       clipOffset = _computeClipOffset(
         bounds,
         imageOrigin,
         image.width.toDouble(),
         image.height.toDouble(),
       ),
       baseTranslation = bounds.topLeft,
       translation = bounds.topLeft,
       rotation = 0.0,
       scaleX = 1.0,
       scaleY = 1.0,
       pivotLocal = Offset(bounds.width / 2, bounds.height / 2);

  final ui.Image image;
  final Rect bounds;
  final Offset imageOrigin;
  final Size fullImageSize;
  final Size imageSize;
  final Offset clipOffset;
  final Offset baseTranslation;
  Offset translation;
  double rotation;
  double scaleX;
  double scaleY;
  final Offset pivotLocal;

  static Offset _computeClipOffset(
    Rect bounds,
    Offset origin,
    double imageWidth,
    double imageHeight,
  ) {
    final double maxX = math.max(0.0, imageWidth - bounds.width);
    final double maxY = math.max(0.0, imageHeight - bounds.height);
    final double dx = (bounds.left - origin.dx).clamp(0.0, maxX);
    final double dy = (bounds.top - origin.dy).clamp(0.0, maxY);
    return Offset(dx, dy);
  }

  Matrix4 get matrix {
    final Matrix4 result = Matrix4.identity();
    result.translate(translation.dx, translation.dy);
    result.translate(pivotLocal.dx, pivotLocal.dy);
    result.rotateZ(rotation);
    result.scale(scaleX, scaleY);
    result.translate(-pivotLocal.dx, -pivotLocal.dy);
    return result;
  }

  Matrix4? get inverseMatrix => Matrix4.tryInvert(matrix);

  List<Offset> get corners {
    final Matrix4 m = matrix;
    return <Offset>[
      MatrixUtils.transformPoint(m, Offset.zero),
      MatrixUtils.transformPoint(m, Offset(imageSize.width, 0)),
      MatrixUtils.transformPoint(m, Offset(imageSize.width, imageSize.height)),
      MatrixUtils.transformPoint(m, Offset(0, imageSize.height)),
    ];
  }

  Offset transformPoint(Offset localPoint) =>
      MatrixUtils.transformPoint(matrix, localPoint);

  Offset toLocal(Offset globalPoint) {
    final Matrix4? inverse = inverseMatrix;
    if (inverse == null) {
      return globalPoint;
    }
    return MatrixUtils.transformPoint(inverse, globalPoint);
  }

  Rect get boundingBox {
    final List<Offset> points = corners;
    double minX = points.first.dx;
    double maxX = minX;
    double minY = points.first.dy;
    double maxY = minY;
    for (final Offset point in points.skip(1)) {
      if (point.dx < minX) {
        minX = point.dx;
      }
      if (point.dx > maxX) {
        maxX = point.dx;
      }
      if (point.dy < minY) {
        minY = point.dy;
      }
      if (point.dy > maxY) {
        maxY = point.dy;
      }
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset localHandlePosition(_LayerTransformHandle handle) {
    switch (handle) {
      case _LayerTransformHandle.topLeft:
        return Offset.zero;
      case _LayerTransformHandle.top:
        return Offset(imageSize.width / 2, 0);
      case _LayerTransformHandle.topRight:
        return Offset(imageSize.width, 0);
      case _LayerTransformHandle.right:
        return Offset(imageSize.width, imageSize.height / 2);
      case _LayerTransformHandle.bottomRight:
        return Offset(imageSize.width, imageSize.height);
      case _LayerTransformHandle.bottom:
        return Offset(imageSize.width / 2, imageSize.height);
      case _LayerTransformHandle.bottomLeft:
        return Offset(0, imageSize.height);
      case _LayerTransformHandle.left:
        return Offset(0, imageSize.height / 2);
      case _LayerTransformHandle.translate:
      case _LayerTransformHandle.rotation:
        return pivotLocal;
    }
  }

  Offset handlePosition(_LayerTransformHandle handle) {
    switch (handle) {
      case _LayerTransformHandle.rotation:
        final Offset topLeft = transformPoint(Offset.zero);
        final Offset topRight = transformPoint(Offset(imageSize.width, 0));
        final Offset topCenter = transformPoint(Offset(imageSize.width / 2, 0));
        final Offset edge = topRight - topLeft;
        Offset normal = Offset(edge.dy, -edge.dx);
        final double length = normal.distance;
        if (length > 0.0001) {
          normal = normal / length;
        } else {
          normal = const Offset(0, -1);
        }
        return topCenter + normal * _kLayerTransformRotationHandleDistance;
      case _LayerTransformHandle.translate:
        return translation + pivotLocal;
      default:
        return transformPoint(localHandlePosition(handle));
    }
  }

  void reset() {
    translation = baseTranslation;
    rotation = 0.0;
    scaleX = 1.0;
    scaleY = 1.0;
  }
}

class _LayerTransformRenderResult {
  const _LayerTransformRenderResult({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int left;
  final int top;
  final int width;
  final int height;
  final Uint8List rgba;
}

class _LayerTransformOverlayPainter extends CustomPainter {
  _LayerTransformOverlayPainter({
    required this.state,
    required this.boardScale,
    required this.lineColor,
    required this.highlightColor,
    required this.revision,
    this.activeHandle,
    this.hoverHandle,
  });

  final _LayerTransformStateModel state;
  final double boardScale;
  final Color lineColor;
  final Color highlightColor;
  final int revision;
  final _LayerTransformHandle? activeHandle;
  final _LayerTransformHandle? hoverHandle;

  @override
  void paint(Canvas canvas, Size size) {
    final List<Offset> points = state.corners;
    if (points.length != 4) {
      return;
    }
    final Paint outlinePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / boardScale
      ..isAntiAlias = true;
    final Path path = Path()..addPolygon(points, true);
    canvas.drawPath(path, outlinePaint);

    final double handleSize = (_kLayerTransformHandleVisualSize / boardScale)
        .clamp(6.0, 24.0);
    final Paint handlePaint = Paint()..isAntiAlias = true;
    for (final _LayerTransformHandle handle in _LayerTransformHandle.values) {
      if (handle == _LayerTransformHandle.translate ||
          handle == _LayerTransformHandle.rotation) {
        continue;
      }
      final Offset position = state.handlePosition(handle);
      final bool isActive = handle == activeHandle;
      final bool isHover = handle == hoverHandle;
      handlePaint.color = isActive || isHover ? highlightColor : lineColor;
      final Rect rect = Rect.fromCenter(
        center: position,
        width: handleSize,
        height: handleSize,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(handleSize / 4)),
        handlePaint,
      );
    }

    // Rotation handle
    final Offset rotateHandle = state.handlePosition(
      _LayerTransformHandle.rotation,
    );
    final Offset topCenter = state.handlePosition(_LayerTransformHandle.top);
    final Paint rotationPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / boardScale
      ..isAntiAlias = true;
    canvas.drawLine(topCenter, rotateHandle, rotationPaint);
    final Paint rotationFill = Paint()
      ..color =
          (activeHandle == _LayerTransformHandle.rotation ||
              hoverHandle == _LayerTransformHandle.rotation)
          ? highlightColor
          : lineColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(
      rotateHandle,
      (_kLayerTransformRotationHandleRadius / boardScale).clamp(3.0, 18.0),
      rotationFill,
    );
  }

  @override
  bool shouldRepaint(covariant _LayerTransformOverlayPainter oldDelegate) {
    return oldDelegate.revision != revision ||
        oldDelegate.boardScale != boardScale ||
        oldDelegate.activeHandle != activeHandle ||
        oldDelegate.hoverHandle != hoverHandle ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.highlightColor != highlightColor;
  }
}

mixin _PaintingBoardLayerTransformMixin on _PaintingBoardBase {
  bool _layerTransformModeActive = false;
  _LayerTransformStateModel? _layerTransformState;
  _LayerTransformHandle? _activeLayerTransformHandle;
  _LayerTransformHandle? _hoverLayerTransformHandle;
  Offset? _layerTransformPointerStartBoard;
  Offset? _layerTransformInitialTranslation;
  double _layerTransformInitialRotation = 0.0;
  double _layerTransformInitialScaleX = 1.0;
  double _layerTransformInitialScaleY = 1.0;
  Matrix4? _layerTransformPointerStartInverse;
  Offset? _layerTransformHandleAnchorLocal;
  Offset _layerTransformPanelOffset = Offset.zero;
  Size _layerTransformPanelSize = const Size(
    _kLayerTransformPanelWidth,
    _kLayerTransformPanelMinHeight,
  );
  bool _layerTransformApplying = false;
  int _layerTransformRevision = 0;
  Offset? _layerTransformCursorWorkspacePosition;
  _LayerTransformHandle? _layerTransformCursorHandle;

  bool get _isLayerFreeTransformActive =>
      _layerTransformModeActive && _layerTransformState != null;

  bool get _layerTransformCursorVisible =>
      _isLayerFreeTransformActive &&
      _layerTransformCursorWorkspacePosition != null &&
      _layerTransformCursorHandle != null;

  bool get _shouldHideCursorForLayerTransform => _layerTransformCursorVisible;

  void toggleLayerFreeTransform() {
    if (_layerTransformModeActive) {
      _cancelLayerFreeTransform();
    } else {
      _startLayerFreeTransform();
    }
  }

  bool _maybeInitializeLayerTransformStateFromController() {
    if (!_layerTransformModeActive || _layerTransformState != null) {
      return false;
    }
    final ui.Image? image = _controller.activeLayerTransformImage;
    final Rect? bounds = _controller.activeLayerTransformBounds;
    final Offset origin = _controller.activeLayerTransformOrigin;
    if (image == null || bounds == null || bounds.isEmpty) {
      return false;
    }
    setState(() {
      _layerTransformState = _LayerTransformStateModel(
        image: image,
        bounds: bounds,
        imageOrigin: origin,
      );
    });
    return true;
  }

  BitmapLayerState? _activeLayerSnapshot() {
    final String? activeId = _controller.activeLayerId;
    if (activeId == null) {
      return null;
    }
    for (final BitmapLayerState layer in _controller.layers) {
      if (layer.id == activeId) {
        return layer;
      }
    }
    return null;
  }

  bool _guardTransformInProgress({String? message}) {
    if (!_layerTransformModeActive) {
      return false;
    }
    if (message != null) {
      AppNotifications.show(
        context,
        message: message,
        severity: InfoBarSeverity.warning,
      );
    }
    return true;
  }

  void _startLayerFreeTransform() {
    if (_layerTransformModeActive ||
        _controller.isActiveLayerTransformPendingCleanup) {
      return;
    }
    final BitmapLayerState? activeLayer = _activeLayerSnapshot();
    if (activeLayer == null) {
      AppNotifications.show(
        context,
        message: '无法定位当前图层。',
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    if (activeLayer.locked) {
      AppNotifications.show(
        context,
        message: '当前图层已锁定，无法变换。',
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    if (!_controller.isActiveLayerTransforming) {
      _controller.translateActiveLayer(0, 0);
    }
    if (!_controller.isActiveLayerTransforming) {
      AppNotifications.show(
        context,
        message: '无法进入自由变换模式。',
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    setState(() {
      _layerTransformModeActive = true;
      _layerTransformState = null;
      _activeLayerTransformHandle = null;
      _hoverLayerTransformHandle = null;
      _layerTransformPointerStartBoard = null;
      _layerTransformInitialTranslation = null;
      _layerTransformInitialRotation = 0.0;
      _layerTransformInitialScaleX = 1.0;
      _layerTransformInitialScaleY = 1.0;
      _layerTransformPointerStartInverse = null;
      _layerTransformHandleAnchorLocal = null;
      _layerTransformApplying = false;
      _layerTransformRevision = 0;
      _layerTransformCursorWorkspacePosition = null;
      _layerTransformCursorHandle = null;
      _layerTransformPanelOffset = _workspacePanelSpawnOffset(
        this,
        panelWidth: _kLayerTransformPanelWidth,
        panelHeight: _kLayerTransformPanelMinHeight,
        additionalDy: 12,
      );
    });
    _toolCursorPosition = null;
    _penCursorWorkspacePosition = null;
    _maybeInitializeLayerTransformStateFromController();
  }

  void _cancelLayerFreeTransform() {
    if (!_layerTransformModeActive || _layerTransformApplying) {
      return;
    }
    _controller.cancelActiveLayerTranslation();
    setState(() {
      _layerTransformModeActive = false;
      _layerTransformState = null;
      _activeLayerTransformHandle = null;
      _hoverLayerTransformHandle = null;
      _layerTransformApplying = false;
      _layerTransformPointerStartInverse = null;
      _layerTransformHandleAnchorLocal = null;
      _layerTransformRevision = 0;
      _layerTransformCursorWorkspacePosition = null;
      _layerTransformCursorHandle = null;
    });
  }

  Future<void> _confirmLayerFreeTransform() async {
    if (!_isLayerFreeTransformActive || _layerTransformApplying) {
      return;
    }
    final BitmapLayerState? activeLayer = _activeLayerSnapshot();
    final _LayerTransformStateModel? state = _layerTransformState;
    if (activeLayer == null || state == null) {
      return;
    }
    setState(() => _layerTransformApplying = true);
    try {
      final _LayerTransformRenderResult result =
          await _renderLayerTransformResult(state);
      final _CanvasHistoryEntry? undoEntry =
          await _buildLayerTransformUndoEntry(state);
      await _pushUndoSnapshot(entry: undoEntry);
      final CanvasLayerData data = CanvasLayerData(
        id: activeLayer.id,
        name: activeLayer.name,
        visible: activeLayer.visible,
        opacity: activeLayer.opacity,
        locked: activeLayer.locked,
        clippingMask: activeLayer.clippingMask,
        blendMode: activeLayer.blendMode,
        bitmap: result.rgba,
        bitmapWidth: result.width,
        bitmapHeight: result.height,
        bitmapLeft: result.left,
        bitmapTop: result.top,
        cloneBitmap: false,
      );
      _controller.replaceLayer(activeLayer.id, data);
      _controller.disposeActiveLayerTransformSession();
      await _waitForLayerTransformComposite();
      if (!mounted) {
        return;
      }
      setState(() {
        _layerTransformModeActive = false;
        _layerTransformState = null;
        _activeLayerTransformHandle = null;
        _hoverLayerTransformHandle = null;
        _layerTransformApplying = false;
        _layerTransformPointerStartInverse = null;
        _layerTransformHandleAnchorLocal = null;
        _layerTransformRevision = 0;
        _layerTransformCursorWorkspacePosition = null;
        _layerTransformCursorHandle = null;
      });
      _markDirty();
    } catch (error, stackTrace) {
      debugPrint('Failed to apply transform: $error\n$stackTrace');
      setState(() => _layerTransformApplying = false);
      AppNotifications.show(
        context,
        message: '应用自由变换失败，请重试。',
        severity: InfoBarSeverity.error,
      );
    }
  }

  // 捕获自由变换前的图层内容，确保撤销记录包含原始像素。
  Future<_CanvasHistoryEntry?> _buildLayerTransformUndoEntry(
    _LayerTransformStateModel state,
  ) async {
    final BitmapLayerState? activeLayer = _activeLayerSnapshot();
    if (activeLayer == null) {
      return null;
    }
    final _CanvasHistoryEntry entry = await _createHistoryEntry();
    final String? activeLayerId = entry.activeLayerId;
    if (activeLayerId == null) {
      return entry;
    }
    final int index = entry.layers.indexWhere(
      (CanvasLayerData layer) => layer.id == activeLayerId,
    );
    if (index < 0) {
      return entry;
    }
    final ByteData? byteData = await state.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      return entry;
    }
    final Uint8List rgba = Uint8List.fromList(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
    );
    entry.layers[index] = CanvasLayerData(
      id: activeLayer.id,
      name: activeLayer.name,
      visible: activeLayer.visible,
      opacity: activeLayer.opacity,
      locked: activeLayer.locked,
      clippingMask: activeLayer.clippingMask,
      blendMode: activeLayer.blendMode,
      bitmap: rgba,
      bitmapWidth: state.image.width,
      bitmapHeight: state.image.height,
      bitmapLeft: state.imageOrigin.dx.round(),
      bitmapTop: state.imageOrigin.dy.round(),
      cloneBitmap: false,
    );
    return entry;
  }

  Future<void> _waitForLayerTransformComposite() async {
    final Completer<void> completer = Completer<void>();
    bool completed = false;
    void listener() {
      if (completed) {
        return;
      }
      completed = true;
      _controller.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    _controller.addListener(listener);
    try {
      await completer.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {
          if (!completed) {
            completed = true;
            _controller.removeListener(listener);
          }
        },
      );
    } finally {
      if (!completed) {
        _controller.removeListener(listener);
      }
    }

    final SchedulerBinding scheduler = SchedulerBinding.instance;
    await scheduler.endOfFrame;
  }

  Future<_LayerTransformRenderResult> _renderLayerTransformResult(
    _LayerTransformStateModel state,
  ) async {
    final Rect bounds = state.boundingBox;
    final int left = bounds.left.floor();
    final int top = bounds.top.floor();
    final int right = bounds.right.ceil();
    final int bottom = bounds.bottom.ceil();
    final int width = math.max(1, right - left);
    final int height = math.max(1, bottom - top);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Matrix4 drawMatrix = Matrix4.translationValues(
      -left.toDouble(),
      -top.toDouble(),
      0.0,
    )..multiply(state.matrix);
    canvas.transform(drawMatrix.storage);
    final Paint paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = false;
    final Rect localBounds = Rect.fromLTWH(
      0.0,
      0.0,
      state.imageSize.width,
      state.imageSize.height,
    );
    canvas.save();
    canvas.clipRect(localBounds);
    canvas.translate(-state.clipOffset.dx, -state.clipOffset.dy);
    canvas.drawImage(state.image, Offset.zero, paint);
    canvas.restore();
    final ui.Picture picture = recorder.endRecording();
    final ui.Image rendered = await picture.toImage(width, height);
    picture.dispose();
    final ByteData? byteData = await rendered.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    rendered.dispose();
    if (byteData == null) {
      throw StateError('无法导出自由变换结果');
    }
    final Uint8List rgba = byteData.buffer.asUint8List();
    return _LayerTransformRenderResult(
      left: left,
      top: top,
      width: width,
      height: height,
      rgba: rgba,
    );
  }

  void _handleLayerTransformPointerDown(Offset boardLocal) {
    if (!_isLayerFreeTransformActive) {
      return;
    }
    final _LayerTransformStateModel? state = _layerTransformState;
    if (state == null) {
      return;
    }
    final _LayerTransformHandle? handle = _hitTestLayerTransformHandles(
      boardLocal,
    );
    if (handle == null) {
      _activeLayerTransformHandle = null;
      return;
    }
    final Matrix4? inverse = state.inverseMatrix;
    _activeLayerTransformHandle = handle;
    _layerTransformPointerStartBoard = boardLocal;
    _layerTransformInitialTranslation = state.translation;
    _layerTransformInitialRotation = state.rotation;
    _layerTransformInitialScaleX = state.scaleX;
    _layerTransformInitialScaleY = state.scaleY;
    _layerTransformPointerStartInverse = inverse;
    _layerTransformHandleAnchorLocal = state.localHandlePosition(handle);
    _updateLayerTransformCursor(boardLocal, handle);
  }

  void _handleLayerTransformPointerMove(Offset boardLocal) {
    if (!_isLayerFreeTransformActive) {
      return;
    }
    final _LayerTransformStateModel? state = _layerTransformState;
    final _LayerTransformHandle? handle = _activeLayerTransformHandle;
    if (state == null) {
      return;
    }
    if (handle == null) {
      _updateLayerTransformHover(boardLocal);
      return;
    }
    _updateLayerTransformCursor(boardLocal, handle);
    switch (handle) {
      case _LayerTransformHandle.translate:
        final Offset? start = _layerTransformPointerStartBoard;
        final Offset? initial = _layerTransformInitialTranslation;
        if (start == null || initial == null) {
          return;
        }
        final Offset delta = boardLocal - start;
        setState(() {
          state.translation = initial + delta;
          _layerTransformRevision++;
        });
        break;
      case _LayerTransformHandle.rotation:
        final Offset pivot = state.translation + state.pivotLocal;
        final Offset? start = _layerTransformPointerStartBoard;
        if (start == null) {
          return;
        }
        double startAngle = math.atan2(
          start.dy - pivot.dy,
          start.dx - pivot.dx,
        );
        double currentAngle = math.atan2(
          boardLocal.dy - pivot.dy,
          boardLocal.dx - pivot.dx,
        );
        double delta = currentAngle - startAngle;
        if (_isShiftModifierPressed()) {
          const double step = math.pi / 12;
          delta = (delta / step).round() * step;
        }
        setState(() {
          state.rotation = _layerTransformInitialRotation + delta;
          _layerTransformRevision++;
        });
        break;
      default:
        final Matrix4? inverse = _layerTransformPointerStartInverse;
        final Offset? anchorLocal = _layerTransformHandleAnchorLocal;
        if (inverse == null || anchorLocal == null) {
          return;
        }
        final Offset localPoint = MatrixUtils.transformPoint(
          inverse,
          boardLocal,
        );
        double nextScaleX = state.scaleX;
        double nextScaleY = state.scaleY;
        bool affectX = false;
        bool affectY = false;
        Offset handleLocal = anchorLocal;
        switch (handle) {
          case _LayerTransformHandle.top:
          case _LayerTransformHandle.bottom:
            affectY = true;
            break;
          case _LayerTransformHandle.left:
          case _LayerTransformHandle.right:
            affectX = true;
            break;
          default:
            affectX = true;
            affectY = true;
            break;
        }
        final double baseDx = handleLocal.dx - state.pivotLocal.dx;
        final double baseDy = handleLocal.dy - state.pivotLocal.dy;
        if (affectX && baseDx.abs() > 0.0001) {
          final double currentDx = localPoint.dx - state.pivotLocal.dx;
          nextScaleX = (currentDx / baseDx) * _layerTransformInitialScaleX;
        }
        if (affectY && baseDy.abs() > 0.0001) {
          final double currentDy = localPoint.dy - state.pivotLocal.dy;
          nextScaleY = (currentDy / baseDy) * _layerTransformInitialScaleY;
        }
        if (_isShiftModifierPressed()) {
          final double uniform = affectX && affectY
              ? (nextScaleX + nextScaleY) / 2
              : affectX
              ? nextScaleX
              : nextScaleY;
          if (affectX) {
            nextScaleX = uniform;
          }
          if (affectY) {
            nextScaleY = uniform;
          }
        }
        nextScaleX = nextScaleX.clamp(
          _kLayerTransformMinScale,
          _kLayerTransformMaxScale,
        );
        nextScaleY = nextScaleY.clamp(
          _kLayerTransformMinScale,
          _kLayerTransformMaxScale,
        );
        setState(() {
          state.scaleX = nextScaleX;
          state.scaleY = nextScaleY;
          _layerTransformRevision++;
        });
        break;
    }
  }

  void _handleLayerTransformPointerUp() {
    _activeLayerTransformHandle = null;
    _layerTransformPointerStartInverse = null;
    _layerTransformHandleAnchorLocal = null;
  }

  void _handleLayerTransformPointerCancel() {
    _activeLayerTransformHandle = null;
    _layerTransformPointerStartInverse = null;
    _layerTransformHandleAnchorLocal = null;
    _updateLayerTransformCursor(null, null);
  }

  void _updateLayerTransformHover(Offset boardLocal) {
    final _LayerTransformHandle? handle = _hitTestLayerTransformHandles(
      boardLocal,
    );
    if (handle == _hoverLayerTransformHandle) {
      _updateLayerTransformCursor(boardLocal, handle);
      return;
    }
    setState(() {
      _hoverLayerTransformHandle = handle;
    });
    _updateLayerTransformCursor(boardLocal, handle);
  }

  void _updateLayerTransformCursor(
    Offset? boardLocal,
    _LayerTransformHandle? handle,
  ) {
    final bool shouldShow =
        _isLayerFreeTransformActive &&
        boardLocal != null &&
        handle != null &&
        handle != _LayerTransformHandle.translate;
    final Offset? nextPosition = shouldShow
        ? _boardRect.topLeft +
              Offset(
                boardLocal.dx * _viewport.scale,
                boardLocal.dy * _viewport.scale,
              )
        : null;
    final _LayerTransformHandle? nextHandle = shouldShow ? handle : null;
    if (_layerTransformCursorHandle == nextHandle &&
        _offsetEquals(_layerTransformCursorWorkspacePosition, nextPosition)) {
      return;
    }
    setState(() {
      _layerTransformCursorWorkspacePosition = nextPosition;
      _layerTransformCursorHandle = nextHandle;
    });
  }

  bool _offsetEquals(Offset? a, Offset? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null) {
      return a == b;
    }
    return (a - b).distanceSquared < 0.25;
  }

  @override
  void _clearLayerTransformCursorIndicator() {
    if (_layerTransformCursorWorkspacePosition == null &&
        _layerTransformCursorHandle == null) {
      return;
    }
    setState(() {
      _layerTransformCursorWorkspacePosition = null;
      _layerTransformCursorHandle = null;
    });
  }

  _LayerTransformHandle? _hitTestLayerTransformHandles(Offset boardLocal) {
    final _LayerTransformStateModel? state = _layerTransformState;
    if (state == null) {
      return null;
    }
    final double hitRadius = (_kLayerTransformHandleHitSize / _viewport.scale)
        .clamp(8.0, 48.0);
    final List<Offset> corners = state.corners;
    _LayerTransformHandle? pickHandle(_LayerTransformHandle handle) {
      if (handle == _LayerTransformHandle.translate) {
        return null;
      }
      if (handle == _LayerTransformHandle.rotation) {
        final Offset position = state.handlePosition(handle);
        if ((boardLocal - position).distance <= hitRadius) {
          return handle;
        }
        return null;
      }
      final Offset position = state.handlePosition(handle);
      if ((boardLocal - position).distance <= hitRadius) {
        return handle;
      }
      return null;
    }

    for (final _LayerTransformHandle handle in <_LayerTransformHandle>[
      _LayerTransformHandle.topLeft,
      _LayerTransformHandle.top,
      _LayerTransformHandle.topRight,
      _LayerTransformHandle.right,
      _LayerTransformHandle.bottomRight,
      _LayerTransformHandle.bottom,
      _LayerTransformHandle.bottomLeft,
      _LayerTransformHandle.left,
      _LayerTransformHandle.rotation,
    ]) {
      final _LayerTransformHandle? result = pickHandle(handle);
      if (result != null) {
        return result;
      }
    }

    final Path polygon = Path()..addPolygon(corners, true);
    if (polygon.contains(boardLocal)) {
      return _LayerTransformHandle.translate;
    }
    final double distance = _distanceToPolygon(boardLocal, corners);
    final double baseRadius = math.max(
      _kLayerTransformHandleHitSize * 2.4,
      _kLayerTransformRotationHandleDistance * 1.1,
    );
    final double rotationHitRadius = (baseRadius / _viewport.scale).clamp(
      24.0,
      96.0,
    );
    if (distance <= rotationHitRadius) {
      return _LayerTransformHandle.rotation;
    }
    return null;
  }

  double _distanceToPolygon(Offset point, List<Offset> polygon) {
    double minDistance = double.infinity;
    for (int i = 0; i < polygon.length; i++) {
      final Offset a = polygon[i];
      final Offset b = polygon[(i + 1) % polygon.length];
      final double distance = _distanceToSegment(point, a, b);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance;
  }

  double _distanceToSegment(Offset point, Offset a, Offset b) {
    final Offset ab = b - a;
    final double lengthSquared = ab.distanceSquared;
    if (lengthSquared <= 1e-6) {
      return (point - a).distance;
    }
    double t =
        ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / lengthSquared;
    t = t.clamp(0.0, 1.0);
    final Offset projection = a + ab * t;
    return (point - projection).distance;
  }

  bool _isShiftModifierPressed() {
    final Set<LogicalKeyboardKey> keys =
        HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight) ||
        keys.contains(LogicalKeyboardKey.shift);
  }

  Widget? buildLayerTransformImageOverlay() {
    if (!_isLayerFreeTransformActive) {
      return null;
    }
    final _LayerTransformStateModel? state = _layerTransformState;
    if (state == null) {
      return null;
    }
    final double opacity = _controller.activeLayerTransformOpacity;
    final ui.BlendMode? blendMode = _flutterBlendMode(
      _controller.activeLayerTransformBlendMode,
    );
    Widget content = RawImage(
      image: state.image,
      filterQuality: FilterQuality.high,
      fit: BoxFit.none,
      alignment: Alignment.topLeft,
      colorBlendMode: blendMode,
      color: blendMode != null ? Colors.white : null,
    );
    if (opacity < 0.999) {
      content = Opacity(opacity: opacity.clamp(0.0, 1.0), child: content);
    }
    content = SizedBox(
      width: state.imageSize.width,
      height: state.imageSize.height,
      child: ClipRect(
        child: Transform.translate(
          offset: -state.clipOffset,
          child: SizedBox(
            width: state.fullImageSize.width,
            height: state.fullImageSize.height,
            child: content,
          ),
        ),
      ),
    );
    return IgnorePointer(
      ignoring: true,
      child: Transform(
        alignment: Alignment.topLeft,
        transform: state.matrix,
        child: SizedBox(
          width: state.imageSize.width,
          height: state.imageSize.height,
          child: content,
        ),
      ),
    );
  }

  Widget? buildLayerTransformHandlesOverlay(FluentThemeData theme) {
    if (!_isLayerFreeTransformActive) {
      return null;
    }
    final _LayerTransformStateModel? state = _layerTransformState;
    if (state == null) {
      return null;
    }
    final Color lineColor = theme.resources.textFillColorSecondary;
    final Color highlightColor = theme.accentColor.defaultBrushFor(
      theme.brightness,
    );
    return IgnorePointer(
      ignoring: true,
      child: CustomPaint(
        size: _canvasSize,
        painter: _LayerTransformOverlayPainter(
          state: state,
          boardScale: _viewport.scale,
          lineColor: lineColor,
          highlightColor: highlightColor,
          revision: _layerTransformRevision,
          activeHandle: _activeLayerTransformHandle,
          hoverHandle: _hoverLayerTransformHandle,
        ),
      ),
    );
  }

  Widget? buildLayerTransformCursorOverlay(FluentThemeData theme) {
    if (!_layerTransformCursorVisible) {
      return null;
    }
    final Offset? position = _layerTransformCursorWorkspacePosition;
    final _LayerTransformHandle? handle = _layerTransformCursorHandle;
    if (position == null || handle == null) {
      return null;
    }
    final bool isActive = _activeLayerTransformHandle == handle;
    final bool isHover =
        _activeLayerTransformHandle == null &&
        _hoverLayerTransformHandle == handle;
    final Color color = (isActive || isHover)
        ? theme.resources.textFillColorPrimary
        : theme.resources.textFillColorSecondary;
    final Color outlineColor = theme.brightness.isDark
        ? Colors.black
        : Colors.white;
    if (handle == _LayerTransformHandle.rotation) {
      const double indicatorSize = 20;
      return Positioned(
        left: position.dx - indicatorSize / 2,
        top: position.dy - indicatorSize / 2,
        child: IgnorePointer(
          ignoring: true,
          child: ToolCursorStyles.buildOutlinedIcon(
            icon: FluentIcons.sync,
            size: indicatorSize,
            outlineColor: outlineColor,
            fillColor: color,
          ),
        ),
      );
    }
    final double? angle = _layerTransformCursorAngle(handle);
    if (angle == null) {
      return null;
    }
    const double indicatorSize = _ResizeHandleIndicator.size;
    return Positioned(
      left: position.dx - indicatorSize / 2,
      top: position.dy - indicatorSize / 2,
      child: IgnorePointer(
        ignoring: true,
        child: _ResizeHandleIndicator(
          angle: angle,
          color: color,
          outlineColor: outlineColor,
        ),
      ),
    );
  }

  double? _layerTransformCursorAngle(_LayerTransformHandle handle) {
    switch (handle) {
      case _LayerTransformHandle.top:
        return -math.pi / 2;
      case _LayerTransformHandle.bottom:
        return math.pi / 2;
      case _LayerTransformHandle.left:
        return math.pi;
      case _LayerTransformHandle.right:
        return 0;
      case _LayerTransformHandle.topLeft:
        return -3 * math.pi / 4;
      case _LayerTransformHandle.topRight:
        return -math.pi / 4;
      case _LayerTransformHandle.bottomRight:
        return math.pi / 4;
      case _LayerTransformHandle.bottomLeft:
        return 3 * math.pi / 4;
      default:
        return null;
    }
  }

  Widget? buildLayerTransformPanel() {
    if (!_layerTransformModeActive) {
      return null;
    }
    final _LayerTransformStateModel? state = _layerTransformState;
    final bool ready = state != null;
    final FluentThemeData theme = FluentTheme.of(context);
    return Positioned(
      left: _layerTransformPanelOffset.dx,
      top: _layerTransformPanelOffset.dy,
      child: MeasuredSize(
        onChanged: _handleLayerTransformPanelSizeChanged,
        child: WorkspaceFloatingPanel(
          width: _kLayerTransformPanelWidth,
          minHeight: _kLayerTransformPanelMinHeight,
          title: '自由变换',
          onDragUpdate: _updateLayerTransformPanelOffset,
          onClose: _cancelLayerFreeTransform,
          footerPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          footer: Row(
            children: [
              Button(
                onPressed: ready && !_layerTransformApplying
                    ? () {
                        setState(() {
                          state.reset();
                          _layerTransformRevision++;
                        });
                      }
                    : null,
                child: const Text('复位'),
              ),
              const Spacer(),
              Button(
                onPressed: _layerTransformApplying
                    ? null
                    : _cancelLayerFreeTransform,
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: ready && !_layerTransformApplying
                    ? () => _confirmLayerFreeTransform()
                    : null,
                child: _layerTransformApplying
                    ? const ProgressRing()
                    : const Text('应用'),
              ),
            ],
          ),
          child: ready
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '旋转：${(state.rotation * 180 / math.pi).toStringAsFixed(1)}°',
                      style: theme.typography.body,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '缩放：${(state.scaleX * 100).toStringAsFixed(1)}% × '
                      '${(state.scaleY * 100).toStringAsFixed(1)}%',
                      style: theme.typography.body,
                    ),
                  ],
                )
              : Row(
                  children: const [
                    ProgressRing(),
                    SizedBox(width: 8),
                    Text('正在准备图层…'),
                  ],
                ),
        ),
      ),
    );
  }

  void _updateLayerTransformPanelOffset(Offset delta) {
    setState(() {
      final Offset next = _layerTransformPanelOffset + delta;
      final double maxX = math.max(
        16,
        _workspaceSize.width - _layerTransformPanelSize.width - 16,
      );
      final double maxY = math.max(
        16,
        _workspaceSize.height - _layerTransformPanelSize.height - 16,
      );
      _layerTransformPanelOffset = Offset(
        next.dx.clamp(16.0, maxX),
        next.dy.clamp(16.0, maxY),
      );
    });
  }

  void _handleLayerTransformPanelSizeChanged(Size size) {
    if (size.isEmpty) {
      return;
    }
    setState(() {
      _layerTransformPanelSize = size;
    });
  }
}
