import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

const _libwebpRepo = 'https://github.com/swipelab/libwebp.git';

String _getCacheDir() {
  final customCache = Platform.environment['SWIPELAB_WEBP_CACHE_DIR'];
  if (customCache != null && customCache.isNotEmpty) {
    return customCache;
  }

  if (Platform.isWindows) {
    // Prefer a short writable temp path on CI to reduce Windows path length risk.
    final runnerTemp = Platform.environment['RUNNER_TEMP'];
    if (runnerTemp != null && runnerTemp.isNotEmpty) {
      return '$runnerTemp\\swipelab_webp';
    }

    final temp = Platform.environment['TEMP'];
    if (temp != null && temp.isNotEmpty) {
      return '$temp\\swipelab_webp';
    }

    // Fallback to LOCALAPPDATA (e.g., C:\Users\<user>\AppData\Local)
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      return '$localAppData\\swipelab_webp';
    }

    // Last resort fallback to USERPROFILE.
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    return '$userProfile\\.cache\\swipelab_webp';
  }

  // Unix-like systems (macOS, Linux)
  final home = Platform.environment['HOME'] ?? '';
  return '$home/.cache/swipelab_webp';
}

List<String> _collectSources(
  String directoryPath,
) {
  return Directory(directoryPath)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.c'))
      .map((f) => f.path)
      .toList();
}

Future<String> _ensureLibwebp(Logger logger) async {
  final cacheDir = _getCacheDir();
  final separator = Platform.isWindows ? '\\' : '/';
  final libwebpPath = '$cacheDir${separator}libwebp';

  if (Directory(libwebpPath).existsSync()) {
    logger.info('libwebp found at $libwebpPath');
    return libwebpPath;
  }

  logger.info('libwebp not found, cloning from $_libwebpRepo...');

  // Create cache directory if it doesn't exist
  await Directory(cacheDir).create(recursive: true);

  // Clone libwebp
  final result = await Process.run(
    'git',
    ['clone', '--depth', '1', _libwebpRepo, libwebpPath],
    workingDirectory: cacheDir,
  );

  if (result.exitCode != 0) {
    throw Exception(
      'Failed to clone libwebp: ${result.stderr}\n'
      'Please ensure git is installed and you have internet access.\n'
      'Alternatively, manually clone $_libwebpRepo to $libwebpPath',
    );
  }

  logger.info('libwebp cloned successfully to $libwebpPath');
  return libwebpPath;
}

void main(List<String> args) async {
  await build(args, (input, output) async {
    final logger = Logger('')
      ..level = Level.ALL
      ..onRecord.listen((record) => print(record.message));

    final packageName = input.packageName;
    final targetOS = input.config.code.targetOS;

    // Ensure libwebp is available (clone if needed)
    final libwebpPath = await _ensureLibwebp(logger);

    // Collect all libwebp source files
    final webpSources = <String>[
      // Our wrapper
      'src/swipelab_webp.c',
      // sharpyuv
      ..._collectSources('$libwebpPath/sharpyuv'),
      // src/enc
      ..._collectSources('$libwebpPath/src/enc'),
      // src/dsp
      ..._collectSources('$libwebpPath/src/dsp'),
      // src/utils
      ..._collectSources('$libwebpPath/src/utils'),
    ];

    final builder = CBuilder.library(
      name: packageName,
      assetName: 'swipelab_webp.dart',
      sources: webpSources,
      includes: [
        libwebpPath,
        '$libwebpPath/src',
      ],
      defines: const {
        'WEBP_USE_THREAD': '1',
        'WEBP_NEAR_LOSSLESS': '1',
      },
      // Link against libm for math functions (not needed on Windows)
      libraries: targetOS == OS.windows ? [] : ['m'],
    );

    await builder.run(
      input: input,
      output: output,
      logger: logger,
    );
  });
}
