import 'dart:async';

import 'package:flutter/widgets.dart';

import 'menu_action_dispatcher.dart';
import 'menu_definitions.dart';

class MacosMenuBuilder {
  const MacosMenuBuilder._();

  static List<PlatformMenu> build(MenuActionHandler handler) {
    final List<MenuDefinition> definitions = MenuDefinitionBuilder.build(
      handler,
    );
    return definitions
        .map(_buildPlatformMenu)
        .whereType<PlatformMenu>()
        .toList(growable: false);
  }

  static PlatformMenu? _buildPlatformMenu(MenuDefinition definition) {
    final List<PlatformMenuItem> menus = _convertEntries(definition.entries);
    if (menus.isEmpty) {
      return null;
    }
    return PlatformMenu(label: definition.label, menus: menus);
  }

  static List<PlatformMenuItem> _convertEntries(List<MenuEntry> entries) {
    final List<PlatformMenuItem> menuItems = <PlatformMenuItem>[];
    List<PlatformMenuItem> currentGroup = <PlatformMenuItem>[];

    void flushGroup() {
      if (currentGroup.isEmpty) {
        return;
      }
      menuItems.add(
        PlatformMenuItemGroup(
          members: List<PlatformMenuItem>.unmodifiable(currentGroup),
        ),
      );
      currentGroup = <PlatformMenuItem>[];
    }

    for (final MenuEntry entry in entries) {
      if (entry is MenuSeparatorEntry) {
        flushGroup();
        continue;
      }
      final PlatformMenuItem? item = _convertEntry(entry);
      if (item != null) {
        currentGroup.add(item);
      }
    }

    flushGroup();
    return menuItems;
  }

  static PlatformMenuItem? _convertEntry(MenuEntry entry) {
    if (entry is MenuActionEntry) {
      final VoidCallback? callback = _wrap(entry.action);
      if (callback == null) {
        return null;
      }
      final String label = entry.checked ? '* ${entry.label}' : entry.label;
      return PlatformMenuItem(
        label: label,
        onSelected: callback,
        shortcut: entry.shortcut,
      );
    }

    if (entry is MenuSubmenuEntry) {
      final List<PlatformMenuItem> submenus = _convertEntries(entry.entries);
      if (submenus.isEmpty) {
        return null;
      }
      return PlatformMenu(label: entry.label, menus: submenus);
    }

    if (entry is MenuProvidedEntry) {
      return PlatformProvidedMenuItem(type: _mapProvidedType(entry.type));
    }

    return null;
  }

  static PlatformProvidedMenuItemType _mapProvidedType(MenuProvidedType type) {
    switch (type) {
      case MenuProvidedType.servicesSubmenu:
        return PlatformProvidedMenuItemType.servicesSubmenu;
      case MenuProvidedType.hide:
        return PlatformProvidedMenuItemType.hide;
      case MenuProvidedType.hideOthers:
        return PlatformProvidedMenuItemType.hideOtherApplications;
      case MenuProvidedType.showAll:
        return PlatformProvidedMenuItemType.showAllApplications;
      case MenuProvidedType.quit:
        return PlatformProvidedMenuItemType.quit;
      case MenuProvidedType.minimizeWindow:
        return PlatformProvidedMenuItemType.minimizeWindow;
      case MenuProvidedType.zoomWindow:
        return PlatformProvidedMenuItemType.zoomWindow;
      case MenuProvidedType.arrangeWindowsInFront:
        return PlatformProvidedMenuItemType.arrangeWindowsInFront;
    }
  }

  static VoidCallback? _wrap(MenuAsyncAction? action) {
    if (action == null) {
      return null;
    }
    return () => unawaited(Future.sync(action));
  }
}
