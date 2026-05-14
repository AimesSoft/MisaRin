import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:misa_rin/mobile/responsive_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

enum _FontLanguageCategory { all, favorites, latin, zhHans, zhHant, ja, ko }

typedef FontFamilyPickerRightPaneBuilder =
    Widget Function(BuildContext context, FontFamilyPickerPreviewState state);

class FontFamilyPickerPreviewState {
  const FontFamilyPickerPreviewState({
    required this.selectedFamily,
    required this.selectedDisplay,
    required this.previewController,
    required this.previewSize,
    required this.minPreviewSize,
    required this.maxPreviewSize,
    required this.includeLatin,
    required this.includeZhHans,
    required this.includeZhHant,
    required this.includeJa,
    required this.includeKo,
    required this.buildSampleText,
    required this.onPreviewSizeChanged,
    required this.onToggleLatin,
    required this.onToggleZhHans,
    required this.onToggleZhHant,
    required this.onToggleJa,
    required this.onToggleKo,
  });

  final String selectedFamily;
  final String selectedDisplay;
  final TextEditingController previewController;
  final double previewSize;
  final double minPreviewSize;
  final double maxPreviewSize;
  final bool includeLatin;
  final bool includeZhHans;
  final bool includeZhHant;
  final bool includeJa;
  final bool includeKo;
  final String Function() buildSampleText;
  final ValueChanged<double> onPreviewSizeChanged;
  final ValueChanged<bool> onToggleLatin;
  final ValueChanged<bool> onToggleZhHans;
  final ValueChanged<bool> onToggleZhHant;
  final ValueChanged<bool> onToggleJa;
  final ValueChanged<bool> onToggleKo;

  String get effectivePreviewText {
    final String text = previewController.text;
    return text.isEmpty ? buildSampleText() : text;
  }

  String? get selectedFlutterFamily =>
      selectedFamily == 'System Default' ? null : selectedFamily;
}

Future<String?> showFontFamilyPickerDialog(
  BuildContext context, {
  required List<String> fontFamilies,
  required String selectedFamily,
  bool isLoading = false,
  double? initialPreviewSize,
  FontFamilyPickerRightPaneBuilder? rightPaneBuilder,
}) {
  return showResponsiveDialog<String>(
    context: context,
    builder: (context) => FontFamilyPickerDialog(
      fontFamilies: fontFamilies,
      selectedFamily: selectedFamily,
      isLoading: isLoading,
      initialPreviewSize: initialPreviewSize,
      rightPaneBuilder: rightPaneBuilder,
    ),
  );
}

class FontFamilyPickerDialog extends StatefulWidget {
  const FontFamilyPickerDialog({
    super.key,
    required this.fontFamilies,
    required this.selectedFamily,
    this.isLoading = false,
    this.initialPreviewSize,
    this.rightPaneBuilder,
  });

  final List<String> fontFamilies;
  final String selectedFamily;
  final bool isLoading;
  final double? initialPreviewSize;
  final FontFamilyPickerRightPaneBuilder? rightPaneBuilder;

  @override
  State<FontFamilyPickerDialog> createState() => _FontFamilyPickerDialogState();
}

class _FontFamilyPickerDialogState extends State<FontFamilyPickerDialog> {
  static const String _favoritesStorageKey = 'misa_rin.font_favorites';
  static const double _listItemExtent = 44;
  static const double _minPreviewSize = 10;
  static const double _maxPreviewSize = 200;
  static const String _sampleLatin =
      'The quick brown fox jumps over the lazy dog. 0123456789';
  static const String _sampleZhHans = '简体中文：欢迎使用字体测试！';
  static const String _sampleZhHant = '繁體中文：歡迎使用字體測試！';
  static const String _sampleJa = '日本語：こんにちは世界！';
  static const String _sampleKo = '한국어: 안녕하세요 세계!';

  static const int _langZhHans = 1 << 0;
  static const int _langZhHant = 1 << 1;
  static const int _langJa = 1 << 2;
  static const int _langKo = 1 << 3;
  static const int _langCjk = _langZhHans | _langZhHant | _langJa | _langKo;

