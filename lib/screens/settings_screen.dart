import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_config_service.dart';
import '../services/recognition_service.dart';
import '../services/storage_service.dart';
import 'ocr_settings_screen.dart';

/// 设置页面
/// 包含识别模式、云端配置、默认参数、外观设置、缓存管理、关于信息
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? '已切换到云端识别' : '已切换到本地识别'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// 清除临时文件缓存
  Future<void> _clearCache() async {
    setState(() => _isClearing = true);
    try {
      await StorageService.cleanupTemp();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('临时文件已清除')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除失败: $e')),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('参数已重置为默认值')),
      );
    }
  }

  /// 更新滑块值并实时保存
  Future<void> _updateThreshold(double value) async {
    setState(() => _threshold = value);
    await _config.setThreshold(value);
  }

  Future<void> _updateContrast(double value) async {
    setState(() => _contrast = value);
    await _config.setContrast(value);
  }

  Future<void> _updateSmoothness(double value) async {
    setState(() => _smoothness = value);
    await _config.setSmoothness(value);
  }

  Future<void> _updateStrokeWidth(double value) async {
    setState(() => _strokeWidth = value);
    await _config.setStrokeWidth(value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ===== 识别模式 =====
                _buildSectionHeader(context, '识别模式', Icons.auto_fix_high),
                _buildRecognitionSection(colorScheme),

                const SizedBox(height: 8),

                // ===== 默认参数 =====
                _buildSectionHeader(context, '默认处理参数', Icons.tune),
                _buildParamsSection(colorScheme),

                const SizedBox(height: 8),

                // ===== 外观 =====
                _buildSectionHeader(context, '外观', Icons.palette),
                _buildAppearanceSection(colorScheme),

                const SizedBox(height: 8),

                // ===== 缓存管理 =====
                _buildSectionHeader(context, '存储管理', Icons.storage),
                _buildStorageSection(colorScheme),

                const SizedBox(height: 8),

                // ===== 关于 =====
                _buildSectionHeader(context, '关于', Icons.info_outline),
                _buildAboutSection(colorScheme),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  /// 分段标题
  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 识别模式切换区域
  Widget _buildRecognitionSection(ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // 本地识别选项
          RadioListTile<bool>(
            value: false,
            groupValue: _useCloud,
            onChanged: (v) => _toggleUseCloud(v!),
            title: const Text('本地 ML Kit'),
            subtitle: const Text('离线识别，无需网络，免费使用'),
            secondary: Icon(
              Icons.phone_android,
              color: _useCloud
                  ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                  : colorScheme.primary,
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          // 云端识别选项
          RadioListTile<bool>(
            value: true,
            groupValue: _useCloud,
            onChanged: (v) => _toggleUseCloud(v!),
            title: const Text('云端 DeepSeek-OCR'),
            subtitle: const Text('更高精度，需要网络和 API Key'),
            secondary: Icon(
              Icons.cloud_outlined,
              color: _useCloud
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
          // 云端配置入口
          if (_useCloud) ...[
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ListTile(
              leading: Icon(Icons.settings, color: colorScheme.secondary),
              title: const Text('云端配置'),
              subtitle: const Text('API 地址、Key、模型'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OcrSettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  /// 默认处理参数区域
  Widget _buildParamsSection(ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            // 阈值
            _buildSliderRow(
              label: '阈值',
              value: _threshold,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              colorScheme: colorScheme,
              onChanged: _updateThreshold,
            ),
            const SizedBox(height: 8),

            // 对比度
            _buildSliderRow(
              label: '对比度',
              value: _contrast,
              min: 0.5,
              max: 3.0,
              divisions: 25,
              colorScheme: colorScheme,
              onChanged: _updateContrast,
            ),
            const SizedBox(height: 8),

            // 平滑度
            _buildSliderRow(
              label: '平滑度',
              value: _smoothness,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              colorScheme: colorScheme,
              onChanged: _updateSmoothness,
            ),
            const SizedBox(height: 8),

            // 笔画宽度
            _buildSliderRow(
              label: '笔画宽度',
              value: _strokeWidth,
              min: 0.5,
              max: 3.0,
              divisions: 25,
              colorScheme: colorScheme,
              onChanged: _updateStrokeWidth,
            ),
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
      ),
    );
  }

  /// 滑块行
  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ColorScheme colorScheme,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  /// 外观设置区域（深色模式切换）
  Widget _buildAppearanceSection(ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          RadioListTile<String>(
            value: 'light',
            groupValue: _themeMode,
            onChanged: (v) => _setThemeMode(v!),
            title: const Text('浅色'),
            secondary: Icon(
              Icons.light_mode,
              color: _themeMode == 'light'
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          RadioListTile<String>(
            value: 'dark',
            groupValue: _themeMode,
            onChanged: (v) => _setThemeMode(v!),
            title: const Text('深色'),
            secondary: Icon(
              Icons.dark_mode,
              color: _themeMode == 'dark'
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          RadioListTile<String>(
            value: 'system',
            groupValue: _themeMode,
            onChanged: (v) => _setThemeMode(v!),
            title: const Text('跟随系统'),
            secondary: Icon(
              Icons.settings_brightness,
              color: _themeMode == 'system'
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  /// 切换主题模式
  Future<void> _setThemeMode(String mode) async {
    await _config.setThemeMode(mode);
    if (mounted) {
      setState(() => _themeMode = mode);
      // 通知主页面刷新主题
      widget.onThemeChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('外观已切换为${_themeModeLabel(mode)}'),
          duration: const Duration(seconds: 1),
        ),
      );
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

  /// 存储管理区域
  Widget _buildStorageSection(ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListTile(
        leading: Icon(Icons.delete_sweep, color: colorScheme.error),
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
    );
  }

  /// 关于区域
  Widget _buildAboutSection(ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.info_outline, color: colorScheme.primary),
            title: const Text('版本'),
            subtitle: Text('v$_version'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Build $_buildNumber',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ListTile(
            leading: Icon(Icons.code, color: colorScheme.tertiary),
            title: const Text('开源协议'),
            subtitle: const Text('MIT License'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () {
              _showLicenseDialog(colorScheme);
            },
          ),
          Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ListTile(
            leading: Icon(Icons.language, color: colorScheme.secondary),
            title: const Text('GitHub'),
            subtitle: const Text('查看源代码'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () async {
              final uri = Uri.parse('https://github.com/MrLing1202/writefont');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('无法打开链接')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// 显示开源协议对话框
  void _showLicenseDialog(ColorScheme colorScheme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('MIT License'),
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
      ),
    );
  }
}
