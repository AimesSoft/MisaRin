// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get closeAppTitle => 'Quit App';

  @override
  String unsavedProjectsWarning(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Detected $count unsaved projects. If you quit now, your recent changes will be lost.',
      one:
          'Detected 1 unsaved project. If you quit now, your recent changes will be lost.',
    );
    return '$_temp0';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get discardAndExit => 'Discard and Quit';

  @override
  String get homeTagline => 'Start creating here';

  @override
  String get homeNewProject => 'New Project';

  @override
  String get homeNewProjectDesc => 'Start a new idea from a blank canvas';

  @override
  String get homeOpenProject => 'Open Project';

  @override
  String get homeOpenProjectDesc =>
      'Load a .rin / .psd / .sai2 or image file from disk';

  @override
  String get homeRecentProjects => 'Recent';

  @override
  String get homeRecentProjectsDesc => 'Quickly restore autosaved projects';

  @override
  String get homeProjectManager => 'Project Manager';

  @override
  String get homeProjectManagerDesc =>
      'View or clean up autosaved project files in bulk';

  @override
  String get homeSettings => 'Settings';

  @override
  String get homeSettingsDesc => 'Preview personalization options coming soon';

  @override
  String get homeAbout => 'About';

  @override
  String get homeAboutDesc => 'Learn more about Misa Rin';

  @override
  String createProjectFailed(Object error) {
    return 'Failed to create project: $error';
  }

  @override
  String get openProjectDialogTitle => 'Open Project';

  @override
  String get openingProjectTitle => 'Opening project…';

  @override
  String openingProjectMessage(Object fileName) {
    return 'Loading $fileName';
  }

  @override
  String get cannotReadPsdContent => 'Unable to read PSD file contents.';

  @override
  String get cannotReadSai2Content => 'Unable to read SAI2 file contents.';

  @override
  String get cannotReadProjectFileContent =>
      'Unable to read project file contents.';

  @override
  String openedProjectInfo(Object name) {
    return 'Opened project: $name';
  }

  @override
  String openProjectFailed(Object error) {
    return 'Failed to open project: $error';
  }

  @override
  String get importImageDialogTitle => 'Import Image';

  @override
  String importedImageInfo(Object name) {
    return 'Imported image: $name';
  }

  @override
  String importImageFailed(Object error) {
    return 'Failed to import image: $error';
  }

  @override
  String get clipboardNoBitmapFound =>
      'No bitmap found in clipboard to import.';

  @override
  String get clipboardImageDefaultName => 'Clipboard Image';

  @override
  String get importedClipboardImageInfo => 'Imported clipboard image';

  @override
  String importClipboardImageFailed(Object error) {
    return 'Failed to import clipboard image: $error';
  }

  @override
  String get aboutTitle => 'About Misa Rin';

  @override
  String get aboutDescription =>
      'Misa Rin is an app focused on creative drawing and project management, designed to provide creators with a smooth painting experience and reliable project archiving.';

  @override
  String get aboutAppIdLabel => 'App ID';

  @override
  String get aboutAppVersionLabel => 'Version';

  @override
  String get aboutDeveloperLabel => 'Developer';

  @override
  String get close => 'Close';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsTabGeneral => 'General';

  @override
  String get settingsTabInput => 'Input & Brushes';

  @override
  String get settingsTabStorage => 'History & Storage';

  @override
  String get settingsTabAbout => 'About';

  @override
  String get tabletTest => 'Tablet Test';

  @override
  String get restoreDefaults => 'Restore Defaults';

  @override
  String get ok => 'OK';

  @override
  String get languageLabel => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageJapanese => 'Japanese';

  @override
  String get languageKorean => 'Korean';

  @override
  String get languageChineseSimplified => 'Chinese (Simplified)';

  @override
  String get languageChineseTraditional => 'Chinese (Traditional)';

  @override
  String get themeModeLabel => 'Theme Mode';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get stylusPressureSettingsLabel => 'Stylus Pressure';

  @override
  String get enableStylusPressure => 'Enable stylus pressure';

  @override
  String get responseCurveLabel => 'Response curve';

  @override
  String get responseCurveDesc =>
      'Adjust how pressure transitions into stroke width.';

  @override
  String get brushSizeSliderRangeLabel => 'Brush size slider range';

  @override
  String get brushSizeSliderRangeDesc =>
      'Affects the brush size slider in the tool panel, helping you switch precision quickly.';

  @override
  String get penSliderRangeCompact => '1 - 60 px (coarse)';

  @override
  String get penSliderRangeMedium => '0.1 - 500 px (medium)';

  @override
  String get penSliderRangeFull => '0.01 - 1000 px (full)';

  @override
  String get historyLimitLabel => 'Undo/Redo limit';

  @override
  String historyLimitCurrent(Object count) {
    return 'Current limit: $count steps';
  }

  @override
  String historyLimitDesc(Object min, Object max) {
    return 'Adjust how many undo/redo steps are kept. Range $min-$max.';
  }

  @override
  String get canvasBackendLabel => 'Canvas backend';

  @override
  String get canvasBackendGpu => 'Rust WGPU';

  @override
  String get canvasBackendCpu => 'Rust CPU';

  @override
  String get canvasBackendRestartHint =>
      'Canvas backend change will take effect after restart.';

  @override
  String get developerOptionsLabel => 'Developer Options';

  @override
  String get performanceOverlayLabel => 'Performance overlay';

  @override
  String get performanceOverlayDesc =>
      'Shows a Flutter Performance Pulse dashboard in the corner with FPS, CPU, memory, disk, etc.';

  @override
  String get tabletInputTestTitle => 'Tablet Input Test';

  @override
  String get recentProjectsTitle => 'Recent';

  @override
  String recentProjectsLoadFailed(Object error) {
    return 'Failed to load recent projects: $error';
  }

  @override
  String get recentProjectsEmpty => 'No recent projects';

  @override
  String get openFileLocation => 'Reveal in File Manager';

  @override
  String lastOpened(Object date) {
    return 'Last opened: $date';
  }

  @override
  String canvasSize(Object width, Object height) {
    return 'Canvas size: $width x $height';
  }

  @override
  String get menuFile => 'File';

  @override
  String get menuEdit => 'Edit';

  @override
  String get menuImage => 'Image';

  @override
  String get menuLayer => 'Layer';

  @override
  String get menuSelection => 'Select';

  @override
  String get menuFilter => 'Filter';

  @override
  String get menuTool => 'Tools';

  @override
  String get menuView => 'View';

  @override
  String get menuWorkspace => 'Workspace';

  @override
  String get menuWindow => 'Window';

  @override
  String get menuRoot => 'Menu';

  @override
  String get menuAbout => 'About Misa Rin';

  @override
  String get menuPreferences => 'Preferences…';

  @override
  String get menuNewEllipsis => 'New…';

  @override
  String get menuOpenEllipsis => 'Open…';

  @override
  String get menuImportImageEllipsis => 'Import Image…';

  @override
  String get menuImportImageFromClipboard => 'Import Image from Clipboard';

  @override
  String get menuSave => 'Save';

  @override
  String get menuSaveAsEllipsis => 'Save As…';

  @override
  String get menuExportEllipsis => 'Export…';

  @override
  String get menuCloseAll => 'Close All';

  @override
  String get menuUndo => 'Undo';

  @override
  String get menuRedo => 'Redo';

  @override
  String get menuCut => 'Cut';

  @override
  String get menuCopy => 'Copy';

  @override
  String get menuPaste => 'Paste';

  @override
  String get menuImageTransform => 'Transform';

  @override
  String get menuRotate90CW => 'Rotate 90° CW';

  @override
  String get menuRotate90CCW => 'Rotate 90° CCW';

  @override
  String get menuRotate180CW => 'Rotate 180° CW';

  @override
  String get menuRotate180CCW => 'Rotate 180° CCW';

  @override
  String get menuFlipHorizontal => 'Flip Horizontal';

  @override
  String get menuFlipVertical => 'Flip Vertical';

  @override
  String get menuImageSizeEllipsis => 'Image Size…';

  @override
  String get menuCanvasSizeEllipsis => 'Canvas Size…';

  @override
  String get menuNewSubmenu => 'New';

  @override
  String get menuNewLayerEllipsis => 'Layer…';

  @override
  String get menuMergeDown => 'Merge Down';

  @override
  String get menuRasterize => 'Rasterize';

  @override
  String get menuTransform => 'Transform';

  @override
  String get menuSelectAll => 'Select All';

  @override
  String get menuDeselect => 'Deselect';

  @override
  String get menuInvertSelection => 'Invert Selection';

  @override
  String get menuPalette => 'Palette';

  @override
  String get menuGeneratePaletteFromCanvasEllipsis =>
      'Generate palette from current canvas…';

  @override
  String get menuGenerateGradientPalette =>
      'Generate gradient palette from current colors';

  @override
  String get menuImportPaletteEllipsis => 'Import palette…';

  @override
  String get menuReferenceImage => 'Reference Images';

  @override
  String get menuCreateReferenceImage => 'Create Reference Image';

  @override
  String get menuImportReferenceImageEllipsis => 'Import Reference Image…';

  @override
  String get menuReferenceModel => 'Reference Model';

  @override
  String get menuReferenceModelSteve => 'Steve Model';

  @override
  String get menuReferenceModelAlex => 'Alex Model';

  @override
  String get menuReferenceModelCube => 'Cube Model';

  @override
  String get menuImportReferenceModelEllipsis => 'Import Model…';

  @override
  String get referenceModelRefreshTexture => 'Refresh Texture';

  @override
  String get referenceModelRefreshTextureDesc =>
      'Generate a model texture from the current canvas';

  @override
  String get referenceModelResetView => 'Reset View';

  @override
  String get referenceModelResetViewDesc => 'Reset rotation and zoom';

  @override
  String get referenceModelSixView => '6 Views';

  @override
  String get referenceModelSixViewDesc =>
      'Split the viewport into a 2×3 grid (Front/Back/Top/Bottom/Left/Right)';

  @override
  String get referenceModelSingleView => 'Single View';

  @override
  String get referenceModelSingleViewDesc =>
      'Back to single view (drag to rotate)';

  @override
  String get referenceModelViewFront => 'Front View';

  @override
  String get referenceModelViewBack => 'Back View';

  @override
  String get referenceModelViewTop => 'Top View';

  @override
  String get referenceModelViewBottom => 'Bottom View';

  @override
  String get referenceModelViewLeft => 'Left View';

  @override
  String get referenceModelViewRight => 'Right View';

  @override
  String get menuZoomIn => 'Zoom In';

  @override
  String get menuZoomOut => 'Zoom Out';

  @override
  String get menuShowGrid => 'Show Grid';

  @override
  String get menuHideGrid => 'Hide Grid';

  @override
  String get menuBlackWhite => 'Black & White';

  @override
  String get menuDisableBlackWhite => 'Disable Black & White';

  @override
  String get menuMirrorPreview => 'Mirror Preview';

  @override
  String get menuDisableMirror => 'Disable Mirror';

  @override
  String get menuTiledPreview => 'Tiled Preview';

  @override
  String get menuDisableTiledPreview => 'Disable Tiled Preview';

  @override
  String get menuShowPerspectiveGuide => 'Show Perspective Guide';

  @override
  String get menuHidePerspectiveGuide => 'Hide Perspective Guide';

  @override
  String get menuPerspectiveMode => 'Perspective Mode';

  @override
  String get menuPerspective1Point => '1-Point';

  @override
  String get menuPerspective2Point => '2-Point';

  @override
  String get menuPerspective3Point => '3-Point';

  @override
  String get menuWorkspaceDefault => 'Default';

  @override
  String get menuWorkspaceSai2 => 'SAI2';

  @override
  String get menuWorkspaceCsp => 'CSP';

  @override
  String get menuSwitchWorkspace => 'Switch Workspace';

  @override
  String get menuResetWorkspace => 'Reset Workspace';

  @override
  String get menuEdgeSofteningEllipsis => 'Edge Softening…';

  @override
  String get menuNarrowLinesEllipsis => 'Narrow Lines…';

  @override
  String get menuExpandFillEllipsis => 'Expand Fill…';

  @override
  String get menuGaussianBlurEllipsis => 'Gaussian Blur…';

  @override
  String get menuRemoveColorLeakEllipsis => 'Remove Color Leak…';

  @override
  String get menuHueSaturationEllipsis => 'Hue/Saturation…';

  @override
  String get menuBrightnessContrastEllipsis => 'Brightness/Contrast…';

  @override
  String get menuColorRangeEllipsis => 'Color Range…';

  @override
  String get menuBlackWhiteEllipsis => 'Black & White…';

  @override
  String get menuBinarizeEllipsis => 'Binarize…';

  @override
  String get menuScanPaperDrawingEllipsis => 'Scan Paper Drawing…';

  @override
  String get menuScanPaperDrawing => 'Scan Paper Drawing';

  @override
  String get menuInvertColors => 'Invert Colors';

  @override
  String get canvasSizeTitle => 'Canvas Size';

  @override
  String get canvasSizeAnchorLabel => 'Anchor';

  @override
  String get canvasSizeAnchorDesc => 'Resize canvas based on anchor point.';

  @override
  String get confirm => 'Confirm';

  @override
  String get projectManagerTitle => 'Project Manager';

  @override
  String get selectAll => 'Select All';

  @override
  String get openFolder => 'Open Folder';

  @override
  String deleteSelected(Object count) {
    return 'Delete Selected ($count)';
  }

  @override
  String get imageSizeTitle => 'Image Size';

  @override
  String get lockAspectRatio => 'Lock Aspect Ratio';

  @override
  String get realtimeParams => 'Realtime Parameters';

  @override
  String get clearScribble => 'Clear Scribble';

  @override
  String get newCanvasSettingsTitle => 'New Canvas Settings';

  @override
  String get custom => 'Custom';

  @override
  String get colorWhite => 'White';

  @override
  String get colorLightGray => 'Light Gray';

  @override
  String get colorBlack => 'Black';

  @override
  String get colorTransparent => 'Transparent';

  @override
  String get create => 'Create';

  @override
  String currentPreset(Object name) {
    return 'Current Preset: $name';
  }

  @override
  String get exportSettingsTitle => 'Export Settings';

  @override
  String get exportTypeLabel => 'Export Type';

  @override
  String get exportTypeBitmap => 'Bitmap';

  @override
  String get exportTypePng => 'Bitmap PNG';

  @override
  String get exportTypeSvg => 'Vector SVG (Experimental)';

  @override
  String get exportBitmapFormatLabel => 'Bitmap Format';

  @override
  String get exportBitmapFormatPng => 'PNG';

  @override
  String get exportBitmapFormatWebp => 'WebP';

  @override
  String get webpCompressionLabel => 'WebP Compression';

  @override
  String get webpLossless => 'Lossless';

  @override
  String get webpLossy => 'Lossy';

  @override
  String webpQualityLabel(Object value) {
    return 'Quality: $value';
  }

  @override
  String get exportScaleLabel => 'Export Scale';

  @override
  String get reset => 'Reset';

  @override
  String exportOutputSize(Object width, Object height) {
    return 'Output Size: $width x $height px';
  }

  @override
  String get exportAntialiasingLabel => 'Antialiasing';

  @override
  String get enableAntialiasing => 'Enable Antialiasing';

  @override
  String get vectorParamsLabel => 'Vector Parameters';

  @override
  String vectorMaxColors(Object count) {
    return 'Max Colors: $count';
  }

  @override
  String vectorSimplify(Object value) {
    return 'Simplify Strength: $value';
  }

  @override
  String get export => 'Export';

  @override
  String get invalidDimensions => 'Please enter valid dimensions (px).';

  @override
  String get widthPx => 'Width (px)';

  @override
  String get heightPx => 'Height (px)';

  @override
  String get noAutosavedProjects => 'No autosaved projects';

  @override
  String get revealProjectLocation => 'Reveal selected project location';

  @override
  String get deleteSelectedProjects => 'Delete selected projects';

  @override
  String loadFailed(Object error) {
    return 'Failed to load: $error';
  }

  @override
  String deleteFailed(Object error) {
    return 'Failed to delete: $error';
  }

  @override
  String projectFileInfo(Object size, Object date) {
    return 'Size: $size · Modified: $date';
  }

  @override
  String projectCanvasInfo(Object width, Object height) {
    return 'Canvas $width x $height';
  }

  @override
  String get samplingMethod => 'Sampling Method';

  @override
  String currentSize(Object width, Object height) {
    return 'Current Size: $width x $height px';
  }

  @override
  String get samplingNearestLabel => 'Nearest Neighbor';

  @override
  String get samplingNearestDesc => 'Preserves hard edges, good for pixel art.';

  @override
  String get samplingBilinearLabel => 'Bilinear';

  @override
  String get samplingBilinearDesc =>
      'Smooth interpolation, good for general resizing.';

  @override
  String get tabletPressureLatest => 'Latest Pressure';

  @override
  String get tabletPressureMin => 'Pressure Min';

  @override
  String get tabletPressureMax => 'Pressure Max';

  @override
  String get tabletRadiusPx => 'Estimated Radius (px)';

  @override
  String get tabletTiltRad => 'Tilt (radians)';

  @override
  String get tabletSampleCount => 'Sample Count';

  @override
  String get tabletSampleRateHz => 'Sample Rate (Hz)';

  @override
  String get tabletPointerType => 'Pointer Type';

  @override
  String get pointerKindMouse => 'Mouse';

  @override
  String get pointerKindTouch => 'Touch';

  @override
  String get pointerKindStylus => 'Stylus';

  @override
  String get pointerKindInvertedStylus => 'Stylus (Eraser)';

  @override
  String get pointerKindTrackpad => 'Trackpad';

  @override
  String get pointerKindUnknown => 'Unknown';

  @override
  String get presetMobilePortrait => 'Mobile Portrait (1080 x 1920)';

  @override
  String get presetSquare => 'Square (1024 x 1024)';

  @override
  String presetPixelArt(Object width, Object height) {
    return 'Pixel Art ($width x $height)';
  }

  @override
  String get untitledProject => 'Untitled Project';

  @override
  String get invalidResolution => 'Please enter valid resolution';

  @override
  String minResolutionError(Object value) {
    return 'Resolution cannot be less than $value px';
  }

  @override
  String maxResolutionError(Object value) {
    return 'Resolution cannot exceed $value px';
  }

  @override
  String get projectName => 'Project Name';

  @override
  String get workspacePreset => 'Workspace Preset';

  @override
  String get workspacePresetDesc =>
      'Automatically apply common tool settings when creating a canvas.';

  @override
  String get workspaceIllustration => 'Illustration';

  @override
  String get workspaceIllustrationDesc => 'Brush: Pencil, Edge softening: 1';

  @override
  String get workspaceIllustrationDesc2 => 'Streamline: Unchanged';

  @override
  String get workspaceCelShading => 'Cel Shading';

  @override
  String get workspaceCelShadingDesc1 => 'Brush: Cel Brush, Edge softening: 0';

  @override
  String get workspaceCelShadingDesc2 => 'Fill tool expand to line: On';

  @override
  String get workspaceCelShadingDesc3 => 'Fill tool antialiasing: Off';

  @override
  String get workspacePixel => 'Pixel';

  @override
  String get workspacePixelDesc1 =>
      'Brush: Pixel, Brush/Fill tool antialiasing: 0';

  @override
  String get workspacePixelDesc2 => 'Show Grid: On';

  @override
  String get workspacePixelDesc3 => 'Vector Drawing: Unchanged';

  @override
  String get workspacePixelDesc4 => 'Stabilizer: 0';

  @override
  String get workspaceDefault => 'Default';

  @override
  String get workspaceDefaultDesc => 'Do not change current tool settings';

  @override
  String get resolutionPreset => 'Resolution Preset';

  @override
  String get customResolution => 'Custom Resolution';

  @override
  String get swapDimensions => 'Swap Width/Height';

  @override
  String finalSizePreview(Object width, Object height, Object ratio) {
    return 'Final Size: $width x $height px (Ratio $ratio)';
  }

  @override
  String get enterValidDimensions => 'Please enter valid dimensions';

  @override
  String get backgroundColor => 'Background Color';

  @override
  String get exportBitmapDesc =>
      'Suitable for regular exports requiring raster format, supports scaling and antialiasing.';

  @override
  String get exportVectorDesc =>
      'Automatically transcribes current canvas to vector paths, suitable for editing in vector tools.';

  @override
  String get exampleScale => 'e.g. 1.0';

  @override
  String get enterPositiveValue => 'Please enter a value > 0';

  @override
  String get antialiasingBeforeExport => 'Antialiasing before export';

  @override
  String get brushAntialiasing => 'Brush antialiasing';

  @override
  String get bucketAntialiasing => 'Fill antialiasing';

  @override
  String get antialiasingDesc =>
      'Smoothens edges while preserving line density, a tribute to the texture of Retas animation software.';

  @override
  String levelLabel(Object level) {
    return 'Level $level';
  }

  @override
  String vectorExportSize(Object width, Object height) {
    return 'Export Size: $width x $height (Use Canvas Size)';
  }

  @override
  String colorCount(Object count) {
    return '$count colors';
  }

  @override
  String get vectorSimplifyDesc =>
      'Fewer colors and higher simplification yield simpler SVG; too low values result in too many nodes.';

  @override
  String get antialiasNone =>
      'Level 0 (Off): Preserves pixel hard edges, no antialiasing.';

  @override
  String get antialiasLow =>
      'Level 1 (Low): Slight softening of aliasing, smoothing edges while maintaining line density.';

  @override
  String get antialiasMedium =>
      'Level 2 (Standard): Balance sharpness and softening, presenting clean lines like Retas.';

  @override
  String get antialiasHigh =>
      'Level 3 (High): Strongest softening effect, for edges requiring soft transitions or large scaling.';

  @override
  String get tolerance => 'Tolerance';

  @override
  String get fillGap => 'Fill Gap';

  @override
  String get sampleAllLayers => 'Sample All Layers';

  @override
  String get contiguous => 'Contiguous';

  @override
  String get swallowColorLine => 'Swallow Color Line';

  @override
  String get swallowBlueColorLine => 'Swallow Blue Line';

  @override
  String get swallowGreenColorLine => 'Swallow Green Line';

  @override
  String get swallowRedColorLine => 'Swallow Red Line';

  @override
  String get swallowAllColorLine => 'Swallow All Lines';

  @override
  String get cropOutsideCanvas => 'Crop Outside Canvas';

  @override
  String get noAdjustableSettings => 'No adjustable settings for this tool';

  @override
  String get hollowStroke => 'Hollow Stroke';

  @override
  String get hollowStrokeRatio => 'Hollow Ratio';

  @override
  String get eraseOccludedParts => 'Erase Occluded Parts';

  @override
  String get solidFill => 'Solid Fill';

  @override
  String get autoSharpTaper => 'Auto Sharp Taper';

  @override
  String get stylusPressure => 'Stylus Pressure';

  @override
  String get touchDrawing => 'Touch Drawing';

  @override
  String get simulatedPressure => 'Simulated Pressure';

  @override
  String get switchToEraser => 'Switch to Eraser';

  @override
  String get vectorDrawing => 'Vector Drawing';

  @override
  String get smoothCurve => 'Smooth Curve';

  @override
  String get sprayEffect => 'Spray Effect';

  @override
  String get brushPreset => 'Brush Preset';

  @override
  String get brushPresetDesc =>
      'Select a brush preset for spacing, flow, and shape.';

  @override
  String get editBrushPreset => 'Edit Preset';

  @override
  String get editBrushPresetDesc =>
      'Adjust the current preset\'s internal parameters.';

  @override
  String get brushPresetDialogTitle => 'Edit Brush Preset';

  @override
  String get brushPresetNameLabel => 'Preset Name';

  @override
  String get brushPresetPencil => 'Pencil';

  @override
  String get brushPresetCel => 'Cel Brush';

  @override
  String get brushPresetPen => 'Pen';

  @override
  String get brushPresetScreentone => 'Screentone';

  @override
  String get brushPresetPixel => 'Pixel';

  @override
  String get brushPresetDryInk => 'Dry Ink';

  @override
  String get brushPresetCharcoal => 'Charcoal';

  @override
  String get brushPresetStarBrush => 'Star Brush';

  @override
  String get brushSpacing => 'Spacing';

  @override
  String get brushHardness => 'Hardness';

  @override
  String get brushFlow => 'Flow';

  @override
  String get brushScatter => 'Scatter';

  @override
  String get brushRotationJitter => 'Rotation Jitter';

  @override
  String get brushSnapToPixel => 'Snap to Pixel';

  @override
  String get screentoneEnabled => 'Screentone';

  @override
  String get screentoneShape => 'Dot Shape';

  @override
  String get screentoneSpacing => 'Dot Spacing';

  @override
  String get screentoneDotSize => 'Dot Size';

  @override
  String get screentoneRotation => 'Dot Rotation';

  @override
  String get screentoneSoftness => 'Dot Softness';

  @override
  String get brushShape => 'Brush Shape';

  @override
  String get brushAuthorLabel => 'Author';

  @override
  String get brushVersionLabel => 'Version';

  @override
  String get importBrush => 'Import Brush';

  @override
  String get exportBrush => 'Export Brush';

  @override
  String get exportBrushTitle => 'Export Brush';

  @override
  String get unsavedBrushChangesPrompt =>
      'Brush settings have been modified. Save changes?';

  @override
  String get discardChanges => 'Discard Changes';

  @override
  String get brushShapeFolderLabel => 'Brush Shape Folder';

  @override
  String get openBrushShapesFolder => 'Open Brush Shape Folder';

  @override
  String get randomRotation => 'Random rotation';

  @override
  String get smoothRotation => 'Smooth rotation';

  @override
  String get selectionShape => 'Selection Shape';

  @override
  String get selectionAdditive => 'Additive Selection';

  @override
  String get selectionAdditiveDesc =>
      'When enabled, new selections are added without holding Shift.';

  @override
  String get fontSize => 'Font Size';

  @override
  String get lineHeight => 'Line Height';

  @override
  String get letterSpacing => 'Letter Spacing';

  @override
  String get textStroke => 'Text Stroke';

  @override
  String get strokeWidth => 'Stroke Width';

  @override
  String get strokeColor => 'Stroke Color';

  @override
  String get pickColor => 'Pick Color';

  @override
  String get alignment => 'Alignment';

  @override
  String get alignCenter => 'Center';

  @override
  String get alignRight => 'Right';

  @override
  String get alignLeft => 'Left';

  @override
  String get orientation => 'Orientation';

  @override
  String get horizontal => 'Horizontal';

  @override
  String get vertical => 'Vertical';

  @override
  String get textToolHint =>
      'Use the color picker in the bottom left for text fill, and the secondary color for stroke.';

  @override
  String get shapeType => 'Shape Type';

  @override
  String get brushSize => 'Brush Size';

  @override
  String get spraySize => 'Spray Size';

  @override
  String get brushFineTune => 'Brush Fine Tune';

  @override
  String get increase => 'Increase';

  @override
  String get decrease => 'Decrease';

  @override
  String get stabilizer => 'Stabilizer';

  @override
  String get streamline => 'StreamLine';

  @override
  String get off => 'Off';

  @override
  String get taperEnds => 'Taper Ends';

  @override
  String get taperCenter => 'Taper Center';

  @override
  String get auto => 'Auto';

  @override
  String get softSpray => 'Soft Spray';

  @override
  String get splatter => 'Splatter';

  @override
  String get rectSelection => 'Rectangle Selection';

  @override
  String get ellipseSelection => 'Ellipse Selection';

  @override
  String get polygonLasso => 'Polygon Lasso';

  @override
  String get rectangle => 'Rectangle';

  @override
  String get ellipse => 'Ellipse';

  @override
  String get triangle => 'Triangle';

  @override
  String get line => 'Line';

  @override
  String get circle => 'Circle';

  @override
  String get square => 'Square';

  @override
  String get star => 'Star';

  @override
  String get brushSizeDesc =>
      'Sets the pixel diameter of the current brush. Larger values make thicker lines, smaller for details.';

  @override
  String get spraySizeDesc =>
      'Determines the radius of the spray area. Larger radius covers more area but particles are more dispersed.';

  @override
  String get toleranceDesc =>
      'Controls the threshold for \'color similarity\' for Bucket or Magic Wand. Higher tolerance grabs more similar colors.';

  @override
  String get fillGapDesc =>
      'Attempts to close small gaps in line art during bucket fill to prevent leaks. Higher values close larger gaps but may miss very thin areas.';

  @override
  String get antialiasingSliderDesc =>
      'Adds multi-sampling smoothing to brush or fill edges, preserving line density. Level 0 keeps pixel style.';

  @override
  String get stabilizerDesc =>
      'Smooths pointer trajectory in real-time to counteract hand tremors. Higher levels are steadier but respond slower.';

  @override
  String get streamlineDesc =>
      'Procreate-like StreamLine: smooths the stroke after lift-off and tween-snaps it to a cleaner path (higher levels are stronger).';

  @override
  String get fontSizeDesc =>
      'Adjusts the pixel height of the text for overall scaling.';

  @override
  String get lineHeightDesc =>
      'Controls vertical distance between lines of text.';

  @override
  String get letterSpacingDesc =>
      'Changes horizontal spacing between characters.';

  @override
  String get strokeWidthDesc => 'Sets the thickness of the text stroke.';

  @override
  String get hollowStrokeDesc =>
      'Cuts out the center of strokes for a hollow outline effect.';

  @override
  String get hollowStrokeRatioDesc =>
      'Controls the size of the hollow interior. Higher values make the outline thinner.';

  @override
  String get eraseOccludedPartsDesc =>
      'When enabled, later hollow strokes erase overlapping pixels from existing strokes on the same layer.';

  @override
  String get solidFillDesc =>
      'Determines if the shape tool draws a filled block or hollow outline. Toggle on for solid shapes.';

  @override
  String get randomRotationDesc =>
      'When enabled, square/triangle/star stamps rotate randomly along the stroke.';

  @override
  String get autoSharpTaperDesc =>
      'Automatically tapers the start and end of strokes for a sharp, cel-shading look.';

  @override
  String get stylusPressureDesc =>
      'Allows stylus pressure to affect brush size/opacity. Turn off to ignore hardware pressure.';

  @override
  String get touchDrawingDesc =>
      'When off, finger touch cannot draw. Stylus can still draw.';

  @override
  String get simulatedPressureDesc =>
      'Simulates pressure based on mouse speed when no pressure device is present.';

  @override
  String get switchToEraserDesc =>
      'Switches current brush/spray to an eraser with the same texture.';

  @override
  String get vectorDrawingDesc =>
      'Previews strokes as vector curves for 120Hz smooth feedback and lossless scaling. Turn off for direct pixel output.';

  @override
  String get smoothCurveDesc =>
      'Further smooths curve nodes when Vector Drawing is on, reducing corners but sacrificing some responsiveness.';

  @override
  String get sampleAllLayersDesc =>
      'Bucket samples colors from all visible layers. Turn off to detect only the current layer.';

  @override
  String get contiguousDesc =>
      'Spreads only to adjacent pixels. Turn off to match the entire canvas.';

  @override
  String get swallowColorLineDesc =>
      'Automatically expands fill into color lines to remove white edges. Dedicated for Retas workflow.';

  @override
  String get swallowBlueColorLineDesc =>
      'Swallows only blue lines when filling.';

  @override
  String get swallowGreenColorLineDesc =>
      'Swallows only green lines when filling.';

  @override
  String get swallowRedColorLineDesc => 'Swallows only red lines when filling.';

  @override
  String get swallowAllColorLineDesc =>
      'Swallows red/green/blue lines when filling.';

  @override
  String get cropOutsideCanvasDesc =>
      'Crops pixels outside the canvas when adjusting layers. Turn off to keep all pixels.';

  @override
  String get textAntialiasingDesc =>
      'Enables antialiasing for text rendering, smoothing glyphs while preserving density.';

  @override
  String get textStrokeDesc => 'Enables the stroke channel for text outlines.';

  @override
  String get sprayEffectDesc =>
      'Switches spray model: \'Soft Spray\' for misty gradients, \'Splatter\' for particles.';

  @override
  String get rectSelectDesc => 'Quickly select a rectangular area.';

  @override
  String get ellipseSelectDesc => 'Create circular or elliptical selections.';

  @override
  String get polyLassoDesc =>
      'Draw arbitrary polygon selections point by point.';

  @override
  String get rectShapeDesc =>
      'Draw horizontal rectangles or squares (outline/fill).';

  @override
  String get ellipseShapeDesc => 'Draw elliptical or circular outlines/fills.';

  @override
  String get triangleShapeDesc =>
      'Draw geometric triangles or use a triangle tip for sharp outlines.';

  @override
  String get lineShapeDesc => 'Draw straight lines from start to end.';

  @override
  String get circleTipDesc =>
      'Keep brush tip circular for smooth, soft strokes.';

  @override
  String get squareTipDesc => 'Use a square tip for hard-edged pixel strokes.';

  @override
  String get starTipDesc => 'Use a five-point star tip for decorative strokes.';

  @override
  String get apply => 'Apply';

  @override
  String get next => 'Next';

  @override
  String get disableVectorDrawing => 'Disable Vector Drawing';

  @override
  String get disableVectorDrawingConfirm =>
      'Are you sure you want to disable vector drawing?';

  @override
  String get disableVectorDrawingDesc =>
      'Performance will decrease after disabling.';

  @override
  String get dontShowAgain => 'Don\'t show again';

  @override
  String get newLayer => 'New Layer';

  @override
  String get mergeDown => 'Merge Down';

  @override
  String get delete => 'Delete';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get rasterizeTextLayer => 'Rasterize Text Layer';

  @override
  String get opacity => 'Opacity';

  @override
  String get blendMode => 'Blend Mode';

  @override
  String get clearFill => 'Clear Fill';

  @override
  String get colorLine => 'Color Line';

  @override
  String get currentColor => 'Current Color';

  @override
  String get rgb => 'RGB';

  @override
  String get hsv => 'HSV';

  @override
  String get preparingLayer => 'Preparing layer...';

  @override
  String get generatePaletteTitle => 'Generate palette from canvas';

  @override
  String get generatePaletteDesc => 'Choose color count or enter custom value.';

  @override
  String get customCount => 'Custom Count';

  @override
  String get selectExportFormat => 'Select Export Format';

  @override
  String get selectPaletteFormatDesc => 'Select palette export format.';

  @override
  String get noColorsDetected => 'No colors detected.';

  @override
  String get alphaThreshold => 'Alpha Threshold';

  @override
  String get blurRadius => 'Blur Radius';

  @override
  String get repairRange => 'Repair Range';

  @override
  String get selectAntialiasLevel => 'Select Antialias Level';

  @override
  String get colorCountLabel => 'Color Count';

  @override
  String get completeTransformFirst =>
      'Please complete the current transform first.';

  @override
  String get enablePerspectiveGuideFirst =>
      'Please enable perspective guide before using perspective pen.';

  @override
  String get lineNotAlignedWithPerspective =>
      'Current line does not align with perspective direction, please adjust angle.';

  @override
  String get layerBackground => 'Background';

  @override
  String layerDefaultName(Object index) {
    return 'Layer $index';
  }

  @override
  String get duplicateLayer => 'Duplicate Layer';

  @override
  String layerCopyName(Object name) {
    return '$name Copy';
  }

  @override
  String get unlockLayer => 'Unlock Layer';

  @override
  String get lockLayer => 'Lock Layer';

  @override
  String get releaseClippingMask => 'Release Clipping Mask';

  @override
  String get createClippingMask => 'Create Clipping Mask';

  @override
  String get hide => 'Hide';

  @override
  String get show => 'Show';

  @override
  String get colorRangeTitle => 'Color Range';

  @override
  String get colorPickerTitle => 'Color Picker';

  @override
  String get layerManagerTitle => 'Layer Manager';

  @override
  String get edgeSoftening => 'Edge Softening';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String undoShortcut(Object shortcut) {
    return 'Undo ($shortcut)';
  }

  @override
  String redoShortcut(Object shortcut) {
    return 'Redo ($shortcut)';
  }

  @override
  String opacityPercent(Object percent) {
    return 'Opacity $percent%';
  }

  @override
  String get clippingMask => 'Clipping Mask';

  @override
  String get deleteLayerTitle => 'Delete Layer';

  @override
  String get deleteLayerDesc => 'Remove this layer. Undo available.';

  @override
  String get mergeDownDesc => 'Merge with the layer below.';

  @override
  String get duplicateLayerDesc => 'Duplicate entire layer content.';

  @override
  String get more => 'More';

  @override
  String get lockLayerDesc => 'Lock to prevent accidental edits.';

  @override
  String get unlockLayerDesc => 'Unlock to enable editing.';

  @override
  String get clippingMaskDescOn => 'Restore to normal layer.';

  @override
  String get clippingMaskDescOff => 'Clip to layer below.';

  @override
  String get red => 'Red';

  @override
  String get green => 'Green';

  @override
  String get blue => 'Blue';

  @override
  String get hue => 'Hue';

  @override
  String get saturation => 'Saturation';

  @override
  String get value => 'Value';

  @override
  String get hsvBoxSpectrum => 'HSV Box Spectrum';

  @override
  String get hueRingSpectrum => 'Hue Ring Spectrum';

  @override
  String get rgbHsvSliders => 'RGB / HSV Sliders';

  @override
  String get boardPanelPicker => 'Board Panel Picker';

  @override
  String get adjustCurrentColor => 'Adjust Current Color';

  @override
  String get adjustStrokeColor => 'Adjust Stroke Color';

  @override
  String copiedHex(Object hex) {
    return 'Copied $hex';
  }

  @override
  String rotationLabel(Object degrees) {
    return 'Rotation: $degrees°';
  }

  @override
  String scaleLabel(Object x, Object y) {
    return 'Scale: $x% x $y%';
  }

  @override
  String get failedToExportTransform => 'Failed to export transform result';

  @override
  String get cannotLocateLayer => 'Cannot locate active layer.';

  @override
  String get layerLockedCannotTransform =>
      'Active layer is locked, cannot transform.';

  @override
  String get cannotEnterTransformMode => 'Cannot enter free transform mode.';

  @override
  String get applyTransformFailed =>
      'Failed to apply transform, please try again.';

  @override
  String get freeTransformTitle => 'Free Transform';

  @override
  String get colorIndicatorDetail =>
      'Click to open color editor, enter values or copy HEX.';

  @override
  String get gplDesc =>
      'Text format compatible with GIMP, Krita, Clip Studio Paint, etc.';

  @override
  String get aseDesc =>
      'Suitable for Aseprite, LibreSprite pixel art software.';

  @override
  String get asepriteDesc =>
      'Uses .aseprite extension for direct opening in Aseprite.';

  @override
  String get gradientPaletteFailed =>
      'Current color cannot generate gradient palette, please try again.';

  @override
  String get gradientPaletteTitle => 'Gradient Palette (Current Color)';

  @override
  String paletteCountRange(Object min, Object max) {
    return 'Range $min - $max';
  }

  @override
  String allowedRange(Object min, Object max) {
    return 'Allowed Range: $min - $max colors';
  }

  @override
  String get enterValidColorCount => 'Please enter a valid color count.';

  @override
  String get paletteGenerationFailed =>
      'Unable to generate palette momentarily, please try again.';

  @override
  String get noValidColorsFound =>
      'No valid colors found, please ensure canvas has content.';

  @override
  String get paletteEmpty => 'This palette has no usable colors.';

  @override
  String paletteMinColors(Object min) {
    return 'Palette requires at least $min colors.';
  }

  @override
  String get paletteDefaultName => 'Palette';

  @override
  String get paletteEmptyExport => 'This palette has no exportable colors.';

  @override
  String get exportPaletteTitle => 'Export Palette';

  @override
  String paletteExported(Object path) {
    return 'Palette exported to $path';
  }

  @override
  String paletteExportFailed(Object error) {
    return 'Failed to export palette: $error';
  }

  @override
  String get selectEditableLayerFirst =>
      'Please select an editable layer first.';

  @override
  String get layerLockedNoFilter =>
      'Active layer is locked, cannot apply filter.';

  @override
  String get textLayerNoFilter =>
      'Active layer is text, please rasterize or switch layer.';

  @override
  String get hueSaturation => 'Hue/Saturation';

  @override
  String get brightnessContrast => 'Brightness/Contrast';

  @override
  String get blackAndWhite => 'Black & White';

  @override
  String get binarize => 'Binarize';

  @override
  String get gaussianBlur => 'Gaussian Blur';

  @override
  String get leakRemoval => 'Leak Removal';

  @override
  String get lineNarrow => 'Line Narrow';

  @override
  String get narrowRadius => 'Narrow Radius';

  @override
  String get fillExpand => 'Fill Expand';

  @override
  String get expandRadius => 'Expand Radius';

  @override
  String get noTransparentPixelsFound =>
      'No processable transparent pixels detected.';

  @override
  String get filterApplyFailed => 'Failed to apply filter, please try again.';

  @override
  String get canvasNotReadyInvert => 'Canvas not ready, cannot invert colors.';

  @override
  String get layerLockedInvert => 'Active layer locked, cannot invert colors.';

  @override
  String get layerEmptyInvert => 'Active layer empty, cannot invert colors.';

  @override
  String get noPixelsToInvert => 'Active layer has no pixels to invert.';

  @override
  String get layerEmptyScanPaperDrawing =>
      'Active layer empty, cannot scan paper drawing.';

  @override
  String get scanPaperDrawingNoChanges => 'No convertible pixels detected.';

  @override
  String get edgeSofteningFailed =>
      'Cannot apply edge softening, layer might be empty or locked.';

  @override
  String get layerLockedEdgeSoftening =>
      'Active layer locked, cannot apply edge softening.';

  @override
  String get canvasNotReadyColorRange =>
      'Canvas not ready, cannot count color range.';

  @override
  String get layerLockedColorRange =>
      'Active layer locked, cannot set color range.';

  @override
  String get layerEmptyColorRange =>
      'Active layer empty, cannot set color range.';

  @override
  String get noColorsToProcess => 'Active layer has no processable colors.';

  @override
  String get targetColorsNotLess =>
      'Target color count not less than current, layer unchanged.';

  @override
  String get colorRangeApplyFailed =>
      'Failed to apply color range, please try again.';

  @override
  String get colorRangePreviewFailed =>
      'Failed to generate color range preview, please try again.';

  @override
  String get lightness => 'Lightness';

  @override
  String get brightness => 'Brightness';

  @override
  String get contrast => 'Contrast';

  @override
  String get selectSaveFormat => 'Please select a file format to save.';

  @override
  String get saveAsPsd => 'Save as PSD';

  @override
  String get saveAsSai2 => 'Save as SAI2';

  @override
  String get saveAsRin => 'Save as RIN';

  @override
  String get dontSave => 'Don\'t Save';

  @override
  String get save => 'Save';

  @override
  String get renameProject => 'Rename Project';

  @override
  String get enterNewProjectName => 'Please enter a new project name';

  @override
  String get rename => 'Rename';

  @override
  String get canvasNotReady => 'Canvas not ready';

  @override
  String get toolPanel => 'Tool Panel';

  @override
  String get toolbarTitle => 'Toolbar';

  @override
  String get toolOptionsTitle => 'Tool Options';

  @override
  String get defaultProjectDirectory => 'Default Project Directory';

  @override
  String get minimize => 'Minimize';

  @override
  String get maximizeRestore => 'Maximize/Restore';

  @override
  String get fontFamily => 'Font Family';

  @override
  String get fontSearchPlaceholder => 'Search fonts...';

  @override
  String get noMatchingFonts => 'No matching fonts.';

  @override
  String get fontPreviewText => 'Preview text';

  @override
  String get fontPreviewLanguages => 'Test languages';

  @override
  String get fontLanguageCategory => 'Language category';

  @override
  String get fontLanguageAll => 'All';

  @override
  String get fontFavorites => 'Favorites';

  @override
  String get noFavoriteFonts => 'No favorite fonts yet.';

  @override
  String get importPaletteTitle => 'Import Palette';

  @override
  String get cannotReadFile => 'Cannot read file';

  @override
  String paletteImported(Object name) {
    return 'Palette imported: $name';
  }

  @override
  String paletteImportFailed(Object error) {
    return 'Failed to import palette: $error';
  }

  @override
  String noChangesToSave(Object location) {
    return 'No changes to save to $location';
  }

  @override
  String projectSaved(Object location) {
    return 'Project saved to $location';
  }

  @override
  String projectSaveFailed(Object error) {
    return 'Failed to save project: $error';
  }

  @override
  String get canvasNotReadySave => 'Canvas is not ready to save.';

  @override
  String get saveProjectAs => 'Save Project As';

  @override
  String psdExported(Object path) {
    return 'PSD exported to $path';
  }

  @override
  String sai2Exported(Object path) {
    return 'SAI2 exported to $path';
  }

  @override
  String projectDownloaded(Object fileName) {
    return 'Project downloaded: $fileName';
  }

  @override
  String psdDownloaded(Object fileName) {
    return 'PSD downloaded: $fileName';
  }

  @override
  String sai2Downloaded(Object fileName) {
    return 'SAI2 downloaded: $fileName';
  }

  @override
  String get exportAsPsdTooltip => 'Export as PSD';

  @override
  String get exportAsSai2Tooltip => 'Export as SAI2';

  @override
  String get canvasNotReadyExport => 'Canvas is not ready to export.';

  @override
  String exportFileTitle(Object extension) {
    return 'Export $extension File';
  }

  @override
  String fileExported(Object path) {
    return 'File exported to $path';
  }

  @override
  String exportFailed(Object error) {
    return 'Export failed: $error';
  }

  @override
  String get canvasNotReadyTransform => 'Canvas not ready for transformation.';

  @override
  String get canvasSizeErrorTransform =>
      'Canvas size error during transformation.';

  @override
  String get canvasNotReadyResizeImage => 'Canvas not ready to resize image.';

  @override
  String get resizeImageFailed => 'Failed to resize image.';

  @override
  String get canvasNotReadyResizeCanvas => 'Canvas not ready to resize canvas.';

  @override
  String get resizeCanvasFailed => 'Failed to resize canvas.';

  @override
  String get returnToHome => 'Return to Home';

  @override
  String get saveBeforeReturn =>
      'Do you want to save changes before returning to home?';

  @override
  String get closeCanvas => 'Close Canvas';

  @override
  String get saveBeforeClose => 'Do you want to save changes before closing?';

  @override
  String get nameCannotBeEmpty => 'Name cannot be empty.';

  @override
  String get noSupportedImageFormats => 'No supported image formats found.';

  @override
  String importFailed(Object item, Object error) {
    return 'Failed to import $item: $error';
  }

  @override
  String get createdCanvasFromDrop => 'Created canvas from dropped item.';

  @override
  String createdCanvasesFromDrop(Object count) {
    return 'Created $count canvases from dropped items.';
  }

  @override
  String get dropImageCreateFailed =>
      'Failed to create canvas from dropped image.';

  @override
  String get canvasNotReadyDrop => 'Canvas not ready for drop operation.';

  @override
  String get insertedDropImage => 'Inserted dropped image.';

  @override
  String insertedDropImages(Object count) {
    return 'Inserted $count dropped images.';
  }

  @override
  String get dropImageInsertFailed => 'Failed to insert dropped image.';

  @override
  String get image => 'Image';

  @override
  String get on => 'On';

  @override
  String get perspective1Point => '1-Point Perspective';

  @override
  String get perspective2Point => '2-Point Perspective';

  @override
  String get perspective3Point => '3-Point Perspective';

  @override
  String resolutionLabel(Object resolution) {
    return 'Resolution: $resolution';
  }

  @override
  String zoomLabel(Object zoom) {
    return 'Zoom: $zoom';
  }

  @override
  String positionLabel(Object position) {
    return 'Pos: $position';
  }

  @override
  String gridLabel(Object grid) {
    return 'Grid: $grid';
  }

  @override
  String blackWhiteLabel(Object state) {
    return 'B&W: $state';
  }

  @override
  String mirrorLabel(Object state) {
    return 'Mirror: $state';
  }

  @override
  String tileLabel(Object state) {
    return 'Tile: $state';
  }

  @override
  String perspectiveLabel(Object perspective) {
    return 'Perspective: $perspective';
  }

  @override
  String get fileNameCannotBeEmpty => 'File name cannot be empty.';

  @override
  String get blackPoint => 'Black Point';

  @override
  String get whitePoint => 'White Point';

  @override
  String get midTone => 'Mid Tone';

  @override
  String get rendererLabel => 'Renderer';

  @override
  String get rendererNormal => 'Normal';

  @override
  String get rendererNormalDesc =>
      'Real-time rendering, fastest speed, suitable for preview.';

  @override
  String get rendererCinematic => 'Trailer';

  @override
  String get rendererCinematicDesc =>
      'Recreates the official Minecraft trailer style with soft shadows and high-contrast lighting.';

  @override
  String get rendererCycles => 'Realistic';

  @override
  String get rendererCyclesDesc =>
      'Simulates path tracing style, extremely realistic lighting effects.';

  @override
  String get autoSaveCleanupThresholdLabel => 'Auto-save cleanup threshold';

  @override
  String autoSaveCleanupThresholdValue(Object size) {
    return 'Current threshold: $size';
  }

  @override
  String get autoSaveCleanupThresholdDesc =>
      'If the auto-save folder exceeds this size, you will be prompted to clean up on startup.';

  @override
  String get autoSaveCleanupDialogTitle => 'Auto-save storage is large';

  @override
  String autoSaveCleanupDialogMessage(Object size, Object limit) {
    return 'Auto-saved projects are using $size (limit $limit). Clean up now?';
  }

  @override
  String get autoSaveCleanupDialogClean => 'Clean Up';

  @override
  String get exportDestinationTitle => 'Export destination';

  @override
  String get exportDestinationDesc => 'Choose where to export the image.';

  @override
  String get imageSourceTitle => 'Select image source';

  @override
  String get imageSourceDesc => 'Choose to import from Photos or Files.';

  @override
  String get exportDestinationPhotos => 'Photos';

  @override
  String get exportDestinationFiles => 'Files';

  @override
  String get imageSavedToPhotos => 'Image saved to Photos.';

  @override
  String get exportDirectoryLabel => 'Export directory';

  @override
  String get exportDirectoryDesc =>
      'Set the default export location on Android.';

  @override
  String get selectExportDirectory => 'Choose folder';

  @override
  String get resetExportDirectory => 'Use default';

  @override
  String exportDirectoryCurrent(Object path) {
    return 'Current: $path';
  }

  @override
  String exportDirectoryDefault(Object path) {
    return 'Default: $path';
  }

  @override
  String exportDirectoryUpdated(Object path) {
    return 'Export directory updated: $path';
  }

  @override
  String get exportDirectoryCleared => 'Export directory reset to default.';

  @override
  String exportDirectoryUpdateFailed(Object error) {
    return 'Failed to update export directory: $error';
  }
}
