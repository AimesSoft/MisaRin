import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../canvas/canvas_settings.dart';
import '../l10n/l10n.dart';
import 'misarin_dialog.dart';

enum CanvasExportMode {
  bitmap,
  vector,
}

enum CanvasBitmapFormat {
  png,
  webp,
}

class CanvasExportOptions {
  const CanvasExportOptions({
    required this.mode,
    required this.width,
    required this.height,
    this.bitmapFormat = CanvasBitmapFormat.png,
    this.webpLossless = false,
    this.webpQuality = 85,
    this.edgeSofteningEnabled = false,
    this.edgeSofteningLevel = 2,
    this.vectorMaxColors,
    this.vectorSimplifyEpsilon,
  });

  final CanvasExportMode mode;
  final int width;
  final int height;
  final CanvasBitmapFormat bitmapFormat;
  final bool webpLossless;
  final int webpQuality;
  final bool edgeSofteningEnabled;
  final int edgeSofteningLevel;
  final int? vectorMaxColors;
  final double? vectorSimplifyEpsilon;
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
  int antialiasLevel = 2;
  bool antialiasEnabled = false;
  CanvasExportMode exportMode = CanvasExportMode.bitmap;
  CanvasBitmapFormat bitmapFormat = CanvasBitmapFormat.png;
  bool webpLossless = false;
  int webpQuality = 85;
  int vectorMaxColors = 8;
  double vectorSimplifyEpsilon = 1.2;
  CanvasExportOptions? result;

