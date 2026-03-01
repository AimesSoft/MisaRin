import 'dart:async';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show StatefulElement, State, StatefulWidget;
import 'package:path/path.dart' as p;
import 'package:misa_rin/canvas/canvas_engine_bridge.dart';

import '../../brushes/brush_library.dart';
import '../../canvas/canvas_settings.dart';
import '../dialogs/canvas_settings_dialog.dart';
import '../dialogs/settings_dialog.dart';
import '../l10n/l10n.dart';
import '../preferences/app_preferences.dart';
import '../project/project_document.dart';
import '../project/project_repository.dart';
import '../utils/clipboard_image_reader.dart';
import '../view/canvas_page.dart';
import '../widgets/app_notification.dart';
import '../widgets/backend_canvas_surface.dart';

class AppMenuActions {
  const AppMenuActions._();

  static Future<void> createProject(BuildContext context) async {
    final AppPreferences prefs = AppPreferences.instance;
    final CanvasSettings initialSettings = CanvasSettings(
      width: prefs.newCanvasWidth.toDouble(),
      height: prefs.newCanvasHeight.toDouble(),
      backgroundColor: prefs.newCanvasBackgroundColor,
    );
    final NewProjectConfig? config = await showCanvasSettingsDialog(
      context,
      initialSettings: initialSettings,
    );
    if (config == null || !context.mounted) {
      return;
    }

    final sw = Stopwatch()..start();
    debugPrint('[Performance] Starting project creation...');

    try {
      _applyWorkspacePreset(config.workspacePreset);
      debugPrint('[Performance] Workspace preset applied: ${sw.elapsedMilliseconds}ms');

      final repoSw = Stopwatch()..start();
      ProjectDocument document = await ProjectRepository.instance
          .createDocumentFromSettings(config.settings, name: config.name);
      debugPrint('[Performance] ProjectRepository.createDocumentFromSettings took: ${repoSw.elapsedMilliseconds}ms');

      if (!kIsWeb && CanvasBackendFacade.instance.isSupported) {
        final prewarmSw = Stopwatch()..start();
        unawaited(
          BackendCanvasSurface.prewarm(
            surfaceKey: document.id,
            canvasSize: config.settings.size,
            layerCount: document.layers.length,
            backgroundColorArgb: config.settings.backgroundColor.value,
          ).then((_) {
            debugPrint('[Performance] Async BackendCanvasSurface.prewarm completed in: ${prewarmSw.elapsedMilliseconds}ms');
          }).catchError((e) {
            debugPrint('[Performance] Async BackendCanvasSurface.prewarm failed: $e');
          }),
        );
      }
      document = _applyNewProjectPresetDefaults(document, config);
      if (!context.mounted) {
        return;
      }
      
      final showSw = Stopwatch()..start();
      await _showProject(context, document);
      debugPrint('[Performance] _showProject total took: ${showSw.elapsedMilliseconds}ms');
      
      debugPrint('[Performance] createProject total took: ${sw.elapsedMilliseconds}ms');
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showInfoBar(
        context,
        context.l10n.createProjectFailed(error),
        severity: InfoBarSeverity.error,
      );
    }
  }

  static ProjectDocument _applyNewProjectPresetDefaults(
    ProjectDocument document,
    NewProjectConfig config,
  ) {
    if (!_shouldHideSolidBackgroundLayer(config)) {
      return document;
    }
    if (document.layers.isEmpty) {
      return document;
    }
    final firstLayer = document.layers.first;
    if (!firstLayer.visible || firstLayer.fillColor == null) {
      return document;
    }
    final layers = List.of(document.layers);
    layers[0] = firstLayer.copyWith(visible: false);
    return document.copyWith(layers: layers);
  }

  static bool _shouldHideSolidBackgroundLayer(NewProjectConfig config) {
    if (config.workspacePreset == WorkspacePreset.pixel) {
      return true;
    }
    final int width = config.settings.width.round();
    final int height = config.settings.height.round();
    return width == height && (width == 64 || width == 32 || width == 16);
  }

  static void _applyWorkspacePreset(WorkspacePreset preset) {
    if (preset == WorkspacePreset.none) {
      return;
    }
    final AppPreferences prefs = AppPreferences.instance;
    bool changed = false;

    void setPenAntialias(int value) {
      if (prefs.penAntialiasLevel != value) {
        prefs.penAntialiasLevel = value;
        changed = true;
      }
    }

    void setBucketAntialias(int value) {
      if (prefs.bucketAntialiasLevel != value) {
        prefs.bucketAntialiasLevel = value;
        changed = true;
      }
    }

    void setBucketSwallowColorLine(bool value) {
      if (prefs.bucketSwallowColorLine != value) {
        prefs.bucketSwallowColorLine = value;
        changed = true;
      }
    }

    void setPixelGridVisible(bool value) {
      final bool current = prefs.pixelGridVisible;
      prefs.updatePixelGridVisible(value);
      if (current != value) {
        changed = true;
      }
    }

    void setStrokeStabilizerStrength(double value) {
      if (prefs.strokeStabilizerStrength != value) {
        prefs.strokeStabilizerStrength = value;
        changed = true;
      }
    }

    void setBrushPreset(String id) {
      try {
        BrushLibrary.instance.selectPreset(id);
      } catch (_) {}
    }

    switch (preset) {
      case WorkspacePreset.illustration:
        setBrushPreset('pencil');
        setPenAntialias(1);
        break;
      case WorkspacePreset.celShading:
        setBrushPreset('cel');
        setPenAntialias(0);
        setBucketAntialias(0);
        setBucketSwallowColorLine(true);
        break;
      case WorkspacePreset.pixel:
        setBrushPreset('pixel');
        setPenAntialias(0);
        setBucketAntialias(0);
        setStrokeStabilizerStrength(0.0);
        setPixelGridVisible(true);
        break;
      default:
        break;
    }

    if (changed) {
      unawaited(AppPreferences.save());
    }
  }