  static final RegExp _cjkNamePattern = RegExp(
    r'(cjk|source\s*han|sourcehan|noto\s*sans\s*cjk|noto\s*serif\s*cjk|han\s*sans|han\s*serif)',
    caseSensitive: false,
  );
  static final RegExp _zhHansNamePattern = RegExp(
    r'(\bsc\b|\bchs\b|\bhans\b|\bsimplified\b|pingfang\s*sc|pingfangsc|yahei|simsun|simhei|heiti\s*sc|songti\s*sc|fangsong|kaiti)',
    caseSensitive: false,
  );
  static final RegExp _zhHantNamePattern = RegExp(
    r'(\btc\b|\bcht\b|\bhant\b|\btraditional\b|pingfang\s*tc|pingfangtc|pingfang\s*hk|pingfanghk|jhenghei|mingliu|pmingliu|heiti\s*tc|songti\s*tc)',
    caseSensitive: false,
  );
  static final RegExp _jaNamePattern = RegExp(
    r'(\bjp\b|\bjapanese\b|hiragino|meiryo|yu\s*gothic|yugothic|ms\s*gothic|ms\s*mincho)',
    caseSensitive: false,
  );
  static final RegExp _koNamePattern = RegExp(
    r'(\bkr\b|\bkorean\b|malgun|nanum|apple\s*sd\s*gothic|gulim|dotum|batang)',
    caseSensitive: false,
  );

  static bool _containsRuneInRange(String input, int start, int end) {
    for (final int rune in input.runes) {
      if (rune >= start && rune <= end) {
        return true;
      }
    }
    return false;
  }

  static bool _containsHangul(String input) {
    return _containsRuneInRange(input, 0xAC00, 0xD7AF) ||
        _containsRuneInRange(input, 0x1100, 0x11FF) ||
        _containsRuneInRange(input, 0x3130, 0x318F) ||
        _containsRuneInRange(input, 0xA960, 0xA97F) ||
        _containsRuneInRange(input, 0xD7B0, 0xD7FF);
  }

  static bool _containsKana(String input) {
    return _containsRuneInRange(input, 0x3040, 0x30FF) ||
        _containsRuneInRange(input, 0x31F0, 0x31FF) ||
        _containsRuneInRange(input, 0xFF66, 0xFF9D);
  }

  static bool _containsHan(String input) {
    return _containsRuneInRange(input, 0x4E00, 0x9FFF) ||
        _containsRuneInRange(input, 0x3400, 0x4DBF) ||
        _containsRuneInRange(input, 0xF900, 0xFAFF);
  }

  late final TextEditingController _searchController;
  late final TextEditingController _previewController;
  late final ScrollController _scrollController;
  late final List<_FontFamilyEntry> _entries;

  late List<_FontFamilyEntry> _filteredEntries;
  late String _selectedFamily;
  late double _previewSize;
  _FontLanguageCategory _languageCategory = _FontLanguageCategory.all;
  Set<String> _favoriteFamilies = <String>{};
  bool _includeLatin = true;
  bool _includeZhHans = true;
  bool _includeZhHant = true;
  bool _includeJa = true;
  bool _includeKo = true;

