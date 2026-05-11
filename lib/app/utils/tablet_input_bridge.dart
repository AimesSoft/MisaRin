import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:misa_rin/utils/io_shim.dart';

final bool _kDebugPencilPrediction =
    kDebugMode ||
    bool.fromEnvironment(
      'MISA_RIN_DEBUG_PENCIL_PREDICTION',
      defaultValue: false,
    );
const bool _kEnableSyntheticPredictionFallback = bool.fromEnvironment(
  'MISA_RIN_ENABLE_SYNTHETIC_PREDICTION_FALLBACK',
  defaultValue: false,
);

class TabletStylusPoint {
  const TabletStylusPoint({required this.position, this.pressure});

  final Offset position;
  final double? pressure;
}

class TabletHoverSample {
  const TabletHoverSample({
    required this.position,
    required this.inContact,
    required this.inRange,
    required this.deviceId,
  });

  final Offset position;
  final bool inContact;
  final bool inRange;
  final int deviceId;
}

class TabletInputBridge {
  TabletInputBridge._();

  static final TabletInputBridge instance = TabletInputBridge._();

  final MethodChannel _channel = const MethodChannel('misarin/tablet_input');
  final StreamController<TabletHoverSample> _hoverController =
      StreamController<TabletHoverSample>.broadcast();
  final StreamController<void> _pencilDoubleTapController =
      StreamController<void>.broadcast();
  bool _initialized = false;
  final Map<int, _TabletSample> _samples = <int, _TabletSample>{};
  _PencilMotionFrame? _latestPencilMotion;
  int _latestPencilMotionMicros = 0;
  int _debugMotionPackets = 0;
  int _debugMotionPredictedPoints = 0;
  int _debugMotionSyntheticPredictedPoints = 0;
  int _debugMotionCoalescedPoints = 0;
  int _debugResolveRequests = 0;
  int _debugResolveHits = 0;
  int _debugResolveMissNoFrame = 0;
  int _debugResolveMissKind = 0;
  int _debugResolveMissAge = 0;
  int _debugResolveMissContact = 0;
  int _debugResolveMissDistance = 0;
  int _debugRawPredictedCount = 0;
  int _debugRawCoalescedCount = 0;
  int _debugRawPredictedPencilCount = 0;
  int _debugRawCoalescedPencilCount = 0;
  DateTime? _debugLastMotionLogAt;

  bool get _supportMacOS => Platform.isMacOS;
  bool get _supportWindows => Platform.isWindows;
  bool get _supportDesktopTabletChannel => _supportMacOS || _supportWindows;
  bool get _supportApplePencilTapChannel =>
      Platform.isMacOS || Platform.isIOS;
  bool get _supportApplePencilMotionChannel => Platform.isIOS;

  Stream<void> get pencilDoubleTapEvents => _pencilDoubleTapController.stream;
  Stream<TabletHoverSample> get hoverEvents => _hoverController.stream;

