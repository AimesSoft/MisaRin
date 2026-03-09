import 'dart:ffi';
import 'dart:typed_data';

import '../../src/rust/rust_dylib.dart';

typedef _AllocNative = Pointer<Uint32> Function(UintPtr len);
typedef _AllocDart = Pointer<Uint32> Function(int len);
typedef _FreeNative = Void Function(Pointer<Uint32> ptr, UintPtr len);
typedef _FreeDart = void Function(Pointer<Uint32> ptr, int len);

class NativeMemoryManager {
  static final DynamicLibrary _lib = RustDynamicLibrary.open();
  static final _AllocDart _alloc =
      _lib.lookupFunction<_AllocNative, _AllocDart>('misarin_alloc_pixel_buffer');
  static final _FreeDart _free =
      _lib.lookupFunction<_FreeNative, _FreeDart>('misarin_free_pixel_buffer');

  static PixelBufferHandle allocate(int size) {
    if (size <= 0) {
      throw ArgumentError.value(size, 'size', 'Must be positive');
    }

    final Pointer<Uint32> ptr = _alloc(size);
    if (ptr == nullptr) {
      throw StateError('Failed to allocate pixel buffer (size=$size)');
    }

    return PixelBufferHandle._(ptr: ptr, size: size);
  }
}

class PixelBufferHandle {
  PixelBufferHandle._({required this.ptr, required this.size})
    : pixels = ptr.asTypedList(size);

  final Pointer<Uint32> ptr;
  final int size;
  final Uint32List pixels;
  int get address => ptr.address;

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;

    NativeMemoryManager._free(ptr, size);
  }
}
