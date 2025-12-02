import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../dialogs/about_dialog.dart';
import '../dialogs/canvas_settings_dialog.dart';
import '../dialogs/settings_dialog.dart';
import '../project/project_document.dart';
import '../project/project_repository.dart';
import '../utils/clipboard_image_reader.dart';
import '../view/canvas_page.dart';
import '../widgets/app_notification.dart';

class AppMenuActions {
  const AppMenuActions._();

  static Future<void> createProject(BuildContext context) async {
    final NewProjectConfig? config = await showCanvasSettingsDialog(context);
    if (config == null || !context.mounted) {
      return;
    }
    try {
      final ProjectDocument document = await ProjectRepository.instance
          .createDocumentFromSettings(config.settings, name: config.name);
      if (!context.mounted) {
        return;
      }
      await _showProject(context, document);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showInfoBar(context, '创建项目失败：$error', severity: InfoBarSeverity.error);
    }
  }

  static Future<void> openProjectFromDisk(BuildContext context) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: '打开项目',
      type: FileType.custom,
      allowedExtensions: const ['rin', 'psd'],
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
            title: '正在打开项目…',
            message: '正在加载 ${file.name}',
            action: () async {
              final String extension = file.name.toLowerCase();
              if (extension.endsWith('.psd')) {
                if (path != null && !kIsWeb) {
                  return ProjectRepository.instance.importPsd(path);
                } else if (bytes != null) {
                  return ProjectRepository.instance.importPsdFromBytes(
                    bytes,
                    fileName: file.name,
                  );
                }
                throw Exception('无法读取 PSD 文件内容。');
              }
              if (path != null && !kIsWeb) {
                return ProjectRepository.instance.loadDocument(path);
              }
              if (bytes != null) {
                return ProjectRepository.instance.loadDocumentFromBytes(bytes);
              }
              throw Exception('无法读取项目文件内容。');
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
        '已打开项目：${document.name}',
        severity: InfoBarSeverity.success,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showInfoBar(context, '打开项目失败：$error', severity: InfoBarSeverity.error);
    }
  }

  static Future<void> openSettings(BuildContext context) async {
    await showSettingsDialog(context);
  }

  static Future<void> showAbout(BuildContext context) async {
    await showAboutMisarinDialog(context);
  }

  static Future<void> importImage(BuildContext context) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入图片',
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
        '已导入图片：${file.name}',
        severity: InfoBarSeverity.success,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showInfoBar(context, '导入图片失败：$error', severity: InfoBarSeverity.error);
    }
  }

  static Future<void> importImageFromClipboard(BuildContext context) async {
    final ClipboardImageData? payload = await ClipboardImageReader.readImage();
    if (payload == null) {
      if (!context.mounted) {
        return;
      }
      _showInfoBar(
        context,
        '剪贴板中没有找到可以导入的位图。',
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    try {
      final ProjectDocument document = await ProjectRepository.instance
          .createDocumentFromImageBytes(
            payload.bytes,
            name: payload.fileName ?? '剪贴板图像',
          );
      if (!context.mounted) {
        return;
      }
      await _showProject(context, document);
      if (!context.mounted) {
        return;
      }
      _showInfoBar(context, '已导入剪贴板图像', severity: InfoBarSeverity.success);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showInfoBar(
        context,
        '导入剪贴板图像失败：$error',
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
    final CanvasPageState? canvasState = context
        .findAncestorStateOfType<CanvasPageState>();
    try {
      if (canvasState != null) {
        await canvasState.openDocument(document);
      } else {
        if (!context.mounted) {
          return;
        }
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
      }
    } finally {
      hideLoadingOverlay();
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
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
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
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    final OverlayEntry entry = OverlayEntry(
      builder: (context) => const _WebProgressOverlay(
        title: '正在准备画布…',
        message: 'Web 端需要一些时间才能完成初始化，请稍候。',
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
