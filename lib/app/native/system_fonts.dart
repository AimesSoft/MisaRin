import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:misa_rin/utils/io_shim.dart';
import 'package:path/path.dart' as p;

class SystemFonts {
  const SystemFonts._();

  static const MethodChannel _platformChannel = MethodChannel(
    'misarin/system_fonts',
  );

  static List<String>? _cachedFamilies;

  static const List<String> _fallbackFamilies = <String>[
    'Arial',
    'Helvetica',
    'Times New Roman',
    'Courier New',
    'Roboto',
    'Noto Sans',
    'Noto Serif',
    'PingFang SC',
    'Microsoft YaHei',
  ];

  static Future<List<String>> loadFamilies() async {
    if (_cachedFamilies != null) {
      return _cachedFamilies!;
    }
    if (!_supportsNativeFonts) {
      _cachedFamilies = _fallbackFamilies;
      return _cachedFamilies!;
    }

    if (Platform.isMacOS) {
      final List<String>? native = await _loadFamiliesFromPlatformChannel();
      if (native != null && native.isNotEmpty) {
        _cachedFamilies = native;
        return _cachedFamilies!;
      }
    }

    final List<String> directories = _fontDirectories();
    if (directories.isEmpty) {
      _cachedFamilies = _fallbackFamilies;
      return _cachedFamilies!;
    }
    try {
      final List<String> families = await compute(
        _collectFontNames,
        directories,
      );
      _cachedFamilies = families.isEmpty ? _fallbackFamilies : families;
    } catch (_) {
      _cachedFamilies = _fallbackFamilies;
    }
    return _cachedFamilies!;
  }

  static Future<String?> resolveFontFileForFamily(String family) async {
    final String trimmed = family.trim();
    if (!_supportsNativeFonts ||
        trimmed.isEmpty ||
        trimmed == 'System Default') {
      return null;
    }
    if (!Platform.isMacOS) {
      return null;
    }
    try {
      final String? path = await _platformChannel.invokeMethod<String>(
        'getFontFileForFamily',
        <String, Object?>{'family': trimmed},
      );
      if (path == null || path.trim().isEmpty) {
        return null;
      }
      return path.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>?> _loadFamiliesFromPlatformChannel() async {
    try {
      final List<String>? families = await _platformChannel
          .invokeListMethod<String>('getFamilies');
      if (families == null || families.isEmpty) {
        return null;
      }
      return families;
    } catch (_) {
      return null;
    }
  }

  static bool get _supportsNativeFonts {
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  static List<String> _fontDirectories() {
    final List<String> dirs = <String>[];
    if (Platform.isMacOS) {
      dirs.add('/System/Library/Fonts');
      dirs.add('/Library/Fonts');
      final String? home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        dirs.add(p.join(home, 'Library', 'Fonts'));
      }
      dirs.add('/Network/Library/Fonts');
      try {
        final Directory assetsRoot = Directory('/System/Library/AssetsV2');
        if (assetsRoot.existsSync()) {
          for (final FileSystemEntity entity in assetsRoot.listSync(
            followLinks: false,
          )) {
            if (entity is! Directory) {
              continue;
            }
            final String name = p.basename(entity.path);
            if (!name.startsWith('com_apple_MobileAsset_Font')) {
              continue;
            }
            dirs.add(entity.path);
          }
        }
      } catch (_) {
        // Ignore sandboxed asset directories.
      }
    } else if (Platform.isWindows) {
      final String? winDir = Platform.environment['WINDIR'];
      if (winDir != null && winDir.isNotEmpty) {
        dirs.add(p.join(winDir, 'Fonts'));
      } else {
        dirs.add(r'C:\Windows\Fonts');
      }
      final String? userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        dirs.add(
          p.join(
            userProfile,
            'AppData',
            'Local',
            'Microsoft',
            'Windows',
            'Fonts',
          ),
        );
      }
    } else if (Platform.isLinux) {
      dirs.add('/usr/share/fonts');
      dirs.add('/usr/local/share/fonts');
      final String? home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        dirs.add(p.join(home, '.fonts'));
        dirs.add(p.join(home, '.local', 'share', 'fonts'));
      }
    }
    return dirs;
  }
}

List<String> _collectFontNames(List<String> roots) {
  final Set<String> visitedDirs = <String>{};
  final Map<String, String> familiesByLower = <String, String>{};
  for (final String root in roots) {
    _collectDirectoryFontNames(root, visitedDirs, familiesByLower);
  }
  final List<String> fonts = familiesByLower.values.toList(growable: false);
  fonts.sort(
    (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
  );
  return fonts;
}

const Set<String> _supportedFontExtensions = <String>{
  '.ttf',
  '.otf',
  '.ttc',
  '.otc',
  '.dfont',
};

void _collectDirectoryFontNames(
  String rawPath,
  Set<String> visitedDirs,
  Map<String, String> familiesByLower,
) {
  if (rawPath.isEmpty) {
    return;
  }
  final String normalized = p.normalize(rawPath);
  if (!visitedDirs.add(normalized)) {
    return;
  }
  final Directory directory = Directory(normalized);
  if (!directory.existsSync()) {
    return;
  }
  try {
    for (final FileSystemEntity entity in directory.listSync(
      followLinks: false,
    )) {
      if (entity is Directory) {
        _collectDirectoryFontNames(entity.path, visitedDirs, familiesByLower);
        continue;
      }
      if (entity is! File) {
        continue;
      }
      final String ext = p.extension(entity.path).toLowerCase();
      if (!_supportedFontExtensions.contains(ext)) {
        continue;
      }
      final String family = p.basenameWithoutExtension(entity.path).trim();
      if (family.isEmpty) {
        continue;
      }
      familiesByLower.putIfAbsent(family.toLowerCase(), () => family);
    }
  } catch (_) {
    // Ignore directories we cannot traverse.
  }
}
