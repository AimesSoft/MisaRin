import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';

enum CanvasLayerBlendMode {
  normal,
  multiply,
  dissolve,
  darken,
  colorBurn,
  linearBurn,
  darkerColor,
  lighten,
  screen,
  colorDodge,
  linearDodge,
  lighterColor,
  overlay,
  softLight,
  hardLight,
  vividLight,
  linearLight,
  pinLight,
  hardMix,
  difference,
  exclusion,
  subtract,
  divide,
  hue,
  saturation,
  color,
  luminosity,
}

@immutable
class CanvasLayerData {
  CanvasLayerData({
    required this.id,
    required this.name,
    this.visible = true,
    this.opacity = 1.0,
    this.locked = false,
    this.clippingMask = false,
    this.blendMode = CanvasLayerBlendMode.normal,
    Color? fillColor,
    Uint8List? bitmap,
    int? bitmapWidth,
    int? bitmapHeight,
    int? bitmapLeft,
    int? bitmapTop,
    bool cloneBitmap = true,
  }) : fillColor = fillColor,
       bitmap = bitmap != null
           ? (cloneBitmap ? Uint8List.fromList(bitmap) : bitmap)
           : null,
       bitmapWidth = bitmap != null ? bitmapWidth : null,
       bitmapHeight = bitmap != null ? bitmapHeight : null,
       bitmapLeft = bitmap != null ? bitmapLeft ?? 0 : null,
       bitmapTop = bitmap != null ? bitmapTop ?? 0 : null;

  final String id;
  final String name;
  final bool visible;
  final double opacity;
  final bool locked;
  final bool clippingMask;
  final CanvasLayerBlendMode blendMode;
  final Color? fillColor;
  final Uint8List? bitmap;
  final int? bitmapWidth;
  final int? bitmapHeight;
  final int? bitmapLeft;
  final int? bitmapTop;

  bool get hasFill => fillColor != null;
  bool get hasBitmap =>
      bitmap != null && bitmapWidth != null && bitmapHeight != null;

  CanvasLayerData copyWith({
    String? id,
    String? name,
    bool? visible,
    double? opacity,
    bool? locked,
    bool? clippingMask,
    CanvasLayerBlendMode? blendMode,
    Color? fillColor,
    bool clearFill = false,
    Uint8List? bitmap,
    int? bitmapWidth,
    int? bitmapHeight,
    int? bitmapLeft,
    int? bitmapTop,
    bool clearBitmap = false,
    bool cloneBitmap = true,
  }) {
    final Uint8List? resolvedBitmap;
    if (clearBitmap) {
      resolvedBitmap = null;
    } else if (bitmap != null) {
      resolvedBitmap = cloneBitmap ? Uint8List.fromList(bitmap) : bitmap;
    } else {
      resolvedBitmap = this.bitmap != null
          ? (cloneBitmap ? Uint8List.fromList(this.bitmap!) : this.bitmap!)
          : null;
    }
    final int? resolvedWidth;
    final int? resolvedHeight;
    final int? resolvedLeft;
    final int? resolvedTop;
    if (resolvedBitmap == null) {
      resolvedWidth = null;
      resolvedHeight = null;
      resolvedLeft = null;
      resolvedTop = null;
    } else {
      resolvedWidth = bitmapWidth ?? this.bitmapWidth;
      resolvedHeight = bitmapHeight ?? this.bitmapHeight;
      resolvedLeft = bitmapLeft ?? this.bitmapLeft ?? 0;
      resolvedTop = bitmapTop ?? this.bitmapTop ?? 0;
    }

    return CanvasLayerData(
      id: id ?? this.id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      locked: locked ?? this.locked,
      clippingMask: clippingMask ?? this.clippingMask,
      blendMode: blendMode ?? this.blendMode,
      fillColor: clearFill ? null : (fillColor ?? this.fillColor),
      bitmap: resolvedBitmap,
      bitmapWidth: resolvedWidth,
      bitmapHeight: resolvedHeight,
      bitmapLeft: resolvedLeft,
      bitmapTop: resolvedTop,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'visible': visible,
      'opacity': opacity,
      'locked': locked,
      'clippingMask': clippingMask,
      'blendMode': blendMode.name,
      if (fillColor != null) 'fillColor': _encodeColor(fillColor!),
      if (hasBitmap)
        'bitmap': <String, dynamic>{
          if (bitmapLeft != null) 'left': bitmapLeft,
          if (bitmapTop != null) 'top': bitmapTop,
          'width': bitmapWidth,
          'height': bitmapHeight,
          'pixels': base64Encode(bitmap!),
        },
    };
  }

  static CanvasLayerData fromJson(Map<String, dynamic> json) {
    Color? fill;
    if (json.containsKey('fillColor')) {
      fill = Color(json['fillColor'] as int);
    } else if (json['type'] == 'color' && json.containsKey('color')) {
      fill = Color(json['color'] as int);
    }

    Uint8List? bitmap;
    int? bitmapWidth;
    int? bitmapHeight;
    int? bitmapLeft;
    int? bitmapTop;
    final Object? rawBitmap = json['bitmap'];
    if (rawBitmap is Map<String, dynamic>) {
      final String? encoded = rawBitmap['pixels'] as String?;
      if (encoded != null) {
        try {
          bitmap = Uint8List.fromList(base64Decode(encoded));
          bitmapWidth = rawBitmap['width'] as int?;
          bitmapHeight = rawBitmap['height'] as int?;
          bitmapLeft = rawBitmap['left'] as int? ?? 0;
          bitmapTop = rawBitmap['top'] as int? ?? 0;
        } catch (_) {
          bitmap = null;
          bitmapWidth = null;
          bitmapHeight = null;
          bitmapLeft = null;
          bitmapTop = null;
        }
      }
    }

    return CanvasLayerData(
      id: json['id'] as String,
      name: json['name'] as String,
      visible: json['visible'] as bool? ?? true,
      opacity: _parseOpacity(json['opacity']),
      locked: json['locked'] as bool? ?? false,
      clippingMask: json['clippingMask'] as bool? ?? false,
      blendMode: _parseBlendMode(json['blendMode'] as String?),
      fillColor: fill,
      bitmap: bitmap,
      bitmapWidth: bitmapWidth,
      bitmapHeight: bitmapHeight,
      bitmapLeft: bitmapLeft,
      bitmapTop: bitmapTop,
    );
  }

  static CanvasLayerBlendMode _parseBlendMode(String? raw) {
    if (raw == null) {
      return CanvasLayerBlendMode.normal;
    }
    return CanvasLayerBlendMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => CanvasLayerBlendMode.normal,
    );
  }

  static double _parseOpacity(Object? value) {
    if (value is num) {
      final double normalized = value.toDouble();
      if (normalized <= 0) {
        return 0;
      }
      if (normalized >= 1) {
        return 1;
      }
      return normalized;
    }
    return 1.0;
  }
}

String generateLayerId() {
  final int timestamp = DateTime.now().microsecondsSinceEpoch;
  final int randomBits = Random().nextInt(0x7FFFFFFF);
  return 'layer_${timestamp.toRadixString(16)}_${randomBits.toRadixString(16)}';
}

int _encodeColor(Color color) {
  return (color.alpha << 24) |
      (color.red << 16) |
      (color.green << 8) |
      color.blue;
}
