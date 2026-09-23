import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

import 'app_slider.dart';

/// The opaque color picker used by the canvas and text material dialogs.
/// Keeps Fluent's spectrum and inputs, replacing its internal Material slider
/// on macOS for the same AXTree workaround as [AppSlider].
class AppColorPicker extends StatefulWidget {
  const AppColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
    this.colorSpectrumShape = ColorSpectrumShape.ring,
    this.isHexInputVisible = true,
  });

  final Color color;
  final ValueChanged<Color> onChanged;
  final ColorSpectrumShape colorSpectrumShape;
  final bool isHexInputVisible;

  @override
  State<AppColorPicker> createState() => _AppColorPickerState();
}

class _AppColorPickerState extends State<AppColorPicker> {
  late Color _color = widget.color;
  late HSVColor _hsv = HSVColor.fromColor(widget.color);

  @override
  void didUpdateWidget(covariant AppColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.color != oldWidget.color && widget.color != _color) {
      _setColor(widget.color);
    }
  }

  void _setColor(Color color) {
    _color = color;
    final hsv = HSVColor.fromColor(color);
    // Retain the chosen hue when brightness passes through black.
    _hsv = hsv.value == 0 ? _hsv.withValue(0) : hsv;
  }

  void _change(Color color) {
    setState(() => _setColor(color));
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    final macOS = defaultTargetPlatform == TargetPlatform.macOS;
    final hsv = _hsv;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ColorPicker(
          color: _color,
          onChanged: _change,
          colorSpectrumShape: widget.colorSpectrumShape,
          isHexInputVisible: widget.isHexInputVisible,
          isColorSliderVisible: !macOS,
          isMoreButtonVisible: false,
          isColorChannelTextInputVisible: false,
          isAlphaEnabled: false,
          isAlphaSliderVisible: false,
          isAlphaTextInputVisible: false,
        ),
        if (macOS) ...[
          const SizedBox(height: 24),
          SizedBox(
            width: 312,
            height: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  colors: [Colors.black, hsv.withValue(1).toColor()],
                ),
              ),
              child: AppSlider(
                value: hsv.value,
                min: 0,
                max: 1,
                style: SliderThemeData(
                  activeColor: WidgetStatePropertyAll(
                    FluentTheme.of(context).resources.focusStrokeColorOuter,
                  ),
                  trackHeight: const WidgetStatePropertyAll(0),
                  thumbRadius: const WidgetStatePropertyAll(8),
                  thumbBallInnerFactor: const WidgetStatePropertyAll(0.6),
                ),
                label: FluentLocalizations.of(
                  context,
                ).valueSliderTooltip((hsv.value * 100).round(), ''),
                onChanged: (value) => _change(hsv.withValue(value).toColor()),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
