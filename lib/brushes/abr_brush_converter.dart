import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:misa_rin/utils/io_shim.dart';
import 'package:path/path.dart' as p;

import '../app/preferences/app_preferences.dart';
import '../canvas/canvas_tools.dart';
import '../src/rust/api/abr.dart' as rust_abr;
import '../src/rust/rust_init.dart';
import 'brush_package.dart';
import 'brush_preset.dart';
import 'brush_shape_library.dart';

class AbrConvertedTip {
  const AbrConvertedTip({
    required this.presetId,
    required this.presetName,
    required this.tip,
    required this.shapePngBytes,
  });

  final String presetId;
  final String presetName;
  final rust_abr.AbrTip tip;
  final Uint8List shapePngBytes;
}

class AbrConversionResult {
  const AbrConversionResult({
    required this.version,
    required this.subversion,
    required this.tips,
  });

  final int version;
  final int subversion;
  final List<AbrConvertedTip> tips;
}

class AbrConvertedPackage {
  const AbrConvertedPackage({
    required this.presetId,
    required this.presetName,
    required this.packageBytes,
  });

  final String presetId;
  final String presetName;
  final Uint8List packageBytes;
}

class AbrNativeConversionResult {
  const AbrNativeConversionResult({
    required this.version,
    required this.subversion,
    required this.packages,
  });

  final int version;
  final int subversion;
  final List<AbrConvertedPackage> packages;
}

/// One-shot ABR converter.
/// It decodes ABR and prepares deterministic intermediate data so runtime
/// painting only consumes our native preset format.
class AbrBrushConverter {
  static const List<int> _pngSignature = <int>[
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ];

  static Future<AbrConversionResult?> convertFile(
    String path, {
    required Set<String> usedIds,
    required Set<String> usedNames,
  }) async {
    final File file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final Uint8List bytes = await file.readAsBytes();
    await ensureRustInitialized();

    rust_abr.AbrFile abrData;
    try {
      abrData = await rust_abr.abrDecode(
        bytes: bytes,
        fileName: p.basename(path),
      );
    } catch (_) {
      return null;
    }
    if (abrData.tips.isEmpty) {
      return null;
    }

    final List<AbrConvertedTip> converted = <AbrConvertedTip>[];
    final String sourceBase = _sanitizeFileId(p.basenameWithoutExtension(path));
    for (int i = 0; i < abrData.tips.length; i++) {
      final rust_abr.AbrTip tip = abrData.tips[i];
      if (tip.width <= 0 ||
          tip.height <= 0 ||
          tip.alphaMask.length != tip.width * tip.height) {
        continue;
      }

      final Uint8List? shapePngBytes = _encodeMaskPng(
        tip.alphaMask,
        tip.width,
        tip.height,
      );
      if (shapePngBytes == null || shapePngBytes.isEmpty) {
        continue;
      }

      final String rawName = tip.name.trim();
      final String baseName = rawName.isEmpty
          ? '${sourceBase}_${i + 1}'
          : rawName;
      final String baseId = _sanitizeFileId(
        rawName.isEmpty ? '${sourceBase}_${i + 1}' : rawName,
      );
      final String presetId = _uniqueId(baseId, usedIds);
      usedIds.add(presetId);
      final String presetName = _uniqueName(baseName, usedNames);
      usedNames.add(presetName);

      converted.add(
        AbrConvertedTip(
          presetId: presetId,
          presetName: presetName,
          tip: tip,
          shapePngBytes: shapePngBytes,
        ),
      );
    }

    if (converted.isEmpty) {
      return null;
    }
    return AbrConversionResult(
      version: abrData.version,
      subversion: abrData.subversion,
      tips: converted,
    );
  }

  /// Convert ABR to native `.mrb` package bytes in one shot.
  static Future<AbrNativeConversionResult?> convertFileToNativePackages(
    String path, {
    required Set<String> usedIds,
    required Set<String> usedNames,
  }) async {
    final AbrConversionResult? converted = await convertFile(
      path,
      usedIds: usedIds,
      usedNames: usedNames,
    );
    if (converted == null || converted.tips.isEmpty) {
      return null;
    }

    final List<AbrConvertedPackage> packages = <AbrConvertedPackage>[];
    for (final AbrConvertedTip convertedTip in converted.tips) {
      final BrushPreset preset = _presetFromConvertedTip(
        convertedTip,
        converted.version,
        converted.subversion,
      );
      final Uint8List packageBytes = BrushPackageCodec.encode(
        preset: preset,
        shapeBytes: convertedTip.shapePngBytes,
        shapeFileName: '${convertedTip.presetId}_shape.png',
        shapeType: BrushShapeFileType.png,
      );
      if (packageBytes.isEmpty) {
        continue;
      }
      packages.add(
        AbrConvertedPackage(
          presetId: convertedTip.presetId,
          presetName: convertedTip.presetName,
          packageBytes: packageBytes,
        ),
      );
    }

    if (packages.isEmpty) {
      return null;
    }

    return AbrNativeConversionResult(
      version: converted.version,
      subversion: converted.subversion,
      packages: packages,
    );
  }

