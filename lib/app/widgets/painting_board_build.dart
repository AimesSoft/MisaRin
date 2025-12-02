part of 'painting_board.dart';

mixin _PaintingBoardBuildMixin
    on
        _PaintingBoardBase,
        _PaintingBoardLayerTransformMixin,
        _PaintingBoardInteractionMixin,
        _PaintingBoardPaletteMixin,
        _PaintingBoardReferenceMixin,
        _PaintingBoardFilterMixin {
  @override
  Widget build(BuildContext context) {
    _refreshStylusPreferencesIfNeeded();
    _refreshHistoryLimit();
    final bool canUndo = this.canUndo || widget.externalCanUndo;
    final bool canRedo = this.canRedo || widget.externalCanRedo;
    final Map<LogicalKeySet, Intent> shortcutBindings = {
      for (final key in ToolbarShortcuts.of(ToolbarAction.undo).shortcuts)
        key: const UndoIntent(),
      for (final key in ToolbarShortcuts.of(ToolbarAction.redo).shortcuts)
        key: const RedoIntent(),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.resizeImage,
      ).shortcuts)
        key: const ResizeImageIntent(),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.resizeCanvas,
      ).shortcuts)
        key: const ResizeCanvasIntent(),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.adjustHueSaturation,
      ).shortcuts)
        key: const AdjustHueSaturationIntent(),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.adjustBrightnessContrast,
      ).shortcuts)
        key: const AdjustBrightnessContrastIntent(),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.gaussianBlur,
      ).shortcuts)
        key: const AdjustGaussianBlurIntent(),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.layerAntialiasPanel,
      ).shortcuts)
        key: const ShowLayerAntialiasIntent(),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.freeTransform,
      ).shortcuts)
        key: const LayerFreeTransformIntent(),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.layerAdjustTool,
      ).shortcuts)
        key: const SelectToolIntent(CanvasTool.layerAdjust),
      for (final key in ToolbarShortcuts.of(ToolbarAction.penTool).shortcuts)
        key: const SelectToolIntent(CanvasTool.pen),
      for (final key in ToolbarShortcuts.of(ToolbarAction.sprayTool).shortcuts)
        key: const SelectToolIntent(CanvasTool.spray),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.curvePenTool,
      ).shortcuts)
        key: const SelectToolIntent(CanvasTool.curvePen),
      for (final key in ToolbarShortcuts.of(ToolbarAction.shapeTool).shortcuts)
        key: const SelectToolIntent(CanvasTool.shape),
      for (final key in ToolbarShortcuts.of(ToolbarAction.eraserTool).shortcuts)
        key: const SelectToolIntent(CanvasTool.eraser),
      for (final key in ToolbarShortcuts.of(ToolbarAction.bucketTool).shortcuts)
        key: const SelectToolIntent(CanvasTool.bucket),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.magicWandTool,
      ).shortcuts)
        key: const SelectToolIntent(CanvasTool.magicWand),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.eyedropperTool,
      ).shortcuts)
        key: const SelectToolIntent(CanvasTool.eyedropper),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.selectionTool,
      ).shortcuts)
        key: const SelectToolIntent(CanvasTool.selection),
      for (final key in ToolbarShortcuts.of(ToolbarAction.handTool).shortcuts)
        key: const SelectToolIntent(CanvasTool.hand),
      for (final key in ToolbarShortcuts.of(ToolbarAction.exit).shortcuts)
        key: const ExitBoardIntent(),
      for (final key in ToolbarShortcuts.of(ToolbarAction.deselect).shortcuts)
        key: const DeselectIntent(),
      for (final key in ToolbarShortcuts.of(
        ToolbarAction.importReferenceImage,
      ).shortcuts)
        key: const ImportReferenceImageIntent(),
      LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyX):
          const CutIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyX):
          const CutIntent(),
      LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyC):
          const CopyIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyC):
          const CopyIntent(),
      LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyV):
          const PasteIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyV):
          const PasteIntent(),
    };

    final theme = FluentTheme.of(context);
    final bool isDark = theme.brightness.isDark;
    final Color workspaceColor = isDark
        ? const Color(0xFF1B1B1F)
        : const Color(0xFFE5E5E5);

    return LayoutBuilder(
      builder: (context, constraints) {
        final Size candidate = constraints.biggest;
        if (candidate.width.isFinite && candidate.height.isFinite) {
          _workspaceSize = candidate;
        }
        _scheduleWorkspaceMeasurement(context);
        _initializeViewportIfNeeded();
        _layoutBaseOffset = _baseOffsetForScale(_viewport.scale);
        final BoardLayoutMetrics? layoutMetrics = _layoutMetrics;
        final CanvasToolbarLayout toolbarLayout =
            layoutMetrics?.layout ?? _toolbarLayout;
        final double toolSettingsLeft =
            layoutMetrics?.toolSettingsLeft ??
            (_toolButtonPadding + toolbarLayout.width + _toolSettingsSpacing);
        final double sidebarLeft =
            layoutMetrics?.sidebarLeft ??
            (_workspaceSize.width - _sidePanelWidth - _toolButtonPadding).clamp(
              0.0,
              double.infinity,
            );
        final double? toolSettingsMaxWidth =
            layoutMetrics?.toolSettingsMaxWidth ??
            (() {
              final double computed =
                  sidebarLeft - toolSettingsLeft - _toolSettingsSpacing;
              return computed.isFinite && computed > 0 ? computed : null;
            })();
        final Rect boardRect = _boardRect;
        final ToolCursorStyle? cursorStyle = ToolCursorStyles.styleFor(
          _effectiveActiveTool,
        );
        final bool hideCursorBecauseToolOverlay =
            cursorStyle != null &&
            _toolCursorPosition != null &&
            cursorStyle.hideSystemCursor;
        final bool hideCursorBecausePen =
            _penRequiresOverlay && _penCursorWorkspacePosition != null;
        final bool hideCursorBecauseReferenceResize = _isReferenceCardResizing;
        final bool hideCursorBecauseLayerTransform =
            _shouldHideCursorForLayerTransform;
        final bool shouldHideCursor =
            hideCursorBecauseToolOverlay ||
            hideCursorBecausePen ||
            hideCursorBecauseReferenceResize ||
            hideCursorBecauseLayerTransform;
        final bool isLayerAdjustDragging =
            _effectiveActiveTool == CanvasTool.layerAdjust && _isLayerDragging;
        final double overlayBrushDiameter =
            _effectiveActiveTool == CanvasTool.spray
            ? _sprayStrokeWidth
            : _penStrokeWidth;
        final BrushShape overlayBrushShape =
            _effectiveActiveTool == CanvasTool.spray
            ? BrushShape.circle
            : _brushShape;
        final Widget? antialiasCard = _buildAntialiasCard();
        final Widget? transformPanel = buildLayerTransformPanel();
        final Widget? transformCursorOverlay = buildLayerTransformCursorOverlay(
          theme,
        );

        final bool transformActive = _isLayerFreeTransformActive;
        final MouseCursor boardCursor;
        if (shouldHideCursor) {
          boardCursor = SystemMouseCursors.none;
        } else if (transformActive) {
          boardCursor = SystemMouseCursors.basic;
        } else if (_effectiveActiveTool == CanvasTool.layerAdjust) {
          boardCursor = _isLayerDragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.move;
        } else {
          boardCursor = MouseCursor.defer;
        }

        final MouseCursor workspaceCursor;
        if (shouldHideCursor) {
          workspaceCursor = SystemMouseCursors.none;
        } else {
          if (transformActive) {
            workspaceCursor = SystemMouseCursors.basic;
          } else {
            switch (_effectiveActiveTool) {
              case CanvasTool.hand:
                workspaceCursor = _isDraggingBoard
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.grab;
                break;
              case CanvasTool.layerAdjust:
                workspaceCursor = _isLayerDragging
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.move;
                break;
              case CanvasTool.curvePen:
                workspaceCursor = SystemMouseCursors.precise;
                break;
              case CanvasTool.shape:
                workspaceCursor = SystemMouseCursors.precise;
                break;
              case CanvasTool.eraser:
                workspaceCursor = SystemMouseCursors.precise;
                break;
              case CanvasTool.eyedropper:
                workspaceCursor = SystemMouseCursors.basic;
                break;
              default:
                workspaceCursor = SystemMouseCursors.basic;
                break;
            }
          }
        }

        final PaintingToolbarLayoutStyle toolbarStyle =
            widget.toolbarLayoutStyle;
        final bool isSai2Layout =
            toolbarStyle == PaintingToolbarLayoutStyle.sai2;
        final bool includeHistoryOnToolbar = _includeHistoryOnToolbar;
        final CanvasToolbarLayout activeToolbarLayout =
            _resolveToolbarLayoutForStyle(
              toolbarStyle,
              toolbarLayout,
              includeHistoryButtons: includeHistoryOnToolbar,
            );
        final Widget toolbarWidget = CanvasToolbar(
          activeTool: _activeTool,
          selectionShape: selectionShape,
          shapeToolVariant: shapeToolVariant,
          onToolSelected: _setActiveTool,
          onUndo: _handleUndo,
          onRedo: _handleRedo,
          canUndo: canUndo,
          canRedo: canRedo,
          layout: activeToolbarLayout,
          includeHistoryButtons: includeHistoryOnToolbar,
        );
        final Widget toolSettingsCard = ToolSettingsCard(
          activeTool: _activeTool,
          penStrokeWidth: _penStrokeWidth,
          sprayStrokeWidth: _sprayStrokeWidth,
          sprayMode: _sprayMode,
          penStrokeSliderRange: _penStrokeSliderRange,
          onPenStrokeWidthChanged: _updatePenStrokeWidth,
          onSprayStrokeWidthChanged: _updateSprayStrokeWidth,
          onSprayModeChanged: _updateSprayMode,
          brushShape: _brushShape,
          onBrushShapeChanged: _updateBrushShape,
          strokeStabilizerStrength: _strokeStabilizerStrength,
          onStrokeStabilizerChanged: _updateStrokeStabilizerStrength,
          stylusPressureEnabled: _stylusPressureEnabled,
          onStylusPressureEnabledChanged: _updateStylusPressureEnabled,
          simulatePenPressure: _simulatePenPressure,
          onSimulatePenPressureChanged: _updatePenPressureSimulation,
          penPressureProfile: _penPressureProfile,
          onPenPressureProfileChanged: _updatePenPressureProfile,
          brushAntialiasLevel: _penAntialiasLevel,
          onBrushAntialiasChanged: _updatePenAntialiasLevel,
          autoSharpPeakEnabled: _autoSharpPeakEnabled,
          onAutoSharpPeakChanged: _updateAutoSharpPeakEnabled,
          bucketSampleAllLayers: _bucketSampleAllLayers,
          bucketContiguous: _bucketContiguous,
          bucketSwallowColorLine: _bucketSwallowColorLine,
          bucketAntialiasLevel: _bucketAntialiasLevel,
          onBucketSampleAllLayersChanged: _updateBucketSampleAllLayers,
          onBucketContiguousChanged: _updateBucketContiguous,
          onBucketSwallowColorLineChanged: _updateBucketSwallowColorLine,
          onBucketAntialiasChanged: _updateBucketAntialiasLevel,
          bucketTolerance: _bucketTolerance,
          onBucketToleranceChanged: _updateBucketTolerance,
          layerAdjustCropOutside: _layerAdjustCropOutside,
          onLayerAdjustCropOutsideChanged: _updateLayerAdjustCropOutside,
          selectionShape: selectionShape,
          onSelectionShapeChanged: _updateSelectionShape,
          shapeToolVariant: shapeToolVariant,
          onShapeToolVariantChanged: _updateShapeToolVariant,
          shapeFillEnabled: _shapeFillEnabled,
          onShapeFillChanged: _updateShapeFillEnabled,
          onSizeChanged: _updateToolSettingsCardSize,
          magicWandTolerance: _magicWandTolerance,
          onMagicWandToleranceChanged: _updateMagicWandTolerance,
          brushToolsEraserMode: _brushToolsEraserMode,
          onBrushToolsEraserModeChanged: _updateBrushToolsEraserMode,
          vectorDrawingEnabled: _vectorDrawingEnabled,
          onVectorDrawingEnabledChanged: _updateVectorDrawingEnabled,
          strokeStabilizerMaxLevel: _strokeStabilizerMaxLevel,
          compactLayout: isSai2Layout,
        );
        final ToolbarPanelData colorPanelData = ToolbarPanelData(
          title: '取色',
          trailing: _buildColorPanelTrailing(theme),
          child: _buildColorPanelContent(theme),
        );
        final Widget addLayerButton = _buildAddLayerButton();
        final ToolbarPanelData layerPanelData = ToolbarPanelData(
          title: '图层管理',
          trailing: isSai2Layout ? addLayerButton : null,
          child: _buildLayerPanelContent(theme),
          expand: true,
        );
        final PaintingToolbarElements toolbarElements = PaintingToolbarElements(
          toolbar: toolbarWidget,
          toolSettings: toolSettingsCard,
          colorIndicator: _buildColorIndicator(theme),
          colorPanel: colorPanelData,
          layerPanel: layerPanelData,
          exitButton: null,
        );
        final WorkspaceLayoutSplits workspaceSplits = WorkspaceLayoutSplits(
          floatingColorPanelHeight: _floatingColorPanelHeight,
          floatingColorPanelMeasuredHeight: _floatingColorPanelMeasuredHeight,
          onFloatingColorPanelHeightChanged: _setFloatingColorPanelHeight,
          onFloatingColorPanelMeasured: _handleFloatingColorPanelMeasured,
          sai2ColorPanelHeight: _sai2ColorPanelHeight,
          sai2ColorPanelMeasuredHeight: _sai2ColorPanelMeasuredHeight,
          onSai2ColorPanelHeightChanged: _setSai2ColorPanelHeight,
          onSai2ColorPanelMeasured: _handleSai2ColorPanelMeasured,
          sai2ToolbarSectionRatio: _sai2ToolSectionRatio,
          onSai2ToolbarSectionRatioChanged: _setSai2ToolSectionRatio,
          sai2LayerPanelWidthRatio: _sai2LayerPanelWidthRatio,
          onSai2LayerPanelWidthRatioChanged: _setSai2LayerPanelWidthRatio,
        );
        final PaintingToolbarMetrics toolbarMetrics = PaintingToolbarMetrics(
          toolbarLayout: activeToolbarLayout,
          toolSettingsSize: _toolSettingsCardSize,
          workspaceSize: _workspaceSize,
          toolButtonPadding: _toolButtonPadding,
          toolSettingsSpacing: _toolSettingsSpacing,
          sidePanelWidth: _sidePanelWidth,
          sidePanelSpacing: _sidePanelSpacing,
          colorIndicatorSize: _colorIndicatorSize,
          toolSettingsLeft: toolSettingsLeft,
          sidebarLeft: sidebarLeft,
          toolSettingsMaxWidth: toolSettingsMaxWidth,
          workspaceSplits: workspaceSplits,
        );
        final PaintingToolbarLayoutDelegate toolbarLayoutDelegate =
            toolbarStyle == PaintingToolbarLayoutStyle.sai2
            ? const Sai2ToolbarLayoutDelegate()
            : const FloatingToolbarLayoutDelegate();
        final PaintingToolbarLayoutResult toolbarLayoutResult =
            toolbarLayoutDelegate.build(
              context,
              toolbarElements,
              toolbarMetrics,
            );
        _toolbarHitRegions = toolbarLayoutResult.hitRegions;
        _ensureToolbarDoesNotOverlapColorIndicator();

        return Shortcuts(
          shortcuts: shortcutBindings,
          child: Actions(
            actions: <Type, Action<Intent>>{
              UndoIntent: CallbackAction<UndoIntent>(
                onInvoke: (intent) {
                  _handleUndo();
                  return null;
                },
              ),
              RedoIntent: CallbackAction<RedoIntent>(
                onInvoke: (intent) {
                  _handleRedo();
                  return null;
                },
              ),
              SelectToolIntent: CallbackAction<SelectToolIntent>(
                onInvoke: (intent) {
                  _setActiveTool(intent.tool);
                  return null;
                },
              ),
              ExitBoardIntent: CallbackAction<ExitBoardIntent>(
                onInvoke: (intent) {
                  widget.onRequestExit();
                  return null;
                },
              ),
              DeselectIntent: CallbackAction<DeselectIntent>(
                onInvoke: (intent) {
                  _clearSelection();
                  return null;
                },
              ),
              CutIntent: CallbackAction<CutIntent>(
                onInvoke: (intent) {
                  unawaited(cut());
                  return null;
                },
              ),
              CopyIntent: CallbackAction<CopyIntent>(
                onInvoke: (intent) {
                  unawaited(copy());
                  return null;
                },
              ),
              PasteIntent: CallbackAction<PasteIntent>(
                onInvoke: (intent) {
                  unawaited(paste());
                  return null;
                },
              ),
              ResizeImageIntent: CallbackAction<ResizeImageIntent>(
                onInvoke: (intent) {
                  widget.onResizeImage?.call();
                  return null;
                },
              ),
              ResizeCanvasIntent: CallbackAction<ResizeCanvasIntent>(
                onInvoke: (intent) {
                  widget.onResizeCanvas?.call();
                  return null;
                },
              ),
              AdjustHueSaturationIntent:
                  CallbackAction<AdjustHueSaturationIntent>(
                    onInvoke: (intent) {
                      showHueSaturationAdjustments();
                      return null;
                    },
                  ),
              AdjustBrightnessContrastIntent:
                  CallbackAction<AdjustBrightnessContrastIntent>(
                    onInvoke: (intent) {
                      showBrightnessContrastAdjustments();
                      return null;
                    },
                  ),
              AdjustGaussianBlurIntent:
                  CallbackAction<AdjustGaussianBlurIntent>(
                    onInvoke: (intent) {
                      showGaussianBlurAdjustments();
                      return null;
                    },
                  ),
              ShowLayerAntialiasIntent:
                  CallbackAction<ShowLayerAntialiasIntent>(
                    onInvoke: (intent) {
                      showLayerAntialiasPanel();
                      return null;
                    },
                  ),
              LayerFreeTransformIntent:
                  CallbackAction<LayerFreeTransformIntent>(
                    onInvoke: (intent) {
                      toggleLayerFreeTransform();
                      return null;
                    },
                  ),
              ImportReferenceImageIntent:
                  CallbackAction<ImportReferenceImageIntent>(
                    onInvoke: (intent) {
                      unawaited(importReferenceImageCard());
                      return null;
                    },
                  ),
            },
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: _handleWorkspaceKeyEvent,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                onScaleEnd: _handleScaleEnd,
                child: MouseRegion(
                  cursor: workspaceCursor,
                  onExit: (_) => _handleWorkspacePointerExit(),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _handlePointerDown,
                    onPointerMove: _handlePointerMove,
                    onPointerUp: _handlePointerUp,
                    onPointerCancel: _handlePointerCancel,
                    onPointerSignal: _handlePointerSignal,
                    onPointerHover: _handlePointerHover,
                    child: Container(
                      color: workspaceColor,
                      child: Stack(
                        children: [
                          Positioned(
                            left: boardRect.left,
                            top: boardRect.top,
                            child: MouseRegion(
                              cursor: boardCursor,
                              child: Transform.scale(
                                scale: _viewport.scale,
                                alignment: Alignment.topLeft,
                                child: SizedBox(
                                  width: _canvasSize.width,
                                  height: _canvasSize.height,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: isDark
                                            ? Color.lerp(
                                                Colors.white,
                                                Colors.transparent,
                                                0.88,
                                              )!
                                            : const Color(0x33000000),
                                        width: 1,
                                      ),
                                    ),
                                    child: ClipRect(
                                      child: RepaintBoundary(
                                        child: AnimatedBuilder(
                                          animation: _controller,
                                          builder: (context, _) {
                                            final BitmapCanvasFrame? frame =
                                                _controller.frame;
                                            if (frame == null) {
                                              return ColoredBox(
                                                color:
                                                    _controller.backgroundColor,
                                              );
                                            }
                                            final bool isTransforming =
                                                _controller
                                                    .isActiveLayerTransforming;
                                            final ui.Image?
                                            transformedActiveLayerImage =
                                                _controller
                                                    .activeLayerTransformImage;
                                            final Offset
                                            transformedLayerOffset = _controller
                                                .activeLayerTransformOffset;
                                            final double
                                            transformedLayerOpacity = _controller
                                                .activeLayerTransformOpacity;
                                            final ui.BlendMode?
                                            transformedLayerBlendMode =
                                                _flutterBlendMode(
                                                  _controller
                                                      .activeLayerTransformBlendMode,
                                                );
                                            final bool hasSelectionOverlay =
                                                selectionPath != null ||
                                                selectionPreviewPath != null ||
                                                magicWandPreviewPath != null;
                                            final Widget?
                                            transformImageOverlay =
                                                _isLayerFreeTransformActive
                                                ? buildLayerTransformImageOverlay()
                                                : null;
                                            final Widget?
                                            transformHandlesOverlay =
                                                _isLayerFreeTransformActive
                                                ? buildLayerTransformHandlesOverlay(
                                                    theme,
                                                  )
                                                : null;

                                            // 客户端预测：显示当前笔画的实时预览，以及正在提交中的笔画，解决 worker 延迟导致的滞后感和闪烁
                                            final bool canPreviewStroke =
                                                _effectiveActiveTool ==
                                                    CanvasTool.pen ||
                                                _effectiveActiveTool ==
                                                    CanvasTool.eraser;
                                            final bool hasActiveStroke =
                                                canPreviewStroke &&
                                                _controller
                                                    .activeStrokePoints
                                                    .isNotEmpty;
                                            final bool showActiveStroke =
                                                _vectorDrawingEnabled &&
                                                !_isLayerFreeTransformActive &&
                                                !_controller
                                                    .isActiveLayerTransforming &&
                                                (hasActiveStroke ||
                                                    _controller
                                                        .committingStrokes
                                                        .isNotEmpty);
                                            final bool activeStrokeIsEraser =
                                                _controller
                                                    .activeStrokeEraseMode;
                                            final Path? pendingFillOverlayPath =
                                                shapeVectorFillOverlayPath;
                                            final Color?
                                            pendingFillOverlayColor =
                                                shapeVectorFillOverlayColor;

                                            return Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                _CheckboardBackground(
                                                  cellSize: 8.0,
                                                  lightColor: theme.brightness.isDark ? const Color(0xFF242424) : const Color(0xFFF5F5F5),
                                                  darkColor: theme.brightness.isDark ? const Color(0xFF1C1C1C) : const Color(0xFFE0E0E0),
                                                ),
                                                if (_filterSession != null &&
                                                    _previewActiveLayerImage !=
                                                        null)
                                                  _buildFilterPreviewStack()
                                                else if (_layerOpacityPreviewActive &&
                                                    _layerOpacityPreviewActiveLayerImage !=
                                                        null)
                                                  _buildLayerOpacityPreviewStack()
                                                else
                                                  BitmapCanvasSurface(
                                                    frame: frame,
                                                  ),
                                                if (_pixelGridVisible)
                                                  Positioned.fill(
                                                    child: IgnorePointer(
                                                      ignoring: true,
                                                      child: CustomPaint(
                                                        painter:
                                                            _PixelGridPainter(
                                                              pixelWidth:
                                                                  _controller
                                                                      .width,
                                                              pixelHeight:
                                                                  _controller
                                                                      .height,
                                                              color:
                                                                  _pixelGridColor,
                                                              scale: _viewport
                                                                  .scale,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                if (showActiveStroke)
                                                  Positioned.fill(
                                                    child: CustomPaint(
                                                      painter: _ActiveStrokeOverlayPainter(
                                                        points: _controller.activeStrokePoints,
                                                        radii: _controller.activeStrokeRadii,
                                                        color: _controller.activeStrokeColor,
                                                        shape: _controller.activeStrokeShape,
                                                        committingStrokes:
                                                            _controller.committingStrokes,
                                                        activeStrokeIsEraser:
                                                            activeStrokeIsEraser,
                                                        eraserPreviewColor:
                                                            _kVectorEraserPreviewColor,
                                                        antialiasLevel: _penAntialiasLevel, // Added missing required parameter
                                                      ),
                                                    ),
                                                  ),
                                                if (transformImageOverlay !=
                                                    null)
                                                  transformImageOverlay
                                                else if (!_isLayerFreeTransformActive &&
                                                    isTransforming &&
                                                    transformedActiveLayerImage !=
                                                        null)
                                                  Positioned.fill(
                                                    child: IgnorePointer(
                                                      ignoring: true,
                                                      child: Transform.translate(
                                                        offset:
                                                            transformedLayerOffset,
                                                        child: _buildTransformedLayerOverlay(
                                                          image:
                                                              transformedActiveLayerImage,
                                                          opacity:
                                                              transformedLayerOpacity,
                                                          blendMode:
                                                              transformedLayerBlendMode,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                if (transformHandlesOverlay !=
                                                    null)
                                                  transformHandlesOverlay,
                                                if (_vectorDrawingEnabled &&
                                                    _curvePreviewPath != null)
                                                  Positioned.fill(
                                                    child: CustomPaint(
                                                      painter: _PreviewPathPainter(
                                                        path:
                                                            _curvePreviewPath!,
                                                        color: _primaryColor,
                                                        strokeWidth:
                                                            _penStrokeWidth,
                                                      ),
                                                    ),
                                                  ),
                                                if (_vectorDrawingEnabled &&
                                                    shapePreviewPath != null)
                                                  Positioned.fill(
                                                    child: CustomPaint(
                                                      painter: _PreviewPathPainter(
                                                        path: shapePreviewPath!,
                                                        color: _primaryColor,
                                                        strokeWidth:
                                                            _penStrokeWidth,
                                                        fill:
                                                            _shapeFillEnabled &&
                                                            shapeToolVariant !=
                                                                ShapeToolVariant
                                                                    .line,
                                                      ),
                                                    ),
                                                  ),
                                                if (_vectorDrawingEnabled &&
                                                    pendingFillOverlayPath !=
                                                        null &&
                                                    pendingFillOverlayColor !=
                                                        null)
                                                  Positioned.fill(
                                                    child: IgnorePointer(
                                                      ignoring: true,
                                                      child: CustomPaint(
                                                        painter: _ShapeFillOverlayPainter(
                                                          path:
                                                              pendingFillOverlayPath,
                                                          color:
                                                              pendingFillOverlayColor,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                if (hasSelectionOverlay)
                                                  Positioned.fill(
                                                    child: CustomPaint(
                                                      painter: _SelectionOverlayPainter(
                                                        selectionPath:
                                                            selectionPath,
                                                        selectionPreviewPath:
                                                            selectionPreviewPath,
                                                        magicPreviewPath:
                                                            magicWandPreviewPath,
                                                        dashPhase:
                                                            selectionDashPhase,
                                                        viewportScale:
                                                            _viewport.scale,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          ...toolbarLayoutResult.widgets,
                          ..._buildReferenceCards(),
                          ..._buildPaletteCards(),
                          if (antialiasCard != null) antialiasCard,
                          if (transformPanel != null) transformPanel,
                          if (transformCursorOverlay != null)
                            transformCursorOverlay,
                          if (_toolCursorPosition != null &&
                              cursorStyle != null)
                            Positioned(
                              left:
                                  _toolCursorPosition!.dx -
                                  cursorStyle.anchor.dx +
                                  cursorStyle.iconOffset.dx,
                              top:
                                  _toolCursorPosition!.dy -
                                  cursorStyle.anchor.dy +
                                  cursorStyle.iconOffset.dy,
                              child: IgnorePointer(
                                ignoring: true,
                                child: ToolCursorStyles.iconFor(
                                  _effectiveActiveTool,
                                  isDragging: isLayerAdjustDragging,
                                ),
                              ),
                            ),
                          if (_penRequiresOverlay &&
                              _penCursorWorkspacePosition != null)
                            PenCursorOverlay(
                              position: _penCursorWorkspacePosition!,
                              diameter: overlayBrushDiameter * _viewport.scale,
                              shape: overlayBrushShape,
                            ),
                          if (_toolCursorPosition != null)
                            Positioned(
                              left:
                                  _toolCursorPosition!.dx -
                                  ToolCursorStyles.crosshairSize / 2,
                              top:
                                  _toolCursorPosition!.dy -
                                  ToolCursorStyles.crosshairSize / 2,
                              child: const IgnorePointer(
                                ignoring: true,
                                child: ToolCursorCrosshair(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildPaletteCards() {
    if (_paletteCards.isEmpty) {
      return const <Widget>[];
    }
    return _paletteCards
        .map((entry) {
          return Positioned(
            left: entry.offset.dx,
            top: entry.offset.dy,
            child: _WorkspacePaletteCard(
              title: entry.title,
              colors: entry.colors,
              onExport: () => _exportPaletteCard(entry.id),
              onClose: () => _closePaletteCard(entry.id),
              onDragStart: () => _handlePaletteDragStart(entry.id),
              onDragEnd: _handlePaletteDragEnd,
              onDragUpdate: (delta) =>
                  _updatePaletteCardOffset(entry.id, delta),
              onSizeChanged: (size) => _updatePaletteCardSize(entry.id, size),
              onColorTap: _setPrimaryColor,
            ),
          );
        })
        .toList(growable: false);
  }

  List<Widget> _buildReferenceCards() {
    if (_referenceCards.isEmpty) {
      return const <Widget>[];
    }
    final bool eyedropperActive = _effectiveActiveTool == CanvasTool.eyedropper;
    return _referenceCards
        .map((entry) {
          return Positioned(
            left: entry.offset.dx,
            top: entry.offset.dy,
            child: _ReferenceImageCard(
              image: entry.image,
              bodySize: entry.bodySize,
              pixelBytes: entry.pixelBytes,
              enableEyedropperSampling: eyedropperActive,
              onSamplePreview: (color) =>
                  _setPrimaryColor(color, remember: false),
              onSampleCommit: (color) => _setPrimaryColor(color),
              onClose: () => _closeReferenceCard(entry.id),
              onDragStart: () => _focusReferenceCard(entry.id),
              onDragEnd: () {},
              onDragUpdate: (delta) =>
                  _updateReferenceCardOffset(entry.id, delta),
              onSizeChanged: (size) =>
                  _handleReferenceCardSizeChanged(entry.id, size),
              onResizeStart: () => _beginReferenceCardResize(entry.id),
              onResize: (edge, delta) =>
                  _resizeReferenceCard(entry.id, edge, delta),
              onResizeEnd: _endReferenceCardResize,
            ),
          );
        })
        .toList(growable: false);
  }

  Widget _buildFilterPreviewStack() {
    final _FilterSession? session = _filterSession;
    if (session == null) return const SizedBox.shrink();

    ui.Image? activeImage = _previewActiveLayerImage;
    final bool useHuePreviewImage =
        session.type == _FilterPanelType.hueSaturation &&
        _previewFilteredActiveLayerImage != null;
    if (useHuePreviewImage) {
      activeImage = _previewFilteredActiveLayerImage;
    }
    Widget activeLayerWidget = RawImage(
      image: activeImage,
      filterQuality: FilterQuality.low,
    );

    // Apply Filters
    if (session.type == _FilterPanelType.gaussianBlur) {
      final double sigma = _gaussianBlurSigmaForRadius(
        session.gaussianBlur.radius,
      );
      if (sigma > 0) {
        activeLayerWidget = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: activeLayerWidget,
        );
      }
    } else if (session.type == _FilterPanelType.hueSaturation) {
      final double hue = session.hueSaturation.hue;
      final double saturation = session.hueSaturation.saturation;
      final double lightness = session.hueSaturation.lightness;
      final bool requiresAdjustments =
          hue != 0 || saturation != 0 || lightness != 0;
      if (requiresAdjustments && !useHuePreviewImage) {
        if (hue != 0) {
          activeLayerWidget = ColorFiltered(
            colorFilter: ColorFilter.matrix(ColorFilterGenerator.hue(hue)),
            child: activeLayerWidget,
          );
        }
        if (saturation != 0) {
          activeLayerWidget = ColorFiltered(
            colorFilter: ColorFilter.matrix(
              ColorFilterGenerator.saturation(saturation),
            ),
            child: activeLayerWidget,
          );
        }
        if (lightness != 0) {
          activeLayerWidget = ColorFiltered(
            colorFilter: ColorFilter.matrix(
              ColorFilterGenerator.brightness(lightness),
            ),
            child: activeLayerWidget,
          );
        }
      }
    } else if (session.type == _FilterPanelType.brightnessContrast) {
      final double brightness = session.brightnessContrast.brightness;
      final double contrast = session.brightnessContrast.contrast;
      if (brightness != 0 || contrast != 0) {
        activeLayerWidget = ColorFiltered(
          colorFilter: ColorFilter.matrix(
            ColorFilterGenerator.brightnessContrast(brightness, contrast),
          ),
          child: activeLayerWidget,
        );
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_previewBackground != null) RawImage(image: _previewBackground),
        activeLayerWidget,
        if (_previewForeground != null) RawImage(image: _previewForeground),
      ],
    );
  }

  Widget _buildLayerOpacityPreviewStack() {
    if (_layerOpacityPreviewActiveLayerImage == null) {
      return const SizedBox.shrink();
    }
    final theme = FluentTheme.of(context);
    final Color checkerLightColor = theme.brightness.isDark
        ? const Color(0xFF242424)
        : const Color(0xFFF5F5F5);
    final Color checkerDarkColor = theme.brightness.isDark
        ? const Color(0xFF1C1C1C)
        : const Color(0xFFE0E0E0);
    final bool hasVisibleLowerLayers =
        _layerOpacityPreviewHasVisibleLowerLayers;
    Widget activeLayerWidget = RawImage(
      image: _layerOpacityPreviewActiveLayerImage,
      filterQuality: FilterQuality.low,
    );
    final double previewOpacity = (_layerOpacityPreviewValue ?? 1.0).clamp(
      0.0,
      1.0,
    );
    if (previewOpacity < 0.999) {
      activeLayerWidget = Opacity(
        opacity: previewOpacity,
        child: activeLayerWidget,
      );
    }
    final List<Widget> children = <Widget>[
      if (_layerOpacityPreviewBackground != null)
        RawImage(image: _layerOpacityPreviewBackground)
      else if (!hasVisibleLowerLayers)
        _CheckboardBackground(
          cellSize: 8.0,
          lightColor: checkerLightColor,
          darkColor: checkerDarkColor,
        ),
      activeLayerWidget,
    ];
    if (_layerOpacityPreviewForeground != null) {
      children.add(RawImage(image: _layerOpacityPreviewForeground));
    }
    return Stack(fit: StackFit.expand, children: children);
  }

  Widget? _buildAntialiasCard() {
    if (!_antialiasCardVisible) {
      return null;
    }
    return Positioned(
      left: _antialiasCardOffset.dx,
      top: _antialiasCardOffset.dy,
      child: MeasuredSize(
        onChanged: _handleAntialiasCardSizeChanged,
        child: WorkspaceFloatingPanel(
          width: _kAntialiasPanelWidth,
          minHeight: _kAntialiasPanelMinHeight,
          title: '抗锯齿',
          onClose: hideLayerAntialiasPanel,
          onDragUpdate: _updateAntialiasCardOffset,
          bodyPadding: const EdgeInsets.symmetric(horizontal: 16),
          headerPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          footerPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          bodySpacing: 0,
          footerSpacing: 10,
          footer: Row(
            children: [
              Button(
                onPressed: hideLayerAntialiasPanel,
                child: const Text('取消'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _applyAntialiasFromCard,
                child: const Text('应用'),
              ),
            ],
          ),
          child: _AntialiasPanelBody(
            level: _antialiasCardLevel,
            onLevelChanged: _handleAntialiasLevelChanged,
          ),
        ),
      ),
    );
  }
}

Widget _buildTransformedLayerOverlay({
  required ui.Image image,
  required double opacity,
  required ui.BlendMode? blendMode,
}) {
  Widget content = RawImage(
    image: image,
    filterQuality: FilterQuality.none,
    colorBlendMode: blendMode,
    color: blendMode != null ? const Color(0xFFFFFFFF) : null,
  );
  final double clampedOpacity = opacity.clamp(0.0, 1.0).toDouble();
  if (clampedOpacity < 0.999) {
    content = Opacity(opacity: clampedOpacity, child: content);
  }
  return content;
}

ui.BlendMode? _flutterBlendMode(CanvasLayerBlendMode mode) {
  return mode.flutterBlendMode;
}
