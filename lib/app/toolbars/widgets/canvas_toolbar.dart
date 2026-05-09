import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import '../../../canvas/canvas_tools.dart';
import '../../shortcuts/toolbar_shortcuts.dart';
import '../../tooltips/hover_detail_tooltip.dart';
import '../../utils/platform_target.dart';
import 'bucket_tool_button.dart';
import 'magic_wand_tool_button.dart';
import 'pen_tool_button.dart';
import 'eraser_tool_button.dart';
import 'perspective_pen_tool_button.dart';
import 'selection_tool_button.dart';
import 'selection_pen_tool_button.dart';
import 'redo_tool_button.dart';
import 'undo_tool_button.dart';
import 'layer_adjust_tool_button.dart';
import 'curve_pen_tool_button.dart';
import 'eyedropper_tool_button.dart';
import 'liquify_tool_button.dart';
import 'shape_tool_button.dart';
import 'spray_tool_button.dart';
import 'text_tool_button.dart';
import 'hand_tool_button.dart';
import 'rotate_tool_button.dart';

class CanvasToolbar extends StatelessWidget {
  const CanvasToolbar({
    super.key,
    required this.activeTool,
    required this.selectionShape,
    required this.shapeToolVariant,
    required this.onToolSelected,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.canRedo,
    required this.layout,
    this.includeHistoryButtons = true,
  });

  final CanvasTool activeTool;
  final SelectionShape selectionShape;
  final ShapeToolVariant shapeToolVariant;
  final ValueChanged<CanvasTool> onToolSelected;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndo;
  final bool canRedo;
  final CanvasToolbarLayout layout;
  final bool includeHistoryButtons;

  static const int buttonCount = 16;
  static const int historyButtonCount = 2;
  static const double buttonSize = 48;
  static const double spacing = 9;

  static CanvasToolbarLayout layoutForAvailableHeight(
    double availableHeight, {
    int toolCount = buttonCount,
  }) {
    final int clampedToolCount = math.max(1, toolCount);
    final double effectiveHeight = availableHeight.isFinite
        ? math.max(0, availableHeight)
        : double.infinity;

    final double singleColumnHeight =
        buttonSize * clampedToolCount + spacing * (clampedToolCount - 1);
    if (!effectiveHeight.isFinite) {
      return CanvasToolbarLayout(
        columns: 1,
        rows: clampedToolCount,
        width: buttonSize,
        height: singleColumnHeight,
        buttonExtent: buttonSize,
      );
    }

    final double rowExtent = buttonSize + spacing;
    final int maxRows = math.max(
      1,
      ((effectiveHeight + spacing) / rowExtent).floor(),
    );
    if (maxRows >= clampedToolCount) {
      final double height = math.max(
        buttonSize,
        math.min(singleColumnHeight, effectiveHeight),
      );
      return CanvasToolbarLayout(
        columns: 1,
        rows: clampedToolCount,
        width: buttonSize,
        height: height,
        buttonExtent: buttonSize,
      );
    }

    final int columns = (clampedToolCount / maxRows).ceil();
    final double width = buttonSize * columns + spacing * (columns - 1);
    final double height = maxRows * buttonSize + spacing * (maxRows - 1);
    return CanvasToolbarLayout(
      columns: columns,
      rows: maxRows,
      width: width,
      height: height,
      buttonExtent: buttonSize,
    );
  }

  static const TooltipThemeData _rightTooltipStyle = TooltipThemeData(
    preferBelow: false,
    verticalOffset: 24,
    waitDuration: Duration.zero,
  );

  static const Map<ToolbarAction, String> _tooltipDetails = {
    ToolbarAction.layerAdjustTool: '调整图层顺序、透明度以及混合模式，快速整理画面结构',
    ToolbarAction.penTool: '使用当前画笔绘制连续笔触，兼容压力与速度控制',
    ToolbarAction.perspectivePenTool: '沿透视线绘制直线，先预览再落笔，确保对齐消失点',
    ToolbarAction.sprayTool: '喷洒颗粒色点，适合铺色或叠加随机纹理',
    ToolbarAction.liquifyTool: '推拉并融合彩色像素，适合调整局部形变和颜色过渡',
    ToolbarAction.curvePenTool: '通过锚点绘制可编辑的曲线路径',
    ToolbarAction.eraserTool: '擦除当前图层内容，可调节笔刷大小和硬度',
    ToolbarAction.bucketTool: '在闭合区域内填充颜色，并沿用前景色配置',
    ToolbarAction.magicWandTool: '根据颜色相似度自动生成选区',
    ToolbarAction.eyedropperTool: '拾取画布上的颜色并设置为当前前景色',
    ToolbarAction.selectionTool: '创建矩形或椭圆选区以移动、复制或裁剪内容',
    ToolbarAction.selectionPenTool: '像画笔一样涂抹创建选区，可与现有选区叠加',
    ToolbarAction.textTool: '在画布上插入文本并调整字体样式',
    ToolbarAction.handTool: '拖拽画布以平移视图，便于查看不同区域',
    ToolbarAction.undo: '撤销最近的操作，逐步回退修改',
    ToolbarAction.redo: '重做刚刚撤销的操作，恢复修改',
  };

