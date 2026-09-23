import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:misa_rin/utils/io_shim.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../bitmap_canvas/stroke_dynamics.dart';
import '../../canvas/canvas_backend.dart';
import '../../canvas/canvas_backend_state.dart';
import '../../canvas/canvas_tools.dart';
import '../constants/color_line_presets.dart';
import '../constants/pen_constants.dart';
import '../models/workspace_layout.dart';

part 'app_preferences_defaults.dart';
part 'app_preferences_models.dart';
part 'app_preferences_codec.dart';
part 'app_preferences_storage.dart';
part 'app_preferences_loader.dart';
part 'app_preferences_saver.dart';

class AppPreferences {
  AppPreferences._({
    required this.bucketSampleAllLayers,
    required this.bucketContiguous,
    required this.historyLimit,
    required this.themeMode,
    this.localeOverride,
    required this.penStrokeWidth,
    required this.simulatePenPressure,
    required this.penPressureProfile,
    required this.penAntialiasLevel,
    required this.stylusPressureEnabled,
    required this.stylusPressureCurve,
    required this.autoSharpPeakEnabled,
    required this.penStrokeSliderRange,
    this.sprayStrokeSliderRange = _defaultSprayStrokeSliderRange,
    this.eraserStrokeSliderRange = _defaultEraserStrokeSliderRange,
    required this.strokeStabilizerStrength,
    this.streamlineStrength = _defaultStreamlineStrength,
    required this.brushShape,
    this.brushRandomRotationEnabled = _defaultBrushRandomRotationEnabled,
    required this.layerAdjustCropOutside,
    required this.colorLineColor,
    required this.bucketSwallowColorLine,
    this.bucketSwallowColorLineMode = _defaultBucketSwallowColorLineMode,
    this.primaryColor = _defaultPrimaryColor,
    this.hollowStrokeEnabled = _defaultHollowStrokeEnabled,
    this.hollowStrokeRatio = _defaultHollowStrokeRatio,
    this.hollowStrokeEraseOccludedParts =
        _defaultHollowStrokeEraseOccludedParts,
    this.shapeToolFillEnabled = _defaultShapeToolFillEnabled,
    this.bucketAntialiasLevel = _defaultBucketAntialiasLevel,
    this.bucketTolerance = _defaultBucketTolerance,
    this.bucketFillGap = _defaultBucketFillGap,
    this.magicWandTolerance = _defaultMagicWandTolerance,
    this.brushToolsEraserMode = _defaultBrushToolsEraserMode,
    this.touchDrawingEnabled = _defaultTouchDrawingEnabled,
    this.showFpsOverlay = _defaultShowFpsOverlay,
    this.pixelGridVisible = _defaultPixelGridVisible,
    this.autoSaveCleanupThresholdMb = _defaultAutoSaveCleanupThresholdMb,
    this.workspaceLayout = _defaultWorkspaceLayout,
    this.floatingColorPanelHeight,
    this.sai2ColorPanelHeight,
    this.sai2ToolPanelSplit = _defaultSai2ToolPanelSplit,
    this.sai2LayerPanelWidthSplit = _defaultSai2LayerPanelSplit,
    this.sprayStrokeWidth = _defaultSprayStrokeWidth,
    this.eraserStrokeWidth = _defaultEraserStrokeWidth,
    this.liquifyStrokeWidth = _defaultLiquifyStrokeWidth,
    this.liquifyStrength = _defaultLiquifyStrength,
    this.liquifySoftness = _defaultLiquifySoftness,
    this.liquifyMix = _defaultLiquifyMix,
    this.smudgeStrokeWidth = _defaultSmudgeStrokeWidth,
    this.smudgeStrength = _defaultSmudgeStrength,
    this.smudgeSoftness = _defaultSmudgeSoftness,
    this.sprayMode = _defaultSprayMode,
    this.newCanvasWidth = _defaultNewCanvasWidth,
    this.newCanvasHeight = _defaultNewCanvasHeight,
    this.newCanvasBackgroundColor = _defaultNewCanvasBackgroundColor,
    this.canvasBackend = _defaultCanvasBackend,
  });

