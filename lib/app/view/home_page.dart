import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:misa_rin/utils/io_shim.dart';
import 'package:path/path.dart' as p;

import '../dialogs/svg_rasterize_size_dialog.dart';
import '../dialogs/project_manager_dialog.dart';
import '../dialogs/recent_projects_dialog.dart';
import '../l10n/l10n.dart';
import '../project/project_document.dart';
import '../project/project_repository.dart';
import '../menu/menu_action_dispatcher.dart';
import '../menu/menu_app_actions.dart';
import '../utils/svg_rasterizer.dart';
import '../widgets/app_notification.dart';
import '../workspace/canvas_workspace_controller.dart';

class MisarinHomePage extends StatefulWidget {
  const MisarinHomePage({super.key});

  @override
  State<MisarinHomePage> createState() => _MisarinHomePageState();
}

class _MisarinHomePageState extends State<MisarinHomePage> {
  static const Set<String> _kDropImageExtensions = <String>{
    'png',
    'jpg',
    'jpeg',
    'bmp',
    'gif',
    'webp',
    'svg',
  };
  static const Duration _kDropDuplicateDebounce = Duration(seconds: 1);

  late final ScrollController _sidebarScrollController;
  final ProjectRepository _repository = ProjectRepository.instance;
  bool _isHandlingHomeDrop = false;
  String? _lastHomeDropSignature;
  DateTime? _lastHomeDropAt;

