import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import '../theme/theme_controller.dart';
import '../preferences/app_preferences.dart';
import '../utils/tablet_input_bridge.dart';
import '../../performance/stroke_latency_monitor.dart';
import 'misarin_dialog.dart';

Future<void> showSettingsDialog(BuildContext context) {
  final GlobalKey<_SettingsDialogContentState> contentKey =
      GlobalKey<_SettingsDialogContentState>();
  return showMisarinDialog<void>(
    context: context,
    title: const Text('设置'),
    content: _SettingsDialogContent(key: contentKey),
    contentWidth: 420,
    maxWidth: 520,
    actions: [
      Button(
        onPressed: () => contentKey.currentState?.openTabletDiagnostic(),
        child: const Text('数位板测试'),
      ),
      Button(
        onPressed: () => contentKey.currentState?.resetToDefaults(),
        child: const Text('恢复默认'),
      ),
      Button(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('好的'),
      ),
    ],
  );
}

class _SettingsDialogContent extends StatefulWidget {
  const _SettingsDialogContent({super.key});

  @override
  State<_SettingsDialogContent> createState() => _SettingsDialogContentState();
}

class _SettingsDialogContentState extends State<_SettingsDialogContent> {
  late int _historyLimit;
  late bool _stylusPressureEnabled;
  late double _stylusCurve;
  late PenStrokeSliderRange _penSliderRange;
  late bool _fpsOverlayEnabled;

