import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misa_rin/app/widgets/app_slider.dart';

void main() {
  testWidgets(
    'macOS slider retains the Fluent geometry and painting',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final smallThumb in [false, true]) {
          final reference = GlobalKey();
          final actual = GlobalKey();
          final style = smallThumb
              ? const fluent.SliderThemeData(
                  trackHeight: WidgetStatePropertyAll(0),
                  thumbRadius: WidgetStatePropertyAll(8),
                  thumbBallInnerFactor: WidgetStatePropertyAll(0.6),
                )
              : null;
          Widget sample(GlobalKey key, Widget slider) => RepaintBoundary(
            key: key,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(width: 300, child: slider),
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: fluent.FluentTheme(
                  data: fluent.FluentThemeData(brightness: brightness),
                  child: Column(
                    children: [
                      sample(
                        reference,
                        fluent.Slider(
                          value: 37,
                          style: style,
                          onChanged: (_) {},
                        ),
                      ),
                      sample(
                        actual,
                        AppSlider(value: 37, style: style, onChanged: (_) {}),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final expectedSize = tester.getSize(find.byKey(reference));
          expect(tester.getSize(find.byKey(actual)), expectedSize);
          await tester.runAsync(() async {
            final first =
                await (reference.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final second =
                await (actual.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final expected = (await first.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            final result = (await second.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            int different = 0;
            for (var i = 0; i < expected.length; i++) {
              if ((expected[i] - result[i]).abs() > 2) different++;
            }
            first.dispose();
            second.dispose();
            expect(
              different / expected.length,
              lessThan(0.002),
              reason: '$brightness, smallThumb=$smallThumb',
            );
          });
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
