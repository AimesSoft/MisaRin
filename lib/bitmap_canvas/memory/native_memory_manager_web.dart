import 'dart:typed_data';

class NativeMemoryManager {
  static PixelBufferHandle allocate(int size) {
    if (size <= 0) {
      throw ArgumentError.value(size, 'size', 'Must be positive');
    }
    return PixelBufferHandle._(size: size);
  }
}

class PixelBufferHandle {
  PixelBufferHandle._({required this.size}) : pixels = Uint32List(size);

  final int address = 0;
  final int size;
  final Uint32List pixels;

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
  }
}
