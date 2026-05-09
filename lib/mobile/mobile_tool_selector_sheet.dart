import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app/l10n/l10n.dart';
import '../../canvas/canvas_tools.dart';

class MobileToolSelectorSheet extends StatelessWidget {
  const MobileToolSelectorSheet({
    super.key,
    required this.activeTool,
    required this.onToolSelected,
  });

  final CanvasTool activeTool;
  final ValueChanged<CanvasTool> onToolSelected;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final l10n = context.l10n;

    final List<_ToolItem> tools = [
      _ToolItem(CanvasTool.pen, FluentIcons.edit, '画笔'),
      _ToolItem(CanvasTool.eraser, FluentIcons.erase_tool, '橡皮擦'),
      _ToolItem(CanvasTool.spray, 'icons/spray.svg', '喷枪'),
      _ToolItem(CanvasTool.smudge, FluentIcons.line_style, '涂抹'),
      _ToolItem(CanvasTool.liquify, FluentIcons.processing, '液化'),
      _ToolItem(CanvasTool.bucket, FluentIcons.bucket_color, '油漆桶'),
      _ToolItem(CanvasTool.eyedropper, FluentIcons.eyedropper, '吸管'),
      _ToolItem(CanvasTool.selection, 'icons/warp1.svg', '选区'),
      _ToolItem(CanvasTool.selectionPen, FluentIcons.inking_tool, '选区笔'),
      _ToolItem(CanvasTool.magicWand, FluentIcons.auto_enhance_on, '魔棒'),
      _ToolItem(CanvasTool.shape, FluentIcons.shapes, '图形'),
      _ToolItem(CanvasTool.text, FluentIcons.text_field, '文字'),
      _ToolItem(CanvasTool.layerAdjust, FluentIcons.move, '图层调节'),
      _ToolItem(CanvasTool.perspectivePen, FluentIcons.pencil_reply, '透视画笔'),
      _ToolItem(CanvasTool.curvePen, 'icons/line.svg', '曲线画笔'),
      _ToolItem(CanvasTool.hand, FluentIcons.hands_free, '手型'),
      _ToolItem(CanvasTool.rotate, FluentIcons.rotate, '旋转'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.menuTool,
            style: theme.typography.subtitle?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.82,
              ),
              itemCount: tools.length,
              itemBuilder: (context, index) {
                final tool = tools[index];
                final isSelected = tool.tool == activeTool;

                return _ToolGridItem(
                  icon: tool.icon,
                  label: tool.label,
                  isSelected: isSelected,
                  onPressed: () {
                    onToolSelected(tool.tool);
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolItem {
  final CanvasTool tool;
  final dynamic icon; // IconData or String (SVG path)
  final String label;

  _ToolItem(this.tool, this.icon, this.label);
}

class _ToolGridItem extends StatelessWidget {
  const _ToolGridItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  final dynamic icon;
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final Color color = isSelected
        ? Colors.white
        : theme.resources.textFillColorPrimary;
    const double labelSpacing = 4;
    const double labelHeight = 16;

    Widget iconWidget;
    if (icon is IconData) {
      iconWidget = Icon(icon as IconData, size: 32, color: color);
    } else {
      iconWidget = SvgPicture.asset(
        icon as String,
        width: 32,
        height: 32,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        double buttonSize = constraints.maxWidth;
        final double maxButton =
            constraints.maxHeight - labelHeight - labelSpacing;
        if (maxButton > 0 && maxButton < buttonSize) {
          buttonSize = maxButton;
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: buttonSize,
              child: Button(
                onPressed: onPressed,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (isSelected) return theme.accentColor;
                    if (states.isHovered) {
                      return theme.resources.subtleFillColorTertiary;
                    }
                    return theme.resources.subtleFillColorSecondary;
                  }),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  padding: WidgetStateProperty.all(EdgeInsets.zero),
                ),
                child: iconWidget,
              ),
            ),
            const SizedBox(height: labelSpacing),
            SizedBox(
              height: labelHeight,
              child: Center(
                child: Text(
                  label,
                  style: theme.typography.caption?.copyWith(
                    fontSize: 12,
                    color: isSelected ? theme.accentColor : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
