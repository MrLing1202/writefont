import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_config_service.dart';
import '../services/recognition_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'ocr_settings_screen.dart';

/// 设置页面
/// 使用 WFCard 分组展示，支持深色模式实时切换
class SettingsScreen extends StatefulWidget {
  /// 主题变更回调，通知主页面刷新主题模式
  final VoidCallback? onThemeChanged;

  const SettingsScreen({super.key, this.onThemeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final RecognitionService _recognition = RecognitionService.instance;
  final AppConfigService _config = AppConfigService.instance;

  // 识别模式
  bool _useCloud = false;
  bool _isLoading = true;

  // 默认参数
  double _threshold = AppConfigService.defaultThreshold;
  double _contrast = AppConfigService.defaultContrast;
  double _smoothness = AppConfigService.defaultSmoothness;
  double _strokeWidth = AppConfigService.defaultStrokeWidth;

  // 缓存状态
  bool _isClearing = false;

  // 外观设置
  String _themeMode = AppConfigService.defaultThemeMode;

  // 版本信息
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 加载当前设置
  Future<void> _loadSettings() async {
    final useCloud = await _recognition.getUseCloud();
    final threshold = await _config.getThreshold();
    final contrast = await _config.getContrast();
    final smoothness = await _config.getSmoothness();
    final strokeWidth = await _config.getStrokeWidth();
    final themeMode = await _config.getThemeMode();
    final packageInfo = await PackageInfo.fromPlatform();

    if (mounted) {
      setState(() {
        _useCloud = useCloud;
        _threshold = threshold;
        _contrast = contrast;
        _smoothness = smoothness;
        _strokeWidth = strokeWidth;
        _themeMode = themeMode;
        _version = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
        _isLoading = false;
      });
    }
  }

  /// 切换识别模式
  Future<void> _toggleUseCloud(bool value) async {
    await _recognition.setUseCloud(value);
    if (mounted) {
      setState(() => _useCloud = value);
      WFSnackBar.show(context, value ? '已切换到云端识别' : '已切换到本地识别');
    }
  }

  /// 清除临时文件缓存
  Future<void> _clearCache() async {
    setState(() => _isClearing = true);
    try {
      await StorageService.cleanupTemp();
      if (mounted) {
        WFSnackBar.show(context, '临时文件已清除');
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '清除失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  /// 重置默认参数
  Future<void> _resetParams() async {
    await _config.resetParams();
    if (mounted) {
      setState(() {
        _threshold = AppConfigService.defaultThreshold;
        _contrast = AppConfigService.defaultContrast;
        _smoothness = AppConfigService.defaultSmoothness;
        _strokeWidth = AppConfigService.defaultStrokeWidth;
      });
      WFSnackBar.show(context, '参数已重置为默认值');
    }
  }

  /// 导出设置
  Future<void> _exportSettings() async {
    try {
      final settings = {
        'threshold': _threshold,
        'contrast': _contrast,
        'smoothness': _smoothness,
        'strokeWidth': _strokeWidth,
        'themeMode': _themeMode,
        'useCloud': _useCloud,
        'exportedAt': DateTime.now().toIso8601String(),
        'version': '1.1.7',
      };
      final jsonString = const JsonEncoder.withIndent('  ').convert(settings);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/writefont_settings.json');
      await file.writeAsString(jsonString);

      if (mounted) {
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'WriteFont 设置备份',
          text: 'WriteFont 设置文件',
        );
        WFSnackBar.show(context, '设置已导出');
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '导出失败: $e');
      }
    }
  }

  /// 导入设置
  Future<void> _importSettings() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: '选择 WriteFont 设置文件',
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final file = File(filePath);
      final jsonString = await file.readAsString();
      final settings = jsonDecode(jsonString) as Map<String, dynamic>;

      // 校验
      if (!settings.containsKey('version')) {
        if (mounted) WFSnackBar.error(context, '无效的设置文件');
        return;
      }

      // 应用设置
      if (settings.containsKey('threshold')) {
        await _config.setThreshold((settings['threshold'] as num).toDouble());
      }
      if (settings.containsKey('contrast')) {
        await _config.setContrast((settings['contrast'] as num).toDouble());
      }
      if (settings.containsKey('smoothness')) {
        await _config.setSmoothness((settings['smoothness'] as num).toDouble());
      }
      if (settings.containsKey('strokeWidth')) {
        await _config.setStrokeWidth((settings['strokeWidth'] as num).toDouble());
      }
      if (settings.containsKey('themeMode')) {
        await _config.setThemeMode(settings['themeMode'] as String);
        widget.onThemeChanged?.call();
      }
      if (settings.containsKey('useCloud')) {
        await _recognition.setUseCloud(settings['useCloud'] as bool);
      }

      // 重新加载 UI
      await _loadSettings();

      if (mounted) {
        WFSnackBar.show(context, '设置已导入');
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '导入失败: $e');
      }
    }
  }

