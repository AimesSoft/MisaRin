part of 'painting_board.dart';

const String _kSteveReferenceModelAsset =
    'assets/bedrock_models/armor_steve.json';
const String _kAlexReferenceModelAsset =
    'assets/bedrock_models/armor_alex.json';
const String _kCubeReferenceModelAsset = 'assets/bedrock_models/cube.json';
const String _kReferenceModelAnimationAsset =
    'assets/bedrock_models/dfsteve_armor.animation.json';

const double _referenceModelCardWidth = 420;
const double _referenceModelViewportHeight = 320;
const double _referenceModelCardChromeHeight = 120;
const double _referenceModelCardBaseHeight =
    _referenceModelViewportHeight + _referenceModelCardChromeHeight;
const double _referenceModelCardMobileWidthFactor = 0.6;

double _referenceModelCardWidthForContext(BuildContext context) {
  if (isMobileOrPhone(context)) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth.isFinite && screenWidth > 0) {
      return screenWidth * _referenceModelCardMobileWidthFactor;
    }
  }
  return _referenceModelCardWidth;
}

double _referenceModelViewportHeightForContext(BuildContext context) {
  if (isMobileOrPhone(context)) {
    final double width = _referenceModelCardWidthForContext(context);
    return (width - _referenceModelCardChromeHeight).clamp(0.0, width);
  }
  return _referenceModelViewportHeight;
}

double _referenceModelCardHeightForContext(BuildContext context) {
  if (isMobileOrPhone(context)) {
    return _referenceModelCardWidthForContext(context);
  }
  return _referenceModelCardBaseHeight;
}

Size _referenceModelCardDefaultSize(BuildContext context) {
  return Size(
    _referenceModelCardWidthForContext(context),
    _referenceModelCardHeightForContext(context),
  );
}

const String _kReferenceModelActionNone = '__none__';

final Expando<bool> _imageDisposedCache = Expando<bool>('imageDisposed');

bool _isImageDisposed(ui.Image? image) {
  if (image == null) {
    return true;
  }
  final bool? cached = _imageDisposedCache[image];
  if (cached == true) {
    return true;
  }
  bool disposed = false;
  assert(() {
    disposed = image.debugDisposed;
    return true;
  }());
  if (disposed) {
    _imageDisposedCache[image] = true;
  }
  return disposed;
}

bool _isImageUsable(ui.Image? image) => !_isImageDisposed(image);

void _markImageDisposed(ui.Image image) {
  _imageDisposedCache[image] = true;
}

void _disposeImageSafely(ui.Image? image) {
  if (image == null) {
    return;
  }
  if (_isImageDisposed(image)) {
    return;
  }
  image.dispose();
  _markImageDisposed(image);
}

enum _ReferenceModelActionType { none, pose, animation }

class _ReferenceModelActionSeed {
  const _ReferenceModelActionSeed({
    required this.id,
    required this.label,
    required this.type,
    required this.order,
  });

  final String id;
  final String label;
  final _ReferenceModelActionType type;
  final int order;
}

