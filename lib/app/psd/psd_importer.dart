import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import '../../canvas/blend_mode_utils.dart';
import '../../canvas/canvas_layer.dart';
import '../../canvas/canvas_settings.dart';
import '../project/project_document.dart';

/// 仅支持 8bit RGB PSD，读取所有图层并转换为 `ProjectDocument`。
///
/// 解析逻辑参考 Adobe PSD 规范以及 Krita 中的实现，但进行了大量简化：
/// - 仅解析 `8BPS` 旧版 PSD（版本 1），不支持 PSB。
/// - 只处理 8bit 深度、RGB 色彩空间，通道压缩仅支持 Raw 与 RLE。
/// - 忽略通道以外的附加信息（图层效果、调整图层、蒙版等）。
/// - 图层位图会被铺满到画布尺寸，超出画布范围的像素会被裁剪。
class PsdImporter {
  const PsdImporter();

  Future<ProjectDocument> importFile(String path, {String? displayName}) async {
    final Uint8List data = await File(path).readAsBytes();
    return importBytes(data, displayName: displayName ?? _nameFromPath(path));
  }

  Future<ProjectDocument> importBytes(
    Uint8List data, {
    String? displayName,
  }) async {
    final _ByteReader reader = _ByteReader(data);

    final _PsdHeader header = _readHeader(reader);
    final _PsdSections sections = _readSections(reader);
    final List<_PsdLayerRecord> records = _readLayers(
      reader,
      header,
      sections.layerAndMaskLength,
    );

    final DateTime now = DateTime.now();
    final CanvasSettings settings = CanvasSettings(
      width: header.width.toDouble(),
      height: header.height.toDouble(),
      backgroundColor: const Color(0xFFFFFFFF),
      creationLogic: CanvasCreationLogic.multiThread,
    );

    final ProjectDocument base = ProjectDocument.newProject(
      settings: settings,
      name: displayName ?? 'PSD 项目',
    );

    final List<CanvasLayerData> canvasLayers = <CanvasLayerData>[];
    for (final _PsdLayerRecord record in records) {
      final CanvasLayerData? canvasLayer = _convertLayer(
        record,
        header.width,
        header.height,
      );
      if (canvasLayer != null) {
        canvasLayers.add(canvasLayer);
      }
    }

    if (canvasLayers.isEmpty) {
      canvasLayers.add(
        CanvasLayerData(
          id: generateLayerId(),
          name: 'PSD 图层',
          bitmap: Uint8List(header.width * header.height * 4),
          bitmapWidth: header.width,
          bitmapHeight: header.height,
        ),
      );
    }

    return base.copyWith(
      layers: canvasLayers,
      createdAt: now,
      updatedAt: now,
      previewBytes: null,
      path: null,
    );
  }

  _PsdHeader _readHeader(_ByteReader reader) {
    final String signature = reader.readAscii(4);
    if (signature != '8BPS') {
      throw const FormatException('不是有效的 PSD 文件');
    }
    final int version = reader.readUint16();
    if (version != 1) {
      throw UnsupportedError('仅支持 PSD (8BPS) 版本 1，当前版本：$version');
    }
    reader.skip(6); // 保留字段

    final int channels = reader.readUint16();
    final int height = reader.readUint32();
    final int width = reader.readUint32();
    final int depth = reader.readUint16();
    final int colorMode = reader.readUint16();

    if (depth != 8) {
      throw UnsupportedError('仅支持 8bit PSD，当前深度：$depth');
    }
    if (colorMode != 3) {
      throw UnsupportedError('仅支持 RGB PSD，色彩模式代码：$colorMode');
    }

    return _PsdHeader(
      width: width,
      height: height,
      channels: channels,
      depth: depth,
      colorMode: colorMode,
    );
  }

  _PsdSections _readSections(_ByteReader reader) {
    final int colorModeLength = reader.readUint32();
    reader.skip(colorModeLength);

    final int imageResourcesLength = reader.readUint32();
    reader.skip(imageResourcesLength);

    final int layerAndMaskLength = reader.readUint32();
    return _PsdSections(layerAndMaskLength: layerAndMaskLength);
  }

