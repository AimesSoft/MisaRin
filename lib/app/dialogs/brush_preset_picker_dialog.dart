import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:misa_rin/mobile/responsive_dialog.dart';
import 'package:misa_rin/mobile/mobile_bottom_sheet.dart';
import 'package:misa_rin/mobile/mobile_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../brushes/brush_library.dart';
import '../../brushes/brush_preset.dart';
import '../debug/brush_preset_timeline.dart';
import '../l10n/l10n.dart';
import '../utils/file_name_dialog.dart';
import '../utils/mobile_export_paths.dart';
import '../widgets/app_notification.dart';
import '../widgets/brush_preset_stroke_preview.dart';
import 'misarin_dialog.dart';
import 'brush_preset_editor_dialog.dart';
import 'package:misa_rin/utils/io_shim.dart';

const bool _kBrushPresetEditLog = bool.fromEnvironment(
  'MISA_RIN_BRUSH_PREVIEW_LOG',
  defaultValue: false,
);

Future<String?> showBrushPresetPickerDialog(
  BuildContext context, {
  required BrushLibrary library,
  required String selectedId,
}) {
  return showResponsiveDialog<String>(
    context: context,
    builder: (_) =>
        _BrushPresetPickerDialog(library: library, selectedId: selectedId),
  );
}

class _BrushPresetPickerDialog extends StatefulWidget {
  const _BrushPresetPickerDialog({
    required this.library,
    required this.selectedId,
  });

  final BrushLibrary library;
  final String selectedId;

  @override
  State<_BrushPresetPickerDialog> createState() =>
      _BrushPresetPickerDialogState();
}

class _BrushPresetPickerDialogState extends State<_BrushPresetPickerDialog> {
  late final ScrollController _scrollController;
  late List<BrushPreset> _presets;
  late String _selectedId;
  Set<String> _selectedIds = <String>{};
  String? _selectionAnchorId;
  BrushPreset? _draftPreset;
  int _editorResetToken = 0;
  DateTime? _lastTapAt;
  String? _lastTapId;