  static const int minHistoryLimit = _minHistoryLimit;
  static const int maxHistoryLimit = _maxHistoryLimit;

  static const bool defaultStylusPressureEnabled =
      _defaultStylusPressureEnabled;
  static const double defaultStylusCurve = _defaultStylusCurve;
  static const double stylusCurveLowerBound = _stylusCurveLowerBound;
  static const double stylusCurveUpperBound = _stylusCurveUpperBound;
  static const int defaultPenAntialiasLevel = _defaultPenAntialiasLevel;
  static const bool defaultAutoSharpPeakEnabled = _defaultAutoSharpPeakEnabled;
  static const PenStrokeSliderRange defaultPenStrokeSliderRange =
      _defaultPenStrokeSliderRange;
  static const PenStrokeSliderRange defaultSprayStrokeSliderRange =
      _defaultSprayStrokeSliderRange;
  static const PenStrokeSliderRange defaultEraserStrokeSliderRange =
      _defaultEraserStrokeSliderRange;
  static const double defaultStrokeStabilizerStrength =
      _defaultStrokeStabilizerStrength;
  static const double defaultStreamlineStrength = _defaultStreamlineStrength;
  static const BrushShape defaultBrushShape = _defaultBrushShape;
  static const bool defaultBrushRandomRotationEnabled =
      _defaultBrushRandomRotationEnabled;
  static const bool defaultHollowStrokeEnabled = _defaultHollowStrokeEnabled;
  static const double defaultHollowStrokeRatio = _defaultHollowStrokeRatio;
  static const bool defaultHollowStrokeEraseOccludedParts =
      _defaultHollowStrokeEraseOccludedParts;
  static const double defaultSprayStrokeWidth = _defaultSprayStrokeWidth;
  static const double defaultEraserStrokeWidth = _defaultEraserStrokeWidth;
  static const double defaultLiquifyStrokeWidth = _defaultLiquifyStrokeWidth;
  static const double defaultLiquifyStrength = _defaultLiquifyStrength;
  static const double defaultLiquifySoftness = _defaultLiquifySoftness;
  static const double defaultLiquifyMix = _defaultLiquifyMix;
  static const double defaultSmudgeStrokeWidth = _defaultSmudgeStrokeWidth;
  static const double defaultSmudgeStrength = _defaultSmudgeStrength;
  static const double defaultSmudgeSoftness = _defaultSmudgeSoftness;
  static const SprayMode defaultSprayMode = _defaultSprayMode;
  static const bool defaultLayerAdjustCropOutside = false;
  static const Color defaultColorLineColor = _defaultColorLineColor;
  static const Color defaultPrimaryColor = _defaultPrimaryColor;
  static const bool defaultBucketSwallowColorLine =
      _defaultBucketSwallowColorLine;
  static const BucketSwallowColorLineMode defaultBucketSwallowColorLineMode =
      _defaultBucketSwallowColorLineMode;
  static const int defaultBucketTolerance = _defaultBucketTolerance;
  static const int defaultBucketFillGap = _defaultBucketFillGap;
  static const int defaultMagicWandTolerance = _defaultMagicWandTolerance;
  static const bool defaultBrushToolsEraserMode = _defaultBrushToolsEraserMode;
  static const bool defaultTouchDrawingEnabled = _defaultTouchDrawingEnabled;
  static const bool defaultShapeToolFillEnabled = _defaultShapeToolFillEnabled;
  static const int defaultBucketAntialiasLevel = _defaultBucketAntialiasLevel;
  static const bool defaultShowFpsOverlay = _defaultShowFpsOverlay;
  static const CanvasBackend defaultCanvasBackend = _defaultCanvasBackend;
  static const int defaultAutoSaveCleanupThresholdMb =
      _defaultAutoSaveCleanupThresholdMb;
  static const int minAutoSaveCleanupThresholdMb =
      _minAutoSaveCleanupThresholdMb;
  static const int maxAutoSaveCleanupThresholdMb =
      _maxAutoSaveCleanupThresholdMb;
  static const WorkspaceLayoutPreference defaultWorkspaceLayout =
      _defaultWorkspaceLayout;
  static const double defaultSai2ToolPanelSplit = _defaultSai2ToolPanelSplit;
  static const double defaultSai2LayerPanelSplit = _defaultSai2LayerPanelSplit;

