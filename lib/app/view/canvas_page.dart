import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../canvas/canvas_exporter.dart';
import '../../canvas/canvas_settings.dart';
import '../dialogs/canvas_size_dialog.dart';
import '../dialogs/export_dialog.dart';
import '../dialogs/image_size_dialog.dart';
import '../dialogs/misarin_dialog.dart';
import '../menu/menu_action_dispatcher.dart';
import '../menu/menu_app_actions.dart';
import '../models/canvas_resize_anchor.dart';
import '../models/workspace_layout.dart';
import '../palette/palette_importer.dart';
import '../preferences/app_preferences.dart';
import '../project/project_binary_codec.dart';
import '../project/project_document.dart';
import '../project/project_repository.dart';
import '../psd/psd_exporter.dart';
import '../toolbars/layouts/painting_toolbar_layout.dart';
import '../widgets/app_notification.dart';
import '../widgets/canvas_title_bar.dart';
import '../widgets/painting_board.dart';
import '../workspace/canvas_workspace_controller.dart';
import '../workspace/workspace_shared_state.dart';
import '../utils/web_file_dialog.dart';
import '../utils/web_file_saver.dart';

class CanvasPage extends StatefulWidget {
  const CanvasPage({
    super.key,
    required this.document,
    this.onInitialBoardReady,
  });

  final ProjectDocument document;
  final VoidCallback? onInitialBoardReady;

  @override
  State<CanvasPage> createState() => CanvasPageState();
}

class _ImportedPaletteEntry {
  const _ImportedPaletteEntry({
    required this.id,
    required this.name,
    required this.colors,
  });

  final String id;
  final String name;
  final List<Color> colors;
}

class CanvasPageState extends State<CanvasPage> {
  final Map<String, GlobalKey<PaintingBoardState>> _boardKeys =
      <String, GlobalKey<PaintingBoardState>>{};
  final CanvasExporter _exporter = CanvasExporter();
  final ProjectRepository _repository = ProjectRepository.instance;
  final CanvasWorkspaceController _workspace =
      CanvasWorkspaceController.instance;
  final Map<String, List<ProjectDocument>> _documentUndoStacks =
      <String, List<ProjectDocument>>{};
  final Map<String, List<ProjectDocument>> _documentRedoStacks =
      <String, List<ProjectDocument>>{};
  WorkspaceOverlaySnapshot? _sharedOverlaySnapshot;
  ToolSettingsSnapshot? _sharedToolSettingsSnapshot;

  final List<_ImportedPaletteEntry> _importedPalettes =
      <_ImportedPaletteEntry>[];
  int _paletteLibrarySerial = 0;
  CanvasResizeAnchor _lastCanvasAnchor = CanvasResizeAnchor.center;

  late ProjectDocument _document;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  bool _isAutoSaving = false;
  Timer? _autoSaveTimer;
  WorkspaceLayoutPreference _workspaceLayoutPreference =
      AppPreferences.instance.workspaceLayout;
  final Map<String, Completer<void>> _boardReadyCompleters =
      <String, Completer<void>>{};
  bool _initialBoardReadyDispatched = false;

  PaintingBoardState? get _activeBoard => _boardFor(_document.id);

  List<ProjectDocument> _undoStackFor(String id) {
    return _documentUndoStacks.putIfAbsent(id, () => <ProjectDocument>[]);
  }

  List<ProjectDocument> _redoStackFor(String id) {
    return _documentRedoStacks.putIfAbsent(id, () => <ProjectDocument>[]);
  }

  void _removeDocumentHistory(String id) {
    _documentUndoStacks.remove(id);
    _documentRedoStacks.remove(id);
  }

  void _pushDocumentHistorySnapshot() {
    final String id = _document.id;
    final List<ProjectDocument> undoStack = _undoStackFor(id);
    undoStack.add(_document.copyWith());
    _documentRedoStacks[id]?.clear();
    _trimDocumentHistoryStacks(id);
  }