  List<_PsdLayerRecord> _readLayers(
    _ByteReader reader,
    _PsdHeader header,
    int layerAndMaskLength,
  ) {
    if (layerAndMaskLength <= 0) {
      return const <_PsdLayerRecord>[];
    }
    final int sectionEnd = reader.offset + layerAndMaskLength;
    final int layerInfoLength = reader.readUint32();
    if (layerInfoLength <= 0) {
      reader.offset = sectionEnd;
      return const <_PsdLayerRecord>[];
    }
    final int layerInfoEnd = reader.offset + layerInfoLength;

    int layerCount = reader.readInt16();
    if (layerCount < 0) {
      layerCount = -layerCount;
    }

    final List<_PsdLayerRecord> records = <_PsdLayerRecord>[];
    for (int i = 0; i < layerCount; i++) {
      records.add(_readLayerRecord(reader, header));
    }

    for (final _PsdLayerRecord record in records) {
      for (final _PsdChannel channel in record.channels) {
        _readChannelPixels(reader, record, channel);
      }
    }

    reader.offset = layerInfoEnd;
    reader.offset = sectionEnd;

    return records;
  }

  _PsdLayerRecord _readLayerRecord(_ByteReader reader, _PsdHeader header) {
    final int top = reader.readInt32();
    final int left = reader.readInt32();
    final int bottom = reader.readInt32();
    final int right = reader.readInt32();
    final int channelCount = reader.readUint16();

    final List<_PsdChannel> channels = <_PsdChannel>[];
    for (int i = 0; i < channelCount; i++) {
      final int channelId = reader.readInt16();
      final int length = reader.readUint32();
      channels.add(_PsdChannel(id: channelId, length: length));
    }

    final String blendSignature = reader.readAscii(4);
    if (blendSignature != '8BIM') {
      throw const FormatException('无效的图层混合签名');
    }
    final String blendKey = reader.readAscii(4);
    final int opacity = reader.readUint8();
    final int clipping = reader.readUint8();
    final int flags = reader.readUint8();
    reader.skip(1); // filler

    final int extraDataSize = reader.readUint32();
    final int extraEnd = reader.offset + extraDataSize;

    final int maskLength = reader.readUint32();
    reader.skip(maskLength);

    final int blendRangesLength = reader.readUint32();
    reader.skip(blendRangesLength);

    String layerName = reader.readPascalString(padding: 4);
    layerName = layerName.isEmpty ? 'PSD 图层' : layerName;
    if (reader.offset < extraEnd) {
      layerName = _consumeAdditionalLayerInfo(reader, extraEnd, layerName);
    }
    reader.offset = extraEnd;

    return _PsdLayerRecord(
      top: top,
      left: left,
      bottom: bottom,
      right: right,
      channels: channels,
      opacity: opacity,
      clipping: clipping,
      flags: flags,
      blendKey: blendKey,
      name: layerName,
      width: header.width,
      height: header.height,
    );
  }

  String _consumeAdditionalLayerInfo(
    _ByteReader reader,
    int extraEnd,
    String currentName,
  ) {
    String resolvedName = currentName;
    while (reader.offset + 12 <= extraEnd) {
      final String signature = reader.readAscii(4);
      final String key = reader.readAscii(4);
      final int length = reader.readUint32();
      final int dataStart = reader.offset;
      final int dataEnd = dataStart + length;
      if (dataEnd > extraEnd) {
        reader.offset = extraEnd;
        break;
      }
      if ((signature == '8BIM' || signature == '8B64') && key == 'luni') {
        final String? unicodeName = _readUnicodeString(reader, length);
        if (unicodeName != null && unicodeName.isNotEmpty) {
          resolvedName = unicodeName;
        }
      } else {
        reader.offset = dataEnd;
      }
      if ((length & 1) == 1) {
        reader.skip(1);
      }
    }
    return resolvedName;
  }

