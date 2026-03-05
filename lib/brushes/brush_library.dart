import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:misa_rin/utils/io_shim.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/preferences/app_preferences.dart';
import '../canvas/canvas_tools.dart';
import '../l10n/app_localizations.dart';
import 'abr_brush_converter.dart';
import 'brush_package.dart';
import 'brush_preset.dart';
import 'brush_shape_library.dart';

Uint8List _byteDataToUint8List(ByteData data) {
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

class BrushLibrary extends ChangeNotifier {
  BrushLibrary._({
    required BrushShapeLibrary shapeLibrary,
    required List<BrushPreset> presets,
    required Map<String, BrushPreset> basePresets,
    required Map<String, _BrushSource> sources,
    required Map<String, BrushPreset> overrides,
    required Map<String, BrushLocalizationTable> localizations,
    required String selectedId,
  }) : _shapeLibrary = shapeLibrary,
       _presets = presets,
       _basePresets = basePresets,
       _sources = sources,
       _overrides = overrides,
       _localizations = localizations,
       _selectedId = selectedId;

  static const int _version = 1;
  static const String brushFileExtension = 'mrb';
  static const String abrFileExtension = 'abr';
  static const String _folderName = 'MisaRin';
  static const String _brushFolderName = 'brushes';
  static const String _libraryFileName = 'brush_library.json';
  static const String _legacyFileName = 'brush_presets.json';
  static const String _storageKey = 'misa_rin.brush_library';
  static const String _legacyStorageKey = 'misa_rin.brush_presets';
  static const String _defaultBuiltInAuthor = 'Misa Rin';
  static const String _defaultBuiltInVersion = '1.0.0';

  static const List<String> _defaultBrushAssets = <String>[
    'assets/brushes/pencil.mrb',
    'assets/brushes/cel.mrb',
    'assets/brushes/pen.mrb',
    'assets/brushes/sumi_e.mrb',
    'assets/brushes/chalk.mrb',
    'assets/brushes/screentone.mrb',
    'assets/brushes/pixel.mrb',
    'assets/brushes/triangle.mrb',
    'assets/brushes/square.mrb',
    'assets/brushes/star.mrb',
  ];

  static BrushLibrary? _instance;

  final BrushShapeLibrary _shapeLibrary;
  final List<BrushPreset> _presets;
  final Map<String, BrushPreset> _basePresets;
  final Map<String, _BrushSource> _sources;
  final Map<String, BrushPreset> _overrides;
  final Map<String, BrushLocalizationTable> _localizations;
  String _selectedId;

  static BrushLibrary get instance {
    final BrushLibrary? current = _instance;
    if (current == null) {
      throw StateError('BrushLibrary has not been loaded');
    }
    return current;
  }

  BrushShapeLibrary get shapeLibrary => _shapeLibrary;

  List<BrushPreset> get presets => List<BrushPreset>.unmodifiable(_presets);

  String get selectedId => _selectedId;

  String displayNameFor(BrushPreset preset, ui.Locale locale) {
    final BrushLocalizationTable? table = _localizations[preset.id];
    if (table != null) {
      final String? resolved = table.resolve(preset.name, _localeTag(locale));
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }
    return preset.name;
  }

  bool isNameLocalized(BrushPreset preset, ui.Locale locale) {
    final BrushLocalizationTable? table = _localizations[preset.id];
    if (table == null) {
      return false;
    }
    return table.resolve(preset.name, _localeTag(locale)) != null;
  }

  BrushPreset get selectedPreset {
    return _presets.firstWhere(
      (BrushPreset preset) => preset.id == _selectedId,
      orElse: () => _presets.first,
    );
  }

  bool isBuiltInPreset(String id) => _sources[id]?.isBuiltIn ?? false;

  BrushPreset? basePresetById(String id) => _basePresets[id];

  static Future<BrushLibrary> load({AppPreferences? prefs}) async {
    if (_instance != null) {
      return _instance!;
    }
    final AppLocalizations l10n = _resolveL10n(prefs);
    final BrushShapeLibrary shapeLibrary = await BrushShapeLibrary.load();
    final Map<String, BrushPreset> basePresets = <String, BrushPreset>{};
    final Map<String, _BrushSource> sources = <String, _BrushSource>{};
    final Map<String, BrushLocalizationTable> localizations =
        <String, BrushLocalizationTable>{};
    final List<BrushPreset> orderedPresets = <BrushPreset>[];

    // Load built-in brush packages from assets.
    for (final String assetPath in _defaultBrushAssets) {
      final ByteData data = await rootBundle.load(assetPath);
      final BrushPackageData? package = BrushPackageCodec.decode(
        _byteDataToUint8List(data),
      );
      if (package == null) {
        continue;
      }
      BrushPreset preset = package.preset.sanitized();
      final BrushLocalizationTable? table = package.localizations;
      if (table == null || !table.hasKey(preset.name)) {
        preset = _localizeBuiltInPreset(preset, l10n);
      } else {
        localizations[preset.id] = table;
      }
      preset.shapeId ??= preset.resolvedShapeId;
      basePresets[preset.id] = preset;
      sources[preset.id] = _BrushSource.asset(assetPath);
      orderedPresets.add(preset);
      await _ensureShapeForPackage(shapeLibrary, preset, package);
    }

    // Load user brush packages.
    final List<_UserBrushEntry> userPresets = <_UserBrushEntry>[];
    if (!kIsWeb) {
      final Directory directory = await _brushDirectory();
      await directory.create(recursive: true);
      final List<FileSystemEntity> files = await directory.list().toList();
      for (final FileSystemEntity entity in files) {
        if (entity is! File) {
          continue;
        }
        if (!entity.path.toLowerCase().endsWith('.$brushFileExtension')) {
          continue;
        }
        final Uint8List bytes = await entity.readAsBytes();
        final BrushPackageData? package = BrushPackageCodec.decode(bytes);
        if (package == null) {
          continue;
        }
        final BrushPreset preset = package.preset.sanitized();
        await _ensureShapeForPackage(shapeLibrary, preset, package);
        userPresets.add(
          _UserBrushEntry(
            preset: preset,
            path: entity.path,
            localizations: package.localizations,
          ),
        );
      }
    }

    userPresets.sort((a, b) => a.preset.name.compareTo(b.preset.name));
    for (final _UserBrushEntry entry in userPresets) {
      BrushPreset preset = entry.preset;
      if (basePresets.containsKey(preset.id)) {
        preset = preset.copyWith(
          id: _uniqueId(preset.id, basePresets.keys.toSet()),
        );
      }
      preset = preset.copyWith(
        name: _uniqueName(
          preset.name,
          basePresets.values.map((p) => p.name).toSet(),
        ),
      );
      basePresets[preset.id] = preset;
      sources[preset.id] = _BrushSource.file(entry.path);
      if (entry.localizations != null) {
        localizations[preset.id] = entry.localizations!;
      }
      orderedPresets.add(preset);
    }

    if (orderedPresets.isEmpty) {
      final BrushPreset fallback = _fallbackPreset(l10n);
      basePresets[fallback.id] = fallback;
      sources[fallback.id] = _BrushSource.asset('fallback');
      orderedPresets.add(fallback);
      debugPrint(
        'BrushLibrary: no built-in brushes loaded; using fallback preset.',
      );
    }

    Map<String, BrushPreset> overrides = <String, BrushPreset>{};
    String? selectedId;
    bool patchedOverrides = false;

    final Map<String, dynamic>? payload = await _readPayload();
    if (payload != null) {
      selectedId = payload['selectedId'] as String?;
      overrides = _parseOverrides(payload['overrides'], basePresets);
      patchedOverrides = _repairOverridesForBuiltIns(
        overrides,
        basePresets,
        sources,
        localizations,
      );
    } else {
      final Map<String, dynamic>? legacy = await _readLegacyPayload();
      if (legacy != null) {
        selectedId = legacy['selectedId'] as String?;
        final List<BrushPreset> legacyPresets = _legacyPresetsFromPayload(
          legacy,
        );
        overrides = await _migrateLegacyPresets(
          legacyPresets,
          basePresets,
          sources,
          orderedPresets,
          shapeLibrary,
        );
        patchedOverrides = _repairOverridesForBuiltIns(
          overrides,
          basePresets,
          sources,
          localizations,
        );
      }
    }

    final List<BrushPreset> effectivePresets = <BrushPreset>[];
    for (final BrushPreset base in orderedPresets) {
      final BrushPreset? override = overrides[base.id];
      BrushPreset effective = (override ?? base).sanitized();
      if (sources[base.id]?.isBuiltIn ?? false) {
        final String? author = effective.author;
        final String? version = effective.version;
        if (author == null || author.trim().isEmpty) {
          effective = effective.copyWith(
            author: base.author ?? _defaultBuiltInAuthor,
          );
        }
        if (version == null || version.trim().isEmpty) {
          effective = effective.copyWith(
            version: base.version ?? _defaultBuiltInVersion,
          );
        }
      }
      effectivePresets.add(effective);
    }

    String resolvedSelectedId = selectedId ?? effectivePresets.first.id;
    if (effectivePresets.indexWhere(
          (preset) => preset.id == resolvedSelectedId,
        ) <
        0) {
      resolvedSelectedId = effectivePresets.first.id;
    }

    final BrushLibrary library = BrushLibrary._(
      shapeLibrary: shapeLibrary,
      presets: effectivePresets,
      basePresets: basePresets,
      sources: sources,
      overrides: overrides,
      localizations: localizations,
      selectedId: resolvedSelectedId,
    );
    _instance = library;

    if (payload == null) {
      unawaited(library.save());
    } else if (patchedOverrides) {
      unawaited(library.save());
    }
    return library;
  }

  Future<void> save() async {
    await _writePayload(_toPayload());
  }

  void selectPreset(String id) {
    if (_selectedId == id) {
      return;
    }
    if (_presets.indexWhere((BrushPreset preset) => preset.id == id) < 0) {
      return;
    }
    _selectedId = id;
    notifyListeners();
    unawaited(save());
  }

  void updatePreset(BrushPreset preset) {
    final int index = _presets.indexWhere(
      (BrushPreset entry) => entry.id == preset.id,
    );
    if (index < 0) {
      return;
    }
    final BrushPreset sanitized = preset.sanitized();
    _presets[index] = sanitized;
    _overrides[preset.id] = sanitized;
    notifyListeners();
    unawaited(save());
  }

  Future<void> resetPreset(String id) async {
    final BrushPreset? base = _basePresets[id];
    if (base == null) {
      return;
    }
    final int index = _presets.indexWhere((preset) => preset.id == id);
    if (index < 0) {
      return;
    }
    _presets[index] = base.sanitized();
    _overrides.remove(id);
    notifyListeners();
    await save();
  }

  Future<void> addPreset(BrushPreset preset) async {
    BrushPreset sanitized = preset.sanitized();
    final Set<String> ids = _basePresets.keys.toSet();
    sanitized = sanitized.copyWith(
      id: _uniqueId(sanitized.id, ids),
      name: _uniqueName(sanitized.name, _presets.map((p) => p.name).toSet()),
    );
    final String? filePath = await _writeUserBrushPackage(
      sanitized,
      _shapeLibrary,
    );
    if (filePath == null) {
      return;
    }
    _basePresets[sanitized.id] = sanitized;
    _sources[sanitized.id] = _BrushSource.file(filePath);
    _presets.add(sanitized);
    notifyListeners();
    await save();
  }

  Future<void> removePreset(String id) async {
    if (_presets.length <= 1) {
      return;
    }
    final _BrushSource? source = _sources[id];
    if (source == null || source.isBuiltIn) {
      return;
    }
    final int index = _presets.indexWhere(
      (BrushPreset preset) => preset.id == id,
    );
    if (index < 0) {
      return;
    }
    _presets.removeAt(index);
    _basePresets.remove(id);
    _overrides.remove(id);
    if (_selectedId == id) {
      _selectedId = _presets.first.id;
    }
    _sources.remove(id);
    _localizations.remove(id);
    if (!kIsWeb) {
      final File file = File(source.path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    notifyListeners();
    await save();
  }

  Future<BrushPreset?> importBrushBytes(Uint8List bytes) async {
    if (kIsWeb) {
      return null;
    }
    final BrushPackageData? package = BrushPackageCodec.decode(bytes);
    if (package == null) {
      return null;
    }
    BrushPreset preset = package.preset.sanitized();
    preset = preset.copyWith(
      id: _uniqueId(preset.id, _basePresets.keys.toSet()),
      name: _uniqueName(preset.name, _presets.map((p) => p.name).toSet()),
    );
    await _ensureShapeForPackage(_shapeLibrary, preset, package);
    if (package.localizations != null) {
      _localizations[preset.id] = package.localizations!;
    }
    final String? filePath = await _writeUserBrushPackage(
      preset,
      _shapeLibrary,
      package: package,
    );
    if (filePath == null) {
      return null;
    }
    _basePresets[preset.id] = preset;
    _sources[preset.id] = _BrushSource.file(filePath);
    _presets.add(preset);
    notifyListeners();
    await save();
    return preset;
  }

  Future<BrushPreset?> importBrushFile(String path) async {
    if (kIsWeb) {
      return null;
    }
    final File file = File(path);
    if (!await file.exists()) {
      return null;
    }
    if (path.toLowerCase().endsWith('.$abrFileExtension')) {
      return _importAbrFile(path);
    }
    final Uint8List bytes = await file.readAsBytes();
    return importBrushBytes(bytes);
  }

  Future<BrushPreset?> _importAbrFile(String path) async {
    final Set<String> usedIds = _basePresets.keys.toSet();
    final Set<String> usedNames = _presets.map((p) => p.name).toSet();
    final AbrNativeConversionResult? converted =
        await AbrBrushConverter.convertFileToNativePackages(
          path,
          usedIds: usedIds,
          usedNames: usedNames,
        );
    if (converted == null || converted.packages.isEmpty) {
      return null;
    }

    BrushPreset? firstImported;
    for (final AbrConvertedPackage convertedPackage in converted.packages) {
      final BrushPreset? imported = await importBrushBytes(
        convertedPackage.packageBytes,
      );
      firstImported ??= imported;
    }

    return firstImported;
  }

  Future<bool> exportBrush(String id, String outputPath) async {
    BrushPreset? preset;
    for (final BrushPreset entry in _presets) {
      if (entry.id == id) {
        preset = entry;
        break;
      }
    }
    if (preset == null) {
      return false;
    }
    final BrushShapeDefinition? shape = _shapeLibrary.resolve(
      preset.resolvedShapeId,
    );
    Uint8List? shapeBytes;
    String? shapeFileName;
    BrushShapeFileType? shapeType;
    if (shape != null) {
      shapeBytes = await _shapeLibrary.loadShapeBytes(shape.id);
      shapeFileName = shape.filePath != null
          ? p.basename(shape.filePath!)
          : '${shape.id}.${shape.type == BrushShapeFileType.svg ? 'svg' : 'png'}';
      shapeType = shape.type;
    }
    final BrushLocalizationTable? localizations = _localizations[id];
    final Uint8List bytes = BrushPackageCodec.encode(
      preset: preset,
      shapeBytes: shapeBytes,
      shapeFileName: shapeFileName,
      shapeType: shapeType,
      localizations: localizations,
    );
    if (bytes.isEmpty) {
      return false;
    }
    final File outFile = File(outputPath);
    await outFile.create(recursive: true);
    await outFile.writeAsBytes(bytes, flush: true);
    return true;
  }

  Map<String, dynamic> _toPayload() {
    final Map<String, dynamic> overrides = <String, dynamic>{};
    for (final BrushPreset preset in _presets) {
      final BrushPreset? base = _basePresets[preset.id];
      if (base == null) {
        continue;
      }
      if (!preset.isSameAs(base)) {
        overrides[preset.id] = preset.toJson();
      }
    }
    return <String, dynamic>{
      'version': _version,
      'selectedId': _selectedId,
      'overrides': overrides,
    };
  }

  static Map<String, BrushPreset> _parseOverrides(
    Object? payload,
    Map<String, BrushPreset> basePresets,
  ) {
    final Map<String, BrushPreset> overrides = <String, BrushPreset>{};
    if (payload is! Map<String, dynamic>) {
      return overrides;
    }
    payload.forEach((String key, Object? value) {
      if (value is Map<String, dynamic>) {
        BrushPreset preset = BrushPreset.fromJson(value);
        final BrushPreset? base = basePresets[key];
        if (base != null) {
          preset = _mergeOverrideWithBase(
            preset,
            base,
            hasAuthor: value.containsKey('author'),
            hasVersion: value.containsKey('version'),
          );
        }
        overrides[key] = preset;
      }
    });
    return overrides;
  }

  static Future<Map<String, dynamic>?> _readPayload() async {
    if (kIsWeb) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? encoded = prefs.getString(_storageKey);
      if (encoded == null || encoded.isEmpty) {
        return null;
      }
      try {
        final Object? decoded = jsonDecode(encoded);
        return decoded is Map<String, dynamic> ? decoded : null;
      } catch (_) {
        return null;
      }
    }
    final File file = await _libraryFile();
    if (!await file.exists()) {
      return null;
    }
    try {
      final String content = await file.readAsString();
      final Object? decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writePayload(Map<String, dynamic> payload) async {
    if (kIsWeb) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(payload));
      return;
    }
    final File file = await _libraryFile();
    await file.create(recursive: true);
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  static Future<File> _libraryFile() async {
    final base = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(p.join(base.path, _folderName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, _libraryFileName));
  }

  static Future<Map<String, dynamic>?> _readLegacyPayload() async {
    if (kIsWeb) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? encoded = prefs.getString(_legacyStorageKey);
      if (encoded == null || encoded.isEmpty) {
        return null;
      }
      try {
        final Object? decoded = jsonDecode(encoded);
        return decoded is Map<String, dynamic> ? decoded : null;
      } catch (_) {
        return null;
      }
    }
    final File file = await _legacyLibraryFile();
    if (!await file.exists()) {
      return null;
    }
    try {
      final String content = await file.readAsString();
      final Object? decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<File> _legacyLibraryFile() async {
    final base = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(p.join(base.path, _folderName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, _legacyFileName));
  }

  static List<BrushPreset> _legacyPresetsFromPayload(
    Map<String, dynamic> payload,
  ) {
    final List<dynamic> entries =
        payload['presets'] as List<dynamic>? ?? <dynamic>[];
    return entries
        .whereType<Map<String, dynamic>>()
        .map(BrushPreset.fromJson)
        .toList();
  }

  static Future<Map<String, BrushPreset>> _migrateLegacyPresets(
    List<BrushPreset> legacyPresets,
    Map<String, BrushPreset> basePresets,
    Map<String, _BrushSource> sources,
    List<BrushPreset> orderedPresets,
    BrushShapeLibrary shapeLibrary,
  ) async {
    final Map<String, BrushPreset> overrides = <String, BrushPreset>{};
    for (final BrushPreset preset in legacyPresets) {
      if (basePresets.containsKey(preset.id)) {
        final BrushPreset base = basePresets[preset.id]!;
        BrushPreset merged = preset.sanitized();
        merged = _mergeOverrideWithBase(
          merged,
          base,
          hasAuthor: false,
          hasVersion: false,
        );
        overrides[preset.id] = merged;
        continue;
      }
      final String newId = _uniqueId(preset.id, basePresets.keys.toSet());
      final String newName = _uniqueName(
        preset.name,
        basePresets.values.map((p) => p.name).toSet(),
      );
      final BrushPreset sanitized = preset.sanitized().copyWith(
        id: newId,
        name: newName,
      );
      final String? filePath = await _writeUserBrushPackage(
        sanitized,
        shapeLibrary,
      );
      if (filePath == null) {
        continue;
      }
      basePresets[sanitized.id] = sanitized;
      sources[sanitized.id] = _BrushSource.file(filePath);
      orderedPresets.add(sanitized);
    }
    return overrides;
  }

  static Future<Directory> _brushDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, _folderName, _brushFolderName));
  }

  static Future<void> _ensureShapeForPackage(
    BrushShapeLibrary shapeLibrary,
    BrushPreset preset,
    BrushPackageData package,
  ) async {
    final String shapeId = preset.resolvedShapeId;
    final Uint8List? packageBytes = package.shapeBytes;
    final BrushShapeFileType? packageType = package.shapeType;
    final BrushShapeDefinition? existing = shapeLibrary.resolve(shapeId);
    if (existing != null) {
      if (packageBytes == null || packageType == null) {
        return;
      }
      final Uint8List existingBytes = await shapeLibrary.loadShapeBytes(
        existing.id,
      );
      if (existingBytes.isNotEmpty &&
          _bytesEqual(existingBytes, packageBytes)) {
        return;
      }
      final BrushShapeDefinition? imported = await shapeLibrary
          .importShapeBytes(
            id: shapeId,
            bytes: packageBytes,
            type: packageType,
          );
      if (imported != null && imported.id != shapeId) {
        preset.shapeId = imported.id;
      }
      return;
    }
    if (packageBytes != null && packageType != null) {
      final BrushShapeDefinition? imported = await shapeLibrary
          .importShapeBytes(
            id: shapeId,
            bytes: packageBytes,
            type: packageType,
          );
      if (imported != null && imported.id != shapeId) {
        preset.shapeId = imported.id;
      }
    }
  }

  static Future<String?> _writeUserBrushPackage(
    BrushPreset preset,
    BrushShapeLibrary shapeLibrary, {
    BrushPackageData? package,
    BrushLocalizationTable? localizations,
  }) async {
    if (kIsWeb) {
      return null;
    }
    final Directory directory = await _brushDirectory();
    await directory.create(recursive: true);
    final String baseName = _sanitizeFileId(preset.id);
    String fileName = '$baseName.$brushFileExtension';
    File file = File(p.join(directory.path, fileName));
    int suffix = 2;
    while (await file.exists()) {
      fileName = '${baseName}_$suffix.$brushFileExtension';
      file = File(p.join(directory.path, fileName));
      suffix += 1;
    }

    final BrushShapeDefinition? shape = shapeLibrary.resolve(
      preset.resolvedShapeId,
    );
    Uint8List? shapeBytes = package?.shapeBytes;
    String? shapeFileName = package?.shapeFileName;
    BrushShapeFileType? shapeType = package?.shapeType;
    if (shapeBytes == null && shape != null) {
      shapeBytes = await shapeLibrary.loadShapeBytes(shape.id);
      shapeFileName = shape.filePath != null
          ? p.basename(shape.filePath!)
          : '${shape.id}.${shape.type == BrushShapeFileType.svg ? 'svg' : 'png'}';
      shapeType = shape.type;
    }
    final BrushLocalizationTable? resolvedLocalizations =
        localizations ?? package?.localizations;
    final Uint8List bytes = BrushPackageCodec.encode(
      preset: preset,
      shapeBytes: shapeBytes,
      shapeFileName: shapeFileName,
      shapeType: shapeType,
      localizations: resolvedLocalizations,
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static AppLocalizations _resolveL10n(AppPreferences? prefs) {
    final ui.Locale locale =
        prefs?.localeOverride ?? ui.PlatformDispatcher.instance.locale;
    try {
      return lookupAppLocalizations(locale);
    } catch (_) {
      return lookupAppLocalizations(const ui.Locale('en'));
    }
  }

  static BrushPreset _localizeBuiltInPreset(
    BrushPreset preset,
    AppLocalizations l10n,
  ) {
    final _DefaultPresetNames names = _DefaultPresetNames.fromL10n(l10n);
    final String? localized = names.nameForId(preset.id);
    if (localized == null) {
      return preset;
    }
    return preset.copyWith(name: localized);
  }

  static BrushPreset _fallbackPreset(AppLocalizations l10n) {
    return BrushPreset(
      id: 'pencil',
      name: l10n.brushPresetPencil,
      shape: AppPreferences.defaultBrushShape,
      shapeId: null,
      author: _defaultBuiltInAuthor,
      version: _defaultBuiltInVersion,
      spacing: 0.15,
      hardness: 0.8,
      flow: 1.0,
      scatter: 0.0,
      randomRotation: AppPreferences.defaultBrushRandomRotationEnabled,
      smoothRotation: true,
      rotationJitter: 1.0,
      antialiasLevel: AppPreferences.defaultPenAntialiasLevel,
      hollowEnabled: AppPreferences.defaultHollowStrokeEnabled,
      hollowRatio: AppPreferences.defaultHollowStrokeRatio,
      hollowEraseOccludedParts:
          AppPreferences.defaultHollowStrokeEraseOccludedParts,
      autoSharpTaper: AppPreferences.defaultAutoSharpPeakEnabled,
      snapToPixel: false,
      screentoneEnabled: false,
      screentoneSpacing: 10.0,
      screentoneDotSize: 0.6,
      screentoneRotation: 45.0,
      screentoneSoftness: 0.0,
      screentoneShape: BrushShape.circle,
    ).sanitized();
  }

  static String _uniqueId(String base, Set<String> ids) {
    if (!ids.contains(base)) {
      return base;
    }
    int counter = 2;
    while (ids.contains('${base}_$counter')) {
      counter += 1;
    }
    return '${base}_$counter';
  }

  static String _uniqueName(String base, Set<String> names) {
    if (!names.contains(base)) {
      return base;
    }
    int counter = 2;
    while (names.contains('$base $counter')) {
      counter += 1;
    }
    return '$base $counter';
  }

  static String _sanitizeFileId(String id) {
    final StringBuffer buffer = StringBuffer();
    for (final int rune in id.runes) {
      final int code = rune;
      final bool ok =
          (code >= 48 && code <= 57) ||
          (code >= 65 && code <= 90) ||
          (code >= 97 && code <= 122) ||
          code == 45 ||
          code == 95;
      buffer.write(ok ? String.fromCharCode(code) : '_');
    }
    final String sanitized = buffer.toString();
    return sanitized.isEmpty ? 'brush' : sanitized;
  }

  static String _localeTag(ui.Locale locale) {
    final String tag = locale.toString();
    if (tag.isEmpty) {
      return locale.languageCode.toLowerCase();
    }
    return tag.replaceAll('-', '_').toLowerCase();
  }

  static BrushPreset _mergeOverrideWithBase(
    BrushPreset override,
    BrushPreset base, {
    required bool hasAuthor,
    required bool hasVersion,
  }) {
    BrushPreset merged = override;
    final String? author = merged.author;
    if (!hasAuthor || author == null || author.trim().isEmpty) {
      merged = merged.copyWith(author: base.author);
    }
    final String? version = merged.version;
    if (!hasVersion || version == null || version.trim().isEmpty) {
      merged = merged.copyWith(version: base.version);
    }
    return merged;
  }

  static bool _repairOverridesForBuiltIns(
    Map<String, BrushPreset> overrides,
    Map<String, BrushPreset> basePresets,
    Map<String, _BrushSource> sources,
    Map<String, BrushLocalizationTable> localizations,
  ) {
    bool patched = false;
    overrides.forEach((String id, BrushPreset preset) {
      if (!(sources[id]?.isBuiltIn ?? false)) {
        return;
      }
      final BrushPreset? base = basePresets[id];
      if (base == null) {
        return;
      }
      final String? author = preset.author;
      final String? version = preset.version;
      final bool patchAuthor = author == null || author.trim().isEmpty;
      final bool patchVersion = version == null || version.trim().isEmpty;
      bool patchName = false;
      BrushPreset updated = preset;
      if (patchAuthor) {
        updated = updated.copyWith(
          author: base.author ?? _defaultBuiltInAuthor,
        );
      }
      if (patchVersion) {
        updated = updated.copyWith(
          version: base.version ?? _defaultBuiltInVersion,
        );
      }
      final BrushLocalizationTable? table = localizations[id];
      if (table != null) {
        final String baseKey = base.name;
        final String overrideName = preset.name;
        final Map<String, String>? values = table.entries[baseKey];
        if (values != null &&
            overrideName != baseKey &&
            values.values.any((value) => value == overrideName)) {
          updated = updated.copyWith(name: baseKey);
          patchName = true;
        }
      }
      if (patchAuthor || patchVersion || patchName) {
        overrides[id] = updated;
        patched = true;
      }
    });
    return patched;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

class _BrushSource {
  const _BrushSource._({required this.path, required this.isBuiltIn});

  final String path;
  final bool isBuiltIn;

  factory _BrushSource.asset(String path) =>
      _BrushSource._(path: path, isBuiltIn: true);

  factory _BrushSource.file(String path) =>
      _BrushSource._(path: path, isBuiltIn: false);
}

class _UserBrushEntry {
  const _UserBrushEntry({
    required this.preset,
    required this.path,
    this.localizations,
  });

  final BrushPreset preset;
  final String path;
  final BrushLocalizationTable? localizations;
}

class _DefaultPresetNames {
  const _DefaultPresetNames({
    required this.pencil,
    required this.cel,
    required this.pen,
    required this.screentone,
    required this.pixel,
    required this.triangle,
    required this.square,
    required this.star,
  });

  final String pencil;
  final String cel;
  final String pen;
  final String screentone;
  final String pixel;
  final String triangle;
  final String square;
  final String star;

  static _DefaultPresetNames fromL10n(AppLocalizations l10n) {
    return _DefaultPresetNames(
      pencil: l10n.brushPresetPencil,
      cel: l10n.brushPresetCel,
      pen: l10n.brushPresetPen,
      screentone: l10n.brushPresetScreentone,
      pixel: l10n.brushPresetPixel,
      triangle: l10n.triangle,
      square: l10n.square,
      star: l10n.star,
    );
  }

  String? nameForId(String id) {
    switch (id) {
      case 'pencil':
        return pencil;
      case 'cel':
        return cel;
      case 'pen':
        return pen;
      case 'screentone':
        return screentone;
      case 'pixel':
        return pixel;
      case 'triangle':
        return triangle;
      case 'square':
        return square;
      case 'star':
        return star;
    }
    return null;
  }
}