  void _trimDocumentHistoryStacks(String id) {
    final int limit = _documentHistoryLimit;
    final List<ProjectDocument>? undoStack = _documentUndoStacks[id];
    final List<ProjectDocument>? redoStack = _documentRedoStacks[id];
    if (undoStack != null) {
      while (undoStack.length > limit) {
        undoStack.removeAt(0);
      }
    }
    if (redoStack != null) {
      while (redoStack.length > limit) {
        redoStack.removeAt(0);
      }
    }
  }

  bool _canUndoDocumentFor(String id) {
    final List<ProjectDocument>? undoStack = _documentUndoStacks[id];
    return undoStack != null && undoStack.isNotEmpty;
  }

  bool _canRedoDocumentFor(String id) {
    final List<ProjectDocument>? redoStack = _documentRedoStacks[id];
    return redoStack != null && redoStack.isNotEmpty;
  }

  bool _undoDocumentChange() {
    final String id = _document.id;
    final List<ProjectDocument>? undoStack = _documentUndoStacks[id];
    if (undoStack == null || undoStack.isEmpty) {
      return false;
    }
    final ProjectDocument previous = undoStack.removeLast();
    final List<ProjectDocument> redoStack = _redoStackFor(id);
    redoStack.add(_document.copyWith());
    _trimDocumentHistoryStacks(id);
    _applyDocumentState(previous);
    return true;
  }

  bool _redoDocumentChange() {
    final String id = _document.id;
    final List<ProjectDocument>? redoStack = _documentRedoStacks[id];
    if (redoStack == null || redoStack.isEmpty) {
      return false;
    }
    final ProjectDocument next = redoStack.removeLast();
    final List<ProjectDocument> undoStack = _undoStackFor(id);
    undoStack.add(_document.copyWith());
    _trimDocumentHistoryStacks(id);
    _applyDocumentState(next);
    return true;
  }

  void _applyDocumentState(ProjectDocument entry) {
    setState(() {
      _document = entry;
      _hasUnsavedChanges = true;
    });
    _workspace.updateDocument(entry);
    _workspace.markDirty(entry.id, true);
  }

  void _snapshotWorkspaceState([PaintingBoardState? board]) {
    final PaintingBoardState? source = board ?? _activeBoard;
    if (source == null) {
      return;
    }
    _sharedOverlaySnapshot = source.buildWorkspaceOverlaySnapshot();
    _sharedToolSettingsSnapshot = source.buildToolSettingsSnapshot();
  }

