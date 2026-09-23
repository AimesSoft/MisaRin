import 'dart:async';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:misa_rin/mobile/responsive_dialog.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/scheduler.dart';
import 'package:misa_rin/l10n/app_localizations.dart';
import 'package:misa_rin/utils/io_shim.dart';
import 'package:window_manager/window_manager.dart';

import 'dialogs/misarin_dialog.dart';
import 'l10n/locale_controller.dart';
import 'l10n/l10n.dart';
import 'menu/custom_menu_bar.dart';
import 'menu/custom_menu_shell.dart';
import 'menu/macos_menu_shell.dart';
import 'preferences/app_preferences.dart';
import 'theme/theme_controller.dart';
import 'view/home_page.dart';
import 'widgets/performance_pulse_overlay.dart';
import 'workspace/canvas_workspace_controller.dart';
import 'view/canvas_perf_stress_page.dart';
import 'project/project_repository.dart';
import 'utils/file_manager.dart';
import '../mobile/mobile_home_page.dart';
import '../mobile/mobile_utils.dart';

const bool _kCanvasPerfStressMode = bool.fromEnvironment(
  'MISA_RIN_CANVAS_PERF_STRESS',
  defaultValue: false,
);

class MisarinApp extends StatefulWidget {
  const MisarinApp({
    super.key,
    this.showCustomMenu = false,
    this.showCustomMenuItems = true,
  });

  final bool showCustomMenu;
  final bool showCustomMenuItems;

  @override
  State<MisarinApp> createState() => _MisarinAppState();
}

class _MisarinAppState extends State<MisarinApp> with WindowListener {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  late ThemeMode _themeMode;
  late Locale? _locale;
  bool _windowListenerAttached = false;
  bool _closeRequestInProgress = false;

  @override
  void initState() {
    super.initState();
    _themeMode = AppPreferences.instance.themeMode;
    _locale = AppPreferences.instance.localeOverride;
    _initWindowCloseHandler();
    _scheduleStartupDiagnostics();
    _scheduleAutoSaveCleanupCheck();
  }

