import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:window_manager/window_manager.dart';

import '../workspace/canvas_workspace_controller.dart';

typedef CanvasTabCallback = void Function(String id);

class CanvasTitleBar extends StatelessWidget {
  const CanvasTitleBar({
    super.key,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onCreateTab,
    required this.onRenameTab,
  });

  final CanvasTabCallback onSelectTab;
  final CanvasTabCallback onCloseTab;
  final VoidCallback onCreateTab;
  final CanvasTabCallback onRenameTab;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final CanvasWorkspaceController controller =
        CanvasWorkspaceController.instance;
    final bool showLinuxControls =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
    const EdgeInsets padding = EdgeInsets.only(
      left: 12,
      right: 12,
      top: 6,
      bottom: 6,
    );
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.micaBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.resources.controlStrokeColorDefault,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final List<CanvasWorkspaceEntry> entries = controller.entries;
                final String? activeId = controller.activeId;
                if (entries.isEmpty) {
                  return const SizedBox.shrink();
                }
                return _WorkspaceTabStrip(
                  entries: entries,
                  activeId: activeId,
                  onSelectTab: onSelectTab,
                  onCloseTab: onCloseTab,
                  onCreateTab: onCreateTab,
                  onRenameTab: onRenameTab,
                );
              },
            ),
          ),
          if (showLinuxControls) ...[
            const SizedBox(width: 12),
            const _LinuxWindowControls(),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceTabStrip extends StatelessWidget {
  const _WorkspaceTabStrip({
    required this.entries,
    required this.activeId,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onCreateTab,
    required this.onRenameTab,
  });

  final List<CanvasWorkspaceEntry> entries;
  final String? activeId;
  final CanvasTabCallback onSelectTab;
  final CanvasTabCallback onCloseTab;
  final VoidCallback onCreateTab;
  final CanvasTabCallback onRenameTab;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color hoverBackground = theme.resources.subtleFillColorTertiary;
    final Color pressedBackground = theme.resources.subtleFillColorSecondary;
    final Color baseIconColor = theme.resources.textFillColorSecondary;
    final Color hoverIconColor = theme.resources.textFillColorPrimary;
    final CanvasWorkspaceController controller =
        CanvasWorkspaceController.instance;
    return SizedBox(
      height: 36,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        primary: false,
        physics: const ClampingScrollPhysics(),
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) => child,
        itemCount: entries.length + 1,
        onReorder: (int oldIndex, int newIndex) {
          if (oldIndex >= entries.length) {
            return;
          }
          if (newIndex > entries.length) {
            newIndex = entries.length;
          }
          controller.reorder(oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          if (index >= entries.length) {
            return Padding(
              key: const ValueKey('__workspace_add_button__'),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Button(
                onPressed: onCreateTab,
                style: ButtonStyle(
                  padding: WidgetStateProperty.all<EdgeInsets>(
                    const EdgeInsets.all(6),
                  ),
                  shape: WidgetStateProperty.all<OutlinedBorder>(
                    const CircleBorder(),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                    states,
                  ) {
                    if (states.contains(WidgetState.pressed)) {
                      return pressedBackground;
                    }
                    if (states.contains(WidgetState.hovered)) {
                      return hoverBackground;
                    }
                    return Colors.transparent;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                    (states) => states.contains(WidgetState.hovered)
                        ? hoverIconColor
                        : baseIconColor,
                  ),
                ),
                child: const Icon(FluentIcons.add, size: 14),
              ),
            );
          }
          final CanvasWorkspaceEntry entry = entries[index];
          return Padding(
            key: ValueKey<String>(entry.id),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ReorderableDragStartListener(
              index: index,
              child: _WorkspaceTab(
                entry: entry,
                isActive: entry.id == activeId,
                onSelect: onSelectTab,
                onClose: onCloseTab,
                onRename: onRenameTab,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WorkspaceTab extends StatefulWidget {
  const _WorkspaceTab({
    required this.entry,
    required this.isActive,
    required this.onSelect,
    required this.onClose,
    required this.onRename,
  });

  final CanvasWorkspaceEntry entry;
  final bool isActive;
  final CanvasTabCallback onSelect;
  final CanvasTabCallback onClose;
  final CanvasTabCallback onRename;

  @override
  State<_WorkspaceTab> createState() => _WorkspaceTabState();
}

class _LinuxWindowControls extends StatelessWidget {
  const _LinuxWindowControls();

  Future<void> _handleClose() async {
    await windowManager.close();
  }

  Future<void> _handleMinimize() async {
    await windowManager.minimize();
  }

  Future<void> _handleToggleMaximize() async {
    final bool isMaximized = await windowManager.isMaximized();
    if (isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color hoverColor = FluentTheme.of(
      context,
    ).resources.subtleFillColorSecondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowControlButton(
          tooltip: '最小化',
          icon: FluentIcons.chrome_minimize,
          onPressed: _handleMinimize,
          hoverColor: hoverColor,
        ),
        const SizedBox(width: 6),
        _WindowControlButton(
          tooltip: '最大化/还原',
          icon: FluentIcons.chrome_restore,
          onPressed: _handleToggleMaximize,
          hoverColor: hoverColor,
        ),
        const SizedBox(width: 6),
        _WindowControlButton(
          tooltip: '关闭',
          icon: FluentIcons.chrome_close,
          onPressed: _handleClose,
          hoverColor: hoverColor,
        ),
      ],
    );
  }
}

class _WindowControlButton extends StatelessWidget {
  const _WindowControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.hoverColor,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final Color hoverColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Button(
        onPressed: () {
          onPressed();
        },
        style: ButtonStyle(
          padding: WidgetStateProperty.all<EdgeInsets>(const EdgeInsets.all(6)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered)
                ? hoverColor
                : Colors.transparent,
          ),
          shape: WidgetStateProperty.all<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
        child: Icon(icon, size: 12),
      ),
    );
  }
}

class _WorkspaceTabState extends State<_WorkspaceTab> {
  bool _hovered = false;

  Color _opaqueFill(Color fill, Color background) {
    if (fill.alpha == 0xFF) {
      return fill;
    }
    return Color.alphaBlend(fill, background);
  }

  void _handlePointer(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final bool isActive = widget.isActive;
    final bool hovered = _hovered;
    final Color containerBackground = theme.micaBackgroundColor;
    final Color hoverFill = _opaqueFill(
      theme.resources.subtleFillColorTertiary,
      containerBackground,
    );
    final Color baseFill = containerBackground;
    final bool highlight = hovered || isActive;
    final Color backgroundColor = highlight ? hoverFill : baseFill;
    final Color borderColor = highlight
        ? theme.resources.controlStrokeColorSecondary
        : Colors.transparent;
    final TextStyle baseStyle =
        theme.typography.caption ?? theme.typography.body ?? const TextStyle();
    final Color inactiveTextColor =
        baseStyle.color ?? theme.resources.textFillColorSecondary;
    final Color hoverTextColor =
        theme.typography.body?.color ??
        theme.typography.bodyStrong?.color ??
        inactiveTextColor;
    final Color textColor = highlight ? hoverTextColor : inactiveTextColor;
    final Color closeIconColor = textColor.withOpacity(highlight ? 0.95 : 0.75);
    final List<BoxShadow>? shadows = highlight
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(
                theme.brightness.isDark ? 0.3 : 0.12,
              ),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ]
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: MouseRegion(
        onEnter: (_) => _handlePointer(true),
        onExit: (_) => _handlePointer(false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelect(widget.entry.id),
          onDoubleTap: () {
            widget.onSelect(widget.entry.id);
            widget.onRename(widget.entry.id);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: shadows,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    style: baseStyle.copyWith(color: textColor),
                    child: Text(
                      widget.entry.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (widget.entry.isDirty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      FluentIcons.circle_shape_solid,
                      size: 6,
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onClose(widget.entry.id),
                      child: Icon(
                        FluentIcons.chrome_close,
                        size: 10,
                        color: closeIconColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
