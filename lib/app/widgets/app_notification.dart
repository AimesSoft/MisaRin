import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

class AppNotificationAnchor extends StatefulWidget {
  const AppNotificationAnchor({super.key, required this.child});

  final Widget child;

  @override
  State<AppNotificationAnchor> createState() => _AppNotificationAnchorState();
}

class _AppNotificationAnchorState extends State<AppNotificationAnchor> {
  final Object _token = Object();
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleUpdate();
  }

  @override
  void didUpdateWidget(covariant AppNotificationAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    if (_updateScheduled) {
      return;
    }
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (!mounted) {
        return;
      }
      final RenderObject? renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        return;
      }
      final Offset offset = renderObject.localToGlobal(Offset.zero);
      final Rect rect = offset & renderObject.size;
      _AppNotificationAnchorRegistry.instance.register(_token, rect);
    });
  }

  @override
  void dispose() {
    _AppNotificationAnchorRegistry.instance.unregister(_token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleUpdate();
    return widget.child;
  }
}

class AppNotifications {
  const AppNotifications._();

  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context, {
    required String message,
    InfoBarSeverity severity = InfoBarSeverity.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);

    _currentEntry?.remove();
    _currentEntry = null;

    final Rect? anchorRect = _AppNotificationAnchorRegistry.instance.rect;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AppNotificationOverlay(
        message: message,
        severity: severity,
        duration: duration,
        anchorRect: anchorRect,
        onClosed: () {
          if (_currentEntry == entry) {
            _currentEntry = null;
          }
          entry.remove();
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _AppNotificationAnchorRegistry {
  _AppNotificationAnchorRegistry._();

  static final _AppNotificationAnchorRegistry instance =
      _AppNotificationAnchorRegistry._();

  Object? _token;
  Rect? _rect;

  Rect? get rect => _rect;

  void register(Object token, Rect rect) {
    _token = token;
    _rect = rect;
  }

  void unregister(Object token) {
    if (_token == token) {
      _token = null;
      _rect = null;
    }
  }
}

class _AppNotificationOverlay extends StatefulWidget {
  const _AppNotificationOverlay({
    required this.message,
    required this.severity,
    required this.duration,
    required this.anchorRect,
    required this.onClosed,
  });

  final String message;
  final InfoBarSeverity severity;
  final Duration duration;
  final Rect? anchorRect;
  final VoidCallback onClosed;

  @override
  State<_AppNotificationOverlay> createState() =>
      _AppNotificationOverlayState();
}

class _AppNotificationOverlayState extends State<_AppNotificationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  Timer? _timer;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) {
      widget.onClosed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget card = FadeTransition(
      opacity: _fade,
      child: _AppNotificationCard(
        message: widget.message,
        severity: widget.severity,
        onClose: _dismiss,
      ),
    );

    return CustomSingleChildLayout(
      delegate: _NotificationLayoutDelegate(anchorRect: widget.anchorRect),
      child: card,
    );
  }
}

class _AppNotificationCard extends StatelessWidget {
  const _AppNotificationCard({
    required this.message,
    required this.severity,
    required this.onClose,
  });

  final String message;
  final InfoBarSeverity severity;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final _AppNotificationVisual visual = _AppNotificationVisual.resolve(
      theme,
      severity,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: visual.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: visual.border, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(visual.icon, color: visual.iconColor, size: 14),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: (theme.typography.body ?? const TextStyle(fontSize: 13))
                  .copyWith(color: visual.textColor, height: 1.2),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onClose,
            icon: Icon(FluentIcons.clear, size: 12, color: visual.iconColor),
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.all(2)),
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppNotificationVisual {
  const _AppNotificationVisual({
    required this.background,
    required this.border,
    required this.textColor,
    required this.iconColor,
    required this.icon,
  });

  final Color background;
  final Color border;
  final Color textColor;
  final Color iconColor;
  final IconData icon;

  static _AppNotificationVisual resolve(
    FluentThemeData theme,
    InfoBarSeverity severity,
  ) {
    final bool isDark = theme.brightness.isDark;
    final Color fallbackColor = isDark ? const Color(0xFF1F1F1F) : Colors.white;
    Color background = theme.cardColor;
    if (background.alpha != 0xFF) {
      background = fallbackColor;
    }
    final Color border = isDark
        ? Colors.white.withOpacity(0.12)
        : Colors.black.withOpacity(0.08);
    final Color textColor =
        theme.typography.body?.color ?? theme.resources.textFillColorPrimary;
    final Color iconColor = textColor;
    return _AppNotificationVisual(
      background: background,
      border: border,
      textColor: textColor,
      iconColor: iconColor,
      icon: _iconForSeverity(severity),
    );
  }

  static IconData _iconForSeverity(InfoBarSeverity severity) {
    switch (severity) {
      case InfoBarSeverity.success:
        return FluentIcons.check_mark;
      case InfoBarSeverity.warning:
        return FluentIcons.warning;
      case InfoBarSeverity.error:
        return FluentIcons.status_error_full;
      case InfoBarSeverity.info:
      default:
        return FluentIcons.info;
    }
  }
}

class _NotificationLayoutDelegate extends SingleChildLayoutDelegate {
  const _NotificationLayoutDelegate({required this.anchorRect});

  final Rect? anchorRect;

  static const double _margin = 16;
  static const double _spacing = 12;
  static const double _fallbackMaxWidth = 360;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final Size biggest = constraints.biggest;
    final double overlayWidth = biggest.width;

    if (!overlayWidth.isFinite) {
      return const BoxConstraints(maxWidth: _fallbackMaxWidth);
    }

    final double left = anchorRect != null
        ? anchorRect!.right + _spacing
        : _margin;
    final double availableWidth = math.max(0, overlayWidth - left - _margin);

    double maxWidth = availableWidth;
    if (maxWidth == 0) {
      maxWidth = math.max(0, overlayWidth - (_margin * 2));
    }
    if (maxWidth == 0) {
      maxWidth = _fallbackMaxWidth;
    }

    maxWidth = math.min(maxWidth, overlayWidth);

    return BoxConstraints(maxWidth: maxWidth);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double left = _margin;
    double top = size.height - childSize.height - _margin;
    if (anchorRect != null) {
      left = anchorRect!.right + _spacing;
      top = anchorRect!.center.dy - childSize.height / 2;
    }
    final double maxLeft = size.width - childSize.width - _margin;
    final double maxTop = size.height - childSize.height - _margin;
    final double safeLeftUpper = maxLeft.isFinite
        ? math.max(_margin, maxLeft)
        : double.infinity;
    final double safeTopUpper = maxTop.isFinite
        ? math.max(_margin, maxTop)
        : double.infinity;
    left = left.clamp(_margin, safeLeftUpper);
    top = top.clamp(_margin, safeTopUpper);
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _NotificationLayoutDelegate oldDelegate) {
    return oldDelegate.anchorRect != anchorRect;
  }
}
