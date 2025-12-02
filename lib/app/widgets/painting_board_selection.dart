part of 'painting_board.dart';

const Color _kSelectionFillColor = Color(0x338A2BE2);
const Color _kSelectionPreviewFillColor = Color(0x558A2BE2);
const Color _kSelectionStrokeColor = Color(0x668A2BE2);
const double _kPolygonCloseThreshold = 8.0;
const Duration _kPolygonDoubleTapInterval = Duration(milliseconds: 300);
const double _kSelectionDashLength = 6.0;
const double _kSelectionDashGap = 4.0;

mixin _PaintingBoardSelectionMixin on _PaintingBoardBase {
  SelectionShape _selectionShape = SelectionShape.rectangle;
  Path? _selectionPath;
  Uint8List? _selectionMask;

  Path? _selectionPreviewPath;
  bool _isSelectionDragging = false;
  Offset? _selectionDragStart;

  final List<Offset> _polygonPoints = <Offset>[];
  Offset? _polygonHoverPoint;
  Duration? _lastPolygonTapTime;
  Offset? _lastPolygonTapPosition;

  Path? _magicWandPreviewPath;
  Uint8List? _magicWandPreviewMask;
  AnimationController? _selectionDashController;
  double _selectionDashPhase = 0.0;
  double _selectionDashValue = 0.0;
  bool _selectionUndoArmed = false;
  bool _isAdditiveSelection = false;
  Path? _currentDragPath;

  bool get _isShiftPressed {
    final Set<LogicalKeyboardKey> pressed =
        HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight) ||
        pressed.contains(LogicalKeyboardKey.shift);
  }

  @override
  SelectionShape get selectionShape => _selectionShape;

  @override
  Path? get selectionPath => _selectionPath;

  @override
  Path? get selectionPreviewPath => _selectionPreviewPath;

  @override
  Path? get magicWandPreviewPath => _magicWandPreviewPath;

  @override
  double get selectionDashPhase => _selectionDashPhase;

  @override
  Uint8List? get selectionMaskSnapshot => _selectionMask;

  @override
  Path? get selectionPathSnapshot => _selectionPath;

  @override
  bool isPointInsideSelection(Offset position) {
    final Uint8List? mask = _selectionMask;
    if (mask == null) {
      return true;
    }
    final int x = position.dx.floor();
    final int y = position.dy.floor();
    if (x < 0 || y < 0 || x >= _controller.width || y >= _controller.height) {
      return false;
    }
    return mask[y * _controller.width + x] != 0;
  }

  @override
  void _updateSelectionShape(SelectionShape shape) {
    if (_selectionShape == shape) {
      return;
    }
    setState(() {
      _selectionShape = shape;
      _resetSelectionPreview();
      _resetPolygonState();
    });
  }

  @override
  void _clearSelection() async {
    if (_selectionPath == null &&
        _selectionMask == null &&
        _selectionPreviewPath == null &&
        _magicWandPreviewPath == null) {
      return;
    }
    await _prepareSelectionUndo();
    setState(() {
      setSelectionState(path: null, mask: null);
      clearSelectionArtifacts();
    });
    _updateSelectionAnimation();
    _finishSelectionUndo();
  }

  @override
  void _handleMagicWandPointerDown(Offset position) {
    final bool additive = _isShiftPressed && _magicWandPreviewMask != null;
    _applyMagicWandPreview(position, additive: additive);
  }

  @override
  void _convertMagicWandPreviewToSelection() async {
    final Uint8List? mask = _magicWandPreviewMask;
    final Path? path = _magicWandPreviewPath;
    if (mask == null || path == null) {
      return;
    }
    await _prepareSelectionUndo();
    setState(() {
      _applySelectionPathInternal(path, mask: mask);
      if (identical(_magicWandPreviewMask, mask)) {
        _magicWandPreviewMask = null;
      }
      if (identical(_magicWandPreviewPath, path)) {
        _magicWandPreviewPath = null;
      }
    });
    _updateSelectionAnimation();
    _finishSelectionUndo();
  }

  @override
  void _convertSelectionToMagicWandPreview() {
    if (_selectionPath == null && _selectionMask == null) {
      return;
    }
    Uint8List? mask = _selectionMask;
    Path? path = _selectionPath;
    if (mask == null && path == null) {
      return;
    }
    if (mask == null && path != null) {
      mask = _maskFromPath(path);
    }
    if (path == null && mask != null) {
      path = _pathFromMask(mask, _controller.width);
    }
    if (mask == null || path == null) {
      return;
    }
    _magicWandPreviewMask = mask;
    _magicWandPreviewPath = path;
    setSelectionState(path: null, mask: null);
  }

  void _applyMagicWandPreview(Offset position, {bool additive = false}) {
    unawaited(_applyMagicWandPreviewAsync(position, additive: additive));
  }

  Future<void> _applyMagicWandPreviewAsync(
    Offset position, {
    required bool additive,
  }) async {
    final Uint8List? mask = await _controller.computeMagicWandMask(
      position,
      sampleAllLayers: true,
      tolerance: _magicWandTolerance,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      if (mask == null) {
        if (!additive) {
          _clearMagicWandPreview();
        }
        return;
      }
      final Path? path = _pathFromMask(mask, _controller.width);
      if (path == null) {
        if (!additive) {
          _clearMagicWandPreview();
        }
        return;
      }
      if (additive && _magicWandPreviewMask != null) {
        final Uint8List merged = _mergeMasks(_magicWandPreviewMask!, mask);
        final Path basePath =
            _magicWandPreviewPath ??
            (_pathFromMask(_magicWandPreviewMask!, _controller.width) ??
                Path());
        final Path combinedPath = Path.combine(
          ui.PathOperation.union,
          basePath,
          path,
        );
        _magicWandPreviewMask = merged;
        _magicWandPreviewPath = combinedPath;
      } else {
        _magicWandPreviewMask = mask;
        _magicWandPreviewPath = path;
      }
    });
    _updateSelectionAnimation();
  }

  @override
  void _handleSelectionPointerDown(Offset position, Duration timestamp) async {
    _magicWandPreviewMask = null;
    _magicWandPreviewPath = null;
    if (_selectionShape == SelectionShape.polygon) {
      _handlePolygonPointerDown(position, timestamp);
      _updateSelectionAnimation();
      return;
    }
    await _prepareSelectionUndo();
    final bool additive =
        _isShiftPressed &&
        _selectionMask != null &&
        _selectionShape != SelectionShape.polygon;
    _beginDragSelection(position, additive: additive);
    _updateSelectionAnimation();
  }

  @override
  void _handleSelectionPointerMove(Offset position) {
    if (_selectionShape == SelectionShape.polygon) {
      return;
    }
    if (!_isSelectionDragging || _selectionDragStart == null) {
      return;
    }
    setState(() {
      _currentDragPath = _buildDragPath(position);
      _selectionPreviewPath = _computeDragPreviewPath();
    });
    _updateSelectionAnimation();
  }

  @override
  void _handleSelectionPointerUp() {
    if (_selectionShape == SelectionShape.polygon) {
      return;
    }
    if (!_isSelectionDragging) {
      return;
    }
    final Path? finalizedPath = _currentDragPath;
    final bool additive = _isAdditiveSelection;
    setState(() {
      _isSelectionDragging = false;
      _selectionDragStart = null;
      _selectionPreviewPath = null;
      _currentDragPath = null;
      _isAdditiveSelection = false;
    });
    _applySelectionPathInternal(finalizedPath, additive: additive);
    _updateSelectionAnimation();
    _finishSelectionUndo();
  }

  @override
  void _handleSelectionPointerCancel() {
    if (_selectionShape == SelectionShape.polygon) {
      return;
    }
    if (!_isSelectionDragging) {
      return;
    }
    setState(() {
      _isSelectionDragging = false;
      _selectionDragStart = null;
      _selectionPreviewPath = null;
      _currentDragPath = null;
      _isAdditiveSelection = false;
    });
    _updateSelectionAnimation();
    _finishSelectionUndo();
  }

  @override
  void _handleSelectionHover(Offset position) {
    if (_selectionShape != SelectionShape.polygon) {
      return;
    }
    if (_polygonPoints.isEmpty) {
      return;
    }
    setState(() {
      _polygonHoverPoint = position;
      _selectionPreviewPath = _buildPolygonPath(
        points: _polygonPoints,
        hover: _polygonHoverPoint,
      );
    });
    _updateSelectionAnimation();
  }

  @override
  void _clearSelectionHover() {
    if (_selectionShape != SelectionShape.polygon) {
      return;
    }
    if (_polygonHoverPoint == null) {
      return;
    }
    setState(() {
      _polygonHoverPoint = null;
      _selectionPreviewPath = _buildPolygonPath(
        points: _polygonPoints,
        hover: null,
      );
    });
    _updateSelectionAnimation();
  }

  void _abortPolygonSelection() {
    if (_polygonPoints.isEmpty) {
      return;
    }
    setState(() {
      _polygonPoints.clear();
      _polygonHoverPoint = null;
      _selectionPreviewPath = null;
    });
    _updateSelectionAnimation();
  }

  void _beginDragSelection(Offset position, {required bool additive}) {
    setState(() {
      if (!additive) {
        setSelectionState(path: null, mask: null);
      }
      _isAdditiveSelection = additive;
      _isSelectionDragging = true;
      _selectionDragStart = position;
      _currentDragPath = null;
      _selectionPreviewPath = null;
    });
    _updateSelectionAnimation();
  }

  Path? _buildDragPath(Offset current) {
    final Offset? start = _selectionDragStart;
    if (start == null) {
      return null;
    }
    Offset constrainedCurrent = current;
    if (_isShiftPressed &&
        (_selectionShape == SelectionShape.rectangle ||
            _selectionShape == SelectionShape.ellipse)) {
      constrainedCurrent = _constrainToSquare(start, current);
    }
    final Offset effective = constrainedCurrent;
    final double left = start.dx < effective.dx ? start.dx : effective.dx;
    final double top = start.dy < effective.dy ? start.dy : effective.dy;
    final double right = start.dx > effective.dx ? start.dx : effective.dx;
    final double bottom = start.dy > effective.dy ? start.dy : effective.dy;
    double width = right - left;
    double height = bottom - top;
    if (width < 1) {
      width = 1;
    }
    if (height < 1) {
      height = 1;
    }
    final Rect rect = Rect.fromLTWH(left, top, width, height);
    if (_selectionShape == SelectionShape.rectangle) {
      return Path()..addRect(rect);
    }
    if (_selectionShape == SelectionShape.ellipse) {
      return Path()..addOval(rect);
    }
    return null;
  }

  Offset _constrainToSquare(Offset start, Offset current) {
    final double dx = current.dx - start.dx;
    final double dy = current.dy - start.dy;
    final double side = math.max(dx.abs(), dy.abs());
    final double adjustedDx = dx >= 0 ? side : -side;
    final double adjustedDy = dy >= 0 ? side : -side;
    return Offset(start.dx + adjustedDx, start.dy + adjustedDy);
  }

  Path? _computeDragPreviewPath() {
    final Path? dragPath = _currentDragPath;
    if (dragPath == null) {
      return _isAdditiveSelection ? _selectionPath : null;
    }
    if (_isAdditiveSelection &&
        (_selectionPath != null || _selectionMask != null)) {
      final Path? base =
          _selectionPath ?? _pathFromMask(_selectionMask!, _controller.width);
      if (base != null) {
        return Path.combine(ui.PathOperation.union, base, dragPath);
      }
    }
    return dragPath;
  }

  void _handlePolygonPointerDown(Offset position, Duration timestamp) async {
    final bool isDoubleTap = _isPolygonDoubleTap(position, timestamp);
    if (_polygonPoints.isEmpty) {
      await _prepareSelectionUndo();
      setState(() {
        setSelectionState(path: null, mask: null);
        _polygonPoints.add(position);
        _selectionPreviewPath = _buildPolygonPath(
          points: _polygonPoints,
          hover: _polygonHoverPoint,
        );
      });
      _lastPolygonTapTime = timestamp;
      _lastPolygonTapPosition = position;
      _updateSelectionAnimation();
      return;
    }

    final bool closeToFirst =
        (position - _polygonPoints.first).distance <= _kPolygonCloseThreshold;
    if ((isDoubleTap || closeToFirst) && _polygonPoints.length >= 3) {
      Path? finalizedPath;
      setState(() {
        if (!closeToFirst) {
          _polygonPoints.add(position);
        }
        finalizedPath = _buildPolygonPath(points: _polygonPoints, close: true);
        _selectionPreviewPath = null;
        _polygonPoints.clear();
        _polygonHoverPoint = null;
        _applySelectionPathInternal(finalizedPath);
      });
      _lastPolygonTapTime = null;
      _lastPolygonTapPosition = null;
      _updateSelectionAnimation();
      _finishSelectionUndo();
      return;
    }

    setState(() {
      _polygonPoints.add(position);
      _selectionPreviewPath = _buildPolygonPath(
        points: _polygonPoints,
        hover: _polygonHoverPoint,
      );
    });
    _lastPolygonTapTime = timestamp;
    _lastPolygonTapPosition = position;
    _updateSelectionAnimation();
  }

  bool _isPolygonDoubleTap(Offset position, Duration timestamp) {
    final Duration? previous = _lastPolygonTapTime;
    final Offset? previousPosition = _lastPolygonTapPosition;
    if (previous == null || previousPosition == null) {
      return false;
    }
    final Duration delta = timestamp - previous;
    if (delta > _kPolygonDoubleTapInterval) {
      return false;
    }
    final double distance = (position - previousPosition).distance;
    return distance <= _kPolygonCloseThreshold;
  }

  @override
  void _resetSelectionPreview() {
    _isSelectionDragging = false;
    _selectionDragStart = null;
    _selectionPreviewPath = null;
  }

  @override
  void _resetPolygonState() {
    _polygonPoints.clear();
    _polygonHoverPoint = null;
    _lastPolygonTapTime = null;
    _lastPolygonTapPosition = null;
  }

  @override
  void _clearMagicWandPreview() {
    _magicWandPreviewMask = null;
    _magicWandPreviewPath = null;
  }

  bool get _hasSelectionOverlay =>
      _selectionPath != null ||
      _selectionPreviewPath != null ||
      _magicWandPreviewPath != null;

  @override
  @override
  void _updateSelectionAnimation() {
    final AnimationController? controller = _selectionDashController;
    if (controller == null) {
      return;
    }
    if (_hasSelectionOverlay) {
      if (!controller.isAnimating) {
        controller.repeat();
        _selectionDashValue = controller.value;
      }
    } else {
      if (controller.isAnimating) {
        controller.stop();
      }
      _selectionDashPhase = 0;
    }
  }

  @override
  void initializeSelectionTicker(TickerProvider provider) {
    _selectionDashController =
        AnimationController(
          vsync: provider,
          duration: const Duration(milliseconds: 550),
        )..addListener(() {
          final AnimationController controller = _selectionDashController!;
          final double value = controller.value;
          double delta = value - _selectionDashValue;
          if (delta < 0) {
            delta += 1.0;
          }
          _selectionDashValue = value;
          if (!_hasSelectionOverlay) {
            return;
          }
          _selectionDashPhase +=
              delta * (_kSelectionDashLength + _kSelectionDashGap);
          if (_selectionDashPhase > 1e6) {
            _selectionDashPhase =
                _selectionDashPhase %
                (_kSelectionDashLength + _kSelectionDashGap);
          }
          if (mounted) {
            setState(() {});
          }
        });
    _updateSelectionAnimation();
  }

  @override
  void disposeSelectionTicker() {
    _selectionDashController?.dispose();
    _selectionDashController = null;
    _selectionDashValue = 0;
  }

  Path? _buildPolygonPath({
    required List<Offset> points,
    Offset? hover,
    bool close = false,
  }) {
    if (points.isEmpty) {
      return null;
    }
    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final Offset point = points[i];
      path.lineTo(point.dx, point.dy);
    }
    if (hover != null) {
      path.lineTo(hover.dx, hover.dy);
    }
    if (close || points.length >= 2) {
      path.close();
    }
    return path;
  }

  void _applySelectionPathInternal(
    Path? path, {
    Uint8List? mask,
    bool additive = false,
  }) {
    Uint8List? effectiveMask = mask;
    Path? effectivePath = path;
    if (effectiveMask == null && effectivePath != null) {
      effectiveMask = _maskFromPath(effectivePath);
    }
    if (effectiveMask == null) {
      if (!additive) {
        setSelectionState(path: null, mask: null);
      }
      return;
    }
    if (!_maskHasCoverage(effectiveMask)) {
      if (!additive) {
        setSelectionState(path: null, mask: null);
      }
      return;
    }
    if (additive && _selectionMask != null) {
      final Uint8List merged = _mergeMasks(_selectionMask!, effectiveMask);
      if (!_maskHasCoverage(merged)) {
        setSelectionState(path: null, mask: null);
        return;
      }
      final Path basePath =
          _selectionPath ??
          (_pathFromMask(_selectionMask!, _controller.width) ?? Path());
      if (effectivePath != null) {
        final Path combinedPath = Path.combine(
          ui.PathOperation.union,
          basePath,
          effectivePath,
        );
        setSelectionState(path: combinedPath, mask: merged);
        return;
      }
      setSelectionState(path: basePath, mask: merged);
      return;
    }
    final Path? resolvedPath =
        effectivePath ?? _pathFromMask(effectiveMask, _controller.width);
    setSelectionState(path: resolvedPath, mask: effectiveMask);
  }

  Future<void> _prepareSelectionUndo() async {
    if (_selectionUndoArmed) {
      return;
    }
    await _pushUndoSnapshot();
    _selectionUndoArmed = true;
  }

  void _finishSelectionUndo() {
    resetSelectionUndoFlag();
  }

  @override
  void setSelectionState({SelectionShape? shape, Path? path, Uint8List? mask}) {
    if (shape != null) {
      _selectionShape = shape;
    }
    _selectionPath = path;
    _selectionMask = mask;
    _controller.setSelectionMask(mask);
  }

  @override
  void clearSelectionArtifacts() {
    _selectionPreviewPath = null;
    _clearMagicWandPreview();
    _isSelectionDragging = false;
    _selectionDragStart = null;
    _resetPolygonState();
  }

  @override
  void resetSelectionUndoFlag() {
    _selectionUndoArmed = false;
  }

  Uint8List _maskFromPath(Path path) {
    final int width = _controller.width;
    final int height = _controller.height;
    final Uint8List mask = Uint8List(width * height);
    final Rect canvasRect = Rect.fromLTWH(
      0,
      0,
      width.toDouble(),
      height.toDouble(),
    );
    final Rect bounds = path.getBounds().inflate(1).intersect(canvasRect);
    if (bounds.isEmpty) {
      return mask;
    }
    final int minX = math.max(0, bounds.left.floor());
    final int maxX = math.min(width, bounds.right.ceil());
    final int minY = math.max(0, bounds.top.floor());
    final int maxY = math.min(height, bounds.bottom.ceil());
    for (int y = minY; y < maxY; y++) {
      final double py = y + 0.5;
      for (int x = minX; x < maxX; x++) {
        final double px = x + 0.5;
        if (path.contains(Offset(px, py))) {
          mask[y * width + x] = 1;
        }
      }
    }
    return mask;
  }

  bool _maskHasCoverage(Uint8List mask) {
    for (final int value in mask) {
      if (value != 0) {
        return true;
      }
    }
    return false;
  }

  Uint8List _mergeMasks(Uint8List current, Uint8List added) {
    final Uint8List result = Uint8List(current.length);
    for (int i = 0; i < current.length; i++) {
      result[i] = (current[i] != 0 || added[i] != 0) ? 1 : 0;
    }
    return result;
  }

  Path? _pathFromMask(Uint8List mask, int width) {
    if (mask.isEmpty) {
      return null;
    }
    final int height = mask.length ~/ width;
    final Map<int, Set<int>> adjacency = <int, Set<int>>{};
    final Set<int> edges = <int>{};
    bool hasCoverage = false;

    void addEdge(int startX, int startY, int direction) {
      final int vertex = _encodeVertex(startX, startY);
      final Set<int> directions = adjacency.putIfAbsent(vertex, () => <int>{});
      if (directions.add(direction)) {
        edges.add(_encodeEdge(vertex, direction));
      }
    }

    for (int y = 0; y < height; y++) {
      final int rowOffset = y * width;
      for (int x = 0; x < width; x++) {
        final int index = rowOffset + x;
        if (mask[index] == 0) {
          continue;
        }
        hasCoverage = true;
        if (y == 0 || mask[index - width] == 0) {
          addEdge(x, y, 0); // top edge, moving right
        }
        if (x == width - 1 || mask[index + 1] == 0) {
          addEdge(x + 1, y, 1); // right edge, moving down
        }
        if (y == height - 1 || mask[index + width] == 0) {
          addEdge(x + 1, y + 1, 2); // bottom edge, moving left
        }
        if (x == 0 || mask[index - 1] == 0) {
          addEdge(x, y + 1, 3); // left edge, moving up
        }
      }
    }

    if (!hasCoverage || edges.isEmpty) {
      return null;
    }

    final Path path = Path()..fillType = PathFillType.evenOdd;
    bool aborted = false;

    void consumeEdge(int encodedEdge) {
      if (!edges.remove(encodedEdge)) {
        return;
      }
      final int vertex = _edgeVertex(encodedEdge);
      final int direction = _edgeDirection(encodedEdge);
      final Set<int>? options = adjacency[vertex];
      if (options == null) {
        return;
      }
      options.remove(direction);
      if (options.isEmpty) {
        adjacency.remove(vertex);
      }
    }

    while (edges.isNotEmpty) {
      final int startEdge = edges.first;
      final int startVertex = _edgeVertex(startEdge);
      int currentDirection = _edgeDirection(startEdge);
      consumeEdge(startEdge);

      path.moveTo(
        _vertexX(startVertex).toDouble(),
        _vertexY(startVertex).toDouble(),
      );

      int currentVertex = startVertex;
      int nextX = _vertexX(currentVertex) + _directionDx[currentDirection];
      int nextY = _vertexY(currentVertex) + _directionDy[currentDirection];
      path.lineTo(nextX.toDouble(), nextY.toDouble());
      currentVertex = _encodeVertex(nextX, nextY);

      while (currentVertex != startVertex) {
        final int? nextDirection = _selectNextDirection(
          currentVertex,
          currentDirection,
          adjacency,
        );
        if (nextDirection == null) {
          aborted = true;
          break;
        }
        currentDirection = nextDirection;
        final int encodedEdge = _encodeEdge(currentVertex, currentDirection);
        consumeEdge(encodedEdge);
        nextX = _vertexX(currentVertex) + _directionDx[currentDirection];
        nextY = _vertexY(currentVertex) + _directionDy[currentDirection];
        path.lineTo(nextX.toDouble(), nextY.toDouble());
        currentVertex = _encodeVertex(nextX, nextY);
      }
      if (aborted) {
        break;
      }
      path.close();
    }

    if (aborted) {
      return _pathFromMaskFallback(mask, width);
    }

    return path;
  }
}