  static BrushPreset _presetFromConvertedTip(
    AbrConvertedTip convertedTip,
    int version,
    int subversion,
  ) {
    final rust_abr.AbrTip tip = convertedTip.tip;
    final double spacing = _abrSpacingForPreset(tip);
    final int antialiasLevel = _abrAntialiasLevel(tip);

    return BrushPreset(
      id: convertedTip.presetId,
      name: convertedTip.presetName,
      shape: BrushShape.circle,
      shapeId: '${convertedTip.presetId}_shape',
      author: 'ABR Import',
      version: 'ABR $version.$subversion',
      spacing: spacing,
      hardness: 1.0,
      flow: 1.0,
      scatter: 0.0,
      randomRotation: false,
      smoothRotation: false,
      rotationJitter: 0.0,
      antialiasLevel: antialiasLevel,
      hollowEnabled: AppPreferences.defaultHollowStrokeEnabled,
      hollowRatio: AppPreferences.defaultHollowStrokeRatio,
      hollowEraseOccludedParts:
          AppPreferences.defaultHollowStrokeEraseOccludedParts,
      autoSharpTaper: AppPreferences.defaultAutoSharpPeakEnabled,
      snapToPixel: false,
      screentoneEnabled: false,
      screentoneSpacing: 10.0,
      screentoneDotSize: 0.6,
      screentoneRotation: 45.0,
      screentoneSoftness: 0.0,
      screentoneShape: BrushShape.circle,
    ).sanitized();
  }

  static double _abrSpacingForPreset(rust_abr.AbrTip tip) {
    final double? parsed = tip.spacing;
    if (parsed == null || !parsed.isFinite || parsed <= 0.0) {
      return 0.25;
    }
    return parsed;
  }

  static int _abrAntialiasLevel(rust_abr.AbrTip tip) {
    final bool? parsed = tip.antialias;
    if (parsed == null) {
      return AppPreferences.defaultPenAntialiasLevel;
    }
    if (!parsed) {
      return 0;
    }
    final int preferred = AppPreferences.defaultPenAntialiasLevel;
    return preferred > 0 ? preferred : 1;
  }

  static Uint8List? _encodeMaskPng(Uint8List mask, int width, int height) {
    if (mask.length != width * height || width <= 0 || height <= 0) {
      return null;
    }

    final int bytesPerPixel = 4;
    final int rawRowStride = 1 + width * bytesPerPixel;
    final Uint8List rawRows = Uint8List(rawRowStride * height);

    int src = 0;
    int dst = 0;
    for (int y = 0; y < height; y++) {
      rawRows[dst++] = 0; // filter type: none
      for (int x = 0; x < width; x++) {
        final int alpha = mask[src++];
        rawRows[dst++] = 255;
        rawRows[dst++] = 255;
        rawRows[dst++] = 255;
        rawRows[dst++] = alpha;
      }
    }

    final List<int> compressedList = ZLibEncoder().encode(rawRows);
    final Uint8List compressed = Uint8List.fromList(compressedList);

    final ByteData ihdr = ByteData(13);
    ihdr.setUint32(0, width, Endian.big);
    ihdr.setUint32(4, height, Endian.big);
    ihdr.setUint8(8, 8); // bit depth
    ihdr.setUint8(9, 6); // color type: RGBA
    ihdr.setUint8(10, 0); // compression method
    ihdr.setUint8(11, 0); // filter method
    ihdr.setUint8(12, 0); // interlace method

    final BytesBuilder out = BytesBuilder(copy: false);
    out.add(_pngSignature);
    _writePngChunk(
      out,
      'IHDR',
      ihdr.buffer.asUint8List(ihdr.offsetInBytes, ihdr.lengthInBytes),
    );
    _writePngChunk(out, 'IDAT', compressed);
    _writePngChunk(out, 'IEND', Uint8List(0));
    return out.toBytes();
  }

  static void _writePngChunk(BytesBuilder out, String type, Uint8List data) {
    final Uint8List typeBytes = Uint8List.fromList(type.codeUnits);

    final ByteData lengthData = ByteData(4);
    lengthData.setUint32(0, data.length, Endian.big);
    out.add(
      lengthData.buffer.asUint8List(
        lengthData.offsetInBytes,
        lengthData.lengthInBytes,
      ),
    );

    out.add(typeBytes);
    out.add(data);

    final Uint8List crcInput = Uint8List(typeBytes.length + data.length);
    crcInput.setRange(0, typeBytes.length, typeBytes);
    crcInput.setRange(typeBytes.length, crcInput.length, data);

    final ByteData crcData = ByteData(4);
    crcData.setUint32(0, getCrc32(crcInput), Endian.big);
    out.add(
      crcData.buffer.asUint8List(crcData.offsetInBytes, crcData.lengthInBytes),
    );
  }

  static String _uniqueId(String base, Set<String> ids) {
    if (!ids.contains(base)) {
      return base;
    }
    int counter = 2;
    while (ids.contains('${base}_$counter')) {
      counter += 1;
    }
    return '${base}_$counter';
  }

  static String _uniqueName(String base, Set<String> names) {
    if (!names.contains(base)) {
      return base;
    }
    int counter = 2;
    while (names.contains('$base $counter')) {
      counter += 1;
    }
    return '$base $counter';
  }

  static String _sanitizeFileId(String id) {
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
    return sanitized.isEmpty ? 'brush' : sanitized;
  }
}
