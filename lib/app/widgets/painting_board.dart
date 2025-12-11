import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/animation.dart' show AnimationController;
import 'package:flutter/foundation.dart'
    show
        ValueChanged,
        ValueListenable,
        ValueNotifier,
        compute,
        debugPrint,
        defaultTargetPlatform,
        TargetPlatform,
        kIsWeb,
        protected;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    as material
    show ReorderableDragStartListener, ReorderableListView;
import 'package:flutter/painting.dart' show MatrixUtils;
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        FilteringTextInputFormatter,
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyEventResult,
        KeyRepeatEvent,
        KeyUpEvent,
        LogicalKeyboardKey,
        LogicalKeySet,
        TextInputFormatter,
        TextInputType,
        TextEditingValue,
        TextSelection;
import 'package:flutter/rendering.dart'
    show
        RenderBox,
        RenderProxyBox,
        RenderProxyBoxWithHitTestBehavior,
        TextPainter;
import 'package:flutter/scheduler.dart'
    show
        SchedulerBinding,
        SchedulerPhase,
        Ticker,
        TickerProvider,
        TickerProviderStateMixin;
import 'package:flutter/widgets.dart'
    show
        CustomPaint,
        EditableText,
        FocusNode,
        SingleChildRenderObjectWidget,
        StrutStyle,
        TextEditingController,
        TextHeightBehavior,
        WidgetsBinding;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalMaterialLocalizations;
import 'package:vector_math/vector_math_64.dart' show Matrix4;
import 'package:file_picker/file_picker.dart';

import '../../bitmap_canvas/bitmap_canvas.dart';
import '../../bitmap_canvas/raster_frame.dart';
import '../../bitmap_canvas/controller.dart';
import '../../bitmap_canvas/stroke_dynamics.dart' show StrokePressureProfile;
import '../../canvas/blend_mode_utils.dart';
import '../../canvas/canvas_layer.dart';
import '../../canvas/canvas_settings.dart';
import '../../canvas/canvas_exporter.dart';
import '../../canvas/canvas_tools.dart';
import '../../canvas/canvas_viewport.dart';
import '../../canvas/vector_stroke_painter.dart';
import '../../canvas/text_renderer.dart';
import '../../canvas/perspective_guide.dart';
import '../toolbars/widgets/canvas_toolbar.dart';
import '../toolbars/widgets/tool_settings_card.dart';
import '../toolbars/layouts/layouts.dart';
import '../toolbars/widgets/measured_size.dart';
import '../../painting/krita_spray_engine.dart';
import 'canvas_board_client.dart';
import 'tool_cursor_overlay.dart';
import 'bitmap_canvas_surface.dart';
import '../shortcuts/toolbar_shortcuts.dart';
import '../menu/menu_action_dispatcher.dart';
import '../constants/color_line_presets.dart';
import '../constants/antialias_levels.dart';
import '../preferences/app_preferences.dart';
import '../constants/pen_constants.dart';
import '../models/canvas_resize_anchor.dart';
import '../models/canvas_view_info.dart';
import '../models/image_resize_sampling.dart';
import '../utils/tablet_input_bridge.dart';
import '../utils/color_filter_generator.dart';
import '../palette/palette_exporter.dart';
import '../utils/web_file_dialog.dart';
import '../utils/web_file_saver.dart';
import '../utils/platform_target.dart';
import '../utils/clipboard_image_reader.dart';
import 'layer_visibility_button.dart';
import 'app_notification.dart';
import '../native/system_fonts.dart';
import '../tooltips/hover_detail_tooltip.dart';
import '../../backend/layout_compute_worker.dart';
import '../../backend/canvas_painting_worker.dart';
import '../../backend/canvas_raster_backend.dart';
import '../../performance/stroke_latency_monitor.dart';
import '../workspace/workspace_shared_state.dart';

part 'painting_board_layers.dart';
part 'painting_board_layers_panel.dart';
part 'painting_board_layer_widgets.dart';
part 'painting_board_colors.dart';
part 'painting_board_palette.dart';
part 'painting_board_marching_ants.dart';
part 'painting_board_selection.dart';
part 'painting_board_layer_transform.dart';
part 'painting_board_shapes.dart';
part 'painting_board_perspective.dart';
part 'painting_board_text.dart';
part 'painting_board_clipboard.dart';
part 'painting_board_interactions.dart';
part 'painting_board_build.dart';
part 'painting_board_widgets.dart';
part 'painting_board_workspace_panel.dart';
part 'painting_board_filters.dart';
part 'painting_board_reference.dart';

class _SyntheticStrokeSample {
  const _SyntheticStrokeSample({
    required this.point,
    required this.distance,
    required this.progress,
  });

  final Offset point;
  final double distance;
  final double progress;
}

enum _SyntheticStrokeTimelineStyle { natural, fastCurve }

const double _toolButtonPadding = 16;
const double _toolbarButtonSize = CanvasToolbar.buttonSize;
const double _toolbarSpacing = CanvasToolbar.spacing;
const double _toolSettingsSpacing = 12;
const double _zoomStep = 1.1;
const double _defaultPenStrokeWidth = 3;
const double _defaultSprayStrokeWidth = kDefaultSprayStrokeWidth;
const double _sidePanelWidth = 240;
const double _sidePanelSpacing = 12;
const double _colorIndicatorSize = 56;
const double _colorIndicatorBorder = 3;
const int _recentColorCapacity = 5;
const double _initialViewportScaleFactor = 0.8;
const double _curveStrokeSampleSpacing = 3.4;
const double _syntheticStrokeMinDeltaMs =
    3.6; // keep >= StrokeDynamics._minDeltaMs
const int _strokeStabilizerMaxLevel = 30;

enum CanvasRotation {
  clockwise90,
  counterClockwise90,
  clockwise180,
  counterClockwise180,
}

class CanvasRotationResult {
  const CanvasRotationResult({
    required this.layers,
    required this.width,
    required this.height,
  });

  final List<CanvasLayerData> layers;
  final int width;
  final int height;
}

class CanvasResizeResult {
  const CanvasResizeResult({
    required this.layers,
    required this.width,
    required this.height,
  });

  final List<CanvasLayerData> layers;
  final int width;
  final int height;
}

