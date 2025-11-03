import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import '../../canvas/canvas_layer.dart';
import '../../canvas/canvas_settings.dart';
import 'project_document.dart';

class ProjectBinaryCodec {
  static const String _magic = 'MISARIN';
  static const int _version = 3;

  static Uint8List encode(ProjectDocument document) {
    final BytesBuilder builder = BytesBuilder();
    builder.add(utf8.encode(_magic));
    builder.addByte(_version);

    final Map<String, dynamic> metadata = <String, dynamic>{
      'id': document.id,
      'name': document.name,
      'createdAt': document.createdAt.toIso8601String(),
      'updatedAt': document.updatedAt.toIso8601String(),
      'settings': <String, dynamic>{
        'width': document.settings.width,
        'height': document.settings.height,
        'backgroundColor': _encodeColor(document.settings.backgroundColor),
      },
      'bucketSampleAllLayers': document.bucketSampleAllLayers,
      'bucketContiguous': document.bucketContiguous,
    };

    final Uint8List metadataBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(metadata)),
    );
    builder.add(_writeUint32(metadataBytes.length));
    builder.add(metadataBytes);

    final Uint8List layerBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(_encodeLayers(document.layers))),
    );
    builder.add(_writeUint32(layerBytes.length));
    builder.add(layerBytes);

    final Uint8List preview = document.previewBytes ?? Uint8List(0);
    builder.add(_writeUint32(preview.length));
    if (preview.isNotEmpty) {
      builder.add(preview);
    }

    return builder.toBytes();
  }

  static ProjectDocument decode(Uint8List bytes, {String? path}) {
    final _ByteReader reader = _ByteReader(bytes);
    reader.expectMagic(_magic);
    final int version = reader.readByte();
    if (version < 1 || version > _version) {
      throw UnsupportedError('不支持的项目文件版本：$version');
    }

    final int metadataLength = reader.readUint32();
    final Map<String, dynamic> metadata =
        jsonDecode(utf8.decode(reader.readBytes(metadataLength)))
            as Map<String, dynamic>;

    late final List<CanvasLayerData> layers;
    if (version == 1) {
      final int strokesLength = reader.readUint32();
      final List<List<Offset>> strokes = _decodeStrokes(
        reader.readBytes(strokesLength),
      );
      layers = _legacyLayers(
        settings: _parseSettings(metadata['settings'] as Map<String, dynamic>),
        strokes: strokes,
      );
    } else {
      final int layersLength = reader.readUint32();
      layers = _decodeLayers(reader.readBytes(layersLength));
    }
    final int previewLength = reader.readUint32();
    final Uint8List? preview = previewLength == 0
        ? null
        : reader.readBytes(previewLength);

    final bool bucketSampleAllLayers = _readBool(
      metadata,
      'bucketSampleAllLayers',
      fallback: false,
    );
    final bool bucketContiguous = _readBool(
      metadata,
      'bucketContiguous',
      fallback: true,
    );

    return ProjectDocument(
      id: metadata['id'] as String,
      name: metadata['name'] as String,
      createdAt: DateTime.parse(metadata['createdAt'] as String),
      updatedAt: DateTime.parse(metadata['updatedAt'] as String),
      settings: _parseSettings(metadata['settings'] as Map<String, dynamic>),
      layers: layers,
      previewBytes: preview,
      path: path,
      bucketSampleAllLayers: bucketSampleAllLayers,
      bucketContiguous: bucketContiguous,
    );
  }

  static ProjectSummary decodeSummary(
    Uint8List bytes, {
    required String path,
    DateTime? lastOpened,
  }) {
    final _ByteReader reader = _ByteReader(bytes);
    reader.expectMagic(_magic);
    final int version = reader.readByte();
    if (version < 1 || version > _version) {
      throw UnsupportedError('不支持的项目文件版本：$version');
    }

    final int metadataLength = reader.readUint32();
    final Map<String, dynamic> metadata =
        jsonDecode(utf8.decode(reader.readBytes(metadataLength)))
            as Map<String, dynamic>;

    if (version == 1) {
      final int strokesLength = reader.readUint32();
      reader.skip(strokesLength);
    } else {
      final int layersLength = reader.readUint32();
      reader.skip(layersLength);
    }

    final int previewLength = reader.readUint32();
    final Uint8List? preview = previewLength == 0
        ? null
        : reader.readBytes(previewLength);

    final DateTime updatedAt = DateTime.parse(metadata['updatedAt'] as String);
    return ProjectSummary(
      id: metadata['id'] as String,
      name: metadata['name'] as String,
      path: path,
      updatedAt: updatedAt,
      lastOpened: lastOpened ?? updatedAt,
      settings: _parseSettings(metadata['settings'] as Map<String, dynamic>),
      previewBytes: preview,
    );
  }

  static CanvasSettings _parseSettings(Map<String, dynamic> json) {
    return CanvasSettings(
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      backgroundColor: Color(json['backgroundColor'] as int),
    );
  }

  static List<List<Offset>> _decodeStrokes(Uint8List bytes) {
    final _ByteReader reader = _ByteReader(bytes);
    final int strokeCount = reader.readUint32();
    final List<List<Offset>> strokes = <List<Offset>>[];
    for (int i = 0; i < strokeCount; i++) {
      final int pointCount = reader.readUint32();
      final List<Offset> stroke = <Offset>[];
      for (int j = 0; j < pointCount; j++) {
        final double dx = reader.readFloat32();
        final double dy = reader.readFloat32();
        stroke.add(Offset(dx, dy));
      }
      strokes.add(stroke);
    }
    return strokes;
  }

  static List<Map<String, dynamic>> _encodeLayers(
    List<CanvasLayerData> layers,
  ) {
    return layers.map((layer) => layer.toJson()).toList(growable: false);
  }

  static List<CanvasLayerData> _decodeLayers(Uint8List bytes) {
    final List<dynamic> jsonList =
        jsonDecode(utf8.decode(bytes)) as List<dynamic>;
    return jsonList
        .map((dynamic entry) => CanvasLayerData.fromJson(
              entry as Map<String, dynamic>,
            ))
        .toList(growable: false);
  }

  static bool _readBool(
    Map<String, dynamic> json,
    String key, {
    required bool fallback,
  }) {
    final dynamic value = json[key];
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    return fallback;
  }

  static List<CanvasLayerData> _legacyLayers({
    required CanvasSettings settings,
    required List<List<Offset>> strokes,
  }) {
    final String backgroundId = generateLayerId();
    return <CanvasLayerData>[
      CanvasLayerData(
        id: backgroundId,
        name: '图层 1',
        fillColor: settings.backgroundColor,
      ),
      if (strokes.isNotEmpty)
        CanvasLayerData(
          id: generateLayerId(),
          name: '图层 2',
          strokes: strokes
              .map(
                (points) => CanvasStroke(
                  color: const Color(0xFF000000),
                  width: 3,
                  points: List<Offset>.from(points),
                ),
              )
              .toList(growable: false),
        ),
    ];
  }

  static Uint8List _writeUint32(int value) {
    final ByteData data = ByteData(4);
    data.setUint32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  static int _encodeColor(Color color) {
    final int alpha = (color.a * 255.0).round() & 0xff;
    final int red = (color.r * 255.0).round() & 0xff;
    final int green = (color.g * 255.0).round() & 0xff;
    final int blue = (color.b * 255.0).round() & 0xff;
    return (alpha << 24) | (red << 16) | (green << 8) | blue;
  }
}