const List<int> _directionDx = <int>[1, 0, -1, 0];
const List<int> _directionDy = <int>[0, 1, 0, -1];

int _encodeVertex(int x, int y) => (y << 32) | (x & 0xFFFFFFFF);

int _vertexX(int key) => key & 0xFFFFFFFF;

int _vertexY(int key) => key >> 32;

int _encodeEdge(int vertex, int direction) => (vertex << 2) | direction;

int _edgeVertex(int edge) => edge >> 2;

int _edgeDirection(int edge) => edge & 0x3;

int? _selectNextDirection(
  int vertex,
  int previousDirection,
  Map<int, Set<int>> adjacency,
) {
  final Set<int>? options = adjacency[vertex];
  if (options == null || options.isEmpty) {
    return null;
  }
  for (final int offset in const <int>[1, 0, 3, 2]) {
    final int candidate = (previousDirection + offset) & 0x3;
    if (options.contains(candidate)) {
      return candidate;
    }
  }
  return null;
}

Path? _pathFromMaskFallback(Uint8List mask, int width) {
  if (mask.isEmpty) {
    return null;
  }
  final int height = mask.length ~/ width;
  Path? result;
  for (int y = 0; y < height; y++) {
    final int rowOffset = y * width;
    int x = 0;
    while (x < width) {
      if (mask[rowOffset + x] == 0) {
        x += 1;
        continue;
      }
      final int start = x;
      while (x < width && mask[rowOffset + x] != 0) {
        x += 1;
      }
      final Rect rect = Rect.fromLTWH(
        start.toDouble(),
        y.toDouble(),
        (x - start).toDouble(),
        1,
      );
      final Path segment = Path()..addRect(rect);
      result = result == null
          ? segment
          : Path.combine(ui.PathOperation.union, result, segment);
    }
  }
  return result;
}