  static const Duration _doubleTapThreshold = Duration(milliseconds: 260);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _presets = widget.library.presets;
    _selectedId = _resolveSelectedId(widget.selectedId, _presets);
    _selectedIds = _selectedId.isEmpty ? <String>{} : <String>{_selectedId};
    _selectionAnchorId = _selectedId.isEmpty ? null : _selectedId;
    _syncDraftWithSelection();
    widget.library.addListener(_handleLibraryChanged);
    _refreshShapes();
  }

  @override
  void dispose() {
    widget.library.removeListener(_handleLibraryChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleLibraryChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _presets = widget.library.presets;
      _selectedId = _resolveSelectedId(_selectedId, _presets);
      final Set<String> availableIds = _presets
          .map((BrushPreset preset) => preset.id)
          .toSet();
      _selectedIds.removeWhere((String id) => !availableIds.contains(id));
      if (_selectedIds.isEmpty && _selectedId.isNotEmpty) {
        _selectedIds = <String>{_selectedId};
      } else if (_selectedIds.isNotEmpty &&
          !_selectedIds.contains(_selectedId)) {
        _selectedId = _resolveSelectedId(_selectedIds.first, _presets);
      }
      if (_selectionAnchorId == null ||
          !availableIds.contains(_selectionAnchorId)) {
        _selectionAnchorId = _selectedId.isEmpty ? null : _selectedId;
      }
      _syncDraftWithSelection();
    });
  }

  void _refreshShapes() {
    widget.library.shapeLibrary.refresh().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  void _ensureSelectionState() {
    final Set<String> availableIds = _presets
        .map((BrushPreset preset) => preset.id)
        .toSet();
    _selectedIds.removeWhere((String id) => !availableIds.contains(id));
    if (_selectedIds.isEmpty && _selectedId.isNotEmpty) {
      _selectedIds = <String>{_selectedId};
    }
    if (_selectionAnchorId == null ||
        !availableIds.contains(_selectionAnchorId)) {
      _selectionAnchorId = _selectedId.isEmpty ? null : _selectedId;
    }
  }

  String _resolveSelectedId(String desired, List<BrushPreset> presets) {
    if (presets.any((preset) => preset.id == desired)) {
      return desired;
    }
    return presets.isNotEmpty ? presets.first.id : '';
  }

  BrushPreset? get _selectedPreset {
    if (_presets.isEmpty) {
      return null;
    }
    for (final BrushPreset preset in _presets) {
      if (preset.id == _selectedId) {
        return preset;
      }
    }
    return _presets.first;
  }

  BrushPreset? _presetForId(String id) {
    for (final BrushPreset preset in _presets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  void _syncDraftWithSelection([String? id]) {
    final BrushPreset? preset = _presetForId(id ?? _selectedId);
    _draftPreset = preset?.sanitized();
  }

  void _selectPreset(String id) {
    if (_selectedId == id &&
        _selectedIds.length == 1 &&
        _selectedIds.contains(id)) {
      return;
    }
    BrushPresetTimeline.start('select_preset id=$id');
    setState(() {
      _selectedId = id;
      _selectedIds = <String>{id};
      _selectionAnchorId = id;
      _syncDraftWithSelection(id);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BrushPresetTimeline.mark('frame_painted id=$id');
    });
  }

  bool _isShiftPressed() {
    final Set<LogicalKeyboardKey> keys =
        HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  List<String> _rangeSelectionIds(String fromId, String toId) {
    final int fromIndex = _presets.indexWhere(
      (BrushPreset p) => p.id == fromId,
    );
    final int toIndex = _presets.indexWhere((BrushPreset p) => p.id == toId);
    if (fromIndex < 0 || toIndex < 0) {
      return <String>[toId];
    }
    int start = fromIndex;
    int end = toIndex;
    if (start > end) {
      final int temp = start;
      start = end;
      end = temp;
    }
    return _presets
        .sublist(start, end + 1)
        .map((BrushPreset preset) => preset.id)
        .toList();
  }

  void _handlePresetTap(String id) {
    final bool shiftPressed = _isShiftPressed();
    BrushPresetTimeline.mark('tap_pressed id=$id shift=$shiftPressed');
    final DateTime now = DateTime.now();
    final bool isDoubleTap =
        _lastTapId == id &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) <= _doubleTapThreshold;
    _lastTapId = id;
    _lastTapAt = now;
    if (shiftPressed && _selectionAnchorId != null) {
      final List<String> range = _rangeSelectionIds(_selectionAnchorId!, id);
      setState(() {
        _selectedId = id;
        _selectedIds = range.toSet();
        _syncDraftWithSelection(id);
      });
    } else {
      _selectPreset(id);
    }
    if (isDoubleTap && !shiftPressed) {
      _confirm();
    }
  }

  void _handleDraftChanged(BrushPreset preset) {
    if (!mounted) {
      return;
    }
    if (preset.id != _selectedId) {
      return;
    }
    if (_kBrushPresetEditLog) {
      debugPrint(
        '[brush-picker] draft id=${preset.id} '
        'aa=${preset.antialiasLevel} snap=${preset.snapToPixel}',
      );
    }
    setState(() => _draftPreset = preset.sanitized());
  }

  void _saveDraft() {
    final BrushPreset? updated = _draftPreset ?? _selectedPreset;
    if (updated == null) {
      return;
    }
    widget.library.updatePreset(updated);
    setState(() {
      _selectedId = updated.id;
      _selectedIds = <String>{updated.id};
      _selectionAnchorId = updated.id;
      _draftPreset = updated.sanitized();
    });
  }

  Future<void> _deleteSelected() async {
    if (_presets.length <= 1) {
      return;
    }
    final List<String> orderedSelected = _presets
        .where(
          (BrushPreset preset) =>
              _selectedIds.contains(preset.id) &&
              !widget.library.isBuiltInPreset(preset.id),
        )
        .map((BrushPreset preset) => preset.id)
        .toList();
    if (orderedSelected.isEmpty) {
      return;
    }
    int remainingRemovalsBudget = _presets.length - 1;
    for (final String id in orderedSelected) {
      if (remainingRemovalsBudget <= 0) {
        break;
      }
      await widget.library.removePreset(id);
      remainingRemovalsBudget -= 1;
    }
  }

  Future<void> _resetSelectedToDefault() async {
    final BrushPreset? preset = _selectedPreset;
    if (preset == null) {
      return;
    }
    await widget.library.resetPreset(preset.id);
    setState(() {
      _selectedId = preset.id;
      _selectedIds = <String>{preset.id};
      _selectionAnchorId = preset.id;
      _draftPreset = widget.library.selectedPreset.sanitized();
      _editorResetToken += 1;
    });
  }

  Future<void> _duplicateSelected() async {
    final BrushPreset? preset = _selectedPreset;
    if (preset == null) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final String displayName = _displayNameFor(preset);
    final String baseName = l10n.layerCopyName(displayName);
    final String name = _uniqueName(baseName);
    final String id = _uniqueId('${preset.id}_copy');
    final BrushPreset copy = BrushPreset(
      id: id,
      name: name,
      shape: preset.shape,
      spacing: preset.spacing,
      hardness: preset.hardness,
      flow: preset.flow,
      scatter: preset.scatter,
      randomRotation: preset.randomRotation,
      smoothRotation: preset.smoothRotation,
      rotationJitter: preset.rotationJitter,
      antialiasLevel: preset.antialiasLevel,
      hollowEnabled: preset.hollowEnabled,
      hollowRatio: preset.hollowRatio,
      hollowEraseOccludedParts: preset.hollowEraseOccludedParts,
      autoSharpTaper: preset.autoSharpTaper,
      snapToPixel: preset.snapToPixel,
      screentoneEnabled: preset.screentoneEnabled,
      screentoneSpacing: preset.screentoneSpacing,
      screentoneDotSize: preset.screentoneDotSize,
      screentoneRotation: preset.screentoneRotation,
      screentoneSoftness: preset.screentoneSoftness,
      screentoneShape: preset.screentoneShape,
      author: preset.author,
      version: preset.version,
      shapeId: preset.shapeId,
    );
    await widget.library.addPreset(copy);
    setState(() {
      _selectedId = id;
      _selectedIds = <String>{id};
      _selectionAnchorId = id;
      _syncDraftWithSelection(id);
    });
    _scrollToId(id);
  }

  String _uniqueId(String base) {
    final Set<String> ids = _presets.map((preset) => preset.id).toSet();
    if (!ids.contains(base)) {
      return base;
    }
    int counter = 2;
    while (ids.contains('${base}_$counter')) {
      counter += 1;
    }
    return '${base}_$counter';
  }

  String _uniqueName(String base) {
    final Set<String> names = _presets
        .map((preset) => _displayNameFor(preset))
        .toSet();
    if (!names.contains(base)) {
      return base;
    }
    int counter = 2;
    while (names.contains('$base $counter')) {
      counter += 1;
    }
    return '$base $counter';
  }

  String _displayNameFor(BrushPreset preset) {
    return widget.library.displayNameFor(
      preset,
      Localizations.localeOf(context),
    );
  }

  void _scrollToId(String id) {
    if (!_scrollController.hasClients) {
      return;
    }
    final int index = _presets.indexWhere((preset) => preset.id == id);
    if (index < 0) {
      return;
    }
    _scrollController.animateTo(
      math.min(
        _scrollController.position.maxScrollExtent,
        index * _listItemExtent,
      ),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _confirm() async {
    if (_selectedId.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final bool ok = await _promptSaveIfNeeded();
    if (!ok) {
      return;
    }
    Navigator.of(context).pop(_selectedId);
  }

  bool _hasUnsavedChanges() {
    final BrushPreset? selected = _selectedPreset;
    final BrushPreset? draft = _draftPreset;
    if (selected == null || draft == null) {
      return false;
    }
    return !draft.isSameAs(selected);
  }

  Future<bool> _promptSaveIfNeeded() async {
    if (!_hasUnsavedChanges()) {
      return true;
    }
    final AppLocalizations l10n = context.l10n;
    final bool? shouldSave = await showMisarinDialog<bool>(
      context: context,
      title: Text(l10n.brushPreset),
      content: Text(l10n.unsavedBrushChangesPrompt),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.discardChanges),
        ),
        Button(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.save),
        ),
      ],
    );
    if (shouldSave == null) {
      return false;
    }
    if (shouldSave) {
      _saveDraft();
    }
    return true;
  }

  Future<void> _importBrush() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        BrushLibrary.brushFileExtension,
        BrushLibrary.abrFileExtension,
      ],
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    BrushPreset? imported;
    if (kIsWeb) {
      final Uint8List? bytes = result.files.single.bytes;
      if (bytes == null) {
        return;
      }
      imported = await widget.library.importBrushBytes(bytes);
    } else {
      final String? path = result.files.single.path;
      if (path == null) {
        return;
      }
      imported = await widget.library.importBrushFile(path);
    }
    if (imported == null) {
      return;
    }
    setState(() {
      _selectedId = imported!.id;
      _selectedIds = <String>{imported.id};
      _selectionAnchorId = imported.id;
      _syncDraftWithSelection(imported.id);
    });
    _scrollToId(imported.id);
  }

  Future<void> _exportBrush() async {
    final BrushPreset? preset = _selectedPreset;
    if (preset == null) {
      return;
    }
    final l10n = context.l10n;
    final String displayName = _displayNameFor(preset);
    final String fileBase = displayName.trim().isEmpty
        ? preset.id
        : displayName.trim();
    String sanitizeFileName(String value) {
      final String sanitized =
          value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      return sanitized.isEmpty ? preset.id : sanitized;
    }

    String ensureExtension(String value) {
      final String lower = value.toLowerCase();
      final String suffix = '.${BrushLibrary.brushFileExtension}';
      return lower.endsWith(suffix) ? value : '$value$suffix';
    }

    String? outputPath;
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final String? fileName = await showFileNameDialog(
        context: context,
        title: l10n.exportBrushTitle,
        suggestedFileName: '$fileBase.${BrushLibrary.brushFileExtension}',
        confirmLabel: l10n.export,
      );
      if (fileName == null) {
        return;
      }
      final String normalizedName =
          ensureExtension(sanitizeFileName(fileName));
      outputPath = await MobileExportPaths.resolveExportPath(normalizedName);
    } else {
      final String? selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: l10n.exportBrushTitle,
        fileName: '$fileBase.${BrushLibrary.brushFileExtension}',
        type: FileType.custom,
        allowedExtensions: [BrushLibrary.brushFileExtension],
      );
      if (selectedPath == null) {
        return;
      }
      outputPath = ensureExtension(selectedPath);
    }

    try {
      final bool success =
          await widget.library.exportBrush(preset.id, outputPath!);
      if (!mounted) {
        return;
      }
      if (success) {
        AppNotifications.show(
          context,
          message: l10n.fileExported(outputPath!),
          severity: InfoBarSeverity.success,
        );
      } else {
        AppNotifications.show(
          context,
          message: l10n.exportFailed(l10n.exportBrushTitle),
          severity: InfoBarSeverity.error,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: l10n.exportFailed(error),
        severity: InfoBarSeverity.error,
      );
    }
  }

  static const double _listItemExtent = 56;

  Future<void> _showMobilePresetEditorSheet() async {
    final BrushPreset? initialSelected = _selectedPreset;
    if (initialSelected == null) {
      return;
    }
    BrushPreset? localDraft =
        (_draftPreset != null && _draftPreset?.id == initialSelected.id)
            ? _draftPreset
            : initialSelected.sanitized();

    await showMobileBottomSheet<void>(
      context: context,
      builder: (context) {
        final FluentThemeData theme = FluentTheme.of(context);
        final AppLocalizations l10n = context.l10n;
        return StatefulBuilder(
          builder: (context, setState) {
            final BrushPreset? selected = _selectedPreset ?? initialSelected;
            final BrushPreset? previewPreset =
                (localDraft != null && localDraft?.id == selected?.id)
                    ? localDraft
                    : selected;
            final bool isBuiltInPreset =
                selected != null && widget.library.isBuiltInPreset(selected.id);
            final bool canDelete =
                selected != null && !isBuiltInPreset && _presets.length > 1;

            Widget buildPreviewArea() {
              return Container(
                decoration: BoxDecoration(
                  color: theme.resources.controlFillColorSecondary,
                  border: Border.all(color: theme.resources.controlStrokeColorDefault),
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.all(12),
                child: previewPreset == null
                    ? Center(child: Text('--', style: theme.typography.caption))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BrushPresetStrokePreview(
                            preset: previewPreset,
                            height: 120,
                            color: theme.resources.textFillColorPrimary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.brushPresetDesc,
                            style: theme.typography.caption,
                          ),
                        ],
                      ),
              );
            }

            Widget buildActionsWrap() {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Button(
                    onPressed: selected == null
                        ? null
                        : () async {
                            await _resetSelectedToDefault();
                            setState(() => localDraft = _draftPreset);
                          },
                    child: Text(l10n.reset),
                  ),
                  if (!isBuiltInPreset)
                    Button(
                      onPressed: canDelete
                          ? () async {
                              await _deleteSelected();
                              setState(() => localDraft = _draftPreset);
                            }
                          : null,
                      child: Text(l10n.delete),
                    ),
                  Button(
                    onPressed: selected == null
                        ? null
                        : () async {
                            await _duplicateSelected();
                            setState(() => localDraft = _draftPreset);
                          },
                    child: Text(l10n.duplicate),
                  ),
                  Button(
                    onPressed: _importBrush,
                    child: Text(l10n.importBrush),
                  ),
                  Button(
                    onPressed: selected == null
                        ? null
                        : () async {
                            await _exportBrush();
                          },
                    child: Text(l10n.exportBrush),
                  ),
                  FilledButton(
                    onPressed: selected == null
                        ? null
                        : () {
                            _saveDraft();
                            setState(() => localDraft = _draftPreset);
                          },
                    child: Text(l10n.save),
                  ),
                ],
              );
            }

            final Widget editorContent = selected == null
                ? Text('--', style: theme.typography.caption)
                : BrushPresetEditorForm(
                    key: ValueKey<String?>('${selected?.id}-${_editorResetToken}'),
                    preset: previewPreset ?? selected,
                    scrollable: false,
                    onChanged: (preset) {
                      setState(() => localDraft = preset.sanitized());
                      _handleDraftChanged(preset);
                    },
                  );

            final Widget editorBody = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.editBrushPreset, style: theme.typography.caption),
                const SizedBox(height: 4),
                Text(l10n.editBrushPresetDesc, style: theme.typography.caption),
                const SizedBox(height: 8),
                editorContent,
              ],
            );

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected == null ? '--' : _displayNameFor(selected),
                          style: theme.typography.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        buildActionsWrap(),
                        const SizedBox(height: 12),
                        buildPreviewArea(),
                        const SizedBox(height: 12),
                        editorBody,
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureSelectionState();
    final Stopwatch? buildTimer = BrushPresetTimeline.enabled
        ? (Stopwatch()..start())
        : null;
    final FluentThemeData theme = FluentTheme.of(context);
    final AppLocalizations l10n = context.l10n;
    final BrushPreset? selected = _selectedPreset;
    final BrushPreset? previewPreset =
        (_draftPreset != null && _draftPreset?.id == selected?.id)
        ? _draftPreset
        : selected;
    final int deletableSelectedCount = _selectedIds.where((String id) {
      return !widget.library.isBuiltInPreset(id);
    }).length;
    final bool canDelete = deletableSelectedCount > 0 && _presets.length > 1;
    final Color selectedBackground = theme.accentColor.defaultBrushFor(
      theme.brightness,
    );
    final Color selectedForeground =
        theme.resources.textOnAccentFillColorPrimary;
    final bool isMobile = isMobileOrPhone(context);

    final Widget presetList = Container(
      decoration: BoxDecoration(
        color: theme.resources.controlFillColorDefault,
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
        borderRadius: BorderRadius.circular(6),
      ),
      child: _presets.isEmpty
          ? Center(
              child: Text(
                '--',
                style: theme.typography.caption,
                textAlign: TextAlign.center,
              ),
            )
          : Scrollbar(
              controller: _scrollController,
              child: ListView.builder(
                controller: _scrollController,
                itemExtent: _listItemExtent,
                itemCount: _presets.length,
                itemBuilder: (context, index) {
                  final BrushPreset preset = _presets[index];
                  final bool isSelected = _selectedIds.contains(preset.id);
                  final String displayName = _displayNameFor(preset);
                  final Color foreground = isSelected
                      ? selectedForeground
                      : theme.typography.body?.color ??
                            theme.resources.textFillColorPrimary;
                  return Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) {
                      BrushPresetTimeline.mark('tap_down id=${preset.id}');
                    },
                    onPointerUp: (_) {
                      BrushPresetTimeline.mark('tap_up id=${preset.id}');
                    },
                    child: Button(
                      style: ButtonStyle(
                        padding: WidgetStateProperty.all<EdgeInsets>(
                          const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        backgroundColor:
                            WidgetStateProperty.resolveWith<Color?>((states) {
                              if (isSelected) {
                                return selectedBackground;
                              }
                              if (states.contains(WidgetState.hovered)) {
                                return theme
                                    .resources
                                    .controlFillColorSecondary;
                              }
                              return Colors.transparent;
                            }),
                      ),
                      onPressed: () => _handlePresetTap(preset.id),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: BrushPresetStrokePreview(
                              preset: preset,
                              height: 24,
                              color: foreground,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.typography.body?.copyWith(
                                color: foreground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );

    final Widget previewArea = Container(
      decoration: BoxDecoration(
        color: theme.resources.controlFillColorSecondary,
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(12),
      child: previewPreset == null
          ? Center(child: Text('--', style: theme.typography.caption))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrushPresetStrokePreview(
                  preset: previewPreset,
                  height: 120,
                  color: theme.resources.textFillColorPrimary,
                ),
                const SizedBox(height: 12),
                Text(l10n.brushPresetDesc, style: theme.typography.caption),
              ],
            ),
    );

    final Widget actionsRow = Row(
      children: [
        Button(
          onPressed: selected == null ? null : _resetSelectedToDefault,
          child: Text(l10n.reset),
        ),
        const SizedBox(width: 8),
        Button(
          onPressed: canDelete ? _deleteSelected : null,
          child: Text(l10n.delete),
        ),
        const SizedBox(width: 8),
        Button(
          onPressed: selected == null ? null : _duplicateSelected,
          child: Text(l10n.duplicate),
        ),
        const SizedBox(width: 8),
        Button(onPressed: _importBrush, child: Text(l10n.importBrush)),
        const SizedBox(width: 8),
        Button(
          onPressed: selected == null ? null : _exportBrush,
          child: Text(l10n.exportBrush),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: selected == null ? null : _saveDraft,
          child: Text(l10n.save),
        ),
      ],
    );

    final Widget editorContent = selected == null
        ? Text('--', style: theme.typography.caption)
        : BrushPresetEditorForm(
            key: ValueKey<String>('${selected.id}-$_editorResetToken'),
            preset: previewPreset ?? selected,
            scrollable: false,
            onChanged: _handleDraftChanged,
          );

    final Widget editorBody = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.editBrushPreset, style: theme.typography.caption),
          const SizedBox(height: 4),
          Text(l10n.editBrushPresetDesc, style: theme.typography.caption),
          const SizedBox(height: 8),
          editorContent,
        ],
      ),
    );

    final Widget desktopContent = SizedBox(
      width: 820,
      height: 560,
      child: Row(
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.brushPreset,
                    style: theme.typography.caption,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: presetList),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected == null ? '--' : _displayNameFor(selected),
                  style: theme.typography.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                actionsRow,
                const SizedBox(height: 12),
                previewArea,
                const SizedBox(height: 12),
                Expanded(child: editorBody),
              ],
            ),
          ),
        ],
      ),
    );

    final Widget mobileContent = SizedBox(
      width: double.infinity,
      height: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.brushPreset,
              style: theme.typography.caption,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: presetList),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: selected == null ? null : _showMobilePresetEditorSheet,
            child: Text(l10n.editBrushPreset),
          ),
        ],
      ),
    );

    final Widget dialog = ContentDialog(
      title: Text(l10n.brushPreset),
      constraints: const BoxConstraints(maxWidth: 860),
      content: isMobile ? mobileContent : desktopContent,
      actions: [
        Button(
          onPressed: () async {
            final bool ok = await _promptSaveIfNeeded();
            if (!ok) {
              return;
            }
            if (!mounted) {
              return;
            }
            Navigator.of(context).pop();
          },
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _confirm, child: Text(l10n.confirm)),
      ],
    );
    if (buildTimer != null) {
      final int elapsedMs = buildTimer.elapsedMilliseconds;
      if (elapsedMs > 8) {
        BrushPresetTimeline.mark('dialog_build t=${elapsedMs}ms');
      }
    }
    return dialog;
  }
}