  static String? _tooltipDetail(
    ToolbarAction action,
    ShapeToolVariant shapeVariant,
  ) {
    if (action == ToolbarAction.shapeTool) {
      final String shapeName = _shapeTooltipLabel(
        shapeVariant,
      ).replaceAll('工具', '');
      return '绘制$shapeName，并可直接调整描边与填充';
    }
    return _tooltipDetails[action];
  }

  static String _tooltipMessage(String base, ToolbarAction action) {
    final shortcutLabel = ToolbarShortcuts.labelForPlatform(
      action,
      resolvedTargetPlatform(),
    );
    if (shortcutLabel.isEmpty) {
      return base;
    }
    return '$base ($shortcutLabel)';
  }

  static String _shapeTooltipLabel(ShapeToolVariant variant) {
    switch (variant) {
      case ShapeToolVariant.rectangle:
        return '矩形工具';
      case ShapeToolVariant.ellipse:
        return '椭圆工具';
      case ShapeToolVariant.triangle:
        return '三角形工具';
      case ShapeToolVariant.line:
        return '直线工具';
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget wrapWithTooltip({
      required ToolbarAction action,
      required String label,
      required Widget child,
    }) {
      return HoverDetailTooltip(
        message: _tooltipMessage(label, action),
        detail: _tooltipDetail(action, shapeToolVariant),
        displayHorizontally: true,
        style: _rightTooltipStyle,
        useMousePosition: false,
        child: child,
      );
    }

    final List<Widget> items = <Widget>[];
    items.addAll([
      wrapWithTooltip(
        action: ToolbarAction.layerAdjustTool,
        label: '图层调节',
        child: LayerAdjustToolButton(
          isSelected: activeTool == CanvasTool.layerAdjust,
          onPressed: () => onToolSelected(CanvasTool.layerAdjust),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.selectionTool,
        label: '选区工具',
        child: SelectionToolButton(
          isSelected: activeTool == CanvasTool.selection,
          selectionShape: selectionShape,
          onPressed: () => onToolSelected(CanvasTool.selection),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.selectionPenTool,
        label: '选区笔',
        child: SelectionPenToolButton(
          isSelected: activeTool == CanvasTool.selectionPen,
          onPressed: () => onToolSelected(CanvasTool.selectionPen),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.magicWandTool,
        label: '魔棒工具',
        child: MagicWandToolButton(
          isSelected: activeTool == CanvasTool.magicWand,
          onPressed: () => onToolSelected(CanvasTool.magicWand),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.eyedropperTool,
        label: '吸管工具',
        child: EyedropperToolButton(
          isSelected: activeTool == CanvasTool.eyedropper,
          onPressed: () => onToolSelected(CanvasTool.eyedropper),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.penTool,
        label: '画笔工具',
        child: PenToolButton(
          isSelected: activeTool == CanvasTool.pen,
          onPressed: () => onToolSelected(CanvasTool.pen),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.sprayTool,
        label: '喷枪工具',
        child: SprayToolButton(
          isSelected: activeTool == CanvasTool.spray,
          onPressed: () => onToolSelected(CanvasTool.spray),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.liquifyTool,
        label: '液化笔刷',
        child: LiquifyToolButton(
          isSelected: activeTool == CanvasTool.liquify,
          onPressed: () => onToolSelected(CanvasTool.liquify),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.perspectivePenTool,
        label: '透视画笔',
        child: PerspectivePenToolButton(
          isSelected: activeTool == CanvasTool.perspectivePen,
          onPressed: () => onToolSelected(CanvasTool.perspectivePen),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.curvePenTool,
        label: '曲线画笔',
        child: CurvePenToolButton(
          isSelected: activeTool == CanvasTool.curvePen,
          onPressed: () => onToolSelected(CanvasTool.curvePen),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.eraserTool,
        label: '橡皮擦',
        child: EraserToolButton(
          isSelected: activeTool == CanvasTool.eraser,
          onPressed: () => onToolSelected(CanvasTool.eraser),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.bucketTool,
        label: '油漆桶',
        child: BucketToolButton(
          isSelected: activeTool == CanvasTool.bucket,
          onPressed: () => onToolSelected(CanvasTool.bucket),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.textTool,
        label: '文字工具',
        child: TextToolButton(
          isSelected: activeTool == CanvasTool.text,
          onPressed: () => onToolSelected(CanvasTool.text),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.shapeTool,
        label: _shapeTooltipLabel(shapeToolVariant),
        child: ShapeToolButton(
          isSelected: activeTool == CanvasTool.shape,
          variant: shapeToolVariant,
          onPressed: () => onToolSelected(CanvasTool.shape),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.handTool,
        label: '拖拽画布',
        child: HandToolButton(
          isSelected: activeTool == CanvasTool.hand,
          onPressed: () => onToolSelected(CanvasTool.hand),
        ),
      ),
      wrapWithTooltip(
        action: ToolbarAction.rotateTool,
        label: '旋转画布',
        child: RotateToolButton(
          isSelected: activeTool == CanvasTool.rotate,
          onPressed: () => onToolSelected(CanvasTool.rotate),
        ),
      ),
    ]);

    if (includeHistoryButtons) {
      items.addAll([
        wrapWithTooltip(
          action: ToolbarAction.undo,
          label: '撤销',
          child: UndoToolButton(enabled: canUndo, onPressed: onUndo),
        ),
        wrapWithTooltip(
          action: ToolbarAction.redo,
          label: '恢复',
          child: RedoToolButton(enabled: canRedo, onPressed: onRedo),
        ),
      ]);
    }

    final double buttonExtent = layout.buttonExtent;

    List<Widget> sizedItems(List<Widget> children) {
      return [
        for (final Widget child in children)
          SizedBox(width: buttonExtent, height: buttonExtent, child: child),
      ];
    }

    List<Widget> withVerticalSpacing(List<Widget> children) {
      if (children.isEmpty) {
        return const [];
      }
      return [
        for (int index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: spacing),
          children[index],
        ],
      ];
    }

    if (layout.columns <= 1) {
      final Widget content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: withVerticalSpacing(sizedItems(items)),
      );
      final int itemCount = items.length;
      final double contentHeight = itemCount <= 0
          ? 0
          : buttonExtent * itemCount + spacing * (itemCount - 1);
      if (contentHeight <= layout.height + 0.5) {
        return content;
      }
      return SizedBox(
        width: layout.width,
        height: layout.height,
        child: _CanvasToolbarScrollArea(child: content),
      );
    }

    final columnWidgets = <Widget>[];
    int startIndex = 0;
    for (
      int column = 0;
      column < layout.columns && startIndex < items.length;
      column++
    ) {
      final int remaining = items.length - startIndex;
      final int targetCount = column == layout.columns - 1
          ? remaining
          : math.min(layout.rows, remaining);
      final columnChildren = sizedItems(
        items.sublist(startIndex, startIndex + targetCount),
      );
      startIndex += targetCount;
      columnWidgets.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: withVerticalSpacing(columnChildren),
        ),
      );
    }

    final Widget multiColumnLayout = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int index = 0; index < columnWidgets.length; index++) ...[
          if (index > 0) const SizedBox(width: spacing),
          columnWidgets[index],
        ],
      ],
    );

    if (!layout.horizontalFlow) {
      return multiColumnLayout;
    }

    final wrappedItems = sizedItems(items);
    return SizedBox(
      width: layout.width,
      height: layout.height,
      child: Align(
        alignment: Alignment.topLeft,
        child: Wrap(
          direction: layout.flowDirection,
          spacing: spacing,
          runSpacing: spacing,
          children: wrappedItems,
        ),
      ),
    );
  }
}

class CanvasToolbarLayout {
  const CanvasToolbarLayout({
    required this.columns,
    required this.rows,
    required this.width,
    required this.height,
    this.buttonExtent = CanvasToolbar.buttonSize,
    this.horizontalFlow = false,
    this.flowDirection = Axis.horizontal,
  });

  final int columns;
  final int rows;
  final double width;
  final double height;
  final double buttonExtent;
  final bool horizontalFlow;
  final Axis flowDirection;

  bool get isMultiColumn => columns > 1;
}

class _CanvasToolbarScrollArea extends StatefulWidget {
  const _CanvasToolbarScrollArea({required this.child});

  final Widget child;

  @override
  State<_CanvasToolbarScrollArea> createState() =>
      _CanvasToolbarScrollAreaState();
}

class _CanvasToolbarScrollAreaState extends State<_CanvasToolbarScrollArea> {
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
    final ScrollBehavior behavior = ScrollConfiguration.of(
      context,
    ).copyWith(scrollbars: false);
    return ScrollConfiguration(
      behavior: behavior,
      child: SingleChildScrollView(
        controller: _controller,
        primary: false,
        child: Align(alignment: Alignment.topLeft, child: widget.child),
      ),
    );
  }
}
