import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../bitmap_canvas/stroke_dynamics.dart' show StrokePressureProfile;
import '../../../canvas/canvas_tools.dart';
import '../../../canvas/text_renderer.dart' show CanvasTextOrientation;
import '../../preferences/app_preferences.dart' show PenStrokeSliderRange;
import '../../constants/pen_constants.dart'
    show kSprayStrokeMin, kSprayStrokeMax;
import '../../tooltips/hover_detail_tooltip.dart';
import 'measured_size.dart';
import 'selection_shape_icon.dart';

class ToolSettingsCard extends StatefulWidget {
  const ToolSettingsCard({
    super.key,
    required this.activeTool,
    required this.penStrokeWidth,
    required this.sprayStrokeWidth,
    required this.sprayMode,
    required this.penStrokeSliderRange,
    required this.onPenStrokeWidthChanged,
    required this.onSprayStrokeWidthChanged,
    required this.onSprayModeChanged,
    required this.brushShape,
    required this.onBrushShapeChanged,
    required this.strokeStabilizerStrength,
    required this.onStrokeStabilizerChanged,
    required this.stylusPressureEnabled,
    required this.onStylusPressureEnabledChanged,
    required this.simulatePenPressure,
    required this.onSimulatePenPressureChanged,
    required this.penPressureProfile,
    required this.onPenPressureProfileChanged,
    required this.brushAntialiasLevel,
    required this.onBrushAntialiasChanged,
    this.brushAntialiasMaxLevel = 3,
    required this.autoSharpPeakEnabled,
    required this.onAutoSharpPeakChanged,
    required this.bucketSampleAllLayers,
    required this.bucketContiguous,
    required this.bucketSwallowColorLine,
    required this.bucketAntialiasLevel,
    required this.onBucketSampleAllLayersChanged,
    required this.onBucketContiguousChanged,
    required this.onBucketSwallowColorLineChanged,
    required this.onBucketAntialiasChanged,
    this.bucketAntialiasMaxLevel = 3,
    required this.bucketTolerance,
    required this.onBucketToleranceChanged,
    required this.layerAdjustCropOutside,
    required this.onLayerAdjustCropOutsideChanged,
    required this.selectionShape,
    required this.onSelectionShapeChanged,
    required this.shapeToolVariant,
    required this.onShapeToolVariantChanged,
    required this.shapeFillEnabled,
    required this.onShapeFillChanged,
    required this.onSizeChanged,
    required this.magicWandTolerance,
    required this.onMagicWandToleranceChanged,
    required this.brushToolsEraserMode,
    required this.onBrushToolsEraserModeChanged,
    required this.vectorDrawingEnabled,
    required this.onVectorDrawingEnabledChanged,
    required this.vectorStrokeSmoothingEnabled,
    required this.onVectorStrokeSmoothingChanged,
    required this.strokeStabilizerMaxLevel,
    required this.textFontSize,
    required this.onTextFontSizeChanged,
    required this.textLineHeight,
    required this.onTextLineHeightChanged,
    required this.textLetterSpacing,
    required this.onTextLetterSpacingChanged,
    required this.textFontFamily,
    required this.onTextFontFamilyChanged,
    required this.availableFontFamilies,
    required this.fontsLoading,
    required this.textAlign,
    required this.onTextAlignChanged,
    required this.textOrientation,
    required this.onTextOrientationChanged,
    required this.textAntialias,
    required this.onTextAntialiasChanged,
    required this.textStrokeEnabled,
    required this.onTextStrokeEnabledChanged,
    required this.textStrokeWidth,
    required this.onTextStrokeWidthChanged,
    required this.textStrokeColor,
    required this.onTextStrokeColorPressed,
    this.compactLayout = false,
  });

  final CanvasTool activeTool;
  final double penStrokeWidth;
  final double sprayStrokeWidth;
  final SprayMode sprayMode;
  final PenStrokeSliderRange penStrokeSliderRange;
  final ValueChanged<double> onPenStrokeWidthChanged;
  final ValueChanged<double> onSprayStrokeWidthChanged;
  final ValueChanged<SprayMode> onSprayModeChanged;
  final BrushShape brushShape;
  final ValueChanged<BrushShape> onBrushShapeChanged;
  final double strokeStabilizerStrength;
  final ValueChanged<double> onStrokeStabilizerChanged;
  final bool stylusPressureEnabled;
  final ValueChanged<bool> onStylusPressureEnabledChanged;
  final bool simulatePenPressure;
  final ValueChanged<bool> onSimulatePenPressureChanged;
  final StrokePressureProfile penPressureProfile;
  final ValueChanged<StrokePressureProfile> onPenPressureProfileChanged;
  final int brushAntialiasLevel;
  final ValueChanged<int> onBrushAntialiasChanged;
  final int brushAntialiasMaxLevel;
  final bool autoSharpPeakEnabled;
  final ValueChanged<bool> onAutoSharpPeakChanged;
  final bool bucketSampleAllLayers;
  final bool bucketContiguous;
  final bool bucketSwallowColorLine;
  final int bucketAntialiasLevel;
  final int bucketAntialiasMaxLevel;
  final ValueChanged<bool> onBucketSampleAllLayersChanged;
  final ValueChanged<bool> onBucketContiguousChanged;
  final ValueChanged<bool> onBucketSwallowColorLineChanged;
  final ValueChanged<int> onBucketAntialiasChanged;
  final int bucketTolerance;
  final ValueChanged<int> onBucketToleranceChanged;
  final bool layerAdjustCropOutside;
  final ValueChanged<bool> onLayerAdjustCropOutsideChanged;
  final SelectionShape selectionShape;
  final ValueChanged<SelectionShape> onSelectionShapeChanged;
  final ShapeToolVariant shapeToolVariant;
  final ValueChanged<ShapeToolVariant> onShapeToolVariantChanged;
  final bool shapeFillEnabled;
  final ValueChanged<bool> onShapeFillChanged;
  final ValueChanged<Size> onSizeChanged;
  final int magicWandTolerance;
  final ValueChanged<int> onMagicWandToleranceChanged;
  final bool brushToolsEraserMode;
  final ValueChanged<bool> onBrushToolsEraserModeChanged;
  final bool vectorDrawingEnabled;
  final ValueChanged<bool> onVectorDrawingEnabledChanged;
  final bool vectorStrokeSmoothingEnabled;
  final ValueChanged<bool> onVectorStrokeSmoothingChanged;
  final int strokeStabilizerMaxLevel;
  final bool compactLayout;
  final double textFontSize;
  final ValueChanged<double> onTextFontSizeChanged;
  final double textLineHeight;
  final ValueChanged<double> onTextLineHeightChanged;
  final double textLetterSpacing;
  final ValueChanged<double> onTextLetterSpacingChanged;
  final String textFontFamily;
  final ValueChanged<String> onTextFontFamilyChanged;
  final List<String> availableFontFamilies;
  final bool fontsLoading;
  final TextAlign textAlign;
  final ValueChanged<TextAlign> onTextAlignChanged;
  final CanvasTextOrientation textOrientation;
  final ValueChanged<CanvasTextOrientation> onTextOrientationChanged;
  final bool textAntialias;
  final ValueChanged<bool> onTextAntialiasChanged;
  final bool textStrokeEnabled;
  final ValueChanged<bool> onTextStrokeEnabledChanged;
  final double textStrokeWidth;
  final ValueChanged<double> onTextStrokeWidthChanged;
  final Color textStrokeColor;
  final VoidCallback onTextStrokeColorPressed;

