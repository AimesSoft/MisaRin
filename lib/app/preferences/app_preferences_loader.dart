part of 'app_preferences.dart';

Future<AppPreferences> _loadAppPreferences() async {
  if (AppPreferences._instance != null) {
    return AppPreferences._instance!;
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
        final BucketSwallowColorLineMode decodedBucketSwallowColorLineMode =
            version >= 33 && bytes.length >= 49
            ? _decodeBucketSwallowColorLineMode(bytes[48])
            : _defaultBucketSwallowColorLineMode;
        final int decodedBucketFillGap = version >= 34 && bytes.length >= 50
            ? _clampFillGapValue(bytes[49])
            : _defaultBucketFillGap;
        final bool decodedBrushRandomRotationEnabled =
            version >= 35 && bytes.length >= 51
            ? bytes[50] != 0
            : _defaultBrushRandomRotationEnabled;
        final double decodedStreamlineStrength =
            version >= 38 && bytes.length >= 52
            ? _decodeStreamlineStrength(bytes[51])
            : _defaultStreamlineStrength;
        final CanvasBackend decodedCanvasBackend =
            version >= 40 && bytes.length >= 53
            ? _decodeCanvasBackend(bytes[52])
            : _defaultCanvasBackend;
        final int decodedAutoSaveCleanupThresholdMb =
            version >= 41 && bytes.length >= 63
            ? _clampAutoSaveCleanupThresholdMb(bytes[61] | (bytes[62] << 8))
            : _defaultAutoSaveCleanupThresholdMb;
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
          final PenStrokeSliderRange decodedSprayStrokeSliderRange =
              version >= 28 && bytes.length >= 35
              ? _decodeOptionalStrokeSliderRange(
                  bytes[32],
                  _defaultSprayStrokeSliderRange,
                )
              : _defaultSprayStrokeSliderRange;
          final PenStrokeSliderRange decodedEraserStrokeSliderRange =
              version >= 28 && bytes.length >= 35
              ? _decodeOptionalStrokeSliderRange(
                  bytes[33],
                  _defaultEraserStrokeSliderRange,
                )
              : _defaultEraserStrokeSliderRange;
          final bool decodedShapeToolFillEnabled =
              version >= 23 &&
                  ((version >= 28 && bytes.length >= 35) ||
                      (version < 28 && bytes.length >= 34))
              ? bytes[version >= 28 ? 34 : 33] != 0
              : _defaultShapeToolFillEnabled;
          final double decodedSprayStrokeWidth =
              version >= 24 &&
                  ((version >= 28 && bytes.length >= 37) ||
                      (version < 28 && bytes.length >= 36))
              ? _decodeSprayStrokeWidth(
                  bytes[version >= 28 ? 35 : 34] |
                      (bytes[version >= 28 ? 36 : 35] << 8),
                )
              : _defaultSprayStrokeWidth;
          if (version >= 28 && bytes.length >= 43) {
            final SprayMode decodedSprayMode = _decodeSprayMode(bytes[37]);
            final bool decodedPixelGridVisible = bytes[38] != 0;
            final int primaryColorValue =
                bytes[39] |
                (bytes[40] << 8) |
                (bytes[41] << 16) |
                (bytes[42] << 24);
            final Color decodedPrimaryColor = Color(primaryColorValue);
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            final double decodedPenStrokeWidth = _decodePenStrokeWidthV10(
              rawStroke,
            );
            final double decodedEraserStrokeWidth =
                version >= 42 && bytes.length >= 65
                ? _decodeEraserStrokeWidth(bytes[63] | (bytes[64] << 8))
                : _clampEraserStrokeWidth(decodedPenStrokeWidth);
            final Locale? decodedLocaleOverride =
                version >= 30 && bytes.length >= 45
                ? _decodeLocaleOverride(bytes[44])
                : _defaultLocaleOverride;
            final bool hasNewCanvasDefaults =
                version >= 39 && bytes.length >= 61;
            final int decodedNewCanvasWidth = hasNewCanvasDefaults
                ? _decodeNewCanvasDimension(
                    bytes[53] | (bytes[54] << 8),
                    _defaultNewCanvasWidth,
                  )
                : _defaultNewCanvasWidth;
            final int decodedNewCanvasHeight = hasNewCanvasDefaults
                ? _decodeNewCanvasDimension(
                    bytes[55] | (bytes[56] << 8),
                    _defaultNewCanvasHeight,
                  )
                : _defaultNewCanvasHeight;
            final Color decodedNewCanvasBackgroundColor = hasNewCanvasDefaults
                ? Color(
                    bytes[57] |
                        (bytes[58] << 8) |
                        (bytes[59] << 16) |
                        (bytes[60] << 24),
                  )
                : _defaultNewCanvasBackgroundColor;
            final bool decodedTouchDrawingEnabled =
                version >= 43 && bytes.length >= 66
                ? bytes[65] != 0
                : _defaultTouchDrawingEnabled;
            final double decodedLiquifyStrokeWidth =
                version >= 44 && bytes.length >= 71
                ? _decodeLiquifyStrokeWidth(bytes[66] | (bytes[67] << 8))
                : _defaultLiquifyStrokeWidth;
            final double decodedLiquifyStrength =
                version >= 44 && bytes.length >= 71
                ? _decodeRatioByte(bytes[68])
                : _defaultLiquifyStrength;
            final double decodedLiquifySoftness =
                version >= 44 && bytes.length >= 71
                ? _decodeRatioByte(bytes[69])
                : _defaultLiquifySoftness;
            final double decodedLiquifyMix = version >= 44 && bytes.length >= 71
                ? _decodeRatioByte(bytes[70])
                : _defaultLiquifyMix;
            final bool decodedHollowStrokeEnabled;
            final double decodedHollowStrokeRatio;
            final bool decodedHollowStrokeEraseOccludedParts;
            if (version >= 32 && bytes.length >= 48) {
              decodedHollowStrokeEnabled = bytes[45] != 0;
              decodedHollowStrokeRatio = _decodeRatioByte(bytes[46]);
              decodedHollowStrokeEraseOccludedParts = bytes[47] != 0;
            } else if (version >= 31 && bytes.length >= 51) {
              decodedHollowStrokeEnabled = bytes[45] != 0;
              decodedHollowStrokeRatio = _decodeRatioByte(bytes[46]);
              decodedHollowStrokeEraseOccludedParts =
                  _defaultHollowStrokeEraseOccludedParts;
            } else {
              decodedHollowStrokeEnabled = _defaultHollowStrokeEnabled;
              decodedHollowStrokeRatio = _defaultHollowStrokeRatio;
              decodedHollowStrokeEraseOccludedParts =
                  _defaultHollowStrokeEraseOccludedParts;
            }
            AppPreferences._instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              localeOverride: decodedLocaleOverride,
              penStrokeWidth: decodedPenStrokeWidth,
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
              streamlineStrength: decodedStreamlineStrength,
              brushShape: _decodeBrushShape(bytes[16]),
              brushRandomRotationEnabled: decodedBrushRandomRotationEnabled,
              layerAdjustCropOutside: bytes[17] != 0,
              colorLineColor: decodedColorLineColor,
              bucketSwallowColorLine: decodedBucketSwallowColorLine,
              bucketSwallowColorLineMode: decodedBucketSwallowColorLineMode,
              hollowStrokeEnabled: decodedHollowStrokeEnabled,
              hollowStrokeRatio: decodedHollowStrokeRatio,
              hollowStrokeEraseOccludedParts:
                  decodedHollowStrokeEraseOccludedParts,
              shapeToolFillEnabled: decodedShapeToolFillEnabled,
              bucketTolerance: _clampToleranceValue(bytes[20]),
              bucketFillGap: decodedBucketFillGap,
              magicWandTolerance: _clampToleranceValue(bytes[21]),
              brushToolsEraserMode: bytes[22] != 0,
              touchDrawingEnabled: decodedTouchDrawingEnabled,
              bucketAntialiasLevel: _decodeAntialiasLevel(bytes[23]),
              showFpsOverlay: bytes[24] != 0,
              workspaceLayout: _decodeWorkspaceLayoutPreference(bytes[25]),
              floatingColorPanelHeight: decodedFloatingColorHeight,
              sai2ColorPanelHeight: decodedSai2ColorHeight,
              sai2ToolPanelSplit: decodedSai2ToolSplit,
              sai2LayerPanelWidthSplit: decodedSai2LayerSplit,
              sprayStrokeWidth: decodedSprayStrokeWidth,
              eraserStrokeWidth: decodedEraserStrokeWidth,
              liquifyStrokeWidth: decodedLiquifyStrokeWidth,
              liquifyStrength: decodedLiquifyStrength,
              liquifySoftness: decodedLiquifySoftness,
              liquifyMix: decodedLiquifyMix,
              sprayStrokeSliderRange: decodedSprayStrokeSliderRange,
              eraserStrokeSliderRange: decodedEraserStrokeSliderRange,
              sprayMode: decodedSprayMode,
              pixelGridVisible: decodedPixelGridVisible,
              primaryColor: decodedPrimaryColor,
              newCanvasWidth: decodedNewCanvasWidth,
              newCanvasHeight: decodedNewCanvasHeight,
              newCanvasBackgroundColor: decodedNewCanvasBackgroundColor,
              canvasBackend: decodedCanvasBackend,
              autoSaveCleanupThresholdMb: decodedAutoSaveCleanupThresholdMb,
            );
            return _finalizeLoadedPreferences();
          } else if (version >= 27 && bytes.length >= 42) {
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
            final double decodedPenStrokeWidth = _decodePenStrokeWidthV10(
              rawStroke,
            );
            final double decodedEraserStrokeWidth = _clampEraserStrokeWidth(
              decodedPenStrokeWidth,
            );
            AppPreferences._instance = AppPreferences._(
              bucketSampleAllLayers: bytes[1] != 0,
              bucketContiguous: bytes[2] != 0,
              historyLimit: _clampHistoryLimit(rawHistory),
              themeMode: _decodeThemeMode(bytes[5]),
              penStrokeWidth: decodedPenStrokeWidth,
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
              showFpsOverlay: bytes[24] != 0,
              workspaceLayout: _decodeWorkspaceLayoutPreference(bytes[25]),
              floatingColorPanelHeight: decodedFloatingColorHeight,
              sai2ColorPanelHeight: decodedSai2ColorHeight,
              sai2ToolPanelSplit: decodedSai2ToolSplit,
              sai2LayerPanelWidthSplit: decodedSai2LayerSplit,
              sprayStrokeWidth: decodedSprayStrokeWidth,
              eraserStrokeWidth: decodedEraserStrokeWidth,
              sprayMode: decodedSprayMode,
              pixelGridVisible: decodedPixelGridVisible,
              primaryColor: decodedPrimaryColor,
              canvasBackend: _defaultCanvasBackend,
            );
            return _finalizeLoadedPreferences();
          } else if (version >= 26 && bytes.length >= 38) {
            final SprayMode decodedSprayMode = _decodeSprayMode(bytes[36]);
            final bool decodedPixelGridVisible = bytes[37] != 0;
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            AppPreferences._instance = AppPreferences._(
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
              showFpsOverlay: bytes[24] != 0,
              workspaceLayout: _decodeWorkspaceLayoutPreference(bytes[25]),
              floatingColorPanelHeight: decodedFloatingColorHeight,
              sai2ColorPanelHeight: decodedSai2ColorHeight,
              sai2ToolPanelSplit: decodedSai2ToolSplit,
              sai2LayerPanelWidthSplit: decodedSai2LayerSplit,
              sprayStrokeWidth: decodedSprayStrokeWidth,
              sprayMode: decodedSprayMode,
              pixelGridVisible: decodedPixelGridVisible,
              canvasBackend: _defaultCanvasBackend,
            );
            return _finalizeLoadedPreferences();
          } else if (version >= 25 && bytes.length >= 37) {
            final SprayMode decodedSprayMode = _decodeSprayMode(bytes[36]);
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            AppPreferences._instance = AppPreferences._(
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
              showFpsOverlay: bytes[24] != 0,
              workspaceLayout: _decodeWorkspaceLayoutPreference(bytes[25]),
              floatingColorPanelHeight: decodedFloatingColorHeight,
              sai2ColorPanelHeight: decodedSai2ColorHeight,
              sai2ToolPanelSplit: decodedSai2ToolSplit,
              sai2LayerPanelWidthSplit: decodedSai2LayerSplit,
              sprayStrokeWidth: decodedSprayStrokeWidth,
              sprayMode: decodedSprayMode,
              canvasBackend: _defaultCanvasBackend,
            );
            return _finalizeLoadedPreferences();
          }
          if (version >= 24 && bytes.length >= 36) {
            final int rawHistory = bytes[3] | (bytes[4] << 8);
            final int rawStroke = bytes[6] | (bytes[7] << 8);
            AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
          AppPreferences._instance = AppPreferences._(
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
  AppPreferences._instance = AppPreferences._(
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
    workspaceLayout: _defaultWorkspaceLayout,
    floatingColorPanelHeight: null,
    sai2ColorPanelHeight: null,
    sai2ToolPanelSplit: _defaultSai2ToolPanelSplit,
    sai2LayerPanelWidthSplit: _defaultSai2LayerPanelSplit,
  );
  return _finalizeLoadedPreferences();
}

AppPreferences _finalizeLoadedPreferences() {
  final AppPreferences prefs = AppPreferences._instance!;
  prefs.canvasBackend = CanvasBackend.rustWgpu;
  CanvasBackendState.initialize(prefs.canvasBackend);
  AppPreferences.fpsOverlayEnabledNotifier.value = prefs.showFpsOverlay;
  AppPreferences.pixelGridVisibleNotifier.value = prefs.pixelGridVisible;
  return prefs;
}
