import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter_svg/flutter_svg.dart';
import '../../canvas/canvas_tools.dart';
import 'mobile_rounded_button.dart';
import 'mobile_tool_selector_sheet.dart';
import 'mobile_bottom_sheet.dart';

class MobileToolButtons extends StatelessWidget {
  const MobileToolButtons({
    super.key,
    required this.activeTool,
    required this.onToolSelected,
    required this.toolSettingsBuilder,
    this.rebuildListenable,
  });

  final CanvasTool activeTool;
  final ValueChanged<CanvasTool> onToolSelected;
  final WidgetBuilder toolSettingsBuilder;
  final Listenable? rebuildListenable;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tool Settings Button
            MobileRoundedButton(
              onPressed: () => _showToolSettings(context),
              child: const Icon(FluentIcons.settings, size: 24),
            ),
            const SizedBox(height: 16),
            // Tool Selector Button
            MobileRoundedButton(
              onPressed: () => _showToolSelector(context),
              child: _getToolIconWidget(activeTool, theme.accentColor),
            ),
          ],
        ),
      ),
    );
  }

  void _showToolSelector(BuildContext context) {
    showMobileBottomSheet(
      context: context,
      rebuildListenable: rebuildListenable,
      builder: (context) => MobileToolSelectorSheet(
        activeTool: activeTool,
        onToolSelected: onToolSelected,
      ),
    );
  }

  void _showToolSettings(BuildContext context) {
    showMobileBottomSheet(
      context: context,
      rebuildListenable: rebuildListenable,
      builder: toolSettingsBuilder,
    );
  }

  Widget _getToolIconWidget(CanvasTool tool, Color color) {
    final dynamic icon = _getToolIconData(tool);
    if (icon is IconData) {
      return Icon(icon, size: 28, color: color);
    } else {
      return SvgPicture.asset(
        icon as String,
        width: 28,
        height: 28,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
  }

  dynamic _getToolIconData(CanvasTool tool) {
    switch (tool) {
      case CanvasTool.layerAdjust:
        return FluentIcons.move;
      case CanvasTool.pen:
        return FluentIcons.edit;
      case CanvasTool.perspectivePen:
        return FluentIcons.pencil_reply;
      case CanvasTool.spray:
        return 'icons/spray.svg';
      case CanvasTool.smudge:
        return FluentIcons.line_style;
      case CanvasTool.liquify:
        return FluentIcons.processing;
      case CanvasTool.curvePen:
        return 'icons/line.svg';
      case CanvasTool.shape:
        return FluentIcons.shapes;
      case CanvasTool.eraser:
        return FluentIcons.erase_tool;
      case CanvasTool.bucket:
        return FluentIcons.bucket_color;
      case CanvasTool.magicWand:
        return FluentIcons.auto_enhance_on;
      case CanvasTool.eyedropper:
        return FluentIcons.eyedropper;
      case CanvasTool.selection:
        return 'icons/warp1.svg';
      case CanvasTool.selectionPen:
        return FluentIcons.inking_tool;
      case CanvasTool.text:
        return FluentIcons.text_field;
      case CanvasTool.hand:
        return FluentIcons.hands_free;
      case CanvasTool.rotate:
        return FluentIcons.rotate;
    }
  }
}
