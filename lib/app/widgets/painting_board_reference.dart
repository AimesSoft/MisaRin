part of 'painting_board.dart';

const double _referenceCardMinBodyWidth = 160;
const double _referenceCardMinBodyHeight = 120;
const double _referenceCardMaxBodyWidth = 520;
const double _referenceCardMaxBodyHeight = 360;
const double _referenceCardBodyHorizontalPadding = 24;
const double _referenceCardPanelChromeHeight = 68;
const double _referenceCardWorkspaceHorizontalPadding = 220;
const double _referenceCardWorkspaceVerticalPadding = 200;
const double _referenceCardMinScale = 0.35;
const double _referenceCardMaxScale = 8.0;
const double _referenceCardBodyPaddingLeft = 12;
const double _referenceCardBodyPaddingRight = 12;
const double _referenceCardBodyPaddingTop = 0;
const double _referenceCardBodyPaddingBottom = 12;
const double _referenceCardResizeEdgeHitExtent = 14.0;
const double _referenceCardResizeCornerHitExtent = 18.0;

enum _ReferenceCardResizeEdge { left, right, bottom, bottomLeft, bottomRight }

typedef _ReferenceCardResizeCallback =
    void Function(_ReferenceCardResizeEdge edge, Offset delta);

class _ReferenceCardEntry {
  _ReferenceCardEntry({
    required this.id,
    required this.image,
    required this.offset,
    required this.bodySize,
    required this.initialPanelSize,
    this.pixelBytes,
    required this.rawBytes,
  });

  final int id;
  ui.Image image;
  Offset offset;
  Size bodySize;
  final Size initialPanelSize;
  final Uint8List? pixelBytes;
  final Uint8List rawBytes;
  Size? size;

  Size get panelSize => size ?? initialPanelSize;
}

