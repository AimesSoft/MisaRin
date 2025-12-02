import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../canvas/canvas_settings.dart';
import 'misarin_dialog.dart';

class CanvasExportOptions {
  const CanvasExportOptions({required this.width, required this.height});

  final int width;
  final int height;
}

Future<CanvasExportOptions?> showCanvasExportDialog({
  required BuildContext context,
  required CanvasSettings settings,
}) async {
  final TextEditingController scaleController = TextEditingController(
    text: '1.0',
  );
  double scale = 1.0;
  String? scaleError;
  StateSetter? dialogSetState;
  CanvasExportOptions? result;

  await showMisarinDialog<CanvasExportOptions>(
    context: context,
    title: const Text('导出 PNG 设置'),
    contentWidth: 420,
    content: StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        dialogSetState = setState;
        final double outputWidth = settings.width * scale;
        final double outputHeight = settings.height * scale;
        final List<double> presets = <double>[0.25, 0.5, 1.0, 2.0, 4.0];

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('导出倍率'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormBox(
                    controller: scaleController,
                    placeholder: '如：1.0',
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (String value) {
                      final double? parsed = double.tryParse(value);
                      setState(() {
                        if (parsed == null || parsed <= 0) {
                          scaleError = '请输入大于 0 的数值';
                        } else {
                          scaleError = null;
                          scale = parsed;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Button(
                  onPressed: () {
                    setState(() {
                      scale = 1.0;
                      scaleController.text = '1.0';
                      scaleError = null;
                    });
                  },
                  child: const Text('重置'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final double value in presets)
                  Button(
                    onPressed: () {
                      setState(() {
                        scale = value;
                        scaleController.text = value.toString();
                        scaleError = null;
                      });
                    },
                    child: Text('${value}x'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('输出尺寸：${outputWidth.round()} × ${outputHeight.round()} 像素'),
            if (scaleError != null) ...[
              const SizedBox(height: 8),
              Text(
                scaleError!,
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
      FilledButton(
        onPressed: () {
          final double? parsed = double.tryParse(scaleController.text);
          if (parsed == null || parsed <= 0) {
            dialogSetState?.call(() {
              scaleError = '请输入大于 0 的数值';
            });
            return;
          }
          scale = parsed;
          final CanvasExportOptions options = CanvasExportOptions(
            width: (settings.width * scale).round().clamp(1, 100000),
            height: (settings.height * scale).round().clamp(1, 100000),
          );
          Navigator.of(context).pop(options);
        },
        child: const Text('导出'),
      ),
    ],
  ).then((CanvasExportOptions? value) {
    result = value;
  });

  scaleController.dispose();
  return result;
}
