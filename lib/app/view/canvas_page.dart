import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../canvas/canvas_exporter.dart';
import '../dialogs/export_dialog.dart';
import '../dialogs/misarin_dialog.dart';
import '../menu/menu_action_dispatcher.dart';
import '../menu/menu_app_actions.dart';
import '../project/project_document.dart';
import '../project/project_repository.dart';
import '../widgets/canvas_title_bar.dart';
import '../widgets/painting_board.dart';
import '../workspace/canvas_workspace_controller.dart';

class CanvasPage extends StatefulWidget {
  const CanvasPage({super.key, required this.document});

  final ProjectDocument document;

  @override
  State<CanvasPage> createState() => CanvasPageState();
}

class CanvasPageState extends State<CanvasPage> {
  final Map<String, GlobalKey<PaintingBoardState>> _boardKeys =
      <String, GlobalKey<PaintingBoardState>>{};
  final CanvasExporter _exporter = CanvasExporter();
  final ProjectRepository _repository = ProjectRepository.instance;
  final CanvasWorkspaceController _workspace =
      CanvasWorkspaceController.instance;

  late ProjectDocument _document;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  bool _isAutoSaving = false;
  Timer? _autoSaveTimer;

  PaintingBoardState? get _activeBoard => _boardFor(_document.id);

  String _timestamp() {
    final DateTime now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }

  String _sanitizeFileName(String input) {
    final sanitized = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? '未命名项目' : sanitized;
  }

  String _suggestedFileName(String extension) {
    final String trimmedName = _document.name.trim();
    final bool isUntitled = trimmedName.isEmpty || trimmedName == '未命名项目';
    final String baseName = isUntitled
        ? '未命名项目_${_timestamp()}'
        : _sanitizeFileName(trimmedName);
    return '$baseName.$extension';
  }

  GlobalKey<PaintingBoardState> _ensureBoardKey(String id) {
    return _boardKeys.putIfAbsent(id, () => GlobalKey<PaintingBoardState>());
  }

  PaintingBoardState? _boardFor(String id) {
    return _boardKeys[id]?.currentState;
  }

  void _removeBoardKey(String id) {
    _boardKeys.remove(id);
  }