class _ImportedImageData {
  const _ImportedImageData({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;
  final Uint8List bytes;
}

class PaintingBoard extends StatefulWidget {
  const PaintingBoard({
    super.key,
    required this.settings,
    required this.onRequestExit,
    this.onDirtyChanged,
    this.initialLayers,
    this.initialPerspectiveGuide,
    this.onUndoFallback,
    this.onRedoFallback,
    this.externalCanUndo = false,
    this.externalCanRedo = false,
    this.onResizeImage,
    this.onResizeCanvas,
    this.onReadyChanged,
    this.toolbarLayoutStyle = PaintingToolbarLayoutStyle.floating,
  });

  final CanvasSettings settings;
  final VoidCallback onRequestExit;
  final ValueChanged<bool>? onDirtyChanged;
  final List<CanvasLayerData>? initialLayers;
  final PerspectiveGuideState? initialPerspectiveGuide;
  final VoidCallback? onUndoFallback;
  final VoidCallback? onRedoFallback;
  final bool externalCanUndo;
  final bool externalCanRedo;
  final Future<void> Function()? onResizeImage;
  final Future<void> Function()? onResizeCanvas;
  final ValueChanged<bool>? onReadyChanged;
  final PaintingToolbarLayoutStyle toolbarLayoutStyle;

  @override
  State<PaintingBoard> createState() => PaintingBoardState();
}

abstract class _PaintingBoardBase extends State<PaintingBoard> {
  late BitmapCanvasController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _boardReadyNotified = false;

  CanvasTool _activeTool = CanvasTool.pen;
  bool _isDrawing = false;
  bool _isDraggingBoard = false;
  bool _isDirty = false;
  bool _isScalingGesture = false;
  bool _pixelGridVisible = false;
  bool _viewBlackWhiteOverlay = false;
  bool _viewMirrorOverlay = false;
  double _scaleGestureInitialScale = 1.0;
  double _penStrokeWidth = _defaultPenStrokeWidth;
  double _sprayStrokeWidth = _defaultSprayStrokeWidth;
  SprayMode _sprayMode = AppPreferences.defaultSprayMode;
  double _strokeStabilizerStrength =
      AppPreferences.defaultStrokeStabilizerStrength;
  bool _simulatePenPressure = false;
  int _penAntialiasLevel = AppPreferences.defaultPenAntialiasLevel;
  int _bucketAntialiasLevel = AppPreferences.defaultBucketAntialiasLevel;
  bool _stylusPressureEnabled = AppPreferences.defaultStylusPressureEnabled;
  double _stylusCurve = AppPreferences.defaultStylusCurve;
  bool _autoSharpPeakEnabled = AppPreferences.defaultAutoSharpPeakEnabled;
  bool _vectorDrawingEnabled = AppPreferences.defaultVectorDrawingEnabled;
  bool _vectorStrokeSmoothingEnabled =
      AppPreferences.defaultVectorStrokeSmoothingEnabled;
  BrushShape _brushShape = AppPreferences.defaultBrushShape;
  PenStrokeSliderRange _penStrokeSliderRange =
      AppPreferences.defaultPenStrokeSliderRange;
  bool _bucketSampleAllLayers = false;
  bool _bucketContiguous = true;
  bool _bucketSwallowColorLine = AppPreferences.defaultBucketSwallowColorLine;
  int _bucketTolerance = AppPreferences.defaultBucketTolerance;
  int _magicWandTolerance = AppPreferences.defaultMagicWandTolerance;
  bool _brushToolsEraserMode = AppPreferences.defaultBrushToolsEraserMode;
  bool _shapeFillEnabled = AppPreferences.defaultShapeToolFillEnabled;
  bool _layerAdjustCropOutside = false;
  bool _layerOpacityGestureActive = false;
  String? _layerOpacityGestureLayerId;
  double? _layerOpacityUndoOriginalValue;
  String? _layerOpacityPreviewLayerId;
  double? _layerOpacityPreviewValue;
  bool _layerOpacityPreviewActive = false;
  int _layerOpacityPreviewRequestId = 0;
  int? _layerOpacityPreviewAwaitedGeneration;
  int? _layerOpacityPreviewCapturedSignature;
  bool _layerOpacityPreviewHasVisibleLowerLayers = false;
  ui.Image? _layerOpacityPreviewBackground;
  ui.Image? _layerOpacityPreviewActiveLayerImage;
  ui.Image? _layerOpacityPreviewForeground;
  final Map<String, _LayerPreviewCacheEntry> _layerPreviewCache =
      <String, _LayerPreviewCacheEntry>{};
  int _layerPreviewRequestSerial = 0;
  bool _spacePanOverrideActive = false;
  bool _isLayerDragging = false;
  Offset? _layerDragStart;
  int _layerDragAppliedDx = 0;
  int _layerDragAppliedDy = 0;
  final math.Random _syntheticStrokeRandom = math.Random();
  Offset? _curveAnchor;
  Offset? _curvePendingEnd;
  Offset? _curveDragOrigin;
  Offset _curveDragDelta = Offset.zero;
  bool _isCurvePlacingSegment = false;
  Path? _curvePreviewPath;
  CanvasLayerData? _curveRasterPreviewSnapshot;
  bool _curveUndoCapturedForPreview = false;
  Rect? _curvePreviewDirtyRect;
  Uint32List? _curveRasterPreviewPixels;
  bool _isEyedropperSampling = false;
  bool _eyedropperOverrideActive = false;
  Offset? _lastEyedropperSample;
  Offset? _toolCursorPosition;
  Offset? _lastWorkspacePointer;
  Offset? _penCursorWorkspacePosition;
  Duration? _lastPenSampleTimestamp;
  bool _activeStrokeUsesStylus = false;
  double? _activeStylusPressureMin;
  double? _activeStylusPressureMax;
  double? _lastStylusPressureValue;
  Offset? _lastStrokeBoardPosition;
  Offset? _lastStylusDirection;
  final _StrokeStabilizer _strokeStabilizer = _StrokeStabilizer();
  bool _isSpraying = false;
  Offset? _sprayBoardPosition;
  Ticker? _sprayTicker;
  Duration? _sprayTickerTimestamp;
  double _sprayEmissionAccumulator = 0.0;
  double _sprayCurrentPressure = 1.0;
  KritaSprayEngine? _kritaSprayEngine;
  Color? _activeSprayColor;
  Offset? _softSprayLastPoint;
  double _softSprayResidual = 0.0;
  Size _toolSettingsCardSize = const Size(320, _toolbarButtonSize);
  CanvasToolbarLayout _toolbarLayout = const CanvasToolbarLayout(
    columns: 1,
    rows: CanvasToolbar.buttonCount,
    width: CanvasToolbar.buttonSize,
    height:
        CanvasToolbar.buttonSize * CanvasToolbar.buttonCount +
        CanvasToolbar.spacing * (CanvasToolbar.buttonCount - 1),
  );
  List<Rect> _toolbarHitRegions = const <Rect>[];
  BoardLayoutWorker? _layoutWorker;
  BoardLayoutMetrics? _layoutMetrics;
  Future<BoardLayoutMetrics>? _pendingLayoutTask;

  final CanvasViewport _viewport = CanvasViewport();
  bool _viewportInitialized = false;
  Size _workspaceSize = Size.zero;
  Offset _layoutBaseOffset = Offset.zero;
  bool _workspaceMeasurementScheduled = false;
  final ScrollController _layerScrollController = ScrollController();
  late final ValueNotifier<CanvasViewInfo> _viewInfoNotifier;
  bool _viewInfoNotificationScheduled = false;
  CanvasViewInfo? _pendingViewInfo;
  Color _primaryColor = AppPreferences.defaultPrimaryColor;
  late HSVColor _primaryHsv;

  /// 颜色更新后由颜色面板调用的钩子，子类/混入可以覆写以响应颜色变化。
  @protected
  void _handlePrimaryColorChanged() {}
  @protected
  void _handleTextStrokeColorChanged(Color color) {}
  final List<Color> _recentColors = <Color>[];
  Color _colorLineColor = AppPreferences.defaultColorLineColor;
  final List<_CanvasHistoryEntry> _undoStack = <_CanvasHistoryEntry>[];
  final List<_CanvasHistoryEntry> _redoStack = <_CanvasHistoryEntry>[];
  bool _historyLocked = false;
  int _historyLimit = AppPreferences.instance.historyLimit;
  final List<_PaletteCardEntry> _paletteCards = <_PaletteCardEntry>[];
  int _paletteCardSerial = 0;
  bool _referenceCardResizeInProgress = false;
  double? _floatingColorPanelHeight;
  double? _floatingColorPanelMeasuredHeight;
  double? _sai2ColorPanelHeight;
  double? _sai2ColorPanelMeasuredHeight;
  double _sai2ToolSectionRatio = AppPreferences.defaultSai2ToolPanelSplit;
  double _sai2LayerPanelWidthRatio = AppPreferences.defaultSai2LayerPanelSplit;

  Future<bool> insertImageLayerFromBytes(Uint8List bytes, {String? name});

  bool get _includeHistoryOnToolbar => false;

  int get _toolbarButtonCount =>
      CanvasToolbar.buttonCount +
      (_includeHistoryOnToolbar ? CanvasToolbar.historyButtonCount : 0);

  bool _isInsidePaletteCardArea(Offset workspacePosition) {
    for (final _PaletteCardEntry entry in _paletteCards) {
      final Size size = entry.size ?? const Size(_paletteCardWidth, 180.0);
      final Rect rect = Rect.fromLTWH(
        entry.offset.dx,
        entry.offset.dy,
        size.width,
        size.height,
      );
      if (rect.contains(workspacePosition)) {
        return true;
      }
    }
    return false;
  }

  bool _isInsideReferenceCardArea(Offset workspacePosition);

  bool _isInsideAntialiasCardArea(Offset workspacePosition);

  bool _isInsideColorRangeCardArea(Offset workspacePosition);

  bool _isInsideWorkspacePanelArea(Offset workspacePosition) {
    return _isInsidePaletteCardArea(workspacePosition) ||
        _isInsideReferenceCardArea(workspacePosition) ||
        _isInsideAntialiasCardArea(workspacePosition) ||
        _isInsideColorRangeCardArea(workspacePosition);
  }

  // 透视辅助线相关成员由 _PaintingBoardPerspectiveMixin 提供。
  PerspectiveGuideMode get _perspectiveMode;
  bool get _perspectiveEnabled;
  bool get _perspectiveVisible;
  double get _perspectiveHorizonY;
  Offset get _perspectiveVp1;
  Offset? get _perspectiveVp2;
  Offset? get _perspectiveVp3;
  double get _perspectiveSnapAngleTolerance;
  _PerspectiveHandle? get _activePerspectiveHandle;
  _PerspectiveHandle? get _hoveringPerspectiveHandle;
  void togglePerspectiveGuide();
  void setPerspectiveMode(PerspectiveGuideMode mode);
  void _resetPerspectiveLock();
  void _updatePerspectiveHover(Offset boardLocal);
  void _clearPerspectiveHover();
  Offset _maybeSnapToPerspective(Offset position, {Offset? anchor});
  bool _handlePerspectivePointerDown(
    Offset boardLocal, {
    bool allowNearest = false,
  });
  bool get _isDraggingPerspectiveHandle;
  void _handlePerspectivePointerMove(Offset boardLocal);
  void _handlePerspectivePointerUp();

  void _clearLayerTransformCursorIndicator() {}

  Size get _canvasSize => widget.settings.size;

  Size get _scaledBoardSize => Size(
    _canvasSize.width * _viewport.scale,
    _canvasSize.height * _viewport.scale,
  );

  Color get _pixelGridColor => const ui.Color.fromARGB(255, 133, 133, 133);

  bool _isWithinCanvasBounds(Offset position) {
    final Size size = _canvasSize;
    return position.dx >= 0 &&
        position.dy >= 0 &&
        position.dx <= size.width &&
        position.dy <= size.height;
  }

  void _applyStylusSettingsToController() {
    _controller.configureStylusPressure(
      enabled: _stylusPressureEnabled,
      curve: _stylusCurve,
    );
    _controller.configureSharpTips(enabled: _autoSharpPeakEnabled);
  }

  List<_SyntheticStrokeSample> _buildSyntheticStrokeSamples(
    List<Offset> points,
    Offset initialPoint,
  ) {
    if (points.isEmpty) {
      return const <_SyntheticStrokeSample>[];
    }
    final List<_SyntheticStrokeSample> pending = <_SyntheticStrokeSample>[];
    double totalDistance = 0.0;
    Offset previous = initialPoint;
    for (final Offset point in points) {
      final double distance = (point - previous).distance;
      if (distance < 0.001) {
        previous = point;
        continue;
      }
      pending.add(
        _SyntheticStrokeSample(point: point, distance: distance, progress: 0.0),
      );
      totalDistance += distance;
      previous = point;
    }
    if (pending.isEmpty) {
      return const <_SyntheticStrokeSample>[];
    }
    if (totalDistance <= 0.0001) {
      final int count = pending.length;
      for (int i = 0; i < count; i++) {
        final _SyntheticStrokeSample sample = pending[i];
        pending[i] = _SyntheticStrokeSample(
          point: sample.point,
          distance: sample.distance,
          progress: (i + 1) / count,
        );
      }
      return pending;
    }
    double cumulative = 0.0;
    for (int i = 0; i < pending.length; i++) {
      final _SyntheticStrokeSample sample = pending[i];
      cumulative += sample.distance;
      pending[i] = _SyntheticStrokeSample(
        point: sample.point,
        distance: sample.distance,
        progress: (cumulative / totalDistance).clamp(0.0, 1.0),
      );
    }
    return pending;
  }

  void _simulateStrokeWithSyntheticTimeline(
    List<_SyntheticStrokeSample> samples, {
    required double totalDistance,
    required double initialTimestamp,
    _SyntheticStrokeTimelineStyle style = _SyntheticStrokeTimelineStyle.natural,
  }) {
    if (samples.isEmpty) {
      return;
    }
    final bool useFastCurveStyle =
        style == _SyntheticStrokeTimelineStyle.fastCurve;
    final double effectiveDistance = totalDistance > 0.0001
        ? totalDistance
        : samples.length.toDouble();
    double targetDuration = _syntheticStrokeTargetDuration(
      effectiveDistance,
    ).clamp(160.0, 720.0);
    if (useFastCurveStyle) {
      targetDuration *= 0.62;
    }
    final double durationJitter =
        ui.lerpDouble(0.85, 1.25, _syntheticStrokeRandom.nextDouble()) ?? 1.0;
    targetDuration *= durationJitter;
    final double minimumTimeline = samples.length * _syntheticStrokeMinDeltaMs;
    final double resolvedDuration = math.max(targetDuration, minimumTimeline);
    final List<double> weights = <double>[];
    double totalWeight = 0.0;
    for (final _SyntheticStrokeSample sample in samples) {
      final double baseSpeed = _syntheticStrokeSpeedFactor(
        sample.progress,
        _penPressureProfile,
      );
      final double styleScale = _syntheticTimelineSpeedScale(
        sample.progress,
        style,
      );
      final double speed = math.max(baseSpeed * styleScale, 0.05);
      final double jitter =
          ui.lerpDouble(0.82, 1.24, _syntheticStrokeRandom.nextDouble()) ?? 1.0;
      final double normalizedDistance = math.max(sample.distance, 0.02) / speed;
      final double weight = math.max(0.001, normalizedDistance * jitter);
      weights.add(weight);
      totalWeight += weight;
    }
    if (totalWeight <= 0.0001) {
      totalWeight = samples.length.toDouble();
      for (int i = 0; i < weights.length; i++) {
        weights[i] = 1.0;
      }
    }
    final double scale = resolvedDuration / totalWeight;
    double timestamp = initialTimestamp;
    for (int i = 0; i < samples.length; i++) {
      final double deltaTime = math.max(
        _syntheticStrokeMinDeltaMs,
        weights[i] * scale,
      );
      timestamp += deltaTime;
      _controller.extendStroke(
        samples[i].point,
        deltaTimeMillis: deltaTime,
        timestampMillis: timestamp,
      );
    }
  }

  double _syntheticStrokeTotalDistance(List<_SyntheticStrokeSample> samples) {
    double total = 0.0;
    for (final _SyntheticStrokeSample sample in samples) {
      total += sample.distance;
    }
    return total;
  }

  /// Adds an optional speed bias so synthetic strokes can mimic a faster
  /// flick, which emphasises the contrast between slow and fast segments.
  double _syntheticTimelineSpeedScale(
    double progress,
    _SyntheticStrokeTimelineStyle style,
  ) {
    if (style == _SyntheticStrokeTimelineStyle.natural) {
      return 1.0;
    }
    final double normalized = progress.clamp(0.0, 1.0);
    final double sine = math.sin(normalized * math.pi).abs();
    final double eased = math.pow(sine, 0.78).toDouble().clamp(0.0, 1.0);
    final double scale = ui.lerpDouble(0.24, 4.25, eased) ?? 1.0;
    return scale.clamp(0.24, 4.25);
  }

  double _syntheticStrokeTargetDuration(double totalDistance) {
    final double normalized = (totalDistance / 320.0).clamp(0.0, 1.0);
    return ui.lerpDouble(200.0, 500.0, normalized) ?? 320.0;
  }

  double _syntheticStrokeSpeedFactor(
    double progress,
    StrokePressureProfile profile,
  ) {
    final double normalized = progress.clamp(0.0, 1.0);
    final double fromCenter = (normalized - 0.5).abs() * 2.0;
    switch (profile) {
      case StrokePressureProfile.taperEnds:
        return ui.lerpDouble(2.8, 0.38, fromCenter) ?? 1.0;
      case StrokePressureProfile.taperCenter:
        return ui.lerpDouble(0.42, 2.6, fromCenter) ?? 1.0;
      case StrokePressureProfile.auto:
        final double sine = math.sin(normalized * math.pi).abs();
        final double blend = ui.lerpDouble(1.8, 0.55, sine) ?? 1.0;
        final double edgeBias = ui.lerpDouble(1.1, 0.75, fromCenter) ?? 1.0;
        return blend * edgeBias;
    }
  }

  List<Offset> _densifyStrokePolyline(
    List<Offset> points, {
    double maxSegmentLength = 6.0,
  }) {
    if (points.length < 2) {
      return List<Offset>.from(points);
    }
    final double spacing = maxSegmentLength.clamp(0.8, 24.0);
    final List<Offset> dense = <Offset>[points.first];
    for (int i = 1; i < points.length; i++) {
      final Offset from = dense.last;
      final Offset to = points[i];
      final double segmentLength = (to - from).distance;
      if (segmentLength <= spacing + 1e-3) {
        dense.add(to);
        continue;
      }
      final int segments = math.max(1, (segmentLength / spacing).ceil());
      for (int s = 1; s <= segments; s++) {
        final double t = s / segments;
        final double x = ui.lerpDouble(from.dx, to.dx, t) ?? to.dx;
        final double y = ui.lerpDouble(from.dy, to.dy, t) ?? to.dy;
        dense.add(Offset(x, y));
      }
    }
    return dense;
  }

  void _refreshStylusPreferencesIfNeeded() {
    final AppPreferences prefs = AppPreferences.instance;
    const double epsilon = 0.0001;
    final bool needsUpdate =
        _stylusPressureEnabled != prefs.stylusPressureEnabled ||
        (_stylusCurve - prefs.stylusPressureCurve).abs() > epsilon;
    if (!needsUpdate) {
      return;
    }
    _stylusPressureEnabled = prefs.stylusPressureEnabled;
    _stylusCurve = prefs.stylusPressureCurve;
    if (mounted) {
      _applyStylusSettingsToController();
    }
  }

  Offset _baseOffsetForScale(double scale) {
    final Size workspace = _workspaceSize;
    if (workspace.width <= 0 ||
        workspace.height <= 0 ||
        !workspace.width.isFinite ||
        !workspace.height.isFinite) {
      return Offset.zero;
    }

    final double scaledWidth = _canvasSize.width * scale;
    final double scaledHeight = _canvasSize.height * scale;

    final double rawLeft = (workspace.width - scaledWidth) / 2;
    final double rawTop = (workspace.height - scaledHeight) / 2;

    final double left = rawLeft.isFinite ? rawLeft : 0.0;
    final double top = rawTop.isFinite ? rawTop : 0.0;

    return Offset(left, top);
  }

  void _updateToolSettingsCardSize(Size size) {
    final double width = size.width.isFinite && size.width > 0
        ? size.width
        : _toolSettingsCardSize.width;
    final double height = size.height.isFinite && size.height > 0
        ? size.height
        : _toolSettingsCardSize.height;
    if ((width - _toolSettingsCardSize.width).abs() < 0.5 &&
        (height - _toolSettingsCardSize.height).abs() < 0.5) {
      return;
    }
    _toolSettingsCardSize = Size(width, height);
  }

  void _scheduleWorkspaceMeasurement(BuildContext context) {
    if (_workspaceMeasurementScheduled) {
      return;
    }
    _workspaceMeasurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _workspaceMeasurementScheduled = false;
      if (!mounted) {
        return;
      }
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        return;
      }
      final Size size = box.size;
      if (size.width <= 0 ||
          size.height <= 0 ||
          !size.width.isFinite ||
          !size.height.isFinite) {
        return;
      }
      final bool widthChanged = (size.width - _workspaceSize.width).abs() > 0.5;
      final bool heightChanged =
          (size.height - _workspaceSize.height).abs() > 0.5;
      if (!widthChanged && !heightChanged) {
        return;
      }
      setState(() {
        _workspaceSize = size;
        final double reservedColorSpace =
            _colorIndicatorSize + CanvasToolbar.spacing;
        _toolbarLayout = CanvasToolbar.layoutForAvailableHeight(
          _workspaceSize.height - _toolButtonPadding * 2 - reservedColorSpace,
          toolCount: _toolbarButtonCount,
        );
        _layoutMetrics = null;
        if (!_viewportInitialized) {
          // 仍需初始化视口，下一帧会根据新尺寸完成初始化
        }
        _scheduleLayoutMetricsUpdate();
      });
    });
  }

  BoardLayoutWorker _layoutWorkerInstance() {
    return _layoutWorker ??= BoardLayoutWorker();
  }

  void _scheduleLayoutMetricsUpdate() {
    if (!mounted) {
      return;
    }
    final BoardLayoutInput input = BoardLayoutInput(
      workspaceWidth: _workspaceSize.width,
      workspaceHeight: _workspaceSize.height,
      toolButtonPadding: _toolButtonPadding,
      toolSettingsSpacing: _toolSettingsSpacing,
      sidePanelWidth: _sidePanelWidth,
      colorIndicatorSize: _colorIndicatorSize,
      toolbarButtonCount: _toolbarButtonCount,
    );
    final Future<BoardLayoutMetrics> task = _layoutWorkerInstance().compute(
      input,
    );
    _pendingLayoutTask = task;
    task
        .then((BoardLayoutMetrics metrics) {
          if (!mounted || _pendingLayoutTask != task) {
            return;
          }
          setState(() {
            _layoutMetrics = metrics;
            _toolbarLayout = metrics.layout;
          });
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('Layout worker failed: $error');
        });
  }

  void _applyToolbarLayout(CanvasToolbarLayout layout) {
    if (_toolbarLayout.columns == layout.columns &&
        (_toolbarLayout.height - layout.height).abs() < 0.5 &&
        (_toolbarLayout.width - layout.width).abs() < 0.5) {
      return;
    }
    setState(() {
      _toolbarLayout = layout;
      _layoutMetrics = null;
      _scheduleLayoutMetricsUpdate();
    });
  }

  void _ensureToolbarDoesNotOverlapColorIndicator() {
    if (_toolbarHitRegions.length < 3) {
      return;
    }
    final Rect toolbarRect = _toolbarHitRegions[0];
    final Rect colorRect = _toolbarHitRegions[2];
    final double gap = colorRect.top - toolbarRect.bottom;
    final double fullAvailableHeight =
        _workspaceSize.height - _toolButtonPadding * 2 - _colorIndicatorSize;
    final double safeAvailableHeight =
        fullAvailableHeight - CanvasToolbar.spacing;
    if (!safeAvailableHeight.isFinite || safeAvailableHeight <= 0) {
      return;
    }
    if (gap >= CanvasToolbar.spacing) {
      if (_toolbarLayout.isMultiColumn) {
        final CanvasToolbarLayout candidate =
            CanvasToolbar.layoutForAvailableHeight(
              safeAvailableHeight,
              toolCount: _toolbarButtonCount,
            );
        if (candidate.columns == 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            _applyToolbarLayout(candidate);
          });
        }
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final CanvasToolbarLayout wrappedLayout =
          CanvasToolbar.layoutForAvailableHeight(
            safeAvailableHeight,
            toolCount: _toolbarButtonCount,
          );
      _applyToolbarLayout(wrappedLayout);
    });
  }

  CanvasToolbarLayout _resolveToolbarLayoutForStyle(
    PaintingToolbarLayoutStyle style,
    CanvasToolbarLayout base, {
    required bool includeHistoryButtons,
  }) {
    if (style != PaintingToolbarLayoutStyle.sai2) {
      return base;
    }
    const int targetColumns = 4;
    final double availableWidth = math.max(0, _sidePanelWidth - 32);
    final double totalSpacing = CanvasToolbar.spacing * (targetColumns - 1);
    final double maxExtent = targetColumns > 0
        ? (availableWidth - totalSpacing) / targetColumns
        : CanvasToolbar.buttonSize;
    final double buttonExtent = maxExtent.isFinite && maxExtent > 0
        ? maxExtent.clamp(36.0, CanvasToolbar.buttonSize)
        : CanvasToolbar.buttonSize;
    final int toolCount =
        CanvasToolbar.buttonCount +
        (includeHistoryButtons ? CanvasToolbar.historyButtonCount : 0);
    final int rows = math.max(1, (toolCount / targetColumns).ceil());
    final double width = targetColumns * buttonExtent + totalSpacing;
    final double height =
        rows * buttonExtent + (rows - 1) * CanvasToolbar.spacing;
    return CanvasToolbarLayout(
      columns: targetColumns,
      rows: rows,
      width: width,
      height: height,
      buttonExtent: buttonExtent,
      horizontalFlow: true,
      flowDirection: Axis.horizontal,
    );
  }

  Rect get _boardRect {
    final Offset position = _layoutBaseOffset + _viewport.offset;
    final Size size = _scaledBoardSize;
    return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  }

  Offset _toBoardLocal(Offset workspacePosition) {
    final Rect boardRect = _boardRect;
    return (workspacePosition - boardRect.topLeft) / _viewport.scale;
  }

  Offset? _boardCursorPosition() {
    final Offset? workspacePointer = _lastWorkspacePointer;
    if (workspacePointer == null) {
      return null;
    }
    final Rect boardRect = _boardRect;
    if (!boardRect.contains(workspacePointer)) {
      return null;
    }
    return _toBoardLocal(workspacePointer);
  }

  CanvasViewInfo _buildViewInfo() {
    return CanvasViewInfo(
      canvasSize: _canvasSize,
      scale: _viewport.scale,
      cursorPosition: _boardCursorPosition(),
      pixelGridVisible: _pixelGridVisible,
      viewBlackWhiteEnabled: _viewBlackWhiteOverlay,
      viewMirrorEnabled: _viewMirrorOverlay,
      perspectiveMode: _perspectiveMode,
      perspectiveEnabled: _perspectiveEnabled,
      perspectiveVisible: _perspectiveVisible,
    );
  }

  void _notifyViewInfoChanged() {
    final CanvasViewInfo next = _buildViewInfo();
    if (_viewInfoNotifier.value == next) {
      return;
    }
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    final bool safeToUpdateNow =
        phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks;
    if (safeToUpdateNow) {
      _viewInfoNotifier.value = next;
      _pendingViewInfo = null;
      return;
    }
    _pendingViewInfo = next;
    if (_viewInfoNotificationScheduled) {
      return;
    }
    _viewInfoNotificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewInfoNotificationScheduled = false;
      if (!mounted) {
        _pendingViewInfo = null;
        return;
      }
      final CanvasViewInfo? pending = _pendingViewInfo;
      _pendingViewInfo = null;
      if (pending != null && _viewInfoNotifier.value != pending) {
        _viewInfoNotifier.value = pending;
      }
    });
  }

  ValueListenable<CanvasViewInfo> get viewInfoListenable => _viewInfoNotifier;

  CanvasTool get activeTool => _activeTool;
  CanvasTool get _effectiveActiveTool {
    if (_eyedropperOverrideActive) {
      return CanvasTool.eyedropper;
    }
    if (_spacePanOverrideActive) {
      return CanvasTool.hand;
    }
    return _activeTool;
  }

  bool get _isReferenceCardResizing => _referenceCardResizeInProgress;

  bool get _cursorRequiresOverlay =>
      ToolCursorStyles.hasOverlay(_effectiveActiveTool);

  bool get _penRequiresOverlay =>
      _effectiveActiveTool == CanvasTool.pen ||
      _effectiveActiveTool == CanvasTool.spray ||
      _effectiveActiveTool == CanvasTool.curvePen ||
      _effectiveActiveTool == CanvasTool.shape ||
      _effectiveActiveTool == CanvasTool.eraser;

  bool get _isBrushEraserEnabled =>
      _brushToolsEraserMode || _activeTool == CanvasTool.eraser;

  bool get hasContent => _controller.hasVisibleContent;
  bool get isDirty => _isDirty;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  SelectionShape get selectionShape;
  ShapeToolVariant get shapeToolVariant;
  Path? get selectionPath;
  Path? get selectionPreviewPath;
  Path? get shapePreviewPath;
  Path? get shapeVectorFillOverlayPath;
  Color? get shapeVectorFillOverlayColor;
  Path? get magicWandPreviewPath;
  double get selectionDashPhase;
  bool isPointInsideSelection(Offset position);

  Uint8List? get selectionMaskSnapshot;
  Path? get selectionPathSnapshot;

  void setSelectionState({SelectionShape? shape, Path? path, Uint8List? mask});

  void clearSelectionArtifacts();
  void resetSelectionUndoFlag();

  UnmodifiableListView<BitmapLayerState> get _layers => _controller.layers;
  String? get _activeLayerId => _controller.activeLayerId;
  Color get _backgroundPreviewColor;

  List<CanvasLayerData> _buildInitialLayers();

  Future<void> _pickColor({
    required String title,
    required Color initialColor,
    required ValueChanged<Color> onSelected,
    VoidCallback? onCleared,
  });

  void _rememberColor(Color color);
  void _setPrimaryColor(Color color, {bool remember = true});
  Future<void> _applyPaintBucket(Offset position);

  void _setActiveTool(CanvasTool tool);
  void _convertMagicWandPreviewToSelection();
  void _convertSelectionToMagicWandPreview();
  void _clearMagicWandPreview();
  void _resetSelectionPreview();
  void _resetPolygonState();
  void _handleMagicWandPointerDown(Offset position);
  void _handleSelectionPointerDown(Offset position, Duration timestamp);
  void _handleSelectionPointerMove(Offset position);
  void _handleSelectionPointerUp();
  void _handleSelectionPointerCancel();
  void _handleSelectionHover(Offset position);
  void _clearSelectionHover();
  void _clearSelection();
  void _updateSelectionShape(SelectionShape shape);
  void _updateShapeToolVariant(ShapeToolVariant variant);
  void initializeSelectionTicker(TickerProvider provider);
  void disposeSelectionTicker();
  void _updateSelectionAnimation();

  void _handlePointerDown(PointerDownEvent event);
  void _handlePointerMove(PointerMoveEvent event);
  void _handlePointerUp(PointerUpEvent event);
  void _handlePointerCancel(PointerCancelEvent event);
  void _handlePointerHover(PointerHoverEvent event);
  void _handleWorkspacePointerExit();
  void _handlePointerSignal(PointerSignalEvent event);
  KeyEventResult _handleWorkspaceKeyEvent(FocusNode node, KeyEvent event);

  void _updatePenPressureSimulation(bool value);
  void _updatePenPressureProfile(StrokePressureProfile profile);
  void _updatePenAntialiasLevel(int value);
  void _updateAutoSharpPeakEnabled(bool value);

  void _handleScaleStart(ScaleStartDetails details);
  void _handleScaleUpdate(ScaleUpdateDetails details);
  void _handleScaleEnd(ScaleEndDetails details);

  void _handleUndo();
  void _handleRedo();
  Future<bool> cut();
  Future<bool> copy();
  Future<bool> paste();

  void _updatePenStrokeWidth(double value);
  void _updateSprayStrokeWidth(double value);
  void _updateBucketSampleAllLayers(bool value);
  void _updateBucketContiguous(bool value);

  void _handleAddLayer();
  void _handleRemoveLayer(String id);

  Widget _buildLayerPanelContent(FluentThemeData theme);
  Widget _buildColorPanelContent(FluentThemeData theme);
  Widget? _buildColorPanelTrailing(FluentThemeData theme);
  Widget _buildColorIndicator(FluentThemeData theme);

  List<CanvasLayerData> snapshotLayers() => _controller.snapshotLayers();

  @override
  Future<List<CanvasLayerData>> exportLayers() async => snapshotLayers();

  CanvasRotationResult? rotateCanvas(CanvasRotation rotation) {
    final int width = _controller.width;
    final int height = _controller.height;
    if (width <= 0 || height <= 0) {
      return null;
    }
    _controller.commitActiveLayerTranslation();
    final List<CanvasLayerData> original = snapshotLayers();
    if (original.isEmpty) {
      return CanvasRotationResult(
        layers: const <CanvasLayerData>[],
        width: width,
        height: height,
      );
    }
    final List<CanvasLayerData> rotated = <CanvasLayerData>[
      for (final CanvasLayerData layer in original)
        _rotateLayerData(layer, rotation),
    ];
    setSelectionState(path: null, mask: null);
    clearSelectionArtifacts();
    resetSelectionUndoFlag();
    final bool swaps = _rotationSwapsDimensions(rotation);
    if (!swaps) {
      _controller.loadLayers(rotated, _controller.backgroundColor);
      _resetHistory();
      setState(() {});
    }
    return CanvasRotationResult(
      layers: rotated,
      width: swaps ? height : width,
      height: swaps ? width : height,
    );
  }

  void markSaved() {
    if (!_isDirty) {
      return;
    }
    _isDirty = false;
    widget.onDirtyChanged?.call(false);
  }

  CanvasLayerData _rotateLayerData(
    CanvasLayerData layer,
    CanvasRotation rotation,
  ) {
    final Uint8List? bitmap = layer.bitmap;
    final int? bitmapWidth = layer.bitmapWidth;
    final int? bitmapHeight = layer.bitmapHeight;
    if (bitmap != null && bitmapWidth != null && bitmapHeight != null) {
      final bool swaps = _rotationSwapsDimensions(rotation);
      final int targetWidth = swaps ? bitmapHeight : bitmapWidth;
      final int targetHeight = swaps ? bitmapWidth : bitmapHeight;
      final Uint8List rotated = _rotateBitmapRgba(
        bitmap,
        bitmapWidth,
        bitmapHeight,
        rotation,
      );
      return CanvasLayerData(
        id: layer.id,
        name: layer.name,
        visible: layer.visible,
        opacity: layer.opacity,
        locked: layer.locked,
        clippingMask: layer.clippingMask,
        blendMode: layer.blendMode,
        bitmap: rotated,
        bitmapWidth: targetWidth,
        bitmapHeight: targetHeight,
        fillColor: layer.fillColor,
      );
    }

    return CanvasLayerData(
      id: layer.id,
      name: layer.name,
      visible: layer.visible,
      opacity: layer.opacity,
      locked: layer.locked,
      clippingMask: layer.clippingMask,
      blendMode: layer.blendMode,
      fillColor: layer.fillColor,
    );
  }

  static bool _rotationSwapsDimensions(CanvasRotation rotation) {
    return rotation == CanvasRotation.clockwise90 ||
        rotation == CanvasRotation.counterClockwise90;
  }

  static Uint8List _rotateBitmapRgba(
    Uint8List source,
    int width,
    int height,
    CanvasRotation rotation,
  ) {
    if (source.length != width * height * 4) {
      return Uint8List.fromList(source);
    }
    final bool swaps = _rotationSwapsDimensions(rotation);
    final int targetWidth = swaps ? height : width;
    final int targetHeight = swaps ? width : height;
    final Uint8List output = Uint8List(targetWidth * targetHeight * 4);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int srcIndex = (y * width + x) * 4;
        late int destX;
        late int destY;
        switch (rotation) {
          case CanvasRotation.clockwise90:
            destX = height - 1 - y;
            destY = x;
            break;
          case CanvasRotation.counterClockwise90:
            destX = y;
            destY = width - 1 - x;
            break;
          case CanvasRotation.clockwise180:
          case CanvasRotation.counterClockwise180:
            destX = width - 1 - x;
            destY = height - 1 - y;
            break;
        }
        final int destIndex = (destY * targetWidth + destX) * 4;
        output[destIndex] = source[srcIndex];
        output[destIndex + 1] = source[srcIndex + 1];
        output[destIndex + 2] = source[srcIndex + 2];
        output[destIndex + 3] = source[srcIndex + 3];
      }
    }
    return output;
  }

  CanvasLayerData _scaleLayerData(
    CanvasLayerData layer,
    int sourceCanvasWidth,
    int sourceCanvasHeight,
    int targetWidth,
    int targetHeight,
    ImageResizeSampling sampling,
  ) {
    final Uint8List? bitmap = layer.bitmap;
    final int? bitmapWidth = layer.bitmapWidth;
    final int? bitmapHeight = layer.bitmapHeight;
    if (bitmap == null || bitmapWidth == null || bitmapHeight == null) {
      return layer;
    }
    final double scaleX = targetWidth / sourceCanvasWidth;
    final double scaleY = targetHeight / sourceCanvasHeight;
    final int scaledWidth = math.max(1, (bitmapWidth * scaleX).round());
    final int scaledHeight = math.max(1, (bitmapHeight * scaleY).round());
    final int scaledLeft = (scaleX == 0)
        ? 0
        : ((layer.bitmapLeft ?? 0) * scaleX).round();
    final int scaledTop = (scaleY == 0)
        ? 0
        : ((layer.bitmapTop ?? 0) * scaleY).round();
    final Uint8List scaledBitmap = _scaleBitmapRgba(
      bitmap,
      bitmapWidth,
      bitmapHeight,
      scaledWidth,
      scaledHeight,
      sampling,
    );
    if (!_hasVisiblePixels(scaledBitmap)) {
      return layer.copyWith(clearBitmap: true);
    }
    return layer.copyWith(
      bitmap: scaledBitmap,
      bitmapWidth: scaledWidth,
      bitmapHeight: scaledHeight,
      bitmapLeft: scaledLeft,
      bitmapTop: scaledTop,
    );
  }

  CanvasLayerData _reframeLayerData(
    CanvasLayerData layer,
    int sourceCanvasWidth,
    int sourceCanvasHeight,
    int targetWidth,
    int targetHeight,
    CanvasResizeAnchor anchor,
  ) {
    final Uint8List? bitmap = layer.bitmap;
    final int? bitmapWidth = layer.bitmapWidth;
    final int? bitmapHeight = layer.bitmapHeight;
    final int offsetX = _anchorOffsetValue(
      sourceCanvasWidth,
      targetWidth,
      _horizontalAnchorFactor(anchor),
    );
    final int offsetY = _anchorOffsetValue(
      sourceCanvasHeight,
      targetHeight,
      _verticalAnchorFactor(anchor),
    );
    if (bitmap == null || bitmapWidth == null || bitmapHeight == null) {
      if (layer.bitmapLeft == null && layer.bitmapTop == null) {
        return layer;
      }
      return layer.copyWith(
        bitmapLeft: layer.bitmapLeft == null
            ? null
            : layer.bitmapLeft! + offsetX,
        bitmapTop: layer.bitmapTop == null ? null : layer.bitmapTop! + offsetY,
      );
    }
    int newLeft = (layer.bitmapLeft ?? 0) + offsetX;
    int newTop = (layer.bitmapTop ?? 0) + offsetY;
    int visibleWidth = bitmapWidth;
    int visibleHeight = bitmapHeight;
    int cropLeft = 0;
    int cropTop = 0;
    if (newLeft < 0) {
      cropLeft = -newLeft;
      visibleWidth -= cropLeft;
      newLeft = 0;
    }
    if (newTop < 0) {
      cropTop = -newTop;
      visibleHeight -= cropTop;
      newTop = 0;
    }
    final int rightOverflow = newLeft + visibleWidth - targetWidth;
    if (rightOverflow > 0) {
      visibleWidth -= rightOverflow;
    }
    final int bottomOverflow = newTop + visibleHeight - targetHeight;
    if (bottomOverflow > 0) {
      visibleHeight -= bottomOverflow;
    }
    if (visibleWidth <= 0 || visibleHeight <= 0) {
      return layer.copyWith(clearBitmap: true);
    }
    Uint8List nextBitmap = bitmap;
    if (cropLeft != 0 ||
        cropTop != 0 ||
        visibleWidth != bitmapWidth ||
        visibleHeight != bitmapHeight) {
      nextBitmap = _cropBitmapRgba(
        bitmap,
        bitmapWidth,
        bitmapHeight,
        cropLeft,
        cropTop,
        visibleWidth,
        visibleHeight,
      );
    }
    if (!_hasVisiblePixels(nextBitmap)) {
      return layer.copyWith(clearBitmap: true);
    }
    return layer.copyWith(
      bitmap: nextBitmap,
      bitmapWidth: visibleWidth,
      bitmapHeight: visibleHeight,
      bitmapLeft: newLeft,
      bitmapTop: newTop,
    );
  }

  int _anchorOffsetValue(int sourceSize, int targetSize, double factor) {
    final double delta = (targetSize - sourceSize) * factor;
    return delta.round();
  }

  double _horizontalAnchorFactor(CanvasResizeAnchor anchor) {
    switch (anchor) {
      case CanvasResizeAnchor.topLeft:
      case CanvasResizeAnchor.centerLeft:
      case CanvasResizeAnchor.bottomLeft:
        return 0;
      case CanvasResizeAnchor.topCenter:
      case CanvasResizeAnchor.center:
      case CanvasResizeAnchor.bottomCenter:
        return 0.5;
      case CanvasResizeAnchor.topRight:
      case CanvasResizeAnchor.centerRight:
      case CanvasResizeAnchor.bottomRight:
        return 1.0;
    }
  }

  double _verticalAnchorFactor(CanvasResizeAnchor anchor) {
    switch (anchor) {
      case CanvasResizeAnchor.topLeft:
      case CanvasResizeAnchor.topCenter:
      case CanvasResizeAnchor.topRight:
        return 0;
      case CanvasResizeAnchor.centerLeft:
      case CanvasResizeAnchor.center:
      case CanvasResizeAnchor.centerRight:
        return 0.5;
      case CanvasResizeAnchor.bottomLeft:
      case CanvasResizeAnchor.bottomCenter:
      case CanvasResizeAnchor.bottomRight:
        return 1.0;
    }
  }

  Uint8List _scaleBitmapRgba(
    Uint8List source,
    int sourceWidth,
    int sourceHeight,
    int targetWidth,
    int targetHeight,
    ImageResizeSampling sampling,
  ) {
    if (sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        targetWidth <= 0 ||
        targetHeight <= 0) {
      return Uint8List(0);
    }
    switch (sampling) {
      case ImageResizeSampling.nearest:
        return _scaleBitmapNearest(
          source,
          sourceWidth,
          sourceHeight,
          targetWidth,
          targetHeight,
        );
      case ImageResizeSampling.bilinear:
        return _scaleBitmapBilinear(
          source,
          sourceWidth,
          sourceHeight,
          targetWidth,
          targetHeight,
        );
    }
  }

  Uint8List _scaleBitmapNearest(
    Uint8List source,
    int sourceWidth,
    int sourceHeight,
    int targetWidth,
    int targetHeight,
  ) {
    final Uint8List output = Uint8List(targetWidth * targetHeight * 4);
    final double scaleX = sourceWidth / targetWidth;
    final double scaleY = sourceHeight / targetHeight;
    int destIndex = 0;
    for (int y = 0; y < targetHeight; y++) {
      final int srcY = math.min(sourceHeight - 1, (y * scaleY).floor());
      for (int x = 0; x < targetWidth; x++) {
        final int srcX = math.min(sourceWidth - 1, (x * scaleX).floor());
        final int srcIndex = (srcY * sourceWidth + srcX) * 4;
        output[destIndex] = source[srcIndex];
        output[destIndex + 1] = source[srcIndex + 1];
        output[destIndex + 2] = source[srcIndex + 2];
        output[destIndex + 3] = source[srcIndex + 3];
        destIndex += 4;
      }
    }
    return output;
  }

  Uint8List _scaleBitmapBilinear(
    Uint8List source,
    int sourceWidth,
    int sourceHeight,
    int targetWidth,
    int targetHeight,
  ) {
    final Uint8List output = Uint8List(targetWidth * targetHeight * 4);
    final double scaleX = sourceWidth / targetWidth;
    final double scaleY = sourceHeight / targetHeight;
    int destIndex = 0;
    for (int y = 0; y < targetHeight; y++) {
      final double rawY = (y + 0.5) * scaleY - 0.5;
      double clampedY = rawY;
      if (clampedY < 0) {
        clampedY = 0;
      } else if (clampedY > sourceHeight - 1) {
        clampedY = (sourceHeight - 1).toDouble();
      }
      final int y0 = clampedY.floor();
      final int y1 = math.min(y0 + 1, sourceHeight - 1);
      final double wy = clampedY - y0;
      final double wy0 = 1 - wy;
      final double wy1 = wy;
      for (int x = 0; x < targetWidth; x++) {
        final double rawX = (x + 0.5) * scaleX - 0.5;
        double clampedX = rawX;
        if (clampedX < 0) {
          clampedX = 0;
        } else if (clampedX > sourceWidth - 1) {
          clampedX = (sourceWidth - 1).toDouble();
        }
        final int x0 = clampedX.floor();
        final int x1 = math.min(x0 + 1, sourceWidth - 1);
        final double wx = clampedX - x0;
        final double wx0 = 1 - wx;
        final double wx1 = wx;
        final double w00 = wx0 * wy0;
        final double w01 = wx1 * wy0;
        final double w10 = wx0 * wy1;
        final double w11 = wx1 * wy1;
        final int index00 = (y0 * sourceWidth + x0) * 4;
        final int index01 = (y0 * sourceWidth + x1) * 4;
        final int index10 = (y1 * sourceWidth + x0) * 4;
        final int index11 = (y1 * sourceWidth + x1) * 4;
        final double red =
            source[index00] * w00 +
            source[index01] * w01 +
            source[index10] * w10 +
            source[index11] * w11;
        final double green =
            source[index00 + 1] * w00 +
            source[index01 + 1] * w01 +
            source[index10 + 1] * w10 +
            source[index11 + 1] * w11;
        final double blue =
            source[index00 + 2] * w00 +
            source[index01 + 2] * w01 +
            source[index10 + 2] * w10 +
            source[index11 + 2] * w11;
        final double alpha =
            source[index00 + 3] * w00 +
            source[index01 + 3] * w01 +
            source[index10 + 3] * w10 +
            source[index11 + 3] * w11;
        output[destIndex] = _clampChannel(red);
        output[destIndex + 1] = _clampChannel(green);
        output[destIndex + 2] = _clampChannel(blue);
        output[destIndex + 3] = _clampChannel(alpha);
        destIndex += 4;
      }
    }
    return output;
  }

  int _clampChannel(double value) {
    if (value <= 0) {
      return 0;
    }
    if (value >= 255) {
      return 255;
    }
    return value.round();
  }

  Uint8List _cropBitmapRgba(
    Uint8List source,
    int sourceWidth,
    int sourceHeight,
    int left,
    int top,
    int width,
    int height,
  ) {
    if (width <= 0 || height <= 0) {
      return Uint8List(0);
    }
    final Uint8List output = Uint8List(width * height * 4);
    for (int row = 0; row < height; row++) {
      final int srcY = top + row;
      if (srcY < 0 || srcY >= sourceHeight) {
        continue;
      }
      final int srcStart = ((srcY * sourceWidth) + left) * 4;
      final int destStart = row * width * 4;
      output.setRange(destStart, destStart + width * 4, source, srcStart);
    }
    return output;
  }

  bool _hasVisiblePixels(Uint8List bitmap) {
    for (int i = 3; i < bitmap.length; i += 4) {
      if (bitmap[i] != 0) {
        return true;
      }
    }
    return false;
  }

  void _markDirty() {
    if (_isDirty) {
      return;
    }
    _isDirty = true;
    widget.onDirtyChanged?.call(true);
  }

  void _emitClean() {
    if (!_isDirty) {
      return;
    }
    _isDirty = false;
    widget.onDirtyChanged?.call(false);
  }

  void _resetHistory() {
    _undoStack.clear();
    _redoStack.clear();
    _historyLocked = false;
    _historyLimit = AppPreferences.instance.historyLimit;
  }

  Future<void> _pushUndoSnapshot({_CanvasHistoryEntry? entry}) async {
    _refreshHistoryLimit();
    if (_historyLocked) {
      return;
    }
    final _CanvasHistoryEntry snapshot = entry ?? await _createHistoryEntry();
    _undoStack.add(snapshot);
    _trimHistoryStacks();
    _redoStack.clear();
  }

  Future<_CanvasHistoryEntry> _createHistoryEntry() async {
    await _controller.waitForPendingWorkerTasks();
    return _CanvasHistoryEntry(
      layers: _controller.snapshotLayers(),
      backgroundColor: _controller.backgroundColor,
      activeLayerId: _controller.activeLayerId,
      selectionShape: selectionShape,
      selectionMask: selectionMaskSnapshot != null
          ? Uint8List.fromList(selectionMaskSnapshot!)
          : null,
      selectionPath: selectionPathSnapshot != null
          ? (Path()..addPath(selectionPathSnapshot!, Offset.zero))
          : null,
    );
  }

  Future<void> _applyHistoryEntry(_CanvasHistoryEntry entry) async {
    await _controller.waitForPendingWorkerTasks();
    _historyLocked = true;
    try {
      _controller.loadLayers(entry.layers, entry.backgroundColor);
      final String? activeId = entry.activeLayerId;
      if (activeId != null) {
        _controller.setActiveLayer(activeId);
      }
      setSelectionState(
        shape: entry.selectionShape,
        path: entry.selectionPath != null
            ? (Path()..addPath(entry.selectionPath!, Offset.zero))
            : null,
        mask: entry.selectionMask != null
            ? Uint8List.fromList(entry.selectionMask!)
            : null,
      );
      clearSelectionArtifacts();
    } finally {
      _historyLocked = false;
    }
    setState(() {});
    _focusNode.requestFocus();
    _markDirty();
    resetSelectionUndoFlag();
    _updateSelectionAnimation();
  }

  void _refreshHistoryLimit() {
    final int nextLimit = AppPreferences.instance.historyLimit;
    if (_historyLimit == nextLimit) {
      return;
    }
    _historyLimit = nextLimit;
    _trimHistoryStacks();
  }

  void _trimHistoryStacks() {
    while (_undoStack.length > _historyLimit) {
      _undoStack.removeAt(0);
    }
    while (_redoStack.length > _historyLimit) {
      _redoStack.removeAt(0);
    }
  }

  void _handleFloatingColorPanelMeasured(double height) {
    if (!height.isFinite || height <= 0) {
      return;
    }
    final double? current = _floatingColorPanelMeasuredHeight;
    if (current != null && (current - height).abs() < 0.5) {
      return;
    }
    setState(() => _floatingColorPanelMeasuredHeight = height);
  }

  void _handleSai2ColorPanelMeasured(double height) {
    if (!height.isFinite || height <= 0) {
      return;
    }
    final double? current = _sai2ColorPanelMeasuredHeight;
    if (current != null && (current - height).abs() < 0.5) {
      return;
    }
    setState(() => _sai2ColorPanelMeasuredHeight = height);
  }

  void _setFloatingColorPanelHeight(double? value) {
    double? sanitized = value;
    if (sanitized != null && (!sanitized.isFinite || sanitized <= 0)) {
      sanitized = null;
    }
    if (_floatingColorPanelHeight == sanitized) {
      return;
    }
    setState(() => _floatingColorPanelHeight = sanitized);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.floatingColorPanelHeight = sanitized;
    unawaited(AppPreferences.save());
  }

  void _setSai2ColorPanelHeight(double? value) {
    double? sanitized = value;
    if (sanitized != null && (!sanitized.isFinite || sanitized <= 0)) {
      sanitized = null;
    }
    if (_sai2ColorPanelHeight == sanitized) {
      return;
    }
    setState(() => _sai2ColorPanelHeight = sanitized);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.sai2ColorPanelHeight = sanitized;
    unawaited(AppPreferences.save());
  }

  void _setSai2ToolSectionRatio(double value) {
    final double normalized = value.clamp(0.0, 1.0);
    if ((_sai2ToolSectionRatio - normalized).abs() < 0.0001) {
      return;
    }
    setState(() => _sai2ToolSectionRatio = normalized);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.sai2ToolPanelSplit = normalized;
    unawaited(AppPreferences.save());
  }

  void _setSai2LayerPanelWidthRatio(double value) {
    final double normalized = value.clamp(0.0, 1.0);
    if ((_sai2LayerPanelWidthRatio - normalized).abs() < 0.0001) {
      return;
    }
    setState(() => _sai2LayerPanelWidthRatio = normalized);
    final AppPreferences prefs = AppPreferences.instance;
    prefs.sai2LayerPanelWidthSplit = normalized;
    unawaited(AppPreferences.save());
  }

  void resetWorkspaceLayout() {
    final AppPreferences prefs = AppPreferences.instance;
    setState(() {
      _floatingColorPanelHeight = null;
      _sai2ColorPanelHeight = null;
      _sai2ToolSectionRatio = AppPreferences.defaultSai2ToolPanelSplit;
      _sai2LayerPanelWidthRatio = AppPreferences.defaultSai2LayerPanelSplit;
    });
    prefs.floatingColorPanelHeight = null;
    prefs.sai2ColorPanelHeight = null;
    prefs.sai2ToolPanelSplit = AppPreferences.defaultSai2ToolPanelSplit;
    prefs.sai2LayerPanelWidthSplit = AppPreferences.defaultSai2LayerPanelSplit;
    unawaited(AppPreferences.save());
  }

  void _initializeViewportIfNeeded() {
    if (_viewportInitialized) {
      return;
    }

    final Size workspaceSize = _workspaceSize;
    if (workspaceSize.width <= 0 ||
        workspaceSize.height <= 0 ||
        !workspaceSize.width.isFinite ||
        !workspaceSize.height.isFinite) {
      return;
    }

    final Size canvasSize = _canvasSize;
    if (canvasSize.width <= 0 ||
        canvasSize.height <= 0 ||
        !canvasSize.width.isFinite ||
        !canvasSize.height.isFinite) {
      _viewportInitialized = true;
      return;
    }

    final double widthScale = workspaceSize.width / canvasSize.width;
    final double heightScale = workspaceSize.height / canvasSize.height;
    final double baseScale = widthScale < heightScale
        ? widthScale
        : heightScale;

    double targetScale = baseScale * _initialViewportScaleFactor;
    if (!targetScale.isFinite || targetScale <= 0) {
      targetScale = baseScale.isFinite && baseScale > 0 ? baseScale : 1.0;
    }

    if (targetScale > baseScale && baseScale.isFinite && baseScale > 0) {
      targetScale = baseScale;
    }

    _viewport.setScale(targetScale);
    _viewport.setOffset(Offset.zero);
    _viewportInitialized = true;
    _notifyViewInfoChanged();
  }

  bool get isPixelGridVisible => _pixelGridVisible;
  bool get isViewBlackWhiteEnabled => _viewBlackWhiteOverlay;
  bool get isViewMirrorEnabled => _viewMirrorOverlay;
  bool get isPerspectiveGuideEnabled => _perspectiveEnabled;
  bool get isPerspectiveGuideVisible => _perspectiveVisible;
  PerspectiveGuideMode get perspectiveGuideMode => _perspectiveMode;

  bool get isBoardReady => _controller.frame != null;

  void _handlePixelGridPreferenceChanged() {
    if (!mounted) {
      return;
    }
    final bool visible = AppPreferences.pixelGridVisibleNotifier.value;
    if (visible == _pixelGridVisible) {
      return;
    }
    setState(() {
      _pixelGridVisible = visible;
    });
    _notifyViewInfoChanged();
  }

  void togglePixelGridVisibility() {
    final AppPreferences prefs = AppPreferences.instance;
    final bool nextVisible = !prefs.pixelGridVisible;
    prefs.updatePixelGridVisible(nextVisible);
    unawaited(AppPreferences.save());
  }

  void toggleViewBlackWhiteOverlay() {
    setState(() {
      _viewBlackWhiteOverlay = !_viewBlackWhiteOverlay;
    });
    _notifyViewInfoChanged();
  }

  void toggleViewMirrorOverlay() {
    setState(() {
      _viewMirrorOverlay = !_viewMirrorOverlay;
    });
    _notifyViewInfoChanged();
  }

  void togglePerspectiveGuideVisibility() {
    togglePerspectiveGuide();
  }

  void setPerspectiveGuideMode(PerspectiveGuideMode mode) {
    setPerspectiveMode(mode);
  }
}

