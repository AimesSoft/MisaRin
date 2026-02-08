part of 'painting_board.dart';

const int _kEllipseSegments = 64;
const double _kEquilateralHeightFactor = 0.8660254037844386; // sqrt(3) / 2

mixin _PaintingBoardShapeMixin on _PaintingBoardBase {
  ShapeToolVariant _shapeToolVariant = ShapeToolVariant.rectangle;
  Offset? _shapeDragStart;
  Offset? _shapeDragCurrent;
  Path? _shapePreviewPath;
  List<Offset> _shapeStrokePoints = <Offset>[];
  CanvasLayerData? _shapeRasterPreviewSnapshot;
  bool _shapeUndoCapturedForPreview = false;
  Rect? _shapePreviewDirtyRect;
  Uint32List? _shapeRasterPreviewPixels;

  ShapeToolVariant get shapeToolVariant => _shapeToolVariant;

  Path? get shapePreviewPath => _shapePreviewPath;

  void _updateShapeToolVariant(ShapeToolVariant variant) {
    if (_shapeToolVariant == variant) {
      return;
    }
    setState(() {
      _shapeToolVariant = variant;
    });
  }

  void _updateShapeFillEnabled(bool value) {
    if (_shapeFillEnabled == value) {
      return;
    }
    setState(() {
      _shapeFillEnabled = value;
    });
    final AppPreferences prefs = AppPreferences.instance;
    prefs.shapeToolFillEnabled = value;
    unawaited(AppPreferences.save());
  }

  void _resetShapeDrawingState() {
    _shapeDragStart = null;
    _shapeDragCurrent = null;
    _shapePreviewPath = null;
    _shapeStrokePoints = <Offset>[];
    _shapePreviewDirtyRect = null;
  }

  Future<void> _beginShapeDrawing(Offset boardLocal) async {
    if (!isPointInsideSelection(boardLocal)) {
      return;
    }
    _resetPerspectiveLock();
    final bool useRustCanvas = _canUseRustCanvasEngine();
    if (useRustCanvas && !await _syncActiveLayerPixelsFromRust()) {
      _showRustCanvasMessage('Rust 画布同步图层失败。');
      return;
    }
    await _prepareShapeRasterPreview(captureUndo: !useRustCanvas);
    final Offset clamped = _clampToCanvas(boardLocal);
    setState(() {
      _shapeDragStart = clamped;
      _shapeDragCurrent = clamped;
      _shapeStrokePoints = <Offset>[];
      _shapePreviewPath = _buildShapePreviewPath(
        start: clamped,
        current: clamped,
        variant: _shapeToolVariant,
      );
    });
  }

  void _updateShapeDrawing(Offset boardLocal) {
    final Offset? start = _shapeDragStart;
    if (start == null) {
      return;
    }
    final Offset rawCurrent = _clampToCanvas(boardLocal);
    Offset current = rawCurrent;
    if (_isShapeShiftPressed) {
      current = _applyShiftConstraint(
        start: start,
        current: rawCurrent,
        variant: _shapeToolVariant,
      );
      current = _clampToCanvas(current);
    }
    current = _clampToCanvas(
      _maybeSnapToPerspective(current, anchor: start),
    );

    if (_shapeDragCurrent != null &&
        (_shapeDragCurrent! - current).distanceSquared < 0.25) {
      return;
    }
    _shapeDragCurrent = current;
    final List<Offset> strokePoints = _buildShapeStrokePoints(
      start: start,
      current: current,
      variant: _shapeToolVariant,
    );
    final Path preview = _buildShapePreviewPath(
      start: start,
      current: current,
      variant: _shapeToolVariant,
    );
    setState(() {
      _shapeStrokePoints = strokePoints;
      _shapePreviewPath = preview;
    });
    _refreshShapeRasterPreview(strokePoints);
  }

  Future<void> _finishShapeDrawing() async {
    final List<Offset> strokePoints = _shapeStrokePoints;
    _shapeDragCurrent = null;
    _resetPerspectiveLock();
    if (strokePoints.length < 2) {
      _disposeShapeRasterPreview(restoreLayer: true);
      _resetShapeDrawingState();
      return;
    }

    final bool useRustCanvas = _canUseRustCanvasEngine();
    if (!_shapeUndoCapturedForPreview && !useRustCanvas) {
      await _pushUndoSnapshot();
    }
    const double initialTimestamp = 0.0;
    _clearShapePreviewOverlay();
    if (useRustCanvas && !await _syncActiveLayerPixelsFromRust()) {
      _showRustCanvasMessage('Rust 画布同步图层失败。');
      _disposeShapeRasterPreview(restoreLayer: true);
      setState(_resetShapeDrawingState);
      return;
    }
    _controller.runSynchronousRasterization(() {
      _paintShapeStroke(strokePoints, initialTimestamp);
    });
    _disposeShapeRasterPreview(
      restoreLayer: false,
      clearPreviewImage: !useRustCanvas,
    );
    if (useRustCanvas) {
      await _controller.waitForPendingWorkerTasks();
      if (!await _commitActiveLayerToRust()) {
        _showRustCanvasMessage('Rust 画布写入图层失败。');
      }
      _clearShapePreviewRasterImage(notify: false);
    }

    setState(_resetShapeDrawingState);
  }

  void _cancelShapeDrawing() {
    if (_shapeDragStart == null) {
      return;
    }
    _resetPerspectiveLock();
    _disposeShapeRasterPreview(restoreLayer: true);
    setState(_resetShapeDrawingState);
  }

  bool get _isShapeShiftPressed {
    final Set<LogicalKeyboardKey> keys =
        HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight) ||
        keys.contains(LogicalKeyboardKey.shift);
  }

  List<Offset> _buildShapeStrokePoints({
    required Offset start,
    required Offset current,
    required ShapeToolVariant variant,
  }) {
    final Rect bounds = Rect.fromPoints(start, current);
    switch (variant) {
      case ShapeToolVariant.rectangle:
        if (bounds.width.abs() < 0.5 || bounds.height.abs() < 0.5) {
          return <Offset>[];
        }
        return <Offset>[
          bounds.topLeft,
          bounds.topRight,
          bounds.bottomRight,
          bounds.bottomLeft,
          bounds.topLeft,
        ];
      case ShapeToolVariant.ellipse:
        if (bounds.width.abs() < 0.5 || bounds.height.abs() < 0.5) {
          return <Offset>[];
        }
        final List<Offset> points = <Offset>[];
        final Offset center = bounds.center;
        final double radiusX = bounds.width / 2;
        final double radiusY = bounds.height / 2;
        for (int i = 0; i <= _kEllipseSegments; i++) {
          final double t = (i / _kEllipseSegments) * 2 * math.pi;
          points.add(
            Offset(
              center.dx + radiusX * math.cos(t),
              center.dy + radiusY * math.sin(t),
            ),
          );
        }
        return points;
      case ShapeToolVariant.triangle:
        if (bounds.width.abs() < 0.5 || bounds.height.abs() < 0.5) {
          return <Offset>[];
        }
        final Offset top = Offset(bounds.center.dx, bounds.top);
        final Offset bottomLeft = Offset(bounds.left, bounds.bottom);
        final Offset bottomRight = Offset(bounds.right, bounds.bottom);
        return <Offset>[top, bottomRight, bottomLeft, top];
      case ShapeToolVariant.line:
        if ((start - current).distance < 0.5) {
          return <Offset>[];
        }
        return <Offset>[start, current];
    }
  }

  Path _buildShapePreviewPath({
    required Offset start,
    required Offset current,
    required ShapeToolVariant variant,
  }) {
    final Rect bounds = Rect.fromPoints(start, current);
    switch (variant) {
      case ShapeToolVariant.rectangle:
        return Path()..addRect(bounds);
      case ShapeToolVariant.ellipse:
        return Path()..addOval(bounds);
      case ShapeToolVariant.triangle:
        final Path path = Path();
        path.moveTo(bounds.center.dx, bounds.top);
        path.lineTo(bounds.right, bounds.bottom);
        path.lineTo(bounds.left, bounds.bottom);
        path.close();
        return path;
      case ShapeToolVariant.line:
        final Path path = Path();
        path.moveTo(start.dx, start.dy);
        path.lineTo(current.dx, current.dy);
        return path;
    }
  }

  Offset _applyShiftConstraint({
    required Offset start,
    required Offset current,
    required ShapeToolVariant variant,
  }) {
    switch (variant) {
      case ShapeToolVariant.rectangle:
      case ShapeToolVariant.ellipse:
        return _constrainToSquare(start, current);
      case ShapeToolVariant.triangle:
        return _constrainToEquilateralTriangle(start, current);
      case ShapeToolVariant.line:
        return _constrainLineAngle(start, current);
    }
  }

  Offset _constrainToSquare(Offset start, Offset current) {
    final double dx = current.dx - start.dx;
    final double dy = current.dy - start.dy;
    final double length = math.max(dx.abs(), dy.abs());
    if (length == 0) {
      return current;
    }
    final double signX = dx >= 0 ? 1 : -1;
    final double signY = dy >= 0 ? 1 : -1;
    return Offset(start.dx + length * signX, start.dy + length * signY);
  }

  Offset _constrainToEquilateralTriangle(Offset start, Offset current) {
    final double dx = current.dx - start.dx;
    final double dy = current.dy - start.dy;
    double width = dx.abs();
    double height = dy.abs();
    if (width == 0 && height == 0) {
      return current;
    }

    if (width == 0) {
      width = height / _kEquilateralHeightFactor;
    } else if (height == 0) {
      height = width * _kEquilateralHeightFactor;
    } else if (height > width * _kEquilateralHeightFactor) {
      width = height / _kEquilateralHeightFactor;
    } else {
      height = width * _kEquilateralHeightFactor;
    }

    final double signX = dx >= 0 ? 1 : -1;
    final double signY = dy >= 0 ? 1 : -1;
    return Offset(start.dx + width * signX, start.dy + height * signY);
  }

  Offset _constrainLineAngle(Offset start, Offset current) {
    final double dx = current.dx - start.dx;
    final double dy = current.dy - start.dy;
    final double distance = math.sqrt(dx * dx + dy * dy);
    if (distance == 0) {
      return current;
    }
    const double step = math.pi / 4;
    final double angle = math.atan2(dy, dx);
    final double snappedAngle = (angle / step).round() * step;
    return Offset(
      start.dx + math.cos(snappedAngle) * distance,
      start.dy + math.sin(snappedAngle) * distance,
    );
  }

  Future<void> _prepareShapeRasterPreview({bool captureUndo = true}) async {
    if (_shapeUndoCapturedForPreview) {
      return;
    }
    if (captureUndo) {
      await _pushUndoSnapshot();
    } else {
      _clearShapePreviewRasterImage(notify: false);
    }
    _shapeUndoCapturedForPreview = true;
    final String? activeLayerId = _controller.activeLayerId;
    if (activeLayerId == null) {
      return;
    }
    _shapeRasterPreviewSnapshot = _controller.buildClipboardLayer(
      activeLayerId,
    );
    final CanvasLayerData? snapshot = _shapeRasterPreviewSnapshot;
    if (snapshot != null &&
        snapshot.bitmap != null &&
        snapshot.bitmapWidth != null &&
        snapshot.bitmapHeight != null) {
      _shapeRasterPreviewPixels = BitmapCanvasController.rgbaToPixels(
        snapshot.bitmap!,
        snapshot.bitmapWidth!,
        snapshot.bitmapHeight!,
      );
    } else {
      _shapeRasterPreviewPixels = null;
    }
  }

  void _refreshShapeRasterPreview(List<Offset> strokePoints) {
    final bool useRustCanvas = _canUseRustCanvasEngine();
    final CanvasLayerData? snapshot = _shapeRasterPreviewSnapshot;
    if (snapshot == null || strokePoints.length < 2) {
      _clearShapePreviewOverlay();
      if (useRustCanvas) {
        _clearShapePreviewRasterImage();
      }
      return;
    }
    final Rect? previous = _shapePreviewDirtyRect;
    Rect? restoredRegion;
    if (previous != null) {
      restoredRegion = _controller.restoreLayerRegion(
        snapshot,
        previous,
        pixelCache: _shapeRasterPreviewPixels,
        markDirty: false,
      );
    }
    final Rect? dirty = _shapePreviewBoundsForPoints(strokePoints);
    if (dirty == null) {
      _shapePreviewDirtyRect = null;
      if (restoredRegion != null) {
        _controller.markLayerRegionDirty(snapshot.id, restoredRegion);
      }
      return;
    }
    _shapePreviewDirtyRect = dirty;
    _controller.runSynchronousRasterization(() {
      _paintShapeStroke(strokePoints, 0.0);
    });
    if (restoredRegion != null) {
      _controller.markLayerRegionDirty(snapshot.id, restoredRegion);
    }
    if (useRustCanvas) {
      unawaited(_updateShapePreviewRasterImage());
    }
  }

  void _disposeShapeRasterPreview({
    required bool restoreLayer,
    bool clearPreviewImage = true,
  }) {
    final CanvasLayerData? snapshot = _shapeRasterPreviewSnapshot;
    if (snapshot != null && restoreLayer) {
      _clearShapePreviewOverlay();
    }
    _shapeRasterPreviewSnapshot = null;
    _shapeUndoCapturedForPreview = false;
    _shapeRasterPreviewPixels = null;
    if (clearPreviewImage) {
      _clearShapePreviewRasterImage(notify: false);
    }
  }

  void _clearShapePreviewOverlay() {
    final CanvasLayerData? snapshot = _shapeRasterPreviewSnapshot;
    final Rect? dirty = _shapePreviewDirtyRect;
    if (snapshot == null || dirty == null) {
      _shapePreviewDirtyRect = null;
      return;
    }
    _controller.restoreLayerRegion(
      snapshot,
      dirty,
      pixelCache: _shapeRasterPreviewPixels,
    );
    _shapePreviewDirtyRect = null;
  }

  Future<void> _updateShapePreviewRasterImage() async {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    if (_shapePreviewPath == null) {
      _clearShapePreviewRasterImage();
      return;
    }
    final BitmapLayerState layer = _controller.activeLayer;
    if (!layer.visible) {
      _clearShapePreviewRasterImage();
      return;
    }
    final int width = layer.surface.width;
    final int height = layer.surface.height;
    if (width <= 0 || height <= 0) {
      _clearShapePreviewRasterImage();
      return;
    }
    final int token = ++_shapePreviewRasterToken;
    await _controller.waitForPendingWorkerTasks();
    if (!mounted ||
        token != _shapePreviewRasterToken ||
        _shapePreviewPath == null) {
      return;
    }
    final Uint32List pixels = layer.surface.pixels;
    if (pixels.length != width * height) {
      _clearShapePreviewRasterImage();
      return;
    }
    final Uint8List rgba = _argbPixelsToRgbaForPreview(pixels);
    final ui.Image image = await _decodeImage(rgba, width, height);
    if (!mounted ||
        token != _shapePreviewRasterToken ||
        _shapePreviewPath == null) {
      image.dispose();
      return;
    }
    _shapePreviewRasterImage?.dispose();
    _shapePreviewRasterImage = image;
    setState(() {});
    _hideRustLayerForVectorPreview(layer.id);
  }

  void _clearShapePreviewRasterImage({bool notify = true}) {
    _shapePreviewRasterToken++;
    final bool hadImage = _shapePreviewRasterImage != null;
    _shapePreviewRasterImage?.dispose();
    _shapePreviewRasterImage = null;
    if (!_isRustVectorPreviewActive) {
      _restoreRustLayerAfterVectorPreview();
    }
    if (notify && hadImage && mounted) {
      setState(() {});
    }
  }

  void _paintShapeStroke(List<Offset> strokePoints, double initialTimestamp) {
    final bool simulatePressure = _simulatePenPressure;
    final List<Offset> effectivePoints = simulatePressure
        ? _densifyStrokePolyline(strokePoints)
        : strokePoints;
    if (effectivePoints.length < 2) {
      return;
    }
    final Offset strokeStart = effectivePoints.first;
    final bool erase = _isBrushEraserEnabled;
    final Color strokeColor = erase ? const Color(0xFFFFFFFF) : _primaryColor;
    if (_shapeFillEnabled && _shapeToolVariant != ShapeToolVariant.line) {
      _paintShapeFill(strokePoints, strokeColor, erase);
    }
    _controller.beginStroke(
      strokeStart,
      color: strokeColor,
      radius: _penStrokeWidth / 2,
      simulatePressure: simulatePressure,
      profile: _penPressureProfile,
      timestampMillis: initialTimestamp,
      antialiasLevel: _penAntialiasLevel,
      brushShape: _brushShape,
      randomRotation: _brushRandomRotationEnabled,
      rotationSeed: _brushRandomRotationPreviewSeed,
      spacing: _brushSpacing,
      hardness: _brushHardness,
      flow: _brushFlow,
      scatter: _brushScatter,
      rotationJitter: _brushRotationJitter,
      snapToPixel: _brushSnapToPixel,
      erase: erase,
    );
    if (simulatePressure) {
      final List<Offset> samplePoints = effectivePoints.length > 1
          ? effectivePoints.sublist(1)
          : const <Offset>[];
      final List<_SyntheticStrokeSample> samples = _buildSyntheticStrokeSamples(
        samplePoints,
        strokeStart,
      );
      final double totalDistance = _syntheticStrokeTotalDistance(samples);
      _simulateStrokeWithSyntheticTimeline(
        samples,
        totalDistance: totalDistance,
        initialTimestamp: initialTimestamp,
      );
    } else {
      for (int i = 1; i < effectivePoints.length; i++) {
        _controller.extendStroke(effectivePoints[i]);
      }
    }
    _controller.endStroke();
    if (_brushRandomRotationEnabled) {
      _brushRandomRotationPreviewSeed = _brushRotationRandom.nextInt(1 << 31);
    }
    _markDirty();
  }

  void _paintShapeFill(
    List<Offset> strokePoints,
    Color strokeColor,
    bool erase,
  ) {
    if (strokePoints.length < 3) {
      return;
    }
    final List<Offset> polygon = _buildShapeFillPolygon(strokePoints);
    if (polygon.length < 3) {
      return;
    }
    void drawFill() {
      _controller.drawFilledPolygon(
        points: polygon,
        color: strokeColor,
        antialiasLevel: _penAntialiasLevel,
        erase: erase,
      );
    }
    drawFill();
  }

  List<Offset> _buildShapeFillPolygon(List<Offset> strokePoints) {
    final List<Offset> polygon = <Offset>[];
    Offset? previous;
    for (final Offset point in strokePoints) {
      if (previous != null &&
          (point.dx - previous.dx).abs() < 1e-4 &&
          (point.dy - previous.dy).abs() < 1e-4) {
        continue;
      }
      polygon.add(point);
      previous = point;
    }
    if (polygon.length >= 3) {
      final Offset first = polygon.first;
      final Offset last = polygon.last;
      if ((first.dx - last.dx).abs() < 1e-4 &&
          (first.dy - last.dy).abs() < 1e-4) {
        polygon.removeLast();
      }
    }
    return polygon;
  }

  Rect? _shapePreviewBoundsForPoints(List<Offset> strokePoints) {
    if (strokePoints.isEmpty) {
      return null;
    }
    double minX = strokePoints.first.dx;
    double minY = strokePoints.first.dy;
    double maxX = strokePoints.first.dx;
    double maxY = strokePoints.first.dy;
    for (final Offset point in strokePoints) {
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }
    final double padding = _shapePreviewPadding;
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(padding);
  }

  double get _shapePreviewPadding => math.max(_penStrokeWidth * 0.5, 0.5) + 4.0;
}
