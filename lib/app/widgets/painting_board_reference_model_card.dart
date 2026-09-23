part of 'painting_board.dart';

class _ReferenceModelCard extends StatefulWidget {
  const _ReferenceModelCard({
    required super.key,
    required this.title,
    required this.modelMesh,
    required this.texture,
    this.supportsActions = true,
    this.supportsMultiView = true,
    required this.dialogContext,
    required this.onClose,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onRefreshTexture,
    required this.onSizeChanged,
  });

  final String title;
  final BedrockModelMesh modelMesh;
  final ui.Image? texture;
  final bool supportsActions;
  final bool supportsMultiView;
  final BuildContext dialogContext;
  final VoidCallback onClose;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onRefreshTexture;
  final ValueChanged<Size> onSizeChanged;

  @override
  State<_ReferenceModelCard> createState() => _ReferenceModelCardState();
}

class _ReferenceModelCardState extends State<_ReferenceModelCard>
    with TickerProviderStateMixin {
  static Future<BedrockAnimationLibrary?>? _animationLibraryFuture;
  static Future<_ReferenceModelActionCatalog?>? _actionCatalogFuture;

  double _yaw = 0;
  double _pitch = 0;
  double _zoom = 1.0;
  double _zoomScaleStart = 1.0;
  bool _multiViewEnabled = false;

  late final AnimationController _actionController;
  BedrockAnimationLibrary? _animationLibrary;
  _ReferenceModelActionCatalog? _actionCatalog;
  String _selectedAction = _kReferenceModelActionNone;
  _ReferenceModelActionItem? _selectedActionItem;
  BedrockAnimation? _selectedAnimation;

  @override
  void initState() {
    super.initState();
    _actionController = AnimationController(vsync: this);
    if (widget.supportsActions) {
      unawaited(_ensureActionCatalog());
    }
  }

  @override
  void dispose() {
    _actionController.dispose();
    super.dispose();
  }

  void _resetView() {
    setState(() {
      _yaw = 0;
      _pitch = 0;
      _zoom = 1.0;
    });
  }

  void _toggleMultiView() {
    if (!widget.supportsMultiView) {
      return;
    }
    setState(() {
      _multiViewEnabled = !_multiViewEnabled;
    });
  }

  void _updateRotation(Offset delta) {
    setState(() {
      _yaw -= delta.dx * 0.01;
      _pitch = (_pitch - delta.dy * 0.01).clamp(-math.pi / 2, math.pi / 2);
    });
  }

  void _updateZoom(double delta) {
    setState(() {
      _zoom = (_zoom + delta).clamp(0.35, 6.0);
    });
  }

  Future<BedrockAnimationLibrary?> _ensureAnimationLibrary() async {
    if (!widget.supportsActions) {
      return null;
    }
    if (_animationLibrary != null) {
      return _animationLibrary;
    }
    _animationLibraryFuture ??= () async {
      final String text = await rootBundle.loadString(
        _kReferenceModelAnimationAsset,
      );
      return BedrockAnimationLibrary.tryParseFromJsonText(text);
    }();

    final BedrockAnimationLibrary? library = await _animationLibraryFuture;
    if (!mounted) {
      return library;
    }
    setState(() {
      _animationLibrary = library;
      if (_selectedAnimation == null &&
          _selectedAction != _kReferenceModelActionNone) {
        _selectedAnimation = library?.animations[_selectedAction];
      }
    });
    return library;
  }

  String _formatActionName(String name) {
    const List<String> prefixes = <String>[
      'animation.dfsteve_armor.',
      'animation.armor.',
    ];
    for (final prefix in prefixes) {
      if (name.startsWith(prefix)) {
        return name.substring(prefix.length);
      }
    }
    return name;
  }

  Future<_ReferenceModelActionCatalog?> _ensureActionCatalog() async {
    if (!widget.supportsActions) {
      return null;
    }
    final BedrockAnimationLibrary? library = await _ensureAnimationLibrary();
    if (library == null) {
      return null;
    }
    _actionCatalogFuture ??= _loadReferenceModelActionCatalog(library);
    final _ReferenceModelActionCatalog? catalog = await _actionCatalogFuture;
    if (!mounted) {
      return catalog;
    }
    setState(() {
      _actionCatalog = catalog;
      _selectedActionItem = catalog?.byId[_selectedAction];
      if (_selectedAction == _kReferenceModelActionNone) {
        _selectedAnimation = null;
      } else {
        _selectedAnimation ??= library.animations[_selectedAction];
      }
    });
    return catalog;
  }

  String _displayNameForActionId(String actionId) {
    if (actionId == _kReferenceModelActionNone) {
      return '无';
    }
    final _ReferenceModelActionItem? item = _actionCatalog?.byId[actionId];
    if (item != null) {
      return item.label;
    }
    return _formatActionName(actionId);
  }

  void _applySelectedAnimation() {
    _actionController.stop();
    if (!widget.supportsActions) {
      _actionController.value = 0;
      return;
    }
    if (_selectedAction == _kReferenceModelActionNone) {
      _actionController.value = 0;
      return;
    }

    final BedrockAnimation? animation = _selectedAnimation;
    if (animation == null) {
      _actionController.value = 0;
      return;
    }
    final bool shouldAnimate =
        _selectedActionItem?.isAnimated ?? animation.isDynamic;
    if (!shouldAnimate || animation.lengthSeconds <= 0) {
      _actionController.value = 0;
      return;
    }
    final int durationMs = math.max(
      1,
      (animation.lengthSeconds * 1000).round(),
    );
    _actionController.duration = Duration(milliseconds: durationMs);
    if (animation.loop) {
      _actionController.repeat();
    } else {
      _actionController.forward(from: 0);
    }
  }

  Future<void> _showActionDialog() => _showActionDialogImpl();
  Future<void> _showBakeDialog() => _showBakeDialogImpl();

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color border = theme.resources.controlStrokeColorDefault;
    final Color background = theme.brightness.isDark
        ? const Color(0xFF101010)
        : const Color(0xFFF7F7F7);
    final double viewportHeight = _referenceModelViewportHeightForContext(
      context,
    );
    final Color accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final l10n = context.l10n;

    final Color gridLineColor = border.withValues(alpha: border.a * 0.55);
    final bool multiViewEnabled =
        widget.supportsMultiView && _multiViewEnabled;

    Widget buildModelPaint({
      required double yaw,
      required double pitch,
      String? label,
    }) {
      Widget painted = _BedrockModelZBufferView(
        baseModel: widget.modelMesh,
        modelTextureWidth: widget.modelMesh.model.textureWidth,
        modelTextureHeight: widget.modelMesh.model.textureHeight,
        texture: widget.texture,
        yaw: yaw,
        pitch: pitch,
        zoom: _zoom,
        animation: widget.supportsActions ? _selectedAnimation : null,
        animationController: widget.supportsActions ? _actionController : null,
      );

      if (label != null && label.trim().isNotEmpty) {
        final Color chipBackground = theme.brightness.isDark
            ? const Color(0x99000000)
            : const Color(0xCCFFFFFF);
        final Color chipForeground = theme.brightness.isDark
            ? const Color(0xFFE6E6E6)
            : const Color(0xFF333333);
        painted = Stack(
          fit: StackFit.expand,
          children: [
            painted,
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: chipBackground,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: border.withValues(alpha: border.a * 0.6),
                  ),
                ),
                child: Text(
                  label,
                  style: theme.typography.caption?.copyWith(
                    color: chipForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      }

      return SizedBox.expand(child: painted);
    }

    Widget buildModelViewport({
      required double height,
      required double yaw,
      required double pitch,
      String? label,
      bool interactive = false,
    }) {
      Widget painted = buildModelPaint(yaw: yaw, pitch: pitch, label: label);

      if (interactive) {
        painted = Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _updateZoom(-event.scrollDelta.dy * 0.002);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _resetView,
            onScaleStart: (_) => _zoomScaleStart = _zoom,
            onScaleUpdate: (details) {
              final double scaleDelta = details.scale - 1.0;
              if (scaleDelta.abs() > 0.001) {
                setState(() {
                  _zoom = (_zoomScaleStart * details.scale).clamp(0.35, 6.0);
                });
                return;
              }
              _updateRotation(details.focalPointDelta);
            },
            child: painted,
          ),
        );
      }

      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: painted,
      );
    }

    return MeasuredSize(
      onChanged: widget.onSizeChanged,
      child: WorkspaceFloatingPanel(
        title: widget.title,
        width: _referenceModelCardWidthForContext(context),
        headerActions: [
          if (widget.supportsActions)
            HoverDetailTooltip(
              message: '动作',
              detail: _selectedAction == _kReferenceModelActionNone
                  ? '切换预览动作'
                  : '当前：${_displayNameForActionId(_selectedAction)}'
                        '${_selectedActionItem?.isAnimated == true ? '（动画）' : ''}',
              child: IconButton(
                icon: const Icon(FluentIcons.running, size: 14),
                iconButtonMode: IconButtonMode.small,
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
                ),
                onPressed: _showActionDialog,
              ),
            ),
          HoverDetailTooltip(
            message: l10n.referenceModelRefreshTexture,
            detail: l10n.referenceModelRefreshTextureDesc,
            child: IconButton(
              icon: const Icon(FluentIcons.refresh, size: 14),
              iconButtonMode: IconButtonMode.small,
              style: ButtonStyle(
                padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
              ),
              onPressed: widget.onRefreshTexture,
            ),
          ),
          HoverDetailTooltip(
            message: l10n.referenceModelResetView,
            detail: l10n.referenceModelResetViewDesc,
            child: IconButton(
              icon: const Icon(FluentIcons.reset, size: 14),
              iconButtonMode: IconButtonMode.small,
              style: ButtonStyle(
                padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
              ),
              onPressed: _resetView,
            ),
          ),
          HoverDetailTooltip(
            message: '烘焙',
            detail: '按时间烘焙光照并导出图片',
            child: IconButton(
              icon: const Icon(FluentIcons.auto_enhance_on, size: 14),
              iconButtonMode: IconButtonMode.small,
              style: ButtonStyle(
                padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
              ),
              onPressed: _showBakeDialog,
            ),
          ),
          if (widget.supportsMultiView)
            HoverDetailTooltip(
              message: multiViewEnabled
                  ? l10n.referenceModelSingleView
                  : l10n.referenceModelSixView,
              detail: multiViewEnabled
                  ? l10n.referenceModelSingleViewDesc
                  : l10n.referenceModelSixViewDesc,
              child: IconButton(
                icon: Icon(
                  FluentIcons.picture,
                  size: 14,
                  color: multiViewEnabled ? accent : null,
                ),
                iconButtonMode: IconButtonMode.small,
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
                ),
                onPressed: _toggleMultiView,
              ),
            ),
        ],
        onClose: widget.onClose,
        onDragStart: widget.onDragStart,
        onDragUpdate: widget.onDragUpdate,
        onDragEnd: widget.onDragEnd,
        bodyPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        bodySpacing: 8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!multiViewEnabled)
              buildModelViewport(
                height: viewportHeight,
                yaw: _yaw,
                pitch: _pitch,
                interactive: true,
              )
            else
              Container(
                height: viewportHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      _updateZoom(-event.scrollDelta.dy * 0.002);
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: _resetView,
                    onScaleStart: (_) => _zoomScaleStart = _zoom,
                    onScaleUpdate: (details) {
                      final double scaleDelta = details.scale - 1.0;
                      if (scaleDelta.abs() <= 0.001) {
                        return;
                      }
                      setState(() {
                        _zoom = (_zoomScaleStart * details.scale).clamp(
                          0.35,
                          6.0,
                        );
                      });
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: gridLineColor),
                                      bottom: BorderSide(color: gridLineColor),
                                    ),
                                  ),
                                  child: buildModelPaint(
                                    yaw: 0,
                                    pitch: 0,
                                    label: l10n.referenceModelViewFront,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: gridLineColor),
                                      bottom: BorderSide(color: gridLineColor),
                                    ),
                                  ),
                                  child: buildModelPaint(
                                    yaw: math.pi,
                                    pitch: 0,
                                    label: l10n.referenceModelViewBack,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: gridLineColor),
                                    ),
                                  ),
                                  child: buildModelPaint(
                                    yaw: 0,
                                    pitch: -math.pi / 2,
                                    label: l10n.referenceModelViewTop,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(color: gridLineColor),
                                    ),
                                  ),
                                  child: buildModelPaint(
                                    yaw: 0,
                                    pitch: math.pi / 2,
                                    label: l10n.referenceModelViewBottom,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(color: gridLineColor),
                                    ),
                                  ),
                                  child: buildModelPaint(
                                    yaw: -math.pi / 2,
                                    pitch: 0,
                                    label: l10n.referenceModelViewLeft,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: buildModelPaint(
                                  yaw: math.pi / 2,
                                  pitch: 0,
                                  label: l10n.referenceModelViewRight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(FluentIcons.search, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: AppSlider(
                    value: _zoom.clamp(0.35, 6.0),
                    min: 0.35,
                    max: 6.0,
                    onChanged: (value) => setState(() => _zoom = value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
