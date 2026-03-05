import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart' as svg;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../canvas/canvas_tools.dart';
import '../l10n/app_localizations.dart';
import '../utils/io_shim.dart';
import 'brush_shape_raster.dart';

Uint8List _byteDataToUint8List(ByteData data) {
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

enum BrushShapeFileType { svg, png }

enum BrushShapeSource { builtIn, user, imported }

class BrushShapeDefinition {
  const BrushShapeDefinition({
    required this.id,
    required this.name,
    required this.type,
    required this.source,
    this.assetPath,
    this.filePath,
    this.builtInShape,
  });

  final String id;
  final String name;
  final BrushShapeFileType type;
  final BrushShapeSource source;
  final String? assetPath;
  final String? filePath;
  final BrushShape? builtInShape;

  bool get isBuiltIn => builtInShape != null;
}

class BrushShapeLibrary {
  BrushShapeLibrary._({
    required List<BrushShapeDefinition> shapes,
    required Directory? shapeDirectory,
  }) : _shapes = shapes,
       _shapeDirectory = shapeDirectory;

  static const String _folderName = 'MisaRin';
  static const String _shapeFolderName = 'brush_shapes';

  static const List<_BuiltInShapeAsset> _builtInShapes = <_BuiltInShapeAsset>[
    _BuiltInShapeAsset(
      id: 'circle',
      assetPath: 'assets/brush_shapes/circle.svg',
      type: BrushShapeFileType.svg,
      builtInShape: BrushShape.circle,
    ),
    _BuiltInShapeAsset(
      id: 'square',
      assetPath: 'assets/brush_shapes/square.svg',
      type: BrushShapeFileType.svg,
      builtInShape: BrushShape.square,
    ),
    _BuiltInShapeAsset(
      id: 'triangle',
      assetPath: 'assets/brush_shapes/triangle.svg',
      type: BrushShapeFileType.svg,
      builtInShape: BrushShape.triangle,
    ),
    _BuiltInShapeAsset(
      id: 'star',
      assetPath: 'assets/brush_shapes/star.svg',
      type: BrushShapeFileType.svg,
      builtInShape: BrushShape.star,
    ),
  ];

  final List<BrushShapeDefinition> _shapes;
  final Directory? _shapeDirectory;
  final Map<String, BrushShapeRaster> _rasterCache =
      <String, BrushShapeRaster>{};

  List<BrushShapeDefinition> get shapes =>
      List<BrushShapeDefinition>.unmodifiable(_shapes);

  BrushShapeDefinition? resolve(String id) {
    for (final BrushShapeDefinition shape in _shapes) {
      if (shape.id == id) {
        return shape;
      }
    }
    return null;
  }

  bool isBuiltInId(String? id) {
    if (id == null || id.isEmpty) {
      return false;
    }
    for (final _BuiltInShapeAsset shape in _builtInShapes) {
      if (shape.id == id) {
        return true;
      }
    }
    return false;
  }

  BrushShapeRaster? getCachedRaster(String id) => _rasterCache[id];

  Future<BrushShapeRaster?> loadRaster(String id, {int? size}) async {
    if (id.isEmpty) {
      return null;
    }
    final BrushShapeRaster? cached = _rasterCache[id];
    if (cached != null) {
      return cached;
    }
    final BrushShapeDefinition? shape = resolve(id);
    if (shape == null) {
      return null;
    }
    final Uint8List bytes = await _loadShapeBytes(shape);
    if (bytes.isEmpty) {
      return null;
    }
    final ui.Image? image = await _decodeShapeImage(shape, bytes, size);
    if (image == null) {
      return null;
    }
    try {
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) {
        return null;
      }
      final Uint8List rgba = data.buffer.asUint8List();
      final int pixelCount = image.width * image.height;
      final Uint8List alpha = Uint8List(pixelCount);
      for (int i = 0; i < pixelCount; i++) {
        alpha[i] = rgba[i * 4 + 3];
      }
      final Uint8List softAlpha = _blurAlpha(alpha, image.width, image.height);
      final BrushShapeRaster raster = BrushShapeRaster(
        id: shape.id,
        width: image.width,
        height: image.height,
        alpha: alpha,
        softAlpha: softAlpha,
      );
      _rasterCache[id] = raster;
      return raster;
    } finally {
      image.dispose();
    }
  }

  Future<Uint8List> loadShapeBytes(String id) async {
    final BrushShapeDefinition? shape = resolve(id);
    if (shape == null) {
      return Uint8List(0);
    }
    return _loadShapeBytes(shape);
  }

  Future<BrushShapeDefinition?> importShapeBytes({
    required String id,
    required Uint8List bytes,
    required BrushShapeFileType type,
    BrushShapeSource source = BrushShapeSource.imported,
  }) async {
    if (kIsWeb) {
      return null;
    }
    final Directory? directory =
        _shapeDirectory ?? await _resolveShapeDirectory();
    if (directory == null) {
      return null;
    }
    await directory.create(recursive: true);
    final String sanitized = _sanitizeId(id);
    final String extension = type == BrushShapeFileType.svg ? 'svg' : 'png';
    String fileName = '$sanitized.$extension';
    File file = File(p.join(directory.path, fileName));
    if (await file.exists()) {
      final Uint8List existing = await file.readAsBytes();
      if (!_shapeBytesEqual(existing, bytes, type)) {
        final String prefix = '${sanitized}_';
        await for (final FileSystemEntity entry in directory.list()) {
          if (entry is! File) {
            continue;
          }
          final String entryName = p.basename(entry.path);
          if (!entryName.startsWith(prefix)) {
            continue;
          }
          if (p.extension(entryName).toLowerCase() != '.$extension') {
            continue;
          }
          final Uint8List entryBytes = await entry.readAsBytes();
          if (_shapeBytesEqual(entryBytes, bytes, type)) {
            await refresh();
            return resolve(p.basenameWithoutExtension(entry.path));
          }
        }
        int suffix = 2;
        while (await file.exists()) {
          fileName = '${sanitized}_$suffix.$extension';
          file = File(p.join(directory.path, fileName));
          suffix += 1;
        }
      }
    }
    await file.writeAsBytes(bytes, flush: true);
    await refresh();
    return resolve(p.basenameWithoutExtension(file.path));
  }

  String labelFor(AppLocalizations l10n, String id) {
    final BrushShapeDefinition? shape = resolve(id);
    if (shape?.builtInShape != null) {
      switch (shape!.builtInShape!) {
        case BrushShape.circle:
          return l10n.circle;
        case BrushShape.triangle:
          return l10n.triangle;
        case BrushShape.square:
          return l10n.square;
        case BrushShape.star:
          return l10n.star;
      }
    }
    return shape?.name ?? id;
  }

  Future<String?> resolveShapeDirectoryPath() async {
    if (kIsWeb) {
      return null;
    }
    final Directory? directory =
        _shapeDirectory ?? await _resolveShapeDirectory();
    return directory?.path;
  }

  Future<void> refresh() async {
    if (kIsWeb) {
      return;
    }
    final Directory? directory =
        _shapeDirectory ?? await _resolveShapeDirectory();
    if (directory == null) {
      return;
    }
    _shapes
      ..clear()
      ..addAll(await _scanShapes(directory));
    _shapes.sort((a, b) => a.name.compareTo(b.name));
  }

  static Future<BrushShapeLibrary> load() async {
    if (kIsWeb) {
      final List<BrushShapeDefinition> shapes = _builtInShapes
          .map((shape) => shape.toDefinition())
          .toList();
      return BrushShapeLibrary._(shapes: shapes, shapeDirectory: null);
    }
    final Directory? directory = await _resolveShapeDirectory();
    if (directory == null) {
      return BrushShapeLibrary._(
        shapes: const <BrushShapeDefinition>[],
        shapeDirectory: null,
      );
    }
    await directory.create(recursive: true);
    await _copyDefaultShapes(directory);
    final List<BrushShapeDefinition> shapes = await _scanShapes(directory);
    shapes.sort((a, b) => a.name.compareTo(b.name));
    return BrushShapeLibrary._(shapes: shapes, shapeDirectory: directory);
  }

  static Future<Directory?> _resolveShapeDirectory() async {
    if (kIsWeb) {
      return null;
    }
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, _folderName, _shapeFolderName));
  }

  static Future<void> _copyDefaultShapes(Directory directory) async {
    for (final _BuiltInShapeAsset shape in _builtInShapes) {
      final String extension = shape.type == BrushShapeFileType.svg
          ? 'svg'
          : 'png';
      final File target = File(
        p.join(directory.path, '${shape.id}.$extension'),
      );
      if (await target.exists()) {
        continue;
      }
      final ByteData data = await rootBundle.load(shape.assetPath);
      await target.writeAsBytes(_byteDataToUint8List(data), flush: true);
    }
  }

  static Future<List<BrushShapeDefinition>> _scanShapes(
    Directory directory,
  ) async {
    final List<BrushShapeDefinition> shapes = <BrushShapeDefinition>[];
    final List<FileSystemEntity> entries = await directory.list().toList();
    for (final FileSystemEntity entry in entries) {
      if (entry is! File) {
        continue;
      }
      final String extension = p.extension(entry.path).toLowerCase();
      final BrushShapeFileType? type = switch (extension) {
        '.svg' => BrushShapeFileType.svg,
        '.png' => BrushShapeFileType.png,
        _ => null,
      };
      if (type == null) {
        continue;
      }
      final String id = p.basenameWithoutExtension(entry.path);
      final _BuiltInShapeAsset? builtIn = _builtInShapes
          .cast<_BuiltInShapeAsset?>()
          .firstWhere((shape) => shape?.id == id, orElse: () => null);
      shapes.add(
        BrushShapeDefinition(
          id: id,
          name: _titleCaseId(id),
          type: type,
          source: builtIn != null
              ? BrushShapeSource.builtIn
              : BrushShapeSource.user,
          assetPath: builtIn?.assetPath,
          filePath: entry.path,
          builtInShape: builtIn?.builtInShape,
        ),
      );
    }
    if (shapes.isEmpty) {
      for (final _BuiltInShapeAsset shape in _builtInShapes) {
        shapes.add(shape.toDefinition());
      }
    }
    return shapes;
  }

  static String _sanitizeId(String id) {
    final StringBuffer buffer = StringBuffer();
    for (final int rune in id.runes) {
      final int code = rune;
      final bool ok =
          (code >= 48 && code <= 57) ||
          (code >= 65 && code <= 90) ||
          (code >= 97 && code <= 122) ||
          code == 45 ||
          code == 95;
      buffer.write(ok ? String.fromCharCode(code) : '_');
    }
    final String sanitized = buffer.toString();
    return sanitized.isEmpty ? 'shape' : sanitized;
  }

  static String _titleCaseId(String id) {
    if (id.isEmpty) {
      return id;
    }
    final String replaced = id.replaceAll('_', ' ').replaceAll('-', ' ');
    return replaced[0].toUpperCase() + replaced.substring(1);
  }

  Future<Uint8List> _loadShapeBytes(BrushShapeDefinition shape) async {
    if (!kIsWeb && shape.filePath != null) {
      final File file = File(shape.filePath!);
      if (await file.exists()) {
        return file.readAsBytes();
      }
    }
    if (shape.assetPath != null) {
      final ByteData data = await rootBundle.load(shape.assetPath!);
      return _byteDataToUint8List(data);
    }
    return Uint8List(0);
  }

  Future<ui.Image?> _decodeShapeImage(
    BrushShapeDefinition shape,
    Uint8List bytes,
    int? size,
  ) async {
    if (shape.type == BrushShapeFileType.png) {
      final int? target = size != null && size > 0 ? size : null;
      final ui.Codec codec = target == null
          ? await ui.instantiateImageCodec(bytes)
          : await ui.instantiateImageCodec(
              bytes,
              targetWidth: target,
              targetHeight: target,
            );
      final ui.FrameInfo frame = await codec.getNextFrame();
      return frame.image;
    }
    try {
      final int rasterSize = size != null && size > 0 ? size : 128;
      final svg.PictureInfo pictureInfo = await svg.vg.loadPicture(
        svg.SvgBytesLoader(bytes),
        null,
      );
      final ui.Picture picture = pictureInfo.picture;
      final ui.Size sourceSize = pictureInfo.size;
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      if (sourceSize.width > 0 && sourceSize.height > 0) {
        final double scaleX = rasterSize / sourceSize.width;
        final double scaleY = rasterSize / sourceSize.height;
        final double scale = math.min(scaleX, scaleY);
        final double dx = (rasterSize - sourceSize.width * scale) * 0.5;
        final double dy = (rasterSize - sourceSize.height * scale) * 0.5;
        canvas.translate(dx, dy);
        canvas.scale(scale, scale);
      }
      canvas.drawPicture(picture);
      final ui.Picture scaledPicture = recorder.endRecording();
      final ui.Image image = await scaledPicture.toImage(
        rasterSize,
        rasterSize,
      );
      picture.dispose();
      scaledPicture.dispose();
      return image;
    } catch (_) {
      return null;
    }
  }

  static Uint8List _blurAlpha(Uint8List src, int width, int height) {
    final Uint8List out = Uint8List(src.length);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int sum = 0;
        int count = 0;
        for (int dy = -1; dy <= 1; dy++) {
          final int yy = y + dy;
          if (yy < 0 || yy >= height) {
            continue;
          }
          for (int dx = -1; dx <= 1; dx++) {
            final int xx = x + dx;
            if (xx < 0 || xx >= width) {
              continue;
            }
            sum += src[yy * width + xx];
            count += 1;
          }
        }
        out[y * width + x] = (sum / count).round().clamp(0, 255);
      }
    }
    return out;
  }

  static bool _shapeBytesEqual(
    Uint8List a,
    Uint8List b,
    BrushShapeFileType type,
  ) {
    if (type == BrushShapeFileType.svg) {
      final Uint8List normalizedA = _normalizeLineEndings(a);
      final Uint8List normalizedB = _normalizeLineEndings(b);
      return _bytesEqual(normalizedA, normalizedB);
    }
    return _bytesEqual(a, b);
  }

  static Uint8List _normalizeLineEndings(Uint8List bytes) {
    bool changed = false;
    final Uint8List out = Uint8List(bytes.length);
    int outIndex = 0;
    int i = 0;
    while (i < bytes.length) {
      final int byte = bytes[i++];
      if (byte == 0x0d) {
        changed = true;
        if (i < bytes.length && bytes[i] == 0x0a) {
          i += 1;
        }
        out[outIndex++] = 0x0a;
        continue;
      }
      out[outIndex++] = byte;
    }
    if (!changed) {
      return bytes;
    }
    if (outIndex == out.length) {
      return out;
    }
    return Uint8List.sublistView(out, 0, outIndex);
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

class _BuiltInShapeAsset {
  const _BuiltInShapeAsset({
    required this.id,
    required this.assetPath,
    required this.type,
    required this.builtInShape,
  });

  final String id;
  final String assetPath;
  final BrushShapeFileType type;
  final BrushShape builtInShape;

  BrushShapeDefinition toDefinition() {
    return BrushShapeDefinition(
      id: id,
      name: BrushShapeLibrary._titleCaseId(id),
      type: type,
      source: BrushShapeSource.builtIn,
      assetPath: assetPath,
      filePath: null,
      builtInShape: builtInShape,
    );
  }
}
