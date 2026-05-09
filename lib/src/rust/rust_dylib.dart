import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:path/path.dart' as p;

const bool _kRustDylibLog = bool.fromEnvironment(
  'MISA_RIN_RUST_DYLIB_LOG',
  defaultValue: false,
);

/// Opens the native Rust library that backs both flutter_rust_bridge APIs and
/// the hand-written dart:ffi shims (brush/blend/filters/etc).
///
/// Why this exists:
/// - On desktop (especially macOS), relying on `DynamicLibrary.process()` can be
///   fragile when the Rust code is packaged as a framework/dylib and loaded via
///   different mechanisms. Explicitly opening the framework binary is more
///   reliable.
/// - On iOS, Rust is linked into the process, so `process()` is the correct
///   handle.
class RustDynamicLibrary {
  RustDynamicLibrary._();

  static ffi.DynamicLibrary open() => _cached;

  static final ffi.DynamicLibrary _cached = _openImpl();

  static ffi.DynamicLibrary _openImpl() {
    if (Platform.isWindows) {
      if (_kRustDylibLog) {
        final String cwd = Directory.current.path;
        final String exeDir = p.dirname(Platform.resolvedExecutable);
        final String cwdDll = p.join(cwd, 'rust_lib_misa_rin.dll');
        final String exeDll = p.join(exeDir, 'rust_lib_misa_rin.dll');
        print(
          'RustDynamicLibrary windows: '
          'cwd=$cwd exists=${File(cwdDll).existsSync()} '
          'exeDir=$exeDir exists=${File(exeDll).existsSync()}',
        );
      }
      return ffi.DynamicLibrary.open('rust_lib_misa_rin.dll');
    }

    // iOS does not allow loading arbitrary dynamic libraries; Rust is linked in.
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }

    // Prefer explicit library paths when available; fall back to `process()`.
    final List<String> candidates = <String>[];

    if (Platform.isMacOS) {
      final String exeDir = p.dirname(Platform.resolvedExecutable);
      candidates.add(
        p.normalize(
          p.join(
            exeDir,
            '..',
            'Frameworks',
            'rust_lib_misa_rin.framework',
            'rust_lib_misa_rin',
          ),
        ),
      );
      candidates.add(
        p.normalize(
          p.join(exeDir, '..', 'Frameworks', 'librust_lib_misa_rin.dylib'),
        ),
      );
      // Dev/test fallback (e.g. `flutter test`).
      candidates.add(
        p.normalize(
          p.join(
            Directory.current.path,
            'rust',
            'target',
            'release',
            'librust_lib_misa_rin.dylib',
          ),
        ),
      );
    } else {
      // Linux / Android: try common SONAMEs.
      candidates.add(
        p.normalize(
          p.join(
            Directory.current.path,
            'rust',
            'target',
            'release',
            'librust_lib_misa_rin.so',
          ),
        ),
      );
      candidates.add('librust_lib_misa_rin.so');
      candidates.add('rust_lib_misa_rin.so');
    }

    for (final String candidate in candidates) {
      try {
        // If it looks like a path, avoid throwing for obvious missing files.
        if (candidate.contains('/') || candidate.contains(r'\')) {
          if (!File(candidate).existsSync()) {
            continue;
          }
        }
        return ffi.DynamicLibrary.open(candidate);
      } catch (_) {
        // Try next candidate.
      }
    }

    return ffi.DynamicLibrary.process();
  }
}
