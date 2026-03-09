import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../mobile/responsive_dialog.dart';
import '../l10n/l10n.dart';
import '../utils/svg_rasterizer.dart';

Future<int?> showSvgRasterizeSizeDialog(
  BuildContext context, {
  String? fileName,
  int initialSizePx = kDefaultSvgRasterSizePx,
}) async {
  final TextEditingController controller = TextEditingController(
    text: normalizeSvgRasterSize(initialSizePx).toString(),
  );
  String? errorMessage;
  final int? result = await showResponsiveDialog<int>(
    context: context,
    builder: (BuildContext dialogContext) {
      final AppLocalizations l10n = dialogContext.l10n;
      return StatefulBuilder(
        builder: (BuildContext dialogContext, StateSetter setState) {
          void submit() {
            final int? parsed = int.tryParse(controller.text.trim());
            if (parsed == null) {
              setState(() {
                errorMessage = l10n.invalidResolution;
              });
              return;
            }
            if (parsed < kMinSvgRasterSizePx) {
              setState(() {
                errorMessage = l10n.minResolutionError(kMinSvgRasterSizePx);
              });
              return;
            }
            if (parsed > kMaxSvgRasterSizePx) {
              setState(() {
                errorMessage = l10n.maxResolutionError(kMaxSvgRasterSizePx);
              });
              return;
            }
            Navigator.of(dialogContext).pop(parsed);
          }

          return ContentDialog(
            title: const Text('SVG 栅格化分辨率'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (fileName != null && fileName.trim().isNotEmpty) ...[
                  Text('文件：$fileName'),
                  const SizedBox(height: 6),
                ],
                Text(
                  '请输入导入 SVG 时位图最长边像素，默认 1024。',
                  style: FluentTheme.of(dialogContext).typography.caption,
                ),
                const SizedBox(height: 12),
                InfoLabel(
                  label: '最长边（像素）',
                  child: TextBox(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (_) {
                      if (errorMessage == null) {
                        return;
                      }
                      setState(() {
                        errorMessage = null;
                      });
                    },
                    onSubmitted: (_) => submit(),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: Color(0xFFC42B1C)),
                  ),
                ],
              ],
            ),
            actions: <Widget>[
              Button(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(onPressed: submit, child: Text(l10n.ok)),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return result;
}