  static Future<void> openProjectFromDisk(BuildContext context) async {
    final l10n = context.l10n;
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: l10n.openProjectDialogTitle,
      type: FileType.custom,
      allowedExtensions: const [
        'rin',
        'psd',
        'sai2',
        'png',
        'jpg',
        'jpeg',
        'webp',
        'avif',
      ],
      withData: kIsWeb,
    );
    final PlatformFile? file = result?.files.singleOrNull;
    if (file == null || !context.mounted) {
      return;
    }
    final String? path = kIsWeb ? null : file.path;
    final Uint8List? bytes = file.bytes;
    if (path == null && bytes == null) {
      return;
    }
    try {
      final ProjectDocument document =
          await _runWithWebProgress<ProjectDocument>(
            context,
            title: l10n.openingProjectTitle,
            message: l10n.openingProjectMessage(file.name),
            action: () async {
              final String extension = p.extension(file.name).toLowerCase();
              if (extension == '.psd') {
                if (path != null && !kIsWeb) {
                  return ProjectRepository.instance.importPsd(path);
                } else if (bytes != null) {
                  return ProjectRepository.instance.importPsdFromBytes(
                    bytes,
                    fileName: file.name,
                  );
                }
                throw Exception(l10n.cannotReadPsdContent);
              }
              if (extension == '.sai2') {
                if (path != null && !kIsWeb) {
                  return ProjectRepository.instance.importSai2(path);
                } else if (bytes != null) {
                  return ProjectRepository.instance.importSai2FromBytes(
                    bytes,
                    fileName: file.name,
                  );
                }
                throw Exception(l10n.cannotReadSai2Content);
              }
              if (extension == '.png' ||
                  extension == '.jpg' ||
                  extension == '.jpeg' ||
                  extension == '.webp' ||
                  extension == '.avif') {
                final String name = p.basenameWithoutExtension(file.name);
                if (path != null && !kIsWeb) {
                  return ProjectRepository.instance.createDocumentFromImage(
                    path,
                    name: name,
                  );
                }
                if (bytes != null) {
                  return ProjectRepository.instance.createDocumentFromImageBytes(
                    bytes,
                    name: name,
                  );
                }
                throw Exception(l10n.cannotReadProjectFileContent);
              }
              if (path != null && !kIsWeb) {
                return ProjectRepository.instance.loadDocument(path);
              }
              if (bytes != null) {
                return ProjectRepository.instance.loadDocumentFromBytes(bytes);
              }
              throw Exception(l10n.cannotReadProjectFileContent);
            },
          );
      if (!context.mounted) {
        return;
      }
      await _showProject(context, document);
      if (!context.mounted) {
        return;
      }
      _showInfoBar(
        context,
        l10n.openedProjectInfo(document.name),
        severity: InfoBarSeverity.success,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showInfoBar(
        context,
        l10n.openProjectFailed(error),
        severity: InfoBarSeverity.error,
      );
    }
  }

  static Future<void> openSettings(BuildContext context) async {
    await showSettingsDialog(context);
  }

  static Future<void> showAbout(BuildContext context) async {
    await showSettingsDialog(context, openAboutTab: true);
  }

