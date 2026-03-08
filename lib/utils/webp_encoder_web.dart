import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List> encodeWebpRgbaImpl({
  required Uint8List rgba,
  required int width,
  required int height,
  required bool lossless,
  required int quality,
}) async {
  final html.CanvasElement canvas = html.CanvasElement(
    width: width,
    height: height,
  );
  final html.CanvasRenderingContext2D ctx = canvas.context2D;
  final Uint8ClampedList clamped = Uint8ClampedList.fromList(rgba);
  final html.ImageData imageData = html.ImageData(clamped, width, height);
  ctx.putImageData(imageData, 0, 0);

  final double qualityValue =
      (lossless ? 1.0 : quality.clamp(1, 100) / 100.0);
  final html.Blob? blob = await canvas.toBlob('image/webp', qualityValue);
  if (blob == null) {
    throw StateError('导出 WebP 时发生未知错误');
  }

  final Completer<Uint8List> completer = Completer<Uint8List>();
  final html.FileReader reader = html.FileReader();
  reader.onLoad.listen((_) {
    final Object? result = reader.result;
    if (result is ByteBuffer) {
      completer.complete(Uint8List.view(result));
    } else {
      completer.completeError(StateError('导出 WebP 时发生未知错误'));
    }
  });
  reader.onError.listen((_) {
    completer.completeError(StateError('导出 WebP 时发生未知错误'));
  });
  reader.readAsArrayBuffer(blob);
  return completer.future;
}
