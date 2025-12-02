import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart'
    show Colors, Divider, FluentTheme, Scrollbar;
import 'package:flutter/widgets.dart';

import '../widgets/measured_size.dart';
import '../widgets/workspace_split_handle.dart';
import 'painting_toolbar_layout.dart';

const double _sai2ColorMinHeight = 160;
const double _sai2ToolSectionsMinHeight = 320;
const double _sai2ToolbarMinHeight = 140;
const double _sai2ToolSettingsMinHeight = 180;
const double _sai2LayerPanelMinWidth = 150;

class Sai2ToolbarLayoutDelegate extends PaintingToolbarLayoutDelegate {
  const Sai2ToolbarLayoutDelegate();

  @override
  PaintingToolbarLayoutResult build(
    BuildContext context,
    PaintingToolbarElements elements,
    PaintingToolbarMetrics metrics,
  ) {
    final double padding = metrics.toolButtonPadding;
    final double columnWidth = metrics.sidePanelWidth;
    final double gutter = metrics.toolSettingsSpacing;
    final double columnHeight = (metrics.workspaceSize.height - 2 * padding)
        .clamp(0.0, double.infinity);
    final WorkspaceLayoutSplits? splits = metrics.workspaceSplits;
    final double toolsWidth = math.max(0.0, columnWidth);
    final double layerAvailableWidth = math.max(0.0, columnWidth);
    final double minLayerWidth = layerAvailableWidth <= 0
        ? 0.0
        : math.min(_sai2LayerPanelMinWidth, layerAvailableWidth);
    final double minRatio = layerAvailableWidth <= 0
        ? 0.0
        : (minLayerWidth / layerAvailableWidth).clamp(0.0, 1.0);
    final double requestedRatio = splits?.sai2LayerPanelWidthRatio ?? 0.5;
    final double normalizedRatio = layerAvailableWidth <= 0
        ? 0.0
        : requestedRatio.clamp(minRatio, 1.0);
    final double layerWidth = layerAvailableWidth * normalizedRatio;

    final theme = FluentTheme.of(context);
    final WorkspaceLayoutSplits? currentSplits = splits;

    Widget buildSectionHeader(String title, {Widget? trailing}) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(title, style: theme.typography.bodyStrong)),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      );
    }

    Widget buildScrollableContent(Widget child) {
      return _Sai2ToolbarScrollArea(child: child);
    }

    Widget buildColorSection() {
      Widget content = elements.colorPanel.child;
      final ValueChanged<double>? onMeasured =
          currentSplits?.onSai2ColorPanelMeasured;
      if (onMeasured != null) {
        content = MeasuredSize(
          onChanged: (size) => onMeasured(size.height),
          child: content,
        );
      }
      final double? overrideHeight = currentSplits?.sai2ColorPanelHeight;
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

    Widget buildColorDivider() {
      final ValueChanged<double?>? onChanged =
          currentSplits?.onSai2ColorPanelHeightChanged;
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
                (currentSplits?.sai2ColorPanelHeight ??
                        currentSplits?.sai2ColorPanelMeasuredHeight)
                    ?.clamp(0.0, double.infinity) ??
                _sai2ColorMinHeight;
            final double maxHeight = math.max(
              _sai2ColorMinHeight,
              columnHeight - _sai2ToolSectionsMinHeight,
            );
            if (maxHeight <= _sai2ColorMinHeight) {
              onChanged(_sai2ColorMinHeight);
              return;
            }
            final double next = (base + delta).clamp(
              _sai2ColorMinHeight,
              maxHeight,
            );
            onChanged(next);
          },
        ),
      );
    }

    Widget buildSplitSection({
      required String title,
      Widget? trailing,
      required Widget child,
      required int flex,
    }) {
      return Expanded(
        flex: flex,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildSectionHeader(title, trailing: trailing),
            const SizedBox(height: 8),
            Expanded(child: child),
          ],
        ),
      );
    }

    Widget buildToolSections() {
      return Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double availableHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 0;
            final double ratio =
                currentSplits?.sai2ToolbarSectionRatio.clamp(0.0, 1.0) ?? 0.5;
            final int toolbarFlex = math.max(1, (ratio * 1000).round());
            final int settingsFlex = math.max(1, 1000 - toolbarFlex);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildSplitSection(
                  title: '工具栏',
                  child: buildScrollableContent(elements.toolbar),
                  flex: toolbarFlex,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: WorkspaceSplitHandle.horizontal(
                    onDragUpdate: (delta) {
                      if (availableHeight <= 0) {
                        return;
                      }
                      final double minFraction =
                          (_sai2ToolbarMinHeight / availableHeight).clamp(
                            0.0,
                            0.9,
                          );
                      final double maxFraction =
                          1 -
                          (_sai2ToolSettingsMinHeight / availableHeight).clamp(
                            0.0,
                            0.9,
                          );
                      if (maxFraction <= minFraction) {
                        return;
                      }
                      final double next = (ratio + delta / availableHeight)
                          .clamp(minFraction, maxFraction);
                      currentSplits?.onSai2ToolbarSectionRatioChanged(next);
                    },
                  ),
                ),
                buildSplitSection(
                  title: '工具选项',
                  child: buildScrollableContent(elements.toolSettings),
                  flex: settingsFlex,
                ),
              ],
            );
          },
        ),
      );
    }

    Widget buildLayerSection() {
      final Widget? trailing = elements.layerPanel.trailing;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(elements.layerPanel.title, style: theme.typography.subtitle),
          if (trailing != null) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: trailing),
          ],
          const SizedBox(height: 14),
          Expanded(child: elements.layerPanel.child),
        ],
      );
    }

    Widget buildToolsSection() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('工具面板', style: theme.typography.subtitle),
          const SizedBox(height: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildColorSection(),
                buildColorDivider(),
                buildToolSections(),
              ],
            ),
          ),
        ],
      );
    }

    Widget buildLayerToolsPanel(double widthA, double widthB) {
      final double totalWidth = math.max(0.0, widthA + widthB + gutter);
      final Color fallbackColor = theme.brightness == Brightness.dark
          ? const Color(0xFF1F1F1F)
          : Colors.white;
      Color backgroundColor = theme.cardColor;
      if (backgroundColor.alpha != 0xFF) {
        backgroundColor = fallbackColor;
      }
      final Color borderColor = theme.brightness == Brightness.dark
          ? Colors.white.withOpacity(0.12)
          : Colors.black.withOpacity(0.08);

      Widget buildVerticalSplitHandle() {
        final Color dividerColor = theme.resources.controlStrokeColorSecondary;
        return Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: dividerColor,
              ),
            ),
            WorkspaceSplitHandle.vertical(
              onDragUpdate: (delta) {
                if (layerAvailableWidth <= 0) {
                  return;
                }
                final double next =
                    (normalizedRatio + delta / layerAvailableWidth).clamp(
                      minRatio,
                      1.0,
                    );
                splits?.onSai2LayerPanelWidthRatioChanged(next);
              },
            ),
          ],
        );
      }

      return SizedBox(
        width: totalWidth,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: widthA,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: buildLayerSection(),
                  ),
                ),
                SizedBox(width: gutter, child: buildVerticalSplitHandle()),
                SizedBox(
                  width: widthB,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 16),
                    child: buildToolsSection(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final Widget layout = Positioned(
      left: padding,
      top: padding,
      bottom: padding,
      child: SizedBox(
        height: columnHeight,
        child: buildLayerToolsPanel(layerWidth, toolsWidth),
      ),
    );

    final double indicatorSize = metrics.colorIndicatorSize;
    final double indicatorLeft =
        (metrics.workspaceSize.width - padding - indicatorSize).clamp(
          0.0,
          double.infinity,
        );
    final double indicatorTop =
        (metrics.workspaceSize.height - padding - indicatorSize).clamp(
          0.0,
          double.infinity,
        );
    final Widget? exitButton = elements.exitButton;
    final bool hasExitButton = exitButton != null;
    final double exitTop = hasExitButton
        ? math.max(padding, indicatorTop - gutter - indicatorSize)
        : 0.0;

    final Widget dockedControls = Positioned(
      right: padding,
      bottom: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (hasExitButton) ...[exitButton, SizedBox(height: gutter)],
          elements.colorIndicator,
        ],
      ),
    );

    final double rightColumnLeft = padding + layerWidth + gutter;

    final List<Rect> hitRegions = <Rect>[
      Rect.fromLTWH(padding, padding, math.max(0, layerWidth), columnHeight),
      Rect.fromLTWH(
        rightColumnLeft,
        padding,
        math.max(0, toolsWidth),
        columnHeight,
      ),
      Rect.fromLTWH(indicatorLeft, indicatorTop, indicatorSize, indicatorSize),
    ];
    if (hasExitButton) {
      hitRegions.add(
        Rect.fromLTWH(indicatorLeft, exitTop, indicatorSize, indicatorSize),
      );
    }

    return PaintingToolbarLayoutResult(
      widgets: <Widget>[layout, dockedControls],
      hitRegions: hitRegions,
    );
  }
}

class _Sai2ToolbarScrollArea extends StatefulWidget {
  const _Sai2ToolbarScrollArea({required this.child});

  final Widget child;

  @override
  State<_Sai2ToolbarScrollArea> createState() => _Sai2ToolbarScrollAreaState();
}

class _Sai2ToolbarScrollAreaState extends State<_Sai2ToolbarScrollArea> {
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
