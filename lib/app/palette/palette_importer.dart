import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';

class PaletteImportResult {
  PaletteImportResult({required this.name, required List<Color> colors})
    : colors = List<Color>.unmodifiable(colors);

  final String name;
  final List<Color> colors;
}

class PaletteImportException implements Exception {
  PaletteImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PaletteFileImporter {
  const PaletteFileImporter._();

  static const List<String> supportedExtensions = <String>[
    'gpl',
    'ase',
    'aseprite',
    'json',
  ];

  static PaletteImportResult importData(
    Uint8List data, {
    required String extension,
    String? fileName,
  }) {
    final String normalizedExt = extension.toLowerCase();
    for (final _PaletteFileParser parser in _parsers) {
      if (!parser.canHandle(normalizedExt)) {
        continue;
      }
      final PaletteImportResult? result = parser.parse(
        data,
        fileName: fileName,
      );
      if (result != null) {
        return result;
      }
    }
    throw PaletteImportException('暂不支持该调色盘格式 ($extension)。');
  }

  static final List<_PaletteFileParser> _parsers = <_PaletteFileParser>[
    _GimpPaletteParser(),
    _AsepritePaletteParser(),
    _JsonPaletteParser(),
  ];
}

abstract class _PaletteFileParser {
  const _PaletteFileParser(this.extensions);

  final List<String> extensions;

  bool canHandle(String extension) => extensions.contains(extension);

  PaletteImportResult? parse(Uint8List data, {String? fileName});
}

class _GimpPaletteParser extends _PaletteFileParser {
  _GimpPaletteParser() : super(const <String>['gpl']);

  @override
  PaletteImportResult? parse(Uint8List data, {String? fileName}) {
    final String content = _decodeText(data);
    final List<String> lines = content.split(RegExp(r'\r?\n'));
    if (lines.isEmpty ||
        !lines.first.trim().toLowerCase().startsWith('gimp palette')) {
      return null;
    }
    String name = fileName ?? 'GIMP 调色盘';
    final List<Color> colors = <Color>[];
    for (final String raw in lines.skip(1)) {
      final String line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.toLowerCase().startsWith('name:')) {
        name = line.substring('Name:'.length).trim();
        continue;
      }
      if (line.startsWith('#')) {
        continue;
      }
      final List<String> parts = line.split(RegExp(r'\s+'));
      if (parts.length < 3) {
        continue;
      }
      final int? r = int.tryParse(parts[0]);
      final int? g = int.tryParse(parts[1]);
      final int? b = int.tryParse(parts[2]);
      if (r == null || g == null || b == null) {
        continue;
      }
      colors.add(
        Color.fromARGB(0xFF, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255)),
      );
    }
    if (colors.isEmpty) {
      throw PaletteImportException('该 GIMP 调色盘没有有效的颜色数据。');
    }
    return PaletteImportResult(
      name: name.isEmpty ? (fileName ?? '调色盘') : name,
      colors: colors,
    );
  }

  String _decodeText(Uint8List data) {
    try {
      return utf8.decode(data, allowMalformed: true);
    } catch (_) {
      return latin1.decode(data, allowInvalid: true);
    }
  }
}

class _AsepritePaletteParser extends _PaletteFileParser {
  _AsepritePaletteParser() : super(const <String>['ase', 'aseprite']);

  @override
  PaletteImportResult? parse(Uint8List data, {String? fileName}) {
    if (data.lengthInBytes < 128) {
      return null;
    }
    final _ByteReader reader = _ByteReader(data);
    reader.readUint32(); // file size
    final int magic = reader.readUint16();
    if (magic != 0xA5E0) {
      return null;
    }
    final int frameCount = reader.readUint16();
    reader.skip(120); // skip the rest of the header
    final List<Color> colors = <Color>[];
    for (int frame = 0; frame < frameCount; frame++) {
      reader.readUint32(); // frame bytes
      final int frameMagic = reader.readUint16();
      if (frameMagic != 0xF1FA) {
        throw PaletteImportException('无效的 Aseprite 文件。');
      }
      final int oldChunkCount = reader.readUint16();
      reader.readUint16(); // frame duration
      reader.skip(2);
      final int chunkCount = reader.readUint32();
      final int actualChunkCount = chunkCount == 0 ? oldChunkCount : chunkCount;
      for (int chunk = 0; chunk < actualChunkCount; chunk++) {
        final int chunkSize = reader.readUint32();
        final int chunkType = reader.readUint16();
        final int chunkDataEnd = reader.offset + chunkSize - 6;
        if (chunkType == 0x2019) {
          colors.clear();
          colors.addAll(_readPaletteChunk(reader));
          // No need to parse further chunks.
          return PaletteImportResult(
            name: fileName ?? 'Aseprite 调色盘',
            colors: colors,
          );
        } else if (chunkType == 0x0004 || chunkType == 0x0011) {
          colors.clear();
          colors.addAll(
            _readOldPaletteChunk(reader, isSixBit: chunkType == 0x0011),
          );
          return PaletteImportResult(
            name: fileName ?? 'Aseprite 调色盘',
            colors: colors,
          );
        }
        reader.seek(chunkDataEnd);
      }
    }
    throw PaletteImportException('文件中不包含可用的调色盘。');
  }

