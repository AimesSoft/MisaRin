import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../bitmap_canvas/stroke_dynamics.dart' show StrokePressureProfile;
import '../../../canvas/canvas_tools.dart';
import '../../preferences/app_preferences.dart' show PenStrokeSliderRange;
import '../../constants/pen_constants.dart'
    show kSprayStrokeMin, kSprayStrokeMax;
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
    required this.strokeStabilizerMaxLevel,
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
  final bool autoSharpPeakEnabled;
  final ValueChanged<bool> onAutoSharpPeakChanged;
  final bool bucketSampleAllLayers;
  final bool bucketContiguous;
  final bool bucketSwallowColorLine;
  final int bucketAntialiasLevel;
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
  final int strokeStabilizerMaxLevel;
  final bool compactLayout;

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
    final bool isPenTool = widget.activeTool == CanvasTool.pen;
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
        return Image.asset(
          'icons/line2.png',
          width: 24,
          height: 24,
          color: color,
          colorBlendMode: BlendMode.srcIn,
          filterQuality: FilterQuality.high,
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

    return Tooltip(
      message: tooltip,
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

    return Tooltip(
      message: _brushShapeLabel(shape),
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
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          SizedBox(width: _defaultSliderWidth, child: slider),
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
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(labelText, style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          SizedBox(width: _defaultSliderWidth, child: slider),
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
      onChanged: widget.onBrushAntialiasChanged,
    );
  }

  Widget _buildBucketAntialiasRow(FluentThemeData theme) {
    return _buildAntialiasRow(
      theme,
      value: widget.bucketAntialiasLevel,
      onChanged: widget.onBucketAntialiasChanged,
    );
  }

  Widget _buildAntialiasRow(
    FluentThemeData theme, {
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final Slider slider = Slider(
      value: value.toDouble(),
      min: 0,
      max: 3,
      divisions: 3,
      onChanged: (raw) => onChanged(raw.round()),
    );
    if (!widget.compactLayout) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('抗锯齿', style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          SizedBox(width: _defaultSliderWidth, child: slider),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              '等级 $value',
              style: theme.typography.caption,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      );
    }
    return _buildSliderSection(
      theme,
      label: '抗锯齿',
      valueText: '等级 $value',
      slider: slider,
      tooltipText: '抗锯齿：等级 $value',
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
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('手抖修正', style: theme.typography.bodyStrong),
          const SizedBox(width: 8),
          SizedBox(width: _defaultSliderWidth, child: slider),
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
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.typography.bodyStrong),
        const SizedBox(width: 8),
        ToggleSwitch(checked: value, onChanged: onChanged),
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
    if (widget.compactLayout && tooltipText != null) {
      sliderWidget = Tooltip(
        message: tooltipText,
        style: const TooltipThemeData(waitDuration: Duration.zero),
        useMousePosition: true,
        displayHorizontally: true,
        child: sliderWidget,
      );
    }
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
    final Widget combo = SizedBox(
      width: widget.compactLayout ? double.infinity : width,
      child: ComboBox<T>(value: value, items: items, onChanged: onChanged),
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
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(icon, size: 14),
        onPressed: () => _adjustBrushSizeBy(delta),
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
        ToggleSwitch(checked: value, onChanged: onChanged),
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
