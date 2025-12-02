import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

/// 在 Web 平台上请求用户输入导出的文件名。
Future<String?> showWebFileNameDialog({
  required BuildContext context,
  required String title,
  required String suggestedFileName,
  String? description,
  String confirmLabel = '下载',
}) async {
  if (!kIsWeb) {
    return null;
  }
  final TextEditingController controller = TextEditingController(
    text: suggestedFileName,
  );
  String? error;
  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      final FluentThemeData theme = FluentTheme.of(context);
      return ContentDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (description != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(description),
                  ),
                TextBox(
                  controller: controller,
                  autofocus: true,
                  onChanged: (value) {
                    setState(() {
                      error = value.trim().isEmpty ? '文件名不能为空' : null;
                    });
                  },
                  onSubmitted: (_) {
                    final String trimmed = controller.text.trim();
                    if (trimmed.isNotEmpty) {
                      Navigator.of(context).pop(trimmed);
                    }
                  },
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: theme.typography.caption?.copyWith(
                        color: Colors.red,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final String trimmed = controller.text.trim();
              if (trimmed.isEmpty) {
                return;
              }
              Navigator.of(context).pop(trimmed);
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  controller.dispose();
  final String value = result?.trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  return value;
}
