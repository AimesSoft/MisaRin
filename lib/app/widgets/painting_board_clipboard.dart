part of 'painting_board.dart';

class _ClipboardPayload {
  _ClipboardPayload({required this.layerData});

  final CanvasLayerData layerData;
}

mixin _PaintingBoardClipboardMixin on _PaintingBoardBase {
  _ClipboardPayload? _clipboard;

  Future<bool> cut() {
    return _copyActiveLayer(clearAfter: true);
  }

  Future<bool> copy() {
    return _copyActiveLayer(clearAfter: false);
  }

  Future<bool> paste() {
    return _performPaste();
  }

  Future<bool> deleteSelection() {
    return _deleteSelectionContent();
  }

  Future<bool> _copyActiveLayer({required bool clearAfter}) async {
    // 魔棒预览需要先固化为正式选区，否则复制/剪切会忽略选区。
    _convertMagicWandPreviewToSelection();
    await _controller.waitForPendingWorkerTasks();

    final String? activeLayerId = _activeLayerId;
    if (activeLayerId == null) {
      return false;
    }
    bool undoCaptured = false;
    if (_canUseRustCanvasEngine()) {
      final bool needsUndo = clearAfter;
      if (needsUndo) {
        await _pushUndoSnapshot();
        undoCaptured = true;
      }
      final bool handled = await _copyActiveLayerFromRust(
        activeLayerId: activeLayerId,
        clearAfter: clearAfter,
      );
      if (handled) {
        if (!clearAfter) {
          return true;
        }
        final Uint8List? selection = selectionMaskSnapshot;
        _controller.clearLayerRegion(activeLayerId, mask: selection);
        setState(() {
          setSelectionState(path: null, mask: null);
          clearSelectionArtifacts();
        });
        _updateSelectionAnimation();
        _markDirty();
        return true;
      }
    }
    final Uint8List? selection = selectionMaskSnapshot;
    final CanvasLayerData? layer = _controller.buildClipboardLayer(
      activeLayerId,
      mask: selection,
    );
    if (layer == null) {
      return false;
    }
    _clipboard = _ClipboardPayload(layerData: layer.copyWith());
    if (!clearAfter) {
      return true;
    }
    if (!undoCaptured) {
      await _pushUndoSnapshot();
    }
    _controller.clearLayerRegion(activeLayerId, mask: selection);
    setState(() {
      setSelectionState(path: null, mask: null);
      clearSelectionArtifacts();
    });
    _updateSelectionAnimation();
    _markDirty();
    return true;
  }

  Future<bool> _deleteSelectionContent() async {
    _convertMagicWandPreviewToSelection();
    await _controller.waitForPendingWorkerTasks();

    final String? activeLayerId = _activeLayerId;
    if (activeLayerId == null) {
      return false;
    }
    final Uint8List? selection = selectionMaskSnapshot;
    if (selection == null || !_maskHasCoverage(selection)) {
      return false;
    }
    await _pushUndoSnapshot();
    if (_canUseRustCanvasEngine()) {
      await _deleteSelectionFromRust(activeLayerId: activeLayerId);
    }
    _controller.clearLayerRegion(activeLayerId, mask: selection);
    setState(() {
      setSelectionState(path: null, mask: null);
      clearSelectionArtifacts();
    });
    _updateSelectionAnimation();
    _markDirty();
    return true;
  }

  Future<bool> _performPaste() async {
    final _ClipboardPayload? payload = _clipboard;
    if (payload == null) {
      return _pasteImageFromSystemClipboard();
    }
    final CanvasLayerData source = payload.layerData;
    final String newId = generateLayerId();
    final String pasteName = source.name.isEmpty ? '粘贴图层' : '${source.name} 副本';
    final CanvasLayerData layerData = source.copyWith(
      id: newId,
      name: pasteName,
      visible: true,
      locked: false,
      clippingMask: false,
    );
    await _pushUndoSnapshot();
    _controller.insertLayerFromData(layerData, aboveLayerId: _activeLayerId);
    _controller.setActiveLayer(newId);
    if (_canUseRustCanvasEngine()) {
      _syncRustCanvasLayersToEngine();
      await _pasteLayerToRust(layerId: newId, layerData: layerData);
    }
    setState(() {
      setSelectionState(path: null, mask: null);
      clearSelectionArtifacts();
    });
    _updateSelectionAnimation();
    _markDirty();
    return true;
  }

  BitmapLayerState? _resolveActiveLayerState(String id) {
    for (final BitmapLayerState layer in _controller.layers) {
      if (layer.id == id) {
        return layer;
      }
    }
    return null;
  }

  bool _maskHasCoverage(Uint8List mask) {
    for (final int value in mask) {
      if (value != 0) {
        return true;
      }
    }
    return false;
  }

  Uint32List _applySelectionMaskToPixels(
    Uint32List source,
    Uint8List? mask,
  ) {
    if (mask == null) {
      return Uint32List.fromList(source);
    }
    final Uint32List output = Uint32List(source.length);
    final int limit = math.min(source.length, mask.length);
    for (int i = 0; i < limit; i++) {
      if (mask[i] != 0) {
        output[i] = source[i];
      }
    }
    return output;
  }

  Uint32List _clearSelectionInPixels(
    Uint32List source,
    Uint8List? mask,
  ) {
    if (mask == null) {
      return Uint32List(source.length);
    }
    final Uint32List output = Uint32List.fromList(source);
    final int limit = math.min(source.length, mask.length);
    for (int i = 0; i < limit; i++) {
      if (mask[i] != 0) {
        output[i] = 0;
      }
    }
    return output;
  }

  Uint32List? _resolveRustPastePixels(
    CanvasLayerData layer,
    int width,
    int height,
  ) {
    final int? srcWidth = layer.bitmapWidth;
    final int? srcHeight = layer.bitmapHeight;
    Uint32List? srcPixels = layer.rawPixels;
    if (srcPixels == null) {
      final Uint8List? rgba = layer.bitmap;
      if (rgba == null || srcWidth == null || srcHeight == null) {
        return null;
      }
      srcPixels = BitmapCanvasController.rgbaToPixels(rgba, srcWidth, srcHeight);
    }
    if (srcWidth == null ||
        srcHeight == null ||
        srcPixels.length != srcWidth * srcHeight) {
      return null;
    }
    final int left = layer.bitmapLeft ?? 0;
    final int top = layer.bitmapTop ?? 0;
    if (srcWidth == width && srcHeight == height && left == 0 && top == 0) {
      return srcPixels;
    }
    final Uint32List dest = Uint32List(width * height);
    for (int y = 0; y < srcHeight; y++) {
      final int destY = y + top;
      if (destY < 0 || destY >= height) {
        continue;
      }
      final int srcRow = y * srcWidth;
      final int destRow = destY * width;
      for (int x = 0; x < srcWidth; x++) {
        final int destX = x + left;
        if (destX < 0 || destX >= width) {
          continue;
        }
        dest[destRow + destX] = srcPixels[srcRow + x];
      }
    }
    return dest;
  }

  Future<bool> _copyActiveLayerFromRust({
    required String activeLayerId,
    required bool clearAfter,
  }) async {
    final int? handle = _rustCanvasEngineHandle;
    if (!_canUseRustCanvasEngine() || handle == null) {
      return false;
    }
    final BitmapLayerState? layer = _resolveActiveLayerState(activeLayerId);
    if (layer == null) {
      return false;
    }
    final int? layerIndex = _rustCanvasLayerIndexForId(activeLayerId);
    if (layerIndex == null) {
      return false;
    }
    final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return false;
    }
    final Uint32List? sourcePixels = await CanvasEngineFfi.instance.readLayer(
      handle: handle,
      layerIndex: layerIndex,
      width: width,
      height: height,
    );
    if (sourcePixels == null) {
      return false;
    }
    final Uint8List? selectionMask =
        _resolveSelectionMaskForRust(width, height);
    if (selectionMask != null && !_maskHasCoverage(selectionMask)) {
      return false;
    }
    final Uint32List clipboardPixels =
        _applySelectionMaskToPixels(sourcePixels, selectionMask);
    _clipboard = _ClipboardPayload(
      layerData: CanvasLayerData(
        id: layer.id,
        name: layer.name,
        visible: true,
        opacity: layer.opacity,
        locked: false,
        clippingMask: false,
        blendMode: layer.blendMode,
        rawPixels: clipboardPixels,
        bitmapWidth: width,
        bitmapHeight: height,
        bitmapLeft: 0,
        bitmapTop: 0,
      ),
    );
    if (!clearAfter) {
      return true;
    }
    final Uint32List clearedPixels =
        _clearSelectionInPixels(sourcePixels, selectionMask);
    final bool applied = await CanvasEngineFfi.instance.writeLayer(
      handle: handle,
      layerIndex: layerIndex,
      pixels: clearedPixels,
      recordUndo: true,
    );
    if (applied) {
      _recordRustHistoryAction(layerId: activeLayerId);
      if (mounted) {
        setState(() {});
      }
      _markDirty();
    }
    return applied;
  }

  Future<bool> _deleteSelectionFromRust({required String activeLayerId}) async {
    final int? handle = _rustCanvasEngineHandle;
    if (!_canUseRustCanvasEngine() || handle == null) {
      return false;
    }
    final int? layerIndex = _rustCanvasLayerIndexForId(activeLayerId);
    if (layerIndex == null) {
      return false;
    }
    final Size engineSize = _rustCanvasEngineSize ?? _canvasSize;
    final int width = engineSize.width.round();
    final int height = engineSize.height.round();
    if (width <= 0 || height <= 0) {
      return false;
    }
    final Uint8List? selectionMask =
        _resolveSelectionMaskForRust(width, height);
    if (selectionMask == null || !_maskHasCoverage(selectionMask)) {
      return false;
    }
    final Uint32List? sourcePixels = await CanvasEngineFfi.instance.readLayer(
      handle: handle,
      layerIndex: layerIndex,
      width: width,
      height: height,
    );
    if (sourcePixels == null) {
      return false;
    }
    final Uint32List clearedPixels =
        _clearSelectionInPixels(sourcePixels, selectionMask);
    final bool applied = await CanvasEngineFfi.instance.writeLayer(
      handle: handle,
      layerIndex: layerIndex,
      pixels: clearedPixels,
      recordUndo: true,
    );
    if (applied) {
      _recordRustHistoryAction(layerId: activeLayerId);
      if (mounted) {
        setState(() {});
      }
      _markDirty();
    }
    return applied;
  }

  Future<bool> _pasteLayerToRust({
    required String layerId,
    required CanvasLayerData layerData,
  }) async {
    final int? handle = _rustCanvasEngineHandle;
    if (!_canUseRustCanvasEngine() || handle == null) {
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
    final Uint32List pixels =
        _resolveRustPastePixels(layerData, width, height) ??
        Uint32List(width * height);
    final bool applied = await CanvasEngineFfi.instance.writeLayer(
      handle: handle,
      layerIndex: layerIndex,
      pixels: pixels,
      recordUndo: true,
    );
    if (applied) {
      _recordRustHistoryAction(layerId: layerId);
      if (mounted) {
        setState(() {});
      }
      _markDirty();
    }
    return applied;
  }

  Future<bool> _pasteImageFromSystemClipboard() async {
    final ClipboardImageData? payload = await ClipboardImageReader.readImage();
    if (payload == null) {
      return false;
    }
    return insertImageLayerFromBytes(payload.bytes, name: payload.fileName);
  }
}