  String? _readUnicodeString(_ByteReader reader, int blockLength) {
    final int blockStart = reader.offset;
    if (blockLength < 4) {
      reader.skip(blockLength);
      return null;
    }
    final int charCount = reader.readUint32();
    final int maxBytes = blockLength - 4;
    final int expectedBytes = charCount * 2;
    final int readLength = expectedBytes <= maxBytes ? expectedBytes : maxBytes;
    final Uint8List encoded = reader.readBytes(readLength);
    final List<int> codeUnits = <int>[];
    for (int i = 0; i + 1 < encoded.length; i += 2) {
      codeUnits.add((encoded[i] << 8) | encoded[i + 1]);
    }
    final String value = codeUnits.isEmpty
        ? ''
        : String.fromCharCodes(codeUnits);
    final int consumed = reader.offset - blockStart;
    final int remaining = blockLength - consumed;
    if (remaining > 0) {
      reader.skip(remaining);
    }
    return value;
  }

  void _readChannelPixels(
    _ByteReader reader,
    _PsdLayerRecord record,
    _PsdChannel channel,
  ) {
    final int expectedEnd = reader.offset + channel.length;
    final int compression = reader.readUint16();

    final int layerWidth = record.layerWidth;
    final int layerHeight = record.layerHeight;
    Uint8List data;
    if (compression == 0) {
      data = reader.readBytes(layerWidth * layerHeight);
    } else if (compression == 1) {
      data = _decodeRle(reader, layerWidth, layerHeight);
    } else {
      throw UnsupportedError('暂不支持该通道压缩方式：$compression');
    }

    channel.data = data;
    reader.offset = expectedEnd;
  }

  Uint8List _decodeRle(_ByteReader reader, int width, int height) {
    final List<int> rowLengths = <int>[];
    for (int i = 0; i < height; i++) {
      rowLengths.add(reader.readUint16());
    }
    final Uint8List output = Uint8List(width * height);
    int offset = 0;
    for (int row = 0; row < height; row++) {
      final int length = rowLengths[row];
      final Uint8List rowData = reader.readBytes(length);
      offset = _decodePackBits(rowData, output, offset, width);
    }
    return output;
  }

  int _decodePackBits(
    Uint8List input,
    Uint8List output,
    int offset,
    int expectedPixels,
  ) {
    int i = 0;
    int written = 0;
    while (i < input.length && written < expectedPixels) {
      final int value = input[i++];
      final int signed = value > 127 ? value - 256 : value;
      if (signed >= 0) {
        final int count = signed + 1;
        for (
          int j = 0;
          j < count && written < expectedPixels && i < input.length;
          j++
        ) {
          output[offset + written] = input[i++];
          written += 1;
        }
      } else if (signed > -128) {
        if (i >= input.length) {
          break;
        }
        final int count = 1 - signed;
        final int byte = input[i++];
        for (int j = 0; j < count && written < expectedPixels; j++) {
          output[offset + written] = byte;
          written += 1;
        }
      }
    }
    return offset + written;
  }

  CanvasLayerData? _convertLayer(
    _PsdLayerRecord record,
    int canvasWidth,
    int canvasHeight,
  ) {
    final int layerWidth = record.layerWidth;
    final int layerHeight = record.layerHeight;
    if (layerWidth <= 0 || layerHeight <= 0) {
      return null;
    }

    final Uint8List red =
        record.channelData(0) ?? _filled(layerWidth * layerHeight, 0);
    final Uint8List green =
        record.channelData(1) ?? _filled(layerWidth * layerHeight, 0);
    final Uint8List blue =
        record.channelData(2) ?? _filled(layerWidth * layerHeight, 0);
    final Uint8List alpha =
        record.channelData(-1) ?? _filled(layerWidth * layerHeight, 255);

    final Uint8List bitmap = Uint8List(canvasWidth * canvasHeight * 4);

    for (int y = 0; y < layerHeight; y++) {
      final int destY = record.top + y;
      if (destY < 0 || destY >= canvasHeight) {
        continue;
      }
      for (int x = 0; x < layerWidth; x++) {
        final int destX = record.left + x;
        if (destX < 0 || destX >= canvasWidth) {
          continue;
        }
        final int srcIndex = y * layerWidth + x;
        final int destIndex = (destY * canvasWidth + destX) * 4;
        bitmap[destIndex] = red[srcIndex];
        bitmap[destIndex + 1] = green[srcIndex];
        bitmap[destIndex + 2] = blue[srcIndex];
        bitmap[destIndex + 3] = alpha[srcIndex];
      }
    }

    return CanvasLayerData(
      id: generateLayerId(),
      name: record.name,
      visible: record.visible,
      opacity: record.opacity / 255.0,
      clippingMask: record.isClippingMask,
      blendMode: record.blendMode,
      bitmap: bitmap,
      bitmapWidth: canvasWidth,
      bitmapHeight: canvasHeight,
    );
  }

