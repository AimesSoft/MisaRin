import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A Fluent slider with an overlay-free implementation on macOS.
///
/// Material Slider's OverlayPortal can serialize orphan semantics nodes when a
/// route opens (flutter/flutter#190357). On macOS this corrupts the native AX
/// tree and can crash FlutterTextField.frame. ExcludeSemantics alone does not
/// prevent the portal from publishing orphan nodes during route transitions.
class AppSlider extends fluent.Slider {
  const AppSlider({
    super.key,
    required super.value,
    required super.onChanged,
    super.onChangeStart,
    super.onChangeEnd,
    super.min,
    super.max,
    super.divisions,
    super.style,
    super.label,
    super.focusNode,
    super.vertical,
    super.autofocus,
    super.mouseCursor,
  });

  @override
  State<fluent.Slider> createState() =>
      // Select the matching state before Fluent creates its Material slider.
      // ignore: no_logic_in_create_state
      defaultTargetPlatform == TargetPlatform.macOS
      ? _MacosSliderState()
      : super.createState();
}

class _MacosSliderState extends State<fluent.Slider> {
  final FocusNode _ownedFocusNode = FocusNode();
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;
  double? _dragValue;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;
  bool get _enabled => widget.onChanged != null && widget.max > widget.min;
  double get _step => (widget.max - widget.min) / (widget.divisions ?? 10);
  double _clamp(double value) => value.clamp(widget.min, widget.max);
  String _percentage(double value) => widget.max == widget.min
      ? '0%'
      : '${((value - widget.min) / (widget.max - widget.min) * 100).round()}%';

