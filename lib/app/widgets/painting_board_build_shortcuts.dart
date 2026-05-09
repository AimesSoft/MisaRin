part of 'painting_board.dart';

extension _PaintingBoardBuildShortcutsExtension on _PaintingBoardBuildMixin {
  Map<LogicalKeySet, Intent> _buildWorkspaceShortcutBindings() {
    if (_isTextEditingActive) {
      return <LogicalKeySet, Intent>{};
    }
    return {
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
              ToolbarAction.colorRange,
            ).shortcuts)
              key: const ShowColorRangeIntent(),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.adjustBlackWhite,
            ).shortcuts)
              key: const AdjustBlackWhiteIntent(),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.binarize,
            ).shortcuts)
              key: const AdjustBinarizeIntent(),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.scanPaperDrawing,
            ).shortcuts)
              key: const AdjustScanPaperDrawingIntent(),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.invertColors,
            ).shortcuts)
              key: const InvertColorsIntent(),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.narrowLines,
            ).shortcuts)
              key: const NarrowLinesIntent(),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.expandFill,
            ).shortcuts)
              key: const ExpandFillIntent(),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.gaussianBlur,
            ).shortcuts)
              key: const AdjustGaussianBlurIntent(),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.removeColorLeak,
            ).shortcuts)
              key: const RemoveColorLeakIntent(),
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
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.penTool,
            ).shortcuts)
              key: const SelectToolIntent(CanvasTool.pen),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.perspectivePenTool,
            ).shortcuts)
              key: const SelectToolIntent(CanvasTool.perspectivePen),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.sprayTool,
            ).shortcuts)
              key: const SelectToolIntent(CanvasTool.spray),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.smudgeTool,
            ).shortcuts)
              key: const SelectToolIntent(CanvasTool.smudge),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.curvePenTool,
            ).shortcuts)
              key: const SelectToolIntent(CanvasTool.curvePen),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.shapeTool,
            ).shortcuts)
              key: const SelectToolIntent(CanvasTool.shape),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.eraserTool,
            ).shortcuts)
              key: const SelectToolIntent(CanvasTool.eraser),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.bucketTool,
            ).shortcuts)
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
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.selectionPenTool,
            ).shortcuts)
              key: const SelectToolIntent(CanvasTool.selectionPen),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.textTool,
            ).shortcuts)
              key: const SelectToolIntent(CanvasTool.text),
	            for (final key in ToolbarShortcuts.of(
	              ToolbarAction.handTool,
	            ).shortcuts)
	              key: const SelectToolIntent(CanvasTool.hand),
	            for (final key in ToolbarShortcuts.of(
	              ToolbarAction.rotateTool,
	            ).shortcuts)
	              key: const SelectToolIntent(CanvasTool.rotate),
	            for (final key in ToolbarShortcuts.of(ToolbarAction.exit).shortcuts)
	              key: const ExitBoardIntent(),
	            for (final key in ToolbarShortcuts.of(
	              ToolbarAction.deselect,
            ).shortcuts)
              key: const DeselectIntent(),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.importReferenceImage,
            ).shortcuts)
              key: const ImportReferenceImageIntent(),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.viewBlackWhiteOverlay,
            ).shortcuts)
              key: const ToggleViewBlackWhiteIntent(),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.togglePixelGrid,
            ).shortcuts)
              key: const TogglePixelGridIntent(),
            for (final key in ToolbarShortcuts.of(
              ToolbarAction.viewMirrorOverlay,
            ).shortcuts)
              key: const ToggleViewMirrorIntent(),
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
            LogicalKeySet(LogicalKeyboardKey.delete):
                const DeleteSelectionIntent(),
            LogicalKeySet(LogicalKeyboardKey.backspace):
                const DeleteSelectionIntent(),
    };
  }

  Map<Type, Action<Intent>> _buildWorkspaceActionBindings({
    required VoidCallback toggleViewBlackWhiteOverlay,
    required VoidCallback togglePixelGridVisibility,
    required VoidCallback toggleViewMirrorOverlay,
  }) {
    return <Type, Action<Intent>>{
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
              DeleteSelectionIntent: CallbackAction<DeleteSelectionIntent>(
                onInvoke: (intent) {
                  unawaited(deleteSelection());
                  return null;
                },
              ),
              ToggleViewBlackWhiteIntent:
                  CallbackAction<ToggleViewBlackWhiteIntent>(
                    onInvoke: (intent) {
                      toggleViewBlackWhiteOverlay();
                      return null;
                    },
                  ),
              TogglePixelGridIntent: CallbackAction<TogglePixelGridIntent>(
                onInvoke: (intent) {
                  togglePixelGridVisibility();
                  return null;
                },
              ),
              ToggleViewMirrorIntent: CallbackAction<ToggleViewMirrorIntent>(
                onInvoke: (intent) {
                  toggleViewMirrorOverlay();
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
              ShowColorRangeIntent: CallbackAction<ShowColorRangeIntent>(
                onInvoke: (intent) {
                  unawaited(showColorRangeCard());
                  return null;
                },
              ),
              AdjustBlackWhiteIntent: CallbackAction<AdjustBlackWhiteIntent>(
                onInvoke: (intent) {
                  showBlackWhiteAdjustments();
                  return null;
                },
              ),
              AdjustBinarizeIntent: CallbackAction<AdjustBinarizeIntent>(
                onInvoke: (intent) {
                  showBinarizeAdjustments();
                  return null;
                },
              ),
              AdjustScanPaperDrawingIntent:
                  CallbackAction<AdjustScanPaperDrawingIntent>(
                    onInvoke: (intent) {
                      showScanPaperDrawingAdjustments();
                      return null;
                    },
                  ),
              InvertColorsIntent: CallbackAction<InvertColorsIntent>(
                onInvoke: (intent) {
                  unawaited(invertActiveLayerColors());
                  return null;
                },
              ),
              NarrowLinesIntent: CallbackAction<NarrowLinesIntent>(
                onInvoke: (intent) {
                  showLineNarrowAdjustments();
                  return null;
                },
              ),
              ExpandFillIntent: CallbackAction<ExpandFillIntent>(
                onInvoke: (intent) {
                  showFillExpandAdjustments();
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
              RemoveColorLeakIntent: CallbackAction<RemoveColorLeakIntent>(
                onInvoke: (intent) {
                  showLeakRemovalAdjustments();
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
    };
  }
}