class _ByteReader {
  _ByteReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  void expectMagic(String magic) {
    final List<int> expected = utf8.encode(magic);
    final List<int> actual = readBytes(expected.length);
    if (expected.length != actual.length) {
      throw const FormatException('项目文件头部损坏');
    }
    for (int i = 0; i < expected.length; i++) {
      if (expected[i] != actual[i]) {
        throw const FormatException('项目文件头部不匹配');
      }
    }
  }

  int readByte() {
    if (_offset >= _bytes.length) {
      throw const FormatException('意外读取到文件末尾');
    }
    return _bytes[_offset++];
  }

  int readUint32() {
    final ByteData data = ByteData.sublistView(_bytes, _offset, _offset + 4);
    _offset += 4;
    return data.getUint32(0, Endian.big);
  }

  double readFloat32() {
    final ByteData data = ByteData.sublistView(_bytes, _offset, _offset + 4);
    _offset += 4;
    return data.getFloat32(0, Endian.big);
  }

  Uint8List readBytes(int length) {
    if (length == 0) {
      return Uint8List(0);
    }
    final Uint8List slice = Uint8List.sublistView(
      _bytes,
      _offset,
      _offset + length,
    );
    _offset += length;
    return Uint8List.fromList(slice);
  }

  void skip(int length) {
    _offset += length;
    if (_offset > _bytes.length) {
      throw const FormatException('项目文件结构不完整');
    }
  }
}
