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
        final bool isLandscapeLayout = candidate.width > candidate.height;
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
        const double toolIconBaseExtent = 20.0;
        final double toolIconLocateScale = _cursorLocateScaleForExtent(
          toolIconBaseExtent,
        );
        final double crosshairLocateScale = _cursorLocateScaleForExtent(
          ToolCursorStyles.crosshairSize,
        );
        final double overlayBrushDiameter =
            _effectiveActiveTool == CanvasTool.spray
            ? _sprayStrokeWidth
            : _effectiveActiveTool == CanvasTool.smudge
            ? _smudgeStrokeWidth
            : _effectiveActiveTool == CanvasTool.liquify
            ? _liquifyStrokeWidth
            : _effectiveActiveTool == CanvasTool.eraser
            ? _eraserStrokeWidth
            : _penStrokeWidth;
        final double overlayCursorDiameter = _cursorLocateScaledExtent(
          overlayBrushDiameter * _viewport.scale,
        );
        final BrushShape overlayBrushShape =
            _effectiveActiveTool == CanvasTool.spray ||
                _effectiveActiveTool == CanvasTool.smudge ||
                _effectiveActiveTool == CanvasTool.liquify ||
                _effectiveActiveTool == CanvasTool.selectionPen
            ? BrushShape.circle
            : _brushShape;
        final BrushShapeRaster? overlayBrushRaster =
            _effectiveActiveTool == CanvasTool.spray ||
                _effectiveActiveTool == CanvasTool.smudge ||
                _effectiveActiveTool == CanvasTool.liquify ||
                _effectiveActiveTool == CanvasTool.selectionPen
            ? null
            : (_brushShapeRaster != null &&
                      _brushShapeRaster!.id == _brushShapeId
                  ? _brushShapeRaster
                  : null);
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
              case CanvasTool.liquify:
                workspaceCursor = SystemMouseCursors.precise;
                break;
              case CanvasTool.smudge:
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
        final bool isDockedLayout =
            toolbarStyle != PaintingToolbarLayoutStyle.floating;
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
          eraserStrokeWidth: _eraserStrokeWidth,
          liquifyStrokeWidth: _liquifyStrokeWidth,
          liquifyStrength: _liquifyStrength,
          liquifySoftness: _liquifySoftness,
          liquifyMix: _liquifyMix,
          smudgeStrokeWidth: _smudgeStrokeWidth,
          smudgeStrength: _smudgeStrength,
          smudgeSoftness: _smudgeSoftness,
          sprayMode: _sprayMode,
          penStrokeSliderRange: _penStrokeSliderRange,
          sprayStrokeSliderRange: _sprayStrokeSliderRange,
          eraserStrokeSliderRange: _eraserStrokeSliderRange,
          onPenStrokeWidthChanged: _updatePenStrokeWidth,
          onSprayStrokeWidthChanged: _updateSprayStrokeWidth,
          onEraserStrokeWidthChanged: _updateEraserStrokeWidth,
          onLiquifyStrokeWidthChanged: _updateLiquifyStrokeWidth,
          onLiquifyStrengthChanged: _updateLiquifyStrength,
          onLiquifySoftnessChanged: _updateLiquifySoftness,
          onLiquifyMixChanged: _updateLiquifyMix,
          onSmudgeStrokeWidthChanged: _updateSmudgeStrokeWidth,
          onSmudgeStrengthChanged: _updateSmudgeStrength,
          onSmudgeSoftnessChanged: _updateSmudgeSoftness,
          onPenStrokeSliderRangeChanged: _updatePenStrokeSliderRange,
          onSprayStrokeSliderRangeChanged: _updateSprayStrokeSliderRange,
          onEraserStrokeSliderRangeChanged: _updateEraserStrokeSliderRange,
          onSprayModeChanged: _updateSprayMode,
          brushPresets: _brushLibrary?.presets ?? const <BrushPreset>[],
          activeBrushPresetId:
              _activeBrushPreset?.id ?? _brushLibrary?.selectedId ?? 'pencil',
          onOpenBrushPresetPicker: _openBrushPresetPicker,
          strokeStabilizerStrength: _strokeStabilizerStrength,
          onStrokeStabilizerChanged: _updateStrokeStabilizerStrength,
          streamlineStrength: _streamlineStrength,
          onStreamlineChanged: _updateStreamlineStrength,
          stylusPressureEnabled: _stylusPressureEnabled,
          onStylusPressureEnabledChanged: _updateStylusPressureEnabled,
          touchDrawingEnabled: _touchDrawingEnabled,
          onTouchDrawingEnabledChanged: _updateTouchDrawingEnabled,
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
          onBucketSwallowColorLineModeChanged:
              _updateBucketSwallowColorLineMode,
          onBucketAntialiasChanged: _updateBucketAntialiasLevel,
          bucketTolerance: _bucketTolerance,
          onBucketToleranceChanged: _updateBucketTolerance,
          bucketFillGap: _bucketFillGap,
          onBucketFillGapChanged: _updateBucketFillGap,
          layerAdjustCropOutside: _layerAdjustCropOutside,
          onLayerAdjustCropOutsideChanged: _updateLayerAdjustCropOutside,
          selectionShape: selectionShape,
          onSelectionShapeChanged: _updateSelectionShape,
          selectionAdditiveEnabled: _selectionAdditiveEnabled,
          onSelectionAdditiveChanged: _updateSelectionAdditiveEnabled,
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
          streamlineMaxLevel: _streamlineMaxLevel,
          compactLayout: isDockedLayout,
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
          toolbar: widget.showToolbars
              ? toolbarWidget
              : const SizedBox.shrink(),
          toolSettings: widget.showToolbars
              ? toolSettingsCard
              : const SizedBox.shrink(),
          colorIndicator: widget.showToolbars
              ? _buildColorIndicator(theme)
              : const SizedBox.shrink(),
          colorPanel: widget.showToolbars
              ? colorPanelData
              : ToolbarPanelData.empty(),
          layerPanel: widget.showToolbars
              ? layerPanelData
              : ToolbarPanelData.empty(),
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
        final PaintingToolbarLayoutDelegate
        toolbarLayoutDelegate = switch (toolbarStyle) {
          PaintingToolbarLayoutStyle.sai2 => const Sai2ToolbarLayoutDelegate(),
          PaintingToolbarLayoutStyle.csp => const CspToolbarLayoutDelegate(),
          PaintingToolbarLayoutStyle.floating =>
            const FloatingToolbarLayoutDelegate(),
        };
        final PaintingToolbarLayoutResult toolbarLayoutResult =
            widget.showToolbars
            ? toolbarLayoutDelegate.build(
                context,
                toolbarElements,
                toolbarMetrics,
              )
            : const PaintingToolbarLayoutResult(widgets: [], hitRegions: []);
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
                supportedDevices: const <PointerDeviceKind>{
                  PointerDeviceKind.touch,
                  PointerDeviceKind.trackpad,
                },
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
                        clipBehavior: Clip.hardEdge,
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
                                            final bool
                                            suppressLayerAdjustOverlay =
                                                _layerAdjustUsingBackendPreview;
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
                                                (_backend.isReady || kIsWeb) &&
                                                (_effectiveActiveTool ==
                                                        CanvasTool.pen ||
                                                    _effectiveActiveTool ==
                                                        CanvasTool.eraser);
                                            final bool activeLayerLocked = () {
                                              final String? activeId =
                                                  _controller.activeLayerId;
                                              if (activeId == null) {
                                                return false;
                                              }
                                              for (final CanvasLayerInfo layer
                                                  in _controller.layers) {
                                                if (layer.id == activeId) {
                                                  return layer.locked;
                                                }
                                              }
                                              return false;
                                            }();
                                            final bool
                                            allowActiveStrokeOverlay =
                                                !(kIsWeb &&
                                                    _controller
                                                        .activeStrokeSnapToPixel);
                                            final bool hasActiveStroke =
                                                canPreviewStroke &&
                                                allowActiveStrokeOverlay &&
                                                _controller
                                                    .activeStrokePoints
                                                    .isNotEmpty;
                                            final bool showActiveStroke =
                                                allowActiveStrokeOverlay &&
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
                                            final bool
                                            showBackendPredictedStroke =
                                                !_isLayerFreeTransformActive &&
                                                !_controller
                                                    .isActiveLayerTransforming &&
                                                _showBackendPredictedOverlay;
                                            final Color predictedStrokeColor =
                                                (_isBrushEraserEnabled
                                                        ? _kVectorEraserPreviewColor
                                                        : _primaryColor)
                                                    .withAlpha(210);

                                            Widget applyViewOverlay(
                                              Widget child,
                                            ) {
                                              if (_viewMirrorOverlay) {
                                                child = Transform(
                                                  transform:
                                                      _kViewMirrorTransform,
                                                  alignment: Alignment.center,
                                                  transformHitTests: false,
                                                  child: child,
                                                );
                                              }
                                              if (_viewBlackWhiteOverlay) {
                                                child = ColorFiltered(
                                                  colorFilter:
                                                      _kViewBlackWhiteColorFilter,
                                                  child: child,
                                                );
                                              }
                                              return child;
                                            }

                                            final Widget
                                            canvasSurface = IgnorePointer(
                                              ignoring: true,
                                              child: AdaptiveCanvasSurface(
                                                surfaceKey: widget.surfaceKey,
                                                canvasSize: _canvasSize,
                                                frame: _controller.frame,
                                                enableDrawing:
                                                    canPreviewStroke &&
                                                    !activeLayerLocked &&
                                                    !_layerTransformModeActive &&
                                                    !_isLayerFreeTransformActive &&
                                                    !_controller
                                                        .isActiveLayerTransforming,
                                                allowBackendCanvas:
                                                    _brushShapeSupportsBackend,
                                                layerCount:
                                                    _controller.layers.length,
                                                brushColorArgb:
                                                    _isBrushEraserEnabled
                                                    ? 0xFFFFFFFF
                                                    : _primaryColor.value,
                                                brushRadius:
                                                    (_activeTool ==
                                                            CanvasTool.eraser
                                                        ? _eraserStrokeWidth
                                                        : _penStrokeWidth) /
                                                    2,
                                                erase: _isBrushEraserEnabled,
                                                brushShape: _brushShape,
                                                brushRandomRotationEnabled:
                                                    _brushRandomRotationEnabled,
                                                brushSmoothRotationEnabled:
                                                    _brushSmoothRotationEnabled,
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
                                                brushScreentoneEnabled:
                                                    _brushScreentoneEnabled,
                                                brushScreentoneSpacing:
                                                    _brushScreentoneSpacing,
                                                brushScreentoneDotSize:
                                                    _brushScreentoneDotSize,
                                                brushScreentoneRotation:
                                                    _brushScreentoneRotation,
                                                brushScreentoneSoftness:
                                                    _brushScreentoneSoftness,
                                                brushScreentoneShape:
                                                    _brushScreentoneShape,
                                                hollowStrokeEnabled:
                                                    _hollowStrokeEnabled,
                                                hollowStrokeRatio:
                                                    _hollowStrokeRatio,
                                                hollowStrokeEraseOccludedParts:
                                                    _hollowStrokeEraseOccludedParts,
                                                antialiasLevel:
                                                    _penAntialiasLevel,
                                                backgroundColorArgb: widget
                                                    .settings
                                                    .backgroundColor
                                                    .toARGB32(),
                                                usePressure:
                                                    _stylusPressureEnabled ||
                                                    _simulatePenPressure ||
                                                    _autoSharpPeakEnabled,
                                                stylusCurve: _stylusCurve,
                                                streamlineStrength:
                                                    _streamlineStrength,
                                                strokeStabilizerStrength:
                                                    _strokeStabilizerStrength,
                                                onStrokeBegin: _markDirty,
                                                onEngineInfoChanged:
                                                    _handleBackendCanvasEngineInfoChanged,
                                              ),
                                            );
                                            final bool tiledViewEnabled =
                                                _viewTiledCanvas;
                                            final int? backendTextureId =
                                                _backendCanvasTextureId;
                                            final bool canRepeatSurface =
                                                backendTextureId != null;

                                            Widget buildRepeatSurface() {
                                              return Texture(
                                                textureId: backendTextureId!,
                                                filterQuality:
                                                    FilterQuality.none,
                                              );
                                            }

                                            Widget buildRepeatTile() {
                                              Widget surface = IgnorePointer(
                                                ignoring: true,
                                                child: buildRepeatSurface(),
                                              );
                                              Widget tile = SizedBox(
                                                width: _canvasSize.width,
                                                height: _canvasSize.height,
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  clipBehavior: Clip.hardEdge,
                                                  children: [
                                                    const _CheckboardBackground(),
                                                    surface,
                                                  ],
                                                ),
                                              );
                                              return tile;
                                            }

                                            final _FilterSession?
                                            filterSession = _filterSession;
                                            final bool
                                            showBackendFilterPreview =
                                                filterSession != null &&
                                                _shouldShowBackendFilterPreviewOverlay(
                                                  filterSession,
                                                );
                                            final bool showBackendCurvePreview =
                                                _backend.isReady &&
                                                _curvePreviewRasterImage !=
                                                    null;
                                            final bool showBackendShapePreview =
                                                _backend.isReady &&
                                                _shapePreviewRasterImage !=
                                                    null;
                                            final bool showVectorCurvePreview =
                                                _backend.isReady &&
                                                _curvePreviewPath != null &&
                                                !showBackendCurvePreview;
                                            final bool showVectorShapePreview =
                                                _backend.isReady &&
                                                _shapePreviewPath != null &&
                                                !showBackendShapePreview;
                                            final bool previewErase =
                                                _isBrushEraserEnabled;
                                            final Color previewStrokeColor =
                                                previewErase
                                                ? _kVectorEraserPreviewColor
                                                : _primaryColor;
                                            final bool previewFillEnabled =
                                                _shapeFillEnabled &&
                                                _shapeToolVariant !=
                                                    ShapeToolVariant.line;
                                            final Color? previewFillColor =
                                                previewFillEnabled
                                                ? previewStrokeColor
                                                : null;
                                            final CanvasLayerInfo activeLayer =
                                                _controller.activeLayer;
                                            final ui.BlendMode?
                                            backendPreviewBlendMode =
                                                _flutterBlendMode(
                                                  activeLayer.blendMode,
                                                );
                                            final double backendPreviewOpacity =
                                                activeLayer.opacity
                                                    .clamp(0.0, 1.0)
                                                    .toDouble();
                                            final List<Widget>
                                            overlayChildren = <Widget>[
                                              if (showBackendFilterPreview)
                                                _buildBackendFilterPreviewOverlay(),
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
                                                            scale:
                                                                _viewport.scale,
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
                                                        committingStrokes:
                                                            _controller
                                                                .committingStrokes,
                                                        commitOverlayOpacityFor:
                                                            _controller
                                                                .commitOverlayOpacityFor,
                                                        commitOverlayFadeVersion:
                                                            _controller
                                                                .commitOverlayFadeVersion,
                                                        activeStrokeIsEraser:
                                                            activeStrokeIsEraser,
                                                        eraserPreviewColor:
                                                            _kVectorEraserPreviewColor,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (showBackendPredictedStroke)
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    ignoring: true,
                                                    child: CustomPaint(
                                                      painter: _PredictedStrokeOverlayPainter(
                                                        points:
                                                            _backendPredictedPoints,
                                                        radii:
                                                            _backendPredictedRadii,
                                                        revision:
                                                            _backendPredictedOverlayRevision,
                                                        color:
                                                            predictedStrokeColor,
                                                        shape: _brushShape,
                                                        antialiasLevel:
                                                            _penAntialiasLevel,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (showVectorCurvePreview)
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    ignoring: true,
                                                    child: CustomPaint(
                                                      painter: _PathPreviewPainter(
                                                        path:
                                                            _curvePreviewPath!,
                                                        strokeColor:
                                                            previewStrokeColor,
                                                        strokeWidth:
                                                            _penStrokeWidth,
                                                        antialiasLevel:
                                                            _penAntialiasLevel,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (showVectorShapePreview)
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    ignoring: true,
                                                    child: CustomPaint(
                                                      painter: _PathPreviewPainter(
                                                        path:
                                                            _shapePreviewPath!,
                                                        strokeColor:
                                                            previewStrokeColor,
                                                        strokeWidth:
                                                            _penStrokeWidth,
                                                        fill:
                                                            previewFillEnabled,
                                                        fillColor:
                                                            previewFillColor,
                                                        antialiasLevel:
                                                            _penAntialiasLevel,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (showBackendCurvePreview)
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    ignoring: true,
                                                    child: _buildTransformedLayerOverlay(
                                                      image:
                                                          _curvePreviewRasterImage!,
                                                      opacity:
                                                          backendPreviewOpacity,
                                                      blendMode:
                                                          backendPreviewBlendMode,
                                                    ),
                                                  ),
                                                ),
                                              if (showBackendShapePreview)
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    ignoring: true,
                                                    child: _buildTransformedLayerOverlay(
                                                      image:
                                                          _shapePreviewRasterImage!,
                                                      opacity:
                                                          backendPreviewOpacity,
                                                      blendMode:
                                                          backendPreviewBlendMode,
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
                                                      alignment:
                                                          Alignment.topLeft,
                                                      minWidth: 0,
                                                      minHeight: 0,
                                                      maxWidth: double.infinity,
                                                      maxHeight:
                                                          double.infinity,
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
                                                !_backend.isReady;
                                            final Widget canvasWithView =
                                                applyViewToCanvas
                                                ? applyViewOverlay(canvasLayer)
                                                : canvasLayer;
                                            final Widget?
                                            transformHandlesViewOverlay =
                                                transformHandlesOverlay == null
                                                ? null
                                                : applyViewOverlay(
                                                    transformHandlesOverlay,
                                                  );
                                            final Widget clippedContent =
                                                ClipRect(
                                                  child: Stack(
                                                    fit: StackFit.expand,
                                                    clipBehavior: Clip.none,
                                                    children: [
                                                      canvasWithView,
                                                      if (overlayChildren
                                                          .isNotEmpty)
                                                        applyViewOverlay(
                                                          overlayLayer,
                                                        ),
                                                    ],
                                                  ),
                                                );

                                            final Widget centralContent = Stack(
                                              fit: StackFit.expand,
                                              clipBehavior: Clip.none,
                                              children: [
                                                clippedContent,
                                                if (transformHandlesViewOverlay !=
                                                    null)
                                                  transformHandlesViewOverlay,
                                              ],
                                            );

                                            final Widget keyedCentralContent =
                                                KeyedSubtree(
                                                  key: const ValueKey<String>(
                                                    'tiled-preview-central',
                                                  ),
                                                  child: centralContent,
                                                );
                                            final bool canBuildTiledView =
                                                tiledViewEnabled &&
                                                canRepeatSurface &&
                                                _canvasSize.width > 0 &&
                                                _canvasSize.height > 0;
                                            if (!canBuildTiledView) {
                                              return Stack(
                                                fit: StackFit.expand,
                                                clipBehavior: Clip.none,
                                                children: [keyedCentralContent],
                                              );
                                            }
                                            const int maxTileRadius = 6;
                                            int tileRadius(
                                              double viewportExtent,
                                              double tileExtent,
                                            ) {
                                              if (tileExtent <= 0 ||
                                                  !tileExtent.isFinite ||
                                                  viewportExtent <= 0 ||
                                                  !viewportExtent.isFinite) {
                                                return 1;
                                              }
                                              final double adjustedExtent =
                                                  _viewport.rotation == 0.0
                                                  ? viewportExtent
                                                  : viewportExtent * 1.5;
                                              final double coverage =
                                                  adjustedExtent / tileExtent;
                                              final int needed =
                                                  coverage.isFinite
                                                  ? coverage.ceil()
                                                  : 1;
                                              final int radius = needed + 2;
                                              return radius.clamp(
                                                1,
                                                maxTileRadius,
                                              );
                                            }

                                            final int radiusX = tileRadius(
                                              _workspaceSize.width,
                                              _canvasSize.width *
                                                  _viewport.scale,
                                            );
                                            final int radiusY = tileRadius(
                                              _workspaceSize.height,
                                              _canvasSize.height *
                                                  _viewport.scale,
                                            );
                                            final List<Widget> tiledChildren =
                                                <Widget>[];
                                            for (
                                              int ty = -radiusY;
                                              ty <= radiusY;
                                              ty++
                                            ) {
                                              for (
                                                int tx = -radiusX;
                                                tx <= radiusX;
                                                tx++
                                              ) {
                                                if (tx == 0 && ty == 0) {
                                                  continue;
                                                }
                                                tiledChildren.add(
                                                  Positioned(
                                                    left:
                                                        tx * _canvasSize.width,
                                                    top:
                                                        ty * _canvasSize.height,
                                                    child: buildRepeatTile(),
                                                  ),
                                                );
                                              }
                                            }

                                            return Stack(
                                              fit: StackFit.expand,
                                              clipBehavior: Clip.none,
                                              children: [
                                                ...tiledChildren,
                                                keyedCentralContent,
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
                                              target:
                                                  _perspectivePenPreviewTarget ??
                                                  _perspectivePenAnchor!,
                                              snapped:
                                                  _perspectivePenSnappedTarget ??
                                                  _perspectivePenPreviewTarget ??
                                                  _perspectivePenAnchor!,
                                              isValid:
                                                  _perspectivePenPreviewValid,
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
                                              viewportScale: _viewport.scale,
                                              handleFillRadiusScreen:
                                                  _perspectiveHandleFillRadiusScreen,
                                              handleOutlineRadiusScreen:
                                                  _perspectiveHandleOutlineRadiusScreen,
                                              handleOutlineWidthScreen:
                                                  _perspectiveHandleOutlineWidthScreen,
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
                          if (widget.showToolbars) ...[
                            ...toolbarLayoutResult.widgets,
                            if (colorRangeCard != null) colorRangeCard,
                            if (antialiasCard != null) antialiasCard,
                            if (transformPanel != null) transformPanel,
                            if (transformCursorOverlay != null)
                              transformCursorOverlay,
                          ] else ...[
                            Align(
                              alignment: Alignment.bottomLeft,
                              child: MobileToolButtons(
                                activeTool: _activeTool,
                                onToolSelected: _setActiveTool,
                                rebuildListenable: _mobileUiRebuildListenable,
                                toolSettingsBuilder: (context) {
                                  return MisarinDialog(
                                    title: Text(context.l10n.menuTool),
                                    content: ToolSettingsCard(
                                      activeTool: _activeTool,
                                      penStrokeWidth: _penStrokeWidth,
                                      sprayStrokeWidth: _sprayStrokeWidth,
                                      eraserStrokeWidth: _eraserStrokeWidth,
                                      liquifyStrokeWidth: _liquifyStrokeWidth,
                                      liquifyStrength: _liquifyStrength,
                                      liquifySoftness: _liquifySoftness,
                                      liquifyMix: _liquifyMix,
                                      smudgeStrokeWidth: _smudgeStrokeWidth,
                                      smudgeStrength: _smudgeStrength,
                                      smudgeSoftness: _smudgeSoftness,
                                      sprayMode: _sprayMode,
                                      penStrokeSliderRange:
                                          _penStrokeSliderRange,
                                      sprayStrokeSliderRange:
                                          _sprayStrokeSliderRange,
                                      eraserStrokeSliderRange:
                                          _eraserStrokeSliderRange,
                                      onPenStrokeWidthChanged:
                                          _updatePenStrokeWidth,
                                      onSprayStrokeWidthChanged:
                                          _updateSprayStrokeWidth,
                                      onEraserStrokeWidthChanged:
                                          _updateEraserStrokeWidth,
                                      onLiquifyStrokeWidthChanged:
                                          _updateLiquifyStrokeWidth,
                                      onLiquifyStrengthChanged:
                                          _updateLiquifyStrength,
                                      onLiquifySoftnessChanged:
                                          _updateLiquifySoftness,
                                      onLiquifyMixChanged: _updateLiquifyMix,
                                      onSmudgeStrokeWidthChanged:
                                          _updateSmudgeStrokeWidth,
                                      onSmudgeStrengthChanged:
                                          _updateSmudgeStrength,
                                      onSmudgeSoftnessChanged:
                                          _updateSmudgeSoftness,
                                      onPenStrokeSliderRangeChanged:
                                          _updatePenStrokeSliderRange,
                                      onSprayStrokeSliderRangeChanged:
                                          _updateSprayStrokeSliderRange,
                                      onEraserStrokeSliderRangeChanged:
                                          _updateEraserStrokeSliderRange,
                                      onSprayModeChanged: _updateSprayMode,
                                      brushPresets:
                                          _brushLibrary?.presets ??
                                          const <BrushPreset>[],
                                      activeBrushPresetId:
                                          _activeBrushPreset?.id ??
                                          _brushLibrary?.selectedId ??
                                          'pencil',
                                      onOpenBrushPresetPicker:
                                          _openBrushPresetPicker,
                                      strokeStabilizerStrength:
                                          _strokeStabilizerStrength,
                                      onStrokeStabilizerChanged:
                                          _updateStrokeStabilizerStrength,
                                      streamlineStrength: _streamlineStrength,
                                      onStreamlineChanged:
                                          _updateStreamlineStrength,
                                      stylusPressureEnabled:
                                          _stylusPressureEnabled,
                                      onStylusPressureEnabledChanged:
                                          _updateStylusPressureEnabled,
                                      touchDrawingEnabled: _touchDrawingEnabled,
                                      onTouchDrawingEnabledChanged:
                                          _updateTouchDrawingEnabled,
                                      simulatePenPressure: _simulatePenPressure,
                                      onSimulatePenPressureChanged:
                                          _updatePenPressureSimulation,
                                      penPressureProfile: _penPressureProfile,
                                      onPenPressureProfileChanged:
                                          _updatePenPressureProfile,
                                      bucketSampleAllLayers:
                                          _bucketSampleAllLayers,
                                      bucketContiguous: _bucketContiguous,
                                      bucketSwallowColorLine:
                                          _bucketSwallowColorLine,
                                      bucketSwallowColorLineMode:
                                          _bucketSwallowColorLineMode,
                                      bucketAntialiasLevel:
                                          _bucketAntialiasLevel,
                                      onBucketSampleAllLayersChanged:
                                          _updateBucketSampleAllLayers,
                                      onBucketContiguousChanged:
                                          _updateBucketContiguous,
                                      onBucketSwallowColorLineChanged:
                                          _updateBucketSwallowColorLine,
                                      onBucketSwallowColorLineModeChanged:
                                          _updateBucketSwallowColorLineMode,
                                      onBucketAntialiasChanged:
                                          _updateBucketAntialiasLevel,
                                      bucketTolerance: _bucketTolerance,
                                      onBucketToleranceChanged:
                                          _updateBucketTolerance,
                                      bucketFillGap: _bucketFillGap,
                                      onBucketFillGapChanged:
                                          _updateBucketFillGap,
                                      layerAdjustCropOutside:
                                          _layerAdjustCropOutside,
                                      onLayerAdjustCropOutsideChanged:
                                          _updateLayerAdjustCropOutside,
                                      selectionShape: selectionShape,
                                      onSelectionShapeChanged:
                                          _updateSelectionShape,
                                      selectionAdditiveEnabled:
                                          _selectionAdditiveEnabled,
                                      onSelectionAdditiveChanged:
                                          _updateSelectionAdditiveEnabled,
                                      shapeToolVariant: shapeToolVariant,
                                      onShapeToolVariantChanged:
                                          _updateShapeToolVariant,
                                      shapeFillEnabled: _shapeFillEnabled,
                                      onShapeFillChanged:
                                          _updateShapeFillEnabled,
                                      onSizeChanged:
                                          _updateToolSettingsCardSize,
                                      magicWandTolerance: _magicWandTolerance,
                                      onMagicWandToleranceChanged:
                                          _updateMagicWandTolerance,
                                      brushToolsEraserMode:
                                          _brushToolsEraserMode,
                                      onBrushToolsEraserModeChanged:
                                          _updateBrushToolsEraserMode,
                                      strokeStabilizerMaxLevel:
                                          _strokeStabilizerMaxLevel,
                                      streamlineMaxLevel: _streamlineMaxLevel,
                                      compactLayout: true,
                                      textFontSize: _textFontSize,
                                      onTextFontSizeChanged:
                                          _updateTextFontSize,
                                      textLineHeight: _textLineHeight,
                                      onTextLineHeightChanged:
                                          _updateTextLineHeight,
                                      textLetterSpacing: _textLetterSpacing,
                                      onTextLetterSpacingChanged:
                                          _updateTextLetterSpacing,
                                      textFontFamily: _textFontFamily,
                                      onTextFontFamilyChanged:
                                          _updateTextFontFamily,
                                      availableFontFamilies: _textFontFamilies,
                                      fontsLoading: _textFontsLoading,
                                      textAlign: _textAlign,
                                      onTextAlignChanged: _updateTextAlign,
                                      textOrientation: _textOrientation,
                                      onTextOrientationChanged:
                                          _updateTextOrientation,
                                      textAntialias: _textAntialias,
                                      onTextAntialiasChanged:
                                          _updateTextAntialias,
                                      textStrokeEnabled: _textStrokeEnabled,
                                      onTextStrokeEnabledChanged:
                                          _updateTextStrokeEnabled,
                                      textStrokeWidth: _textStrokeWidth,
                                      onTextStrokeWidthChanged:
                                          _updateTextStrokeWidth,
                                      textStrokeColor: _colorLineColor,
                                      onTextStrokeColorPressed:
                                          _handleEditTextStrokeColor,
                                      canvasRotation: _viewport.rotation,
                                      onCanvasRotationChanged:
                                          _setViewportRotation,
                                      onCanvasRotationReset:
                                          _resetViewportRotation,
                                    ),
                                  );
                                },
                              ),
                            ),
                            Align(
                              alignment: isLandscapeLayout
                                  ? Alignment.bottomCenter
                                  : Alignment.centerRight,
                              child: SafeArea(
                                top: !isLandscapeLayout,
                                left: isLandscapeLayout,
                                child: Padding(
                                  padding: isLandscapeLayout
                                      ? const EdgeInsets.only(bottom: 16)
                                      : const EdgeInsets.only(right: 16),
                                  child: _buildMobileRecentColors(
                                    theme,
                                    axis: isLandscapeLayout
                                        ? Axis.horizontal
                                        : Axis.vertical,
                                  ),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: MobileRightButtons(
                                colorIndicator: _buildColorIndicator(theme),
                                layerPanelBuilder: (context) =>
                                    _buildLayerPanelContent(theme),
                                rebuildListenable: _mobileUiRebuildListenable,
                              ),
                            ),
                            if (transformPanel != null) transformPanel,
                            if (transformCursorOverlay != null)
                              transformCursorOverlay,
                          ],
                          if (!suppressToolCursorOverlays &&
                              _toolCursorPosition != null &&
                              cursorStyle != null)
                            (() {
                              final Offset hotspot =
                                  cursorStyle.anchor - cursorStyle.iconOffset;
                              return Positioned(
                                left:
                                    _toolCursorPosition!.dx -
                                    hotspot.dx * toolIconLocateScale,
                                top:
                                    _toolCursorPosition!.dy -
                                    hotspot.dy * toolIconLocateScale,
                                child: IgnorePointer(
                                  ignoring: true,
                                  child: Transform.scale(
                                    scale: toolIconLocateScale,
                                    alignment: Alignment.topLeft,
                                    child: ToolCursorStyles.iconFor(
                                      _effectiveActiveTool,
                                      isDragging: isLayerAdjustDragging,
                                    ),
                                  ),
                                ),
                              );
                            })(),
                          if (!suppressToolCursorOverlays &&
                              _penRequiresOverlay &&
                              _penCursorWorkspacePosition != null)
                            overlayBrushRaster != null
                                ? CustomBrushCursorOverlay(
                                    position: _penCursorWorkspacePosition!,
                                    diameter: overlayCursorDiameter,
                                    raster: overlayBrushRaster,
                                    rotation: _brushRandomRotationEnabled
                                        ? brushRandomRotationRadians(
                                            center: _toBoardLocal(
                                              _penCursorWorkspacePosition!,
                                            ),
                                            seed: _isDrawing
                                                ? _controller
                                                      .activeStrokeRotationSeed
                                                : _brushRandomRotationPreviewSeed,
                                          )
                                        : 0.0,
                                  )
                                : PenCursorOverlay(
                                    position: _penCursorWorkspacePosition!,
                                    diameter: overlayCursorDiameter,
                                    shape: overlayBrushShape,
                                    rotation:
                                        _brushRandomRotationEnabled &&
                                            overlayBrushShape !=
                                                BrushShape.circle
                                        ? brushRandomRotationRadians(
                                            center: _toBoardLocal(
                                              _penCursorWorkspacePosition!,
                                            ),
                                            seed: _isDrawing
                                                ? _controller
                                                      .activeStrokeRotationSeed
                                                : _brushRandomRotationPreviewSeed,
                                          )
                                        : 0.0,
                                  ),
                          if (!suppressToolCursorOverlays &&
                              _toolCursorPosition != null)
                            Positioned(
                              left:
                                  _toolCursorPosition!.dx -
                                  (ToolCursorStyles.crosshairSize *
                                          crosshairLocateScale) /
                                      2,
                              top:
                                  _toolCursorPosition!.dy -
                                  (ToolCursorStyles.crosshairSize *
                                          crosshairLocateScale) /
                                      2,
                              child: IgnorePointer(
                                ignoring: true,
                                child: Transform.scale(
                                  scale: crosshairLocateScale,
                                  alignment: Alignment.topLeft,
                                  child: const ToolCursorCrosshair(),
                                ),
                              ),
                            ),
                          _buildBrushPresetWheelOverlay(theme),
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
