import 'package:fluent_ui/fluent_ui.dart';

import 'package:misa_rin/canvas/canvas_tools.dart';

import 'toolbar_tool_button_frame.dart';

class ShapeToolButton extends StatelessWidget {
  const ShapeToolButton({
    super.key,
    required this.isSelected,
    required this.variant,
    required this.onPressed,
  });

  final bool isSelected;
  final ShapeToolVariant variant;
  final VoidCallback onPressed;

  static IconData _iconForVariant(ShapeToolVariant variant) {
    switch (variant) {
      case ShapeToolVariant.rectangle:
        return FluentIcons.rectangle_shape;
      case ShapeToolVariant.ellipse:
        return FluentIcons.circle_shape;
      case ShapeToolVariant.triangle:
        return FluentIcons.triangle_shape;
      case ShapeToolVariant.line:
        return FluentIcons.line_style;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolbarToolButtonFrame(
      isSelected: isSelected,
      onPressed: onPressed,
      builder: (context, iconColor, _) => Center(child: _buildIcon(iconColor)),
    );
  }

  Widget _buildIcon(Color color) {
    if (variant == ShapeToolVariant.line) {
      return Image.asset(
        'icons/line2.png',
        width: 24,
        height: 24,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.high,
      );
    }
    return Icon(_iconForVariant(variant), color: color, size: 24);
  }
}
