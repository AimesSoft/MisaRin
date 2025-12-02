import 'package:fluent_ui/fluent_ui.dart';

class LayerVisibilityButton extends StatelessWidget {
  const LayerVisibilityButton({
    super.key,
    required this.visible,
    required this.onChanged,
  });

  final bool visible;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final Color accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final Color borderColor = theme.resources.controlStrokeColorDefault;
    final Color background = Color.lerp(
      borderColor.withValues(alpha: borderColor.a * 0.1),
      accent,
      0.05,
    )!;
    final Color iconColor = visible
        ? accent
        : theme.brightness.isDark
        ? const Color(0xFFC0C0C0)
        : const Color(0xFF666666);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!visible),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: background,
            border: Border.all(
              color: borderColor.withValues(alpha: borderColor.a * 0.6),
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(
              visible ? FluentIcons.red_eye : FluentIcons.hide3,
              size: 14,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
