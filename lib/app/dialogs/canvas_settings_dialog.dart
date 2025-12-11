import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../canvas/canvas_settings.dart';
import 'misarin_dialog.dart';

enum WorkspacePreset { none, illustration, celShading, pixel }

class NewProjectConfig {
  const NewProjectConfig({
    required this.name,
    required this.settings,
    required this.workspacePreset,
  });

  final String name;
  final CanvasSettings settings;
  final WorkspacePreset workspacePreset;
}

class _ResolutionPreset {
  const _ResolutionPreset({
    required this.width,
    required this.height,
    required this.label,
  });

  final int width;
  final int height;
  final String label;
}

class _WorkspacePresetOption {
  const _WorkspacePresetOption({
    required this.preset,
    required this.title,
    required this.changes,
  });

  final WorkspacePreset preset;
  final String title;
  final List<String> changes;
}

Future<NewProjectConfig?> showCanvasSettingsDialog(
  BuildContext context, {
  CanvasSettings? initialSettings,
}) {
  return showDialog<NewProjectConfig>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _CanvasSettingsDialog(
      initialSettings: initialSettings ?? CanvasSettings.defaults,
    ),
  );
}

class _CanvasSettingsDialog extends StatefulWidget {
  const _CanvasSettingsDialog({required this.initialSettings});

  final CanvasSettings initialSettings;

  @override
  State<_CanvasSettingsDialog> createState() => _CanvasSettingsDialogState();
}

class _CanvasSettingsDialogState extends State<_CanvasSettingsDialog> {
  static const List<_ResolutionPreset> _presets = <_ResolutionPreset>[
    _ResolutionPreset(width: 7680, height: 4320, label: '8K UHD (7680 × 4320)'),
    _ResolutionPreset(width: 3840, height: 2160, label: '4K UHD (3840 × 2160)'),
    _ResolutionPreset(width: 2560, height: 1440, label: 'QHD (2560 × 1440)'),
    _ResolutionPreset(width: 1920, height: 1080, label: 'FHD (1920 × 1080)'),
    _ResolutionPreset(width: 1600, height: 1200, label: 'UXGA (1600 × 1200)'),
    _ResolutionPreset(width: 1280, height: 720, label: 'HD (1280 × 720)'),
    _ResolutionPreset(width: 1080, height: 1920, label: '移动端纵向 (1080 × 1920)'),
    _ResolutionPreset(width: 1024, height: 1024, label: '方形 (1024 × 1024)'),
    _ResolutionPreset(width: 64, height: 64, label: '像素画 (64 × 64)'),
    _ResolutionPreset(width: 32, height: 32, label: '像素画 (32 × 32)'),
    _ResolutionPreset(width: 16, height: 16, label: '像素画 (16 × 16)'),
  ];

