import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';

import '../../canvas/canvas_layer.dart';
import '../../canvas/canvas_settings.dart';
import 'project_document.dart';

const int _kUint32Bits = 32;
const int _kUint32Mask = 0xFFFFFFFF;
const int _kInt64SignBit = 0x80000000;
final BigInt _kBigUint64 = BigInt.one << 64;
final BigInt _kBigUint32Mask = BigInt.from(_kUint32Mask);

/// `.rin` 二进制编解码器（v6，向后兼容 v4）
///
/// 结构参考 PSD 分块思路：头部 + 文档元数据 + 图层块 + 预览块。
/// 所有字符串按 UTF-8 存储并携带 32bit 长度前缀；位图数据按需使用
/// zlib 压缩，避免 JSON 与 Base64 的额外开销。
class ProjectBinaryCodec {
  static const String _magic = 'MISARIN';
  static const int _version = 6;
  static const int _minSupportedVersion = 4;

  static final ZLibEncoder _encoder = ZLibEncoder();
  static final ZLibDecoder _decoder = ZLibDecoder();

  static const int _compressionRaw = 0;
  static const int _compressionZlib = 1;

  static Uint8List encode(ProjectDocument document) {
    final _ByteWriter writer = _ByteWriter();
    writer.writeBytes(Uint8List.fromList(_magic.codeUnits));
    writer.writeUint16(_version);

    writer.writeString(document.id);
    writer.writeString(document.name);
    writer.writeInt64(document.createdAt.microsecondsSinceEpoch);
    writer.writeInt64(document.updatedAt.microsecondsSinceEpoch);

    writer.writeFloat32(document.settings.width);
    writer.writeFloat32(document.settings.height);
    writer.writeUint32(document.settings.backgroundColor.value);
    writer.writeUint8(document.settings.creationLogic.index);

    writer.writeUint32(document.layers.length);
    for (final CanvasLayerData layer in document.layers) {
      writer.writeString(layer.id);
      writer.writeString(layer.name);
      writer.writeBool(layer.visible);
      writer.writeFloat32(layer.opacity);
      writer.writeBool(layer.locked);
      writer.writeBool(layer.clippingMask);
      writer.writeUint8(layer.blendMode.index);

      writer.writeBool(layer.fillColor != null);
      if (layer.fillColor != null) {
        writer.writeUint32(layer.fillColor!.value);
      }

      writer.writeBool(layer.hasBitmap);
      if (layer.hasBitmap) {
        writer.writeInt32(layer.bitmapLeft ?? 0);
        writer.writeInt32(layer.bitmapTop ?? 0);
        writer.writeUint32(layer.bitmapWidth!);
        writer.writeUint32(layer.bitmapHeight!);
        final Uint8List rawBitmap = Uint8List.fromList(layer.bitmap!);
        final Uint8List compressedBitmap = Uint8List.fromList(
          _encoder.encode(rawBitmap),
        );
        final bool useCompression = compressedBitmap.length < rawBitmap.length;
        writer.writeUint8(useCompression ? _compressionZlib : _compressionRaw);
        final Uint8List storedBitmap = useCompression
            ? compressedBitmap
            : rawBitmap;
        writer.writeUint32(storedBitmap.length);
        writer.writeBytes(storedBitmap);
      }
    }

    final Uint8List previewRaw = document.previewBytes == null
        ? Uint8List(0)
        : Uint8List.fromList(document.previewBytes!);
    if (previewRaw.isEmpty) {
      writer.writeBool(false);
    } else {
      final Uint8List compressedPreview = Uint8List.fromList(
        _encoder.encode(previewRaw),
      );
      final bool useCompression = compressedPreview.length < previewRaw.length;
      writer.writeBool(true);
      writer.writeUint8(useCompression ? _compressionZlib : _compressionRaw);
      final Uint8List storedPreview = useCompression
          ? compressedPreview
          : previewRaw;
      writer.writeUint32(storedPreview.length);
      writer.writeBytes(storedPreview);
    }

    return writer.toBytes();
  }