  @override
  State<ToolSettingsCard> createState() => _ToolSettingsCardState();
}

class _ToolSettingsCardState extends State<ToolSettingsCard> {
  static const double _defaultSliderWidth = 220;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isProgrammaticTextUpdate = false;

  static final List<TextInputFormatter> _digitInputFormatters =
      <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ];

  double get _sliderMin => widget.penStrokeSliderRange.min;
  double get _sliderMax => widget.penStrokeSliderRange.max;
  bool get _isSprayTool => widget.activeTool == CanvasTool.spray;
  double get _activeSliderMin => _isSprayTool ? kSprayStrokeMin : _sliderMin;
  double get _activeSliderMax => _isSprayTool ? kSprayStrokeMax : _sliderMax;
  bool get _sliderUsesIntegers =>
      _isSprayTool ||
      widget.penStrokeSliderRange == PenStrokeSliderRange.compact;
  double get _activeBrushValue => _isSprayTool
      ? widget.sprayStrokeWidth.clamp(kSprayStrokeMin, kSprayStrokeMax)
      : widget.penStrokeSliderRange.clamp(widget.penStrokeWidth);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatBrushValue(_activeBrushValue),
    );
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant ToolSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final double newValue = _activeBrushValue;
    final double previousValue = oldWidget.activeTool == CanvasTool.spray
        ? oldWidget.sprayStrokeWidth
        : oldWidget.penStrokeWidth;
    final bool toolChanged = widget.activeTool != oldWidget.activeTool;
    if (!_focusNode.hasFocus &&
        (toolChanged || (newValue - previousValue).abs() >= 0.01)) {
      final String nextValue = _formatBrushValue(newValue);
      if (_controller.text != nextValue) {
        _isProgrammaticTextUpdate = true;
        _controller.text = nextValue;
        _isProgrammaticTextUpdate = false;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final BorderRadius borderRadius = BorderRadius.circular(12);
    final Color fallbackColor = theme.brightness.isDark
        ? const Color(0xFF1F1F1F)
        : Colors.white;
    Color backgroundColor = theme.cardColor;
    if (backgroundColor.alpha != 0xFF) {
      backgroundColor = fallbackColor;
    }

    Widget content;
    switch (widget.activeTool) {
      case CanvasTool.pen:
      case CanvasTool.perspectivePen:
      case CanvasTool.curvePen:
        content = _buildBrushControls(theme);
        break;
      case CanvasTool.spray:
        content = _buildSprayControls(theme);
        break;
      case CanvasTool.eraser:
        content = _buildBrushControls(theme, includeEraserToggle: false);
        break;
      case CanvasTool.shape:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildShapeVariantRow(theme),
            const SizedBox(height: 12),
            _buildBrushControls(theme),
          ],
        );
        break;
      case CanvasTool.bucket:
        content = _buildControlsGroup(
          [
            _buildToleranceSlider(
              theme,
              label: '容差',
              value: widget.bucketTolerance,
              onChanged: widget.onBucketToleranceChanged,
            ),
            _buildBucketAntialiasRow(theme),
            _BucketOptionTile(
              title: '跨图层',
              value: widget.bucketSampleAllLayers,
              onChanged: widget.onBucketSampleAllLayersChanged,
              compact: widget.compactLayout,
            ),
            _BucketOptionTile(
              title: '连续',
              value: widget.bucketContiguous,
              onChanged: widget.onBucketContiguousChanged,
              compact: widget.compactLayout,
            ),
            _BucketOptionTile(
              title: '吞并色线',
              value: widget.bucketSwallowColorLine,
              onChanged: widget.onBucketSwallowColorLineChanged,
              compact: widget.compactLayout,
            ),
          ],
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
        );
        break;
      case CanvasTool.magicWand:
        content = _buildToleranceSlider(
          theme,
          label: '容差',
          value: widget.magicWandTolerance,
          onChanged: widget.onMagicWandToleranceChanged,
        );
        break;
      case CanvasTool.layerAdjust:
        content = _buildToggleSwitchRow(
          theme,
          label: '裁剪出界画面',
          value: widget.layerAdjustCropOutside,
          onChanged: widget.onLayerAdjustCropOutsideChanged,
        );
        break;
      case CanvasTool.selection:
        content = _buildSelectionShapeRow(theme);
        break;
      case CanvasTool.text:
        content = _buildTextControls(theme);
        break;
      default:
        content = Text('该工具暂无可调节参数', style: theme.typography.body);
        break;
    }

    Widget padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: content,
      ),
    );
    if (!widget.compactLayout) {
      padded = DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
          border: Border.all(
            color: theme.brightness.isDark
                ? Colors.white.withOpacity(0.12)
                : Colors.black.withOpacity(0.08),
          ),
        ),
        child: padded,
      );
    }
    return MeasuredSize(onChanged: widget.onSizeChanged, child: padded);
  }

  Widget _buildBrushControls(
    FluentThemeData theme, {
    bool includeEraserToggle = true,
  }) {
    final bool isPenTool = widget.activeTool == CanvasTool.pen ||
        widget.activeTool == CanvasTool.perspectivePen;
    final bool isEraserTool = widget.activeTool == CanvasTool.eraser;
    final bool isCurvePenTool = widget.activeTool == CanvasTool.curvePen;
    final bool isShapeTool = widget.activeTool == CanvasTool.shape;
    final bool showAdvancedBrushToggles =
        isPenTool || isCurvePenTool || isShapeTool || isEraserTool;

    final List<Widget> wrapChildren = <Widget>[
      _buildBrushSizeRow(theme),
      _buildBrushShapeRow(theme),
      if (isPenTool || isEraserTool) _buildStrokeStabilizerRow(theme),
    ];

    if (showAdvancedBrushToggles) {
      wrapChildren.add(_buildBrushAntialiasRow(theme));
      if (isShapeTool) {
        wrapChildren.add(
          _buildToggleSwitchRow(
            theme,
            label: '实心',
            value: widget.shapeFillEnabled,
            onChanged: widget.onShapeFillChanged,
          ),
        );
      }
      wrapChildren.add(
        _buildToggleSwitchRow(
          theme,
          label: '自动尖锐出入峰',
          value: widget.autoSharpPeakEnabled,
          onChanged: widget.onAutoSharpPeakChanged,
        ),
      );
      wrapChildren.add(
        _buildToggleSwitchRow(
          theme,
          label: '数位笔笔压',
          value: widget.stylusPressureEnabled,
          onChanged: widget.onStylusPressureEnabledChanged,
        ),
      );
      wrapChildren.add(
        _buildToggleSwitchRow(
          theme,
          label: '模拟笔压',
          value: widget.simulatePenPressure,
          onChanged: widget.onSimulatePenPressureChanged,
        ),
      );
      if (includeEraserToggle) {
        wrapChildren.add(
          _buildToggleSwitchRow(
            theme,
            label: '转换为擦除',
            value: widget.brushToolsEraserMode,
            onChanged: widget.onBrushToolsEraserModeChanged,
          ),
        );
      }
      wrapChildren.add(
        _buildToggleSwitchRow(
          theme,
          label: '矢量作画',
          value: widget.vectorDrawingEnabled,
          onChanged: widget.onVectorDrawingEnabledChanged,
        ),
      );
      if (widget.vectorDrawingEnabled) {
        wrapChildren.add(
          _buildToggleSwitchRow(
            theme,
            label: '平滑曲线',
            value: widget.vectorStrokeSmoothingEnabled,
            onChanged: widget.onVectorStrokeSmoothingChanged,
          ),
        );
      }
      if (widget.simulatePenPressure) {
        wrapChildren.add(
          SizedBox(
            width: widget.compactLayout ? double.infinity : 160,
            child: ComboBox<StrokePressureProfile>(
              value: widget.penPressureProfile,
              items: StrokePressureProfile.values
                  .map(
                    (profile) => ComboBoxItem<StrokePressureProfile>(
                      value: profile,
                      child: Text(_pressureProfileLabel(profile)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  widget.onPenPressureProfileChanged(value);
                }
              },
            ),
          ),
        );
      }
    }

    return _buildControlsGroup(
      wrapChildren,
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
    );
  }

  Widget _buildSprayControls(FluentThemeData theme) {
    final List<Widget> children = <Widget>[
      _buildBrushSizeRow(theme),
      _buildSprayModeSelector(theme),
      _buildToggleSwitchRow(
        theme,
        label: '转换为擦除',
        value: widget.brushToolsEraserMode,
        onChanged: widget.onBrushToolsEraserModeChanged,
      ),
    ];
    if (widget.sprayMode == SprayMode.splatter) {
      children.add(_buildBrushAntialiasRow(theme));
    }
    return _buildControlsGroup(
      children,
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
    );
  }

  Widget _buildSprayModeSelector(FluentThemeData theme) {
    return _buildLabeledComboField<SprayMode>(
      theme,
      label: '喷枪效果',
      width: 180,
      value: widget.sprayMode,
      items: SprayMode.values
          .map(
            (mode) => ComboBoxItem<SprayMode>(
              value: mode,
              child: Text(_sprayModeLabel(mode)),
            ),
          )
          .toList(growable: false),
      onChanged: (mode) {
        if (mode != null) {
          widget.onSprayModeChanged(mode);
        }
      },
    );
  }

  Widget _buildBrushShapeRow(FluentThemeData theme) {
    final Widget selector = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: BrushShape.values
          .map((shape) => _buildBrushShapeButton(theme, shape))
          .toList(),
    );

    if (!widget.compactLayout) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('笔刷形状', style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          selector,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('笔刷形状', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        selector,
      ],
    );
  }

  Widget _buildSelectionShapeRow(FluentThemeData theme) {
    final Widget selector = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: SelectionShape.values
          .map((shape) => _buildSelectionShapeButton(theme, shape))
          .toList(),
    );

    if (!widget.compactLayout) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('选区形状', style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          selector,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('选区形状', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        selector,
      ],
    );
  }

  Widget _buildTextControls(FluentThemeData theme) {
    final List<String> fontOptions = <String>[
      '系统默认',
      ...widget.availableFontFamilies,
    ];
    final bool fontAvailable =
        widget.textFontFamily.isNotEmpty &&
        widget.availableFontFamilies.contains(widget.textFontFamily);
    final String selectedFont = fontAvailable ? widget.textFontFamily : '系统默认';
    final List<Widget> children = <Widget>[
      _buildFontSelectorRow(
        theme,
        fontOptions: fontOptions,
        selectedFont: selectedFont,
        isLoading: widget.fontsLoading,
      ),
      _buildLabeledSlider(
        theme: theme,
        label: '字号',
        value: widget.textFontSize,
        min: 6,
        max: 200,
        formatter: (value) => '${value.toStringAsFixed(0)} px',
        onChanged: widget.onTextFontSizeChanged,
      ),
      _buildLabeledSlider(
        theme: theme,
        label: '行距',
        value: widget.textLineHeight,
        min: 0.5,
        max: 3.0,
        formatter: (value) => value.toStringAsFixed(2),
        onChanged: widget.onTextLineHeightChanged,
      ),
      _buildLabeledSlider(
        theme: theme,
        label: '文字间距',
        value: widget.textLetterSpacing,
        min: -100,
        max: 200,
        formatter: (value) => '${value.toStringAsFixed(1)} px',
        onChanged: widget.onTextLetterSpacingChanged,
      ),
      _buildTextAlignRow(theme),
      _buildTextOrientationRow(theme),
      _buildToggleSwitchRow(
        theme,
        label: '边缘柔化',
        value: widget.textAntialias,
        onChanged: widget.onTextAntialiasChanged,
      ),
      _buildToggleSwitchRow(
        theme,
        label: '文字描边',
        value: widget.textStrokeEnabled,
        onChanged: widget.onTextStrokeEnabledChanged,
      ),
    ];

    if (widget.textStrokeEnabled) {
      children.add(_buildTextStrokeColorRow(theme));
      children.add(
        _buildLabeledSlider(
          theme: theme,
          label: '描边宽度',
          value: widget.textStrokeWidth,
          min: 0.5,
          max: 20,
          formatter: (value) => value.toStringAsFixed(1),
          onChanged: widget.onTextStrokeWidthChanged,
        ),
      );
    }
    return _buildControlsGroup(
      children,
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
    );
  }

  Widget _buildFontSelectorRow(
    FluentThemeData theme, {
    required List<String> fontOptions,
    required String selectedFont,
    required bool isLoading,
  }) {
    final ComboBox<String> comboBox = ComboBox<String>(
      value: selectedFont,
      isExpanded: true,
      items: fontOptions
          .map(
            (family) => ComboBoxItem<String>(
              value: family,
              child: Text(
                _sanitizeDisplayText(family),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value == null) {
          return;
        }
        widget.onTextFontFamilyChanged(value == '系统默认' ? '' : value);
      },
    );

    final Widget loadingIndicator = SizedBox(
      width: 18,
      height: 18,
      child: const ProgressRing(strokeWidth: 2.0),
    );

    if (!widget.compactLayout) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('字体', style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          SizedBox(width: 220, child: comboBox),
          if (isLoading) ...[const SizedBox(width: 8), loadingIndicator],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('字体', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: comboBox),
            if (isLoading) ...[const SizedBox(width: 8), loadingIndicator],
          ],
        ),
      ],
    );
  }

  Widget _buildTextStrokeColorRow(FluentThemeData theme) {
    final Color borderColor = theme.resources.controlStrokeColorDefault;
    final Widget colorButton = _wrapButtonTooltip(
      label: '描边颜色',
      detail: '打开颜色选择器以调整文字描边颜色',
      child: Button(
        onPressed: widget.onTextStrokeColorPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: widget.textStrokeColor,
                border: Border.all(color: borderColor),
              ),
            ),
            const SizedBox(width: 8),
            const Text('选择颜色'),
          ],
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('描边颜色', style: theme.typography.bodyStrong),
        const SizedBox(width: 12),
        colorButton,
      ],
    );
  }

  Widget _buildTextAlignRow(FluentThemeData theme) {
    final List<TextAlign> alignments = <TextAlign>[
      TextAlign.left,
      TextAlign.center,
      TextAlign.right,
    ];
    final Wrap alignSelector = Wrap(
      spacing: 8,
      children: alignments
          .map((alignment) {
            final bool selected = widget.textAlign == alignment;
            final IconData icon;
            final String optionLabel;
            switch (alignment) {
              case TextAlign.center:
                icon = FluentIcons.align_center;
                optionLabel = '居中';
                break;
              case TextAlign.right:
                icon = FluentIcons.align_right;
                optionLabel = '右对齐';
                break;
              case TextAlign.left:
              default:
                icon = FluentIcons.align_left;
                optionLabel = '左对齐';
                break;
            }
            return _wrapButtonTooltip(
              label: '对齐方式：$optionLabel',
              detail: '切换文字对齐方式',
              child: ToggleButton(
                checked: selected,
                onChanged: (_) => widget.onTextAlignChanged(alignment),
                child: Icon(icon),
              ),
            );
          })
          .toList(growable: false),
    );
    if (!widget.compactLayout) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('对齐方式', style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          alignSelector,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('对齐方式', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        alignSelector,
      ],
    );
  }

  Widget _buildTextOrientationRow(FluentThemeData theme) {
    final Wrap orientationSelector = Wrap(
      spacing: 8,
      children: CanvasTextOrientation.values
          .map((orientation) {
            final bool selected = widget.textOrientation == orientation;
            final String label = orientation == CanvasTextOrientation.horizontal
                ? '横排'
                : '竖排';
            return _wrapButtonTooltip(
              label: '文字方向：$label',
              detail: '切换文字排版方向',
              child: ToggleButton(
                checked: selected,
                onChanged: (_) => widget.onTextOrientationChanged(orientation),
                child: Text(label),
              ),
            );
          })
          .toList(growable: false),
    );
    if (!widget.compactLayout) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('排列方向', style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          orientationSelector,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('排列方向', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        orientationSelector,
      ],
    );
  }

  Widget _buildTextToolHint(FluentThemeData theme) {
    return SizedBox(
      width: widget.compactLayout ? double.infinity : 320,
      child: Text(
        '文字填充颜色使用左下角取色器，描边颜色使用当前辅助色。',
        style: theme.typography.caption,
      ),
    );
  }

  String _sanitizeDisplayText(String raw) {
    if (raw.isEmpty) {
      return raw;
    }
    final List<int> units = raw.codeUnits;
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < units.length; i++) {
      final int unit = units[i];
      if (unit < 0x20) {
        continue;
      }
      if (_isLowSurrogate(unit)) {
        // 忽略孤立的低代理项，避免渲染异常。
        continue;
      }
      if (_isHighSurrogate(unit)) {
        if (i + 1 < units.length && _isLowSurrogate(units[i + 1])) {
          final int high = unit;
          final int low = units[++i];
          final int codePoint =
              0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
          buffer.writeCharCode(codePoint);
        } else {
          buffer.writeCharCode(0xFFFD);
        }
        continue;
      }
      buffer.writeCharCode(unit);
    }
    return buffer.toString();
  }

  bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;

  bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

  Widget _buildLabeledSlider({
    required FluentThemeData theme,
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String Function(double)? formatter,
  }) {
    final String display = formatter == null
        ? value.toStringAsFixed(1)
        : formatter(value);
    final Slider slider = Slider(
      min: min,
      max: max,
      value: value.clamp(min, max),
      onChanged: onChanged,
    );
    if (!widget.compactLayout) {
      final Widget sliderControl = _wrapSliderTooltip(
        label: label,
        valueText: display,
        child: SizedBox(width: _defaultSliderWidth, child: slider),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('$label：$display', style: theme.typography.body),
          const SizedBox(width: 8),
          sliderControl,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label：$display', style: theme.typography.body),
        const SizedBox(height: 4),
        _wrapSliderTooltip(label: label, valueText: display, child: slider),
      ],
    );
  }

  Widget _buildShapeVariantRow(FluentThemeData theme) {
    final Widget selector = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ShapeToolVariant.values
          .map((variant) => _buildShapeVariantButton(theme, variant))
          .toList(),
    );

    if (!widget.compactLayout) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('图形类型', style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          selector,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('图形类型', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        selector,
      ],
    );
  }

  Widget _buildShapeVariantButton(
    FluentThemeData theme,
    ShapeToolVariant variant,
  ) {
    return _buildIconToggleButton(
      theme: theme,
      isSelected: widget.shapeToolVariant == variant,
      tooltip: _shapeVariantLabel(variant),
      onPressed: () => widget.onShapeToolVariantChanged(variant),
      iconBuilder: (color) => _buildShapeVariantIcon(variant, color),
    );
  }

  Widget _buildShapeVariantIcon(ShapeToolVariant variant, Color color) {
    switch (variant) {
      case ShapeToolVariant.rectangle:
        return Icon(FluentIcons.rectangle_shape, size: 18, color: color);
      case ShapeToolVariant.ellipse:
        return Icon(FluentIcons.circle_shape, size: 18, color: color);
      case ShapeToolVariant.triangle:
        return Icon(FluentIcons.triangle_shape, size: 18, color: color);
      case ShapeToolVariant.line:
        return SvgPicture.asset(
          'icons/line2.svg',
          width: 24,
          height: 24,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        );
    }
  }

  Widget _buildSelectionShapeButton(
    FluentThemeData theme,
    SelectionShape shape,
  ) {
    return _buildIconToggleButton(
      theme: theme,
      isSelected: widget.selectionShape == shape,
      tooltip: _selectionShapeLabel(shape),
      onPressed: () => widget.onSelectionShapeChanged(shape),
      iconBuilder: (color) => _buildSelectionShapeIcon(shape, color),
    );
  }

  Widget _buildSelectionShapeIcon(SelectionShape shape, Color color) {
    return SelectionShapeIcon(shape: shape, color: color, size: 18);
  }

  Widget _buildIconToggleButton({
    required FluentThemeData theme,
    required bool isSelected,
    required String tooltip,
    required VoidCallback onPressed,
    required Widget Function(Color color) iconBuilder,
  }) {
    final Color accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final Color inactiveBackground = theme.resources.subtleFillColorSecondary;
    final Color baseBackground = isSelected
        ? accent.withOpacity(theme.brightness.isDark ? 0.35 : 0.2)
        : inactiveBackground;
    final Color hoverBackground =
        Color.lerp(baseBackground, accent.withOpacity(0.6), 0.2) ??
        baseBackground;
    final Color pressedBackground =
        Color.lerp(baseBackground, accent.withOpacity(0.8), 0.35) ??
        baseBackground;
    final Color borderColor = isSelected
        ? accent
        : theme.resources.controlStrokeColorDefault;
    final Color iconColor = isSelected
        ? accent
        : theme.typography.body?.color ?? theme.resources.textFillColorPrimary;

    return _wrapButtonTooltip(
      label: tooltip,
      child: Button(
        onPressed: onPressed,
        style: ButtonStyle(
          padding: WidgetStateProperty.all<EdgeInsets>(
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return pressedBackground;
            }
            if (states.contains(WidgetState.hovered)) {
              return hoverBackground;
            }
            return baseBackground;
          }),
          shape: WidgetStateProperty.all<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: borderColor, width: 1),
            ),
          ),
          foregroundColor: WidgetStateProperty.all<Color>(iconColor),
        ),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(child: iconBuilder(iconColor)),
        ),
      ),
    );
  }

  Widget _buildBrushShapeButton(FluentThemeData theme, BrushShape shape) {
    final bool isSelected = widget.brushShape == shape;
    final Color accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final Color inactiveBackground = theme.resources.subtleFillColorSecondary;
    final Color baseBackground = isSelected
        ? accent.withOpacity(theme.brightness.isDark ? 0.35 : 0.2)
        : inactiveBackground;
    final Color hoverBackground =
        Color.lerp(baseBackground, accent.withOpacity(0.6), 0.2) ??
        baseBackground;
    final Color pressedBackground =
        Color.lerp(baseBackground, accent.withOpacity(0.8), 0.35) ??
        baseBackground;
    final Color borderColor = isSelected
        ? accent
        : theme.resources.controlStrokeColorDefault;
    final TextStyle textStyle =
        (theme.typography.body ?? const TextStyle(fontSize: 12)).copyWith(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        );

    return _wrapButtonTooltip(
      label: _brushShapeLabel(shape),
      child: Button(
        onPressed: () => widget.onBrushShapeChanged(shape),
        style: ButtonStyle(
          padding: WidgetStateProperty.all<EdgeInsets>(
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return pressedBackground;
            }
            if (states.contains(WidgetState.hovered)) {
              return hoverBackground;
            }
            return baseBackground;
          }),
          shape: WidgetStateProperty.all<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: borderColor, width: 1),
            ),
          ),
          foregroundColor: WidgetStateProperty.all<Color>(
            theme.typography.body?.color ??
                theme.resources.textFillColorPrimary,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _brushShapeIcon(shape),
              size: 14,
              color: isSelected
                  ? accent
                  : theme.typography.body?.color ??
                        theme.resources.textFillColorPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              _brushShapeLabel(shape),
              style: textStyle.copyWith(
                color:
                    theme.typography.body?.color ??
                    theme.resources.textFillColorPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToleranceSlider(
    FluentThemeData theme, {
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    int max = 255,
  }) {
    final double sliderValue = value.clamp(0, max).toDouble();
    final Slider slider = Slider(
      value: sliderValue,
      min: 0,
      max: max.toDouble(),
      divisions: max,
      onChanged: (raw) => onChanged(raw.round()),
    );
    if (!widget.compactLayout) {
      final Widget sliderControl = _wrapSliderTooltip(
        label: label,
        valueText: '$value',
        child: SizedBox(width: _defaultSliderWidth, child: slider),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          sliderControl,
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: theme.typography.caption,
            ),
          ),
        ],
      );
    }
    return _buildSliderSection(
      theme,
      label: label,
      valueText: '$value',
      slider: slider,
      tooltipText: '$label：$value',
    );
  }

  double _clampBrushValue(double value) {
    if (_isSprayTool) {
      final double clamped = value.clamp(kSprayStrokeMin, kSprayStrokeMax);
      return clamped.roundToDouble();
    }
    return widget.penStrokeSliderRange.clamp(value);
  }

  void _notifyBrushSizeChanged(double value) {
    final double clamped = _clampBrushValue(value);
    if (_isSprayTool) {
      if ((clamped - widget.sprayStrokeWidth).abs() < 0.0005) {
        return;
      }
      widget.onSprayStrokeWidthChanged(clamped);
    } else {
      if ((clamped - widget.penStrokeWidth).abs() < 0.0005) {
        return;
      }
      widget.onPenStrokeWidthChanged(clamped);
    }
  }

  String _formatBrushValue(double value) {
    if (_isSprayTool) {
      return value.round().toString();
    }
    return _formatValue(value);
  }

  Widget _buildBrushSizeRow(FluentThemeData theme) {
    final double brushSize = _clampBrushValue(_activeBrushValue);
    final bool sliderUsesIntegers = _sliderUsesIntegers;
    final double sliderValue = sliderUsesIntegers
        ? brushSize.roundToDouble()
        : brushSize;
    final int? sliderDivisions = sliderUsesIntegers
        ? (_activeSliderMax - _activeSliderMin).round()
        : null;
    final String brushLabel = sliderUsesIntegers
        ? brushSize.round().toString()
        : _formatValue(brushSize);
    final String labelText = _isSprayTool ? '喷枪大小' : '笔刷大小';
    final Slider slider = Slider(
      value: sliderValue,
      min: _activeSliderMin,
      max: _activeSliderMax,
      divisions: sliderDivisions,
      onChanged: (raw) {
        final double nextValue = sliderUsesIntegers ? raw.roundToDouble() : raw;
        _notifyBrushSizeChanged(nextValue);
        if (!_focusNode.hasFocus) {
          final String formatted = _formatBrushValue(nextValue);
          if (_controller.text != formatted) {
            _isProgrammaticTextUpdate = true;
            _controller.value = TextEditingValue(
              text: formatted,
              selection: TextSelection.collapsed(offset: formatted.length),
            );
            _isProgrammaticTextUpdate = false;
          }
        }
      },
    );
    Widget buildStandardAdjustRow() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 124,
            child: SizedBox(
              height: 32,
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  _buildStrokeAdjustButton(
                    icon: FluentIcons.calculator_subtract,
                    delta: -1,
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 56,
                    child: TextBox(
                      focusNode: _focusNode,
                      controller: _controller,
                      inputFormatters: _digitInputFormatters,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: false,
                        decimal: true,
                      ),
                      onChanged: _handleTextChanged,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildStrokeAdjustButton(icon: FluentIcons.add, delta: 1),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('px', style: theme.typography.caption),
        ],
      );
    }

    Widget buildCompactAdjustRow() {
      return Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          _buildStrokeAdjustButton(
            icon: FluentIcons.calculator_subtract,
            delta: -1,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextBox(
                focusNode: _focusNode,
                controller: _controller,
                inputFormatters: _digitInputFormatters,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: false,
                  decimal: true,
                ),
                onChanged: _handleTextChanged,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _buildStrokeAdjustButton(icon: FluentIcons.add, delta: 1),
          const SizedBox(width: 6),
          Text('px', style: theme.typography.caption),
        ],
      );
    }

    if (!widget.compactLayout) {
      final Widget sliderControl = _wrapSliderTooltip(
        label: labelText,
        valueText: '$brushLabel px',
        child: SizedBox(width: _defaultSliderWidth, child: slider),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(labelText, style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          sliderControl,
          const SizedBox(width: 8),
          buildStandardAdjustRow(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSliderSection(
          theme,
          label: labelText,
          valueText: '$brushLabel px',
          slider: slider,
          tooltipText: '$labelText：$brushLabel px',
        ),
        const SizedBox(height: 8),
        buildCompactAdjustRow(),
      ],
    );
  }

  Widget _buildBrushAntialiasRow(FluentThemeData theme) {
    return _buildAntialiasRow(
      theme,
      value: widget.brushAntialiasLevel,
      maxLevel: widget.brushAntialiasMaxLevel,
      onChanged: widget.onBrushAntialiasChanged,
    );
  }

  Widget _buildBucketAntialiasRow(FluentThemeData theme) {
    return _buildAntialiasRow(
      theme,
      value: widget.bucketAntialiasLevel,
      maxLevel: widget.bucketAntialiasMaxLevel,
      onChanged: widget.onBucketAntialiasChanged,
    );
  }

  Widget _buildAntialiasRow(
    FluentThemeData theme, {
    required int value,
    required int maxLevel,
    required ValueChanged<int> onChanged,
  }) {
    final int safeMaxLevel = maxLevel.clamp(1, 50).toInt();
    final int clampedValue = value.clamp(0, safeMaxLevel).toInt();
    final Slider slider = Slider(
      value: clampedValue.toDouble(),
      min: 0,
      max: safeMaxLevel.toDouble(),
      divisions: safeMaxLevel,
      onChanged: (raw) => onChanged(raw.round().clamp(0, safeMaxLevel)),
    );
    if (!widget.compactLayout) {
      final Widget sliderControl = _wrapSliderTooltip(
        label: '边缘柔化',
        valueText: '等级 $clampedValue',
        child: SizedBox(width: _defaultSliderWidth, child: slider),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('边缘柔化', style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          sliderControl,
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              '等级 $clampedValue',
              style: theme.typography.caption,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      );
    }
    return _buildSliderSection(
      theme,
      label: '边缘柔化',
      valueText: '等级 $clampedValue',
      slider: slider,
      tooltipText: '边缘柔化：等级 $clampedValue',
    );
  }

  Widget _buildStrokeStabilizerRow(FluentThemeData theme) {
    final double value = widget.strokeStabilizerStrength.clamp(0.0, 1.0);
    final double projected = (value * widget.strokeStabilizerMaxLevel).clamp(
      0.0,
      widget.strokeStabilizerMaxLevel.toDouble(),
    );
    final int level = projected.round().clamp(
      0,
      widget.strokeStabilizerMaxLevel,
    );
    final double sliderValue = level.toDouble();
    final String label = level == 0 ? '关' : '等级 $level';
    final Slider slider = Slider(
      value: sliderValue,
      min: 0,
      max: widget.strokeStabilizerMaxLevel.toDouble(),
      divisions: widget.strokeStabilizerMaxLevel,
      onChanged: (raw) => widget.onStrokeStabilizerChanged(
        (raw / widget.strokeStabilizerMaxLevel).clamp(0.0, 1.0),
      ),
    );
    if (!widget.compactLayout) {
      final Widget sliderControl = _wrapSliderTooltip(
        label: '手抖修正',
        valueText: label,
        child: SizedBox(width: _defaultSliderWidth, child: slider),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('手抖修正', style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          sliderControl,
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: theme.typography.caption,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      );
    }
    return _buildSliderSection(
      theme,
      label: '手抖修正',
      valueText: label,
      slider: slider,
      tooltipText: '手抖修正：$label',
    );
  }

  Widget _buildToggleSwitchRow(
    FluentThemeData theme, {
    required String label,
    required bool value,
    ValueChanged<bool>? onChanged,
  }) {
    final Widget toggle = _wrapToggleTooltip(
      label: label,
      child: ToggleSwitch(checked: value, onChanged: onChanged),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.typography.bodyStrong),
        const SizedBox(width: 8),
        toggle,
      ],
    );
  }

  Widget _buildControlsGroup(
    List<Widget> children, {
    double spacing = 16,
    double runSpacing = 12,
    WrapCrossAlignment crossAxisAlignment = WrapCrossAlignment.center,
  }) {
    if (!widget.compactLayout) {
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        crossAxisAlignment: crossAxisAlignment,
        children: children,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _separateChildren(children, runSpacing),
    );
  }

  Widget _buildSliderSection(
    FluentThemeData theme, {
    required String label,
    required String valueText,
    required Widget slider,
    String? tooltipText,
  }) {
    Widget sliderWidget = LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(width: constraints.maxWidth, child: slider);
      },
    );
    sliderWidget = _wrapSliderTooltip(
      label: label,
      valueText: valueText,
      child: sliderWidget,
      messageOverride: tooltipText,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(label, style: theme.typography.bodyStrong),
            const SizedBox(width: 8),
            Text(valueText, style: theme.typography.caption),
          ],
        ),
        const SizedBox(height: 8),
        sliderWidget,
      ],
    );
  }

  Widget _wrapSliderTooltip({
    required String label,
    required String valueText,
    required Widget child,
    String? detail,
    String? messageOverride,
  }) {
    final String message = messageOverride ?? '$label：$valueText';
    final String resolvedDetail =
        detail ?? _sliderDetails[label] ?? '调整$label 以获得更合适的效果';
    return HoverDetailTooltip(
      message: message,
      detail: resolvedDetail,
      child: child,
    );
  }

  Widget _wrapButtonTooltip({
    required String label,
    required Widget child,
    String? detail,
  }) {
    final String resolvedDetail =
        detail ?? _buttonDetails[label] ?? '点击切换或应用$label';
    return HoverDetailTooltip(
      message: label,
      detail: resolvedDetail,
      child: child,
    );
  }

  Widget _wrapToggleTooltip({required String label, required Widget child}) {
    final String detail = _toggleDetails[label] ?? '点击开启或关闭$label';
    return HoverDetailTooltip(
      message: label,
      detail: detail,
      child: child,
    );
  }

  Widget _wrapComboTooltip({
    required String label,
    required Widget child,
    String? detail,
  }) {
    final String resolvedDetail =
        detail ?? _comboDetails[label] ?? '点击展开并选择$label';
    return HoverDetailTooltip(
      message: label,
      detail: resolvedDetail,
      child: child,
    );
  }

  List<Widget> _separateChildren(List<Widget> children, double spacing) {
    if (children.isEmpty) {
      return const <Widget>[];
    }
    final List<Widget> separated = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      separated.add(children[i]);
      if (i < children.length - 1) {
        separated.add(SizedBox(height: spacing));
      }
    }
    return separated;
  }

  Widget _buildLabeledComboField<T>(
    FluentThemeData theme, {
    required String label,
    required double width,
    required T value,
    required List<ComboBoxItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final Widget combo = _wrapComboTooltip(
      label: label,
      child: SizedBox(
        width: widget.compactLayout ? double.infinity : width,
        child: ComboBox<T>(value: value, items: items, onChanged: onChanged),
      ),
    );
    if (!widget.compactLayout) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          combo,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        combo,
      ],
    );
  }

  String _pressureProfileLabel(StrokePressureProfile profile) {
    switch (profile) {
      case StrokePressureProfile.taperEnds:
        return '两端粗中间细';
      case StrokePressureProfile.taperCenter:
        return '两端细中间粗';
      case StrokePressureProfile.auto:
        return '自动';
    }
  }

  String _sprayModeLabel(SprayMode mode) {
    switch (mode) {
      case SprayMode.smudge:
        return '柔和喷枪';
      case SprayMode.splatter:
        return '喷溅';
    }
  }

  void _handleTextChanged(String value) {
    if (_isProgrammaticTextUpdate) {
      return;
    }
    final double? parsed = double.tryParse(value);
    if (parsed == null) {
      return;
    }
    final double clamped = _clampBrushValue(parsed);
    final String formatted = _formatBrushValue(clamped);
    if (_controller.text != formatted) {
      _isProgrammaticTextUpdate = true;
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _isProgrammaticTextUpdate = false;
    }
    _notifyBrushSizeChanged(clamped);
  }

  void _handleFocusChange() {
    final String formatted = _formatBrushValue(_activeBrushValue);
    if (_controller.text != formatted) {
      _isProgrammaticTextUpdate = true;
      _controller.text = formatted;
      _isProgrammaticTextUpdate = false;
    }
  }

  void _adjustBrushSizeBy(int delta) {
    final double nextValue = _clampBrushValue(_activeBrushValue + delta);
    final double previousValue = _isSprayTool
        ? widget.sprayStrokeWidth
        : widget.penStrokeWidth;
    if ((nextValue - previousValue).abs() < 0.0005) {
      return;
    }
    _notifyBrushSizeChanged(nextValue);
    final String formatted = _formatBrushValue(nextValue);
    if (_controller.text != formatted) {
      _isProgrammaticTextUpdate = true;
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _isProgrammaticTextUpdate = false;
    }
  }

  Widget _buildStrokeAdjustButton({
    required IconData icon,
    required int delta,
  }) {
    final String action = delta > 0 ? '增大' : '减小';
    final int amount = delta.abs();
    final String label = '笔刷微调';
    final String detail = '$action笔刷大小 ${amount}px';
    return SizedBox(
      width: 28,
      height: 28,
      child: HoverDetailTooltip(
        message: '$label（$action）',
        detail: detail,
        child: IconButton(
          icon: Icon(icon, size: 14),
          onPressed: () => _adjustBrushSizeBy(delta),
        ),
      ),
    );
  }

  static String _formatValue(double value) {
    final double absValue = value.abs();
    String formatted;
    if (absValue >= 100.0) {
      formatted = value.toStringAsFixed(0);
    } else if (absValue >= 10.0) {
      formatted = value.toStringAsFixed(1);
    } else if (absValue >= 1.0) {
      formatted = value.toStringAsFixed(2);
    } else {
      formatted = value.toStringAsFixed(3);
    }
    return _stripTrailingZeros(formatted);
  }

  static String _stripTrailingZeros(String value) {
    if (!value.contains('.')) {
      return value;
    }
    String trimmed = value.replaceFirst(RegExp(r'0+$'), '');
    if (trimmed.endsWith('.')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.isEmpty ? '0' : trimmed;
  }
}

