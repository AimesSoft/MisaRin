import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../widgets/window_drag_area.dart';
import 'menu_action_dispatcher.dart';
import 'menu_definitions.dart';

class CustomMenuBar extends StatefulWidget {
  const CustomMenuBar({
    super.key,
    required this.menus,
    this.navigatorKey,
    this.showMenus = true,
  });

  final List<MenuDefinition> menus;
  final GlobalKey<NavigatorState>? navigatorKey;
  final bool showMenus;

  @override
  State<CustomMenuBar> createState() => _CustomMenuBarState();

  static MenuDefinition? _pruneMenu(MenuDefinition menu) {
    final List<MenuEntry> entries = _pruneEntries(menu.entries);
    if (entries.isEmpty) {
      return null;
    }
    return MenuDefinition(label: menu.label, entries: entries);
  }

  static List<MenuEntry> _pruneEntries(List<MenuEntry> entries) {
    final List<MenuEntry> result = <MenuEntry>[];
    for (final MenuEntry entry in entries) {
      if (entry is MenuProvidedEntry) {
        continue;
      }
      if (entry is MenuSubmenuEntry) {
        final List<MenuEntry> children = _pruneEntries(entry.entries);
        if (children.isEmpty) {
          continue;
        }
        result.add(MenuSubmenuEntry(label: entry.label, entries: children));
        continue;
      }
      if (entry is MenuSeparatorEntry) {
        if (result.isEmpty || result.last is MenuSeparatorEntry) {
          continue;
        }
        result.add(entry);
        continue;
      }
      result.add(entry);
    }
    while (result.isNotEmpty && result.last is MenuSeparatorEntry) {
      result.removeLast();
    }
    return result;
  }

  static bool _supportsWindowDragArea() {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static bool _shouldShowWindowControls() {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }
}

class _CustomMenuBarState extends State<CustomMenuBar> {
  FlyoutController? _openController;
  final ValueNotifier<bool> _menuOpenNotifier = ValueNotifier<bool>(false);

  void _handleMenuWillOpen(FlyoutController controller) {
    if (_openController == controller) {
      return;
    }
    if (_openController?.isOpen ?? false) {
      _openController!.forceClose();
    }
    _openController = controller;
    if (!_menuOpenNotifier.value) {
      _menuOpenNotifier.value = true;
    }
  }

  void _handleMenuClosed(FlyoutController controller) {
    if (_openController == controller) {
      _openController = null;
      if (_menuOpenNotifier.value) {
        _menuOpenNotifier.value = false;
      }
    }
  }