  await showMisarinDialog<CanvasExportOptions>(
    context: context,
    title: Text(context.l10n.exportSettingsTitle),
    contentWidth: 420,
    content: StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        dialogSetState = setState;
        final FluentThemeData theme = FluentTheme.of(context);
        final l10n = context.l10n;
        final double outputWidth = settings.width * scale;
        final double outputHeight = settings.height * scale;
        final List<double> presets = <double>[0.25, 0.5, 1.0, 2.0, 4.0];

        final List<String> antialiasDescriptions = [
          l10n.antialiasNone,
          l10n.antialiasLow,
          l10n.antialiasMedium,
          l10n.antialiasHigh,
        ];
        final String antialiasDescription = antialiasLevel <
                antialiasDescriptions.length
            ? antialiasDescriptions[antialiasLevel]
            : l10n.antialiasingDesc;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.exportTypeLabel, style: theme.typography.bodyStrong),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioButton(
                  checked: exportMode == CanvasExportMode.bitmap,
                  onChanged: (value) {
                    dialogSetState?.call(() {
                      exportMode = CanvasExportMode.bitmap;
                    });
                  },
                  content: Text(l10n.exportTypeBitmap),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Text(
                    l10n.exportBitmapDesc,
                    style: theme.typography.caption,
                  ),
                ),
                const SizedBox(height: 8),
                RadioButton(
                  checked: exportMode == CanvasExportMode.vector,
                  onChanged: (value) {
                    dialogSetState?.call(() {
                      exportMode = CanvasExportMode.vector;
                    });
                  },
                  content: Text(l10n.exportTypeSvg),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Text(
                    l10n.exportVectorDesc,
                    style: theme.typography.caption,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (exportMode == CanvasExportMode.bitmap) ...[
              Text(l10n.exportBitmapFormatLabel,
                  style: theme.typography.bodyStrong),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioButton(
                    checked: bitmapFormat == CanvasBitmapFormat.png,
                    onChanged: (value) {
                      dialogSetState?.call(() {
                        bitmapFormat = CanvasBitmapFormat.png;
                      });
                    },
                    content: Text(l10n.exportBitmapFormatPng),
                  ),
                  RadioButton(
                    checked: bitmapFormat == CanvasBitmapFormat.webp,
                    onChanged: (value) {
                      dialogSetState?.call(() {
                        bitmapFormat = CanvasBitmapFormat.webp;
                      });
                    },
                    content: Text(l10n.exportBitmapFormatWebp),
                  ),
                ],
              ),
              if (bitmapFormat == CanvasBitmapFormat.webp) ...[
                const SizedBox(height: 12),
                Text(l10n.webpCompressionLabel,
                    style: theme.typography.bodyStrong),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioButton(
                      checked: webpLossless,
                      onChanged: (value) {
                        dialogSetState?.call(() {
                          webpLossless = true;
                        });
                      },
                      content: Text(l10n.webpLossless),
                    ),
                    RadioButton(
                      checked: !webpLossless,
                      onChanged: (value) {
                        dialogSetState?.call(() {
                          webpLossless = false;
                        });
                      },
                      content: Text(l10n.webpLossy),
                    ),
                  ],
                ),
                if (!webpLossless) ...[
                  const SizedBox(height: 12),
                  Text(l10n.webpQualityLabel(webpQuality)),
                  Slider(
                    min: 1,
                    max: 100,
                    divisions: 99,
                    value: webpQuality.toDouble(),
                    label: l10n.webpQualityLabel(webpQuality),
                    onChanged: (value) {
                      dialogSetState?.call(() {
                        webpQuality = value.round();
                      });
                    },
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Text(l10n.exportScaleLabel),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormBox(
                      controller: scaleController,
                      placeholder: l10n.exampleScale,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: (String value) {
                        final double? parsed = double.tryParse(value);
                        setState(() {
                          if (parsed == null || parsed <= 0) {
                            scaleError = l10n.enterPositiveValue;
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
                    child: Text(l10n.reset),
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
              Text(l10n.exportOutputSize(
                  outputWidth.round(), outputHeight.round())),
              if (scaleError != null) ...[
                const SizedBox(height: 8),
                Text(
                  scaleError!,
                  style: const TextStyle(color: Color(0xFFD13438)),
                ),
              ],
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              Text(l10n.antialiasingBeforeExport,
                  style: theme.typography.bodyStrong),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ToggleSwitch(
                    checked: antialiasEnabled,
                    onChanged: (value) {
                      dialogSetState?.call(() {
                        antialiasEnabled = value;
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.enableAntialiasing),
                        const SizedBox(height: 4),
                        Text(
                          l10n.antialiasingDesc,
                          style: theme.typography.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (antialiasEnabled) ...[
                const SizedBox(height: 12),
                Slider(
                  min: 0,
                  max: 9,
                  divisions: 9,
                  value: antialiasLevel.toDouble(),
                  label: l10n.levelLabel(antialiasLevel),
                  onChanged: (value) {
                    dialogSetState?.call(() {
                      antialiasLevel = value.round();
                    });
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  antialiasDescription,
                  style: theme.typography.caption,
                ),
              ],
            ] else ...[
              Text(l10n.vectorParamsLabel, style: theme.typography.bodyStrong),
              const SizedBox(height: 8),
              Text(l10n.vectorExportSize(
                  settings.width.round(), settings.height.round())),
              const SizedBox(height: 12),
              Text(l10n.vectorMaxColors(vectorMaxColors)),
              Slider(
                min: 2,
                max: 16,
                divisions: 14,
                value: vectorMaxColors.toDouble(),
                label: l10n.colorCount(vectorMaxColors),
                onChanged: (value) {
                  dialogSetState?.call(() {
                    vectorMaxColors = value.round();
                  });
                },
              ),
              const SizedBox(height: 8),
              Text(l10n.vectorSimplify(vectorSimplifyEpsilon.toStringAsFixed(2))),
              Slider(
                min: 0.5,
                max: 4.0,
                divisions: 14,
                value: vectorSimplifyEpsilon.clamp(0.5, 4.0) as double,
                label: 'ε = ${vectorSimplifyEpsilon.toStringAsFixed(2)}',
                onChanged: (value) {
                  dialogSetState?.call(() {
                    vectorSimplifyEpsilon = value;
                  });
                },
              ),
              const SizedBox(height: 4),
              Text(
                l10n.vectorSimplifyDesc,
                style: theme.typography.caption,
              ),
            ],
          ],
        );
      },
    ),
    actions: [
      Button(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: () {
          final l10n = context.l10n;
          if (exportMode == CanvasExportMode.bitmap) {
            final double? parsed = double.tryParse(scaleController.text);
            if (parsed == null || parsed <= 0) {
              dialogSetState?.call(() {
                scaleError = l10n.enterPositiveValue;
              });
              return;
            }
            scale = parsed;
          }
          final CanvasExportOptions options = CanvasExportOptions(
            mode: exportMode,
            width: (exportMode == CanvasExportMode.bitmap
                    ? (settings.width * scale)
                    : settings.width)
                .round()
                .clamp(1, 100000),
            height: (exportMode == CanvasExportMode.bitmap
                    ? (settings.height * scale)
                    : settings.height)
                .round()
                .clamp(1, 100000),
            bitmapFormat: bitmapFormat,
            webpLossless: webpLossless,
            webpQuality: webpQuality.clamp(1, 100),
            edgeSofteningEnabled:
                exportMode == CanvasExportMode.bitmap && antialiasEnabled,
            edgeSofteningLevel:
                exportMode == CanvasExportMode.bitmap ? antialiasLevel.clamp(0, 9) : 0,
            vectorMaxColors:
                exportMode == CanvasExportMode.vector ? vectorMaxColors : null,
            vectorSimplifyEpsilon: exportMode == CanvasExportMode.vector
                ? vectorSimplifyEpsilon
                : null,
          );
          Navigator.of(context).pop(options);
        },
        child: Text(context.l10n.export),
      ),
    ],
  ).then((CanvasExportOptions? value) {
    result = value;
  });

  scaleController.dispose();
  return result;
}