const List<_ReferenceModelActionSeed> _kReferenceModelActionSeeds =
    <_ReferenceModelActionSeed>[
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.default_pose',
        label: '站立',
        type: _ReferenceModelActionType.pose,
        order: 0,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.kawaii',
        label: '坐',
        type: _ReferenceModelActionType.pose,
        order: 1,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.solemn_pose',
        label: '肃立',
        type: _ReferenceModelActionType.pose,
        order: 2,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.brandish_pose',
        label: '挥舞',
        type: _ReferenceModelActionType.pose,
        order: 3,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.honor_pose',
        label: '荣耀',
        type: _ReferenceModelActionType.pose,
        order: 4,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.entertain_pose',
        label: '拥抱',
        type: _ReferenceModelActionType.pose,
        order: 5,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.salute_pose',
        label: '欢迎',
        type: _ReferenceModelActionType.pose,
        order: 6,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.zombie_pose',
        label: '僵尸',
        type: _ReferenceModelActionType.pose,
        order: 7,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.cancan_a_pose',
        label: '康康舞a',
        type: _ReferenceModelActionType.pose,
        order: 8,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.cancan_b_pose',
        label: '康康舞b',
        type: _ReferenceModelActionType.pose,
        order: 9,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.hero_pose',
        label: '英雄',
        type: _ReferenceModelActionType.pose,
        order: 10,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.athena_pose',
        label: '雅典娜',
        type: _ReferenceModelActionType.pose,
        order: 11,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.wiggle',
        label: '立正',
        type: _ReferenceModelActionType.pose,
        order: 12,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.riposte_pose',
        label: '耍酷',
        type: _ReferenceModelActionType.pose,
        order: 13,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.qitao_pose',
        label: '卖萌',
        type: _ReferenceModelActionType.pose,
        order: 14,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.hello_pose',
        label: '打招呼',
        type: _ReferenceModelActionType.pose,
        order: 15,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.jojo_pose',
        label: 'JOJO立',
        type: _ReferenceModelActionType.pose,
        order: 16,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.dontstop_pose',
        label: '不要停下来',
        type: _ReferenceModelActionType.pose,
        order: 17,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.bata_pose',
        label: '异议！！',
        type: _ReferenceModelActionType.pose,
        order: 18,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.sneak_pose',
        label: '潜行',
        type: _ReferenceModelActionType.pose,
        order: 19,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.sleep_pose',
        label: '睡觉',
        type: _ReferenceModelActionType.pose,
        order: 20,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.sleep2_pose',
        label: '侧躺',
        type: _ReferenceModelActionType.pose,
        order: 21,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.houbunjump_pose',
        label: '芳文跳',
        type: _ReferenceModelActionType.pose,
        order: 22,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.yee_pose',
        label: '四脚着地',
        type: _ReferenceModelActionType.pose,
        order: 23,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.run_pose',
        label: '奔跑',
        type: _ReferenceModelActionType.pose,
        order: 24,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.saber_pose',
        label: '拔剑',
        type: _ReferenceModelActionType.pose,
        order: 25,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.dame',
        label: '拦截',
        type: _ReferenceModelActionType.pose,
        order: 26,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.down',
        label: '后仰撑地',
        type: _ReferenceModelActionType.pose,
        order: 27,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.move',
        label: '奔跑',
        type: _ReferenceModelActionType.animation,
        order: 100,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.stop',
        label: '立正',
        type: _ReferenceModelActionType.animation,
        order: 101,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.armor.swim',
        label: '游泳',
        type: _ReferenceModelActionType.animation,
        order: 102,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.armor.shoot',
        label: '射击',
        type: _ReferenceModelActionType.animation,
        order: 103,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.anime_sneak',
        label: '潜行',
        type: _ReferenceModelActionType.animation,
        order: 104,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.anime_eat',
        label: '吃东西',
        type: _ReferenceModelActionType.animation,
        order: 105,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.anime_omedetou',
        label: '鼓掌',
        type: _ReferenceModelActionType.animation,
        order: 106,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.anime_agree',
        label: '点头',
        type: _ReferenceModelActionType.animation,
        order: 107,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.anime_disagree',
        label: '摇头',
        type: _ReferenceModelActionType.animation,
        order: 108,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.anime_loop',
        label: '大风车',
        type: _ReferenceModelActionType.animation,
        order: 109,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.anime_hunbunjump',
        label: '芳文跳',
        type: _ReferenceModelActionType.animation,
        order: 110,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.anime_nani',
        label: '上下转',
        type: _ReferenceModelActionType.animation,
        order: 111,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.anime_nani2',
        label: '左右转',
        type: _ReferenceModelActionType.animation,
        order: 112,
      ),
      _ReferenceModelActionSeed(
        id: 'animation.dfsteve_armor.anime_head',
        label: '分头行动',
        type: _ReferenceModelActionType.animation,
        order: 113,
      ),
    ];

class _ReferenceModelActionItem {
  const _ReferenceModelActionItem({
    required this.id,
    required this.label,
    required this.type,
    required this.isAnimated,
    required this.order,
  });

  final String id;
  final String label;
  final _ReferenceModelActionType type;
  final bool isAnimated;
  final int order;
}

class _ReferenceModelActionCatalog {
  const _ReferenceModelActionCatalog({required this.items, required this.byId});

  final List<_ReferenceModelActionItem> items;
  final Map<String, _ReferenceModelActionItem> byId;
}

class _ReferenceModelCardEntry {
  _ReferenceModelCardEntry({
    required this.id,
    required this.title,
    required this.modelMesh,
    required this.offset,
    required this.supportsActions,
    required this.supportsMultiView,
  });

  final int id;
  final String title;
  final BedrockModelMesh modelMesh;
  final bool supportsActions;
  final bool supportsMultiView;
  Offset offset;
  Size? size;
}

