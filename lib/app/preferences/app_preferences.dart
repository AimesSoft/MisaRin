import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bitmap_canvas/stroke_dynamics.dart';
import '../../canvas/canvas_tools.dart';
import '../constants/color_line_presets.dart';
import '../constants/pen_constants.dart';
import '../models/workspace_layout.dart';

class AppPreferences {
  AppPreferences._({
    required this.bucketSampleAllLayers,
    required this.bucketContiguous,
    required this.historyLimit,
    required this.themeMode,
    required this.penStrokeWidth,
    required this.simulatePenPressure,
    required this.penPressureProfile,
    required this.penAntialiasLevel,
    required this.stylusPressureEnabled,
    required this.stylusPressureCurve,
    required this.autoSharpPeakEnabled,
    required this.penStrokeSliderRange,
    required this.strokeStabilizerStrength,
    required this.brushShape,
    required this.layerAdjustCropOutside,
    required this.colorLineColor,
    required this.bucketSwallowColorLine,
    this.primaryColor = _defaultPrimaryColor,
    this.shapeToolFillEnabled = _defaultShapeToolFillEnabled,
    this.bucketAntialiasLevel = _defaultBucketAntialiasLevel,
    this.bucketTolerance = _defaultBucketTolerance,
    this.magicWandTolerance = _defaultMagicWandTolerance,
    this.brushToolsEraserMode = _defaultBrushToolsEraserMode,
    this.vectorDrawingEnabled = _defaultVectorDrawingEnabled,
    this.showFpsOverlay = _defaultShowFpsOverlay,
    this.pixelGridVisible = _defaultPixelGridVisible,
    this.workspaceLayout = _defaultWorkspaceLayout,
    this.floatingColorPanelHeight,
    this.sai2ColorPanelHeight,
    this.sai2ToolPanelSplit = _defaultSai2ToolPanelSplit,
    this.sai2LayerPanelWidthSplit = _defaultSai2LayerPanelSplit,
    this.sprayStrokeWidth = _defaultSprayStrokeWidth,
    this.sprayMode = _defaultSprayMode,
  });

  static const String _folderName = 'MisaRin';
  static const String _fileName = 'app_preferences.rinconfig';
  static const String _preferencesStorageKey = 'misa_rin.preferences';
  static const int _version = 27;
  static const int _defaultHistoryLimit = 30;
  static const int minHistoryLimit = 5;
  static const int maxHistoryLimit = 200;
  static const ThemeMode _defaultThemeMode = ThemeMode.system;
  static const double _defaultPenStrokeWidth = 3.0;
  static const double _defaultSprayStrokeWidth = kDefaultSprayStrokeWidth;
  static const SprayMode _defaultSprayMode = SprayMode.smudge;
  static const bool _defaultSimulatePenPressure = false;
  static const StrokePressureProfile _defaultPenPressureProfile =
      StrokePressureProfile.auto;
  static const int _defaultPenAntialiasLevel = 1;
  static const bool _defaultStylusPressureEnabled = true;
  static const double _defaultStylusCurve = 0.85;
  static const bool _defaultAutoSharpPeakEnabled = false;
  static const PenStrokeSliderRange _defaultPenStrokeSliderRange =
      PenStrokeSliderRange.compact;
  static const double _defaultStrokeStabilizerStrength = 0.0;
  static const BrushShape _defaultBrushShape = BrushShape.circle;
  static const double _strokeStabilizerLowerBound = 0.0;
  static const double _strokeStabilizerUpperBound = 1.0;
  static const Color _defaultColorLineColor = kDefaultColorLineColor;
  static const Color _defaultPrimaryColor = Color(0xFF000000);
  static const bool _defaultBucketSwallowColorLine = false;
  static const int _defaultBucketTolerance = 0;
  static const int _defaultMagicWandTolerance = 0;
  static const bool _defaultBrushToolsEraserMode = false;
  static const bool _defaultVectorDrawingEnabled = true;
  static const bool _defaultShapeToolFillEnabled = false;
  static const int _defaultBucketAntialiasLevel = 0;
  static const bool _defaultShowFpsOverlay = false;
  static const bool _defaultPixelGridVisible = false;
  static const WorkspaceLayoutPreference _defaultWorkspaceLayout =
      WorkspaceLayoutPreference.floating;
  static const double _defaultSai2ToolPanelSplit = 0.5;
  static const double _defaultSai2LayerPanelSplit = 0.5;

  static const double _stylusCurveLowerBound = 0.25;
  static const double _stylusCurveUpperBound = 3.2;

  static const bool defaultStylusPressureEnabled =
      _defaultStylusPressureEnabled;
  static const double defaultStylusCurve = _defaultStylusCurve;
  static const double stylusCurveLowerBound = _stylusCurveLowerBound;
  static const double stylusCurveUpperBound = _stylusCurveUpperBound;
  static const int defaultPenAntialiasLevel = _defaultPenAntialiasLevel;
  static const bool defaultAutoSharpPeakEnabled = _defaultAutoSharpPeakEnabled;
  static const PenStrokeSliderRange defaultPenStrokeSliderRange =
      _defaultPenStrokeSliderRange;
  static const double defaultStrokeStabilizerStrength =
      _defaultStrokeStabilizerStrength;
  static const BrushShape defaultBrushShape = _defaultBrushShape;
  static const double defaultSprayStrokeWidth = _defaultSprayStrokeWidth;
  static const SprayMode defaultSprayMode = _defaultSprayMode;
  static const bool defaultLayerAdjustCropOutside = false;
  static const Color defaultColorLineColor = _defaultColorLineColor;
  static const Color defaultPrimaryColor = _defaultPrimaryColor;
  static const bool defaultBucketSwallowColorLine =
      _defaultBucketSwallowColorLine;
  static const int defaultBucketTolerance = _defaultBucketTolerance;
  static const int defaultMagicWandTolerance = _defaultMagicWandTolerance;
  static const bool defaultBrushToolsEraserMode = _defaultBrushToolsEraserMode;
  static const bool defaultVectorDrawingEnabled = _defaultVectorDrawingEnabled;
  static const bool defaultShapeToolFillEnabled = _defaultShapeToolFillEnabled;
  static const int defaultBucketAntialiasLevel = _defaultBucketAntialiasLevel;
  static const bool defaultShowFpsOverlay = _defaultShowFpsOverlay;
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
  double penStrokeWidth;
  bool simulatePenPressure;
  StrokePressureProfile penPressureProfile;
  int penAntialiasLevel;
  bool stylusPressureEnabled;
  double stylusPressureCurve;
  bool autoSharpPeakEnabled;
  PenStrokeSliderRange penStrokeSliderRange;
  double strokeStabilizerStrength;
  BrushShape brushShape;
  double sprayStrokeWidth;
  SprayMode sprayMode;
  bool layerAdjustCropOutside;
  Color colorLineColor;
  bool bucketSwallowColorLine;
  Color primaryColor;
  bool shapeToolFillEnabled;
  int bucketTolerance;
  int magicWandTolerance;
  bool brushToolsEraserMode;
  bool vectorDrawingEnabled;
  int bucketAntialiasLevel;
  bool showFpsOverlay;
  bool pixelGridVisible;
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

