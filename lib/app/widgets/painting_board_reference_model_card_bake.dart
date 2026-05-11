part of 'painting_board.dart';

enum _MobileImageExportDestination { photos, files }

Future<_MobileImageExportDestination?> _showMobileImageExportDestinationDialog(
  BuildContext context,
) {
  final l10n = context.l10n;
  if (isMobileOrPhone(context)) {
    return showMobileBottomSheetOnRootOverlay<_MobileImageExportDestination?>(
      context: context,
      heightFactor: 0.45,
      builder: (BuildContext context) {
        final theme = FluentTheme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.exportDestinationTitle,
                    style: theme.typography.subtitle?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.exportDestinationDesc,
                    style: theme.typography.caption,
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  ListTile(
                    title: Text(l10n.exportDestinationPhotos),
                    onPressed: () => MobileBottomSheetScope.of(context)
                        .close(_MobileImageExportDestination.photos),
                  ),
                  ListTile(
                    title: Text(l10n.exportDestinationFiles),
                    onPressed: () => MobileBottomSheetScope.of(context)
                        .close(_MobileImageExportDestination.files),
                  ),
                  const Divider(),
                  ListTile(
                    title: Text(l10n.cancel),
                    onPressed: () =>
                        MobileBottomSheetScope.of(context).close(null),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
  return showDialog<_MobileImageExportDestination?>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      return ContentDialog(
        title: Text(l10n.exportDestinationTitle),
        content: Text(l10n.exportDestinationDesc),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(l10n.cancel),
          ),
          Button(
            onPressed: () =>
                Navigator.of(context).pop(_MobileImageExportDestination.files),
            child: Text(l10n.exportDestinationFiles),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_MobileImageExportDestination.photos),
            child: Text(l10n.exportDestinationPhotos),
          ),
        ],
      );
    },
  );
}

