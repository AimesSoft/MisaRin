import 'package:fluent_ui/fluent_ui.dart';

/// Shared card layout used by toolbar-related panels.
class ToolbarPanelCard extends StatelessWidget {
  const ToolbarPanelCard({
    super.key,
    this.width,
    required this.title,
    required this.child,
    this.expand = false,
    this.trailing,
    this.showHeader = true,
  });

  final double? width;
  final String title;
  final Widget child;
  final bool expand;
  final Widget? trailing;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final BorderRadius borderRadius = BorderRadius.circular(20);
    final Color fallbackColor = theme.brightness.isDark
        ? const Color(0xFF1F1F1F)
        : Colors.white;
    Color backgroundColor = theme.cardColor;
    if (backgroundColor.alpha != 0xFF) {
      backgroundColor = fallbackColor;
    }

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
        border: Border.all(
          color: theme.brightness.isDark
              ? Colors.white.withOpacity(0.12)
              : Colors.black.withOpacity(0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (showHeader) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(title, style: theme.typography.subtitle),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 14),
            ],
            if (expand) Expanded(child: child) else child,
          ],
        ),
      ),
    );

    if (width != null) {
      content = SizedBox(width: width, child: content);
    }
    return content;
  }
}
