import 'package:flutter/foundation.dart';
import 'package:misa_rin/utils/io_shim.dart';

Future<void> revealInFileManager(String projectPath) async {
  if (projectPath.isEmpty) {
    return;
  }
  final File file = File(projectPath);
  final Directory directory = file.parent;
  try {
    final bool fileExists = await file.exists();
    final bool directoryExists = await directory.exists();
    if (Platform.isMacOS) {
      if (fileExists) {
        await Process.run('open', ['-R', file.path]);
      } else {
        await Process.run('open', [directory.path]);
      }
    } else if (Platform.isWindows) {
      if (fileExists) {
        await Process.run('explorer.exe', ['/select,', file.path]);
      } else {
        await Process.run('explorer.exe', [directory.path]);
      }
    } else if (Platform.isLinux) {
      final String target = directoryExists
          ? directory.path
          : (fileExists ? file.path : projectPath);
      await Process.run('xdg-open', [target]);
    }
  } catch (error, stackTrace) {
    debugPrint('Failed to reveal project location: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

Future<void> revealDirectoryInFileManager(String directoryPath) async {
  if (directoryPath.isEmpty) {
    return;
  }
  final Directory directory = Directory(directoryPath);
  try {
    final bool directoryExists = await directory.exists();
    final String target = directoryExists ? directory.path : directoryPath;
    if (Platform.isMacOS) {
      await Process.run('open', [target]);
    } else if (Platform.isWindows) {
      await Process.run('explorer.exe', [target]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [target]);
    }
  } catch (error, stackTrace) {
    debugPrint('Failed to reveal directory location: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