  void ensureInitialized() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    if (!_supportDesktopTabletChannel &&
        !_supportApplePencilTapChannel &&
        !_supportApplePencilMotionChannel) {
      return;
    }
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'pencilDoubleTap') {
      _pencilDoubleTapController.add(null);
      return;
    }
    if (call.method == 'pencilMotion') {
      _updatePencilMotion(call.arguments);
      return;
    }
    if (call.method != 'tabletEvent') {
      return;
    }
    final Map<dynamic, dynamic>? raw = call.arguments as Map<dynamic, dynamic>?;
    if (raw == null) {
      return;
    }
    final int? deviceId = raw['device'] as int?;
    if (deviceId == null) {
      return;
    }
    final double pressure = (raw['pressure'] as num?)?.toDouble() ?? 0.0;
    final double pressureMin = (raw['pressureMin'] as num?)?.toDouble() ?? 0.0;
    final double pressureMax = (raw['pressureMax'] as num?)?.toDouble() ?? 1.0;
    final bool inContact = raw['inContact'] as bool? ?? false;
    final bool inRange = raw['inRange'] as bool? ?? inContact;
    final double? x = (raw['x'] as num?)?.toDouble();
    final double? y = (raw['y'] as num?)?.toDouble();
    _samples[deviceId] = _TabletSample(
      pressure: pressure,
      min: pressureMin,
      max: pressureMax,
      inContact: inContact,
      inRange: inRange,
    );
    if (!inContact && pressure <= 0.0 && !inRange) {
      _samples.remove(deviceId);
    }
    if (x != null && y != null && x.isFinite && y.isFinite) {
      _hoverController.add(
        TabletHoverSample(
          position: Offset(x, y),
          inContact: inContact,
          inRange: inRange,
          deviceId: deviceId,
        ),
      );
    }
  }

  void _updatePencilMotion(dynamic arguments) {
    if (!_supportApplePencilMotionChannel) {
      return;
    }
    final Map<dynamic, dynamic>? raw = arguments as Map<dynamic, dynamic>?;
    if (raw == null) {
      return;
    }
    final double? x = (raw['x'] as num?)?.toDouble();
    final double? y = (raw['y'] as num?)?.toDouble();
    if (x == null || y == null || !x.isFinite || !y.isFinite) {
      return;
    }
    final bool inContact = raw['inContact'] as bool? ?? true;
    final double? pressure = _normalizedNullablePressure(
      (raw['pressure'] as num?)?.toDouble(),
    );
    final List<TabletStylusPoint> coalesced = _parseStylusPoints(
      raw['coalesced'],
    );
    final List<TabletStylusPoint> predicted = _parseStylusPoints(
      raw['predicted'],
    );
    final int rawPredictedCount =
        (raw['rawPredictedCount'] as num?)?.toInt() ?? -1;
    final int rawCoalescedCount =
        (raw['rawCoalescedCount'] as num?)?.toInt() ?? -1;
    final int rawPredictedPencilCount =
        (raw['rawPredictedPencilCount'] as num?)?.toInt() ?? -1;
    final int rawCoalescedPencilCount =
        (raw['rawCoalescedPencilCount'] as num?)?.toInt() ?? -1;
    if (!inContact && coalesced.isEmpty && predicted.isEmpty) {
      _latestPencilMotion = null;
      _latestPencilMotionMicros = 0;
      return;
    }
    _latestPencilMotion = _PencilMotionFrame(
      anchor: Offset(x, y),
      pressure: pressure,
      inContact: inContact,
      coalesced: coalesced,
      predicted: predicted,
      rawPredictedCount: rawPredictedCount,
      rawCoalescedCount: rawCoalescedCount,
      rawPredictedPencilCount: rawPredictedPencilCount,
      rawCoalescedPencilCount: rawCoalescedPencilCount,
    );
    _latestPencilMotionMicros = DateTime.now().microsecondsSinceEpoch;
    if (_kDebugPencilPrediction) {
      _debugMotionPackets += 1;
      _debugMotionCoalescedPoints += coalesced.length;
      _debugMotionPredictedPoints += predicted.length;
      if (rawPredictedCount >= 0) {
        _debugRawPredictedCount += rawPredictedCount;
      }
      if (rawCoalescedCount >= 0) {
        _debugRawCoalescedCount += rawCoalescedCount;
      }
      if (rawPredictedPencilCount >= 0) {
        _debugRawPredictedPencilCount += rawPredictedPencilCount;
      }
      if (rawCoalescedPencilCount >= 0) {
        _debugRawCoalescedPencilCount += rawCoalescedPencilCount;
      }
      _maybeLogPencilMotionSummary();
    }
  }

  List<TabletStylusPoint> predictedSamplesForEvent(PointerEvent event) {
    final _PencilMotionFrame? frame = _resolvePencilMotionForEvent(event);
    if (frame == null) {
      return const <TabletStylusPoint>[];
    }
    if (frame.predicted.isNotEmpty) {
      if (frame.predicted.length >= 2) {
        return frame.predicted;
      }
      if (!_kEnableSyntheticPredictionFallback) {
        return frame.predicted;
      }
      final List<TabletStylusPoint> synthesized = _synthesizePredictedPoints(
        frame,
      );
      if (synthesized.isEmpty) {
        return frame.predicted;
      }
      final List<TabletStylusPoint> merged = <TabletStylusPoint>[
        ...frame.predicted,
        ...synthesized.take(2),
      ];
      if (_kDebugPencilPrediction) {
        _debugMotionSyntheticPredictedPoints +=
            merged.length - frame.predicted.length;
        _maybeLogPencilMotionSummary();
      }
      return merged;
    }
    final List<TabletStylusPoint> synthesized = _synthesizePredictedPoints(
      frame,
    );
    if (!_kEnableSyntheticPredictionFallback) {
      return const <TabletStylusPoint>[];
    }
    if (_kDebugPencilPrediction && synthesized.isNotEmpty) {
      _debugMotionSyntheticPredictedPoints += synthesized.length;
      _maybeLogPencilMotionSummary();
    }
    return synthesized;
  }

  List<TabletStylusPoint> coalescedSamplesForEvent(PointerEvent event) {
    final _PencilMotionFrame? frame = _resolvePencilMotionForEvent(event);
    if (frame == null || frame.coalesced.isEmpty) {
      return const <TabletStylusPoint>[];
    }
    return frame.coalesced;
  }

  List<TabletStylusPoint> _synthesizePredictedPoints(_PencilMotionFrame frame) {
    final List<TabletStylusPoint> coalesced = frame.coalesced;
    if (coalesced.length < 2) {
      return const <TabletStylusPoint>[];
    }
    final TabletStylusPoint previous = coalesced[coalesced.length - 2];
    final TabletStylusPoint current = coalesced.last;
    final Offset delta = current.position - previous.position;
    final double distance = delta.distance;
    if (!distance.isFinite || distance < 0.15) {
      return const <TabletStylusPoint>[];
    }
    final Offset direction = delta / distance;
    final int steps = distance > 4.0 ? 3 : 2;
    final double baseStep = distance.clamp(0.6, 8.0).toDouble();
    const double kMaxLeadDistance = 24.0;
    double accumulated = 0.0;
    final List<TabletStylusPoint> points = <TabletStylusPoint>[];
    for (int i = 0; i < steps; i++) {
      final double stepDistance = i == 0 ? baseStep : baseStep * 0.85;
      final double remaining = kMaxLeadDistance - accumulated;
      if (remaining <= 0.05) {
        break;
      }
      final double clampedStep = math.min(stepDistance, remaining);
      accumulated += clampedStep;
      points.add(
        TabletStylusPoint(
          position: current.position + direction * accumulated,
          pressure: current.pressure ?? frame.pressure,
        ),
      );
    }
    return points;
  }

  _PencilMotionFrame? _resolvePencilMotionForEvent(PointerEvent event) {
    if (!_supportApplePencilMotionChannel) {
      return null;
    }
    if (_kDebugPencilPrediction) {
      _debugResolveRequests += 1;
    }
    final bool isTabletEvent = isTabletPointer(event);
    if (!isTabletEvent) {
      final bool iOSFallbackCandidate =
          defaultTargetPlatform == TargetPlatform.iOS &&
          (event.kind == PointerDeviceKind.touch ||
              event.kind == PointerDeviceKind.unknown) &&
          event.down;
      if (!iOSFallbackCandidate) {
        if (_kDebugPencilPrediction) {
          _debugResolveMissKind += 1;
          _maybeLogPencilMotionSummary();
        }
        return null;
      }
    }
    final _PencilMotionFrame? frame = _latestPencilMotion;
    if (frame == null || _latestPencilMotionMicros <= 0) {
      if (_kDebugPencilPrediction) {
        _debugResolveMissNoFrame += 1;
        _maybeLogPencilMotionSummary();
      }
      return null;
    }
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    final double ageMs = (nowMicros - _latestPencilMotionMicros) / 1000.0;
    if (!ageMs.isFinite || ageMs > 140.0) {
      if (_kDebugPencilPrediction) {
        _debugResolveMissAge += 1;
        _maybeLogPencilMotionSummary();
      }
      return null;
    }
    if (!frame.inContact && !event.down) {
      if (_kDebugPencilPrediction) {
        _debugResolveMissContact += 1;
        _maybeLogPencilMotionSummary();
      }
      return null;
    }
    final double anchorDistance = (frame.anchor - event.position).distance;
    if (anchorDistance.isFinite && anchorDistance > 220.0) {
      if (_kDebugPencilPrediction) {
        _debugResolveMissDistance += 1;
        _maybeLogPencilMotionSummary();
      }
      return null;
    }
    if (_kDebugPencilPrediction) {
      _debugResolveHits += 1;
      _maybeLogPencilMotionSummary();
    }
    return frame;
  }

  void _maybeLogPencilMotionSummary() {
    if (!_kDebugPencilPrediction || !kDebugMode) {
      return;
    }
    final DateTime now = DateTime.now();
    final DateTime? lastAt = _debugLastMotionLogAt;
    if (lastAt != null && now.difference(lastAt).inMilliseconds < 1000) {
      return;
    }
    _debugLastMotionLogAt = now;
    final _PencilMotionFrame? frame = _latestPencilMotion;
    debugPrint(
      '[pencil_prediction/bridge] '
      'packets=$_debugMotionPackets '
      'rawPred=$_debugRawPredictedCount '
      'rawCoa=$_debugRawCoalescedCount '
      'rawPredPencil=$_debugRawPredictedPencilCount '
      'rawCoaPencil=$_debugRawCoalescedPencilCount '
      'nativePredPts=$_debugMotionPredictedPoints '
      'syntheticPredPts=$_debugMotionSyntheticPredictedPoints '
      'coalescedPts=$_debugMotionCoalescedPoints '
      'resolve=$_debugResolveHits/$_debugResolveRequests '
      'miss(kind/noFrame/age/contact/dist)='
      '$_debugResolveMissKind/$_debugResolveMissNoFrame/'
      '$_debugResolveMissAge/$_debugResolveMissContact/'
      '$_debugResolveMissDistance '
      'frameRawPred=${frame?.rawPredictedCount ?? -1} '
      'frameRawCoa=${frame?.rawCoalescedCount ?? -1} '
      'frameRawPredPencil=${frame?.rawPredictedPencilCount ?? -1} '
      'frameRawCoaPencil=${frame?.rawCoalescedPencilCount ?? -1} '
      'framePred=${frame?.predicted.length ?? 0} '
      'frameCoa=${frame?.coalesced.length ?? 0} '
      'frameInContact=${frame?.inContact ?? false}',
    );
    _debugMotionPackets = 0;
    _debugMotionPredictedPoints = 0;
    _debugMotionSyntheticPredictedPoints = 0;
    _debugMotionCoalescedPoints = 0;
    _debugResolveRequests = 0;
    _debugResolveHits = 0;
    _debugResolveMissNoFrame = 0;
    _debugResolveMissKind = 0;
    _debugResolveMissAge = 0;
    _debugResolveMissContact = 0;
    _debugResolveMissDistance = 0;
    _debugRawPredictedCount = 0;
    _debugRawCoalescedCount = 0;
    _debugRawPredictedPencilCount = 0;
    _debugRawCoalescedPencilCount = 0;
  }

  List<TabletStylusPoint> _parseStylusPoints(dynamic raw) {
    if (raw is! List<dynamic>) {
      return const <TabletStylusPoint>[];
    }
    final List<TabletStylusPoint> parsed = <TabletStylusPoint>[];
    for (final dynamic item in raw) {
      final Map<dynamic, dynamic>? point = item as Map<dynamic, dynamic>?;
      if (point == null) {
        continue;
      }
      final double? x = (point['x'] as num?)?.toDouble();
      final double? y = (point['y'] as num?)?.toDouble();
      if (x == null || y == null || !x.isFinite || !y.isFinite) {
        continue;
      }
      final double? pressure = _normalizedNullablePressure(
        (point['pressure'] as num?)?.toDouble(),
      );
      parsed.add(TabletStylusPoint(position: Offset(x, y), pressure: pressure));
    }
    return parsed;
  }

  double? _normalizedNullablePressure(double? pressure) {
    if (pressure == null || !pressure.isFinite) {
      return null;
    }
    return pressure.clamp(0.0, 1.0);
  }

  bool isTabletPointer(PointerEvent event) {
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      return true;
    }
    if (!_supportDesktopTabletChannel) {
      return false;
    }
    final _TabletSample? sample = _sampleForPointer(event);
    if (sample == null) {
      return false;
    }
    return sample.inContact || sample.pressure > 0.0;
  }

  double? pressureForEvent(PointerEvent? event) {
    if (event == null) {
      return null;
    }
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      final double value = event.pressure;
      if (value.isFinite) {
        return value.clamp(0.0, 1.0);
      }
      return null;
    }
    if (!_supportDesktopTabletChannel) {
      return null;
    }
    final _TabletSample? sample = _sampleForPointer(event);
    if (sample == null) {
      return null;
    }
    if (!sample.inContact && !event.down) {
      return null;
    }
    return sample.pressure.clamp(0.0, 1.0);
  }

  _TabletSample? _sampleForPointer(PointerEvent event) {
    final _TabletSample? direct = _samples[event.device];
    if (direct != null) {
      return direct;
    }
    if (_samples.isEmpty) {
      return null;
    }
    if (_samples.length == 1) {
      return _samples.values.first;
    }
    for (final _TabletSample sample in _samples.values) {
      if (sample.inContact) {
        return sample;
      }
    }
    return _samples.values.first;
  }
}

class _TabletSample {
  const _TabletSample({
    required this.pressure,
    required this.min,
    required this.max,
    required this.inContact,
    required this.inRange,
  });

  final double pressure;
  final double min;
  final double max;
  final bool inContact;
  final bool inRange;
}

class _PencilMotionFrame {
  const _PencilMotionFrame({
    required this.anchor,
    required this.pressure,
    required this.inContact,
    required this.coalesced,
    required this.predicted,
    required this.rawPredictedCount,
    required this.rawCoalescedCount,
    required this.rawPredictedPencilCount,
    required this.rawCoalescedPencilCount,
  });

  final Offset anchor;
  final double? pressure;
  final bool inContact;
  final List<TabletStylusPoint> coalesced;
  final List<TabletStylusPoint> predicted;
  final int rawPredictedCount;
  final int rawCoalescedCount;
  final int rawPredictedPencilCount;
  final int rawCoalescedPencilCount;
}