  List<Color> _readPaletteChunk(_ByteReader reader) {
    final int paletteSize = reader.readUint32();
    reader.readUint32(); // first color index
    reader.readUint32(); // last color index
    reader.skip(8);
    final List<Color> colors = <Color>[];
    for (int i = 0; i < paletteSize; i++) {
      final int flags = reader.readUint16();
      final int r = reader.readUint8();
      final int g = reader.readUint8();
      final int b = reader.readUint8();
      final int a = reader.readUint8();
      if ((flags & 0x0001) != 0) {
        reader.readString();
      }
      colors.add(Color.fromARGB(a, r, g, b));
    }
    if (colors.isEmpty) {
      throw PaletteImportException('Aseprite 调色盘为空。');
    }
    return colors;
  }

  List<Color> _readOldPaletteChunk(
    _ByteReader reader, {
    required bool isSixBit,
  }) {
    final int packetCount = reader.readUint16();
    final List<Color?> entries = List<Color?>.filled(256, null);
    int index = 0;
    for (int packet = 0; packet < packetCount; packet++) {
      final int skip = reader.readUint8();
      index = math.min(entries.length, index + skip);
      int colorCount = reader.readUint8();
      if (colorCount == 0) {
        colorCount = 256;
      }
      for (int i = 0; i < colorCount; i++) {
        final int r = reader.readUint8();
        final int g = reader.readUint8();
        final int b = reader.readUint8();
        if (index >= entries.length) {
          continue;
        }
        entries[index] = Color.fromARGB(
          0xFF,
          isSixBit ? _expand6BitChannel(r) : r,
          isSixBit ? _expand6BitChannel(g) : g,
          isSixBit ? _expand6BitChannel(b) : b,
        );
        index++;
      }
    }
    final List<Color> colors = entries.whereType<Color>().toList(
      growable: false,
    );
    if (colors.isEmpty) {
      throw PaletteImportException('该 Aseprite 调色盘没有有效颜色。');
    }
    return colors;
  }

  int _expand6BitChannel(int value) {
    final int scaled = (value & 0x3F) * 255 ~/ 63;
    return scaled.clamp(0, 255);
  }
}

class _JsonPaletteParser extends _PaletteFileParser {
  _JsonPaletteParser() : super(const <String>['json']);

  @override
  PaletteImportResult? parse(Uint8List data, {String? fileName}) {
    final Object? root;
    try {
      root = jsonDecode(utf8.decode(data, allowMalformed: true));
    } on FormatException {
      throw PaletteImportException('JSON 文件格式无效。');
    } catch (_) {
      throw PaletteImportException('无法读取 JSON 调色盘。');
    }
    if (root is! Map<String, dynamic>) {
      throw PaletteImportException('JSON 调色盘根节点必须是对象。');
    }

    final Object? rawColors = root['colors'];
    if (rawColors is! List<dynamic>) {
      throw PaletteImportException('JSON 调色盘缺少 colors 数组。');
    }
    final List<Color> colors = <Color>[];
    for (final Object? raw in rawColors) {
      final Color? parsed = _parseJsonColor(raw);
      if (parsed != null) {
        colors.add(parsed);
      }
    }
    if (colors.isEmpty) {
      throw PaletteImportException('JSON 调色盘没有有效颜色。');
    }

    final String name = _resolvePaletteName(root['name'], fileName: fileName);
    return PaletteImportResult(name: name, colors: colors);
  }

