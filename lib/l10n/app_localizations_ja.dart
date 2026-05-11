// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get closeAppTitle => 'アプリを終了';

  @override
  String unsavedProjectsWarning(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '未保存のプロジェクトが $count 件あります。今終了すると、最新の変更が失われます。',
      one: '未保存のプロジェクトが 1 件あります。今終了すると、最新の変更が失われます。',
    );
    return '$_temp0';
  }

  @override
  String get cancel => 'キャンセル';

  @override
  String get discardAndExit => '破棄して終了';

  @override
  String get homeTagline => 'ここから制作を始めましょう';

  @override
  String get homeNewProject => '新規プロジェクト';

  @override
  String get homeNewProjectDesc => '空のキャンバスから新しいアイデアを始める';

  @override
  String get homeOpenProject => 'プロジェクトを開く';

  @override
  String get homeOpenProjectDesc => 'ディスクから .rin / .psd / .sai2 または画像ファイルを読み込む';

  @override
  String get homeRecentProjects => '最近開いた';

  @override
  String get homeRecentProjectsDesc => '自動保存したプロジェクトをすばやく復元';

  @override
  String get homeProjectManager => 'プロジェクト管理';

  @override
  String get homeProjectManagerDesc => '自動保存プロジェクトをまとめて表示／整理';

  @override
  String get homeSettings => '設定';

  @override
  String get homeSettingsDesc => '近日公開のカスタマイズ項目をプレビュー';

  @override
  String get homeAbout => 'このアプリについて';

  @override
  String get homeAboutDesc => 'Misa Rin について';

  @override
  String createProjectFailed(Object error) {
    return 'プロジェクトの作成に失敗しました: $error';
  }

  @override
  String get openProjectDialogTitle => 'プロジェクトを開く';

  @override
  String get openingProjectTitle => 'プロジェクトを開いています…';

  @override
  String openingProjectMessage(Object fileName) {
    return '$fileName を読み込み中';
  }

  @override
  String get cannotReadPsdContent => 'PSD ファイルの内容を読み取れません。';

  @override
  String get cannotReadSai2Content => 'SAI2 ファイルの内容を読み取れません。';

  @override
  String get cannotReadProjectFileContent => 'プロジェクトファイルの内容を読み取れません。';

  @override
  String openedProjectInfo(Object name) {
    return 'プロジェクトを開きました: $name';
  }

  @override
  String openProjectFailed(Object error) {
    return 'プロジェクトを開けませんでした: $error';
  }

  @override
  String get importImageDialogTitle => '画像をインポート';

  @override
  String importedImageInfo(Object name) {
    return '画像をインポートしました: $name';
  }

  @override
  String importImageFailed(Object error) {
    return '画像のインポートに失敗しました: $error';
  }

  @override
  String get clipboardNoBitmapFound => 'クリップボードにインポートできるビットマップが見つかりません。';

  @override
  String get clipboardImageDefaultName => 'クリップボード画像';

  @override
  String get importedClipboardImageInfo => 'クリップボード画像をインポートしました';

  @override
  String importClipboardImageFailed(Object error) {
    return 'クリップボード画像のインポートに失敗しました: $error';
  }

  @override
  String get aboutTitle => 'Misa Rin について';

  @override
  String get aboutDescription =>
      'Misa Rin は、創作とプロジェクト管理に特化したアプリです。スムーズな描画体験と信頼できるプロジェクト保存機能を提供します。';

  @override
  String get aboutAppIdLabel => 'アプリ ID';

  @override
  String get aboutAppVersionLabel => 'バージョン';

  @override
  String get aboutDeveloperLabel => '開発者';

  @override
  String get close => '閉じる';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsTabGeneral => '一般';

  @override
  String get settingsTabInput => '入力とブラシ';

  @override
  String get settingsTabStorage => '履歴とストレージ';

  @override
  String get settingsTabAbout => 'このアプリについて';

  @override
  String get tabletTest => 'ペンタブテスト';

  @override
  String get restoreDefaults => '既定に戻す';

  @override
  String get ok => 'OK';

  @override
  String get languageLabel => '言語';

  @override
  String get languageSystem => 'システム';

  @override
  String get languageEnglish => '英語';

  @override
  String get languageJapanese => '日本語';

  @override
  String get languageKorean => '韓国語';

  @override
  String get languageChineseSimplified => '中国語（簡体字）';

  @override
  String get languageChineseTraditional => '中国語（繁体字）';

  @override
  String get themeModeLabel => 'テーマ';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeDark => 'ダーク';

  @override
  String get themeSystem => 'システム';

  @override
  String get stylusPressureSettingsLabel => '筆圧設定';

  @override
  String get enableStylusPressure => '筆圧を有効にする';

  @override
  String get responseCurveLabel => '応答曲線';

  @override
  String get responseCurveDesc => '圧力とストローク幅の変化の速さを調整します。';

  @override
  String get brushSizeSliderRangeLabel => 'ブラシサイズ スライダー範囲';

  @override
  String get brushSizeSliderRangeDesc =>
      'ツールパネルのブラシサイズスライダーに影響します。精度をすばやく切り替えるのに役立ちます。';

  @override
  String get penSliderRangeCompact => '1 - 60 px（粗め）';

  @override
  String get penSliderRangeMedium => '0.1 - 500 px（中）';

  @override
  String get penSliderRangeFull => '0.01 - 1000 px（全範囲）';

  @override
  String get historyLimitLabel => '取り消し/やり直しの上限';

  @override
  String historyLimitCurrent(Object count) {
    return '現在の上限: $count ステップ';
  }

  @override
  String historyLimitDesc(Object min, Object max) {
    return '取り消し/やり直し履歴の保存数を調整します（$min-$max）。';
  }

  @override
  String get canvasBackendLabel => 'キャンバスバックエンド';

  @override
  String get canvasBackendGpu => 'Rust WGPU';

  @override
  String get canvasBackendCpu => 'Rust CPU';

  @override
  String get canvasBackendRestartHint => 'バックエンドの切り替えは再起動後に反映されます。';

  @override
  String get developerOptionsLabel => '開発者オプション';

  @override
  String get performanceOverlayLabel => 'パフォーマンス表示';

  @override
  String get performanceOverlayDesc =>
      '画面隅に Flutter Performance Pulse ダッシュボードを表示し、FPS、CPU、メモリ、ディスクなどをリアルタイムで確認できます。';

  @override
  String get tabletInputTestTitle => 'ペンタブ入力テスト';

  @override
  String get recentProjectsTitle => '最近開いた';

  @override
  String recentProjectsLoadFailed(Object error) {
    return '最近のプロジェクトの読み込みに失敗しました: $error';
  }

  @override
  String get recentProjectsEmpty => '最近のプロジェクトはありません';

  @override
  String get openFileLocation => 'ファイルの場所を開く';

  @override
  String lastOpened(Object date) {
    return '最終オープン: $date';
  }

  @override
  String canvasSize(Object width, Object height) {
    return 'キャンバスサイズ: $width x $height';
  }

  @override
  String get menuFile => 'ファイル';

  @override
  String get menuEdit => '編集';

  @override
  String get menuImage => '画像';

  @override
  String get menuLayer => 'レイヤー';

  @override
  String get menuSelection => '選択';

  @override
  String get menuFilter => 'フィルター';

  @override
  String get menuTool => 'ツール';

  @override
  String get menuView => '表示';

  @override
  String get menuWorkspace => 'ワークスペース';

  @override
  String get menuWindow => 'ウィンドウ';

  @override
  String get menuRoot => 'メニュー';

  @override
  String get menuAbout => 'Misa Rin について';

  @override
  String get menuPreferences => '環境設定…';

  @override
  String get menuNewEllipsis => '新規…';

  @override
  String get menuOpenEllipsis => '開く…';

  @override
  String get menuImportImageEllipsis => '画像をインポート…';

  @override
  String get menuImportImageFromClipboard => 'クリップボードから画像をインポート';

  @override
  String get menuSave => '保存';

  @override
  String get menuSaveAsEllipsis => '別名で保存…';

  @override
  String get menuExportEllipsis => '書き出し…';

  @override
  String get menuCloseAll => 'すべて閉じる';

  @override
  String get menuUndo => '取り消し';

  @override
  String get menuRedo => 'やり直し';

  @override
  String get menuCut => '切り取り';

  @override
  String get menuCopy => 'コピー';

  @override
  String get menuPaste => '貼り付け';

  @override
  String get menuImageTransform => '変形';

  @override
  String get menuRotate90CW => '90° 右回転';

  @override
  String get menuRotate90CCW => '90° 左回転';

  @override
  String get menuRotate180CW => '180° 右回転';

  @override
  String get menuRotate180CCW => '180° 左回転';

  @override
  String get menuFlipHorizontal => '左右反転';

  @override
  String get menuFlipVertical => '上下反転';

  @override
  String get menuImageSizeEllipsis => '画像サイズ…';

  @override
  String get menuCanvasSizeEllipsis => 'キャンバスサイズ…';

  @override
  String get menuNewSubmenu => '新規';

  @override
  String get menuNewLayerEllipsis => 'レイヤー…';

  @override
  String get menuMergeDown => '下のレイヤーに結合';

  @override
  String get menuRasterize => 'ラスタライズ';

  @override
  String get menuTransform => '変形';

  @override
  String get menuSelectAll => 'すべて選択';

  @override
  String get menuDeselect => '選択解除';

  @override
  String get menuInvertSelection => '選択範囲を反転';

  @override
  String get menuPalette => 'パレット';

  @override
  String get menuGeneratePaletteFromCanvasEllipsis => '現在のキャンバスからパレットを生成…';

  @override
  String get menuGenerateGradientPalette => '現在の色からグラデーションパレットを生成';

  @override
  String get menuImportPaletteEllipsis => 'パレットをインポート…';

  @override
  String get menuReferenceImage => '参照画像';

  @override
  String get menuCreateReferenceImage => '参照画像を作成';

  @override
  String get menuImportReferenceImageEllipsis => '参照画像をインポート…';

  @override
  String get menuReferenceModel => '参照モデル';

  @override
  String get menuReferenceModelSteve => 'Steveモデル';

  @override
  String get menuReferenceModelAlex => 'Alexモデル';

  @override
  String get menuReferenceModelCube => 'キューブモデル';

  @override
  String get menuImportReferenceModelEllipsis => 'モデルをインポート…';

  @override
  String get referenceModelRefreshTexture => 'テクスチャを更新';

  @override
  String get referenceModelRefreshTextureDesc => '現在のキャンバスからモデル用テクスチャを生成';

  @override
  String get referenceModelResetView => '表示をリセット';

  @override
  String get referenceModelResetViewDesc => '回転とズームを初期化';

  @override
  String get referenceModelSixView => '6視点';

  @override
  String get referenceModelSixViewDesc => '表示を2×3に分割（正/背/上/下/左/右）';

  @override
  String get referenceModelSingleView => '単一表示';

  @override
  String get referenceModelSingleViewDesc => '単一表示に戻す（ドラッグで回転）';

  @override
  String get referenceModelViewFront => '正面';

  @override
  String get referenceModelViewBack => '背面';

  @override
  String get referenceModelViewTop => '上面';

  @override
  String get referenceModelViewBottom => '下面';

  @override
  String get referenceModelViewLeft => '左面';

  @override
  String get referenceModelViewRight => '右面';

  @override
  String get menuZoomIn => '拡大';

  @override
  String get menuZoomOut => '縮小';

  @override
  String get menuShowGrid => 'グリッドを表示';

  @override
  String get menuHideGrid => 'グリッドを非表示';

  @override
  String get menuBlackWhite => '白黒';

  @override
  String get menuDisableBlackWhite => '白黒を解除';

  @override
  String get menuMirrorPreview => 'ミラープレビュー';

  @override
  String get menuDisableMirror => 'ミラーを解除';

  @override
  String get menuTiledPreview => 'タイルプレビュー';

  @override
  String get menuDisableTiledPreview => 'タイルプレビューを無効化';

  @override
  String get menuShowPerspectiveGuide => '透視線を表示';

  @override
  String get menuHidePerspectiveGuide => '透視線を非表示';

  @override
  String get menuPerspectiveMode => '透視モード';

  @override
  String get menuPerspective1Point => '1 点透視';

  @override
  String get menuPerspective2Point => '2 点透視';

  @override
  String get menuPerspective3Point => '3 点透視';

  @override
  String get menuWorkspaceDefault => 'デフォルト';

  @override
  String get menuWorkspaceSai2 => 'SAI2';

  @override
  String get menuWorkspaceCsp => 'CSP';

  @override
  String get menuSwitchWorkspace => 'ワークスペースを切り替え';

  @override
  String get menuResetWorkspace => 'ワークスペースをリセット';

  @override
  String get menuEdgeSofteningEllipsis => 'エッジの柔化…';

  @override
  String get menuNarrowLinesEllipsis => '線を細く…';

  @override
  String get menuExpandFillEllipsis => '塗りの拡張…';

  @override
  String get menuGaussianBlurEllipsis => 'ガウスぼかし…';

  @override
  String get menuRemoveColorLeakEllipsis => '色漏れを除去…';

  @override
  String get menuHueSaturationEllipsis => '色相/彩度…';

  @override
  String get menuBrightnessContrastEllipsis => '明るさ/コントラスト…';

  @override
  String get menuColorRangeEllipsis => '色域…';

  @override
  String get menuBlackWhiteEllipsis => '白黒…';

  @override
  String get menuBinarizeEllipsis => '二値化…';

  @override
  String get menuScanPaperDrawingEllipsis => 'スキャン紙絵…';

  @override
  String get menuScanPaperDrawing => 'スキャン紙絵';

  @override
  String get menuInvertColors => '色を反転';

  @override
  String get canvasSizeTitle => 'キャンバスサイズ';

  @override
  String get canvasSizeAnchorLabel => 'アンカー';

  @override
  String get canvasSizeAnchorDesc => 'アンカーポイントを基準にキャンバスをリサイズします。';

  @override
  String get confirm => '確認';

  @override
  String get projectManagerTitle => 'プロジェクト管理';

  @override
  String get selectAll => 'すべて選択';

  @override
  String get openFolder => 'フォルダを開く';

  @override
  String deleteSelected(Object count) {
    return '選択項目を削除 ($count)';
  }

  @override
  String get imageSizeTitle => '画像サイズ';

  @override
  String get lockAspectRatio => '縦横比を固定';

  @override
  String get realtimeParams => 'リアルタイムパラメータ';

  @override
  String get clearScribble => '落書きを消去';

  @override
  String get newCanvasSettingsTitle => '新規キャンバス設定';

  @override
  String get custom => 'カスタム';

  @override
  String get colorWhite => '白';

  @override
  String get colorLightGray => 'ライトグレー';

  @override
  String get colorBlack => '黒';

  @override
  String get colorTransparent => '透明';

  @override
  String get create => '作成';

  @override
  String currentPreset(Object name) {
    return '現在のプリセット: $name';
  }

  @override
  String get exportSettingsTitle => '書き出し設定';

  @override
  String get exportTypeLabel => '書き出し形式';

  @override
  String get exportTypeBitmap => 'ビットマップ';

  @override
  String get exportTypePng => 'ビットマップ PNG';

  @override
  String get exportTypeSvg => 'ベクター SVG（実験的）';

  @override
  String get exportBitmapFormatLabel => 'ビットマップ形式';

  @override
  String get exportBitmapFormatPng => 'PNG';

  @override
  String get exportBitmapFormatWebp => 'WebP';

  @override
  String get webpCompressionLabel => 'WebP 圧縮';

  @override
  String get webpLossless => '可逆';

  @override
  String get webpLossy => '非可逆';

  @override
  String webpQualityLabel(Object value) {
    return '画質: $value';
  }

  @override
  String get exportScaleLabel => '書き出し倍率';

  @override
  String get reset => 'リセット';

  @override
  String exportOutputSize(Object width, Object height) {
    return '出力サイズ: $width x $height px';
  }

  @override
  String get exportAntialiasingLabel => 'アンチエイリアス';

  @override
  String get enableAntialiasing => 'アンチエイリアスを有効化';

  @override
  String get vectorParamsLabel => 'ベクターパラメータ';

  @override
  String vectorMaxColors(Object count) {
    return '最大色数: $count';
  }

  @override
  String vectorSimplify(Object value) {
    return '単純化強度: $value';
  }

  @override
  String get export => '書き出し';

  @override
  String get invalidDimensions => '有効な寸法（px）を入力してください。';

  @override
  String get widthPx => '幅 (px)';

  @override
  String get heightPx => '高さ (px)';

  @override
  String get noAutosavedProjects => '自動保存されたプロジェクトはありません';

  @override
  String get revealProjectLocation => '選択したプロジェクトの場所を表示';

  @override
  String get deleteSelectedProjects => '選択したプロジェクトを削除';

  @override
  String loadFailed(Object error) {
    return '読み込みに失敗しました: $error';
  }

  @override
  String deleteFailed(Object error) {
    return '削除に失敗しました: $error';
  }

  @override
  String projectFileInfo(Object size, Object date) {
    return 'サイズ: $size · 更新日時: $date';
  }

  @override
  String projectCanvasInfo(Object width, Object height) {
    return 'キャンバス $width x $height';
  }

  @override
  String get samplingMethod => 'サンプリング方式';

  @override
  String currentSize(Object width, Object height) {
    return '現在のサイズ: $width x $height px';
  }

  @override
  String get samplingNearestLabel => 'ニアレストネイバー法';

  @override
  String get samplingNearestDesc => 'エッジを保持します。ドット絵に適しています。';

  @override
  String get samplingBilinearLabel => 'バイリニア法';

  @override
  String get samplingBilinearDesc => '滑らかに補間します。一般的なリサイズに適しています。';

  @override
  String get tabletPressureLatest => '現在の筆圧';

  @override
  String get tabletPressureMin => '最小筆圧';

  @override
  String get tabletPressureMax => '最大筆圧';

  @override
  String get tabletRadiusPx => '推定半径 (px)';

  @override
  String get tabletTiltRad => '傾き (rad)';

  @override
  String get tabletSampleCount => 'サンプル数';

  @override
  String get tabletSampleRateHz => 'サンプリングレート (Hz)';

  @override
  String get tabletPointerType => 'ポインタタイプ';

  @override
  String get pointerKindMouse => 'マウス';

  @override
  String get pointerKindTouch => 'タッチ';

  @override
  String get pointerKindStylus => 'スタイラス';

  @override
  String get pointerKindInvertedStylus => 'スタイラス（消しゴム）';

  @override
  String get pointerKindTrackpad => 'トラックパッド';

  @override
  String get pointerKindUnknown => '不明';

  @override
  String get presetMobilePortrait => 'モバイル 縦向き (1080 x 1920)';

  @override
  String get presetSquare => '正方形 (1024 x 1024)';

  @override
  String presetPixelArt(Object width, Object height) {
    return 'ドット絵 ($width x $height)';
  }

  @override
  String get untitledProject => '無題のプロジェクト';

  @override
  String get invalidResolution => '有効な解像度を入力してください';

  @override
  String minResolutionError(Object value) {
    return '解像度は $value px 以上にしてください';
  }

  @override
  String maxResolutionError(Object value) {
    return '解像度は $value px 以下にしてください';
  }

  @override
  String get projectName => 'プロジェクト名';

  @override
  String get workspacePreset => 'ワークスペースプリセット';

  @override
  String get workspacePresetDesc => 'キャンバス作成時に一般的なツール設定を自動適用します。';

  @override
  String get workspaceIllustration => 'イラスト';

  @override
  String get workspaceIllustrationDesc => 'ブラシ: 鉛筆、エッジ柔化: 1';

  @override
  String get workspaceIllustrationDesc2 => 'ストリームライン: 変更なし';

  @override
  String get workspaceCelShading => 'アニメ塗り';

  @override
  String get workspaceCelShadingDesc1 => 'ブラシ: セル画ブラシ、エッジ柔化: 0';

  @override
  String get workspaceCelShadingDesc2 => '塗りつぶしツールの領域拡張: オン';

  @override
  String get workspaceCelShadingDesc3 => '塗りつぶしツールのアンチエイリアス: オフ';

  @override
  String get workspacePixel => 'ドット絵';

  @override
  String get workspacePixelDesc1 => 'ブラシ: ピクセル、ブラシ/塗りつぶしツールのアンチエイリアス: 0';

  @override
  String get workspacePixelDesc2 => 'グリッド表示: オン';

  @override
  String get workspacePixelDesc3 => 'ベクター描画: 変更なし';

  @override
  String get workspacePixelDesc4 => '手ブレ補正: 0';

  @override
  String get workspaceDefault => 'デフォルト';

  @override
  String get workspaceDefaultDesc => '現在のツール設定を変更しません';

  @override
  String get resolutionPreset => '解像度プリセット';

  @override
  String get customResolution => 'カスタム解像度';

  @override
  String get swapDimensions => '幅と高さを入れ替え';

  @override
  String finalSizePreview(Object width, Object height, Object ratio) {
    return '最終サイズ: $width x $height px (比率 $ratio)';
  }

  @override
  String get enterValidDimensions => '有効な寸法を入力してください';

  @override
  String get backgroundColor => '背景色';

  @override
  String get exportBitmapDesc =>
      'ラスター形式が必要な通常の書き出しに適しており、拡大縮小やアンチエイリアスをサポートします。';

  @override
  String get exportVectorDesc => '現在のキャンバスをベクターパスに自動変換します。ベクターツールでの編集に適しています。';

  @override
  String get exampleScale => '例: 1.0';

  @override
  String get enterPositiveValue => '0 より大きい値を入力してください';

  @override
  String get antialiasingBeforeExport => '書き出し前にアンチエイリアスを適用';

  @override
  String get brushAntialiasing => 'ブラシのアンチエイリアス';

  @override
  String get bucketAntialiasing => '塗りつぶしのアンチエイリアス';

  @override
  String get antialiasingDesc =>
      '線の密度を保ちつつエッジを滑らかにします。Retas アニメーションソフトの質感を再現します。';

  @override
  String levelLabel(Object level) {
    return 'レベル $level';
  }

  @override
  String vectorExportSize(Object width, Object height) {
    return '書き出しサイズ: $width x $height (キャンバスサイズを使用)';
  }

  @override
  String colorCount(Object count) {
    return '$count 色';
  }

  @override
  String get vectorSimplifyDesc =>
      '色数を減らし単純化強度を上げると SVG がシンプルになります。値が低すぎるとノード数が過多になります。';

  @override
  String get antialiasNone => 'レベル 0 (オフ): ピクセルのハードエッジを保持し、アンチエイリアスを行いません。';

  @override
  String get antialiasLow => 'レベル 1 (弱): エイリアシングをわずかに和らげ、線の密度を保ちつつエッジを滑らかにします。';

  @override
  String get antialiasMedium =>
      'レベル 2 (標準): シャープさと柔らかさのバランスを取り、Retas のような綺麗な線にします。';

  @override
  String get antialiasHigh =>
      'レベル 3 (強): 最も強い柔化効果。柔らかい遷移が必要な場合や大きく拡大する場合に適しています。';

  @override
  String get tolerance => '許容値';

  @override
  String get fillGap => '隙間閉じ';

  @override
  String get sampleAllLayers => '全レイヤーを参照';

  @override
  String get contiguous => '隣接ピクセルのみ';

  @override
  String get swallowColorLine => '色トレス線を飲み込む';

  @override
  String get swallowBlueColorLine => '青色線を飲み込む';

  @override
  String get swallowGreenColorLine => '緑色線を飲み込む';

  @override
  String get swallowRedColorLine => '赤色線を飲み込む';

  @override
  String get swallowAllColorLine => '全ての色線を飲み込む';

  @override
  String get cropOutsideCanvas => 'キャンバス外を切り取る';

  @override
  String get noAdjustableSettings => 'このツールには調整可能な設定がありません';

  @override
  String get hollowStroke => '中空ストローク';

  @override
  String get hollowStrokeRatio => '中空比率';

  @override
  String get eraseOccludedParts => '重なり部分を消去';

  @override
  String get solidFill => '塗りつぶし';

  @override
  String get autoSharpTaper => '入り抜き自動補正';

  @override
  String get stylusPressure => '筆圧感知';

  @override
  String get touchDrawing => 'タッチ描画';

  @override
  String get simulatedPressure => '擬似筆圧';

  @override
  String get switchToEraser => '消しゴムに切り替え';

  @override
  String get vectorDrawing => 'ベクター描画';

  @override
  String get smoothCurve => '曲線を滑らかに';

  @override
  String get sprayEffect => 'スプレー効果';

  @override
  String get brushPreset => 'ブラシプリセット';

  @override
  String get brushPresetDesc => '間隔・流量・形状などを含むプリセットを選択します。';

  @override
  String get editBrushPreset => 'プリセットを編集';

  @override
  String get editBrushPresetDesc => '現在のプリセットの内部パラメータを調整します。';

  @override
  String get brushPresetDialogTitle => 'ブラシプリセットを編集';

  @override
  String get brushPresetNameLabel => 'プリセット名';

  @override
  String get brushPresetPencil => '鉛筆';

  @override
  String get brushPresetCel => 'セル画ブラシ';

  @override
  String get brushPresetPen => 'ペン';

  @override
  String get brushPresetScreentone => 'スクリーントーン';

  @override
  String get brushPresetPixel => 'ピクセル';

  @override
  String get brushPresetDryInk => '枯墨';

  @override
  String get brushPresetCharcoal => '木炭';

  @override
  String get brushPresetStarBrush => '星形ブラシ';

  @override
  String get brushSpacing => '間隔';

  @override
  String get brushHardness => '硬さ';

  @override
  String get brushFlow => '流量';

  @override
  String get brushScatter => '散布';

  @override
  String get brushRotationJitter => '回転ジッター';

  @override
  String get brushSnapToPixel => 'ピクセルにスナップ';

  @override
  String get screentoneEnabled => 'スクリーントーン';

  @override
  String get screentoneShape => 'ドット形状';

  @override
  String get screentoneSpacing => 'ドット間隔';

  @override
  String get screentoneDotSize => 'ドットサイズ';

  @override
  String get screentoneRotation => 'ドット回転';

  @override
  String get screentoneSoftness => 'ドットの柔らかさ';

  @override
  String get brushShape => 'ブラシ形状';

  @override
  String get brushAuthorLabel => '作者';

  @override
  String get brushVersionLabel => 'バージョン';

  @override
  String get importBrush => 'ブラシをインポート';

  @override
  String get exportBrush => 'ブラシをエクスポート';

  @override
  String get exportBrushTitle => 'ブラシを書き出し';

  @override
  String get unsavedBrushChangesPrompt => 'ブラシ設定が変更されています。保存しますか？';

  @override
  String get discardChanges => '変更を破棄';

  @override
  String get brushShapeFolderLabel => 'ブラシ形状フォルダー';

  @override
  String get openBrushShapesFolder => 'ブラシ形状フォルダーを開く';

  @override
  String get randomRotation => 'ランダム回転';

  @override
  String get smoothRotation => 'スムーズ回転';

  @override
  String get selectionShape => '選択形状';

  @override
  String get selectionAdditive => '選択を追加';

  @override
  String get selectionAdditiveDesc => '有効時、Shift を押さなくても選択を追加できます。';

  @override
  String get fontSize => 'フォントサイズ';

  @override
  String get lineHeight => '行間';

  @override
  String get letterSpacing => '文字間隔';

  @override
  String get textStroke => 'テキストの境界線';

  @override
  String get strokeWidth => '境界線の太さ';

  @override
  String get strokeColor => '境界線の色';

  @override
  String get pickColor => '色を取得';

  @override
  String get alignment => '配置';

  @override
  String get alignCenter => '中央揃え';

  @override
  String get alignRight => '右揃え';

  @override
  String get alignLeft => '左揃え';

  @override
  String get orientation => '方向';

  @override
  String get horizontal => '水平';

  @override
  String get vertical => '垂直';

  @override
  String get textToolHint => 'テキストの塗りつぶしには左下のカラーピッカーを、境界線にはサブカラーを使用してください。';

  @override
  String get shapeType => '図形タイプ';

  @override
  String get brushSize => 'ブラシサイズ';

  @override
  String get spraySize => 'スプレーサイズ';

  @override
  String get brushFineTune => 'ブラシ微調整';

  @override
  String get increase => '増加';

  @override
  String get decrease => '減少';

  @override
  String get stabilizer => '手ブレ補正';

  @override
  String get streamline => 'ストリームライン';

  @override
  String get off => 'オフ';

  @override
  String get taperEnds => '両端を細く';

  @override
  String get taperCenter => '中央を細く';

  @override
  String get auto => '自動';

  @override
  String get softSpray => 'ソフトスプレー';

  @override
  String get splatter => '飛沫';

  @override
  String get rectSelection => '長方形選択';

  @override
  String get ellipseSelection => '楕円選択';

  @override
  String get polygonLasso => '多角形選択';

  @override
  String get rectangle => '長方形';

  @override
  String get ellipse => '楕円';

  @override
  String get triangle => '三角形';

  @override
  String get line => '直線';

  @override
  String get circle => '円';

  @override
  String get square => '正方形';

  @override
  String get star => '五芒星';

  @override
  String get brushSizeDesc =>
      '現在のブラシの直径（ピクセル）を設定します。値が大きいほど線が太くなり、小さいほど細部用になります。';

  @override
  String get spraySizeDesc => 'スプレー範囲の半径を決定します。半径が大きいほど広範囲をカバーしますが、粒子は分散します。';

  @override
  String get toleranceDesc => '塗りつぶしや自動選択時の「色の類似性」の許容値を制御します。高いほど似た色を多く含みます。';

  @override
  String get fillGapDesc =>
      '塗りつぶし時に線画の小さな隙間を閉じて漏れを防ぎます。値を上げるほど大きな隙間を閉じられますが、細い領域が拾われにくくなることがあります。';

  @override
  String get antialiasingSliderDesc =>
      'ブラシや塗りつぶしのエッジにマルチサンプリングによる平滑化を加えます。レベル 0 はピクセルスタイルを維持します。';

  @override
  String get stabilizerDesc =>
      '手の震えを打ち消すためにポインタの軌跡をリアルタイムで滑らかにします。レベルが高いほど安定しますが、追従は遅れます。';

  @override
  String get streamlineDesc =>
      'Procreate の StreamLine 風の補正です。ペンを離した後にストロークを平滑化し、補間アニメーションでより滑らかな線に戻します（レベルが高いほど強い）。';

  @override
  String get fontSizeDesc => 'テキスト全体のピクセル高さを調整します。';

  @override
  String get lineHeightDesc => 'テキストの行間の垂直距離を制御します。';

  @override
  String get letterSpacingDesc => '文字間の水平間隔を変更します。';

  @override
  String get strokeWidthDesc => 'テキストの境界線の太さを設定します。';

  @override
  String get hollowStrokeDesc => 'ストロークの中心をくり抜き、中空の輪郭線にします。';

  @override
  String get hollowStrokeRatioDesc => '中空部分の大きさを調整します。値が大きいほど輪郭が細くなります。';

  @override
  String get eraseOccludedPartsDesc => '同じレイヤーで後から描いた中空線が、他の線との重なり部分を消去します。';

  @override
  String get solidFillDesc =>
      '図形ツールで塗りつぶされたブロックを描くか、中空の輪郭を描くかを決定します。オンにすると塗りつぶされます。';

  @override
  String get randomRotationDesc =>
      'オンにすると、四角形/三角形/五芒星のスタンプがストロークに沿ってランダムに回転します。';

  @override
  String get autoSharpTaperDesc => 'ストロークの始点と終点を自動的に細くし、アニメ塗りのようなシャープな線にします。';

  @override
  String get stylusPressureDesc =>
      '筆圧によるブラシサイズ/不透明度の変化を許可します。オフにするとハードウェアの筆圧を無視します。';

  @override
  String get touchDrawingDesc => 'オフにすると指で描画できません。スタイラスは引き続き描画できます。';

  @override
  String get simulatedPressureDesc => '筆圧デバイスがない場合に、マウスの速度に基づいて筆圧をシミュレートします。';

  @override
  String get switchToEraserDesc => '現在のブラシ/スプレーと同じテクスチャを持つ消しゴムに切り替えます。';

  @override
  String get vectorDrawingDesc =>
      'ストロークをベクター曲線としてプレビューし、120Hz の滑らかなフィードバックとロスレス拡大を実現します。ピクセル出力の場合はオフにしてください。';

  @override
  String get smoothCurveDesc =>
      'ベクター描画がオンのとき、曲線のノードをさらに滑らかにし、角を減らしますが、追従性が多少犠牲になります。';

  @override
  String get sampleAllLayersDesc =>
      '塗りつぶし時に表示されている全レイヤーの色を参照します。オフにすると現在のレイヤーのみを検出します。';

  @override
  String get contiguousDesc => '隣接するピクセルにのみ広がります。オフにするとキャンバス全体の一致する色を塗りつぶします。';

  @override
  String get swallowColorLineDesc =>
      '色トレス線に塗りつぶしを自動的に拡張し、白い隙間をなくします。Retas ワークフロー専用です。';

  @override
  String get swallowBlueColorLineDesc => '塗りつぶし時に青色線だけを飲み込みます。';

  @override
  String get swallowGreenColorLineDesc => '塗りつぶし時に緑色線だけを飲み込みます。';

  @override
  String get swallowRedColorLineDesc => '塗りつぶし時に赤色線だけを飲み込みます。';

  @override
  String get swallowAllColorLineDesc => '塗りつぶし時に赤/緑/青の色線を飲み込みます。';

  @override
  String get cropOutsideCanvasDesc =>
      'レイヤー調整時にキャンバス外のピクセルを切り取ります。オフにするとすべてのピクセルを保持します。';

  @override
  String get textAntialiasingDesc => 'テキスト描画のアンチエイリアスを有効にし、密度を保ちながら文字を滑らかにします。';

  @override
  String get textStrokeDesc => 'テキストの輪郭線チャンネルを有効にします。';

  @override
  String get sprayEffectDesc =>
      'スプレーモデルを切り替えます。「ソフトスプレー」は霧状のグラデーション、「飛沫」は粒子状です。';

  @override
  String get rectSelectDesc => '長方形の領域を素早く選択します。';

  @override
  String get ellipseSelectDesc => '円形または楕円形の選択範囲を作成します。';

  @override
  String get polyLassoDesc => '点を打って任意の多角形選択範囲を描画します。';

  @override
  String get rectShapeDesc => '水平な長方形または正方形を描画します（輪郭/塗り）。';

  @override
  String get ellipseShapeDesc => '楕円または円の輪郭/塗りを描画します。';

  @override
  String get triangleShapeDesc => '幾何学的な三角形を描画するか、三角形のチップを使用して鋭い輪郭を描きます。';

  @override
  String get lineShapeDesc => '始点から終点まで直線を描画します。';

  @override
  String get circleTipDesc => 'ブラシチップを円形に保ち、滑らかで柔らかいストロークにします。';

  @override
  String get squareTipDesc => '四角形のチップを使用し、ハードエッジなピクセルストロークにします。';

  @override
  String get starTipDesc => '五芒星のチップで装飾的なストロークを描きます。';

  @override
  String get apply => '適用';

  @override
  String get next => '次へ';

  @override
  String get disableVectorDrawing => 'ベクター描画を無効化';

  @override
  String get disableVectorDrawingConfirm => 'ベクター描画を無効にしてもよろしいですか？';

  @override
  String get disableVectorDrawingDesc => '無効にするとパフォーマンスが低下します。';

  @override
  String get dontShowAgain => '次回から表示しない';

  @override
  String get newLayer => '新規レイヤー';

  @override
  String get mergeDown => '下のレイヤーと結合';

  @override
  String get delete => '削除';

  @override
  String get duplicate => '複製';

  @override
  String get rasterizeTextLayer => 'テキストレイヤーをラスタライズ';

  @override
  String get opacity => '不透明度';

  @override
  String get blendMode => 'ブレンドモード';

  @override
  String get clearFill => '塗りを消去';

  @override
  String get colorLine => '色トレス線';

  @override
  String get currentColor => '現在の色';

  @override
  String get rgb => 'RGB';

  @override
  String get hsv => 'HSV';

  @override
  String get preparingLayer => 'レイヤーを準備中...';

  @override
  String get generatePaletteTitle => 'キャンバスからパレットを生成';

  @override
  String get generatePaletteDesc => '色数を選択するかカスタム値を入力してください。';

  @override
  String get customCount => 'カスタム数';

  @override
  String get selectExportFormat => '書き出し形式を選択';

  @override
  String get selectPaletteFormatDesc => 'パレットの書き出し形式を選択してください。';

  @override
  String get noColorsDetected => '色が検出されませんでした。';

  @override
  String get alphaThreshold => 'アルファしきい値';

  @override
  String get blurRadius => 'ぼかし半径';

  @override
  String get repairRange => '修正範囲';

  @override
  String get selectAntialiasLevel => 'アンチエイリアスレベルを選択';

  @override
  String get colorCountLabel => '色数';

  @override
  String get completeTransformFirst => '現在の変形を先に完了してください。';

  @override
  String get enablePerspectiveGuideFirst => '透視ペンを使用する前に透視ガイドを有効にしてください。';

  @override
  String get lineNotAlignedWithPerspective => '現在の線は透視方向と一致していません。角度を調整してください。';

  @override
  String get layerBackground => '背景';

  @override
  String layerDefaultName(Object index) {
    return 'レイヤー $index';
  }

  @override
  String get duplicateLayer => 'レイヤーを複製';

  @override
  String layerCopyName(Object name) {
    return '$name のコピー';
  }

  @override
  String get unlockLayer => 'レイヤーのロック解除';

  @override
  String get lockLayer => 'レイヤーをロック';

  @override
  String get releaseClippingMask => 'クリッピングマスクを解除';

  @override
  String get createClippingMask => 'クリッピングマスクを作成';

  @override
  String get hide => '非表示';

  @override
  String get show => '表示';

  @override
  String get colorRangeTitle => '色域指定';

  @override
  String get colorPickerTitle => 'カラーピッカー';

  @override
  String get layerManagerTitle => 'レイヤー管理';

  @override
  String get edgeSoftening => 'エッジ柔化';

  @override
  String get undo => '取り消し';

  @override
  String get redo => 'やり直し';

  @override
  String undoShortcut(Object shortcut) {
    return '取り消し ($shortcut)';
  }

  @override
  String redoShortcut(Object shortcut) {
    return 'やり直し ($shortcut)';
  }

  @override
  String opacityPercent(Object percent) {
    return '不透明度 $percent%';
  }

  @override
  String get clippingMask => 'クリッピングマスク';

  @override
  String get deleteLayerTitle => 'レイヤーを削除';

  @override
  String get deleteLayerDesc => 'このレイヤーを削除します。取り消し可能です。';

  @override
  String get mergeDownDesc => '下のレイヤーと結合します。';

  @override
  String get duplicateLayerDesc => 'レイヤーの内容をすべて複製します。';

  @override
  String get more => 'その他';

  @override
  String get lockLayerDesc => '誤編集を防ぐためにロックします。';

  @override
  String get unlockLayerDesc => '編集できるようにロックを解除します。';

  @override
  String get clippingMaskDescOn => '通常のレイヤーに戻します。';

  @override
  String get clippingMaskDescOff => '下のレイヤーでクリッピングします。';

  @override
  String get red => '赤';

  @override
  String get green => '緑';

  @override
  String get blue => '青';

  @override
  String get hue => '色相';

  @override
  String get saturation => '彩度';

  @override
  String get value => '明度';

  @override
  String get hsvBoxSpectrum => 'HSV ボックススペクトル';

  @override
  String get hueRingSpectrum => '色相リングスペクトル';

  @override
  String get rgbHsvSliders => 'RGB / HSV スライダー';

  @override
  String get boardPanelPicker => 'ボードパネルピッカー';

  @override
  String get adjustCurrentColor => '現在の色を調整';

  @override
  String get adjustStrokeColor => '境界線の色を調整';

  @override
  String copiedHex(Object hex) {
    return '$hex をコピーしました';
  }

  @override
  String rotationLabel(Object degrees) {
    return '回転: $degrees°';
  }

  @override
  String scaleLabel(Object x, Object y) {
    return '拡大率: $x% x $y%';
  }

  @override
  String get failedToExportTransform => '変形結果の書き出しに失敗しました';

  @override
  String get cannotLocateLayer => 'アクティブなレイヤーが見つかりません。';

  @override
  String get layerLockedCannotTransform => 'アクティブなレイヤーがロックされているため変形できません。';

  @override
  String get cannotEnterTransformMode => '自由変形モードに入れません。';

  @override
  String get applyTransformFailed => '変形の適用に失敗しました。もう一度試してください。';

  @override
  String get freeTransformTitle => '自由変形';

  @override
  String get colorIndicatorDetail => 'クリックしてカラーエディタを開くか、値を入力または HEX をコピーします。';

  @override
  String get gplDesc => 'GIMP, Krita, Clip Studio Paint などと互換性のあるテキスト形式。';

  @override
  String get aseDesc => 'Aseprite, LibreSprite ドット絵ソフトに適しています。';

  @override
  String get asepriteDesc => 'Aseprite で直接開ける .aseprite 拡張子を使用します。';

  @override
  String get gradientPaletteFailed => '現在の色からグラデーションパレットを生成できません。もう一度試してください。';

  @override
  String get gradientPaletteTitle => 'グラデーションパレット（現在の色）';

  @override
  String paletteCountRange(Object min, Object max) {
    return '範囲 $min - $max';
  }

  @override
  String allowedRange(Object min, Object max) {
    return '許可される範囲: $min - $max 色';
  }

  @override
  String get enterValidColorCount => '有効な色数を入力してください。';

  @override
  String get paletteGenerationFailed => 'パレットを生成できませんでした。もう一度試してください。';

  @override
  String get noValidColorsFound => '有効な色が見つかりません。キャンバスに内容があることを確認してください。';

  @override
  String get paletteEmpty => 'このパレットには使用可能な色がありません。';

  @override
  String paletteMinColors(Object min) {
    return 'パレットには少なくとも $min 色が必要です。';
  }

  @override
  String get paletteDefaultName => 'パレット';

  @override
  String get paletteEmptyExport => 'このパレットには書き出し可能な色がありません。';

  @override
  String get exportPaletteTitle => 'パレットを書き出し';

  @override
  String paletteExported(Object path) {
    return 'パレットを $path に書き出しました';
  }

  @override
  String paletteExportFailed(Object error) {
    return 'パレットの書き出しに失敗しました: $error';
  }

  @override
  String get selectEditableLayerFirst => 'まず編集可能なレイヤーを選択してください。';

  @override
  String get layerLockedNoFilter => 'アクティブなレイヤーがロックされているためフィルターを適用できません。';

  @override
  String get textLayerNoFilter => 'アクティブなレイヤーはテキストです。ラスタライズするかレイヤーを切り替えてください。';

  @override
  String get hueSaturation => '色相/彩度';

  @override
  String get brightnessContrast => '明るさ/コントラスト';

  @override
  String get blackAndWhite => '白黒';

  @override
  String get binarize => '二値化';

  @override
  String get gaussianBlur => 'ガウスぼかし';

  @override
  String get leakRemoval => '漏れ除去';

  @override
  String get lineNarrow => '線幅収縮';

  @override
  String get narrowRadius => '収縮半径';

  @override
  String get fillExpand => '塗り拡張';

  @override
  String get expandRadius => '拡張半径';

  @override
  String get noTransparentPixelsFound => '処理可能な透明ピクセルが見つかりません。';

  @override
  String get filterApplyFailed => 'フィルターの適用に失敗しました。もう一度試してください。';

  @override
  String get canvasNotReadyInvert => 'キャンバスの準備ができていないため色を反転できません。';

  @override
  String get layerLockedInvert => 'アクティブなレイヤーがロックされているため色を反転できません。';

  @override
  String get layerEmptyInvert => 'アクティブなレイヤーが空のため色を反転できません。';

  @override
  String get noPixelsToInvert => '反転するピクセルがありません。';

  @override
  String get layerEmptyScanPaperDrawing => 'アクティブなレイヤーが空のためスキャン紙絵を適用できません。';

  @override
  String get scanPaperDrawingNoChanges => '変換できるピクセルが見つかりません。';

  @override
  String get edgeSofteningFailed => 'エッジ柔化を適用できません。レイヤーが空かロックされています。';

  @override
  String get layerLockedEdgeSoftening => 'アクティブなレイヤーがロックされているためエッジ柔化を適用できません。';

  @override
  String get canvasNotReadyColorRange => 'キャンバスの準備ができていないため色域をカウントできません。';

  @override
  String get layerLockedColorRange => 'アクティブなレイヤーがロックされているため色域を設定できません。';

  @override
  String get layerEmptyColorRange => 'アクティブなレイヤーが空のため色域を設定できません。';

  @override
  String get noColorsToProcess => '処理可能な色がありません。';

  @override
  String get targetColorsNotLess => 'ターゲット色数が現在より少なくないため、レイヤーは変更されません。';

  @override
  String get colorRangeApplyFailed => '色域の適用に失敗しました。もう一度試してください。';

  @override
  String get colorRangePreviewFailed => '色域プレビューの生成に失敗しました。もう一度試してください。';

  @override
  String get lightness => '明度';

  @override
  String get brightness => '明るさ';

  @override
  String get contrast => 'コントラスト';

  @override
  String get selectSaveFormat => '保存するファイル形式を選択してください。';

  @override
  String get saveAsPsd => 'PSD として保存';

  @override
  String get saveAsSai2 => 'SAI2 として保存';

  @override
  String get saveAsRin => 'RIN として保存';

  @override
  String get dontSave => '保存しない';

  @override
  String get save => '保存';

  @override
  String get renameProject => 'プロジェクト名を変更';

  @override
  String get enterNewProjectName => '新しいプロジェクト名を入力してください';

  @override
  String get rename => '名前を変更';

  @override
  String get canvasNotReady => 'キャンバス準備中';

  @override
  String get toolPanel => 'ツールパネル';

  @override
  String get toolbarTitle => 'ツールバー';

  @override
  String get toolOptionsTitle => 'ツールオプション';

  @override
  String get defaultProjectDirectory => 'デフォルトのプロジェクト保存先';

  @override
  String get minimize => '最小化';

  @override
  String get maximizeRestore => '最大化/元に戻す';

  @override
  String get fontFamily => 'フォントファミリー';

  @override
  String get fontSearchPlaceholder => 'フォントを検索...';

  @override
  String get noMatchingFonts => '一致するフォントがありません。';

  @override
  String get fontPreviewText => 'プレビュー文';

  @override
  String get fontPreviewLanguages => 'テスト言語';

  @override
  String get fontLanguageCategory => '言語カテゴリ';

  @override
  String get fontLanguageAll => 'すべて';

  @override
  String get fontFavorites => 'お気に入り';

  @override
  String get noFavoriteFonts => 'お気に入りのフォントはまだありません。';

  @override
  String get importPaletteTitle => 'パレットをインポート';

  @override
  String get cannotReadFile => 'ファイルを読み取れません';

  @override
  String paletteImported(Object name) {
    return 'パレットをインポートしました: $name';
  }

  @override
  String paletteImportFailed(Object error) {
    return 'パレットのインポートに失敗しました: $error';
  }

  @override
  String noChangesToSave(Object location) {
    return '$location に保存する変更はありません';
  }

  @override
  String projectSaved(Object location) {
    return 'プロジェクトを $location に保存しました';
  }

  @override
  String projectSaveFailed(Object error) {
    return 'プロジェクトの保存に失敗しました: $error';
  }

  @override
  String get canvasNotReadySave => 'キャンバスの準備ができていないため保存できません。';

  @override
  String get saveProjectAs => 'プロジェクトを別名で保存';

  @override
  String psdExported(Object path) {
    return 'PSD を $path に書き出しました';
  }

  @override
  String sai2Exported(Object path) {
    return 'SAI2 を $path に書き出しました';
  }

  @override
  String projectDownloaded(Object fileName) {
    return 'プロジェクトをダウンロードしました: $fileName';
  }

  @override
  String psdDownloaded(Object fileName) {
    return 'PSD をダウンロードしました: $fileName';
  }

  @override
  String sai2Downloaded(Object fileName) {
    return 'SAI2 をダウンロードしました: $fileName';
  }

  @override
  String get exportAsPsdTooltip => 'PSD として書き出し';

  @override
  String get exportAsSai2Tooltip => 'SAI2 として書き出し';

  @override
  String get canvasNotReadyExport => 'キャンバスの準備ができていないため書き出しできません。';

  @override
  String exportFileTitle(Object extension) {
    return '$extension ファイルを書き出し';
  }

  @override
  String fileExported(Object path) {
    return 'ファイルを $path に書き出しました';
  }

  @override
  String exportFailed(Object error) {
    return '書き出しに失敗しました: $error';
  }

  @override
  String get canvasNotReadyTransform => 'キャンバスの準備ができていないため変形できません。';

  @override
  String get canvasSizeErrorTransform => '変形中にキャンバスサイズエラーが発生しました。';

  @override
  String get canvasNotReadyResizeImage => 'キャンバスの準備ができていないため画像サイズを変更できません。';

  @override
  String get resizeImageFailed => '画像サイズの変更に失敗しました。';

  @override
  String get canvasNotReadyResizeCanvas => 'キャンバスの準備ができていないためキャンバスサイズを変更できません。';

  @override
  String get resizeCanvasFailed => 'キャンバスサイズの変更に失敗しました。';

  @override
  String get returnToHome => 'ホームに戻る';

  @override
  String get saveBeforeReturn => 'ホームに戻る前に変更を保存しますか？';

  @override
  String get closeCanvas => 'キャンバスを閉じる';

  @override
  String get saveBeforeClose => '閉じる前に変更を保存しますか？';

  @override
  String get nameCannotBeEmpty => '名前は空にできません。';

  @override
  String get noSupportedImageFormats => 'サポートされている画像形式が見つかりません。';

  @override
  String importFailed(Object item, Object error) {
    return '$item のインポートに失敗しました: $error';
  }

  @override
  String get createdCanvasFromDrop => 'ドロップされた項目からキャンバスを作成しました。';

  @override
  String createdCanvasesFromDrop(Object count) {
    return 'ドロップされた項目から $count 個のキャンバスを作成しました。';
  }

  @override
  String get dropImageCreateFailed => 'ドロップされた画像からキャンバスを作成できませんでした。';

  @override
  String get canvasNotReadyDrop => 'キャンバスの準備ができていないためドロップ操作を行えません。';

  @override
  String get insertedDropImage => 'ドロップされた画像を挿入しました。';

  @override
  String insertedDropImages(Object count) {
    return '$count 枚のドロップされた画像を挿入しました。';
  }

  @override
  String get dropImageInsertFailed => 'ドロップされた画像の挿入に失敗しました。';

  @override
  String get image => '画像';

  @override
  String get on => 'オン';

  @override
  String get perspective1Point => '1 点透視';

  @override
  String get perspective2Point => '2 点透視';

  @override
  String get perspective3Point => '3 点透視';

  @override
  String resolutionLabel(Object resolution) {
    return '解像度: $resolution';
  }

  @override
  String zoomLabel(Object zoom) {
    return 'ズーム: $zoom';
  }

  @override
  String positionLabel(Object position) {
    return '位置: $position';
  }

  @override
  String gridLabel(Object grid) {
    return 'グリッド: $grid';
  }

  @override
  String blackWhiteLabel(Object state) {
    return '白黒: $state';
  }

  @override
  String mirrorLabel(Object state) {
    return 'ミラー: $state';
  }

  @override
  String tileLabel(Object state) {
    return 'タイル: $state';
  }

  @override
  String perspectiveLabel(Object perspective) {
    return '透視: $perspective';
  }

  @override
  String get fileNameCannotBeEmpty => 'ファイル名は空にできません。';

  @override
  String get blackPoint => '黒点';

  @override
  String get whitePoint => '白点';

  @override
  String get midTone => '中間色';

  @override
  String get rendererLabel => 'レンダラー';

  @override
  String get rendererNormal => '通常';

  @override
  String get rendererNormalDesc => 'リアルタイム、最速、プレビューに最適。';

  @override
  String get rendererCinematic => 'トレーラー';

  @override
  String get rendererCinematicDesc =>
      'Minecraft公式トレーラー風のスタイルを再現。ソフトな影と高コントラストな照明。';

  @override
  String get rendererCycles => 'リアル';

  @override
  String get rendererCyclesDesc => 'パストレーシング風のスタイルをシミュレート。極めてリアルな照明効果。';

  @override
  String get autoSaveCleanupThresholdLabel => '自動保存のクリーンアップ閾値';

  @override
  String autoSaveCleanupThresholdValue(Object size) {
    return '現在の閾値: $size';
  }

  @override
  String get autoSaveCleanupThresholdDesc =>
      '自動保存フォルダーの合計サイズがこの値を超えると、起動時にクリーンアップを促します。';

  @override
  String get autoSaveCleanupDialogTitle => '自動保存の容量が大きすぎます';

  @override
  String autoSaveCleanupDialogMessage(Object size, Object limit) {
    return '自動保存プロジェクトが $size（上限 $limit）を使用しています。今すぐクリーンアップしますか？';
  }

  @override
  String get autoSaveCleanupDialogClean => 'クリーンアップ';

  @override
  String get exportDestinationTitle => 'Export destination';

  @override
  String get exportDestinationDesc => 'Choose where to export the image.';

  @override
  String get imageSourceTitle => '画像の取得元を選択';

  @override
  String get imageSourceDesc => '写真またはファイルから画像を読み込みます。';

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