  @override
  void initState() {
    super.initState();
    _historyLimit = AppPreferences.instance.historyLimit;
    _stylusPressureEnabled = AppPreferences.instance.stylusPressureEnabled;
    _stylusCurve = AppPreferences.instance.stylusPressureCurve;
    _penSliderRange = AppPreferences.instance.penStrokeSliderRange;
    _fpsOverlayEnabled = AppPreferences.instance.showFpsOverlay;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final ThemeController controller = ThemeController.of(context);
    final ThemeMode themeMode = controller.themeMode;
    final int minHistory = AppPreferences.minHistoryLimit;
    final int maxHistory = AppPreferences.maxHistoryLimit;

    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: '主题模式',
          child: ComboBox<ThemeMode>(
            isExpanded: true,
            value: themeMode,
            items: const [
              ComboBoxItem(value: ThemeMode.light, child: Text('浅色')),
              ComboBoxItem(value: ThemeMode.dark, child: Text('深色')),
              ComboBoxItem(value: ThemeMode.system, child: Text('跟随系统')),
            ],
            onChanged: (mode) {
              if (mode == null) {
                return;
              }
              controller.onThemeModeChanged(mode);
              final AppPreferences prefs = AppPreferences.instance;
              if (prefs.themeMode != mode) {
                prefs.themeMode = mode;
                unawaited(AppPreferences.save());
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: '数位笔压设置',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('启用数位笔笔压'),
                  const SizedBox(width: 12),
                  ToggleSwitch(
                    checked: _stylusPressureEnabled,
                    onChanged: (value) {
                      setState(() => _stylusPressureEnabled = value);
                      final AppPreferences prefs = AppPreferences.instance;
                      prefs.stylusPressureEnabled = value;
                      unawaited(AppPreferences.save());
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StylusSliderTile(
                label: '响应曲线',
                description: '调整压力与笔触粗细之间的过渡速度。',
                value: _stylusCurve,
                min: AppPreferences.stylusCurveLowerBound,
                max: AppPreferences.stylusCurveUpperBound,
                enabled: _stylusPressureEnabled,
                asMultiplier: false,
                onChanged: (value) {
                  setState(() => _stylusCurve = value);
                  final AppPreferences prefs = AppPreferences.instance;
                  prefs.stylusPressureCurve = _stylusCurve;
                  unawaited(AppPreferences.save());
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: '笔刷大小滑块区间',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ComboBox<PenStrokeSliderRange>(
                isExpanded: true,
                value: _penSliderRange,
                items: PenStrokeSliderRange.values
                    .map(
                      (range) => ComboBoxItem<PenStrokeSliderRange>(
                        value: range,
                        child: Text(_sliderRangeLabel(range)),
                      ),
                    )
                    .toList(),
                onChanged: (range) {
                  if (range == null) {
                    return;
                  }
                  _updatePenSliderRange(range);
                },
              ),
              const SizedBox(height: 8),
              Text(
                '影响工具面板内的笔刷大小滑块，有助于在不同精度间快速切换。',
                style: theme.typography.caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: '撤销/恢复步数上限',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Slider(
                value: _historyLimit.toDouble(),
                min: minHistory.toDouble(),
                max: maxHistory.toDouble(),
                divisions: maxHistory - minHistory,
                onChanged: (value) {
                  final int rounded = value.round().clamp(
                    minHistory,
                    maxHistory,
                  );
                  if (rounded == _historyLimit) {
                    return;
                  }
                  setState(() => _historyLimit = rounded);
                  final AppPreferences prefs = AppPreferences.instance;
                  prefs.historyLimit = rounded;
                  unawaited(AppPreferences.save());
                },
              ),
              Text('当前上限：$_historyLimit 步', style: theme.typography.caption),
              Text(
                '调整撤销/恢复历史的保存数量，范围 $minHistory-$maxHistory。',
                style: theme.typography.caption,
              ),
            ],
          ),
        ),
        if (!kIsWeb) ...[
          const SizedBox(height: 16),
          InfoLabel(
            label: '开发者选项',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('性能监控面板')),
                    ToggleSwitch(
                      checked: _fpsOverlayEnabled,
                      onChanged: (value) {
                        setState(() => _fpsOverlayEnabled = value);
                        final AppPreferences prefs = AppPreferences.instance;
                        prefs.updateShowFpsOverlay(value);
                        unawaited(AppPreferences.save());
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '打开后会在屏幕角落显示 Flutter Performance Pulse 仪表盘，实时展示 FPS、CPU、内存与磁盘等数据。',
                  style: theme.typography.caption,
                ),
              ],
            ),
          ),
        ],
      ],
    );

    return SingleChildScrollView(primary: true, child: body);
  }

  void _updatePenSliderRange(PenStrokeSliderRange range) {
    setState(() => _penSliderRange = range);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.penStrokeSliderRange = range;
    _clampPenWidthForRange(prefs, range);
    unawaited(AppPreferences.save());
  }

  void _clampPenWidthForRange(
    AppPreferences prefs,
    PenStrokeSliderRange range,
  ) {
    final double adjusted = range.clamp(prefs.penStrokeWidth);
    if ((adjusted - prefs.penStrokeWidth).abs() > 0.0001) {
      prefs.penStrokeWidth = adjusted;
    }
  }

  String _sliderRangeLabel(PenStrokeSliderRange range) {
    switch (range) {
      case PenStrokeSliderRange.compact:
        return '1 - 60 px（粗调）';
      case PenStrokeSliderRange.medium:
        return '0.1 - 500 px（中档）';
      case PenStrokeSliderRange.full:
        return '0.01 - 1000 px（全范围）';
    }
  }

  void resetToDefaults() {
    final ThemeController controller = ThemeController.of(context);
    final AppPreferences prefs = AppPreferences.instance;
    final int defaultHistory = AppPreferences.defaultHistoryLimit;
    final ThemeMode defaultTheme = AppPreferences.defaultThemeMode;
    controller.onThemeModeChanged(defaultTheme);
    setState(() {
      _historyLimit = defaultHistory;
      _stylusPressureEnabled = AppPreferences.defaultStylusPressureEnabled;
      _stylusCurve = AppPreferences.defaultStylusCurve;
      _penSliderRange = AppPreferences.defaultPenStrokeSliderRange;
      _fpsOverlayEnabled = AppPreferences.defaultShowFpsOverlay;
    });
    prefs.historyLimit = defaultHistory;
    prefs.themeMode = defaultTheme;
    prefs.stylusPressureEnabled = _stylusPressureEnabled;
    prefs.stylusPressureCurve = _stylusCurve;
    prefs.penStrokeSliderRange = _penSliderRange;
    prefs.updateShowFpsOverlay(_fpsOverlayEnabled);
    _clampPenWidthForRange(prefs, _penSliderRange);
    unawaited(AppPreferences.save());
  }

  void openTabletDiagnostic() {
    _showTabletInspectDialog(context);
  }
}

Future<void> _showTabletInspectDialog(BuildContext context) async {
  return showMisarinDialog<void>(
    context: context,
    title: const Text('数位板输入测试'),
    contentWidth: 720,
    maxWidth: 820,
    content: const _TabletInspectPane(),
    actions: [
      Button(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
    ],
  );
}

class _StylusSliderTile extends StatelessWidget {
  const _StylusSliderTile({
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    this.asMultiplier = true,
  });

  final String label;
  final String description;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final bool asMultiplier;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final double clampedValue = value.clamp(min, max);
    final Widget slider = Slider(
      value: clampedValue,
      min: min,
      max: max,
      divisions: 100,
      onChanged: enabled ? onChanged : null,
    );

    final String valueLabel = asMultiplier
        ? '${clampedValue.toStringAsFixed(2)}x'
        : clampedValue.toStringAsFixed(2);

    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label：$valueLabel', style: theme.typography.bodyStrong),
          slider,
          Text(description, style: theme.typography.caption),
        ],
      ),
    );
  }
}

