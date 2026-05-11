import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/services.dart' show rootBundle;
import 'package:misa_rin/utils/io_shim.dart';
import 'package:path/path.dart' as p;

import '../../mobile/mobile_utils.dart';
import '../../src/rust/api/cube_text.dart' as cube_text;
import '../../src/rust/rust_init.dart';
import '../utils/file_name_dialog.dart';
import '../utils/mobile_export_paths.dart';

class ArtTextImageResult {
  const ArtTextImageResult({required this.bytes, required this.layerName});

  final Uint8List bytes;
  final String layerName;
}

Future<ArtTextImageResult?> showArtTextGeneratorDialog(BuildContext context) {
  return showDialog<ArtTextImageResult>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => const _ArtTextGeneratorDialog(),
  );
}

const Map<String, String> _kBuiltinFonts = <String, String>{
  '汉仪力量黑(简)': 'HYLiLiangHeiJ_Regular.json',
  '锐字太空历险像素简': 'REEJI-TaikoMagicGB-Flash_Regular.json',
  'Minecraft Ten': 'Minecraft_Ten_Regular.json',
  'Fusion Pixel 8px': 'Fusion_Pixel_8px_Proportional_zh_hans_Regular.json',
  'Fusion Pixel 10px': 'Fusion_Pixel_10px_Proportional_zh_hans_Regular.json',
  '得意黑': 'Smiley_Sans_Oblique_Regular.json',
  'Unifont ASCII': 'Unifont_ASCII_Regular.json',
};

const List<_OverlayChoice> _kOverlayChoices = <_OverlayChoice>[
  _OverlayChoice('', '无'),
  _OverlayChoice('overlay.highlightTop', '顶部高光'),
  _OverlayChoice('overlay.highlightBottom', '底部高光'),
  _OverlayChoice('overlay.highlightTopBottom', '上下高光'),
  _OverlayChoice('overlay.highlightInnerStroke', '内描边'),
  _OverlayChoice('overlay.highlightInnerHighlight', '内高光'),
  _OverlayChoice('overlay.highlightShine', '斜向闪光'),
  _OverlayChoice('overlay.highlightGlass', '玻璃高光'),
];

const List<String> _kMaterialFaces = <String>[
  'front',
  'back',
  'up',
  'down',
  'left',
  'right',
  'outline',
];

const Map<String, String> _kMaterialFaceLabels = <String, String>{
  'front': '正面',
  'back': '背面',
  'up': '上侧',
  'down': '下侧',
  'left': '左侧',
  'right': '右侧',
  'outline': '描边',
};

const int _kRasterAntialiasSamples = 2;
const int _kPreviewMaxSupersampledPixels = 10000000;

int _objectSerial = 0;

double _previewPixelRatio(
  double logicalWidth,
  double logicalHeight,
  double devicePixelRatio,
) {
  final double logicalPixels = math.max(1.0, logicalWidth * logicalHeight);
  final double maxRatio = math.sqrt(
    _kPreviewMaxSupersampledPixels /
        (logicalPixels * _kRasterAntialiasSamples * _kRasterAntialiasSamples),
  );
  final double targetRatio = devicePixelRatio.clamp(1.0, 2.0).toDouble();
  return math.max(1.0, math.min(targetRatio, maxRatio));
}

int _exportAntialiasSamples(int width, int height) {
  final int pixels = math.max(1, width) * math.max(1, height);
  return pixels * _kRasterAntialiasSamples * _kRasterAntialiasSamples <=
          12000000
      ? _kRasterAntialiasSamples
      : 1;
}

class _OverlayChoice {
  const _OverlayChoice(this.value, this.label);

  final String value;
  final String label;
}

class _ArtTextGeneratorDialog extends StatefulWidget {
  const _ArtTextGeneratorDialog();

  @override
  State<_ArtTextGeneratorDialog> createState() =>
      _ArtTextGeneratorDialogState();
}

class _ArtTextGeneratorDialogState extends State<_ArtTextGeneratorDialog> {
  final Map<String, TextEditingController> _contentControllers =
      <String, TextEditingController>{};
  final Map<String, ui.Image> _materialImages = <String, ui.Image>{};

  List<_CubeFontAsset> _fonts = <_CubeFontAsset>[];
  Map<String, _TextMaterials> _materialPresets = <String, _TextMaterials>{};
  List<_ArtTextObject> _texts = <_ArtTextObject>[];
  String _globalFontId = 'Fusion Pixel 10px';
  int _selectedTextIndex = 0;

  cube_text.CubeTextScene? _scene;
  Timer? _buildDebounce;
  int _buildSerial = 0;
  bool _loadingAssets = true;
  bool _buildingScene = false;
  bool _busy = false;
  String? _statusMessage;
  InfoBarSeverity _statusSeverity = InfoBarSeverity.info;

  double _yaw = 0;
  double _pitch = -22;
  double _zoom = 1.0;
  double _fov = 75;
  int _outputWidth = 1600;
  int _outputHeight = 900;
  bool _transparentBackground = true;
  String _modelFormat = 'glb';

  @override
  void initState() {
    super.initState();
    _texts = <_ArtTextObject>[
      _ArtTextObject(
        id: _newObjectId(),
        content: '我的世界',
        options: _TextOptions(
          size: 10,
          depth: 5,
          x: 0,
          y: 8,
          z: 0,
          rotY: 0,
          rotX: 0,
          rotZ: 0,
          materials: _defaultYellowMaterials(),
          outlineWidth: 0.4,
          letterSpacing: 1.0,
          spacingWidth: 0.2,
          overlay: '',
        ),
      ),
      _ArtTextObject(
        id: _newObjectId(),
        content: '中国版',
        options: _TextOptions(
          size: 5,
          depth: 3,
          x: 0,
          y: -4,
          z: 0,
          rotY: 0,
          rotX: 0,
          rotZ: 0,
          materials: _defaultBlueMaterials(),
          outlineWidth: 0.5,
          letterSpacing: 1.5,
          spacingWidth: 0.2,
          overlay: '',
        ),
      ),
    ];
    for (final _ArtTextObject text in _texts) {
      _contentControllers[text.id] = TextEditingController(text: text.content);
    }
    _loadAssets();
  }

  @override
  void dispose() {
    _buildDebounce?.cancel();
    for (final TextEditingController controller in _contentControllers.values) {
      controller.dispose();
    }
    for (final ui.Image image in _materialImages.values) {
      image.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAssets() async {
    try {
      final List<_CubeFontAsset> fonts = <_CubeFontAsset>[];
      for (final MapEntry<String, String> entry in _kBuiltinFonts.entries) {
        final String json = await rootBundle.loadString(
          'assets/cube_3d_text/font/${entry.value}',
        );
        fonts.add(
          _CubeFontAsset(
            id: entry.key,
            json: json,
            fileName: entry.value,
            builtin: true,
          ),
        );
      }

      final String indexJson = await rootBundle.loadString(
        'assets/cube_3d_text/materials/index.json',
      );
      final Object? decodedIndex = jsonDecode(indexJson);
      final Map<String, _TextMaterials> presets = <String, _TextMaterials>{};
      if (decodedIndex is List<Object?>) {
        for (final Object? item in decodedIndex) {
          final String id = item?.toString() ?? '';
          if (id.isEmpty) {
            continue;
          }
          final String presetJson = await rootBundle.loadString(
            'assets/cube_3d_text/materials/$id.json',
          );
          final Object? decoded = jsonDecode(presetJson);
          if (decoded is Map<String, Object?>) {
            final Object? material = decoded['material'];
            if (material is Map<String, Object?>) {
              presets[id] = _TextMaterials.fromJson(material);
            }
          }
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _fonts = fonts;
        _materialPresets = presets;
        _loadingAssets = false;
      });
      _scheduleSceneBuild(immediate: true);
      unawaited(_syncMaterialImages());
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingAssets = false;
        _statusSeverity = InfoBarSeverity.error;
        _statusMessage = '艺术字体资源加载失败：$error';
      });
    }
  }

  void _mutate(VoidCallback update, {bool rebuild = true}) {
    setState(update);
    if (rebuild) {
      _scheduleSceneBuild();
      unawaited(_syncMaterialImages());
    }
  }

  void _scheduleSceneBuild({bool immediate = false}) {
    _buildDebounce?.cancel();
    if (immediate) {
      unawaited(_buildScene());
      return;
    }
    _buildDebounce = Timer(const Duration(milliseconds: 160), _buildScene);
  }

  Future<void> _buildScene() async {
    if (_fonts.isEmpty) {
      return;
    }
    final int serial = ++_buildSerial;
    setState(() {
      _buildingScene = true;
    });
    try {
      await ensureRustInitialized();
      final cube_text.CubeTextScene scene = await cube_text.cubeTextBuildScene(
        fonts: _cubeFonts,
        globalFontId: _globalFontId,
        texts: _cubeTexts,
      );
      if (!mounted || serial != _buildSerial) {
        return;
      }
      setState(() {
        _scene = scene;
        _buildingScene = false;
        if (_statusSeverity == InfoBarSeverity.error) {
          _statusMessage = null;
        }
      });
    } catch (error) {
      if (!mounted || serial != _buildSerial) {
        return;
      }
      setState(() {
        _buildingScene = false;
        _statusSeverity = InfoBarSeverity.error;
        _statusMessage = '网格生成失败：$error';
      });
    }
  }

  List<cube_text.CubeTextFontAsset> get _cubeFonts {
    return _fonts
        .map(
          (_CubeFontAsset font) =>
              cube_text.CubeTextFontAsset(id: font.id, json: font.json),
        )
        .toList(growable: false);
  }

  List<cube_text.CubeTextObject> get _cubeTexts {
    return _texts
        .map((text) => text.toCubeTextObject())
        .toList(growable: false);
  }

  _ArtTextObject get _selectedText {
    if (_texts.isEmpty) {
      throw StateError('No art text objects');
    }
    _selectedTextIndex = _selectedTextIndex.clamp(0, _texts.length - 1);
    return _texts[_selectedTextIndex];
  }

  bool get _canRender => _scene != null && !_loadingAssets;

  void _setStatus(String message, InfoBarSeverity severity) {
    setState(() {
      _statusMessage = message;
      _statusSeverity = severity;
    });
  }

  void _addText() {
    final int index = _texts.length;
    final _ArtTextObject text = _ArtTextObject(
      id: _newObjectId(),
      content: 'New Text',
      options: _TextOptions(
        size: 5,
        depth: 3,
        x: 0,
        y: index * -6.0,
        z: 0,
        rotY: 0,
        rotX: 0,
        rotZ: 0,
        materials: _defaultBlueMaterials(),
        outlineWidth: 0.5,
        letterSpacing: 1.5,
        spacingWidth: 0.2,
        overlay: '',
      ),
    );
    _contentControllers[text.id] = TextEditingController(text: text.content);
    _mutate(() {
      _texts.add(text);
      _selectedTextIndex = _texts.length - 1;
    });
  }

  void _removeText(int index) {
    if (_texts.length <= 1) {
      return;
    }
    final _ArtTextObject removed = _texts.removeAt(index);
    _contentControllers.remove(removed.id)?.dispose();
    _mutate(() {
      _selectedTextIndex = _selectedTextIndex.clamp(0, _texts.length - 1);
    });
  }

  void _resetCamera() {
    setState(() {
      _yaw = 0;
      _pitch = -22;
      _zoom = 1.0;
      _fov = 75;
    });
  }

  Future<void> _importFont() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['ttf', 'otf', 'json'],
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final PlatformFile file = result.files.single;
    final String extension = p.extension(file.name).toLowerCase();
    try {
      setState(() => _busy = true);
      final Uint8List bytes = await _readPickedFileBytes(file);
      late final String fontId;
      late final String fontJson;
      if (extension == '.json') {
        fontJson = utf8.decode(bytes);
        fontId = _fontIdFromJson(fontJson, file.name);
      } else {
        await ensureRustInitialized();
        final cube_text.CubeTextFontConvertResult converted = await cube_text
            .cubeTextConvertTtfToFontJson(bytes: bytes);
        fontId = converted.fontId.trim().isEmpty
            ? p.basenameWithoutExtension(file.name)
            : converted.fontId.trim();
        fontJson = converted.json;
      }
      final String uniqueId = _uniqueFontId(fontId);
      setState(() {
        _fonts.add(
          _CubeFontAsset(
            id: uniqueId,
            json: fontJson,
            fileName: file.name,
            builtin: false,
          ),
        );
        _globalFontId = uniqueId;
        _busy = false;
        _statusSeverity = InfoBarSeverity.success;
        _statusMessage = '已导入字体：$uniqueId';
      });
      _scheduleSceneBuild(immediate: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      _setStatus('字体导入失败：$error', InfoBarSeverity.error);
    }
  }