mixin _PaintingBoardReferenceMixin on _PaintingBoardBase {
  final List<_ReferenceCardEntry> _referenceCards = <_ReferenceCardEntry>[];
  int _referenceCardSerial = 0;
  bool _isCreatingReferenceCard = false;
  bool _isImportingReferenceCard = false;

  Future<void> createReferenceImageCard() async {
    if (_isCreatingReferenceCard) {
      AppNotifications.show(
        context,
        message: '正在生成参考图像，请稍候…',
        severity: InfoBarSeverity.info,
      );
      return;
    }
    _isCreatingReferenceCard = true;
    try {
      final List<CanvasLayerData> snapshot = _controller.snapshotLayers();
      if (snapshot.isEmpty) {
        AppNotifications.show(
          context,
          message: '当前画布没有可用内容。',
          severity: InfoBarSeverity.warning,
        );
        return;
      }
      final CanvasExporter exporter = CanvasExporter();
      final Uint8List pngBytes = await exporter.exportToPng(
        settings: widget.settings,
        layers: snapshot,
      );
      final ui.Codec codec = await ui.instantiateImageCodec(pngBytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      final ui.Image image = frame.image;
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final Uint8List? pixelBytes = byteData?.buffer.asUint8List();
      if (!mounted) {
        image.dispose();
        return;
      }
      final Size bodySize = _referenceCardBodySize(image);
      final Size panelSize = _referencePanelSize(bodySize);
      _insertReferenceCard(
        image: image,
        pixelBytes: pixelBytes,
        bodySize: bodySize,
        panelSize: panelSize,
        rawBytes: Uint8List.fromList(pngBytes),
      );
      AppNotifications.show(
        context,
        message: '参考图像已创建。',
        severity: InfoBarSeverity.success,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to create reference image: $error\n$stackTrace');
      AppNotifications.show(
        context,
        message: '创建参考图像失败。',
        severity: InfoBarSeverity.error,
      );
    } finally {
      _isCreatingReferenceCard = false;
    }
  }

  Future<void> importReferenceImageCard() async {
    if (_isImportingReferenceCard) {
      AppNotifications.show(
        context,
        message: '正在导入参考图像，请稍候…',
        severity: InfoBarSeverity.info,
      );
      return;
    }
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择参考图像',
      type: FileType.custom,
      allowedExtensions: const <String>['png', 'jpg', 'jpeg', 'bmp', 'webp'],
    );
    final PlatformFile? file = result?.files.singleOrNull;
    Uint8List? bytes = file?.bytes;
    if (bytes == null) {
      final String? path = file?.path;
      if (path == null) {
        return;
      }
      try {
        bytes = await File(path).readAsBytes();
      } catch (error) {
        if (!mounted) {
          return;
        }
        AppNotifications.show(
          context,
          message: '读取图像失败：$error',
          severity: InfoBarSeverity.error,
        );
        return;
      }
    }
    if (bytes.isEmpty) {
      return;
    }
    _isImportingReferenceCard = true;
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      final ui.Image image = frame.image;
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final Uint8List? pixelBytes = byteData?.buffer.asUint8List();
      if (!mounted) {
        image.dispose();
        return;
      }
      final Size bodySize = _referenceCardBodySize(image);
      final Size panelSize = _referencePanelSize(bodySize);
      _insertReferenceCard(
        image: image,
        pixelBytes: pixelBytes,
        bodySize: bodySize,
        panelSize: panelSize,
        rawBytes: Uint8List.fromList(bytes),
      );
      AppNotifications.show(
        context,
        message: '已导入参考图像${file?.name != null ? '：${file!.name}' : ''}',
        severity: InfoBarSeverity.success,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to import reference image: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: '导入参考图像失败。',
        severity: InfoBarSeverity.error,
      );
    } finally {
      _isImportingReferenceCard = false;
    }
  }

  void _insertReferenceCard({
    required ui.Image image,
    required Uint8List? pixelBytes,
    required Size bodySize,
    required Size panelSize,
    required Uint8List rawBytes,
  }) {
    final int id = ++_referenceCardSerial;
    final Offset offset = _initialReferenceCardOffset(panelSize);
    setState(() {
      _referenceCards.add(
        _ReferenceCardEntry(
          id: id,
          image: image,
          offset: offset,
          bodySize: bodySize,
          initialPanelSize: panelSize,
          pixelBytes: pixelBytes,
          rawBytes: rawBytes,
        ),
      );
    });
  }

  void _closeReferenceCard(int id) {
    final int index = _referenceCards.indexWhere((card) => card.id == id);
    if (index < 0) {
      return;
    }
    final _ReferenceCardEntry entry = _referenceCards[index];
    setState(() {
      _referenceCards.removeAt(index);
    });
    entry.image.dispose();
  }

  void _updateReferenceCardOffset(int id, Offset delta) {
    if (delta == Offset.zero) {
      return;
    }
    final _ReferenceCardEntry? entry = _referenceCardById(id);
    if (entry == null) {
      return;
    }
    setState(() {
      final Offset next = entry.offset + delta;
      entry.offset = _clampReferenceCardOffset(
        next,
        entry.size ?? _referencePanelSize(entry.bodySize),
      );
    });
  }

  void _resizeReferenceCard(
    int id,
    _ReferenceCardResizeEdge edge,
    Offset delta,
  ) {
    if (delta == Offset.zero) {
      return;
    }
    final _ReferenceCardEntry? entry = _referenceCardById(id);
    if (entry == null) {
      return;
    }
    final _ReferenceCardBodyConstraints limits =
        _referenceCardBodyConstraints();
    double width = entry.bodySize.width;
    double height = entry.bodySize.height;
    Offset offset = entry.offset;
    bool widthChanged = false;
    bool heightChanged = false;

    void resizeFromRight(double dx) {
      if (dx == 0) {
        return;
      }
      final double clampedWidth = (width + dx)
          .clamp(limits.minWidth, limits.maxWidth)
          .toDouble();
      if (clampedWidth == width) {
        return;
      }
      width = clampedWidth;
      widthChanged = true;
    }

    void resizeFromLeft(double dx) {
      if (dx == 0) {
        return;
      }
      final double clampedWidth = (width - dx)
          .clamp(limits.minWidth, limits.maxWidth)
          .toDouble();
      final double appliedShift = width - clampedWidth;
      if (appliedShift == 0) {
        return;
      }
      width = clampedWidth;
      offset = offset.translate(appliedShift, 0);
      widthChanged = true;
    }

    void resizeFromBottom(double dy) {
      if (dy == 0) {
        return;
      }
      final double clampedHeight = (height + dy)
          .clamp(limits.minHeight, limits.maxHeight)
          .toDouble();
      if (clampedHeight == height) {
        return;
      }
      height = clampedHeight;
      heightChanged = true;
    }

    switch (edge) {
      case _ReferenceCardResizeEdge.right:
        resizeFromRight(delta.dx);
        break;
      case _ReferenceCardResizeEdge.left:
        resizeFromLeft(delta.dx);
        break;
      case _ReferenceCardResizeEdge.bottom:
        resizeFromBottom(delta.dy);
        break;
      case _ReferenceCardResizeEdge.bottomLeft:
        resizeFromLeft(delta.dx);
        resizeFromBottom(delta.dy);
        break;
      case _ReferenceCardResizeEdge.bottomRight:
        resizeFromRight(delta.dx);
        resizeFromBottom(delta.dy);
        break;
    }

    if (!widthChanged && !heightChanged) {
      return;
    }
    final Size nextBodySize = Size(width, height);
    setState(() {
      entry.bodySize = nextBodySize;
      entry.offset = _clampReferenceCardOffset(
        offset,
        _referencePanelSize(nextBodySize),
      );
    });
  }

  void _handleReferenceCardSizeChanged(int id, Size size) {
    final _ReferenceCardEntry? entry = _referenceCardById(id);
    if (entry == null) {
      return;
    }
    entry.size = size;
    final Offset clamped = _clampReferenceCardOffset(entry.offset, size);
    if (clamped == entry.offset) {
      return;
    }
    setState(() {
      entry.offset = clamped;
    });
  }

  void _focusReferenceCard(int id) {
    final int index = _referenceCards.indexWhere((card) => card.id == id);
    if (index < 0 || index == _referenceCards.length - 1) {
      return;
    }
    setState(() {
      final _ReferenceCardEntry entry = _referenceCards.removeAt(index);
      _referenceCards.add(entry);
    });
  }

  void _beginReferenceCardResize(int id) {
    _focusReferenceCard(id);
    if (_referenceCardResizeInProgress) {
      return;
    }
    setState(() {
      _referenceCardResizeInProgress = true;
      _toolCursorPosition = null;
      _penCursorWorkspacePosition = null;
    });
  }

  void _endReferenceCardResize() {
    if (!_referenceCardResizeInProgress) {
      return;
    }
    setState(() {
      _referenceCardResizeInProgress = false;
    });
  }

  Offset _initialReferenceCardOffset(Size panelSize) {
    final double stackOffset = _referenceCards.length * 28.0;
    return _workspacePanelSpawnOffset(
      this,
      panelWidth: panelSize.width,
      panelHeight: panelSize.height,
      additionalDy: stackOffset,
    );
  }

  Offset _clampReferenceCardOffset(Offset value, [Size? size]) {
    if (_workspaceSize.isEmpty) {
      return value;
    }
    final double width =
        size?.width ??
        _referencePanelSize(
          const Size(_referenceCardMinBodyWidth, _referenceCardMinBodyHeight),
        ).width;
    final double height =
        size?.height ??
        _referencePanelSize(
          const Size(_referenceCardMinBodyWidth, _referenceCardMinBodyHeight),
        ).height;
    const double margin = 12.0;
    final double maxX = math.max(margin, _workspaceSize.width - width - margin);
    final double maxY = math.max(
      margin,
      _workspaceSize.height - height - margin,
    );
    return Offset(value.dx.clamp(margin, maxX), value.dy.clamp(margin, maxY));
  }

  _ReferenceCardEntry? _referenceCardById(int id) {
    for (final _ReferenceCardEntry entry in _referenceCards) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  @override
  bool _isInsideReferenceCardArea(Offset workspacePosition) {
    for (final _ReferenceCardEntry entry in _referenceCards) {
      final Size size = entry.panelSize;
      final Rect rect = Rect.fromLTWH(
        entry.offset.dx,
        entry.offset.dy,
        size.width,
        size.height,
      );
      if (rect.contains(workspacePosition)) {
        return true;
      }
    }
    return false;
  }

  Size _referenceCardBodySize(ui.Image image) {
    final double width = image.width.toDouble();
    final double height = image.height.toDouble();
    if (width <= 0 || height <= 0) {
      return const Size(
        _referenceCardMinBodyWidth,
        _referenceCardMinBodyHeight,
      );
    }
    double maxWidth = _referenceCardMaxBodyWidth;
    double maxHeight = _referenceCardMaxBodyHeight;
    if (!_workspaceSize.isEmpty) {
      final double availableWidth =
          _workspaceSize.width - _referenceCardWorkspaceHorizontalPadding;
      if (availableWidth.isFinite && availableWidth > 0) {
        maxWidth = math.min(maxWidth, availableWidth);
      }
      final double availableHeight =
          _workspaceSize.height - _referenceCardWorkspaceVerticalPadding;
      if (availableHeight.isFinite && availableHeight > 0) {
        maxHeight = math.min(maxHeight, availableHeight);
      }
    }
    if (maxWidth <= 0 || !maxWidth.isFinite) {
      maxWidth = _referenceCardMinBodyWidth;
    }
    if (maxHeight <= 0 || !maxHeight.isFinite) {
      maxHeight = _referenceCardMinBodyHeight;
    }

    final double downscale = math.min(
      1.0,
      math.min(maxWidth / width, maxHeight / height),
    );
    double targetWidth = width * downscale;
    double targetHeight = height * downscale;

    if (targetWidth < _referenceCardMinBodyWidth &&
        targetHeight < _referenceCardMinBodyHeight &&
        maxWidth >= _referenceCardMinBodyWidth &&
        maxHeight >= _referenceCardMinBodyHeight) {
      final double upscale = math.min(
        _referenceCardMinBodyWidth / targetWidth,
        _referenceCardMinBodyHeight / targetHeight,
      );
      targetWidth *= upscale;
      targetHeight *= upscale;
    }

    return Size(targetWidth, targetHeight);
  }

  Size _referencePanelSize(Size bodySize) {
    return Size(
      bodySize.width + _referenceCardBodyHorizontalPadding,
      bodySize.height + _referenceCardPanelChromeHeight,
    );
  }

  _ReferenceCardBodyConstraints _referenceCardBodyConstraints() {
    double maxWidth = _referenceCardMaxBodyWidth;
    double maxHeight = _referenceCardMaxBodyHeight;
    if (!_workspaceSize.isEmpty) {
      final double availableWidth =
          _workspaceSize.width - _referenceCardWorkspaceHorizontalPadding;
      if (availableWidth.isFinite && availableWidth > 0) {
        maxWidth = math.min(maxWidth, availableWidth);
      }
      final double availableHeight =
          _workspaceSize.height - _referenceCardWorkspaceVerticalPadding;
      if (availableHeight.isFinite && availableHeight > 0) {
        maxHeight = math.min(maxHeight, availableHeight);
      }
    }
    if (!maxWidth.isFinite || maxWidth <= 0) {
      maxWidth = _referenceCardMinBodyWidth;
    }
    if (!maxHeight.isFinite || maxHeight <= 0) {
      maxHeight = _referenceCardMinBodyHeight;
    }
    final double minWidth = math.min(_referenceCardMinBodyWidth, maxWidth);
    final double minHeight = math.min(_referenceCardMinBodyHeight, maxHeight);
    return _ReferenceCardBodyConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
    );
  }

  void _disposeReferenceCards() {
    for (final _ReferenceCardEntry entry in _referenceCards) {
      entry.image.dispose();
    }
    _referenceCards.clear();
  }

  List<ReferenceCardSnapshot> buildReferenceSnapshots() {
    return _referenceCards
        .map(
          (entry) => ReferenceCardSnapshot(
            imageBytes: Uint8List.fromList(entry.rawBytes),
            pixelBytes: entry.pixelBytes != null
                ? Uint8List.fromList(entry.pixelBytes!)
                : null,
            bodySize: entry.bodySize,
            panelSize: entry.panelSize,
            offset: entry.offset,
            size: entry.size,
          ),
        )
        .toList(growable: false);
  }

  Future<void> restoreReferenceSnapshots(
    List<ReferenceCardSnapshot> snapshots,
  ) async {
    _referenceCardSerial = 0;
    if (mounted) {
      setState(() {
        _disposeReferenceCards();
      });
    } else {
      _disposeReferenceCards();
    }
    if (snapshots.isEmpty) {
      return;
    }
    final List<_ReferenceCardEntry> restored = <_ReferenceCardEntry>[];
    for (final ReferenceCardSnapshot snapshot in snapshots) {
      try {
        final ui.Codec codec = await ui.instantiateImageCodec(
          snapshot.imageBytes,
        );
        final ui.FrameInfo frame = await codec.getNextFrame();
        codec.dispose();
        final ui.Image image = frame.image;
        Uint8List? pixelBytes = snapshot.pixelBytes != null
            ? Uint8List.fromList(snapshot.pixelBytes!)
            : null;
        pixelBytes ??= (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))?.buffer.asUint8List();
        final Offset offset = _clampReferenceCardOffset(
          snapshot.offset,
          snapshot.size ?? snapshot.panelSize,
        );
        final _ReferenceCardEntry entry = _ReferenceCardEntry(
          id: ++_referenceCardSerial,
          image: image,
          offset: offset,
          bodySize: snapshot.bodySize,
          initialPanelSize: snapshot.panelSize,
          pixelBytes: pixelBytes,
          rawBytes: Uint8List.fromList(snapshot.imageBytes),
        )..size = snapshot.size;
        restored.add(entry);
      } catch (error, stackTrace) {
        debugPrint('Failed to restore reference card: $error\n$stackTrace');
      }
    }
    if (!mounted) {
      for (final _ReferenceCardEntry entry in restored) {
        entry.image.dispose();
      }
      return;
    }
    setState(() {
      _referenceCards.addAll(restored);
    });
  }
}