class _TabletInspectPane extends StatefulWidget {
  const _TabletInspectPane();

  @override
  State<_TabletInspectPane> createState() => _TabletInspectPaneState();
}

class _TabletInspectPaneState extends State<_TabletInspectPane> {
  final List<_TabletPoint> _points = <_TabletPoint>[];
  double? _latestPressure;
  double? _latestMin;
  double? _latestMax;
  double? _latestPhysicalRadius;
  double? _latestTilt;
  PointerDeviceKind? _latestPointerKind;
  int _sampleCount = 0;
  DateTime? _lastSample;
  double _estimatedRps = 0;
  bool _isDrawingContact = false;
  bool _latencyPending = false;
  bool _latencyFrameScheduled = false;

  void _handlePointer(PointerEvent event) {
    if (!_shouldCaptureEvent(event)) {
      return;
    }
    final Offset pos = event.localPosition;
    final double devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final double pressure =
        TabletInputBridge.instance.pressureForEvent(event) ??
        (event.pressure.isFinite ? event.pressure.clamp(0.0, 1.0) : 0.0);
    final double radius = _brushRadiusForPressure(pressure, devicePixelRatio);
    final double physicalRadius = radius * devicePixelRatio;
    final bool inContact = event.down || pressure > 0.0;
    setState(() {
      _latestPressure = pressure;
      _latestMin = event.pressureMin;
      _latestMax = event.pressureMax;
      _latestPhysicalRadius = physicalRadius;
      _latestTilt = event.orientation;
      _latestPointerKind = event.kind;
      final DateTime now = DateTime.now();
      if (_lastSample != null) {
        final Duration delta = now.difference(_lastSample!);
        if (delta.inMilliseconds > 0) {
          _estimatedRps =
              (_estimatedRps * 0.8) + (1000 / delta.inMilliseconds) * 0.2;
        }
      }
      _lastSample = now;
      if (!inContact) {
        _isDrawingContact = false;
        _latencyPending = false;
        return;
      }
      final bool isNewStroke = !_isDrawingContact;
      _isDrawingContact = true;
      if (isNewStroke) {
        StrokeLatencyMonitor.instance.recordStrokeStart();
        _latencyPending = true;
      }
      _points.add(
        _TabletPoint(
          position: pos,
          pressure: pressure,
          radius: radius,
          isNewStroke: isNewStroke,
        ),
      );
      _sampleCount += 1;
    });
    _scheduleLatencyFrameReport();
  }

  void _clear() {
    setState(() {
      _points.clear();
      _sampleCount = 0;
      _estimatedRps = 0;
      _latestPressure = null;
      _latestPhysicalRadius = null;
      _latestTilt = null;
      _latestPointerKind = null;
      _lastSample = null;
      _isDrawingContact = false;
      _latencyPending = false;
    });
    _latencyFrameScheduled = false;
  }

