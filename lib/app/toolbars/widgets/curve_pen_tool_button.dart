import 'package:fluent_ui/fluent_ui.dart';

import 'toolbar_tool_button_frame.dart';

class CurvePenToolButton extends StatelessWidget {
  const CurvePenToolButton({
    super.key,
    required this.isSelected,
    required this.onPressed,
  });

  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ToolbarToolButtonFrame(
      isSelected: isSelected,
      onPressed: onPressed,
      builder: (context, iconColor, _) => Center(
        child: Image.asset(
          'icons/line.png',
          width: 20,
          height: 20,
          color: iconColor,
          colorBlendMode: BlendMode.srcIn,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
