import 'dart:ffi';
import 'dart:typed_data';

import '../../src/rust/frb_generated.dart';

class NativeMemoryManager {
  static PixelBufferHandle allocate(int size) {
    if (size <= 0) {
      throw ArgumentError.value(size, 'size', 'Must be positive');
    }

    final BigInt ptr = RustLib.instance.api.crateApiMemoryAllocatePixelBuffer(
      size: size,
    );
    final int address = ptr.toInt();
    if (address == 0) {
      throw StateError('Failed to allocate pixel buffer (size=$size)');
    }

    return PixelBufferHandle._(address: address, size: size);
  }
}

class PixelBufferHandle {
  PixelBufferHandle._({required this.address, required this.size})
    : pixels = Pointer<Uint32>.fromAddress(address).asTypedList(size);

  final int address;
  final int size;
  final Uint32List pixels;

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;

    RustLib.instance.api.crateApiMemoryFreePixelBuffer(
      ptr: BigInt.from(address),
      size: size,
    );
  }
}
