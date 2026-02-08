import 'dart:typed_data';

class NativeMemoryManager {
  static PixelBufferHandle allocate(int size) {
    if (size <= 0) {
      throw ArgumentError.value(size, 'size', 'Must be positive');
    }

    return PixelBufferHandle._(Uint32List(size));
  }
}

class PixelBufferHandle {
  PixelBufferHandle._(this.pixels);

  final Uint32List pixels;

  int get address => 0;
  int get size => pixels.length;

  void dispose() {}
}