mixin _PaintingBoardReferenceModelMixin on _PaintingBoardBase {
  final List<_ReferenceModelCardEntry> _referenceModelCards =
      <_ReferenceModelCardEntry>[];
  int _referenceModelCardSerial = 0;

  ui.Image? _referenceModelTexture;
  bool _referenceModelTextureLoading = false;
  bool _referenceModelTextureDirty = false;
  bool _referenceModelTextureSyncScheduled = false;
  int? _referenceModelTextureLastAppliedGeneration;

  final List<ui.Image> _referenceModelTexturePendingDisposals = <ui.Image>[];
  bool _referenceModelTextureDisposalScheduled = false;

  bool _referenceModelImportInProgress = false;
  bool _referenceModelBuiltinLoadInProgress = false;

  @override
  void _recordBackendHistoryAction({
    String? layerId,
    bool deferPreview = false,
  }) {
    super._recordBackendHistoryAction(
      layerId: layerId,
      deferPreview: deferPreview,
    );
    _scheduleReferenceModelTextureRefresh();
  }

  Future<void> showSteveReferenceModelCard() async {
    await _openReferenceModelFromAsset(
      _kSteveReferenceModelAsset,
      title: 'Steve模型',
    );
  }

  Future<void> showAlexReferenceModelCard() async {
    await _openReferenceModelFromAsset(
      _kAlexReferenceModelAsset,
      title: 'Alex模型',
    );
  }

  Future<void> showCubeReferenceModelCard() async {
    await _openReferenceModelFromAsset(
      _kCubeReferenceModelAsset,
      title: '方块模型',
      supportsActions: false,
      supportsMultiView: false,
    );
  }

  Future<void> importReferenceModelCard() async {
    if (_referenceModelImportInProgress) {
      AppNotifications.show(
        context,
        message: '正在导入模型，请稍候…',
        severity: InfoBarSeverity.info,
      );
      return;
    }
    _referenceModelImportInProgress = true;
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: '导入模型',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      final PlatformFile? file = result?.files.singleOrNull;
      if (!mounted || file == null) {
        return;
      }
      final Uint8List? bytes = file.bytes;
      final String? path = file.path;
      Uint8List? jsonBytes = bytes;
      if (jsonBytes == null && path != null) {
        jsonBytes = await File(path).readAsBytes();
      }
      if (jsonBytes == null) {
        AppNotifications.show(
          context,
          message: '无法读取模型文件内容。',
          severity: InfoBarSeverity.error,
        );
        return;
      }
      await _openReferenceModelFromJsonBytes(
        jsonBytes,
        sourcePath: path,
        title: file.name.isNotEmpty ? file.name : '导入模型',
      );
      AppNotifications.show(
        context,
        message: '已导入模型${file.name.isNotEmpty ? '：${file.name}' : ''}',
        severity: InfoBarSeverity.success,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to import reference model: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: '导入模型失败。',
        severity: InfoBarSeverity.error,
      );
    } finally {
      _referenceModelImportInProgress = false;
    }
  }

  Future<void> _openReferenceModelFromAsset(
    String asset, {
    required String title,
    bool supportsActions = true,
    bool supportsMultiView = true,
  }) async {
    if (_referenceModelBuiltinLoadInProgress) {
      AppNotifications.show(
        context,
        message: '正在加载模型，请稍候…',
        severity: InfoBarSeverity.info,
      );
      return;
    }
    _referenceModelBuiltinLoadInProgress = true;
    try {
      final String text = await rootBundle.loadString(asset);
      final BedrockGeometryModel? geometry =
          BedrockGeometryModel.tryParseFromJsonText(text);
      if (geometry == null) {
        if (!mounted) return;
        AppNotifications.show(
          context,
          message: '内置模型格式无效：$asset',
          severity: InfoBarSeverity.error,
        );
        return;
      }
      final BedrockModelMesh modelMesh = buildBedrockModelMesh(geometry);
      await _ensureReferenceModelTexture();
      if (!mounted) return;
      _insertReferenceModelCard(
        title: title,
        modelMesh: modelMesh,
        supportsActions: supportsActions,
        supportsMultiView: supportsMultiView,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to load built-in reference model: $error\n$stackTrace',
      );
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: '加载模型失败。',
        severity: InfoBarSeverity.error,
      );
    } finally {
      _referenceModelBuiltinLoadInProgress = false;
    }
  }

  Future<void> _openReferenceModelFromJsonBytes(
    Uint8List jsonBytes, {
    required String title,
    String? sourcePath,
    bool supportsActions = true,
    bool supportsMultiView = true,
  }) async {
    final BedrockModelMesh modelMesh = await _loadBedrockModelMeshFromAnyJson(
      jsonBytes,
      sourcePath: sourcePath,
    );
    await _ensureReferenceModelTexture();
    if (!mounted) {
      return;
    }
    _insertReferenceModelCard(
      title: title,
      modelMesh: modelMesh,
      supportsActions: supportsActions,
      supportsMultiView: supportsMultiView,
    );
  }

  Future<BedrockModelMesh> _loadBedrockModelMeshFromAnyJson(
    Uint8List jsonBytes, {
    String? sourcePath,
  }) async {
    final String text = utf8.decode(jsonBytes, allowMalformed: true);
    final BedrockGeometryModel? geometry =
        BedrockGeometryModel.tryParseFromJsonText(text);
    if (geometry != null) {
      return buildBedrockModelMesh(geometry);
    }

    final Object? decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('Invalid JSON root');
    }
    final Map<String, Object?> root = decoded.cast<String, Object?>();
    final String? preferredGeometryId = _extractGeometryIdentifier(root);
    if (preferredGeometryId == null) {
      throw const FormatException(
        'Not a Bedrock geometry / client entity file',
      );
    }
    if (sourcePath == null || sourcePath.isEmpty) {
      throw const FormatException(
        'Client entity JSON needs a file path to resolve geometry',
      );
    }
    final String? geometryPath = _resolveGeometryPath(
      sourcePath,
      preferredGeometryId,
    );
    if (geometryPath == null) {
      throw FormatException(
        '无法解析几何文件：$preferredGeometryId（请直接导入 geometry JSON）',
      );
    }
    final Uint8List geometryBytes = await File(geometryPath).readAsBytes();
    final String geometryText = utf8.decode(
      geometryBytes,
      allowMalformed: true,
    );
    final BedrockGeometryModel? resolved =
        BedrockGeometryModel.tryParseFromJsonText(
          geometryText,
          preferredIdentifier: preferredGeometryId,
        );
    if (resolved == null) {
      throw FormatException('几何文件中未找到：$preferredGeometryId');
    }
    return buildBedrockModelMesh(resolved);
  }

  String? _extractGeometryIdentifier(Map<String, Object?> root) {
    final Map<String, Object?>? clientEntity =
        root['minecraft:client_entity'] is Map
        ? (root['minecraft:client_entity'] as Map).cast<String, Object?>()
        : null;
    final Map<String, Object?>? description =
        clientEntity?['description'] is Map
        ? (clientEntity!['description'] as Map).cast<String, Object?>()
        : null;
    final Object? geometry = description?['geometry'];
    if (geometry is String) {
      return geometry.trim().isNotEmpty ? geometry.trim() : null;
    }
    if (geometry is Map) {
      final Map<String, Object?> entries = geometry.cast<String, Object?>();
      final Object? defaultGeo = entries['default'];
      if (defaultGeo is String && defaultGeo.trim().isNotEmpty) {
        return defaultGeo.trim();
      }
      for (final value in entries.values) {
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }
    return null;
  }

  String? _resolveGeometryPath(String sourcePath, String geometryId) {
    final String? root = _findResourcePackRoot(sourcePath);
    if (root == null) {
      return null;
    }
    String name = geometryId;
    if (name.startsWith('geometry.')) {
      name = name.substring('geometry.'.length);
    }
    final String guessed = p.join(root, 'models', 'entity', '$name.json');
    if (File(guessed).existsSync()) {
      return guessed;
    }

    final Directory dir = Directory(p.join(root, 'models', 'entity'));
    if (!dir.existsSync()) {
      return null;
    }
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.json') continue;
      try {
        final String text = entity.readAsStringSync();
        final BedrockGeometryModel? parsed =
            BedrockGeometryModel.tryParseFromJsonText(
              text,
              preferredIdentifier: geometryId,
            );
        if (parsed != null) {
          return entity.path;
        }
      } catch (_) {
        // Ignore invalid JSON during scan.
      }
    }
    return null;
  }

  String? _findResourcePackRoot(String sourcePath) {
    String dir = p.dirname(sourcePath);
    for (int i = 0; i < 6; i++) {
      final Directory models = Directory(p.join(dir, 'models', 'entity'));
      if (models.existsSync()) {
        return dir;
      }
      final String next = p.dirname(dir);
      if (next == dir) {
        break;
      }
      dir = next;
    }
    return null;
  }

  Future<void> _ensureReferenceModelTexture() async {
    if (_referenceModelTexture != null) {
      return;
    }
    await _refreshReferenceModelTexture(showSuccessToast: false, force: true);
  }

  Future<void> _syncReferenceModelTextureFromBackend({
    required bool showWarning,
  }) async {
    if (!_backend.supportsInputQueue) {
      return;
    }
    await _controller.waitForPendingWorkerTasks();
    final bool queueEmpty = await _backend.waitForInputQueueIdle();
    if (queueEmpty) {
      await Future.delayed(const Duration(milliseconds: 16));
    }
    final bool ok = await _backend.syncAllLayerPixelsFromBackend();
    if (!ok) {
      debugPrint('referenceModel: backend sync failed');
      if (showWarning) {
        _showBackendCanvasMessage('画布后端同步图层失败。');
      }
    }
  }

  Future<void> _refreshReferenceModelTexture({
    bool showSuccessToast = true,
    bool force = false,
  }) async {
    if (_referenceModelCards.isEmpty && !force) {
      return;
    }
    if (_referenceModelTextureLoading) {
      _referenceModelTextureDirty = true;
      if (showSuccessToast) {
        AppNotifications.show(
          context,
          message: '正在更新模型贴图，请稍候…',
          severity: InfoBarSeverity.info,
        );
      }
      return;
    }
    final int? generation = _controller.frame?.generation;
    final bool forceRefresh = force || _referenceModelTextureDirty;
    if (!forceRefresh &&
        generation != null &&
        _referenceModelTexture != null &&
        _referenceModelTextureLastAppliedGeneration == generation) {
      _referenceModelTextureDirty = false;
      return;
    }
    // Clear the dirty flag now; if another change arrives while we are doing
    // work, the scheduler will mark it dirty again and re-run after completion.
    _referenceModelTextureDirty = false;
    _referenceModelTextureLoading = true;
    try {
      await _syncReferenceModelTextureFromBackend(
        showWarning: showSuccessToast,
      );
      final ui.Image image = await _controller.snapshotImage();
      if (!mounted) {
        _disposeImageSafely(image);
        return;
      }
      final ui.Image? previous = _referenceModelTexture;
      setState(() {
        _referenceModelTexture = image;
      });
      _scheduleWorkspaceCardsOverlaySync();
      if (previous != null) {
        _enqueueReferenceModelTextureDisposal(previous);
      }
      _referenceModelTextureLastAppliedGeneration = generation;
      if (showSuccessToast) {
        AppNotifications.show(
          context,
          message: '模型贴图已更新。',
          severity: InfoBarSeverity.success,
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to refresh reference model texture: $error\n$stackTrace',
      );
      if (!mounted) {
        return;
      }
      AppNotifications.show(
        context,
        message: '更新模型贴图失败。',
        severity: InfoBarSeverity.error,
      );
    } finally {
      _referenceModelTextureLoading = false;
      if (_referenceModelTextureDirty) {
        _scheduleReferenceModelTextureRefresh();
      }
    }
  }

  void _scheduleReferenceModelTextureRefresh() {
    if (_referenceModelCards.isEmpty) {
      return;
    }
    _referenceModelTextureDirty = true;
    if (_referenceModelTextureSyncScheduled) {
      return;
    }
    _referenceModelTextureSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _referenceModelTextureSyncScheduled = false;
      if (!mounted || _referenceModelCards.isEmpty) {
        return;
      }
      unawaited(_refreshReferenceModelTexture(showSuccessToast: false));
    });
  }

  void _enqueueReferenceModelTextureDisposal(ui.Image image) {
    if (_isImageDisposed(image)) {
      return;
    }
    _referenceModelTexturePendingDisposals.add(image);
    if (_referenceModelTextureDisposalScheduled) {
      return;
    }
    _referenceModelTextureDisposalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _referenceModelTextureDisposalScheduled = false;
      if (_referenceModelTexturePendingDisposals.isEmpty) {
        return;
      }
      final List<ui.Image> pending = List<ui.Image>.from(
        _referenceModelTexturePendingDisposals,
      );
      _referenceModelTexturePendingDisposals.clear();
      for (final ui.Image image in pending) {
        _disposeImageSafely(image);
      }
    });
  }

  void _insertReferenceModelCard({
    required String title,
    required BedrockModelMesh modelMesh,
    bool supportsActions = true,
    bool supportsMultiView = true,
  }) {
    final int id = ++_referenceModelCardSerial;
    final Offset offset = _initialReferenceModelCardOffset();
    setState(() {
      _referenceModelCards.add(
        _ReferenceModelCardEntry(
          id: id,
          title: title,
          modelMesh: modelMesh,
          offset: offset,
          supportsActions: supportsActions,
          supportsMultiView: supportsMultiView,
        ),
      );
    });
    _scheduleWorkspaceCardsOverlaySync();
  }

  Offset _initialReferenceModelCardOffset() {
    final double stackOffset = _referenceModelCards.length * 28.0;
    final Size panelSize = _referenceModelCardDefaultSize(context);
    return _workspacePanelSpawnOffset(
      this,
      panelWidth: panelSize.width,
      panelHeight: panelSize.height,
      additionalDy: stackOffset,
    );
  }

  void _closeReferenceModelCard(int id) {
    final int index = _referenceModelCards.indexWhere((card) => card.id == id);
    if (index < 0) {
      return;
    }
    final bool wasLast = _referenceModelCards.length == 1;
    final ui.Image? texture = wasLast ? _referenceModelTexture : null;
    setState(() {
      _referenceModelCards.removeAt(index);
      if (_referenceModelCards.isEmpty) {
        _referenceModelTexture = null;
      }
    });
    if (texture != null) {
      _enqueueReferenceModelTextureDisposal(texture);
    }
    _scheduleWorkspaceCardsOverlaySync();
  }

  void _updateReferenceModelCardOffset(int id, Offset delta) {
    if (delta == Offset.zero) return;
    final _ReferenceModelCardEntry? entry = _referenceModelCardById(id);
    if (entry == null) return;
    setState(() {
      final Size size = entry.size ?? _referenceModelCardDefaultSize(context);
      entry.offset = _clampWorkspaceOffsetToViewport(
        this,
        entry.offset + delta,
        childSize: size,
        margin: 12,
      );
    });
    _scheduleWorkspaceCardsOverlaySync();
  }

  void _handleReferenceModelCardSizeChanged(int id, Size size) {
    final _ReferenceModelCardEntry? entry = _referenceModelCardById(id);
    if (entry == null) return;
    entry.size = size;
    final Offset clamped = _clampWorkspaceOffsetToViewport(
      this,
      entry.offset,
      childSize: size,
      margin: 12,
    );
    if (clamped == entry.offset) return;
    setState(() {
      entry.offset = clamped;
    });
    _scheduleWorkspaceCardsOverlaySync();
  }

  void _focusReferenceModelCard(int id) {
    final int index = _referenceModelCards.indexWhere((card) => card.id == id);
    if (index < 0 || index == _referenceModelCards.length - 1) return;
    setState(() {
      final _ReferenceModelCardEntry entry = _referenceModelCards.removeAt(
        index,
      );
      _referenceModelCards.add(entry);
    });
    _scheduleWorkspaceCardsOverlaySync();
  }

  _ReferenceModelCardEntry? _referenceModelCardById(int id) {
    for (final entry in _referenceModelCards) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  @override
  bool _isInsideReferenceModelCardArea(Offset workspacePosition) {
    for (final _ReferenceModelCardEntry entry in _referenceModelCards) {
      final Size size = entry.size ?? _referenceModelCardDefaultSize(context);
      final Rect rect = Rect.fromLTWH(
        entry.offset.dx,
        entry.offset.dy,
        size.width,
        size.height,
      );
      if (rect.contains(workspacePosition)) {
        return true;
      }
    }
    return false;
  }

  void _disposeReferenceModelCards() {
    for (final ui.Image image in _referenceModelTexturePendingDisposals) {
      _disposeImageSafely(image);
    }
    _referenceModelTexturePendingDisposals.clear();
    _referenceModelTextureDisposalScheduled = false;
    _referenceModelTextureSyncScheduled = false;
    _referenceModelTextureDirty = false;
    _referenceModelTextureLastAppliedGeneration = null;
    _disposeImageSafely(_referenceModelTexture);
    _referenceModelTexture = null;
    _referenceModelCards.clear();
  }
}
