import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:misa_rin/mobile/responsive_dialog.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/widgets.dart'
    show
        StatefulBuilder,
        StateSetter,
        TextEditingController,
        ValueListenableBuilder,
        WidgetsBinding;
import 'package:misa_rin/utils/io_shim.dart';
import 'package:path/path.dart' as p;

import '../../canvas/canvas_backend.dart';
import '../../canvas/canvas_exporter.dart';
import '../../canvas/canvas_settings.dart';
import '../../canvas/perspective_guide.dart';
import '../dialogs/canvas_size_dialog.dart';
import '../dialogs/export_dialog.dart';
import '../dialogs/image_size_dialog.dart';
import '../dialogs/misarin_dialog.dart';
import '../dialogs/svg_rasterize_size_dialog.dart';
import '../l10n/l10n.dart';
import '../menu/custom_menu_bar.dart';
import '../menu/menu_action_dispatcher.dart';
import '../menu/menu_app_actions.dart';
import '../models/canvas_resize_anchor.dart';
import '../models/canvas_view_info.dart';
import '../models/workspace_layout.dart';
import '../debug/backend_canvas_timeline.dart';
import '../palette/palette_importer.dart';
import '../preferences/app_preferences.dart';
import '../project/project_binary_codec.dart';
import '../project/project_document.dart';
import '../project/project_repository.dart';
import '../psd/psd_exporter.dart';
import '../sai2/sai2_exporter.dart';
import '../toolbars/layouts/painting_toolbar_layout.dart';
import '../widgets/app_notification.dart';
import '../widgets/canvas_title_bar.dart';
import '../widgets/painting_board.dart';
import '../workspace/canvas_workspace_controller.dart';
import '../workspace/workspace_shared_state.dart';
import '../utils/file_name_dialog.dart';
import '../utils/ios_photo_saver.dart';
import '../utils/mobile_export_paths.dart';
import '../utils/platform_target.dart';
import '../utils/svg_rasterizer.dart';
import '../utils/web_file_dialog.dart';
import '../utils/web_file_saver.dart';
import '../../mobile/mobile_utils.dart';
import '../../mobile/mobile_menu_button.dart';
import '../../mobile/mobile_right_buttons.dart';
import '../../mobile/mobile_tool_buttons.dart';
import '../../mobile/mobile_undo_redo_buttons.dart';
import '../../mobile/mobile_bottom_sheet.dart';

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

  late ProjectDocument _document;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  bool _isAutoSaving = false;
  Timer? _autoSaveTimer;
  WorkspaceLayoutPreference _workspaceLayoutPreference =
      AppPreferences.instance.workspaceLayout;
  final Map<String, Completer<void>> _boardReadyCompleters =
      <String, Completer<void>>{};
  Widget? _menuOverlay;
  bool _initialBoardReadyDispatched = false;

  PaintingBoardState? get _activeBoard => _boardFor(_document.id);
  bool get _supportsFileDrops =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  bool _isHandlingTabBarDrop = false;
  String? _lastTabBarDropSignature;
  DateTime? _lastTabBarDropAt;
  bool _isHandlingCanvasDrop = false;
  String? _lastCanvasDropSignature;
  DateTime? _lastCanvasDropAt;

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

  void _pushDocumentHistorySnapshot({ProjectDocument? snapshot}) {
    final String id = _document.id;
    final List<ProjectDocument> undoStack = _undoStackFor(id);
    final ProjectDocument entry = (snapshot ?? _document).copyWith();
    undoStack.add(entry);
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
    return sanitized.isEmpty ? context.l10n.untitledProject : sanitized;
  }

  String _normalizeProjectName(String input) {
    final String trimmed = input.trim();
    return trimmed.isEmpty ? context.l10n.untitledProject : trimmed;
  }

  String _suggestedFileName(String extension) {
    final l10n = context.l10n;
    final String trimmedName = _document.name.trim();
    final bool isUntitled =
        trimmedName.isEmpty ||
        trimmedName == '未命名项目' ||
        trimmedName == l10n.untitledProject;
    final String baseName = isUntitled
        ? '${l10n.untitledProject}_${_timestamp()}'
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
    if (id == _document.id) {
      _updateMenuOverlay();
    }
    if (!_initialBoardReadyDispatched && id == widget.document.id) {
      BackendCanvasTimeline.mark(
        'canvasPage: board ready for active document id=$id',
      );
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

  String _displayPaletteName(String raw, AppLocalizations l10n) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return l10n.paletteDefaultName;
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
    final l10n = context.l10n;
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: l10n.importPaletteTitle,
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
        message: l10n.cannotReadFile,
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
      final String displayName = _displayPaletteName(palette.name, l10n);
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
        message: l10n.paletteImported(entry.name),
        severity: InfoBarSeverity.success,
      );
    } on PaletteImportException catch (error) {
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: l10n.paletteImportFailed(error.message),
        severity: InfoBarSeverity.error,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: l10n.paletteImportFailed(error),
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

  void _updateMenuOverlay() {
    final Widget overlay = _CanvasStatusOverlay(board: _activeBoard);
    _menuOverlay = overlay;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _menuOverlay != overlay) {
        return;
      }
      CustomMenuBarOverlay.centerOverlay.value = overlay;
    });
  }

  void _clearMenuOverlay() {
    if (CustomMenuBarOverlay.centerOverlay.value == _menuOverlay) {
      CustomMenuBarOverlay.centerOverlay.value = null;
    }
    _menuOverlay = null;
  }

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    BackendCanvasTimeline.mark(
      'canvasPage: initState '
      'size=${_document.settings.width.round()}x${_document.settings.height.round()}',
    );
    _workspace.open(_document, activate: true);
    _workspace.markDirty(_document.id, false);
    _ensureBoardKey(_document.id);
    _updateMenuOverlay();
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
    _clearMenuOverlay();
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
    final l10n = context.l10n;
    final bool shouldPersist =
        force || _document.path == null || _hasUnsavedChanges;
    if (!shouldPersist) {
      if (showMessage) {
        final String location = _document.path ?? l10n.defaultProjectDirectory;
        _showInfoBar(l10n.noChangesToSave(location));
      }
      return false;
    }
    setState(() => _isAutoSaving = true);
    try {
      final layers = await board.snapshotLayersForExport();
      final preview = await _exporter.exportToPng(
        settings: _document.settings,
        layers: layers,
        maxDimension: 256,
      );
      final ProjectDocument updated = _document.copyWith(
        layers: layers,
        previewBytes: preview,
        perspectiveGuide: board.snapshotPerspectiveGuide(),
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
        final String location = saved.path ?? l10n.defaultProjectDirectory;
        _showInfoBar(
          l10n.projectSaved(location),
          severity: InfoBarSeverity.success,
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _isAutoSaving = false);
        _showInfoBar(
          l10n.projectSaveFailed(error),
          severity: InfoBarSeverity.error,
        );
      }
      return false;
    }
  }

  PaintingToolbarLayoutStyle get _toolbarLayoutStyle {
    switch (_workspaceLayoutPreference) {
      case WorkspaceLayoutPreference.sai2:
        return PaintingToolbarLayoutStyle.sai2;
      case WorkspaceLayoutPreference.csp:
        return PaintingToolbarLayoutStyle.csp;
      case WorkspaceLayoutPreference.floating:
        return PaintingToolbarLayoutStyle.floating;
    }
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
    final l10n = context.l10n;
    if (board == null) {
      _showInfoBar(l10n.canvasNotReadySave, severity: InfoBarSeverity.error);
      return false;
    }

    final _ExportChoice? choice = await _showExportFormatDialog();
    if (choice == null) {
      return false;
    }
    if (kIsWeb) {
      final String? fileName = await _promptWebFileName(
        title: l10n.saveProjectAs,
        suggestedFileName: _suggestedFileName(choice.extension),
        description: l10n.webSaveDesc,
        confirmLabel: l10n.download,
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
    final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    String? normalizedPath;
    if (isMobile) {
      final String? fileName = await showFileNameDialog(
        context: context,
        title: l10n.saveProjectAs,
        suggestedFileName: _suggestedFileName(choice.extension),
        confirmLabel: l10n.save,
      );
      if (fileName == null) {
        return false;
      }
      final String normalizedName = _normalizeExportPath(
        _sanitizeFileName(fileName),
        choice.extension,
      );
      normalizedPath = await MobileExportPaths.resolveExportPath(
        normalizedName,
      );
    } else {
      final String? selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: l10n.saveProjectAs,
        fileName: _suggestedFileName(choice.extension),
        type: FileType.custom,
        allowedExtensions: <String>[choice.extension],
      );
      if (selectedPath == null) {
        return false;
      }
      normalizedPath = _normalizeExportPath(selectedPath, choice.extension);
    }

    setState(() => _isSaving = true);
    try {
      final layers = await board.snapshotLayersForExport();
      final perspective = board.snapshotPerspectiveGuide();
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
          perspectiveGuide: perspective,
        );
        saved = await _repository.saveDocumentAs(updated, normalizedPath);
        successMessage = l10n.projectSaved(normalizedPath);
      } else if (choice.type == _ExportType.psd) {
        await _repository.exportDocumentAsPsd(
          document: _document.copyWith(
            layers: layers,
            previewBytes: preview,
            perspectiveGuide: perspective,
          ),
          path: normalizedPath,
        );
        saved = _document.copyWith(
          layers: layers,
          previewBytes: preview,
          path: _document.path,
          perspectiveGuide: perspective,
        );
        successMessage = l10n.psdExported(normalizedPath);
      } else {
        await _repository.exportDocumentAsSai2(
          document: _document.copyWith(
            layers: layers,
            previewBytes: preview,
            perspectiveGuide: perspective,
          ),
          path: normalizedPath,
        );
        saved = _document.copyWith(
          layers: layers,
          previewBytes: preview,
          path: _document.path,
          perspectiveGuide: perspective,
        );
        successMessage = l10n.sai2Exported(normalizedPath);
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
        _showInfoBar(
          l10n.projectSaveFailed(error),
          severity: InfoBarSeverity.error,
        );
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
    final l10n = context.l10n;
    try {
      final layers = await board.snapshotLayersForExport();
      final perspective = board.snapshotPerspectiveGuide();
      final Uint8List preview = await _exporter.exportToPng(
        settings: _document.settings,
        layers: layers,
        maxDimension: 256,
      );
      late ProjectDocument resolved = _document.copyWith(
        layers: layers,
        previewBytes: preview,
        updatedAt: DateTime.now(),
        perspectiveGuide: perspective,
      );
      late Uint8List bytes;
      late String successMessage;
      late String mimeType;
      if (choice.type == _ExportType.rin) {
        resolved = await _repository.saveDocument(resolved);
        bytes = ProjectBinaryCodec.encode(resolved);
        successMessage = l10n.projectDownloaded(fileName);
        mimeType = 'application/octet-stream';
      } else if (choice.type == _ExportType.psd) {
        bytes = await const PsdExporter().exportToBytes(resolved);
        successMessage = l10n.psdDownloaded(fileName);
        mimeType = 'image/vnd.adobe.photoshop';
      } else {
        bytes = await const Sai2Exporter().exportToBytes(resolved);
        successMessage = l10n.sai2Downloaded(fileName);
        mimeType = 'application/octet-stream';
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
        _showInfoBar(
          l10n.projectSaveFailed(error),
          severity: InfoBarSeverity.error,
        );
      }
      return false;
    }
  }

  Future<_ExportChoice?> _showExportFormatDialog() async {
    final l10n = context.l10n;
    if (isMobileOrPhone(context)) {
      return showMobileBottomSheet<_ExportChoice?>(
        context: context,
        heightFactor: 0.5,
        builder: (BuildContext context) {
          final theme = FluentTheme.of(context);
          Widget buildOptionTitle(String title, [String? description]) {
            final String? trimmed = description?.trim();
            if (trimmed == null || trimmed.isEmpty) {
              return Text(title);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const SizedBox(height: 2),
                Text(trimmed, style: theme.typography.caption),
              ],
            );
          }

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
                      l10n.selectExportFormat,
                      style: theme.typography.subtitle?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.selectSaveFormat,
                      style: theme.typography.caption,
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    ListTile(
                      title: buildOptionTitle(
                        l10n.saveAsPsd,
                        l10n.exportAsPsdTooltip,
                      ),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(const _ExportChoice(_ExportType.psd, 'psd')),
                    ),
                    ListTile(
                      title: buildOptionTitle(
                        l10n.saveAsSai2,
                        l10n.exportAsSai2Tooltip,
                      ),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(const _ExportChoice(_ExportType.sai2, 'sai2')),
                    ),
                    ListTile(
                      title: buildOptionTitle(l10n.saveAsRin),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(const _ExportChoice(_ExportType.rin, 'rin')),
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

    return showDialog<_ExportChoice?>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return ContentDialog(
          title: Text(l10n.selectExportFormat),
          content: Text(l10n.selectSaveFormat),
          actions: [
            Button(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(l10n.cancel),
            ),
            Tooltip(
              message: l10n.exportAsPsdTooltip,
              child: Button(
                onPressed: () => Navigator.of(
                  context,
                ).pop(const _ExportChoice(_ExportType.psd, 'psd')),
                child: Text(l10n.saveAsPsd),
              ),
            ),
            Tooltip(
              message: l10n.exportAsSai2Tooltip,
              child: Button(
                onPressed: () => Navigator.of(
                  context,
                ).pop(const _ExportChoice(_ExportType.sai2, 'sai2')),
                child: Text(l10n.saveAsSai2),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(const _ExportChoice(_ExportType.rin, 'rin')),
              child: Text(l10n.saveAsRin),
            ),
          ],
        );
      },
    );
  }

  Future<_MobileImageExportDestination?>
  _showMobileImageExportDestinationDialog() {
    final l10n = context.l10n;
    if (isMobileOrPhone(context)) {
      return showMobileBottomSheet<_MobileImageExportDestination?>(
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
                      l10n.exportDestinationTitle,
                      style: theme.typography.subtitle?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.exportDestinationDesc,
                      style: theme.typography.caption,
                    ),
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
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(_MobileImageExportDestination.photos),
                    ),
                    ListTile(
                      title: Text(l10n.exportDestinationFiles),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(_MobileImageExportDestination.files),
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
    return showDialog<_MobileImageExportDestination?>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return ContentDialog(
          title: Text(l10n.exportDestinationTitle),
          content: Text(l10n.exportDestinationDesc),
          actions: [
            Button(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(l10n.cancel),
            ),
            Button(
              onPressed: () => Navigator.of(
                context,
              ).pop(_MobileImageExportDestination.files),
              child: Text(l10n.exportDestinationFiles),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(_MobileImageExportDestination.photos),
              child: Text(l10n.exportDestinationPhotos),
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
    final l10n = context.l10n;
    if (board == null) {
      _showInfoBar(l10n.canvasNotReadyExport, severity: InfoBarSeverity.error);
      return false;
    }

    final CanvasExportOptions? options = await showCanvasExportDialog(
      context: context,
      settings: _document.settings,
    );
    if (options == null) {
      return false;
    }
    final bool exportVector = options.mode == CanvasExportMode.vector;
    final bool exportWebp =
        !exportVector && options.bitmapFormat == CanvasBitmapFormat.webp;
    final String extension = exportVector
        ? 'svg'
        : exportWebp
        ? 'webp'
        : 'png';
    String? normalizedPath;
    String? downloadName;
    String? mobileFileName;
    _MobileImageExportDestination? mobileDestination;
    if (kIsWeb) {
      final String? fileName = await _promptWebFileName(
        title: l10n.exportFileTitle(extension.toUpperCase()),
        suggestedFileName: _suggestedFileName(extension),
        description: l10n.webExportDesc,
        confirmLabel: l10n.export,
      );
      if (fileName == null) {
        return false;
      }
      downloadName = _normalizeExportPath(fileName, extension);
    } else if (Platform.isAndroid || Platform.isIOS) {
      if (Platform.isIOS && !exportVector) {
        mobileDestination = await _showMobileImageExportDestinationDialog();
        if (mobileDestination == null) {
          return false;
        }
      } else {
        mobileDestination = _MobileImageExportDestination.files;
      }
      if (mobileDestination == _MobileImageExportDestination.files) {
        final String? fileName = await showFileNameDialog(
          context: context,
          title: l10n.exportFileTitle(extension.toUpperCase()),
          suggestedFileName: _suggestedFileName(extension),
          confirmLabel: l10n.export,
        );
        if (fileName == null) {
          return false;
        }
        mobileFileName = _normalizeExportPath(
          _sanitizeFileName(fileName),
          extension,
        );
        normalizedPath = await MobileExportPaths.resolveExportPath(
          mobileFileName,
        );
      } else {
        mobileFileName = _suggestedFileName(extension);
      }
    } else {
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: l10n.exportFileTitle(extension.toUpperCase()),
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
      final layers = await board.snapshotLayersForExport();
      final Uint8List bytes = exportVector
          ? await _exporter.exportToSvg(
              settings: _document.settings,
              layers: layers,
              maxColors: options.vectorMaxColors ?? 8,
              simplifyEpsilon: options.vectorSimplifyEpsilon ?? 1.2,
            )
          : exportWebp
          ? await _exporter.exportToWebp(
              settings: _document.settings,
              layers: layers,
              applyEdgeSoftening: options.edgeSofteningEnabled,
              edgeSofteningLevel: options.edgeSofteningLevel,
              outputSize: ui.Size(
                options.width.toDouble(),
                options.height.toDouble(),
              ),
              lossless: options.webpLossless,
              quality: options.webpQuality,
            )
          : await _exporter.exportToPng(
              settings: _document.settings,
              layers: layers,
              applyEdgeSoftening: options.edgeSofteningEnabled,
              edgeSofteningLevel: options.edgeSofteningLevel,
              outputSize: ui.Size(
                options.width.toDouble(),
                options.height.toDouble(),
              ),
            );
      if (kIsWeb) {
        await WebFileSaver.saveBytes(
          fileName: downloadName!,
          bytes: bytes,
          mimeType: exportVector
              ? 'image/svg+xml'
              : exportWebp
              ? 'image/webp'
              : 'image/png',
        );
        _showInfoBar(
          l10n.fileDownloaded(extension.toUpperCase(), downloadName!),
          severity: InfoBarSeverity.success,
        );
      } else if (Platform.isIOS &&
          mobileDestination == _MobileImageExportDestination.photos &&
          !exportVector) {
        await IosPhotoSaver.saveImageToPhotos(bytes, fileName: mobileFileName);
        _showInfoBar(
          l10n.imageSavedToPhotos,
          severity: InfoBarSeverity.success,
        );
      } else {
        final file = File(normalizedPath!);
        await file.writeAsBytes(bytes, flush: true);
        _showInfoBar(
          l10n.fileExported(normalizedPath!),
          severity: InfoBarSeverity.success,
        );
      }
      return true;
    } catch (error) {
      _showInfoBar(l10n.exportFailed(error), severity: InfoBarSeverity.error);
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _applyCanvasRotation(CanvasRotation rotation) async {
    final PaintingBoardState? board = _activeBoard;
    if (board == null) {
      _showInfoBar(
        context.l10n.canvasNotReadyTransform,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    final ProjectDocument historySnapshot = _document.copyWith(
      layers: await board.snapshotLayersForExport(),
    );
    final CanvasRotationResult? result = await board.rotateCanvas(rotation);
    if (result == null) {
      _showInfoBar(
        context.l10n.canvasSizeErrorTransform,
        severity: InfoBarSeverity.error,
      );
      return;
    }

    _pushDocumentHistorySnapshot(snapshot: historySnapshot);
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

  Future<void> _applyCanvasFlip(CanvasFlip flip) async {
    final PaintingBoardState? board = _activeBoard;
    if (board == null) {
      _showInfoBar(
        context.l10n.canvasNotReadyTransform,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    final ProjectDocument historySnapshot = _document.copyWith(
      layers: await board.snapshotLayersForExport(),
    );
    final CanvasRotationResult? result = await board.flipCanvas(flip);
    if (result == null) {
      _showInfoBar(
        context.l10n.canvasSizeErrorTransform,
        severity: InfoBarSeverity.error,
      );
      return;
    }

    _pushDocumentHistorySnapshot(snapshot: historySnapshot);
    final DateTime now = DateTime.now();
    final ProjectDocument updated = _document.copyWith(
      updatedAt: now,
      layers: result.layers,
      previewBytes: null,
    );

    _applyDocumentState(updated);
  }

  Future<void> _handleResizeImage() async {
    final PaintingBoardState? board = _activeBoard;
    if (board == null) {
      _showInfoBar(
        context.l10n.canvasNotReadyResizeImage,
        severity: InfoBarSeverity.warning,
      );
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
    debugPrint(
      'canvasPage: resizeImage request '
      'doc=${_document.settings.width.round()}x${_document.settings.height.round()} '
      'target=${config.width}x${config.height} sampling=${config.sampling}',
    );
    final CanvasResizeResult? result = await board.resizeImage(
      config.width,
      config.height,
      config.sampling,
    );
    if (result == null) {
      debugPrint('canvasPage: resizeImage result=null');
      _showInfoBar(
        context.l10n.resizeImageFailed,
        severity: InfoBarSeverity.error,
      );
      return;
    }
    final ProjectDocument historySnapshot = _document.copyWith(
      layers: await board.snapshotLayersForExport(),
    );
    _pushDocumentHistorySnapshot(snapshot: historySnapshot);
    debugPrint(
      'canvasPage: resizeImage result '
      '${result.width}x${result.height} layers=${result.layers.length}',
    );
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
      _showInfoBar(
        context.l10n.canvasNotReadyResizeCanvas,
        severity: InfoBarSeverity.warning,
      );
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
    debugPrint(
      'canvasPage: resizeCanvas request '
      'doc=${_document.settings.width.round()}x${_document.settings.height.round()} '
      'target=${config.width}x${config.height} anchor=${config.anchor}',
    );
    final CanvasResizeResult? result = await board.resizeCanvas(
      config.width,
      config.height,
      config.anchor,
    );
    if (result == null) {
      debugPrint('canvasPage: resizeCanvas result=null');
      _showInfoBar(
        context.l10n.resizeCanvasFailed,
        severity: InfoBarSeverity.error,
      );
      return;
    }
    final ProjectDocument historySnapshot = _document.copyWith(
      layers: await board.snapshotLayersForExport(),
    );
    _pushDocumentHistorySnapshot(snapshot: historySnapshot);
    debugPrint(
      'canvasPage: resizeCanvas result '
      '${result.width}x${result.height} layers=${result.layers.length}',
    );
    _applyCanvasResizeResult(result);
  }

  Future<void> _handleExitRequest() async {
    final l10n = context.l10n;
    final bool canLeave = await _ensureCanLeave(
      dialogTitle: l10n.returnToHome,
      dialogContent: l10n.saveBeforeReturn,
    );
    if (!canLeave) {
      return;
    }
    await _closePage();
  }

  Future<_ExitAction?> _showExitDialog({String? title, String? content}) {
    final l10n = context.l10n;
    return showResponsiveDialog<_ExitAction>(
      context: context,
      barrierDismissible: true,
      builder: (context) => MisarinDialog(
        title: Text(title ?? l10n.returnToHome),
        content: Text(content ?? l10n.saveBeforeReturn),
        contentWidth: 360,
        maxWidth: 480,
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(_ExitAction.cancel),
            child: Text(l10n.cancel),
          ),
          Button(
            onPressed: () => Navigator.of(context).pop(_ExitAction.discard),
            child: Text(l10n.dontSave),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_ExitAction.save),
            child: Text(l10n.save),
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
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    if (!navigator.canPop()) {
      return;
    }
    navigator.popUntil((route) => route.isFirst);
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
      final l10n = context.l10n;
      final bool canLeave = await _ensureCanLeave(
        dialogTitle: l10n.closeCanvas,
        dialogContent: l10n.saveBeforeClose,
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
    final l10n = context.l10n;

    void submit() {
      final String trimmed = controller.text.trim();
      if (trimmed.isEmpty) {
        dialogSetState?.call(() {
          errorText = l10n.nameCannotBeEmpty;
        });
        return;
      }
      Navigator.of(context).pop(trimmed);
    }

    final String? result = await showMisarinDialog<String>(
      context: context,
      title: Text(l10n.renameProject),
      contentWidth: 360,
      content: StatefulBuilder(
        builder: (context, setState) {
          dialogSetState = setState;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.enterNewProjectName),
              const SizedBox(height: 8),
              TextBox(
                controller: controller,
                autofocus: true,
                placeholder: l10n.untitledProject,
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
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: submit, child: Text(l10n.rename)),
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
    _updateMenuOverlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _restoreWorkspaceStateFor(entry.id);
    });
  }

  void _applyCanvasResizeResult(CanvasResizeResult result) {
    debugPrint(
      'canvasPage: applyCanvasResize '
      '${result.width}x${result.height} layers=${result.layers.length}',
    );
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

  Future<void> _handleTabBarFileDrop(List<DropItem> items) async {
    if (!_supportsFileDrops || items.isEmpty) {
      return;
    }
    final List<DropItem> candidates = _filterSupportedDropItems(items);
    if (candidates.isEmpty) {
      _showInfoBar(
        context.l10n.noSupportedImageFormats,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    final String signature = _dropItemsSignature(candidates);
    if (_isHandlingTabBarDrop ||
        _isRecentDuplicateDrop(
          signature,
          previousSignature: _lastTabBarDropSignature,
          previousAt: _lastTabBarDropAt,
        )) {
      return;
    }
    _isHandlingTabBarDrop = true;
    int createdCount = 0;
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
          await openDocument(document);
          createdCount += 1;
        } catch (error) {
          _showInfoBar(
            context.l10n.importFailed(_describeDropItem(item), error),
            severity: InfoBarSeverity.error,
          );
        }
      }
      if (!mounted) {
        return;
      }
      if (createdCount > 0) {
        _showInfoBar(
          createdCount == 1
              ? context.l10n.createdCanvasFromDrop
              : context.l10n.createdCanvasesFromDrop(createdCount),
          severity: InfoBarSeverity.success,
        );
      } else {
        _showInfoBar(
          context.l10n.dropImageCreateFailed,
          severity: InfoBarSeverity.warning,
        );
      }
    } finally {
      _isHandlingTabBarDrop = false;
      _lastTabBarDropSignature = signature;
      _lastTabBarDropAt = DateTime.now();
    }
  }

  Future<void> _handleCanvasFileDrop(List<DropItem> items) async {
    if (!_supportsFileDrops || items.isEmpty) {
      return;
    }
    final PaintingBoardState? board = _activeBoard;
    if (board == null || !board.isBoardReady) {
      _showInfoBar(
        context.l10n.canvasNotReadyDrop,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    final List<DropItem> candidates = _filterSupportedDropItems(items);
    if (candidates.isEmpty) {
      _showInfoBar(
        context.l10n.noSupportedImageFormats,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    final String signature = _dropItemsSignature(candidates);
    if (_isHandlingCanvasDrop ||
        _isRecentDuplicateDrop(
          signature,
          previousSignature: _lastCanvasDropSignature,
          previousAt: _lastCanvasDropAt,
        )) {
      return;
    }
    _isHandlingCanvasDrop = true;
    int insertedCount = 0;
    int? svgRasterSizePx;
    bool svgRasterSizeResolved = false;
    try {
      for (final DropItem item in candidates) {
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
        final Uint8List? bytes = await _readDropItemBytes(item);
        if (bytes == null) {
          continue;
        }
        final bool inserted = await board.insertImageLayerFromBytes(
          bytes,
          name: _preferredLayerNameForDrop(item),
          svgRasterSizePx: itemSvgRasterSizePx,
        );
        if (inserted) {
          insertedCount += 1;
        }
      }
      if (!mounted) {
        return;
      }
      if (insertedCount > 0) {
        _showInfoBar(
          insertedCount == 1
              ? context.l10n.insertedDropImage
              : context.l10n.insertedDropImages(insertedCount),
          severity: InfoBarSeverity.success,
        );
      } else {
        _showInfoBar(
          context.l10n.dropImageInsertFailed,
          severity: InfoBarSeverity.error,
        );
      }
    } finally {
      _isHandlingCanvasDrop = false;
      _lastCanvasDropSignature = signature;
      _lastCanvasDropAt = DateTime.now();
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

  String? _preferredLayerNameForDrop(DropItem item) {
    final String source = item.name.trim().isNotEmpty
        ? item.name.trim()
        : item.path.trim();
    if (source.isEmpty) {
      return null;
    }
    final String base = p.basenameWithoutExtension(source);
    return base.isEmpty ? source : base;
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

  Widget _buildBoard(CanvasWorkspaceEntry entry, {required bool isActive}) {
    final String id = entry.id;
    return PaintingBoard(
      key: _ensureBoardKey(id),
      surfaceKey: id,
      settings: entry.document.settings,
      onRequestExit: _handleExitRequest,
      isActive: isActive,
      onDirtyChanged: (dirty) => _handleDirtyChanged(id, dirty),
      initialLayers: entry.document.layers,
      initialPerspectiveGuide: entry.document.perspectiveGuide,
      onUndoFallback: _undoDocumentChange,
      onRedoFallback: _redoDocumentChange,
      externalCanUndo: _canUndoDocumentFor(id),
      externalCanRedo: _canRedoDocumentFor(id),
      onResizeImage: _handleResizeImage,
      onResizeCanvas: _handleResizeCanvas,
      onReadyChanged: (ready) => _handleBoardReadyChanged(id, ready),
      toolbarLayoutStyle: _toolbarLayoutStyle,
      showToolbars: !isMobileOrPhone(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    // desktop_drop keeps hidden routes listening unless disabled explicitly.
    final bool enableDropTargets =
        _supportsFileDrops && (ModalRoute.of(context)?.isCurrent ?? true);
    final handler = MenuActionHandler(
      newProject: () => AppMenuActions.createProject(context),
      open: () => AppMenuActions.openProjectFromDisk(context),
      closeAll: _handleExitRequest,
      importImage: () => AppMenuActions.importImage(context),
      importImageFromClipboard: () =>
          AppMenuActions.importImageFromClipboard(context),
      preferences: () => AppMenuActions.openSettings(context),
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
      undoEnabled: () {
        final PaintingBoardState? board = _activeBoard;
        return (board?.canUndo ?? false) || _canUndoDocumentFor(_document.id);
      },
      redoEnabled: () {
        final PaintingBoardState? board = _activeBoard;
        return (board?.canRedo ?? false) || _canRedoDocumentFor(_document.id);
      },
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
      cutEnabled: () => _activeBoard?.canCut ?? false,
      copyEnabled: () => _activeBoard?.canCopy ?? false,
      pasteEnabled: () => _activeBoard?.canPaste ?? false,
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
      showSteveReferenceModel: () {
        final board = _activeBoard;
        unawaited(board?.showSteveReferenceModelCard());
      },
      showAlexReferenceModel: () {
        final board = _activeBoard;
        unawaited(board?.showAlexReferenceModelCard());
      },
      showCubeReferenceModel: () {
        final board = _activeBoard;
        unawaited(board?.showCubeReferenceModelCard());
      },
      importReferenceModel: () {
        final board = _activeBoard;
        unawaited(board?.importReferenceModelCard());
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
      toggleViewBlackWhite: () {
        final board = _activeBoard;
        if (board == null) {
          return;
        }
        board.toggleViewBlackWhiteOverlay();
        setState(() {});
      },
      viewBlackWhiteEnabled: _activeBoard?.isViewBlackWhiteEnabled ?? false,
      toggleViewMirror: () {
        final board = _activeBoard;
        if (board == null) {
          return;
        }
        board.toggleViewMirrorOverlay();
        setState(() {});
      },
      viewMirrorEnabled: _activeBoard?.isViewMirrorEnabled ?? false,
      toggleViewTiled: () {
        final board = _activeBoard;
        if (board == null) {
          return;
        }
        board.toggleViewTiledCanvas();
        setState(() {});
      },
      viewTiledEnabled: _activeBoard?.isViewTiledEnabled ?? false,
      togglePerspectiveGuide: () {
        final board = _activeBoard;
        if (board == null) {
          return;
        }
        board.togglePerspectiveGuideVisibility();
        setState(() {});
      },
      setPerspectiveOnePoint: () {
        final board = _activeBoard;
        board?.setPerspectiveGuideMode(PerspectiveGuideMode.onePoint);
        setState(() {});
      },
      setPerspectiveTwoPoint: () {
        final board = _activeBoard;
        board?.setPerspectiveGuideMode(PerspectiveGuideMode.twoPoint);
        setState(() {});
      },
      setPerspectiveThreePoint: () {
        final board = _activeBoard;
        board?.setPerspectiveGuideMode(PerspectiveGuideMode.threePoint);
        setState(() {});
      },
      perspectiveMode:
          _activeBoard?.perspectiveGuideMode ?? PerspectiveGuideMode.off,
      perspectiveVisible: _activeBoard?.isPerspectiveGuideVisible ?? false,
      rotateCanvas90Clockwise: () async {
        await _applyCanvasRotation(CanvasRotation.clockwise90);
      },
      rotateCanvas90CounterClockwise: () async {
        await _applyCanvasRotation(CanvasRotation.counterClockwise90);
      },
      rotateCanvas180Clockwise: () async {
        await _applyCanvasRotation(CanvasRotation.clockwise180);
      },
      rotateCanvas180CounterClockwise: () async {
        await _applyCanvasRotation(CanvasRotation.counterClockwise180);
      },
      flipCanvasHorizontal: () async {
        await _applyCanvasFlip(CanvasFlip.horizontal);
      },
      flipCanvasVertical: () async {
        await _applyCanvasFlip(CanvasFlip.vertical);
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
      removeColorLeak: () {
        final board = _activeBoard;
        if (board == null) {
          _showInfoBar('画布尚未准备好，无法去除漏色。', severity: InfoBarSeverity.warning);
          return;
        }
        board.showLeakRemovalAdjustments();
      },
      resizeImage: _handleResizeImage,
      resizeCanvas: _handleResizeCanvas,
      mergeLayerDown: () {
        final board = _activeBoard;
        board?.mergeActiveLayerDown();
      },
      mergeLayerDownEnabled: () =>
          _activeBoard?.canMergeActiveLayerDown ?? false,
      rasterizeLayer: () async {
        final board = _activeBoard;
        if (board == null) {
          _showInfoBar('画布尚未准备好，无法栅格化图层。', severity: InfoBarSeverity.warning);
          return;
        }
        final bool success = await board.rasterizeActiveTextLayer();
        if (!success) {
          _showInfoBar(
            '当前图层无法栅格化，仅文字图层支持该操作。',
            severity: InfoBarSeverity.warning,
          );
        }
      },
      rasterizeLayerEnabled: () {
        final board = _activeBoard;
        return board?.canRasterizeActiveLayer ?? false;
      },
      binarizeLayer: () {
        final board = _activeBoard;
        if (board == null) {
          _showInfoBar('画布尚未准备好，无法二值化。', severity: InfoBarSeverity.warning);
          return;
        }
        board.showBinarizeAdjustments();
      },
      scanPaperDrawing: () {
        final board = _activeBoard;
        if (board == null) {
          _showInfoBar('画布尚未准备好，无法扫描纸绘。', severity: InfoBarSeverity.warning);
          return;
        }
        board.showScanPaperDrawingAdjustments();
      },
      layerFreeTransform: () {
        final board = _activeBoard;
        board?.toggleLayerFreeTransform();
      },
      selectAll: () {
        final board = _activeBoard;
        board?.selectEntireCanvas();
      },
      clearSelection: () {
        final board = _activeBoard;
        board?.clearSelection();
      },
      invertSelection: () {
        final board = _activeBoard;
        board?.invertSelection();
      },
      selectAllEnabled: () => _activeBoard?.canSelectAll ?? false,
      clearSelectionEnabled: () => _activeBoard?.canClearSelection ?? false,
      invertSelectionEnabled: () => _activeBoard?.canInvertSelection ?? false,
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
      narrowLines: () {
        final board = _activeBoard;
        if (board == null) {
          _showInfoBar('画布尚未准备好，无法收窄线条。', severity: InfoBarSeverity.warning);
          return;
        }
        board.showLineNarrowAdjustments();
      },
      expandFill: () {
        final board = _activeBoard;
        if (board == null) {
          _showInfoBar('画布尚未准备好，无法拉伸填色。', severity: InfoBarSeverity.warning);
          return;
        }
        board.showFillExpandAdjustments();
      },
      adjustBlackWhite: () {
        final board = _activeBoard;
        if (board == null) {
          _showInfoBar('画布尚未准备好，无法调节黑白。', severity: InfoBarSeverity.warning);
          return;
        }
        board.showBlackWhiteAdjustments();
      },
      colorRange: () {
        final board = _activeBoard;
        if (board == null) {
          _showInfoBar('画布尚未准备好，无法设置色彩范围。', severity: InfoBarSeverity.warning);
          return;
        }
        unawaited(board.showColorRangeCard());
      },
      invertColors: () {
        final board = _activeBoard;
        if (board == null) {
          _showInfoBar('画布尚未准备好，无法颜色反转。', severity: InfoBarSeverity.warning);
          return;
        }
        unawaited(board.invertActiveLayerColors());
      },
      workspaceLayoutPreference: _workspaceLayoutPreference,
      switchWorkspaceLayout: _setWorkspaceLayoutPreference,
      resetWorkspaceLayout: () {
        final board = _activeBoard;
        board?.resetWorkspaceLayout();
      },
    );

    Widget titleBar = CanvasTitleBar(
      onSelectTab: _handleTabSelected,
      onCloseTab: _handleTabClosed,
      onCreateTab: () => AppMenuActions.createProject(context),
      onRenameTab: _handleTabRename,
    );

    if (_supportsFileDrops) {
      titleBar = DropTarget(
        enable: enableDropTargets,
        onDragDone: (details) =>
            unawaited(_handleTabBarFileDrop(details.files)),
        child: titleBar,
      );
    }

    Widget workspace = Container(
      color: FluentTheme.of(context).micaBackgroundColor,
      child: AnimatedBuilder(
        animation: _workspace,
        builder: (context, _) {
          final List<CanvasWorkspaceEntry> entries = _workspace.entries;
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
                  child: _buildBoard(entry, isActive: entry.id == _document.id),
                ),
            ],
          );
        },
      ),
    );
    if (_supportsFileDrops) {
      workspace = DropTarget(
        enable: enableDropTargets,
        onDragDone: (details) =>
            unawaited(_handleCanvasFileDrop(details.files)),
        child: workspace,
      );
    }
    final bool isMobile = isMobileOrPhone(context);

    final Widget body = isMobile
        ? SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Column(
                  children: [
                    titleBar,
                    Expanded(child: workspace),
                  ],
                ),
                const Align(
                  alignment: Alignment.topRight,
                  child: MobileMenuButton(),
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: MobileUndoRedoButtons(
                    onUndo: _handleUndo,
                    onRedo: _handleRedo,
                  ),
                ),
              ],
            ),
          )
        : Column(
            children: [
              titleBar,
              Expanded(child: ClipRect(child: workspace)),
            ],
          );

    return MenuActionBinding(
      handler: handler,
      child: NavigationView(
        content: ScaffoldPage(padding: EdgeInsets.zero, content: body),
      ),
    );
  }
}

class _CanvasStatusOverlay extends StatelessWidget {
  const _CanvasStatusOverlay({required this.board});

  final PaintingBoardState? board;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final l10n = context.l10n;
    final bool alignStatusLeft = kIsWeb || !isResolvedPlatformMacOS();

    final TextStyle textStyle =
        (theme.typography.body ??
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w400))
            .copyWith(color: theme.resources.textFillColorSecondary);

    if (board == null) {
      return Text(l10n.canvasNotReady, style: textStyle, maxLines: 1);
    }

    return ValueListenableBuilder<CanvasViewInfo>(
      valueListenable: board!.viewInfoListenable,
      builder: (context, info, _) {
        final String resolution =
            '${info.canvasSize.width.round()} x ${info.canvasSize.height.round()}';
        final double zoomPercent = (info.scale * 100)
            .clamp(-100000.0, 100000.0)
            .toDouble();
        final String zoom = '${zoomPercent.toStringAsFixed(1)}%';
        final CanvasBackend backend = board!.canvasBackend;
        final String backendName = backend == CanvasBackend.rustWgpu
            ? l10n.canvasBackendGpu
            : l10n.canvasBackendCpu;
        final String backendLabel = '${l10n.canvasBackendLabel}: $backendName';
        final String position = info.cursorPosition != null
            ? '${info.cursorPosition!.dx.round()}, ${info.cursorPosition!.dy.round()}'
            : '--';
        final String grid = info.pixelGridVisible ? l10n.on : l10n.off;
        final String blackWhite = info.viewBlackWhiteEnabled
            ? l10n.on
            : l10n.off;
        final String mirror = info.viewMirrorEnabled ? l10n.on : l10n.off;
        final String tile = info.viewTiledEnabled ? l10n.on : l10n.off;
        final String perspective = (() {
          final PerspectiveGuideMode mode = info.perspectiveMode;
          if (!info.perspectiveEnabled || mode == PerspectiveGuideMode.off) {
            return l10n.off;
          }
          switch (mode) {
            case PerspectiveGuideMode.onePoint:
              return l10n.perspective1Point;
            case PerspectiveGuideMode.twoPoint:
              return l10n.perspective2Point;
            case PerspectiveGuideMode.threePoint:
              return l10n.perspective3Point;
            case PerspectiveGuideMode.off:
              return l10n.off;
          }
        })();
        final List<String> parts = <String>[
          l10n.resolutionLabel(resolution),
          backendLabel,
          l10n.zoomLabel(zoom),
          l10n.positionLabel(position),
          l10n.gridLabel(grid),
          l10n.blackWhiteLabel(blackWhite),
          l10n.mirrorLabel(mirror),
          l10n.tileLabel(tile),
          l10n.perspectiveLabel(perspective),
        ];
        final TextAlign textAlign = alignStatusLeft
            ? TextAlign.start
            : TextAlign.center;
        return Text(
          parts.join(' | '),
          style: textStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        );
      },
    );
  }
}

enum _ExportType { rin, psd, sai2 }

enum _MobileImageExportDestination { photos, files }

class _ExportChoice {
  const _ExportChoice(this.type, this.extension);

  final _ExportType type;
  final String extension;
}

enum _ExitAction { save, discard, cancel }