  void _handleDirtyChanged(String id, bool dirty) {
    if (id == _document.id && _hasUnsavedChanges != dirty) {
      setState(() => _hasUnsavedChanges = dirty);
    }
    _workspace.markDirty(id, dirty);
  }

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _workspace.open(_document, activate: true);
    _workspace.markDirty(_document.id, false);
    _ensureBoardKey(_document.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureInitialSave();
    });
    _autoSaveTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _saveProject();
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _ensureInitialSave() async {
    if (!mounted) {
      return;
    }
    if (_document.path != null) {
      return;
    }
    await _saveProject(force: true);
  }

  Future<bool> _saveProject({
    bool force = false,
    bool showMessage = false,
  }) async {
    if (!mounted) {
      return false;
    }
    if (_isAutoSaving) {
      return false;
    }
    final PaintingBoardState? board = _activeBoard;
    if (board == null) {
      return false;
    }
    final bool shouldPersist =
        force || _document.path == null || _hasUnsavedChanges;
    if (!shouldPersist) {
      if (showMessage) {
        final String location = _document.path ?? '默认项目目录';
        _showInfoBar('没有需要保存的更改（当前路径：$location）');
      }
      return false;
    }
    setState(() => _isAutoSaving = true);
    try {
      final layers = board.snapshotLayers();
      final preview = await _exporter.exportToPng(
        settings: _document.settings,
        layers: layers,
        maxDimension: 256,
      );
      final ProjectDocument updated = _document.copyWith(
        layers: layers,
        previewBytes: preview,
        bucketSampleAllLayers: board.bucketSampleAllLayers,
        bucketContiguous: board.bucketContiguous,
      );
      final ProjectDocument saved = await _repository.saveDocument(updated);
      if (!mounted) {
        return true;
      }
      setState(() {
        _document = saved;
        _isAutoSaving = false;
      });
      _workspace.updateDocument(saved);
      _workspace.markDirty(saved.id, false);
      board.markSaved();
      if (showMessage) {
        final String location = saved.path ?? '默认项目目录';
        _showInfoBar('项目已保存到 $location', severity: InfoBarSeverity.success);
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _isAutoSaving = false);
        _showInfoBar('保存项目失败：$error', severity: InfoBarSeverity.error);
      }
      return false;
    }
  }

  Future<bool> _saveProjectAs() async {
    if (!mounted || _isSaving || _isAutoSaving) {
      return false;
    }
    final PaintingBoardState? board = _activeBoard;
    if (board == null) {
      _showInfoBar('画布尚未准备好，无法保存。', severity: InfoBarSeverity.error);
      return false;
    }

    final String? selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: '另存为项目文件',
      fileName: _suggestedFileName('rin'),
      type: FileType.custom,
      allowedExtensions: const ['rin'],
    );
    if (selectedPath == null) {
      return false;
    }
    final String normalizedPath = selectedPath.toLowerCase().endsWith('.rin')
        ? selectedPath
        : '$selectedPath.rin';

    setState(() => _isSaving = true);
    try {
      final layers = board.snapshotLayers();
      final preview = await _exporter.exportToPng(
        settings: _document.settings,
        layers: layers,
        maxDimension: 256,
      );
      final ProjectDocument updated = _document.copyWith(
        layers: layers,
        previewBytes: preview,
        path: normalizedPath,
        bucketSampleAllLayers: board.bucketSampleAllLayers,
        bucketContiguous: board.bucketContiguous,
      );
      final ProjectDocument saved = await _repository.saveDocumentAs(
        updated,
        normalizedPath,
      );
      if (!mounted) {
        return true;
      }
      setState(() {
        _document = saved;
        _isSaving = false;
      });
      _workspace.updateDocument(saved);
      _workspace.markDirty(saved.id, false);
      board.markSaved();
      _showInfoBar('项目已保存到 $normalizedPath', severity: InfoBarSeverity.success);
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showInfoBar('保存项目失败：$error', severity: InfoBarSeverity.error);
      }
      return false;
    }
  }

  Future<bool> _exportProject() async {
    final PaintingBoardState? board = _activeBoard;
    if (board == null) {
      _showInfoBar('画布尚未准备好，无法导出。', severity: InfoBarSeverity.error);
      return false;
    }

    final CanvasExportOptions? options = await showCanvasExportDialog(
      context: context,
      settings: _document.settings,
    );
    if (options == null) {
      return false;
    }
    final String extension = options.format == CanvasExportFormat.png
        ? 'png'
        : 'svg';
    final String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出 ${extension.toUpperCase()} 文件',
      fileName: _suggestedFileName(extension),
      type: FileType.custom,
      allowedExtensions: <String>[extension],
    );
    if (outputPath == null) {
      return false;
    }
    final String normalizedPath =
        outputPath.toLowerCase().endsWith('.$extension')
        ? outputPath
        : '$outputPath.$extension';

    try {
      setState(() => _isSaving = true);
      late Uint8List bytes;
      final layers = board.snapshotLayers();
      if (options.format == CanvasExportFormat.png) {
        bytes = await _exporter.exportToPng(
          settings: _document.settings,
          layers: layers,
          outputSize: ui.Size(
            options.width.toDouble(),
            options.height.toDouble(),
          ),
        );
      } else {
        bytes = await _exporter.exportToSvg(
          settings: _document.settings,
          layers: layers,
        );
      }
      final file = File(normalizedPath);
      await file.writeAsBytes(bytes, flush: true);
      _showInfoBar('已导出到 $normalizedPath', severity: InfoBarSeverity.success);
      return true;
    } catch (error) {
      _showInfoBar('导出失败：$error', severity: InfoBarSeverity.error);
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _handleExitRequest() async {
    final bool canLeave = await _ensureCanLeave(
      dialogTitle: '返回主页面',
      dialogContent: '是否在返回前保存当前画布？',
      includeCanvasExport: true,
    );
    if (!canLeave) {
      return;
    }
    await _closePage();
  }

  Future<_ExitAction?> _showExitDialog({
    String title = '返回主页面',
    String content = '是否在返回前保存当前画布？',
  }) {
    return showDialog<_ExitAction>(
      context: context,
      barrierDismissible: true,
      builder: (context) => MisarinDialog(
        title: Text(title),
        content: Text(content),
        contentWidth: 360,
        maxWidth: 480,
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(_ExitAction.cancel),
            child: const Text('取消'),
          ),
          Button(
            onPressed: () => Navigator.of(context).pop(_ExitAction.discard),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_ExitAction.save),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureCanLeave({
    required String dialogTitle,
    required String dialogContent,
    required bool includeCanvasExport,
  }) async {
    if (_isSaving || _isAutoSaving) {
      return false;
    }
    if (!_hasUnsavedChanges) {
      return true;
    }
    final _ExitAction? action = await _showExitDialog(
      title: dialogTitle,
      content: dialogContent,
    );
    if (!mounted || action == null) {
      return false;
    }
    switch (action) {
      case _ExitAction.save:
        final bool projectSaved = _document.path == null
            ? await _saveProjectAs()
            : await _saveProject(force: true);
        if (!projectSaved) {
          return false;
        }
        if (includeCanvasExport) {
          final bool exported = await _saveCanvas();
          if (!exported) {
            return false;
          }
        }
        _workspace.markDirty(_document.id, false);
        return true;
      case _ExitAction.discard:
        _workspace.markDirty(_document.id, false);
        return true;
      case _ExitAction.cancel:
        return false;
    }
  }

  Future<bool> _saveCanvas() async {
    final PaintingBoardState? board = _activeBoard;
    if (board == null) {
      _showInfoBar('画布尚未准备好，无法保存。', severity: InfoBarSeverity.error);
      return false;
    }
    final String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: '保存画布为 PNG',
      fileName: 'misa_rin_${DateTime.now().millisecondsSinceEpoch}.png',
      type: FileType.custom,
      allowedExtensions: const ['png'],
    );
    if (outputPath == null) {
      return false;
    }
    final String normalizedPath = outputPath.toLowerCase().endsWith('.png')
        ? outputPath
        : '$outputPath.png';

    try {
      setState(() => _isSaving = true);
      final bytes = await _exporter.exportToPng(
        settings: _document.settings,
        layers: board.snapshotLayers(),
      );
      final file = File(normalizedPath);
      await file.writeAsBytes(bytes, flush: true);
      board.markSaved();
      _workspace.markDirty(_document.id, false);
      _showInfoBar('已保存到 $normalizedPath', severity: InfoBarSeverity.success);
      return true;
    } catch (error) {
      _showInfoBar('保存失败：$error', severity: InfoBarSeverity.error);
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showInfoBar(
    String message, {
    InfoBarSeverity severity = InfoBarSeverity.info,
  }) {
    if (!mounted) {
      return;
    }
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        severity: severity,
        title: Text(message),
        action: IconButton(
          icon: const Icon(FluentIcons.clear),
          onPressed: close,
        ),
      ),
    );
  }

  Future<void> _closePage() async {
    if (!mounted) {
      return;
    }
    _removeBoardKey(_document.id);
    _workspace.remove(_document.id);
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<void> openDocument(ProjectDocument document) async {
    _workspace.open(document, activate: true);
    _switchToEntry(_workspace.entryById(document.id));
  }

  void _handleTabSelected(String id) {
    if (id == _document.id) {
      _workspace.setActive(id);
      return;
    }
    final CanvasWorkspaceEntry? entry = _workspace.entryById(id);
    if (entry == null) {
      return;
    }
    _workspace.setActive(id);
    _switchToEntry(entry);
  }

  Future<void> _handleTabClosed(String id) async {
    if (id != _document.id) {
      _removeBoardKey(id);
      _workspace.remove(id);
      return;
    }
    final CanvasWorkspaceEntry? neighbor = _workspace.neighborFor(id);
    if (_hasUnsavedChanges) {
      final bool canLeave = await _ensureCanLeave(
        dialogTitle: '关闭画布',
        dialogContent: '是否在关闭前保存当前画布？',
        includeCanvasExport: true,
      );
      if (!canLeave) {
        _workspace.setActive(_document.id);
        return;
      }
    }
    if (neighbor != null) {
      final String nextId = neighbor.id;
      _workspace.remove(id, activateAfter: nextId);
      _removeBoardKey(id);
      _switchToEntry(_workspace.entryById(nextId));
      return;
    }
    _removeBoardKey(id);
    await _closePage();
  }

  void _switchToEntry(CanvasWorkspaceEntry? entry) {
    if (entry == null) {
      return;
    }
    _ensureBoardKey(entry.id);
    setState(() {
      _document = entry.document;
      _hasUnsavedChanges = entry.isDirty;
      _isSaving = false;
      _isAutoSaving = false;
    });
  }

  Widget _buildBoard(CanvasWorkspaceEntry entry) {
    return PaintingBoard(
      key: _ensureBoardKey(entry.id),
      settings: entry.document.settings,
      onRequestExit: _handleExitRequest,
      onDirtyChanged: (dirty) => _handleDirtyChanged(entry.id, dirty),
      initialLayers: entry.document.layers,
      bucketSampleAllLayers: entry.document.bucketSampleAllLayers,
      bucketContiguous: entry.document.bucketContiguous,
    );
  }

  @override
  Widget build(BuildContext context) {
    final handler = MenuActionHandler(
      newProject: () => AppMenuActions.createProject(context),
      open: () => AppMenuActions.openProjectFromDisk(context),
      preferences: () => AppMenuActions.openSettings(context),
      about: () => AppMenuActions.showAbout(context),
      save: () async {
        if (_document.path == null) {
          await _saveProjectAs();
        } else {
          await _saveProject(force: true, showMessage: true);
        }
      },
      saveAs: () async {
        await _saveProjectAs();
      },
      undo: () {
        final board = _activeBoard;
        board?.undo();
      },
      redo: () {
        final board = _activeBoard;
        board?.redo();
      },
      zoomIn: () {
        final board = _activeBoard;
        board?.zoomIn();
      },
      zoomOut: () {
        final board = _activeBoard;
        board?.zoomOut();
      },
      export: () async {
        await _exportProject();
      },
    );

    return MenuActionBinding(
      handler: handler,
      child: NavigationView(
        content: ScaffoldPage(
          padding: EdgeInsets.zero,
          content: Column(
            children: [
              CanvasTitleBar(
                onSelectTab: _handleTabSelected,
                onCloseTab: _handleTabClosed,
                onCreateTab: () => AppMenuActions.createProject(context),
              ),
              Expanded(
                child: Container(
                  color: FluentTheme.of(context).micaBackgroundColor,
                  child: AnimatedBuilder(
                    animation: _workspace,
                    builder: (context, _) {
                      final List<CanvasWorkspaceEntry> entries =
                          _workspace.entries;
                      if (entries.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final int activeIndex = entries.indexWhere(
                        (entry) => entry.id == _document.id,
                      );
                      if (activeIndex < 0) {
                        return const SizedBox.shrink();
                      }
                      return IndexedStack(
                        index: activeIndex,
                        alignment: Alignment.center,
                        children: [
                          for (final CanvasWorkspaceEntry entry in entries)
                            Align(
                              alignment: Alignment.center,
                              child: _buildBoard(entry),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ExitAction { save, discard, cancel }