  static const int _minDimension = 1;
  static const int _maxDimension = 16000;
  static const List<_WorkspacePresetOption> _workspacePresets =
      <_WorkspacePresetOption>[
        _WorkspacePresetOption(
          preset: WorkspacePreset.illustration,
          title: '插画',
          changes: <String>['画笔边缘柔化设为 1 级'],
        ),
        _WorkspacePresetOption(
          preset: WorkspacePreset.celShading,
          title: '赛璐璐',
          changes: <String>['画笔边缘柔化设为 0 级', '油漆桶吞并色线：开启', '油漆桶边缘柔化：关闭'],
        ),
        _WorkspacePresetOption(
          preset: WorkspacePreset.pixel,
          title: '像素',
          changes: <String>['笔刷/油漆桶边缘柔化设为 0 级', '显示网格：开启', '矢量作画：关闭'],
        ),
        _WorkspacePresetOption(
          preset: WorkspacePreset.none,
          title: '默认',
          changes: <String>['不更改当前工具参数'],
        ),
      ];

  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _nameController;
  late Color _selectedColor;
  _ResolutionPreset? _selectedPreset;
  WorkspacePreset _selectedWorkspacePreset = WorkspacePreset.none;
  CanvasRenderBackend _selectedRenderBackend = CanvasRenderBackend.cpu;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(
      text: widget.initialSettings.width.round().toString(),
    );
    _heightController = TextEditingController(
      text: widget.initialSettings.height.round().toString(),
    );
    _widthController.addListener(_handleDimensionChanged);
    _heightController.addListener(_handleDimensionChanged);
    _nameController = TextEditingController(text: '未命名项目');
    _selectedColor = widget.initialSettings.backgroundColor;
    _selectedPreset = _matchPreset(
      widget.initialSettings.width.round(),
      widget.initialSettings.height.round(),
    );
    _selectedRenderBackend = widget.initialSettings.renderBackend;
  }

  @override
  void dispose() {
    _widthController.removeListener(_handleDimensionChanged);
    _heightController.removeListener(_handleDimensionChanged);
    _widthController.dispose();
    _heightController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final int? width = int.tryParse(_widthController.text);
    final int? height = int.tryParse(_heightController.text);
    if (width == null || height == null) {
      setState(() => _errorMessage = '请输入有效的分辨率');
      return;
    }
    if (width < _minDimension || height < _minDimension) {
      setState(() => _errorMessage = '分辨率不能小于 $_minDimension 像素');
      return;
    }
    if (width > _maxDimension || height > _maxDimension) {
      setState(() => _errorMessage = '分辨率不能超过 $_maxDimension 像素');
      return;
    }

    final String rawName = _nameController.text.trim();
    final String resolvedName = rawName.isEmpty ? '未命名项目' : rawName;
    setState(() => _errorMessage = null);
    Navigator.of(context).pop(
      NewProjectConfig(
        name: resolvedName,
        settings: CanvasSettings(
          width: width.toDouble(),
          height: height.toDouble(),
          backgroundColor: _selectedColor,
          renderBackend: _selectedRenderBackend,
        ),
        workspacePreset: _selectedWorkspacePreset,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return MisarinDialog(
      title: const Text('新建画布设置'),
      contentWidth: 420,
      maxWidth: 520,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoLabel(
                label: '项目名称',
                child: TextBox(
                  controller: _nameController,
                  placeholder: '未命名项目',
                ),
              ),
              const SizedBox(height: 12),
              InfoLabel(
                label: '工作预设',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '创建画布时自动应用常用工具参数。',
                      style:
                          theme.typography.caption ??
                          const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _workspacePresets
                          .map((option) => _buildPresetButton(theme, option))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    _buildPresetDescription(theme),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InfoLabel(
                label: '渲染后端',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ComboBox<CanvasRenderBackend>(
                      isExpanded: true,
                      value: _selectedRenderBackend,
                      items: const [
                        ComboBoxItem(
                          value: CanvasRenderBackend.cpu,
                          child: Text('CPU（默认稳定）'),
                        ),
                        ComboBoxItem(
                          value: CanvasRenderBackend.gpu,
                          child: Text('GPU（实验性，仅基础画笔）'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _selectedRenderBackend = value);
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'GPU 画布走独立的着色器渲染路径，目前只有基础画笔功能，后续会逐步完善。',
                      style:
                          theme.typography.caption ??
                          const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InfoLabel(
                label: '分辨率预设',
                child: ComboBox<_ResolutionPreset?>(
                  isExpanded: true,
                  value: _selectedPreset,
                  items: [
                    const ComboBoxItem<_ResolutionPreset?>(
                      value: null,
                      child: Text('自定义'),
                    ),
                    ..._presets.map(
                      (preset) => ComboBoxItem<_ResolutionPreset?>(
                        value: preset,
                        child: Text(preset.label),
                      ),
                    ),
                  ],
                  onChanged: (value) => _applyPreset(value),
                ),
              ),
              const SizedBox(height: 12),
              InfoLabel(
                label: '自定义分辨率',
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormBox(
                        controller: _widthController,
                        placeholder: '宽度（像素）',
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('×'),
                    ),
                    Expanded(
                      child: TextFormBox(
                        controller: _heightController,
                        placeholder: '高度（像素）',
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _sizePreviewText(),
                style:
                    theme.typography.caption ?? const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              InfoLabel(
                label: '背景颜色',
                child: ComboBox<Color>(
                  isExpanded: true,
                  icon: const Icon(FluentIcons.color),
                  value: _selectedColor,
                  items: const [
                    ComboBoxItem(value: Color(0xFFFFFFFF), child: Text('白色')),
                    ComboBoxItem(value: Color(0xFFF5F5F5), child: Text('浅灰')),
                    ComboBoxItem(value: Color(0xFF000000), child: Text('黑色')),
                  ],
                  onChanged: (color) {
                    if (color == null) {
                      return;
                    }
                    setState(() => _selectedColor = color);
                  },
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.warningPrimaryColor),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _handleSubmit, child: const Text('创建')),
      ],
    );
  }

  void _applyPreset(_ResolutionPreset? preset) {
    setState(() => _selectedPreset = preset);
    if (preset == null) {
      return;
    }
    _widthController.text = preset.width.toString();
    _heightController.text = preset.height.toString();
  }

  void _handleDimensionChanged() {
    final int? width = int.tryParse(_widthController.text);
    final int? height = int.tryParse(_heightController.text);
    final _ResolutionPreset? matched = width == null || height == null
        ? null
        : _matchPreset(width, height);
    if (matched != _selectedPreset) {
      setState(() => _selectedPreset = matched);
    }
  }

  String _sizePreviewText() {
    final int? width = int.tryParse(_widthController.text);
    final int? height = int.tryParse(_heightController.text);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return '请输入有效的宽高数值';
    }
    final String ratio = _formatAspectRatio(width, height);
    return '最终尺寸：$width × $height 像素（比例 $ratio）';
  }

  _ResolutionPreset? _matchPreset(int width, int height) {
    if (width <= 0 || height <= 0) {
      return null;
    }
    for (final preset in _presets) {
      if (preset.width == width && preset.height == height) {
        return preset;
      }
    }
    return null;
  }

  String _formatAspectRatio(int width, int height) {
    final int gcd = _gcd(width, height);
    final int normalizedWidth = math.max(1, width ~/ gcd);
    final int normalizedHeight = math.max(1, height ~/ gcd);
    return '$normalizedWidth:$normalizedHeight';
  }

  int _gcd(int a, int b) {
    a = a.abs();
    b = b.abs();
    if (a == 0 && b == 0) {
      return 1;
    }
    if (b == 0) {
      return a == 0 ? 1 : a;
    }
    while (b != 0) {
      final int temp = a % b;
      a = b;
      b = temp;
    }
    return a == 0 ? 1 : a;
  }

  Widget _buildPresetButton(
    FluentThemeData theme,
    _WorkspacePresetOption option,
  ) {
    final bool selected = _selectedWorkspacePreset == option.preset;
    final ButtonStyle style = ButtonStyle(
      padding: WidgetStateProperty.all(const EdgeInsets.all(12)),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (selected) {
          return theme.accentColor.withOpacity(0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return theme.resources.controlFillColorSecondary;
        }
        return theme.resources.controlFillColorDefault;
      }),
      shape: WidgetStateProperty.all<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected
                ? theme.accentColor
                : theme.resources.controlStrokeColorDefault,
          ),
        ),
      ),
    );

    return Button(
      style: style,
      onPressed: () => setState(() {
        _selectedWorkspacePreset = option.preset;
      }),
      child: SizedBox(
        width: 100,
        child: Center(
          child: Text(option.title, style: theme.typography.bodyStrong),
        ),
      ),
    );
  }

  Widget _buildPresetDescription(FluentThemeData theme) {
    final _WorkspacePresetOption option = _workspacePresets.firstWhere(
      (item) => item.preset == _selectedWorkspacePreset,
      orElse: () => _workspacePresets.last,
    );
    final TextStyle caption =
        theme.typography.caption ?? const TextStyle(fontSize: 12);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorTertiary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前预设：${option.title}', style: theme.typography.bodyStrong),
            const SizedBox(height: 6),
            ...option.changes.map(
              (text) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(text, style: caption)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