  void _restoreWorkspaceStateFor(String id) {
    final PaintingBoardState? board = _boardFor(id);
    if (board == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _restoreWorkspaceStateFor(id);
      });
      return;
    }
    final ToolSettingsSnapshot? toolSnapshot = _sharedToolSettingsSnapshot;
    if (toolSnapshot != null) {
      board.applyToolSettingsSnapshot(toolSnapshot);
    }
    final WorkspaceOverlaySnapshot? overlaySnapshot = _sharedOverlaySnapshot;
    if (overlaySnapshot != null) {
      unawaited(board.restoreWorkspaceOverlaySnapshot(overlaySnapshot));
    }
  }

  int get _documentHistoryLimit => AppPreferences.instance.historyLimit;

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

  String _normalizeProjectName(String input) {
    final String trimmed = input.trim();
    return trimmed.isEmpty ? '未命名项目' : trimmed;
  }

  String _suggestedFileName(String extension) {
    final String trimmedName = _document.name.trim();
    final bool isUntitled = trimmedName.isEmpty || trimmedName == '未命名项目';
    final String baseName = isUntitled
        ? '未命名项目_${_timestamp()}'
        : _sanitizeFileName(trimmedName);
    return '$baseName.$extension';
  }

  Future<String?> _promptWebFileName({
    required String title,
    required String suggestedFileName,
    String? description,
    String confirmLabel = '下载',
  }) async {
    final String? raw = await showWebFileNameDialog(
      context: context,
      title: title,
      suggestedFileName: suggestedFileName,
      description: description,
      confirmLabel: confirmLabel,
    );
    if (raw == null) {
      return null;
    }
    return _sanitizeFileName(raw);
  }

  GlobalKey<PaintingBoardState> _ensureBoardKey(String id) {
    return _boardKeys.putIfAbsent(id, () => GlobalKey<PaintingBoardState>());
  }

  PaintingBoardState? _boardFor(String id) {
    return _boardKeys[id]?.currentState;
  }

  void _removeBoardKey(String id) {
    _boardKeys.remove(id);
    _boardReadyCompleters.remove(id)?.complete();
    _removeDocumentHistory(id);
  }

  Completer<void>? _trackBoardReady(String id) {
    if (!kIsWeb) {
      return null;
    }
    final Completer<void> completer = Completer<void>();
    _boardReadyCompleters[id] = completer;
    final PaintingBoardState? board = _boardFor(id);
    if (board != null && board.isBoardReady) {
      scheduleMicrotask(() {
        _boardReadyCompleters.remove(id)?.complete();
      });
    }
    return completer;
  }

  void _handleBoardReadyChanged(String id, bool ready) {
    if (!ready) {
      return;
    }
    _boardReadyCompleters.remove(id)?.complete();
    if (!_initialBoardReadyDispatched && id == widget.document.id) {
      _initialBoardReadyDispatched = true;
      widget.onInitialBoardReady?.call();
    }
  }

  String _fileExtension(String? name) {
    if (name == null) {
      return '';
    }
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  String _displayPaletteName(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '调色盘';
    }
    final int dot = trimmed.lastIndexOf('.');
    if (dot > 0 && dot < trimmed.length - 1) {
      final String ext = trimmed.substring(dot + 1).toLowerCase();
      if (PaletteFileImporter.supportedExtensions.contains(ext)) {
        final String base = trimmed.substring(0, dot).trim();
        if (base.isNotEmpty) {
          return base;
        }
      }
    }
    return trimmed;
  }

  _ImportedPaletteEntry? _paletteById(String id) {
    for (final _ImportedPaletteEntry entry in _importedPalettes) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _importPaletteFromDisk() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入调色盘',
      type: FileType.custom,
      allowedExtensions: PaletteFileImporter.supportedExtensions,
      withData: true,
    );
    final PlatformFile? file = result?.files.singleOrNull;
    if (file == null) {
      return;
    }
    Uint8List? bytes = file.bytes;
    final String? path = file.path;
    if (bytes == null && path != null) {
      bytes = await File(path).readAsBytes();
    }
    if (bytes == null) {
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: '无法读取文件内容。',
        severity: InfoBarSeverity.error,
      );
      return;
    }
    final String ext = _fileExtension(file.name);
    try {
      final PaletteImportResult palette = PaletteFileImporter.importData(
        bytes,
        extension: ext,
        fileName: file.name,
      );
      final String displayName = _displayPaletteName(palette.name);
      final _ImportedPaletteEntry entry = _ImportedPaletteEntry(
        id: 'palette_${_paletteLibrarySerial++}',
        name: displayName,
        colors: palette.colors,
      );
      setState(() {
        _importedPalettes.add(entry);
      });
      final PaintingBoardState? board = _activeBoard;
      board?.showPaletteFromColors(title: entry.name, colors: entry.colors);
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: '已导入调色盘：${entry.name}',
        severity: InfoBarSeverity.success,
      );
    } on PaletteImportException catch (error) {
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: '导入调色盘失败：${error.message}',
        severity: InfoBarSeverity.error,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: '导入调色盘失败：$error',
        severity: InfoBarSeverity.error,
      );
    }
  }

  Future<void> _activateImportedPalette(String id) async {
    final _ImportedPaletteEntry? entry = _paletteById(id);
    if (entry == null) {
      return;
    }
    final PaintingBoardState? board = _activeBoard;
    board?.showPaletteFromColors(title: entry.name, colors: entry.colors);
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

  PaintingToolbarLayoutStyle get _toolbarLayoutStyle {
    return _workspaceLayoutPreference == WorkspaceLayoutPreference.sai2
        ? PaintingToolbarLayoutStyle.sai2
        : PaintingToolbarLayoutStyle.floating;
  }

  Future<void> _setWorkspaceLayoutPreference(
    WorkspaceLayoutPreference preference,
  ) async {
    if (_workspaceLayoutPreference == preference) {
      return;
    }
    final AppPreferences prefs = AppPreferences.instance;
    prefs.workspaceLayout = preference;
    if (mounted) {
      setState(() {
        _workspaceLayoutPreference = preference;
      });
    } else {
      _workspaceLayoutPreference = preference;
    }
    await AppPreferences.save();
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

    final _ExportChoice? choice = await _showExportFormatDialog();
    if (choice == null) {
      return false;
    }
    if (kIsWeb) {
      final String? fileName = await _promptWebFileName(
        title: '另存为项目文件',
        suggestedFileName: _suggestedFileName(choice.extension),
        description: '浏览器会将文件下载到默认的下载目录，你也可以在弹出的提示中修改名称。',
        confirmLabel: '下载',
      );
      if (fileName == null) {
        return false;
      }
      final String normalizedName = _normalizeExportPath(
        fileName,
        choice.extension,
      );
      return _saveProjectAsOnWeb(
        board: board,
        choice: choice,
        fileName: normalizedName,
      );
    }
    final String? selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: '另存为项目文件',
      fileName: _suggestedFileName(choice.extension),
      type: FileType.custom,
      allowedExtensions: <String>[choice.extension],
    );
    if (selectedPath == null) {
      return false;
    }
    final String normalizedPath = _normalizeExportPath(
      selectedPath,
      choice.extension,
    );

    setState(() => _isSaving = true);
    try {
      final layers = board.snapshotLayers();
      final preview = await _exporter.exportToPng(
        settings: _document.settings,
        layers: layers,
        maxDimension: 256,
      );
      late final ProjectDocument saved;
      late final String successMessage;
      if (choice.type == _ExportType.rin) {
        final ProjectDocument updated = _document.copyWith(
          layers: layers,
          previewBytes: preview,
          path: normalizedPath,
        );
        saved = await _repository.saveDocumentAs(updated, normalizedPath);
        successMessage = '项目已保存到 $normalizedPath';
      } else {
        await _repository.exportDocumentAsPsd(
          document: _document.copyWith(layers: layers, previewBytes: preview),
          path: normalizedPath,
        );
        saved = _document.copyWith(
          layers: layers,
          previewBytes: preview,
          path: _document.path,
        );
        successMessage = 'PSD 已导出到 $normalizedPath';
      }
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
      _showInfoBar(successMessage, severity: InfoBarSeverity.success);
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showInfoBar('保存项目失败：$error', severity: InfoBarSeverity.error);
      }
      return false;
    }
  }

  Future<bool> _saveProjectAsOnWeb({
    required PaintingBoardState board,
    required _ExportChoice choice,
    required String fileName,
  }) async {
    setState(() => _isSaving = true);
    try {
      final layers = board.snapshotLayers();
      final Uint8List preview = await _exporter.exportToPng(
        settings: _document.settings,
        layers: layers,
        maxDimension: 256,
      );
      late ProjectDocument resolved = _document.copyWith(
        layers: layers,
        previewBytes: preview,
        updatedAt: DateTime.now(),
      );
      late Uint8List bytes;
      late String successMessage;
      late String mimeType;
      if (choice.type == _ExportType.rin) {
        resolved = await _repository.saveDocument(resolved);
        bytes = ProjectBinaryCodec.encode(resolved);
        successMessage = '项目已下载：$fileName';
        mimeType = 'application/octet-stream';
      } else {
        bytes = await const PsdExporter().exportToBytes(resolved);
        successMessage = 'PSD 已下载：$fileName';
        mimeType = 'image/vnd.adobe.photoshop';
      }
      await WebFileSaver.saveBytes(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );
      if (!mounted) {
        return true;
      }
      setState(() {
        _document = resolved;
        _isSaving = false;
      });
      _workspace.updateDocument(resolved);
      _workspace.markDirty(resolved.id, false);
      board.markSaved();
      _showInfoBar(successMessage, severity: InfoBarSeverity.success);
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showInfoBar('保存项目失败：$error', severity: InfoBarSeverity.error);
      }
      return false;
    }
  }

  Future<_ExportChoice?> _showExportFormatDialog() async {
    return showDialog<_ExportChoice?>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return ContentDialog(
          title: const Text('选择导出格式'),
          content: const Text('请选择要保存的文件格式。'),
          actions: [
            Button(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('取消'),
            ),
            Tooltip(
              message: '导出为 PSD 文件',
              child: Button(
                onPressed: () => Navigator.of(
                  context,
                ).pop(const _ExportChoice(_ExportType.psd, 'psd')),
                child: const Text('保存为 PSD'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(const _ExportChoice(_ExportType.rin, 'rin')),
              child: const Text('保存为 RIN'),
            ),
          ],
        );
      },
    );
  }

  String _normalizeExportPath(String raw, String extension) {
    final String lower = raw.toLowerCase();
    final String suffix = '.$extension';
    return lower.endsWith(suffix) ? raw : '$raw$suffix';
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
    const String extension = 'png';
    String? normalizedPath;
    String? downloadName;
    if (kIsWeb) {
      final String? fileName = await _promptWebFileName(
        title: '导出 PNG 文件',
        suggestedFileName: _suggestedFileName(extension),
        description: '浏览器会将图像保存到默认的下载目录。',
        confirmLabel: '导出',
      );
      if (fileName == null) {
        return false;
      }
      downloadName = _normalizeExportPath(fileName, extension);
    } else {
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出 PNG 文件',
        fileName: _suggestedFileName(extension),
        type: FileType.custom,
        allowedExtensions: <String>[extension],
      );
      if (outputPath == null) {
        return false;
      }
      normalizedPath = _normalizeExportPath(outputPath, extension);
    }

    try {
      setState(() => _isSaving = true);
      final layers = board.snapshotLayers();
      final Uint8List bytes = await _exporter.exportToPng(
        settings: _document.settings,
        layers: layers,
        outputSize: ui.Size(
          options.width.toDouble(),
          options.height.toDouble(),
        ),
      );
      if (kIsWeb) {
        await WebFileSaver.saveBytes(
          fileName: downloadName!,
          bytes: bytes,
          mimeType: 'image/png',
        );
        _showInfoBar(
          'PNG 已下载：$downloadName',
          severity: InfoBarSeverity.success,
        );
      } else {
        final file = File(normalizedPath!);
        await file.writeAsBytes(bytes, flush: true);
        _showInfoBar('已导出到 $normalizedPath', severity: InfoBarSeverity.success);
      }
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

  void _applyCanvasRotation(CanvasRotation rotation) {
    final PaintingBoardState? board = _activeBoard;
    if (board == null) {
      _showInfoBar('画布尚未准备好，无法执行图像变换。', severity: InfoBarSeverity.warning);
      return;
    }
    final CanvasRotationResult? result = board.rotateCanvas(rotation);
    if (result == null) {
      _showInfoBar('画布尺寸异常，无法执行图像变换。', severity: InfoBarSeverity.error);
      return;
    }

    _pushDocumentHistorySnapshot();
    final CanvasSettings updatedSettings = _document.settings.copyWith(
      width: result.width.toDouble(),
      height: result.height.toDouble(),
    );
    final DateTime now = DateTime.now();
    final ProjectDocument updated = _document.copyWith(
      settings: updatedSettings,
      updatedAt: now,
      layers: result.layers,
      previewBytes: null,
    );

    _applyDocumentState(updated);
  }

  Future<void> _handleResizeImage() async {
    final PaintingBoardState? board = _activeBoard;
    if (board == null) {
      _showInfoBar('画布尚未准备好，无法调整图像大小。', severity: InfoBarSeverity.warning);
      return;
    }
    final ImageResizeConfig? config = await showImageSizeDialog(
      context,
      initialWidth: _document.settings.width.round(),
      initialHeight: _document.settings.height.round(),
    );
    if (config == null) {
      return;
    }
    final CanvasResizeResult? result = await board.resizeImage(
      config.width,
      config.height,
      config.sampling,
    );
    if (result == null) {
      _showInfoBar('调整图像大小失败。', severity: InfoBarSeverity.error);
      return;
    }
    _applyCanvasResizeResult(result);
  }

  Future<void> _handleUndo() async {
    final PaintingBoardState? board = _activeBoard;
    if (board != null && await board.undo()) {
      return;
    }
    _undoDocumentChange();
  }

  Future<void> _handleRedo() async {
    final PaintingBoardState? board = _activeBoard;
    if (board != null && await board.redo()) {
      return;
    }
    _redoDocumentChange();
  }

  Future<void> _handleResizeCanvas() async {
    final PaintingBoardState? board = _activeBoard;
    if (board == null) {
      _showInfoBar('画布尚未准备好，无法调整画布大小。', severity: InfoBarSeverity.warning);
      return;
    }
    final CanvasSizeConfig? config = await showCanvasSizeDialog(
      context,
      initialWidth: _document.settings.width.round(),
      initialHeight: _document.settings.height.round(),
      initialAnchor: _lastCanvasAnchor,
    );
    if (config == null) {
      return;
    }
    _lastCanvasAnchor = config.anchor;
    final CanvasResizeResult? result = await board.resizeCanvas(
      config.width,
      config.height,
      config.anchor,
    );
    if (result == null) {
      _showInfoBar('调整画布大小失败。', severity: InfoBarSeverity.error);
      return;
    }
    _applyCanvasResizeResult(result);
  }

  Future<void> _handleExitRequest() async {
    final bool canLeave = await _ensureCanLeave(
      dialogTitle: '返回主页面',
      dialogContent: '是否在返回前保存当前项目？',
    );
    if (!canLeave) {
      return;
    }
    await _closePage();
  }

  Future<_ExitAction?> _showExitDialog({
    String title = '返回主页面',
    String content = '是否在返回前保存当前项目？',
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
        _workspace.markDirty(_document.id, false);
        return true;
      case _ExitAction.discard:
        _workspace.markDirty(_document.id, false);
        return true;
      case _ExitAction.cancel:
        return false;
    }
  }

  void _showInfoBar(
    String message, {
    InfoBarSeverity severity = InfoBarSeverity.info,
  }) {
    if (!mounted) {
      return;
    }
    AppNotifications.show(context, message: message, severity: severity);
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
    final Completer<void>? readyCompleter = _trackBoardReady(document.id);
    _workspace.open(document, activate: true);
    _switchToEntry(_workspace.entryById(document.id));
    if (readyCompleter != null) {
      await readyCompleter.future;
    }
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
    final PaintingBoardState? previousBoard = _activeBoard;
    final CanvasWorkspaceEntry? neighbor = _workspace.neighborFor(id);
    if (_hasUnsavedChanges) {
      final bool canLeave = await _ensureCanLeave(
        dialogTitle: '关闭画布',
        dialogContent: '是否在关闭前保存当前项目？',
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
      _switchToEntry(
        _workspace.entryById(nextId),
        previousBoard: previousBoard,
      );
      return;
    }
    _snapshotWorkspaceState(previousBoard);
    _removeBoardKey(id);
    await _closePage();
  }

  Future<void> _handleTabRename(String id) async {
    final CanvasWorkspaceEntry? entry = _workspace.entryById(id);
    if (entry == null) {
      return;
    }
    final String? rawName = await _showProjectRenameDialog(entry.name);
    if (rawName == null) {
      return;
    }
    final String resolvedName = _normalizeProjectName(rawName);
    if (resolvedName == entry.name) {
      return;
    }
    final ProjectDocument updated = entry.document.copyWith(
      name: resolvedName,
      updatedAt: DateTime.now(),
    );
    if (id == _document.id) {
      setState(() {
        _document = updated;
        _hasUnsavedChanges = true;
      });
    }
    _workspace.updateDocument(updated);
    _workspace.markDirty(id, true);
  }

  Future<String?> _showProjectRenameDialog(String currentName) async {
    final TextEditingController controller = TextEditingController(
      text: currentName,
    );
    String? errorText;
    StateSetter? dialogSetState;

    void submit() {
      final String trimmed = controller.text.trim();
      if (trimmed.isEmpty) {
        dialogSetState?.call(() {
          errorText = '名称不能为空';
        });
        return;
      }
      Navigator.of(context).pop(trimmed);
    }

    final String? result = await showMisarinDialog<String>(
      context: context,
      title: const Text('重命名项目'),
      contentWidth: 360,
      content: StatefulBuilder(
        builder: (context, setState) {
          dialogSetState = setState;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('请输入新的项目名称'),
              const SizedBox(height: 8),
              TextBox(
                controller: controller,
                autofocus: true,
                placeholder: '未命名项目',
                onChanged: (_) {
                  if (errorText != null) {
                    setState(() => errorText = null);
                  }
                },
                onSubmitted: (_) => submit(),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorText!,
                  style: const TextStyle(color: Color(0xFFD13438)),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: submit, child: const Text('重命名')),
      ],
    );
    controller.dispose();
    return result;
  }

  void _switchToEntry(
    CanvasWorkspaceEntry? entry, {
    PaintingBoardState? previousBoard,
  }) {
    if (entry == null) {
      return;
    }
    _snapshotWorkspaceState(previousBoard);
    _ensureBoardKey(entry.id);
    setState(() {
      _document = entry.document;
      _hasUnsavedChanges = entry.isDirty;
      _isSaving = false;
      _isAutoSaving = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _restoreWorkspaceStateFor(entry.id);
    });
  }

  void _applyCanvasResizeResult(CanvasResizeResult result) {
    _pushDocumentHistorySnapshot();
    final CanvasSettings updatedSettings = _document.settings.copyWith(
      width: result.width.toDouble(),
      height: result.height.toDouble(),
    );
    final ProjectDocument updated = _document.copyWith(
      settings: updatedSettings,
      layers: result.layers,
      updatedAt: DateTime.now(),
      previewBytes: null,
    );
    _applyDocumentState(updated);
  }

  Widget _buildBoard(CanvasWorkspaceEntry entry) {
    final String id = entry.id;
    return PaintingBoard(
      key: _ensureBoardKey(id),
      settings: entry.document.settings,
      onRequestExit: _handleExitRequest,
      onDirtyChanged: (dirty) => _handleDirtyChanged(id, dirty),
      initialLayers: entry.document.layers,
      onUndoFallback: _undoDocumentChange,
      onRedoFallback: _redoDocumentChange,
      externalCanUndo: _canUndoDocumentFor(id),
      externalCanRedo: _canRedoDocumentFor(id),
      onResizeImage: _handleResizeImage,
      onResizeCanvas: _handleResizeCanvas,
      onReadyChanged: kIsWeb
          ? (ready) => _handleBoardReadyChanged(id, ready)
          : null,
      toolbarLayoutStyle: _toolbarLayoutStyle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final handler = MenuActionHandler(
      newProject: () => AppMenuActions.createProject(context),
      open: () => AppMenuActions.openProjectFromDisk(context),
      closeAll: _handleExitRequest,
      importImage: () => AppMenuActions.importImage(context),
      importImageFromClipboard: () =>
          AppMenuActions.importImageFromClipboard(context),
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
      undo: _handleUndo,
      redo: _handleRedo,
      cut: () async {
        final board = _activeBoard;
        if (board != null) {
          await board.cut();
        }
      },
      copy: () async {
        final board = _activeBoard;
        if (board != null) {
          await board.copy();
        }
      },
      paste: () async {
        final board = _activeBoard;
        if (board != null) {
          await board.paste();
        }
      },
      newLayer: () {
        final board = _activeBoard;
        board?.addLayerAboveActiveLayer();
      },
      importPalette: () => _importPaletteFromDisk(),
      paletteMenuEntries: _importedPalettes
          .map((entry) => MenuPaletteMenuEntry(id: entry.id, label: entry.name))
          .toList(growable: false),
      selectPaletteFromMenu: (id) => _activateImportedPalette(id),
      createReferenceImage: () {
        final board = _activeBoard;
        unawaited(board?.createReferenceImageCard());
      },
      importReferenceImage: () {
        final board = _activeBoard;
        unawaited(board?.importReferenceImageCard());
      },
      zoomIn: () {
        final board = _activeBoard;
        board?.zoomIn();
      },
      zoomOut: () {
        final board = _activeBoard;
        board?.zoomOut();
      },
      togglePixelGrid: () {
        final board = _activeBoard;
        if (board == null) {
          return;
        }
        board.togglePixelGridVisibility();
        setState(() {});
      },
      pixelGridVisible: _activeBoard?.isPixelGridVisible ?? false,
      rotateCanvas90Clockwise: () {
        _applyCanvasRotation(CanvasRotation.clockwise90);
      },
      rotateCanvas90CounterClockwise: () {
        _applyCanvasRotation(CanvasRotation.counterClockwise90);
      },
      rotateCanvas180Clockwise: () {
        _applyCanvasRotation(CanvasRotation.clockwise180);
      },
      rotateCanvas180CounterClockwise: () {
        _applyCanvasRotation(CanvasRotation.counterClockwise180);
      },
      export: () async {
        await _exportProject();
      },
      generatePalette: () {
        final board = _activeBoard;
        board?.showPaletteGenerator();
      },
      generateGradientPalette: () {
        final board = _activeBoard;
        board?.showGradientPaletteFromPrimaryColor();
      },
      showLayerAntialiasPanel: () {
        final board = _activeBoard;
        board?.showLayerAntialiasPanel();
      },
      gaussianBlur: () {
        final board = _activeBoard;
        board?.showGaussianBlurAdjustments();
      },
      resizeImage: _handleResizeImage,
      resizeCanvas: _handleResizeCanvas,
      mergeLayerDown: () {
        final board = _activeBoard;
        board?.mergeActiveLayerDown();
      },
      layerFreeTransform: () {
        final board = _activeBoard;
        board?.toggleLayerFreeTransform();
      },
      selectAll: () {
        final board = _activeBoard;
        board?.selectEntireCanvas();
      },
      invertSelection: () {
        final board = _activeBoard;
        board?.invertSelection();
      },
      adjustHueSaturation: () {
        final board = _activeBoard;
        if (board == null) {
          _showInfoBar(
            '画布尚未准备好，无法调节色相/饱和度。',
            severity: InfoBarSeverity.warning,
          );
          return;
        }
        board.showHueSaturationAdjustments();
      },
      adjustBrightnessContrast: () {
        final board = _activeBoard;
        if (board == null) {
          _showInfoBar(
            '画布尚未准备好，无法调节亮度/对比度。',
            severity: InfoBarSeverity.warning,
          );
          return;
        }
        board.showBrightnessContrastAdjustments();
      },
      workspaceLayoutPreference: _workspaceLayoutPreference,
      switchWorkspaceLayout: _setWorkspaceLayoutPreference,
      resetWorkspaceLayout: () {
        final board = _activeBoard;
        board?.resetWorkspaceLayout();
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
                onRenameTab: _handleTabRename,
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

enum _ExportType { rin, psd }

class _ExportChoice {
  const _ExportChoice(this.type, this.extension);

  final _ExportType type;
  final String extension;
}

enum _ExitAction { save, discard, cancel }