  String _resolvePaletteName(Object? raw, {String? fileName}) {
    if (raw is String) {
      final String trimmed = raw.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    if (fileName != null && fileName.trim().isNotEmpty) {
      return fileName.trim();
    }
    return 'JSON 调色盘';
  }

  Color? _parseJsonColor(Object? raw) {
    if (raw is String) {
      return _parseHexColor(raw);
    }
    if (raw is Map<String, dynamic>) {
      final Object? hex = raw['hex'] ?? raw['color'] ?? raw['value'];
      if (hex is String) {
        return _parseHexColor(hex);
      }
      final int? r = _parseChannel(raw['r'] ?? raw['red']);
      final int? g = _parseChannel(raw['g'] ?? raw['green']);
      final int? b = _parseChannel(raw['b'] ?? raw['blue']);
      final int? a = _parseChannel(raw['a'] ?? raw['alpha'], isAlpha: true);
      if (r == null || g == null || b == null) {
        return null;
      }
      return Color.fromARGB(a ?? 0xFF, r, g, b);
    }
    if (raw is List<dynamic>) {
      if (raw.length < 3) {
        return null;
      }
      final int? r = _parseChannel(raw[0]);
      final int? g = _parseChannel(raw[1]);
      final int? b = _parseChannel(raw[2]);
      final int? a = raw.length >= 4
          ? _parseChannel(raw[3], isAlpha: true)
          : 0xFF;
      if (r == null || g == null || b == null || a == null) {
        return null;
      }
      return Color.fromARGB(a, r, g, b);
    }
    return null;
  }

  int? _parseChannel(Object? raw, {bool isAlpha = false}) {
    if (raw is int) {
      return raw.clamp(0, 255).toInt();
    }
    if (raw is double) {
      if (!raw.isFinite) {
        return null;
      }
      final double scaled = (isAlpha && raw >= 0 && raw <= 1) ? raw * 255 : raw;
      return scaled.round().clamp(0, 255).toInt();
    }
    if (raw is String) {
      final String trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final num? parsed = num.tryParse(trimmed);
      if (parsed == null) {
        return null;
      }
      final double value = parsed.toDouble();
      if (!value.isFinite) {
        return null;
      }
      final double scaled = (isAlpha && value >= 0 && value <= 1)
          ? value * 255
          : value;
      return scaled.round().clamp(0, 255).toInt();
    }
    return null;
  }

  Color? _parseHexColor(String raw) {
    String normalized = raw.trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    } else if (normalized.startsWith('0x') || normalized.startsWith('0X')) {
      normalized = normalized.substring(2);
    }
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.length == 3) {
      final String r = normalized[0];
      final String g = normalized[1];
      final String b = normalized[2];
      normalized = '$r$r$g$g$b$b';
    }
    if (normalized.length == 6) {
      normalized = 'FF$normalized';
    } else if (normalized.length != 8) {
      return null;
    }
    final int? argb = int.tryParse(normalized, radix: 16);
    if (argb == null) {
      return null;
    }
    final int a = (argb >> 24) & 0xFF;
    final int r = (argb >> 16) & 0xFF;
    final int g = (argb >> 8) & 0xFF;
    final int b = argb & 0xFF;
    return Color.fromARGB(a, r, g, b);
  }
}

class _ByteReader {
  _ByteReader(Uint8List data)
    : _data = ByteData.sublistView(data),
      _bytes = Uint8List.sublistView(data);

  final ByteData _data;
  final Uint8List _bytes;
  int _offset = 0;

  int get offset => _offset;

  void seek(int position) {
    _offset = math.max(0, math.min(_data.lengthInBytes, position));
  }

  void skip(int bytes) {
    seek(_offset + bytes);
  }

  int readUint8() {
    final int value = _data.getUint8(_offset);
    _offset += 1;
    return value;
  }

  int readUint16() {
    final int value = _data.getUint16(_offset, Endian.little);
    _offset += 2;
    return value;
  }

  int readUint32() {
    final int value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  String readString() {
    final int length = readUint16();
    if (length <= 0) {
      return '';
    }
    if (_offset + length > _bytes.lengthInBytes) {
      throw PaletteImportException('字符串长度超出文件范围。');
    }
    final Uint8List slice = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    return utf8.decode(slice, allowMalformed: true);
  }
}
