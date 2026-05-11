import 'package:misa_rin/utils/io_shim.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MobileExportPaths {
  static const String _folderName = 'MisaRin';
  static const String _exportFolderName = 'exports';
  static const String _androidExportKey = 'misa_rin.android_export_directory';

  static Future<String?> readAndroidExportDirectory() async {
    if (!Platform.isAndroid) {
      return null;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? value = prefs.getString(_androidExportKey);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  static Future<void> writeAndroidExportDirectory(String? path) async {
    if (!Platform.isAndroid) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String trimmed = path?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(_androidExportKey);
    } else {
      await prefs.setString(_androidExportKey, trimmed);
    }
  }

  static Future<String> resolveExportDirectory({
    bool useAndroidPreference = true,
  }) async {
    if (useAndroidPreference && Platform.isAndroid) {
      final String? stored = await readAndroidExportDirectory();
      if (stored != null) {
        try {
          final Directory directory = Directory(stored);
          if (!await directory.exists()) {
            await directory.create(recursive: true);
          }
          return directory.path;
        } catch (_) {
          // Fall back to app documents directory.
        }
      }
    }

    final Directory base = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(
      p.join(base.path, _folderName, _exportFolderName),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory.path;
  }

  static Future<String> resolveExportPath(
    String fileName, {
    bool useAndroidPreference = true,
  }) async {
    final String directory = await resolveExportDirectory(
      useAndroidPreference: useAndroidPreference,
    );
    return p.join(directory, fileName);
  }
}
