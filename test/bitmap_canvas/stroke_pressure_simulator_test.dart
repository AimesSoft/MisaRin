import 'package:flutter_test/flutter_test.dart';
import 'package:misa_rin/bitmap_canvas/stroke_pressure_simulator.dart';

void main() {
  group('StrokePressureSimulator', () {
    late StrokePressureSimulator simulator;

    setUp(() {
      simulator = StrokePressureSimulator();
    });

    test('beginStroke with sharp tips enabled but dynamics disabled', () {
      const double baseRadius = 5.0;
      // simulatePressure = false, but needleTipsEnabled = true (via helper logic usually)
      // Actually in beginStroke: needleTipsEnabled param corresponds to "Auto Sharp Peak"
      // combined with other logic in controller.
      // Let's pass needleTipsEnabled = true directly.

      final double? initialRadius = simulator.beginStroke(
        position: Offset.zero,
        timestampMillis: 0,
        baseRadius: baseRadius,
        simulatePressure: false,
        needleTipsEnabled: true, // Simulate "Auto Sharp Peak" on
      );

      expect(initialRadius, isNotNull);
      expect(initialRadius, lessThan(baseRadius));
      expect(simulator.isSimulatingStroke, isTrue);
    });

    test(
      'sampleNextRadius ramps up when dynamics disabled but sharp tips enabled',
      () {
        const double baseRadius = 5.0;
        simulator.beginStroke(
          position: Offset.zero,
          timestampMillis: 0,
          baseRadius: baseRadius,
          simulatePressure: false,
          needleTipsEnabled: true,
        );

        // First sample (after beginStroke)
        double? r1 = simulator.sampleNextRadius(
          lastPosition: Offset.zero,
          position: const Offset(10, 10),
          timestampMillis: 16,
        );
        expect(r1, isNotNull);
        expect(r1, lessThan(baseRadius));

        // Subsequent samples should approach baseRadius
        double? r2 = simulator.sampleNextRadius(
          lastPosition: const Offset(10, 10),
          position: const Offset(20, 20),
          timestampMillis: 32,
        );
        expect(r2, isNotNull);
        expect(r2, greaterThanOrEqualTo(r1!));

        // Jump ahead to end of ramp
        for (int i = 0; i < 10; i++) {
          simulator.sampleNextRadius(
            lastPosition: Offset.zero,
            position: Offset(i * 10.0, i * 10.0),
            timestampMillis: 100 + i * 16,
          );
        }

        double? rFinal = simulator.sampleNextRadius(
          lastPosition: const Offset(100, 100),
          position: const Offset(110, 110),
          timestampMillis: 500,
        );
        expect(rFinal, equals(baseRadius));
      },
    );

    test('dynamics enabled takes precedence', () {
      const double baseRadius = 5.0;
      simulator.beginStroke(
        position: Offset.zero,
        timestampMillis: 0,
        baseRadius: baseRadius,
        simulatePressure: true, // Dynamics ON
        needleTipsEnabled: true,
      );

      // When dynamics are on, StrokeDynamics logic is used.
      // We just check that it doesn't crash and returns something.
      double? r1 = simulator.sampleNextRadius(
        lastPosition: Offset.zero,
        position: const Offset(10, 10),
        timestampMillis: 16,
      );
      expect(r1, isNotNull);
    });
  });
}
