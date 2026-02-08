part of 'painting_board.dart';
class _TextEditingSession {
  _TextEditingSession({
    required this.origin,
    required this.isNewLayer,
    this.layerId,
    this.layerWasVisible = true,
    this.originalData,
    this.pendingHistoryEntry,
  });
  final Offset origin;
  final bool isNewLayer;
  final String? layerId;
  final bool layerWasVisible;
  final CanvasTextData? originalData;
  final Future<_CanvasHistoryEntry>? pendingHistoryEntry;
  CanvasTextData? data;
  Rect? bounds;
  bool isFinalizing = false;
}
class _CommitTextEditingIntent extends Intent {
  const _CommitTextEditingIntent();
}
class _CancelTextEditingIntent extends Intent {
  const _CancelTextEditingIntent();
}
class _SelectAllTextOverlayIntent extends Intent {
  const _SelectAllTextOverlayIntent();
}
class _MoveTextCaretIntent extends Intent {
  const _MoveTextCaretIntent(
    this.delta, {
    this.expandSelection = false,
  });
  final int delta;
  final bool expandSelection;
}
mixin _PaintingBoardTextMixin on _PaintingBoardBase {
  final CanvasTextRenderer _textOverlayRenderer = CanvasTextRenderer();
  final TextEditingController _textEditingController = TextEditingController();
  final FocusNode _textEditingFocusNode = FocusNode();
  _TextEditingSession? _textSession;
  List<String> _textFontFamilies = const <String>[];
  bool _textFontsLoading = false;
  Rect? _hoverTextBounds;
  String? _hoverTextLayerId;
  double _textFontSize = 48;
  double _textLineHeight = 1.2;
  double _textLetterSpacing = 0;
  double _textStrokeWidth = 1.0;
  String _textFontFamily = '';
  TextAlign _textAlign = TextAlign.left;
  CanvasTextOrientation _textOrientation =
      CanvasTextOrientation.horizontal;
  bool _textAntialias = true;
  bool _textStrokeEnabled = false;
  Future<void>? _pendingTextLayerUpdate;
  Color _textOverlayContrastColor() {
    final Color canvasColor = _controller.backgroundColor;
    // Match UI accents to the opposite of the canvas so they stay visible.
    return canvasColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }
  void initializeTextTool() {
    _textEditingController.addListener(_handleTextFieldChanged);
    _loadSystemFonts();
  }
  void disposeTextTool() {
    _textEditingController.removeListener(_handleTextFieldChanged);
    _textEditingController.dispose();
    _textEditingFocusNode.dispose();
  }
  Future<void> _loadSystemFonts() async {
    setState(() => _textFontsLoading = true);
    final List<String> fonts = await SystemFonts.loadFamilies();
    if (!mounted) {
      return;
    }
    setState(() {
      _textFontFamilies = fonts;
      _textFontsLoading = false;
    });
  }
  bool get _isTextEditingActive => _textSession != null;
  @override
  void _handlePrimaryColorChanged() {
    super._handlePrimaryColorChanged();
    _updateActiveTextSessionColor();
  }
  @override
  void _handleTextStrokeColorChanged(Color color) {
    super._handleTextStrokeColorChanged(color);
    if (_textStrokeEnabled) {
      _refreshTextPreview();
    }
  }
  Widget? buildTextEditingOverlay() {
      final _TextEditingSession? session = _textSession;
      if (session == null || session.data == null || session.bounds == null) {
        return null;
      }
      final Rect bounds = session.bounds!;
      final double scale = _viewport.scale;
      final Offset workspacePosition = Offset(
        _boardRect.left + bounds.left * scale,
        _boardRect.top + bounds.top * scale,
      );
      final CanvasTextData data = session.data!;
      const bool showPreviewPainter = true;
      final bool isFinalizing = session.isFinalizing;
      final Color overlayColor = _textOverlayContrastColor();
      final Color selectionColor = overlayColor.withOpacity(0.25);
      final Color confirmBackgroundColor = overlayColor.withOpacity(0.08);
      final Color confirmBorderColor = overlayColor;
      final ButtonStyle confirmButtonStyle = ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStatePropertyAll(overlayColor),
      );
      final Widget editor = Container(
        decoration: BoxDecoration(
          border: Border.all(color: overlayColor),
        ),
        child: _TextEditorOverlay(
          renderer: _textOverlayRenderer,
          data: data,
          bounds: bounds,
          scale: scale,
          controller: _textEditingController,
          focusNode: _textEditingFocusNode,
          cursorColor: overlayColor,
          selectionColor: selectionColor,
          onConfirm: () {
            unawaited(_commitTextEditingSession());
          },
          onCancel: () {
            unawaited(_cancelTextEditingSession());
          },
          paintPreview: showPreviewPainter,
          interactive: !isFinalizing,
        ),
      );
      final Widget confirmButton = Padding(
        padding: const EdgeInsets.only(left: 8, top: 4),
        child: Container(
          decoration: BoxDecoration(
            color: confirmBackgroundColor,
            border: Border.all(
              color: confirmBorderColor,
            ),
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: isFinalizing
              ? const SizedBox(
                  width: 32,
                  height: 32,
                  child: ProgressRing(strokeWidth: 2.0),
                )
              : IconButton(
                  icon: Icon(
                    FluentIcons.check_mark,
                    color: overlayColor,
                  ),
                  style: confirmButtonStyle,
                  onPressed: () {
                    unawaited(_commitTextEditingSession());
                  },
                ),
        ),
      );
      return Positioned(
        left: workspacePosition.dx,
        top: workspacePosition.dy,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            editor,
            confirmButton,
          ],
        ),
      );
    }
  Widget? buildTextHoverOverlay() {
    if (_isTextEditingActive) {
      return null;
    }
    final Rect? hoverRect = _textHoverWorkspaceRect();
    if (hoverRect == null) {
      return null;
    }
    final Color overlayColor = _textOverlayContrastColor();
    return Positioned(
      left: hoverRect.left,
      top: hoverRect.top,
      child: IgnorePointer(
        ignoring: true,
        child: Container(
          width: hoverRect.width,
          height: hoverRect.height,
          decoration: BoxDecoration(
            border: Border.all(color: overlayColor),
          ),
        ),
      ),
    );
  }
  Rect? _textHoverWorkspaceRect() {
    final Rect? bounds = _hoverTextBounds;
    if (bounds == null) {
      return null;
    }
    final double scale = _viewport.scale;
    final double width = math.max(bounds.width * scale, 1.0);
    final double height = math.max(bounds.height * scale, 1.0);
    return Rect.fromLTWH(
      _boardRect.left + bounds.left * scale,
      _boardRect.top + bounds.top * scale,
      width,
      height,
    );
  }
  void _handleTextHover(Offset boardLocal) {
    if (_isTextEditingActive) {
      _clearTextHoverHighlight();
      return;
    }
    final BitmapLayerState? targetLayer = _hitTestTextLayer(boardLocal);
    if (targetLayer == null || targetLayer.locked) {
      _clearTextHoverHighlight();
      return;
    }
    final Rect? bounds = targetLayer.textBounds;
    if (bounds == null) {
      _clearTextHoverHighlight();
      return;
    }
    if (_hoverTextLayerId == targetLayer.id &&
        _hoverTextBounds == bounds) {
      return;
    }
    setState(() {
      _hoverTextLayerId = targetLayer.id;
      _hoverTextBounds = bounds;
    });
  }
  void _clearTextHoverHighlight() {
    if (_hoverTextLayerId == null && _hoverTextBounds == null) {
      return;
    }
    setState(() {
      _hoverTextLayerId = null;
      _hoverTextBounds = null;
    });
  }
    void _handleTextFieldChanged() {
      final _TextEditingSession? session = _textSession;
      if (session == null || session.isFinalizing) {
        return;
      }
      _updateTextPreview(session.origin);
    }
    void _updateTextPreview(Offset origin) {
      final _TextEditingSession? session = _textSession;
      if (session == null) {
        return;
      }
      final CanvasTextData data = _buildTextData(
        origin: origin,
        text: _textEditingController.text,
      );
      final CanvasTextLayout layout = _textOverlayRenderer.layout(data);
      final int? initialFrameGeneration = _controller.frame?.generation;
      setState(() {
        session.data = data;
        session.bounds = layout.bounds;
      });
      if (!session.isNewLayer && session.layerId != null) {
        _scheduleLiveTextLayerUpdate(
          session.layerId!,
          data,
          waitForHistoryEntry: session.pendingHistoryEntry,
        );
      }
    }
    void _scheduleLiveTextLayerUpdate(
      String layerId,
      CanvasTextData data, {
      Future<_CanvasHistoryEntry>? waitForHistoryEntry,
    }) {
      Future<void> previous =
          _pendingTextLayerUpdate ?? Future<void>.value();
      if (waitForHistoryEntry != null) {
        previous = Future.wait<void>(
          <Future<void>>[
            previous,
            waitForHistoryEntry.then((_) {}),
          ],
        );
      }
      final Future<void> next =
          previous.then((_) => _controller.updateTextLayer(layerId, data));
      _pendingTextLayerUpdate =
          next.catchError((Object error, StackTrace stackTrace) {
        debugPrint('文字图层实时渲染失败: $error');
      });
    }
    Future<void> _waitForPendingTextLayerUpdate() async {
      final Future<void>? pending = _pendingTextLayerUpdate;
      if (pending == null) {
        return;
      }
      try {
        await pending;
      } finally {
        if (identical(_pendingTextLayerUpdate, pending)) {
          _pendingTextLayerUpdate = null;
        }
      }
    }
    CanvasTextData _buildTextData({
      required Offset origin,
      required String text,
    }) {
      final double maxWidth = (_canvasSize.width - origin.dx)
          .clamp(32.0, _canvasSize.width);
      return CanvasTextData(
        text: text,
        origin: origin,
        fontSize: _textFontSize,
        fontFamily: _textFontFamily,
        color: _primaryColor,
        lineHeight: _textLineHeight,
        letterSpacing: _textLetterSpacing,
        maxWidth: maxWidth,
        align: _textAlign,
        orientation: _textOrientation,
        antialias: _textAntialias,
        strokeEnabled: _textStrokeEnabled,
        strokeWidth: _textStrokeWidth,
        strokeColor: _colorLineColor,
      );
    }
    void _beginNewTextSession(Offset origin) {
      _clearTextHoverHighlight();
      _pendingTextLayerUpdate = null;
      _textEditingController
        ..clear()
        ..selection = const TextSelection.collapsed(offset: 0);
      _textSession = _TextEditingSession(
        origin: origin,
        isNewLayer: true,
      );
      _updateTextPreview(origin);
      setState(() {});
      _textEditingFocusNode.requestFocus();
    }
    Rect? _textOverlayWorkspaceRect() {
      final _TextEditingSession? session = _textSession;
      if (session == null || session.bounds == null) {
        return null;
      }
      final Rect bounds = session.bounds!;
      final double scale = _viewport.scale;
      return Rect.fromLTWH(
        _boardRect.left + bounds.left * scale,
        _boardRect.top + bounds.top * scale,
        bounds.width * scale,
        bounds.height * scale,
      );
    }
    Future<void> _beginEditExistingTextLayer(BitmapLayerState layer) async {
      _clearTextHoverHighlight();
      final CanvasTextData? existing = layer.text;
      if (existing == null) {
        return;
      }
      if (layer.locked) {
        AppNotifications.show(
          context,
          message: '请先解锁文字图层后再编辑。',
          severity: InfoBarSeverity.warning,
        );
        return;
      }
      if (_canUseRustCanvasEngine()) {
        await _controller.waitForPendingWorkerTasks();
        if (!await _syncAllLayerPixelsFromRust()) {
          _showRustCanvasMessage('Rust 画布同步图层失败。');
          return;
        }
      }
      if (!mounted) {
        return;
      }
      _textFontFamily = existing.fontFamily;
      _textFontSize = existing.fontSize;
      _textLineHeight = existing.lineHeight;
      _textLetterSpacing = existing.letterSpacing;
      _textAlign = existing.align;
      _textOrientation = existing.orientation;
      _textAntialias = existing.antialias;
      _textStrokeEnabled = existing.strokeEnabled;
      _textStrokeWidth = existing.strokeWidth;
      _colorLineColor = existing.strokeColor;
      _primaryColor = existing.color;
      _primaryHsv = HSVColor.fromColor(existing.color);
      _textEditingController.text = existing.text;
      _textEditingController.selection = TextSelection.collapsed(
        offset: existing.text.length,
      );
      _pendingTextLayerUpdate = null;
      final Future<_CanvasHistoryEntry> pendingHistory =
          _createHistoryEntry(rustPixelsSynced: _canUseRustCanvasEngine());
      final bool layerWasVisible = layer.visible;
      _textSession = _TextEditingSession(
        origin: existing.origin,
        isNewLayer: false,
        layerId: layer.id,
        layerWasVisible: layerWasVisible,
        originalData: existing,
        pendingHistoryEntry: pendingHistory,
      );
      if (layerWasVisible) {
        layer.visible = false;
        _controller.notifyListeners();
      }
      _updateTextPreview(existing.origin);
      setState(() {});
      _textEditingFocusNode.requestFocus();
    }
    Future<bool> _commitTextLayerToRust(String layerId) async {
      if (!_canUseRustCanvasEngine()) {
        return false;
      }
      final int? handle = _rustCanvasEngineHandle;
      if (handle == null) {
        return false;
      }
      BitmapLayerState? layer;
      for (final BitmapLayerState candidate in _controller.layers) {
        if (candidate.id == layerId) {
          layer = candidate;
          break;
        }
      }
      if (layer == null) {
        return false;
      }
      final int? layerIndex = _rustCanvasLayerIndexForId(layerId);
      if (layerIndex == null) {
        return false;
      }
      final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
      final int width = engineSize.width.round();
      final int height = engineSize.height.round();
      if (width <= 0 || height <= 0) {
        return false;
      }
      if (layer.surface.width != width || layer.surface.height != height) {
        return false;
      }
      if (layer.surface.pixels.length != width * height) {
        return false;
      }
      final bool applied = await CanvasEngineFfi.instance.writeLayer(
        handle: handle,
        layerIndex: layerIndex,
        pixels: layer.surface.pixels,
        recordUndo: false,
      );
      if (applied) {
        _bumpRustLayerPreviewRevision(layerId);
        if (mounted) {
          setState(() {});
        }
        _markDirty();
      }
      return applied;
    }
    Future<void> _commitTextEditingSession() async {
      final _TextEditingSession? session = _textSession;
      if (session == null || session.isFinalizing) {
        return;
      }
      final String content = _textEditingController.text;
      if (content.trim().isEmpty) {
        await _cancelTextEditingSession();
        return;
      }
      final CanvasTextData baseData =
          session.data ?? _buildTextData(origin: session.origin, text: content);
      final CanvasTextData data = baseData.copyWith(text: content);
      final CanvasTextLayout layout = _textOverlayRenderer.layout(data);
      await _waitForPendingTextLayerUpdate();
      if (session.isNewLayer && _canUseRustCanvasEngine()) {
        await _controller.waitForPendingWorkerTasks();
        if (!await _syncAllLayerPixelsFromRust()) {
          _showRustCanvasMessage('Rust 画布同步图层失败。');
          return;
        }
      }
      final int? initialFrameGeneration = _controller.frame?.generation;
      setState(() {
        session.isFinalizing = true;
        session.data = data;
        session.bounds = layout.bounds;
      });
      try {
        if (session.isNewLayer) {
          final bool rustSynced = _canUseRustCanvasEngine();
          await _pushUndoSnapshot(rustPixelsSynced: rustSynced);
          final String layerId = await _controller.createTextLayer(data);
          _markDirty();
          if (rustSynced) {
            await _controller.waitForPendingWorkerTasks();
            if (!await _commitTextLayerToRust(layerId)) {
              _showRustCanvasMessage('Rust 画布写入图层失败。');
            }
          }
          return;
        }
        if (session.layerId == null) {
          return;
        }
        final Future<_CanvasHistoryEntry>? pendingHistory =
            session.pendingHistoryEntry;
        _restoreTextLayerVisibility(
          session.layerId!,
          session.layerWasVisible,
        );
        if (pendingHistory != null) {
          final _CanvasHistoryEntry entry = await pendingHistory;
          await _pushUndoSnapshot(entry: entry);
        } else {
          await _pushUndoSnapshot();
        }
        await _controller.updateTextLayer(session.layerId!, data);
        _markDirty();
        if (_canUseRustCanvasEngine()) {
          await _controller.waitForPendingWorkerTasks();
          if (!await _commitTextLayerToRust(session.layerId!)) {
            _showRustCanvasMessage('Rust 画布写入图层失败。');
          }
        }
      } finally {
        await _finalizeTextEditingSessionCleanup(
          session,
          initialFrameGeneration,
        );
      }
    }
    Future<void> _cancelTextEditingSession() async {
      final _TextEditingSession? session = _textSession;
      if (session == null || session.isFinalizing) {
        return;
      }
      setState(() {
        session.isFinalizing = true;
      });
      final int? initialFrameGeneration = _controller.frame?.generation;
      try {
        if (!session.isNewLayer && session.layerId != null) {
          await _waitForPendingTextLayerUpdate();
          _restoreTextLayerVisibility(
            session.layerId!,
            session.layerWasVisible,
          );
          final CanvasTextData? original = session.originalData;
          if (original != null) {
            await _controller.updateTextLayer(session.layerId!, original);
          }
        }
      } finally {
        await _finalizeTextEditingSessionCleanup(
          session,
          initialFrameGeneration,
        );
      }
    }
    void _restoreTextLayerVisibility(String id, bool wasVisible) {
      for (final BitmapLayerState layer in _controller.layers) {
        if (layer.id == id) {
          layer.visible = wasVisible;
          break;
        }
      }
      _controller.notifyListeners();
    }
  bool _activeLayerIsText() {
    final BitmapLayerState layer = _controller.activeLayer;
    return layer.text != null;
  }
  bool _shouldBlockToolOnTextLayer(CanvasTool tool) {
    if (!_activeLayerIsText()) {
      return false;
    }
    switch (tool) {
      case CanvasTool.text:
      case CanvasTool.hand:
      case CanvasTool.rotate:
      case CanvasTool.eyedropper:
      case CanvasTool.layerAdjust:
        return false;
      case CanvasTool.pen:
      case CanvasTool.eraser:
      case CanvasTool.curvePen:
      case CanvasTool.perspectivePen:
      case CanvasTool.shape:
      case CanvasTool.spray:
      case CanvasTool.bucket:
      case CanvasTool.magicWand:
      case CanvasTool.selection:
      case CanvasTool.selectionPen:
        return true;
    }
  }
    void _showTextToolConflictWarning() {
      AppNotifications.show(
        context,
        message: '当前图层是文字图层，请先栅格化或切换其他图层。',
        severity: InfoBarSeverity.warning,
      );
    }
    BitmapLayerState? _hitTestTextLayer(Offset boardLocal) {
      final List<BitmapLayerState> layers =
          _controller.layers.toList(growable: false);
      for (int i = layers.length - 1; i >= 0; i--) {
        final BitmapLayerState layer = layers[i];
        if (!layer.visible || layer.text == null || layer.textBounds == null) {
          continue;
        }
        if (layer.textBounds!.contains(boardLocal)) {
          return layer;
        }
      }
      return null;
    }
    void _updateTextFontFamily(String family) {
      if (_textFontFamily == family) {
        return;
      }
      setState(() => _textFontFamily = family);
      _refreshTextPreview();
    }
    void _updateTextFontSize(double value) {
      final double clamped = value.clamp(4.0, 512.0);
      if ((_textFontSize - clamped).abs() < 0.01) {
        return;
      }
      setState(() => _textFontSize = clamped);
      _refreshTextPreview();
    }
    void _updateTextLineHeight(double value) {
      final double clamped = value.clamp(0.5, 4.0);
      if ((_textLineHeight - clamped).abs() < 0.01) {
        return;
      }
      setState(() => _textLineHeight = clamped);
      _refreshTextPreview();
    }
    void _updateTextLetterSpacing(double value) {
      final double clamped = value.clamp(-100.0, 200.0);
      if ((_textLetterSpacing - clamped).abs() < 0.01) {
        return;
      }
      setState(() => _textLetterSpacing = clamped);
      _refreshTextPreview();
    }
    void _updateTextAlign(TextAlign align) {
      if (_textAlign == align) {
        return;
      }
      setState(() => _textAlign = align);
      _refreshTextPreview();
    }
    void _updateTextOrientation(CanvasTextOrientation orientation) {
      if (_textOrientation == orientation) {
        return;
      }
      setState(() => _textOrientation = orientation);
      _refreshTextPreview();
    }
    void _updateTextAntialias(bool value) {
      if (_textAntialias == value) {
        return;
      }
      setState(() => _textAntialias = value);
      _refreshTextPreview();
    }
    void _updateTextStrokeEnabled(bool value) {
      if (_textStrokeEnabled == value) {
        return;
      }
      setState(() => _textStrokeEnabled = value);
      _refreshTextPreview();
    }
    void _updateTextStrokeWidth(double value) {
      final double clamped = value.clamp(0.5, 20.0);
      if ((_textStrokeWidth - clamped).abs() < 0.01) {
        return;
      }
      setState(() => _textStrokeWidth = clamped);
      _refreshTextPreview();
    }
    void _refreshTextPreview() {
      final _TextEditingSession? session = _textSession;
      if (session == null) {
        return;
      }
      _updateTextPreview(session.origin);
    }
    void _updateActiveTextSessionColor() {
      final _TextEditingSession? session = _textSession;
      if (session == null || session.data == null) {
        return;
      }
      final CanvasTextData updated = session.data!.copyWith(
        color: _primaryColor,
      );
      session.data = updated;
      if (!session.isNewLayer && session.layerId != null) {
        _scheduleLiveTextLayerUpdate(
          session.layerId!,
          updated,
          waitForHistoryEntry: session.pendingHistoryEntry,
        );
      }
      setState(() {});
    }
    Future<void> _finalizeTextEditingSessionCleanup(
      _TextEditingSession session,
      int? initialFrameGeneration,
    ) async {
      const int maxWaitFrames = 24;
      final SchedulerBinding binding = SchedulerBinding.instance;
      int waits = 0;
      while (waits < maxWaitFrames) {
        final BitmapCanvasFrame? frame = _controller.frame;
        if (frame != null) {
          if (initialFrameGeneration == null ||
              frame.generation != initialFrameGeneration) {
            break;
          }
        }
        waits += 1;
        await binding.endOfFrame;
      }
      await binding.endOfFrame;
      if (!mounted || !identical(_textSession, session)) {
        return;
      }
      _textEditingController.clear();
      _textEditingController.selection =
          const TextSelection.collapsed(offset: 0);
      final bool shouldRestoreFocus = identical(_textSession, session);
      setState(() {
        if (shouldRestoreFocus) {
          _textSession = null;
        }
      });
      if (shouldRestoreFocus) {
        _focusNode.requestFocus();
      }
    }
  }
  class _TextEditorOverlay extends StatefulWidget {
    const _TextEditorOverlay({
      required this.renderer,
      required this.data,
      required this.bounds,
      required this.scale,
      required this.controller,
      required this.focusNode,
      required this.cursorColor,
      required this.selectionColor,
      required this.onConfirm,
      required this.onCancel,
      this.paintPreview = true,
      this.interactive = true,
    });
    final CanvasTextRenderer renderer;
    final CanvasTextData data;
    final Rect bounds;
    final double scale;
    final TextEditingController controller;
    final FocusNode focusNode;
    final Color cursorColor;
    final Color selectionColor;
    final VoidCallback onConfirm;
    final VoidCallback onCancel;
    final bool paintPreview;
    final bool interactive;
    @override
    State<_TextEditorOverlay> createState() => _TextEditorOverlayState();
  }
  class _TextEditorOverlayState extends State<_TextEditorOverlay> {
    final GlobalKey<EditableTextState> _editableKey =
        GlobalKey<EditableTextState>();
    Offset? _selectionDragOrigin;
    int? _selectionPointer;
    @override
    Widget build(BuildContext context) {
      final Size scaledSize = Size(
        math.max(widget.bounds.width * widget.scale, 4),
        math.max(widget.bounds.height * widget.scale, 4),
      );
      final double scaledFontSize =
          (widget.data.fontSize * widget.scale).clamp(0.1, 4096.0);
      final Map<LogicalKeySet, Intent> shortcuts = <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.escape):
            const _CancelTextEditingIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.enter,
        ): const _CommitTextEditingIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.enter,
        ): const _CommitTextEditingIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.keyA,
        ): const _SelectAllTextOverlayIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyA,
        ): const _SelectAllTextOverlayIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft):
            const _MoveTextCaretIntent(-1),
        LogicalKeySet(LogicalKeyboardKey.arrowRight):
            const _MoveTextCaretIntent(1),
        LogicalKeySet(
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.arrowLeft,
        ): const _MoveTextCaretIntent(-1, expandSelection: true),
        LogicalKeySet(
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.arrowRight,
        ): const _MoveTextCaretIntent(1, expandSelection: true),
      };
      return Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            _CommitTextEditingIntent: CallbackAction<_CommitTextEditingIntent>(
              onInvoke: (intent) {
                if (!widget.interactive) {
                  return null;
                }
                widget.onConfirm();
                return null;
              },
            ),
            _CancelTextEditingIntent: CallbackAction<_CancelTextEditingIntent>(
              onInvoke: (intent) {
                if (!widget.interactive) {
                  return null;
                }
                widget.onCancel();
                return null;
              },
            ),
            _SelectAllTextOverlayIntent:
                CallbackAction<_SelectAllTextOverlayIntent>(
              onInvoke: (intent) {
                if (!widget.interactive) {
                  return null;
                }
                _handleSelectAll();
                return null;
              },
            ),
            _MoveTextCaretIntent: CallbackAction<_MoveTextCaretIntent>(
              onInvoke: (intent) {
                if (!widget.interactive) {
                  return null;
                }
                _handleMoveCaret(intent);
                return null;
              },
            ),
          },
          child: IgnorePointer(
            ignoring: !widget.interactive,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerCancel,
              child: SizedBox(
                width: scaledSize.width,
                height: scaledSize.height,
                child: Stack(
                  fit: StackFit.loose,
                  clipBehavior: Clip.none,
                  children: [
                    if (widget.paintPreview)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _TextPreviewPainter(
                            renderer: widget.renderer,
                            data: widget.data,
                            bounds: widget.bounds,
                            scale: widget.scale,
                          ),
                        ),
                      ),
                    Positioned(
                      left: widget.data.align == TextAlign.right ||
                              widget.data.align == TextAlign.end ||
                              widget.data.align == TextAlign.center
                          ? -scaledFontSize
                          : 0,
                      right: widget.data.align == TextAlign.left ||
                              widget.data.align == TextAlign.start ||
                              widget.data.align == TextAlign.justify ||
                              widget.data.align == TextAlign.center
                          ? -scaledFontSize
                          : 0,
                      top: 0,
                      bottom: 0,
                      child: EditableText(
                        key: _editableKey,
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        cursorColor: widget.cursorColor,
                        backgroundCursorColor: Colors.transparent,
                        style: TextStyle(
                          color: Colors.transparent,
                          fontSize: scaledFontSize,
                          fontFamily: widget.data.fontFamily.isEmpty
                              ? null
                              : widget.data.fontFamily,
                          height: widget.data.lineHeight,
                          letterSpacing:
                              widget.data.letterSpacing * widget.scale,
                        ),
                        selectionColor: widget.selectionColor,
                        readOnly: !widget.interactive,
                        enableInteractiveSelection: widget.interactive,
                        showCursor: widget.interactive,
                        keyboardType: TextInputType.multiline,
                        maxLines: null,
                        textAlign: widget.data.align,
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  void _handleSelectAll() {
    final EditableTextState? state = _editableKey.currentState;
    if (state != null && state.mounted) {
      state.selectAll(SelectionChangedCause.keyboard);
      return;
    }
    final String value = widget.controller.text;
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: value.length,
    );
  }
  void _handleMoveCaret(_MoveTextCaretIntent intent) {
    final TextSelection selection = widget.controller.selection;
    final String text = widget.controller.text;
    final int textLength = text.length;
    final int normalizedBase = _clampOffset(selection.baseOffset, textLength);
    final int normalizedExtent =
        _clampOffset(selection.extentOffset, textLength);
    final bool hasSelection = normalizedBase != normalizedExtent;
    if (hasSelection && !intent.expandSelection) {
      final int collapseOffset = intent.delta < 0
          ? math.min(normalizedBase, normalizedExtent)
          : math.max(normalizedBase, normalizedExtent);
      widget.controller.selection = TextSelection.collapsed(
        offset: collapseOffset,
      );
      return;
    }
    final int targetExtent =
        (normalizedExtent + intent.delta).clamp(0, textLength);
    if (intent.expandSelection) {
      widget.controller.selection = TextSelection(
        baseOffset: normalizedBase,
        extentOffset: targetExtent,
      );
    } else {
      widget.controller.selection = TextSelection.collapsed(
        offset: targetExtent,
      );
    }
  }
  int _clampOffset(int offset, int length) {
    if (offset.isNegative) {
      return 0;
    }
    if (offset > length) {
      return length;
    }
    return offset;
  }
  void _handlePointerDown(PointerDownEvent event) {
    if (!_isPrimarySelectionPointer(event)) {
      return;
    }
    widget.focusNode.requestFocus();
    _selectionPointer = event.pointer;
    _selectionDragOrigin = event.position;
    _selectFromGlobalPosition(
      from: event.position,
      cause: SelectionChangedCause.tap,
    );
  }
  void _handlePointerMove(PointerMoveEvent event) {
    if (_selectionPointer != event.pointer || _selectionDragOrigin == null) {
      return;
    }
    _selectFromGlobalPosition(
      from: _selectionDragOrigin!,
      to: event.position,
      cause: SelectionChangedCause.drag,
    );
  }
  void _handlePointerUp(PointerUpEvent event) {
    if (_selectionPointer != event.pointer) {
      return;
    }
    if (_selectionDragOrigin != null) {
      _selectFromGlobalPosition(
        from: _selectionDragOrigin!,
        to: event.position,
        cause: SelectionChangedCause.drag,
      );
    }
    _selectionPointer = null;
    _selectionDragOrigin = null;
  }
  void _handlePointerCancel(PointerCancelEvent event) {
    if (_selectionPointer != event.pointer) {
      return;
    }
    _selectionPointer = null;
    _selectionDragOrigin = null;
  }
  void _selectFromGlobalPosition({
    required Offset from,
    Offset? to,
    required SelectionChangedCause cause,
  }) {
    final EditableTextState? state = _editableKey.currentState;
    if (state == null || !state.mounted) {
      return;
    }
    state.renderEditable.selectPositionAt(
      from: from,
      to: to,
      cause: cause,
    );
  }
  bool _isPrimarySelectionPointer(PointerDownEvent event) {
    switch (event.kind) {
      case PointerDeviceKind.mouse:
        return (event.buttons & kPrimaryMouseButton) != 0;
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
        return (event.buttons & kPrimaryStylusButton) != 0 || event.down;
      default:
        return event.down;
    }
  }
}
