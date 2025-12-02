import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart' show Divider, FluentTheme;
import 'package:flutter/widgets.dart';

import '../widgets/toolbar_panel_card.dart';
import '../widgets/measured_size.dart';
import '../widgets/workspace_split_handle.dart';
import 'painting_toolbar_layout.dart';

const double _floatingColorMinHeight = 160;
const double _floatingLayerMinHeight = 200;

class FloatingToolbarLayoutDelegate extends PaintingToolbarLayoutDelegate {
  const FloatingToolbarLayoutDelegate();

  @override
  PaintingToolbarLayoutResult build(
    BuildContext context,
    PaintingToolbarElements elements,
    PaintingToolbarMetrics metrics,
  ) {
    final double toolbarPadding = metrics.toolButtonPadding;
    final theme = FluentTheme.of(context);
    final Widget toolbar = Positioned(
      left: toolbarPadding,
      top: toolbarPadding,
      child: elements.toolbar,
    );

    Widget toolSettings = elements.toolSettings;
    final double? maxWidth = metrics.toolSettingsMaxWidth;
    if (maxWidth != null) {
      toolSettings = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: toolSettings,
      );
    }
    toolSettings = Positioned(
      left: metrics.toolSettingsLeft,
      top: toolbarPadding,
      child: toolSettings,
    );

    final Widget colorIndicator = Positioned(
      left: toolbarPadding,
      bottom: toolbarPadding,
      child: elements.colorIndicator,
    );
    Widget buildCombinedPanel() {
      final WorkspaceLayoutSplits? splits = metrics.workspaceSplits;
      Widget buildSectionHeader(String title, {Widget? trailing}) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(title, style: theme.typography.bodyStrong)),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        );
      }

      Widget buildColorSection() {
        Widget content = elements.colorPanel.child;
        final ValueChanged<double>? onMeasured =
            splits?.onFloatingColorPanelMeasured;
        if (onMeasured != null) {
          content = MeasuredSize(
            onChanged: (size) => onMeasured(size.height),
            child: content,
          );
        }
        final double? overrideHeight = splits?.floatingColorPanelHeight;
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

      Widget buildLayerSection() {
        final Widget content = elements.layerPanel.child;
        if (elements.layerPanel.expand) {
          return Expanded(child: content);
        }
        return content;
      }

      Widget buildResizableDivider(double availableHeight) {
        final ValueChanged<double?>? onChanged =
            splits?.onFloatingColorPanelHeightChanged;
        if (onChanged == null || !availableHeight.isFinite) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: WorkspaceSplitHandle.horizontal(
            onDragUpdate: (delta) {
              final double? measured = splits?.floatingColorPanelMeasuredHeight;
              final double base =
                  (splits?.floatingColorPanelHeight ?? measured)?.clamp(
                    0.0,
                    double.infinity,
                  ) ??
                  _floatingColorMinHeight;
              final double maxHeight = math.max(
                _floatingColorMinHeight,
                availableHeight - _floatingLayerMinHeight,
              );
              if (maxHeight <= _floatingColorMinHeight) {
                onChanged(_floatingColorMinHeight);
                return;
              }
              final double next = (base + delta).clamp(
                _floatingColorMinHeight,
                maxHeight,
              );
              onChanged(next);
            },
          ),
        );
      }

      return ToolbarPanelCard(
        width: metrics.sidePanelWidth,
        title: elements.layerPanel.title,
        trailing: elements.layerPanel.trailing,
        expand: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double availableHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildColorSection(),
                buildResizableDivider(availableHeight),
                buildLayerSection(),
              ],
            );
          },
        ),
      );
    }

    final Widget rightPanel = Positioned(
      right: toolbarPadding,
      top: toolbarPadding,
      bottom: toolbarPadding,
      child: SizedBox(
        width: metrics.sidePanelWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Expanded(child: buildCombinedPanel())],
        ),
      ),
    );

    final List<Rect> hitRegions = <Rect>[
      Rect.fromLTWH(
        toolbarPadding,
        toolbarPadding,
        metrics.toolbarLayout.width,
        metrics.toolbarLayout.height,
      ),
      Rect.fromLTWH(
        metrics.toolSettingsLeft,
        toolbarPadding,
        metrics.toolSettingsSize.width,
        metrics.toolSettingsSize.height,
      ),
      Rect.fromLTWH(
        toolbarPadding,
        (metrics.workspaceSize.height -
                toolbarPadding -
                metrics.colorIndicatorSize)
            .clamp(0.0, double.infinity),
        metrics.colorIndicatorSize,
        metrics.colorIndicatorSize,
      ),
      Rect.fromLTWH(
        metrics.sidebarLeft,
        toolbarPadding,
        metrics.sidePanelWidth,
        (metrics.workspaceSize.height - 2 * toolbarPadding).clamp(
          0.0,
          double.infinity,
        ),
      ),
    ];

    return PaintingToolbarLayoutResult(
      widgets: <Widget>[toolbar, toolSettings, colorIndicator, rightPanel],
      hitRegions: hitRegions,
    );
  }
}