  static Future<void> importImage(BuildContext context) async {
    final l10n = context.l10n;
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: l10n.importImageDialogTitle,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'bmp', 'gif'],
    );
    final PlatformFile? file = result?.files.singleOrNull;
    final String? path = file?.path;
    if (path == null || !context.mounted) {
      return;
    }
    try {
      final ProjectDocument document = await ProjectRepository.instance
          .createDocumentFromImage(path, name: file!.name);
      if (!context.mounted) {
        return;
      }
      await _showProject(context, document);
      if (!context.mounted) {
        return;
      }
      _showInfoBar(
        context,
        l10n.importedImageInfo(file.name),
        severity: InfoBarSeverity.success,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showInfoBar(
        context,
        l10n.importImageFailed(error),
        severity: InfoBarSeverity.error,
      );
    }
  }

  static Future<void> importImageFromClipboard(BuildContext context) async {
    final l10n = context.l10n;
    final ClipboardImageData? payload = await ClipboardImageReader.readImage();
    if (payload == null) {
      if (!context.mounted) {
        return;
      }
      _showInfoBar(
        context,
        l10n.clipboardNoBitmapFound,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    try {
      final ProjectDocument document = await ProjectRepository.instance
          .createDocumentFromImageBytes(
            payload.bytes,
            name: payload.fileName ?? l10n.clipboardImageDefaultName,
          );
      if (!context.mounted) {
        return;
      }
      await _showProject(context, document);
      if (!context.mounted) {
        return;
      }
      _showInfoBar(
        context,
        l10n.importedClipboardImageInfo,
        severity: InfoBarSeverity.success,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showInfoBar(
        context,
        l10n.importClipboardImageFailed(error),
        severity: InfoBarSeverity.error,
      );
    }
  }

  static Future<void> openProject(
    BuildContext context,
    ProjectDocument document,
  ) async {
    await _showProject(context, document);
  }

  static Future<void> _showProject(
    BuildContext context,
    ProjectDocument document,
  ) async {
    final sw = Stopwatch()..start();
    debugPrint('[Performance] _showProject: document.id=${document.id}');

    OverlayEntry? loadingOverlay;
    void hideLoadingOverlay() {
      if (loadingOverlay == null) {
        return;
      }
      loadingOverlay!.remove();
      loadingOverlay = null;
    }

    if (kIsWeb) {
      loadingOverlay = _showWebCanvasLoadingOverlay(context);
    }
    final CanvasPageState? canvasState = () {
      final CanvasPageState? ancestor =
          context.findAncestorStateOfType<CanvasPageState>();
      if (ancestor != null) {
        return ancestor;
      }
      if (context is StatefulElement) {
        final State<StatefulWidget> state = context.state;
        if (state is CanvasPageState) {
          return state;
        }
      }
      return null;
    }();
    if (!kIsWeb && CanvasBackendFacade.instance.isSupported) {
      // FIRE AND FORGET - NEVER AWAIT PREWARM ON UI THREAD
      unawaited(BackendCanvasSurface.prewarm(
        surfaceKey: document.id,
        canvasSize: document.settings.size,
        layerCount: document.layers.length,
        backgroundColorArgb: document.settings.backgroundColor.value,
      ).catchError((_) {}));
    }
    try {
      if (canvasState != null) {
        final openSw = Stopwatch()..start();
        await canvasState.openDocument(document);
        debugPrint('[Performance] _showProject: canvasState.openDocument took: ${openSw.elapsedMilliseconds}ms');
      } else {
        if (!context.mounted) {
          return;
        }
        final pushSw = Stopwatch()..start();
        await Navigator.of(context).push(
          PageRouteBuilder<void>(
            pageBuilder: (_, __, ___) => CanvasPage(
              document: document,
              onInitialBoardReady: kIsWeb ? hideLoadingOverlay : null,
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        debugPrint('[Performance] _showProject: Navigator.push/CanvasPage took: ${pushSw.elapsedMilliseconds}ms');
      }
    } finally {
      hideLoadingOverlay();
      debugPrint('[Performance] _showProject total: ${sw.elapsedMilliseconds}ms');
    }
  }

  static void _showInfoBar(
    BuildContext context,
    String message, {
    InfoBarSeverity severity = InfoBarSeverity.info,
  }) {
    AppNotifications.show(context, message: message, severity: severity);
  }

  static Future<T> _runWithWebProgress<T>(
    BuildContext context, {
    required Future<T> Function() action,
    required String title,
    String? message,
  }) async {
    if (!context.mounted || !kIsWeb) {
      return action();
    }
    final OverlayState? overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) {
      return action();
    }
    final OverlayEntry entry = OverlayEntry(
      builder: (context) => AbsorbPointer(
        absorbing: true,
        child: _WebProgressOverlay(title: title, message: message),
      ),
    );
    overlay.insert(entry);
    // Give Flutter a frame to render the overlay before running heavy tasks.
    await Future<void>.delayed(Duration.zero);
    try {
      return await action();
    } finally {
      entry.remove();
    }
  }

  static OverlayEntry? _showWebCanvasLoadingOverlay(BuildContext context) {
    if (!context.mounted) {
      return null;
    }
    final OverlayState? overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) {
      return null;
    }
    final l10n = context.l10n;
    final OverlayEntry entry = OverlayEntry(
      builder: (context) => _WebProgressOverlay(
        title: l10n.webPreparingCanvasTitle,
        message: l10n.webPreparingCanvasMessage,
      ),
    );
    overlay.insert(entry);
    return entry;
  }
}

class _WebProgressOverlay extends StatelessWidget {
  const _WebProgressOverlay({required this.title, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color overlayColor = theme.micaBackgroundColor.withOpacity(0.65);
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: overlayColor)),
        Positioned.fill(
          child: Center(
            child: Container(
              width: 360,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 32,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.typography.subtitle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const ProgressBar(),
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Opacity(
                      opacity: 0.8,
                      child: Text(
                        message!,
                        style: theme.typography.body,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
