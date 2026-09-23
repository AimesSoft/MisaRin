part of 'painting_board.dart';

class _HueSaturationControls extends StatelessWidget {
  const _HueSaturationControls({
    required this.settings,
    required this.onHueChanged,
    required this.onSaturationChanged,
    required this.onLightnessChanged,
  });

  final _HueSaturationSettings settings;
  final ValueChanged<double> onHueChanged;
  final ValueChanged<double> onSaturationChanged;
  final ValueChanged<double> onLightnessChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FilterSlider(
          label: l10n.hue,
          value: settings.hue,
          min: -180,
          max: 180,
          onChanged: onHueChanged,
        ),
        _FilterSlider(
          label: l10n.saturation,
          value: settings.saturation,
          min: -100,
          max: 100,
          onChanged: onSaturationChanged,
        ),
        _FilterSlider(
          label: l10n.lightness,
          value: settings.lightness,
          min: -100,
          max: 100,
          onChanged: onLightnessChanged,
        ),
      ],
    );
  }
}

class _BrightnessContrastControls extends StatelessWidget {
  const _BrightnessContrastControls({
    required this.settings,
    required this.onBrightnessChanged,
    required this.onContrastChanged,
  });

  final _BrightnessContrastSettings settings;
  final ValueChanged<double> onBrightnessChanged;
  final ValueChanged<double> onContrastChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FilterSlider(
          label: l10n.brightness,
          value: settings.brightness,
          min: -100,
          max: 100,
          onChanged: onBrightnessChanged,
        ),
        _FilterSlider(
          label: l10n.contrast,
          value: settings.contrast,
          min: -100,
          max: 100,
          onChanged: onContrastChanged,
        ),
      ],
    );
  }
}

class _BlackWhiteControls extends StatelessWidget {
  const _BlackWhiteControls({
    required this.settings,
    required this.onBlackPointChanged,
    required this.onWhitePointChanged,
    required this.onMidToneChanged,
  });

  final _BlackWhiteSettings settings;
  final ValueChanged<double> onBlackPointChanged;
  final ValueChanged<double> onWhitePointChanged;
  final ValueChanged<double> onMidToneChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FilterSlider(
          label: l10n.blackPoint,
          value: settings.blackPoint,
          min: 0,
          max: 100,
          onChanged: onBlackPointChanged,
        ),
        _FilterSlider(
          label: l10n.whitePoint,
          value: settings.whitePoint,
          min: 0,
          max: 100,
          onChanged: onWhitePointChanged,
        ),
        _FilterSlider(
          label: l10n.midTone,
          value: settings.midTone,
          min: -100,
          max: 100,
          onChanged: onMidToneChanged,
        ),
      ],
    );
  }
}

class _BinarizeControls extends StatelessWidget {
  const _BinarizeControls({
    required this.threshold,
    required this.onThresholdChanged,
  });

  final double threshold;
  final ValueChanged<double> onThresholdChanged;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final double clamped = threshold.clamp(0.0, 255.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('透明度阈值', style: theme.typography.bodyStrong),
            const Spacer(),
            Text(clamped.toStringAsFixed(0), style: theme.typography.caption),
          ],
        ),
        AppSlider(
          min: 0,
          max: 255,
          divisions: 255,
          value: clamped,
          onChanged: onThresholdChanged,
        ),
        const SizedBox(height: 8),
        Text(
          '低于阈值的半透明像素会被清除，其余像素提升为全不透明。默认阈值 128，适用于赛璐璐线稿与色块二值化。',
          style: theme.typography.caption,
        ),
      ],
    );
  }
}

class _GaussianBlurStepSegment {
  _GaussianBlurStepSegment({
    required this.start,
    required this.end,
    required this.step,
  }) : assert(end > start),
       assert(step > 0),
       assert(() {
         final double count = (end - start) / step;
         return (count - count.round()).abs() < 1e-6;
       }());

  final double start;
  final double end;
  final double step;

  int get stepCount => ((end - start) / step).round();
}

class _GaussianBlurSliderScale {
  _GaussianBlurSliderScale(this.segments)
    : assert(segments.isNotEmpty),
      assert(segments.last.end >= _kGaussianBlurMaxRadius);

  final List<_GaussianBlurStepSegment> segments;

  int get totalSteps => _totalSteps ??= _computeTotalSteps();
  int? _totalSteps;

