import 'dart:async';
import 'dart:collection';

class StrokeLatencyMonitor {
  StrokeLatencyMonitor._();

  static final StrokeLatencyMonitor instance = StrokeLatencyMonitor._();

  final StreamController<double> _latencyController =
      StreamController<double>.broadcast();
  final ListQueue<_LatencySample> _pendingSamples = ListQueue<_LatencySample>();
  double _latestLatencyMs = 0;

  Stream<double> get latencyStream => _latencyController.stream;
  double get latestLatencyMs => _latestLatencyMs;

  void recordStrokeStart() {
    _pendingSamples.add(
      _LatencySample(startMicros: DateTime.now().microsecondsSinceEpoch),
    );
  }

  void recordFramePresented() {
    if (_pendingSamples.isEmpty) {
      return;
    }
    final _LatencySample sample = _pendingSamples.removeFirst();
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    final double elapsedMs = (nowMicros - sample.startMicros) / 1000.0;
    if (elapsedMs.isNaN || elapsedMs.isInfinite || elapsedMs < 0) {
      return;
    }
    _latestLatencyMs = elapsedMs;
    _latencyController.add(elapsedMs);
  }

  void reset() {
    _pendingSamples.clear();
    _latestLatencyMs = 0;
  }

  Future<void> dispose() async {
    await _latencyController.close();
    _pendingSamples.clear();
  }
}

class _LatencySample {
  _LatencySample({required this.startMicros});

  final int startMicros;
}