class _ResizeHandleIndicator extends StatelessWidget {
  const _ResizeHandleIndicator({
    required this.angle,
    required this.color,
    required this.outlineColor,
  });

  final double angle;
  final Color color;
  final Color outlineColor;

  static const double size = 26;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ResizeHandleIndicatorPainter(
          angle: angle,
          color: color,
          outlineColor: outlineColor,
        ),
      ),
    );
  }
}

class _ResizeHandleIndicatorPainter extends CustomPainter {
  _ResizeHandleIndicatorPainter({
    required this.angle,
    required this.color,
    required this.outlineColor,
  });

  final double angle;
  final Color color;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Color solidFillColor = color.withAlpha(0xFF);
    final Color solidOutlineColor = outlineColor.withAlpha(0xFF);
    final Paint outlinePaint = Paint()
      ..color = solidOutlineColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final Paint fillPaint = Paint()
      ..color = solidFillColor
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    final double length = math.min(size.width, size.height) * 0.75;
    final double half = length / 2;
    final double head = 5;
    void drawArrow(Paint paint) {
      canvas.drawLine(Offset(-half, 0), Offset(half, 0), paint);
      canvas.drawLine(Offset(half, 0), Offset(half - head, head), paint);
      canvas.drawLine(Offset(half, 0), Offset(half - head, -head), paint);
      canvas.drawLine(Offset(-half, 0), Offset(-half + head, head), paint);
      canvas.drawLine(Offset(-half, 0), Offset(-half + head, -head), paint);
    }