  @override
  void initState() {
    super.initState();
    _selectedFamily = widget.selectedFamily;
    _previewSize = (widget.initialPreviewSize ?? 28).clamp(
      _minPreviewSize,
      _maxPreviewSize,
    );
    _searchController = TextEditingController()..addListener(_applySearch);
    _previewController = TextEditingController();
    _applySampleText();
    _scrollController = ScrollController();
    _entries = widget.fontFamilies
        .map((family) {
          final String display = _sanitizeDisplayText(family);
          return _FontFamilyEntry(
            family: family,
            display: display,
            displayLower: display.toLowerCase(),
            languageTags: _detectLanguageTags(family),
          );
        })
        .toList(growable: false);
    _filteredEntries = _entries;
    _loadFavorites();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scrollToSelected();
    });
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_applySearch)
      ..dispose();
    _previewController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _applySearch() {
    final String query = _searchController.text.trim().toLowerCase();
    final Iterable<_FontFamilyEntry> candidates = _entries.where(
      (entry) => _matchesLanguageCategory(entry, _languageCategory),
    );
    final List<_FontFamilyEntry> nextEntries = query.isEmpty
        ? candidates.toList(growable: false)
        : candidates
              .where((entry) => entry.displayLower.contains(query))
              .toList(growable: false);
    setState(() => _filteredEntries = nextEntries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (query.isEmpty) {
        _scrollToSelected();
        return;
      }
      if (_scrollController.hasClients && _filteredEntries.isNotEmpty) {
        _scrollController.jumpTo(0);
      }
    });
  }

  Future<void> _loadFavorites() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String>? stored = prefs.getStringList(_favoritesStorageKey);
      if (!mounted) {
        return;
      }
      setState(() {
        _favoriteFamilies = (stored ?? const <String>[]).toSet();
      });
      if (_languageCategory == _FontLanguageCategory.favorites) {
        _applySearch();
      }
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  Future<void> _saveFavorites() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> values = _favoriteFamilies.toList(growable: false)
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      await prefs.setStringList(_favoritesStorageKey, values);
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  void _toggleFavorite(String family) {
    if (family == 'System Default') {
      return;
    }
    final bool nextIsFavorite = !_favoriteFamilies.contains(family);
    setState(() {
      if (nextIsFavorite) {
        _favoriteFamilies.add(family);
      } else {
        _favoriteFamilies.remove(family);
      }
    });
    _saveFavorites();
    if (_languageCategory == _FontLanguageCategory.favorites) {
      _applySearch();
    }
  }

  bool _matchesLanguageCategory(
    _FontFamilyEntry entry,
    _FontLanguageCategory category,
  ) {
    if (entry.family == 'System Default') {
      return true;
    }
    switch (category) {
      case _FontLanguageCategory.all:
        return true;
      case _FontLanguageCategory.favorites:
        return _favoriteFamilies.contains(entry.family);
      case _FontLanguageCategory.latin:
        return entry.languageTags == 0;
      case _FontLanguageCategory.zhHans:
        return (entry.languageTags & _langZhHans) != 0;
      case _FontLanguageCategory.zhHant:
        return (entry.languageTags & _langZhHant) != 0;
      case _FontLanguageCategory.ja:
        return (entry.languageTags & _langJa) != 0;
      case _FontLanguageCategory.ko:
        return (entry.languageTags & _langKo) != 0;
    }
  }

  int _detectLanguageTags(String family) {
    if (family == 'System Default') {
      return _langCjk;
    }
    int tags = 0;
    if (_containsHangul(family)) {
      tags |= _langKo;
    }
    if (_containsKana(family)) {
      tags |= _langJa;
    }
    if (_containsHan(family) && (tags & (_langJa | _langKo)) == 0) {
      tags |= _langZhHans | _langZhHant;
    }
    final String normalized = family
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (_zhHansNamePattern.hasMatch(normalized)) {
      tags |= _langZhHans;
    }
    if (_zhHantNamePattern.hasMatch(normalized)) {
      tags |= _langZhHant;
    }
    if (_jaNamePattern.hasMatch(normalized)) {
      tags |= _langJa;
    }
    if (_koNamePattern.hasMatch(normalized)) {
      tags |= _langKo;
    }
    final bool likelyHans =
        family.contains('简体') ||
        family.contains('簡體') ||
        family.contains('简中') ||
        family.contains('字体');
    final bool likelyHant =
        family.contains('繁體') ||
        family.contains('繁体') ||
        family.contains('繁中') ||
        family.contains('臺') ||
        family.contains('字體');
    if (likelyHans && !likelyHant) {
      tags = (tags & ~_langZhHant) | _langZhHans;
    } else if (likelyHant && !likelyHans) {
      tags = (tags & ~_langZhHans) | _langZhHant;
    }
    if (tags != 0) {
      return tags;
    }
    if (_cjkNamePattern.hasMatch(normalized)) {
      return _langCjk;
    }
    return tags;
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) {
      return;
    }
    final int index = _filteredEntries.indexWhere(
      (entry) => entry.family == _selectedFamily,
    );
    if (index < 0) {
      _scrollController.jumpTo(0);
      return;
    }
    if (index == 0) {
      return;
    }
    final double target = math.max(0.0, (index - 3) * _listItemExtent);
    _scrollController.jumpTo(
      math.min(target, _scrollController.position.maxScrollExtent),
    );
  }

  void _selectFamily(String family) {
    if (_selectedFamily == family) {
      return;
    }
    setState(() => _selectedFamily = family);
  }

  void _confirm() {
    Navigator.of(context).pop(_selectedFamily);
  }

  void _applySampleText() {
    final String text = _buildSampleText();
    _previewController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  int get _enabledLanguageCount {
    int count = 0;
    if (_includeLatin) count++;
    if (_includeZhHans) count++;
    if (_includeZhHant) count++;
    if (_includeJa) count++;
    if (_includeKo) count++;
    return count;
  }

  void _toggleLanguage({
    required bool current,
    required bool next,
    required void Function(bool) assign,
  }) {
    if (!next && current && _enabledLanguageCount <= 1) {
      return;
    }
    setState(() => assign(next));
    _applySampleText();
  }

  String _buildSampleText() {
    final List<String> lines = <String>[];
    if (_includeLatin) {
      lines.add(_sampleLatin);
    }
    if (_includeZhHans) {
      lines.add(_sampleZhHans);
    }
    if (_includeZhHant) {
      lines.add(_sampleZhHant);
    }
    if (_includeJa) {
      lines.add(_sampleJa);
    }
    if (_includeKo) {
      lines.add(_sampleKo);
    }
    if (lines.isEmpty) {
      return _sampleLatin;
    }
    return lines.join('\n');
  }

  static Color _bestForegroundFor(Color background) {
    final double luminance = background.computeLuminance();
    final double contrastWithWhite = (1.05) / (luminance + 0.05);
    final double contrastWithBlack = (luminance + 0.05) / 0.05;
    return contrastWithWhite >= contrastWithBlack ? Colors.white : Colors.black;
  }

  String _sanitizeDisplayText(String raw) {
    if (raw.isEmpty) {
      return raw;
    }
    final List<int> units = raw.codeUnits;
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < units.length; i++) {
      final int unit = units[i];
      if (unit < 0x20) {
        continue;
      }
      if (_isLowSurrogate(unit)) {
        continue;
      }
      if (_isHighSurrogate(unit)) {
        if (i + 1 < units.length && _isLowSurrogate(units[i + 1])) {
          final int high = unit;
          final int low = units[++i];
          final int codePoint =
              0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
          buffer.writeCharCode(codePoint);
        } else {
          buffer.writeCharCode(0xFFFD);
        }
        continue;
      }
      buffer.writeCharCode(unit);
    }
    return buffer.toString();
  }

  bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;

  bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

  FontFamilyPickerPreviewState _buildPreviewState() {
    return FontFamilyPickerPreviewState(
      selectedFamily: _selectedFamily,
      selectedDisplay: _sanitizeDisplayText(_selectedFamily),
      previewController: _previewController,
      previewSize: _previewSize,
      minPreviewSize: _minPreviewSize,
      maxPreviewSize: _maxPreviewSize,
      includeLatin: _includeLatin,
      includeZhHans: _includeZhHans,
      includeZhHant: _includeZhHant,
      includeJa: _includeJa,
      includeKo: _includeKo,
      buildSampleText: _buildSampleText,
      onPreviewSizeChanged: (double value) {
        setState(() {
          _previewSize = value.clamp(_minPreviewSize, _maxPreviewSize);
        });
      },
      onToggleLatin: (bool value) => _toggleLanguage(
        current: _includeLatin,
        next: value,
        assign: (next) => _includeLatin = next,
      ),
      onToggleZhHans: (bool value) => _toggleLanguage(
        current: _includeZhHans,
        next: value,
        assign: (next) => _includeZhHans = next,
      ),
      onToggleZhHant: (bool value) => _toggleLanguage(
        current: _includeZhHant,
        next: value,
        assign: (next) => _includeZhHant = next,
      ),
      onToggleJa: (bool value) => _toggleLanguage(
        current: _includeJa,
        next: value,
        assign: (next) => _includeJa = next,
      ),
      onToggleKo: (bool value) => _toggleLanguage(
        current: _includeKo,
        next: value,
        assign: (next) => _includeKo = next,
      ),
    );
  }

  Widget _buildDefaultRightPane(
    BuildContext context,
    FluentThemeData theme,
    FontFamilyPickerPreviewState state,
  ) {
    final l10n = context.l10n;
    final Widget previewTextBox = TextBox(controller: state.previewController);
    final Widget languageToggles = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ToggleButton(
          checked: state.includeLatin,
          onChanged: state.onToggleLatin,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('EN+123'),
          ),
        ),
        ToggleButton(
          checked: state.includeZhHans,
          onChanged: state.onToggleZhHans,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('简体'),
          ),
        ),
        ToggleButton(
          checked: state.includeZhHant,
          onChanged: state.onToggleZhHant,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('繁體'),
          ),
        ),
        ToggleButton(
          checked: state.includeJa,
          onChanged: state.onToggleJa,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('日本語'),
          ),
        ),
        ToggleButton(
          checked: state.includeKo,
          onChanged: state.onToggleKo,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('한국어'),
          ),
        ),
      ],
    );
    final Widget previewSlider = Row(
      children: [
        Text(
          '${l10n.fontSize}：${state.previewSize.toStringAsFixed(0)}',
          style: theme.typography.caption,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Slider(
            min: state.minPreviewSize,
            max: state.maxPreviewSize,
            value: state.previewSize,
            onChanged: state.onPreviewSizeChanged,
          ),
        ),
      ],
    );
    final Widget previewArea = Container(
      decoration: BoxDecoration(
        color: theme.resources.controlFillColorSecondary,
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(12),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: state.previewController,
        builder: (context, value, _) {
          return SingleChildScrollView(
            child: SelectableText(
              state.effectivePreviewText,
              style: theme.typography.body?.copyWith(
                fontFamily: state.selectedFlutterFamily,
                fontSize: state.previewSize,
              ),
            ),
          );
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.selectedDisplay,
          style: theme.typography.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
        const SizedBox(height: 12),
        Text(l10n.fontPreviewText, style: theme.typography.caption),
        const SizedBox(height: 4),
        previewTextBox,
        const SizedBox(height: 12),
        Text(l10n.fontPreviewLanguages, style: theme.typography.caption),
        const SizedBox(height: 4),
        languageToggles,
        const SizedBox(height: 12),
        previewSlider,
        const SizedBox(height: 12),
        Expanded(child: previewArea),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final l10n = context.l10n;
    final Color selectedBackground = theme.accentColor.defaultBrushFor(
      theme.brightness,
    );
    final Color selectedForeground = _bestForegroundFor(selectedBackground);

    final Widget loadingIndicator = SizedBox(
      width: 18,
      height: 18,
      child: const ProgressRing(strokeWidth: 2.0),
    );

    final Widget title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.fontFamily),
        if (widget.isLoading) ...[const SizedBox(width: 8), loadingIndicator],
      ],
    );

    final Widget searchBox = TextBox(
      controller: _searchController,
      autofocus: true,
      placeholder: l10n.fontSearchPlaceholder,
    );

    Widget buildCategoryToggle(_FontLanguageCategory category, Widget child) {
      final bool selected = _languageCategory == category;
      return ToggleButton(
        checked: selected,
        onChanged: (value) {
          if (!value) {
            return;
          }
          setState(() => _languageCategory = category);
          _applySearch();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: child,
        ),
      );
    }

    final Widget languageCategorySelector = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        buildCategoryToggle(
          _FontLanguageCategory.all,
          Text(l10n.fontLanguageAll),
        ),
        buildCategoryToggle(
          _FontLanguageCategory.favorites,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FluentIcons.favorite_star_fill, size: 14),
              const SizedBox(width: 6),
              Text(l10n.fontFavorites),
            ],
          ),
        ),
        buildCategoryToggle(_FontLanguageCategory.latin, const Text('EN+123')),
        buildCategoryToggle(_FontLanguageCategory.zhHans, const Text('简体')),
        buildCategoryToggle(_FontLanguageCategory.zhHant, const Text('繁體')),
        buildCategoryToggle(_FontLanguageCategory.ja, const Text('日本語')),
        buildCategoryToggle(_FontLanguageCategory.ko, const Text('한국어')),
      ],
    );

    final bool shouldShowEmptyFavoritesHint =
        _languageCategory == _FontLanguageCategory.favorites &&
        _favoriteFamilies.isEmpty &&
        _searchController.text.trim().isEmpty;
    final String emptyHint = shouldShowEmptyFavoritesHint
        ? l10n.noFavoriteFonts
        : l10n.noMatchingFonts;

    final Widget fontList = Container(
      decoration: BoxDecoration(
        color: theme.resources.controlFillColorDefault,
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
        borderRadius: BorderRadius.circular(6),
      ),
      child: _filteredEntries.isEmpty
          ? Center(
              child: Text(
                emptyHint,
                style: theme.typography.caption,
                textAlign: TextAlign.center,
              ),
            )
          : Scrollbar(
              controller: _scrollController,
              child: ListView.builder(
                controller: _scrollController,
                itemExtent: _listItemExtent,
                itemCount: _filteredEntries.length,
                itemBuilder: (context, index) {
                  final _FontFamilyEntry entry = _filteredEntries[index];
                  final bool selected = entry.family == _selectedFamily;
                  final bool isFavorite = _favoriteFamilies.contains(
                    entry.family,
                  );
                  final Color foreground = selected
                      ? selectedForeground
                      : theme.typography.body?.color ?? Colors.black;
                  final String? family = entry.family == 'System Default'
                      ? null
                      : entry.family;
                  final Color favoriteIconColor = selected
                      ? selectedForeground
                      : isFavorite
                      ? theme.accentColor.defaultBrushFor(theme.brightness)
                      : theme.resources.textFillColorSecondary;
                  return Button(
                    style: ButtonStyle(
                      padding: WidgetStateProperty.all<EdgeInsets>(
                        const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                        states,
                      ) {
                        if (selected) {
                          return selectedBackground;
                        }
                        if (states.contains(WidgetState.hovered)) {
                          return theme.resources.controlFillColorSecondary;
                        }
                        return Colors.transparent;
                      }),
                    ),
                    onPressed: () => _selectFamily(entry.family),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: theme.typography.body?.copyWith(
                              color: foreground,
                              fontFamily: family,
                            ),
                          ),
                        ),
                        if (entry.family != 'System Default')
                          IconButton(
                            icon: Icon(
                              isFavorite
                                  ? FluentIcons.favorite_star_fill
                                  : FluentIcons.favorite_star,
                              size: 14,
                              color: favoriteIconColor,
                            ),
                            onPressed: () => _toggleFavorite(entry.family),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );

    final FontFamilyPickerPreviewState previewState = _buildPreviewState();
    final Widget rightPane =
        widget.rightPaneBuilder?.call(context, previewState) ??
        _buildDefaultRightPane(context, theme, previewState);

    final Widget content = SizedBox(
      width: 820,
      height: 560,
      child: Row(
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                searchBox,
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.fontLanguageCategory,
                    style: theme.typography.caption,
                  ),
                ),
                const SizedBox(height: 6),
                languageCategorySelector,
                const SizedBox(height: 12),
                Expanded(child: fontList),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: rightPane),
        ],
      ),
    );

    return ContentDialog(
      title: title,
      constraints: const BoxConstraints(maxWidth: 860),
      content: content,
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _confirm, child: Text(l10n.confirm)),
      ],
    );
  }
}

class _FontFamilyEntry {
  const _FontFamilyEntry({
    required this.family,
    required this.display,
    required this.displayLower,
    required this.languageTags,
  });

  final String family;
  final String display;
  final String displayLower;
  final int languageTags;
}