  @override
  void dispose() {
    _menuOpenNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<MenuDefinition> visibleMenus = widget.showMenus
        ? widget.menus
              .map(CustomMenuBar._pruneMenu)
              .whereType<MenuDefinition>()
              .toList(growable: false)
        : const <MenuDefinition>[];
    final theme = FluentTheme.of(context);
    final bool canDrag = CustomMenuBar._supportsWindowDragArea();
    final bool showWindowControls = CustomMenuBar._shouldShowWindowControls();
    final bool hasMenuButtons = visibleMenus.isNotEmpty;
    if (!hasMenuButtons && !canDrag && !showWindowControls) {
      return const SizedBox.shrink();
    }
    final Widget dragArea = canDrag
        ? Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: WindowDragArea(
                enableDoubleClickToMaximize: true,
                canDragAtPosition: (_) => true,
                child: const SizedBox.expand(),
              ),
            ),
          )
        : const Spacer();
    return Container(
      decoration: BoxDecoration(
        color: theme.micaBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.resources.controlStrokeColorDefault,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 36,
          child: ValueListenableBuilder<bool>(
            valueListenable: _menuOpenNotifier,
            builder: (context, anyMenuOpen, _) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < visibleMenus.length; i++) ...[
                    _MenuButton(
                      definition: visibleMenus[i],
                      navigatorKey: widget.navigatorKey,
                      onMenuWillOpen: _handleMenuWillOpen,
                      onMenuClosed: _handleMenuClosed,
                      isAnyMenuOpen: anyMenuOpen,
                    ),
                    if (i != visibleMenus.length - 1) const SizedBox(width: 4),
                  ],
                  dragArea,
                  if (showWindowControls) ...[
                    const SizedBox(width: 8),
                    const _WindowControlButtons(),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatefulWidget {
  const _MenuButton({
    required this.definition,
    this.navigatorKey,
    this.onMenuWillOpen,
    this.onMenuClosed,
    this.isAnyMenuOpen = false,
  });

  final MenuDefinition definition;
  final GlobalKey<NavigatorState>? navigatorKey;
  final ValueChanged<FlyoutController>? onMenuWillOpen;
  final ValueChanged<FlyoutController>? onMenuClosed;
  final bool isAnyMenuOpen;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  late final FlyoutController _flyoutController = FlyoutController();
  bool _hovered = false;

  @override
  void dispose() {
    _flyoutController.dispose();
    super.dispose();
  }

  void _openMenu({bool toggleIfOpen = true}) {
    if (widget.definition.entries.isEmpty) {
      return;
    }
    final NavigatorState? navigator =
        widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);
    if (navigator == null) {
      return;
    }
    if (_flyoutController.isOpen) {
      if (toggleIfOpen) {
        _flyoutController.close();
        widget.onMenuClosed?.call(_flyoutController);
      }
      return;
    }
    widget.onMenuWillOpen?.call(_flyoutController);
    unawaited(
      _flyoutController
          .showFlyout(
            barrierDismissible: true,
            barrierColor: Colors.transparent,
            placementMode: FlyoutPlacementMode.bottomLeft,
            navigatorKey: navigator,
            additionalOffset: 0,
            margin: 0,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            transitionBuilder: (context, animation, placementMode, flyout) =>
                flyout,
            builder: (context) {
              return MenuFlyout(
                items: _buildMenuItems(context, widget.definition.entries),
              );
            },
          )
          .whenComplete(() => widget.onMenuClosed?.call(_flyoutController)),
    );
  }

  void _handlePointerEnter(PointerEnterEvent event) {
    setState(() => _hovered = true);
    if (widget.isAnyMenuOpen && !_flyoutController.isOpen) {
      _openMenu(toggleIfOpen: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final TextStyle textStyle =
        theme.typography.body?.copyWith(fontWeight: FontWeight.w600) ??
        const TextStyle(fontWeight: FontWeight.w600);
    final Color textColor = _hovered
        ? theme.resources.textFillColorPrimary
        : theme.typography.body?.color ?? Colors.white;

    return FlyoutTarget(
      controller: _flyoutController,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: _handlePointerEnter,
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openMenu(toggleIfOpen: true),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? theme.resources.subtleFillColorSecondary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.definition.label,
              style: textStyle.copyWith(color: textColor),
            ),
          ),
        ),
      ),
    );
  }

  List<MenuFlyoutItemBase> _buildMenuItems(
    BuildContext context,
    List<MenuEntry> entries,
  ) {
    final List<MenuFlyoutItemBase> items = <MenuFlyoutItemBase>[];
    for (final MenuEntry entry in entries) {
      if (entry is MenuSeparatorEntry) {
        if (items.isEmpty || items.last is MenuFlyoutSeparator) {
          continue;
        }
        items.add(const MenuFlyoutSeparator());
        continue;
      }
      final MenuFlyoutItemBase? flyoutItem = _convertEntry(context, entry);
      if (flyoutItem != null) {
        items.add(flyoutItem);
      }
    }
    if (items.isNotEmpty && items.last is MenuFlyoutSeparator) {
      items.removeLast();
    }
    return items;
  }

  MenuFlyoutItemBase? _convertEntry(BuildContext context, MenuEntry entry) {
    if (entry is MenuActionEntry) {
      final VoidCallback? onPressed = _wrapAction(entry.action);
      if (onPressed == null) {
        return null;
      }
      final String? shortcutLabel = _formatShortcut(entry.shortcut);
      final TextStyle? shortcutStyle = FluentTheme.of(context)
          .typography
          .caption
          ?.copyWith(
            color: FluentTheme.of(context).resources.textFillColorSecondary,
          );
      return MenuFlyoutItem(
        leading: entry.checked
            ? const Icon(FluentIcons.check_mark, size: 12)
            : null,
        text: Text(entry.label),
        trailing: shortcutLabel == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(shortcutLabel, style: shortcutStyle),
              ),
        onPressed: onPressed,
      );
    }
    if (entry is MenuSubmenuEntry) {
      final List<MenuEntry> children = entry.entries;
      if (children.isEmpty) {
        return null;
      }
      return MenuFlyoutSubItem(
        text: Text(entry.label),
        items: (context) => _buildMenuItems(context, children),
      );
    }
    return null;
  }
}

class _WindowControlButtons extends StatefulWidget {
  const _WindowControlButtons();