  int _computeTotalSteps() {
    int steps = 0;
    for (final _GaussianBlurStepSegment segment in segments) {
      steps += segment.stepCount;
    }
    return steps;
  }

  double sliderValueFromRadius(double radius) {
    final double clamped = radius.clamp(0.0, _kGaussianBlurMaxRadius);
    if (clamped <= 0) {
      return 0;
    }
    double sliderPosition = 0;
    for (final _GaussianBlurStepSegment segment in segments) {
      if (clamped <= segment.end) {
        final double offset = clamped - segment.start;
        final double steps = (offset / segment.step).clamp(
          0.0,
          segment.stepCount.toDouble(),
        );
        return (sliderPosition + steps).clamp(0.0, totalSteps.toDouble());
      }
      sliderPosition += segment.stepCount;
    }
    return totalSteps.toDouble();
  }

  double radiusFromSliderValue(double sliderValue) {
    final int stepIndex = sliderValue.round().clamp(0, totalSteps);
    if (stepIndex == 0) {
      return 0;
    }
    int remaining = stepIndex;
    for (final _GaussianBlurStepSegment segment in segments) {
      if (remaining <= segment.stepCount) {
        return (segment.start + remaining * segment.step).clamp(
          0.0,
          _kGaussianBlurMaxRadius,
        );
      }
      remaining -= segment.stepCount;
    }
    return _kGaussianBlurMaxRadius;
  }
}

final _GaussianBlurSliderScale _gaussianBlurSliderScale =
    _GaussianBlurSliderScale(<_GaussianBlurStepSegment>[
      _GaussianBlurStepSegment(start: 0, end: 2, step: 0.1),
      _GaussianBlurStepSegment(start: 2, end: 10, step: 0.2),
      _GaussianBlurStepSegment(start: 10, end: 50, step: 1),
      _GaussianBlurStepSegment(start: 50, end: 200, step: 5),
      _GaussianBlurStepSegment(start: 200, end: 500, step: 10),
      _GaussianBlurStepSegment(start: 500, end: 1000, step: 20),
    ]);

class _GaussianBlurControls extends StatelessWidget {
  const _GaussianBlurControls({
    required this.radius,
    required this.onRadiusChanged,
  });

  final double radius;
  final ValueChanged<double> onRadiusChanged;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final double clamped = radius.clamp(0, _kGaussianBlurMaxRadius);
    final double sliderValue = _gaussianBlurSliderScale.sliderValueFromRadius(
      clamped,
    );
    final int sliderDivisions = _gaussianBlurSliderScale.totalSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('模糊半径', style: theme.typography.bodyStrong),
            const Spacer(),
            Text(
              '${clamped.toStringAsFixed(1)} px',
              style: theme.typography.caption,
            ),
          ],
        ),
        AppSlider(
          min: 0,
          max: sliderDivisions.toDouble(),
          divisions: sliderDivisions,
          value: sliderValue,
          onChanged: (value) => onRadiusChanged(
            _gaussianBlurSliderScale.radiusFromSliderValue(value),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '调节模糊强度（0 - 1000 px）。滑块前段拥有更高的分辨率，向右拖动时步进会逐渐增大。',
          style: theme.typography.caption,
        ),
      ],
    );
  }
}

class _LeakRemovalControls extends StatelessWidget {
  const _LeakRemovalControls({
    required this.radius,
    required this.onRadiusChanged,
  });

  final double radius;
  final ValueChanged<double> onRadiusChanged;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final double clamped = radius.clamp(0, _kLeakRemovalMaxRadius);
    final int divisions = _kLeakRemovalMaxRadius.round().clamp(1, 1000).toInt();
    final int rounded = clamped.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('修复范围', style: theme.typography.bodyStrong),
            const Spacer(),
            Text('$rounded px', style: theme.typography.caption),
          ],
        ),
        AppSlider(
          min: 0,
          max: _kLeakRemovalMaxRadius,
          divisions: divisions,
          value: clamped,
          onChanged: onRadiusChanged,
        ),
        const SizedBox(height: 8),
        Text(
          '填充完全被线稿包围的透明针眼，可设置填补半径（像素）。数值越大，可修复的漏色面积越大。',
          style: theme.typography.caption,
        ),
      ],
    );
  }
}

class _MorphologyControls extends StatelessWidget {
  const _MorphologyControls({
    required this.label,
    required this.radius,
    required this.maxRadius,
    required this.onRadiusChanged,
  });

