import 'dart:math';
import 'dart:typed_data';

import '../../canvas/canvas_layer.dart';
import '../../canvas/canvas_settings.dart';

Uint8List? _clonePreview(Uint8List? bytes) {
  if (bytes == null) {
    return null;
  }
  return Uint8List.fromList(bytes);
}

String _generateProjectId() {
  final int timestamp = DateTime.now().microsecondsSinceEpoch;
  final int randomBits = Random().nextInt(0x7FFFFFFF);
  return '${timestamp.toRadixString(16)}-${randomBits.toRadixString(16)}';
}

List<CanvasLayerData> _cloneLayers(List<CanvasLayerData> layers) {
  return List<CanvasLayerData>.unmodifiable(
    layers.map((layer) => layer.copyWith()),
  );
}

class ProjectDocument {
  ProjectDocument({
    required this.id,
    required this.name,
    required this.settings,
    required this.createdAt,
    required this.updatedAt,
    required List<CanvasLayerData> layers,
    Uint8List? previewBytes,
    this.path,
  }) : layers = _cloneLayers(layers),
       previewBytes = _clonePreview(previewBytes);

  factory ProjectDocument.newProject({
    required CanvasSettings settings,
    String name = '未命名项目',
  }) {
    final DateTime now = DateTime.now();
    final int width = settings.width.round();
    final int height = settings.height.round();
    return ProjectDocument(
      id: _generateProjectId(),
      name: name,
      settings: settings,
      createdAt: now,
      updatedAt: now,
      layers: <CanvasLayerData>[
        CanvasLayerData(
          id: generateLayerId(),
          name: '背景',
          fillColor: settings.backgroundColor,
        ),
        CanvasLayerData(id: generateLayerId(), name: '图层 2'),
      ],
    );
  }

  final String id;
  final String name;
  final CanvasSettings settings;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<CanvasLayerData> layers;
  final Uint8List? previewBytes;
  final String? path;

  ProjectDocument copyWith({
    String? id,
    String? name,
    CanvasSettings? settings,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<CanvasLayerData>? layers,
    Uint8List? previewBytes,
    String? path,
  }) {
    return ProjectDocument(
      id: id ?? this.id,
      name: name ?? this.name,
      settings: settings ?? this.settings,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      layers: layers == null ? this.layers : _cloneLayers(layers),
      previewBytes: previewBytes ?? this.previewBytes,
      path: path ?? this.path,
    );
  }
}

class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.path,
    required this.updatedAt,
    required this.lastOpened,
    required this.settings,
    this.previewBytes,
  });

  final String id;
  final String name;
  final String path;
  final DateTime updatedAt;
  final DateTime lastOpened;
  final CanvasSettings settings;
  final Uint8List? previewBytes;

  ProjectSummary copyWith({
    String? id,
    String? name,
    String? path,
    DateTime? updatedAt,
    DateTime? lastOpened,
    CanvasSettings? settings,
    Uint8List? previewBytes,
  }) {
    return ProjectSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      updatedAt: updatedAt ?? this.updatedAt,
      lastOpened: lastOpened ?? this.lastOpened,
      settings: settings ?? this.settings,
      previewBytes: previewBytes ?? this.previewBytes,
    );
  }
}