class PaintingBoardState extends _PaintingBoardBase
    with
        TickerProviderStateMixin,
        _PaintingBoardLayerTransformMixin,
        _PaintingBoardLayerMixin,
        _PaintingBoardColorMixin,
        _PaintingBoardPaletteMixin,
        _PaintingBoardReferenceMixin,
        _PaintingBoardPerspectiveMixin,
        _PaintingBoardTextMixin,
        _PaintingBoardSelectionMixin,
        _PaintingBoardShapeMixin,
        _PaintingBoardClipboardMixin,
        _PaintingBoardInteractionMixin,
        _PaintingBoardFilterMixin,
        _PaintingBoardBuildMixin
    implements CanvasBoardClient {
  @override
  void initState() {
    super.initState();
    _viewInfoNotifier = ValueNotifier<CanvasViewInfo>(_buildViewInfo());
    initializeTextTool();
    initializeSelectionTicker(this);
    _layerRenameFocusNode.addListener(_handleLayerRenameFocusChange);
    final AppPreferences prefs = AppPreferences.instance;
    _pixelGridVisible = prefs.pixelGridVisible;
    AppPreferences.pixelGridVisibleNotifier.addListener(
      _handlePixelGridPreferenceChanged,
    );
    _bucketSampleAllLayers = prefs.bucketSampleAllLayers;
    _bucketContiguous = prefs.bucketContiguous;
    _bucketSwallowColorLine = prefs.bucketSwallowColorLine;
    _bucketTolerance = prefs.bucketTolerance;
    _magicWandTolerance = prefs.magicWandTolerance;
    _brushToolsEraserMode = prefs.brushToolsEraserMode;
    _shapeFillEnabled = prefs.shapeToolFillEnabled;
    _layerAdjustCropOutside = prefs.layerAdjustCropOutside;
    _penStrokeSliderRange = prefs.penStrokeSliderRange;
    _penStrokeWidth = _penStrokeSliderRange.clamp(prefs.penStrokeWidth);
    _sprayStrokeWidth = prefs.sprayStrokeWidth.clamp(
      kSprayStrokeMin,
      kSprayStrokeMax,
    );
    _sprayMode = prefs.sprayMode;
    _strokeStabilizerStrength = prefs.strokeStabilizerStrength;
    _simulatePenPressure = prefs.simulatePenPressure;
    _penPressureProfile = prefs.penPressureProfile;
    _penAntialiasLevel = prefs.penAntialiasLevel.clamp(0, 3);
    _bucketAntialiasLevel = prefs.bucketAntialiasLevel.clamp(0, 3);
    _stylusPressureEnabled = prefs.stylusPressureEnabled;
    _stylusCurve = prefs.stylusPressureCurve;
    _autoSharpPeakEnabled = prefs.autoSharpPeakEnabled;
    _vectorDrawingEnabled = prefs.vectorDrawingEnabled;
    _vectorStrokeSmoothingEnabled = prefs.vectorStrokeSmoothingEnabled;
    _brushShape = prefs.brushShape;
    _colorLineColor = prefs.colorLineColor;
    _primaryColor = prefs.primaryColor;
    _primaryHsv = HSVColor.fromColor(_primaryColor);
    _floatingColorPanelHeight = prefs.floatingColorPanelHeight;
    _sai2ColorPanelHeight = prefs.sai2ColorPanelHeight;
    _sai2ToolSectionRatio = prefs.sai2ToolPanelSplit.clamp(0.0, 1.0);
    _sai2LayerPanelWidthRatio = prefs.sai2LayerPanelWidthSplit.clamp(0.0, 1.0);
    _rememberColor(widget.settings.backgroundColor);
    _rememberColor(_primaryColor);
    initializePerspectiveGuide(widget.initialPerspectiveGuide);
    final List<CanvasLayerData> layers = _buildInitialLayers();
    _controller = BitmapCanvasController(
      width: widget.settings.width.round(),
      height: widget.settings.height.round(),
      backgroundColor: widget.settings.backgroundColor,
      initialLayers: layers,
      creationLogic: widget.settings.creationLogic,
    );
    _controller.setVectorDrawingEnabled(_vectorDrawingEnabled);
    _controller.setVectorStrokeSmoothingEnabled(_vectorStrokeSmoothingEnabled);
    _controller.setVectorStrokeSmoothingEnabled(_vectorStrokeSmoothingEnabled);
    _controller.setLayerOverflowCropping(_layerAdjustCropOutside);
    _applyStylusSettingsToController();
    _controller.addListener(_handleControllerChanged);
    _boardReadyNotified = _controller.frame != null;
    if (_boardReadyNotified) {
      widget.onReadyChanged?.call(true);
    }
    _resetHistory();
    _syncRasterizeMenuAvailability();
    _notifyViewInfoChanged();
  }

  @override
  void dispose() {
    disposeTextTool();
    _removeFilterOverlay(restoreOriginal: false);
    _disposeReferenceCards();
    disposeSelectionTicker();
    _controller.removeListener(_handleControllerChanged);
    unawaited(_controller.disposeController());
    _layerOpacityPreviewReset(this);
    _disposeLayerPreviewCache();
    _layerScrollController.dispose();
    _layerContextMenuController.dispose();
    _blendModeFlyoutController.dispose();
    _layerRenameFocusNode.removeListener(_handleLayerRenameFocusChange);
    _layerRenameController.dispose();
    _layerRenameFocusNode.dispose();
    _pendingLayoutTask = null;
    unawaited(_layoutWorker?.dispose());
    _focusNode.dispose();
    _sprayTicker?.dispose();
    _viewInfoNotifier.dispose();
    AppPreferences.pixelGridVisibleNotifier.removeListener(
      _handlePixelGridPreferenceChanged,
    );
    super.dispose();
  }

  void addLayerAboveActiveLayer() {
    _handleAddLayer();
  }

  @override
  Future<bool> insertImageLayerFromBytes(
    Uint8List bytes, {
    String? name,
  }) async {
    if (!isBoardReady) {
      return false;
    }
    try {
      final _ImportedImageData decoded = await _decodeExternalImage(bytes);
      final int canvasWidth = widget.settings.width.round();
      final int canvasHeight = widget.settings.height.round();
      final int offsetX = ((canvasWidth - decoded.width) / 2).floor();
      final int offsetY = ((canvasHeight - decoded.height) / 2).floor();
      final String resolvedName = _normalizeImportedLayerName(name);
      final CanvasLayerData layerData = CanvasLayerData(
        id: generateLayerId(),
        name: resolvedName,
        bitmap: decoded.bytes,
        bitmapWidth: decoded.width,
        bitmapHeight: decoded.height,
        bitmapLeft: offsetX,
        bitmapTop: offsetY,
        cloneBitmap: false,
      );
      await _pushUndoSnapshot();
      _controller.insertLayerFromData(layerData, aboveLayerId: _activeLayerId);
      _controller.setActiveLayer(layerData.id);
      setState(() {});
      _markDirty();
      return true;
    } catch (error, stackTrace) {
      debugPrint('Failed to insert image layer: $error\n$stackTrace');
      return false;
    }
  }

  String _normalizeImportedLayerName(String? raw) {
    final String? trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '导入图层';
    }
    return trimmed;
  }

  Future<_ImportedImageData> _decodeExternalImage(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    final ByteData? pixelData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    codec.dispose();
    if (pixelData == null) {
      image.dispose();
      throw StateError('无法读取位图像素数据');
    }
    final Uint8List rgba = Uint8List.fromList(pixelData.buffer.asUint8List());
    final _ImportedImageData result = _ImportedImageData(
      width: image.width,
      height: image.height,
      bytes: rgba,
    );
    image.dispose();
    return result;
  }

  void mergeActiveLayerDown() {
    final String? activeLayerId = _activeLayerId;
    if (activeLayerId == null) {
      return;
    }
    final BitmapLayerState? layer = _layerById(activeLayerId);
    if (layer == null) {
      return;
    }
    _handleMergeLayerDown(layer);
  }

  Future<void> binarizeActiveLayer() async {
    if (!isBoardReady) {
      _showBinarizeMessage('画布尚未准备好，无法二值化。');
      return;
    }
    final String? activeLayerId = _activeLayerId;
    if (activeLayerId == null) {
      _showBinarizeMessage('请先选择一个可编辑的图层。');
      return;
    }
    final BitmapLayerState? layer = _layerById(activeLayerId);
    if (layer == null) {
      _showBinarizeMessage('无法定位当前图层。');
      return;
    }
    if (layer.locked) {
      _showBinarizeMessage('当前图层已锁定，无法二值化。');
      return;
    }
    if (layer.text != null) {
      _showBinarizeMessage('当前图层是文字图层，请先栅格化或切换其他图层。');
      return;
    }

    await _controller.waitForPendingWorkerTasks();
    final List<CanvasLayerData> snapshot = _controller.snapshotLayers();
    final int index = snapshot.indexWhere((item) => item.id == activeLayerId);
    if (index < 0) {
      _showBinarizeMessage('无法定位当前图层。');
      return;
    }
    final CanvasLayerData data = snapshot[index];
    Uint8List? bitmap = data.bitmap != null
        ? Uint8List.fromList(data.bitmap!)
        : null;
    Color? fillColor = data.fillColor;
    if (bitmap == null && fillColor == null) {
      _showBinarizeMessage('当前图层为空，无法二值化。');
      return;
    }

    const int alphaThreshold = 128;
    bool bitmapModified = false;
    bool bitmapHasCoverage = false;
    if (bitmap != null) {
      for (int i = 0; i < bitmap.length; i += 4) {
        final int alpha = bitmap[i + 3];
        if (alpha == 0) {
          continue;
        }
        if (alpha >= alphaThreshold) {
          if (alpha != 255) {
            bitmap[i + 3] = 255;
            bitmapModified = true;
          }
          bitmapHasCoverage = true;
          continue;
        }
        if (bitmap[i] != 0 || bitmap[i + 1] != 0 || bitmap[i + 2] != 0) {
          bitmap[i] = 0;
          bitmap[i + 1] = 0;
          bitmap[i + 2] = 0;
        }
        if (alpha != 0) {
          bitmap[i + 3] = 0;
          bitmapModified = true;
        }
      }
      if (!bitmapHasCoverage) {
        bitmap = null;
        if (data.bitmap != null) {
          bitmapModified = true;
        }
      }
    }

    bool fillChanged = false;
    if (fillColor != null) {
      final int alpha = fillColor.alpha;
      if (alpha > 0 && alpha < 255) {
        final int nextAlpha = alpha >= alphaThreshold ? 255 : 0;
        if (nextAlpha != alpha) {
          fillColor = fillColor.withAlpha(nextAlpha);
          fillChanged = true;
        }
      }
    }

    if (!bitmapModified && !fillChanged) {
      _showBinarizeMessage('未检测到可处理的半透明像素。');
      return;
    }

    await _pushUndoSnapshot();
    final CanvasLayerData updated = CanvasLayerData(
      id: data.id,
      name: data.name,
      visible: data.visible,
      opacity: data.opacity,
      locked: data.locked,
      clippingMask: data.clippingMask,
      blendMode: data.blendMode,
      fillColor: fillColor,
      bitmap: bitmap,
      bitmapWidth: bitmap != null ? data.bitmapWidth : null,
      bitmapHeight: bitmap != null ? data.bitmapHeight : null,
      bitmapLeft: bitmap != null ? data.bitmapLeft : null,
      bitmapTop: bitmap != null ? data.bitmapTop : null,
      text: data.text,
      cloneBitmap: false,
    );
    _controller.replaceLayer(activeLayerId, updated);
    _controller.setActiveLayer(activeLayerId);
    setState(() {});
    _markDirty();
  }

  void _showBinarizeMessage(String message) {
    AppNotifications.show(
      context,
      message: message,
      severity: InfoBarSeverity.warning,
    );
  }

  void selectEntireCanvas() async {
    final int width = _controller.width;
    final int height = _controller.height;
    if (width <= 0 || height <= 0) {
      return;
    }
    final int length = width * height;
    final Uint8List mask = Uint8List(length)..fillRange(0, length, 1);
    final Path selectionPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    await _prepareSelectionUndo();
    setState(() {
      clearSelectionArtifacts();
      setSelectionState(path: selectionPath, mask: mask);
    });
    _updateSelectionAnimation();
    _finishSelectionUndo();
  }

  void invertSelection() async {
    final int width = _controller.width;
    final int height = _controller.height;
    if (width <= 0 || height <= 0) {
      return;
    }
    final int length = width * height;
    final Uint8List? currentMask = _selectionMask;
    final Uint8List inverted = Uint8List(length);
    if (currentMask == null) {
      inverted.fillRange(0, length, 1);
    } else {
      if (currentMask.length != length) {
        return;
      }
      for (int i = 0; i < length; i++) {
        inverted[i] = currentMask[i] == 0 ? 1 : 0;
      }
    }
    if (!_maskHasCoverage(inverted)) {
      await _prepareSelectionUndo();
      setState(() {
        clearSelectionArtifacts();
        setSelectionState(path: null, mask: null);
      });
      _updateSelectionAnimation();
      _finishSelectionUndo();
      return;
    }
    final Path? path = currentMask == null
        ? (Path()
            ..addRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble())))
        : _pathFromMask(inverted, width);
    await _prepareSelectionUndo();
    setState(() {
      clearSelectionArtifacts();
      setSelectionState(path: path, mask: inverted);
    });
    _updateSelectionAnimation();
    _finishSelectionUndo();
  }

  Future<CanvasResizeResult?> resizeImage(
    int width,
    int height,
    ImageResizeSampling sampling,
  ) {
    if (width <= 0 || height <= 0) {
      return Future.value(null);
    }
    _controller.commitActiveLayerTranslation();
    final int sourceWidth = _controller.width;
    final int sourceHeight = _controller.height;
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return Future.value(null);
    }
    final List<CanvasLayerData> layers = _controller.snapshotLayers();
    final List<CanvasLayerData> resizedLayers = <CanvasLayerData>[
      for (final CanvasLayerData layer in layers)
        _scaleLayerData(
          layer,
          sourceWidth,
          sourceHeight,
          width,
          height,
          sampling,
        ),
    ];
    return Future.value(
      CanvasResizeResult(layers: resizedLayers, width: width, height: height),
    );
  }

  Future<CanvasResizeResult?> resizeCanvas(
    int width,
    int height,
    CanvasResizeAnchor anchor,
  ) {
    if (width <= 0 || height <= 0) {
      return Future.value(null);
    }
    _controller.commitActiveLayerTranslation();
    final int sourceWidth = _controller.width;
    final int sourceHeight = _controller.height;
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return Future.value(null);
    }
    final List<CanvasLayerData> layers = _controller.snapshotLayers();
    final List<CanvasLayerData> resizedLayers = <CanvasLayerData>[
      for (final CanvasLayerData layer in layers)
        _reframeLayerData(
          layer,
          sourceWidth,
          sourceHeight,
          width,
          height,
          anchor,
        ),
    ];
    return Future.value(
      CanvasResizeResult(layers: resizedLayers, width: width, height: height),
    );
  }

  @override
  void didUpdateWidget(covariant PaintingBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool sizeChanged = widget.settings.size != oldWidget.settings.size;
    final bool backgroundChanged =
        widget.settings.backgroundColor != oldWidget.settings.backgroundColor;
    final bool logicChanged =
        widget.settings.creationLogic != oldWidget.settings.creationLogic;
    if (sizeChanged || backgroundChanged || logicChanged) {
      _controller.removeListener(_handleControllerChanged);
      unawaited(_controller.disposeController());
      _controller = BitmapCanvasController(
        width: widget.settings.width.round(),
        height: widget.settings.height.round(),
        backgroundColor: widget.settings.backgroundColor,
        initialLayers: _buildInitialLayers(),
        creationLogic: widget.settings.creationLogic,
      );
      _controller.setVectorDrawingEnabled(_vectorDrawingEnabled);
      _applyStylusSettingsToController();
      _controller.addListener(_handleControllerChanged);
      _boardReadyNotified = _controller.frame != null;
      if (_boardReadyNotified) {
        widget.onReadyChanged?.call(true);
      }
      _resetHistory();
      setState(() {
        if (sizeChanged) {
          _viewport.reset();
          _workspaceSize = Size.zero;
          _layoutBaseOffset = Offset.zero;
          _viewportInitialized = false;
        }
      });
      _notifyViewInfoChanged();
    }
  }

  void _handleControllerChanged() {
    final BitmapCanvasFrame? frame = _controller.frame;
    final int? awaitedGeneration = _layerOpacityPreviewAwaitedGeneration;
    if (awaitedGeneration != null &&
        frame != null &&
        frame.generation != awaitedGeneration) {
      if (_layerOpacityGestureActive) {
        _layerOpacityPreviewAwaitedGeneration = null;
      } else {
        _layerOpacityPreviewDeactivate(this, notifyListeners: true);
      }
    }
    _handleFilterApplyFrameProgress(frame);
    final bool shouldClearVectorFillOverlay =
        _shapeVectorFillOverlayPath != null &&
        _controller.committingStrokes.isEmpty;
    if (_maybeInitializeLayerTransformStateFromController()) {
      if (shouldClearVectorFillOverlay) {
        setState(() {
          _shapeVectorFillOverlayPath = null;
          _shapeVectorFillOverlayColor = null;
        });
      }
      return;
    }
    setState(() {
      if (shouldClearVectorFillOverlay) {
        _shapeVectorFillOverlayPath = null;
        _shapeVectorFillOverlayColor = null;
      }
    });
    _syncRasterizeMenuAvailability();
    _notifyBoardReadyIfNeeded();
  }

  void _notifyBoardReadyIfNeeded() {
    if (_boardReadyNotified) {
      return;
    }
    if (_controller.frame == null) {
      return;
    }
    _boardReadyNotified = true;
    widget.onReadyChanged?.call(true);
  }

  WorkspaceOverlaySnapshot buildWorkspaceOverlaySnapshot() {
    return WorkspaceOverlaySnapshot(
      paletteCards: buildPaletteSnapshots(),
      referenceCards: buildReferenceSnapshots(),
    );
  }

  Future<void> restoreWorkspaceOverlaySnapshot(
    WorkspaceOverlaySnapshot snapshot,
  ) async {
    restorePaletteSnapshots(snapshot.paletteCards);
    await restoreReferenceSnapshots(snapshot.referenceCards);
  }

  ToolSettingsSnapshot buildToolSettingsSnapshot() {
    return ToolSettingsSnapshot(
      activeTool: _activeTool,
      primaryColor: _primaryColor.value,
      recentColors: _recentColors
          .map((color) => color.value)
          .toList(growable: false),
      colorLineColor: _colorLineColor.value,
      penStrokeWidth: _penStrokeWidth,
      sprayStrokeWidth: _sprayStrokeWidth,
      sprayMode: _sprayMode,
      penStrokeSliderRange: _penStrokeSliderRange,
      brushShape: _brushShape,
      strokeStabilizerStrength: _strokeStabilizerStrength,
      stylusPressureEnabled: _stylusPressureEnabled,
      simulatePenPressure: _simulatePenPressure,
      penPressureProfile: _penPressureProfile,
      penAntialiasLevel: _penAntialiasLevel,
      bucketAntialiasLevel: _bucketAntialiasLevel,
      autoSharpPeakEnabled: _autoSharpPeakEnabled,
      vectorDrawingEnabled: _vectorDrawingEnabled,
      vectorStrokeSmoothingEnabled: _vectorStrokeSmoothingEnabled,
      bucketSampleAllLayers: _bucketSampleAllLayers,
      bucketContiguous: _bucketContiguous,
      bucketSwallowColorLine: _bucketSwallowColorLine,
      bucketTolerance: _bucketTolerance,
      magicWandTolerance: _magicWandTolerance,
      brushToolsEraserMode: _brushToolsEraserMode,
      layerAdjustCropOutside: _layerAdjustCropOutside,
      shapeFillEnabled: _shapeFillEnabled,
      selectionShape: _selectionShape,
      shapeToolVariant: _shapeToolVariant,
      textFontSize: _textFontSize,
      textLineHeight: _textLineHeight,
      textLetterSpacing: _textLetterSpacing,
      textFontFamily: _textFontFamily,
      textAlign: _textAlign,
      textOrientation: _textOrientation,
      textAntialias: _textAntialias,
      textStrokeEnabled: _textStrokeEnabled,
      textStrokeWidth: _textStrokeWidth,
    );
  }

  void applyToolSettingsSnapshot(ToolSettingsSnapshot snapshot) {
    _setActiveTool(snapshot.activeTool);
    _updateShapeToolVariant(snapshot.shapeToolVariant);
    _updateShapeFillEnabled(snapshot.shapeFillEnabled);
    _updateSelectionShape(snapshot.selectionShape);
    _updateTextFontSize(snapshot.textFontSize);
    _updateTextLineHeight(snapshot.textLineHeight);
    _updateTextLetterSpacing(snapshot.textLetterSpacing);
    _updateTextFontFamily(snapshot.textFontFamily);
    _updateTextAlign(snapshot.textAlign);
    _updateTextOrientation(snapshot.textOrientation);
    _updateTextAntialias(snapshot.textAntialias);
    _updateTextStrokeEnabled(snapshot.textStrokeEnabled);
    _updateTextStrokeWidth(snapshot.textStrokeWidth);
    _updatePenStrokeWidth(snapshot.penStrokeWidth);
    _updateSprayStrokeWidth(snapshot.sprayStrokeWidth);
    _updateSprayMode(snapshot.sprayMode);
    if (_penStrokeSliderRange != snapshot.penStrokeSliderRange) {
      setState(() => _penStrokeSliderRange = snapshot.penStrokeSliderRange);
    }
    _updateBrushShape(snapshot.brushShape);
    _updateStrokeStabilizerStrength(snapshot.strokeStabilizerStrength);
    _updateStylusPressureEnabled(snapshot.stylusPressureEnabled);
    _updatePenPressureSimulation(snapshot.simulatePenPressure);
    _updatePenPressureProfile(snapshot.penPressureProfile);
    _updatePenAntialiasLevel(snapshot.penAntialiasLevel);
    _updateBucketAntialiasLevel(snapshot.bucketAntialiasLevel);
    _updateAutoSharpPeakEnabled(snapshot.autoSharpPeakEnabled);
    _updateVectorDrawingEnabled(snapshot.vectorDrawingEnabled);
    _updateVectorStrokeSmoothingEnabled(snapshot.vectorStrokeSmoothingEnabled);
    _updateBucketSampleAllLayers(snapshot.bucketSampleAllLayers);
    _updateBucketContiguous(snapshot.bucketContiguous);
    _updateBucketSwallowColorLine(snapshot.bucketSwallowColorLine);
    _updateBucketTolerance(snapshot.bucketTolerance);
    _updateMagicWandTolerance(snapshot.magicWandTolerance);
    _updateBrushToolsEraserMode(snapshot.brushToolsEraserMode);
    _updateLayerAdjustCropOutside(snapshot.layerAdjustCropOutside);
    _setPrimaryColor(Color(snapshot.primaryColor), remember: false);
    setState(() {
      _recentColors
        ..clear()
        ..addAll(snapshot.recentColors.map((value) => Color(value)));
    });
    final Color targetColorLine = Color(snapshot.colorLineColor);
    if (_colorLineColor.value != targetColorLine.value) {
      setState(() => _colorLineColor = targetColorLine);
    }
  }
}

