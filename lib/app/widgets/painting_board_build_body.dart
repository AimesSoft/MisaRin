part of 'painting_board.dart';

extension _PaintingBoardBuildBodyExtension on _PaintingBoardBuildMixin {
  Widget _buildPaintingBoardBody(
    BuildContext context, {
    required bool canUndo,
    required bool canRedo,
    required VoidCallback toggleViewBlackWhiteOverlay,
    required VoidCallback togglePixelGridVisibility,
    required VoidCallback toggleViewMirrorOverlay,
  }) {
    final Map<LogicalKeySet, Intent> shortcutBindings =
        _buildWorkspaceShortcutBindings();
    final Map<Type, Action<Intent>> actionBindings =
        _buildWorkspaceActionBindings(
          toggleViewBlackWhiteOverlay: toggleViewBlackWhiteOverlay,
          togglePixelGridVisibility: togglePixelGridVisibility,
          toggleViewMirrorOverlay: toggleViewMirrorOverlay,
        );

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
        _notifyViewInfoChanged();
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
        final bool suppressToolCursorOverlays = _layerTransformModeActive;
        final bool perspectiveCursorActive =
            _perspectiveVisible &&
            _perspectiveMode != PerspectiveGuideMode.off &&
            (_isDraggingPerspectiveHandle ||
                _hoveringPerspectiveHandle != null);
        final bool shouldHideCursor =
            !perspectiveCursorActive &&
            (hideCursorBecauseToolOverlay ||
                hideCursorBecausePen ||
                hideCursorBecauseReferenceResize ||
                hideCursorBecauseLayerTransform);
        final bool isLayerAdjustDragging =
            _effectiveActiveTool == CanvasTool.layerAdjust && _isLayerDragging;
        final double overlayBrushDiameter =
            _effectiveActiveTool == CanvasTool.spray
            ? _sprayStrokeWidth
            : _penStrokeWidth;
        final BrushShape overlayBrushShape =
            _effectiveActiveTool == CanvasTool.spray ||
                    _effectiveActiveTool == CanvasTool.selectionPen
                ? BrushShape.circle
                : _brushShape;
        final Widget? antialiasCard = _buildAntialiasCard();
        final Widget? colorRangeCard = _buildColorRangeCard();
        final Widget? transformPanel = buildLayerTransformPanel();
        final Widget? transformCursorOverlay = buildLayerTransformCursorOverlay(
          theme,
        );
        final Widget? textHoverOverlay = buildTextHoverOverlay();
        final Widget? textOverlay = buildTextEditingOverlay();

        final bool transformActive = _isLayerFreeTransformActive;
        MouseCursor boardCursor;
        if (shouldHideCursor) {
          boardCursor = SystemMouseCursors.none;
        } else if (transformActive) {
          boardCursor = SystemMouseCursors.basic;
        } else if (_effectiveActiveTool == CanvasTool.layerAdjust) {
          boardCursor = _isLayerDragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.move;
        } else if (_effectiveActiveTool == CanvasTool.text) {
          boardCursor = SystemMouseCursors.text;
        } else if (_effectiveActiveTool == CanvasTool.perspectivePen) {
          boardCursor = SystemMouseCursors.precise;
        } else {
          boardCursor = MouseCursor.defer;
        }

        MouseCursor workspaceCursor;
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
              case CanvasTool.rotate:
                workspaceCursor = SystemMouseCursors.resizeLeftRight;
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
              case CanvasTool.selectionPen:
                workspaceCursor = SystemMouseCursors.precise;
                break;
              case CanvasTool.eyedropper:
                workspaceCursor = SystemMouseCursors.basic;
                break;
              case CanvasTool.text:
                workspaceCursor = SystemMouseCursors.text;
                break;
              case CanvasTool.perspectivePen:
                workspaceCursor = SystemMouseCursors.precise;
                break;
              default:
                workspaceCursor = SystemMouseCursors.basic;
                break;
            }
          }
        }

        MouseCursor _applyPerspectiveCursor(MouseCursor current) {
          if (perspectiveCursorActive) {
            return _isDraggingPerspectiveHandle
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.grab;
          }
          return current;
        }

        boardCursor = _applyPerspectiveCursor(boardCursor);
        workspaceCursor = _applyPerspectiveCursor(workspaceCursor);

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
          brushPresets: _brushLibrary?.presets ?? const <BrushPreset>[],
          activeBrushPresetId:
              _activeBrushPreset?.id ?? _brushLibrary?.selectedId ?? 'pencil',
          onBrushPresetChanged: _selectBrushPreset,
          onEditBrushPreset: _openBrushPresetEditor,
          strokeStabilizerStrength: _strokeStabilizerStrength,
          onStrokeStabilizerChanged: _updateStrokeStabilizerStrength,
          streamlineStrength: _streamlineStrength,
          onStreamlineChanged: _updateStreamlineStrength,
          stylusPressureEnabled: _stylusPressureEnabled,
          onStylusPressureEnabledChanged: _updateStylusPressureEnabled,
          simulatePenPressure: _simulatePenPressure,
          onSimulatePenPressureChanged: _updatePenPressureSimulation,
          penPressureProfile: _penPressureProfile,
          onPenPressureProfileChanged: _updatePenPressureProfile,
          bucketSampleAllLayers: _bucketSampleAllLayers,
          bucketContiguous: _bucketContiguous,
          bucketSwallowColorLine: _bucketSwallowColorLine,
          bucketSwallowColorLineMode: _bucketSwallowColorLineMode,
          bucketAntialiasLevel: _bucketAntialiasLevel,
          onBucketSampleAllLayersChanged: _updateBucketSampleAllLayers,
          onBucketContiguousChanged: _updateBucketContiguous,
          onBucketSwallowColorLineChanged: _updateBucketSwallowColorLine,
          onBucketSwallowColorLineModeChanged: _updateBucketSwallowColorLineMode,
          onBucketAntialiasChanged: _updateBucketAntialiasLevel,
          bucketTolerance: _bucketTolerance,
          onBucketToleranceChanged: _updateBucketTolerance,
          bucketFillGap: _bucketFillGap,
          onBucketFillGapChanged: _updateBucketFillGap,
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
          strokeStabilizerMaxLevel: _strokeStabilizerMaxLevel,
          compactLayout: isSai2Layout,
          textFontSize: _textFontSize,
          onTextFontSizeChanged: _updateTextFontSize,
          textLineHeight: _textLineHeight,
          onTextLineHeightChanged: _updateTextLineHeight,
          textLetterSpacing: _textLetterSpacing,
          onTextLetterSpacingChanged: _updateTextLetterSpacing,
          textFontFamily: _textFontFamily,
          onTextFontFamilyChanged: _updateTextFontFamily,
          availableFontFamilies: _textFontFamilies,
          fontsLoading: _textFontsLoading,
          textAlign: _textAlign,
          onTextAlignChanged: _updateTextAlign,
          textOrientation: _textOrientation,
          onTextOrientationChanged: _updateTextOrientation,
          textAntialias: _textAntialias,
          onTextAntialiasChanged: _updateTextAntialias,
          textStrokeEnabled: _textStrokeEnabled,
          onTextStrokeEnabledChanged: _updateTextStrokeEnabled,
	          textStrokeWidth: _textStrokeWidth,
	          onTextStrokeWidthChanged: _updateTextStrokeWidth,
	          textStrokeColor: _colorLineColor,
	          onTextStrokeColorPressed: _handleEditTextStrokeColor,
	          canvasRotation: _viewport.rotation,
	          onCanvasRotationChanged: _setViewportRotation,
	          onCanvasRotationReset: _resetViewportRotation,
	        );
        final ToolbarPanelData colorPanelData = ToolbarPanelData(
          title: context.l10n.colorPickerTitle,
          trailing: _buildColorPanelTrailing(theme),
          child: _buildColorPanelContent(theme),
        );
        final Widget addLayerButton = _buildAddLayerButton();
        final ToolbarPanelData layerPanelData = ToolbarPanelData(
          title: context.l10n.layerManagerTitle,
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
            actions: actionBindings,
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
	                                child: Transform.rotate(
	                                  angle: _viewport.rotation,
	                                  alignment: Alignment.center,
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
	                                    child: RepaintBoundary(
	                                      child: AnimatedBuilder(
	                                          animation: _controller,
	                                          builder: (context, _) {
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
                                            final bool suppressLayerAdjustOverlay =
                                                _layerAdjustUsingRustPreview;
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
                                            final bool activeLayerLocked = () {
                                              final String? activeId =
                                                  _controller.activeLayerId;
                                              if (activeId == null) {
                                                return false;
                                              }
                                              for (final BitmapLayerState layer
                                                  in _controller.layers) {
                                                if (layer.id == activeId) {
                                                  return layer.locked;
                                                }
                                              }
                                              return false;
                                            }();
                                            final bool hasActiveStroke =
                                                canPreviewStroke &&
                                                _controller
                                                    .activeStrokePoints
                                                    .isNotEmpty;
                                            final bool showActiveStroke =
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

                                            Widget applyViewOverlay(Widget child) {
                                              if (_viewMirrorOverlay) {
                                                child = Transform(
                                                  transform: _kViewMirrorTransform,
                                                  alignment: Alignment.center,
                                                  transformHitTests: false,
                                                  child: child,
                                                );
                                              }
                                              if (_viewBlackWhiteOverlay) {
                                                child = ColorFiltered(
                                                  colorFilter: _kViewBlackWhiteColorFilter,
                                                  child: child,
                                                );
                                              }
                                              return child;
                                            }

                                            final Widget canvasSurface = IgnorePointer(
                                              ignoring: true,
                                              child: RustCanvasSurface(
                                                surfaceKey: widget.surfaceKey,
                                                canvasSize: _canvasSize,
                                                enableDrawing:
                                                    canPreviewStroke &&
                                                    !activeLayerLocked &&
                                                    !_layerTransformModeActive &&
                                                    !_isLayerFreeTransformActive &&
                                                    !_controller
                                                        .isActiveLayerTransforming,
                                                frame: _controller.frame,
                                                layerCount:
                                                    _controller.layers.length,
                                                brushColorArgb:
                                                    _isBrushEraserEnabled
                                                        ? 0xFFFFFFFF
                                                        : _primaryColor.value,
                                                brushRadius: _penStrokeWidth / 2,
                                                erase: _isBrushEraserEnabled,
                                                brushShape: _brushShape,
                                                brushRandomRotationEnabled:
                                                    _brushRandomRotationEnabled,
                                                brushRotationSeed:
                                                    _brushRandomRotationPreviewSeed,
                                                brushSpacing: _brushSpacing,
                                                brushHardness: _brushHardness,
                                                brushFlow: _brushFlow,
                                                brushScatter: _brushScatter,
                                                brushRotationJitter:
                                                    _brushRotationJitter,
                                                brushSnapToPixel:
                                                    _brushSnapToPixel,
                                                hollowStrokeEnabled:
                                                    _hollowStrokeEnabled,
                                                hollowStrokeRatio:
                                                    _hollowStrokeRatio,
                                                hollowStrokeEraseOccludedParts:
                                                    _hollowStrokeEraseOccludedParts,
                                                antialiasLevel: _penAntialiasLevel,
                                                backgroundColorArgb:
                                                    widget.settings.backgroundColor.toARGB32(),
                                                usePressure:
                                                    _stylusPressureEnabled ||
                                                    _simulatePenPressure ||
                                                    _autoSharpPeakEnabled,
                                                stylusCurve: _stylusCurve,
                                                streamlineStrength:
                                                    _streamlineStrength,
                                                onStrokeBegin: _markDirty,
                                                onEngineInfoChanged:
                                                    _handleRustCanvasEngineInfoChanged,
                                              ),
                                            );

                                            final _FilterSession? filterSession =
                                                _filterSession;
                                            final bool showRustFilterPreview =
                                                filterSession != null &&
                                                _shouldShowRustFilterPreviewOverlay(
                                                  filterSession,
                                                );
                                            final bool showRustCurvePreview =
                                                _canUseRustCanvasEngine() &&
                                                _curvePreviewRasterImage != null;
                                            final bool showRustShapePreview =
                                                _canUseRustCanvasEngine() &&
                                                _shapePreviewRasterImage != null;
                                            final BitmapLayerState activeLayer =
                                                _controller.activeLayer;
                                            final ui.BlendMode?
                                                rustPreviewBlendMode =
                                                _flutterBlendMode(
                                                  activeLayer.blendMode,
                                                );
                                            final double rustPreviewOpacity =
                                                activeLayer.opacity
                                                    .clamp(0.0, 1.0)
                                                    .toDouble();
                                            final List<Widget> overlayChildren =
                                                <Widget>[
                                              if (showRustFilterPreview)
                                                _buildRustFilterPreviewOverlay(),
                                              if (_pixelGridVisible)
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    ignoring: true,
                                                    child: CustomPaint(
                                                      painter: _PixelGridPainter(
                                                        pixelWidth:
                                                            _controller.width,
                                                        pixelHeight:
                                                            _controller.height,
                                                        color: _pixelGridColor,
                                                        scale: _viewport.scale,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (showActiveStroke)
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    ignoring: true,
                                                    child: CustomPaint(
                                                      painter: _ActiveStrokeOverlayPainter(
                                                        points: _controller
                                                            .activeStrokePoints,
                                                        radii: _controller
                                                            .activeStrokeRadii,
                                                        color: _controller
                                                            .activeStrokeColor,
                                                        shape: _controller
                                                            .activeStrokeShape,
                                                        randomRotationEnabled:
                                                            _controller
                                                                .activeStrokeRandomRotationEnabled,
                                                        rotationSeed: _controller
                                                            .activeStrokeRotationSeed,
                                                        antialiasLevel: _controller
                                                            .activeStrokeAntialiasLevel,
                                                        hollowStrokeEnabled:
                                                            _controller
                                                                .activeStrokeHollowEnabled,
                                                        hollowStrokeRatio:
                                                            _controller
                                                                .activeStrokeHollowRatio,
                                                        committingStrokes: _controller
                                                            .committingStrokes,
                                                        activeStrokeIsEraser:
                                                            activeStrokeIsEraser,
                                                        eraserPreviewColor:
                                                            _kVectorEraserPreviewColor,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (showRustCurvePreview)
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    ignoring: true,
                                                    child:
                                                        _buildTransformedLayerOverlay(
                                                          image:
                                                              _curvePreviewRasterImage!,
                                                          opacity:
                                                              rustPreviewOpacity,
                                                          blendMode:
                                                              rustPreviewBlendMode,
                                                        ),
                                                  ),
                                                ),
                                              if (showRustShapePreview)
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    ignoring: true,
                                                    child:
                                                        _buildTransformedLayerOverlay(
                                                          image:
                                                              _shapePreviewRasterImage!,
                                                          opacity:
                                                              rustPreviewOpacity,
                                                          blendMode:
                                                              rustPreviewBlendMode,
                                                        ),
                                                  ),
                                                ),
                                              if (transformImageOverlay != null)
                                                transformImageOverlay
                                              else if (!_isLayerFreeTransformActive &&
                                                  !suppressLayerAdjustOverlay &&
                                                  isTransforming &&
                                                  transformedActiveLayerImage !=
                                                      null)
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    ignoring: true,
                                                    child: OverflowBox(
                                                      alignment: Alignment.topLeft,
                                                      minWidth: 0,
                                                      minHeight: 0,
                                                      maxWidth: double.infinity,
                                                      maxHeight: double.infinity,
                                                      child: Transform.translate(
                                                        offset:
                                                            transformedLayerOffset,
                                                        child:
                                                            _buildTransformedLayerOverlay(
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
                                                ),
                                              if (hasSelectionOverlay)
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    ignoring: true,
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
                                                        showPreviewStroke:
                                                            _effectiveActiveTool !=
                                                                CanvasTool
                                                                    .selectionPen,
                                                        fillSelectionPath:
                                                            _activeTool ==
                                                                CanvasTool
                                                                    .selectionPen,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ];

                                            final Widget canvasLayer = Stack(
                                              fit: StackFit.expand,
                                              clipBehavior: Clip.none,
                                              children: [
                                                const _CheckboardBackground(),
                                                canvasSurface,
                                              ],
                                            );

                                            final Widget overlayLayer = Stack(
                                              fit: StackFit.expand,
                                              clipBehavior: Clip.none,
                                              children: overlayChildren,
                                            );

                                            final bool applyViewToCanvas =
                                                !_canUseRustCanvasEngine();
                                            final Widget canvasWithView =
                                                applyViewToCanvas
                                                ? applyViewOverlay(canvasLayer)
                                                : canvasLayer;
                                            final Widget? transformHandlesViewOverlay =
                                                transformHandlesOverlay == null
                                                ? null
                                                : applyViewOverlay(
                                                    transformHandlesOverlay,
                                                  );
                                            final Widget clippedContent = ClipRect(
                                              child: Stack(
                                                fit: StackFit.expand,
                                                clipBehavior: Clip.none,
                                                children: [
                                                  canvasWithView,
                                                  if (overlayChildren.isNotEmpty)
                                                    applyViewOverlay(overlayLayer),
                                                ],
                                              ),
                                            );

                                            return Stack(
                                              fit: StackFit.expand,
                                              clipBehavior: Clip.none,
                                              children: [
                                                clippedContent,
                                                if (transformHandlesViewOverlay != null)
                                                  transformHandlesViewOverlay,
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
	                          if (_perspectivePenAnchor != null)
	                            Positioned.fill(
	                              child: IgnorePointer(
		                                ignoring: true,
		                                child: Transform.translate(
		                                  offset: _boardRect.topLeft,
		                                  child: Transform.scale(
		                                    scale: _viewport.scale,
		                                    alignment: Alignment.topLeft,
		                                    child: Transform.rotate(
		                                      angle: _viewport.rotation,
		                                      alignment: Alignment.center,
		                                      child: Builder(
		                                        builder: (context) {
		                                        Widget overlay = CustomPaint(
		                                          size: _canvasSize,
		                                          painter: _PerspectivePenPreviewPainter(
		                                            anchor: _perspectivePenAnchor!,
                                            target: _perspectivePenPreviewTarget ??
                                                _perspectivePenAnchor!,
                                            snapped: _perspectivePenSnappedTarget ??
                                                _perspectivePenPreviewTarget ??
                                                _perspectivePenAnchor!,
                                            isValid: _perspectivePenPreviewValid,
                                            viewportScale: _viewport.scale,
                                          ),
                                        );
                                        if (_viewMirrorOverlay) {
                                          overlay = Transform(
                                            transform: _kViewMirrorTransform,
                                            alignment: Alignment.center,
                                            transformHitTests: false,
                                            child: overlay,
                                          );
	                                        }
		                                        return overlay;
		                                      },
		                                      ),
		                                    ),
		                                  ),
		                                ),
		                              ),
		                            ),
	                          if (_perspectiveVisible &&
	                              _perspectiveMode != PerspectiveGuideMode.off)
	                            Positioned.fill(
	                              child: IgnorePointer(
		                                ignoring: true,
		                                child: Transform.translate(
		                                  offset: _boardRect.topLeft,
		                                  child: Transform.scale(
		                                    scale: _viewport.scale,
		                                    alignment: Alignment.topLeft,
		                                    child: Transform.rotate(
		                                      angle: _viewport.rotation,
		                                      alignment: Alignment.center,
		                                      child: Builder(
		                                        builder: (context) {
		                                        Widget overlay = CustomPaint(
		                                          size: _canvasSize,
		                                          painter: _PerspectiveGuidePainter(
		                                            canvasSize: _canvasSize,
                                            vp1: _perspectiveVp1,
                                            vp2: _perspectiveVp2,
                                            vp3: _perspectiveVp3,
                                            mode: _perspectiveMode,
                                            activeHandle:
                                                _activePerspectiveHandle,
                                          ),
                                        );
                                        if (_viewMirrorOverlay) {
                                          overlay = Transform(
                                            transform: _kViewMirrorTransform,
                                            alignment: Alignment.center,
                                            transformHitTests: false,
                                            child: overlay,
                                          );
                                        }
                                        if (_viewBlackWhiteOverlay) {
                                          overlay = ColorFiltered(
                                            colorFilter:
                                                _kViewBlackWhiteColorFilter,
                                            child: overlay,
                                          );
	                                        }
		                                        return overlay;
		                                      },
		                                      ),
		                                    ),
		                                  ),
		                                ),
		                              ),
		                            ),
                          if (textHoverOverlay != null) textHoverOverlay,
                          if (textOverlay != null) textOverlay,
                          ...toolbarLayoutResult.widgets,
                          if (colorRangeCard != null) colorRangeCard,
                          if (antialiasCard != null) antialiasCard,
                          if (transformPanel != null) transformPanel,
                          if (transformCursorOverlay != null)
                            transformCursorOverlay,
                          if (!suppressToolCursorOverlays &&
                              _toolCursorPosition != null &&
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
                          if (!suppressToolCursorOverlays &&
                              _penRequiresOverlay &&
                              _penCursorWorkspacePosition != null)
                            PenCursorOverlay(
                              position: _penCursorWorkspacePosition!,
                              diameter: overlayBrushDiameter * _viewport.scale,
                              shape: overlayBrushShape,
                              rotation:
                                  _brushRandomRotationEnabled &&
                                          overlayBrushShape != BrushShape.circle
                                      ? brushRandomRotationRadians(
                                          center: _toBoardLocal(
                                            _penCursorWorkspacePosition!,
                                          ),
                                          seed: _isDrawing
                                              ? _controller.activeStrokeRotationSeed
                                              : _brushRandomRotationPreviewSeed,
                                        )
                                      : 0.0,
                            ),
                          if (!suppressToolCursorOverlays &&
                              _toolCursorPosition != null)
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
}
