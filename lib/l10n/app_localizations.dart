import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('zh'),
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
  ];

  /// No description provided for @closeAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Quit App'**
  String get closeAppTitle;

  /// No description provided for @unsavedProjectsWarning.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Detected 1 unsaved project. If you quit now, your recent changes will be lost.} other{Detected {count} unsaved projects. If you quit now, your recent changes will be lost.}}'**
  String unsavedProjectsWarning(num count);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @discardAndExit.
  ///
  /// In en, this message translates to:
  /// **'Discard and Quit'**
  String get discardAndExit;

  /// No description provided for @homeTagline.
  ///
  /// In en, this message translates to:
  /// **'Start creating here'**
  String get homeTagline;

  /// No description provided for @homeNewProject.
  ///
  /// In en, this message translates to:
  /// **'New Project'**
  String get homeNewProject;

  /// No description provided for @homeNewProjectDesc.
  ///
  /// In en, this message translates to:
  /// **'Start a new idea from a blank canvas'**
  String get homeNewProjectDesc;

  /// No description provided for @homeOpenProject.
  ///
  /// In en, this message translates to:
  /// **'Open Project'**
  String get homeOpenProject;

  /// No description provided for @homeOpenProjectDesc.
  ///
  /// In en, this message translates to:
  /// **'Load a .rin / .psd / .sai2 or image file from disk'**
  String get homeOpenProjectDesc;

  /// No description provided for @homeRecentProjects.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get homeRecentProjects;

  /// No description provided for @homeRecentProjectsDesc.
  ///
  /// In en, this message translates to:
  /// **'Quickly restore autosaved projects'**
  String get homeRecentProjectsDesc;

  /// No description provided for @homeProjectManager.
  ///
  /// In en, this message translates to:
  /// **'Project Manager'**
  String get homeProjectManager;

  /// No description provided for @homeProjectManagerDesc.
  ///
  /// In en, this message translates to:
  /// **'View or clean up autosaved project files in bulk'**
  String get homeProjectManagerDesc;

  /// No description provided for @homeSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get homeSettings;

  /// No description provided for @homeSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Preview personalization options coming soon'**
  String get homeSettingsDesc;

  /// No description provided for @homeAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get homeAbout;

  /// No description provided for @homeAboutDesc.
  ///
  /// In en, this message translates to:
  /// **'Learn more about Misa Rin'**
  String get homeAboutDesc;

  /// No description provided for @createProjectFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create project: {error}'**
  String createProjectFailed(Object error);

  /// No description provided for @openProjectDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Project'**
  String get openProjectDialogTitle;

  /// No description provided for @openingProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Opening project…'**
  String get openingProjectTitle;

  /// No description provided for @openingProjectMessage.
  ///
  /// In en, this message translates to:
  /// **'Loading {fileName}'**
  String openingProjectMessage(Object fileName);

  /// No description provided for @cannotReadPsdContent.
  ///
  /// In en, this message translates to:
  /// **'Unable to read PSD file contents.'**
  String get cannotReadPsdContent;

  /// No description provided for @cannotReadSai2Content.
  ///
  /// In en, this message translates to:
  /// **'Unable to read SAI2 file contents.'**
  String get cannotReadSai2Content;

  /// No description provided for @cannotReadProjectFileContent.
  ///
  /// In en, this message translates to:
  /// **'Unable to read project file contents.'**
  String get cannotReadProjectFileContent;

  /// No description provided for @openedProjectInfo.
  ///
  /// In en, this message translates to:
  /// **'Opened project: {name}'**
  String openedProjectInfo(Object name);

  /// No description provided for @openProjectFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open project: {error}'**
  String openProjectFailed(Object error);

  /// No description provided for @importImageDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Image'**
  String get importImageDialogTitle;

  /// No description provided for @importedImageInfo.
  ///
  /// In en, this message translates to:
  /// **'Imported image: {name}'**
  String importedImageInfo(Object name);

  /// No description provided for @importImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import image: {error}'**
  String importImageFailed(Object error);

  /// No description provided for @clipboardNoBitmapFound.
  ///
  /// In en, this message translates to:
  /// **'No bitmap found in clipboard to import.'**
  String get clipboardNoBitmapFound;

  /// No description provided for @clipboardImageDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Clipboard Image'**
  String get clipboardImageDefaultName;

  /// No description provided for @importedClipboardImageInfo.
  ///
  /// In en, this message translates to:
  /// **'Imported clipboard image'**
  String get importedClipboardImageInfo;

  /// No description provided for @importClipboardImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import clipboard image: {error}'**
  String importClipboardImageFailed(Object error);

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About Misa Rin'**
  String get aboutTitle;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'Misa Rin is an app focused on creative drawing and project management, designed to provide creators with a smooth painting experience and reliable project archiving.'**
  String get aboutDescription;

  /// No description provided for @aboutAppIdLabel.
  ///
  /// In en, this message translates to:
  /// **'App ID'**
  String get aboutAppIdLabel;

  /// No description provided for @aboutAppVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutAppVersionLabel;

  /// No description provided for @aboutDeveloperLabel.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get aboutDeveloperLabel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsTabGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsTabGeneral;

  /// No description provided for @settingsTabInput.
  ///
  /// In en, this message translates to:
  /// **'Input & Brushes'**
  String get settingsTabInput;

  /// No description provided for @settingsTabStorage.
  ///
  /// In en, this message translates to:
  /// **'History & Storage'**
  String get settingsTabStorage;

  /// No description provided for @settingsTabAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsTabAbout;

  /// No description provided for @tabletTest.
  ///
  /// In en, this message translates to:
  /// **'Tablet Test'**
  String get tabletTest;

  /// No description provided for @restoreDefaults.
  ///
  /// In en, this message translates to:
  /// **'Restore Defaults'**
  String get restoreDefaults;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get languageJapanese;

  /// No description provided for @languageKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get languageKorean;

  /// No description provided for @languageChineseSimplified.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Simplified)'**
  String get languageChineseSimplified;

  /// No description provided for @languageChineseTraditional.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Traditional)'**
  String get languageChineseTraditional;

  /// No description provided for @themeModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get themeModeLabel;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @stylusPressureSettingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Stylus Pressure'**
  String get stylusPressureSettingsLabel;

  /// No description provided for @enableStylusPressure.
  ///
  /// In en, this message translates to:
  /// **'Enable stylus pressure'**
  String get enableStylusPressure;

  /// No description provided for @responseCurveLabel.
  ///
  /// In en, this message translates to:
  /// **'Response curve'**
  String get responseCurveLabel;

  /// No description provided for @responseCurveDesc.
  ///
  /// In en, this message translates to:
  /// **'Adjust how pressure transitions into stroke width.'**
  String get responseCurveDesc;

  /// No description provided for @brushSizeSliderRangeLabel.
  ///
  /// In en, this message translates to:
  /// **'Brush size slider range'**
  String get brushSizeSliderRangeLabel;

  /// No description provided for @brushSizeSliderRangeDesc.
  ///
  /// In en, this message translates to:
  /// **'Affects the brush size slider in the tool panel, helping you switch precision quickly.'**
  String get brushSizeSliderRangeDesc;

  /// No description provided for @penSliderRangeCompact.
  ///
  /// In en, this message translates to:
  /// **'1 - 60 px (coarse)'**
  String get penSliderRangeCompact;

  /// No description provided for @penSliderRangeMedium.
  ///
  /// In en, this message translates to:
  /// **'0.1 - 500 px (medium)'**
  String get penSliderRangeMedium;

  /// No description provided for @penSliderRangeFull.
  ///
  /// In en, this message translates to:
  /// **'0.01 - 1000 px (full)'**
  String get penSliderRangeFull;

  /// No description provided for @historyLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Undo/Redo limit'**
  String get historyLimitLabel;

  /// No description provided for @historyLimitCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current limit: {count} steps'**
  String historyLimitCurrent(Object count);

  /// No description provided for @historyLimitDesc.
  ///
  /// In en, this message translates to:
  /// **'Adjust how many undo/redo steps are kept. Range {min}-{max}.'**
  String historyLimitDesc(Object min, Object max);

  /// No description provided for @canvasBackendLabel.
  ///
  /// In en, this message translates to:
  /// **'Canvas backend'**
  String get canvasBackendLabel;

  /// No description provided for @canvasBackendGpu.
  ///
  /// In en, this message translates to:
  /// **'Rust WGPU'**
  String get canvasBackendGpu;

  /// No description provided for @canvasBackendCpu.
  ///
  /// In en, this message translates to:
  /// **'Rust CPU'**
  String get canvasBackendCpu;

  /// No description provided for @canvasBackendRestartHint.
  ///
  /// In en, this message translates to:
  /// **'Canvas backend change will take effect after restart.'**
  String get canvasBackendRestartHint;

  /// No description provided for @developerOptionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Developer Options'**
  String get developerOptionsLabel;

  /// No description provided for @performanceOverlayLabel.
  ///
  /// In en, this message translates to:
  /// **'Performance overlay'**
  String get performanceOverlayLabel;

  /// No description provided for @performanceOverlayDesc.
  ///
  /// In en, this message translates to:
  /// **'Shows a Flutter Performance Pulse dashboard in the corner with FPS, CPU, memory, disk, etc.'**
  String get performanceOverlayDesc;

  /// No description provided for @tabletInputTestTitle.
  ///
  /// In en, this message translates to:
  /// **'Tablet Input Test'**
  String get tabletInputTestTitle;

  /// No description provided for @recentProjectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentProjectsTitle;

  /// No description provided for @recentProjectsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load recent projects: {error}'**
  String recentProjectsLoadFailed(Object error);

  /// No description provided for @recentProjectsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recent projects'**
  String get recentProjectsEmpty;

  /// No description provided for @openFileLocation.
  ///
  /// In en, this message translates to:
  /// **'Reveal in File Manager'**
  String get openFileLocation;

  /// No description provided for @lastOpened.
  ///
  /// In en, this message translates to:
  /// **'Last opened: {date}'**
  String lastOpened(Object date);

  /// No description provided for @canvasSize.
  ///
  /// In en, this message translates to:
  /// **'Canvas size: {width} x {height}'**
  String canvasSize(Object width, Object height);

  /// No description provided for @menuFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get menuFile;

  /// No description provided for @menuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get menuEdit;

  /// No description provided for @menuImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get menuImage;

  /// No description provided for @menuLayer.
  ///
  /// In en, this message translates to:
  /// **'Layer'**
  String get menuLayer;

  /// No description provided for @menuSelection.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get menuSelection;

  /// No description provided for @menuFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get menuFilter;

  /// No description provided for @menuTool.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get menuTool;

  /// No description provided for @menuView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get menuView;

  /// No description provided for @menuWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get menuWorkspace;

  /// No description provided for @menuWindow.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get menuWindow;

  /// No description provided for @menuRoot.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menuRoot;

  /// No description provided for @menuAbout.
  ///
  /// In en, this message translates to:
  /// **'About Misa Rin'**
  String get menuAbout;

  /// No description provided for @menuPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences…'**
  String get menuPreferences;

  /// No description provided for @menuNewEllipsis.
  ///
  /// In en, this message translates to:
  /// **'New…'**
  String get menuNewEllipsis;

  /// No description provided for @menuOpenEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Open…'**
  String get menuOpenEllipsis;

  /// No description provided for @menuImportImageEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Import Image…'**
  String get menuImportImageEllipsis;

  /// No description provided for @menuImportImageFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Import Image from Clipboard'**
  String get menuImportImageFromClipboard;

  /// No description provided for @menuSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get menuSave;

  /// No description provided for @menuSaveAsEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Save As…'**
  String get menuSaveAsEllipsis;

  /// No description provided for @menuExportEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get menuExportEllipsis;

  /// No description provided for @menuCloseAll.
  ///
  /// In en, this message translates to:
  /// **'Close All'**
  String get menuCloseAll;

  /// No description provided for @menuUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get menuUndo;

  /// No description provided for @menuRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get menuRedo;

  /// No description provided for @menuCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get menuCut;

  /// No description provided for @menuCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get menuCopy;

  /// No description provided for @menuPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get menuPaste;

  /// No description provided for @menuImageTransform.
  ///
  /// In en, this message translates to:
  /// **'Transform'**
  String get menuImageTransform;

  /// No description provided for @menuRotate90CW.
  ///
  /// In en, this message translates to:
  /// **'Rotate 90° CW'**
  String get menuRotate90CW;

  /// No description provided for @menuRotate90CCW.
  ///
  /// In en, this message translates to:
  /// **'Rotate 90° CCW'**
  String get menuRotate90CCW;

  /// No description provided for @menuRotate180CW.
  ///
  /// In en, this message translates to:
  /// **'Rotate 180° CW'**
  String get menuRotate180CW;

  /// No description provided for @menuRotate180CCW.
  ///
  /// In en, this message translates to:
  /// **'Rotate 180° CCW'**
  String get menuRotate180CCW;

  /// No description provided for @menuFlipHorizontal.
  ///
  /// In en, this message translates to:
  /// **'Flip Horizontal'**
  String get menuFlipHorizontal;

  /// No description provided for @menuFlipVertical.
  ///
  /// In en, this message translates to:
  /// **'Flip Vertical'**
  String get menuFlipVertical;

  /// No description provided for @menuImageSizeEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Image Size…'**
  String get menuImageSizeEllipsis;

  /// No description provided for @menuCanvasSizeEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Canvas Size…'**
  String get menuCanvasSizeEllipsis;

  /// No description provided for @menuNewSubmenu.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get menuNewSubmenu;

  /// No description provided for @menuNewLayerEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Layer…'**
  String get menuNewLayerEllipsis;

  /// No description provided for @menuMergeDown.
  ///
  /// In en, this message translates to:
  /// **'Merge Down'**
  String get menuMergeDown;

  /// No description provided for @menuRasterize.
  ///
  /// In en, this message translates to:
  /// **'Rasterize'**
  String get menuRasterize;

  /// No description provided for @menuTransform.
  ///
  /// In en, this message translates to:
  /// **'Transform'**
  String get menuTransform;

  /// No description provided for @menuSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get menuSelectAll;

  /// No description provided for @menuDeselect.
  ///
  /// In en, this message translates to:
  /// **'Deselect'**
  String get menuDeselect;

  /// No description provided for @menuInvertSelection.
  ///
  /// In en, this message translates to:
  /// **'Invert Selection'**
  String get menuInvertSelection;

  /// No description provided for @menuPalette.
  ///
  /// In en, this message translates to:
  /// **'Palette'**
  String get menuPalette;

  /// No description provided for @menuGeneratePaletteFromCanvasEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Generate palette from current canvas…'**
  String get menuGeneratePaletteFromCanvasEllipsis;

  /// No description provided for @menuGenerateGradientPalette.
  ///
  /// In en, this message translates to:
  /// **'Generate gradient palette from current colors'**
  String get menuGenerateGradientPalette;

  /// No description provided for @menuImportPaletteEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Import palette…'**
  String get menuImportPaletteEllipsis;

  /// No description provided for @menuReferenceImage.
  ///
  /// In en, this message translates to:
  /// **'Reference Images'**
  String get menuReferenceImage;

  /// No description provided for @menuCreateReferenceImage.
  ///
  /// In en, this message translates to:
  /// **'Create Reference Image'**
  String get menuCreateReferenceImage;

  /// No description provided for @menuImportReferenceImageEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Import Reference Image…'**
  String get menuImportReferenceImageEllipsis;

  /// No description provided for @menuReferenceModel.
  ///
  /// In en, this message translates to:
  /// **'Reference Model'**
  String get menuReferenceModel;

  /// No description provided for @menuReferenceModelSteve.
  ///
  /// In en, this message translates to:
  /// **'Steve Model'**
  String get menuReferenceModelSteve;

  /// No description provided for @menuReferenceModelAlex.
  ///
  /// In en, this message translates to:
  /// **'Alex Model'**
  String get menuReferenceModelAlex;

  /// No description provided for @menuReferenceModelCube.
  ///
  /// In en, this message translates to:
  /// **'Cube Model'**
  String get menuReferenceModelCube;

  /// No description provided for @menuImportReferenceModelEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Import Model…'**
  String get menuImportReferenceModelEllipsis;

  /// No description provided for @referenceModelRefreshTexture.
  ///
  /// In en, this message translates to:
  /// **'Refresh Texture'**
  String get referenceModelRefreshTexture;

  /// No description provided for @referenceModelRefreshTextureDesc.
  ///
  /// In en, this message translates to:
  /// **'Generate a model texture from the current canvas'**
  String get referenceModelRefreshTextureDesc;

  /// No description provided for @referenceModelResetView.
  ///
  /// In en, this message translates to:
  /// **'Reset View'**
  String get referenceModelResetView;

  /// No description provided for @referenceModelResetViewDesc.
  ///
  /// In en, this message translates to:
  /// **'Reset rotation and zoom'**
  String get referenceModelResetViewDesc;

  /// No description provided for @referenceModelSixView.
  ///
  /// In en, this message translates to:
  /// **'6 Views'**
  String get referenceModelSixView;

  /// No description provided for @referenceModelSixViewDesc.
  ///
  /// In en, this message translates to:
  /// **'Split the viewport into a 2×3 grid (Front/Back/Top/Bottom/Left/Right)'**
  String get referenceModelSixViewDesc;

  /// No description provided for @referenceModelSingleView.
  ///
  /// In en, this message translates to:
  /// **'Single View'**
  String get referenceModelSingleView;

  /// No description provided for @referenceModelSingleViewDesc.
  ///
  /// In en, this message translates to:
  /// **'Back to single view (drag to rotate)'**
  String get referenceModelSingleViewDesc;

  /// No description provided for @referenceModelViewFront.
  ///
  /// In en, this message translates to:
  /// **'Front View'**
  String get referenceModelViewFront;

  /// No description provided for @referenceModelViewBack.
  ///
  /// In en, this message translates to:
  /// **'Back View'**
  String get referenceModelViewBack;

  /// No description provided for @referenceModelViewTop.
  ///
  /// In en, this message translates to:
  /// **'Top View'**
  String get referenceModelViewTop;

  /// No description provided for @referenceModelViewBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom View'**
  String get referenceModelViewBottom;

  /// No description provided for @referenceModelViewLeft.
  ///
  /// In en, this message translates to:
  /// **'Left View'**
  String get referenceModelViewLeft;

  /// No description provided for @referenceModelViewRight.
  ///
  /// In en, this message translates to:
  /// **'Right View'**
  String get referenceModelViewRight;

  /// No description provided for @menuZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom In'**
  String get menuZoomIn;

  /// No description provided for @menuZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom Out'**
  String get menuZoomOut;

  /// No description provided for @menuShowGrid.
  ///
  /// In en, this message translates to:
  /// **'Show Grid'**
  String get menuShowGrid;

  /// No description provided for @menuHideGrid.
  ///
  /// In en, this message translates to:
  /// **'Hide Grid'**
  String get menuHideGrid;

  /// No description provided for @menuBlackWhite.
  ///
  /// In en, this message translates to:
  /// **'Black & White'**
  String get menuBlackWhite;

  /// No description provided for @menuDisableBlackWhite.
  ///
  /// In en, this message translates to:
  /// **'Disable Black & White'**
  String get menuDisableBlackWhite;

  /// No description provided for @menuMirrorPreview.
  ///
  /// In en, this message translates to:
  /// **'Mirror Preview'**
  String get menuMirrorPreview;

  /// No description provided for @menuDisableMirror.
  ///
  /// In en, this message translates to:
  /// **'Disable Mirror'**
  String get menuDisableMirror;

  /// No description provided for @menuTiledPreview.
  ///
  /// In en, this message translates to:
  /// **'Tiled Preview'**
  String get menuTiledPreview;

  /// No description provided for @menuDisableTiledPreview.
  ///
  /// In en, this message translates to:
  /// **'Disable Tiled Preview'**
  String get menuDisableTiledPreview;

  /// No description provided for @menuShowPerspectiveGuide.
  ///
  /// In en, this message translates to:
  /// **'Show Perspective Guide'**
  String get menuShowPerspectiveGuide;

  /// No description provided for @menuHidePerspectiveGuide.
  ///
  /// In en, this message translates to:
  /// **'Hide Perspective Guide'**
  String get menuHidePerspectiveGuide;

  /// No description provided for @menuPerspectiveMode.
  ///
  /// In en, this message translates to:
  /// **'Perspective Mode'**
  String get menuPerspectiveMode;

  /// No description provided for @menuPerspective1Point.
  ///
  /// In en, this message translates to:
  /// **'1-Point'**
  String get menuPerspective1Point;

  /// No description provided for @menuPerspective2Point.
  ///
  /// In en, this message translates to:
  /// **'2-Point'**
  String get menuPerspective2Point;

  /// No description provided for @menuPerspective3Point.
  ///
  /// In en, this message translates to:
  /// **'3-Point'**
  String get menuPerspective3Point;

  /// No description provided for @menuWorkspaceDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get menuWorkspaceDefault;

  /// No description provided for @menuWorkspaceSai2.
  ///
  /// In en, this message translates to:
  /// **'SAI2'**
  String get menuWorkspaceSai2;

  /// No description provided for @menuWorkspaceCsp.
  ///
  /// In en, this message translates to:
  /// **'CSP'**
  String get menuWorkspaceCsp;

  /// No description provided for @menuSwitchWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Switch Workspace'**
  String get menuSwitchWorkspace;

  /// No description provided for @menuResetWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Reset Workspace'**
  String get menuResetWorkspace;

  /// No description provided for @menuEdgeSofteningEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Edge Softening…'**
  String get menuEdgeSofteningEllipsis;

  /// No description provided for @menuNarrowLinesEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Narrow Lines…'**
  String get menuNarrowLinesEllipsis;

  /// No description provided for @menuExpandFillEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Expand Fill…'**
  String get menuExpandFillEllipsis;

  /// No description provided for @menuGaussianBlurEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Gaussian Blur…'**
  String get menuGaussianBlurEllipsis;

  /// No description provided for @menuRemoveColorLeakEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Remove Color Leak…'**
  String get menuRemoveColorLeakEllipsis;

  /// No description provided for @menuHueSaturationEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Hue/Saturation…'**
  String get menuHueSaturationEllipsis;

  /// No description provided for @menuBrightnessContrastEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Brightness/Contrast…'**
  String get menuBrightnessContrastEllipsis;

  /// No description provided for @menuColorRangeEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Color Range…'**
  String get menuColorRangeEllipsis;

  /// No description provided for @menuBlackWhiteEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Black & White…'**
  String get menuBlackWhiteEllipsis;

  /// No description provided for @menuBinarizeEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Binarize…'**
  String get menuBinarizeEllipsis;

  /// No description provided for @menuScanPaperDrawingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Scan Paper Drawing…'**
  String get menuScanPaperDrawingEllipsis;

  /// No description provided for @menuScanPaperDrawing.
  ///
  /// In en, this message translates to:
  /// **'Scan Paper Drawing'**
  String get menuScanPaperDrawing;

  /// No description provided for @menuInvertColors.
  ///
  /// In en, this message translates to:
  /// **'Invert Colors'**
  String get menuInvertColors;

  /// No description provided for @canvasSizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Canvas Size'**
  String get canvasSizeTitle;

  /// No description provided for @canvasSizeAnchorLabel.
  ///
  /// In en, this message translates to:
  /// **'Anchor'**
  String get canvasSizeAnchorLabel;

  /// No description provided for @canvasSizeAnchorDesc.
  ///
  /// In en, this message translates to:
  /// **'Resize canvas based on anchor point.'**
  String get canvasSizeAnchorDesc;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @projectManagerTitle.
  ///
  /// In en, this message translates to:
  /// **'Project Manager'**
  String get projectManagerTitle;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get openFolder;

  /// No description provided for @deleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete Selected ({count})'**
  String deleteSelected(Object count);

  /// No description provided for @imageSizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Image Size'**
  String get imageSizeTitle;

  /// No description provided for @lockAspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Lock Aspect Ratio'**
  String get lockAspectRatio;

  /// No description provided for @realtimeParams.
  ///
  /// In en, this message translates to:
  /// **'Realtime Parameters'**
  String get realtimeParams;

  /// No description provided for @clearScribble.
  ///
  /// In en, this message translates to:
  /// **'Clear Scribble'**
  String get clearScribble;

  /// No description provided for @newCanvasSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'New Canvas Settings'**
  String get newCanvasSettingsTitle;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @colorWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get colorWhite;

  /// No description provided for @colorLightGray.
  ///
  /// In en, this message translates to:
  /// **'Light Gray'**
  String get colorLightGray;

  /// No description provided for @colorBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get colorBlack;

  /// No description provided for @colorTransparent.
  ///
  /// In en, this message translates to:
  /// **'Transparent'**
  String get colorTransparent;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @currentPreset.
  ///
  /// In en, this message translates to:
  /// **'Current Preset: {name}'**
  String currentPreset(Object name);

  /// No description provided for @exportSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Settings'**
  String get exportSettingsTitle;

  /// No description provided for @exportTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Export Type'**
  String get exportTypeLabel;

  /// No description provided for @exportTypeBitmap.
  ///
  /// In en, this message translates to:
  /// **'Bitmap'**
  String get exportTypeBitmap;

  /// No description provided for @exportTypePng.
  ///
  /// In en, this message translates to:
  /// **'Bitmap PNG'**
  String get exportTypePng;

  /// No description provided for @exportTypeSvg.
  ///
  /// In en, this message translates to:
  /// **'Vector SVG (Experimental)'**
  String get exportTypeSvg;

  /// No description provided for @exportBitmapFormatLabel.
  ///
  /// In en, this message translates to:
  /// **'Bitmap Format'**
  String get exportBitmapFormatLabel;

  /// No description provided for @exportBitmapFormatPng.
  ///
  /// In en, this message translates to:
  /// **'PNG'**
  String get exportBitmapFormatPng;

  /// No description provided for @exportBitmapFormatWebp.
  ///
  /// In en, this message translates to:
  /// **'WebP'**
  String get exportBitmapFormatWebp;

  /// No description provided for @webpCompressionLabel.
  ///
  /// In en, this message translates to:
  /// **'WebP Compression'**
  String get webpCompressionLabel;

  /// No description provided for @webpLossless.
  ///
  /// In en, this message translates to:
  /// **'Lossless'**
  String get webpLossless;

  /// No description provided for @webpLossy.
  ///
  /// In en, this message translates to:
  /// **'Lossy'**
  String get webpLossy;

  /// No description provided for @webpQualityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quality: {value}'**
  String webpQualityLabel(Object value);

  /// No description provided for @exportScaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Export Scale'**
  String get exportScaleLabel;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @exportOutputSize.
  ///
  /// In en, this message translates to:
  /// **'Output Size: {width} x {height} px'**
  String exportOutputSize(Object width, Object height);

  /// No description provided for @exportAntialiasingLabel.
  ///
  /// In en, this message translates to:
  /// **'Antialiasing'**
  String get exportAntialiasingLabel;

  /// No description provided for @enableAntialiasing.
  ///
  /// In en, this message translates to:
  /// **'Enable Antialiasing'**
  String get enableAntialiasing;

  /// No description provided for @vectorParamsLabel.
  ///
  /// In en, this message translates to:
  /// **'Vector Parameters'**
  String get vectorParamsLabel;

  /// No description provided for @vectorMaxColors.
  ///
  /// In en, this message translates to:
  /// **'Max Colors: {count}'**
  String vectorMaxColors(Object count);

  /// No description provided for @vectorSimplify.
  ///
  /// In en, this message translates to:
  /// **'Simplify Strength: {value}'**
  String vectorSimplify(Object value);

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @invalidDimensions.
  ///
  /// In en, this message translates to:
  /// **'Please enter valid dimensions (px).'**
  String get invalidDimensions;

  /// No description provided for @widthPx.
  ///
  /// In en, this message translates to:
  /// **'Width (px)'**
  String get widthPx;

  /// No description provided for @heightPx.
  ///
  /// In en, this message translates to:
  /// **'Height (px)'**
  String get heightPx;

  /// No description provided for @noAutosavedProjects.
  ///
  /// In en, this message translates to:
  /// **'No autosaved projects'**
  String get noAutosavedProjects;

  /// No description provided for @revealProjectLocation.
  ///
  /// In en, this message translates to:
  /// **'Reveal selected project location'**
  String get revealProjectLocation;

  /// No description provided for @deleteSelectedProjects.
  ///
  /// In en, this message translates to:
  /// **'Delete selected projects'**
  String get deleteSelectedProjects;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String loadFailed(Object error);

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete: {error}'**
  String deleteFailed(Object error);

  /// No description provided for @projectFileInfo.
  ///
  /// In en, this message translates to:
  /// **'Size: {size} · Modified: {date}'**
  String projectFileInfo(Object size, Object date);

  /// No description provided for @projectCanvasInfo.
  ///
  /// In en, this message translates to:
  /// **'Canvas {width} x {height}'**
  String projectCanvasInfo(Object width, Object height);

  /// No description provided for @samplingMethod.
  ///
  /// In en, this message translates to:
  /// **'Sampling Method'**
  String get samplingMethod;

  /// No description provided for @currentSize.
  ///
  /// In en, this message translates to:
  /// **'Current Size: {width} x {height} px'**
  String currentSize(Object width, Object height);

  /// No description provided for @samplingNearestLabel.
  ///
  /// In en, this message translates to:
  /// **'Nearest Neighbor'**
  String get samplingNearestLabel;

  /// No description provided for @samplingNearestDesc.
  ///
  /// In en, this message translates to:
  /// **'Preserves hard edges, good for pixel art.'**
  String get samplingNearestDesc;

  /// No description provided for @samplingBilinearLabel.
  ///
  /// In en, this message translates to:
  /// **'Bilinear'**
  String get samplingBilinearLabel;

  /// No description provided for @samplingBilinearDesc.
  ///
  /// In en, this message translates to:
  /// **'Smooth interpolation, good for general resizing.'**
  String get samplingBilinearDesc;

  /// No description provided for @tabletPressureLatest.
  ///
  /// In en, this message translates to:
  /// **'Latest Pressure'**
  String get tabletPressureLatest;

  /// No description provided for @tabletPressureMin.
  ///
  /// In en, this message translates to:
  /// **'Pressure Min'**
  String get tabletPressureMin;

  /// No description provided for @tabletPressureMax.
  ///
  /// In en, this message translates to:
  /// **'Pressure Max'**
  String get tabletPressureMax;

  /// No description provided for @tabletRadiusPx.
  ///
  /// In en, this message translates to:
  /// **'Estimated Radius (px)'**
  String get tabletRadiusPx;

  /// No description provided for @tabletTiltRad.
  ///
  /// In en, this message translates to:
  /// **'Tilt (radians)'**
  String get tabletTiltRad;

  /// No description provided for @tabletSampleCount.
  ///
  /// In en, this message translates to:
  /// **'Sample Count'**
  String get tabletSampleCount;

  /// No description provided for @tabletSampleRateHz.
  ///
  /// In en, this message translates to:
  /// **'Sample Rate (Hz)'**
  String get tabletSampleRateHz;

  /// No description provided for @tabletPointerType.
  ///
  /// In en, this message translates to:
  /// **'Pointer Type'**
  String get tabletPointerType;

  /// No description provided for @pointerKindMouse.
  ///
  /// In en, this message translates to:
  /// **'Mouse'**
  String get pointerKindMouse;

  /// No description provided for @pointerKindTouch.
  ///
  /// In en, this message translates to:
  /// **'Touch'**
  String get pointerKindTouch;

  /// No description provided for @pointerKindStylus.
  ///
  /// In en, this message translates to:
  /// **'Stylus'**
  String get pointerKindStylus;

  /// No description provided for @pointerKindInvertedStylus.
  ///
  /// In en, this message translates to:
  /// **'Stylus (Eraser)'**
  String get pointerKindInvertedStylus;

  /// No description provided for @pointerKindTrackpad.
  ///
  /// In en, this message translates to:
  /// **'Trackpad'**
  String get pointerKindTrackpad;

  /// No description provided for @pointerKindUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get pointerKindUnknown;

  /// No description provided for @presetMobilePortrait.
  ///
  /// In en, this message translates to:
  /// **'Mobile Portrait (1080 x 1920)'**
  String get presetMobilePortrait;

  /// No description provided for @presetSquare.
  ///
  /// In en, this message translates to:
  /// **'Square (1024 x 1024)'**
  String get presetSquare;

  /// No description provided for @presetPixelArt.
  ///
  /// In en, this message translates to:
  /// **'Pixel Art ({width} x {height})'**
  String presetPixelArt(Object width, Object height);

  /// No description provided for @untitledProject.
  ///
  /// In en, this message translates to:
  /// **'Untitled Project'**
  String get untitledProject;

  /// No description provided for @invalidResolution.
  ///
  /// In en, this message translates to:
  /// **'Please enter valid resolution'**
  String get invalidResolution;

  /// No description provided for @minResolutionError.
  ///
  /// In en, this message translates to:
  /// **'Resolution cannot be less than {value} px'**
  String minResolutionError(Object value);

  /// No description provided for @maxResolutionError.
  ///
  /// In en, this message translates to:
  /// **'Resolution cannot exceed {value} px'**
  String maxResolutionError(Object value);

  /// No description provided for @projectName.
  ///
  /// In en, this message translates to:
  /// **'Project Name'**
  String get projectName;

  /// No description provided for @workspacePreset.
  ///
  /// In en, this message translates to:
  /// **'Workspace Preset'**
  String get workspacePreset;

  /// No description provided for @workspacePresetDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically apply common tool settings when creating a canvas.'**
  String get workspacePresetDesc;

  /// No description provided for @workspaceIllustration.
  ///
  /// In en, this message translates to:
  /// **'Illustration'**
  String get workspaceIllustration;

  /// No description provided for @workspaceIllustrationDesc.
  ///
  /// In en, this message translates to:
  /// **'Brush: Pencil, Edge softening: 1'**
  String get workspaceIllustrationDesc;

  /// No description provided for @workspaceIllustrationDesc2.
  ///
  /// In en, this message translates to:
  /// **'Streamline: Unchanged'**
  String get workspaceIllustrationDesc2;

  /// No description provided for @workspaceCelShading.
  ///
  /// In en, this message translates to:
  /// **'Cel Shading'**
  String get workspaceCelShading;

  /// No description provided for @workspaceCelShadingDesc1.
  ///
  /// In en, this message translates to:
  /// **'Brush: Cel Brush, Edge softening: 0'**
  String get workspaceCelShadingDesc1;

  /// No description provided for @workspaceCelShadingDesc2.
  ///
  /// In en, this message translates to:
  /// **'Fill tool expand to line: On'**
  String get workspaceCelShadingDesc2;

  /// No description provided for @workspaceCelShadingDesc3.
  ///
  /// In en, this message translates to:
  /// **'Fill tool antialiasing: Off'**
  String get workspaceCelShadingDesc3;

  /// No description provided for @workspacePixel.
  ///
  /// In en, this message translates to:
  /// **'Pixel'**
  String get workspacePixel;

  /// No description provided for @workspacePixelDesc1.
  ///
  /// In en, this message translates to:
  /// **'Brush: Pixel, Brush/Fill tool antialiasing: 0'**
  String get workspacePixelDesc1;

  /// No description provided for @workspacePixelDesc2.
  ///
  /// In en, this message translates to:
  /// **'Show Grid: On'**
  String get workspacePixelDesc2;

  /// No description provided for @workspacePixelDesc3.
  ///
  /// In en, this message translates to:
  /// **'Vector Drawing: Unchanged'**
  String get workspacePixelDesc3;

  /// No description provided for @workspacePixelDesc4.
  ///
  /// In en, this message translates to:
  /// **'Stabilizer: 0'**
  String get workspacePixelDesc4;

  /// No description provided for @workspaceDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get workspaceDefault;

  /// No description provided for @workspaceDefaultDesc.
  ///
  /// In en, this message translates to:
  /// **'Do not change current tool settings'**
  String get workspaceDefaultDesc;

  /// No description provided for @resolutionPreset.
  ///
  /// In en, this message translates to:
  /// **'Resolution Preset'**
  String get resolutionPreset;

  /// No description provided for @customResolution.
  ///
  /// In en, this message translates to:
  /// **'Custom Resolution'**
  String get customResolution;

  /// No description provided for @swapDimensions.
  ///
  /// In en, this message translates to:
  /// **'Swap Width/Height'**
  String get swapDimensions;

  /// No description provided for @finalSizePreview.
  ///
  /// In en, this message translates to:
  /// **'Final Size: {width} x {height} px (Ratio {ratio})'**
  String finalSizePreview(Object width, Object height, Object ratio);

  /// No description provided for @enterValidDimensions.
  ///
  /// In en, this message translates to:
  /// **'Please enter valid dimensions'**
  String get enterValidDimensions;

  /// No description provided for @backgroundColor.
  ///
  /// In en, this message translates to:
  /// **'Background Color'**
  String get backgroundColor;

  /// No description provided for @exportBitmapDesc.
  ///
  /// In en, this message translates to:
  /// **'Suitable for regular exports requiring raster format, supports scaling and antialiasing.'**
  String get exportBitmapDesc;

  /// No description provided for @exportVectorDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically transcribes current canvas to vector paths, suitable for editing in vector tools.'**
  String get exportVectorDesc;

  /// No description provided for @exampleScale.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1.0'**
  String get exampleScale;

  /// No description provided for @enterPositiveValue.
  ///
  /// In en, this message translates to:
  /// **'Please enter a value > 0'**
  String get enterPositiveValue;

  /// No description provided for @antialiasingBeforeExport.
  ///
  /// In en, this message translates to:
  /// **'Antialiasing before export'**
  String get antialiasingBeforeExport;

  /// No description provided for @brushAntialiasing.
  ///
  /// In en, this message translates to:
  /// **'Brush antialiasing'**
  String get brushAntialiasing;

  /// No description provided for @bucketAntialiasing.
  ///
  /// In en, this message translates to:
  /// **'Fill antialiasing'**
  String get bucketAntialiasing;

  /// No description provided for @antialiasingDesc.
  ///
  /// In en, this message translates to:
  /// **'Smoothens edges while preserving line density, a tribute to the texture of Retas animation software.'**
  String get antialiasingDesc;

  /// No description provided for @levelLabel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String levelLabel(Object level);

  /// No description provided for @vectorExportSize.
  ///
  /// In en, this message translates to:
  /// **'Export Size: {width} x {height} (Use Canvas Size)'**
  String vectorExportSize(Object width, Object height);

  /// No description provided for @colorCount.
  ///
  /// In en, this message translates to:
  /// **'{count} colors'**
  String colorCount(Object count);

  /// No description provided for @vectorSimplifyDesc.
  ///
  /// In en, this message translates to:
  /// **'Fewer colors and higher simplification yield simpler SVG; too low values result in too many nodes.'**
  String get vectorSimplifyDesc;

  /// No description provided for @antialiasNone.
  ///
  /// In en, this message translates to:
  /// **'Level 0 (Off): Preserves pixel hard edges, no antialiasing.'**
  String get antialiasNone;

  /// No description provided for @antialiasLow.
  ///
  /// In en, this message translates to:
  /// **'Level 1 (Low): Slight softening of aliasing, smoothing edges while maintaining line density.'**
  String get antialiasLow;

  /// No description provided for @antialiasMedium.
  ///
  /// In en, this message translates to:
  /// **'Level 2 (Standard): Balance sharpness and softening, presenting clean lines like Retas.'**
  String get antialiasMedium;

  /// No description provided for @antialiasHigh.
  ///
  /// In en, this message translates to:
  /// **'Level 3 (High): Strongest softening effect, for edges requiring soft transitions or large scaling.'**
  String get antialiasHigh;

  /// No description provided for @tolerance.
  ///
  /// In en, this message translates to:
  /// **'Tolerance'**
  String get tolerance;

  /// No description provided for @fillGap.
  ///
  /// In en, this message translates to:
  /// **'Fill Gap'**
  String get fillGap;

  /// No description provided for @sampleAllLayers.
  ///
  /// In en, this message translates to:
  /// **'Sample All Layers'**
  String get sampleAllLayers;

  /// No description provided for @contiguous.
  ///
  /// In en, this message translates to:
  /// **'Contiguous'**
  String get contiguous;

  /// No description provided for @swallowColorLine.
  ///
  /// In en, this message translates to:
  /// **'Swallow Color Line'**
  String get swallowColorLine;

  /// No description provided for @swallowBlueColorLine.
  ///
  /// In en, this message translates to:
  /// **'Swallow Blue Line'**
  String get swallowBlueColorLine;

  /// No description provided for @swallowGreenColorLine.
  ///
  /// In en, this message translates to:
  /// **'Swallow Green Line'**
  String get swallowGreenColorLine;

  /// No description provided for @swallowRedColorLine.
  ///
  /// In en, this message translates to:
  /// **'Swallow Red Line'**
  String get swallowRedColorLine;

  /// No description provided for @swallowAllColorLine.
  ///
  /// In en, this message translates to:
  /// **'Swallow All Lines'**
  String get swallowAllColorLine;

  /// No description provided for @cropOutsideCanvas.
  ///
  /// In en, this message translates to:
  /// **'Crop Outside Canvas'**
  String get cropOutsideCanvas;

  /// No description provided for @noAdjustableSettings.
  ///
  /// In en, this message translates to:
  /// **'No adjustable settings for this tool'**
  String get noAdjustableSettings;

  /// No description provided for @hollowStroke.
  ///
  /// In en, this message translates to:
  /// **'Hollow Stroke'**
  String get hollowStroke;

  /// No description provided for @hollowStrokeRatio.
  ///
  /// In en, this message translates to:
  /// **'Hollow Ratio'**
  String get hollowStrokeRatio;

  /// No description provided for @eraseOccludedParts.
  ///
  /// In en, this message translates to:
  /// **'Erase Occluded Parts'**
  String get eraseOccludedParts;

  /// No description provided for @solidFill.
  ///
  /// In en, this message translates to:
  /// **'Solid Fill'**
  String get solidFill;

  /// No description provided for @autoSharpTaper.
  ///
  /// In en, this message translates to:
  /// **'Auto Sharp Taper'**
  String get autoSharpTaper;

  /// No description provided for @stylusPressure.
  ///
  /// In en, this message translates to:
  /// **'Stylus Pressure'**
  String get stylusPressure;

  /// No description provided for @touchDrawing.
  ///
  /// In en, this message translates to:
  /// **'Touch Drawing'**
  String get touchDrawing;

  /// No description provided for @simulatedPressure.
  ///
  /// In en, this message translates to:
  /// **'Simulated Pressure'**
  String get simulatedPressure;

  /// No description provided for @switchToEraser.
  ///
  /// In en, this message translates to:
  /// **'Switch to Eraser'**
  String get switchToEraser;

  /// No description provided for @vectorDrawing.
  ///
  /// In en, this message translates to:
  /// **'Vector Drawing'**
  String get vectorDrawing;

  /// No description provided for @smoothCurve.
  ///
  /// In en, this message translates to:
  /// **'Smooth Curve'**
  String get smoothCurve;

  /// No description provided for @sprayEffect.
  ///
  /// In en, this message translates to:
  /// **'Spray Effect'**
  String get sprayEffect;

  /// No description provided for @brushPreset.
  ///
  /// In en, this message translates to:
  /// **'Brush Preset'**
  String get brushPreset;

  /// No description provided for @brushPresetDesc.
  ///
  /// In en, this message translates to:
  /// **'Select a brush preset for spacing, flow, and shape.'**
  String get brushPresetDesc;

  /// No description provided for @editBrushPreset.
  ///
  /// In en, this message translates to:
  /// **'Edit Preset'**
  String get editBrushPreset;

  /// No description provided for @editBrushPresetDesc.
  ///
  /// In en, this message translates to:
  /// **'Adjust the current preset\'s internal parameters.'**
  String get editBrushPresetDesc;

  /// No description provided for @brushPresetDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Brush Preset'**
  String get brushPresetDialogTitle;

  /// No description provided for @brushPresetNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Preset Name'**
  String get brushPresetNameLabel;

  /// No description provided for @brushPresetPencil.
  ///
  /// In en, this message translates to:
  /// **'Pencil'**
  String get brushPresetPencil;

  /// No description provided for @brushPresetCel.
  ///
  /// In en, this message translates to:
  /// **'Cel Brush'**
  String get brushPresetCel;

  /// No description provided for @brushPresetPen.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get brushPresetPen;

  /// No description provided for @brushPresetScreentone.
  ///
  /// In en, this message translates to:
  /// **'Screentone'**
  String get brushPresetScreentone;

  /// No description provided for @brushPresetPixel.
  ///
  /// In en, this message translates to:
  /// **'Pixel'**
  String get brushPresetPixel;

  /// No description provided for @brushPresetDryInk.
  ///
  /// In en, this message translates to:
  /// **'Dry Ink'**
  String get brushPresetDryInk;

  /// No description provided for @brushPresetCharcoal.
  ///
  /// In en, this message translates to:
  /// **'Charcoal'**
  String get brushPresetCharcoal;

  /// No description provided for @brushPresetStarBrush.
  ///
  /// In en, this message translates to:
  /// **'Star Brush'**
  String get brushPresetStarBrush;

  /// No description provided for @brushSpacing.
  ///
  /// In en, this message translates to:
  /// **'Spacing'**
  String get brushSpacing;

  /// No description provided for @brushHardness.
  ///
  /// In en, this message translates to:
  /// **'Hardness'**
  String get brushHardness;

  /// No description provided for @brushFlow.
  ///
  /// In en, this message translates to:
  /// **'Flow'**
  String get brushFlow;

  /// No description provided for @brushScatter.
  ///
  /// In en, this message translates to:
  /// **'Scatter'**
  String get brushScatter;

  /// No description provided for @brushRotationJitter.
  ///
  /// In en, this message translates to:
  /// **'Rotation Jitter'**
  String get brushRotationJitter;

  /// No description provided for @brushSnapToPixel.
  ///
  /// In en, this message translates to:
  /// **'Snap to Pixel'**
  String get brushSnapToPixel;

  /// No description provided for @screentoneEnabled.
  ///
  /// In en, this message translates to:
  /// **'Screentone'**
  String get screentoneEnabled;

  /// No description provided for @screentoneShape.
  ///
  /// In en, this message translates to:
  /// **'Dot Shape'**
  String get screentoneShape;

  /// No description provided for @screentoneSpacing.
  ///
  /// In en, this message translates to:
  /// **'Dot Spacing'**
  String get screentoneSpacing;

  /// No description provided for @screentoneDotSize.
  ///
  /// In en, this message translates to:
  /// **'Dot Size'**
  String get screentoneDotSize;

  /// No description provided for @screentoneRotation.
  ///
  /// In en, this message translates to:
  /// **'Dot Rotation'**
  String get screentoneRotation;

  /// No description provided for @screentoneSoftness.
  ///
  /// In en, this message translates to:
  /// **'Dot Softness'**
  String get screentoneSoftness;

  /// No description provided for @brushShape.
  ///
  /// In en, this message translates to:
  /// **'Brush Shape'**
  String get brushShape;

  /// No description provided for @brushAuthorLabel.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get brushAuthorLabel;

  /// No description provided for @brushVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get brushVersionLabel;

  /// No description provided for @importBrush.
  ///
  /// In en, this message translates to:
  /// **'Import Brush'**
  String get importBrush;

  /// No description provided for @exportBrush.
  ///
  /// In en, this message translates to:
  /// **'Export Brush'**
  String get exportBrush;

  /// No description provided for @exportBrushTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Brush'**
  String get exportBrushTitle;

  /// No description provided for @unsavedBrushChangesPrompt.
  ///
  /// In en, this message translates to:
  /// **'Brush settings have been modified. Save changes?'**
  String get unsavedBrushChangesPrompt;

  /// No description provided for @discardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard Changes'**
  String get discardChanges;

  /// No description provided for @brushShapeFolderLabel.
  ///
  /// In en, this message translates to:
  /// **'Brush Shape Folder'**
  String get brushShapeFolderLabel;

  /// No description provided for @openBrushShapesFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Brush Shape Folder'**
  String get openBrushShapesFolder;

  /// No description provided for @randomRotation.
  ///
  /// In en, this message translates to:
  /// **'Random rotation'**
  String get randomRotation;

  /// No description provided for @smoothRotation.
  ///
  /// In en, this message translates to:
  /// **'Smooth rotation'**
  String get smoothRotation;

  /// No description provided for @selectionShape.
  ///
  /// In en, this message translates to:
  /// **'Selection Shape'**
  String get selectionShape;

  /// No description provided for @selectionAdditive.
  ///
  /// In en, this message translates to:
  /// **'Additive Selection'**
  String get selectionAdditive;

  /// No description provided for @selectionAdditiveDesc.
  ///
  /// In en, this message translates to:
  /// **'When enabled, new selections are added without holding Shift.'**
  String get selectionAdditiveDesc;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get fontSize;

  /// No description provided for @lineHeight.
  ///
  /// In en, this message translates to:
  /// **'Line Height'**
  String get lineHeight;

  /// No description provided for @letterSpacing.
  ///
  /// In en, this message translates to:
  /// **'Letter Spacing'**
  String get letterSpacing;

  /// No description provided for @textStroke.
  ///
  /// In en, this message translates to:
  /// **'Text Stroke'**
  String get textStroke;

  /// No description provided for @strokeWidth.
  ///
  /// In en, this message translates to:
  /// **'Stroke Width'**
  String get strokeWidth;

  /// No description provided for @strokeColor.
  ///
  /// In en, this message translates to:
  /// **'Stroke Color'**
  String get strokeColor;

  /// No description provided for @pickColor.
  ///
  /// In en, this message translates to:
  /// **'Pick Color'**
  String get pickColor;

  /// No description provided for @alignment.
  ///
  /// In en, this message translates to:
  /// **'Alignment'**
  String get alignment;

  /// No description provided for @alignCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get alignCenter;

  /// No description provided for @alignRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get alignRight;

  /// No description provided for @alignLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get alignLeft;

  /// No description provided for @orientation.
  ///
  /// In en, this message translates to:
  /// **'Orientation'**
  String get orientation;

  /// No description provided for @horizontal.
  ///
  /// In en, this message translates to:
  /// **'Horizontal'**
  String get horizontal;

  /// No description provided for @vertical.
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get vertical;

  /// No description provided for @textToolHint.
  ///
  /// In en, this message translates to:
  /// **'Use the color picker in the bottom left for text fill, and the secondary color for stroke.'**
  String get textToolHint;

  /// No description provided for @shapeType.
  ///
  /// In en, this message translates to:
  /// **'Shape Type'**
  String get shapeType;

  /// No description provided for @brushSize.
  ///
  /// In en, this message translates to:
  /// **'Brush Size'**
  String get brushSize;

  /// No description provided for @spraySize.
  ///
  /// In en, this message translates to:
  /// **'Spray Size'**
  String get spraySize;

  /// No description provided for @brushFineTune.
  ///
  /// In en, this message translates to:
  /// **'Brush Fine Tune'**
  String get brushFineTune;

  /// No description provided for @increase.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get increase;

  /// No description provided for @decrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get decrease;

  /// No description provided for @stabilizer.
  ///
  /// In en, this message translates to:
  /// **'Stabilizer'**
  String get stabilizer;

  /// No description provided for @streamline.
  ///
  /// In en, this message translates to:
  /// **'StreamLine'**
  String get streamline;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @taperEnds.
  ///
  /// In en, this message translates to:
  /// **'Taper Ends'**
  String get taperEnds;

  /// No description provided for @taperCenter.
  ///
  /// In en, this message translates to:
  /// **'Taper Center'**
  String get taperCenter;

  /// No description provided for @auto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get auto;

  /// No description provided for @softSpray.
  ///
  /// In en, this message translates to:
  /// **'Soft Spray'**
  String get softSpray;

  /// No description provided for @splatter.
  ///
  /// In en, this message translates to:
  /// **'Splatter'**
  String get splatter;

  /// No description provided for @rectSelection.
  ///
  /// In en, this message translates to:
  /// **'Rectangle Selection'**
  String get rectSelection;

  /// No description provided for @ellipseSelection.
  ///
  /// In en, this message translates to:
  /// **'Ellipse Selection'**
  String get ellipseSelection;

  /// No description provided for @polygonLasso.
  ///
  /// In en, this message translates to:
  /// **'Polygon Lasso'**
  String get polygonLasso;

  /// No description provided for @rectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get rectangle;

  /// No description provided for @ellipse.
  ///
  /// In en, this message translates to:
  /// **'Ellipse'**
  String get ellipse;

  /// No description provided for @triangle.
  ///
  /// In en, this message translates to:
  /// **'Triangle'**
  String get triangle;

  /// No description provided for @line.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get line;

  /// No description provided for @circle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get circle;

  /// No description provided for @square.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get square;

  /// No description provided for @star.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get star;

  /// No description provided for @brushSizeDesc.
  ///
  /// In en, this message translates to:
  /// **'Sets the pixel diameter of the current brush. Larger values make thicker lines, smaller for details.'**
  String get brushSizeDesc;

  /// No description provided for @spraySizeDesc.
  ///
  /// In en, this message translates to:
  /// **'Determines the radius of the spray area. Larger radius covers more area but particles are more dispersed.'**
  String get spraySizeDesc;

  /// No description provided for @toleranceDesc.
  ///
  /// In en, this message translates to:
  /// **'Controls the threshold for \'color similarity\' for Bucket or Magic Wand. Higher tolerance grabs more similar colors.'**
  String get toleranceDesc;

  /// No description provided for @fillGapDesc.
  ///
  /// In en, this message translates to:
  /// **'Attempts to close small gaps in line art during bucket fill to prevent leaks. Higher values close larger gaps but may miss very thin areas.'**
  String get fillGapDesc;

  /// No description provided for @antialiasingSliderDesc.
  ///
  /// In en, this message translates to:
  /// **'Adds multi-sampling smoothing to brush or fill edges, preserving line density. Level 0 keeps pixel style.'**
  String get antialiasingSliderDesc;

  /// No description provided for @stabilizerDesc.
  ///
  /// In en, this message translates to:
  /// **'Smooths pointer trajectory in real-time to counteract hand tremors. Higher levels are steadier but respond slower.'**
  String get stabilizerDesc;

  /// No description provided for @streamlineDesc.
  ///
  /// In en, this message translates to:
  /// **'Procreate-like StreamLine: smooths the stroke after lift-off and tween-snaps it to a cleaner path (higher levels are stronger).'**
  String get streamlineDesc;

  /// No description provided for @fontSizeDesc.
  ///
  /// In en, this message translates to:
  /// **'Adjusts the pixel height of the text for overall scaling.'**
  String get fontSizeDesc;

  /// No description provided for @lineHeightDesc.
  ///
  /// In en, this message translates to:
  /// **'Controls vertical distance between lines of text.'**
  String get lineHeightDesc;

  /// No description provided for @letterSpacingDesc.
  ///
  /// In en, this message translates to:
  /// **'Changes horizontal spacing between characters.'**
  String get letterSpacingDesc;

  /// No description provided for @strokeWidthDesc.
  ///
  /// In en, this message translates to:
  /// **'Sets the thickness of the text stroke.'**
  String get strokeWidthDesc;

  /// No description provided for @hollowStrokeDesc.
  ///
  /// In en, this message translates to:
  /// **'Cuts out the center of strokes for a hollow outline effect.'**
  String get hollowStrokeDesc;

  /// No description provided for @hollowStrokeRatioDesc.
  ///
  /// In en, this message translates to:
  /// **'Controls the size of the hollow interior. Higher values make the outline thinner.'**
  String get hollowStrokeRatioDesc;

  /// No description provided for @eraseOccludedPartsDesc.
  ///
  /// In en, this message translates to:
  /// **'When enabled, later hollow strokes erase overlapping pixels from existing strokes on the same layer.'**
  String get eraseOccludedPartsDesc;

  /// No description provided for @solidFillDesc.
  ///
  /// In en, this message translates to:
  /// **'Determines if the shape tool draws a filled block or hollow outline. Toggle on for solid shapes.'**
  String get solidFillDesc;

  /// No description provided for @randomRotationDesc.
  ///
  /// In en, this message translates to:
  /// **'When enabled, square/triangle/star stamps rotate randomly along the stroke.'**
  String get randomRotationDesc;

  /// No description provided for @autoSharpTaperDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically tapers the start and end of strokes for a sharp, cel-shading look.'**
  String get autoSharpTaperDesc;

  /// No description provided for @stylusPressureDesc.
  ///
  /// In en, this message translates to:
  /// **'Allows stylus pressure to affect brush size/opacity. Turn off to ignore hardware pressure.'**
  String get stylusPressureDesc;

  /// No description provided for @touchDrawingDesc.
  ///
  /// In en, this message translates to:
  /// **'When off, finger touch cannot draw. Stylus can still draw.'**
  String get touchDrawingDesc;

  /// No description provided for @simulatedPressureDesc.
  ///
  /// In en, this message translates to:
  /// **'Simulates pressure based on mouse speed when no pressure device is present.'**
  String get simulatedPressureDesc;

  /// No description provided for @switchToEraserDesc.
  ///
  /// In en, this message translates to:
  /// **'Switches current brush/spray to an eraser with the same texture.'**
  String get switchToEraserDesc;

  /// No description provided for @vectorDrawingDesc.
  ///
  /// In en, this message translates to:
  /// **'Previews strokes as vector curves for 120Hz smooth feedback and lossless scaling. Turn off for direct pixel output.'**
  String get vectorDrawingDesc;

  /// No description provided for @smoothCurveDesc.
  ///
  /// In en, this message translates to:
  /// **'Further smooths curve nodes when Vector Drawing is on, reducing corners but sacrificing some responsiveness.'**
  String get smoothCurveDesc;

  /// No description provided for @sampleAllLayersDesc.
  ///
  /// In en, this message translates to:
  /// **'Bucket samples colors from all visible layers. Turn off to detect only the current layer.'**
  String get sampleAllLayersDesc;

  /// No description provided for @contiguousDesc.
  ///
  /// In en, this message translates to:
  /// **'Spreads only to adjacent pixels. Turn off to match the entire canvas.'**
  String get contiguousDesc;

  /// No description provided for @swallowColorLineDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically expands fill into color lines to remove white edges. Dedicated for Retas workflow.'**
  String get swallowColorLineDesc;

  /// No description provided for @swallowBlueColorLineDesc.
  ///
  /// In en, this message translates to:
  /// **'Swallows only blue lines when filling.'**
  String get swallowBlueColorLineDesc;

  /// No description provided for @swallowGreenColorLineDesc.
  ///
  /// In en, this message translates to:
  /// **'Swallows only green lines when filling.'**
  String get swallowGreenColorLineDesc;

  /// No description provided for @swallowRedColorLineDesc.
  ///
  /// In en, this message translates to:
  /// **'Swallows only red lines when filling.'**
  String get swallowRedColorLineDesc;

  /// No description provided for @swallowAllColorLineDesc.
  ///
  /// In en, this message translates to:
  /// **'Swallows red/green/blue lines when filling.'**
  String get swallowAllColorLineDesc;

  /// No description provided for @cropOutsideCanvasDesc.
  ///
  /// In en, this message translates to:
  /// **'Crops pixels outside the canvas when adjusting layers. Turn off to keep all pixels.'**
  String get cropOutsideCanvasDesc;

  /// No description provided for @textAntialiasingDesc.
  ///
  /// In en, this message translates to:
  /// **'Enables antialiasing for text rendering, smoothing glyphs while preserving density.'**
  String get textAntialiasingDesc;

  /// No description provided for @textStrokeDesc.
  ///
  /// In en, this message translates to:
  /// **'Enables the stroke channel for text outlines.'**
  String get textStrokeDesc;

  /// No description provided for @sprayEffectDesc.
  ///
  /// In en, this message translates to:
  /// **'Switches spray model: \'Soft Spray\' for misty gradients, \'Splatter\' for particles.'**
  String get sprayEffectDesc;

  /// No description provided for @rectSelectDesc.
  ///
  /// In en, this message translates to:
  /// **'Quickly select a rectangular area.'**
  String get rectSelectDesc;

  /// No description provided for @ellipseSelectDesc.
  ///
  /// In en, this message translates to:
  /// **'Create circular or elliptical selections.'**
  String get ellipseSelectDesc;

  /// No description provided for @polyLassoDesc.
  ///
  /// In en, this message translates to:
  /// **'Draw arbitrary polygon selections point by point.'**
  String get polyLassoDesc;

  /// No description provided for @rectShapeDesc.
  ///
  /// In en, this message translates to:
  /// **'Draw horizontal rectangles or squares (outline/fill).'**
  String get rectShapeDesc;

  /// No description provided for @ellipseShapeDesc.
  ///
  /// In en, this message translates to:
  /// **'Draw elliptical or circular outlines/fills.'**
  String get ellipseShapeDesc;

  /// No description provided for @triangleShapeDesc.
  ///
  /// In en, this message translates to:
  /// **'Draw geometric triangles or use a triangle tip for sharp outlines.'**
  String get triangleShapeDesc;

  /// No description provided for @lineShapeDesc.
  ///
  /// In en, this message translates to:
  /// **'Draw straight lines from start to end.'**
  String get lineShapeDesc;

  /// No description provided for @circleTipDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep brush tip circular for smooth, soft strokes.'**
  String get circleTipDesc;

  /// No description provided for @squareTipDesc.
  ///
  /// In en, this message translates to:
  /// **'Use a square tip for hard-edged pixel strokes.'**
  String get squareTipDesc;

  /// No description provided for @starTipDesc.
  ///
  /// In en, this message translates to:
  /// **'Use a five-point star tip for decorative strokes.'**
  String get starTipDesc;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @disableVectorDrawing.
  ///
  /// In en, this message translates to:
  /// **'Disable Vector Drawing'**
  String get disableVectorDrawing;

  /// No description provided for @disableVectorDrawingConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to disable vector drawing?'**
  String get disableVectorDrawingConfirm;

  /// No description provided for @disableVectorDrawingDesc.
  ///
  /// In en, this message translates to:
  /// **'Performance will decrease after disabling.'**
  String get disableVectorDrawingDesc;

  /// No description provided for @dontShowAgain.
  ///
  /// In en, this message translates to:
  /// **'Don\'t show again'**
  String get dontShowAgain;

  /// No description provided for @newLayer.
  ///
  /// In en, this message translates to:
  /// **'New Layer'**
  String get newLayer;

  /// No description provided for @mergeDown.
  ///
  /// In en, this message translates to:
  /// **'Merge Down'**
  String get mergeDown;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// No description provided for @rasterizeTextLayer.
  ///
  /// In en, this message translates to:
  /// **'Rasterize Text Layer'**
  String get rasterizeTextLayer;

  /// No description provided for @opacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get opacity;

  /// No description provided for @blendMode.
  ///
  /// In en, this message translates to:
  /// **'Blend Mode'**
  String get blendMode;

  /// No description provided for @clearFill.
  ///
  /// In en, this message translates to:
  /// **'Clear Fill'**
  String get clearFill;

  /// No description provided for @colorLine.
  ///
  /// In en, this message translates to:
  /// **'Color Line'**
  String get colorLine;

  /// No description provided for @currentColor.
  ///
  /// In en, this message translates to:
  /// **'Current Color'**
  String get currentColor;

  /// No description provided for @rgb.
  ///
  /// In en, this message translates to:
  /// **'RGB'**
  String get rgb;

  /// No description provided for @hsv.
  ///
  /// In en, this message translates to:
  /// **'HSV'**
  String get hsv;

  /// No description provided for @preparingLayer.
  ///
  /// In en, this message translates to:
  /// **'Preparing layer...'**
  String get preparingLayer;

  /// No description provided for @generatePaletteTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate palette from canvas'**
  String get generatePaletteTitle;

  /// No description provided for @generatePaletteDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose color count or enter custom value.'**
  String get generatePaletteDesc;

  /// No description provided for @customCount.
  ///
  /// In en, this message translates to:
  /// **'Custom Count'**
  String get customCount;

  /// No description provided for @selectExportFormat.
  ///
  /// In en, this message translates to:
  /// **'Select Export Format'**
  String get selectExportFormat;

  /// No description provided for @selectPaletteFormatDesc.
  ///
  /// In en, this message translates to:
  /// **'Select palette export format.'**
  String get selectPaletteFormatDesc;

  /// No description provided for @noColorsDetected.
  ///
  /// In en, this message translates to:
  /// **'No colors detected.'**
  String get noColorsDetected;

  /// No description provided for @alphaThreshold.
  ///
  /// In en, this message translates to:
  /// **'Alpha Threshold'**
  String get alphaThreshold;

  /// No description provided for @blurRadius.
  ///
  /// In en, this message translates to:
  /// **'Blur Radius'**
  String get blurRadius;

  /// No description provided for @repairRange.
  ///
  /// In en, this message translates to:
  /// **'Repair Range'**
  String get repairRange;

  /// No description provided for @selectAntialiasLevel.
  ///
  /// In en, this message translates to:
  /// **'Select Antialias Level'**
  String get selectAntialiasLevel;

  /// No description provided for @colorCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Color Count'**
  String get colorCountLabel;

  /// No description provided for @completeTransformFirst.
  ///
  /// In en, this message translates to:
  /// **'Please complete the current transform first.'**
  String get completeTransformFirst;

  /// No description provided for @enablePerspectiveGuideFirst.
  ///
  /// In en, this message translates to:
  /// **'Please enable perspective guide before using perspective pen.'**
  String get enablePerspectiveGuideFirst;

  /// No description provided for @lineNotAlignedWithPerspective.
  ///
  /// In en, this message translates to:
  /// **'Current line does not align with perspective direction, please adjust angle.'**
  String get lineNotAlignedWithPerspective;

  /// No description provided for @layerBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get layerBackground;

  /// No description provided for @layerDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Layer {index}'**
  String layerDefaultName(Object index);

  /// No description provided for @duplicateLayer.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Layer'**
  String get duplicateLayer;

  /// No description provided for @layerCopyName.
  ///
  /// In en, this message translates to:
  /// **'{name} Copy'**
  String layerCopyName(Object name);

  /// No description provided for @unlockLayer.
  ///
  /// In en, this message translates to:
  /// **'Unlock Layer'**
  String get unlockLayer;

  /// No description provided for @lockLayer.
  ///
  /// In en, this message translates to:
  /// **'Lock Layer'**
  String get lockLayer;

  /// No description provided for @releaseClippingMask.
  ///
  /// In en, this message translates to:
  /// **'Release Clipping Mask'**
  String get releaseClippingMask;

  /// No description provided for @createClippingMask.
  ///
  /// In en, this message translates to:
  /// **'Create Clipping Mask'**
  String get createClippingMask;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @show.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// No description provided for @colorRangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Color Range'**
  String get colorRangeTitle;

  /// No description provided for @colorPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Color Picker'**
  String get colorPickerTitle;

  /// No description provided for @layerManagerTitle.
  ///
  /// In en, this message translates to:
  /// **'Layer Manager'**
  String get layerManagerTitle;

  /// No description provided for @edgeSoftening.
  ///
  /// In en, this message translates to:
  /// **'Edge Softening'**
  String get edgeSoftening;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @undoShortcut.
  ///
  /// In en, this message translates to:
  /// **'Undo ({shortcut})'**
  String undoShortcut(Object shortcut);

  /// No description provided for @redoShortcut.
  ///
  /// In en, this message translates to:
  /// **'Redo ({shortcut})'**
  String redoShortcut(Object shortcut);

  /// No description provided for @opacityPercent.
  ///
  /// In en, this message translates to:
  /// **'Opacity {percent}%'**
  String opacityPercent(Object percent);

  /// No description provided for @clippingMask.
  ///
  /// In en, this message translates to:
  /// **'Clipping Mask'**
  String get clippingMask;

  /// No description provided for @deleteLayerTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Layer'**
  String get deleteLayerTitle;

  /// No description provided for @deleteLayerDesc.
  ///
  /// In en, this message translates to:
  /// **'Remove this layer. Undo available.'**
  String get deleteLayerDesc;

  /// No description provided for @mergeDownDesc.
  ///
  /// In en, this message translates to:
  /// **'Merge with the layer below.'**
  String get mergeDownDesc;

  /// No description provided for @duplicateLayerDesc.
  ///
  /// In en, this message translates to:
  /// **'Duplicate entire layer content.'**
  String get duplicateLayerDesc;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @lockLayerDesc.
  ///
  /// In en, this message translates to:
  /// **'Lock to prevent accidental edits.'**
  String get lockLayerDesc;

  /// No description provided for @unlockLayerDesc.
  ///
  /// In en, this message translates to:
  /// **'Unlock to enable editing.'**
  String get unlockLayerDesc;

  /// No description provided for @clippingMaskDescOn.
  ///
  /// In en, this message translates to:
  /// **'Restore to normal layer.'**
  String get clippingMaskDescOn;

  /// No description provided for @clippingMaskDescOff.
  ///
  /// In en, this message translates to:
  /// **'Clip to layer below.'**
  String get clippingMaskDescOff;

  /// No description provided for @red.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get red;

  /// No description provided for @green.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get green;

  /// No description provided for @blue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get blue;

  /// No description provided for @hue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get hue;

  /// No description provided for @saturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get saturation;

  /// No description provided for @value.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get value;

  /// No description provided for @hsvBoxSpectrum.
  ///
  /// In en, this message translates to:
  /// **'HSV Box Spectrum'**
  String get hsvBoxSpectrum;

  /// No description provided for @hueRingSpectrum.
  ///
  /// In en, this message translates to:
  /// **'Hue Ring Spectrum'**
  String get hueRingSpectrum;

  /// No description provided for @rgbHsvSliders.
  ///
  /// In en, this message translates to:
  /// **'RGB / HSV Sliders'**
  String get rgbHsvSliders;

  /// No description provided for @boardPanelPicker.
  ///
  /// In en, this message translates to:
  /// **'Board Panel Picker'**
  String get boardPanelPicker;

  /// No description provided for @adjustCurrentColor.
  ///
  /// In en, this message translates to:
  /// **'Adjust Current Color'**
  String get adjustCurrentColor;

  /// No description provided for @adjustStrokeColor.
  ///
  /// In en, this message translates to:
  /// **'Adjust Stroke Color'**
  String get adjustStrokeColor;

  /// No description provided for @copiedHex.
  ///
  /// In en, this message translates to:
  /// **'Copied {hex}'**
  String copiedHex(Object hex);

  /// No description provided for @rotationLabel.
  ///
  /// In en, this message translates to:
  /// **'Rotation: {degrees}°'**
  String rotationLabel(Object degrees);

  /// No description provided for @scaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Scale: {x}% x {y}%'**
  String scaleLabel(Object x, Object y);

  /// No description provided for @failedToExportTransform.
  ///
  /// In en, this message translates to:
  /// **'Failed to export transform result'**
  String get failedToExportTransform;

  /// No description provided for @cannotLocateLayer.
  ///
  /// In en, this message translates to:
  /// **'Cannot locate active layer.'**
  String get cannotLocateLayer;

  /// No description provided for @layerLockedCannotTransform.
  ///
  /// In en, this message translates to:
  /// **'Active layer is locked, cannot transform.'**
  String get layerLockedCannotTransform;

  /// No description provided for @cannotEnterTransformMode.
  ///
  /// In en, this message translates to:
  /// **'Cannot enter free transform mode.'**
  String get cannotEnterTransformMode;

  /// No description provided for @applyTransformFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply transform, please try again.'**
  String get applyTransformFailed;

  /// No description provided for @freeTransformTitle.
  ///
  /// In en, this message translates to:
  /// **'Free Transform'**
  String get freeTransformTitle;

  /// No description provided for @colorIndicatorDetail.
  ///
  /// In en, this message translates to:
  /// **'Click to open color editor, enter values or copy HEX.'**
  String get colorIndicatorDetail;

  /// No description provided for @gplDesc.
  ///
  /// In en, this message translates to:
  /// **'Text format compatible with GIMP, Krita, Clip Studio Paint, etc.'**
  String get gplDesc;

  /// No description provided for @aseDesc.
  ///
  /// In en, this message translates to:
  /// **'Suitable for Aseprite, LibreSprite pixel art software.'**
  String get aseDesc;

  /// No description provided for @asepriteDesc.
  ///
  /// In en, this message translates to:
  /// **'Uses .aseprite extension for direct opening in Aseprite.'**
  String get asepriteDesc;

  /// No description provided for @gradientPaletteFailed.
  ///
  /// In en, this message translates to:
  /// **'Current color cannot generate gradient palette, please try again.'**
  String get gradientPaletteFailed;

  /// No description provided for @gradientPaletteTitle.
  ///
  /// In en, this message translates to:
  /// **'Gradient Palette (Current Color)'**
  String get gradientPaletteTitle;

  /// No description provided for @paletteCountRange.
  ///
  /// In en, this message translates to:
  /// **'Range {min} - {max}'**
  String paletteCountRange(Object min, Object max);

  /// No description provided for @allowedRange.
  ///
  /// In en, this message translates to:
  /// **'Allowed Range: {min} - {max} colors'**
  String allowedRange(Object min, Object max);

  /// No description provided for @enterValidColorCount.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid color count.'**
  String get enterValidColorCount;

  /// No description provided for @paletteGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to generate palette momentarily, please try again.'**
  String get paletteGenerationFailed;

  /// No description provided for @noValidColorsFound.
  ///
  /// In en, this message translates to:
  /// **'No valid colors found, please ensure canvas has content.'**
  String get noValidColorsFound;

  /// No description provided for @paletteEmpty.
  ///
  /// In en, this message translates to:
  /// **'This palette has no usable colors.'**
  String get paletteEmpty;

  /// No description provided for @paletteMinColors.
  ///
  /// In en, this message translates to:
  /// **'Palette requires at least {min} colors.'**
  String paletteMinColors(Object min);

  /// No description provided for @paletteDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Palette'**
  String get paletteDefaultName;

  /// No description provided for @paletteEmptyExport.
  ///
  /// In en, this message translates to:
  /// **'This palette has no exportable colors.'**
  String get paletteEmptyExport;

  /// No description provided for @exportPaletteTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Palette'**
  String get exportPaletteTitle;

  /// No description provided for @paletteExported.
  ///
  /// In en, this message translates to:
  /// **'Palette exported to {path}'**
  String paletteExported(Object path);

  /// No description provided for @paletteExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to export palette: {error}'**
  String paletteExportFailed(Object error);

  /// No description provided for @selectEditableLayerFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select an editable layer first.'**
  String get selectEditableLayerFirst;

  /// No description provided for @layerLockedNoFilter.
  ///
  /// In en, this message translates to:
  /// **'Active layer is locked, cannot apply filter.'**
  String get layerLockedNoFilter;

  /// No description provided for @textLayerNoFilter.
  ///
  /// In en, this message translates to:
  /// **'Active layer is text, please rasterize or switch layer.'**
  String get textLayerNoFilter;

  /// No description provided for @hueSaturation.
  ///
  /// In en, this message translates to:
  /// **'Hue/Saturation'**
  String get hueSaturation;

  /// No description provided for @brightnessContrast.
  ///
  /// In en, this message translates to:
  /// **'Brightness/Contrast'**
  String get brightnessContrast;

  /// No description provided for @blackAndWhite.
  ///
  /// In en, this message translates to:
  /// **'Black & White'**
  String get blackAndWhite;

  /// No description provided for @binarize.
  ///
  /// In en, this message translates to:
  /// **'Binarize'**
  String get binarize;

  /// No description provided for @gaussianBlur.
  ///
  /// In en, this message translates to:
  /// **'Gaussian Blur'**
  String get gaussianBlur;

  /// No description provided for @leakRemoval.
  ///
  /// In en, this message translates to:
  /// **'Leak Removal'**
  String get leakRemoval;

  /// No description provided for @lineNarrow.
  ///
  /// In en, this message translates to:
  /// **'Line Narrow'**
  String get lineNarrow;

  /// No description provided for @narrowRadius.
  ///
  /// In en, this message translates to:
  /// **'Narrow Radius'**
  String get narrowRadius;

  /// No description provided for @fillExpand.
  ///
  /// In en, this message translates to:
  /// **'Fill Expand'**
  String get fillExpand;

  /// No description provided for @expandRadius.
  ///
  /// In en, this message translates to:
  /// **'Expand Radius'**
  String get expandRadius;

  /// No description provided for @noTransparentPixelsFound.
  ///
  /// In en, this message translates to:
  /// **'No processable transparent pixels detected.'**
  String get noTransparentPixelsFound;

  /// No description provided for @filterApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply filter, please try again.'**
  String get filterApplyFailed;

  /// No description provided for @canvasNotReadyInvert.
  ///
  /// In en, this message translates to:
  /// **'Canvas not ready, cannot invert colors.'**
  String get canvasNotReadyInvert;

  /// No description provided for @layerLockedInvert.
  ///
  /// In en, this message translates to:
  /// **'Active layer locked, cannot invert colors.'**
  String get layerLockedInvert;

  /// No description provided for @layerEmptyInvert.
  ///
  /// In en, this message translates to:
  /// **'Active layer empty, cannot invert colors.'**
  String get layerEmptyInvert;

  /// No description provided for @noPixelsToInvert.
  ///
  /// In en, this message translates to:
  /// **'Active layer has no pixels to invert.'**
  String get noPixelsToInvert;

  /// No description provided for @layerEmptyScanPaperDrawing.
  ///
  /// In en, this message translates to:
  /// **'Active layer empty, cannot scan paper drawing.'**
  String get layerEmptyScanPaperDrawing;

  /// No description provided for @scanPaperDrawingNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No convertible pixels detected.'**
  String get scanPaperDrawingNoChanges;

  /// No description provided for @edgeSofteningFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot apply edge softening, layer might be empty or locked.'**
  String get edgeSofteningFailed;

  /// No description provided for @layerLockedEdgeSoftening.
  ///
  /// In en, this message translates to:
  /// **'Active layer locked, cannot apply edge softening.'**
  String get layerLockedEdgeSoftening;

  /// No description provided for @canvasNotReadyColorRange.
  ///
  /// In en, this message translates to:
  /// **'Canvas not ready, cannot count color range.'**
  String get canvasNotReadyColorRange;

  /// No description provided for @layerLockedColorRange.
  ///
  /// In en, this message translates to:
  /// **'Active layer locked, cannot set color range.'**
  String get layerLockedColorRange;

  /// No description provided for @layerEmptyColorRange.
  ///
  /// In en, this message translates to:
  /// **'Active layer empty, cannot set color range.'**
  String get layerEmptyColorRange;

  /// No description provided for @noColorsToProcess.
  ///
  /// In en, this message translates to:
  /// **'Active layer has no processable colors.'**
  String get noColorsToProcess;

  /// No description provided for @targetColorsNotLess.
  ///
  /// In en, this message translates to:
  /// **'Target color count not less than current, layer unchanged.'**
  String get targetColorsNotLess;

  /// No description provided for @colorRangeApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply color range, please try again.'**
  String get colorRangeApplyFailed;

  /// No description provided for @colorRangePreviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate color range preview, please try again.'**
  String get colorRangePreviewFailed;

  /// No description provided for @lightness.
  ///
  /// In en, this message translates to:
  /// **'Lightness'**
  String get lightness;

  /// No description provided for @brightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get brightness;

  /// No description provided for @contrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get contrast;

  /// No description provided for @selectSaveFormat.
  ///
  /// In en, this message translates to:
  /// **'Please select a file format to save.'**
  String get selectSaveFormat;

  /// No description provided for @saveAsPsd.
  ///
  /// In en, this message translates to:
  /// **'Save as PSD'**
  String get saveAsPsd;

  /// No description provided for @saveAsSai2.
  ///
  /// In en, this message translates to:
  /// **'Save as SAI2'**
  String get saveAsSai2;

  /// No description provided for @saveAsRin.
  ///
  /// In en, this message translates to:
  /// **'Save as RIN'**
  String get saveAsRin;

  /// No description provided for @dontSave.
  ///
  /// In en, this message translates to:
  /// **'Don\'t Save'**
  String get dontSave;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @renameProject.
  ///
  /// In en, this message translates to:
  /// **'Rename Project'**
  String get renameProject;

  /// No description provided for @enterNewProjectName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a new project name'**
  String get enterNewProjectName;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @canvasNotReady.
  ///
  /// In en, this message translates to:
  /// **'Canvas not ready'**
  String get canvasNotReady;

  /// No description provided for @toolPanel.
  ///
  /// In en, this message translates to:
  /// **'Tool Panel'**
  String get toolPanel;

  /// No description provided for @toolbarTitle.
  ///
  /// In en, this message translates to:
  /// **'Toolbar'**
  String get toolbarTitle;

  /// No description provided for @toolOptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tool Options'**
  String get toolOptionsTitle;

  /// No description provided for @defaultProjectDirectory.
  ///
  /// In en, this message translates to:
  /// **'Default Project Directory'**
  String get defaultProjectDirectory;

  /// No description provided for @minimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimize;

  /// No description provided for @maximizeRestore.
  ///
  /// In en, this message translates to:
  /// **'Maximize/Restore'**
  String get maximizeRestore;

  /// No description provided for @fontFamily.
  ///
  /// In en, this message translates to:
  /// **'Font Family'**
  String get fontFamily;

  /// No description provided for @fontSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search fonts...'**
  String get fontSearchPlaceholder;

  /// No description provided for @noMatchingFonts.
  ///
  /// In en, this message translates to:
  /// **'No matching fonts.'**
  String get noMatchingFonts;

  /// No description provided for @fontPreviewText.
  ///
  /// In en, this message translates to:
  /// **'Preview text'**
  String get fontPreviewText;

  /// No description provided for @fontPreviewLanguages.
  ///
  /// In en, this message translates to:
  /// **'Test languages'**
  String get fontPreviewLanguages;

  /// No description provided for @fontLanguageCategory.
  ///
  /// In en, this message translates to:
  /// **'Language category'**
  String get fontLanguageCategory;

  /// No description provided for @fontLanguageAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get fontLanguageAll;

  /// No description provided for @fontFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get fontFavorites;

  /// No description provided for @noFavoriteFonts.
  ///
  /// In en, this message translates to:
  /// **'No favorite fonts yet.'**
  String get noFavoriteFonts;

  /// No description provided for @importPaletteTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Palette'**
  String get importPaletteTitle;

  /// No description provided for @cannotReadFile.
  ///
  /// In en, this message translates to:
  /// **'Cannot read file'**
  String get cannotReadFile;

  /// No description provided for @paletteImported.
  ///
  /// In en, this message translates to:
  /// **'Palette imported: {name}'**
  String paletteImported(Object name);

  /// No description provided for @paletteImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import palette: {error}'**
  String paletteImportFailed(Object error);

  /// No description provided for @noChangesToSave.
  ///
  /// In en, this message translates to:
  /// **'No changes to save to {location}'**
  String noChangesToSave(Object location);

  /// No description provided for @projectSaved.
  ///
  /// In en, this message translates to:
  /// **'Project saved to {location}'**
  String projectSaved(Object location);

  /// No description provided for @projectSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save project: {error}'**
  String projectSaveFailed(Object error);

  /// No description provided for @canvasNotReadySave.
  ///
  /// In en, this message translates to:
  /// **'Canvas is not ready to save.'**
  String get canvasNotReadySave;

  /// No description provided for @saveProjectAs.
  ///
  /// In en, this message translates to:
  /// **'Save Project As'**
  String get saveProjectAs;

  /// No description provided for @psdExported.
  ///
  /// In en, this message translates to:
  /// **'PSD exported to {path}'**
  String psdExported(Object path);

  /// No description provided for @sai2Exported.
  ///
  /// In en, this message translates to:
  /// **'SAI2 exported to {path}'**
  String sai2Exported(Object path);

  /// No description provided for @projectDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Project downloaded: {fileName}'**
  String projectDownloaded(Object fileName);

  /// No description provided for @psdDownloaded.
  ///
  /// In en, this message translates to:
  /// **'PSD downloaded: {fileName}'**
  String psdDownloaded(Object fileName);

  /// No description provided for @sai2Downloaded.
  ///
  /// In en, this message translates to:
  /// **'SAI2 downloaded: {fileName}'**
  String sai2Downloaded(Object fileName);

  /// No description provided for @exportAsPsdTooltip.
  ///
  /// In en, this message translates to:
  /// **'Export as PSD'**
  String get exportAsPsdTooltip;

  /// No description provided for @exportAsSai2Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Export as SAI2'**
  String get exportAsSai2Tooltip;

  /// No description provided for @canvasNotReadyExport.
  ///
  /// In en, this message translates to:
  /// **'Canvas is not ready to export.'**
  String get canvasNotReadyExport;

  /// No description provided for @exportFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Export {extension} File'**
  String exportFileTitle(Object extension);

  /// No description provided for @fileExported.
  ///
  /// In en, this message translates to:
  /// **'File exported to {path}'**
  String fileExported(Object path);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(Object error);

  /// No description provided for @canvasNotReadyTransform.
  ///
  /// In en, this message translates to:
  /// **'Canvas not ready for transformation.'**
  String get canvasNotReadyTransform;

  /// No description provided for @canvasSizeErrorTransform.
  ///
  /// In en, this message translates to:
  /// **'Canvas size error during transformation.'**
  String get canvasSizeErrorTransform;

  /// No description provided for @canvasNotReadyResizeImage.
  ///
  /// In en, this message translates to:
  /// **'Canvas not ready to resize image.'**
  String get canvasNotReadyResizeImage;

  /// No description provided for @resizeImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to resize image.'**
  String get resizeImageFailed;

  /// No description provided for @canvasNotReadyResizeCanvas.
  ///
  /// In en, this message translates to:
  /// **'Canvas not ready to resize canvas.'**
  String get canvasNotReadyResizeCanvas;

  /// No description provided for @resizeCanvasFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to resize canvas.'**
  String get resizeCanvasFailed;

  /// No description provided for @returnToHome.
  ///
  /// In en, this message translates to:
  /// **'Return to Home'**
  String get returnToHome;

  /// No description provided for @saveBeforeReturn.
  ///
  /// In en, this message translates to:
  /// **'Do you want to save changes before returning to home?'**
  String get saveBeforeReturn;

  /// No description provided for @closeCanvas.
  ///
  /// In en, this message translates to:
  /// **'Close Canvas'**
  String get closeCanvas;

  /// No description provided for @saveBeforeClose.
  ///
  /// In en, this message translates to:
  /// **'Do you want to save changes before closing?'**
  String get saveBeforeClose;

  /// No description provided for @nameCannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be empty.'**
  String get nameCannotBeEmpty;

  /// No description provided for @noSupportedImageFormats.
  ///
  /// In en, this message translates to:
  /// **'No supported image formats found.'**
  String get noSupportedImageFormats;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import {item}: {error}'**
  String importFailed(Object item, Object error);

  /// No description provided for @createdCanvasFromDrop.
  ///
  /// In en, this message translates to:
  /// **'Created canvas from dropped item.'**
  String get createdCanvasFromDrop;

  /// No description provided for @createdCanvasesFromDrop.
  ///
  /// In en, this message translates to:
  /// **'Created {count} canvases from dropped items.'**
  String createdCanvasesFromDrop(Object count);

  /// No description provided for @dropImageCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create canvas from dropped image.'**
  String get dropImageCreateFailed;

  /// No description provided for @canvasNotReadyDrop.
  ///
  /// In en, this message translates to:
  /// **'Canvas not ready for drop operation.'**
  String get canvasNotReadyDrop;

  /// No description provided for @insertedDropImage.
  ///
  /// In en, this message translates to:
  /// **'Inserted dropped image.'**
  String get insertedDropImage;

  /// No description provided for @insertedDropImages.
  ///
  /// In en, this message translates to:
  /// **'Inserted {count} dropped images.'**
  String insertedDropImages(Object count);

  /// No description provided for @dropImageInsertFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to insert dropped image.'**
  String get dropImageInsertFailed;

  /// No description provided for @image.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get image;

  /// No description provided for @on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get on;

  /// No description provided for @perspective1Point.
  ///
  /// In en, this message translates to:
  /// **'1-Point Perspective'**
  String get perspective1Point;

  /// No description provided for @perspective2Point.
  ///
  /// In en, this message translates to:
  /// **'2-Point Perspective'**
  String get perspective2Point;

  /// No description provided for @perspective3Point.
  ///
  /// In en, this message translates to:
  /// **'3-Point Perspective'**
  String get perspective3Point;

  /// No description provided for @resolutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Resolution: {resolution}'**
  String resolutionLabel(Object resolution);

  /// No description provided for @zoomLabel.
  ///
  /// In en, this message translates to:
  /// **'Zoom: {zoom}'**
  String zoomLabel(Object zoom);

  /// No description provided for @positionLabel.
  ///
  /// In en, this message translates to:
  /// **'Pos: {position}'**
  String positionLabel(Object position);

  /// No description provided for @gridLabel.
  ///
  /// In en, this message translates to:
  /// **'Grid: {grid}'**
  String gridLabel(Object grid);

  /// No description provided for @blackWhiteLabel.
  ///
  /// In en, this message translates to:
  /// **'B&W: {state}'**
  String blackWhiteLabel(Object state);

  /// No description provided for @mirrorLabel.
  ///
  /// In en, this message translates to:
  /// **'Mirror: {state}'**
  String mirrorLabel(Object state);

  /// No description provided for @tileLabel.
  ///
  /// In en, this message translates to:
  /// **'Tile: {state}'**
  String tileLabel(Object state);

  /// No description provided for @perspectiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Perspective: {perspective}'**
  String perspectiveLabel(Object perspective);

  /// No description provided for @fileNameCannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'File name cannot be empty.'**
  String get fileNameCannotBeEmpty;

  /// No description provided for @blackPoint.
  ///
  /// In en, this message translates to:
  /// **'Black Point'**
  String get blackPoint;

  /// No description provided for @whitePoint.
  ///
  /// In en, this message translates to:
  /// **'White Point'**
  String get whitePoint;

  /// No description provided for @midTone.
  ///
  /// In en, this message translates to:
  /// **'Mid Tone'**
  String get midTone;

  /// No description provided for @rendererLabel.
  ///
  /// In en, this message translates to:
  /// **'Renderer'**
  String get rendererLabel;

  /// No description provided for @rendererNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get rendererNormal;

  /// No description provided for @rendererNormalDesc.
  ///
  /// In en, this message translates to:
  /// **'Real-time rendering, fastest speed, suitable for preview.'**
  String get rendererNormalDesc;

  /// No description provided for @rendererCinematic.
  ///
  /// In en, this message translates to:
  /// **'Trailer'**
  String get rendererCinematic;

  /// No description provided for @rendererCinematicDesc.
  ///
  /// In en, this message translates to:
  /// **'Recreates the official Minecraft trailer style with soft shadows and high-contrast lighting.'**
  String get rendererCinematicDesc;

  /// No description provided for @rendererCycles.
  ///
  /// In en, this message translates to:
  /// **'Realistic'**
  String get rendererCycles;

  /// No description provided for @rendererCyclesDesc.
  ///
  /// In en, this message translates to:
  /// **'Simulates path tracing style, extremely realistic lighting effects.'**
  String get rendererCyclesDesc;

  /// No description provided for @autoSaveCleanupThresholdLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-save cleanup threshold'**
  String get autoSaveCleanupThresholdLabel;

  /// No description provided for @autoSaveCleanupThresholdValue.
  ///
  /// In en, this message translates to:
  /// **'Current threshold: {size}'**
  String autoSaveCleanupThresholdValue(Object size);

  /// No description provided for @autoSaveCleanupThresholdDesc.
  ///
  /// In en, this message translates to:
  /// **'If the auto-save folder exceeds this size, you will be prompted to clean up on startup.'**
  String get autoSaveCleanupThresholdDesc;

  /// No description provided for @autoSaveCleanupDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-save storage is large'**
  String get autoSaveCleanupDialogTitle;

  /// No description provided for @autoSaveCleanupDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Auto-saved projects are using {size} (limit {limit}). Clean up now?'**
  String autoSaveCleanupDialogMessage(Object size, Object limit);

  /// No description provided for @autoSaveCleanupDialogClean.
  ///
  /// In en, this message translates to:
  /// **'Clean Up'**
  String get autoSaveCleanupDialogClean;

  /// No description provided for @exportDestinationTitle.
  ///
  /// In en, this message translates to:
  /// **'Export destination'**
  String get exportDestinationTitle;

  /// No description provided for @exportDestinationDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose where to export the image.'**
  String get exportDestinationDesc;

  /// No description provided for @imageSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Select image source'**
  String get imageSourceTitle;

  /// No description provided for @imageSourceDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose to import from Photos or Files.'**
  String get imageSourceDesc;

  /// No description provided for @exportDestinationPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get exportDestinationPhotos;

  /// No description provided for @exportDestinationFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get exportDestinationFiles;

  /// No description provided for @imageSavedToPhotos.
  ///
  /// In en, this message translates to:
  /// **'Image saved to Photos.'**
  String get imageSavedToPhotos;

  /// No description provided for @exportDirectoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Export directory'**
  String get exportDirectoryLabel;

  /// No description provided for @exportDirectoryDesc.
  ///
  /// In en, this message translates to:
  /// **'Set the default export location on Android.'**
  String get exportDirectoryDesc;

  /// No description provided for @selectExportDirectory.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get selectExportDirectory;

  /// No description provided for @resetExportDirectory.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get resetExportDirectory;

  /// No description provided for @exportDirectoryCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current: {path}'**
  String exportDirectoryCurrent(Object path);

  /// No description provided for @exportDirectoryDefault.
  ///
  /// In en, this message translates to:
  /// **'Default: {path}'**
  String exportDirectoryDefault(Object path);

  /// No description provided for @exportDirectoryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Export directory updated: {path}'**
  String exportDirectoryUpdated(Object path);

  /// No description provided for @exportDirectoryCleared.
  ///
  /// In en, this message translates to:
  /// **'Export directory reset to default.'**
  String get exportDirectoryCleared;

  /// No description provided for @exportDirectoryUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update export directory: {error}'**
  String exportDirectoryUpdateFailed(Object error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