class _CanvasHistoryEntry {
  const _CanvasHistoryEntry({
    required this.layers,
    required this.backgroundColor,
    required this.activeLayerId,
    required this.selectionShape,
    this.selectionMask,
    this.selectionPath,
  });

  final List<CanvasLayerData> layers;
  final Color backgroundColor;
  final String? activeLayerId;
  final SelectionShape selectionShape;
  final Uint8List? selectionMask;
  final Path? selectionPath;
}

StrokePressureProfile _penPressureProfile = StrokePressureProfile.auto;

void _layerOpacityPreviewReset(
  _PaintingBoardBase board, {
  bool notifyListeners = false,
}) {
  final bool hadPreview =
      board._layerOpacityPreviewActive ||
      board._layerOpacityPreviewLayerId != null ||
      board._layerOpacityPreviewValue != null;
  board._layerOpacityPreviewActive = false;
  board._layerOpacityPreviewLayerId = null;
  board._layerOpacityPreviewValue = null;
  board._layerOpacityPreviewRequestId++;
  board._layerOpacityPreviewAwaitedGeneration = null;
  board._layerOpacityPreviewCapturedSignature = null;
  board._layerOpacityPreviewHasVisibleLowerLayers = false;
  _layerOpacityPreviewDisposeImages(board);
  if (notifyListeners && hadPreview && board.mounted) {
    board.setState(() {});
  }
}

