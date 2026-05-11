part of 'painting_board.dart';

const List<int> _defaultPaletteChoices = <int>[4, 8, 12, 16];
const int _minPaletteColorCount = 2;
const int _maxPaletteColorCount = 32;
const double _paletteCardWidth = 184;
const double _paletteCardPadding = 12;
const double _paletteSwatchSize = 32;
const double _paletteMinimumColorDistance = 0.12;
const double _paletteDuplicateEpsilon = 0.01;

List<_PaletteExportFormatOption> _getPaletteExportFormatOptions(
    AppLocalizations l10n) {
  return <_PaletteExportFormatOption>[
    _PaletteExportFormatOption(
      name: 'GIMP GPL',
      description: l10n.gplDesc,
      extension: 'gpl',
      format: PaletteExportFormat.gimp,
    ),
    _PaletteExportFormatOption(
      name: 'Aseprite ASE',
      description: l10n.aseDesc,
      extension: 'ase',
      format: PaletteExportFormat.aseprite,
    ),
    _PaletteExportFormatOption(
      name: 'Aseprite ASEPRITE',
      description: l10n.asepriteDesc,
      extension: 'aseprite',
      format: PaletteExportFormat.aseprite,
    ),
  ];
}

class _PaletteCardEntry {
  _PaletteCardEntry({
    required this.id,
    required this.title,
    required this.colors,
    required this.offset,
  });

  final int id;
  final String title;
  final List<Color> colors;
  Offset offset;
  Size? size;
}

class _PaletteExportFormatOption {
  const _PaletteExportFormatOption({
    required this.name,
    required this.description,
    required this.extension,
    required this.format,
  });

  final String name;
  final String description;
  final String extension;
  final PaletteExportFormat format;
}

class _PaletteBucket {
  int weight = 0;
  int r = 0;
  int g = 0;
  int b = 0;
}

class _PaletteSelection {
  const _PaletteSelection({required this.color, required this.score});

  final Color color;
  final double score;
}

