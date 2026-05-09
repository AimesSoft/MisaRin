import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misa_rin/bitmap_canvas/controller.dart';
import 'package:misa_rin/canvas/canvas_layer.dart';
import 'package:misa_rin/canvas/canvas_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deduplicates loaded layer ids and keeps addLayer ids unique', () async {
    final BitmapCanvasController controller = BitmapCanvasController(
      width: 8,
      height: 8,
      backgroundColor: Colors.white,
      creationLogic: CanvasCreationLogic.singleThread,
      initialLayers: <CanvasLayerData>[
        CanvasLayerData(
          id: 'duplicate-id',
          name: '背景',
          fillColor: const Color(0xFFFFFFFF),
        ),
        CanvasLayerData(
          id: 'duplicate-id',
          name: '图层 2',
          bitmap: Uint8List(8 * 8 * 4),
          bitmapWidth: 8,
          bitmapHeight: 8,
        ),
      ],
    );
    addTearDown(() async {
      await controller.disposeController();
    });

    final List<String> loadedIds = controller.layers
        .map((layer) => layer.id)
        .toList(growable: false);
    expect(loadedIds.length, 2);
    expect(loadedIds.toSet().length, loadedIds.length);

    final int beforeCount = controller.layers.length;
    final Set<String> beforeIds = controller.layers
        .map((layer) => layer.id)
        .toSet();

    controller.addLayer(aboveLayerId: controller.activeLayerId);

    final List<String> afterIds = controller.layers
        .map((layer) => layer.id)
        .toList(growable: false);
    expect(afterIds.length, beforeCount + 1);
    expect(afterIds.toSet().length, afterIds.length);
    expect(afterIds.toSet().difference(beforeIds).length, 1);
  });
}