  @override
  State<_WindowControlButtons> createState() => _WindowControlButtonsState();
}

class _WindowControlButtonsState extends State<_WindowControlButtons>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncMaximizeState());
  }

  Future<void> _syncMaximizeState() async {
    final bool value = await windowManager.isMaximized();
    if (!mounted) {
      return;
    }
    setState(() => _isMaximized = value);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _minimize() {
    unawaited(windowManager.minimize());
  }

  void _toggleMaximize() {
    unawaited(_toggle());
  }

  Future<void> _toggle() async {
    final bool isMaximized = await windowManager.isMaximized();
    if (isMaximized) {
      await windowManager.unmaximize();
      _updateMaximizeState(false);
    } else {
      await windowManager.maximize();
      _updateMaximizeState(true);
    }
  }

  void _close() {
    unawaited(windowManager.close());
  }

  void _updateMaximizeState(bool value) {
    if (!mounted || _isMaximized == value) {
      return;
    }
    setState(() => _isMaximized = value);
  }

  @override
  void onWindowMaximize() {
    _updateMaximizeState(true);
  }

  @override
  void onWindowUnmaximize() {
    _updateMaximizeState(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final Color iconColor =
        theme.typography.body?.color ?? theme.resources.textFillColorPrimary;
    final Color hoverColor = theme.resources.subtleFillColorSecondary
        .withOpacity(0.8);
    final Color closeHoverColor = const Color(0xFFD13438).withOpacity(0.85);
    final IconData maximizeIcon = _isMaximized
        ? FluentIcons.chrome_restore
        : FluentIcons.square_shape;
    final String maximizeTooltip = _isMaximized ? '还原' : '最大化';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          tooltip: '最小化',
          icon: FluentIcons.chrome_minimize,
          iconColor: iconColor,
          hoverColor: hoverColor,
          onPressed: _minimize,
        ),
        const SizedBox(width: 4),
        _CaptionButton(
          tooltip: maximizeTooltip,
          icon: maximizeIcon,
          iconColor: iconColor,
          hoverColor: hoverColor,
          onPressed: _toggleMaximize,
        ),
        const SizedBox(width: 4),
        _CaptionButton(
          tooltip: '关闭',
          icon: FluentIcons.chrome_close,
          iconColor: iconColor,
          hoverColor: closeHoverColor,
          onPressed: _close,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.icon,
    required this.iconColor,
    required this.hoverColor,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color iconColor;
  final Color hoverColor;
  final VoidCallback onPressed;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    final Color background = _hovered ? widget.hoverColor : Colors.transparent;
    final Color iconColor = _hovered
        ? _contrastingColor(widget.hoverColor)
        : widget.iconColor;
    const EdgeInsets padding = EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 6,
    );

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: padding,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(widget.icon, size: 12, color: iconColor),
          ),
        ),
      ),
    );
  }

  Color _contrastingColor(Color background) {
    return background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }
}

VoidCallback? _wrapAction(MenuAsyncAction? action) {
  if (action == null) {
    return null;
  }
  return () => unawaited(Future.sync(action));
}

String? _formatShortcut(MenuSerializableShortcut? shortcut) {
  if (shortcut == null) {
    return null;
  }
  if (shortcut is! SingleActivator) {
    return null;
  }
  final bool isMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  final List<String> parts = <String>[];

  if (shortcut.control) {
    parts.add(isMac ? '⌃' : 'Ctrl');
  }
  if (shortcut.meta) {
    parts.add(isMac ? '⌘' : 'Ctrl');
  }
  if (shortcut.alt) {
    parts.add(isMac ? '⌥' : 'Alt');
  }
  if (shortcut.shift) {
    parts.add(isMac ? '⇧' : 'Shift');
  }

  final String keyLabel = _describeLogicalKey(shortcut.trigger);
  if (keyLabel.isNotEmpty) {
    parts.add(isMac ? keyLabel : keyLabel.toUpperCase());
  }

  if (parts.isEmpty) {
    return null;
  }

  return isMac ? parts.join() : parts.join('+');
}

String _describeLogicalKey(LogicalKeyboardKey key) {
  final String label = key.keyLabel;
  if (label.isNotEmpty) {
    if (label.length == 1 &&
        label.codeUnitAt(0) >= 97 &&
        label.codeUnitAt(0) <= 122) {
      return label.toUpperCase();
    }
    return label;
  }
  return key.debugName ?? '';
}
