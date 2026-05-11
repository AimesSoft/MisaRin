import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/platform_target.dart';
import '../widgets/window_drag_area.dart';
import 'menu_definitions.dart';
import 'menu_helpers.dart';
import 'touch_menu_overlay.dart';

class CustomMenuBarOverlay {
  static final ValueNotifier<Widget?> centerOverlay = ValueNotifier<Widget?>(
    null,
  );
  static final ValueNotifier<PointerDeviceKind?> lastPointerKind =
      ValueNotifier<PointerDeviceKind?>(null);

  static void reportPointerKind(PointerDeviceKind kind) {
    if (lastPointerKind.value == kind) {
      return;
    }
    lastPointerKind.value = kind;
  }
}

enum _MenuInteractionMode { mouse, touch }

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
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static bool _shouldShowWindowControls() {
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }
}

class _CustomMenuBarState extends State<CustomMenuBar> {
  FlyoutController? _openController;
  final ValueNotifier<bool> _menuOpenNotifier = ValueNotifier<bool>(false);
  OverlayEntry? _touchMenuEntry;
  MenuDefinition? _touchMenuDefinition;
  Rect _touchMenuAnchor = Rect.zero;
  double _menuBarHeight = 0;
  _MenuInteractionMode _interactionMode = _MenuInteractionMode.mouse;
  late final VoidCallback _pointerKindListener;

  @override
  void initState() {
    super.initState();
    _interactionMode = _defaultInteractionMode();
    final PointerDeviceKind? initialKind =
        CustomMenuBarOverlay.lastPointerKind.value;
    final _MenuInteractionMode? initialMode =
        initialKind == null ? null : _modeForPointerKind(initialKind);
    if (initialMode != null) {
      _interactionMode = initialMode;
    }
    _pointerKindListener = () {
      final PointerDeviceKind? kind =
          CustomMenuBarOverlay.lastPointerKind.value;
      if (kind == null) {
        return;
      }
      _handlePointerKind(kind);
    };
    CustomMenuBarOverlay.lastPointerKind.addListener(_pointerKindListener);
  }

  _MenuInteractionMode _defaultInteractionMode() {
    return defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.fuchsia
        ? _MenuInteractionMode.touch
        : _MenuInteractionMode.mouse;
  }

  bool get _useTouchMenu {
    return _interactionMode == _MenuInteractionMode.touch;
  }

  _MenuInteractionMode? _modeForPointerKind(PointerDeviceKind kind) {
    switch (kind) {
      case PointerDeviceKind.mouse:
      case PointerDeviceKind.trackpad:
        return _MenuInteractionMode.mouse;
      case PointerDeviceKind.touch:
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
        return _MenuInteractionMode.touch;
      case PointerDeviceKind.unknown:
        return null;
    }
  }

  void _handlePointerKind(PointerDeviceKind kind) {
    final _MenuInteractionMode? mode = _modeForPointerKind(kind);
    if (mode == null || mode == _interactionMode) {
      return;
    }
    setState(() => _interactionMode = mode);
    if (mode == _MenuInteractionMode.touch) {
      _closeHoverMenu();
    } else {
      _closeTouchMenu();
    }
  }

  void _closeHoverMenu() {
    final FlyoutController? controller = _openController;
    if (controller == null) {
      return;
    }
    if (controller.isOpen) {
      controller.forceClose();
    }
    _openController = null;
    if (_menuOpenNotifier.value) {
      _menuOpenNotifier.value = false;
    }
  }

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
    _touchMenuEntry?.remove();
    _menuOpenNotifier.dispose();
    CustomMenuBarOverlay.lastPointerKind.removeListener(_pointerKindListener);
    super.dispose();
  }

  bool _isTouchMenuOpenFor(MenuDefinition menu) {
    return _touchMenuEntry != null &&
        _touchMenuDefinition?.label == menu.label;
  }

  void _openTouchMenu(MenuDefinition menu, Rect anchorRect) {
    if (!_useTouchMenu) {
      return;
    }
    if (_openController?.isOpen ?? false) {
      _openController!.forceClose();
      _openController = null;
    }
    _touchMenuDefinition = menu;
    _touchMenuAnchor = anchorRect;
    if (_touchMenuEntry == null) {
      _touchMenuEntry = OverlayEntry(
        builder: (context) {
          final MenuDefinition? definition = _touchMenuDefinition;
          if (definition == null) {
            return const SizedBox.shrink();
          }
          return TouchMenuOverlay(
            anchorRect: _touchMenuAnchor,
            entries: definition.entries,
            menuBarHeight: _menuBarHeight,
            onDismiss: _closeTouchMenu,
          );
        },
      );
      Overlay.of(context, rootOverlay: true)?.insert(_touchMenuEntry!);
    } else {
      _touchMenuEntry!.markNeedsBuild();
    }
    if (!_menuOpenNotifier.value) {
      _menuOpenNotifier.value = true;
    }
  }

  void _closeTouchMenu() {
    _touchMenuEntry?.remove();
    _touchMenuEntry = null;
    _touchMenuDefinition = null;
    if (_menuOpenNotifier.value) {
      _menuOpenNotifier.value = false;
    }
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
    final bool isMac = isResolvedPlatformMacOS();
    final bool hasMenuButtons = visibleMenus.isNotEmpty;
    if (!hasMenuButtons && !canDrag && !showWindowControls) {
      return const SizedBox.shrink();
    }
    Widget buildDragArea(Widget? overlay) {
      if (!canDrag) {
        return const SizedBox.shrink();
      }
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: WindowDragArea(
            enableDoubleClickToMaximize: true,
            canDragAtPosition: (_) => true,
            child: overlay ?? const SizedBox.expand(),
          ),
        ),
      );
    }
    final Widget rowContent = ValueListenableBuilder<bool>(
      valueListenable: _menuOpenNotifier,
      builder: (context, anyMenuOpen, _) {
        return ValueListenableBuilder<Widget?>(
          valueListenable: CustomMenuBarOverlay.centerOverlay,
          builder: (context, overlay, _) {
            final List<Widget> children = <Widget>[
              for (int i = 0; i < visibleMenus.length; i++) ...[
                _MenuButton(
                  key: ValueKey(visibleMenus[i].label),
                  definition: visibleMenus[i],
                  navigatorKey: widget.navigatorKey,
                  onMenuWillOpen: _handleMenuWillOpen,
                  onMenuClosed: _handleMenuClosed,
                  isAnyMenuOpen: anyMenuOpen,
                  onTouchMenuRequested: _openTouchMenu,
                  onTouchMenuClose: _closeTouchMenu,
                  isTouchMenuOpen: _isTouchMenuOpenFor,
                  useTouchMenu: _useTouchMenu,
                ),
                if (i != visibleMenus.length - 1) const SizedBox(width: 4),
              ],
            ];

            Widget? dragOverlay;
            if (!isMac && overlay != null) {
              dragOverlay = IgnorePointer(
                ignoring: true,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: overlay,
                ),
              );
              if (children.isNotEmpty) {
                children.add(const SizedBox(width: 8));
              }
            }
            children.add(buildDragArea(dragOverlay));
            if (showWindowControls) {
              children.addAll(const <Widget>[
                SizedBox(width: 8),
                _WindowControlButtons(),
              ]);
            }

            final Widget buttons = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            );

            if (overlay == null || !isMac) {
              return buttons;
            }

            return Stack(
              alignment: Alignment.center,
              children: [
                buttons,
                IgnorePointer(
                  ignoring: true,
                  child: Align(alignment: Alignment.center, child: overlay),
                ),
              ],
            );
          },
        );
      },
    );

    final double topInset = MediaQuery.of(context).viewPadding.top;
    _menuBarHeight = topInset + 36;
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
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: SizedBox(height: 36, child: rowContent),
      ),
    );
  }
}