  void _handleThemeModeChanged(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }
    setState(() => _themeMode = mode);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.themeMode = mode;
    unawaited(AppPreferences.save());
  }

  void _handleLocaleChanged(Locale? locale) {
    if (_locale == locale) {
      return;
    }
    setState(() => _locale = locale);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.localeOverride = locale;
    unawaited(AppPreferences.save());
  }

  void _initWindowCloseHandler() {
    if (!_supportsDesktopWindowManagement) {
      return;
    }
    windowManager.addListener(this);
    _windowListenerAttached = true;
    unawaited(windowManager.setPreventClose(true));
  }

  void _scheduleStartupDiagnostics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_logDisplayDiagnostics('first-frame'));
      unawaited(
        _logDisplayDiagnostics(
          'post-settle',
          delay: const Duration(milliseconds: 500),
        ),
      );
      _startFrameTimingDiagnostics();
    });
  }

  void _scheduleAutoSaveCleanupCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkAutoSaveCleanup());
    });
  }

  Future<void> _checkAutoSaveCleanup() async {
    if (!mounted) {
      return;
    }
    final int thresholdMb =
        AppPreferences.instance.autoSaveCleanupThresholdMb;
    if (thresholdMb <= 0) {
      return;
    }
    final ProjectRepository repository = ProjectRepository.instance;
    final int totalBytes = await repository.autoSaveDirectorySizeBytes();
    final int thresholdBytes = thresholdMb * 1024 * 1024;
    if (!mounted || totalBytes <= thresholdBytes) {
      return;
    }
    final String folderPath = await repository.autoSaveDirectoryPath();
    if (!mounted) {
      return;
    }
    final String sizeText = _formatBytes(totalBytes);
    final String limitText = _formatBytes(thresholdBytes);
    await showResponsiveDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return MisarinDialog(
          title: Text(l10n.autoSaveCleanupDialogTitle),
          content: Text(
            l10n.autoSaveCleanupDialogMessage(sizeText, limitText),
          ),
          contentWidth: 420,
          maxWidth: 520,
          actions: [
            Button(
              onPressed: () => unawaited(
                revealDirectoryInFileManager(folderPath),
              ),
              child: Text(l10n.openFolder),
            ),
            Button(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () async {
                await repository.deleteAutoSavedProjects();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text(l10n.autoSaveCleanupDialogClean),
            ),
          ],
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const int kB = 1024;
    const int mB = kB * 1024;
    const int gB = mB * 1024;
    if (bytes >= gB) {
      return '${(bytes / gB).toStringAsFixed(2)} GB';
    }
    if (bytes >= mB) {
      return '${(bytes / mB).toStringAsFixed(1)} MB';
    }
    if (bytes >= kB) {
      return '${(bytes / kB).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  Future<void> _logDisplayDiagnostics(
    String label, {
    Duration delay = Duration.zero,
  }) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!mounted) {
      return;
    }
    final view = View.of(context);
    final Size logicalSize = Size(
      view.physicalSize.width / view.devicePixelRatio,
      view.physicalSize.height / view.devicePixelRatio,
    );
    final views = WidgetsBinding.instance.platformDispatcher.views;
    String refreshRateText = 'unknown';
    try {
      refreshRateText = '${view.display.refreshRate.toStringAsFixed(1)}Hz';
    } catch (error) {
      debugPrint('[startup][$label] refreshRate unavailable: $error');
    }
    debugPrint(
      '[startup][$label] viewCount=${views.length} refreshRate=$refreshRateText '
      'logical=${logicalSize.width.toStringAsFixed(1)}x'
      '${logicalSize.height.toStringAsFixed(1)} '
      'physical=${view.physicalSize.width.toStringAsFixed(1)}x'
      '${view.physicalSize.height.toStringAsFixed(1)} '
      'dpr=${view.devicePixelRatio.toStringAsFixed(2)}',
    );
    if (_supportsDesktopWindowManagement) {
      try {
        final bounds = await windowManager.getBounds();
        debugPrint(
          '[startup][$label] windowBounds='
          '${bounds.width.toStringAsFixed(1)}x'
          '${bounds.height.toStringAsFixed(1)} '
          '@(${bounds.left.toStringAsFixed(1)},'
          '${bounds.top.toStringAsFixed(1)})',
        );
      } catch (error) {
        debugPrint('[startup][$label] windowBounds failed: $error');
      }
    }
  }

  void _startFrameTimingDiagnostics() {
    if (!Platform.isWindows) {
      return;
    }
    const int sampleTarget = 120;
    final Stopwatch stopwatch = Stopwatch()..start();
    int? lastVsyncStart;
    final List<int> intervals = <int>[];
    final List<int> buildDurations = <int>[];
    final List<int> rasterDurations = <int>[];

    void handler(List<FrameTiming> timings) {
      for (final FrameTiming timing in timings) {
        final int vsyncStart =
            timing.timestampInMicroseconds(FramePhase.vsyncStart);
        if (lastVsyncStart != null) {
          intervals.add(vsyncStart - lastVsyncStart!);
        }
        lastVsyncStart = vsyncStart;
        buildDurations.add(timing.buildDuration.inMicroseconds);
        rasterDurations.add(timing.rasterDuration.inMicroseconds);
      }
      if (intervals.length < sampleTarget &&
          stopwatch.elapsedMilliseconds < 2500) {
        return;
      }
      SchedulerBinding.instance.removeTimingsCallback(handler);
      if (intervals.isEmpty) {
        debugPrint('[startup][timings] no frame intervals captured');
        return;
      }
      final double avgIntervalUs =
          intervals.reduce((a, b) => a + b) / intervals.length;
      final double avgFps = avgIntervalUs > 0
          ? 1000000.0 / avgIntervalUs
          : 0;
      final double avgBuildUs =
          buildDurations.reduce((a, b) => a + b) / buildDurations.length;
      final double avgRasterUs =
          rasterDurations.reduce((a, b) => a + b) / rasterDurations.length;
      debugPrint(
        '[startup][timings] samples=${intervals.length} '
        'avgInterval=${(avgIntervalUs / 1000).toStringAsFixed(2)}ms '
        'avgFps=${avgFps.toStringAsFixed(1)} '
        'build=${(avgBuildUs / 1000).toStringAsFixed(2)}ms '
        'raster=${(avgRasterUs / 1000).toStringAsFixed(2)}ms',
      );
    }

    SchedulerBinding.instance.addTimingsCallback(handler);
  }

  bool get _supportsDesktopWindowManagement =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void dispose() {
    if (_windowListenerAttached) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (!_windowListenerAttached) {
      return;
    }
    if (_closeRequestInProgress) {
      return;
    }
    unawaited(_handleWindowCloseRequest());
  }

  Future<void> _handleWindowCloseRequest() async {
    if (_closeRequestInProgress) {
      return;
    }
    _closeRequestInProgress = true;
    try {
      final bool isPreventClose = await windowManager.isPreventClose();
      if (!isPreventClose) {
        return;
      }
      final bool canClose = mounted ? await _confirmDiscardUnsavedProjects() : true;
      if (!canClose) {
        return;
      }
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } finally {
      _closeRequestInProgress = false;
    }
  }

  Future<bool> _confirmDiscardUnsavedProjects() async {
    final CanvasWorkspaceController workspace =
        CanvasWorkspaceController.instance;
    final List<CanvasWorkspaceEntry> entries = workspace.entries;
    final Iterable<CanvasWorkspaceEntry> dirtyEntries = entries.where(
      (entry) => entry.isDirty,
    );
    if (entries.isEmpty || dirtyEntries.isEmpty) {
      return true;
    }
    final BuildContext? context = _navigatorKey.currentContext;
    if (context == null) {
      return true;
    }
    final int unsavedCount = dirtyEntries.length;
    final l10n = context.l10n;
    final bool? discard = await showMisarinDialog<bool>(
      context: context,
      barrierDismissible: false,
      title: Text(l10n.closeAppTitle),
      content: Text(
        l10n.unsavedProjectsWarning(unsavedCount),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.discardAndExit),
        ),
      ],
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData lightFluentTheme = FluentThemeData(
      brightness: Brightness.light,
      accentColor: Colors.black.toAccentColor(),
    );
    final FluentThemeData darkFluentTheme = FluentThemeData(
      brightness: Brightness.dark,
      accentColor: Colors.white.toAccentColor(),
    );
    final material.ThemeData lightMaterialTheme =
        _materialThemeFromFluent(lightFluentTheme);
    final material.ThemeData darkMaterialTheme =
        _materialThemeFromFluent(darkFluentTheme);
    return ThemeController(
      themeMode: _themeMode,
      onThemeModeChanged: _handleThemeModeChanged,
      child: LocaleController(
        locale: _locale,
        onLocaleChanged: _handleLocaleChanged,
        child: material.MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Misa Rin',
          locale: _locale,
          localizationsDelegates: <LocalizationsDelegate<dynamic>>[
            ...AppLocalizations.localizationsDelegates,
            FluentLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          scrollBehavior: const FluentScrollBehavior(),
          theme: lightMaterialTheme,
          darkTheme: darkMaterialTheme,
          themeMode: _themeMode,
          builder: (context, child) {
            final FluentThemeData resolvedFluentTheme = _resolveFluentTheme(
              context,
              lightTheme: lightFluentTheme,
              darkTheme: darkFluentTheme,
            );
            return AnimatedFluentTheme(
              curve: resolvedFluentTheme.animationCurve,
              data: resolvedFluentTheme,
              child: Builder(
                builder: (context) {
                  Widget content = child ?? const SizedBox.shrink();
                  if (widget.showCustomMenu && child != null && !isMobileOrPhone(context)) {
                    content = CustomMenuShell(
                      navigatorKey: _navigatorKey,
                      showMenus: widget.showCustomMenuItems,
                      child: child,
                    );
                  }
                  Widget appBody = ValueListenableBuilder<bool>(
                    valueListenable: AppPreferences.fpsOverlayEnabledNotifier,
                    builder: (context, enabled, appChild) {
                      final Widget resolvedChild =
                          appChild ?? const SizedBox.shrink();
                      if (!enabled) {
                        return resolvedChild;
                      }
                      return Stack(
                        fit: StackFit.passthrough,
                        children: [
                          resolvedChild,
                          const PerformancePulseOverlay(),
                        ],
                      );
                    },
                    child: content,
                  );

                  // PlatformMenuBar needs AppLocalizations, so build it inside the app.
                  if (Platform.isMacOS) {
                    appBody = MacosMenuShell(child: appBody);
                  }

                  appBody = Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (event) =>
                        CustomMenuBarOverlay.reportPointerKind(event.kind),
                    onPointerHover: (event) =>
                        CustomMenuBarOverlay.reportPointerKind(event.kind),
                    onPointerMove: (event) =>
                        CustomMenuBarOverlay.reportPointerKind(event.kind),
                    child: appBody,
                  );

                  final FluentThemeData theme = FluentTheme.of(context);
                  final Color selectionColor =
                      Color.lerp(
                        theme.resources.controlFillColorInputActive,
                        theme.resources.textFillColorPrimary,
                        0.25,
                      ) ??
                      theme.resources.textFillColorPrimary.withOpacity(0.25);

                  return DefaultSelectionStyle(
                    cursorColor:
                        theme.accentColor.defaultBrushFor(theme.brightness),
                    selectionColor: selectionColor,
                    child: appBody,
                  );
                },
              ),
            );
          },
          home: !_kCanvasPerfStressMode
              ? Builder(
                  builder: (context) => isMobileOrPhone(context)
                      ? const MobileHomePage()
                      : const MisarinHomePage(),
                )
              : const CanvasPerfStressPage(),
        ),
      ),
    );
  }

  FluentThemeData _resolveFluentTheme(
    BuildContext context, {
    required FluentThemeData lightTheme,
    required FluentThemeData darkTheme,
  }) {
    switch (_themeMode) {
      case ThemeMode.light:
        return lightTheme;
      case ThemeMode.dark:
        return darkTheme;
      case ThemeMode.system:
        final Brightness platformBrightness =
            MediaQuery.platformBrightnessOf(context);
        return platformBrightness == Brightness.dark ? darkTheme : lightTheme;
    }
  }

  material.ThemeData _materialThemeFromFluent(FluentThemeData fluentTheme) {
    final AccentColor accent = fluentTheme.accentColor;
    final material.MaterialColor primarySwatch = material.MaterialColor(
      accent.value,
      <int, Color>{
        50: accent.lightest,
        100: accent.lighter,
        200: accent.light,
        300: accent.normal,
        400: accent.normal,
        500: accent.normal,
        600: accent.dark,
        700: accent.darker,
        800: accent.darkest,
        900: accent.darkest,
      },
    );
    return material.ThemeData(
      colorScheme: material.ColorScheme.fromSwatch(
        primarySwatch: primarySwatch,
        accentColor: accent.normal,
        errorColor: fluentTheme.resources.systemFillColorCritical,
        backgroundColor: fluentTheme.resources.controlFillColorDefault,
        cardColor: fluentTheme.resources.cardBackgroundFillColorDefault,
        brightness: fluentTheme.brightness,
      ),
      primaryColorDark: accent.darker,
      extensions: fluentTheme.extensions.values,
      brightness: fluentTheme.brightness,
      canvasColor: fluentTheme.cardColor,
      shadowColor: fluentTheme.shadowColor,
      disabledColor: fluentTheme.resources.controlFillColorDisabled,
      textSelectionTheme: material.TextSelectionThemeData(
        selectionColor: fluentTheme.selectionColor,
        cursorColor: fluentTheme.inactiveColor,
      ),
    );
  }
}