  Uint8List _filled(int length, int value) {
    final Uint8List list = Uint8List(length);
    for (int i = 0; i < length; i++) {
      list[i] = value;
    }
    return list;
  }

  String _nameFromPath(String path) {
    final String base = path.split(Platform.pathSeparator).last;
    final int index = base.lastIndexOf('.');
    if (index <= 0) {
      return base;
    }
    return base.substring(0, index);
  }
}

class _PsdHeader {
  const _PsdHeader({
    required this.width,
    required this.height,
    required this.channels,
    required this.depth,
    required this.colorMode,
  });

  final int width;
  final int height;
  final int channels;
  final int depth;
  final int colorMode;
}

class _PsdSections {
  const _PsdSections({required this.layerAndMaskLength});

  final int layerAndMaskLength;
}

class _PsdLayerRecord {
  _PsdLayerRecord({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
    required this.channels,
    required this.opacity,
    required this.clipping,
    required this.flags,
    required this.blendKey,
    required this.name,
    required this.width,
    required this.height,
  });

  final int top;
  final int left;
  final int bottom;
  final int right;
  final List<_PsdChannel> channels;
  final int opacity;
  final int clipping;
  final int flags;
  final String blendKey;
  final String name;
  final int width;
  final int height;

  bool get visible => (flags & 0x02) == 0;
  bool get isClippingMask => clipping == 1;

  int get layerWidth {
    final int value = right - left;
    return value > 0 ? value : 0;
  }

  int get layerHeight {
    final int value = bottom - top;
    return value > 0 ? value : 0;
  }

  CanvasLayerBlendMode get blendMode =>
      CanvasLayerBlendModeX.fromPsdKey(blendKey);

  Uint8List? channelData(int channelId) {
    for (final _PsdChannel channel in channels) {
      if (channel.id == channelId) {
        return channel.data;
      }
    }
    return null;
  }
}

class _PsdChannel {
  _PsdChannel({required this.id, required this.length});

  final int id;
  final int length;
  Uint8List? data;
}

class _ByteReader {
  _ByteReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  int get offset => _offset;
  set offset(int value) => _offset = value.clamp(0, _bytes.length);

  String readAscii(int length) {
    final Uint8List bytes = readBytes(length);
    return String.fromCharCodes(bytes);
  }

  int readUint8() {
    return _bytes[_offset++];
  }

  int readUint16() {
    final int value = (_bytes[_offset] << 8) | _bytes[_offset + 1];
    _offset += 2;
    return value;
  }

  int readInt16() {
    final int value = readUint16();
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  int readUint32() {
    final int value =
        (_bytes[_offset] << 24) |
        (_bytes[_offset + 1] << 16) |
        (_bytes[_offset + 2] << 8) |
        _bytes[_offset + 3];
    _offset += 4;
    return value;
  }

  int readInt32() {
    final int value = readUint32();
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  Uint8List readBytes(int length) {
    if (length <= 0) {
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
  }

  String readPascalString({int padding = 1}) {
    final int length = readUint8();
    final Uint8List bytes = readBytes(length);
    final String value = length == 0 ? '' : String.fromCharCodes(bytes);
    final int consumed = 1 + length;
    final int remainder = consumed % padding;
    if (remainder != 0) {
      skip(padding - remainder);
    }
    return value;
  }
}