  bool _shouldCaptureEvent(PointerEvent event) {
    if (TabletInputBridge.instance.isTabletPointer(event) ||
        event.kind == PointerDeviceKind.unknown) {
      return true;
    }
    if (event.kind == PointerDeviceKind.mouse) {
      if (event is PointerDownEvent || event is PointerUpEvent) {
        return true;
      }
      if (event is PointerMoveEvent) {
        return event.down || (event.buttons & kPrimaryMouseButton) != 0;
      }
      return false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final double devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    return SizedBox(
      width: 700,
      height: 420,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handlePointer,
              onPointerMove: _handlePointer,
              onPointerUp: _handlePointerUp,
              onPointerHover: _handlePointer,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.brightness.isDark
                      ? const Color(0xFF171717)
                      : Colors.white,
                  border: Border.all(color: theme.accentColor.lighter),
                ),
                child: CustomPaint(
                  painter: _TabletPainter(_points, devicePixelRatio),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('实时参数', style: theme.typography.subtitle),
                const SizedBox(height: 12),
                _buildStat('最近压力', _latestPressure),
                _buildStat('pressureMin', _latestMin),
                _buildStat('pressureMax', _latestMax),
                _buildStat('估算半径 (px)', _latestPhysicalRadius),
                _buildStat('倾角(弧度)', _latestTilt),
                _buildStat('采样计数', _sampleCount.toDouble(), fractionDigits: 0),
                _buildStat('采样频率(Hz)', _estimatedRps),
                _buildTextStat('指针类型', _pointerKindLabel(_latestPointerKind)),
                const Spacer(),
                Button(onPressed: _clear, child: const Text('清空涂鸦')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _brushRadiusForPressure(double pressure, double devicePixelRatio) {
    const double minPhysicalRadius = 1.0;
    const double maxPhysicalRadius = 12.0;
    final double normalized = pressure.clamp(0.0, 1.0);
    final double eased = math.sqrt(normalized);
    final double physicalRadius =
        minPhysicalRadius + (maxPhysicalRadius - minPhysicalRadius) * eased;
    final double safePixelRatio = devicePixelRatio <= 0
        ? 1.0
        : devicePixelRatio;
    return physicalRadius / safePixelRatio;
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_shouldCaptureEvent(event)) {
      return;
    }
    setState(() {
      _latestPointerKind = event.kind;
      _latestPressure = 0;
      _isDrawingContact = false;
    });
    _latencyPending = false;
  }

  void _scheduleLatencyFrameReport() {
    if (!_latencyPending || _latencyFrameScheduled) {
      return;
    }
    _latencyFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _latencyFrameScheduled = false;
      if (!_latencyPending) {
        return;
      }
      StrokeLatencyMonitor.instance.recordFramePresented();
      _latencyPending = false;
    });
  }

  Widget _buildStat(String label, double? value, {int fractionDigits = 2}) {
    final FluentThemeData theme = FluentTheme.of(context);
    final String text = value == null
        ? '—'
        : value.toStringAsFixed(fractionDigits);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.typography.caption),
          Text(text, style: theme.typography.body),
        ],
      ),
    );
  }

  Widget _buildTextStat(String label, String value) {
    final FluentThemeData theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.typography.caption),
          Text(value, style: theme.typography.body),
        ],
      ),
    );
  }

  String _pointerKindLabel(PointerDeviceKind? kind) {
    if (kind == null) {
      return '—';
    }
    final String raw = kind.toString();
    final int dotIndex = raw.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == raw.length - 1) {
      return raw;
    }
    return raw.substring(dotIndex + 1);
  }
}

class _TabletPoint {
  const _TabletPoint({
    required this.position,
    required this.pressure,
    required this.radius,
    required this.isNewStroke,
  });

  final Offset position;
  final double pressure;
  final double radius;
  final bool isNewStroke;
}

class _TabletPainter extends CustomPainter {
  const _TabletPainter(this.points, this.devicePixelRatio);

  final List<_TabletPoint> points;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    final double safePixelRatio = devicePixelRatio <= 0
        ? 1.0
        : devicePixelRatio;
    final double minLogicalStroke = 1.0 / safePixelRatio;
    final double maxLogicalStroke = 12.0 / safePixelRatio;
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF0063B1).withOpacity(0.85);
    final Paint dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF0063B1).withOpacity(0.6);

    Offset? previous;
    double previousRadius = 0;
    for (final _TabletPoint point in points) {
      final Offset clamped = Offset(
        point.position.dx.clamp(0.0, size.width),
        point.position.dy.clamp(0.0, size.height),
      );
      if (point.isNewStroke || previous == null) {
        final double radius = math.max(point.radius, minLogicalStroke);
        canvas.drawCircle(clamped, radius, dotPaint);
        previous = clamped;
        previousRadius = point.radius;
        continue;
      }
      final double strokeWidth = ((previousRadius + point.radius) / 2)
          .clamp(minLogicalStroke, maxLogicalStroke)
          .toDouble();
      strokePaint.strokeWidth = strokeWidth;
      canvas.drawLine(previous, clamped, strokePaint);
      previous = clamped;
      previousRadius = point.radius;
    }
  }

  @override
  bool shouldRepaint(_TabletPainter oldDelegate) {
    return oldDelegate.points.length != points.length ||
        oldDelegate.devicePixelRatio != devicePixelRatio;
  }
}
