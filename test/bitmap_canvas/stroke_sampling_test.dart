import 'package:flutter_test/flutter_test.dart';

import 'package:misa_rin/bitmap_canvas/stroke_sample.dart';
import 'package:misa_rin/bitmap_canvas/velocity_smoother.dart';

void main() {
  group('StrokeSampleSeries', () {
    test('tracks stationary duration and speed', () {
      final StrokeSampleSeries series = StrokeSampleSeries(
        stationaryDistanceThreshold: 0.5,
      );

      final StrokeSample first = series.add(Offset.zero, 0.0);
      expect(first.speed, 0);
      expect(first.stationaryDuration, 0);

      final StrokeSample second = series.add(const Offset(0.2, 0.0), 16.0);
      expect(second.speed, closeTo(0.0125, 0.0001));
      expect(second.stationaryDuration, closeTo(16.0, 0.0001));

      final StrokeSample third = series.add(const Offset(2.0, 0.0), 32.0);
      expect(third.speed, greaterThan(0));
      expect(third.stationaryDuration, 0);
      expect(series.totalDistance, closeTo(2.0, 0.0001));
      expect(series.totalTime, closeTo(32.0, 0.0001));
    });
  });

  group('VelocitySmoother', () {
    test('produces zero for stationary input', () {
      final VelocitySmoother smoother = VelocitySmoother();
      smoother.addSample(Offset.zero, 0.0);
      final double result = smoother.addSample(Offset.zero, 16.0);
      expect(result, 0);
    });

    test('increases normalized speed for faster motion', () {
      final VelocitySmoother smoother = VelocitySmoother(
        minTrackingDistance: 0.5,
        maxSpeed: 2.0,
      );

      smoother.addSample(Offset.zero, 0.0);

      double? previous;
      for (int i = 1; i <= 6; i++) {
        final double value = smoother.addSample(
          Offset(i.toDouble(), 0.0),
          i * 4.0,
        );
        if (previous != null) {
          expect(value, greaterThanOrEqualTo(previous));
        }
        previous = value;
      }

      expect(previous, isNotNull);
      expect(previous!, greaterThan(0));
      expect(previous, lessThanOrEqualTo(1.0));
    });
  });
}