  static ProjectDocument decode(Uint8List bytes, {String? path}) {
    final _ByteReader reader = _ByteReader(bytes);
    reader.expectMagic(_magic);
    final int version = reader.readUint16();
    _ensureSupportedVersion(version);

    final String id = reader.readString();
    final String name = reader.readString();
    final DateTime createdAt = DateTime.fromMicrosecondsSinceEpoch(
      reader.readInt64(),
    );
    final DateTime updatedAt = DateTime.fromMicrosecondsSinceEpoch(
      reader.readInt64(),
    );

    final double width = reader.readFloat32();
    final double height = reader.readFloat32();
    final Color backgroundColor = Color(reader.readUint32());
    final CanvasCreationLogic creationLogic = version >= 6
        ? _decodeCreationLogic(reader.readUint8())
        : CanvasCreationLogic.singleThread;
    final CanvasSettings settings = CanvasSettings(
      width: width,
      height: height,
      backgroundColor: backgroundColor,
      creationLogic: creationLogic,
    );

    final int layerCount = reader.readUint32();
    final List<CanvasLayerData> layers = <CanvasLayerData>[];
    for (int i = 0; i < layerCount; i++) {
      final String layerId = reader.readString();
      final String layerName = reader.readString();
      final bool visible = reader.readBool();
      final double opacity = reader.readFloat32();
      final bool locked = reader.readBool();
      final bool clippingMask = reader.readBool();
      final CanvasLayerBlendMode blendMode = _decodeBlendMode(
        reader.readUint8(),
      );

      Color? fillColor;
      if (reader.readBool()) {
        fillColor = Color(reader.readUint32());
      }

      Uint8List? bitmap;
      int? bitmapWidth;
      int? bitmapHeight;
      int bitmapLeft = 0;
      int bitmapTop = 0;
      if (reader.readBool()) {
        if (version >= 5) {
          bitmapLeft = reader.readInt32();
          bitmapTop = reader.readInt32();
        }
        bitmapWidth = reader.readUint32();
        bitmapHeight = reader.readUint32();
        final int compression = reader.readUint8();
        final int dataLength = reader.readUint32();
        final Uint8List encoded = reader.readBytes(dataLength);
        bitmap = compression == _compressionZlib
            ? Uint8List.fromList(_decoder.decodeBytes(encoded))
            : encoded;
      }

      layers.add(
        CanvasLayerData(
          id: layerId,
          name: layerName,
          visible: visible,
          opacity: opacity,
          locked: locked,
          clippingMask: clippingMask,
          blendMode: blendMode,
          fillColor: fillColor,
          bitmap: bitmap,
          bitmapWidth: bitmapWidth,
          bitmapHeight: bitmapHeight,
          bitmapLeft: bitmap != null ? bitmapLeft : null,
          bitmapTop: bitmap != null ? bitmapTop : null,
        ),
      );
    }

    Uint8List? preview;
    if (reader.readBool()) {
      final int compression = reader.readUint8();
      final int dataLength = reader.readUint32();
      final Uint8List encoded = reader.readBytes(dataLength);
      preview = compression == _compressionZlib
          ? Uint8List.fromList(_decoder.decodeBytes(encoded))
          : encoded;
    }

    return ProjectDocument(
      id: id,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      settings: settings,
      layers: layers,
      previewBytes: preview,
      path: path,
    );
  }

  static ProjectSummary decodeSummary(
    Uint8List bytes, {
    required String path,
    DateTime? lastOpened,
  }) {
    final _ByteReader reader = _ByteReader(bytes);
    reader.expectMagic(_magic);
    final int version = reader.readUint16();
    _ensureSupportedVersion(version);

    final String id = reader.readString();
    final String name = reader.readString();
    reader.readInt64(); // createdAt，无需展示
    final DateTime updatedAt = DateTime.fromMicrosecondsSinceEpoch(
      reader.readInt64(),
    );

    final double width = reader.readFloat32();
    final double height = reader.readFloat32();
    final Color backgroundColor = Color(reader.readUint32());
    final CanvasCreationLogic creationLogic = version >= 6
        ? _decodeCreationLogic(reader.readUint8())
        : CanvasCreationLogic.singleThread;

    final int layerCount = reader.readUint32();
    for (int i = 0; i < layerCount; i++) {
      reader.readString(); // layer id
      reader.readString(); // layer name
      reader.readBool();
      reader.readFloat32();
      reader.readBool();
      reader.readBool();
      reader.readUint8();

      if (reader.readBool()) {
        reader.readUint32();
      }

      if (reader.readBool()) {
        if (version >= 5) {
          reader.readInt32();
          reader.readInt32();
        }
        reader.readUint32();
        reader.readUint32();
        reader.readUint8();
        final int dataLength = reader.readUint32();
        reader.skip(dataLength);
      }
    }

    Uint8List? preview;
    if (reader.readBool()) {
      final int compression = reader.readUint8();
      final int length = reader.readUint32();
      final Uint8List encoded = reader.readBytes(length);
      preview = compression == _compressionZlib
          ? Uint8List.fromList(_decoder.decodeBytes(encoded))
          : encoded;
    }

    return ProjectSummary(
      id: id,
      name: name,
      path: path,
      updatedAt: updatedAt,
      lastOpened: lastOpened ?? updatedAt,
      settings: CanvasSettings(
        width: width,
        height: height,
        backgroundColor: backgroundColor,
        creationLogic: creationLogic,
      ),
      previewBytes: preview,
    );
  }

  static CanvasLayerBlendMode _decodeBlendMode(int raw) {
    if (raw < 0 || raw >= CanvasLayerBlendMode.values.length) {
      return CanvasLayerBlendMode.normal;
    }
    return CanvasLayerBlendMode.values[raw];
  }