    drawArrow(outlinePaint);
    drawArrow(fillPaint);
  }

  @override
  bool shouldRepaint(covariant _ResizeHandleIndicatorPainter oldDelegate) {
    return oldDelegate.angle != angle ||
        oldDelegate.color != color ||
        oldDelegate.outlineColor != outlineColor;
  }
}

class _ReferenceCardBodyConstraints {
  const _ReferenceCardBodyConstraints({
    required this.minWidth,
    required this.maxWidth,
    required this.minHeight,
    required this.maxHeight,
  });

  final double minWidth;
  final double maxWidth;
  final double minHeight;
  final double maxHeight;
}

class _ReferenceImageCard extends StatefulWidget {
  const _ReferenceImageCard({
    required this.image,
    required this.bodySize,
    required this.pixelBytes,
    required this.enableEyedropperSampling,
    required this.onSamplePreview,
    required this.onSampleCommit,
    required this.onClose,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onSizeChanged,
    required this.onResizeStart,
    required this.onResize,
    required this.onResizeEnd,
  });

  final ui.Image image;
  final Size bodySize;
  final Uint8List? pixelBytes;
  final bool enableEyedropperSampling;
  final ValueChanged<Color>? onSamplePreview;
  final ValueChanged<Color>? onSampleCommit;
  final VoidCallback onClose;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final ValueChanged<Offset> onDragUpdate;
  final ValueChanged<Size> onSizeChanged;
  final VoidCallback onResizeStart;
  final _ReferenceCardResizeCallback onResize;
  final VoidCallback onResizeEnd;

