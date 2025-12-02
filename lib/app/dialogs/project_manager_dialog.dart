import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../project/project_repository.dart';
import '../utils/file_manager.dart';
import '../widgets/project_preview_thumbnail.dart';
import 'misarin_dialog.dart';

Future<void> showProjectManagerDialog(BuildContext context) {
  return showMisarinDialog<void>(
    context: context,
    title: const Text('项目管理'),
    content: const _ProjectManagerContent(),
    contentWidth: 540,
    maxWidth: 640,
    actions: [
      Button(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
    ],
  );
}

class _ProjectManagerContent extends StatefulWidget {
  const _ProjectManagerContent();

  @override
  State<_ProjectManagerContent> createState() => _ProjectManagerContentState();
}

class _ProjectManagerContentState extends State<_ProjectManagerContent> {
  final List<StoredProjectInfo> _projects = <StoredProjectInfo>[];
  final Set<String> _selected = <String>{};

  StreamSubscription<StoredProjectInfo>? _subscription;

  bool _selectAll = false;
  bool _deleting = false;
  bool _revealing = false;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _subscription?.cancel();
    setState(() {
      _projects.clear();
      _selected.clear();
      _selectAll = false;
      _deleting = false;
      _revealing = false;
      _loading = true;
      _errorMessage = null;
    });
    final Stream<StoredProjectInfo> stream = ProjectRepository.instance
        .streamStoredProjects();
    _subscription = stream.listen(
      (StoredProjectInfo info) {
        if (!mounted) {
          return;
        }
        setState(() {
          final int insertIndex = _projects.indexWhere(
            (existing) => existing.lastModified.isBefore(info.lastModified),
          );
          if (insertIndex < 0) {
            _projects.add(info);
          } else {
            _projects.insert(insertIndex, info);
          }
          if (_selectAll) {
            _selected.add(info.path);
          }
        });
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorMessage = '加载失败：$error';
          _loading = false;
        });
      },
      onDone: () {
        if (!mounted) {
          return;
        }
        setState(() {
          _loading = false;
        });
      },
      cancelOnError: true,
    );
  }

  void _toggleSelectAll(bool value) {
    setState(() {
      _selectAll = value;
      _selected.clear();
      if (_selectAll) {
        _selected.addAll(_projects.map((p) => p.path));
      }
    });
  }

  void _toggleSelection(String path, bool value) {
    setState(() {
      if (value) {
        _selected.add(path);
      } else {
        _selected.remove(path);
      }
      _selectAll = _projects.isNotEmpty && _selected.length == _projects.length;
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) {
      return;
    }
    setState(() {
      _deleting = true;
      _errorMessage = null;
    });
    final List<String> targets = List<String>.from(_selected);
    try {
      for (final String path in targets) {
        await ProjectRepository.instance.deleteProject(path);
      }
    } catch (error) {
      _errorMessage = '删除失败：$error';
    }
    if (!mounted) {
      return;
    }
    _subscribe();
  }

  Future<void> _revealSelected() async {
    if (_selected.isEmpty || _revealing) {
      return;
    }
    final String? target = _firstSelectedPath();
    if (target == null) {
      return;
    }
    setState(() {
      _revealing = true;
    });
    try {
      await revealInFileManager(target);
    } finally {
      if (mounted) {
        setState(() {
          _revealing = false;
        });
      }
    }
  }

  String? _firstSelectedPath() {
    for (final StoredProjectInfo info in _projects) {
      if (_selected.contains(info.path)) {
        return info.path;
      }
    }
    return _selected.isEmpty ? null : _selected.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final bool hasSelection = _selected.isNotEmpty;
    final int totalSelected = _selected.length;
    final int totalCount = _projects.length;

    if (_projects.isEmpty) {
      if (_loading) {
        return const SizedBox(
          height: 320,
          child: Center(child: ProgressRing()),
        );
      }
      return SizedBox(
        height: 320,
        child: Center(
          child: Text(
            _errorMessage ?? '暂无自动保存的项目',
            style: theme.typography.bodyLarge,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              checked: _selectAll,
              onChanged: (value) => _toggleSelectAll(value ?? false),
            ),
            Text('全选', style: theme.typography.bodyStrong),
            const Spacer(),
            Tooltip(
              message: '打开所选项目所在文件夹',
              child: Button(
                onPressed: !_revealing && hasSelection
                    ? () => _revealSelected()
                    : null,
                child: _revealing
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: ProgressRing(strokeWidth: 2.0),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(FluentIcons.open_file),
                          SizedBox(width: 6),
                          Text('打开文件夹'),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: '删除所选项目',
              child: FilledButton(
                onPressed: !_deleting && hasSelection ? _deleteSelected : null,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.isDisabled ? null : Colors.red,
                  ),
                ),
                child: _deleting
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: ProgressRing(strokeWidth: 2.0),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FluentIcons.delete),
                          const SizedBox(width: 6),
                          Text('删除所选 ($totalSelected)'),
                        ],
                      ),
              ),
            ),
          ],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          InfoBar(
            severity: InfoBarSeverity.error,
            title: Text(_errorMessage!),
            action: IconButton(
              icon: const Icon(FluentIcons.clear),
              onPressed: () => setState(() => _errorMessage = null),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: Stack(
            children: [
              ListView.separated(
                itemBuilder: (context, index) {
                  final StoredProjectInfo info = _projects[index];
                  final bool selected = _selected.contains(info.path);
                  return ListTile.selectable(
                    key: ValueKey(info.path),
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          checked: selected,
                          onChanged: (value) =>
                              _toggleSelection(info.path, value ?? false),
                        ),
                        const SizedBox(width: 12),
                        ProjectPreviewThumbnail(
                          bytes: info.summary?.previewBytes,
                          width: 96,
                          height: 72,
                        ),
                      ],
                    ),
                    onPressed: () => _toggleSelection(info.path, !selected),
                    title: Text(
                      info.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(info.fileName, style: theme.typography.caption),
                        Text(
                          '大小：${_formatFileSize(info.fileSize)} · 更新：${_formatDate(info.lastModified)}',
                          style: theme.typography.caption,
                        ),
                        if (info.summary != null)
                          Text(
                            '画布 ${info.summary!.settings.width.toInt()} x ${info.summary!.settings.height.toInt()}',
                            style: theme.typography.caption,
                          ),
                      ],
                    ),
                    selected: selected,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tileColor: WidgetStateProperty.resolveWith(
                      (states) => states.isHovered || selected
                          ? theme.resources.subtleFillColorSecondary
                          : theme.resources.subtleFillColorTertiary,
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: totalCount,
              ),
              if (_loading)
                const Positioned(
                  right: 12,
                  top: 12,
                  child: ProgressRing(strokeWidth: 2.5),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatFileSize(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const List<String> units = ['B', 'KB', 'MB', 'GB'];
  double value = bytes.toDouble();
  int unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return '${value.toStringAsFixed(value >= 10 || value < 1 ? 1 : 2)} ${units[unitIndex]}';
}

String _formatDate(DateTime dateTime) {
  final DateTime local = dateTime.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