  /// 更新滑块值（仅 UI），保存在 onChangeEnd 中触发
  void _onThresholdChanged(double value) {
    setState(() => _threshold = value);
  }

  void _onContrastChanged(double value) {
    setState(() => _contrast = value);
  }

  void _onSmoothnessChanged(double value) {
    setState(() => _smoothness = value);
  }

  void _onStrokeWidthChanged(double value) {
    setState(() => _strokeWidth = value);
  }

  /// 滑块松手后持久化保存
  Future<void> _onThresholdChangeEnd(double value) async {
    await _config.setThreshold(value);
  }

  Future<void> _onContrastChangeEnd(double value) async {
    await _config.setContrast(value);
  }

  Future<void> _onSmoothnessChangeEnd(double value) async {
    await _config.setSmoothness(value);
  }

  Future<void> _onStrokeWidthChangeEnd(double value) async {
    await _config.setStrokeWidth(value);
  }

  /// 切换主题模式
  Future<void> _setThemeMode(String mode) async {
    await _config.setThemeMode(mode);
    if (mounted) {
      setState(() => _themeMode = mode);
      // 通知主页面刷新主题
      widget.onThemeChanged?.call();
      WFSnackBar.show(context, '外观已切换为${_themeModeLabel(mode)}');
    }
  }

