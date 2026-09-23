import 'dart:async';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart'
    show StatefulElement, State, StatefulWidget;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:misa_rin/canvas/canvas_engine_bridge.dart';

import '../../brushes/brush_library.dart';
import '../../canvas/canvas_settings.dart';
import '../../mobile/mobile_bottom_sheet.dart';
import '../../mobile/mobile_utils.dart';
import '../dialogs/canvas_settings_dialog.dart';
import '../dialogs/settings_dialog.dart';
import '../dialogs/svg_rasterize_size_dialog.dart';
import '../l10n/l10n.dart';
import '../preferences/app_preferences.dart';
import '../project/project_document.dart';
import '../project/project_repository.dart';
import '../utils/clipboard_image_reader.dart';
import '../utils/svg_rasterizer.dart';
import '../view/canvas_page.dart';
import '../widgets/app_notification.dart';
import '../widgets/backend_canvas_surface.dart';

enum _ImageSourceChoice { photos, files }

class AppMenuActions {
  const AppMenuActions._();
  static final ImagePicker _imagePicker = ImagePicker();

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
    try {
      _applyWorkspacePreset(config.workspacePreset);
      ProjectDocument document = await ProjectRepository.instance
          .createDocumentFromSettings(config.settings, name: config.name);
      if (CanvasBackendFacade.instance.isSupported) {
        unawaited(
          BackendCanvasSurface.prewarm(
            surfaceKey: document.id,
            canvasSize: config.settings.size,
            layerCount: document.layers.length,
            backgroundColorArgb: config.settings.backgroundColor.value,
          ).catchError((_) {}),
        );
      }
      document = _applyNewProjectPresetDefaults(document, config);
      if (!context.mounted) {
        return;
      }
      await _showProject(context, document);
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

  static bool _shouldPromptImageSource() {
    final TargetPlatform platform = defaultTargetPlatform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.android;
  }

  static Future<_ImageSourceChoice?> _showImageSourceDialog(
    BuildContext context,
  ) {
    final l10n = context.l10n;
    if (isMobileOrPhone(context)) {
      return showMobileBottomSheet<_ImageSourceChoice?>(
        context: context,
        heightFactor: 0.45,
        builder: (BuildContext context) {
          final theme = FluentTheme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.imageSourceTitle,
                      style: theme.typography.subtitle?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(l10n.imageSourceDesc, style: theme.typography.caption),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    ListTile(
                      title: Text(l10n.exportDestinationPhotos),
                      onPressed: () =>
                          Navigator.of(context).pop(_ImageSourceChoice.photos),
                    ),
                    ListTile(
                      title: Text(l10n.exportDestinationFiles),
                      onPressed: () =>
                          Navigator.of(context).pop(_ImageSourceChoice.files),
                    ),
                    const Divider(),
                    ListTile(
                      title: Text(l10n.cancel),
                      onPressed: () => Navigator.of(context).pop(null),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    }
    return showDialog<_ImageSourceChoice?>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return ContentDialog(
          title: Text(l10n.imageSourceTitle),
          content: Text(l10n.imageSourceDesc),
          actions: [
            Button(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(l10n.cancel),
            ),
            Button(
              onPressed: () =>
                  Navigator.of(context).pop(_ImageSourceChoice.files),
              child: Text(l10n.exportDestinationFiles),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_ImageSourceChoice.photos),
              child: Text(l10n.exportDestinationPhotos),
            ),
          ],
        );
      },
    );
  }

  static Future<({String path, String name})?> _pickImageFromGallery(
    BuildContext context,
  ) async {
    final XFile? file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );
    if (file == null || !context.mounted) {
      return null;
    }
    final String name = file.name.isNotEmpty
        ? file.name
        : p.basename(file.path);
    return (path: file.path, name: name);
  }