  static AppPreferences? _instance;
  static final ValueNotifier<bool> fpsOverlayEnabledNotifier =
      ValueNotifier<bool>(_defaultShowFpsOverlay);
  static final ValueNotifier<bool> pixelGridVisibleNotifier =
      ValueNotifier<bool>(_defaultPixelGridVisible);

  bool bucketSampleAllLayers;
  bool bucketContiguous;
  int historyLimit;
  ThemeMode themeMode;
  Locale? localeOverride;
  double penStrokeWidth;
  bool simulatePenPressure;
  StrokePressureProfile penPressureProfile;
  int penAntialiasLevel;
  bool stylusPressureEnabled;
  double stylusPressureCurve;
  bool autoSharpPeakEnabled;
  PenStrokeSliderRange penStrokeSliderRange;
  PenStrokeSliderRange sprayStrokeSliderRange;
  PenStrokeSliderRange eraserStrokeSliderRange;
  double strokeStabilizerStrength;
  double streamlineStrength;
  BrushShape brushShape;
  bool brushRandomRotationEnabled;
  bool hollowStrokeEnabled;
  double hollowStrokeRatio;
  bool hollowStrokeEraseOccludedParts;
  double sprayStrokeWidth;
  double eraserStrokeWidth;
  double liquifyStrokeWidth;
  double liquifyStrength;
  double liquifySoftness;
  double liquifyMix;
  double smudgeStrokeWidth;
  double smudgeStrength;
  double smudgeSoftness;
  SprayMode sprayMode;
  int newCanvasWidth;
  int newCanvasHeight;
  Color newCanvasBackgroundColor;
  CanvasBackend canvasBackend;
  bool layerAdjustCropOutside;
  Color colorLineColor;
  bool bucketSwallowColorLine;
  BucketSwallowColorLineMode bucketSwallowColorLineMode;
  Color primaryColor;
  bool shapeToolFillEnabled;
  int bucketTolerance;
  int bucketFillGap;
  int magicWandTolerance;
  bool brushToolsEraserMode;
  bool touchDrawingEnabled;
  int bucketAntialiasLevel;
  bool showFpsOverlay;
  bool pixelGridVisible;
  int autoSaveCleanupThresholdMb;
  WorkspaceLayoutPreference workspaceLayout;
  double? floatingColorPanelHeight;
  double? sai2ColorPanelHeight;
  double sai2ToolPanelSplit;
  double sai2LayerPanelWidthSplit;

  static AppPreferences get instance {
    final AppPreferences? current = _instance;
    if (current == null) {
      throw StateError('AppPreferences has not been loaded');
    }
    return current;
  }

  void updateShowFpsOverlay(bool value) {
    if (showFpsOverlay == value) {
      return;
    }
    showFpsOverlay = value;
    fpsOverlayEnabledNotifier.value = value;
  }

  void updatePixelGridVisible(bool value) {
    if (pixelGridVisible == value) {
      return;
    }
    pixelGridVisible = value;
    pixelGridVisibleNotifier.value = value;
  }

  static Future<AppPreferences> load() => _loadAppPreferences();

  static Future<void> save() => _saveAppPreferences();

  static ThemeMode get defaultThemeMode => _defaultThemeMode;
  static int get defaultHistoryLimit => _defaultHistoryLimit;
  static Locale? get defaultLocaleOverride => _defaultLocaleOverride;
}
