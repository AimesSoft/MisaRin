import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/l10n.dart';
import 'misarin_dialog.dart';

Future<void> showAboutMisarinDialog(BuildContext context) async {
  final theme = FluentTheme.of(context);
  final l10n = context.l10n;
  final packageInfo = await PackageInfo.fromPlatform();
  return showMisarinDialog<void>(
    context: context,
    title: Text(l10n.aboutTitle),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.aboutDescription, style: theme.typography.body),
        const SizedBox(height: 12),
        InfoLabel(
          label: l10n.aboutAppIdLabel,
          child: SelectableText(
            'com.aimessoft.misarin',
            style: theme.typography.bodyStrong,
          ),
        ),
        const SizedBox(height: 12),
        InfoLabel(
          label: l10n.aboutAppVersionLabel,
          child: SelectableText(
            packageInfo.version,
            style: theme.typography.bodyStrong,
          ),
        ),
        const SizedBox(height: 12),
        InfoLabel(
          label: l10n.aboutDeveloperLabel,
          child: SelectableText(
            'Aimes Soft',
            style: theme.typography.bodyStrong,
          ),
        ),
        const SizedBox(height: 12),
        InfoLabel(
          label: '鸣谢项目',
          child: SelectableText(
            'cube-3d-text\n'
            'https://github.com/EaseCation/cube-3d-text\n\n'
            'Krita\n'
            'https://krita.org\n\n'
            'Aseprite\n'
            'https://www.aseprite.org\n\n'
            'Blockbench\n'
            'https://www.blockbench.net',
            style: theme.typography.bodyStrong,
          ),
        ),
      ],
    ),
    contentWidth: 420,
    maxWidth: 520,
    actions: [
      Button(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.close),
      ),
    ],
  );
}