  @override
  State<_ReferenceImageCard> createState() => _ReferenceImageCardState();
}

class _ReferenceImageCardState extends State<_ReferenceImageCard> {
  late final TransformationController _transformController;
  bool _samplingActive = false;
  Offset? _cursorPosition;
  Size? _panelSize;
  _ReferenceCardResizeEdge? _hoveredResizeEdge;
  _ReferenceCardResizeEdge? _activeResizeEdge;
  Offset? _lastResizePointer;
  Offset? _resizeCursorPosition;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
  }

  @override
  void didUpdateWidget(covariant _ReferenceImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool previouslyCouldSample =
        oldWidget.enableEyedropperSampling && oldWidget.pixelBytes != null;
    if (previouslyCouldSample && !_canSampleColor && _cursorPosition != null) {
      setState(() => _cursorPosition = null);
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  bool get _canSampleColor =>
      widget.enableEyedropperSampling && widget.pixelBytes != null;

  bool get _interactionLocked => widget.enableEyedropperSampling;

  bool get _isResizing => _activeResizeEdge != null;

  MouseCursor get _currentResizeCursor {
    if (_activeResizeEdge != null || _hoveredResizeEdge != null) {
      return SystemMouseCursors.none;
    }
    return MouseCursor.defer;
  }

  double get _currentScale {
    final Matrix4 matrix = _transformController.value;
    final double scaleX = matrix.storage[0].abs();
    final double scaleY = matrix.storage[5].abs();
    return math.max(scaleX, scaleY);
  }

  void _resetView() {
    if (_interactionLocked) {
      return;
    }
    _transformController.value = Matrix4.identity();
  }

  void _zoomByFactor(double factor) {
    if (_interactionLocked) {
      return;
    }
    final double target = (_currentScale * factor).clamp(
      _referenceCardMinScale,
      _referenceCardMaxScale,
    );
    _updateScale(target, _viewportCenter());
  }

  Offset _viewportCenter() {
    return Offset(widget.bodySize.width / 2, widget.bodySize.height / 2);
  }

  void _updateScale(double targetScale, Offset focalPoint) {
    final double clamped = targetScale.clamp(
      _referenceCardMinScale,
      _referenceCardMaxScale,
    );
    final Offset scenePoint = _transformController.toScene(focalPoint);
    final Offset translation = Offset(
      focalPoint.dx - scenePoint.dx * clamped,
      focalPoint.dy - scenePoint.dy * clamped,
    );
    _transformController.value = Matrix4.identity()
      ..translate(translation.dx, translation.dy)
      ..scale(clamped);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _interactionLocked) {
      return;
    }
    if (event.scrollDelta.dy == 0) {
      return;
    }
    final double target = (_currentScale * (1 - event.scrollDelta.dy * 0.0015))
        .clamp(_referenceCardMinScale, _referenceCardMaxScale);
    _updateScale(target, event.localPosition);
  }

  Size _panelSizeOrDefault() {
    final Size? measured = _panelSize;
    if (measured != null && !measured.isEmpty) {
      return measured;
    }
    return Size(
      widget.bodySize.width + _referenceCardBodyHorizontalPadding,
      widget.bodySize.height + _referenceCardPanelChromeHeight,
    );
  }

  _ReferenceCardResizeEdge? _resolveResizeEdge(Offset position) {
    if (_interactionLocked) {
      return null;
    }
    final Size panelSize = _panelSizeOrDefault();
    if (panelSize.width <= 0 || panelSize.height <= 0) {
      return null;
    }
    final Rect panelRect = Rect.fromLTWH(
      0,
      0,
      panelSize.width,
      panelSize.height,
    );
    final double edgeTolerance = _referenceCardResizeEdgeHitExtent;
    final double cornerTolerance = _referenceCardResizeCornerHitExtent;
    final bool withinVerticalBounds =
        position.dy >= panelRect.top - edgeTolerance &&
        position.dy <= panelRect.bottom + edgeTolerance;
    final bool withinHorizontalBounds =
        position.dx >= panelRect.left - edgeTolerance &&
        position.dx <= panelRect.right + edgeTolerance;
    final bool nearLeft =
        withinVerticalBounds &&
        (position.dx - panelRect.left).abs() <= edgeTolerance;
    final bool nearRight =
        withinVerticalBounds &&
        (position.dx - panelRect.right).abs() <= edgeTolerance;
    final bool nearBottom =
        withinHorizontalBounds &&
        (position.dy - panelRect.bottom).abs() <= edgeTolerance;

    final bool nearBottomLeft =
        (position - panelRect.bottomLeft).distance <= cornerTolerance;
    final bool nearBottomRight =
        (position - panelRect.bottomRight).distance <= cornerTolerance;

    if (nearBottomLeft) {
      return _ReferenceCardResizeEdge.bottomLeft;
    }
    if (nearBottomRight) {
      return _ReferenceCardResizeEdge.bottomRight;
    }
    if (nearLeft) {
      return _ReferenceCardResizeEdge.left;
    }
    if (nearRight) {
      return _ReferenceCardResizeEdge.right;
    }
    if (nearBottom) {
      return _ReferenceCardResizeEdge.bottom;
    }
    return null;
  }

  void _handleResizeHover(PointerHoverEvent event) {
    if (_activeResizeEdge != null || _interactionLocked) {
      return;
    }
    final _ReferenceCardResizeEdge? edge = _resolveResizeEdge(
      event.localPosition,
    );
    if (edge == null) {
      if (_hoveredResizeEdge == null) {
        return;
      }
      setState(() {
        _hoveredResizeEdge = null;
        _resizeCursorPosition = null;
      });
      return;
    }
    setState(() {
      _hoveredResizeEdge = edge;
      _resizeCursorPosition = event.localPosition;
    });
  }

  void _handleResizeHoverExit() {
    if (_activeResizeEdge != null || _hoveredResizeEdge == null) {
      return;
    }
    setState(() {
      _hoveredResizeEdge = null;
      _resizeCursorPosition = null;
    });
  }

  void _handleResizePointerDown(PointerDownEvent event) {
    if (_interactionLocked || event.buttons == 0) {
      return;
    }
    final _ReferenceCardResizeEdge? edge = _resolveResizeEdge(
      event.localPosition,
    );
    if (edge == null) {
      return;
    }
    setState(() {
      _activeResizeEdge = edge;
      _hoveredResizeEdge = edge;
    });
    _lastResizePointer = event.localPosition;
    _resizeCursorPosition = event.localPosition;
    widget.onResizeStart();
  }

  void _handleResizePointerMove(PointerMoveEvent event) {
    final _ReferenceCardResizeEdge? edge = _activeResizeEdge;
    if (edge == null) {
      return;
    }
    final Offset previous = _lastResizePointer ?? event.localPosition;
    final Offset delta = event.localPosition - previous;
    if (delta == Offset.zero) {
      return;
    }
    _lastResizePointer = event.localPosition;
    _resizeCursorPosition = event.localPosition;
    widget.onResize(edge, delta);
  }

  void _handleResizePointerUp(PointerUpEvent event) {
    _finishResize();
  }

  void _handleResizePointerCancel(PointerCancelEvent event) {
    _finishResize();
  }

  void _finishResize() {
    if (_activeResizeEdge == null) {
      return;
    }
    widget.onResizeEnd();
    setState(() {
      _activeResizeEdge = null;
      _hoveredResizeEdge = null;
    });
    _lastResizePointer = null;
    _resizeCursorPosition = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_isResizing) {
      return;
    }
    _updateCursorOverlay(event.localPosition);
    if (!_shouldHandleSample(event)) {
      return;
    }
    _samplingActive = _emitSample(event.localPosition, commit: false);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_isResizing) {
      return;
    }
    _updateCursorOverlay(event.localPosition);
    if (!_samplingActive) {
      return;
    }
    _emitSample(event.localPosition, commit: false);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_isResizing) {
      return;
    }
    if (!_samplingActive) {
      return;
    }
    _emitSample(event.localPosition, commit: true);
    _samplingActive = false;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_isResizing) {
      return;
    }
    if (!_samplingActive) {
      return;
    }
    _samplingActive = false;
  }

  void _handleHover(PointerHoverEvent event) {
    if (_isResizing) {
      return;
    }
    _updateCursorOverlay(event.localPosition);
  }

  bool _shouldHandleSample(PointerEvent event) {
    if (!_canSampleColor) {
      return false;
    }
    if (event.kind == PointerDeviceKind.mouse) {
      return (event.buttons & kPrimaryMouseButton) != 0;
    }
    return true;
  }

  bool _emitSample(Offset localPosition, {required bool commit}) {
    final Color? color = _sampleColor(localPosition);
    if (color == null) {
      return false;
    }
    if (commit) {
      widget.onSampleCommit?.call(color);
    } else {
      widget.onSamplePreview?.call(color);
    }
    return true;
  }

  Color? _sampleColor(Offset localPosition) {
    if (!_canSampleColor) {
      return null;
    }
    final Offset scenePoint = _transformController.toScene(localPosition);
    if (scenePoint.dx < 0 ||
        scenePoint.dy < 0 ||
        scenePoint.dx > widget.bodySize.width ||
        scenePoint.dy > widget.bodySize.height) {
      return null;
    }
    final double relativeX = scenePoint.dx / widget.bodySize.width;
    final double relativeY = scenePoint.dy / widget.bodySize.height;
    final int pixelWidth = widget.image.width;
    final int pixelHeight = widget.image.height;
    if (pixelWidth <= 0 || pixelHeight <= 0) {
      return null;
    }
    final int pixelX = (relativeX * (pixelWidth - 1)).round().clamp(
      0,
      pixelWidth - 1,
    );
    final int pixelY = (relativeY * (pixelHeight - 1)).round().clamp(
      0,
      pixelHeight - 1,
    );
    final Uint8List? pixels = widget.pixelBytes;
    if (pixels == null || pixels.isEmpty) {
      return null;
    }
    final int index = (pixelY * pixelWidth + pixelX) * 4;
    if (index < 0 || index + 3 >= pixels.length) {
      return null;
    }
    final int r = pixels[index];
    final int g = pixels[index + 1];
    final int b = pixels[index + 2];
    final int a = pixels[index + 3];
    return Color.fromARGB(a, r, g, b);
  }

  void _updateCursorOverlay(Offset localPosition) {
    if (!_canSampleColor) {
      return;
    }
    final Offset? current = _cursorPosition;
    if (current != null && (current - localPosition).distanceSquared < 0.25) {
      return;
    }
    setState(() => _cursorPosition = localPosition);
  }

  void _clearCursorOverlay() {
    if (_cursorPosition == null) {
      return;
    }
    setState(() => _cursorPosition = null);
  }

  List<Widget> _buildHeaderActions() {
    final bool disabled = _interactionLocked;
    return [
      Tooltip(
        message: '缩小',
        child: IconButton(
          icon: const Icon(FluentIcons.calculator_subtract),
          iconButtonMode: IconButtonMode.small,
          onPressed: disabled ? null : () => _zoomByFactor(0.9),
        ),
      ),
      Tooltip(
        message: '放大',
        child: IconButton(
          icon: const Icon(FluentIcons.add),
          iconButtonMode: IconButtonMode.small,
          onPressed: disabled ? null : () => _zoomByFactor(1.1),
        ),
      ),
      Tooltip(
        message: '重置视图',
        child: IconButton(
          icon: const Icon(FluentIcons.refresh),
          iconButtonMode: IconButtonMode.small,
          onPressed: disabled ? null : _resetView,
        ),
      ),
    ];
  }

  List<Widget> _buildCursorOverlayWidgets() {
    if (!_canSampleColor) {
      return const <Widget>[];
    }
    final Offset? position = _cursorPosition;
    if (position == null) {
      return const <Widget>[];
    }
    final List<Widget> overlays = <Widget>[];
    final ToolCursorStyle? style = ToolCursorStyles.styleFor(
      CanvasTool.eyedropper,
    );
    if (style != null) {
      overlays.add(
        Positioned(
          left: position.dx - style.anchor.dx + style.iconOffset.dx,
          top: position.dy - style.anchor.dy + style.iconOffset.dy,
          child: IgnorePointer(
            ignoring: true,
            child: ToolCursorStyles.iconFor(
              CanvasTool.eyedropper,
              isDragging: false,
            ),
          ),
        ),
      );
    }
    overlays.add(
      Positioned(
        left: position.dx - ToolCursorStyles.crosshairSize / 2,
        top: position.dy - ToolCursorStyles.crosshairSize / 2,
        child: const IgnorePointer(
          ignoring: true,
          child: ToolCursorCrosshair(),
        ),
      ),
    );
    return overlays;
  }

  List<Widget> _buildResizeHandleIndicators(FluentThemeData theme) {
    final _ReferenceCardResizeEdge? edge =
        _activeResizeEdge ?? _hoveredResizeEdge;
    final Offset? position = _resizeCursorPosition;
    if (edge == null || position == null) {
      return const <Widget>[];
    }
    final double angle = switch (edge) {
      _ReferenceCardResizeEdge.left => 0,
      _ReferenceCardResizeEdge.right => 0,
      _ReferenceCardResizeEdge.bottom => math.pi / 2,
      _ReferenceCardResizeEdge.bottomLeft => -math.pi / 4,
      _ReferenceCardResizeEdge.bottomRight => math.pi / 4,
    };
    final Color color = _activeResizeEdge != null
        ? theme.resources.textFillColorPrimary
        : theme.resources.textFillColorSecondary;
    final Color outlineColor = theme.brightness.isDark
        ? Colors.black
        : Colors.white;
    const double indicatorSize = _ResizeHandleIndicator.size;
    return <Widget>[
      Positioned(
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
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final Size bodySize = widget.bodySize;
    final double panelWidth =
        bodySize.width + _referenceCardBodyHorizontalPadding;
    final FluentThemeData theme = FluentTheme.of(context);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handleResizePointerDown,
      onPointerMove: _handleResizePointerMove,
      onPointerUp: _handleResizePointerUp,
      onPointerCancel: _handleResizePointerCancel,
      onPointerHover: _handleResizeHover,
      child: MouseRegion(
        cursor: _currentResizeCursor,
        onExit: (_) => _handleResizeHoverExit(),
        child: IgnorePointer(
          ignoring: _isResizing,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              MeasuredSize(
                onChanged: (size) {
                  _panelSize = size;
                  widget.onSizeChanged(size);
                },
                child: WorkspaceFloatingPanel(
                  title: '参考图像',
                  width: panelWidth,
                  onClose: widget.onClose,
                  onDragStart: widget.onDragStart,
                  onDragEnd: widget.onDragEnd,
                  onDragUpdate: widget.onDragUpdate,
                  headerPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  bodyPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  bodySpacing: 10,
                  headerActions: _buildHeaderActions(),
                  child: _buildBody(),
                ),
              ),
              ..._buildResizeHandleIndicators(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final Decoration decoration = BoxDecoration(
      color: Colors.black.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
    );
    return DecoratedBox(
      decoration: decoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          onPointerSignal: _handlePointerSignal,
          child: MouseRegion(
            cursor: _canSampleColor
                ? SystemMouseCursors.none
                : MouseCursor.defer,
            onHover: _handleHover,
            onExit: (_) => _clearCursorOverlay(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: widget.bodySize.width,
                  height: widget.bodySize.height,
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    minScale: _referenceCardMinScale,
                    maxScale: _referenceCardMaxScale,
                    panEnabled: !_interactionLocked,
                    scaleEnabled: !_interactionLocked,
                    boundaryMargin: const EdgeInsets.all(240),
                    clipBehavior: Clip.hardEdge,
                    alignment: Alignment.topLeft,
                    child: RawImage(
                      image: widget.image,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                ..._buildCursorOverlayWidgets(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