  static Future<AppPreferences> load() async {
    if (_instance != null) {
      return _instance!;
    }
    final Uint8List? storedBytes = await _readPreferencesPayload();
    if (storedBytes != null && storedBytes.isNotEmpty) {
      try {
        final Uint8List bytes = storedBytes;
        if (bytes.isNotEmpty) {
          final int version = bytes[0];
          final bool hasColorLinePayload = version >= 15 && bytes.length >= 20;
          final Color decodedColorLineColor = hasColorLinePayload
              ? _decodeColorLineColor(bytes[18])
              : _defaultColorLineColor;
          final bool decodedBucketSwallowColorLine = hasColorLinePayload
              ? bytes[19] != 0
              : _defaultBucketSwallowColorLine;
          if (version >= 20 && bytes.length >= 26) {
            final bool hasWorkspaceSplitPayload =
                version >= 21 && bytes.length >= 32;
            final double? decodedFloatingColorHeight = hasWorkspaceSplitPayload
                ? _decodePanelExtent(bytes[26], bytes[27])
                : null;
            final double? decodedSai2ColorHeight = hasWorkspaceSplitPayload
                ? _decodePanelExtent(bytes[28], bytes[29])
                : null;
            final double decodedSai2ToolSplit = hasWorkspaceSplitPayload
                ? _decodeRatioByte(bytes[30])
                : _defaultSai2ToolPanelSplit;
            final double decodedSai2LayerSplit = hasWorkspaceSplitPayload
                ? _decodeRatioByte(bytes[31])
                : _defaultSai2LayerPanelSplit;
            final bool decodedVectorDrawingEnabled =
                version >= 22 && bytes.length >= 33
                ? bytes[32] != 0
                : _defaultVectorDrawingEnabled;
            final bool decodedShapeToolFillEnabled =
                version >= 23 && bytes.length >= 34
                ? bytes[33] != 0
                : _defaultShapeToolFillEnabled;
            final double decodedSprayStrokeWidth =
                version >= 24 && bytes.length >= 36
                ? _decodeSprayStrokeWidth(bytes[34] | (bytes[35] << 8))
                : _defaultSprayStrokeWidth;
            if (version >= 27 && bytes.length >= 42) {
              final SprayMode decodedSprayMode = _decodeSprayMode(bytes[36]);
              final bool decodedPixelGridVisible = bytes[37] != 0;
              final int primaryColorValue =
                  bytes[38] |
                  (bytes[39] << 8) |
                  (bytes[40] << 16) |
                  (bytes[41] << 24);
              final Color decodedPrimaryColor = Color(primaryColorValue);
              final int rawHistory = bytes[3] | (bytes[4] << 8);
              final int rawStroke = bytes[6] | (bytes[7] << 8);
              _instance = AppPreferences._(
                bucketSampleAllLayers: bytes[1] != 0,
                bucketContiguous: bytes[2] != 0,
                historyLimit: _clampHistoryLimit(rawHistory),
                themeMode: _decodeThemeMode(bytes[5]),
                penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
                simulatePenPressure: bytes[8] != 0,
                penPressureProfile: _decodePressureProfile(bytes[9]),
                penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
                stylusPressureEnabled: bytes[11] != 0,
                stylusPressureCurve: _decodeStylusFactor(
                  bytes[12],
                  lower: _stylusCurveLowerBound,
                  upper: _stylusCurveUpperBound,
                ),
                autoSharpPeakEnabled: bytes[13] != 0,
                penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
                strokeStabilizerStrength: _decodeStrokeStabilizerStrength(
                  bytes[15],
                ),
                brushShape: _decodeBrushShape(bytes[16]),
                layerAdjustCropOutside: bytes[17] != 0,
                colorLineColor: decodedColorLineColor,
                bucketSwallowColorLine: decodedBucketSwallowColorLine,
                shapeToolFillEnabled: decodedShapeToolFillEnabled,
                bucketTolerance: _clampToleranceValue(bytes[20]),
                magicWandTolerance: _clampToleranceValue(bytes[21]),
                brushToolsEraserMode: bytes[22] != 0,
                bucketAntialiasLevel: _decodeAntialiasLevel(bytes[23]),
                vectorDrawingEnabled: decodedVectorDrawingEnabled,
                showFpsOverlay: bytes[24] != 0,
                workspaceLayout: _decodeWorkspaceLayoutPreference(bytes[25]),
                floatingColorPanelHeight: decodedFloatingColorHeight,
                sai2ColorPanelHeight: decodedSai2ColorHeight,
                sai2ToolPanelSplit: decodedSai2ToolSplit,
                sai2LayerPanelWidthSplit: decodedSai2LayerSplit,
                sprayStrokeWidth: decodedSprayStrokeWidth,
                sprayMode: decodedSprayMode,
                pixelGridVisible: decodedPixelGridVisible,
                primaryColor: decodedPrimaryColor,
              );
              return _finalizeLoadedPreferences();
            } else if (version >= 26 && bytes.length >= 38) {
              final SprayMode decodedSprayMode = _decodeSprayMode(bytes[36]);
              final bool decodedPixelGridVisible = bytes[37] != 0;
              final int rawHistory = bytes[3] | (bytes[4] << 8);
              final int rawStroke = bytes[6] | (bytes[7] << 8);
              _instance = AppPreferences._(
                bucketSampleAllLayers: bytes[1] != 0,
                bucketContiguous: bytes[2] != 0,
                historyLimit: _clampHistoryLimit(rawHistory),
                themeMode: _decodeThemeMode(bytes[5]),
                penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
                simulatePenPressure: bytes[8] != 0,
                penPressureProfile: _decodePressureProfile(bytes[9]),
                penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
                stylusPressureEnabled: bytes[11] != 0,
                stylusPressureCurve: _decodeStylusFactor(
                  bytes[12],
                  lower: _stylusCurveLowerBound,
                  upper: _stylusCurveUpperBound,
                ),
                autoSharpPeakEnabled: bytes[13] != 0,
                penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
                strokeStabilizerStrength: _decodeStrokeStabilizerStrength(
                  bytes[15],
                ),
                brushShape: _decodeBrushShape(bytes[16]),
                layerAdjustCropOutside: bytes[17] != 0,
                colorLineColor: decodedColorLineColor,
                bucketSwallowColorLine: decodedBucketSwallowColorLine,
                shapeToolFillEnabled: decodedShapeToolFillEnabled,
                bucketTolerance: _clampToleranceValue(bytes[20]),
                magicWandTolerance: _clampToleranceValue(bytes[21]),
                brushToolsEraserMode: bytes[22] != 0,
                bucketAntialiasLevel: _decodeAntialiasLevel(bytes[23]),
                vectorDrawingEnabled: decodedVectorDrawingEnabled,
                showFpsOverlay: bytes[24] != 0,
                workspaceLayout: _decodeWorkspaceLayoutPreference(bytes[25]),
                floatingColorPanelHeight: decodedFloatingColorHeight,
                sai2ColorPanelHeight: decodedSai2ColorHeight,
                sai2ToolPanelSplit: decodedSai2ToolSplit,
                sai2LayerPanelWidthSplit: decodedSai2LayerSplit,
                sprayStrokeWidth: decodedSprayStrokeWidth,
                sprayMode: decodedSprayMode,
                pixelGridVisible: decodedPixelGridVisible,
              );
              return _finalizeLoadedPreferences();
            } else if (version >= 25 && bytes.length >= 37) {
              final SprayMode decodedSprayMode = _decodeSprayMode(bytes[36]);
              final int rawHistory = bytes[3] | (bytes[4] << 8);
              final int rawStroke = bytes[6] | (bytes[7] << 8);
              _instance = AppPreferences._(
                bucketSampleAllLayers: bytes[1] != 0,
                bucketContiguous: bytes[2] != 0,
                historyLimit: _clampHistoryLimit(rawHistory),
                themeMode: _decodeThemeMode(bytes[5]),
                penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
                simulatePenPressure: bytes[8] != 0,
                penPressureProfile: _decodePressureProfile(bytes[9]),
                penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
                stylusPressureEnabled: bytes[11] != 0,
                stylusPressureCurve: _decodeStylusFactor(
                  bytes[12],
                  lower: _stylusCurveLowerBound,
                  upper: _stylusCurveUpperBound,
                ),
                autoSharpPeakEnabled: bytes[13] != 0,
                penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
                strokeStabilizerStrength: _decodeStrokeStabilizerStrength(
                  bytes[15],
                ),
                brushShape: _decodeBrushShape(bytes[16]),
                layerAdjustCropOutside: bytes[17] != 0,
                colorLineColor: decodedColorLineColor,
                bucketSwallowColorLine: decodedBucketSwallowColorLine,
                shapeToolFillEnabled: decodedShapeToolFillEnabled,
                bucketTolerance: _clampToleranceValue(bytes[20]),
                magicWandTolerance: _clampToleranceValue(bytes[21]),
                brushToolsEraserMode: bytes[22] != 0,
                bucketAntialiasLevel: _decodeAntialiasLevel(bytes[23]),
                vectorDrawingEnabled: decodedVectorDrawingEnabled,
                showFpsOverlay: bytes[24] != 0,
                workspaceLayout: _decodeWorkspaceLayoutPreference(bytes[25]),
                floatingColorPanelHeight: decodedFloatingColorHeight,
                sai2ColorPanelHeight: decodedSai2ColorHeight,
                sai2ToolPanelSplit: decodedSai2ToolSplit,
                sai2LayerPanelWidthSplit: decodedSai2LayerSplit,
                sprayStrokeWidth: decodedSprayStrokeWidth,
                sprayMode: decodedSprayMode,
              );
              return _finalizeLoadedPreferences();
            }
            if (version >= 24 && bytes.length >= 36) {
              final int rawHistory = bytes[3] | (bytes[4] << 8);
              final int rawStroke = bytes[6] | (bytes[7] << 8);
              _instance = AppPreferences._(
                bucketSampleAllLayers: bytes[1] != 0,
                bucketContiguous: bytes[2] != 0,
                historyLimit: _clampHistoryLimit(rawHistory),
                themeMode: _decodeThemeMode(bytes[5]),
                penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
                simulatePenPressure: bytes[8] != 0,
                penPressureProfile: _decodePressureProfile(bytes[9]),
                penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
                stylusPressureEnabled: bytes[11] != 0,
                stylusPressureCurve: _decodeStylusFactor(
                  bytes[12],
                  lower: _stylusCurveLowerBound,
                  upper: _stylusCurveUpperBound,
                ),
                autoSharpPeakEnabled: bytes[13] != 0,
                penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
                strokeStabilizerStrength: _decodeStrokeStabilizerStrength(
                  bytes[15],
                ),
                brushShape: _decodeBrushShape(bytes[16]),
                layerAdjustCropOutside: bytes[17] != 0,
                colorLineColor: decodedColorLineColor,
                bucketSwallowColorLine: decodedBucketSwallowColorLine,
                shapeToolFillEnabled: decodedShapeToolFillEnabled,
                bucketTolerance: _clampToleranceValue(bytes[20]),
                magicWandTolerance: _clampToleranceValue(bytes[21]),
                brushToolsEraserMode: bytes[22] != 0,
                bucketAntialiasLevel: _decodeAntialiasLevel(bytes[23]),
                vectorDrawingEnabled: decodedVectorDrawingEnabled,
                showFpsOverlay: bytes[24] != 0,
                workspaceLayout: _decodeWorkspaceLayoutPreference(bytes[25]),
                floatingColorPanelHeight: decodedFloatingColorHeight,
                sai2ColorPanelHeight: decodedSai2ColorHeight,
                sai2ToolPanelSplit: decodedSai2ToolSplit,
                sai2LayerPanelWidthSplit: decodedSai2LayerSplit,
                sprayStrokeWidth: decodedSprayStrokeWidth,
              );
              return _finalizeLoadedPreferences();
            }
          }
          if (version >= 19 && bytes.length >= 25) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
              simulatePenPressure: bytes[8] != 0,
              penPressureProfile: _decodePressureProfile(bytes[9]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
              stylusPressureEnabled: bytes[11] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[12],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: bytes[13] != 0,
              penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
              strokeStabilizerStrength: _decodeStrokeStabilizerStrength(
                bytes[15],
              ),
              brushShape: _decodeBrushShape(bytes[16]),
              layerAdjustCropOutside: bytes[17] != 0,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
              bucketTolerance: _clampToleranceValue(bytes[20]),
              magicWandTolerance: _clampToleranceValue(bytes[21]),
              brushToolsEraserMode: bytes[22] != 0,
              bucketAntialiasLevel: _decodeAntialiasLevel(bytes[23]),
              showFpsOverlay: bytes[24] != 0,
              floatingColorPanelHeight: null,
              sai2ColorPanelHeight: null,
              sai2ToolPanelSplit: _defaultSai2ToolPanelSplit,
              sai2LayerPanelWidthSplit: _defaultSai2LayerPanelSplit,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 18 && bytes.length >= 24) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
              simulatePenPressure: bytes[8] != 0,
              penPressureProfile: _decodePressureProfile(bytes[9]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
              stylusPressureEnabled: bytes[11] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[12],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: bytes[13] != 0,
              penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
              strokeStabilizerStrength: _decodeStrokeStabilizerStrength(
                bytes[15],
              ),
              brushShape: _decodeBrushShape(bytes[16]),
              layerAdjustCropOutside: bytes[17] != 0,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
              bucketTolerance: _clampToleranceValue(bytes[20]),
              magicWandTolerance: _clampToleranceValue(bytes[21]),
              brushToolsEraserMode: bytes[22] != 0,
              bucketAntialiasLevel: _decodeAntialiasLevel(bytes[23]),
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 17 && bytes.length >= 23) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
              simulatePenPressure: bytes[8] != 0,
              penPressureProfile: _decodePressureProfile(bytes[9]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
              stylusPressureEnabled: bytes[11] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[12],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: bytes[13] != 0,
              penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
              strokeStabilizerStrength: _decodeStrokeStabilizerStrength(
                bytes[15],
              ),
              brushShape: _decodeBrushShape(bytes[16]),
              layerAdjustCropOutside: bytes[17] != 0,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
              bucketTolerance: _clampToleranceValue(bytes[20]),
              magicWandTolerance: _clampToleranceValue(bytes[21]),
              brushToolsEraserMode: bytes[22] != 0,
              bucketAntialiasLevel: _defaultBucketAntialiasLevel,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 16 && bytes.length >= 25) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            final bool penEraserMode = bytes[22] != 0;
            final bool curveEraserMode = bytes[23] != 0;
            final bool shapeEraserMode = bytes[24] != 0;
            final bool sharedEraserMode = penEraserMode
                ? penEraserMode
                : (curveEraserMode ? curveEraserMode : shapeEraserMode);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
              simulatePenPressure: bytes[8] != 0,
              penPressureProfile: _decodePressureProfile(bytes[9]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
              stylusPressureEnabled: bytes[11] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[12],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: bytes[13] != 0,
              penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
              strokeStabilizerStrength: _decodeStrokeStabilizerStrength(
                bytes[15],
              ),
              brushShape: _decodeBrushShape(bytes[16]),
              layerAdjustCropOutside: bytes[17] != 0,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
              bucketTolerance: _clampToleranceValue(bytes[20]),
              magicWandTolerance: _clampToleranceValue(bytes[21]),
              brushToolsEraserMode: sharedEraserMode,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 15 && bytes.length >= 20) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
              simulatePenPressure: bytes[8] != 0,
              penPressureProfile: _decodePressureProfile(bytes[9]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
              stylusPressureEnabled: bytes[11] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[12],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: bytes[13] != 0,
              penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
              strokeStabilizerStrength: _decodeStrokeStabilizerStrength(
                bytes[15],
              ),
              brushShape: _decodeBrushShape(bytes[16]),
              layerAdjustCropOutside: bytes[17] != 0,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 14 && bytes.length >= 18) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
              simulatePenPressure: bytes[8] != 0,
              penPressureProfile: _decodePressureProfile(bytes[9]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
              stylusPressureEnabled: bytes[11] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[12],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: bytes[13] != 0,
              penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
              strokeStabilizerStrength: _decodeStrokeStabilizerStrength(
                bytes[15],
              ),
              brushShape: _decodeBrushShape(bytes[16]),
              layerAdjustCropOutside: bytes[17] != 0,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 13 && bytes.length >= 17) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
              simulatePenPressure: bytes[8] != 0,
              penPressureProfile: _decodePressureProfile(bytes[9]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
              stylusPressureEnabled: bytes[11] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[12],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: bytes[13] != 0,
              penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
              strokeStabilizerStrength: _decodeStrokeStabilizerStrength(
                bytes[15],
              ),
              brushShape: _decodeBrushShape(bytes[16]),
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 12 && bytes.length >= 16) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
              simulatePenPressure: bytes[8] != 0,
              penPressureProfile: _decodePressureProfile(bytes[9]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
              stylusPressureEnabled: bytes[11] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[12],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: bytes[13] != 0,
              penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
              strokeStabilizerStrength: _decodeStrokeStabilizerStrength(
                bytes[15],
              ),
              brushShape: _defaultBrushShape,
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 11 && bytes.length >= 15) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
              simulatePenPressure: bytes[8] != 0,
              penPressureProfile: _decodePressureProfile(bytes[9]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
              stylusPressureEnabled: bytes[11] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[12],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: bytes[13] != 0,
              penStrokeSliderRange: _decodePenStrokeSliderRange(bytes[14]),
              strokeStabilizerStrength: _defaultStrokeStabilizerStrength,
              brushShape: _defaultBrushShape,
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 10 && bytes.length >= 14) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthV10(rawStroke),
              simulatePenPressure: bytes[8] != 0,
              penPressureProfile: _decodePressureProfile(bytes[9]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[10]),
              stylusPressureEnabled: bytes[11] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[12],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: bytes[13] != 0,
              penStrokeSliderRange: _defaultPenStrokeSliderRange,
              strokeStabilizerStrength: _defaultStrokeStabilizerStrength,
              brushShape: _defaultBrushShape,
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 9 && bytes.length >= 13) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthLegacy(bytes[6]),
              simulatePenPressure: bytes[7] != 0,
              penPressureProfile: _decodePressureProfile(bytes[8]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[9]),
              stylusPressureEnabled: bytes[10] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[11],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: bytes[12] != 0,
              penStrokeSliderRange: _defaultPenStrokeSliderRange,
              strokeStabilizerStrength: _defaultStrokeStabilizerStrength,
              brushShape: _defaultBrushShape,
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 8 && bytes.length >= 12) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthLegacy(bytes[6]),
              simulatePenPressure: bytes[7] != 0,
              penPressureProfile: _decodePressureProfile(bytes[8]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[9]),
              stylusPressureEnabled: bytes[10] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[11],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: _defaultAutoSharpPeakEnabled,
              penStrokeSliderRange: _defaultPenStrokeSliderRange,
              strokeStabilizerStrength: _defaultStrokeStabilizerStrength,
              brushShape: _defaultBrushShape,
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 7 && bytes.length >= 14) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthLegacy(bytes[6]),
              simulatePenPressure: bytes[7] != 0,
              penPressureProfile: _decodePressureProfile(bytes[8]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[9]),
              stylusPressureEnabled: bytes[10] != 0,
              stylusPressureCurve: _decodeStylusFactor(
                bytes[13],
                lower: _stylusCurveLowerBound,
                upper: _stylusCurveUpperBound,
              ),
              autoSharpPeakEnabled: _defaultAutoSharpPeakEnabled,
              penStrokeSliderRange: _defaultPenStrokeSliderRange,
              strokeStabilizerStrength: _defaultStrokeStabilizerStrength,
              brushShape: _defaultBrushShape,
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 6 && bytes.length >= 10) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthLegacy(bytes[6]),
              simulatePenPressure: bytes[7] != 0,
              penPressureProfile: _decodePressureProfile(bytes[8]),
              penAntialiasLevel: _decodeAntialiasLevel(bytes[9]),
              stylusPressureEnabled: _defaultStylusPressureEnabled,
              stylusPressureCurve: _defaultStylusCurve,
              autoSharpPeakEnabled: _defaultAutoSharpPeakEnabled,
              penStrokeSliderRange: _defaultPenStrokeSliderRange,
              strokeStabilizerStrength: _defaultStrokeStabilizerStrength,
              brushShape: _defaultBrushShape,
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version == 5 && bytes.length >= 10) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthLegacy(bytes[6]),
              simulatePenPressure: bytes[7] != 0,
              penPressureProfile: _decodePressureProfile(bytes[8]),
              penAntialiasLevel: bytes[9] != 0 ? 2 : 0,
              stylusPressureEnabled: _defaultStylusPressureEnabled,
              stylusPressureCurve: _defaultStylusCurve,
              autoSharpPeakEnabled: _defaultAutoSharpPeakEnabled,
              penStrokeSliderRange: _defaultPenStrokeSliderRange,
              strokeStabilizerStrength: _defaultStrokeStabilizerStrength,
              brushShape: _defaultBrushShape,
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version == 4 && bytes.length >= 9) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _decodePenStrokeWidthLegacy(bytes[6]),
              simulatePenPressure: bytes[7] != 0,
              penPressureProfile: _decodePressureProfile(bytes[8]),
              penAntialiasLevel: _defaultPenAntialiasLevel,
              stylusPressureEnabled: _defaultStylusPressureEnabled,
              stylusPressureCurve: _defaultStylusCurve,
              autoSharpPeakEnabled: _defaultAutoSharpPeakEnabled,
              penStrokeSliderRange: _defaultPenStrokeSliderRange,
              strokeStabilizerStrength: _defaultStrokeStabilizerStrength,
              brushShape: _defaultBrushShape,
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version == 3 && bytes.length >= 6) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: _defaultPenStrokeWidth,
              simulatePenPressure: _defaultSimulatePenPressure,
              penPressureProfile: _defaultPenPressureProfile,
              penAntialiasLevel: _defaultPenAntialiasLevel,
              stylusPressureEnabled: _defaultStylusPressureEnabled,
              stylusPressureCurve: _defaultStylusCurve,
              autoSharpPeakEnabled: _defaultAutoSharpPeakEnabled,
              penStrokeSliderRange: _defaultPenStrokeSliderRange,
              strokeStabilizerStrength: _defaultStrokeStabilizerStrength,
              brushShape: _defaultBrushShape,
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
            );
            return _finalizeLoadedPreferences();
          }
          if (version == 2 && bytes.length >= 5) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _defaultThemeMode,
              penStrokeWidth: _defaultPenStrokeWidth,
              simulatePenPressure: _defaultSimulatePenPressure,
              penPressureProfile: _defaultPenPressureProfile,
              penAntialiasLevel: _defaultPenAntialiasLevel,
              stylusPressureEnabled: _defaultStylusPressureEnabled,
              stylusPressureCurve: _defaultStylusCurve,
              autoSharpPeakEnabled: _defaultAutoSharpPeakEnabled,
              penStrokeSliderRange: _defaultPenStrokeSliderRange,
              strokeStabilizerStrength: _defaultStrokeStabilizerStrength,
              brushShape: _defaultBrushShape,
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
              floatingColorPanelHeight: null,
              sai2ColorPanelHeight: null,
              sai2ToolPanelSplit: _defaultSai2ToolPanelSplit,
              sai2LayerPanelWidthSplit: _defaultSai2LayerPanelSplit,
            );
            return _finalizeLoadedPreferences();
          }
          if (version == 1 && bytes.length >= 3) {
            _instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _defaultHistoryLimit,
              themeMode: _defaultThemeMode,
              penStrokeWidth: _defaultPenStrokeWidth,
              simulatePenPressure: _defaultSimulatePenPressure,
              penPressureProfile: _defaultPenPressureProfile,
              penAntialiasLevel: _defaultPenAntialiasLevel,
              stylusPressureEnabled: _defaultStylusPressureEnabled,
              stylusPressureCurve: _defaultStylusCurve,
              autoSharpPeakEnabled: _defaultAutoSharpPeakEnabled,
              penStrokeSliderRange: _defaultPenStrokeSliderRange,
              strokeStabilizerStrength: _defaultStrokeStabilizerStrength,
              brushShape: _defaultBrushShape,
              layerAdjustCropOutside: false,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
              floatingColorPanelHeight: null,
              sai2ColorPanelHeight: null,
              sai2ToolPanelSplit: _defaultSai2ToolPanelSplit,
              sai2LayerPanelWidthSplit: _defaultSai2LayerPanelSplit,
            );
            return _finalizeLoadedPreferences();
          }
        }
      } catch (_) {
        // Ignore corrupted preference files and fall back to defaults.
      }
    }
    _instance = AppPreferences._(
      bucketSampleAllLayers: false,
      bucketContiguous: true,
      historyLimit: _defaultHistoryLimit,
      themeMode: _defaultThemeMode,
      penStrokeWidth: _defaultPenStrokeWidth,
      simulatePenPressure: _defaultSimulatePenPressure,
      penPressureProfile: _defaultPenPressureProfile,
      penAntialiasLevel: _defaultPenAntialiasLevel,
      stylusPressureEnabled: _defaultStylusPressureEnabled,
      stylusPressureCurve: _defaultStylusCurve,
      autoSharpPeakEnabled: _defaultAutoSharpPeakEnabled,
      penStrokeSliderRange: _defaultPenStrokeSliderRange,
      strokeStabilizerStrength: _defaultStrokeStabilizerStrength,
      brushShape: _defaultBrushShape,
      layerAdjustCropOutside: false,
      colorLineColor: _defaultColorLineColor,
      bucketSwallowColorLine: _defaultBucketSwallowColorLine,
      vectorDrawingEnabled: _defaultVectorDrawingEnabled,
      workspaceLayout: _defaultWorkspaceLayout,
      floatingColorPanelHeight: null,
      sai2ColorPanelHeight: null,
      sai2ToolPanelSplit: _defaultSai2ToolPanelSplit,
      sai2LayerPanelWidthSplit: _defaultSai2LayerPanelSplit,
    );
    return _finalizeLoadedPreferences();
  }

  static AppPreferences _finalizeLoadedPreferences() {
    final AppPreferences prefs = _instance!;
    fpsOverlayEnabledNotifier.value = prefs.showFpsOverlay;
    pixelGridVisibleNotifier.value = prefs.pixelGridVisible;
    return prefs;
  }

  static Future<void> save() async {
    final AppPreferences prefs = _instance ?? await load();
    final int history = _clampHistoryLimit(prefs.historyLimit);
    prefs.historyLimit = history;
    final double strokeWidthValue = prefs.penStrokeWidth.clamp(
      kPenStrokeMin,
      kPenStrokeMax,
    );
    prefs.penStrokeWidth = strokeWidthValue;
    final int strokeWidth = _encodePenStrokeWidth(strokeWidthValue);
    final double sprayWidthValue = _clampSprayStrokeWidth(
      prefs.sprayStrokeWidth,
    );
    prefs.sprayStrokeWidth = sprayWidthValue;
    final int sprayWidth = _encodeSprayStrokeWidth(sprayWidthValue);
    final double stylusCurve = _clampStylusFactor(
      prefs.stylusPressureCurve,
      lower: _stylusCurveLowerBound,
      upper: _stylusCurveUpperBound,
    );

    prefs.stylusPressureCurve = stylusCurve;
    prefs.strokeStabilizerStrength = _clampStrokeStabilizerStrength(
      prefs.strokeStabilizerStrength,
    );

    final int stylusCurveEncoded = _encodeStylusFactor(
      stylusCurve,
      lower: _stylusCurveLowerBound,
      upper: _stylusCurveUpperBound,
    );
    final int sliderRangeEncoded = _encodePenStrokeSliderRange(
      prefs.penStrokeSliderRange,
    );
    final int stabilizerEncoded = _encodeStrokeStabilizerStrength(
      prefs.strokeStabilizerStrength,
    );
    final int colorLineEncoded = _encodeColorLineColor(prefs.colorLineColor);
    final int floatingColorEncoded = _encodePanelExtent(
      prefs.floatingColorPanelHeight,
    );
    final int sai2ColorEncoded = _encodePanelExtent(prefs.sai2ColorPanelHeight);
    final int sai2ToolSplitEncoded = _encodeRatioByte(prefs.sai2ToolPanelSplit);
    final int sai2LayerSplitEncoded = _encodeRatioByte(
      prefs.sai2LayerPanelWidthSplit,
    );
    final int primaryColorValue = prefs.primaryColor.value;

    final Uint8List payload = Uint8List.fromList(<int>[
      _version,
      prefs.bucketSampleAllLayers ? 1 : 0,
      prefs.bucketContiguous ? 1 : 0,
      history & 0xff,
      (history >> 8) & 0xff,
      _encodeThemeMode(prefs.themeMode),
      strokeWidth & 0xff,
      (strokeWidth >> 8) & 0xff,
      prefs.simulatePenPressure ? 1 : 0,
      _encodePressureProfile(prefs.penPressureProfile),
      _encodeAntialiasLevel(prefs.penAntialiasLevel),
      prefs.stylusPressureEnabled ? 1 : 0,
      stylusCurveEncoded,
      prefs.autoSharpPeakEnabled ? 1 : 0,
      sliderRangeEncoded,
      stabilizerEncoded,
      _encodeBrushShape(prefs.brushShape),
      prefs.layerAdjustCropOutside ? 1 : 0,
      colorLineEncoded,
      prefs.bucketSwallowColorLine ? 1 : 0,
      _clampToleranceValue(prefs.bucketTolerance),
      _clampToleranceValue(prefs.magicWandTolerance),
      prefs.brushToolsEraserMode ? 1 : 0,
      _encodeAntialiasLevel(prefs.bucketAntialiasLevel),
      prefs.showFpsOverlay ? 1 : 0,
      _encodeWorkspaceLayoutPreference(prefs.workspaceLayout),
      floatingColorEncoded & 0xff,
      (floatingColorEncoded >> 8) & 0xff,
      sai2ColorEncoded & 0xff,
      (sai2ColorEncoded >> 8) & 0xff,
      sai2ToolSplitEncoded,
      sai2LayerSplitEncoded,
      prefs.vectorDrawingEnabled ? 1 : 0,
      prefs.shapeToolFillEnabled ? 1 : 0,
      sprayWidth & 0xff,
      (sprayWidth >> 8) & 0xff,
      _encodeSprayMode(prefs.sprayMode),
      prefs.pixelGridVisible ? 1 : 0,
      primaryColorValue & 0xff,
      (primaryColorValue >> 8) & 0xff,
      (primaryColorValue >> 16) & 0xff,
      (primaryColorValue >> 24) & 0xff,
    ]);
    await _writePreferencesPayload(payload);
  }

  static int _clampHistoryLimit(int value) {
    if (value < minHistoryLimit) {
      return minHistoryLimit;
    }
    if (value > maxHistoryLimit) {
      return maxHistoryLimit;
    }
    return value;
  }

  static int _clampToleranceValue(int value) {
    return value.clamp(0, 255).toInt();
  }

  static ThemeMode _decodeThemeMode(int value) {
    switch (value) {
      case 0:
        return ThemeMode.light;
      case 1:
        return ThemeMode.dark;
      case 2:
      default:
        return ThemeMode.system;
    }
  }

  static int _encodeThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 0;
      case ThemeMode.dark:
        return 1;
      case ThemeMode.system:
      default:
        return 2;
    }
  }

  static Color _decodeColorLineColor(int value) {
    if (value >= 0 && value < kColorLinePresets.length) {
      return kColorLinePresets[value];
    }
    return _defaultColorLineColor;
  }

  static int _encodeColorLineColor(Color color) {
    final int index = kColorLinePresets.indexWhere(
      (candidate) => candidate.value == color.value,
    );
    return index >= 0 ? index : 0;
  }

  static WorkspaceLayoutPreference _decodeWorkspaceLayoutPreference(int value) {
    switch (value) {
      case 1:
        return WorkspaceLayoutPreference.sai2;
      case 0:
      default:
        return WorkspaceLayoutPreference.floating;
    }
  }

  static int _encodeWorkspaceLayoutPreference(WorkspaceLayoutPreference value) {
    switch (value) {
      case WorkspaceLayoutPreference.sai2:
        return 1;
      case WorkspaceLayoutPreference.floating:
      default:
        return 0;
    }
  }

  static SprayMode _decodeSprayMode(int value) {
    switch (value) {
      case 1:
        return SprayMode.splatter;
      case 0:
      default:
        return SprayMode.smudge;
    }
  }

  static int _encodeSprayMode(SprayMode mode) {
    switch (mode) {
      case SprayMode.splatter:
        return 1;
      case SprayMode.smudge:
      default:
        return 0;
    }
  }

  static double? _decodePanelExtent(int low, int high) {
    final int raw = (low & 0xff) | ((high & 0xff) << 8);
    if (raw <= 0) {
      return null;
    }
    return raw.toDouble();
  }

  static int _encodePanelExtent(double? value) {
    if (value == null || value.isNaN || value <= 0) {
      return 0;
    }
    final double clamped = value.clamp(0.0, 65535.0);
    return clamped.round().clamp(0, 0xFFFF);
  }

  static double _decodeRatioByte(int value) {
    final int clamped = value.clamp(0, 255);
    return clamped / 255.0;
  }

  static int _encodeRatioByte(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    return (clamped * 255).round().clamp(0, 255);
  }

  static double _decodePenStrokeWidthLegacy(int value) {
    final double clamped = value.clamp(1, 60).toDouble();
    return clamped.clamp(kPenStrokeMin, kPenStrokeMax);
  }

  static double _decodePenStrokeWidthV10(int value) {
    final int clamped = value.clamp(0, 0xffff);
    if (clamped <= 0) {
      return kPenStrokeMin;
    }
    if (clamped >= 0xffff) {
      return kPenStrokeMax;
    }
    final double t = clamped / 65535.0;
    final double ratio = kPenStrokeMax / kPenStrokeMin;
    return kPenStrokeMin * math.pow(ratio, t);
  }

  static int _encodePenStrokeWidth(double value) {
    final double clamped = value.clamp(kPenStrokeMin, kPenStrokeMax);
    if (clamped <= kPenStrokeMin) {
      return 0;
    }
    if (clamped >= kPenStrokeMax) {
      return 0xffff;
    }
    final double numerator = math.log(clamped / kPenStrokeMin);
    final double denominator = math.log(kPenStrokeMax / kPenStrokeMin);
    final double normalized = denominator == 0
        ? 0.0
        : (numerator / denominator);
    return (normalized * 65535.0).round().clamp(0, 0xffff);
  }

  static double _clampSprayStrokeWidth(double value) {
    if (!value.isFinite) {
      return _defaultSprayStrokeWidth;
    }
    return value.clamp(kSprayStrokeMin, kSprayStrokeMax);
  }

  static double _decodeSprayStrokeWidth(int value) {
    final int resolved = value.clamp(
      kSprayStrokeMin.round(),
      kSprayStrokeMax.round(),
    );
    return resolved.toDouble();
  }

  static int _encodeSprayStrokeWidth(double value) {
    final double clamped = _clampSprayStrokeWidth(value);
    return clamped.round().clamp(
      kSprayStrokeMin.round(),
      kSprayStrokeMax.round(),
    );
  }

  static double _decodeStylusFactor(
    int value, {
    required double lower,
    required double upper,
  }) {
    final double clamped = value.clamp(0, 255).toDouble();
    final double t = clamped / 255.0;
    return lower + (upper - lower) * t;
  }

  static int _encodeStylusFactor(
    double value, {
    required double lower,
    required double upper,
  }) {
    final double clamped = value.clamp(lower, upper);
    if (upper <= lower) {
      return 0;
    }
    final double normalized = (clamped - lower) / (upper - lower);
    return (normalized * 255.0).round().clamp(0, 255);
  }

  static double _clampStylusFactor(
    double value, {
    required double lower,
    required double upper,
  }) {
    final double clamped = value.clamp(lower, upper);
    if (!clamped.isFinite) {
      return lower;
    }
    return clamped;
  }

  static StrokePressureProfile _decodePressureProfile(int value) {
    switch (value) {
      case 0:
        return StrokePressureProfile.taperEnds;
      case 1:
        return StrokePressureProfile.taperCenter;
      case 2:
      default:
        return StrokePressureProfile.auto;
    }
  }

  static int _encodePressureProfile(StrokePressureProfile profile) {
    switch (profile) {
      case StrokePressureProfile.taperEnds:
        return 0;
      case StrokePressureProfile.taperCenter:
        return 1;
      case StrokePressureProfile.auto:
        return 2;
    }
  }

  static int _decodeAntialiasLevel(int value) {
    if (value < 0) {
      return 0;
    }
    if (value > 3) {
      return 3;
    }
    return value;
  }

  static int _encodeAntialiasLevel(int value) {
    if (value < 0) {
      return 0;
    }
    if (value > 3) {
      return 3;
    }
    return value;
  }

  static PenStrokeSliderRange _decodePenStrokeSliderRange(int value) {
    switch (value) {
      case 0:
        return PenStrokeSliderRange.compact;
      case 1:
        return PenStrokeSliderRange.medium;
      case 2:
      default:
        return PenStrokeSliderRange.full;
    }
  }

  static int _encodePenStrokeSliderRange(PenStrokeSliderRange range) {
    switch (range) {
      case PenStrokeSliderRange.compact:
        return 0;
      case PenStrokeSliderRange.medium:
        return 1;
      case PenStrokeSliderRange.full:
      default:
        return 2;
    }
  }

  static double _decodeStrokeStabilizerStrength(int value) {
    final int clamped = value.clamp(0, 255);
    return clamped / 255.0;
  }

  static int _encodeStrokeStabilizerStrength(double value) {
    final double clamped = _clampStrokeStabilizerStrength(value);
    return (clamped * 255.0).round().clamp(0, 255);
  }

  static BrushShape _decodeBrushShape(int value) {
    switch (value) {
      case 1:
        return BrushShape.triangle;
      case 2:
        return BrushShape.square;
      case 0:
      default:
        return BrushShape.circle;
    }
  }

  static int _encodeBrushShape(BrushShape shape) {
    switch (shape) {
      case BrushShape.circle:
        return 0;
      case BrushShape.triangle:
        return 1;
      case BrushShape.square:
        return 2;
    }
  }

  static double _clampStrokeStabilizerStrength(double value) {
    if (!value.isFinite) {
      return _defaultStrokeStabilizerStrength;
    }
    return value.clamp(
      _strokeStabilizerLowerBound,
      _strokeStabilizerUpperBound,
    );
  }

  static ThemeMode get defaultThemeMode => _defaultThemeMode;
  static int get defaultHistoryLimit => _defaultHistoryLimit;

  static Future<Uint8List?> _readPreferencesPayload() async {
    if (kIsWeb) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? encoded = prefs.getString(_preferencesStorageKey);
      if (encoded == null || encoded.isEmpty) {
        return null;
      }
      try {
        return Uint8List.fromList(base64Decode(encoded));
      } catch (_) {
        return null;
      }
    }
    final File file = await _preferencesFile();
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  static Future<void> _writePreferencesPayload(Uint8List bytes) async {
    if (kIsWeb) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferencesStorageKey, base64Encode(bytes));
      return;
    }
    final File file = await _preferencesFile();
    await file.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  static Future<File> _preferencesFile() async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Preferences file storage is not available on web',
      );
    }
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(p.join(base.path, _folderName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, _fileName));
  }
}

enum PenStrokeSliderRange {
  compact(min: 1.0, max: 60.0),
  medium(min: 0.1, max: 500.0),
  full(min: 0.01, max: 1000.0);

  const PenStrokeSliderRange({required this.min, required this.max});

  final double min;
  final double max;

  double clamp(double value) {
    final num clamped = value.clamp(min, max);
    return clamped.toDouble();
  }
}