class _BucketOptionTile extends StatelessWidget {
  const _BucketOptionTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final String detail =
        _toggleDetails[title] ?? '点击开启或关闭$title';
    return Row(
      mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (compact)
          Expanded(
            child: Text(
              title,
              style: theme.typography.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        else
          Text(
            title,
            style: theme.typography.bodyStrong,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(width: 8),
        HoverDetailTooltip(
          message: title,
          detail: detail,
          child: ToggleSwitch(checked: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

String _selectionShapeLabel(SelectionShape shape) {
  switch (shape) {
    case SelectionShape.rectangle:
      return '矩形选区';
    case SelectionShape.ellipse:
      return '圆形选区';
    case SelectionShape.polygon:
      return '多边形套索';
  }
}

String _shapeVariantLabel(ShapeToolVariant variant) {
  switch (variant) {
    case ShapeToolVariant.rectangle:
      return '矩形';
    case ShapeToolVariant.ellipse:
      return '椭圆';
    case ShapeToolVariant.triangle:
      return '三角形';
    case ShapeToolVariant.line:
      return '直线';
  }
}

String _brushShapeLabel(BrushShape shape) {
  switch (shape) {
    case BrushShape.circle:
      return '圆形';
    case BrushShape.triangle:
      return '三角形';
    case BrushShape.square:
      return '正方形';
  }
}

IconData _brushShapeIcon(BrushShape shape) {
  switch (shape) {
    case BrushShape.circle:
      return FluentIcons.circle_shape;
    case BrushShape.triangle:
      return FluentIcons.triangle_shape;
    case BrushShape.square:
      return FluentIcons.square_shape;
  }
}

const Map<String, String> _sliderDetails = <String, String>{
  '笔刷大小': '设置当前笔刷的像素直径，数值越大线条越粗，越小越适合描画细节。',
  '喷枪大小': '决定喷枪喷洒区域的半径，半径大时覆盖面更广但颗粒更分散。',
  '容差': '控制油漆桶或魔棒判断"颜色足够相似"的阈值，容差高会一次抓取更多相近颜色。',
  '边缘柔化': '为笔刷或填色的边缘增加多重采样平滑，在平滑边缘的同时保留线条密度，0 级保持像素风格。',
  '手抖修正': '实时平滑指针轨迹来抵消手抖，等级越高线条越稳但响应会稍慢。',
  '字号': '调整文字的像素高度，用于整体放大或缩小当前文本。',
  '行距': '控制多行文字之间的垂直距离，便于营造疏朗或紧凑的段落。',
  '文字间距': '改变字符之间的水平间隔，可实现紧凑压缩或加宽排版。',
  '描边宽度': '设置文字描边的粗细，用来强调字形或营造漫画嵌字效果。',
};

const Map<String, String> _toggleDetails = <String, String>{
  '实心': '决定形状工具是绘制填充色块还是空心轮廓，开启后直接生成实心图形。',
  '自动尖锐出入峰': '为笔刷起笔与收笔自动收尖，营造赛璐璐式的利落线条。',
  '数位笔笔压': '让数位笔的压力实时影响笔刷粗细或透明度，关闭后忽略硬件笔压。',
  '模拟笔压': '在没有压感设备时根据鼠标速度模拟笔压变化，开启后也能画出有粗细变化的线条。',
  '转换为擦除': '把当前笔刷/喷枪切换为带同样纹理的橡皮擦，方便精确擦除。',
  '矢量作画': '以矢量曲线实时预览笔触，获得 120Hz 丝滑反馈并可无损缩放，关闭则直接落笔成像素。',
  '平滑曲线': '矢量作画开启时进一步平滑曲线节点，减少拐角但会牺牲一点跟手性。',
  '跨图层': '油漆桶采样所有可见图层的颜色，适合参考线稿填色；关闭只检测当前图层。',
  '连续': '仅在相邻像素间扩散，防止填充穿过未闭合的边界；关闭后会匹配整幅画布。',
  '吞并色线': '色块填充时自动吞并指定色线，消除描线与色块之间的白边，是 Retas 色线流程专用。',
  '裁剪出界画面': '调整图层时把超过画布的像素裁掉，保持文档边缘干净；关闭可保留全部像素。',
  '边缘柔化': '为文字绘制过程启用边缘柔化，平滑字形的同时保留线条密度；关闭可保留像素感。',
  '文字描边': '为文字轮廓开启描边通道，配合描边宽度与颜色突出文字。',
};

const Map<String, String> _comboDetails = <String, String>{
  '喷枪效果': '切换喷枪的散布模型："柔和喷枪"呈现雾状渐变，"喷溅"会喷出颗粒噪点，依据素材质感选择。',
};

const Map<String, String> _buttonDetails = <String, String>{
  '矩形选区': '使用矩形框快速圈选规则区域。',
  '圆形选区': '创建圆形或椭圆选区，适合柔和的局部限制。',
  '多边形套索': '逐点连线绘制任意多边形选区，适合复杂形状。',
  '矩形': '形状工具绘制水平矩形或正方形框/填充。',
  '椭圆': '绘制椭圆或圆形轮廓与填充。',
  '三角形': '绘制三角形几何或使用带尖角的三角形笔尖，获得锋利的轮廓。',
  '直线': '从起点到终点绘制直线段，适合构造硬质结构。',
  '圆形': '笔尖保持圆形，适合顺滑、柔和的笔触。',
  '正方形': '使用方形笔尖绘制硬边像素风笔触。',
};