  bool get _supportsFileDrops =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _sidebarScrollController = ScrollController();
  }

  @override
  void dispose() {
    _sidebarScrollController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateProject(BuildContext context) async {
    await AppMenuActions.createProject(context);
  }

  Future<void> _handleOpenProject(BuildContext context) async {
    await AppMenuActions.openProjectFromDisk(context);
  }

  Future<void> _handleOpenRecent(BuildContext context) async {
    final ProjectSummary? summary = await showRecentProjectsDialog(context);
    if (summary == null || !context.mounted) {
      return;
    }
    try {
      final ProjectDocument document = await ProjectRepository.instance
          .loadDocument(summary.path);
      if (!context.mounted) {
        return;
      }
      await AppMenuActions.openProject(context, document);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showInfoBar(
        context,
        context.l10n.openProjectFailed(error),
        severity: InfoBarSeverity.error,
      );
    }
  }

  Future<void> _handleOpenSettings(BuildContext context) async {
    await AppMenuActions.openSettings(context);
  }

  Future<void> _handleManageProjects(BuildContext context) async {
    await showProjectManagerDialog(context);
  }

  void _showInfoBar(
    BuildContext context,
    String message, {
    InfoBarSeverity severity = InfoBarSeverity.info,
  }) {
    AppNotifications.show(context, message: message, severity: severity);
  }

  Future<void> _handleHomeFileDrop(List<DropItem> items) async {
    if (!_supportsFileDrops || items.isEmpty) {
      return;
    }
    final List<DropItem> candidates = _filterSupportedDropItems(items);
    if (candidates.isEmpty) {
      if (!mounted) {
        return;
      }
      _showInfoBar(
        context,
        context.l10n.noSupportedImageFormats,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    final String signature = _dropItemsSignature(candidates);
    if (_isHandlingHomeDrop ||
        _isRecentDuplicateDrop(
          signature,
          previousSignature: _lastHomeDropSignature,
          previousAt: _lastHomeDropAt,
        )) {
      return;
    }
    _isHandlingHomeDrop = true;
    final List<ProjectDocument> documents = <ProjectDocument>[];
    int? svgRasterSizePx;
    bool svgRasterSizeResolved = false;
    try {
      for (final DropItem item in candidates) {
        if (!mounted) {
          return;
        }
        int? itemSvgRasterSizePx;
        if (_isSvgDropItem(item)) {
          if (!svgRasterSizeResolved) {
            svgRasterSizePx = await showSvgRasterizeSizeDialog(
              context,
              fileName: _describeDropItem(item),
            );
            svgRasterSizeResolved = true;
            if (svgRasterSizePx == null || !mounted) {
              return;
            }
          }
          itemSvgRasterSizePx = svgRasterSizePx;
        }
        try {
          final ProjectDocument? document = await _createDocumentFromDropItem(
            item,
            svgRasterSizePx: itemSvgRasterSizePx,
          );
          if (document == null) {
            continue;
          }
          documents.add(document);
        } catch (error) {
          if (!mounted) {
            return;
          }
          _showInfoBar(
            context,
            context.l10n.importFailed(_describeDropItem(item), error),
            severity: InfoBarSeverity.error,
          );
        }
      }
      if (!mounted) {
        return;
      }
      if (documents.isEmpty) {
        _showInfoBar(
          context,
          context.l10n.dropImageCreateFailed,
          severity: InfoBarSeverity.warning,
        );
        return;
      }
      _showInfoBar(
        context,
        documents.length == 1
            ? context.l10n.createdCanvasFromDrop
            : context.l10n.createdCanvasesFromDrop(documents.length),
        severity: InfoBarSeverity.success,
      );
      final CanvasWorkspaceController workspace =
          CanvasWorkspaceController.instance;
      for (final ProjectDocument document in documents.skip(1)) {
        workspace.open(document, activate: false);
        workspace.markDirty(document.id, false);
      }
      await AppMenuActions.openProject(context, documents.first);
    } finally {
      _isHandlingHomeDrop = false;
      _lastHomeDropSignature = signature;
      _lastHomeDropAt = DateTime.now();
    }
  }

  bool _isRecentDuplicateDrop(
    String signature, {
    required String? previousSignature,
    required DateTime? previousAt,
  }) {
    if (signature.trim().isEmpty) {
      return false;
    }
    if (previousSignature == null || previousSignature.trim().isEmpty) {
      return false;
    }
    if (signature != previousSignature) {
      return false;
    }
    if (previousAt == null) {
      return false;
    }
    return DateTime.now().difference(previousAt) < _kDropDuplicateDebounce;
  }

  String _dropItemsSignature(List<DropItem> items) {
    if (items.isEmpty) {
      return '';
    }
    final List<String> keys = <String>{
      for (final DropItem item in items) _dropItemDedupKey(item),
    }.toList()..sort();
    return keys.join('|');
  }

  String _dropItemDedupKey(DropItem item) {
    final String normalizedPath = _normalizeDropItemPath(item.path);
    if (normalizedPath.isNotEmpty) {
      final String resolved = Platform.isWindows
          ? normalizedPath.toLowerCase()
          : normalizedPath;
      return 'path:$resolved';
    }
    final String name = item.name.trim();
    if (name.isNotEmpty) {
      return 'name:${name.toLowerCase()}';
    }
    return 'hash:${item.hashCode}';
  }

  String _normalizeDropItemPath(String rawPath) {
    final String trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('file://')) {
      final Uri? uri = Uri.tryParse(trimmed);
      if (uri != null) {
        try {
          final String decodedPath = uri.toFilePath();
          if (decodedPath.trim().isNotEmpty) {
            return p.normalize(decodedPath);
          }
        } catch (_) {
          return p.normalize(trimmed);
        }
      }
    }
    return p.normalize(trimmed);
  }

  List<DropItem> _filterSupportedDropItems(List<DropItem> items) {
    final Set<String> seen = <String>{};
    final List<DropItem> result = <DropItem>[];
    for (final DropItem item in items) {
      if (!_isSupportedDropItem(item)) {
        continue;
      }
      final String key = _dropItemDedupKey(item);
      if (!seen.add(key)) {
        continue;
      }
      result.add(item);
    }
    if (kIsWeb || !Platform.isMacOS || result.length < 2) {
      return result;
    }
    return _dedupeMacOSFilePromiseItems(result);
  }

  List<DropItem> _dedupeMacOSFilePromiseItems(List<DropItem> items) {
    final String promiseDirectory = _normalizeMacOSVarPath(
      p.normalize(p.join(Directory.systemTemp.path, 'Drops')),
    );
    final Map<String, List<DropItem>> groups = <String, List<DropItem>>{};
    for (final DropItem item in items) {
      final String normalizedPath = _normalizeMacOSVarPath(
        _normalizeDropItemPath(item.path),
      );
      if (normalizedPath.isEmpty) {
        continue;
      }
      final String basename = p.basename(normalizedPath).toLowerCase();
      if (basename.isEmpty) {
        continue;
      }
      groups.putIfAbsent(basename, () => <DropItem>[]).add(item);
    }
    if (groups.isEmpty) {
      return items;
    }
    final Set<String> promisePaths = <String>{};
    for (final List<DropItem> group in groups.values) {
      if (group.length < 2) {
        continue;
      }
      bool hasPromise = false;
      bool hasNormal = false;
      final List<String> promiseCandidates = <String>[];
      for (final DropItem item in group) {
        final String normalizedPath = _normalizeMacOSVarPath(
          _normalizeDropItemPath(item.path),
        );
        final bool isPromise =
            p.isWithin(promiseDirectory, normalizedPath) ||
            p.equals(promiseDirectory, normalizedPath);
        if (isPromise) {
          hasPromise = true;
          promiseCandidates.add(normalizedPath);
        } else {
          hasNormal = true;
        }
      }
      if (hasPromise && hasNormal) {
        promisePaths.addAll(promiseCandidates);
      }
    }
    if (promisePaths.isEmpty) {
      return items;
    }
    return <DropItem>[
      for (final DropItem item in items)
        if (!promisePaths.contains(
          _normalizeMacOSVarPath(_normalizeDropItemPath(item.path)),
        ))
          item,
    ];
  }

  String _normalizeMacOSVarPath(String path) {
    if (path.startsWith('/private/var/')) {
      return '/var/${path.substring('/private/var/'.length)}';
    }
    return path;
  }

  bool _isSupportedDropItem(DropItem item) {
    if (item is DropItemDirectory) {
      return false;
    }
    final String extension = _dropItemExtension(item);
    return extension.isNotEmpty &&
        _kDropImageExtensions.contains(extension.toLowerCase());
  }

  String _dropItemExtension(DropItem item) {
    final String name = item.name.trim();
    final String target = name.isNotEmpty ? name : item.path.trim();
    if (target.isEmpty) {
      return '';
    }
    final String lower = target.toLowerCase();
    final int dotIndex = lower.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex + 1 >= lower.length) {
      return '';
    }
    return lower.substring(dotIndex + 1);
  }

  bool _isSvgDropItem(DropItem item) {
    return hasSvgExtension(_dropItemExtension(item));
  }

  Future<ProjectDocument?> _createDocumentFromDropItem(
    DropItem item, {
    int? svgRasterSizePx,
  }) async {
    if (!kIsWeb) {
      final String path = item.path.trim();
      if (path.isNotEmpty) {
        return _runWithSecurityScopedAccess<ProjectDocument?>(
          item,
          () => _repository.createDocumentFromImage(
            path,
            name: _preferredDocumentNameForDrop(item),
            svgRasterSizePx: svgRasterSizePx,
            hideBackgroundLayer: true,
          ),
        );
      }
    }
    final Uint8List? bytes = await _readDropItemBytes(item);
    if (bytes == null) {
      return null;
    }
    return _repository.createDocumentFromImageBytes(
      bytes,
      name: _preferredDocumentNameForDrop(item),
      svgRasterSizePx: svgRasterSizePx,
      hideBackgroundLayer: true,
    );
  }

  Future<Uint8List?> _readDropItemBytes(DropItem item) async {
    if (!kIsWeb) {
      final String path = item.path.trim();
      if (path.isNotEmpty) {
        return _runWithSecurityScopedAccess<Uint8List?>(item, () async {
          final File file = File(path);
          if (!await file.exists()) {
            return null;
          }
          return file.readAsBytes();
        });
      }
    }
    try {
      return await item.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  String? _preferredDocumentNameForDrop(DropItem item) {
    final String candidate = item.name.trim().isNotEmpty
        ? item.name.trim()
        : item.path.trim();
    if (candidate.isEmpty) {
      return null;
    }
    final String base = p.basename(candidate);
    final String resolved = p.basenameWithoutExtension(base);
    return resolved.isEmpty ? base : resolved;
  }

  String _describeDropItem(DropItem item) {
    final String name = item.name.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final String path = item.path.trim();
    if (path.isNotEmpty) {
      return path;
    }
    return context.l10n.image;
  }

  Future<T> _runWithSecurityScopedAccess<T>(
    DropItem item,
    Future<T> Function() action,
  ) async {
    if (kIsWeb ||
        !Platform.isMacOS ||
        item.extraAppleBookmark == null ||
        item.extraAppleBookmark!.isEmpty) {
      return action();
    }
    final Uint8List bookmark = item.extraAppleBookmark!;
    final bool started = await DesktopDrop.instance
        .startAccessingSecurityScopedResource(bookmark: bookmark);
    try {
      return await action();
    } finally {
      if (started) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // desktop_drop keeps hidden routes listening unless disabled explicitly.
    final bool enableDropTargets =
        _supportsFileDrops && (ModalRoute.of(context)?.isCurrent ?? true);
    final handler = MenuActionHandler(
      newProject: () => AppMenuActions.createProject(context),
      importImage: () => AppMenuActions.importImage(context),
      importImageFromClipboard: () =>
          AppMenuActions.importImageFromClipboard(context),
      preferences: () => AppMenuActions.openSettings(context),
    );
    Widget pageContent = Container(
      color: theme.micaBackgroundColor,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: _buildSidebar(context),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.resources.subtleFillColorTertiary,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: theme.resources.controlStrokeColorDefault,
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (_supportsFileDrops) {
      pageContent = DropTarget(
        enable: enableDropTargets,
        onDragDone: (details) => _handleHomeFileDrop(details.files),
        child: pageContent,
      );
    }
    return MenuActionBinding(
      handler: handler,
      child: NavigationView(
        content: ScaffoldPage(padding: EdgeInsets.zero, content: pageContent),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final theme = FluentTheme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 36),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Scrollbar(
          controller: _sidebarScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _sidebarScrollController,
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Misa Rin', style: theme.typography.titleLarge),
                const SizedBox(height: 4),
                Text(l10n.homeTagline, style: theme.typography.body),
                const SizedBox(height: 24),
                _buildSidebarAction(
                  context,
                  icon: FluentIcons.add,
                  label: l10n.homeNewProject,
                  description: l10n.homeNewProjectDesc,
                  onPressed: () => _handleCreateProject(context),
                ),
                _buildSidebarAction(
                  context,
                  icon: FluentIcons.open_file,
                  label: l10n.homeOpenProject,
                  description: l10n.homeOpenProjectDesc,
                  onPressed: () => _handleOpenProject(context),
                ),
                _buildSidebarAction(
                  context,
                  icon: FluentIcons.clock,
                  label: l10n.homeRecentProjects,
                  description: l10n.homeRecentProjectsDesc,
                  onPressed: () => _handleOpenRecent(context),
                ),
                _buildSidebarAction(
                  context,
                  icon: FluentIcons.folder,
                  label: l10n.homeProjectManager,
                  description: l10n.homeProjectManagerDesc,
                  onPressed: () => _handleManageProjects(context),
                ),
                _buildSidebarAction(
                  context,
                  icon: FluentIcons.settings,
                  label: l10n.homeSettings,
                  description: l10n.homeSettingsDesc,
                  onPressed: () => _handleOpenSettings(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    String? description,
  }) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTile.selectable(
        onPressed: onPressed,
        leading: Icon(icon, size: 20),
        title: Text(label, style: theme.typography.subtitle),
        subtitle: description == null ? null : Text(description),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: WidgetStateProperty.resolveWith(
          (states) => states.isHovered
              ? theme.resources.subtleFillColorSecondary
              : theme.resources.subtleFillColorTertiary,
        ),
      ),
    );
  }
}