  Future<void> _deleteFont(String id) async {
    final _CubeFontAsset? target = _fonts
        .where((font) => font.id == id)
        .firstOrNull;
    if (target == null || target.builtin) {
      return;
    }
    _mutate(() {
      _fonts.removeWhere((font) => font.id == id);
      if (_globalFontId == id) {
        _globalFontId = _fonts.isEmpty ? '' : _fonts.first.id;
      }
      for (final _ArtTextObject text in _texts) {
        if (text.fontId == id) {
          text.fontId = null;
        }
      }
    });
  }

  Future<void> _importWorkspace() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    try {
      final String jsonText = utf8.decode(
        await _readPickedFileBytes(result.files.single),
      );
      final _WorkspaceImport imported = _WorkspaceImport.parse(jsonText);
      final Set<String> existingFontIds = _fonts.map((font) => font.id).toSet();
      for (final _CubeFontAsset font in imported.fonts) {
        if (!existingFontIds.contains(font.id)) {
          _fonts.add(font);
          existingFontIds.add(font.id);
        }
      }
      final String fallbackFont =
          _fonts.any((font) => font.id == imported.globalFontId)
          ? imported.globalFontId
          : (_fonts.isEmpty ? imported.globalFontId : _fonts.first.id);
      for (final TextEditingController controller
          in _contentControllers.values) {
        controller.dispose();
      }
      _contentControllers.clear();
      setState(() {
        _globalFontId = fallbackFont;
        _texts = imported.texts.isEmpty
            ? <_ArtTextObject>[
                _ArtTextObject(
                  id: _newObjectId(),
                  content: 'New Text',
                  options: _TextOptions.defaults(),
                ),
              ]
            : imported.texts
                  .map((_ArtTextObject text) {
                    if (text.fontId != null &&
                        !_fonts.any((font) => font.id == text.fontId)) {
                      text.fontId = null;
                    }
                    _contentControllers[text.id] = TextEditingController(
                      text: text.content,
                    );
                    return text;
                  })
                  .toList(growable: false);
        _selectedTextIndex = 0;
        _statusSeverity = InfoBarSeverity.success;
        _statusMessage = '工作区已导入。';
      });
      if (_contentControllers.isEmpty) {
        for (final _ArtTextObject text in _texts) {
          _contentControllers[text.id] = TextEditingController(
            text: text.content,
          );
        }
      }
      _scheduleSceneBuild(immediate: true);
      unawaited(_syncMaterialImages());
    } catch (error) {
      _setStatus('工作区导入失败：$error', InfoBarSeverity.error);
    }
  }

  Future<void> _exportWorkspace() async {
    final String jsonText = const JsonEncoder.withIndent(
      '  ',
    ).convert(_workspaceJson());
    await _saveBytes(
      title: '导出 3D 字体工作区',
      fileName: '${_safeProjectName()}.json',
      extension: 'json',
      mimeType: 'application/json',
      bytes: Uint8List.fromList(utf8.encode(jsonText)),
    );
  }

  Future<void> _importMaterialForSelected() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    try {
      final String jsonText = utf8.decode(
        await _readPickedFileBytes(result.files.single),
      );
      final Object? decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('不是有效的材质 JSON。');
      }
      final Object? material = decoded['material'] is Map<String, Object?>
          ? decoded['material']
          : decoded;
      if (material is! Map<String, Object?>) {
        throw const FormatException('找不到 material 字段。');
      }
      _mutate(() {
        _selectedText.options = _selectedText.options.copyWith(
          materials: _TextMaterials.fromJson(material),
        );
        _statusSeverity = InfoBarSeverity.success;
        _statusMessage = '材质已导入到当前文字。';
      });
    } catch (error) {
      _setStatus('材质导入失败：$error', InfoBarSeverity.error);
    }
  }

  Future<void> _exportMaterialForSelected() async {
    final Map<String, Object?> jsonMap = <String, Object?>{
      'version': 1,
      'material': _selectedText.options.materials.toJson(),
    };
    await _saveBytes(
      title: '导出材质',
      fileName: 'material.json',
      extension: 'json',
      mimeType: 'application/json',
      bytes: Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(jsonMap)),
      ),
    );
  }

  Future<void> _importImageForMaterial(String face) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    try {
      final PlatformFile file = result.files.single;
      final Uint8List bytes = await _readPickedFileBytes(file);
      final String mimeType = _imageMimeType(file.name);
      final String dataUri = 'data:$mimeType;base64,${base64Encode(bytes)}';
      _updateSelectedMaterial(face, (option) {
        return option.copyWith(
          mode: 'image',
          image: dataUri,
          repeatX: option.repeatX <= 0 ? 0.1 : option.repeatX,
          repeatY: option.repeatY <= 0 ? 0.1 : option.repeatY,
        );
      });
    } catch (error) {
      _setStatus('贴图导入失败：$error', InfoBarSeverity.error);
    }
  }

  Future<void> _exportModel() async {
    if (_fonts.isEmpty) {
      return;
    }
    try {
      setState(() => _busy = true);
      await ensureRustInitialized();
      final cube_text.CubeTextExportResult result = await cube_text
          .cubeTextExportScene(
            fonts: _cubeFonts,
            globalFontId: _globalFontId,
            texts: _cubeTexts,
            format: _modelFormat,
          );
      await _saveBytes(
        title: '导出 ${_modelFormat.toUpperCase()} 模型',
        fileName: result.fileName,
        extension: _modelFormat,
        mimeType: result.mimeType,
        bytes: result.bytes,
      );
      if (mounted) {
        setState(() => _busy = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
      }
      _setStatus('模型导出失败：$error', InfoBarSeverity.error);
    }
  }

  Future<void> _exportPng() async {
    try {
      setState(() => _busy = true);
      final Uint8List bytes = await _renderPngBytes();
      await _saveBytes(
        title: '导出透明 PNG',
        fileName: '${_safeProjectName()}.png',
        extension: 'png',
        mimeType: 'image/png',
        bytes: bytes,
      );
      if (mounted) {
        setState(() => _busy = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
      }
      _setStatus('PNG 导出失败：$error', InfoBarSeverity.error);
    }
  }

  Future<void> _insertIntoCanvas() async {
    try {
      setState(() => _busy = true);
      final Uint8List bytes = await _renderPngBytes();
      if (!mounted) {
        return;
      }
      Navigator.of(
        context,
      ).pop(ArtTextImageResult(bytes: bytes, layerName: _safeProjectName()));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      _setStatus('生成 PNG 失败：$error', InfoBarSeverity.error);
    }
  }

  Future<Uint8List> _renderPngBytes() async {
    if (_scene == null) {
      await _buildScene();
    }
    final cube_text.CubeTextScene? scene = _scene;
    if (scene == null) {
      throw StateError('网格尚未生成。');
    }
    ui.Image image = await _renderCubeTextRasterImage(
      scene: scene,
      texts: _texts,
      width: _outputWidth,
      height: _outputHeight,
      yaw: _yaw,
      pitch: _pitch,
      zoom: _zoom,
      fov: _fov,
      transparentBackground: _transparentBackground,
      materialImages: _materialImages,
      antialiasSamples: _exportAntialiasSamples(_outputWidth, _outputHeight),
    );
    if (_transparentBackground) {
      final ui.Image? cropped = await _cropTransparentImage(image, padding: 8);
      if (cropped != null) {
        image.dispose();
        image = cropped;
      }
    }
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    if (data == null) {
      throw StateError('PNG 编码失败。');
    }
    return data.buffer.asUint8List();
  }

  Future<void> _saveBytes({
    required String title,
    required String fileName,
    required String extension,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final String normalizedExtension = extension.toLowerCase();
    final String suggestedName = _normalizeFileName(
      fileName,
      normalizedExtension,
    );
    try {
      String? outputPath;
      if (Platform.isAndroid || Platform.isIOS) {
        final String? pickedName = await showFileNameDialog(
          context: context,
          title: title,
          suggestedFileName: suggestedName,
          confirmLabel: '保存',
        );
        if (pickedName == null) {
          return;
        }
        outputPath = await MobileExportPaths.resolveExportPath(
          _normalizeFileName(
            _sanitizeFileName(pickedName),
            normalizedExtension,
          ),
        );
      } else {
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: title,
          fileName: suggestedName,
          type: FileType.custom,
          allowedExtensions: <String>[normalizedExtension],
        );
        if (outputPath == null) {
          return;
        }
        outputPath = _normalizeFileName(outputPath, normalizedExtension);
      }
      await File(outputPath).writeAsBytes(bytes, flush: true);
      _setStatus('已导出：$outputPath', InfoBarSeverity.success);
    } catch (error) {
      _setStatus('保存失败：$error', InfoBarSeverity.error);
    }
  }

  Future<Uint8List> _readPickedFileBytes(PlatformFile file) async {
    if (file.bytes != null) {
      return Uint8List.fromList(file.bytes!);
    }
    final String? path = file.path;
    if (path == null || path.isEmpty) {
      throw StateError('无法读取文件：${file.name}');
    }
    return File(path).readAsBytes();
  }

  Map<String, Object?> _workspaceJson() {
    final List<Map<String, Object?>> customFonts = _fonts
        .where((font) => !font.builtin)
        .map(
          (font) => <String, Object?>{
            'id': font.id,
            'json': font.json,
            'fileName': font.fileName,
          },
        )
        .toList(growable: false);
    final Map<String, Object?> data = <String, Object?>{
      'fontId': _globalFontId,
      'texts': _texts.map((text) => text.toWorkspaceJson()).toList(),
    };
    if (customFonts.isNotEmpty) {
      data['fonts'] = customFonts;
    }
    return <String, Object?>{'version': 1, 'data': data};
  }

  Future<void> _syncMaterialImages() async {
    final Set<String> requiredImages = <String>{};
    for (final _ArtTextObject text in _texts) {
      for (final _MaterialOption option in text.options.materials.options) {
        if (option.mode == 'image' && option.image.startsWith('data:image/')) {
          requiredImages.add(option.image);
        }
      }
    }
    for (final String dataUri in requiredImages) {
      if (_materialImages.containsKey(dataUri)) {
        continue;
      }
      try {
        final Uint8List bytes = _decodeDataUri(dataUri);
        final ui.Image image = await _decodeUiImage(bytes);
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _materialImages[dataUri] = image;
        });
      } catch (_) {
        // The mesh and export still keep the original data URI even if preview
        // decoding fails.
      }
    }
  }

  void _updateSelectedOptions(_TextOptions Function(_TextOptions) update) {
    _mutate(() {
      _selectedText.options = update(_selectedText.options);
    });
  }

  void _updateSelectedMaterial(
    String face,
    _MaterialOption Function(_MaterialOption) update,
  ) {
    _updateSelectedOptions((options) {
      return options.copyWith(
        materials: options.materials.copyWithFace(face, update),
      );
    });
  }

  Future<void> _pickColorForFace(String face, String field) async {
    final _MaterialOption option = _selectedText.options.materials.face(face);
    final String current = switch (field) {
      'color' => option.color,
      'start' => option.colorGradualStart,
      'end' => option.colorGradualEnd,
      _ => option.color,
    };
    Color selected = _parseColor(current) ?? const Color(0xFFFFFFFF);
    final Color? result = await showDialog<Color>(
      context: context,
      builder: (BuildContext context) {
        return ContentDialog(
          title: Text('选择${_kMaterialFaceLabels[face] ?? face}颜色'),
          content: SizedBox(
            width: 320,
            child: ColorPicker(
              color: selected,
              onChanged: (Color color) {
                selected = color;
              },
              isAlphaEnabled: false,
              isAlphaSliderVisible: false,
              isAlphaTextInputVisible: false,
              isColorChannelTextInputVisible: false,
              isHexInputVisible: true,
              isMoreButtonVisible: false,
            ),
          ),
          actions: <Widget>[
            Button(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(selected),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (result == null) {
      return;
    }
    final String hex = _colorToHex(result);
    _updateSelectedMaterial(face, (option) {
      return switch (field) {
        'start' => option.copyWith(colorGradualStart: hex),
        'end' => option.copyWith(colorGradualEnd: hex),
        _ => option.copyWith(color: hex),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = isMobileOrPhone(context);
    final double maxWidth = isMobile ? 720 : 1220;
    final double maxHeight = isMobile ? 720 : 820;
    return ContentDialog(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      title: Row(
        children: <Widget>[
          const Expanded(child: Text('Cube 3D Text 艺术字体生成器')),
          if (_loadingAssets || _buildingScene || _busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: ProgressRing(strokeWidth: 2.5),
            ),
        ],
      ),
      content: SizedBox(
        width: maxWidth,
        height: isMobile ? 580 : 680,
        child: _loadingAssets
            ? const Center(child: ProgressRing())
            : LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool narrow = constraints.maxWidth < 860;
                  if (narrow) {
                    return Column(
                      children: <Widget>[
                        SizedBox(
                          height: math.min(300, constraints.maxHeight * 0.45),
                          child: _buildPreviewPane(),
                        ),
                        const SizedBox(height: 12),
                        Expanded(child: _buildSettingsPane()),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: _buildPreviewPane()),
                      const SizedBox(width: 14),
                      SizedBox(width: 390, child: _buildSettingsPane()),
                    ],
                  );
                },
              ),
      ),
      actions: <Widget>[
        Button(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        Button(
          onPressed: _busy || !_canRender ? null : _exportPng,
          child: const Text('导出 PNG'),
        ),
        FilledButton(
          onPressed: _busy || !_canRender ? null : _insertIntoCanvas,
          child: const Text('插入画布'),
        ),
      ],
    );
  }

  Widget _buildPreviewPane() {
    final cube_text.CubeTextScene? scene = _scene;
    final int triangleCount = scene == null ? 0 : scene.indices.length ~/ 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildPreviewToolbar(triangleCount),
        const SizedBox(height: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _transparentBackground
                    ? const Color(0xFFE9EEF5)
                    : const Color(0xFFF7F7F7),
                border: Border.all(color: const Color(0x22000000)),
              ),
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    setState(() {
                      _zoom = (_zoom * (event.scrollDelta.dy > 0 ? 0.92 : 1.08))
                          .clamp(0.25, 5.0);
                    });
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (DragUpdateDetails details) {
                    setState(() {
                      _yaw += details.delta.dx * 0.35;
                      _pitch = (_pitch + details.delta.dy * 0.28).clamp(
                        -85,
                        85,
                      );
                    });
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (scene == null) {
                        return Center(
                          child: Text(
                            _statusMessage ?? '正在生成真实 3D 网格...',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      final double rawWidth = constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : 1;
                      final double rawHeight = constraints.maxHeight.isFinite
                          ? constraints.maxHeight
                          : 1;
                      final double pixelRatio = _previewPixelRatio(
                        rawWidth,
                        rawHeight,
                        MediaQuery.devicePixelRatioOf(context),
                      );
                      final int width = math
                          .max(1, (rawWidth * pixelRatio).round())
                          .toInt();
                      final int height = math
                          .max(1, (rawHeight * pixelRatio).round())
                          .toInt();
                      return _CubeTextRasterPreview(
                        scene: scene,
                        texts: _texts,
                        width: width,
                        height: height,
                        pixelRatio: pixelRatio,
                        yaw: _yaw,
                        pitch: _pitch,
                        zoom: _zoom,
                        fov: _fov,
                        transparentBackground: false,
                        materialImages: _materialImages,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_statusMessage != null || (scene?.warnings.isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InfoBar(
              title: Text(_statusMessage ?? '网格警告'),
              content: Text(
                _statusMessage ?? scene!.warnings.take(3).join('\n'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              severity: _statusSeverity,
              isLong: true,
            ),
          ),
      ],
    );
  }

  Widget _buildPreviewToolbar(int triangleCount) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Button(
          onPressed: _resetCamera,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(FluentIcons.reset, size: 14),
              SizedBox(width: 6),
              Text('重置视角'),
            ],
          ),
        ),
        SizedBox(
          width: 220,
          child: InfoLabel(
            label: _fov == 0 ? '正交投影' : '透视角 ${_fov.round()}°',
            child: Slider(
              min: 0,
              max: 120,
              divisions: 120,
              value: _fov,
              onChanged: (double value) {
                setState(() => _fov = value.roundToDouble());
              },
            ),
          ),
        ),
        SizedBox(
          width: 180,
          child: InfoLabel(
            label: '缩放 ${_zoom.toStringAsFixed(2)}x',
            child: Slider(
              min: 0.25,
              max: 4,
              value: _zoom,
              onChanged: (double value) => setState(() => _zoom = value),
            ),
          ),
        ),
        Text('三角面：$triangleCount'),
      ],
    );
  }

  Widget _buildSettingsPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildGlobalControls(),
        const SizedBox(height: 12),
        Expanded(child: _buildTextTabs()),
      ],
    );
  }

  Widget _buildGlobalControls() {
    return Expander(
      initiallyExpanded: true,
      header: const Text('场景 / 字体 / 输出'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InfoLabel(
            label: '全局字体',
            child: ComboBox<String>(
              value: _fonts.any((font) => font.id == _globalFontId)
                  ? _globalFontId
                  : null,
              isExpanded: true,
              items: _fonts
                  .map(
                    (font) => ComboBoxItem<String>(
                      value: font.id,
                      child: Text(
                        font.builtin ? font.id : '${font.id}（导入）',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }
                _mutate(() => _globalFontId = value);
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Button(
                onPressed: _busy ? null : _importFont,
                child: const Text('导入字体'),
              ),
              Button(
                onPressed: _busy ? null : _importWorkspace,
                child: const Text('导入工作区'),
              ),
              Button(
                onPressed: _busy ? null : _exportWorkspace,
                child: const Text('导出工作区'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _buildIntBox(
                  label: 'PNG 宽',
                  value: _outputWidth,
                  min: 64,
                  max: 4096,
                  onChanged: (int value) {
                    setState(() => _outputWidth = value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildIntBox(
                  label: 'PNG 高',
                  value: _outputHeight,
                  min: 64,
                  max: 4096,
                  onChanged: (int value) {
                    setState(() => _outputHeight = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ToggleSwitch(
            checked: _transparentBackground,
            content: const Text('透明背景 PNG'),
            onChanged: (bool value) {
              setState(() => _transparentBackground = value);
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: ComboBox<String>(
                  value: _modelFormat,
                  isExpanded: true,
                  items: const <ComboBoxItem<String>>[
                    ComboBoxItem<String>(value: 'glb', child: Text('GLB')),
                    ComboBoxItem<String>(value: 'gltf', child: Text('glTF')),
                    ComboBoxItem<String>(value: 'obj', child: Text('OBJ')),
                    ComboBoxItem<String>(value: 'stl', child: Text('STL')),
                  ],
                  onChanged: (String? value) {
                    if (value != null) {
                      setState(() => _modelFormat = value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: _busy || !_canRender ? null : _exportModel,
                child: const Text('导出模型'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextTabs() {
    return TabView(
      currentIndex: _selectedTextIndex.clamp(0, _texts.length - 1),
      onChanged: (int index) {
        setState(() => _selectedTextIndex = index);
      },
      onNewPressed: _addText,
      closeButtonVisibility: _texts.length > 1
          ? CloseButtonVisibilityMode.always
          : CloseButtonVisibilityMode.never,
      tabWidthBehavior: TabWidthBehavior.sizeToContent,
      tabs: List<Tab>.generate(_texts.length, (int index) {
        final _ArtTextObject text = _texts[index];
        final String title = text.content.trim().isEmpty
            ? '文字 ${index + 1}'
            : text.content.trim();
        return Tab(
          text: Text(
            title.length > 8 ? '${title.substring(0, 8)}...' : title,
            overflow: TextOverflow.ellipsis,
          ),
          body: _buildTextSettings(index),
          onClosed: _texts.length > 1 ? () => _removeText(index) : null,
        );
      }),
    );
  }

  Widget _buildTextSettings(int index) {
    final _ArtTextObject text = _texts[index];
    final TextEditingController controller = _contentControllers.putIfAbsent(
      text.id,
      () => TextEditingController(text: text.content),
    );
    if (controller.text != text.content) {
      controller.value = TextEditingValue(
        text: text.content,
        selection: TextSelection.collapsed(offset: text.content.length),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12, right: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InfoLabel(
            label: '内容',
            child: TextBox(
              controller: controller,
              maxLines: 2,
              onChanged: (String value) {
                _mutate(() => text.content = value);
              },
            ),
          ),
          const SizedBox(height: 10),
          InfoLabel(
            label: '本段字体',
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ComboBox<String>(
                    value: text.fontId ?? '__global__',
                    isExpanded: true,
                    items: <ComboBoxItem<String>>[
                      ComboBoxItem<String>(
                        value: '__global__',
                        child: Text('使用全局字体（$_globalFontId）'),
                      ),
                      ..._fonts.map(
                        (font) => ComboBoxItem<String>(
                          value: font.id,
                          child: Text(
                            font.builtin ? font.id : '${font.id}（导入）',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (String? value) {
                      _mutate(() {
                        text.fontId = value == null || value == '__global__'
                            ? null
                            : value;
                      });
                    },
                  ),
                ),
                if (text.fontId != null &&
                    _fonts.any(
                      (font) => font.id == text.fontId && !font.builtin,
                    ))
                  IconButton(
                    icon: const Icon(FluentIcons.delete, size: 14),
                    onPressed: () => _deleteFont(text.fontId!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expander(
            initiallyExpanded: true,
            header: const Text('变换和几何'),
            content: Column(
              children: <Widget>[
                _buildVector3Controls(text),
                _buildNumberSlider(
                  label: '上下旋转',
                  value: text.options.rotY,
                  min: -90,
                  max: 90,
                  step: 1,
                  onChanged: (double value) {
                    _updateObjectOptions(text, (options) {
                      return options.copyWith(rotY: value);
                    });
                  },
                ),
                _buildNumberSlider(
                  label: '左右旋转',
                  value: text.options.rotX,
                  min: -180,
                  max: 180,
                  step: 1,
                  onChanged: (double value) {
                    _updateObjectOptions(text, (options) {
                      return options.copyWith(rotX: value);
                    });
                  },
                ),
                _buildNumberSlider(
                  label: '平面旋转',
                  value: text.options.rotZ,
                  min: -180,
                  max: 180,
                  step: 1,
                  onChanged: (double value) {
                    _updateObjectOptions(text, (options) {
                      return options.copyWith(rotZ: value);
                    });
                  },
                ),
                _buildNumberSlider(
                  label: '字号',
                  value: text.options.size,
                  min: 1,
                  max: 20,
                  step: 0.1,
                  onChanged: (double value) {
                    _updateObjectOptions(text, (options) {
                      return options.copyWith(size: value);
                    });
                  },
                ),
                _buildNumberSlider(
                  label: '厚度',
                  value: text.options.depth,
                  min: 1,
                  max: 10,
                  step: 0.1,
                  onChanged: (double value) {
                    _updateObjectOptions(text, (options) {
                      return options.copyWith(depth: value);
                    });
                  },
                ),
                _buildNumberSlider(
                  label: '描边',
                  value: text.options.outlineWidth,
                  min: 0,
                  max: 1,
                  step: 0.05,
                  onChanged: (double value) {
                    _updateObjectOptions(text, (options) {
                      return options.copyWith(outlineWidth: value);
                    });
                  },
                ),
                _buildNumberSlider(
                  label: '字间距',
                  value: text.options.letterSpacing,
                  min: 0,
                  max: 5,
                  step: 0.1,
                  onChanged: (double value) {
                    _updateObjectOptions(text, (options) {
                      return options.copyWith(letterSpacing: value);
                    });
                  },
                ),
                _buildNumberSlider(
                  label: '空格宽度',
                  value: text.options.spacingWidth,
                  min: -0.2,
                  max: 1,
                  step: 0.05,
                  onChanged: (double value) {
                    _updateObjectOptions(text, (options) {
                      return options.copyWith(spacingWidth: value);
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildMaterialControls(text),
        ],
      ),
    );
  }

  Widget _buildVector3Controls(_ArtTextObject text) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _buildDoubleBox(
                label: 'X',
                value: text.options.x,
                min: -50,
                max: 50,
                onChanged: (double value) {
                  _updateObjectOptions(text, (options) {
                    return options.copyWith(x: value);
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDoubleBox(
                label: 'Y',
                value: text.options.y,
                min: -30,
                max: 30,
                onChanged: (double value) {
                  _updateObjectOptions(text, (options) {
                    return options.copyWith(y: value);
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDoubleBox(
                label: 'Z',
                value: text.options.z,
                min: -30,
                max: 30,
                onChanged: (double value) {
                  _updateObjectOptions(text, (options) {
                    return options.copyWith(z: value);
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildMaterialControls(_ArtTextObject text) {
    return Expander(
      initiallyExpanded: true,
      header: const Text('材质 / 贴图 / 高光'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InfoLabel(
            label: '材质预设',
            child: ComboBox<String>(
              placeholder: const Text('选择预设并应用'),
              isExpanded: true,
              items: _materialPresets.keys
                  .map(
                    (name) =>
                        ComboBoxItem<String>(value: name, child: Text(name)),
                  )
                  .toList(growable: false),
              onChanged: (String? value) {
                final _TextMaterials? preset = value == null
                    ? null
                    : _materialPresets[value];
                if (preset == null) {
                  return;
                }
                _updateObjectOptions(text, (options) {
                  return options.copyWith(materials: preset.clone());
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          InfoLabel(
            label: '叠加高光',
            child: ComboBox<String>(
              value: text.options.overlay,
              isExpanded: true,
              items: _kOverlayChoices
                  .map(
                    (choice) => ComboBoxItem<String>(
                      value: choice.value,
                      child: Text(choice.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (String? value) {
                _updateObjectOptions(text, (options) {
                  return options.copyWith(overlay: value ?? '');
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Button(
                onPressed: _importMaterialForSelected,
                child: const Text('导入材质'),
              ),
              Button(
                onPressed: _exportMaterialForSelected,
                child: const Text('导出材质'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final String face in _kMaterialFaces) ...<Widget>[
            _buildFaceMaterialEditor(text, face),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildFaceMaterialEditor(_ArtTextObject text, String face) {
    final _MaterialOption option = text.options.materials.face(face);
    return Expander(
      header: Row(
        children: <Widget>[
          _MaterialSwatch(option: option),
          const SizedBox(width: 8),
          Text(_kMaterialFaceLabels[face] ?? face),
        ],
      ),
      contentPadding: const EdgeInsets.all(10),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InfoLabel(
            label: '模式',
            child: ComboBox<String>(
              value: option.mode,
              isExpanded: true,
              items: const <ComboBoxItem<String>>[
                ComboBoxItem<String>(value: 'color', child: Text('纯色')),
                ComboBoxItem<String>(value: 'gradient', child: Text('渐变')),
                ComboBoxItem<String>(value: 'image', child: Text('贴图')),
              ],
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }
                _updateObjectOptions(text, (options) {
                  return options.copyWith(
                    materials: options.materials.copyWithFace(
                      face,
                      (current) => current.withMode(value),
                    ),
                  );
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          if (option.mode == 'color')
            _buildColorField(face: face, label: '颜色', value: option.color),
          if (option.mode == 'gradient') ...<Widget>[
            _buildColorField(
              face: face,
              label: '起始色',
              value: option.colorGradualStart,
              field: 'start',
            ),
            const SizedBox(height: 8),
            _buildColorField(
              face: face,
              label: '结束色',
              value: option.colorGradualEnd,
              field: 'end',
            ),
            _buildNumberSlider(
              label: '重复',
              value: option.repeat,
              min: 0.1,
              max: 10,
              step: 0.1,
              onChanged: (double value) {
                _updateSelectedMaterial(
                  face,
                  (current) => current.copyWith(repeat: value),
                );
              },
            ),
            _buildNumberSlider(
              label: '偏移',
              value: option.offset,
              min: 0,
              max: 10,
              step: 0.1,
              onChanged: (double value) {
                _updateSelectedMaterial(
                  face,
                  (current) => current.copyWith(offset: value),
                );
              },
            ),
          ],
          if (option.mode == 'image') ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    option.image.isEmpty ? '尚未选择贴图' : '已嵌入 Data URI 贴图',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Button(
                  onPressed: () => _importImageForMaterial(face),
                  child: const Text('上传'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildNumberSlider(
              label: '重复 X',
              value: option.repeatX,
              min: 0.005,
              max: 2,
              step: 0.005,
              onChanged: (double value) {
                _updateSelectedMaterial(
                  face,
                  (current) => current.copyWith(repeatX: value),
                );
              },
            ),
            _buildNumberSlider(
              label: '重复 Y',
              value: option.repeatY,
              min: 0.005,
              max: 2,
              step: 0.005,
              onChanged: (double value) {
                _updateSelectedMaterial(
                  face,
                  (current) => current.copyWith(repeatY: value),
                );
              },
            ),
            _buildNumberSlider(
              label: '偏移 X',
              value: option.offsetX,
              min: 0,
              max: 10,
              step: 0.01,
              onChanged: (double value) {
                _updateSelectedMaterial(
                  face,
                  (current) => current.copyWith(offsetX: value),
                );
              },
            ),
            _buildNumberSlider(
              label: '偏移 Y',
              value: option.offsetY,
              min: 0,
              max: 10,
              step: 0.01,
              onChanged: (double value) {
                _updateSelectedMaterial(
                  face,
                  (current) => current.copyWith(offsetY: value),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColorField({
    required String face,
    required String label,
    required String value,
    String field = 'color',
  }) {
    return InfoLabel(
      label: label,
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: () => _pickColorForFace(face, field),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _parseColor(value) ?? const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0x55000000)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextBox(
              placeholder: value,
              onSubmitted: (String raw) {
                final String next = raw.trim().isEmpty ? '#ffffff' : raw.trim();
                _updateSelectedMaterial(face, (option) {
                  return switch (field) {
                    'start' => option.copyWith(colorGradualStart: next),
                    'end' => option.copyWith(colorGradualEnd: next),
                    _ => option.copyWith(color: next),
                  };
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    final double clamped = value.clamp(min, max).toDouble();
    final int divisions = math.max(1, ((max - min) / step).round());
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InfoLabel(
        label: '$label ${_formatNumber(value)}',
        child: Row(
          children: <Widget>[
            Expanded(
              child: Slider(
                min: min,
                max: max,
                divisions: divisions > 1000 ? null : divisions,
                value: clamped,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: NumberBox<double>(
                value: value,
                min: min,
                max: max,
                smallChange: step,
                precision: step < 0.01 ? 3 : 2,
                clearButton: false,
                onChanged: (double? next) {
                  if (next != null) {
                    onChanged(next.clamp(min, max).toDouble());
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoubleBox({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return InfoLabel(
      label: label,
      child: NumberBox<double>(
        value: value,
        min: min,
        max: max,
        smallChange: 0.1,
        precision: 2,
        clearButton: false,
        onChanged: (double? next) {
          if (next != null) {
            onChanged(next.clamp(min, max).toDouble());
          }
        },
      ),
    );
  }

  Widget _buildIntBox({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return InfoLabel(
      label: label,
      child: NumberBox<int>(
        value: value,
        min: min,
        max: max,
        smallChange: 16,
        clearButton: false,
        onChanged: (int? next) {
          if (next != null) {
            onChanged(next.clamp(min, max).toInt());
          }
        },
      ),
    );
  }

  void _updateObjectOptions(
    _ArtTextObject text,
    _TextOptions Function(_TextOptions) update,
  ) {
    _mutate(() {
      text.options = update(text.options);
    });
  }

  String _safeProjectName() {
    final String joined = _texts
        .map((text) => text.content.trim())
        .where((text) => text.isNotEmpty)
        .join('-');
    final String safe = _sanitizeFileName(
      joined.isEmpty ? 'cube-3d-text' : joined,
    );
    return safe.length > 30 ? safe.substring(0, 30) : safe;
  }

  String _uniqueFontId(String requested) {
    final String base = requested.trim().isEmpty
        ? 'Custom Font'
        : requested.trim();
    if (!_fonts.any((font) => font.id == base)) {
      return base;
    }
    int index = 2;
    while (_fonts.any((font) => font.id == '$base $index')) {
      index++;
    }
    return '$base $index';
  }

  String _fontIdFromJson(String fontJson, String fileName) {
    try {
      final Object? decoded = jsonDecode(fontJson);
      if (decoded is Map<String, Object?>) {
        final Object? familyName = decoded['familyName'];
        if (familyName != null && familyName.toString().trim().isNotEmpty) {
          return familyName.toString().trim();
        }
      }
    } catch (_) {
      // The Rust side will report invalid font JSON during mesh generation.
    }
    return p.basenameWithoutExtension(fileName);
  }
}

class _CubeFontAsset {
  const _CubeFontAsset({
    required this.id,
    required this.json,
    required this.fileName,
    required this.builtin,
  });

  final String id;
  final String json;
  final String fileName;
  final bool builtin;
}

class _ArtTextObject {
  _ArtTextObject({
    required this.id,
    required this.content,
    required this.options,
    this.fontId,
  });

  final String id;
  String content;
  String? fontId;
  _TextOptions options;

  cube_text.CubeTextObject toCubeTextObject() {
    return cube_text.CubeTextObject(
      content: content,
      fontId: fontId ?? '',
      opts: options.toCubeTextOptions(),
    );
  }

  Map<String, Object?> toWorkspaceJson() {
    final Map<String, Object?> json = <String, Object?>{
      'content': content,
      'opts': options.toWorkspaceJson(),
      'position': <num>[0, 0, 0],
      'rotation': <num>[0, 0, 0],
    };
    if (fontId != null && fontId!.isNotEmpty) {
      json['fontId'] = fontId;
    }
    return json;
  }

  static _ArtTextObject fromWorkspaceJson(Map<String, Object?> json) {
    final Object? opts = json['opts'];
    return _ArtTextObject(
      id: _newObjectId(),
      content: json['content']?.toString() ?? '',
      fontId: _emptyToNull(json['fontId']?.toString()),
      options: opts is Map<String, Object?>
          ? _TextOptions.fromJson(opts)
          : _TextOptions.defaults(),
    );
  }
}

class _TextOptions {
  const _TextOptions({
    required this.size,
    required this.depth,
    required this.x,
    required this.y,
    required this.z,
    required this.rotY,
    required this.rotX,
    required this.rotZ,
    required this.materials,
    required this.outlineWidth,
    required this.letterSpacing,
    required this.spacingWidth,
    required this.overlay,
  });

  factory _TextOptions.defaults() {
    return _TextOptions(
      size: 5,
      depth: 3,
      x: 0,
      y: 0,
      z: 0,
      rotY: 0,
      rotX: 0,
      rotZ: 0,
      materials: _defaultBlueMaterials(),
      outlineWidth: 0.5,
      letterSpacing: 1.5,
      spacingWidth: 0.2,
      overlay: '',
    );
  }

  factory _TextOptions.fromJson(Map<String, Object?> json) {
    final Object? materialsJson = json['materials'];
    return _TextOptions(
      size: _jsonDouble(json, 'size', 5),
      depth: _jsonDouble(json, 'depth', 3),
      x: _jsonDouble(json, 'x', 0),
      y: _jsonDouble(json, 'y', 0),
      z: _jsonDouble(json, 'z', 0),
      rotY: _jsonDouble(json, 'rotY', 0),
      rotX: _jsonDouble(json, 'rotX', 0),
      rotZ: _jsonDouble(json, 'rotZ', 0),
      materials: materialsJson is Map<String, Object?>
          ? _TextMaterials.fromJson(materialsJson)
          : _defaultBlueMaterials(),
      outlineWidth: _jsonDouble(json, 'outlineWidth', 0.5),
      letterSpacing: _jsonDouble(json, 'letterSpacing', 1.5),
      spacingWidth: _jsonDouble(json, 'spacingWidth', 0.2),
      overlay: _overlayName(json['overlay']),
    );
  }

  final double size;
  final double depth;
  final double x;
  final double y;
  final double z;
  final double rotY;
  final double rotX;
  final double rotZ;
  final _TextMaterials materials;
  final double outlineWidth;
  final double letterSpacing;
  final double spacingWidth;
  final String overlay;

  _TextOptions copyWith({
    double? size,
    double? depth,
    double? x,
    double? y,
    double? z,
    double? rotY,
    double? rotX,
    double? rotZ,
    _TextMaterials? materials,
    double? outlineWidth,
    double? letterSpacing,
    double? spacingWidth,
    String? overlay,
  }) {
    return _TextOptions(
      size: size ?? this.size,
      depth: depth ?? this.depth,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      rotY: rotY ?? this.rotY,
      rotX: rotX ?? this.rotX,
      rotZ: rotZ ?? this.rotZ,
      materials: materials ?? this.materials,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      spacingWidth: spacingWidth ?? this.spacingWidth,
      overlay: overlay ?? this.overlay,
    );
  }

  cube_text.CubeTextOptions toCubeTextOptions() {
    return cube_text.CubeTextOptions(
      size: size,
      depth: depth,
      x: x,
      y: y,
      z: z,
      rotY: rotY,
      rotX: rotX,
      rotZ: rotZ,
      outlineWidth: outlineWidth,
      letterSpacing: letterSpacing,
      spacingWidth: spacingWidth,
      overlay: overlay,
      materials: materials.toCubeTextMaterials(),
    );
  }

  Map<String, Object?> toWorkspaceJson() {
    final Map<String, Object?> json = <String, Object?>{
      'size': size,
      'depth': depth,
      'x': x,
      'y': y,
      'z': z,
      'rotY': rotY,
      'rotX': rotX,
      'rotZ': rotZ,
      'materials': materials.toJson(),
      'outlineWidth': outlineWidth,
      'letterSpacing': letterSpacing,
      'spacingWidth': spacingWidth,
    };
    if (overlay.isNotEmpty) {
      json['overlay'] = overlay;
    }
    return json;
  }
}

class _TextMaterials {
  const _TextMaterials({
    required this.front,
    required this.back,
    required this.up,
    required this.down,
    required this.left,
    required this.right,
    required this.outline,
  });

  factory _TextMaterials.fromJson(Map<String, Object?> json) {
    _MaterialOption parse(String key, _MaterialOption fallback) {
      final Object? raw = json[key];
      return raw is Map<String, Object?>
          ? _MaterialOption.fromJson(raw, fallback)
          : fallback;
    }

    final _TextMaterials fallback = _defaultBlueMaterials();
    return _TextMaterials(
      front: parse('front', fallback.front),
      back: parse('back', fallback.back),
      up: parse('up', fallback.up),
      down: parse('down', fallback.down),
      left: parse('left', fallback.left),
      right: parse('right', fallback.right),
      outline: parse('outline', fallback.outline),
    );
  }

  final _MaterialOption front;
  final _MaterialOption back;
  final _MaterialOption up;
  final _MaterialOption down;
  final _MaterialOption left;
  final _MaterialOption right;
  final _MaterialOption outline;

  Iterable<_MaterialOption> get options sync* {
    yield front;
    yield back;
    yield up;
    yield down;
    yield left;
    yield right;
    yield outline;
  }

  _TextMaterials clone() => _TextMaterials.fromJson(toJson());

  _MaterialOption face(String face) {
    return switch (face) {
      'front' => front,
      'back' => back,
      'up' => up,
      'down' => down,
      'left' => left,
      'right' => right,
      'outline' => outline,
      _ => front,
    };
  }

  _TextMaterials copyWithFace(
    String face,
    _MaterialOption Function(_MaterialOption current) update,
  ) {
    return _TextMaterials(
      front: face == 'front' ? update(front) : front,
      back: face == 'back' ? update(back) : back,
      up: face == 'up' ? update(up) : up,
      down: face == 'down' ? update(down) : down,
      left: face == 'left' ? update(left) : left,
      right: face == 'right' ? update(right) : right,
      outline: face == 'outline' ? update(outline) : outline,
    );
  }

  cube_text.CubeTextMaterials toCubeTextMaterials() {
    return cube_text.CubeTextMaterials(
      front: front.toCubeTextMaterialOption(),
      back: back.toCubeTextMaterialOption(),
      up: up.toCubeTextMaterialOption(),
      down: down.toCubeTextMaterialOption(),
      left: left.toCubeTextMaterialOption(),
      right: right.toCubeTextMaterialOption(),
      outline: outline.toCubeTextMaterialOption(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'front': front.toJson(),
      'back': back.toJson(),
      'up': up.toJson(),
      'down': down.toJson(),
      'left': left.toJson(),
      'right': right.toJson(),
      'outline': outline.toJson(),
    };
  }
}

class _MaterialOption {
  const _MaterialOption({
    required this.mode,
    required this.color,
    required this.colorGradualStart,
    required this.colorGradualEnd,
    required this.repeat,
    required this.offset,
    required this.image,
    required this.repeatX,
    required this.repeatY,
    required this.offsetX,
    required this.offsetY,
  });

  factory _MaterialOption.color(String color) {
    return _MaterialOption(
      mode: 'color',
      color: color,
      colorGradualStart: '#ffffff',
      colorGradualEnd: '#000000',
      repeat: 1,
      offset: 0,
      image: '',
      repeatX: 0.1,
      repeatY: 0.1,
      offsetX: 0,
      offsetY: 0,
    );
  }

  factory _MaterialOption.gradient(String start, String end) {
    return _MaterialOption(
      mode: 'gradient',
      color: '#ffffff',
      colorGradualStart: start,
      colorGradualEnd: end,
      repeat: 1,
      offset: 0,
      image: '',
      repeatX: 0.1,
      repeatY: 0.1,
      offsetX: 0,
      offsetY: 0,
    );
  }

  factory _MaterialOption.fromJson(
    Map<String, Object?> json,
    _MaterialOption fallback,
  ) {
    return fallback.copyWith(
      mode: json['mode']?.toString() ?? fallback.mode,
      color: json['color']?.toString() ?? fallback.color,
      colorGradualStart:
          json['colorGradualStart']?.toString() ?? fallback.colorGradualStart,
      colorGradualEnd:
          json['colorGradualEnd']?.toString() ?? fallback.colorGradualEnd,
      repeat: _jsonDouble(json, 'repeat', fallback.repeat),
      offset: _jsonDouble(json, 'offset', fallback.offset),
      image: json['image']?.toString() ?? fallback.image,
      repeatX: _jsonDouble(json, 'repeatX', fallback.repeatX),
      repeatY: _jsonDouble(json, 'repeatY', fallback.repeatY),
      offsetX: _jsonDouble(json, 'offsetX', fallback.offsetX),
      offsetY: _jsonDouble(json, 'offsetY', fallback.offsetY),
    );
  }

  final String mode;
  final String color;
  final String colorGradualStart;
  final String colorGradualEnd;
  final double repeat;
  final double offset;
  final String image;
  final double repeatX;
  final double repeatY;
  final double offsetX;
  final double offsetY;

  _MaterialOption withMode(String mode) {
    if (mode == this.mode) {
      return this;
    }
    return copyWith(
      mode: mode,
      color: color.isEmpty ? '#ffffff' : color,
      colorGradualStart: colorGradualStart.isEmpty
          ? '#ffffff'
          : colorGradualStart,
      colorGradualEnd: colorGradualEnd.isEmpty ? '#000000' : colorGradualEnd,
      image: image,
    );
  }

  _MaterialOption copyWith({
    String? mode,
    String? color,
    String? colorGradualStart,
    String? colorGradualEnd,
    double? repeat,
    double? offset,
    String? image,
    double? repeatX,
    double? repeatY,
    double? offsetX,
    double? offsetY,
  }) {
    return _MaterialOption(
      mode: mode ?? this.mode,
      color: color ?? this.color,
      colorGradualStart: colorGradualStart ?? this.colorGradualStart,
      colorGradualEnd: colorGradualEnd ?? this.colorGradualEnd,
      repeat: repeat ?? this.repeat,
      offset: offset ?? this.offset,
      image: image ?? this.image,
      repeatX: repeatX ?? this.repeatX,
      repeatY: repeatY ?? this.repeatY,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
    );
  }

  cube_text.CubeTextMaterialOption toCubeTextMaterialOption() {
    return cube_text.CubeTextMaterialOption(
      mode: mode,
      color: color,
      colorGradualStart: colorGradualStart,
      colorGradualEnd: colorGradualEnd,
      repeat: repeat,
      offset: offset,
      image: image,
      repeatX: repeatX,
      repeatY: repeatY,
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }

  Map<String, Object?> toJson() {
    return switch (mode) {
      'gradient' => <String, Object?>{
        'mode': 'gradient',
        'colorGradualStart': colorGradualStart,
        'colorGradualEnd': colorGradualEnd,
        'repeat': repeat,
        'offset': offset,
      },
      'image' => <String, Object?>{
        'mode': 'image',
        'image': image,
        'repeatX': repeatX,
        'repeatY': repeatY,
        'offsetX': offsetX,
        'offsetY': offsetY,
      },
      _ => <String, Object?>{'mode': 'color', 'color': color},
    };
  }
}

class _WorkspaceImport {
  const _WorkspaceImport({
    required this.globalFontId,
    required this.texts,
    required this.fonts,
  });

  final String globalFontId;
  final List<_ArtTextObject> texts;
  final List<_CubeFontAsset> fonts;

  static _WorkspaceImport parse(String jsonText) {
    final Object? decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('不是有效的工作区 JSON。');
    }
    final Object? rawData = decoded['data'];
    final Map<String, Object?> data = rawData is Map<String, Object?>
        ? rawData
        : decoded;
    final Object? rawTexts = data['texts'];
    final List<_ArtTextObject> texts = rawTexts is List<Object?>
        ? rawTexts
              .whereType<Map<String, Object?>>()
              .map(_ArtTextObject.fromWorkspaceJson)
              .toList(growable: false)
        : const <_ArtTextObject>[];
    final Object? rawFonts = data['fonts'] ?? decoded['fonts'];
    final List<_CubeFontAsset> fonts = rawFonts is List<Object?>
        ? rawFonts
              .whereType<Map<String, Object?>>()
              .map((font) {
                return _CubeFontAsset(
                  id: font['id']?.toString() ?? 'Custom Font',
                  json: font['json']?.toString() ?? '',
                  fileName: font['fileName']?.toString() ?? 'font.json',
                  builtin: false,
                );
              })
              .where((font) => font.id.isNotEmpty && font.json.isNotEmpty)
              .toList()
        : const <_CubeFontAsset>[];
    return _WorkspaceImport(
      globalFontId: data['fontId']?.toString() ?? 'Fusion Pixel 10px',
      texts: texts,
      fonts: fonts,
    );
  }
}

class _MaterialSwatch extends StatelessWidget {
  const _MaterialSwatch({required this.option});

  final _MaterialOption option;

  @override
  Widget build(BuildContext context) {
    final Decoration decoration;
    if (option.mode == 'gradient') {
      decoration = BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            _parseColor(option.colorGradualStart) ?? const Color(0xFFFFFFFF),
            _parseColor(option.colorGradualEnd) ?? const Color(0xFF000000),
          ],
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0x33000000)),
      );
    } else if (option.mode == 'image') {
      decoration = BoxDecoration(
        color: const Color(0xFF7EA6C8),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0x33000000)),
      );
    } else {
      decoration = BoxDecoration(
        color: _parseColor(option.color) ?? const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0x33000000)),
      );
    }
    return Container(width: 18, height: 18, decoration: decoration);
  }
}

class _CubeTextRasterPreview extends StatefulWidget {
  const _CubeTextRasterPreview({
    required this.scene,
    required this.texts,
    required this.width,
    required this.height,
    required this.pixelRatio,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.fov,
    required this.transparentBackground,
    required this.materialImages,
  });

  final cube_text.CubeTextScene scene;
  final List<_ArtTextObject> texts;
  final int width;
  final int height;
  final double pixelRatio;
  final double yaw;
  final double pitch;
  final double zoom;
  final double fov;
  final bool transparentBackground;
  final Map<String, ui.Image> materialImages;

  @override
  State<_CubeTextRasterPreview> createState() => _CubeTextRasterPreviewState();
}

class _CubeTextRasterPreviewState extends State<_CubeTextRasterPreview> {
  ui.Image? _image;
  int _renderSerial = 0;
  bool _rendering = false;
  bool _renderQueued = false;

  @override
  void initState() {
    super.initState();
    _scheduleRender();
  }

  @override
  void didUpdateWidget(covariant _CubeTextRasterPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene != widget.scene ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height ||
        oldWidget.pixelRatio != widget.pixelRatio ||
        oldWidget.yaw != widget.yaw ||
        oldWidget.pitch != widget.pitch ||
        oldWidget.zoom != widget.zoom ||
        oldWidget.fov != widget.fov ||
        oldWidget.transparentBackground != widget.transparentBackground ||
        oldWidget.materialImages.length != widget.materialImages.length) {
      _scheduleRender();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    _renderSerial++;
    super.dispose();
  }

  void _scheduleRender() {
    if (_rendering) {
      _renderQueued = true;
      return;
    }
    unawaited(_render());
  }

  Future<void> _render() async {
    _rendering = true;
    final int serial = ++_renderSerial;
    late final ui.Image image;
    try {
      image = await _renderCubeTextRasterImage(
        scene: widget.scene,
        texts: widget.texts,
        width: widget.width,
        height: widget.height,
        yaw: widget.yaw,
        pitch: widget.pitch,
        zoom: widget.zoom,
        fov: widget.fov,
        transparentBackground: widget.transparentBackground,
        materialImages: widget.materialImages,
        checkerboardScale: widget.pixelRatio,
        antialiasSamples: _kRasterAntialiasSamples,
      );
    } finally {
      _rendering = false;
    }
    if (!mounted || serial != _renderSerial) {
      image.dispose();
      _flushQueuedRender();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
    });
    _flushQueuedRender();
  }

  void _flushQueuedRender() {
    if (!_renderQueued || !mounted) {
      return;
    }
    _renderQueued = false;
    _scheduleRender();
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? image = _image;
    if (image == null) {
      return CustomPaint(
        painter: _CheckerboardPainter(),
        child: const SizedBox.expand(),
      );
    }
    return SizedBox.expand(
      child: RawImage(
        image: image,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    _paintCheckerboard(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) => false;
}

Future<ui.Image> _renderCubeTextRasterImage({
  required cube_text.CubeTextScene scene,
  required List<_ArtTextObject> texts,
  required int width,
  required int height,
  required double yaw,
  required double pitch,
  required double zoom,
  required double fov,
  required bool transparentBackground,
  required Map<String, ui.Image> materialImages,
  double checkerboardScale = 1,
  int antialiasSamples = 1,
}) async {
  final int safeWidth = math.max(1, width);
  final int safeHeight = math.max(1, height);
  final int samples = math.max(1, antialiasSamples).toInt();
  final int rasterWidth = safeWidth * samples;
  final int rasterHeight = safeHeight * samples;
  final Uint8List pixels = Uint8List(rasterWidth * rasterHeight * 4);
  if (!transparentBackground) {
    _fillCheckerboardPixels(
      pixels,
      rasterWidth,
      rasterHeight,
      checkerboardScale * samples,
    );
  }
  if (scene.positions.isEmpty || scene.indices.isEmpty) {
    return _finishRasterImage(
      pixels,
      rasterWidth,
      rasterHeight,
      safeWidth,
      safeHeight,
    );
  }

  final Map<String, _RasterImagePixels> imagePixels = await _rasterImagePixels(
    materialImages,
  );
  final _Bounds3 bounds = _Bounds3.fromScene(scene);
  final _CameraProjector projector = _CameraProjector(
    bounds: bounds,
    positions: scene.positions,
    size: ui.Size(rasterWidth.toDouble(), rasterHeight.toDouble()),
    yaw: yaw,
    pitch: pitch,
    zoom: zoom,
    fov: fov,
  );
  final List<_ProjectedTriangle> triangles = _projectSceneTriangles(
    scene,
    projector,
  );

  _rasterizeTrianglePass(
    pixels: pixels,
    width: rasterWidth,
    height: rasterHeight,
    scene: scene,
    triangles: triangles,
    outline: true,
    imagePixels: imagePixels,
  );
  _rasterizeTrianglePass(
    pixels: pixels,
    width: rasterWidth,
    height: rasterHeight,
    scene: scene,
    triangles: triangles,
    outline: false,
    imagePixels: imagePixels,
  );
  return _finishRasterImage(
    pixels,
    rasterWidth,
    rasterHeight,
    safeWidth,
    safeHeight,
  );
}

List<_ProjectedTriangle> _projectSceneTriangles(
  cube_text.CubeTextScene scene,
  _CameraProjector projector,
) {
  final List<_ProjectedTriangle> triangles = <_ProjectedTriangle>[];
  final Float32List positions = scene.positions;
  final Float32List normals = scene.normals;
  final Uint32List indices = scene.indices;
  final Int32List materialIndices = scene.materialIndices;
  for (int triIndex = 0; triIndex + 2 < indices.length; triIndex += 3) {
    final int i0 = indices[triIndex] * 3;
    final int i1 = indices[triIndex + 1] * 3;
    final int i2 = indices[triIndex + 2] * 3;
    if (i2 + 2 >= positions.length) {
      continue;
    }
    final _ProjectedPoint? p0 = projector.project(
      positions[i0],
      positions[i0 + 1],
      positions[i0 + 2],
    );
    final _ProjectedPoint? p1 = projector.project(
      positions[i1],
      positions[i1 + 1],
      positions[i1 + 2],
    );
    final _ProjectedPoint? p2 = projector.project(
      positions[i2],
      positions[i2 + 1],
      positions[i2 + 2],
    );
    if (p0 == null || p1 == null || p2 == null) {
      continue;
    }
    if (_screenArea(p0.offset, p1.offset, p2.offset).abs() < 0.05) {
      continue;
    }
    final int vertexIndex = indices[triIndex] * 3;
    final _Vec3 normal = vertexIndex + 2 < normals.length
        ? _Vec3(
            normals[vertexIndex],
            normals[vertexIndex + 1],
            normals[vertexIndex + 2],
          ).normalized()
        : const _Vec3(0, 0, 1);
    final int logicalTri = triIndex ~/ 3;
    final int materialIndex = logicalTri < materialIndices.length
        ? materialIndices[logicalTri].clamp(0, scene.materials.length - 1)
        : 0;
    triangles.add(
      _ProjectedTriangle(
        points: <_ProjectedPoint>[p0, p1, p2],
        normal: normal,
        materialIndex: materialIndex,
        depth: math.max(p0.depth, math.max(p1.depth, p2.depth)),
      ),
    );
  }
  return triangles;
}

void _rasterizeTrianglePass({
  required Uint8List pixels,
  required int width,
  required int height,
  required cube_text.CubeTextScene scene,
  required List<_ProjectedTriangle> triangles,
  required bool outline,
  required Map<String, _RasterImagePixels> imagePixels,
}) {
  final Float32List depthBuffer = Float32List(width * height);
  for (int i = 0; i < depthBuffer.length; i++) {
    depthBuffer[i] = double.negativeInfinity;
  }

  final List<_ProjectedTriangle> visibleTriangles = <_ProjectedTriangle>[];
  final Map<int, ui.Rect> materialBounds = <int, ui.Rect>{};
  for (final _ProjectedTriangle triangle in triangles) {
    final int materialIndex = triangle.materialIndex.clamp(
      0,
      scene.materials.length - 1,
    );
    final cube_text.CubeTextSceneMaterial material =
        scene.materials[materialIndex];
    if ((material.slot == 'outline') != outline) {
      continue;
    }
    if (!_isTriangleVisibleForMaterial(triangle, material)) {
      continue;
    }
    visibleTriangles.add(triangle);
    materialBounds[materialIndex] =
        materialBounds[materialIndex]?.expandToInclude(triangle.screenBounds) ??
        triangle.screenBounds;
  }

  for (final _ProjectedTriangle triangle in visibleTriangles) {
    final int materialIndex = triangle.materialIndex.clamp(
      0,
      scene.materials.length - 1,
    );
    _rasterizeTriangle(
      pixels: pixels,
      depthBuffer: depthBuffer,
      width: width,
      height: height,
      triangle: triangle,
      material: scene.materials[materialIndex],
      materialBounds: materialBounds[materialIndex] ?? triangle.screenBounds,
      imagePixels: imagePixels,
    );
  }
}

bool _isTriangleVisibleForMaterial(
  _ProjectedTriangle triangle,
  cube_text.CubeTextSceneMaterial material,
) {
  final double area = _screenArea(
    triangle.points[0].offset,
    triangle.points[1].offset,
    triangle.points[2].offset,
  );
  if (material.slot == 'outline') {
    return area > 0;
  }
  return area < 0;
}

void _rasterizeTriangle({
  required Uint8List pixels,
  required Float32List depthBuffer,
  required int width,
  required int height,
  required _ProjectedTriangle triangle,
  required cube_text.CubeTextSceneMaterial material,
  required ui.Rect materialBounds,
  required Map<String, _RasterImagePixels> imagePixels,
}) {
  final _ProjectedPoint p0 = triangle.points[0];
  final _ProjectedPoint p1 = triangle.points[1];
  final _ProjectedPoint p2 = triangle.points[2];
  final double x0 = p0.offset.dx;
  final double y0 = p0.offset.dy;
  final double x1 = p1.offset.dx;
  final double y1 = p1.offset.dy;
  final double x2 = p2.offset.dx;
  final double y2 = p2.offset.dy;
  final double denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2);
  if (denom.abs() <= 1e-9) {
    return;
  }

  final int minX = math
      .max(0, triangle.screenBounds.left.floor())
      .clamp(0, width - 1)
      .toInt();
  final int maxX = math
      .min(width - 1, triangle.screenBounds.right.ceil())
      .clamp(0, width - 1)
      .toInt();
  final int minY = math
      .max(0, triangle.screenBounds.top.floor())
      .clamp(0, height - 1)
      .toInt();
  final int maxY = math
      .min(height - 1, triangle.screenBounds.bottom.ceil())
      .clamp(0, height - 1)
      .toInt();
  if (maxX < minX || maxY < minY) {
    return;
  }

  for (int y = minY; y <= maxY; y++) {
    final double py = y + 0.5;
    for (int x = minX; x <= maxX; x++) {
      final double px = x + 0.5;
      final double w0 = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / denom;
      final double w1 = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / denom;
      final double w2 = 1.0 - w0 - w1;
      if (w0 < -1e-5 || w1 < -1e-5 || w2 < -1e-5) {
        continue;
      }
      final double depth = w0 / p0.depth + w1 / p1.depth + w2 / p2.depth;
      final int pixelIndex = y * width + x;
      if (depth <= depthBuffer[pixelIndex]) {
        continue;
      }
      depthBuffer[pixelIndex] = depth;
      final int color = _rasterMaterialColor(
        material,
        materialBounds,
        px,
        py,
        imagePixels,
      );
      final int byteIndex = pixelIndex * 4;
      pixels[byteIndex] = (color >> 24) & 0xFF;
      pixels[byteIndex + 1] = (color >> 16) & 0xFF;
      pixels[byteIndex + 2] = (color >> 8) & 0xFF;
      pixels[byteIndex + 3] = color & 0xFF;
    }
  }
}

int _rasterMaterialColor(
  cube_text.CubeTextSceneMaterial material,
  ui.Rect bounds,
  double x,
  double y,
  Map<String, _RasterImagePixels> imagePixels,
) {
  final cube_text.CubeTextMaterialOption option = material.option;
  if (option.mode == 'gradient') {
    final Color start =
        _parseColor(option.colorGradualStart) ?? const Color(0xFFFFFFFF);
    final Color end = _parseColor(option.colorGradualEnd) ?? start;
    final double repeat = option.repeat <= 0 ? 1 : option.repeat;
    final double offset = option.offset % 1.0;
    final double y0 = bounds.top - bounds.height * offset;
    final double y1 = bounds.bottom / repeat + bounds.top * (1 - 1 / repeat);
    final double t = y1 == y0 ? 0 : ((y - y0) / (y1 - y0)).clamp(0.0, 1.0);
    return _lerpArgb(start, end, t);
  }
  if (option.mode == 'image') {
    final _RasterImagePixels? image = imagePixels[option.image];
    if (image != null) {
      return image.sample(
        x,
        y,
        repeatX: math.max(0.02, option.repeatX) * 24,
        repeatY: math.max(0.02, option.repeatY) * 24,
        offsetX: option.offsetX,
        offsetY: option.offsetY,
      );
    }
    return _rgbaInt(const Color(0xFF8CB7D5));
  }
  return _rgbaInt(_parseColor(option.color) ?? const Color(0xFFFFFFFF));
}

int _lerpArgb(Color a, Color b, double t) {
  final int av = a.toARGB32();
  final int bv = b.toARGB32();
  final int aa = (av >> 24) & 0xFF;
  final int ar = (av >> 16) & 0xFF;
  final int ag = (av >> 8) & 0xFF;
  final int ab = av & 0xFF;
  final int ba = (bv >> 24) & 0xFF;
  final int br = (bv >> 16) & 0xFF;
  final int bg = (bv >> 8) & 0xFF;
  final int bb = bv & 0xFF;
  final int outA = (aa + (ba - aa) * t).round().clamp(0, 255);
  final int outR = (ar + (br - ar) * t).round().clamp(0, 255);
  final int outG = (ag + (bg - ag) * t).round().clamp(0, 255);
  final int outB = (ab + (bb - ab) * t).round().clamp(0, 255);
  return (outR << 24) | (outG << 16) | (outB << 8) | outA;
}

int _rgbaInt(Color color) {
  final int value = color.toARGB32();
  final int a = (value >> 24) & 0xFF;
  final int r = (value >> 16) & 0xFF;
  final int g = (value >> 8) & 0xFF;
  final int b = value & 0xFF;
  return (r << 24) | (g << 16) | (b << 8) | a;
}

Future<Map<String, _RasterImagePixels>> _rasterImagePixels(
  Map<String, ui.Image> materialImages,
) async {
  final Map<String, _RasterImagePixels> result = <String, _RasterImagePixels>{};
  for (final MapEntry<String, ui.Image> entry in materialImages.entries) {
    final ByteData? data = await entry.value.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (data == null) {
      continue;
    }
    result[entry.key] = _RasterImagePixels(
      width: entry.value.width,
      height: entry.value.height,
      pixels: data.buffer.asUint8List(),
    );
  }
  return result;
}

class _RasterImagePixels {
  const _RasterImagePixels({
    required this.width,
    required this.height,
    required this.pixels,
  });

  final int width;
  final int height;
  final Uint8List pixels;

  int sample(
    double x,
    double y, {
    required double repeatX,
    required double repeatY,
    required double offsetX,
    required double offsetY,
  }) {
    final double u = _fract(x / repeatX + offsetX);
    final double v = _fract(y / repeatY + offsetY);
    final int sx = (u * width).floor().clamp(0, width - 1);
    final int sy = (v * height).floor().clamp(0, height - 1);
    final int index = (sy * width + sx) * 4;
    final int r = pixels[index];
    final int g = pixels[index + 1];
    final int b = pixels[index + 2];
    final int a = pixels[index + 3];
    return (r << 24) | (g << 16) | (b << 8) | a;
  }
}

double _fract(double value) => value - value.floorToDouble();

Future<ui.Image> _decodePixelsToImage(Uint8List pixels, int width, int height) {
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<ui.Image> _finishRasterImage(
  Uint8List pixels,
  int rasterWidth,
  int rasterHeight,
  int width,
  int height,
) async {
  final ui.Image image = await _decodePixelsToImage(
    pixels,
    rasterWidth,
    rasterHeight,
  );
  if (rasterWidth == width && rasterHeight == height) {
    return image;
  }
  final ui.Image downsampled = await _downsampleImage(image, width, height);
  image.dispose();
  return downsampled;
}

Future<ui.Image> _downsampleImage(ui.Image image, int width, int height) {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  final ui.Paint paint = ui.Paint()
    ..filterQuality = ui.FilterQuality.high
    ..isAntiAlias = true;
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    paint,
  );
  return recorder.endRecording().toImage(width, height);
}

void _fillCheckerboardPixels(
  Uint8List pixels,
  int width,
  int height,
  double scale,
) {
  const int white = 0xFFFFFFFF;
  const int square = 0xE3E8EFFF;
  final int cell = math.max(1, (18 * scale).round());
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final bool useSquare = ((x ~/ cell) + (y ~/ cell)).isEven;
      final int color = useSquare ? square : white;
      final int index = (y * width + x) * 4;
      pixels[index] = (color >> 24) & 0xFF;
      pixels[index + 1] = (color >> 16) & 0xFF;
      pixels[index + 2] = (color >> 8) & 0xFF;
      pixels[index + 3] = color & 0xFF;
    }
  }
}

// ignore: unused_element
class _CubeTextMeshPainter extends CustomPainter {
  const _CubeTextMeshPainter({
    required this.scene,
    required this.texts,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.fov,
    required this.transparentBackground,
    required this.materialImages,
  });

  final cube_text.CubeTextScene scene;
  final List<_ArtTextObject> texts;
  final double yaw;
  final double pitch;
  final double zoom;
  final double fov;
  final bool transparentBackground;
  final Map<String, ui.Image> materialImages;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (!transparentBackground) {
      _paintCheckerboard(canvas, size);
    }
    if (scene.positions.isEmpty || scene.indices.isEmpty) {
      return;
    }

    final _Bounds3 bounds = _Bounds3.fromScene(scene);
    final _CameraProjector projector = _CameraProjector(
      bounds: bounds,
      positions: scene.positions,
      size: size,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
      fov: fov,
    );
    final List<_ProjectedTriangle> triangles = <_ProjectedTriangle>[];
    final Float32List positions = scene.positions;
    final Float32List normals = scene.normals;
    final Uint32List indices = scene.indices;
    final Int32List materialIndices = scene.materialIndices;
    for (int triIndex = 0; triIndex + 2 < indices.length; triIndex += 3) {
      final int i0 = indices[triIndex] * 3;
      final int i1 = indices[triIndex + 1] * 3;
      final int i2 = indices[triIndex + 2] * 3;
      if (i2 + 2 >= positions.length) {
        continue;
      }
      final _ProjectedPoint? p0 = projector.project(
        positions[i0],
        positions[i0 + 1],
        positions[i0 + 2],
      );
      final _ProjectedPoint? p1 = projector.project(
        positions[i1],
        positions[i1 + 1],
        positions[i1 + 2],
      );
      final _ProjectedPoint? p2 = projector.project(
        positions[i2],
        positions[i2 + 1],
        positions[i2 + 2],
      );
      if (p0 == null || p1 == null || p2 == null) {
        continue;
      }
      final double area = _screenArea(p0.offset, p1.offset, p2.offset).abs();
      if (area < 0.05) {
        continue;
      }
      final int vertexIndex = indices[triIndex] * 3;
      final _Vec3 normal = vertexIndex + 2 < normals.length
          ? _Vec3(
              normals[vertexIndex],
              normals[vertexIndex + 1],
              normals[vertexIndex + 2],
            ).normalized()
          : const _Vec3(0, 0, 1);
      final int logicalTri = triIndex ~/ 3;
      final int materialIndex = logicalTri < materialIndices.length
          ? materialIndices[logicalTri].clamp(0, scene.materials.length - 1)
          : 0;
      triangles.add(
        _ProjectedTriangle(
          points: <_ProjectedPoint>[p0, p1, p2],
          normal: normal,
          materialIndex: materialIndex,
          depth: math.max(p0.depth, math.max(p1.depth, p2.depth)),
        ),
      );
    }

    triangles.sort((a, b) => b.depth.compareTo(a.depth));
    _paintTrianglePass(canvas, triangles, outline: true);
    _paintTrianglePass(canvas, triangles, outline: false);
  }

  void _paintTrianglePass(
    ui.Canvas canvas,
    List<_ProjectedTriangle> triangles, {
    required bool outline,
  }) {
    final List<_ProjectedTriangle> visibleTriangles = <_ProjectedTriangle>[];
    final Map<int, ui.Rect> materialBounds = <int, ui.Rect>{};
    for (final _ProjectedTriangle triangle in triangles) {
      final int materialIndex = triangle.materialIndex.clamp(
        0,
        scene.materials.length - 1,
      );
      final cube_text.CubeTextSceneMaterial material =
          scene.materials[materialIndex];
      if ((material.slot == 'outline') != outline) {
        continue;
      }
      if (!_isTriangleVisibleForMaterial(triangle, material)) {
        continue;
      }
      visibleTriangles.add(triangle);
      final ui.Rect rect = triangle.screenBounds;
      materialBounds[materialIndex] =
          materialBounds[materialIndex]?.expandToInclude(rect) ?? rect;
    }

    for (final _ProjectedTriangle triangle in visibleTriangles) {
      final int materialIndex = triangle.materialIndex.clamp(
        0,
        scene.materials.length - 1,
      );
      _paintTriangle(
        canvas,
        triangle,
        scene.materials[materialIndex],
        materialBounds[materialIndex] ?? triangle.screenBounds,
      );
    }
  }

  bool _isTriangleVisibleForMaterial(
    _ProjectedTriangle triangle,
    cube_text.CubeTextSceneMaterial material,
  ) {
    final double area = _screenArea(
      triangle.points[0].offset,
      triangle.points[1].offset,
      triangle.points[2].offset,
    );
    if (material.slot == 'outline') {
      return area > 0;
    }
    return area < 0;
  }

  void _paintTriangle(
    ui.Canvas canvas,
    _ProjectedTriangle triangle,
    cube_text.CubeTextSceneMaterial material,
    ui.Rect materialBounds,
  ) {
    final ui.Path path = ui.Path()
      ..moveTo(triangle.points[0].offset.dx, triangle.points[0].offset.dy)
      ..lineTo(triangle.points[1].offset.dx, triangle.points[1].offset.dy)
      ..lineTo(triangle.points[2].offset.dx, triangle.points[2].offset.dy)
      ..close();
    final ui.Rect rect = materialBounds;
    if (rect.isEmpty) {
      return;
    }
    final cube_text.CubeTextMaterialOption option = material.option;
    final ui.Paint paint = ui.Paint()
      ..style = ui.PaintingStyle.fill
      ..isAntiAlias = false;
    if (option.mode == 'gradient') {
      final Color start =
          _parseColor(option.colorGradualStart) ?? const Color(0xFFFFFFFF);
      final Color end = _parseColor(option.colorGradualEnd) ?? start;
      final double repeat = option.repeat <= 0 ? 1 : option.repeat;
      final double offset = option.offset % 1.0;
      paint.shader = ui.Gradient.linear(
        ui.Offset(rect.left, rect.top - rect.height * offset),
        ui.Offset(
          rect.left,
          rect.bottom / repeat + rect.top * (1 - 1 / repeat),
        ),
        <Color>[start, end],
      );
    } else if (option.mode == 'image' &&
        materialImages.containsKey(option.image)) {
      final ui.Image image = materialImages[option.image]!;
      final double sx = math.max(0.02, option.repeatX) * 24;
      final double sy = math.max(0.02, option.repeatY) * 24;
      final Float64List matrix = Float64List.fromList(<double>[
        sx,
        0,
        0,
        0,
        0,
        sy,
        0,
        0,
        0,
        0,
        1,
        0,
        option.offsetX * image.width,
        option.offsetY * image.height,
        0,
        1,
      ]);
      paint.shader = ui.ImageShader(
        image,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        matrix,
        filterQuality: ui.FilterQuality.none,
      );
    } else {
      final Color color = option.mode == 'image'
          ? const Color(0xFF8CB7D5)
          : (_parseColor(option.color) ?? const Color(0xFFFFFFFF));
      paint.color = color;
    }
    canvas.drawPath(path, paint);

    final int textIndex = triangle.materialIndex ~/ 7;
    final bool isFront = material.slot == 'front' || material.slot == 'outline';
    if (isFront && textIndex >= 0 && textIndex < texts.length) {
      _paintOverlay(canvas, path, rect, texts[textIndex].options.overlay);
    }
  }

  void _paintOverlay(
    ui.Canvas canvas,
    ui.Path path,
    ui.Rect rect,
    String overlay,
  ) {
    if (overlay.isEmpty || rect.isEmpty) {
      return;
    }
    canvas.save();
    canvas.clipPath(path);
    if (overlay.contains('highlightTop') ||
        overlay.contains('highlightTopBottom') ||
        overlay.contains('Glass')) {
      final ui.Paint paint = ui.Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          ui.Offset(rect.left, rect.top + rect.height * 0.4),
          <Color>[const Color(0x88FFFFFF), const Color(0x00FFFFFF)],
        );
      canvas.drawRect(rect, paint);
    }
    if (overlay.contains('highlightBottom') ||
        overlay.contains('highlightTopBottom')) {
      final ui.Paint paint = ui.Paint()
        ..shader = ui.Gradient.linear(
          ui.Offset(rect.left, rect.bottom - rect.height * 0.35),
          rect.bottomLeft,
          <Color>[const Color(0x00FFFFFF), const Color(0x66FFFFFF)],
        );
      canvas.drawRect(rect, paint);
    }
    if (overlay.contains('InnerStroke') ||
        overlay.contains('InnerHighlight') ||
        overlay.contains('Glass')) {
      final ui.Paint stroke = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, rect.shortestSide * 0.025)
        ..color = const Color(0x77FFFFFF);
      canvas.drawPath(path, stroke);
    }
    if (overlay.contains('Shine')) {
      final ui.Paint shine = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, rect.shortestSide * 0.08)
        ..color = const Color(0x66FFFFFF);
      for (
        double x = rect.left - rect.height;
        x < rect.right + rect.height;
        x += rect.width * 0.35
      ) {
        canvas.drawLine(
          ui.Offset(x, rect.bottom),
          ui.Offset(x + rect.height, rect.top),
          shine,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CubeTextMeshPainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.texts != texts ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.zoom != zoom ||
        oldDelegate.fov != fov ||
        oldDelegate.transparentBackground != transparentBackground ||
        oldDelegate.materialImages.length != materialImages.length;
  }
}

class _CameraProjector {
  _CameraProjector({
    required this.bounds,
    required Float32List positions,
    required this.size,
    required double yaw,
    required double pitch,
    required double zoom,
    required double fov,
  }) : _yawSin = math.sin(yaw * math.pi / 180),
       _yawCos = math.cos(yaw * math.pi / 180),
       _pitchSin = math.sin(pitch * math.pi / 180),
       _pitchCos = math.cos(pitch * math.pi / 180),
       _zoom = zoom.clamp(0.05, 20).toDouble(),
       _fov = fov {
    final _ProjectedFit fit = _computeFit(positions);
    _fitScale = fit.scale;
    _offsetDx = fit.dx;
    _offsetDy = fit.dy;
  }

  final _Bounds3 bounds;
  final ui.Size size;
  final double _yawSin;
  final double _yawCos;
  final double _pitchSin;
  final double _pitchCos;
  final double _zoom;
  final double _fov;
  late final double _fitScale;
  late final double _offsetDx;
  late final double _offsetDy;

  _ProjectedPoint? project(double x, double y, double z) {
    final _RawProjectedPoint? raw = _projectRaw(x, y, z);
    if (raw == null) {
      return null;
    }
    return _ProjectedPoint(
      offset: ui.Offset(
        _offsetDx + raw.x * _fitScale,
        _offsetDy + raw.y * _fitScale,
      ),
      depth: raw.depth,
    );
  }

  _ProjectedFit _computeFit(Float32List positions) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    for (int index = 0; index + 2 < positions.length; index += 3) {
      final _RawProjectedPoint? point = _projectRaw(
        positions[index],
        positions[index + 1],
        positions[index + 2],
      );
      if (point == null) {
        continue;
      }
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }
    if (!minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite) {
      return _ProjectedFit(size.width / 2, size.height / 2, 1);
    }

    final double width = math.max(1.0, maxX - minX);
    final double height = math.max(1.0, maxY - minY);
    final double padding = math
        .min(size.shortestSide * 0.06, 48)
        .clamp(12, 48)
        .toDouble();
    final double availableWidth = math.max(1.0, size.width - padding * 2);
    final double availableHeight = math.max(1.0, size.height - padding * 2);
    final double scale = math.min(
      1.0,
      math.min(availableWidth / width, availableHeight / height),
    );
    return _ProjectedFit(
      size.width / 2 - (minX + width / 2) * scale,
      size.height / 2 - (minY + height / 2) * scale,
      scale,
    );
  }

  _RawProjectedPoint? _projectRaw(double x, double y, double z) {
    final double cx = x - bounds.center.x;
    final double cy = y - bounds.center.y;
    final double cz = z - bounds.center.z;

    final double x1 = cx * _yawCos + cz * _yawSin;
    final double z1 = -cx * _yawSin + cz * _yawCos;
    final double y2 = cy * _pitchCos - z1 * _pitchSin;
    final double z2 = cy * _pitchSin + z1 * _pitchCos;

    final double side = math
        .min(size.width, size.height)
        .clamp(1, double.infinity);
    if (_fov <= 0) {
      final double scale = side / bounds.diagonal * 0.78 * _zoom;
      return _RawProjectedPoint(
        x: x1 * scale,
        y: -y2 * scale,
        depth: bounds.diagonal * 3 - z2,
      );
    }

    final double distance = bounds.diagonal * (1.9 / _zoom + 0.6);
    final double depth = distance - z2;
    if (depth <= 0.01) {
      return null;
    }
    final double focal = 1 / math.tan((_fov.clamp(1, 120)) * math.pi / 360);
    final double nx = (x1 * focal) / depth;
    final double ny = (y2 * focal) / depth;
    return _RawProjectedPoint(
      x: nx * side * 0.55,
      y: -ny * side * 0.55,
      depth: depth,
    );
  }
}

class _RawProjectedPoint {
  const _RawProjectedPoint({
    required this.x,
    required this.y,
    required this.depth,
  });

  final double x;
  final double y;
  final double depth;
}

class _ProjectedFit {
  const _ProjectedFit(this.dx, this.dy, this.scale);

  final double dx;
  final double dy;
  final double scale;
}

class _ProjectedPoint {
  const _ProjectedPoint({required this.offset, required this.depth});

  final ui.Offset offset;
  final double depth;
}

class _ProjectedTriangle {
  const _ProjectedTriangle({
    required this.points,
    required this.normal,
    required this.materialIndex,
    required this.depth,
  });

  final List<_ProjectedPoint> points;
  final _Vec3 normal;
  final int materialIndex;
  final double depth;

  ui.Rect get screenBounds {
    final double minX = math.min(
      points[0].offset.dx,
      math.min(points[1].offset.dx, points[2].offset.dx),
    );
    final double minY = math.min(
      points[0].offset.dy,
      math.min(points[1].offset.dy, points[2].offset.dy),
    );
    final double maxX = math.max(
      points[0].offset.dx,
      math.max(points[1].offset.dx, points[2].offset.dx),
    );
    final double maxY = math.max(
      points[0].offset.dy,
      math.max(points[1].offset.dy, points[2].offset.dy),
    );
    return ui.Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

class _Bounds3 {
  const _Bounds3({required this.min, required this.max});

  factory _Bounds3.fromScene(cube_text.CubeTextScene scene) {
    if (scene.boundsMin.length == 3 && scene.boundsMax.length == 3) {
      return _Bounds3(
        min: _Vec3(scene.boundsMin[0], scene.boundsMin[1], scene.boundsMin[2]),
        max: _Vec3(scene.boundsMax[0], scene.boundsMax[1], scene.boundsMax[2]),
      );
    }
    return const _Bounds3(min: _Vec3(-1, -1, -1), max: _Vec3(1, 1, 1));
  }

  final _Vec3 min;
  final _Vec3 max;

  _Vec3 get center => _Vec3(
    (min.x + max.x) * 0.5,
    (min.y + max.y) * 0.5,
    (min.z + max.z) * 0.5,
  );

  double get diagonal {
    final double dx = (max.x - min.x).abs();
    final double dy = (max.y - min.y).abs();
    final double dz = (max.z - min.z).abs();
    return math.sqrt(dx * dx + dy * dy + dz * dz).clamp(1, double.infinity);
  }
}

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  _Vec3 normalized() {
    final double len = math.sqrt(x * x + y * y + z * z);
    if (len <= 1e-9) {
      return const _Vec3(0, 0, 1);
    }
    return _Vec3(x / len, y / len, z / len);
  }
}

_TextMaterials _defaultYellowMaterials() {
  return _TextMaterials(
    front: _MaterialOption.gradient('#ffd07b', '#ffaa00'),
    back: _MaterialOption.gradient('#ffd07b', '#ffaa00'),
    up: _MaterialOption.color('#553800'),
    down: _MaterialOption.gradient('#a56c00', '#553800'),
    left: _MaterialOption.color('#553800'),
    right: _MaterialOption.color('#553800'),
    outline: _MaterialOption.color('#291a00'),
  );
}

_TextMaterials _defaultBlueMaterials() {
  return _TextMaterials(
    front: _MaterialOption.gradient('#9ae5ff', '#13b2ff'),
    back: _MaterialOption.gradient('#9ae5ff', '#13b2ff'),
    up: _MaterialOption.color('#003855'),
    down: _MaterialOption.gradient('#00649a', '#003855'),
    left: _MaterialOption.color('#003855'),
    right: _MaterialOption.color('#003855'),
    outline: _MaterialOption.color('#001e2b'),
  );
}

String _newObjectId() => 'text_${_objectSerial++}';

String? _emptyToNull(String? value) {
  final String trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

double _jsonDouble(Map<String, Object?> json, String key, double fallback) {
  final Object? value = json[key];
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? fallback;
  }
  return fallback;
}

String _overlayName(Object? raw) {
  if (raw == null) {
    return '';
  }
  if (raw is String) {
    return raw;
  }
  if (raw is Map<String, Object?>) {
    return raw['name']?.toString() ?? '';
  }
  return '';
}

String _formatNumber(double value) {
  if (value.roundToDouble() == value) {
    return value.round().toString();
  }
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _sanitizeFileName(String raw) {
  final String sanitized = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return sanitized.isEmpty ? 'cube-3d-text' : sanitized;
}

String _normalizeFileName(String raw, String extension) {
  final String ext = extension.startsWith('.')
      ? extension.substring(1)
      : extension;
  return raw.toLowerCase().endsWith('.$ext') ? raw : '$raw.$ext';
}

String _imageMimeType(String fileName) {
  return switch (p.extension(fileName).toLowerCase()) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.webp' => 'image/webp',
    '.gif' => 'image/gif',
    '.bmp' => 'image/bmp',
    _ => 'image/png',
  };
}

Uint8List _decodeDataUri(String dataUri) {
  final int comma = dataUri.indexOf(',');
  if (comma < 0) {
    throw const FormatException('无效 Data URI。');
  }
  return base64Decode(dataUri.substring(comma + 1));
}

Future<ui.Image> _decodeUiImage(Uint8List bytes) {
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromList(bytes, completer.complete);
  return completer.future;
}

Future<ui.Image?> _cropTransparentImage(
  ui.Image image, {
  int padding = 0,
}) async {
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (data == null) {
    return null;
  }
  final Uint8List pixels = data.buffer.asUint8List();
  int minX = image.width;
  int minY = image.height;
  int maxX = -1;
  int maxY = -1;
  for (int y = 0; y < image.height; y++) {
    final int row = y * image.width * 4;
    for (int x = 0; x < image.width; x++) {
      final int alpha = pixels[row + x * 4 + 3];
      if (alpha == 0) {
        continue;
      }
      if (x < minX) {
        minX = x;
      }
      if (x > maxX) {
        maxX = x;
      }
      if (y < minY) {
        minY = y;
      }
      if (y > maxY) {
        maxY = y;
      }
    }
  }
  if (maxX < minX || maxY < minY) {
    return null;
  }
  minX = math.max(0, minX - padding);
  minY = math.max(0, minY - padding);
  maxX = math.min(image.width - 1, maxX + padding);
  maxY = math.min(image.height - 1, maxY + padding);
  final int width = math.max(1, maxX - minX + 1);
  final int height = math.max(1, maxY - minY + 1);
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(
      minX.toDouble(),
      minY.toDouble(),
      width.toDouble(),
      height.toDouble(),
    ),
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint(),
  );
  return recorder.endRecording().toImage(width, height);
}

Color? _parseColor(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.startsWith('#')) {
    String hex = trimmed.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((char) => '$char$char').join();
    }
    if (hex.length == 6) {
      return Color(0xFF000000 | int.parse(hex, radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
  }
  final RegExpMatch? rgb = RegExp(
    r'rgba?\(([^)]+)\)',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (rgb != null) {
    final List<String> parts = rgb
        .group(1)!
        .split(',')
        .map((part) => part.trim())
        .toList();
    if (parts.length >= 3) {
      final int r = (double.tryParse(parts[0]) ?? 255).round().clamp(0, 255);
      final int g = (double.tryParse(parts[1]) ?? 255).round().clamp(0, 255);
      final int b = (double.tryParse(parts[2]) ?? 255).round().clamp(0, 255);
      final double alpha = parts.length >= 4
          ? (double.tryParse(parts[3]) ?? 1).clamp(0, 1)
          : 1;
      return Color.fromARGB((alpha * 255).round(), r, g, b);
    }
  }
  return null;
}

String _colorToHex(Color color) {
  final int value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0')}';
}

double _screenArea(ui.Offset a, ui.Offset b, ui.Offset c) {
  return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
}

void _paintCheckerboard(ui.Canvas canvas, ui.Size size) {
  final ui.Paint base = ui.Paint()..color = const Color(0xFFFFFFFF);
  canvas.drawRect(ui.Offset.zero & size, base);
  final ui.Paint square = ui.Paint()..color = const Color(0xFFE3E8EF);
  const double cell = 18;
  for (double y = 0; y < size.height; y += cell) {
    for (double x = 0; x < size.width; x += cell) {
      if (((x / cell).floor() + (y / cell).floor()).isEven) {
        canvas.drawRect(ui.Rect.fromLTWH(x, y, cell, cell), square);
      }
    }
  }
}