mixin _PaintingBoardPaletteMixin on _PaintingBoardBase {
  Future<void> showPaletteGenerator() async {
    final int? count = await _showPaletteColorCountDialog();
    if (count == null) {
      return;
    }
    await _generatePaletteCard(count);
  }

  void showGradientPaletteFromPrimaryColor() {
    final List<Color> palette = _buildPrimaryColorGradientPalette();
    final l10n = context.l10n;
    if (palette.length < _minPaletteColorCount) {
      AppNotifications.show(
        context,
        message: l10n.gradientPaletteFailed,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    _addPaletteCard(
      palette,
      title: l10n.gradientPaletteTitle,
    );
  }

  void _handlePaletteDragStart(int id) {
    _focusPaletteCard(id);
  }

  void _handlePaletteDragEnd() {}

  Future<int?> _showPaletteColorCountDialog() async {
    final TextEditingController controller = TextEditingController(
      text: _defaultPaletteChoices[1].toString(),
    );
    final FocusNode focusNode = FocusNode();
    int selectedCount = _defaultPaletteChoices[1];

    int? result;
    try {
      result = await showResponsiveDialog<int>(
        context: context,
        builder: (context) {
          final theme = FluentTheme.of(context);
          final l10n = context.l10n;
          final bool isMobile = isMobileOrPhone(context);
          final Widget content = StatefulBuilder(
            builder: (context, setState) {
              void handlePresetTap(int value) {
                setState(() {
                  selectedCount = value;
                  controller.value = TextEditingValue(
                    text: value.toString(),
                    selection: TextSelection.collapsed(
                      offset: value.toString().length,
                    ),
                  );
                });
              }

              void handleTextChanged(String text) {
                final int? parsed = int.tryParse(text);
                setState(() {
                  selectedCount = parsed ?? 0;
                });
              }

              final bool isValid =
                  selectedCount >= _minPaletteColorCount &&
                  selectedCount <= _maxPaletteColorCount;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.generatePaletteDesc),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _defaultPaletteChoices
                        .map((int choice) {
                          final bool isActive = selectedCount == choice;
                          final Widget button = isActive
                              ? FilledButton(
                                  onPressed: () => handlePresetTap(choice),
                                  child: Text('$choice'),
                                )
                              : Button(
                                  onPressed: () => handlePresetTap(choice),
                                  child: Text('$choice'),
                                );
                          return SizedBox(width: 56, child: button);
                        })
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 20),
                  Text(l10n.customCount, style: theme.typography.caption),
                  const SizedBox(height: 6),
                  TextBox(
                    controller: controller,
                    focusNode: focusNode,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    keyboardType: TextInputType.number,
                    onChanged: handleTextChanged,
                    placeholder:
                        l10n.paletteCountRange(_minPaletteColorCount, _maxPaletteColorCount),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.allowedRange(_minPaletteColorCount, _maxPaletteColorCount),
                    style: theme.typography.caption,
                  ),
                  if (!isValid)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.enterValidColorCount,
                        style: theme.typography.caption?.copyWith(
                          color: Colors.red,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
          final List<Widget> actions = [
            Button(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (selectedCount < _minPaletteColorCount ||
                    selectedCount > _maxPaletteColorCount) {
                  return;
                }
                Navigator.of(context).pop(selectedCount);
              },
              child: Text(l10n.create),
            ),
          ];

          if (isMobile) {
            return MisarinDialog(
              title: Text(l10n.generatePaletteTitle),
              content: content,
              actions: actions,
              contentWidth: null,
              maxWidth: 420,
            );
          }

          return ContentDialog(
            title: Text(l10n.generatePaletteTitle),
            content: content,
            actions: actions,
          );
        },
      );
    } finally {
      controller.dispose();
      focusNode.dispose();
    }
    return result;
  }

  Future<void> _generatePaletteCard(int colorCount) async {
    ui.Image image;
    final l10n = context.l10n;
    try {
      image = await _controller.snapshotImage();
    } catch (_) {
      AppNotifications.show(
        context,
        message: l10n.paletteGenerationFailed,
        severity: InfoBarSeverity.error,
      );
      return;
    }
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    image.dispose();
    if (bytes == null) {
      AppNotifications.show(
        context,
        message: l10n.paletteGenerationFailed,
        severity: InfoBarSeverity.error,
      );
      return;
    }
    final Uint8List data = bytes.buffer.asUint8List();
    final List<Color> palette = _resolvePalette(
      data,
      image.width,
      image.height,
      colorCount,
    );
    if (palette.isEmpty) {
      AppNotifications.show(
        context,
        message: l10n.noValidColorsFound,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    _addPaletteCard(palette);
  }

  void showPaletteFromColors({
    required String title,
    required List<Color> colors,
  }) {
    if (colors.isEmpty) {
      AppNotifications.show(
        context,
        message: context.l10n.paletteEmpty,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    _addPaletteCard(colors, title: title);
  }

  void _addPaletteCard(List<Color> colors, {String? title}) {
    final l10n = context.l10n;
    final List<Color> sanitized = _sanitizePaletteColors(colors);
    if (sanitized.length < _minPaletteColorCount) {
      AppNotifications.show(
        context,
        message: l10n.paletteMinColors(_minPaletteColorCount),
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    setState(() {
      final Offset offset = _initialPaletteOffset();
      _paletteCards.add(
        _PaletteCardEntry(
          id: _paletteCardSerial++,
          title: title?.trim().isNotEmpty == true ? title!.trim() : l10n.paletteDefaultName,
          colors: sanitized,
          offset: _clampPaletteOffset(offset),
        ),
      );
    });
    _scheduleWorkspaceCardsOverlaySync();
  }

  Future<void> _exportPaletteCard(int id) async {
    final _PaletteCardEntry? entry = _paletteCardById(id);
    if (entry == null) {
      return;
    }
    final l10n = context.l10n;
    if (entry.colors.isEmpty) {
      AppNotifications.show(
        context,
        message: l10n.paletteEmptyExport,
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    final _PaletteExportFormatOption? option =
        await _showPaletteExportFormatDialog();
    if (option == null) {
      return;
    }
    String? normalizedPath;
    if (Platform.isAndroid || Platform.isIOS) {
      final String? fileName = await showFileNameDialog(
        context: context,
        title: l10n.exportPaletteTitle,
        suggestedFileName: _suggestPaletteFileName(
          entry.title,
          option.extension,
        ),
        confirmLabel: l10n.export,
      );
      if (fileName == null) {
        return;
      }
      final String normalizedName = _normalizePaletteExportPath(
        _sanitizePaletteFileNameInput(fileName),
        option.extension,
      );
      normalizedPath = await MobileExportPaths.resolveExportPath(
        normalizedName,
      );
    } else {
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: l10n.exportPaletteTitle,
        fileName: _suggestPaletteFileName(entry.title, option.extension),
        type: FileType.custom,
        allowedExtensions: <String>[option.extension],
      );
      if (outputPath == null) {
        return;
      }
      normalizedPath = _normalizePaletteExportPath(
        outputPath,
        option.extension,
      );
    }
    try {
      final Uint8List bytes = PaletteFileExporter.encode(
        format: option.format,
        paletteName: entry.title,
        colors: entry.colors,
      );
      final File file = File(normalizedPath!);
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: l10n.paletteExported(normalizedPath!),
        severity: InfoBarSeverity.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: l10n.paletteExportFailed(error),
        severity: InfoBarSeverity.error,
      );
    }
  }

  Future<_PaletteExportFormatOption?> _showPaletteExportFormatDialog() async {
    final l10n = context.l10n;
    final List<_PaletteExportFormatOption> options = _getPaletteExportFormatOptions(l10n);
    if (options.isEmpty) {
      return null;
    }
    _PaletteExportFormatOption selected = options.first;
    if (isMobileOrPhone(context)) {
      return showMobileBottomSheet<_PaletteExportFormatOption>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          final FluentThemeData theme = FluentTheme.of(context);
          return StatefulBuilder(
            builder: (context, setState) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.selectExportFormat,
                      style: theme.typography.subtitle
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.selectPaletteFormatDesc,
                      style: theme.typography.body,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: options.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final option = options[index];
                          final bool isActive = option == selected;
                          return RadioButton(
                            checked: isActive,
                            onChanged: (checked) {
                              if (checked != true) {
                                return;
                              }
                              setState(() => selected = option);
                            },
                            content: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${option.name} (.${option.extension.toUpperCase()})',
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  option.description,
                                  style: theme.typography.caption,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Button(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(l10n.cancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                Navigator.of(context).pop(selected),
                            child: Text(l10n.next),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    }
    return showDialog<_PaletteExportFormatOption>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final FluentThemeData theme = FluentTheme.of(context);
        return ContentDialog(
          title: Text(l10n.selectExportFormat),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.selectPaletteFormatDesc),
                  const SizedBox(height: 12),
                  ...options.map((option) {
                    final bool isActive = option == selected;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: RadioButton(
                        checked: isActive,
                        onChanged: (checked) {
                          if (checked != true) {
                            return;
                          }
                          setState(() => selected = option);
                        },
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${option.name} (.${option.extension.toUpperCase()})',
                            ),
                            const SizedBox(height: 2),
                            Text(
                              option.description,
                              style: theme.typography.caption,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
          actions: [
            Button(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(selected),
              child: Text(l10n.next),
            ),
          ],
        );
      },
    );
  }

  String _suggestPaletteFileName(String title, String extension) {
    final String trimmed = title.trim();
    final String fallback = trimmed.isEmpty ? 'palette' : trimmed;
    final String sanitized = fallback.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final String safeName = sanitized.trim().isEmpty
        ? 'palette'
        : sanitized.trim();
    return '$safeName.${extension.toLowerCase()}';
  }

  String _normalizePaletteExportPath(String raw, String extension) {
    final String lower = raw.toLowerCase();
    final String suffix = '.${extension.toLowerCase()}';
    return lower.endsWith(suffix) ? raw : '$raw$suffix';
  }

  String _sanitizePaletteFileNameInput(String input) {
    final String sanitized =
        input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? 'palette' : sanitized;
  }

  List<Color> _sanitizePaletteColors(List<Color> colors) {
    final Set<int> unique = <int>{};
    final List<Color> sanitized = <Color>[];
    for (final Color color in colors) {
      final Color opaque = color.withAlpha(0xFF);
      if (unique.add(opaque.toARGB32())) {
        sanitized.add(opaque);
      }
      if (sanitized.length >= _maxPaletteColorCount) {
        break;
      }
    }
    return sanitized;
  }

  List<Color> _resolvePalette(
    Uint8List rgba,
    int width,
    int height,
    int desiredCount,
  ) {
    if (width <= 0 || height <= 0) {
      return const <Color>[];
    }
    final Map<int, _PaletteBucket> buckets = <int, _PaletteBucket>{};
    final int totalPixels = width * height;
    final int sampleTarget = math.min(60000, totalPixels);
    final int step = math.max(1, totalPixels ~/ sampleTarget);
    for (int i = 0; i < totalPixels; i += step) {
      final int index = i * 4;
      final int r = rgba[index];
      final int g = rgba[index + 1];
      final int b = rgba[index + 2];
      final int a = rgba[index + 3];
      if (a < 12) {
        continue;
      }
      final int key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      final _PaletteBucket bucket = buckets.putIfAbsent(
        key,
        () => _PaletteBucket(),
      );
      bucket.weight += a;
      bucket.r += r * a;
      bucket.g += g * a;
      bucket.b += b * a;
    }
    final List<_PaletteBucket> sorted = buckets.values.toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
    final List<Color> candidates = <Color>[];
    for (final _PaletteBucket bucket in sorted) {
      if (bucket.weight <= 0) {
        continue;
      }
      final int r = (bucket.r ~/ bucket.weight).clamp(0, 255);
      final int g = (bucket.g ~/ bucket.weight).clamp(0, 255);
      final int b = (bucket.b ~/ bucket.weight).clamp(0, 255);
      final Color color = Color.fromARGB(0xFF, r, g, b);
      bool isDuplicate = false;
      for (final Color existing in candidates) {
        if (_colorDistance(existing, color) < _paletteDuplicateEpsilon) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        candidates.add(color);
      }
    }
    if (candidates.isEmpty) {
      return const <Color>[];
    }
    final int clampedDesired = desiredCount
        .clamp(_minPaletteColorCount, _maxPaletteColorCount)
        .toInt();
    final int targetCount = math.max(
      1,
      math.min(clampedDesired, candidates.length),
    );
    // Use a farthest-point style sampling so each new color maximizes its
    // distance to the already selected ones.
    final List<Color> selectedColors = <Color>[candidates.first];
    final Set<int> used = <int>{0};
    while (selectedColors.length < targetCount) {
      double bestDistance = -1;
      int bestIndex = -1;
      for (int i = 0; i < candidates.length; i++) {
        if (used.contains(i)) {
          continue;
        }
        final Color candidate = candidates[i];
        double minDistance = double.infinity;
        for (final Color selection in selectedColors) {
          final double distance = _colorDistance(candidate, selection);
          if (distance < minDistance) {
            minDistance = distance;
          }
        }
        if (minDistance > bestDistance) {
          bestDistance = minDistance;
          bestIndex = i;
        }
      }
      if (bestIndex == -1 || bestDistance < _paletteMinimumColorDistance) {
        break;
      }
      used.add(bestIndex);
      selectedColors.add(candidates[bestIndex]);
    }
    final List<_PaletteSelection> orderedSelections = <_PaletteSelection>[];
    for (int i = 0; i < selectedColors.length; i++) {
      final Color color = selectedColors[i];
      double minDistance = double.infinity;
      for (int j = 0; j < selectedColors.length; j++) {
        if (i == j) {
          continue;
        }
        final double distance = _colorDistance(color, selectedColors[j]);
        if (distance < minDistance) {
          minDistance = distance;
        }
      }
      if (minDistance == double.infinity) {
        minDistance = double.maxFinite;
      }
      orderedSelections.add(
        _PaletteSelection(color: color, score: minDistance),
      );
    }
    orderedSelections.sort((a, b) => b.score.compareTo(a.score));
    return orderedSelections
        .map((entry) => entry.color)
        .toList(growable: false);
  }

  void _closePaletteCard(int id) {
    setState(() {
      _paletteCards.removeWhere((card) => card.id == id);
    });
    _scheduleWorkspaceCardsOverlaySync();
  }

  void _updatePaletteCardOffset(int id, Offset delta) {
    if (delta == Offset.zero) {
      return;
    }
    final _PaletteCardEntry? entry = _paletteCardById(id);
    if (entry == null) {
      return;
    }
    setState(() {
      final Offset next = entry.offset + delta;
      entry.offset = _clampPaletteOffset(next, entry.size);
    });
    _scheduleWorkspaceCardsOverlaySync();
  }

  void _focusPaletteCard(int id) {
    final int index = _paletteCards.indexWhere((card) => card.id == id);
    if (index < 0 || index == _paletteCards.length - 1) {
      return;
    }
    setState(() {
      final _PaletteCardEntry entry = _paletteCards.removeAt(index);
      _paletteCards.add(entry);
    });
    _scheduleWorkspaceCardsOverlaySync();
  }

  void _updatePaletteCardSize(int id, Size size) {
    final _PaletteCardEntry? entry = _paletteCardById(id);
    if (entry == null) {
      return;
    }
    entry.size = size;
    final Offset clamped = _clampPaletteOffset(entry.offset, size);
    if (clamped == entry.offset) {
      return;
    }
    setState(() {
      entry.offset = clamped;
    });
    _scheduleWorkspaceCardsOverlaySync();
  }

  Offset _initialPaletteOffset() {
    final double stackOffset = _paletteCards.length * 24.0;
    return _workspacePanelSpawnOffset(
      this,
      panelWidth: _paletteCardWidth,
      panelHeight: 220,
      additionalDy: stackOffset,
    );
  }

  Offset _clampPaletteOffset(Offset value, [Size? size]) {
    final double width = size?.width ?? _paletteCardWidth;
    final double height = size?.height ?? 180.0;
    return _clampWorkspaceOffsetToViewport(
      this,
      value,
      childSize: Size(width, height),
      margin: _toolButtonPadding,
    );
  }

  _PaletteCardEntry? _paletteCardById(int id) {
    for (final _PaletteCardEntry entry in _paletteCards) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  List<PaletteCardSnapshot> buildPaletteSnapshots() {
    return _paletteCards
        .map(
          (entry) => PaletteCardSnapshot(
            title: entry.title,
            colors: entry.colors
                .map((color) => color.value)
                .toList(growable: false),
            offset: entry.offset,
            size: entry.size,
          ),
        )
        .toList(growable: false);
  }

  void restorePaletteSnapshots(List<PaletteCardSnapshot> snapshots) {
    setState(() {
      _paletteCards.clear();
      _paletteCardSerial = 0;
      for (final PaletteCardSnapshot snapshot in snapshots) {
        final List<Color> colors = snapshot.colors
            .map((value) => Color(value))
            .toList(growable: false);
        final Offset offset = _clampPaletteOffset(snapshot.offset, snapshot.size);
        final _PaletteCardEntry entry = _PaletteCardEntry(
          id: _paletteCardSerial++,
          title: snapshot.title.trim().isEmpty ? '调色盘' : snapshot.title,
          colors: colors,
          offset: offset,
        );
        entry.size = snapshot.size;
        _paletteCards.add(entry);
      }
    });
    _scheduleWorkspaceCardsOverlaySync();
  }

  List<Color> _buildPrimaryColorGradientPalette() {
    final Color baseColor = _primaryColor;
    final HSVColor baseHsv = _primaryHsv;
    final Set<int> unique = <int>{};
    final List<Color> collected = <Color>[];

    void addColor(Color? color) {
      if (color == null) {
        return;
      }
      final Color sanitized = color.withAlpha(0xFF);
      final int argb = sanitized.toARGB32();
      if (unique.add(argb)) {
        collected.add(sanitized);
      }
    }

    addColor(baseColor);

    const List<double> darkStops = <double>[0.2, 0.4, 0.6];
    for (final double stop in darkStops) {
      addColor(Color.lerp(baseColor, Colors.black, stop));
    }
    const List<double> lightStops = <double>[0.18, 0.35, 0.5];
    for (final double stop in lightStops) {
      addColor(Color.lerp(baseColor, Colors.white, stop));
    }

    const Color neutral = Color(0xFF7F7F7F);
    const List<double> neutralStops = <double>[0.25, 0.5, 0.75];
    for (final double stop in neutralStops) {
      addColor(Color.lerp(baseColor, neutral, stop));
    }

    const List<double> saturationAdjustments = <double>[
      -0.4,
      -0.25,
      -0.1,
      0.15,
      0.3,
    ];
    for (final double delta in saturationAdjustments) {
      final double saturation = (baseHsv.saturation + delta).clamp(0.0, 1.0);
      addColor(baseHsv.withSaturation(saturation).toColor());
    }

    const List<double> hueOffsets = <double>[-24, -12, 12, 24];
    for (final double offset in hueOffsets) {
      double hue = baseHsv.hue + offset;
      while (hue < 0) {
        hue += 360;
      }
      while (hue >= 360) {
        hue -= 360;
      }
      addColor(baseHsv.withHue(hue).toColor());
    }

    if (collected.length > _maxPaletteColorCount) {
      return collected.sublist(0, _maxPaletteColorCount);
    }
    return collected;
  }
}

class _WorkspacePaletteCard extends StatelessWidget {
  const _WorkspacePaletteCard({
    super.key,
    required this.title,
    required this.colors,
    this.onExport,
    required this.onClose,
    required this.onDragUpdate,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onSizeChanged,
    required this.onColorTap,
  });

  final String title;
  final List<Color> colors;
  final VoidCallback? onExport;
  final VoidCallback onClose;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final ValueChanged<Size> onSizeChanged;
  final ValueChanged<Color> onColorTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: _PaletteHitTestBlocker(
        child: MeasuredSize(
          onChanged: onSizeChanged,
          child: WorkspaceFloatingPanel(
            title: title,
            child: _PaletteSwatches(colors: colors, onTap: onColorTap),
            width: _paletteCardWidth,
            onClose: onClose,
            headerActions: onExport == null
                ? null
                : <Widget>[
                    Tooltip(
                      message: context.l10n.exportPaletteTitle,
                      child: IconButton(
                        icon: const Icon(FluentIcons.save, size: 14),
                        iconButtonMode: IconButtonMode.small,
                        style: ButtonStyle(
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.all(4),
                          ),
                        ),
                        onPressed: onExport,
                      ),
                    ),
                  ],
            onDragStart: onDragStart,
            onDragUpdate: onDragUpdate,
            onDragEnd: onDragEnd,
            headerPadding: const EdgeInsets.fromLTRB(
              _paletteCardPadding,
              _paletteCardPadding,
              _paletteCardPadding,
              0,
            ),
            bodyPadding: const EdgeInsets.fromLTRB(
              _paletteCardPadding,
              0,
              _paletteCardPadding,
              _paletteCardPadding,
            ),
            bodySpacing: 10,
            footerSpacing: 0,
            closeIconSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PaletteSwatches extends StatelessWidget {
  const _PaletteSwatches({required this.colors, required this.onTap});

  final List<Color> colors;
  final ValueChanged<Color> onTap;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    if (colors.isEmpty) {
      return Text(context.l10n.noColorsDetected, style: theme.typography.caption);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors
          .map((Color color) {
            return Tooltip(
              message: _hexStringForColor(color),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(color),
                  child: Container(
                    width: _paletteSwatchSize,
                    height: _paletteSwatchSize,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _PaletteHitTestBlocker extends SingleChildRenderObjectWidget {
  const _PaletteHitTestBlocker({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _PaletteHitTestRender();
  }
}

class _PaletteHitTestRender extends RenderProxyBoxWithHitTestBehavior {
  _PaletteHitTestRender() : super(behavior: HitTestBehavior.opaque);
}

double _colorDistance(Color a, Color b) {
  final double dr = a.r - b.r;
  final double dg = a.g - b.g;
  final double db = a.b - b.b;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

String _hexStringForColor(Color color) {
  final int argb = color.toARGB32();
  final int a = (argb >> 24) & 0xFF;
  final int r = (argb >> 16) & 0xFF;
  final int g = (argb >> 8) & 0xFF;
  final int b = argb & 0xFF;
  final String alpha = a.toRadixString(16).padLeft(2, '0').toUpperCase();
  final String red = r.toRadixString(16).padLeft(2, '0').toUpperCase();
  final String green = g.toRadixString(16).padLeft(2, '0').toUpperCase();
  final String blue = b.toRadixString(16).padLeft(2, '0').toUpperCase();
  if (a == 0xFF) {
    return '#$red$green$blue';
  }
  return '#$alpha$red$green$blue';
}
