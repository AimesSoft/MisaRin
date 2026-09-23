part of 'app_preferences.dart';

Future<Uint8List?> _readPreferencesPayload() async {
  final File file = await _preferencesFile();
  if (!await file.exists()) {
    return null;
  }
  return file.readAsBytes();
}

Future<void> _writePreferencesPayload(Uint8List bytes) async {
  final File file = await _preferencesFile();
  await file.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

Future<File> _preferencesFile() async {
  final base = await getApplicationDocumentsDirectory();
  final Directory directory = Directory(p.join(base.path, _folderName));
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return File(p.join(directory.path, _fileName));
}
