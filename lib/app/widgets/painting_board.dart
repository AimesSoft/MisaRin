import 'dart:async';
import 'dart:collection';
import 'dart:convert';
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
        rootBundle,
        TextInputFormatter,
        TextInputType,
        TextEditingValue,
        TextSelection;
import 'package:flutter/rendering.dart'
    show
        RenderBox,
        RenderObject,
        RenderRepaintBoundary,
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
        StatefulBuilder,
        SingleChildRenderObjectWidget,
        StrutStyle,
        TextEditingController,
        TextHeightBehavior,
        WidgetsBinding;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalMaterialLocalizations;
import 'package:path/path.dart' as p;
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;
import 'package:file_picker/file_picker.dart';

import '../dialogs/misarin_dialog.dart';
import '../dialogs/brush_preset_editor_dialog.dart';
import '../l10n/l10n.dart';
import '../debug/rust_canvas_timeline.dart';

import '../../minecraft/bedrock_model.dart';
import '../../minecraft/bedrock_animation.dart';
import '../../bitmap_canvas/bitmap_canvas.dart';
import '../../bitmap_canvas/raster_frame.dart';
import '../../bitmap_canvas/controller.dart';
import '../../brushes/brush_library.dart';
import '../../brushes/brush_preset.dart';
import '../../bitmap_canvas/stroke_dynamics.dart'
    show StrokeDynamics, StrokePressureProfile, StrokeSampleMetrics;
import '../../bitmap_canvas/stroke_sample.dart';
import '../../bitmap_canvas/velocity_smoother.dart';
import '../../canvas/blend_mode_utils.dart';
import '../../canvas/canvas_layer.dart';
import '../../canvas/canvas_settings.dart';
import '../../canvas/canvas_exporter.dart';
import '../../canvas/canvas_tools.dart';
import '../../canvas/canvas_viewport.dart';
import '../../canvas/brush_random_rotation.dart';
import '../../canvas/text_renderer.dart';
import '../../canvas/perspective_guide.dart';
import '../toolbars/widgets/canvas_toolbar.dart';
import '../toolbars/widgets/tool_settings_card.dart';
import '../toolbars/layouts/layouts.dart';
import '../toolbars/widgets/measured_size.dart';
import '../../painting/krita_spray_engine.dart';
import 'tool_cursor_overlay.dart';
import 'rust_canvas_surface.dart';
import 'package:misa_rin/src/rust/canvas_engine_ffi.dart';
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
import '../utils/web_log.dart';
import 'layer_visibility_button.dart';
import 'app_notification.dart';
import '../native/system_fonts.dart';
import '../tooltips/hover_detail_tooltip.dart';
import '../../backend/layout_compute_worker.dart';
import '../../backend/canvas_painting_worker.dart';
import '../../backend/canvas_raster_backend.dart';
import '../../backend/rgba_utils.dart';
import '../../src/rust/api/selection_path.dart' as rust_selection_path;
import '../../performance/canvas_perf_stress.dart';
import '../../performance/stroke_latency_monitor.dart';
import '../workspace/workspace_shared_state.dart';

part 'painting_board_layers.dart';
part 'painting_board_layers_panel.dart';
part 'painting_board_layer_widgets.dart';
part 'painting_board_colors.dart';
part 'painting_board_colors_widgets.dart';
part 'painting_board_palette.dart';
part 'painting_board_marching_ants.dart';
part 'painting_board_selection.dart';
part 'painting_board_selection_path_from_mask.dart';
part 'painting_board_layer_transform.dart';
part 'painting_board_layer_transform_models.dart';
part 'painting_board_layer_transform_panel.dart';
part 'painting_board_shapes.dart';
part 'painting_board_perspective.dart';
	part 'painting_board_text.dart';
	part 'painting_board_text_painter.dart';
	part 'painting_board_clipboard.dart';
	part 'painting_board_interactions.dart';
	part 'painting_board_interactions_preferences.dart';
	part 'painting_board_interactions_stroke.dart';
	part 'painting_board_interactions_spray_cursor.dart';
	part 'painting_board_interactions_layer_curve.dart';
	part 'painting_board_interactions_stabilizers.dart';
	part 'painting_board_build.dart';
	part 'painting_board_build_shortcuts.dart';
	part 'painting_board_build_body.dart';
	part 'painting_board_widgets.dart';
	part 'painting_board_workspace_panel.dart';
part 'painting_board_filters.dart';
part 'painting_board_filters_panel.dart';
part 'painting_board_filters_preview.dart';
part 'painting_board_filters_controls.dart';
part 'painting_board_filters_worker.dart';
part 'painting_board_filters_preview_capture.dart';
part 'painting_board_filters_color_range_compute.dart';
part 'painting_board_filters_algorithms_color.dart';
part 'painting_board_filters_algorithms_blur.dart';
part 'painting_board_reference.dart';
part 'painting_board_reference_widgets.dart';
part 'painting_board_reference_model.dart';
part 'painting_board_reference_model_card.dart';
part 'painting_board_reference_model_card_actions.dart';
part 'painting_board_reference_model_card_bake.dart';
part 'painting_board_reference_model_card_bake_support.dart';
part 'painting_board_reference_model_card_bake_texture.dart';
part 'painting_board_reference_model_zbuffer.dart';
part 'painting_board_reference_model_zbuffer_buffers.dart';
part 'painting_board_reference_model_zbuffer_render.dart';
part 'painting_board_reference_model_zbuffer_background.dart';
part 'painting_board_reference_model_zbuffer_self_shadow.dart';
part 'painting_board_reference_model_zbuffer_shadows.dart';
part 'painting_board_reference_model_zbuffer_rasterizer_self_shadow.dart';
part 'painting_board_reference_model_zbuffer_rasterizer.dart';
part 'painting_board_reference_model_zbuffer_painter.dart';
part 'painting_board_core.dart';
part 'painting_board_base_core.dart';
part 'painting_board_base.dart';
part 'painting_board_state.dart';
