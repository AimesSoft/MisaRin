part of 'app_preferences.dart';

Future<void> _saveAppPreferences() async {
  final AppPreferences prefs =
      AppPreferences._instance ?? await _loadAppPreferences();
  final int history = _clampHistoryLimit(prefs.historyLimit);
  prefs.historyLimit = history;
  final double strokeWidthValue = prefs.penStrokeWidth.clamp(
    kPenStrokeMin,
    kPenStrokeMax,
  );
  prefs.penStrokeWidth = strokeWidthValue;
  final int strokeWidth = _encodePenStrokeWidth(strokeWidthValue);
  final double sprayWidthValue = _clampSprayStrokeWidth(prefs.sprayStrokeWidth);
  prefs.sprayStrokeWidth = sprayWidthValue;
  final int sprayWidth = _encodeSprayStrokeWidth(sprayWidthValue);
  final double eraserWidthValue = _clampEraserStrokeWidth(
    prefs.eraserStrokeWidth,
  );
  prefs.eraserStrokeWidth = eraserWidthValue;
  final int eraserWidth = _encodeEraserStrokeWidth(eraserWidthValue);
  final double liquifyWidthValue = _clampLiquifyStrokeWidth(
    prefs.liquifyStrokeWidth,
  );
  prefs.liquifyStrokeWidth = liquifyWidthValue;
  final int liquifyWidth = _encodeLiquifyStrokeWidth(liquifyWidthValue);
  prefs.liquifyStrength = _clampLiquifyRatio(
    prefs.liquifyStrength,
    _defaultLiquifyStrength,
  );
  prefs.liquifySoftness = _clampLiquifyRatio(
    prefs.liquifySoftness,
    _defaultLiquifySoftness,
  );
  prefs.liquifyMix = _clampLiquifyRatio(prefs.liquifyMix, _defaultLiquifyMix);
  final int liquifyStrengthEncoded = _encodeRatioByte(prefs.liquifyStrength);
  final int liquifySoftnessEncoded = _encodeRatioByte(prefs.liquifySoftness);
  final int liquifyMixEncoded = _encodeRatioByte(prefs.liquifyMix);
  final double smudgeWidthValue = _clampSmudgeStrokeWidth(
    prefs.smudgeStrokeWidth,
  );
  prefs.smudgeStrokeWidth = smudgeWidthValue;
  final int smudgeWidth = _encodeSmudgeStrokeWidth(smudgeWidthValue);
  prefs.smudgeStrength = _clampSmudgeRatio(
    prefs.smudgeStrength,
    _defaultSmudgeStrength,
  );
  prefs.smudgeSoftness = _clampSmudgeRatio(
    prefs.smudgeSoftness,
    _defaultSmudgeSoftness,
  );
  final int smudgeStrengthEncoded = _encodeRatioByte(prefs.smudgeStrength);
  final int smudgeSoftnessEncoded = _encodeRatioByte(prefs.smudgeSoftness);
  final double stylusCurve = _clampStylusFactor(
    prefs.stylusPressureCurve,
    lower: _stylusCurveLowerBound,
    upper: _stylusCurveUpperBound,
  );

  prefs.stylusPressureCurve = stylusCurve;
  prefs.strokeStabilizerStrength = _clampStrokeStabilizerStrength(
    prefs.strokeStabilizerStrength,
  );
  prefs.streamlineStrength = _clampStreamlineStrength(prefs.streamlineStrength);

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
  final int streamlineEncoded = _encodeStreamlineStrength(
    prefs.streamlineStrength,
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
  final int spraySliderRangeEncoded = _encodeOptionalStrokeSliderRange(
    prefs.sprayStrokeSliderRange,
    _defaultSprayStrokeSliderRange,
  );
  final int eraserSliderRangeEncoded = _encodeOptionalStrokeSliderRange(
    prefs.eraserStrokeSliderRange,
    _defaultEraserStrokeSliderRange,
  );
  final int primaryColorValue = prefs.primaryColor.value;
  final double hollowStrokeRatio = prefs.hollowStrokeRatio.clamp(0.0, 1.0);
  prefs.hollowStrokeRatio = hollowStrokeRatio;
  final int hollowStrokeRatioEncoded = _encodeRatioByte(hollowStrokeRatio);
  final int localeOverrideEncoded = _encodeLocaleOverride(prefs.localeOverride);
  final bool hollowStrokeEraseOccludedParts =
      prefs.hollowStrokeEraseOccludedParts;
  final int bucketSwallowColorLineModeEncoded =
      _encodeBucketSwallowColorLineMode(prefs.bucketSwallowColorLineMode);
  final int bucketFillGapEncoded = _clampFillGapValue(prefs.bucketFillGap);
  final int newCanvasWidth = _clampNewCanvasDimension(
    prefs.newCanvasWidth <= 0 ? _defaultNewCanvasWidth : prefs.newCanvasWidth,
  );
  final int newCanvasHeight = _clampNewCanvasDimension(
    prefs.newCanvasHeight <= 0
        ? _defaultNewCanvasHeight
        : prefs.newCanvasHeight,
  );
  prefs.newCanvasWidth = newCanvasWidth;
  prefs.newCanvasHeight = newCanvasHeight;
  final int newCanvasBackgroundColorValue =
      prefs.newCanvasBackgroundColor.value;
  final int canvasBackendEncoded = _encodeCanvasBackend(prefs.canvasBackend);
  final int autoSaveCleanupThresholdMb = _clampAutoSaveCleanupThresholdMb(
    prefs.autoSaveCleanupThresholdMb,
  );
  prefs.autoSaveCleanupThresholdMb = autoSaveCleanupThresholdMb;

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
    spraySliderRangeEncoded,
    eraserSliderRangeEncoded,
    prefs.shapeToolFillEnabled ? 1 : 0,
    sprayWidth & 0xff,
    (sprayWidth >> 8) & 0xff,
    _encodeSprayMode(prefs.sprayMode),
    prefs.pixelGridVisible ? 1 : 0,
    primaryColorValue & 0xff,
    (primaryColorValue >> 8) & 0xff,
    (primaryColorValue >> 16) & 0xff,
    (primaryColorValue >> 24) & 0xff,
    0,
    localeOverrideEncoded,
    prefs.hollowStrokeEnabled ? 1 : 0,
    hollowStrokeRatioEncoded,
    hollowStrokeEraseOccludedParts ? 1 : 0,
    bucketSwallowColorLineModeEncoded,
    bucketFillGapEncoded,
    prefs.brushRandomRotationEnabled ? 1 : 0,
    streamlineEncoded,
    canvasBackendEncoded,
    newCanvasWidth & 0xff,
    (newCanvasWidth >> 8) & 0xff,
    newCanvasHeight & 0xff,
    (newCanvasHeight >> 8) & 0xff,
    newCanvasBackgroundColorValue & 0xff,
    (newCanvasBackgroundColorValue >> 8) & 0xff,
    (newCanvasBackgroundColorValue >> 16) & 0xff,
    (newCanvasBackgroundColorValue >> 24) & 0xff,
    autoSaveCleanupThresholdMb & 0xff,
    (autoSaveCleanupThresholdMb >> 8) & 0xff,
    eraserWidth & 0xff,
    (eraserWidth >> 8) & 0xff,
    prefs.touchDrawingEnabled ? 1 : 0,
    liquifyWidth & 0xff,
    (liquifyWidth >> 8) & 0xff,
    liquifyStrengthEncoded,
    liquifySoftnessEncoded,
    liquifyMixEncoded,
    smudgeWidth & 0xff,
    (smudgeWidth >> 8) & 0xff,
    smudgeStrengthEncoded,
    smudgeSoftnessEncoded,
  ]);
  await _writePreferencesPayload(payload);
}
