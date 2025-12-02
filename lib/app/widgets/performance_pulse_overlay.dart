import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_performance_pulse/flutter_performance_pulse.dart';

import '../../performance/stroke_latency_monitor.dart';

class PerformancePulseOverlay extends StatelessWidget {
  const PerformancePulseOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final bool alignRight = defaultTargetPlatform == TargetPlatform.macOS;
    final double? right = alignRight ? 16 : null;
    final double? left = alignRight ? null : 16;
    final FluentThemeData fluentTheme = FluentTheme.of(context);

    final bool isDarkMode = fluentTheme.brightness == Brightness.dark;
    final Color defaultTextColor =
        fluentTheme.typography.body?.color ?? Colors.black;
    final Color backgroundColor = isDarkMode
        ? const Color(0xFF1F1F1F).withOpacity(0.92)
        : Colors.white.withOpacity(0.95);
    final DashboardTheme dashboardTheme = DashboardTheme(
      backgroundColor: backgroundColor,
      textColor: isDarkMode ? Colors.white : defaultTextColor,
      warningColor: Colors.orange,
      errorColor: Colors.red,
      chartLineColor: fluentTheme.accentColor.light,
      chartFillColor: fluentTheme.accentColor.light.withOpacity(0.2),
    );

    return Positioned(
      top: 16,
      right: right,
      left: left,
      child: IgnorePointer(
        ignoring: true,
        child: material.Theme(
          data: material.ThemeData(
            useMaterial3: true,
            colorScheme: material.ColorScheme.fromSeed(
              seedColor: fluentTheme.accentColor.normal,
              brightness: isDarkMode ? Brightness.dark : Brightness.light,
            ),
          ),
          child: material.Material(
            elevation: 10,
            borderRadius: const material.BorderRadius.all(
              material.Radius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PerformanceDashboard(
                  showFPS: true,
                  showCPU: true,
                  showDisk: false,
                  theme: dashboardTheme,
                ),
                const SizedBox(height: 12),
                _LatencyCard(theme: dashboardTheme),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LatencyCard extends StatefulWidget {
  const _LatencyCard({required this.theme});

  final DashboardTheme theme;

  @override
  State<_LatencyCard> createState() => _LatencyCardState();
}

class _LatencyCardState extends State<_LatencyCard> {
  static const int _kMaxSamples = 30;
  StreamSubscription<double>? _subscription;
  List<double> _history = const <double>[];
  double _latestLatency = 0;
  double _averageLatency = 0;

  @override
  void initState() {
    super.initState();
    _subscription = StrokeLatencyMonitor.instance.latencyStream.listen(
      _handleSample,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handleSample(double value) {
    final List<double> next = List<double>.from(_history)..add(value);
    if (next.length > _kMaxSamples) {
      next.removeRange(0, next.length - _kMaxSamples);
    }
    final double average = next.isEmpty
        ? 0
        : next.reduce((double a, double b) => a + b) / next.length;
    setState(() {
      _history = next;
      _latestLatency = value;
      _averageLatency = average;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color textColor = widget.theme.textColor;
    final double maxValue = _history.isEmpty
        ? 1
        : _history.reduce(math.max).clamp(1, 500).toDouble();
    final bool hasData = _history.isNotEmpty;
    final double highlightedLatency = hasData
        ? _latestLatency
        : StrokeLatencyMonitor.instance.latestLatencyMs;
    final String latencyLabel = hasData
        ? '${highlightedLatency.toStringAsFixed(1)} ms'
        : '-- ms';
    final Color latencyColor = highlightedLatency > 45
        ? widget.theme.warningColor
        : widget.theme.textColor;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.theme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(51),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(material.Icons.timeline, color: latencyColor, size: 16),
              const SizedBox(width: 4),
              Text(
                '延迟: $latencyLabel',
                style: TextStyle(
                  color: latencyColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 160,
            height: 40,
            child: _LatencySparkline(
              samples: _history,
              maxValue: maxValue,
              lineColor: widget.theme.chartLineColor,
              fillColor: widget.theme.chartFillColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasData
                ? '最近平均：${_averageLatency.toStringAsFixed(1)} ms'
                : '等待笔迹数据…',
            style: TextStyle(color: textColor.withOpacity(0.9), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LatencySparkline extends StatelessWidget {
  const _LatencySparkline({
    required this.samples,
    required this.maxValue,
    required this.lineColor,
    required this.fillColor,
  });

  final List<double> samples;
  final double maxValue;
  final Color lineColor;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LatencySparklinePainter(
        samples: samples,
        maxValue: maxValue,
        lineColor: lineColor,
        fillColor: fillColor,
      ),
    );
  }
}

class _LatencySparklinePainter extends CustomPainter {
  _LatencySparklinePainter({
    required this.samples,
    required this.maxValue,
    required this.lineColor,
    required this.fillColor,
  });

  final List<double> samples;
  final double maxValue;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) {
      final Paint baseline = Paint()
        ..color = lineColor.withOpacity(0.4)
        ..strokeWidth = 1.5;
      final double midY = size.height / 2;
      canvas.drawLine(Offset(0, midY), Offset(size.width, midY), baseline);
      return;
    }

    final double effectiveMax = maxValue <= 0 ? 1 : maxValue;
    final double step = samples.length == 1
        ? size.width
        : size.width / (samples.length - 1);
    final List<Offset> points = <Offset>[];
    for (int i = 0; i < samples.length; i++) {
      final double normalized = (samples[i] / effectiveMax).clamp(0.0, 1.0);
      final double y = size.height - (normalized * size.height);
      final double x = samples.length == 1 ? size.width : i * step;
      points.add(Offset(x, y));
    }
    final Path line = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      line.lineTo(points[i].dx, points[i].dy);
    }
    final Path fill = Path()
      ..moveTo(points.first.dx, size.height)
      ..lineTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      fill.lineTo(points[i].dx, points[i].dy);
    }
    fill
      ..lineTo(points.last.dx, size.height)
      ..close();

    final Paint fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final Paint linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(line, linePaint);
  }

  @override
  bool shouldRepaint(covariant _LatencySparklinePainter oldDelegate) {
    return !listEquals(oldDelegate.samples, samples) ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor;
  }
}