  static CanvasCreationLogic _decodeCreationLogic(int raw) {
    if (raw < 0 || raw >= CanvasCreationLogic.values.length) {
      return CanvasCreationLogic.singleThread;
    }
    return CanvasCreationLogic.values[raw];
  }

  static void _ensureSupportedVersion(int version) {
    if (version < _minSupportedVersion || version > _version) {
      throw UnsupportedError('不支持的项目文件版本：$version');
    }
  }
}

class _ByteWriter {
  final BytesBuilder _builder = BytesBuilder();

  void writeBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      return;
    }
    _builder.add(bytes);
  }

  void writeUint8(int value) {
    _builder.addByte(value & 0xFF);
  }

  void writeBool(bool value) {
    writeUint8(value ? 1 : 0);
  }

  void writeUint16(int value) {
    final ByteData data = ByteData(2);
    data.setUint16(0, value, Endian.big);
    _builder.add(data.buffer.asUint8List());
  }

  void writeUint32(int value) {
    final ByteData data = ByteData(4);
    data.setUint32(0, value, Endian.big);
    _builder.add(data.buffer.asUint8List());
  }

  void writeInt32(int value) {
    final ByteData data = ByteData(4);
    data.setInt32(0, value, Endian.big);
    _builder.add(data.buffer.asUint8List());
  }

  void writeInt64(int value) {
    // Web 端 ByteData 不支持 Int64 accessor，手动拆分成两个 Uint32。
    final BigInt unsignedValue = _intToUnsignedBigInt64(value);
    final int high = (unsignedValue >> _kUint32Bits).toInt();
    final int low = (unsignedValue & _kBigUint32Mask).toInt();
    final ByteData data = ByteData(8);
    data.setUint32(0, high, Endian.big);
    data.setUint32(4, low, Endian.big);
    _builder.add(data.buffer.asUint8List());
  }

  void writeFloat32(double value) {
    final ByteData data = ByteData(4);
    data.setFloat32(0, value, Endian.big);
    _builder.add(data.buffer.asUint8List());
  }

  void writeString(String value) {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(value));
    writeUint32(bytes.length);
    writeBytes(bytes);
  }

  Uint8List toBytes() {
    return _builder.toBytes();
  }
}

class _ByteReader {
  _ByteReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  void expectMagic(String magic) {
    final Uint8List expected = Uint8List.fromList(magic.codeUnits);
    final Uint8List actual = readBytes(expected.length);
    if (actual.length != expected.length) {
      throw const FormatException('项目文件头部损坏');
    }
    for (int i = 0; i < expected.length; i++) {
      if (expected[i] != actual[i]) {
        throw const FormatException('项目文件头部不匹配');
      }
    }
  }

  int readUint8() {
    if (_offset >= _bytes.length) {
      throw const FormatException('意外读取到文件末尾');
    }
    return _bytes[_offset++];
  }

  bool readBool() {
    return readUint8() != 0;
  }

  int readUint16() {
    final ByteData data = ByteData.sublistView(_bytes, _offset, _offset + 2);
    _offset += 2;
    return data.getUint16(0, Endian.big);
  }

  int readUint32() {
    final ByteData data = ByteData.sublistView(_bytes, _offset, _offset + 4);
    _offset += 4;
    return data.getUint32(0, Endian.big);
  }

  int readInt32() {
    final ByteData data = ByteData.sublistView(_bytes, _offset, _offset + 4);
    _offset += 4;
    return data.getInt32(0, Endian.big);
  }

  int readInt64() {
    final ByteData data = ByteData.sublistView(_bytes, _offset, _offset + 8);
    _offset += 8;
    final int high = data.getUint32(0, Endian.big);
    final int low = data.getUint32(4, Endian.big);
    return _composeSignedInt64(high, low);
  }

  double readFloat32() {
    final ByteData data = ByteData.sublistView(_bytes, _offset, _offset + 4);
    _offset += 4;
    return data.getFloat32(0, Endian.big);
  }

  String readString() {
    final int length = readUint32();
    if (length == 0) {
      return '';
    }
    final Uint8List bytes = readBytes(length);
    return utf8.decode(bytes);
  }

  Uint8List readBytes(int length) {
    if (length == 0) {
      return Uint8List(0);
    }
    if (_offset + length > _bytes.length) {
      throw const FormatException('项目文件结构不完整');
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

BigInt _intToUnsignedBigInt64(int value) {
  BigInt bigValue = BigInt.from(value);
  if (bigValue.isNegative) {
    bigValue += _kBigUint64;
  }
  return bigValue;
}

int _composeSignedInt64(int high, int low) {
  BigInt value = (BigInt.from(high) << _kUint32Bits) | BigInt.from(low);
  if (high >= _kInt64SignBit) {
    value -= _kBigUint64;
  }
  return value.toInt();
}
