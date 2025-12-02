import 'package:flutter/material.dart';

typedef ThemeModeChanged = void Function(ThemeMode mode);

class ThemeController extends InheritedWidget {
  const ThemeController({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required super.child,
  });

  final ThemeMode themeMode;
  final ThemeModeChanged onThemeModeChanged;

  static ThemeController of(BuildContext context) {
    final ThemeController? result = context
        .dependOnInheritedWidgetOfExactType<ThemeController>();
    assert(result != null, 'ThemeController not found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(ThemeController oldWidget) {
    return themeMode != oldWidget.themeMode;
  }
}