extension _ReferenceModelCardStateBakeDialog on _ReferenceModelCardState {
  Future<void> _showBakeDialogImpl() async {
    if (!mounted) {
      return;
    }

    final BuildContext dialogContext = widget.dialogContext;
    final bool useMobileSheet = isMobileOrPhone(dialogContext);
    final OverlayState? overlay = Overlay.maybeOf(dialogContext, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    final ui.Image? bakeTexture = await _prepareBakeDialogTexture();
    if (!mounted) {
      return;
    }

    final GlobalKey previewKey = GlobalKey();
    final GlobalKey<_BedrockModelZBufferViewState> previewModelKey =
        GlobalKey<_BedrockModelZBufferViewState>();

    double previewYaw = _yaw;
    double previewPitch = _pitch;
    double previewZoom = _zoom;
    double previewZoomScaleStart = previewZoom;

    double timeHours = 12.0;
    double renderBrightness = 1.0;
    double renderContrast = 1.0;
    bool isBaking = false;
	    _ReferenceModelBakeRendererPreset rendererPreset =
	        _ReferenceModelBakeRendererPreset.normal;
	    const Color normalSkyColor = Color(0xFFBFD9FF);
	    bool showSky = true;
	    bool showGround = true;
	    bool transparentBackground = false;
	    bool? showSkyBeforeTransparent;
	    bool? showGroundBeforeTransparent;

    _ReferenceModelBakeResolutionPreset? resolutionPreset =
        _kReferenceModelBakeResolutionPresets[1];
    final TextEditingController widthController = TextEditingController(
      text: resolutionPreset.width.toString(),
    );
    final TextEditingController heightController = TextEditingController(
      text: resolutionPreset.height.toString(),
    );

    int previewRenderKey = 0;

    void markPreviewDirty() {
      previewRenderKey += 1;
    }

    bool isTimePlaying = false;
    const double timePlaySpeedHoursPerSecond = 0.25;
    StateSetter? dialogSetState;
    Duration? lastTickElapsed;
    final Ticker timeTicker = createTicker((Duration elapsed) {
      final StateSetter? setState = dialogSetState;
      if (setState == null) {
        lastTickElapsed = elapsed;
        return;
      }
      if (!isTimePlaying || isBaking || !rendererPreset.usesBakedLighting) {
        lastTickElapsed = elapsed;
        return;
      }
      final Duration previous = lastTickElapsed ?? elapsed;
      final double dtSeconds =
          (elapsed - previous).inMicroseconds.toDouble() / 1000000.0;
      lastTickElapsed = elapsed;
      if (dtSeconds <= 0) {
        return;
      }
      setState(() {
        timeHours = (timeHours + dtSeconds * timePlaySpeedHoursPerSecond) % 24.0;
        markPreviewDirty();
      });
    });

    OverlayEntry? dialogEntry;
    Completer<void>? dialogCompleter;

    void closeDialog() {
      if (isBaking) {
        return;
      }
      if (isTimePlaying) {
        isTimePlaying = false;
        timeTicker.stop();
        lastTickElapsed = null;
      }
      dialogEntry?.remove();
      dialogEntry = null;
      dialogCompleter?.complete();
      dialogCompleter = null;
    }

    ({int width, int height})? parseAndValidateResolution(
      BuildContext context, {
      required String widthText,
      required String heightText,
    }) {
      final int? targetWidth = int.tryParse(widthText.trim());
      final int? targetHeight = int.tryParse(heightText.trim());
      if (targetWidth == null ||
          targetHeight == null ||
          targetWidth <= 0 ||
          targetHeight <= 0) {
        AppNotifications.show(
          context,
          message: '分辨率无效：请输入合法的宽高像素值',
          severity: InfoBarSeverity.error,
        );
        return null;
      }
      if (targetWidth > 8192 || targetHeight > 8192) {
        AppNotifications.show(
          context,
          message: '分辨率过大：单边最大支持 8192px',
          severity: InfoBarSeverity.error,
        );
        return null;
      }
      if (targetWidth * targetHeight > 16000000) {
        AppNotifications.show(
          context,
          message: '分辨率过大：总像素建议不超过 1600 万（例如 4K）',
          severity: InfoBarSeverity.error,
        );
        return null;
      }
      return (width: targetWidth, height: targetHeight);
    }

    Future<bool> editCustomResolution(BuildContext context) async {
      final TextEditingController customWidthController = TextEditingController(
        text: widthController.text.trim(),
      );
      final TextEditingController customHeightController = TextEditingController(
        text: heightController.text.trim(),
      );

      try {
        final ({int width, int height})? result = isMobileOrPhone(context)
            ? await showMobileBottomSheetOnRootOverlay<({int width, int height})?>(
                context: widget.dialogContext,
                heightFactor: 0.55,
                builder: (BuildContext context) {
                  final FluentThemeData theme = FluentTheme.of(context);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '自定义分辨率',
                          style: theme.typography.subtitle?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        InfoLabel(
                          label: '宽度 (px)',
                          child: TextFormBox(
                            controller: customWidthController,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        InfoLabel(
                          label: '高度 (px)',
                          child: TextFormBox(
                            controller: customHeightController,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '提示：单边最大 8192px，总像素建议不超过 1600 万。',
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Button(
                                onPressed: () => MobileBottomSheetScope.of(context)
                                    .close(null),
                                child: Text(context.l10n.cancel),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  final ({int width, int height})?
                                      resolution = parseAndValidateResolution(
                                    context,
                                    widthText: customWidthController.text,
                                    heightText: customHeightController.text,
                                  );
                                  if (resolution == null) {
                                    return;
                                  }
                                  MobileBottomSheetScope.of(context)
                                      .close(resolution);
                                },
                                child: const Text('确定'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              )
            : await showMisarinDialog<({int width, int height})>(
                context: context,
                title: const Text('自定义分辨率'),
                contentWidth: 360,
                maxWidth: 420,
                barrierDismissible: true,
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InfoLabel(
                      label: '宽度 (px)',
                      child: TextFormBox(
                        controller: customWidthController,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    InfoLabel(
                      label: '高度 (px)',
                      child: TextFormBox(
                        controller: customHeightController,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '提示：单边最大 8192px，总像素建议不超过 1600 万。',
                    ),
                  ],
                ),
                actions: [
                  Button(
                    child: Text(context.l10n.cancel),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Button(
                    child: const Text('确定'),
                    onPressed: () {
                      final ({int width, int height})? resolution =
                          parseAndValidateResolution(
                        context,
                        widthText: customWidthController.text,
                        heightText: customHeightController.text,
                      );
                      if (resolution == null) {
                        return;
                      }
                      Navigator.of(context).pop(resolution);
                    },
                  ),
                ],
              );

        if (result == null) {
          return false;
        }
        widthController.text = result.width.toString();
        heightController.text = result.height.toString();
        return true;
      } finally {
        customWidthController.dispose();
        customHeightController.dispose();
      }
    }

    Future<void> exportBakeResult(
      BuildContext context,
      StateSetter setDialogState,
    ) async {
      final ({int width, int height})? resolution = parseAndValidateResolution(
        context,
        widthText: widthController.text,
        heightText: heightController.text,
      );
      if (resolution == null) {
        return;
      }

      final DateTime now = DateTime.now();
      final String suggestedName = _sanitizeFileName(
        'bake_${_formatTimestampForFileName(now)}_${_formatTimeForFileName(timeHours)}.png',
      );

      String? normalizedPath;
      String? mobileFileName;
      _MobileImageExportDestination? mobileDestination;

      if (Platform.isAndroid || Platform.isIOS) {
        if (Platform.isIOS) {
          mobileDestination =
              await _showMobileImageExportDestinationDialog(context);
          if (mobileDestination == null) {
            return;
          }
        } else {
          mobileDestination = _MobileImageExportDestination.files;
        }

        if (mobileDestination == _MobileImageExportDestination.files) {
          final String? fileName = await showFileNameDialog(
            context: context,
            title: '导出烘焙结果',
            suggestedFileName: suggestedName,
            confirmLabel: context.l10n.export,
          );
          if (fileName == null) {
            return;
          }
          mobileFileName = _ensurePngExtension(_sanitizeFileName(fileName));
          normalizedPath = await MobileExportPaths.resolveExportPath(
            mobileFileName,
          );
        } else {
          mobileFileName = suggestedName;
        }
      } else {
        final String? outputPath = await FilePicker.platform.saveFile(
          dialogTitle: '导出烘焙结果',
          fileName: suggestedName,
          type: FileType.custom,
          allowedExtensions: const <String>['png'],
        );
        if (outputPath == null) {
          return;
        }
        normalizedPath = _ensurePngExtension(outputPath);
      }

      try {
        setDialogState(() {
          isBaking = true;
          if (isTimePlaying) {
            isTimePlaying = false;
            timeTicker.stop();
            lastTickElapsed = null;
          }
          markPreviewDirty();
        });

        await Future<void>.delayed(const Duration(milliseconds: 16));
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !context.mounted) {
          return;
        }

        final _BedrockModelZBufferViewState? rendererState =
            previewModelKey.currentState;
        if (rendererState == null) {
          throw StateError('无法获取模型渲染器');
        }

        final FluentThemeData theme = FluentTheme.of(context);
        final Color normalBackground = theme.brightness.isDark
            ? const Color(0xFF101010)
            : const Color(0xFFF7F7F7);
        final bool usesBakedLighting = rendererPreset.usesBakedLighting;
        final _ReferenceModelBakeLighting? lighting = usesBakedLighting
            ? _lightingForTime(timeHours, isDark: false)
            : null;
        final Color exportBackground = showSky && !usesBakedLighting
            ? normalSkyColor
            : (lighting?.background ?? normalBackground);
        final _BedrockSkyboxBackground? skybox =
            showSky && usesBakedLighting && lighting != null
            ? _BedrockSkyboxBackground(
                timeHours: timeHours,
                isDark: false,
                skyColor: lighting.skyColor,
                sunColor: lighting.sunColor,
                lightDirection: lighting.lightDirection,
                seed: 1337,
              )
            : null;

        final Uint8List bytes = await rendererState.renderPngBytes(
          width: resolution.width,
          height: resolution.height,
          background: exportBackground,
          skybox: skybox,
          transparentBackground: transparentBackground,
        );
        if (Platform.isIOS &&
            mobileDestination == _MobileImageExportDestination.photos) {
          await IosPhotoSaver.saveImageToPhotos(
            bytes,
            fileName: mobileFileName,
          );
        } else {
          final File file = File(normalizedPath!);
          await file.writeAsBytes(bytes, flush: true);
        }

        if (!mounted || !context.mounted) {
          return;
        }
        AppNotifications.show(
          context,
          message:
              (Platform.isIOS &&
                  mobileDestination == _MobileImageExportDestination.photos)
              ? context.l10n.imageSavedToPhotos
              : '已导出：$normalizedPath',
          severity: InfoBarSeverity.success,
        );
      } catch (error) {
        if (!mounted || !context.mounted) {
          return;
        }
        AppNotifications.show(
          context,
          message: '导出失败：$error',
          severity: InfoBarSeverity.error,
        );
      } finally {
        if (mounted) {
          setDialogState(() {
            isBaking = false;
          });
        }
      }
    }

    final Completer<void> completer = Completer<void>();
    dialogCompleter = completer;
    dialogEntry = OverlayEntry(
      builder: (BuildContext overlayContext) {
        return HeroControllerScope.none(
          child: Navigator(
            onPopPage: (route, result) {
              if (!route.didPop(result)) {
                return false;
              }
              closeDialog();
              return true;
            },
            onGenerateInitialRoutes: (navigator, initialRoute) =>
                <Route<void>>[
              PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
                pageBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
                pageBuilder: (context, animation, secondaryAnimation) {
              final Color barrierColor = Colors.black.withValues(alpha: 0.35);
              return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!isBaking) {
                  closeDialog();
                }
              },
              child: ColoredBox(color: barrierColor),
            ),
            Builder(
              builder: (BuildContext context) {
                final FluentThemeData sheetTheme = FluentTheme.of(context);
                final double sheetHeight =
                    MediaQuery.sizeOf(context).height * 0.85;
                final Widget dialogBody = StatefulBuilder(
                  builder: (BuildContext context, StateSetter setDialogState) {
                  dialogSetState = setDialogState;
                  final FluentThemeData theme = FluentTheme.of(context);
                  final Color border =
                      theme.resources.controlStrokeColorDefault;
                  final Color normalBackground = theme.brightness.isDark
                      ? const Color(0xFF101010)
                      : const Color(0xFFF7F7F7);

                  final _ReferenceModelBakeLighting? lighting =
                      rendererPreset.usesBakedLighting
                      ? _lightingForTime(
                          timeHours,
                          isDark: false,
                        )
                      : null;
                  final Color previewBackground =
                      lighting?.background ?? normalBackground;

                  Widget buildModelPreview() {
                    final double groundY = widget.modelMesh.mesh.boundsMin.y;
                    final bool usesBakedLighting =
                        rendererPreset.usesBakedLighting;
                    final _ReferenceModelBakeLighting? bakedLighting = lighting;
                    final bool isCinematic = rendererPreset ==
                        _ReferenceModelBakeRendererPreset.cinematic;
                    final bool isCycles =
                        rendererPreset == _ReferenceModelBakeRendererPreset.cycles;

                    final double specularStrength = usesBakedLighting
                        ? (isCycles
                              ? bakedLighting!.specularStrength * 0.65
                              : bakedLighting!.specularStrength)
                        : 0.25;
                    final double roughness = usesBakedLighting
                        ? (isCycles ? 0.68 : bakedLighting!.roughness)
                        : 0.55;
                    final double exposure = usesBakedLighting
                        ? (isCinematic
                              ? bakedLighting!.exposure * 1.05
                              : bakedLighting!.exposure)
                        : 1.0;
                    final double baseAmbient =
                        usesBakedLighting ? bakedLighting!.ambient : 0.55;
                    final double baseDiffuse =
                        usesBakedLighting ? bakedLighting!.diffuse : 0.45;
                    double adjustedAmbient = baseAmbient;
                    double adjustedDiffuse = baseDiffuse;
                    final double contrastFactor = renderContrast.isFinite
                        ? renderContrast.clamp(0.0, 2.0).toDouble()
                        : 1.0;
                    if (contrastFactor != 1.0) {
                      final double sum = baseAmbient + baseDiffuse;
                      if (sum > 0) {
                        adjustedDiffuse =
                            (baseDiffuse * contrastFactor).clamp(0.0, sum);
                        adjustedAmbient =
                            (sum - adjustedDiffuse).clamp(0.0, sum);
                      }
                    }
                    adjustedAmbient =
                        adjustedAmbient.clamp(0.0, 1.0).toDouble();
                    adjustedDiffuse =
                        adjustedDiffuse.clamp(0.0, 1.0).toDouble();
                    final double adjustedExposure = (exposure *
                            (renderBrightness.isFinite
                                ? renderBrightness.clamp(0.5, 2.0).toDouble()
                                : 1.0))
                        .clamp(0.0, 4.0)
                        .toDouble();

                    final bool enableSelfShadow = usesBakedLighting;
                    final int shadowMapSize = isCinematic ? 2048 : 1024;
                    final int shadowPcfRadius = isCycles ? 3 : 0;

                    final bool enableContactShadow = usesBakedLighting;
                    final double contactShadowStrength =
                        isCinematic ? 0.22 : 0.14;
	                    final int contactShadowBlurRadius = isCinematic
	                        ? 0
	                        : (isCycles ? 4 : 2);
	                    const double contactShadowDepthEpsilon = 0.012;
	                    final bool showGroundPlane =
	                        transparentBackground ? usesBakedLighting : showGround;
	                    final bool showGroundShadow =
	                        showGroundPlane && usesBakedLighting;
	                    final int groundShadowBlurRadius = showGroundShadow
	                        ? (isCinematic
	                              ? 0
	                              : (isCycles
	                                    ? (bakedLighting!.shadowBlurRadius + 2)
	                                        .clamp(0, 10)
                                        .toInt()
                                    : bakedLighting!.shadowBlurRadius))
                        : 0;
                    final Widget model = _BedrockModelZBufferView(
                      key: previewModelKey,
                      baseModel: widget.modelMesh,
                      modelTextureWidth: widget.modelMesh.model.textureWidth,
                      modelTextureHeight: widget.modelMesh.model.textureHeight,
                      texture: bakeTexture ?? widget.texture,
                      yaw: previewYaw,
                      pitch: previewPitch,
                      zoom: previewZoom,
                      animation: widget.supportsActions ? _selectedAnimation : null,
                      animationController:
                          widget.supportsActions ? _actionController : null,
                      lightDirection:
                          usesBakedLighting ? bakedLighting!.lightDirection : null,
                      ambient: adjustedAmbient,
                      diffuse: adjustedDiffuse,
                      sunColor: usesBakedLighting
                          ? bakedLighting!.sunColor
                          : const Color(0xFFFFFFFF),
                      skyColor: usesBakedLighting
                          ? bakedLighting!.skyColor
                          : const Color(0xFFBFD9FF),
                      groundBounceColor: usesBakedLighting
                          ? bakedLighting!.groundBounceColor
                          : const Color(0xFFFFFFFF),
                      specularStrength: specularStrength,
                      roughness: roughness,
                      exposure: adjustedExposure,
                      toneMap: usesBakedLighting,
                      enableSelfShadow: enableSelfShadow,
                      selfShadowStrength: 1.0,
                      selfShadowMapSize: shadowMapSize,
                      selfShadowBias: isCycles ? 0.03 : 0.02,
                      selfShadowSlopeBias: isCycles ? 0.05 : 0.04,
                      selfShadowPcfRadius: shadowPcfRadius,
                      enableContactShadow: enableContactShadow,
                      contactShadowStrength: contactShadowStrength,
	                      contactShadowBlurRadius: contactShadowBlurRadius,
	                      contactShadowDepthEpsilon: contactShadowDepthEpsilon,
	                      lightFollowsCamera: !usesBakedLighting,
	                      showGround: showGroundPlane,
	                      groundY: groundY,
	                      alignModelToGround: false,
	                      groundColor:
	                          transparentBackground ? Colors.transparent : Colors.white,
	                      showGroundShadow: showGroundShadow,
	                      groundShadowStrength: showGroundShadow
	                          ? bakedLighting!.shadowStrength
	                          : 0.0,
	                      groundShadowBlurRadius: groundShadowBlurRadius,
	                      groundShadowIntoAlpha: transparentBackground,
	                      renderKey: previewRenderKey,
	                    );

                    Widget interactive = Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          setDialogState(() {
                            markPreviewDirty();
                            previewZoom =
                                (previewZoom - event.scrollDelta.dy * 0.002)
                                    .clamp(0.35, 6.0);
                          });
                        }
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: () {
                          setDialogState(() {
                            markPreviewDirty();
                            previewYaw = 0;
                            previewPitch = 0;
                            previewZoom = 1.0;
                          });
                        },
                        onScaleStart: (_) =>
                            previewZoomScaleStart = previewZoom,
                        onScaleUpdate: (details) {
                          setDialogState(() {
                            markPreviewDirty();
                            final double scaleDelta = details.scale - 1.0;
                            if (scaleDelta.abs() > 0.001) {
                              previewZoom =
                                  (previewZoomScaleStart * details.scale).clamp(
                                    0.35,
                                    6.0,
                                  );
                              return;
                            }
                            previewYaw -= details.focalPointDelta.dx * 0.01;
                            previewPitch =
                                (previewPitch -
                                        details.focalPointDelta.dy * 0.01)
                                    .clamp(-math.pi / 2, math.pi / 2);
                          });
                        },
                        child: model,
                      ),
                    );

                    return IgnorePointer(
                      ignoring: isBaking,
                      child: interactive,
                    );
                  }

                  Widget buildPreviewArea() {
                    return Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          RepaintBoundary(
                            key: previewKey,
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (transparentBackground)
                                    const _CheckboardBackground()
                                  else if (showSky &&
                                      rendererPreset.usesBakedLighting &&
                                      lighting != null)
                                    _ReferenceModelBakeSkyboxBackground(
                                      timeHours: timeHours,
                                      lighting: lighting,
                                      isDark: false,
                                      cameraYaw: previewYaw,
                                      cameraPitch: previewPitch,
                                      cameraZoom: previewZoom,
                                    )
                                  else if (showSky)
                                    const ColoredBox(color: normalSkyColor)
                                  else
                                    ColoredBox(color: previewBackground),
                                  buildModelPreview(),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            bottom: 12,
                            child: HoverDetailTooltip(
                              message: '渲染器',
                              detail: rendererPreset.label,
                              child: const SizedBox.shrink(),
                            ),
                          ),
                          if (isBaking)
                            Positioned.fill(
                              child: AbsorbPointer(
                                child: ColoredBox(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  child: Center(
                                    child: SizedBox(
                                      width: 320,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          ProgressBar(value: null),
                                          SizedBox(height: 12),
                                          Text('烘焙中…'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }

                  final Widget dialogContent = SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          buildPreviewArea(),
                          const SizedBox(height: 12),
                          Builder(
                            builder: (context) {
                              Widget buildBackgroundToggle(
                                String label,
                                bool value,
                                ValueChanged<bool>? onChanged,
                              ) {
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      label,
                                      style: theme.typography.bodyStrong,
                                    ),
                                    const SizedBox(width: 8),
                                    ToggleSwitch(
                                      checked: value,
                                      onChanged: onChanged,
                                    ),
                                  ],
                                );
                              }

                              final Widget rendererSection = InfoLabel(
                                label: context.l10n.rendererLabel,
                                child: Container(
                                  height: 32,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: border),
                                    borderRadius: BorderRadius.circular(4),
                                    color: theme.resources.controlFillColorDefault,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (int i = 0;
                                          i <
                                              _ReferenceModelBakeRendererPreset
                                                  .values.length;
                                          i++) ...[
                                        if (i > 0)
                                          Container(
                                            width: 1,
                                            color: border,
                                          ),
                                        (() {
                                          final preset =
                                              _ReferenceModelBakeRendererPreset
                                                  .values[i];
                                          final bool isSelected =
                                              rendererPreset == preset;
                                          IconData icon;
                                          String title;
                                          String detail;

                                          switch (preset) {
                                            case _ReferenceModelBakeRendererPreset
                                                .normal:
                                              icon = FluentIcons.running;
                                              title = context.l10n.rendererNormal;
                                              detail =
                                                  context.l10n.rendererNormalDesc;
                                              break;
                                            case _ReferenceModelBakeRendererPreset
                                                .cinematic:
                                              icon = FluentIcons.video;
                                              title =
                                                  context.l10n.rendererCinematic;
                                              detail =
                                                  context.l10n.rendererCinematicDesc;
                                              break;
                                            case _ReferenceModelBakeRendererPreset
                                                .cycles:
                                              icon = FluentIcons.camera;
                                              title = context.l10n.rendererCycles;
                                              detail =
                                                  context.l10n.rendererCyclesDesc;
                                              break;
                                          }

                                          return HoverDetailTooltip(
                                            message: title,
                                            detail: detail,
                                            child: SizedBox(
                                              width: 32,
                                              height: 32,
                                              child: Button(
                                                style: ButtonStyle(
                                                  padding: ButtonState.all(
                                                    EdgeInsets.zero,
                                                  ),
                                                  backgroundColor:
                                                      ButtonState.resolveWith(
                                                    (states) {
                                                      if (isSelected) {
                                                        return theme
                                                            .accentColor.normal;
                                                      }
                                                      if (states.isHovering &&
                                                          !isBaking) {
                                                        return theme.resources
                                                            .controlFillColorSecondary;
                                                      }
                                                      return Colors.transparent;
                                                    },
                                                  ),
                                                  foregroundColor:
                                                      ButtonState.resolveWith(
                                                    (states) {
                                                      if (isSelected) {
                                                        return Colors.white;
                                                      }
                                                      if (isBaking) {
                                                        return theme.resources
                                                            .textFillColorDisabled;
                                                      }
                                                      return theme
                                                          .typography.body?.color;
                                                    },
                                                  ),
                                                  shape: ButtonState.all(
                                                    const RoundedRectangleBorder(
                                                      side: BorderSide.none,
                                                      borderRadius:
                                                          BorderRadius.zero,
                                                    ),
                                                  ),
                                                ),
                                                onPressed: () {
                                                  if (isBaking) {
                                                    return;
                                                  }
                                                  setDialogState(() {
                                                    rendererPreset = preset;
                                                    if (!preset
                                                            .usesBakedLighting &&
                                                        isTimePlaying) {
                                                      isTimePlaying = false;
                                                      timeTicker.stop();
                                                      lastTickElapsed = null;
                                                    }
                                                    markPreviewDirty();
                                                  });
                                                },
                                                child: IconTheme(
                                                  data: IconThemeData(
                                                    color: isSelected
                                                        ? theme.resources
                                                            .textOnAccentFillColorPrimary
                                                        : (isBaking
                                                            ? theme.resources
                                                                .textFillColorDisabled
                                                            : theme.typography
                                                                .body?.color),
                                                    size: 16,
                                                  ),
                                                  child: Icon(icon),
                                                ),
                                              ),
                                            ),
                                          );
                                        }()),
                                      ],
                                    ],
                                  ),
                                ),
                              );

                              final Widget backgroundRow = Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  buildBackgroundToggle(
                                    '透明背景',
                                    transparentBackground,
                                    isBaking
                                        ? null
                                        : (value) {
                                            setDialogState(() {
                                              transparentBackground = value;
                                              if (transparentBackground) {
                                                showSkyBeforeTransparent ??=
                                                    showSky;
                                                showGroundBeforeTransparent ??=
                                                    showGround;
                                                showSky = false;
                                                showGround = false;
                                              } else {
                                                showSky =
                                                    showSkyBeforeTransparent ??
                                                        showSky;
                                                showGround =
                                                    showGroundBeforeTransparent ??
                                                        showGround;
                                                showSkyBeforeTransparent = null;
                                                showGroundBeforeTransparent =
                                                    null;
                                              }
                                              markPreviewDirty();
                                            });
                                          },
                                  ),
                                  const SizedBox(width: 12),
                                  buildBackgroundToggle(
                                    '天空',
                                    showSky,
                                    isBaking || transparentBackground
                                        ? null
                                        : (value) {
                                            setDialogState(() {
                                              showSky = value;
                                              markPreviewDirty();
                                            });
                                          },
                                  ),
                                  const SizedBox(width: 12),
                                  buildBackgroundToggle(
                                    '地面',
                                    showGround,
                                    isBaking || transparentBackground
                                        ? null
                                        : (value) {
                                            setDialogState(() {
                                              showGround = value;
                                              markPreviewDirty();
                                            });
                                          },
                                  ),
                                ],
                              );

                              final Widget backgroundWrap = Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  buildBackgroundToggle(
                                    '透明背景',
                                    transparentBackground,
                                    isBaking
                                        ? null
                                        : (value) {
                                            setDialogState(() {
                                              transparentBackground = value;
                                              if (transparentBackground) {
                                                showSkyBeforeTransparent ??=
                                                    showSky;
                                                showGroundBeforeTransparent ??=
                                                    showGround;
                                                showSky = false;
                                                showGround = false;
                                              } else {
                                                showSky =
                                                    showSkyBeforeTransparent ??
                                                        showSky;
                                                showGround =
                                                    showGroundBeforeTransparent ??
                                                        showGround;
                                                showSkyBeforeTransparent = null;
                                                showGroundBeforeTransparent =
                                                    null;
                                              }
                                              markPreviewDirty();
                                            });
                                          },
                                  ),
                                  buildBackgroundToggle(
                                    '天空',
                                    showSky,
                                    isBaking || transparentBackground
                                        ? null
                                        : (value) {
                                            setDialogState(() {
                                              showSky = value;
                                              markPreviewDirty();
                                            });
                                          },
                                  ),
                                  buildBackgroundToggle(
                                    '地面',
                                    showGround,
                                    isBaking || transparentBackground
                                        ? null
                                        : (value) {
                                            setDialogState(() {
                                              showGround = value;
                                              markPreviewDirty();
                                            });
                                          },
                                  ),
                                ],
                              );

                              Widget buildResolutionCombo({
                                required double width,
                              }) {
                                return SizedBox(
                                  width: width,
                                  child: ComboBox<
                                      _ReferenceModelBakeResolutionPreset?>(
                                    isExpanded: true,
                                    value: resolutionPreset,
                                    items: [
                                      ComboBoxItem<
                                          _ReferenceModelBakeResolutionPreset?>(
                                        value: null,
                                        child: Text(
                                          '${context.l10n.custom} (${widthController.text} × ${heightController.text})',
                                        ),
                                      ),
                                      ..._kReferenceModelBakeResolutionPresets
                                          .map(
                                        (preset) => ComboBoxItem<
                                            _ReferenceModelBakeResolutionPreset?>(
                                          value: preset,
                                          child: Text(preset.label),
                                        ),
                                      ),
                                    ],
                                    onChanged: isBaking
                                        ? null
                                        : (value) async {
                                            if (value != null) {
                                              setDialogState(() {
                                                resolutionPreset = value;
                                                widthController.text =
                                                    value.width.toString();
                                                heightController.text =
                                                    value.height.toString();
                                              });
                                              return;
                                            }

                                            final _ReferenceModelBakeResolutionPreset?
                                                previousPreset = resolutionPreset;
                                            final String previousWidth =
                                                widthController.text;
                                            final String previousHeight =
                                                heightController.text;

                                            final bool updated =
                                                await editCustomResolution(
                                              context,
                                            );
                                            if (!mounted) {
                                              return;
                                            }

                                            setDialogState(() {
                                              if (updated) {
                                                resolutionPreset = null;
                                              } else {
                                                resolutionPreset =
                                                    previousPreset;
                                                widthController.text =
                                                    previousWidth;
                                                heightController.text =
                                                    previousHeight;
                                              }
                                            });
                                          },
                                  ),
                                );
                              }

                              Widget buildResolutionButton() {
                                return Button(
                                  onPressed: isBaking
                                      ? null
                                      : () async {
                                          final bool updated =
                                              await editCustomResolution(
                                            context,
                                          );
                                          if (!mounted) {
                                            return;
                                          }
                                          if (!updated) {
                                            return;
                                          }
                                          setDialogState(() {});
                                        },
                                  child: Text(context.l10n.settingsTitle),
                                );
                              }

                              if (!useMobileSheet) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    rendererSection,
                                    const SizedBox(width: 24),
                                    InfoLabel(
                                      label: context.l10n.resolutionPreset,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          buildResolutionCombo(width: 240),
                                          if (resolutionPreset == null) ...[
                                            const SizedBox(width: 8),
                                            buildResolutionButton(),
                                          ],
                                          const SizedBox(width: 12),
                                          backgroundRow,
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  rendererSection,
                                  const SizedBox(height: 12),
                                  InfoLabel(
                                    label: context.l10n.resolutionPreset,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        buildResolutionCombo(
                                          width: double.infinity,
                                        ),
                                        if (resolutionPreset == null) ...[
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: buildResolutionButton(),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  InfoLabel(
                                    label: '背景天空配置',
                                    child: backgroundWrap,
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(context.l10n.brightness),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Slider(
                                  value: renderBrightness.clamp(0.5, 2.0),
                                  min: 0.5,
                                  max: 2.0,
                                  divisions: 150,
                                  onChanged: isBaking
                                      ? null
                                      : (value) {
                                          setDialogState(() {
                                            renderBrightness = value;
                                            markPreviewDirty();
                                          });
                                        },
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  renderBrightness.toStringAsFixed(2),
                                  textAlign: TextAlign.end,
                                  style: theme.typography.bodyStrong,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(context.l10n.contrast),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Slider(
                                  value: renderContrast.clamp(0.0, 2.0),
                                  min: 0.0,
                                  max: 2.0,
                                  divisions: 200,
                                  onChanged: isBaking
                                      ? null
                                      : (value) {
                                          setDialogState(() {
                                            renderContrast = value;
                                            markPreviewDirty();
                                          });
                                        },
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  renderContrast.toStringAsFixed(2),
                                  textAlign: TextAlign.end,
                                  style: theme.typography.bodyStrong,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Text('时间'),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Slider(
                                  value: timeHours.clamp(0, 24),
                                  min: 0,
                                  max: 24,
                                  divisions: 96,
                                  onChanged: isBaking ||
                                          !rendererPreset.usesBakedLighting
                                      ? null
                                      : (value) {
                                          setDialogState(() {
                                            if (isTimePlaying) {
                                              isTimePlaying = false;
                                              timeTicker.stop();
                                              lastTickElapsed = null;
                                            }
                                            timeHours = value;
                                            markPreviewDirty();
                                          });
                                        },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _formatTimeForDisplay(timeHours),
                                style: theme.typography.bodyStrong,
                              ),
                              const SizedBox(width: 8),
                              HoverDetailTooltip(
                                message: isTimePlaying ? '暂停' : '播放',
                                detail: '让天空随时间自动变化',
                                child: IconButton(
                                  icon: Icon(
                                    isTimePlaying
                                        ? FluentIcons.pause
                                        : FluentIcons.play,
                                    size: 14,
                                  ),
                                  iconButtonMode: IconButtonMode.small,
                                  style: ButtonStyle(
                                    padding: WidgetStateProperty.all(
                                      const EdgeInsets.all(4),
                                    ),
                                  ),
                                  onPressed: isBaking ||
                                          !rendererPreset.usesBakedLighting
                                      ? null
                                      : () {
                                          setDialogState(() {
                                            isTimePlaying = !isTimePlaying;
                                          });
                                          if (isTimePlaying) {
                                            lastTickElapsed = null;
                                            timeTicker.start();
                                          } else {
                                            timeTicker.stop();
                                            lastTickElapsed = null;
                                          }
                                        },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );

                    if (useMobileSheet) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Text(
                              '烘焙',
                              style: theme.typography.subtitle?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(child: dialogContent),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Button(
                                    onPressed: isBaking ? null : closeDialog,
                                    child: Text(dialogContext.l10n.cancel),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: isBaking
                                        ? null
                                        : () => exportBakeResult(
                                              context,
                                              setDialogState,
                                            ),
                                    child: const Text('导出'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    return MisarinDialog(
                      title: Row(children: [const Text('烘焙')]),
                      contentWidth: null,
                      maxWidth: 920,
                      content: dialogContent,
                      actions: [
                        Button(
                          onPressed: isBaking ? null : closeDialog,
                          child: Text(dialogContext.l10n.cancel),
                        ),
                        Button(
                          onPressed: isBaking
                              ? null
                              : () => exportBakeResult(
                                    context,
                                    setDialogState,
                                  ),
                          child: const Text('导出'),
                        ),
                      ],
                    );
                  },
                );
                if (useMobileSheet) {
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: material.Material(
                      color: Colors.transparent,
                      child: Container(
                        width: double.infinity,
                        height: sheetHeight,
                        decoration: BoxDecoration(
                          color: sheetTheme.micaBackgroundColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(
                              MobileBottomSheetConstants.borderRadius,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 20,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: sheetTheme
                                    .resources
                                    .controlStrokeColorDefault
                                    .withOpacity(0.6),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(
                                    MobileBottomSheetConstants.borderRadius,
                                  ),
                                ),
                                child: dialogBody,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return Center(child: dialogBody);
              },
            ),
          ],
        );
            },
          ),
        ],
          ),
        );
      },
    );

    overlay.insert(dialogEntry!);
    try {
      await completer.future;
	    } finally {
	      closeDialog();
	      timeTicker.dispose();
	      widthController.dispose();
	      heightController.dispose();
	      _disposeImageSafely(bakeTexture);
	    }
  }

  static _ReferenceModelBakeLighting _lightingForTime(
    double timeHours, {
    required bool isDark,
  }) {
    final double normalized = timeHours.isFinite
        ? (timeHours % 24 + 24) % 24
        : 12.0;

    final double azimuth = (normalized / 24.0) * math.pi * 2.0;
    final double dayPhase = ((normalized - 6.0) / 12.0) * math.pi;
    final double sunHeight = math.sin(dayPhase).clamp(-1.0, 1.0).toDouble();
    final double daylight = sunHeight.clamp(0.0, 1.0).toDouble();
    final double night = (-sunHeight).clamp(0.0, 1.0).toDouble();

    double pow01(double value, double power) {
      if (value <= 0) {
        return 0.0;
      }
      if (value >= 1) {
        return 1.0;
      }
      return math.pow(value, power).toDouble();
    }

    double smoothstep(double edge0, double edge1, double x) {
      final double t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
      return t * t * (3.0 - 2.0 * t);
    }

    double lerpDouble(double a, double b, double t) {
      return a + (b - a) * t;
    }

    final double dayBlend = smoothstep(-0.35, 0.15, sunHeight);

    final double sunStrength = pow01(daylight, 1.25);
    final double sunContrast = pow01(daylight, 2.0);
    final double moonStrength = pow01(night, 1.10);
    final double moonContrast = pow01(night, 1.60);

    final Vector3 sunDir = Vector3(
      math.cos(azimuth),
      0.08 + 0.92 * daylight,
      -math.sin(azimuth),
    )..normalize();
    final double moonAzimuth = azimuth + math.pi;
    final Vector3 moonDir = Vector3(
      math.cos(moonAzimuth),
      0.10 + 0.90 * night,
      -math.sin(moonAzimuth),
    )..normalize();

    final Vector3 light = Vector3(
      moonDir.x + (sunDir.x - moonDir.x) * dayBlend,
      moonDir.y + (sunDir.y - moonDir.y) * dayBlend,
      moonDir.z + (sunDir.z - moonDir.z) * dayBlend,
    );
    if (light.length2 > 1e-9) {
      light.normalize();
    } else {
      light.setFrom(sunDir);
    }

    final double ambientDay = lerpDouble(
      isDark ? 0.32 : 0.28,
      isDark ? 0.14 : 0.10,
      sunContrast,
    ).clamp(0.08, 0.36);
    final double diffuseDay =
        lerpDouble(0.08, 0.95, sunStrength).clamp(0.0, 0.95);

    final double ambientNight = lerpDouble(
      isDark ? 0.18 : 0.16,
      isDark ? 0.26 : 0.20,
      moonContrast,
    ).clamp(0.08, 0.36);
    final double diffuseNight =
        lerpDouble(0.03, 0.08, moonStrength).clamp(0.0, 0.25);

    final double ambient =
        lerpDouble(ambientNight, ambientDay, dayBlend).clamp(0.0, 1.0);
    final double diffuse =
        lerpDouble(diffuseNight, diffuseDay, dayBlend).clamp(0.0, 1.0);

    final Color sunWarm = const Color(0xFFFFA36D);
    final Color sunNeutral = const Color(0xFFFFFFFF);
    final double sunTintT = math.sqrt(daylight);
    final Color sunColor =
        Color.lerp(sunWarm, sunNeutral, sunTintT) ?? sunNeutral;

    final Color moonColor = const Color(0xFFB8CFFF);
    final Color directionalColor =
        Color.lerp(moonColor, sunColor, dayBlend) ?? sunColor;

    final Color daySky = isDark
        ? const Color(0xFF2D4461)
        : const Color(0xFFBFD9FF);
    final Color starSky = isDark
        ? const Color(0xFF0A1222)
        : const Color(0xFF121826);
    final Color moonSky = isDark
        ? const Color(0xFF22344F)
        : const Color(0xFF324A6B);
    final Color nightSky = Color.lerp(starSky, moonSky, moonStrength) ?? moonSky;
    final Color skyColor =
        Color.lerp(nightSky, daySky, dayBlend) ?? daySky;

    const Color dayBounce = Color(0xFFD8D8D8);
    final Color nightBounceBase = isDark
        ? const Color(0xFF111A2A)
        : const Color(0xFF151C2A);
    final Color nightBounceMoon = isDark
        ? const Color(0xFF263651)
        : const Color(0xFF2E405E);
    final Color nightBounce =
        Color.lerp(nightBounceBase, nightBounceMoon, moonStrength) ??
            nightBounceMoon;
    final Color groundBounceColor =
        Color.lerp(nightBounce, dayBounce, dayBlend) ?? dayBounce;

    final double specDay =
        (0.12 + (0.58 - 0.12) * sunStrength).clamp(0.0, 0.7);
    final double specNight =
        (0.05 + (0.18 - 0.05) * moonStrength).clamp(0.0, 0.4);
    final double specularStrength =
        (specNight + (specDay - specNight) * dayBlend).clamp(0.0, 1.0);

    final double roughnessDay = 0.55;
    final double roughnessNight = 0.60;
    final double roughness = (roughnessNight +
            (roughnessDay - roughnessNight) * dayBlend)
        .clamp(0.0, 1.0);

    final double exposureDay =
        (1.05 + (0.95 - 1.05) * sunStrength).clamp(0.85, 1.25);
    final double exposureNight =
        (1.18 + (1.12 - 1.18) * moonStrength).clamp(0.85, 1.40);
    final double exposure =
        (exposureNight + (exposureDay - exposureNight) * dayBlend)
            .clamp(0.75, 1.70);

    final double shadowStrengthDay =
        (0.25 + (0.85 - 0.25) * sunStrength).clamp(0.0, 0.9);
    final double shadowStrengthNight =
        (0.08 + (0.32 - 0.08) * moonStrength).clamp(0.0, 0.6);
    final double shadowStrength =
        (shadowStrengthNight + (shadowStrengthDay - shadowStrengthNight) * dayBlend)
            .clamp(0.0, 0.85);

    int lerpInt(int a, int b, double t) {
      return (a + (b - a) * t).round();
    }

    final int shadowBlurDay = lerpInt(6, 2, sunStrength).clamp(1, 6);
    final int shadowBlurNight = lerpInt(7, 3, moonStrength).clamp(1, 6);
    final int shadowBlurRadius =
        lerpInt(shadowBlurNight, shadowBlurDay, dayBlend).clamp(1, 6);

    final Color dayBackground = isDark
        ? const Color(0xFF101010)
        : const Color(0xFFF7F7F7);
    final Color starBackground = isDark
        ? const Color(0xFF050505)
        : const Color(0xFFE7E7E7);
    final Color moonBackground = isDark
        ? const Color(0xFF070A12)
        : const Color(0xFFE7E7E7);
    final Color nightBackground =
        Color.lerp(starBackground, moonBackground, moonStrength) ??
            moonBackground;
    final Color background =
        Color.lerp(nightBackground, dayBackground, dayBlend) ?? dayBackground;

    return _ReferenceModelBakeLighting(
      lightDirection: light,
      ambient: ambient,
      diffuse: diffuse,
      sunColor: directionalColor,
      skyColor: skyColor,
      groundBounceColor: groundBounceColor,
      specularStrength: specularStrength,
      roughness: roughness,
      exposure: exposure,
      background: background,
      shadowStrength: shadowStrength,
      shadowBlurRadius: shadowBlurRadius,
    );
  }

  static String _formatTimeForDisplay(double timeHours) {
    final double normalized = timeHours.isFinite
        ? (timeHours % 24 + 24) % 24
        : 12.0;
    final int hour = normalized.floor();
    int minute = ((normalized - hour) * 60).round();
    int hourAdjusted = hour;
    if (minute >= 60) {
      minute = 0;
      hourAdjusted = (hourAdjusted + 1) % 24;
    }
    return '${hourAdjusted.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static String _formatTimeForFileName(double timeHours) {
    return _formatTimeForDisplay(timeHours).replaceAll(':', '-');
  }

  static String _formatTimestampForFileName(DateTime timestamp) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    String threeDigits(int value) => value.toString().padLeft(3, '0');
    return '${timestamp.year}'
        '${twoDigits(timestamp.month)}'
        '${twoDigits(timestamp.day)}_'
        '${twoDigits(timestamp.hour)}'
        '${twoDigits(timestamp.minute)}'
        '${twoDigits(timestamp.second)}_'
        '${threeDigits(timestamp.millisecond)}';
  }

  static String _ensurePngExtension(String path) {
    if (p.extension(path).toLowerCase() == '.png') {
      return path;
    }
    return p.setExtension(path, '.png');
  }

  static String _sanitizeFileName(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'bake.png';
    }
    return trimmed.replaceAll(RegExp(r'[\\\\/:*?"<>|]+'), '_');
  }
}