  static Future<void> openProjectFromDisk(BuildContext context) async {
    final l10n = context.l10n;
    _ImageSourceChoice source = _ImageSourceChoice.files;
    if (_shouldPromptImageSource()) {
      final _ImageSourceChoice? selected = await _showImageSourceDialog(
        context,
      );
      if (selected == null || !context.mounted) {
        return;
      }
      source = selected;
    }

    if (source == _ImageSourceChoice.photos) {
      final ({String path, String name})? picked = await _pickImageFromGallery(
        context,
      );
      if (picked == null || !context.mounted) {
        return;
      }
      int? svgRasterSizePx;
      if (hasSvgExtension(p.extension(picked.name))) {
        svgRasterSizePx = await showSvgRasterizeSizeDialog(
          context,
          fileName: picked.name,
        );
        if (svgRasterSizePx == null || !context.mounted) {
          return;
        }
      }
      try {
        final ProjectDocument document =
            await _runProjectOpenAction<ProjectDocument>(
              action: () async {
                final String name = p.basenameWithoutExtension(picked.name);
                return ProjectRepository.instance.createDocumentFromImage(
                  picked.path,
                  name: name,
                  svgRasterSizePx: svgRasterSizePx,
                );
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
      return;
    }

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
        'svg',
        'avif',
      ],
    );
    final PlatformFile? file = result?.files.singleOrNull;
    if (file == null || !context.mounted) {
      return;
    }
    final String? path = file.path;
    final Uint8List? bytes = file.bytes;
    if (path == null && bytes == null) {
      return;
    }
    final String extension = p.extension(file.name).toLowerCase();
    int? svgRasterSizePx;
    if (hasSvgExtension(extension)) {
      svgRasterSizePx = await showSvgRasterizeSizeDialog(
        context,
        fileName: file.name,
      );
      if (svgRasterSizePx == null || !context.mounted) {
        return;
      }
    }
    try {
      final ProjectDocument document =
          await _runProjectOpenAction<ProjectDocument>(
            action: () async {
              if (extension == '.psd') {
                if (path != null) {
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
                if (path != null) {
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
                  extension == '.svg' ||
                  extension == '.avif') {
                final String name = p.basenameWithoutExtension(file.name);
                if (path != null) {
                  return ProjectRepository.instance.createDocumentFromImage(
                    path,
                    name: name,
                    svgRasterSizePx: svgRasterSizePx,
                  );
                }
                if (bytes != null) {
                  return ProjectRepository.instance
                      .createDocumentFromImageBytes(
                        bytes,
                        name: name,
                        svgRasterSizePx: svgRasterSizePx,
                      );
                }
                throw Exception(l10n.cannotReadProjectFileContent);
              }
              if (path != null) {
                return ProjectRepository.instance.loadDocument(path);
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
    _ImageSourceChoice source = _ImageSourceChoice.files;
    if (_shouldPromptImageSource()) {
      final _ImageSourceChoice? selected = await _showImageSourceDialog(
        context,
      );
      if (selected == null || !context.mounted) {
        return;
      }
      source = selected;
    }

    if (source == _ImageSourceChoice.photos) {
      final ({String path, String name})? picked = await _pickImageFromGallery(
        context,
      );
      if (picked == null || !context.mounted) {
        return;
      }
      int? svgRasterSizePx;
      if (hasSvgExtension(p.extension(picked.name))) {
        svgRasterSizePx = await showSvgRasterizeSizeDialog(
          context,
          fileName: picked.name,
        );
        if (svgRasterSizePx == null || !context.mounted) {
          return;
        }
      }
      try {
        final ProjectDocument document = await ProjectRepository.instance
            .createDocumentFromImage(
              picked.path,
              name: picked.name,
              svgRasterSizePx: svgRasterSizePx,
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
          l10n.importedImageInfo(picked.name),
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
      return;
    }

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: l10n.importImageDialogTitle,
      type: FileType.custom,
      allowedExtensions: const [
        'png',
        'jpg',
        'jpeg',
        'bmp',
        'gif',
        'webp',
        'svg',
      ],
    );
    final PlatformFile? file = result?.files.singleOrNull;
    if (file == null || !context.mounted) {
      return;
    }
    final String extension = p.extension(file.name).toLowerCase();
    int? svgRasterSizePx;
    if (hasSvgExtension(extension)) {
      svgRasterSizePx = await showSvgRasterizeSizeDialog(
        context,
        fileName: file.name,
      );
      if (svgRasterSizePx == null || !context.mounted) {
        return;
      }
    }
    final String? path = file.path;
    final Uint8List? bytes = file.bytes;
    if (path == null && bytes == null) {
      return;
    }
    try {
      final ProjectDocument document = path != null
          ? await ProjectRepository.instance.createDocumentFromImage(
              path,
              name: file.name,
              svgRasterSizePx: svgRasterSizePx,
            )
          : await ProjectRepository.instance.createDocumentFromImageBytes(
              bytes!,
              name: file.name,
              svgRasterSizePx: svgRasterSizePx,
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
            hideBackgroundLayer: true,
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
    final CanvasPageState? canvasState = () {
      final CanvasPageState? ancestor = context
          .findAncestorStateOfType<CanvasPageState>();
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
    if (CanvasBackendFacade.instance.isSupported) {
      try {
        await BackendCanvasSurface.prewarm(
          surfaceKey: document.id,
          canvasSize: document.settings.size,
          layerCount: document.layers.length,
          backgroundColorArgb: document.settings.backgroundColor.value,
        );
      } catch (_) {}
    }
    if (canvasState != null) {
      await canvasState.openDocument(document);
    } else {
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => CanvasPage(document: document),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    }
  }

  static void _showInfoBar(
    BuildContext context,
    String message, {
    InfoBarSeverity severity = InfoBarSeverity.info,
  }) {
    AppNotifications.show(context, message: message, severity: severity);
  }

  static Future<T> _runProjectOpenAction<T>({
    required Future<T> Function() action,
  }) async {
    return action();
  }
}