void _layerOpacityPreviewDeactivate(
  _PaintingBoardBase board, {
  bool notifyListeners = false,
}) {
  final bool hadPreview =
      board._layerOpacityPreviewActive ||
      board._layerOpacityPreviewValue != null ||
      board._layerOpacityPreviewAwaitedGeneration != null;
  board._layerOpacityPreviewActive = false;
  board._layerOpacityPreviewValue = null;
  board._layerOpacityPreviewAwaitedGeneration = null;
  board._layerOpacityPreviewHasVisibleLowerLayers = false;
  if (notifyListeners && hadPreview && board.mounted) {
    board.setState(() {});
  }
}

void _layerOpacityPreviewDisposeImages(_PaintingBoardBase board) {
  board._layerOpacityPreviewBackground?.dispose();
  board._layerOpacityPreviewBackground = null;
  board._layerOpacityPreviewActiveLayerImage?.dispose();
  board._layerOpacityPreviewActiveLayerImage = null;
  board._layerOpacityPreviewForeground?.dispose();
  board._layerOpacityPreviewForeground = null;
}

int _layerOpacityPreviewSignature(Iterable<BitmapLayerState> layers) {
  int hash = layers.length;
  int index = 1;
  for (final BitmapLayerState layer in layers) {
    hash = 37 * hash + layer.revision;
    hash = 37 * hash + layer.id.hashCode;
    hash = 37 * hash + index;
    hash = 37 * hash + (layer.visible ? 1 : 0);
    hash = 37 * hash + (layer.clippingMask ? 1 : 0);
    hash = 37 * hash + layer.blendMode.index;
    hash = 37 * hash + (layer.opacity * 1000).round();
    index++;
  }
  return hash;
}