  void _adjust(double value) {
    if (!_enabled) return;
    final next = _clamp(value);
    widget.onChangeStart?.call(widget.value);
    widget.onChanged!(next);
    widget.onChangeEnd?.call(next);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_enabled || event is KeyUpEvent) return KeyEventResult.ignored;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowRight => rtl ? -_step : _step,
      LogicalKeyboardKey.arrowLeft => rtl ? _step : -_step,
      LogicalKeyboardKey.arrowUp => _step,
      LogicalKeyboardKey.arrowDown => -_step,
      LogicalKeyboardKey.home => widget.min - widget.value,
      LogicalKeyboardKey.end => widget.max - widget.value,
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;
    _adjust(widget.value + delta);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _ownedFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final style = fluent.SliderTheme.of(context).merge(widget.style);
    final states = <WidgetState>{
      if (!_enabled) WidgetState.disabled,
      if (_hovered) WidgetState.hovered,
      if (_pressed) WidgetState.pressed,
      if (_focused) WidgetState.focused,
    };
    final direction = Directionality.of(context);
    final fraction = widget.max > widget.min
        ? (widget.value - widget.min) / (widget.max - widget.min)
        : 0.0;
    Widget slider = TweenAnimationBuilder<double>(
      duration: theme.fastAnimationDuration,
      tween: Tween<double>(
        end: style.thumbBallInnerFactor?.resolve(states) ?? 0.5,
      ),
      builder: (context, innerFactor, _) => _SliderVisual(
        value: fraction,
        enabled: _enabled,
        divisions: widget.divisions,
        direction: direction,
        thumbShape: fluent.SliderThumbShape(
          pressedElevation: 1,
          useBall: style.useThumbBall ?? true,
          innerFactor: innerFactor,
          borderColor: theme.resources.controlSolidFillColorDefault,
          enabledThumbRadius: style.thumbRadius?.resolve(states) ?? 10,
          disabledThumbRadius: style.thumbRadius?.resolve(states),
        ),
        sliderTheme: material.SliderThemeData(
          trackHeight: style.trackHeight?.resolve(states) ?? 3.75,
          activeTrackColor: style.activeColor?.resolve(states),
          inactiveTrackColor: style.inactiveColor?.resolve(states),
          disabledActiveTrackColor: style.activeColor?.resolve({
            WidgetState.disabled,
          }),
          disabledInactiveTrackColor: style.inactiveColor?.resolve({
            WidgetState.disabled,
          }),
          thumbColor: style.thumbColor?.resolve(states),
          disabledThumbColor: style.thumbColor?.resolve({WidgetState.disabled}),
          activeTickMarkColor: material.Theme.of(
            context,
          ).colorScheme.onPrimary.withValues(alpha: 0.38),
          inactiveTickMarkColor: material.Theme.of(
            context,
          ).colorScheme.onSurfaceVariant,
          disabledActiveTickMarkColor:
              theme.resources.controlStrongFillColorDisabled,
          disabledInactiveTickMarkColor:
              theme.resources.controlStrongFillColorDisabled,
        ),
      ),
    );
    final visual = slider;
    slider = Builder(
      builder: (context) {
        double valueAt(Offset position) {
          final width = (context.findRenderObject()! as RenderBox).size.width;
          final extent = width - 2 * _trackSidePadding;
          if (extent <= 0) return widget.value;
          var fraction = ((position.dx - _trackSidePadding) / extent).clamp(
            0.0,
            1.0,
          );
          if (direction == TextDirection.rtl) fraction = 1 - fraction;
          if (widget.divisions case final divisions?) {
            fraction = (fraction * divisions).round() / divisions;
          }
          return widget.min + fraction * (widget.max - widget.min);
        }

        void update(Offset position) {
          _dragValue = valueAt(position);
          widget.onChanged!(_dragValue!);
        }

        void finish() {
          if (_dragValue case final value?) widget.onChangeEnd?.call(value);
          _dragValue = null;
        }

        return Listener(
          onPointerDown: _enabled
              ? (_) => setState(() => _pressed = true)
              : null,
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: !_enabled
                ? null
                : (details) {
                    _focusNode.requestFocus();
                    _adjust(valueAt(details.localPosition));
                  },
            onHorizontalDragStart: !_enabled
                ? null
                : (details) {
                    _focusNode.requestFocus();
                    widget.onChangeStart?.call(widget.value);
                    update(details.localPosition);
                  },
            onHorizontalDragUpdate: !_enabled
                ? null
                : (details) => update(details.localPosition),
            onHorizontalDragEnd: !_enabled ? null : (_) => finish(),
            onHorizontalDragCancel: !_enabled ? null : finish,
            child: visual,
          ),
        );
      },
    );
    if (widget.vertical) {
      slider = RotatedBox(
        quarterTurns: Directionality.of(context) == TextDirection.ltr ? 3 : 5,
        child: slider,
      );
    }
    if (widget.label case final label?) {
      slider = fluent.Tooltip(message: label, child: slider);
    }
    return Semantics(
      container: true,
      slider: true,
      enabled: _enabled,
      focusable: _enabled,
      focused: _focused,
      value: _percentage(widget.value),
      increasedValue: _enabled
          ? _percentage(_clamp(widget.value + _step))
          : null,
      decreasedValue: _enabled
          ? _percentage(_clamp(widget.value - _step))
          : null,
      onIncrease: _enabled ? () => _adjust(widget.value + _step) : null,
      onDecrease: _enabled ? () => _adjust(widget.value - _step) : null,
      child: ExcludeSemantics(
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          canRequestFocus: _enabled,
          includeSemantics: false,
          onFocusChange: (focused) => setState(() => _focused = focused),
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor: widget.mouseCursor,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: fluent.FocusBorder(
              focused:
                  _focused &&
                  FocusManager.instance.highlightMode ==
                      FocusHighlightMode.traditional,
              child: Padding(
                padding: style.margin ?? EdgeInsets.zero,
                child: slider,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const double _trackSidePadding = 10;

// Reuse Fluent's actual thumb painter and Material's track painter. These are
// painting primitives; they do not create Material Slider's OverlayPortal.
class _SliderVisual extends LeafRenderObjectWidget {
  const _SliderVisual({
    required this.value,
    required this.enabled,
    required this.divisions,
    required this.direction,
    required this.thumbShape,
    required this.sliderTheme,
  });
  final double value;
  final bool enabled;
  final int? divisions;
  final TextDirection direction;
  final fluent.SliderThumbShape thumbShape;
  final material.SliderThemeData sliderTheme;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSliderVisual(this);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliderVisual renderObject,
  ) {
    renderObject.configuration = this;
  }
}

class _RenderSliderVisual extends RenderBox {
  _RenderSliderVisual(this._configuration);
  _SliderVisual _configuration;
  final TextPainter _labelPainter = TextPainter();

  @override
  void dispose() {
    _labelPainter.dispose();
    super.dispose();
  }

  set configuration(_SliderVisual value) {
    _configuration = value;
    markNeedsLayout();
    markNeedsPaint();
  }

  double get _diameter => _configuration.thumbShape
      .getPreferredSize(
        _configuration.enabled,
        _configuration.divisions != null,
      )
      .width;
  double get _height =>
      math.max(_diameter, _configuration.sliderTheme.trackHeight!);

  @override
  double computeMinIntrinsicWidth(double height) => 144 + _diameter;
  @override
  double computeMaxIntrinsicWidth(double height) => 144 + _diameter;
  @override
  double computeMinIntrinsicHeight(double width) => _height;
  @override
  double computeMaxIntrinsicHeight(double width) => _height;
  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    Size(
      constraints.hasBoundedWidth ? constraints.maxWidth : 144 + _diameter,
      constraints.hasBoundedHeight ? constraints.maxHeight : _height,
    ),
  );
  @override
  void performLayout() => size = computeDryLayout(constraints);
  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final config = _configuration;
    final sliderTheme = config.sliderTheme.copyWith(
      thumbShape: config.thumbShape,
      overlayShape: const material.RoundSliderOverlayShape(overlayRadius: 0),
    );
    final track = _FluentTrackShape();
    final rect = track.getPreferredRect(
      parentBox: this,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final visualPosition = config.direction == TextDirection.ltr
        ? config.value
        : 1 - config.value;
    final center = Offset(
      rect.left + visualPosition * rect.width,
      rect.center.dy,
    );
    final enableAnimation = AlwaysStoppedAnimation<double>(
      config.enabled ? 1 : 0,
    );
    track.paint(
      context,
      offset,
      parentBox: this,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: config.direction,
      thumbCenter: center,
      isDiscrete: config.divisions != null,
      isEnabled: config.enabled,
    );
    final tickShape = material.RoundSliderTickMarkShape();
    final tickWidth = tickShape
        .getPreferredSize(isEnabled: config.enabled, sliderTheme: sliderTheme)
        .width;
    if (config.divisions case final divisions?
        when rect.width / divisions >= 3 * tickWidth) {
      for (var i = 0; i <= divisions; i++) {
        tickShape.paint(
          context,
          Offset(
            rect.left +
                i / divisions * (rect.width - rect.height) +
                rect.height / 2,
            center.dy,
          ),
          parentBox: this,
          sliderTheme: sliderTheme,
          enableAnimation: enableAnimation,
          textDirection: config.direction,
          thumbCenter: center,
          isEnabled: config.enabled,
        );
      }
    }
    config.thumbShape.paint(
      context,
      center,
      activationAnimation: const AlwaysStoppedAnimation<double>(1),
      enableAnimation: enableAnimation,
      isDiscrete: config.divisions != null,
      labelPainter: _labelPainter,
      parentBox: this,
      sliderTheme: sliderTheme,
      textDirection: config.direction,
      value: config.value,
      textScaleFactor: 1,
      sizeWithOverflow: size,
    );
  }
}

class _FluentTrackShape extends material.RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required material.SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) => Rect.fromLTWH(
    offset.dx + _trackSidePadding,
    offset.dy + (parentBox.size.height - sliderTheme.trackHeight!) / 2,
    math.max(0, parentBox.size.width - 2 * _trackSidePadding),
    sliderTheme.trackHeight!,
  );
}
