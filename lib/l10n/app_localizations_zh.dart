// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get webLoadingInitializingCanvas => '正在初始化画板…';

  @override
  String get webLoadingMayTakeTime => 'Web 端加载需要一些时间，请稍候。';

  @override
  String get closeAppTitle => '关闭应用';

  @override
  String unsavedProjectsWarning(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '检测到 $count 个未保存的项目。如果现在退出，最近的修改将会丢失。',
      one: '检测到 1 个未保存的项目。如果现在退出，最近的修改将会丢失。',
    );
    return '$_temp0';
  }

  @override
  String get cancel => '取消';

  @override
  String get discardAndExit => '丢弃并退出';

  @override
  String get homeTagline => '创作从这里开始';

  @override
  String get homeNewProject => '新建项目';

  @override
  String get homeNewProjectDesc => '从空白画布开启新的创意';

  @override
  String get homeOpenProject => '打开项目';

  @override
  String get homeOpenProjectDesc => '从磁盘加载 .rin / .psd / .sai2 或图片文件';

  @override
  String get homeRecentProjects => '最近打开';

  @override
  String get homeRecentProjectsDesc => '快速恢复自动保存的项目';

  @override
  String get homeProjectManager => '项目管理';

  @override
  String get homeProjectManagerDesc => '批量查看或清理自动保存的项目文件';

  @override
  String get homeSettings => '设置';

  @override
  String get homeSettingsDesc => '预览即将上线的个性化选项';

  @override
  String get homeAbout => '关于';

  @override
  String get homeAboutDesc => '了解项目 Misa Rin';

  @override
  String createProjectFailed(Object error) {
    return '创建项目失败：$error';
  }

  @override
  String get openProjectDialogTitle => '打开项目';

  @override
  String get openingProjectTitle => '正在打开项目…';

  @override
  String openingProjectMessage(Object fileName) {
    return '正在加载 $fileName';
  }

  @override
  String get cannotReadPsdContent => '无法读取 PSD 文件内容。';

  @override
  String get cannotReadSai2Content => '无法读取 SAI2 文件内容。';

  @override
  String get cannotReadProjectFileContent => '无法读取项目文件内容。';

  @override
  String openedProjectInfo(Object name) {
    return '已打开项目：$name';
  }

  @override
  String openProjectFailed(Object error) {
    return '打开项目失败：$error';
  }

  @override
  String get importImageDialogTitle => '导入图片';

  @override
  String importedImageInfo(Object name) {
    return '已导入图片：$name';
  }

  @override
  String importImageFailed(Object error) {
    return '导入图片失败：$error';
  }

  @override
  String get clipboardNoBitmapFound => '剪贴板中没有找到可以导入的位图。';

  @override
  String get clipboardImageDefaultName => '剪贴板图像';

  @override
  String get importedClipboardImageInfo => '已导入剪贴板图像';

  @override
  String importClipboardImageFailed(Object error) {
    return '导入剪贴板图像失败：$error';
  }

  @override
  String get webPreparingCanvasTitle => '正在准备画布…';

  @override
  String get webPreparingCanvasMessage => 'Web 端需要一些时间才能完成初始化，请稍候。';

  @override
  String get aboutTitle => '关于 Misa Rin';

  @override
  String get aboutDescription =>
      'Misa Rin 是一款专注于创意绘制与项目管理的应用，旨在为创作者提供流畅的绘图体验与可靠的项目存档能力。';

  @override
  String get aboutAppIdLabel => '应用标识';

  @override
  String get aboutAppVersionLabel => '应用版本';

  @override
  String get aboutDeveloperLabel => '开发者';

  @override
  String get close => '关闭';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsTabGeneral => '常规';

  @override
  String get settingsTabInput => '输入与笔刷';

  @override
  String get settingsTabStorage => '历史与存储';

  @override
  String get settingsTabAbout => '关于';

  @override
  String get tabletTest => '数位板测试';

  @override
  String get restoreDefaults => '恢复默认';

  @override
  String get ok => '好的';

  @override
  String get languageLabel => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEnglish => '英语';

  @override
  String get languageJapanese => '日语';

  @override
  String get languageKorean => '韩语';

  @override
  String get languageChineseSimplified => '中文（简体）';

  @override
  String get languageChineseTraditional => '中文（繁体）';

  @override
  String get themeModeLabel => '主题模式';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get stylusPressureSettingsLabel => '数位笔压设置';

  @override
  String get enableStylusPressure => '启用数位笔笔压';

  @override
  String get responseCurveLabel => '响应曲线';

  @override
  String get responseCurveDesc => '调整压力与笔触粗细之间的过渡速度。';

  @override
  String get brushSizeSliderRangeLabel => '笔刷大小滑块区间';

  @override
  String get brushSizeSliderRangeDesc => '影响工具面板内的笔刷大小滑块，有助于在不同精度间快速切换。';

  @override
  String get penSliderRangeCompact => '1 - 60 px（粗调）';

  @override
  String get penSliderRangeMedium => '0.1 - 500 px（中档）';

  @override
  String get penSliderRangeFull => '0.01 - 1000 px（全范围）';

  @override
  String get historyLimitLabel => '撤销/恢复步数上限';

  @override
  String historyLimitCurrent(Object count) {
    return '当前上限：$count 步';
  }

  @override
  String historyLimitDesc(Object min, Object max) {
    return '调整撤销/恢复历史的保存数量，范围 $min-$max。';
  }

  @override
  String get canvasBackendLabel => '画布后端';

  @override
  String get canvasBackendGpu => 'Rust WGPU';

  @override
  String get canvasBackendCpu => 'Rust CPU';

  @override
  String get canvasBackendRestartHint => '切换画布后端需要重启后生效。';

  @override
  String get developerOptionsLabel => '开发者选项';

  @override
  String get performanceOverlayLabel => '性能监控面板';

  @override
  String get performanceOverlayDesc =>
      '打开后会在屏幕角落显示 Flutter Performance Pulse 仪表盘，实时展示 FPS、CPU、内存与磁盘等数据。';

  @override
  String get tabletInputTestTitle => '数位板输入测试';

  @override
  String get recentProjectsTitle => '最近打开';

  @override
  String recentProjectsLoadFailed(Object error) {
    return '加载最近项目失败：$error';
  }

  @override
  String get recentProjectsEmpty => '暂无最近打开的项目';

  @override
  String get openFileLocation => '打开文件所在路径';

  @override
  String lastOpened(Object date) {
    return '最后打开：$date';
  }

  @override
  String canvasSize(Object width, Object height) {
    return '画布尺寸：$width x $height';
  }

  @override
  String get menuFile => '文件';

  @override
  String get menuEdit => '编辑';

  @override
  String get menuImage => '图像';

  @override
  String get menuLayer => '图层';

  @override
  String get menuSelection => '选择';

  @override
  String get menuFilter => '滤镜';

  @override
  String get menuTool => '工具';

  @override
  String get menuView => '视图';

  @override
  String get menuWorkspace => '工作区';

  @override
  String get menuWindow => '窗口';

  @override
  String get menuRoot => '菜单';

  @override
  String get menuAbout => '关于 Misa Rin';

  @override
  String get menuPreferences => '偏好设置…';

  @override
  String get menuNewEllipsis => '新建…';

  @override
  String get menuOpenEllipsis => '打开…';

  @override
  String get menuImportImageEllipsis => '导入图像…';

  @override
  String get menuImportImageFromClipboard => '从剪贴板导入图像';

  @override
  String get menuSave => '保存';

  @override
  String get menuSaveAsEllipsis => '另存为…';

  @override
  String get menuExportEllipsis => '导出…';

  @override
  String get menuCloseAll => '关闭全部';

  @override
  String get menuUndo => '撤销';

  @override
  String get menuRedo => '恢复';

  @override
  String get menuCut => '剪切';

  @override
  String get menuCopy => '复制';

  @override
  String get menuPaste => '粘贴';

  @override
  String get menuImageTransform => '图像变换';

  @override
  String get menuRotate90CW => '顺时针 90 度';

  @override
  String get menuRotate90CCW => '逆时针 90 度';

  @override
  String get menuRotate180CW => '顺时针 180 度';

  @override
  String get menuRotate180CCW => '逆时针 180 度';

  @override
  String get menuFlipHorizontal => '水平翻转';

  @override
  String get menuFlipVertical => '垂直翻转';

  @override
  String get menuImageSizeEllipsis => '图像大小…';

  @override
  String get menuCanvasSizeEllipsis => '画布大小…';

  @override
  String get menuNewSubmenu => '新建';

  @override
  String get menuNewLayerEllipsis => '图层…';

  @override
  String get menuMergeDown => '向下合并';

  @override
  String get menuRasterize => '栅格化';

  @override
  String get menuTransform => '变换';

  @override
  String get menuSelectAll => '全选';

  @override
  String get menuDeselect => '取消选择';

  @override
  String get menuInvertSelection => '反选';

  @override
  String get menuPalette => '调色盘';

  @override
  String get menuGeneratePaletteFromCanvasEllipsis => '取色当前画布生成调色盘…';

  @override
  String get menuGenerateGradientPalette => '使用当前颜色生成渐变调色盘';

  @override
  String get menuImportPaletteEllipsis => '导入调色盘…';

  @override
  String get menuReferenceImage => '参考图像';

  @override
  String get menuCreateReferenceImage => '创建参考图像';

  @override
  String get menuImportReferenceImageEllipsis => '导入参考图像…';

  @override
  String get menuReferenceModel => '参考模型';

  @override
  String get menuReferenceModelSteve => 'Steve模型';

  @override
  String get menuReferenceModelAlex => 'Alex模型';

  @override
  String get menuReferenceModelCube => '方块模型';

  @override
  String get menuImportReferenceModelEllipsis => '导入模型…';

  @override
  String get referenceModelRefreshTexture => '刷新贴图';

  @override
  String get referenceModelRefreshTextureDesc => '从当前画布生成模型贴图';

  @override
  String get referenceModelResetView => '重置视角';

  @override
  String get referenceModelResetViewDesc => '恢复默认旋转与缩放';

  @override
  String get referenceModelSixView => '六视图';

  @override
  String get referenceModelSixViewDesc => '在视口内以 2×3 显示正/背/顶/底/左/右视图';

  @override
  String get referenceModelSingleView => '单视图';

  @override
  String get referenceModelSingleViewDesc => '返回可拖拽旋转的单视图';

  @override
  String get referenceModelViewFront => '正视图';

  @override
  String get referenceModelViewBack => '背视图';

  @override
  String get referenceModelViewTop => '顶视图';

  @override
  String get referenceModelViewBottom => '底视图';

  @override
  String get referenceModelViewLeft => '左视图';

  @override
  String get referenceModelViewRight => '右视图';

  @override
  String get menuZoomIn => '放大';

  @override
  String get menuZoomOut => '缩小';

  @override
  String get menuShowGrid => '显示网格';

  @override
  String get menuHideGrid => '隐藏网格';

  @override
  String get menuBlackWhite => '黑白';

  @override
  String get menuDisableBlackWhite => '取消黑白';

  @override
  String get menuMirrorPreview => '镜像预览';

  @override
  String get menuDisableMirror => '取消镜像';

  @override
  String get menuTiledPreview => '平铺预览';

  @override
  String get menuDisableTiledPreview => '关闭平铺预览';

  @override
  String get menuShowPerspectiveGuide => '显示透视线';

  @override
  String get menuHidePerspectiveGuide => '隐藏透视线';

  @override
  String get menuPerspectiveMode => '透视模式';

  @override
  String get menuPerspective1Point => '1 点透视';

  @override
  String get menuPerspective2Point => '2 点透视';

  @override
  String get menuPerspective3Point => '3 点透视';

  @override
  String get menuWorkspaceDefault => '默认';

  @override
  String get menuWorkspaceSai2 => 'SAI2';

  @override
  String get menuSwitchWorkspace => '切换工作区';

  @override
  String get menuResetWorkspace => '复位工作区';

  @override
  String get menuEdgeSofteningEllipsis => '边缘柔化…';

  @override
  String get menuNarrowLinesEllipsis => '线条收窄…';

  @override
  String get menuExpandFillEllipsis => '填色拉伸…';

  @override
  String get menuGaussianBlurEllipsis => '高斯模糊…';

  @override
  String get menuRemoveColorLeakEllipsis => '去除漏色…';

  @override
  String get menuHueSaturationEllipsis => '色相/饱和度…';

  @override
  String get menuBrightnessContrastEllipsis => '亮度/对比度…';

  @override
  String get menuColorRangeEllipsis => '色彩范围…';

  @override
  String get menuBlackWhiteEllipsis => '黑白…';

  @override
  String get menuBinarizeEllipsis => '二值化…';

  @override
  String get menuScanPaperDrawingEllipsis => '扫描纸绘…';

  @override
  String get menuScanPaperDrawing => '扫描纸绘';

  @override
  String get menuInvertColors => '颜色反转';

  @override
  String get canvasSizeTitle => '画布大小';

  @override
  String get canvasSizeAnchorLabel => '定位方式';

  @override
  String get canvasSizeAnchorDesc => '根据定位点裁剪或扩展画布尺寸。';

  @override
  String get confirm => '确定';

  @override
  String get projectManagerTitle => '项目管理';

  @override
  String get selectAll => '全选';

  @override
  String get openFolder => '打开文件夹';

  @override
  String deleteSelected(Object count) {
    return '删除所选 ($count)';
  }

  @override
  String get imageSizeTitle => '图像大小';

  @override
  String get lockAspectRatio => '锁定纵横比';

  @override
  String get realtimeParams => '实时参数';

  @override
  String get clearScribble => '清空涂鸦';

  @override
  String get newCanvasSettingsTitle => '新建画布设置';

  @override
  String get custom => '自定义';

  @override
  String get colorWhite => '白色';

  @override
  String get colorLightGray => '浅灰';

  @override
  String get colorBlack => '黑色';

  @override
  String get colorTransparent => '透明';

  @override
  String get create => '创建';

  @override
  String currentPreset(Object name) {
    return '当前预设：$name';
  }

  @override
  String get exportSettingsTitle => '导出设置';

  @override
  String get exportTypeLabel => '导出类型';

  @override
  String get exportTypeBitmap => '位图';

  @override
  String get exportTypePng => '位图 PNG';

  @override
  String get exportTypeSvg => '矢量 SVG（实验）';

  @override
  String get exportBitmapFormatLabel => '位图格式';

  @override
  String get exportBitmapFormatPng => 'PNG';

  @override
  String get exportBitmapFormatWebp => 'WebP';

  @override
  String get webpCompressionLabel => 'WebP 压缩';

  @override
  String get webpLossless => '无损';

  @override
  String get webpLossy => '有损';

  @override
  String webpQualityLabel(Object value) {
    return '质量：$value';
  }

  @override
  String get exportScaleLabel => '导出倍率';

  @override
  String get reset => '重置';

  @override
  String exportOutputSize(Object width, Object height) {
    return '输出尺寸：$width x $height 像素';
  }

  @override
  String get exportAntialiasingLabel => '边缘柔化';

  @override
  String get enableAntialiasing => '启用边缘柔化';

  @override
  String get vectorParamsLabel => '矢量化参数';

  @override
  String vectorMaxColors(Object count) {
    return '最大颜色数量：$count';
  }

  @override
  String vectorSimplify(Object value) {
    return '路径简化强度：$value';
  }

  @override
  String get export => '导出';

  @override
  String get invalidDimensions => '请输入有效的宽高（像素）。';

  @override
  String get widthPx => '宽度（像素）';

  @override
  String get heightPx => '高度（像素）';

  @override
  String get noAutosavedProjects => '暂无自动保存的项目';

  @override
  String get revealProjectLocation => '打开所选项目所在文件夹';

  @override
  String get deleteSelectedProjects => '删除所选项目';

  @override
  String loadFailed(Object error) {
    return '加载失败：$error';
  }

  @override
  String deleteFailed(Object error) {
    return '删除失败：$error';
  }

  @override
  String projectFileInfo(Object size, Object date) {
    return '大小：$size · 更新：$date';
  }

  @override
  String projectCanvasInfo(Object width, Object height) {
    return '画布 $width x $height';
  }

  @override
  String get samplingMethod => '采样方式';

  @override
  String currentSize(Object width, Object height) {
    return '当前尺寸：$width x $height 像素';
  }

  @override
  String get samplingNearestLabel => '最邻近';

  @override
  String get samplingNearestDesc => '保持像素边缘硬度，适合像素风或图案缩放。';

  @override
  String get samplingBilinearLabel => '双线性';

  @override
  String get samplingBilinearDesc => '对像素进行平滑插值，适合需要柔和过渡的缩放。';

  @override
  String get tabletPressureLatest => '最近压力';

  @override
  String get tabletPressureMin => '最小压力';

  @override
  String get tabletPressureMax => '最大压力';

  @override
  String get tabletRadiusPx => '估算半径 (px)';

  @override
  String get tabletTiltRad => '倾角 (弧度)';

  @override
  String get tabletSampleCount => '采样计数';

  @override
  String get tabletSampleRateHz => '采样频率 (Hz)';

  @override
  String get tabletPointerType => '指针类型';

  @override
  String get pointerKindMouse => '鼠标';

  @override
  String get pointerKindTouch => '触摸';

  @override
  String get pointerKindStylus => '笔';

  @override
  String get pointerKindInvertedStylus => '笔（橡皮擦）';

  @override
  String get pointerKindTrackpad => '触控板';

  @override
  String get pointerKindUnknown => '未知';

  @override
  String get presetMobilePortrait => '移动端纵向 (1080 x 1920)';

  @override
  String get presetSquare => '方形 (1024 x 1024)';

  @override
  String presetPixelArt(Object width, Object height) {
    return '像素画 ($width x $height)';
  }

  @override
  String get untitledProject => '未命名项目';

  @override
  String get invalidResolution => '请输入有效的分辨率';

  @override
  String minResolutionError(Object value) {
    return '分辨率不能小于 $value 像素';
  }

  @override
  String maxResolutionError(Object value) {
    return '分辨率不能超过 $value 像素';
  }

  @override
  String get projectName => '项目名称';

  @override
  String get workspacePreset => '工作预设';

  @override
  String get workspacePresetDesc => '创建画布时自动应用常用工具参数。';

  @override
  String get workspaceIllustration => '插画';

  @override
  String get workspaceIllustrationDesc => '画笔：铅笔，边缘柔化：1';

  @override
  String get workspaceIllustrationDesc2 => '流线：保持';

  @override
  String get workspaceCelShading => '赛璐璐';

  @override
  String get workspaceCelShadingDesc1 => '画笔：赛璐璐画笔，边缘柔化：0';

  @override
  String get workspaceCelShadingDesc2 => '油漆桶吞并色线：开启';

  @override
  String get workspaceCelShadingDesc3 => '油漆桶边缘柔化：关闭';

  @override
  String get workspacePixel => '像素';

  @override
  String get workspacePixelDesc1 => '画笔：像素笔，笔刷/油漆桶边缘柔化：0';

  @override
  String get workspacePixelDesc2 => '显示网格：开启';

  @override
  String get workspacePixelDesc3 => '矢量作画：保持';

  @override
  String get workspacePixelDesc4 => '手抖修正：0';

  @override
  String get workspaceDefault => '默认';

  @override
  String get workspaceDefaultDesc => '不更改当前工具参数';

  @override
  String get resolutionPreset => '分辨率预设';

  @override
  String get customResolution => '自定义分辨率';

  @override
  String get swapDimensions => '交换宽高';

  @override
  String finalSizePreview(Object width, Object height, Object ratio) {
    return '最终尺寸：$width x $height 像素（比例 $ratio）';
  }

  @override
  String get enterValidDimensions => '请输入有效的宽高数值';

  @override
  String get backgroundColor => '背景颜色';

  @override
  String get exportBitmapDesc => '适合需要栅格格式的常规导出，可设置倍率与边缘柔化。';

  @override
  String get exportVectorDesc => '自动将当前画面转录为矢量路径，便于继续在矢量工具中编辑。';

  @override
  String get exampleScale => '如：1.0';

  @override
  String get enterPositiveValue => '请输入大于 0 的数值';

  @override
  String get antialiasingBeforeExport => '边缘柔化';

  @override
  String get brushAntialiasing => '笔刷抗锯齿';

  @override
  String get bucketAntialiasing => '填充抗锯齿';

  @override
  String get antialiasingDesc => '在平滑边缘的同时保留线条密度，致敬日本动画软件 Retas 的质感。';

  @override
  String levelLabel(Object level) {
    return '等级 $level';
  }

  @override
  String vectorExportSize(Object width, Object height) {
    return '导出尺寸：$width x $height（使用画布尺寸）';
  }

  @override
  String colorCount(Object count) {
    return '$count 色';
  }

  @override
  String get vectorSimplifyDesc => '颜色越少、简化值越高，导出的 SVG 越精简；过小会导致节点过多。';

  @override
  String get antialiasNone => '0 级（关闭）：保留像素硬边，不进行边缘柔化。';

  @override
  String get antialiasLow => '1 级（轻度）：轻微柔化锯齿，平滑边缘的同时尽量保持线条密度。';

  @override
  String get antialiasMedium => '2 级（标准）：平衡锐度与柔化，呈现类似 Retas 的干净线条感。';

  @override
  String get antialiasHigh => '3 级（强力）：最强柔化效果，用于需要柔和过渡或大幅放大的边缘。';

  @override
  String get tolerance => '容差';

  @override
  String get fillGap => '填充间隔';

  @override
  String get sampleAllLayers => '跨图层';

  @override
  String get contiguous => '连续';

  @override
  String get swallowColorLine => '吞并色线';

  @override
  String get swallowBlueColorLine => '吞并蓝色线';

  @override
  String get swallowGreenColorLine => '吞并绿色线';

  @override
  String get swallowRedColorLine => '吞并红色线';

  @override
  String get swallowAllColorLine => '吞并所有色线';

  @override
  String get cropOutsideCanvas => '裁剪出界画面';

  @override
  String get noAdjustableSettings => '该工具暂无可调节参数';

  @override
  String get hollowStroke => '空心描边';

  @override
  String get hollowStrokeRatio => '空心比例';

  @override
  String get eraseOccludedParts => '擦除被遮挡部分';

  @override
  String get solidFill => '实心';

  @override
  String get autoSharpTaper => '自动尖锐出入峰';

  @override
  String get stylusPressure => '数位笔笔压';

  @override
  String get touchDrawing => '触摸绘制';

  @override
  String get simulatedPressure => '模拟笔压';

  @override
  String get switchToEraser => '转换为擦除';

  @override
  String get vectorDrawing => '矢量作画';

  @override
  String get smoothCurve => '平滑曲线';

  @override
  String get sprayEffect => '喷枪效果';

  @override
  String get brushPreset => '笔刷预设';

  @override
  String get brushPresetDesc => '选择笔刷预设以控制间距、流量与形状。';

  @override
  String get editBrushPreset => '编辑预设';

  @override
  String get editBrushPresetDesc => '调整当前预设的内部参数。';

  @override
  String get brushPresetDialogTitle => '编辑笔刷预设';

  @override
  String get brushPresetNameLabel => '预设名称';

  @override
  String get brushPresetPencil => '铅笔';

  @override
  String get brushPresetCel => '赛璐璐画笔';

  @override
  String get brushPresetPen => '钢笔';

  @override
  String get brushPresetScreentone => '网点笔';

  @override
  String get brushPresetPixel => '像素笔';

  @override
  String get brushPresetDryInk => '枯墨';

  @override
  String get brushPresetCharcoal => '炭笔';

  @override
  String get brushPresetStarBrush => '星星笔';

  @override
  String get brushSpacing => '间距';

  @override
  String get brushHardness => '硬度';

  @override
  String get brushFlow => '流量';

  @override
  String get brushScatter => '散布';

  @override
  String get brushRotationJitter => '旋转抖动';

  @override
  String get brushSnapToPixel => '像素对齐';

  @override
  String get screentoneEnabled => '网点';

  @override
  String get screentoneShape => '网点形状';

  @override
  String get screentoneSpacing => '网点间距';

  @override
  String get screentoneDotSize => '网点大小';

  @override
  String get screentoneRotation => '网点旋转';

  @override
  String get screentoneSoftness => '网点柔化';

  @override
  String get brushShape => '笔刷形状';

  @override
  String get brushAuthorLabel => '作者';

  @override
  String get brushVersionLabel => '版本';

  @override
  String get importBrush => '导入笔刷';

  @override
  String get exportBrush => '导出笔刷';

  @override
  String get exportBrushTitle => '导出笔刷';

  @override
  String get unsavedBrushChangesPrompt => '笔刷参数已修改，是否保存？';

  @override
  String get discardChanges => '放弃修改';

  @override
  String get brushShapeFolderLabel => '笔刷形状文件夹';

  @override
  String get openBrushShapesFolder => '打开笔刷形状文件夹';

  @override
  String get randomRotation => '随机旋转';

  @override
  String get smoothRotation => '平滑旋转';

  @override
  String get selectionShape => '选区形状';

  @override
  String get selectionAdditive => '允许交集';

  @override
  String get selectionAdditiveDesc => '开启后无需按 Shift 也可多次框选并合并选区。';

  @override
  String get fontSize => '字号';

  @override
  String get lineHeight => '行距';

  @override
  String get letterSpacing => '文字间距';

  @override
  String get textStroke => '文字描边';

  @override
  String get strokeWidth => '描边宽度';

  @override
  String get strokeColor => '描边颜色';

  @override
  String get pickColor => '选择颜色';

  @override
  String get alignment => '对齐方式';

  @override
  String get alignCenter => '居中';

  @override
  String get alignRight => '右对齐';

  @override
  String get alignLeft => '左对齐';

  @override
  String get orientation => '排列方向';

  @override
  String get horizontal => '横排';

  @override
  String get vertical => '竖排';

  @override
  String get textToolHint => '文字填充颜色使用左下角取色器，描边颜色使用当前辅助色。';

  @override
  String get shapeType => '图形类型';

  @override
  String get brushSize => '笔刷大小';

  @override
  String get spraySize => '喷枪大小';

  @override
  String get brushFineTune => '笔刷微调';

  @override
  String get increase => '增大';

  @override
  String get decrease => '减小';

  @override
  String get stabilizer => '手抖修正';

  @override
  String get streamline => '流线';

  @override
  String get off => '关';

  @override
  String get taperEnds => '两端粗中间细';

  @override
  String get taperCenter => '两端细中间粗';

  @override
  String get auto => '自动';

  @override
  String get softSpray => '柔和喷枪';

  @override
  String get splatter => '喷溅';

  @override
  String get rectSelection => '矩形选区';

  @override
  String get ellipseSelection => '圆形选区';

  @override
  String get polygonLasso => '多边形套索';

  @override
  String get rectangle => '矩形';

  @override
  String get ellipse => '椭圆';

  @override
  String get triangle => '三角形';

  @override
  String get line => '直线';

  @override
  String get circle => '圆形';

  @override
  String get square => '正方形';

  @override
  String get star => '五角星';

  @override
  String get brushSizeDesc => '设置当前笔刷的像素直径，数值越大线条越粗，越小越适合描画细节。';

  @override
  String get spraySizeDesc => '决定喷枪喷洒区域的半径，半径大时覆盖面更广但颗粒更分散。';

  @override
  String get toleranceDesc => '控制油漆桶或魔棒判断\"颜色足够相似\"的阈值，容差高会一次抓取更多相近颜色。';

  @override
  String get fillGapDesc =>
      '在油漆桶填充时尝试闭合线条的细小缺口，防止漏色；数值越大越能闭合更大的缺口，但可能吃掉较细的狭窄区域。';

  @override
  String get antialiasingSliderDesc =>
      '为笔刷或填色的边缘增加多重采样平滑，在平滑边缘的同时保留线条密度，0 级保持像素风格。';

  @override
  String get stabilizerDesc => '实时平滑指针轨迹来抵消手抖，等级越高线条越稳但响应会稍慢。';

  @override
  String get streamlineDesc =>
      '类似 Procreate 的 StreamLine：抬笔后对笔画路径做平滑重算，并以补间动画回弹到更顺的结果（等级越高越明显）。';

  @override
  String get fontSizeDesc => '调整文字的像素高度，用于整体放大或缩小当前文本。';

  @override
  String get lineHeightDesc => '控制多行文字之间的垂直距离，便于营造疏朗或紧凑的段落。';

  @override
  String get letterSpacingDesc => '改变字符之间的水平间隔，可实现紧凑压缩或加宽排版。';

  @override
  String get strokeWidthDesc => '设置文字描边的粗细，用来强调字形或营造漫画嵌字效果。';

  @override
  String get hollowStrokeDesc => '将笔画中心挖空，形成空心描边效果。';

  @override
  String get hollowStrokeRatioDesc => '调整空心内圈大小，数值越高描边越细。';

  @override
  String get eraseOccludedPartsDesc => '开启后，同一图层里后画的空心线条会吃掉与其他线条的重合部分。';

  @override
  String get solidFillDesc => '决定形状工具是绘制填充色块还是空心轮廓，开启后直接生成实心图形。';

  @override
  String get randomRotationDesc => '开启后，方形/三角形/五角星笔刷会在笔触的每个印章上随机旋转。';

  @override
  String get autoSharpTaperDesc => '为笔刷起笔与收笔自动收尖，营造赛璐璐式的利落线条。';

  @override
  String get stylusPressureDesc => '让数位笔的压力实时影响笔刷粗细或透明度，关闭后忽略硬件笔压。';

  @override
  String get touchDrawingDesc => '关闭后手指触摸无法绘制，数位笔仍可绘制。';

  @override
  String get simulatedPressureDesc => '在没有压感设备时根据鼠标速度模拟笔压变化，开启后也能画出有粗细变化的线条。';

  @override
  String get switchToEraserDesc => '把当前笔刷/喷枪切换为带同样纹理的橡皮擦，方便精确擦除。';

  @override
  String get vectorDrawingDesc => '以矢量曲线实时预览笔触，获得 120Hz 丝滑反馈并可无损缩放，关闭则直接落笔成像素。';

  @override
  String get smoothCurveDesc => '矢量作画开启时进一步平滑曲线节点，减少拐角但会牺牲一点跟手性。';

  @override
  String get sampleAllLayersDesc => '油漆桶采样所有可见图层的颜色，适合参考线稿填色；关闭只检测当前图层。';

  @override
  String get contiguousDesc => '仅在相邻像素间扩散，防止填充穿过未闭合的边界；关闭后会匹配整幅画布。';

  @override
  String get swallowColorLineDesc =>
      '色块填充时自动吞并指定色线，消除描线与色块之间的白边，是 Retas 色线流程专用。';

  @override
  String get swallowBlueColorLineDesc => '色块填充时只吞并蓝色线。';

  @override
  String get swallowGreenColorLineDesc => '色块填充时只吞并绿色线。';

  @override
  String get swallowRedColorLineDesc => '色块填充时只吞并红色线。';

  @override
  String get swallowAllColorLineDesc => '色块填充时吞并红/绿/蓝色线。';

  @override
  String get cropOutsideCanvasDesc => '调整图层时把超过画布的像素裁掉，保持文档边缘干净；关闭可保留全部像素。';

  @override
  String get textAntialiasingDesc => '为文字绘制过程启用边缘柔化，平滑字形的同时保留线条密度；关闭可保留像素感。';

  @override
  String get textStrokeDesc => '为文字轮廓开启描边通道，配合描边宽度与颜色突出文字。';

  @override
  String get sprayEffectDesc =>
      '切换喷枪的散布模型：\"柔和喷枪\"呈现雾状渐变，\"喷溅\"会喷出颗粒噪点，依据素材质感选择。';

  @override
  String get rectSelectDesc => '使用矩形框快速圈选规则区域。';

  @override
  String get ellipseSelectDesc => '创建圆形或椭圆选区，适合柔和的局部限制。';

  @override
  String get polyLassoDesc => '逐点连线绘制任意多边形选区，适合复杂形状。';

  @override
  String get rectShapeDesc => '形状工具绘制水平矩形或正方形框/填充。';

  @override
  String get ellipseShapeDesc => '绘制椭圆或圆形轮廓与填充。';

  @override
  String get triangleShapeDesc => '绘制三角形几何或使用带尖角的三角形笔尖，获得锋利的轮廓。';

  @override
  String get lineShapeDesc => '从起点到终点绘制直线段，适合构造硬质结构。';

  @override
  String get circleTipDesc => '笔尖保持圆形，适合顺滑、柔和的笔触。';

  @override
  String get squareTipDesc => '使用方形笔尖绘制硬边像素风笔触。';

  @override
  String get starTipDesc => '使用五角星笔尖绘制装饰性笔触。';

  @override
  String get apply => '应用';

  @override
  String get next => '下一步';

  @override
  String get disableVectorDrawing => '关闭矢量绘制';

  @override
  String get disableVectorDrawingConfirm => '确定要关闭矢量绘制吗？';

  @override
  String get disableVectorDrawingDesc => '关闭后落笔性能会下降。';

  @override
  String get dontShowAgain => '不再显示';

  @override
  String get newLayer => '新增图层';

  @override
  String get mergeDown => '向下合并';

  @override
  String get delete => '删除';

  @override
  String get duplicate => '复制';

  @override
  String get rasterizeTextLayer => '栅格化文字图层';

  @override
  String get opacity => '不透明度';

  @override
  String get blendMode => '混合模式';

  @override
  String get clearFill => '清除填充';

  @override
  String get colorLine => '色线';

  @override
  String get currentColor => '当前颜色';

  @override
  String get rgb => 'RGB';

  @override
  String get hsv => 'HSV';

  @override
  String get preparingLayer => '正在准备图层…';

  @override
  String get generatePaletteTitle => '取色当前画布生成调色盘';

  @override
  String get generatePaletteDesc => '请选择需要生成的颜色数量，可以直接输入自定义数值。';

  @override
  String get customCount => '自定义数量';

  @override
  String get selectExportFormat => '选择导出格式';

  @override
  String get selectPaletteFormatDesc => '请选择要导出的调色盘格式。';

  @override
  String get noColorsDetected => '没有检测到颜色。';

  @override
  String get alphaThreshold => '透明度阈值';

  @override
  String get blurRadius => '模糊半径';

  @override
  String get repairRange => '修复范围';

  @override
  String get selectAntialiasLevel => '选择边缘柔化级别';

  @override
  String get colorCountLabel => '色彩数量';

  @override
  String get completeTransformFirst => '请先完成当前自由变换。';

  @override
  String get enablePerspectiveGuideFirst => '请先开启透视辅助线后再使用透视画笔。';

  @override
  String get lineNotAlignedWithPerspective => '当前线条未对齐透视方向，请调整角度后再落笔。';

  @override
  String get layerBackground => '背景';

  @override
  String layerDefaultName(Object index) {
    return '图层 $index';
  }

  @override
  String get duplicateLayer => '复制图层';

  @override
  String layerCopyName(Object name) {
    return '$name 副本';
  }

  @override
  String get unlockLayer => '解锁图层';

  @override
  String get lockLayer => '锁定图层';

  @override
  String get releaseClippingMask => '取消剪贴蒙版';

  @override
  String get createClippingMask => '创建剪贴蒙版';

  @override
  String get hide => '隐藏';

  @override
  String get show => '显示';

  @override
  String get colorRangeTitle => '色彩范围';

  @override
  String get colorPickerTitle => '取色';

  @override
  String get layerManagerTitle => '图层管理';

  @override
  String get edgeSoftening => '边缘柔化';

  @override
  String get undo => '撤销';

  @override
  String get redo => '恢复';

  @override
  String undoShortcut(Object shortcut) {
    return '撤销 ($shortcut)';
  }

  @override
  String redoShortcut(Object shortcut) {
    return '恢复 ($shortcut)';
  }

  @override
  String opacityPercent(Object percent) {
    return '不透明度 $percent%';
  }

  @override
  String get clippingMask => '剪贴蒙版';

  @override
  String get deleteLayerTitle => '删除图层';

  @override
  String get deleteLayerDesc => '移除该图层，若误删可立即撤销恢复';

  @override
  String get mergeDownDesc => '将该图层与下方图层合并为一个，并保留像素结果';

  @override
  String get duplicateLayerDesc => '复制整层内容，新的副本会出现在原图层上方';

  @override
  String get more => '更多';

  @override
  String get lockLayerDesc => '锁定后不可绘制或移动，防止误操作';

  @override
  String get unlockLayerDesc => '解除保护后即可继续编辑此图层';

  @override
  String get clippingMaskDescOn => '恢复为普通图层，显示全部像素';

  @override
  String get clippingMaskDescOff => '仅显示落在下方图层不透明区域内的内容';

  @override
  String get red => '红';

  @override
  String get green => '绿';

  @override
  String get blue => '蓝';

  @override
  String get hue => '色相';

  @override
  String get saturation => '饱和度';

  @override
  String get value => '明度';

  @override
  String get hsvBoxSpectrum => 'HSV 方形光谱';

  @override
  String get hueRingSpectrum => '色相环光谱';

  @override
  String get rgbHsvSliders => 'RGB / HSV 滑块';

  @override
  String get boardPanelPicker => '画板取色器';

  @override
  String get adjustCurrentColor => '调整当前颜色';

  @override
  String get adjustStrokeColor => '调整描边颜色';

  @override
  String copiedHex(Object hex) {
    return '已复制 $hex';
  }

  @override
  String rotationLabel(Object degrees) {
    return '旋转：$degrees°';
  }

  @override
  String scaleLabel(Object x, Object y) {
    return '缩放：$x% x $y%';
  }

  @override
  String get failedToExportTransform => '无法导出自由变换结果';

  @override
  String get cannotLocateLayer => '无法定位当前图层。';

  @override
  String get layerLockedCannotTransform => '当前图层已锁定，无法变换。';

  @override
  String get cannotEnterTransformMode => '无法进入自由变换模式。';

  @override
  String get applyTransformFailed => '应用自由变换失败，请重试。';

  @override
  String get freeTransformTitle => '自由变换';

  @override
  String get colorIndicatorDetail => '点击打开颜色编辑器，可输入数值或复制 HEX 色值';

  @override
  String get gplDesc => '文本格式，兼容 GIMP、Krita、Clip Studio Paint 等软件。';

  @override
  String get aseDesc => '适用于 Aseprite、LibreSprite 等像素绘图软件。';

  @override
  String get asepriteDesc => '使用 .aseprite 后缀，方便直接在 Aseprite 中打开。';

  @override
  String get gradientPaletteFailed => '当前颜色无法生成渐变调色盘，请重试';

  @override
  String get gradientPaletteTitle => '渐变调色盘（当前颜色）';

  @override
  String paletteCountRange(Object min, Object max) {
    return '范围 $min - $max';
  }

  @override
  String allowedRange(Object min, Object max) {
    return '允许范围：$min - $max 色';
  }

  @override
  String get enterValidColorCount => '请输入有效的颜色数量。';

  @override
  String get paletteGenerationFailed => '暂时无法生成调色盘，请重试';

  @override
  String get noValidColorsFound => '未找到有效颜色，请确认画布中已有内容';

  @override
  String get paletteEmpty => '该调色盘没有可用的颜色。';

  @override
  String paletteMinColors(Object min) {
    return '调色盘至少需要 $min 种颜色。';
  }

  @override
  String get paletteDefaultName => '调色盘';

  @override
  String get paletteEmptyExport => '该调色盘没有可导出的颜色。';

  @override
  String get exportPaletteTitle => '导出调色盘';

  @override
  String get webDownloadDesc => '浏览器会将调色盘保存到默认的下载目录。';

  @override
  String get download => '下载';

  @override
  String paletteDownloaded(Object name) {
    return '调色盘已下载：$name';
  }

  @override
  String paletteExported(Object path) {
    return '调色盘已导出到 $path';
  }

  @override
  String paletteExportFailed(Object error) {
    return '导出调色盘失败：$error';
  }

  @override
  String get selectEditableLayerFirst => '请先选择一个可编辑的图层。';

  @override
  String get layerLockedNoFilter => '当前图层已锁定，无法应用滤镜。';

  @override
  String get textLayerNoFilter => '当前图层是文字图层，请先栅格化或切换其他图层。';

  @override
  String get hueSaturation => '色相/饱和度';

  @override
  String get brightnessContrast => '亮度/对比度';

  @override
  String get blackAndWhite => '黑白';

  @override
  String get binarize => '二值化';

  @override
  String get gaussianBlur => '高斯模糊';

  @override
  String get leakRemoval => '去除漏色';

  @override
  String get lineNarrow => '线条收窄';

  @override
  String get narrowRadius => '收窄半径';

  @override
  String get fillExpand => '填色拉伸';

  @override
  String get expandRadius => '拉伸半径';

  @override
  String get noTransparentPixelsFound => '未检测到可处理的半透明像素。';

  @override
  String get filterApplyFailed => '应用滤镜失败，请重试。';

  @override
  String get canvasNotReadyInvert => '画布尚未准备好，无法颜色反转。';

  @override
  String get layerLockedInvert => '当前图层已锁定，无法颜色反转。';

  @override
  String get layerEmptyInvert => '当前图层为空，无法颜色反转。';

  @override
  String get noPixelsToInvert => '当前图层没有可反转的像素。';

  @override
  String get layerEmptyScanPaperDrawing => '当前图层为空，无法扫描纸绘。';

  @override
  String get scanPaperDrawingNoChanges => '未检测到可转换的像素。';

  @override
  String get edgeSofteningFailed => '无法对当前图层应用边缘柔化，图层可能为空或已锁定。';

  @override
  String get layerLockedEdgeSoftening => '当前图层已锁定，无法应用边缘柔化。';

  @override
  String get canvasNotReadyColorRange => '画布尚未准备好，无法统计色彩范围。';

  @override
  String get layerLockedColorRange => '当前图层已锁定，无法设置色彩范围。';

  @override
  String get layerEmptyColorRange => '当前图层为空，无法设置色彩范围。';

  @override
  String get noColorsToProcess => '当前图层没有可处理的颜色。';

  @override
  String get targetColorsNotLess => '目标颜色数量不少于当前颜色数量，图层保持不变。';

  @override
  String get colorRangeApplyFailed => '应用色彩范围失败，请重试。';

  @override
  String get colorRangePreviewFailed => '生成色彩范围预览失败，请重试。';

  @override
  String get lightness => '明度';

  @override
  String get brightness => '亮度';

  @override
  String get contrast => '对比度';

  @override
  String get selectSaveFormat => '请选择要保存的文件格式。';

  @override
  String get saveAsPsd => '保存为 PSD';

  @override
  String get saveAsSai2 => '保存为 SAI2';

  @override
  String get saveAsRin => '保存为 RIN';

  @override
  String get dontSave => '不保存';

  @override
  String get save => '保存';

  @override
  String get renameProject => '重命名项目';

  @override
  String get enterNewProjectName => '请输入新的项目名称';

  @override
  String get rename => '重命名';

  @override
  String get canvasNotReady => '画布尚未准备好';

  @override
  String get toolPanel => '工具面板';

  @override
  String get toolbarTitle => '工具栏';

  @override
  String get toolOptionsTitle => '工具选项';

  @override
  String get defaultProjectDirectory => '默认项目目录';

  @override
  String get minimize => '最小化';

  @override
  String get maximizeRestore => '最大化/还原';

  @override
  String get fontFamily => '字体';

  @override
  String get fontSearchPlaceholder => '搜索字体...';

  @override
  String get noMatchingFonts => '没有匹配的字体。';

  @override
  String get fontPreviewText => '预览文本';

  @override
  String get fontPreviewLanguages => '测试语言';

  @override
  String get fontLanguageCategory => '语言分类';

  @override
  String get fontLanguageAll => '全部';

  @override
  String get fontFavorites => '收藏';

  @override
  String get noFavoriteFonts => '暂无收藏字体。';

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
  String get webSaveDesc => 'Download the project file to your device.';

  @override
  String psdExported(Object path) {
    return 'PSD exported to $path';
  }

  @override
  String sai2Exported(Object path) {
    return 'SAI2 已导出到 $path';
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
    return 'SAI2 已下载：$fileName';
  }

  @override
  String get exportAsPsdTooltip => 'Export as PSD';

  @override
  String get exportAsSai2Tooltip => '导出为 SAI2';

  @override
  String get canvasNotReadyExport => 'Canvas is not ready to export.';

  @override
  String exportFileTitle(Object extension) {
    return 'Export $extension File';
  }

  @override
  String get webExportDesc => 'Download the exported image to your device.';

  @override
  String fileDownloaded(Object extension, Object name) {
    return '$extension file downloaded: $name';
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
    return '平铺：$state';
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
  String get rendererLabel => '渲染器';

  @override
  String get rendererNormal => '普通';

  @override
  String get rendererNormalDesc => '实时渲染，速度最快，适合预览。';

  @override
  String get rendererCinematic => '宣传片';

  @override
  String get rendererCinematicDesc => '还原 Minecraft 官方宣传片风格，包含柔和阴影与高对比度光效。';

  @override
  String get rendererCycles => '写实';

  @override
  String get rendererCyclesDesc => '模拟路径追踪风格，极其逼真的光照效果。';

  @override
  String get autoSaveCleanupThresholdLabel => '自动保存清理阈值';

  @override
  String autoSaveCleanupThresholdValue(Object size) {
    return '当前阈值：$size';
  }

  @override
  String get autoSaveCleanupThresholdDesc => '自动保存文件夹总大小超过该值时，启动会提示清理。';

  @override
  String get autoSaveCleanupDialogTitle => '自动保存占用过大';

  @override
  String autoSaveCleanupDialogMessage(Object size, Object limit) {
    return '自动保存文件已占用 $size（阈值 $limit）。是否立即清理？';
  }

  @override
  String get autoSaveCleanupDialogClean => '清理';

  @override
  String get exportDestinationTitle => '导出位置';

  @override
  String get exportDestinationDesc => '请选择导出到相册或文件管理。';

  @override
  String get imageSourceTitle => '选择图片来源';

  @override
  String get imageSourceDesc => '请选择从相册或文件管理器导入图片。';

  @override
  String get exportDestinationPhotos => '相册';

  @override
  String get exportDestinationFiles => '文件管理';

  @override
  String get imageSavedToPhotos => '已保存到相册。';

  @override
  String get exportDirectoryLabel => '导出保存目录';

  @override
  String get exportDirectoryDesc => '在安卓上设置导出文件的默认保存位置。';

  @override
  String get selectExportDirectory => '选择导出目录';

  @override
  String get resetExportDirectory => '恢复默认';

  @override
  String exportDirectoryCurrent(Object path) {
    return '当前：$path';
  }

  @override
  String exportDirectoryDefault(Object path) {
    return '默认：$path';
  }

  @override
  String exportDirectoryUpdated(Object path) {
    return '导出目录已更新：$path';
  }

  @override
  String get exportDirectoryCleared => '已恢复默认导出目录';

  @override
  String exportDirectoryUpdateFailed(Object error) {
    return '设置导出目录失败：$error';
  }
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn() : super('zh_CN');

  @override
  String get webLoadingInitializingCanvas => '正在初始化画板…';

  @override
  String get webLoadingMayTakeTime => 'Web 端加载需要一些时间，请稍候。';

  @override
  String get closeAppTitle => '关闭应用';

  @override
  String unsavedProjectsWarning(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '检测到 $count 个未保存的项目。如果现在退出，最近的修改将会丢失。',
      one: '检测到 1 个未保存的项目。如果现在退出，最近的修改将会丢失。',
    );
    return '$_temp0';
  }

  @override
  String get cancel => '取消';

  @override
  String get discardAndExit => '丢弃并退出';

  @override
  String get homeTagline => '创作从这里开始';

  @override
  String get homeNewProject => '新建项目';

  @override
  String get homeNewProjectDesc => '从空白画布开启新的创意';

  @override
  String get homeOpenProject => '打开项目';

  @override
  String get homeOpenProjectDesc => '从磁盘加载 .rin / .psd / .sai2 或图片文件';

  @override
  String get homeRecentProjects => '最近打开';

  @override
  String get homeRecentProjectsDesc => '快速恢复自动保存的项目';

  @override
  String get homeProjectManager => '项目管理';

  @override
  String get homeProjectManagerDesc => '批量查看或清理自动保存的项目文件';

  @override
  String get homeSettings => '设置';

  @override
  String get homeSettingsDesc => '预览即将上线的个性化选项';

  @override
  String get homeAbout => '关于';

  @override
  String get homeAboutDesc => '了解项目 Misa Rin';

  @override
  String createProjectFailed(Object error) {
    return '创建项目失败：$error';
  }

  @override
  String get openProjectDialogTitle => '打开项目';

  @override
  String get openingProjectTitle => '正在打开项目…';

  @override
  String openingProjectMessage(Object fileName) {
    return '正在加载 $fileName';
  }

  @override
  String get cannotReadPsdContent => '无法读取 PSD 文件内容。';

  @override
  String get cannotReadSai2Content => '无法读取 SAI2 文件内容。';

  @override
  String get cannotReadProjectFileContent => '无法读取项目文件内容。';

  @override
  String openedProjectInfo(Object name) {
    return '已打开项目：$name';
  }

  @override
  String openProjectFailed(Object error) {
    return '打开项目失败：$error';
  }

  @override
  String get importImageDialogTitle => '导入图片';

  @override
  String importedImageInfo(Object name) {
    return '已导入图片：$name';
  }

  @override
  String importImageFailed(Object error) {
    return '导入图片失败：$error';
  }

  @override
  String get clipboardNoBitmapFound => '剪贴板中没有找到可以导入的位图。';

  @override
  String get clipboardImageDefaultName => '剪贴板图像';

  @override
  String get importedClipboardImageInfo => '已导入剪贴板图像';

  @override
  String importClipboardImageFailed(Object error) {
    return '导入剪贴板图像失败：$error';
  }

  @override
  String get webPreparingCanvasTitle => '正在准备画布…';

  @override
  String get webPreparingCanvasMessage => 'Web 端需要一些时间才能完成初始化，请稍候。';

  @override
  String get aboutTitle => '关于 Misa Rin';

  @override
  String get aboutDescription =>
      'Misa Rin 是一款专注于创意绘制与项目管理的应用，旨在为创作者提供流畅的绘图体验与可靠的项目存档能力。';

  @override
  String get aboutAppIdLabel => '应用标识';

  @override
  String get aboutAppVersionLabel => '应用版本';

  @override
  String get aboutDeveloperLabel => '开发者';

  @override
  String get close => '关闭';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsTabGeneral => '常规';

  @override
  String get settingsTabInput => '输入与笔刷';

  @override
  String get settingsTabStorage => '历史与存储';

  @override
  String get settingsTabAbout => '关于';

  @override
  String get tabletTest => '数位板测试';

  @override
  String get restoreDefaults => '恢复默认';

  @override
  String get ok => '好的';

  @override
  String get languageLabel => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEnglish => '英语';

  @override
  String get languageJapanese => '日语';

  @override
  String get languageKorean => '韩语';

  @override
  String get languageChineseSimplified => '中文（简体）';

  @override
  String get languageChineseTraditional => '中文（繁体）';

  @override
  String get themeModeLabel => '主题模式';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get stylusPressureSettingsLabel => '数位笔压设置';

  @override
  String get enableStylusPressure => '启用数位笔笔压';

  @override
  String get responseCurveLabel => '响应曲线';

  @override
  String get responseCurveDesc => '调整压力与笔触粗细之间的过渡速度。';

  @override
  String get brushSizeSliderRangeLabel => '笔刷大小滑块区间';

  @override
  String get brushSizeSliderRangeDesc => '影响工具面板内的笔刷大小滑块，有助于在不同精度间快速切换。';

  @override
  String get penSliderRangeCompact => '1 - 60 px（粗调）';

  @override
  String get penSliderRangeMedium => '0.1 - 500 px（中档）';

  @override
  String get penSliderRangeFull => '0.01 - 1000 px（全范围）';

  @override
  String get historyLimitLabel => '撤销/恢复步数上限';

  @override
  String historyLimitCurrent(Object count) {
    return '当前上限：$count 步';
  }

  @override
  String historyLimitDesc(Object min, Object max) {
    return '调整撤销/恢复历史的保存数量，范围 $min-$max。';
  }

  @override
  String get canvasBackendLabel => '画布后端';

  @override
  String get canvasBackendGpu => 'Rust WGPU';

  @override
  String get canvasBackendCpu => 'Rust CPU';

  @override
  String get canvasBackendRestartHint => '切换画布后端需要重启后生效。';

  @override
  String get developerOptionsLabel => '开发者选项';

  @override
  String get performanceOverlayLabel => '性能监控面板';

  @override
  String get performanceOverlayDesc =>
      '打开后会在屏幕角落显示 Flutter Performance Pulse 仪表盘，实时展示 FPS、CPU、内存与磁盘等数据。';

  @override
  String get tabletInputTestTitle => '数位板输入测试';

  @override
  String get recentProjectsTitle => '最近打开';

  @override
  String recentProjectsLoadFailed(Object error) {
    return '加载最近项目失败：$error';
  }

  @override
  String get recentProjectsEmpty => '暂无最近打开的项目';

  @override
  String get openFileLocation => '打开文件所在路径';

  @override
  String lastOpened(Object date) {
    return '最后打开：$date';
  }

  @override
  String canvasSize(Object width, Object height) {
    return '画布尺寸：$width x $height';
  }

  @override
  String get menuFile => '文件';

  @override
  String get menuEdit => '编辑';

  @override
  String get menuImage => '图像';

  @override
  String get menuLayer => '图层';

  @override
  String get menuSelection => '选择';

  @override
  String get menuFilter => '滤镜';

  @override
  String get menuTool => '工具';

  @override
  String get menuView => '视图';

  @override
  String get menuWorkspace => '工作区';

  @override
  String get menuWindow => '窗口';

  @override
  String get menuRoot => '菜单';

  @override
  String get menuAbout => '关于 Misa Rin';

  @override
  String get menuPreferences => '偏好设置…';

  @override
  String get menuNewEllipsis => '新建…';

  @override
  String get menuOpenEllipsis => '打开…';

  @override
  String get menuImportImageEllipsis => '导入图像…';

  @override
  String get menuImportImageFromClipboard => '从剪贴板导入图像';

  @override
  String get menuSave => '保存';

  @override
  String get menuSaveAsEllipsis => '另存为…';

  @override
  String get menuExportEllipsis => '导出…';

  @override
  String get menuCloseAll => '关闭全部';

  @override
  String get menuUndo => '撤销';

  @override
  String get menuRedo => '恢复';

  @override
  String get menuCut => '剪切';

  @override
  String get menuCopy => '复制';

  @override
  String get menuPaste => '粘贴';

  @override
  String get menuImageTransform => '图像变换';

  @override
  String get menuRotate90CW => '顺时针 90 度';

  @override
  String get menuRotate90CCW => '逆时针 90 度';

  @override
  String get menuRotate180CW => '顺时针 180 度';

  @override
  String get menuRotate180CCW => '逆时针 180 度';

  @override
  String get menuFlipHorizontal => '水平翻转';

  @override
  String get menuFlipVertical => '垂直翻转';

  @override
  String get menuImageSizeEllipsis => '图像大小…';

  @override
  String get menuCanvasSizeEllipsis => '画布大小…';

  @override
  String get menuNewSubmenu => '新建';

  @override
  String get menuNewLayerEllipsis => '图层…';

  @override
  String get menuMergeDown => '向下合并';

  @override
  String get menuRasterize => '栅格化';

  @override
  String get menuTransform => '变换';

  @override
  String get menuSelectAll => '全选';

  @override
  String get menuDeselect => '取消选择';

  @override
  String get menuInvertSelection => '反选';

  @override
  String get menuPalette => '调色盘';

  @override
  String get menuGeneratePaletteFromCanvasEllipsis => '取色当前画布生成调色盘…';

  @override
  String get menuGenerateGradientPalette => '使用当前颜色生成渐变调色盘';

  @override
  String get menuImportPaletteEllipsis => '导入调色盘…';

  @override
  String get menuReferenceImage => '参考图像';

  @override
  String get menuCreateReferenceImage => '创建参考图像';

  @override
  String get menuImportReferenceImageEllipsis => '导入参考图像…';

  @override
  String get menuReferenceModel => '参考模型';

  @override
  String get menuReferenceModelSteve => 'Steve模型';

  @override
  String get menuReferenceModelAlex => 'Alex模型';

  @override
  String get menuReferenceModelCube => '方块模型';

  @override
  String get menuImportReferenceModelEllipsis => '导入模型…';

  @override
  String get referenceModelRefreshTexture => '刷新贴图';

  @override
  String get referenceModelRefreshTextureDesc => '从当前画布生成模型贴图';

  @override
  String get referenceModelResetView => '重置视角';

  @override
  String get referenceModelResetViewDesc => '恢复默认旋转与缩放';

  @override
  String get referenceModelSixView => '六视图';

  @override
  String get referenceModelSixViewDesc => '在视口内以 2×3 显示正/背/顶/底/左/右视图';

  @override
  String get referenceModelSingleView => '单视图';

  @override
  String get referenceModelSingleViewDesc => '返回可拖拽旋转的单视图';

  @override
  String get referenceModelViewFront => '正视图';

  @override
  String get referenceModelViewBack => '背视图';

  @override
  String get referenceModelViewTop => '顶视图';

  @override
  String get referenceModelViewBottom => '底视图';

  @override
  String get referenceModelViewLeft => '左视图';

  @override
  String get referenceModelViewRight => '右视图';

  @override
  String get menuZoomIn => '放大';

  @override
  String get menuZoomOut => '缩小';

  @override
  String get menuShowGrid => '显示网格';

  @override
  String get menuHideGrid => '隐藏网格';

  @override
  String get menuBlackWhite => '黑白';

  @override
  String get menuDisableBlackWhite => '取消黑白';

  @override
  String get menuMirrorPreview => '镜像预览';

  @override
  String get menuDisableMirror => '取消镜像';

  @override
  String get menuTiledPreview => '平铺预览';

  @override
  String get menuDisableTiledPreview => '关闭平铺预览';

  @override
  String get menuShowPerspectiveGuide => '显示透视线';

  @override
  String get menuHidePerspectiveGuide => '隐藏透视线';

  @override
  String get menuPerspectiveMode => '透视模式';

  @override
  String get menuPerspective1Point => '1 点透视';

  @override
  String get menuPerspective2Point => '2 点透视';

  @override
  String get menuPerspective3Point => '3 点透视';

  @override
  String get menuWorkspaceDefault => '默认';

  @override
  String get menuWorkspaceSai2 => 'SAI2';

  @override
  String get menuSwitchWorkspace => '切换工作区';

  @override
  String get menuResetWorkspace => '复位工作区';

  @override
  String get menuEdgeSofteningEllipsis => '边缘柔化…';

  @override
  String get menuNarrowLinesEllipsis => '线条收窄…';

  @override
  String get menuExpandFillEllipsis => '填色拉伸…';

  @override
  String get menuGaussianBlurEllipsis => '高斯模糊…';

  @override
  String get menuRemoveColorLeakEllipsis => '去除漏色…';

  @override
  String get menuHueSaturationEllipsis => '色相/饱和度…';

  @override
  String get menuBrightnessContrastEllipsis => '亮度/对比度…';

  @override
  String get menuColorRangeEllipsis => '色彩范围…';

  @override
  String get menuBlackWhiteEllipsis => '黑白…';

  @override
  String get menuBinarizeEllipsis => '二值化…';

  @override
  String get menuInvertColors => '颜色反转';

  @override
  String get colorTransparent => '透明';

  @override
  String get exportTypeBitmap => '位图';

  @override
  String get exportBitmapFormatLabel => '位图格式';

  @override
  String get exportBitmapFormatPng => 'PNG';

  @override
  String get exportBitmapFormatWebp => 'WebP';

  @override
  String get webpCompressionLabel => 'WebP 压缩';

  @override
  String get webpLossless => '无损';

  @override
  String get webpLossy => '有损';

  @override
  String webpQualityLabel(Object value) {
    return '质量：$value';
  }

  @override
  String get swapDimensions => '交换宽高';

  @override
  String get brushAntialiasing => '笔刷抗锯齿';

  @override
  String get bucketAntialiasing => '填充抗锯齿';

  @override
  String get hollowStroke => '空心描边';

  @override
  String get hollowStrokeRatio => '空心比例';

  @override
  String get eraseOccludedParts => '擦除被遮挡部分';

  @override
  String get brushPreset => '笔刷预设';

  @override
  String get brushPresetDesc => '选择笔刷预设以控制间距、流量与形状。';

  @override
  String get editBrushPreset => '编辑预设';

  @override
  String get editBrushPresetDesc => '调整当前预设的内部参数。';

  @override
  String get brushPresetDialogTitle => '编辑笔刷预设';

  @override
  String get brushPresetNameLabel => '预设名称';

  @override
  String get brushPresetPencil => '铅笔';

  @override
  String get brushPresetCel => '赛璐璐画笔';

  @override
  String get brushPresetPen => '钢笔';

  @override
  String get brushPresetScreentone => '网点笔';

  @override
  String get brushPresetPixel => '像素笔';

  @override
  String get brushPresetDryInk => '枯墨';

  @override
  String get brushPresetCharcoal => '炭笔';

  @override
  String get brushPresetStarBrush => '星星笔';

  @override
  String get brushSpacing => '间距';

  @override
  String get brushHardness => '硬度';

  @override
  String get brushFlow => '流量';

  @override
  String get brushScatter => '散布';

  @override
  String get brushRotationJitter => '旋转抖动';

  @override
  String get brushSnapToPixel => '像素对齐';

  @override
  String get screentoneEnabled => '网点';

  @override
  String get screentoneShape => '网点形状';

  @override
  String get screentoneSpacing => '网点间距';

  @override
  String get screentoneDotSize => '网点大小';

  @override
  String get screentoneRotation => '网点旋转';

  @override
  String get screentoneSoftness => '网点柔化';

  @override
  String get brushAuthorLabel => '作者';

  @override
  String get brushVersionLabel => '版本';

  @override
  String get importBrush => '导入笔刷';

  @override
  String get exportBrush => '导出笔刷';

  @override
  String get exportBrushTitle => '导出笔刷';

  @override
  String get unsavedBrushChangesPrompt => '笔刷参数已修改，是否保存？';

  @override
  String get discardChanges => '放弃修改';

  @override
  String get brushShapeFolderLabel => '笔刷形状文件夹';

  @override
  String get openBrushShapesFolder => '打开笔刷形状文件夹';

  @override
  String get smoothRotation => '平滑旋转';

  @override
  String get selectionAdditive => '允许交集';

  @override
  String get selectionAdditiveDesc => '开启后无需按 Shift 也可多次框选并合并选区。';

  @override
  String get hollowStrokeDesc => '将笔画中心挖空，形成空心描边效果。';

  @override
  String get hollowStrokeRatioDesc => '调整空心内圈大小，数值越高描边越细。';

  @override
  String get eraseOccludedPartsDesc => '开启后，同一图层里后画的空心线条会吃掉与其他线条的重合部分。';

  @override
  String get saveAsSai2 => '保存为 SAI2';

  @override
  String get fontFamily => '字体系列';

  @override
  String get fontSearchPlaceholder => '搜索字体...';

  @override
  String get noMatchingFonts => '没有匹配的字体。';

  @override
  String get fontPreviewText => '预览文本';

  @override
  String get fontPreviewLanguages => '测试语言';

  @override
  String get fontLanguageCategory => '语言分类';

  @override
  String get fontLanguageAll => '全部';

  @override
  String get fontFavorites => '收藏';

  @override
  String get noFavoriteFonts => '暂无收藏字体。';

  @override
  String get importPaletteTitle => '导入调色板';

  @override
  String get cannotReadFile => '无法读取文件';

  @override
  String paletteImported(Object name) {
    return '已导入调色板：$name';
  }

  @override
  String paletteImportFailed(Object error) {
    return '导入调色板失败：$error';
  }

  @override
  String noChangesToSave(Object location) {
    return '没有更改需要保存到 $location';
  }

  @override
  String projectSaved(Object location) {
    return '项目已保存到 $location';
  }

  @override
  String projectSaveFailed(Object error) {
    return '保存项目失败：$error';
  }

  @override
  String get canvasNotReadySave => '画布未准备好，无法保存。';

  @override
  String get saveProjectAs => '项目另存为';

  @override
  String get webSaveDesc => '下载项目文件到您的设备。';

  @override
  String psdExported(Object path) {
    return 'PSD 已导出到 $path';
  }

  @override
  String sai2Exported(Object path) {
    return 'SAI2 已导出到 $path';
  }

  @override
  String projectDownloaded(Object fileName) {
    return '项目已下载：$fileName';
  }

  @override
  String psdDownloaded(Object fileName) {
    return 'PSD 已下载：$fileName';
  }

  @override
  String sai2Downloaded(Object fileName) {
    return 'SAI2 已下载：$fileName';
  }

  @override
  String get exportAsPsdTooltip => '导出为 PSD';

  @override
  String get exportAsSai2Tooltip => '导出为 SAI2';

  @override
  String get canvasNotReadyExport => '画布未准备好，无法导出。';

  @override
  String exportFileTitle(Object extension) {
    return '导出 $extension 文件';
  }

  @override
  String get webExportDesc => '下载导出的图像到您的设备。';

  @override
  String fileDownloaded(Object extension, Object name) {
    return '$extension 文件已下载：$name';
  }

  @override
  String fileExported(Object path) {
    return '文件已导出到 $path';
  }

  @override
  String exportFailed(Object error) {
    return '导出失败：$error';
  }

  @override
  String get canvasNotReadyTransform => '画布未准备好，无法变换。';

  @override
  String get canvasSizeErrorTransform => '变换过程中画布尺寸错误。';

  @override
  String get canvasNotReadyResizeImage => '画布未准备好，无法调整图像大小。';

  @override
  String get resizeImageFailed => '调整图像大小失败。';

  @override
  String get canvasNotReadyResizeCanvas => '画布未准备好，无法调整画布大小。';

  @override
  String get resizeCanvasFailed => '调整画布大小失败。';

  @override
  String get returnToHome => '返回首页';

  @override
  String get saveBeforeReturn => '返回首页前是否保存更改？';

  @override
  String get closeCanvas => '关闭画布';

  @override
  String get saveBeforeClose => '关闭前是否保存更改？';

  @override
  String get nameCannotBeEmpty => '名称不能为空。';

  @override
  String get noSupportedImageFormats => '未找到支持的图像格式。';

  @override
  String importFailed(Object item, Object error) {
    return '导入 $item 失败：$error';
  }

  @override
  String get createdCanvasFromDrop => '已从拖放项目创建画布。';

  @override
  String createdCanvasesFromDrop(Object count) {
    return '已从拖放项目创建 $count 个画布。';
  }

  @override
  String get dropImageCreateFailed => '无法从拖放图像创建画布。';

  @override
  String get canvasNotReadyDrop => '画布未准备好进行拖放操作。';

  @override
  String get insertedDropImage => '已插入拖放图像。';

  @override
  String insertedDropImages(Object count) {
    return '已插入 $count 张拖放图像。';
  }

  @override
  String get dropImageInsertFailed => '插入拖放图像失败。';

  @override
  String get image => '图像';

  @override
  String get on => '开';

  @override
  String get perspective1Point => '一点透视';

  @override
  String get perspective2Point => '两点透视';

  @override
  String get perspective3Point => '三点透视';

  @override
  String resolutionLabel(Object resolution) {
    return '分辨率：$resolution';
  }

  @override
  String zoomLabel(Object zoom) {
    return '缩放：$zoom';
  }

  @override
  String positionLabel(Object position) {
    return '位置：$position';
  }

  @override
  String gridLabel(Object grid) {
    return '网格：$grid';
  }

  @override
  String blackWhiteLabel(Object state) {
    return '黑白：$state';
  }

  @override
  String mirrorLabel(Object state) {
    return '镜像：$state';
  }

  @override
  String tileLabel(Object state) {
    return '平铺：$state';
  }

  @override
  String perspectiveLabel(Object perspective) {
    return '透视：$perspective';
  }

  @override
  String get fileNameCannotBeEmpty => '文件名不能为空。';

  @override
  String get blackPoint => '黑点';

  @override
  String get whitePoint => '白点';

  @override
  String get midTone => '中间调';

  @override
  String get rendererLabel => '渲染器';

  @override
  String get rendererNormal => '普通';

  @override
  String get rendererNormalDesc => '实时渲染，速度最快，适合预览。';

  @override
  String get rendererCinematic => '宣传片';

  @override
  String get rendererCinematicDesc => '还原 Minecraft 官方宣传片风格，包含柔和阴影与高对比度光效。';

  @override
  String get rendererCycles => '写实';

  @override
  String get rendererCyclesDesc => '模拟路径追踪风格，极其逼真的光照效果。';

  @override
  String get autoSaveCleanupThresholdLabel => '自动保存清理阈值';

  @override
  String autoSaveCleanupThresholdValue(Object size) {
    return '当前阈值：$size';
  }

  @override
  String get autoSaveCleanupThresholdDesc => '自动保存文件夹总大小超过该值时，启动会提示清理。';

  @override
  String get autoSaveCleanupDialogTitle => '自动保存占用过大';

  @override
  String autoSaveCleanupDialogMessage(Object size, Object limit) {
    return '自动保存文件已占用 $size（阈值 $limit）。是否立即清理？';
  }

  @override
  String get autoSaveCleanupDialogClean => '清理';

  @override
  String get exportDestinationTitle => '导出位置';

  @override
  String get exportDestinationDesc => '请选择导出到相册或文件管理。';

  @override
  String get imageSourceTitle => '选择图片来源';

  @override
  String get imageSourceDesc => '请选择从相册或文件管理器导入图片。';

  @override
  String get exportDestinationPhotos => '相册';

  @override
  String get exportDestinationFiles => '文件管理';

  @override
  String get imageSavedToPhotos => '已保存到相册。';

  @override
  String get exportDirectoryLabel => '导出保存目录';

  @override
  String get exportDirectoryDesc => '在安卓上设置导出文件的默认保存位置。';

  @override
  String get selectExportDirectory => '选择导出目录';

  @override
  String get resetExportDirectory => '恢复默认';

  @override
  String exportDirectoryCurrent(Object path) {
    return '当前：$path';
  }

  @override
  String exportDirectoryDefault(Object path) {
    return '默认：$path';
  }

  @override
  String exportDirectoryUpdated(Object path) {
    return '导出目录已更新：$path';
  }

  @override
  String get exportDirectoryCleared => '已恢复默认导出目录';

  @override
  String exportDirectoryUpdateFailed(Object error) {
    return '设置导出目录失败：$error';
  }
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get webLoadingInitializingCanvas => '正在初始化畫板…';

  @override
  String get webLoadingMayTakeTime => 'Web 端載入需要一些時間，請稍候。';

  @override
  String get closeAppTitle => '關閉應用';

  @override
  String unsavedProjectsWarning(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '偵測到 $count 個未儲存的專案。如果現在退出，最近的修改將會遺失。',
      one: '偵測到 1 個未儲存的專案。如果現在退出，最近的修改將會遺失。',
    );
    return '$_temp0';
  }

  @override
  String get cancel => '取消';

  @override
  String get discardAndExit => '捨棄並退出';

  @override
  String get homeTagline => '創作從這裡開始';

  @override
  String get homeNewProject => '新建專案';

  @override
  String get homeNewProjectDesc => '從空白畫布開啟新的創意';

  @override
  String get homeOpenProject => '開啟專案';

  @override
  String get homeOpenProjectDesc => '從磁碟載入 .rin / .psd / .sai2 或影像檔案';

  @override
  String get homeRecentProjects => '最近開啟';

  @override
  String get homeRecentProjectsDesc => '快速恢復自動儲存的專案';

  @override
  String get homeProjectManager => '專案管理';

  @override
  String get homeProjectManagerDesc => '批次檢視或清理自動儲存的專案檔案';

  @override
  String get homeSettings => '設定';

  @override
  String get homeSettingsDesc => '預覽即將上線的個人化選項';

  @override
  String get homeAbout => '關於';

  @override
  String get homeAboutDesc => '了解專案 Misa Rin';

  @override
  String createProjectFailed(Object error) {
    return '建立專案失敗：$error';
  }

  @override
  String get openProjectDialogTitle => '開啟專案';

  @override
  String get openingProjectTitle => '正在開啟專案…';

  @override
  String openingProjectMessage(Object fileName) {
    return '正在載入 $fileName';
  }

  @override
  String get cannotReadPsdContent => '無法讀取 PSD 檔案內容。';

  @override
  String get cannotReadSai2Content => '無法讀取 SAI2 檔案內容。';

  @override
  String get cannotReadProjectFileContent => '無法讀取專案檔案內容。';

  @override
  String openedProjectInfo(Object name) {
    return '已開啟專案：$name';
  }

  @override
  String openProjectFailed(Object error) {
    return '開啟專案失敗：$error';
  }

  @override
  String get importImageDialogTitle => '匯入圖片';

  @override
  String importedImageInfo(Object name) {
    return '已匯入圖片：$name';
  }

  @override
  String importImageFailed(Object error) {
    return '匯入圖片失敗：$error';
  }

  @override
  String get clipboardNoBitmapFound => '剪貼簿中沒有找到可以匯入的位圖。';

  @override
  String get clipboardImageDefaultName => '剪貼簿影像';

  @override
  String get importedClipboardImageInfo => '已匯入剪貼簿影像';

  @override
  String importClipboardImageFailed(Object error) {
    return '匯入剪貼簿影像失敗：$error';
  }

  @override
  String get webPreparingCanvasTitle => '正在準備畫布…';

  @override
  String get webPreparingCanvasMessage => 'Web 端需要一些時間才能完成初始化，請稍候。';

  @override
  String get aboutTitle => '關於 Misa Rin';

  @override
  String get aboutDescription =>
      'Misa Rin 是一款專注於創意繪製與專案管理的應用，旨在為創作者提供流暢的繪圖體驗與可靠的專案存檔能力。';

  @override
  String get aboutAppIdLabel => '應用識別';

  @override
  String get aboutAppVersionLabel => '應用版本';

  @override
  String get aboutDeveloperLabel => '開發者';

  @override
  String get close => '關閉';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsTabGeneral => '常規';

  @override
  String get settingsTabInput => '輸入與筆刷';

  @override
  String get settingsTabStorage => '歷史與儲存';

  @override
  String get settingsTabAbout => '關於';

  @override
  String get tabletTest => '數位板測試';

  @override
  String get restoreDefaults => '恢復預設';

  @override
  String get ok => '好的';

  @override
  String get languageLabel => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageEnglish => '英文';

  @override
  String get languageJapanese => '日文';

  @override
  String get languageKorean => '韓文';

  @override
  String get languageChineseSimplified => '中文（簡體）';

  @override
  String get languageChineseTraditional => '中文（繁體）';

  @override
  String get themeModeLabel => '主題模式';

  @override
  String get themeLight => '淺色';

  @override
  String get themeDark => '深色';

  @override
  String get themeSystem => '跟隨系統';

  @override
  String get stylusPressureSettingsLabel => '數位筆壓設定';

  @override
  String get enableStylusPressure => '啟用數位筆筆壓';

  @override
  String get responseCurveLabel => '回應曲線';

  @override
  String get responseCurveDesc => '調整壓力與筆觸粗細之間的過渡速度。';

  @override
  String get brushSizeSliderRangeLabel => '筆刷大小滑桿區間';

  @override
  String get brushSizeSliderRangeDesc => '影響工具面板內的筆刷大小滑桿，有助於在不同精度間快速切換。';

  @override
  String get penSliderRangeCompact => '1 - 60 px（粗調）';

  @override
  String get penSliderRangeMedium => '0.1 - 500 px（中檔）';

  @override
  String get penSliderRangeFull => '0.01 - 1000 px（全範圍）';

  @override
  String get historyLimitLabel => '復原/重做步數上限';

  @override
  String historyLimitCurrent(Object count) {
    return '目前上限：$count 步';
  }

  @override
  String historyLimitDesc(Object min, Object max) {
    return '調整復原/重做歷史的儲存數量，範圍 $min-$max。';
  }

  @override
  String get canvasBackendLabel => '畫布後端';

  @override
  String get canvasBackendGpu => 'Rust WGPU';

  @override
  String get canvasBackendCpu => 'Rust CPU';

  @override
  String get canvasBackendRestartHint => '切換畫布後端需要重新啟動後生效。';

  @override
  String get developerOptionsLabel => '開發者選項';

  @override
  String get performanceOverlayLabel => '效能監控面板';

  @override
  String get performanceOverlayDesc =>
      '開啟後會在螢幕角落顯示 Flutter Performance Pulse 儀表板，即時展示 FPS、CPU、記憶體與磁碟等資料。';

  @override
  String get tabletInputTestTitle => '數位板輸入測試';

  @override
  String get recentProjectsTitle => '最近開啟';

  @override
  String recentProjectsLoadFailed(Object error) {
    return '載入最近專案失敗：$error';
  }

  @override
  String get recentProjectsEmpty => '暫無最近開啟的專案';

  @override
  String get openFileLocation => '開啟檔案所在路徑';

  @override
  String lastOpened(Object date) {
    return '最後開啟：$date';
  }

  @override
  String canvasSize(Object width, Object height) {
    return '畫布尺寸：$width x $height';
  }

  @override
  String get menuFile => '檔案';

  @override
  String get menuEdit => '編輯';

  @override
  String get menuImage => '影像';

  @override
  String get menuLayer => '圖層';

  @override
  String get menuSelection => '選取';

  @override
  String get menuFilter => '濾鏡';

  @override
  String get menuTool => '工具';

  @override
  String get menuView => '檢視';

  @override
  String get menuWorkspace => '工作區';

  @override
  String get menuWindow => '視窗';

  @override
  String get menuRoot => '選單';

  @override
  String get menuAbout => '關於 Misa Rin';

  @override
  String get menuPreferences => '偏好設定…';

  @override
  String get menuNewEllipsis => '新建…';

  @override
  String get menuOpenEllipsis => '開啟…';

  @override
  String get menuImportImageEllipsis => '匯入影像…';

  @override
  String get menuImportImageFromClipboard => '從剪貼簿匯入影像';

  @override
  String get menuSave => '儲存';

  @override
  String get menuSaveAsEllipsis => '另存為…';

  @override
  String get menuExportEllipsis => '匯出…';

  @override
  String get menuCloseAll => '關閉全部';

  @override
  String get menuUndo => '復原';

  @override
  String get menuRedo => '重做';

  @override
  String get menuCut => '剪下';

  @override
  String get menuCopy => '複製';

  @override
  String get menuPaste => '貼上';

  @override
  String get menuImageTransform => '影像變換';

  @override
  String get menuRotate90CW => '順時針 90 度';

  @override
  String get menuRotate90CCW => '逆時針 90 度';

  @override
  String get menuRotate180CW => '順時針 180 度';

  @override
  String get menuRotate180CCW => '逆時針 180 度';

  @override
  String get menuFlipHorizontal => '水平翻轉';

  @override
  String get menuFlipVertical => '垂直翻轉';

  @override
  String get menuImageSizeEllipsis => '影像大小…';

  @override
  String get menuCanvasSizeEllipsis => '畫布大小…';

  @override
  String get menuNewSubmenu => '新建';

  @override
  String get menuNewLayerEllipsis => '圖層…';

  @override
  String get menuMergeDown => '向下合併';

  @override
  String get menuRasterize => '柵格化';

  @override
  String get menuTransform => '變換';

  @override
  String get menuSelectAll => '全選';

  @override
  String get menuDeselect => '取消選取';

  @override
  String get menuInvertSelection => '反選';

  @override
  String get menuPalette => '調色盤';

  @override
  String get menuGeneratePaletteFromCanvasEllipsis => '取色目前畫布生成調色盤…';

  @override
  String get menuGenerateGradientPalette => '使用目前顏色生成漸層調色盤';

  @override
  String get menuImportPaletteEllipsis => '匯入調色盤…';

  @override
  String get menuReferenceImage => '參考影像';

  @override
  String get menuCreateReferenceImage => '建立參考影像';

  @override
  String get menuImportReferenceImageEllipsis => '匯入參考影像…';

  @override
  String get menuReferenceModel => '參考模型';

  @override
  String get menuReferenceModelSteve => 'Steve模型';

  @override
  String get menuReferenceModelAlex => 'Alex模型';

  @override
  String get menuReferenceModelCube => '方塊模型';

  @override
  String get menuImportReferenceModelEllipsis => '匯入模型…';

  @override
  String get menuZoomIn => '放大';

  @override
  String get menuZoomOut => '縮小';

  @override
  String get menuShowGrid => '顯示網格';

  @override
  String get menuHideGrid => '隱藏網格';

  @override
  String get menuBlackWhite => '黑白';

  @override
  String get menuDisableBlackWhite => '取消黑白';

  @override
  String get menuMirrorPreview => '鏡像預覽';

  @override
  String get menuDisableMirror => '取消鏡像';

  @override
  String get menuTiledPreview => '平鋪預覽';

  @override
  String get menuDisableTiledPreview => '關閉平鋪預覽';

  @override
  String get menuShowPerspectiveGuide => '顯示透視線';

  @override
  String get menuHidePerspectiveGuide => '隱藏透視線';

  @override
  String get menuPerspectiveMode => '透視模式';

  @override
  String get menuPerspective1Point => '1 點透視';

  @override
  String get menuPerspective2Point => '2 點透視';

  @override
  String get menuPerspective3Point => '3 點透視';

  @override
  String get menuWorkspaceDefault => '預設';

  @override
  String get menuWorkspaceSai2 => 'SAI2';

  @override
  String get menuSwitchWorkspace => '切換工作區';

  @override
  String get menuResetWorkspace => '重置工作區';

  @override
  String get menuEdgeSofteningEllipsis => '邊緣柔化…';

  @override
  String get menuNarrowLinesEllipsis => '線條收窣…';

  @override
  String get menuExpandFillEllipsis => '填色拉伸…';

  @override
  String get menuGaussianBlurEllipsis => '高斯模糊…';

  @override
  String get menuRemoveColorLeakEllipsis => '去除漏色…';

  @override
  String get menuHueSaturationEllipsis => '色相/飽和度…';

  @override
  String get menuBrightnessContrastEllipsis => '亮度/對比度…';

  @override
  String get menuColorRangeEllipsis => '色彩範圍…';

  @override
  String get menuBlackWhiteEllipsis => '黑白…';

  @override
  String get menuBinarizeEllipsis => '二值化…';

  @override
  String get menuScanPaperDrawingEllipsis => '掃描紙繪…';

  @override
  String get menuScanPaperDrawing => '掃描紙繪';

  @override
  String get menuInvertColors => '顏色反轉';

  @override
  String get colorTransparent => '透明';

  @override
  String get exportTypeBitmap => '位圖';

  @override
  String get exportBitmapFormatLabel => '位圖格式';

  @override
  String get exportBitmapFormatPng => 'PNG';

  @override
  String get exportBitmapFormatWebp => 'WebP';

  @override
  String get webpCompressionLabel => 'WebP 壓縮';

  @override
  String get webpLossless => '無損';

  @override
  String get webpLossy => '有損';

  @override
  String webpQualityLabel(Object value) {
    return '品質：$value';
  }

  @override
  String get swapDimensions => '交換寬高';

  @override
  String get brushAntialiasing => '筆刷抗鋸齒';

  @override
  String get bucketAntialiasing => '填充抗鋸齒';

  @override
  String get swallowBlueColorLine => '吞併藍色線';

  @override
  String get swallowGreenColorLine => '吞併綠色線';

  @override
  String get swallowRedColorLine => '吞併紅色線';

  @override
  String get swallowAllColorLine => '吞併所有色線';

  @override
  String get hollowStroke => '空心描邊';

  @override
  String get hollowStrokeRatio => '空心比例';

  @override
  String get eraseOccludedParts => '擦除被遮擋部分';

  @override
  String get touchDrawing => '觸控繪製';

  @override
  String get brushPreset => '筆刷預設';

  @override
  String get brushPresetDesc => '選擇筆刷預設以控制間距、流量與形狀。';

  @override
  String get editBrushPreset => '編輯預設';

  @override
  String get editBrushPresetDesc => '調整目前預設的內部參數。';

  @override
  String get brushPresetDialogTitle => '編輯筆刷預設';

  @override
  String get brushPresetNameLabel => '預設名稱';

  @override
  String get brushPresetPencil => '鉛筆';

  @override
  String get brushPresetCel => '賽璐璐畫筆';

  @override
  String get brushPresetPen => '鋼筆';

  @override
  String get brushPresetScreentone => '網點筆';

  @override
  String get brushPresetPixel => '像素筆';

  @override
  String get brushPresetDryInk => '枯墨';

  @override
  String get brushPresetCharcoal => '炭筆';

  @override
  String get brushPresetStarBrush => '星星筆';

  @override
  String get brushSpacing => '間距';

  @override
  String get brushHardness => '硬度';

  @override
  String get brushFlow => '流量';

  @override
  String get brushScatter => '散佈';

  @override
  String get brushRotationJitter => '旋轉抖動';

  @override
  String get brushSnapToPixel => '像素對齊';

  @override
  String get screentoneEnabled => '網點';

  @override
  String get screentoneShape => '網點形狀';

  @override
  String get screentoneSpacing => '網點間距';

  @override
  String get screentoneDotSize => '網點大小';

  @override
  String get screentoneRotation => '網點旋轉';

  @override
  String get screentoneSoftness => '網點柔化';

  @override
  String get brushAuthorLabel => '作者';

  @override
  String get brushVersionLabel => '版本';

  @override
  String get importBrush => '匯入筆刷';

  @override
  String get exportBrush => '匯出筆刷';

  @override
  String get exportBrushTitle => '匯出筆刷';

  @override
  String get unsavedBrushChangesPrompt => '筆刷參數已修改，是否儲存？';

  @override
  String get discardChanges => '放棄修改';

  @override
  String get brushShapeFolderLabel => '筆刷形狀資料夾';

  @override
  String get openBrushShapesFolder => '打開筆刷形狀資料夾';

  @override
  String get randomRotation => '隨機旋轉';

  @override
  String get smoothRotation => '平滑旋轉';

  @override
  String get selectionAdditive => '允許交集';

  @override
  String get selectionAdditiveDesc => '開啟後無需按 Shift 也可多次框選並合併選區。';

  @override
  String get streamline => '流線';

  @override
  String get star => '五角星';

  @override
  String get streamlineDesc =>
      '類似 Procreate 的 StreamLine：抬筆後對筆畫路徑做平滑重算，並以補間動畫回彈到更順的結果（等級越高越明顯）。';

  @override
  String get hollowStrokeDesc => '將筆畫中心挖空，形成空心描邊效果。';

  @override
  String get hollowStrokeRatioDesc => '調整空心內圈大小，數值越高描邊越細。';

  @override
  String get eraseOccludedPartsDesc => '開啟後，同一圖層裡後畫的空心線條會吃掉與其他線條的重合部分。';

  @override
  String get randomRotationDesc => '開啟後，正方形/三角形/五角星筆刷會在筆觸的每個印章上隨機旋轉。';

  @override
  String get touchDrawingDesc => '關閉後無法用手指觸控繪製，數位筆仍可繪製。';

  @override
  String get swallowBlueColorLineDesc => '色塊填充時只吞併藍色線。';

  @override
  String get swallowGreenColorLineDesc => '色塊填充時只吞併綠色線。';

  @override
  String get swallowRedColorLineDesc => '色塊填充時只吞併紅色線。';

  @override
  String get swallowAllColorLineDesc => '色塊填充時吞併紅/綠/藍色線。';

  @override
  String get starTipDesc => '使用五角星筆尖繪製裝飾性筆觸。';

  @override
  String get layerEmptyScanPaperDrawing => '目前圖層為空，無法掃描紙繪。';

  @override
  String get scanPaperDrawingNoChanges => '未偵測到可轉換的像素。';

  @override
  String get saveAsSai2 => '另存為 SAI2';

  @override
  String get fontFamily => '字體系列';

  @override
  String get fontSearchPlaceholder => '搜尋字體...';

  @override
  String get noMatchingFonts => '沒有符合的字體。';

  @override
  String get fontPreviewText => '預覽文字';

  @override
  String get fontPreviewLanguages => '測試語言';

  @override
  String get fontLanguageCategory => '語言分類';

  @override
  String get fontLanguageAll => '全部';

  @override
  String get fontFavorites => '收藏';

  @override
  String get noFavoriteFonts => '尚無收藏字體。';

  @override
  String get importPaletteTitle => '匯入調色盤';

  @override
  String get cannotReadFile => '無法讀取檔案';

  @override
  String paletteImported(Object name) {
    return '已匯入調色盤：$name';
  }

  @override
  String paletteImportFailed(Object error) {
    return '匯入調色盤失敗：$error';
  }

  @override
  String noChangesToSave(Object location) {
    return '沒有變更需要儲存到 $location';
  }

  @override
  String projectSaved(Object location) {
    return '專案已儲存到 $location';
  }

  @override
  String projectSaveFailed(Object error) {
    return '儲存專案失敗：$error';
  }

  @override
  String get canvasNotReadySave => '畫布未準備好，無法儲存。';

  @override
  String get saveProjectAs => '專案另存為';

  @override
  String get webSaveDesc => '下載專案檔案到您的裝置。';

  @override
  String psdExported(Object path) {
    return 'PSD 已匯出到 $path';
  }

  @override
  String sai2Exported(Object path) {
    return 'SAI2 已匯出到 $path';
  }

  @override
  String projectDownloaded(Object fileName) {
    return '專案已下載：$fileName';
  }

  @override
  String psdDownloaded(Object fileName) {
    return 'PSD 已下載：$fileName';
  }

  @override
  String sai2Downloaded(Object fileName) {
    return 'SAI2 已下載：$fileName';
  }

  @override
  String get exportAsPsdTooltip => '匯出為 PSD';

  @override
  String get exportAsSai2Tooltip => '匯出為 SAI2';

  @override
  String get canvasNotReadyExport => '畫布未準備好，無法匯出。';

  @override
  String exportFileTitle(Object extension) {
    return '匯出 $extension 檔案';
  }

  @override
  String get webExportDesc => '下載匯出的影像到您的裝置。';

  @override
  String fileDownloaded(Object extension, Object name) {
    return '$extension 檔案已下載：$name';
  }

  @override
  String fileExported(Object path) {
    return '檔案已匯出到 $path';
  }

  @override
  String exportFailed(Object error) {
    return '匯出失敗：$error';
  }

  @override
  String get canvasNotReadyTransform => '畫布未準備好，無法變換。';

  @override
  String get canvasSizeErrorTransform => '變換過程中畫布尺寸錯誤。';

  @override
  String get canvasNotReadyResizeImage => '畫布未準備好，無法調整影像大小。';

  @override
  String get resizeImageFailed => '調整影像大小失敗。';

  @override
  String get canvasNotReadyResizeCanvas => '畫布未準備好，無法調整畫布大小。';

  @override
  String get resizeCanvasFailed => '調整畫布大小失敗。';

  @override
  String get returnToHome => '返回首頁';

  @override
  String get saveBeforeReturn => '返回首頁前是否儲存變更？';

  @override
  String get closeCanvas => '關閉畫布';

  @override
  String get saveBeforeClose => '關閉前是否儲存變更？';

  @override
  String get nameCannotBeEmpty => '名稱不能為空。';

  @override
  String get noSupportedImageFormats => '未找到支援的影像格式。';

  @override
  String importFailed(Object item, Object error) {
    return '匯入 $item 失敗：$error';
  }

  @override
  String get createdCanvasFromDrop => '已從拖放項目建立畫布。';

  @override
  String createdCanvasesFromDrop(Object count) {
    return '已從拖放項目建立 $count 個畫布。';
  }

  @override
  String get dropImageCreateFailed => '無法從拖放影像建立畫布。';

  @override
  String get canvasNotReadyDrop => '畫布未準備好進行拖放操作。';

  @override
  String get insertedDropImage => '已插入拖放影像。';

  @override
  String insertedDropImages(Object count) {
    return '已插入 $count 張拖放影像。';
  }

  @override
  String get dropImageInsertFailed => '插入拖放影像失敗。';

  @override
  String get image => '影像';

  @override
  String get on => '開';

  @override
  String get perspective1Point => '一點透視';

  @override
  String get perspective2Point => '兩點透視';

  @override
  String get perspective3Point => '三點透視';

  @override
  String resolutionLabel(Object resolution) {
    return '解析度：$resolution';
  }

  @override
  String zoomLabel(Object zoom) {
    return '縮放：$zoom';
  }

  @override
  String positionLabel(Object position) {
    return '位置：$position';
  }

  @override
  String gridLabel(Object grid) {
    return '網格：$grid';
  }

  @override
  String blackWhiteLabel(Object state) {
    return '黑白：$state';
  }

  @override
  String mirrorLabel(Object state) {
    return '鏡像：$state';
  }

  @override
  String tileLabel(Object state) {
    return '平鋪：$state';
  }

  @override
  String perspectiveLabel(Object perspective) {
    return '透視：$perspective';
  }

  @override
  String get fileNameCannotBeEmpty => '檔名不能為空。';

  @override
  String get blackPoint => '黑點';

  @override
  String get whitePoint => '白點';

  @override
  String get midTone => '中間調';

  @override
  String get rendererLabel => '渲染器';

  @override
  String get rendererNormal => '普通';

  @override
  String get rendererNormalDesc => '即時渲染，速度最快，適合預覽。';

  @override
  String get rendererCinematic => '宣傳片';

  @override
  String get rendererCinematicDesc => '還原 Minecraft 官方宣傳片風格，包含柔和陰影與高對比度光效。';

  @override
  String get rendererCycles => '寫實';

  @override
  String get rendererCyclesDesc => '模擬路徑追蹤風格，極其逼真的光照效果。';

  @override
  String get autoSaveCleanupThresholdLabel => '自動保存清理閾值';

  @override
  String autoSaveCleanupThresholdValue(Object size) {
    return '目前閾值：$size';
  }

  @override
  String get autoSaveCleanupThresholdDesc => '自動保存資料夾總大小超過此值時，啟動會提示清理。';

  @override
  String get autoSaveCleanupDialogTitle => '自動保存占用過大';

  @override
  String autoSaveCleanupDialogMessage(Object size, Object limit) {
    return '自動保存檔案已占用 $size（閾值 $limit）。是否立即清理？';
  }

  @override
  String get autoSaveCleanupDialogClean => '清理';

  @override
  String get exportDestinationTitle => '匯出位置';

  @override
  String get exportDestinationDesc => '請選擇匯出到相簿或檔案管理。';

  @override
  String get imageSourceTitle => '選擇圖片來源';

  @override
  String get imageSourceDesc => '請選擇從相簿或檔案管理匯入圖片。';

  @override
  String get exportDestinationPhotos => '相簿';

  @override
  String get exportDestinationFiles => '檔案管理';

  @override
  String get imageSavedToPhotos => '已儲存到相簿。';

  @override
  String get exportDirectoryLabel => '匯出儲存目錄';

  @override
  String get exportDirectoryDesc => '在 Android 上設定匯出檔案的預設儲存位置。';

  @override
  String get selectExportDirectory => '選擇匯出目錄';

  @override
  String get resetExportDirectory => '恢復預設';

  @override
  String exportDirectoryCurrent(Object path) {
    return '目前：$path';
  }

  @override
  String exportDirectoryDefault(Object path) {
    return '預設：$path';
  }

  @override
  String exportDirectoryUpdated(Object path) {
    return '匯出目錄已更新：$path';
  }

  @override
  String get exportDirectoryCleared => '已恢復預設匯出目錄';

  @override
  String exportDirectoryUpdateFailed(Object error) {
    return '設定匯出目錄失敗：$error';
  }
}