class _SelectionOverlayPainter extends CustomPainter {
  const _SelectionOverlayPainter({
    this.selectionPath,
    this.selectionPreviewPath,
    this.magicPreviewPath,
    required this.dashPhase,
    required this.viewportScale,
  });

  final Path? selectionPath;
  final Path? selectionPreviewPath;
  final Path? magicPreviewPath;
  final double dashPhase;
  final double viewportScale;

  static final Paint _previewFillPaint = Paint()
    ..color = _kSelectionPreviewFillColor
    ..style = PaintingStyle.fill;
  static final _MarchingAntsStroke _selectionStroke = _MarchingAntsStroke(
    dashLength: _kSelectionDashLength,
    dashGap: _kSelectionDashGap,
    strokeWidth: 1.0,
    lightColor: const Color(0xE6FFFFFF),
    darkColor: const Color(0xFF2B2B2B),
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (magicPreviewPath != null) {
      canvas.drawPath(magicPreviewPath!, _previewFillPaint);
      _selectionStroke.paint(
        canvas,
        magicPreviewPath!,
        dashPhase,
        viewportScale: viewportScale,
      );
    }
    if (selectionPreviewPath != null) {
      canvas.drawPath(selectionPreviewPath!, _previewFillPaint);
      _selectionStroke.paint(
        canvas,
        selectionPreviewPath!,
        dashPhase,
        viewportScale: viewportScale,
      );
    }
    if (selectionPath != null) {
      _selectionStroke.paint(
        canvas,
        selectionPath!,
        dashPhase,
        viewportScale: viewportScale,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionOverlayPainter oldDelegate) {
    return oldDelegate.selectionPath != selectionPath ||
        oldDelegate.selectionPreviewPath != selectionPreviewPath ||
        oldDelegate.magicPreviewPath != magicPreviewPath ||
        oldDelegate.dashPhase != dashPhase ||
        oldDelegate.viewportScale != viewportScale;
  }
}
