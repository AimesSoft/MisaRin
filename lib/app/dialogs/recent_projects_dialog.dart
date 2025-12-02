import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../project/project_document.dart';
import '../project/project_repository.dart';
import '../widgets/project_preview_thumbnail.dart';
import 'misarin_dialog.dart';
import '../utils/file_manager.dart';

Future<ProjectSummary?> showRecentProjectsDialog(BuildContext context) {
  return showDialog<ProjectSummary>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _RecentProjectsDialog(),
  );
}

class _RecentProjectsDialog extends StatefulWidget {
  const _RecentProjectsDialog();

  @override
  State<_RecentProjectsDialog> createState() => _RecentProjectsDialogState();
}

class _RecentProjectsDialogState extends State<_RecentProjectsDialog> {
  final List<ProjectSummary> _projects = <ProjectSummary>[];
  StreamSubscription<ProjectSummary>? _subscription;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _startLoading() {
    _subscription?.cancel();
    _subscription = null;
    setState(() {
      _projects.clear();
      _loading = true;
      _errorMessage = null;
    });
    final Stream<ProjectSummary> stream = ProjectRepository.instance
        .streamRecentProjects();
    _subscription = stream.listen(
      (ProjectSummary summary) {
        if (!mounted) {
          return;
        }
        setState(() {
          _projects.add(summary);
        });
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorMessage = '加载最近项目失败：$error';
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

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return MisarinDialog(
      title: const Text('最近打开'),
      content: SizedBox(height: 320, child: _buildContent(context, theme)),
      contentWidth: 480,
      maxWidth: 560,
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, FluentThemeData theme) {
    if (_errorMessage != null && _projects.isEmpty) {
      return Center(child: Text(_errorMessage!));
    }
    if (_projects.isEmpty) {
      if (_loading) {
        return const Center(child: ProgressRing());
      }
      return const Center(child: Text('暂无最近打开的项目'));
    }
    return Stack(
      children: [
        ListView.separated(
          itemBuilder: (context, index) {
            final ProjectSummary summary = _projects[index];
            return _RecentProjectTile(
              summary: summary,
              onOpen: () => Navigator.of(context).pop(summary),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemCount: _projects.length,
        ),
        if (_loading)
          const Positioned(
            right: 12,
            top: 12,
            child: ProgressRing(strokeWidth: 2.5),
          ),
      ],
    );
  }
}

class _RecentProjectTile extends StatefulWidget {
  const _RecentProjectTile({required this.summary, required this.onOpen});

  final ProjectSummary summary;
  final VoidCallback onOpen;

  @override
  State<_RecentProjectTile> createState() => _RecentProjectTileState();
}

class _RecentProjectTileState extends State<_RecentProjectTile> {
  late final FlyoutController _flyoutController;

  @override
  void initState() {
    super.initState();
    _flyoutController = FlyoutController();
  }

  @override
  void dispose() {
    _flyoutController.dispose();
    super.dispose();
  }

  void _showContextMenu(Offset position) {
    final String path = widget.summary.path;
    if (path.isEmpty) {
      return;
    }
    _flyoutController.showFlyout(
      barrierDismissible: true,
      position: position,
      builder: (context) {
        return MenuFlyout(
          items: [
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.folder_open),
              text: const Text('打开文件所在路径'),
              onPressed: () {
                unawaited(revealInFileManager(path));
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return FlyoutTarget(
      controller: _flyoutController,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) {
          _showContextMenu(details.globalPosition);
        },
        child: HoverButton(
          onPressed: widget.onOpen,
          builder: (context, states) {
            final bool hovering = states.isHovered;
            final Color background = hovering
                ? theme.resources.subtleFillColorSecondary
                : theme.cardColor;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.resources.controlStrongStrokeColorDefault,
                  width: 0.6,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProjectPreviewThumbnail(bytes: widget.summary.previewBytes),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.summary.name,
                          style: theme.typography.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '最后打开：${_formatDate(widget.summary.lastOpened)}',
                          style: theme.typography.caption,
                        ),
                        Text(
                          '画布尺寸：${widget.summary.settings.width.toInt()} x ${widget.summary.settings.height.toInt()}',
                          style: theme.typography.caption,
                        ),
                      ],
                    ),
                  ),
                  const Icon(FluentIcons.open_file, size: 18),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _formatDate(DateTime dateTime) {
  final DateTime local = dateTime.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
