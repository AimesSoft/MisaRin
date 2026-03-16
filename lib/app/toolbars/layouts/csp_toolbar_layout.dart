import 'dart:math' as math;
import 'package:fluent_ui/fluent_ui.dart' show Divider, FluentTheme, Scrollbar;
import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../widgets/measured_size.dart';
import '../widgets/toolbar_panel_card.dart';
import '../widgets/workspace_split_handle.dart';
import 'painting_toolbar_layout.dart';

const double _cspColorMinHeight = 160;
const double _cspToolOptionsMinHeight = 220;
const double _cspToolsStripMinWidth = 58;
const double _cspToolsStripMaxWidth = 76;
const double _cspLeftPanelPreferredWidth = 330;
const double _cspLeftPanelMinWidth = 280;
const double _cspRightPanelPreferredWidth = 230;
const double _cspRightPanelMinWidth = 180;
const double _cspToolSettingsMinWidth = 180;

class CspToolbarLayoutDelegate extends PaintingToolbarLayoutDelegate {
  const CspToolbarLayoutDelegate();

  @override
  PaintingToolbarLayoutResult build(
    BuildContext context,
    PaintingToolbarElements elements,
    PaintingToolbarMetrics metrics,
  ) {
    final double padding = metrics.toolButtonPadding;
    final double gutter = metrics.sidePanelSpacing;
    final double panelHeight = (metrics.workspaceSize.height - 2 * padding)
        .clamp(0.0, double.infinity);
    final double availableWidth = (metrics.workspaceSize.width - 2 * padding)
        .clamp(0.0, double.infinity);
    final WorkspaceLayoutSplits? splits = metrics.workspaceSplits;

    double leftPanelWidth = _cspLeftPanelPreferredWidth;
    double rightPanelWidth = _cspRightPanelPreferredWidth;
    double gap = gutter;
    final double preferredTotal = leftPanelWidth + rightPanelWidth + gap;
    if (availableWidth < preferredTotal) {
      // Shrink right panel first to keep tool-settings area readable.
      final double overflow = preferredTotal - availableWidth;
      final double rightShrinkCapacity =
          rightPanelWidth - _cspRightPanelMinWidth;
      final double rightShrink = overflow.clamp(0.0, rightShrinkCapacity);
      rightPanelWidth -= rightShrink;
      double remainingOverflow = overflow - rightShrink;

      if (remainingOverflow > 0.0) {
        final double leftShrinkCapacity =
            leftPanelWidth - _cspLeftPanelMinWidth;
        final double leftShrink = remainingOverflow.clamp(
          0.0,
          leftShrinkCapacity,
        );
        leftPanelWidth -= leftShrink;
        remainingOverflow -= leftShrink;
      }

      if (remainingOverflow > 0.0) {
        gap = math.max(0.0, gap - remainingOverflow);
      }
    }

    final double toolsStripWidth = (() {
      final double preferred = (leftPanelWidth * 0.28).clamp(
        _cspToolsStripMinWidth,
        _cspToolsStripMaxWidth,
      );
      final double maxAllowed = math.max(44.0, leftPanelWidth - 140.0);
      return preferred.clamp(44.0, maxAllowed);
    })();

    final double estimatedToolSettingsWidth = (() {
      // ToolbarPanelCard has horizontal padding 16 * 2.
      final double cardInnerWidth = math.max(0.0, leftPanelWidth - 32.0);
      // Inner row has strip + (10 + 1 + 10) divider spacing.
      return math.max(0.0, cardInnerWidth - toolsStripWidth - 21.0);
    })();

    Widget buildSectionHeader(String title, {Widget? trailing}) {
      final theme = FluentTheme.of(context);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(title, style: theme.typography.bodyStrong)),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      );
    }

    Widget buildScrollableContent(Widget child) {
      return _CspToolbarScrollArea(child: child);
    }

    Widget buildColorSection() {
      Widget content = elements.colorPanel.child;
      final ValueChanged<double>? onMeasured = splits?.onSai2ColorPanelMeasured;
      if (onMeasured != null) {
        content = MeasuredSize(
          onChanged: (size) => onMeasured(size.height),
          child: content,
        );
      }
      final double? overrideHeight = splits?.sai2ColorPanelHeight;
      if (overrideHeight != null) {
        content = SizedBox(height: overrideHeight, child: content);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildSectionHeader(
            elements.colorPanel.title,
            trailing: elements.colorPanel.trailing,
          ),
          const SizedBox(height: 8),
          content,
        ],
      );
    }

    Widget buildColorDivider(double availableHeight) {
      final ValueChanged<double?>? onChanged =
          splits?.onSai2ColorPanelHeightChanged;
      if (onChanged == null) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: WorkspaceSplitHandle.horizontal(
          onDragUpdate: (delta) {
            final double base =
                (splits?.sai2ColorPanelHeight ??
                        splits?.sai2ColorPanelMeasuredHeight)
                    ?.clamp(0.0, double.infinity) ??
                _cspColorMinHeight;
            final double maxHeight = math.max(
              _cspColorMinHeight,
              availableHeight - _cspToolOptionsMinHeight,
            );
            if (maxHeight <= _cspColorMinHeight) {
              onChanged(_cspColorMinHeight);
              return;
            }
            // In CSP, color panel sits below the splitter (its top edge is dragged).
            // So dragging up (negative delta) should increase color height.
            final double next = (base - delta).clamp(
              _cspColorMinHeight,
              maxHeight,
            );
            onChanged(next);
          },
        ),
      );
    }

    Widget buildLeftPanel() {
      final theme = FluentTheme.of(context);
      final Color dividerColor = theme.resources.controlStrokeColorSecondary;
      return ToolbarPanelCard(
        width: leftPanelWidth,
        title: context.l10n.toolPanel,
        expand: true,
        showHeader: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: toolsStripWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: buildScrollableContent(
                      Align(
                        alignment: Alignment.topCenter,
                        child: elements.toolbar,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: elements.colorIndicator,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            DecoratedBox(
              decoration: BoxDecoration(color: dividerColor),
              child: const SizedBox(width: 1),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double availableHeight = constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : 0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buildSectionHeader(context.l10n.toolPanel),
                            const SizedBox(height: 8),
                            Expanded(
                              child: buildScrollableContent(
                                estimatedToolSettingsWidth <
                                        _cspToolSettingsMinWidth
                                    ? SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: SizedBox(
                                          width: _cspToolSettingsMinWidth,
                                          child: elements.toolSettings,
                                        ),
                                      )
                                    : elements.toolSettings,
                              ),
                            ),
                          ],
                        ),
                      ),
                      buildColorDivider(availableHeight),
                      buildColorSection(),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    Widget buildRightPanel() {
      return ToolbarPanelCard(
        width: rightPanelWidth,
        title: elements.layerPanel.title,
        trailing: elements.layerPanel.trailing,
        expand: true,
        child: elements.layerPanel.child,
      );
    }

    final double rightPanelLeft =
        (metrics.workspaceSize.width - padding - rightPanelWidth).clamp(
          0.0,
          double.infinity,
        );

    final Widget leftPanel = Positioned(
      left: padding,
      top: padding,
      bottom: padding,
      child: SizedBox(height: panelHeight, child: buildLeftPanel()),
    );
    final Widget rightPanel = Positioned(
      left: rightPanelLeft,
      top: padding,
      bottom: padding,
      child: SizedBox(height: panelHeight, child: buildRightPanel()),
    );

    final List<Rect> hitRegions = <Rect>[
      Rect.fromLTWH(padding, padding, math.max(0, leftPanelWidth), panelHeight),
      Rect.fromLTWH(
        rightPanelLeft,
        padding,
        math.max(0, rightPanelWidth),
        panelHeight,
      ),
    ];

    return PaintingToolbarLayoutResult(
      widgets: <Widget>[leftPanel, rightPanel],
      hitRegions: hitRegions,
    );
  }
}

class _CspToolbarScrollArea extends StatefulWidget {
  const _CspToolbarScrollArea({required this.child});

  final Widget child;

  @override
  State<_CspToolbarScrollArea> createState() => _CspToolbarScrollAreaState();
}

class _CspToolbarScrollAreaState extends State<_CspToolbarScrollArea> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        child: Align(alignment: Alignment.topLeft, child: widget.child),
      ),
    );
  }
}
