part of 'painting_board.dart';

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
  Offset? _layerTransformHandleFixedLocal;
  Offset? _layerTransformHandleFixedBoard;
  Offset _layerTransformPanelOffset = Offset.zero;
  Size _layerTransformPanelSize = const Size(
    _kLayerTransformPanelWidth,
    _kLayerTransformPanelMinHeight,
  );
  bool _layerTransformApplying = false;
  int _layerTransformRevision = 0;
  Offset? _layerTransformCursorWorkspacePosition;
  _LayerTransformHandle? _layerTransformCursorHandle;
  bool _layerTransformUsingRustPreview = false;
  int? _layerTransformRustLayerIndex;

  bool get _isLayerFreeTransformActive =>
      _layerTransformModeActive && _layerTransformState != null;

  bool get _layerTransformCursorVisible =>
      _isLayerFreeTransformActive &&
      _layerTransformCursorWorkspacePosition != null &&
      _layerTransformCursorHandle != null;

  bool get _shouldHideCursorForLayerTransform => _layerTransformCursorVisible;

  _LayerTransformHandle? _layerTransformOppositeHandle(
    _LayerTransformHandle handle,
  ) {
    switch (handle) {
      case _LayerTransformHandle.topLeft:
        return _LayerTransformHandle.bottomRight;
      case _LayerTransformHandle.top:
        return _LayerTransformHandle.bottom;
      case _LayerTransformHandle.topRight:
        return _LayerTransformHandle.bottomLeft;
      case _LayerTransformHandle.right:
        return _LayerTransformHandle.left;
      case _LayerTransformHandle.bottomRight:
        return _LayerTransformHandle.topLeft;
      case _LayerTransformHandle.bottom:
        return _LayerTransformHandle.top;
      case _LayerTransformHandle.bottomLeft:
        return _LayerTransformHandle.topRight;
      case _LayerTransformHandle.left:
        return _LayerTransformHandle.right;
      case _LayerTransformHandle.translate:
      case _LayerTransformHandle.rotation:
        return null;
    }
  }

  bool _shouldUseTransformBilinear() {
    return _penAntialiasLevel > 0;
  }

  void toggleLayerFreeTransform() {
    if (_layerTransformModeActive) {
      _cancelLayerFreeTransform();
    } else {
      unawaited(_startLayerFreeTransform());
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
        bounds: bounds,
        imageOrigin: origin,
        image: image,
      );
    });
    final BitmapLayerState? activeLayer = _activeLayerSnapshot();
    if (activeLayer != null) {
      _hideRustLayerForTransform(activeLayer);
    }
    return true;
  }

  Future<bool> _startLayerFreeTransformWithRust(
    BitmapLayerState activeLayer,
  ) async {
    if (!_canUseRustCanvasEngine()) {
      return false;
    }
    final int? handle = _rustCanvasEngineHandle;
    if (handle == null) {
      return false;
    }
    final int? layerIndex = _rustCanvasLayerIndexForId(activeLayer.id);
    if (layerIndex == null) {
      return false;
    }
    final Rect? bounds = await _fetchRustLayerBounds(handle, layerIndex);
    if (bounds == null || bounds.isEmpty) {
      return false;
    }
    final _LayerTransformStateModel state = _LayerTransformStateModel(
      bounds: bounds,
      imageOrigin: bounds.topLeft,
      image: null,
      fullImageSizeOverride: bounds.size,
    );
    final bool previewOk = await _setRustLayerTransformPreview(
      handle: handle,
      layerIndex: layerIndex,
      state: state,
      enabled: true,
    );
    if (!previewOk) {
      return false;
    }
    setState(() {
      _layerTransformModeActive = true;
      _layerTransformState = state;
      _activeLayerTransformHandle = null;
      _hoverLayerTransformHandle = null;
      _layerTransformPointerStartBoard = null;
      _layerTransformInitialTranslation = null;
      _layerTransformInitialRotation = 0.0;
      _layerTransformInitialScaleX = 1.0;
      _layerTransformInitialScaleY = 1.0;
      _layerTransformPointerStartInverse = null;
      _layerTransformHandleAnchorLocal = null;
      _layerTransformHandleFixedLocal = null;
      _layerTransformHandleFixedBoard = null;
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
      _layerTransformUsingRustPreview = true;
      _layerTransformRustLayerIndex = layerIndex;
    });
    _toolCursorPosition = null;
    _penCursorWorkspacePosition = null;
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

  Future<void> _startLayerFreeTransform() async {
    if (_layerTransformModeActive ||
        _controller.isActiveLayerTransformPendingCleanup) {
      return;
    }
    _restoreRustLayerAfterTransform();
    final BitmapLayerState? activeLayer = _activeLayerSnapshot();
    if (activeLayer == null) {
      AppNotifications.show(
        context,
        message: context.l10n.cannotLocateLayer,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    if (activeLayer.locked) {
      AppNotifications.show(
        context,
        message: context.l10n.layerLockedCannotTransform,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    if (_canUseRustCanvasEngine()) {
      final bool started = await _startLayerFreeTransformWithRust(activeLayer);
      if (started) {
        return;
      }
      if (!await _syncActiveLayerFromRustForTransform(activeLayer)) {
        AppNotifications.show(
          context,
          message: context.l10n.cannotEnterTransformMode,
          severity: InfoBarSeverity.warning,
        );
        return;
      }
    }
    if (!_controller.isActiveLayerTransforming) {
      _controller.translateActiveLayer(0, 0);
    }
    if (!_controller.isActiveLayerTransforming) {
      AppNotifications.show(
        context,
        message: context.l10n.cannotEnterTransformMode,
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
      _layerTransformHandleFixedLocal = null;
      _layerTransformHandleFixedBoard = null;
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
      _layerTransformUsingRustPreview = false;
      _layerTransformRustLayerIndex = null;
    });
    _toolCursorPosition = null;
    _penCursorWorkspacePosition = null;
    _maybeInitializeLayerTransformStateFromController();
  }

  void _cancelLayerFreeTransform() {
    if (!_layerTransformModeActive || _layerTransformApplying) {
      return;
    }
    if (_layerTransformUsingRustPreview) {
      _clearRustLayerTransformPreview();
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
      _layerTransformHandleFixedLocal = null;
      _layerTransformHandleFixedBoard = null;
      _layerTransformRevision = 0;
      _layerTransformCursorWorkspacePosition = null;
      _layerTransformCursorHandle = null;
      _layerTransformUsingRustPreview = false;
      _layerTransformRustLayerIndex = null;
    });
    _restoreRustLayerAfterTransform();
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
    if (_layerTransformUsingRustPreview) {
      setState(() => _layerTransformApplying = true);
      try {
        final bool applied = await _applyRustLayerTransformPreview(state);
        if (!applied) {
          throw StateError(context.l10n.applyTransformFailed);
        }
        _recordRustHistoryAction(layerId: activeLayer.id);
        _controller.disposeActiveLayerTransformSession();
        _clearRustLayerTransformPreview();
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
          _layerTransformHandleFixedLocal = null;
          _layerTransformHandleFixedBoard = null;
          _layerTransformRevision = 0;
          _layerTransformCursorWorkspacePosition = null;
          _layerTransformCursorHandle = null;
          _layerTransformUsingRustPreview = false;
          _layerTransformRustLayerIndex = null;
        });
        _restoreRustLayerAfterTransform();
        _markDirty();
        return;
      } catch (error, stackTrace) {
        debugPrint('Failed to apply transform: $error\n$stackTrace');
        setState(() => _layerTransformApplying = false);
        AppNotifications.show(
          context,
          message: context.l10n.applyTransformFailed,
          severity: InfoBarSeverity.error,
        );
        return;
      }
    }
    setState(() => _layerTransformApplying = true);
    try {
      final _LayerTransformRenderResult result =
          await _renderLayerTransformResult(state);
      final _CanvasHistoryEntry? undoEntry =
          await _buildLayerTransformUndoEntry(state);
      if (_canUseRustCanvasEngine()) {
        final bool applied = await _applyRustLayerTransform(
          layer: activeLayer,
          result: result,
        );
        if (!applied) {
          throw StateError(context.l10n.applyTransformFailed);
        }
        _recordRustHistoryAction(layerId: activeLayer.id);
      }
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
        _layerTransformHandleFixedLocal = null;
        _layerTransformHandleFixedBoard = null;
        _layerTransformRevision = 0;
        _layerTransformCursorWorkspacePosition = null;
        _layerTransformCursorHandle = null;
      });
      _restoreRustLayerAfterTransform();
      _markDirty();
    } catch (error, stackTrace) {
      debugPrint('Failed to apply transform: $error\n$stackTrace');
      setState(() => _layerTransformApplying = false);
      AppNotifications.show(
        context,
        message: context.l10n.applyTransformFailed,
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
    final ui.Image? image = state.image;
    if (image == null) {
      return entry;
    }
    final ByteData? byteData = await image.toByteData(
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
      bitmapWidth: image.width,
      bitmapHeight: image.height,
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

    final SchedulerBinding? scheduler = SchedulerBinding.instance;
    if (scheduler != null) {
      await scheduler.endOfFrame;
    } else {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<_LayerTransformRenderResult> _renderLayerTransformResult(
    _LayerTransformStateModel state,
  ) async {
    final ui.Image? image = state.image;
    if (image == null) {
      throw StateError(context.l10n.failedToExportTransform);
    }
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
    final bool useBilinear = _shouldUseTransformBilinear();
    final Paint paint = Paint()
      ..filterQuality =
          useBilinear ? FilterQuality.high : FilterQuality.none
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
    canvas.drawImage(image, Offset.zero, paint);
    canvas.restore();
    final ui.Picture picture = recorder.endRecording();
    final ui.Image rendered = await picture.toImage(width, height);
    picture.dispose();
    final ByteData? byteData = await rendered.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    rendered.dispose();
    if (byteData == null) {
      throw StateError(context.l10n.failedToExportTransform);
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

  Future<bool> _syncActiveLayerFromRustForTransform(
    BitmapLayerState layer,
  ) async {
    if (!_canUseRustCanvasEngine()) {
      return false;
    }
    final int? handle = _rustCanvasEngineHandle;
    if (handle == null) {
      return false;
    }
    final int? layerIndex = _rustCanvasLayerIndexForId(layer.id);
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
    final Uint32List? pixels = await CanvasEngineFfi.instance.readLayer(
      handle: handle,
      layerIndex: layerIndex,
      width: width,
      height: height,
    );
    if (pixels == null || pixels.length != layer.surface.pixels.length) {
      return false;
    }
    layer.surface.pixels.setAll(0, pixels);
    layer.surface.markDirty();
    return true;
  }

  void _hideRustLayerForTransform(BitmapLayerState layer) {
    if (!_canUseRustCanvasEngine()) {
      return;
    }
    if (_layerTransformUsingRustPreview) {
      return;
    }
    if (_layerTransformRustHiddenLayerIndex != null) {
      return;
    }
    final int? layerIndex = _rustCanvasLayerIndexForId(layer.id);
    if (layerIndex == null) {
      return;
    }
    _layerTransformRustHiddenLayerIndex = layerIndex;
    _layerTransformRustHiddenVisible = layer.visible;
    CanvasEngineFfi.instance.setLayerVisible(
      handle: _rustCanvasEngineHandle!,
      layerIndex: layerIndex,
      visible: false,
    );
  }

  void _restoreRustLayerAfterTransform() {
    final int? layerIndex = _layerTransformRustHiddenLayerIndex;
    if (layerIndex == null) {
      return;
    }
    if (_canUseRustCanvasEngine()) {
      CanvasEngineFfi.instance.setLayerVisible(
        handle: _rustCanvasEngineHandle!,
        layerIndex: layerIndex,
        visible: _layerTransformRustHiddenVisible,
      );
    }
    _layerTransformRustHiddenLayerIndex = null;
    _layerTransformRustHiddenVisible = false;
  }

  Future<Rect?> _fetchRustLayerBounds(int handle, int layerIndex) async {
    final Int32List? bounds = await CanvasEngineFfi.instance.getLayerBounds(
      handle: handle,
      layerIndex: layerIndex,
    );
    if (bounds == null || bounds.length < 4) {
      return null;
    }
    final double left = bounds[0].toDouble();
    final double top = bounds[1].toDouble();
    final double right = bounds[2].toDouble();
    final double bottom = bounds[3].toDouble();
    if (right <= left || bottom <= top) {
      return null;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Float32List? _buildRustTransformMatrix(_LayerTransformStateModel state) {
    final Matrix4? inverse = state.inverseMatrix;
    if (inverse == null) {
      return null;
    }
    final Matrix4 boardToSource = Matrix4.identity()
      ..translate(state.bounds.left, state.bounds.top)
      ..multiply(inverse);
    final Float32List out = Float32List(16);
    final Float64List storage = boardToSource.storage;
    for (int i = 0; i < 16; i++) {
      out[i] = storage[i].toDouble();
    }
    return out;
  }

  Future<bool> _setRustLayerTransformPreview({
    required int handle,
    required int layerIndex,
    required _LayerTransformStateModel state,
    required bool enabled,
  }) async {
    final Float32List? matrix = _buildRustTransformMatrix(state);
    if (matrix == null) {
      return false;
    }
    return await CanvasEngineFfi.instance.setLayerTransformPreview(
      handle: handle,
      layerIndex: layerIndex,
      matrix: matrix,
      enabled: enabled,
      bilinear: _shouldUseTransformBilinear(),
    );
  }

  void _updateRustLayerTransformPreview() {
    if (!_layerTransformUsingRustPreview) {
      return;
    }
    final _LayerTransformStateModel? state = _layerTransformState;
    final int? handle = _rustCanvasEngineHandle;
    final int? layerIndex = _layerTransformRustLayerIndex;
    if (state == null || handle == null || layerIndex == null) {
      return;
    }
    unawaited(
      _setRustLayerTransformPreview(
        handle: handle,
        layerIndex: layerIndex,
        state: state,
        enabled: true,
      ),
    );
  }

  void _clearRustLayerTransformPreview() {
    if (!_layerTransformUsingRustPreview) {
      return;
    }
    final int? handle = _rustCanvasEngineHandle;
    final int? layerIndex = _layerTransformRustLayerIndex;
    if (handle != null && layerIndex != null && _layerTransformState != null) {
      unawaited(
        _setRustLayerTransformPreview(
          handle: handle,
          layerIndex: layerIndex,
          state: _layerTransformState!,
          enabled: false,
        ),
      );
    }
    _layerTransformUsingRustPreview = false;
    _layerTransformRustLayerIndex = null;
  }

  Future<bool> _applyRustLayerTransformPreview(
    _LayerTransformStateModel state,
  ) async {
    if (!_canUseRustCanvasEngine()) {
      return false;
    }
    final int? handle = _rustCanvasEngineHandle;
    final int? layerIndex = _layerTransformRustLayerIndex;
    if (handle == null || layerIndex == null) {
      return false;
    }
    final Float32List? matrix = _buildRustTransformMatrix(state);
    if (matrix == null) {
      return false;
    }
    return await CanvasEngineFfi.instance.applyLayerTransform(
      handle: handle,
      layerIndex: layerIndex,
      matrix: matrix,
      bilinear: _shouldUseTransformBilinear(),
    );
  }

  Future<bool> _applyRustLayerTransform({
    required BitmapLayerState layer,
    required _LayerTransformRenderResult result,
  }) async {
    if (!_canUseRustCanvasEngine()) {
      return false;
    }
    final int? handle = _rustCanvasEngineHandle;
    if (handle == null) {
      return false;
    }
    final int? layerIndex = _rustCanvasLayerIndexForId(layer.id);
    if (layerIndex == null) {
      return false;
    }
    final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
    final int canvasWidth = engineSize.width.round();
    final int canvasHeight = engineSize.height.round();
    if (canvasWidth <= 0 || canvasHeight <= 0) {
      return false;
    }
    if (layer.surface.width != canvasWidth ||
        layer.surface.height != canvasHeight) {
      return false;
    }
    final Uint32List pixels = _buildRustTransformPixels(
      result: result,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );
    return await CanvasEngineFfi.instance.writeLayer(
      handle: handle,
      layerIndex: layerIndex,
      pixels: pixels,
      recordUndo: true,
    );
  }

  Uint32List _buildRustTransformPixels({
    required _LayerTransformRenderResult result,
    required int canvasWidth,
    required int canvasHeight,
  }) {
    final Uint32List pixels = Uint32List(canvasWidth * canvasHeight);
    final int srcWidth = result.width;
    final int srcHeight = result.height;
    if (srcWidth <= 0 || srcHeight <= 0) {
      return pixels;
    }
    final int left = result.left;
    final int top = result.top;
    final int destLeft = math.max(0, left);
    final int destTop = math.max(0, top);
    final int destRight = math.min(canvasWidth, left + srcWidth);
    final int destBottom = math.min(canvasHeight, top + srcHeight);
    if (destLeft >= destRight || destTop >= destBottom) {
      return pixels;
    }
    final Uint8List rgba = result.rgba;
    final int rowWidth = destRight - destLeft;
    for (int y = destTop; y < destBottom; y++) {
      final int srcY = y - top;
      int srcIndex = (srcY * srcWidth + (destLeft - left)) * 4;
      int destIndex = y * canvasWidth + destLeft;
      for (int x = 0; x < rowWidth; x++) {
        final int r = rgba[srcIndex];
        final int g = rgba[srcIndex + 1];
        final int b = rgba[srcIndex + 2];
        final int a = rgba[srcIndex + 3];
        pixels[destIndex] = (a << 24) | (r << 16) | (g << 8) | b;
        srcIndex += 4;
        destIndex++;
      }
    }
    return pixels;
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
    final _LayerTransformHandle? fixedHandle = _layerTransformOppositeHandle(
      handle,
    );
    if (fixedHandle == null) {
      _layerTransformHandleFixedLocal = null;
      _layerTransformHandleFixedBoard = null;
    } else {
      final Offset fixedLocal = state.localHandlePosition(fixedHandle);
      _layerTransformHandleFixedLocal = fixedLocal;
      _layerTransformHandleFixedBoard = state.transformPoint(fixedLocal);
    }
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
        _updateRustLayerTransformPreview();
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
        _updateRustLayerTransformPreview();
        break;
      default:
        final Matrix4? inverse = _layerTransformPointerStartInverse;
        final Offset? anchorLocal = _layerTransformHandleAnchorLocal;
        final Offset? fixedLocal = _layerTransformHandleFixedLocal;
        final Offset? fixedBoard = _layerTransformHandleFixedBoard;
        if (inverse == null ||
            anchorLocal == null ||
            fixedLocal == null ||
            fixedBoard == null) {
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
        final double baseDx = handleLocal.dx - fixedLocal.dx;
        final double baseDy = handleLocal.dy - fixedLocal.dy;
        if (affectX && baseDx.abs() > 0.0001) {
          final double currentDx = localPoint.dx - fixedLocal.dx;
          nextScaleX = (currentDx / baseDx) * _layerTransformInitialScaleX;
        }
        if (affectY && baseDy.abs() > 0.0001) {
          final double currentDy = localPoint.dy - fixedLocal.dy;
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
        final Matrix4 transformWithoutTranslation = Matrix4.identity()
          ..translate(state.pivotLocal.dx, state.pivotLocal.dy)
          ..rotateZ(_layerTransformInitialRotation)
          ..scale(nextScaleX, nextScaleY)
          ..translate(-state.pivotLocal.dx, -state.pivotLocal.dy);
        final Offset fixedTransformed = MatrixUtils.transformPoint(
          transformWithoutTranslation,
          fixedLocal,
        );
        final Offset nextTranslation = fixedBoard - fixedTransformed;
        setState(() {
          state.translation = nextTranslation;
          state.scaleX = nextScaleX;
          state.scaleY = nextScaleY;
          _layerTransformRevision++;
        });
        _updateRustLayerTransformPreview();
        break;
    }
  }

  void _handleLayerTransformPointerUp() {
    _activeLayerTransformHandle = null;
    _layerTransformPointerStartInverse = null;
    _layerTransformHandleAnchorLocal = null;
    _layerTransformHandleFixedLocal = null;
    _layerTransformHandleFixedBoard = null;
  }

  void _handleLayerTransformPointerCancel() {
    _activeLayerTransformHandle = null;
    _layerTransformPointerStartInverse = null;
    _layerTransformHandleAnchorLocal = null;
    _layerTransformHandleFixedLocal = null;
    _layerTransformHandleFixedBoard = null;
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
                boardLocal!.dx * _viewport.scale,
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
    final double boardScale = _viewport.scale;
    final double hitRadius = _layerTransformHandleHitRadius(state, boardScale);
    final double rotationDistance =
        _layerTransformRotationHandleDistance(state, boardScale);
    final List<Offset> corners = state.corners;
    Offset handlePosition(_LayerTransformHandle handle) {
      return state.handlePosition(
        handle,
        rotationHandleDistance: rotationDistance,
      );
    }
    _LayerTransformHandle? pickHandle(_LayerTransformHandle handle) {
      if (handle == _LayerTransformHandle.translate) {
        return null;
      }
      if (handle == _LayerTransformHandle.rotation) {
        final Offset position = handlePosition(handle);
        if ((boardLocal - position).distance <= hitRadius) {
          return handle;
        }
        return null;
      }
      final Offset position = handlePosition(handle);
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
    final double rotationHitRadius =
        _layerTransformRotationHitRadius(state, boardScale);
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
    if (_layerTransformUsingRustPreview) {
      return null;
    }
    final _LayerTransformStateModel? state = _layerTransformState;
    if (state == null) {
      return null;
    }
    final ui.Image? image = state.image;
    if (image == null) {
      return null;
    }
    final double opacity = _controller.activeLayerTransformOpacity;
    final ui.BlendMode? blendMode = _flutterBlendMode(
      _controller.activeLayerTransformBlendMode,
    );
    final FilterQuality filterQuality = _shouldUseTransformBilinear()
        ? FilterQuality.high
        : FilterQuality.none;
    Widget content = RawImage(
      image: image,
      filterQuality: filterQuality,
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
    const Color lineColor = _kLayerTransformOverlayColor;
    const Color highlightColor = _kLayerTransformOverlayHighlightColor;
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
    return _buildLayerTransformPanelBody();
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
