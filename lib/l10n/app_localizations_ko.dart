// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get webLoadingInitializingCanvas => '캔버스를 초기화하는 중…';

  @override
  String get webLoadingMayTakeTime => '웹에서는 로딩에 시간이 조금 걸릴 수 있습니다. 잠시만 기다려 주세요.';

  @override
  String get closeAppTitle => '앱 종료';

  @override
  String unsavedProjectsWarning(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '저장되지 않은 프로젝트 $count개가 감지되었습니다. 지금 종료하면 최신 변경 사항이 사라집니다.',
      one: '저장되지 않은 프로젝트 1개가 감지되었습니다. 지금 종료하면 최신 변경 사항이 사라집니다.',
    );
    return '$_temp0';
  }

  @override
  String get cancel => '취소';

  @override
  String get discardAndExit => '버리고 종료';

  @override
  String get homeTagline => '여기서 창작을 시작하세요';

  @override
  String get homeNewProject => '새 프로젝트';

  @override
  String get homeNewProjectDesc => '빈 캔버스에서 새로운 아이디어를 시작';

  @override
  String get homeOpenProject => '프로젝트 열기';

  @override
  String get homeOpenProjectDesc => '디스크에서 .rin / .psd / .sai2 또는 이미지 파일 불러오기';

  @override
  String get homeRecentProjects => '최근 열기';

  @override
  String get homeRecentProjectsDesc => '자동 저장된 프로젝트를 빠르게 복원';

  @override
  String get homeProjectManager => '프로젝트 관리';

  @override
  String get homeProjectManagerDesc => '자동 저장 프로젝트 파일을 일괄 보기/정리';

  @override
  String get homeSettings => '설정';

  @override
  String get homeSettingsDesc => '공개 예정인 개인화 옵션을 미리보기';

  @override
  String get homeAbout => '정보';

  @override
  String get homeAboutDesc => 'Misa Rin 알아보기';

  @override
  String createProjectFailed(Object error) {
    return '프로젝트 생성 실패: $error';
  }

  @override
  String get openProjectDialogTitle => '프로젝트 열기';

  @override
  String get openingProjectTitle => '프로젝트를 여는 중…';

  @override
  String openingProjectMessage(Object fileName) {
    return '$fileName 로딩 중';
  }

  @override
  String get cannotReadPsdContent => 'PSD 파일 내용을 읽을 수 없습니다.';

  @override
  String get cannotReadSai2Content => 'SAI2 파일 내용을 읽을 수 없습니다.';

  @override
  String get cannotReadProjectFileContent => '프로젝트 파일 내용을 읽을 수 없습니다.';

  @override
  String openedProjectInfo(Object name) {
    return '프로젝트를 열었습니다: $name';
  }

  @override
  String openProjectFailed(Object error) {
    return '프로젝트 열기 실패: $error';
  }

  @override
  String get importImageDialogTitle => '이미지 가져오기';

  @override
  String importedImageInfo(Object name) {
    return '이미지를 가져왔습니다: $name';
  }

  @override
  String importImageFailed(Object error) {
    return '이미지 가져오기 실패: $error';
  }

  @override
  String get clipboardNoBitmapFound => '클립보드에서 가져올 수 있는 비트맵을 찾지 못했습니다.';

  @override
  String get clipboardImageDefaultName => '클립보드 이미지';

  @override
  String get importedClipboardImageInfo => '클립보드 이미지를 가져왔습니다';

  @override
  String importClipboardImageFailed(Object error) {
    return '클립보드 이미지 가져오기 실패: $error';
  }

  @override
  String get webPreparingCanvasTitle => '캔버스를 준비하는 중…';

  @override
  String get webPreparingCanvasMessage =>
      '웹 초기화에는 시간이 조금 걸릴 수 있습니다. 잠시만 기다려 주세요.';

  @override
  String get aboutTitle => 'Misa Rin 정보';

  @override
  String get aboutDescription =>
      'Misa Rin은 창작과 프로젝트 관리에 초점을 맞춘 앱으로, 부드러운 그리기 경험과 신뢰할 수 있는 프로젝트 보관 기능을 제공합니다.';

  @override
  String get aboutAppIdLabel => '앱 ID';

  @override
  String get aboutAppVersionLabel => '버전';

  @override
  String get aboutDeveloperLabel => '개발자';

  @override
  String get close => '닫기';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsTabGeneral => '일반';

  @override
  String get settingsTabInput => '입력 및 브러시';

  @override
  String get settingsTabStorage => '기록 및 저장소';

  @override
  String get settingsTabAbout => '정보';

  @override
  String get tabletTest => '태블릿 테스트';

  @override
  String get restoreDefaults => '기본값 복원';

  @override
  String get ok => '확인';

  @override
  String get languageLabel => '언어';

  @override
  String get languageSystem => '시스템';

  @override
  String get languageEnglish => '영어';

  @override
  String get languageJapanese => '일본어';

  @override
  String get languageKorean => '한국어';

  @override
  String get languageChineseSimplified => '중국어(간체)';

  @override
  String get languageChineseTraditional => '중국어(번체)';

  @override
  String get themeModeLabel => '테마 모드';

  @override
  String get themeLight => '라이트';

  @override
  String get themeDark => '다크';

  @override
  String get themeSystem => '시스템';

  @override
  String get stylusPressureSettingsLabel => '필압 설정';

  @override
  String get enableStylusPressure => '필압 사용';

  @override
  String get responseCurveLabel => '반응 곡선';

  @override
  String get responseCurveDesc => '압력과 스트로크 두께 사이의 전환 속도를 조정합니다.';

  @override
  String get brushSizeSliderRangeLabel => '브러시 크기 슬라이더 범위';

  @override
  String get brushSizeSliderRangeDesc =>
      '도구 패널의 브러시 크기 슬라이더에 영향을 주며, 정밀도를 빠르게 전환하는 데 도움이 됩니다.';

  @override
  String get penSliderRangeCompact => '1 - 60 px(거친 조정)';

  @override
  String get penSliderRangeMedium => '0.1 - 500 px(중간)';

  @override
  String get penSliderRangeFull => '0.01 - 1000 px(전체)';

  @override
  String get historyLimitLabel => '실행 취소/다시 실행 제한';

  @override
  String historyLimitCurrent(Object count) {
    return '현재 제한: $count단계';
  }

  @override
  String historyLimitDesc(Object min, Object max) {
    return '실행 취소/다시 실행 기록 보관 수를 조정합니다(범위 $min-$max).';
  }

  @override
  String get canvasBackendLabel => '캔버스 백엔드';

  @override
  String get canvasBackendGpu => 'Rust WGPU';

  @override
  String get canvasBackendCpu => 'Rust CPU';

  @override
  String get canvasBackendRestartHint => '백엔드 변경은 재시작 후 적용됩니다.';

  @override
  String get developerOptionsLabel => '개발자 옵션';

  @override
  String get performanceOverlayLabel => '성능 오버레이';

  @override
  String get performanceOverlayDesc =>
      '화면 모서리에 Flutter Performance Pulse 대시보드를 표시하여 FPS, CPU, 메모리, 디스크 등을 실시간으로 보여 줍니다.';

  @override
  String get tabletInputTestTitle => '태블릿 입력 테스트';

  @override
  String get recentProjectsTitle => '최근 열기';

  @override
  String recentProjectsLoadFailed(Object error) {
    return '최근 프로젝트를 불러오지 못했습니다: $error';
  }

  @override
  String get recentProjectsEmpty => '최근 프로젝트가 없습니다';

  @override
  String get openFileLocation => '파일 위치 열기';

  @override
  String lastOpened(Object date) {
    return '마지막 열기: $date';
  }

  @override
  String canvasSize(Object width, Object height) {
    return '캔버스 크기: $width x $height';
  }

  @override
  String get menuFile => '파일';

  @override
  String get menuEdit => '편집';

  @override
  String get menuImage => '이미지';

  @override
  String get menuLayer => '레이어';

  @override
  String get menuSelection => '선택';

  @override
  String get menuFilter => '필터';

  @override
  String get menuTool => '도구';

  @override
  String get menuView => '보기';

  @override
  String get menuWorkspace => '작업 공간';

  @override
  String get menuWindow => '창';

  @override
  String get menuRoot => '메뉴';

  @override
  String get menuAbout => 'Misa Rin 정보';

  @override
  String get menuPreferences => '환경 설정…';

  @override
  String get menuNewEllipsis => '새로 만들기…';

  @override
  String get menuOpenEllipsis => '열기…';

  @override
  String get menuImportImageEllipsis => '이미지 가져오기…';

  @override
  String get menuImportImageFromClipboard => '클립보드에서 이미지 가져오기';

  @override
  String get menuSave => '저장';

  @override
  String get menuSaveAsEllipsis => '다른 이름으로 저장…';

  @override
  String get menuExportEllipsis => '내보내기…';

  @override
  String get menuCloseAll => '모두 닫기';

  @override
  String get menuUndo => '실행 취소';

  @override
  String get menuRedo => '다시 실행';

  @override
  String get menuCut => '잘라내기';

  @override
  String get menuCopy => '복사';

  @override
  String get menuPaste => '붙여넣기';

  @override
  String get menuImageTransform => '이미지 변환';

  @override
  String get menuRotate90CW => '시계 방향 90도';

  @override
  String get menuRotate90CCW => '반시계 방향 90도';

  @override
  String get menuRotate180CW => '시계 방향 180도';

  @override
  String get menuRotate180CCW => '반시계 방향 180도';

  @override
  String get menuFlipHorizontal => '수평 뒤집기';

  @override
  String get menuFlipVertical => '수직 뒤집기';

  @override
  String get menuImageSizeEllipsis => '이미지 크기…';

  @override
  String get menuCanvasSizeEllipsis => '캔버스 크기…';

  @override
  String get menuNewSubmenu => '새로 만들기';

  @override
  String get menuNewLayerEllipsis => '레이어…';

  @override
  String get menuMergeDown => '아래로 병합';

  @override
  String get menuRasterize => '래스터화';

  @override
  String get menuTransform => '변환';

  @override
  String get menuSelectAll => '전체 선택';

  @override
  String get menuDeselect => '선택 해제';

  @override
  String get menuInvertSelection => '선택 반전';

  @override
  String get menuPalette => '팔레트';

  @override
  String get menuGeneratePaletteFromCanvasEllipsis => '현재 캔버스에서 팔레트 생성…';

  @override
  String get menuGenerateGradientPalette => '현재 색상으로 그라데이션 팔레트 생성';

  @override
  String get menuImportPaletteEllipsis => '팔레트 가져오기…';

  @override
  String get menuReferenceImage => '참조 이미지';

  @override
  String get menuCreateReferenceImage => '참조 이미지 만들기';

  @override
  String get menuImportReferenceImageEllipsis => '참조 이미지 가져오기…';

  @override
  String get menuReferenceModel => '참조 모델';

  @override
  String get menuReferenceModelSteve => 'Steve 모델';

  @override
  String get menuReferenceModelAlex => 'Alex 모델';

  @override
  String get menuReferenceModelCube => '큐브 모델';

  @override
  String get menuImportReferenceModelEllipsis => '모델 가져오기…';

  @override
  String get referenceModelRefreshTexture => '텍스처 새로고침';

  @override
  String get referenceModelRefreshTextureDesc => '현재 캔버스로부터 모델 텍스처 생성';

  @override
  String get referenceModelResetView => '시점 초기화';

  @override
  String get referenceModelResetViewDesc => '회전 및 확대/축소 초기화';

  @override
  String get referenceModelSixView => '6뷰';

  @override
  String get referenceModelSixViewDesc => '뷰포트를 2×3으로 분할(정/후/상/하/좌/우)';

  @override
  String get referenceModelSingleView => '단일 뷰';

  @override
  String get referenceModelSingleViewDesc => '단일 뷰로 돌아가기(드래그로 회전)';

  @override
  String get referenceModelViewFront => '정면';

  @override
  String get referenceModelViewBack => '후면';

  @override
  String get referenceModelViewTop => '상단';

  @override
  String get referenceModelViewBottom => '하단';

  @override
  String get referenceModelViewLeft => '좌측';

  @override
  String get referenceModelViewRight => '우측';

  @override
  String get menuZoomIn => '확대';

  @override
  String get menuZoomOut => '축소';

  @override
  String get menuShowGrid => '그리드 표시';

  @override
  String get menuHideGrid => '그리드 숨기기';

  @override
  String get menuBlackWhite => '흑백';

  @override
  String get menuDisableBlackWhite => '흑백 해제';

  @override
  String get menuMirrorPreview => '미러 미리보기';

  @override
  String get menuDisableMirror => '미러 해제';

  @override
  String get menuTiledPreview => '타일 미리보기';

  @override
  String get menuDisableTiledPreview => '타일 미리보기 끄기';

  @override
  String get menuShowPerspectiveGuide => '원근 가이드 표시';

  @override
  String get menuHidePerspectiveGuide => '원근 가이드 숨기기';

  @override
  String get menuPerspectiveMode => '원근 모드';

  @override
  String get menuPerspective1Point => '1점 원근';

  @override
  String get menuPerspective2Point => '2점 원근';

  @override
  String get menuPerspective3Point => '3점 원근';

  @override
  String get menuWorkspaceDefault => '기본';

  @override
  String get menuWorkspaceSai2 => 'SAI2';

  @override
  String get menuSwitchWorkspace => '작업 공간 전환';

  @override
  String get menuResetWorkspace => '작업 공간 재설정';

  @override
  String get menuEdgeSofteningEllipsis => '가장자리 부드럽게…';

  @override
  String get menuNarrowLinesEllipsis => '선 굵기 줄이기…';

  @override
  String get menuExpandFillEllipsis => '채우기 확장…';

  @override
  String get menuGaussianBlurEllipsis => '가우시안 블러…';

  @override
  String get menuRemoveColorLeakEllipsis => '색 번짐 제거…';

  @override
  String get menuHueSaturationEllipsis => '색상/채도…';

  @override
  String get menuBrightnessContrastEllipsis => '밝기/대비…';

  @override
  String get menuColorRangeEllipsis => '색상 범위…';

  @override
  String get menuBlackWhiteEllipsis => '흑백…';

  @override
  String get menuBinarizeEllipsis => '이진화…';

  @override
  String get menuScanPaperDrawingEllipsis => '스캔 종이그림…';

  @override
  String get menuScanPaperDrawing => '스캔 종이그림';

  @override
  String get menuInvertColors => '색상 반전';

  @override
  String get canvasSizeTitle => '캔버스 크기';

  @override
  String get canvasSizeAnchorLabel => '얥커';

  @override
  String get canvasSizeAnchorDesc => '얥커 포인트를 기준으로 캔버스 크기를 조정합니다.';

  @override
  String get confirm => '확인';

  @override
  String get projectManagerTitle => '프로젝트 관리';

  @override
  String get selectAll => '전체 선택';

  @override
  String get openFolder => '폐더 열기';

  @override
  String deleteSelected(Object count) {
    return '선택 항목 삭제 ($count)';
  }

  @override
  String get imageSizeTitle => '이미지 크기';

  @override
  String get lockAspectRatio => '가로세로 비율 고정';

  @override
  String get realtimeParams => '실시간 매개변수';

  @override
  String get clearScribble => '낙서 지우기';

  @override
  String get newCanvasSettingsTitle => '새 캔버스 설정';

  @override
  String get custom => '사용자 정의';

  @override
  String get colorWhite => '흰색';

  @override
  String get colorLightGray => '밝은 회색';

  @override
  String get colorBlack => '검은색';

  @override
  String get colorTransparent => '투명';

  @override
  String get create => '생성';

  @override
  String currentPreset(Object name) {
    return '현재 사전 설정: $name';
  }

  @override
  String get exportSettingsTitle => '내보내기 설정';

  @override
  String get exportTypeLabel => '내보내기 유형';

  @override
  String get exportTypeBitmap => '비트맵';

  @override
  String get exportTypePng => '비트맵 PNG';

  @override
  String get exportTypeSvg => '벡터 SVG (실험적)';

  @override
  String get exportBitmapFormatLabel => '비트맵 형식';

  @override
  String get exportBitmapFormatPng => 'PNG';

  @override
  String get exportBitmapFormatWebp => 'WebP';

  @override
  String get webpCompressionLabel => 'WebP 압축';

  @override
  String get webpLossless => '무손실';

  @override
  String get webpLossy => '손실';

  @override
  String webpQualityLabel(Object value) {
    return '품질: $value';
  }

  @override
  String get exportScaleLabel => '내보내기 배율';

  @override
  String get reset => '초기화';

  @override
  String exportOutputSize(Object width, Object height) {
    return '출력 크기: $width x $height px';
  }

  @override
  String get exportAntialiasingLabel => '안티앨리어싱';

  @override
  String get enableAntialiasing => '안티앨리어싱 활성화';

  @override
  String get vectorParamsLabel => '벡터 매개변수';

  @override
  String vectorMaxColors(Object count) {
    return '최대 색상 수: $count';
  }

  @override
  String vectorSimplify(Object value) {
    return '단순화 강도: $value';
  }

  @override
  String get export => '내보내기';

  @override
  String get invalidDimensions => '유현한 치수(px)를 입력하세요.';

  @override
  String get widthPx => '너비 (px)';

  @override
  String get heightPx => '높이 (px)';

  @override
  String get noAutosavedProjects => '자동 저장된 프로젝트가 없습니다';

  @override
  String get revealProjectLocation => '선택한 프로젝트 위치 열기';

  @override
  String get deleteSelectedProjects => '선택한 프로젝트 삭제';

  @override
  String loadFailed(Object error) {
    return '불러오기 실패: $error';
  }

  @override
  String deleteFailed(Object error) {
    return '삭제 실패: $error';
  }

  @override
  String projectFileInfo(Object size, Object date) {
    return '크기: $size · 수정됨: $date';
  }

  @override
  String projectCanvasInfo(Object width, Object height) {
    return '캔버스 $width x $height';
  }

  @override
  String get samplingMethod => '샘플링 방법';

  @override
  String currentSize(Object width, Object height) {
    return '현재 크기: $width x $height px';
  }

  @override
  String get samplingNearestLabel => '최근접 이웃';

  @override
  String get samplingNearestDesc => '가장자리를 선명하게 유지합니다. 픽셀 아트에 적합합니다.';

  @override
  String get samplingBilinearLabel => '쌍선형';

  @override
  String get samplingBilinearDesc => '부드럽게 보간합니다. 일반적인 크기 조정에 적합합니다.';

  @override
  String get tabletPressureLatest => '최신 압력';

  @override
  String get tabletPressureMin => '최소 압력';

  @override
  String get tabletPressureMax => '최대 압력';

  @override
  String get tabletRadiusPx => '추정 반경 (px)';

  @override
  String get tabletTiltRad => '기울기 (rad)';

  @override
  String get tabletSampleCount => '샘플 수';

  @override
  String get tabletSampleRateHz => '샘플링 속도 (Hz)';

  @override
  String get tabletPointerType => '포인터 유형';

  @override
  String get pointerKindMouse => '마우스';

  @override
  String get pointerKindTouch => '터치';

  @override
  String get pointerKindStylus => '스타일러스';

  @override
  String get pointerKindInvertedStylus => '스타일러스 (지우개)';

  @override
  String get pointerKindTrackpad => '트랙패드';

  @override
  String get pointerKindUnknown => '알 수 없음';

  @override
  String get presetMobilePortrait => '모바일 세로 (1080 x 1920)';

  @override
  String get presetSquare => '정사각형 (1024 x 1024)';

  @override
  String presetPixelArt(Object width, Object height) {
    return '픽셀 아트 ($width x $height)';
  }

  @override
  String get untitledProject => '제목 없는 프로젝트';

  @override
  String get invalidResolution => '유현한 해상도를 입력하세요';

  @override
  String minResolutionError(Object value) {
    return '해상도는 $value px 이상이어야 합니다';
  }

  @override
  String maxResolutionError(Object value) {
    return '해상도는 $value px 이하여야 합니다';
  }

  @override
  String get projectName => '프로젝트 이름';

  @override
  String get workspacePreset => '작업 공간 사전 설정';

  @override
  String get workspacePresetDesc => '캔버스 생성 시 일반적인 도구 설정을 자동으로 적용합니다.';

  @override
  String get workspaceIllustration => '일러스트레이션';

  @override
  String get workspaceIllustrationDesc => '브러시: 연필, 가장자리 부드러움: 1';

  @override
  String get workspaceIllustrationDesc2 => '스트림라인: 변경 없음';

  @override
  String get workspaceCelShading => '셀 셰이딩';

  @override
  String get workspaceCelShadingDesc1 => '브러시: 셀화 브러시, 가장자리 부드러움: 0';

  @override
  String get workspaceCelShadingDesc2 => '채우기 도구 영역 확장: 켜기';

  @override
  String get workspaceCelShadingDesc3 => '채우기 도구 안티앨리어싱: 끄기';

  @override
  String get workspacePixel => '픽셀 아트';

  @override
  String get workspacePixelDesc1 => '브러시: 픽셀, 브러시/채우기 도구 안티앨리어싱: 0';

  @override
  String get workspacePixelDesc2 => '그리드 표시: 켜기';

  @override
  String get workspacePixelDesc3 => '벡터 드로잉: 변경 없음';

  @override
  String get workspacePixelDesc4 => '손떨림 보정: 0';

  @override
  String get workspaceDefault => '기본값';

  @override
  String get workspaceDefaultDesc => '현재 도구 설정을 변경하지 않음';

  @override
  String get resolutionPreset => '해상도 사전 설정';

  @override
  String get customResolution => '사용자 정의 해상도';

  @override
  String get swapDimensions => '너비/높이 바꾸기';

  @override
  String finalSizePreview(Object width, Object height, Object ratio) {
    return '최종 크기: $width x $height px (비율 $ratio)';
  }

  @override
  String get enterValidDimensions => '유현한 치수를 입력하세요';

  @override
  String get backgroundColor => '배경색';

  @override
  String get exportBitmapDesc =>
      '래스터 형식이 필요한 일반적인 내보내기에 적합하며 크기 조정 및 안티앨리어싱을 지원합니다.';

  @override
  String get exportVectorDesc =>
      '현재 캔버스를 벡터 경로로 자동 변환합니다. 벡터 도구에서 편집하기에 적합합니다.';

  @override
  String get exampleScale => '예: 1.0';

  @override
  String get enterPositiveValue => '0보다 큰 값을 입력하세요';

  @override
  String get antialiasingBeforeExport => '내보내기 전 안티앨리어싱 적용';

  @override
  String get brushAntialiasing => '브러시 안티앨리어싱';

  @override
  String get bucketAntialiasing => '채우기 안티앨리어싱';

  @override
  String get antialiasingDesc =>
      '선의 밀도를 유지하면서 가장자리를 부드럽게 합니다. Retas 애니메이션 소프트웨어의 질감을 재현합니다.';

  @override
  String levelLabel(Object level) {
    return '레벨 $level';
  }

  @override
  String vectorExportSize(Object width, Object height) {
    return '내보내기 크기: $width x $height (캔버스 크기 사용)';
  }

  @override
  String colorCount(Object count) {
    return '$count 색상';
  }

  @override
  String get vectorSimplifyDesc =>
      '색상 수를 줄이고 단순화 강도를 높이면 SVG가 단순화됩니다. 값이 너무 낮으면 노드가 너무 많아집니다.';

  @override
  String get antialiasNone =>
      '레벨 0 (끄기): 픽셀의 날카로운 가장자리를 유지하고 안티앨리어싱을 적용하지 않습니다.';

  @override
  String get antialiasLow =>
      '레벨 1 (낮음): 앨리어싱을 약간 완화하고 선의 밀도를 유지하면서 가장자리를 부드럽게 합니다.';

  @override
  String get antialiasMedium =>
      '레벨 2 (표준): 선명함과 부드러움의 균형을 유지하여 Retas와 같은 깔끔한 선을 만듭니다.';

  @override
  String get antialiasHigh =>
      '레벨 3 (높음): 가장 강력한 부드러움 효과. 부드러운 전환이 필요하거나 크게 확대할 때 적합합니다.';

  @override
  String get tolerance => '허용 오차';

  @override
  String get fillGap => '틈새 닫기';

  @override
  String get sampleAllLayers => '모든 레이어 샘플링';

  @override
  String get contiguous => '인접 픽셀만';

  @override
  String get swallowColorLine => '색상 선 삼키기';

  @override
  String get swallowBlueColorLine => '파란색 선 삼키기';

  @override
  String get swallowGreenColorLine => '초록색 선 삼키기';

  @override
  String get swallowRedColorLine => '빨간색 선 삼키기';

  @override
  String get swallowAllColorLine => '모든 색상 선 삼키기';

  @override
  String get cropOutsideCanvas => '캔버스 밖 자르기';

  @override
  String get noAdjustableSettings => '이 도구에는 조정 가능한 설정이 없습니다';

  @override
  String get hollowStroke => '중공 획';

  @override
  String get hollowStrokeRatio => '중공 비율';

  @override
  String get eraseOccludedParts => '겹친 부분 지우기';

  @override
  String get solidFill => '단색 채우기';

  @override
  String get autoSharpTaper => '자동 날카로운 끝';

  @override
  String get stylusPressure => '필압 감지';

  @override
  String get touchDrawing => '터치 드로잉';

  @override
  String get simulatedPressure => '모의 필압';

  @override
  String get switchToEraser => '지우개로 전환';

  @override
  String get vectorDrawing => '벡터 드로잉';

  @override
  String get smoothCurve => '곡선 부드럽게';

  @override
  String get sprayEffect => '스프레이 효과';

  @override
  String get brushPreset => '브러시 프리셋';

  @override
  String get brushPresetDesc => '간격, 흐름, 형태 등을 포함한 프리셋을 선택합니다.';

  @override
  String get editBrushPreset => '프리셋 편집';

  @override
  String get editBrushPresetDesc => '현재 프리셋의 내부 파라미터를 조정합니다.';

  @override
  String get brushPresetDialogTitle => '브러시 프리셋 편집';

  @override
  String get brushPresetNameLabel => '프리셋 이름';

  @override
  String get brushPresetPencil => '연필';

  @override
  String get brushPresetCel => '셀화 브러시';

  @override
  String get brushPresetPen => '펜';

  @override
  String get brushPresetScreentone => '스크린톤';

  @override
  String get brushPresetPixel => '픽셀';

  @override
  String get brushPresetDryInk => '드라이 잉크';

  @override
  String get brushPresetCharcoal => '차콜';

  @override
  String get brushPresetStarBrush => '별 브러시';

  @override
  String get brushSpacing => '간격';

  @override
  String get brushHardness => '경도';

  @override
  String get brushFlow => '흐름';

  @override
  String get brushScatter => '산포';

  @override
  String get brushRotationJitter => '회전 지터';

  @override
  String get brushSnapToPixel => '픽셀 스냅';

  @override
  String get screentoneEnabled => '스크린톤';

  @override
  String get screentoneShape => '도트 모양';

  @override
  String get screentoneSpacing => '도트 간격';

  @override
  String get screentoneDotSize => '도트 크기';

  @override
  String get screentoneRotation => '도트 회전';

  @override
  String get screentoneSoftness => '도트 부드러움';

  @override
  String get brushShape => '브러시 모양';

  @override
  String get brushAuthorLabel => '작성자';

  @override
  String get brushVersionLabel => '버전';

  @override
  String get importBrush => '브러시 가져오기';

  @override
  String get exportBrush => '브러시 내보내기';

  @override
  String get exportBrushTitle => '브러시 내보내기';

  @override
  String get unsavedBrushChangesPrompt => '브러시 설정이 변경되었습니다. 저장할까요?';

  @override
  String get discardChanges => '변경 사항 버리기';

  @override
  String get brushShapeFolderLabel => '브러시 모양 폴더';

  @override
  String get openBrushShapesFolder => '브러시 모양 폴더 열기';

  @override
  String get randomRotation => '무작위 회전';

  @override
  String get smoothRotation => '부드러운 회전';

  @override
  String get selectionShape => '선택 모양';

  @override
  String get selectionAdditive => '선택 추가';

  @override
  String get selectionAdditiveDesc => '켜면 Shift 없이도 선택을 여러 번 추가할 수 있습니다.';

  @override
  String get fontSize => '글꼴 크기';

  @override
  String get lineHeight => '줄 간격';

  @override
  String get letterSpacing => '자간';

  @override
  String get textStroke => '텍스트 획';

  @override
  String get strokeWidth => '획 두께';

  @override
  String get strokeColor => '획 색상';

  @override
  String get pickColor => '색상 추출';

  @override
  String get alignment => '정렬';

  @override
  String get alignCenter => '가운데 정렬';

  @override
  String get alignRight => '오른쪽 정렬';

  @override
  String get alignLeft => '왼쪽 정렬';

  @override
  String get orientation => '방향';

  @override
  String get horizontal => '수평';

  @override
  String get vertical => '수직';

  @override
  String get textToolHint => '텍스트 채우기에는 왼쪽 하단의 색상 선택기를, 획에는 보조 색상을 사용하세요.';

  @override
  String get shapeType => '도형 유형';

  @override
  String get brushSize => '브러시 크기';

  @override
  String get spraySize => '스프레이 크기';

  @override
  String get brushFineTune => '브러시 미세 조정';

  @override
  String get increase => '증가';

  @override
  String get decrease => '감소';

  @override
  String get stabilizer => '손떨림 보정';

  @override
  String get streamline => '스트림라인';

  @override
  String get off => '끄기';

  @override
  String get taperEnds => '양쪽 끝 가늘게';

  @override
  String get taperCenter => '중앙 가늘게';

  @override
  String get auto => '자동';

  @override
  String get softSpray => '소프트 스프레이';

  @override
  String get splatter => '튀기기';

  @override
  String get rectSelection => '사각형 선택';

  @override
  String get ellipseSelection => '타원 선택';

  @override
  String get polygonLasso => '다각형 올가미';

  @override
  String get rectangle => '사각형';

  @override
  String get ellipse => '타원';

  @override
  String get triangle => '삼각형';

  @override
  String get line => '직선';

  @override
  String get circle => '원';

  @override
  String get square => '정사각형';

  @override
  String get star => '오각별';

  @override
  String get brushSizeDesc =>
      '현재 브러시의 직경(픽셀)을 설정합니다. 값이 클수록 선이 굵어지고, 작을수록 세부 묐사에 적합합니다.';

  @override
  String get spraySizeDesc =>
      '스프레이 영역의 반경을 결정합니다. 반경이 클수록 넓은 영역을 덮지만 입자가 분산됩니다.';

  @override
  String get toleranceDesc =>
      '채우기 또는 자동 선택 시 \'색상 유사성\'의 허용 오차를 제어합니다. 높을수록 비슷한 색상을 더 많이 포함합니다.';

  @override
  String get fillGapDesc =>
      '채우기 시 선화의 작은 틈을 닫아 색이 새는 것을 방지합니다. 값이 클수록 더 큰 틈을 닫지만, 아주 얇은 영역은 채우지 못할 수 있습니다.';

  @override
  String get antialiasingSliderDesc =>
      '브러시 또는 채우기 가장자리에 말티샘플링 스무딩을 추가합니다. 레벨 0은 픽셀 스타일을 유지합니다.';

  @override
  String get stabilizerDesc =>
      '손떨림을 상쇄하기 위해 포인터 궤적을 실시간으로 부드럽게 합니다. 레벨이 높을수록 안정적이지만 반응이 느려집니다.';

  @override
  String get streamlineDesc =>
      'Procreate 스타일 StreamLine: 펜을 뗀 후 획을 부드럽게 재계산하고 보간 애니메이션으로 더 매끄러운 경로로 돌아갑니다(레벨이 높을수록 강함).';

  @override
  String get fontSizeDesc => '전체 크기 조정을 위해 텍스트의 픽셀 높이를 조정합니다.';

  @override
  String get lineHeightDesc => '텍스트 줄 사이의 수직 거리를 제어합니다.';

  @override
  String get letterSpacingDesc => '문자 사이의 수평 간격을 변경합니다.';

  @override
  String get strokeWidthDesc => '텍스트 획의 두께를 설정합니다.';

  @override
  String get hollowStrokeDesc => '획의 중심을 비워 중공 윤곽 효과를 만듭니다.';

  @override
  String get hollowStrokeRatioDesc => '중공 영역의 크기를 조절합니다. 값이 클수록 윤곽이 더 얇아집니다.';

  @override
  String get eraseOccludedPartsDesc =>
      '같은 레이어에서 나중에 그린 중공 선이 다른 선과 겹치는 부분을 지웁니다.';

  @override
  String get solidFillDesc =>
      '도형 도구가 채워진 블록을 그릴지 빈 윤곽선을 그릴지 결정합니다. 켜면 채워진 도형을 그립니다.';

  @override
  String get randomRotationDesc => '켜면 사각형/삼각형/오각별 스탬프가 스트로크를 따라 무작위로 회전합니다.';

  @override
  String get autoSharpTaperDesc =>
      '스트로크의 시작과 끝을 자동으로 가늘게 하여 셀 셰이딩과 같은 날카로운 선을 만듭니다.';

  @override
  String get stylusPressureDesc =>
      '필압에 따른 브러시 크기/불투명도 변화를 허용합니다. 끄면 하드웨어 필압을 무시합니다.';

  @override
  String get touchDrawingDesc => '끄면 손가락 터치로는 그릴 수 없으며, 스타일러스는 계속 그릴 수 있습니다.';

  @override
  String get simulatedPressureDesc => '필압 장치가 없는 경우 마우스 속도를 기반으로 필압을 시뮬레이션합니다.';

  @override
  String get switchToEraserDesc => '현재 브러시/스프레이와 동일한 텍스처를 가진 지우개로 전환합니다.';

  @override
  String get vectorDrawingDesc =>
      '스트로크를 벡터 곡선으로 미리 보고, 120Hz의 부드러운 피드백과 무손실 확대를 제공합니다. 픽셀 출력 시에는 끄세요.';

  @override
  String get smoothCurveDesc =>
      '벡터 드로잉이 켜져 있을 때 곡선 노드를 더 부드럽게 하여 모서리를 줄이지만 반응성이 다소 희생됩니다.';

  @override
  String get sampleAllLayersDesc =>
      '채우기 시 보이는 모든 레이어의 색상을 참조합니다. 끄면 현재 레이어만 감지합니다.';

  @override
  String get contiguousDesc => '인접한 픽셀로만 퍼집니다. 끄면 캔버스 전체의 일치하는 색상을 채웁니다.';

  @override
  String get swallowColorLineDesc =>
      '색상 선으로 채우기를 자동으로 확장하여 흰색 틈을 없액니다. Retas 워크플로 전용입니다.';

  @override
  String get swallowBlueColorLineDesc => '채우기 시 파란색 선만 삼킵니다.';

  @override
  String get swallowGreenColorLineDesc => '채우기 시 초록색 선만 삼킵니다.';

  @override
  String get swallowRedColorLineDesc => '채우기 시 빨간색 선만 삼킵니다.';

  @override
  String get swallowAllColorLineDesc => '채우기 시 빨강/초록/파랑 선을 삼킵니다.';

  @override
  String get cropOutsideCanvasDesc =>
      '레이어 조정 시 캔버스 밖의 픽셀을 자릅니다. 끄면 모든 픽셀을 유지합니다.';

  @override
  String get textAntialiasingDesc =>
      '텍스트 렌더링에 안티앨리어싱을 활성화하여 밀도를 유지하면서 글자를 부드럽게 합니다.';

  @override
  String get textStrokeDesc => '텍스트의 윤곽선 채널을 활성화합니다.';

  @override
  String get sprayEffectDesc =>
      '스프레이 모델을 전환합니다. \'소프트 스프레이\'는 안개 같은 그라데이션, \'튀기기\'는 입자 형태입니다.';

  @override
  String get rectSelectDesc => '사각형 영역을 빠르게 선택합니다.';

  @override
  String get ellipseSelectDesc => '원형 또는 타원형 선택 영역을 만듭니다.';

  @override
  String get polyLassoDesc => '점들을 찍어 임의의 다각형 선택 영역을 그립니다.';

  @override
  String get rectShapeDesc => '수평 사각형 또는 정사각형을 그립니다 (윤곽선/채우기).';

  @override
  String get ellipseShapeDesc => '타원 또는 원의 윤곽선/채우기를 그립니다.';

  @override
  String get triangleShapeDesc => '기하학적 삼각형을 그리거나 삼각형 팁을 사용하여 날카로운 윤곽선을 그립니다.';

  @override
  String get lineShapeDesc => '시작점에서 끝점까지 직선을 그립니다.';

  @override
  String get circleTipDesc => '브러시 팁을 원형으로 유지하여 부드럽고 둥근 스트로크를 만듭니다.';

  @override
  String get squareTipDesc => '사각형 팁을 사용하여 날카로운 픽셀 스트로크를 만듭니다.';

  @override
  String get starTipDesc => '오각별 팁으로 장식적인 스트로크를 그립니다.';

  @override
  String get apply => '적용';

  @override
  String get next => '다음';

  @override
  String get disableVectorDrawing => '벡터 드로잉 비활성화';

  @override
  String get disableVectorDrawingConfirm => '벡터 드로잉을 비활성화하시겠습니까?';

  @override
  String get disableVectorDrawingDesc => '비활성화하면 성능이 저하됩니다.';

  @override
  String get dontShowAgain => '다시 표시 안 함';

  @override
  String get newLayer => '새 레이어';

  @override
  String get mergeDown => '아래로 병합';

  @override
  String get delete => '삭제';

  @override
  String get duplicate => '복제';

  @override
  String get rasterizeTextLayer => '텍스트 레이어 래스터화';

  @override
  String get opacity => '불투명도';

  @override
  String get blendMode => '혼합 모드';

  @override
  String get clearFill => '채우기 지우기';

  @override
  String get colorLine => '색상 선';

  @override
  String get currentColor => '현재 색상';

  @override
  String get rgb => 'RGB';

  @override
  String get hsv => 'HSV';

  @override
  String get preparingLayer => '레이어 준비 중...';

  @override
  String get generatePaletteTitle => '캔버스에서 팔레트 생성';

  @override
  String get generatePaletteDesc => '색상 수를 선택하거나 사용자 정의 값을 입력하세요.';

  @override
  String get customCount => '사용자 정의 수';

  @override
  String get selectExportFormat => '내보내기 형식 선택';

  @override
  String get selectPaletteFormatDesc => '팔레트 내보내기 형식을 선택하세요.';

  @override
  String get noColorsDetected => '색상이 감지되지 않았습니다.';

  @override
  String get alphaThreshold => '알파 임계값';

  @override
  String get blurRadius => '흐림 반경';

  @override
  String get repairRange => '수정 별위';

  @override
  String get selectAntialiasLevel => '안티앨리어싱 레벨 선택';

  @override
  String get colorCountLabel => '색상 수';

  @override
  String get completeTransformFirst => '현재 변화를 먼저 완료하세요.';

  @override
  String get enablePerspectiveGuideFirst => '투시 펜을 사용하기 전에 투시 가이드를 활성화하세요.';

  @override
  String get lineNotAlignedWithPerspective =>
      '현재 선이 투시 방향과 일치하지 않습니다. 각도를 조정하세요.';

  @override
  String get layerBackground => '배경';

  @override
  String layerDefaultName(Object index) {
    return '레이어 $index';
  }

  @override
  String get duplicateLayer => '레이어 복제';

  @override
  String layerCopyName(Object name) {
    return '$name 복사본';
  }

  @override
  String get unlockLayer => '레이어 잠금 해제';

  @override
  String get lockLayer => '레이어 잠금';

  @override
  String get releaseClippingMask => '클리핑 마스크 해제';

  @override
  String get createClippingMask => '클리핑 마스크 생성';

  @override
  String get hide => '숨기기';

  @override
  String get show => '표시';

  @override
  String get colorRangeTitle => '색상 별위';

  @override
  String get colorPickerTitle => '색상 선택기';

  @override
  String get layerManagerTitle => '레이어 관리';

  @override
  String get edgeSoftening => '가장자리 부드럽게';

  @override
  String get undo => '실행 취소';

  @override
  String get redo => '다시 실행';

  @override
  String undoShortcut(Object shortcut) {
    return '실행 취소 ($shortcut)';
  }

  @override
  String redoShortcut(Object shortcut) {
    return '다시 실행 ($shortcut)';
  }

  @override
  String opacityPercent(Object percent) {
    return '불투명도 $percent%';
  }

  @override
  String get clippingMask => '클리핑 마스크';

  @override
  String get deleteLayerTitle => '레이어 삭제';

  @override
  String get deleteLayerDesc => '이 레이어를 삭제합니다. 실행 취소 가능합니다.';

  @override
  String get mergeDownDesc => '아래 레이어와 병합합니다.';

  @override
  String get duplicateLayerDesc => '레이어의 모든 내용을 복제합니다.';

  @override
  String get more => '더보기';

  @override
  String get lockLayerDesc => '실수로 편집하는 것을 방지하기 위해 잠급니다.';

  @override
  String get unlockLayerDesc => '편집할 수 있도록 잠금을 해제합니다.';

  @override
  String get clippingMaskDescOn => '일반 레이어로 복원합니다.';

  @override
  String get clippingMaskDescOff => '아래 레이어에 클리핑합니다.';

  @override
  String get red => '빨강';

  @override
  String get green => '초록';

  @override
  String get blue => '파랑';

  @override
  String get hue => '색상';

  @override
  String get saturation => '채도';

  @override
  String get value => '명도';

  @override
  String get hsvBoxSpectrum => 'HSV 상자 스펙트럼';

  @override
  String get hueRingSpectrum => '색상 링 스펙트럼';

  @override
  String get rgbHsvSliders => 'RGB / HSV 슬라이더';

  @override
  String get boardPanelPicker => '보드 패널 피커';

  @override
  String get adjustCurrentColor => '현재 색상 조정';

  @override
  String get adjustStrokeColor => '획 색상 조정';

  @override
  String copiedHex(Object hex) {
    return '$hex 복사됨';
  }

  @override
  String rotationLabel(Object degrees) {
    return '회전: $degrees°';
  }

  @override
  String scaleLabel(Object x, Object y) {
    return '배율: $x% x $y%';
  }

  @override
  String get failedToExportTransform => '변확 결과 내보내기 실패';

  @override
  String get cannotLocateLayer => '활성 레이어를 찾을 수 없습니다.';

  @override
  String get layerLockedCannotTransform => '활성 레이어가 잠겨 있어 변확할 수 없습니다.';

  @override
  String get cannotEnterTransformMode => '자유 변확 모드로 들어갈 수 없습니다.';

  @override
  String get applyTransformFailed => '변확 적용 실패. 다시 시도하세요.';

  @override
  String get freeTransformTitle => '자유 변확';

  @override
  String get colorIndicatorDetail => '클릭하여 색상 편집기를 열거나, 값을 입력하거나, HEX를 복사하세요.';

  @override
  String get gplDesc => 'GIMP, Krita, Clip Studio Paint 등과 호환되는 텍스트 형식.';

  @override
  String get aseDesc => 'Aseprite, LibreSprite 픽셀 아트 소프트웨어에 적합합니다.';

  @override
  String get asepriteDesc => 'Aseprite에서 직접 열 수 있는 .aseprite 확장자를 사용합니다.';

  @override
  String get gradientPaletteFailed =>
      '현재 색상으로 그라데이션 팔레트를 생성할 수 없습니다. 다시 시도하세요.';

  @override
  String get gradientPaletteTitle => '그라데이션 팔레트 (현재 색상)';

  @override
  String paletteCountRange(Object min, Object max) {
    return '범위 $min - $max';
  }

  @override
  String allowedRange(Object min, Object max) {
    return '허용 범위: $min - $max 색상';
  }

  @override
  String get enterValidColorCount => '유현한 색상 수를 입력하세요.';

  @override
  String get paletteGenerationFailed => '팔레트를 생성할 수 없습니다. 다시 시도하세요.';

  @override
  String get noValidColorsFound => '유현한 색상을 찾을 수 없습니다. 캔버스에 내용이 있는지 확인하세요.';

  @override
  String get paletteEmpty => '이 팔레트에는 사용할 수 있는 색상이 없습니다.';

  @override
  String paletteMinColors(Object min) {
    return '팔레트에는 최소 $min가지 색상이 필요합니다.';
  }

  @override
  String get paletteDefaultName => '팔레트';

  @override
  String get paletteEmptyExport => '이 팔레트에는 내보낼 수 있는 색상이 없습니다.';

  @override
  String get exportPaletteTitle => '팔레트 내보내기';

  @override
  String get webDownloadDesc => '브라우저가 기본 다운로드 디렉토리에 팔레트를 저장합니다.';

  @override
  String get download => '다운로드';

  @override
  String paletteDownloaded(Object name) {
    return '팔레트를 다운로드했습니다: $name';
  }

  @override
  String paletteExported(Object path) {
    return '팔레트를 $path에 내보냈습니다';
  }

  @override
  String paletteExportFailed(Object error) {
    return '팔레트 내보내기 실패: $error';
  }

  @override
  String get selectEditableLayerFirst => '먼저 편집 가능한 레이어를 선택하세요.';

  @override
  String get layerLockedNoFilter => '활성 레이어가 잠겨 있어 필터를 적용할 수 없습니다.';

  @override
  String get textLayerNoFilter => '활성 레이어가 텍스트입니다. 래스터화하거나 레이어를 전환하세요.';

  @override
  String get hueSaturation => '색상/채도';

  @override
  String get brightnessContrast => '밝기/대비';

  @override
  String get blackAndWhite => '흑백';

  @override
  String get binarize => '이진화';

  @override
  String get gaussianBlur => '가우시안 흐림';

  @override
  String get leakRemoval => '누출 제거';

  @override
  String get lineNarrow => '선 좁히기';

  @override
  String get narrowRadius => '좁히기 반경';

  @override
  String get fillExpand => '채우기 확장';

  @override
  String get expandRadius => '확장 반경';

  @override
  String get noTransparentPixelsFound => '처리 가능한 투명 픽셀이 감지되지 않았습니다.';

  @override
  String get filterApplyFailed => '필터 적용 실패. 다시 시도하세요.';

  @override
  String get canvasNotReadyInvert => '캔버스가 준비되지 않아 색상을 반전할 수 없습니다.';

  @override
  String get layerLockedInvert => '활성 레이어가 잠겨 있어 색상을 반전할 수 없습니다.';

  @override
  String get layerEmptyInvert => '활성 레이어가 비어 있어 색상을 반전할 수 없습니다.';

  @override
  String get noPixelsToInvert => '반전할 픽셀이 없습니다.';

  @override
  String get layerEmptyScanPaperDrawing => '활성 레이어가 비어 있어 스캔 종이그림을 적용할 수 없습니다.';

  @override
  String get scanPaperDrawingNoChanges => '변환 가능한 픽셀이 감지되지 않았습니다.';

  @override
  String get edgeSofteningFailed =>
      '가장자리 부드럽게를 적용할 수 없습니다. 레이어가 비어 있거나 잠겨 있을 수 있습니다.';

  @override
  String get layerLockedEdgeSoftening => '활성 레이어가 잠겨 있어 가장자리 부드럽게를 적용할 수 없습니다.';

  @override
  String get canvasNotReadyColorRange => '캔버스가 준비되지 않아 색상 변위를 계산할 수 없습니다.';

  @override
  String get layerLockedColorRange => '활성 레이어가 잠겨 있어 색상 변위를 설정할 수 없습니다.';

  @override
  String get layerEmptyColorRange => '활성 레이어가 비어 있어 색상 변위를 설정할 수 없습니다.';

  @override
  String get noColorsToProcess => '처리 가능한 색상이 없습니다.';

  @override
  String get targetColorsNotLess => '대상 색상 수가 현재보다 적지 않아 레이어가 변경되지 않았습니다.';

  @override
  String get colorRangeApplyFailed => '색상 변위 적용 실패. 다시 시도하세요.';

  @override
  String get colorRangePreviewFailed => '색상 변위 미리보기 생성 실패. 다시 시도하세요.';

  @override
  String get lightness => '명도';

  @override
  String get brightness => '밝기';

  @override
  String get contrast => '대비';

  @override
  String get selectSaveFormat => '저장할 파일 형식을 선택하세요.';

  @override
  String get saveAsPsd => 'PSD로 저장';

  @override
  String get saveAsSai2 => 'SAI2로 저장';

  @override
  String get saveAsRin => 'RIN으로 저장';

  @override
  String get dontSave => '저장 안 함';

  @override
  String get save => '저장';

  @override
  String get renameProject => '프로젝트 이름 변경';

  @override
  String get enterNewProjectName => '새 프로젝트 이름을 입력하세요';

  @override
  String get rename => '이름 변경';

  @override
  String get canvasNotReady => '캔버스 준비 중';

  @override
  String get toolPanel => '도구 패널';

  @override
  String get toolbarTitle => '도구 모음';

  @override
  String get toolOptionsTitle => '도구 옵션';

  @override
  String get defaultProjectDirectory => '기본 프로젝트 디렉토리';

  @override
  String get minimize => '최소화';

  @override
  String get maximizeRestore => '최대화/복원';

  @override
  String get fontFamily => '글꼴';

  @override
  String get fontSearchPlaceholder => '글꼴 검색...';

  @override
  String get noMatchingFonts => '일치하는 글꼴이 없습니다.';

  @override
  String get fontPreviewText => '미리보기 텍스트';

  @override
  String get fontPreviewLanguages => '테스트 언어';

  @override
  String get fontLanguageCategory => '언어 분류';

  @override
  String get fontLanguageAll => '전체';

  @override
  String get fontFavorites => '즐겨찾기';

  @override
  String get noFavoriteFonts => '즐겨찾는 글꼴이 없습니다.';

  @override
  String get importPaletteTitle => '팔레트 가져오기';

  @override
  String get cannotReadFile => '파일을 읽을 수 없습니다';

  @override
  String paletteImported(Object name) {
    return '팔레트를 가져왔습니다: $name';
  }

  @override
  String paletteImportFailed(Object error) {
    return '팔레트 가져오기 실패: $error';
  }

  @override
  String noChangesToSave(Object location) {
    return '$location에 저장할 변경 사항이 없습니다';
  }

  @override
  String projectSaved(Object location) {
    return '프로젝트를 $location에 저장했습니다';
  }

  @override
  String projectSaveFailed(Object error) {
    return '프로젝트 저장 실패: $error';
  }

  @override
  String get canvasNotReadySave => '캔버스가 준비되지 않아 저장할 수 없습니다.';

  @override
  String get saveProjectAs => '다른 이름으로 프로젝트 저장';

  @override
  String get webSaveDesc => '프로젝트 파일을 기기에 다운로드합니다.';

  @override
  String psdExported(Object path) {
    return 'PSD를 $path에 내보냈습니다';
  }

  @override
  String sai2Exported(Object path) {
    return 'SAI2를 $path에 내보냈습니다';
  }

  @override
  String projectDownloaded(Object fileName) {
    return '프로젝트를 다운로드했습니다: $fileName';
  }

  @override
  String psdDownloaded(Object fileName) {
    return 'PSD를 다운로드했습니다: $fileName';
  }

  @override
  String sai2Downloaded(Object fileName) {
    return 'SAI2를 다운로드했습니다: $fileName';
  }

  @override
  String get exportAsPsdTooltip => 'PSD로 내보내기';

  @override
  String get exportAsSai2Tooltip => 'SAI2로 내보내기';

  @override
  String get canvasNotReadyExport => '캔버스가 준비되지 않아 내보낼 수 없습니다.';

  @override
  String exportFileTitle(Object extension) {
    return '$extension 파일 내보내기';
  }

  @override
  String get webExportDesc => '내보낸 이미지를 기기에 다운로드합니다.';

  @override
  String fileDownloaded(Object extension, Object name) {
    return '$extension 파일을 다운로드했습니다: $name';
  }

  @override
  String fileExported(Object path) {
    return '파일을 $path에 내보냈습니다';
  }

  @override
  String exportFailed(Object error) {
    return '내보내기 실패: $error';
  }

  @override
  String get canvasNotReadyTransform => '캔버스가 준비되지 않아 변형할 수 없습니다.';

  @override
  String get canvasSizeErrorTransform => '변형 중 캔버스 크기 오류가 발생했습니다.';

  @override
  String get canvasNotReadyResizeImage => '캔버스가 준비되지 않아 이미지 크기를 조정할 수 없습니다.';

  @override
  String get resizeImageFailed => '이미지 크기 조정 실패.';

  @override
  String get canvasNotReadyResizeCanvas => '캔버스가 준비되지 않아 캔버스 크기를 조정할 수 없습니다.';

  @override
  String get resizeCanvasFailed => '캔버스 크기 조정 실패.';

  @override
  String get returnToHome => '홈으로 돌아가기';

  @override
  String get saveBeforeReturn => '홈으로 돌아가기 전에 변경 사항을 저장하시겠습니까?';

  @override
  String get closeCanvas => '캔버스 닫기';

  @override
  String get saveBeforeClose => '닫기 전에 변경 사항을 저장하시겠습니까?';

  @override
  String get nameCannotBeEmpty => '이름은 비워둘 수 없습니다.';

  @override
  String get noSupportedImageFormats => '지원되는 이미지 형식을 찾을 수 없습니다.';

  @override
  String importFailed(Object item, Object error) {
    return '$item 가져오기 실패: $error';
  }

  @override
  String get createdCanvasFromDrop => '드롭된 항목에서 캔버스를 생성했습니다.';

  @override
  String createdCanvasesFromDrop(Object count) {
    return '드롭된 항목에서 $count개의 캔버스를 생성했습니다.';
  }

  @override
  String get dropImageCreateFailed => '드롭된 이미지에서 캔버스를 생성하지 못했습니다.';

  @override
  String get canvasNotReadyDrop => '캔버스가 준비되지 않아 드롭 작업을 수행할 수 없습니다.';

  @override
  String get insertedDropImage => '드롭된 이미지를 삽입했습니다.';

  @override
  String insertedDropImages(Object count) {
    return '$count장의 드롭된 이미지를 삽입했습니다.';
  }

  @override
  String get dropImageInsertFailed => '드롭된 이미지 삽입 실패.';

  @override
  String get image => '이미지';

  @override
  String get on => '켜기';

  @override
  String get perspective1Point => '1점 투시';

  @override
  String get perspective2Point => '2점 투시';

  @override
  String get perspective3Point => '3점 투시';

  @override
  String resolutionLabel(Object resolution) {
    return '해상도: $resolution';
  }

  @override
  String zoomLabel(Object zoom) {
    return '확대/축소: $zoom';
  }

  @override
  String positionLabel(Object position) {
    return '위치: $position';
  }

  @override
  String gridLabel(Object grid) {
    return '그리드: $grid';
  }

  @override
  String blackWhiteLabel(Object state) {
    return '흑백: $state';
  }

  @override
  String mirrorLabel(Object state) {
    return '미러: $state';
  }

  @override
  String tileLabel(Object state) {
    return '타일: $state';
  }

  @override
  String perspectiveLabel(Object perspective) {
    return '투시: $perspective';
  }

  @override
  String get fileNameCannotBeEmpty => '파일 이름은 비워둘 수 없습니다.';

  @override
  String get blackPoint => '블랙 포인트';

  @override
  String get whitePoint => '화이트 포인트';

  @override
  String get midTone => '미드톤';

  @override
  String get rendererLabel => '렌더러';

  @override
  String get rendererNormal => '일반';

  @override
  String get rendererNormalDesc => '실시간 렌더링, 가장 빠름, 미리보기에 적합.';

  @override
  String get rendererCinematic => '트레일러';

  @override
  String get rendererCinematicDesc =>
      'Minecraft 공식 트레일러 스타일 재현. 부드러운 그림자와 고대비 조명.';

  @override
  String get rendererCycles => '사실적';

  @override
  String get rendererCyclesDesc => '패스 트레이싱 스타일 시뮬레이션. 매우 사실적인 조명 효과.';

  @override
  String get autoSaveCleanupThresholdLabel => '자동 저장 정리 임계값';

  @override
  String autoSaveCleanupThresholdValue(Object size) {
    return '현재 임계값: $size';
  }

  @override
  String get autoSaveCleanupThresholdDesc =>
      '자동 저장 폴더의 총 크기가 이 값을 넘으면 시작 시 정리 안내가 표시됩니다.';

  @override
  String get autoSaveCleanupDialogTitle => '자동 저장 용량이 큽니다';

  @override
  String autoSaveCleanupDialogMessage(Object size, Object limit) {
    return '자동 저장 프로젝트가 $size를 사용 중입니다(한도 $limit). 지금 정리할까요?';
  }

  @override
  String get autoSaveCleanupDialogClean => '정리';

  @override
  String get exportDestinationTitle => 'Export destination';

  @override
  String get exportDestinationDesc => 'Choose where to export the image.';

  @override
  String get imageSourceTitle => '이미지 가져오기 위치 선택';

  @override
  String get imageSourceDesc => '사진 또는 파일에서 이미지를 가져옵니다.';

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
