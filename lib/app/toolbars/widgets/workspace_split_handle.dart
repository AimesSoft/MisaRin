import 'package:fluent_ui/fluent_ui.dart';

class WorkspaceSplitHandle extends StatelessWidget {
  const WorkspaceSplitHandle.horizontal({
    super.key,
    required this.onDragUpdate,
    this.hitExtent = 12,
    this.thickness = 1,
  }) : axis = Axis.horizontal;

  const WorkspaceSplitHandle.vertical({
    super.key,
    required this.onDragUpdate,
    this.hitExtent = 12,
    this.thickness = 1,
  }) : axis = Axis.vertical;

  final Axis axis;
  final ValueChanged<double> onDragUpdate;
  final double hitExtent;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final bool horizontal = axis == Axis.horizontal;
    final MouseCursor cursor = horizontal
        ? SystemMouseCursors.resizeRow
        : SystemMouseCursors.resizeColumn;
    final double width = horizontal ? double.infinity : hitExtent;
    final double height = horizontal ? hitExtent : double.infinity;
    final Color strokeColor = FluentTheme.of(
      context,
    ).resources.controlStrokeColorDefault;

    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: horizontal
            ? (details) => onDragUpdate(details.delta.dy)
            : null,
        onHorizontalDragUpdate: horizontal
            ? null
            : (details) => onDragUpdate(details.delta.dx),
        child: SizedBox(
          width: width,
          height: height,
          child: Align(
            alignment: Alignment.center,
            child: Container(
              width: horizontal ? double.infinity : thickness,
              height: horizontal ? thickness : double.infinity,
              decoration: BoxDecoration(
                color: strokeColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
