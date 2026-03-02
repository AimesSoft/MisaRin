import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_performance_pulse/flutter_performance_pulse.dart';
import 'package:misa_rin/l10n/app_localizations.dart';
import 'package:misa_rin/utils/io_shim.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'brushes/brush_library.dart';
import 'app/l10n/l10n.dart';
import 'app/preferences/app_preferences.dart';
import 'app/utils/tablet_input_bridge.dart';
import 'app/widgets/backend_canvas_surface.dart';
import 'backend/canvas_raster_backend.dart';
import 'canvas/canvas_backend.dart';
import 'canvas/canvas_backend_state.dart';
import 'src/rust/rust_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  TabletInputBridge.instance.ensureInitialized();

  await AppPreferences.load();
  await _configureSystemUi();
  try {
    await ensureRustInitialized();
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      if (CanvasBackendState.backend == CanvasBackend.rustWgpu) {
        // Initialize the Rust WGPU compositor and pre-warm shaders/pipelines.
        await CanvasRasterBackend.prewarmRustWgpuEngine();
        // Also pre-warm the Texture engine used by BackendCanvasSurface.
        await BackendCanvasSurface.prewarmTextureEngine();
        // Prewarm a default-size backend canvas in the background to avoid
        // blocking the first new canvas creation.
        unawaited(_prewarmDefaultBackendCanvas());
      }
      // Pre-warm Flutter's image decoding pipeline.
      await _prewarmImageDecoder();
    }
  } catch (error, stackTrace) {
    debugPrint('Rust WGPU init failed: $error\n$stackTrace');
    // We continue anyway, but canvas might fail later.
  }

  final Future<void> preloadFuture = _preloadCoreServices();

  if (kIsWeb) {
    runApp(const _MisarinWebLoadingApp());
  }

  await preloadFuture;

  await _initializeDesktopWindowIfNeeded();

  final bool showCustomMenu = kIsWeb ||
      (!kIsWeb &&
          (Platform.isWindows ||
              Platform.isLinux ||
              Platform.isMacOS ||
              Platform.isAndroid ||
              Platform.isIOS));
  final bool showCustomMenuItems = kIsWeb ||
      (!kIsWeb &&
          (Platform.isWindows ||
              Platform.isLinux ||
              Platform.isAndroid ||
              Platform.isIOS));
  final app = MisarinApp(
    showCustomMenu: showCustomMenu,
    showCustomMenuItems: showCustomMenuItems,
  );

  runApp(app);
}

Future<void> _configureSystemUi() async {
  if (kIsWeb || !Platform.isIOS) {
    return;
  }
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

Future<void> _preloadCoreServices() async {
  await AppPreferences.load();
  await BrushLibrary.load(prefs: AppPreferences.instance);
  if (!kIsWeb) {
    await _initializePerformancePulse();
  }
}

Future<void> _initializeDesktopWindowIfNeeded() async {
  final bool isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  if (!isDesktop) {
    return;
  }
  await windowManager.ensureInitialized();

  final bool isWindowsDesktop = !kIsWeb && Platform.isWindows;
  final Color windowBackgroundColor = isWindowsDesktop
      ? const Color(0xFF0F0F0F)
      : const Color(0x00000000);
  if (isWindowsDesktop) {
    await windowManager.setBackgroundColor(windowBackgroundColor);
  }

  final windowOptions = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: true,
    backgroundColor: windowBackgroundColor,
    skipTaskbar: false,
  );

  await windowManager.waitUntilReadyToShow(windowOptions);
  if (isWindowsDesktop) {
    await windowManager.setMaximizable(true);
  }
  await windowManager.show();
  await windowManager.maximize();
  if (isWindowsDesktop) {
    await _waitForMaximized();
  }
  await windowManager.focus();
}

Future<void> _waitForMaximized() async {
  const Duration step = Duration(milliseconds: 16);
  const Duration timeout = Duration(milliseconds: 400);
  final DateTime start = DateTime.now();
  while (DateTime.now().difference(start) < timeout) {
    if (await windowManager.isMaximized()) {
      return;
    }
    await Future<void>.delayed(step);
  }
}

Future<void> _initializePerformancePulse() async {
  try {
    bool enableBatteryMonitoring = !Platform.isWindows;
    if (Platform.isIOS) {
      try {
        final IosDeviceInfo info = await DeviceInfoPlugin().iosInfo;
        if (!info.isPhysicalDevice) {
          enableBatteryMonitoring = false;
        }
      } catch (_) {
        // Disable on simulator/unknown environments to avoid noisy errors.
        enableBatteryMonitoring = false;
      }
    }
    await PerformanceMonitor.instance.initialize(
      config: MonitorConfig(
        showMemory: true,
        showLogs: true,
        trackStartup: true,
        interceptNetwork: true,
        fpsWarningThreshold: 45,
        memoryWarningThreshold: 500 * 1024 * 1024,
        diskWarningThreshold: 85.0,
        enableNetworkMonitoring: true,
        enableBatteryMonitoring: enableBatteryMonitoring,
        enableDeviceInfo: true,
        enableDiskMonitoring: true,
        logLevel: LogLevel.info,
        exportLogs: false,
      ),
    );
  } catch (error, stackTrace) {
    debugPrint('Performance monitor init failed: $error\n$stackTrace');
  }
}

Future<void> _prewarmDefaultBackendCanvas() async {
  try {
    final AppPreferences prefs = AppPreferences.instance;
    final int width = prefs.newCanvasWidth;
    final int height = prefs.newCanvasHeight;
    if (width <= 0 || height <= 0) {
      return;
    }
    final String surfaceKey = 'prewarm_default_${width}x$height';
    await BackendCanvasSurface.prewarm(
      surfaceKey: surfaceKey,
      canvasSize: Size(width.toDouble(), height.toDouble()),
      layerCount: 2,
      backgroundColorArgb: prefs.newCanvasBackgroundColor.value,
    );
    await BackendCanvasSurface.cancelWarmup(surfaceKey: surfaceKey);
  } catch (_) {}
}

class _MisarinWebLoadingApp extends StatelessWidget {
  const _MisarinWebLoadingApp();

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      debugShowCheckedModeBanner: false,
      title: 'Misa Rin',
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        ...AppLocalizations.localizationsDelegates,
        FluentLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const _MisarinWebLoadingScreen(),
      theme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.white.toAccentColor(),
      ),
    );
  }
}

class _MisarinWebLoadingScreen extends StatelessWidget {
  const _MisarinWebLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final l10n = context.l10n;
    return Container(
      color: theme.micaBackgroundColor,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ProgressBar(),
              const SizedBox(height: 16),
              Text(
                l10n.webLoadingInitializingCanvas,
                style: theme.typography.subtitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Opacity(
                opacity: 0.75,
                child: Text(
                  l10n.webLoadingMayTakeTime,
                  style: theme.typography.body,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _prewarmImageDecoder() async {
  try {
    final Uint8List transparentPixel = Uint8List.fromList([0, 0, 0, 0]);
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      transparentPixel,
      1,
      1,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final ui.Image image = await completer.future;
    image.dispose();
  } catch (_) {
    // Ignore pre-warm errors
  }
}