  final String label;
  final double radius;
  final double maxRadius;
  final ValueChanged<double> onRadiusChanged;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final double clamped = radius.clamp(0, maxRadius);
    final int divisions = maxRadius.round().clamp(1, 1000).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(label, style: theme.typography.bodyStrong),
            const Spacer(),
            Text(
              '${clamped.toStringAsFixed(0)} px',
              style: theme.typography.caption,
            ),
          ],
        ),
        AppSlider(
          min: 0,
          max: maxRadius,
          divisions: divisions,
          value: clamped,
          onChanged: onRadiusChanged,
        ),
        const SizedBox(height: 8),
        Text(
          '基于透明度的形态学处理。收窄会让轮廓内缩，拉伸会让覆盖区域向外扩张。',
          style: theme.typography.caption,
        ),
      ],
    );
  }
}

class _AntialiasPanelBody extends StatelessWidget {
  const _AntialiasPanelBody({
    required this.level,
    required this.onLevelChanged,
  });

  final int level;
  final ValueChanged<int> onLevelChanged;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final int maxLevel = kAntialiasLevelDescriptions.length - 1;
    final int safeLevel = level.clamp(0, maxLevel).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('选择边缘柔化级别', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        Text(
          '在平滑边缘的同时保留线条密度，呈现接近 Retas 的细腻质感。',
          style: theme.typography.caption,
        ),
        const SizedBox(height: 12),
        AppSlider(
          value: safeLevel.toDouble(),
          min: 0,
          max: maxLevel.toDouble(),
          divisions: maxLevel,
          label: '等级 $safeLevel',
          onChanged: (value) => onLevelChanged(value.round()),
        ),
        const SizedBox(height: 8),
        Text(
          kAntialiasLevelDescriptions[safeLevel],
          style: theme.typography.caption,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List<Widget>.generate(maxLevel + 1, (index) {
            final bool selected = index == safeLevel;
            final Widget button = selected
                ? FilledButton(
                    onPressed: () => onLevelChanged(index),
                    child: Text('等级 $index'),
                  )
                : Button(
                    onPressed: () => onLevelChanged(index),
                    child: Text('等级 $index'),
                  );
            return SizedBox(width: 72, child: button);
          }),
        ),
      ],
    );
  }
}

class _ColorRangeCardBody extends StatelessWidget {
  const _ColorRangeCardBody({
    required this.totalColors,
    required this.maxSelectableColors,
    required this.selectedColors,
    required this.isBusy,
    required this.onChanged,
  });

  final int totalColors;
  final int maxSelectableColors;
  final int selectedColors;
  final bool isBusy;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final int maxColors = math.max(1, maxSelectableColors);
    final int clampedSelection = selectedColors.clamp(1, maxColors).toInt();
    final int? divisions = maxColors > 1
        ? (maxColors <= 200 ? math.max(1, maxColors - 1) : null)
        : null;
    final bool limited = totalColors > maxSelectableColors;
    final bool sliderEnabled = !isBusy && maxColors > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('色彩数量', style: theme.typography.bodyStrong),
            const Spacer(),
            if (isBusy)
              const SizedBox(
                width: 16,
                height: 16,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              Text(
                '$clampedSelection / $maxColors 种',
                style: theme.typography.caption,
              ),
          ],
        ),
        AppSlider(
          min: 1,
          max: maxColors.toDouble(),
          value: clampedSelection.toDouble(),
          divisions: divisions,
          onChanged: sliderEnabled ? onChanged : null,
        ),
        const SizedBox(height: 8),
        Text(
          limited
              ? '当前图层包含 $totalColors 种颜色，为保证性能最多保留 $maxSelectableColors 种。'
              : '检测到当前图层包含 $maxColors 种颜色。拖动滑块标记需要保留的颜色数量。',
          style: theme.typography.caption,
        ),
        const SizedBox(height: 6),
        Text('降低颜色数量会产生类似木刻/分色的效果，滑动后立即预览。', style: theme.typography.caption),
      ],
    );
  }
}

class _FilterSlider extends StatelessWidget {
  const _FilterSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: theme.typography.bodyStrong),
              const Spacer(),
              Text(value.toStringAsFixed(0), style: theme.typography.caption),
            ],
          ),
          AppSlider(
            min: min,
            max: max,
            value: value.clamp(min, max),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
