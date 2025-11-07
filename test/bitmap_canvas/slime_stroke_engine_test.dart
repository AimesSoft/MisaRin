import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misa_rin/bitmap_canvas/slime_stroke_engine.dart';
import 'package:misa_rin/bitmap_canvas/stroke_pressure_profile.dart';

void main() {
  group('SlimeStrokeEngine', () {
    test('produces blob while stationary and segment when moving', () {
      final SlimeStrokeEngine engine = SlimeStrokeEngine()
        ..setProfile(StrokePressureProfile.auto);
      engine.startStroke(position: Offset.zero, baseRadius: 3.0, timestampMillis: 0.0);

      final SlimeStrokeSample? blob = engine.extend(
        position: const Offset(0.2, 0.0),
        timestampMillis: 30.0,
      );
      expect(blob, isNotNull);
      expect(blob!.isBlob, isTrue);

      final SlimeStrokeSample? segment = engine.extend(
        position: const Offset(6.0, 0.0),
        timestampMillis: 60.0,
      );
      expect(segment, isNotNull);
      expect(segment!.isBlob, isFalse);
      expect(segment.startRadius, isNotNull);
      expect(segment.endRadius, isNotNull);
      expect(segment.endRadius, greaterThan(0));
    });

    test('finishStroke no longer extends extra tail for moving stroke', () {
      final SlimeStrokeEngine engine = SlimeStrokeEngine()
        ..setProfile(StrokePressureProfile.taperEnds);
      engine.startStroke(position: Offset.zero, baseRadius: 4.0, timestampMillis: 0.0);
      engine.extend(position: const Offset(5.0, 0.0), timestampMillis: 16.0);
      engine.extend(position: const Offset(9.0, 2.0), timestampMillis: 32.0);

      final SlimeTailResult? tail = engine.finishStroke();
      expect(tail, isNull, reason: 'stroke should end exactly at tip');
    });

    test('finishStroke keeps isolated dot without tail', () {
      final SlimeStrokeEngine engine = SlimeStrokeEngine()
        ..setProfile(StrokePressureProfile.auto);
      engine.startStroke(position: Offset.zero, baseRadius: 4.0, timestampMillis: 0.0);
      engine.extend(position: const Offset(0.5, 0.2), timestampMillis: 20.0);

      final SlimeTailResult? tail = engine.finishStroke();
      expect(tail, isNotNull);
      expect(tail!.isLine, isFalse);
      expect(tail.pointRadius, greaterThan(0));
    });
  });
}