  /// 主题模式中文标签
  String _themeModeLabel(String mode) {
    switch (mode) {
      case 'light':
        return '浅色';
      case 'dark':
        return '深色';
      case 'system':
      default:
        return '跟随系统';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WFAppBar(title: '设置'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              children: [
                // ═══ 外观 ═══
                _buildSectionHeader('外观', Icons.palette),
                _buildAppearanceCard(),
                const SizedBox(height: 16),

                // ═══ 识别设置 ═══
                _buildSectionHeader('识别设置', Icons.auto_fix_high),
                _buildRecognitionCard(),
                const SizedBox(height: 16),

                // ═══ 字体生成 ═══
                _buildSectionHeader('字体生成', Icons.tune),
                _buildParamsCard(),
                const SizedBox(height: 16),

                // ═══ 存储 ═══
                _buildSectionHeader('存储', Icons.storage),
                _buildStorageCard(),
                const SizedBox(height: 16),

                // ═══ 关于 ═══
                _buildSectionHeader('关于', Icons.info_outline),
                _buildAboutCard(),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  /// 分段标题 — 使用 WFColors 配色
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: WFColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: WFColors.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 外观设置
  // ═══════════════════════════════════════════════════════════

  Widget _buildAppearanceCard() {
    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // 浅色模式
          _buildThemeRadioTile(
            mode: 'light',
            icon: Icons.light_mode,
            title: '浅色',
          ),
          _buildDivider(),
          // 深色模式
          _buildThemeRadioTile(
            mode: 'dark',
            icon: Icons.dark_mode,
            title: '深色',
          ),
          _buildDivider(),
          // 跟随系统
          _buildThemeRadioTile(
            mode: 'system',
            icon: Icons.settings_brightness,
            title: '跟随系统',
          ),
        ],
      ),
    );
  }

  Widget _buildThemeRadioTile({
    required String mode,
    required IconData icon,
    required String title,
  }) {
    final isActive = _themeMode == mode;
    return ListTile(
      leading: Icon(
        icon,
        color: isActive ? WFColors.primary : WFColors.textLight,
      ),
      title: Text(title),
      trailing: Radio<String>(
        value: mode,
        groupValue: _themeMode,
        onChanged: (v) => _setThemeMode(v!),
        activeColor: WFColors.primary,
      ),
      onTap: () => _setThemeMode(mode),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 识别设置
  // ═══════════════════════════════════════════════════════════

  Widget _buildRecognitionCard() {
    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // 本地识别
          RadioListTile<bool>(
            value: false,
            groupValue: _useCloud,
            onChanged: (v) => _toggleUseCloud(v!),
            title: const Text('本地识别'),
            subtitle: const Text('离线识别，无需网络，免费使用'),
            secondary: Icon(
              Icons.phone_android,
              color: _useCloud ? WFColors.textLight : WFColors.primary,
            ),
            activeColor: WFColors.primary,
          ),
          _buildDivider(),
          // 云端识别
          RadioListTile<bool>(
            value: true,
            groupValue: _useCloud,
            onChanged: (v) => _toggleUseCloud(v!),
            title: const Text('云端 DeepSeek-OCR'),
            subtitle: const Text('更高精度，需要网络和 API Key'),
            secondary: Icon(
              Icons.cloud_outlined,
              color: _useCloud ? WFColors.primary : WFColors.textLight,
            ),
            activeColor: WFColors.primary,
          ),
          // 云端配置入口
          if (_useCloud) ...[
            _buildDivider(),
            ListTile(
              leading: const Icon(Icons.settings, color: WFColors.accent),
              title: const Text('云端配置'),
              subtitle: const Text('API 地址、Key、模型'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  WFAnimations.slideRoute(const OcrSettingsScreen()),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 字体生成参数
  // ═══════════════════════════════════════════════════════════

  Widget _buildParamsCard() {
    return WFCard(
      child: Column(
        children: [
          _buildSliderRow(
            label: '阈值',
            value: _threshold,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: _onThresholdChanged,
            onChangeEnd: _onThresholdChangeEnd,
          ),
          _buildParamHint('控制二值化分割点，值越大笔画越粗'),
          const SizedBox(height: 8),
          _buildSliderRow(
            label: '对比度',
            value: _contrast,
            min: 0.5,
            max: 3.0,
            divisions: 25,
            onChanged: _onContrastChanged,
            onChangeEnd: _onContrastChangeEnd,
          ),
          _buildParamHint('增强手写图片对比度，照片较淡时增大此值'),
          const SizedBox(height: 8),
          _buildSliderRow(
            label: '平滑度',
            value: _smoothness,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: _onSmoothnessChanged,
            onChangeEnd: _onSmoothnessChangeEnd,
          ),
          _buildParamHint('控制轮廓平滑程度，值越大笔画越圆润'),
          const SizedBox(height: 8),
          _buildSliderRow(
            label: '笔画宽度',
            value: _strokeWidth,
            min: 0.5,
            max: 3.0,
            divisions: 25,
            onChanged: _onStrokeWidthChanged,
            onChangeEnd: _onStrokeWidthChangeEnd,
          ),
          _buildParamHint('输出字体的基础笔画粗细'),
          const SizedBox(height: 12),
          // 重置按钮
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _resetParams,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重置为默认值'),
            ),
          ),
        ],
      ),
    );
  }

  /// 滑块行 — 统一样式，onChangeEnd 时才持久化保存
  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: WFColors.textPrimary,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: WFColors.primary,
              thumbColor: WFColors.primary,
              inactiveTrackColor: WFColors.textLight.withValues(alpha: 0.3),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: WFColors.textSecondary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  /// 参数说明行
  Widget _buildParamHint(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 72, top: 2, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: WFColors.textLight,
          height: 1.3,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 存储管理
  // ═══════════════════════════════════════════════════════════

  Widget _buildStorageCard() {
    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file, color: WFColors.primary),
            title: const Text('导出设置'),
            subtitle: const Text('将当前设置导出为 JSON 文件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _exportSettings,
          ),
          _buildDivider(),
          ListTile(
            leading: const Icon(Icons.download, color: WFColors.accent),
            title: const Text('导入设置'),
            subtitle: const Text('从 JSON 文件恢复设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _importSettings,
          ),
          _buildDivider(),
          ListTile(
            leading: const Icon(Icons.delete_sweep, color: WFColors.error),
            title: const Text('清除临时文件'),
            subtitle: const Text('清除识别和处理过程中产生的临时图片'),
            trailing: _isClearing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isClearing ? null : _clearCache,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 关于
  // ═══════════════════════════════════════════════════════════

  Widget _buildAboutCard() {
    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // 版本号
          ListTile(
            leading: const Icon(Icons.info_outline, color: WFColors.primary),
            title: const Text('版本'),
            subtitle: Text('v$_version'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: WFColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Build $_buildNumber',
                style: const TextStyle(
                  fontSize: 11,
                  color: WFColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          _buildDivider(),
          // 开源协议
          ListTile(
            leading: const Icon(Icons.code, color: WFColors.info),
            title: const Text('开源协议'),
            subtitle: const Text('MIT License'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _showLicenseDialog(),
          ),
          _buildDivider(),
          // GitHub
          ListTile(
            leading: const Icon(Icons.language, color: WFColors.accent),
            title: const Text('GitHub'),
            subtitle: const Text('查看源代码'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () async {
              final uri = Uri.parse('https://github.com/MrLing1202/writefont');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (mounted) {
                  WFSnackBar.error(context, '无法打开链接');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════════════════

  /// 统一分隔线
  Widget _buildDivider() {
    return Divider(
      height: 1,
      color: WFColors.textLight.withValues(alpha: 0.3),
    );
  }

  /// 显示开源协议对话框 — 使用 WFDialog 样式
  void _showLicenseDialog() {
    WFDialog.show(
      context,
      title: 'MIT License',
      content: const SingleChildScrollView(
        child: Text(
          'MIT License\n\n'
          'Copyright (c) 2024 WriteFont\n\n'
          'Permission is hereby granted, free of charge, to any person obtaining a copy '
          'of this software and associated documentation files (the "Software"), to deal '
          'in the Software without restriction, including without limitation the rights '
          'to use, copy, modify, merge, publish, distribute, sublicense, and/or sell '
          'copies of the Software, and to permit persons to whom the Software is '
          'furnished to do so, subject to the following conditions:\n\n'
          'The above copyright notice and this permission notice shall be included in all '
          'copies or substantial portions of the Software.\n\n'
          'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR '
          'IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, '
          'FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE '
          'AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER '
          'LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, '
          'OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE '
          'SOFTWARE.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