class _MenuButton extends StatefulWidget {
  const _MenuButton({
    super.key,
    required this.definition,
    this.navigatorKey,
    this.onMenuWillOpen,
    this.onMenuClosed,
    this.isAnyMenuOpen = false,
    this.onTouchMenuRequested,
    this.onTouchMenuClose,
    this.isTouchMenuOpen,
    required this.useTouchMenu,
  });

  final MenuDefinition definition;
  final GlobalKey<NavigatorState>? navigatorKey;
  final ValueChanged<FlyoutController>? onMenuWillOpen;
  final ValueChanged<FlyoutController>? onMenuClosed;
  final bool isAnyMenuOpen;
  final void Function(MenuDefinition definition, Rect anchorRect)?
      onTouchMenuRequested;
  final VoidCallback? onTouchMenuClose;
  final bool Function(MenuDefinition definition)? isTouchMenuOpen;
  final bool useTouchMenu;

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

  Rect? _resolveButtonRect() {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final Offset global = renderObject.localToGlobal(Offset.zero);
    return global & renderObject.size;
  }

  void _notePointerKind(PointerDeviceKind kind) {
    CustomMenuBarOverlay.reportPointerKind(kind);
  }

  void _openMenu({bool toggleIfOpen = true}) {
    if (widget.useTouchMenu) {
      return;
    }
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
    _notePointerKind(event.kind);
    setState(() => _hovered = true);
    if (!widget.useTouchMenu &&
        widget.isAnyMenuOpen &&
        !_flyoutController.isOpen) {
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
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => _notePointerKind(event.kind),
        onPointerHover: (event) => _notePointerKind(event.kind),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: _handlePointerEnter,
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.useTouchMenu
                ? null
                : () {
                    if (kDebugMode) {
                      debugPrint(
                        '[menu_bar] tap label=${widget.definition.label}',
                      );
                    }
                    _openMenu(toggleIfOpen: true);
                  },
            onTapDown: (details) {
              if (kDebugMode) {
                debugPrint(
                  '[menu_bar] tap_down label=${widget.definition.label} local=${details.localPosition} global=${details.globalPosition}',
                );
              }
            },
            onTapUp: (details) {
              if (kDebugMode) {
                debugPrint(
                  '[menu_bar] tap_up label=${widget.definition.label} local=${details.localPosition} global=${details.globalPosition}',
                );
              }
              if (widget.useTouchMenu) {
                final Rect? rect = _resolveButtonRect();
                if (rect == null) {
                  return;
                }
                final bool isOpen =
                    widget.isTouchMenuOpen?.call(widget.definition) ?? false;
                if (isOpen) {
                  widget.onTouchMenuClose?.call();
                } else {
                  widget.onTouchMenuRequested?.call(widget.definition, rect);
                }
              }
            },
            onTapCancel: () {
              if (kDebugMode) {
                debugPrint(
                  '[menu_bar] tap_cancel label=${widget.definition.label}',
                );
              }
            },
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
      final bool resolvedEnabled = entry.isEnabled;
      final VoidCallback? action = wrapMenuAction(entry.action);
      if (action == null && resolvedEnabled) {
        return null;
      }
      final bool enabled = resolvedEnabled && action != null;
      final VoidCallback? onPressed = enabled ? action : null;
      final String? shortcutLabel = formatMenuShortcut(entry.shortcut);
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
        showBehavior: widget.useTouchMenu
            ? SubItemShowAction.press
            : SubItemShowAction.hover,
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
