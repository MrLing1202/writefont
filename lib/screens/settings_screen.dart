import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../generated/l10n/app_localizations.dart';
import '../services/app_config_service.dart';
import '../services/locale_service.dart';
import '../services/recognition_service.dart';
import '../services/storage_service.dart';
import '../services/cloud_sync_service.dart';
import '../theme/app_theme.dart';
import 'cloud_sync_screen.dart';
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

  // 云同步状态
  String _syncStatus = 'none'; // none | synced | pending

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

    // 云同步状态
    String syncStatus = 'none';
    try {
      final cloudSync = CloudSyncService.instance;
      await cloudSync.init();
      if (cloudSync.isSignedIn()) {
        final statusMap = await cloudSync.getSyncStatus();
        final hasPending = statusMap.values.any((s) => s != 'synced');
        syncStatus = hasPending ? 'pending' : 'synced';
      }
    } catch (_) {
      // 同步服务不可用时静默处理
    }

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
        _syncStatus = syncStatus;
        _isLoading = false;
      });
    }
  }

  /// 切换识别模式
  Future<void> _toggleUseCloud(bool value) async {
    await _recognition.setUseCloud(value);
    if (mounted) {
      setState(() => _useCloud = value);
      final l10n = AppLocalizations.of(context);
      WFSnackBar.show(context, value ? l10n.switchedToCloud : l10n.switchedToLocal);
    }
  }

  /// 清除临时文件缓存
  Future<void> _clearCache() async {
    setState(() => _isClearing = true);
    try {
      await StorageService.cleanupTemp();
      if (mounted) {
        WFSnackBar.show(context, AppLocalizations.of(context).tempFilesCleared);
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, AppLocalizations.of(context).clearFailed('$e'));
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
      WFSnackBar.show(context, AppLocalizations.of(context).paramsReset);
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
        final l10n = AppLocalizations.of(context);
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: l10n.settingsBackupSubject,
          text: l10n.settingsBackupText,
        );
        WFSnackBar.show(context, l10n.settingsExported);
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, AppLocalizations.of(context).exportFailed('$e'));
      }
    }
  }

  /// 导入设置
  Future<void> _importSettings() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: AppLocalizations.of(context).selectSettingsFile,
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final file = File(filePath);
      final jsonString = await file.readAsString();
      final settings = jsonDecode(jsonString) as Map<String, dynamic>;

      // 校验
      if (!settings.containsKey('version')) {
        if (mounted) WFSnackBar.error(context, AppLocalizations.of(context).invalidSettingsFile);
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
        WFSnackBar.show(context, AppLocalizations.of(context).settingsImported);
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, AppLocalizations.of(context).importFailed('$e'));
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
      WFSnackBar.show(context, AppLocalizations.of(context).appearanceChanged(_themeModeLabel(mode)));
    }
  }

  /// 主题模式标签
  String _themeModeLabel(String mode) {
    final l10n = AppLocalizations.of(context);
    switch (mode) {
      case 'light':
        return l10n.lightMode;
      case 'dark':
        return l10n.darkMode;
      case 'system':
      default:
        return l10n.followSystem;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: WFAppBar(title: l10n.settings),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              children: [
                // ═══ 外观 ═══
                _buildSectionHeader(l10n.appearance, Icons.palette),
                _buildAppearanceCard(),
                const SizedBox(height: 16),

                // ═══ 语言 ═══
                _buildSectionHeader(l10n.language, Icons.language),
                _buildLanguageCard(),
                const SizedBox(height: 16),

                // ═══ 识别设置 ═══
                _buildSectionHeader(l10n.recognitionSettings, Icons.auto_fix_high),
                _buildRecognitionCard(),
                const SizedBox(height: 16),

                // ═══ 字体生成 ═══
                _buildSectionHeader(l10n.fontGeneration, Icons.tune),
                _buildParamsCard(),
                const SizedBox(height: 16),

                // ═══ 存储 ═══
                _buildSectionHeader(l10n.storage, Icons.storage),
                _buildStorageCard(),
                const SizedBox(height: 16),

                // ═══ 云同步 ═══
                _buildSectionHeader(l10n.cloudSync, Icons.cloud_sync),
                _buildCloudSyncCard(),
                const SizedBox(height: 16),

                // ═══ 关于 ═══
                _buildSectionHeader(l10n.about, Icons.info_outline),
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
    final l10n = AppLocalizations.of(context);
    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _buildThemeRadioTile(
            mode: 'light',
            icon: Icons.light_mode,
            title: l10n.lightMode,
          ),
          _buildDivider(),
          _buildThemeRadioTile(
            mode: 'dark',
            icon: Icons.dark_mode,
            title: l10n.darkMode,
          ),
          _buildDivider(),
          _buildThemeRadioTile(
            mode: 'system',
            icon: Icons.settings_brightness,
            title: l10n.followSystem,
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
  // 语言设置
  // ═══════════════════════════════════════════════════════════

  Widget _buildLanguageCard() {
    final localeService = LocaleService.instance;
    final currentCode = localeService.locale.languageCode;

    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _buildLanguageRadioTile(
            code: 'zh',
            icon: Icons.language,
            title: '中文',
          ),
          _buildDivider(),
          _buildLanguageRadioTile(
            code: 'en',
            icon: Icons.language,
            title: 'English',
          ),
          _buildDivider(),
          _buildLanguageRadioTile(
            code: 'ja',
            icon: Icons.language,
            title: '日本語',
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageRadioTile({
    required String code,
    required IconData icon,
    required String title,
  }) {
    final localeService = LocaleService.instance;
    final isActive = localeService.locale.languageCode == code;
    return ListTile(
      leading: Icon(
        icon,
        color: isActive ? WFColors.primary : WFColors.textLight,
      ),
      title: Text(title),
      trailing: Radio<String>(
        value: code,
        groupValue: localeService.locale.languageCode,
        onChanged: (v) => _setLocale(v!),
        activeColor: WFColors.primary,
      ),
      onTap: () => _setLocale(code),
    );
  }

  Future<void> _setLocale(String code) async {
    await LocaleService.instance.setLocale(Locale(code));
    if (mounted) {
      WFSnackBar.show(context, AppLocalizations.of(context).languageChanged(LocaleService.instance.currentLocaleName));
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 识别设置
  // ═══════════════════════════════════════════════════════════

  Widget _buildRecognitionCard() {
    final l10n = AppLocalizations.of(context);
    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          RadioListTile<bool>(
            value: false,
            groupValue: _useCloud,
            onChanged: (v) => _toggleUseCloud(v!),
            title: Text(l10n.localRecognition),
            subtitle: Text(l10n.localRecognitionDesc),
            secondary: Icon(
              Icons.phone_android,
              color: _useCloud ? WFColors.textLight : WFColors.primary,
            ),
            activeColor: WFColors.primary,
          ),
          _buildDivider(),
          RadioListTile<bool>(
            value: true,
            groupValue: _useCloud,
            onChanged: (v) => _toggleUseCloud(v!),
            title: Text(l10n.cloudRecognition),
            subtitle: Text(l10n.cloudRecognitionDesc),
            secondary: Icon(
              Icons.cloud_outlined,
              color: _useCloud ? WFColors.primary : WFColors.textLight,
            ),
            activeColor: WFColors.primary,
          ),
          if (_useCloud) ...[
            _buildDivider(),
            ListTile(
              leading: const Icon(Icons.settings, color: WFColors.accent),
              title: Text(l10n.cloudConfig),
              subtitle: Text(l10n.cloudConfigDesc),
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
    final l10n = AppLocalizations.of(context);
    return WFCard(
      child: Column(
        children: [
          _buildSliderRow(
            label: l10n.threshold,
            value: _threshold,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: _onThresholdChanged,
            onChangeEnd: _onThresholdChangeEnd,
          ),
          _buildParamHint(l10n.thresholdDesc),
          const SizedBox(height: 8),
          _buildSliderRow(
            label: l10n.contrast,
            value: _contrast,
            min: 0.5,
            max: 3.0,
            divisions: 25,
            onChanged: _onContrastChanged,
            onChangeEnd: _onContrastChangeEnd,
          ),
          _buildParamHint(l10n.contrastDesc),
          const SizedBox(height: 8),
          _buildSliderRow(
            label: l10n.smoothness,
            value: _smoothness,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: _onSmoothnessChanged,
            onChangeEnd: _onSmoothnessChangeEnd,
          ),
          _buildParamHint(l10n.smoothnessDesc),
          const SizedBox(height: 8),
          _buildSliderRow(
            label: l10n.strokeWidth,
            value: _strokeWidth,
            min: 0.5,
            max: 3.0,
            divisions: 25,
            onChanged: _onStrokeWidthChanged,
            onChangeEnd: _onStrokeWidthChangeEnd,
          ),
          _buildParamHint(l10n.strokeWidthDesc),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _resetParams,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.resetToDefault),
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
    final l10n = AppLocalizations.of(context);
    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file, color: WFColors.primary),
            title: Text(l10n.exportSettings),
            subtitle: Text(l10n.exportSettingsDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: _exportSettings,
          ),
          _buildDivider(),
          ListTile(
            leading: const Icon(Icons.download, color: WFColors.accent),
            title: Text(l10n.importSettings),
            subtitle: Text(l10n.importSettingsDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: _importSettings,
          ),
          _buildDivider(),
          ListTile(
            leading: const Icon(Icons.delete_sweep, color: WFColors.error),
            title: Text(l10n.clearTempFiles),
            subtitle: Text(l10n.clearTempFilesDesc),
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
  // 云同步
  // ═══════════════════════════════════════════════════════════

  Widget _buildCloudSyncCard() {
    final l10n = AppLocalizations.of(context);
    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_sync, color: WFColors.primary),
            title: Text(l10n.cloudSync),
            subtitle: Text(l10n.cloudSyncDesc),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 同步状态指示灯
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _syncStatus == 'synced'
                        ? WFColors.success
                        : _syncStatus == 'pending'
                            ? WFColors.warning
                            : WFColors.textLight,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () async {
              await Navigator.push(
                context,
                WFAnimations.slideRoute(const CloudSyncScreen()),
              );
              // 返回时刷新同步状态
              _loadSettings();
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 关于
  // ═══════════════════════════════════════════════════════════

  Widget _buildAboutCard() {
    final l10n = AppLocalizations.of(context);
    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline, color: WFColors.primary),
            title: Text(l10n.version),
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
          ListTile(
            leading: const Icon(Icons.code, color: WFColors.info),
            title: Text(l10n.openSourceLicense),
            subtitle: const Text('AGPL-3.0'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _showLicenseDialog(),
          ),
          _buildDivider(),
          ListTile(
            leading: const Icon(Icons.language, color: WFColors.accent),
            title: const Text('GitHub'),
            subtitle: Text(l10n.viewSourceCode),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () async {
              final uri = Uri.parse('https://github.com/MrLing1202/writefont');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (mounted) {
                  WFSnackBar.error(context, AppLocalizations.of(context).cannotOpenLink);
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
      title: 'AGPL-3.0',
      content: const SingleChildScrollView(
        child: Text(
          'AGPL-3.0 License\n\n'
          'Copyright (c) 2024 WriteFont\n\n'
          'This program is free software: you can redistribute it and/or modify '
          'it under the terms of the GNU Affero General Public License as published by '
          'the Free Software Foundation, either version 3 of the License, or '
          '(at your option) any later version.\n\n'
          'This program is distributed in the hope that it will be useful, '
          'but WITHOUT ANY WARRANTY; without even the implied warranty of '
          'MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the '
          'GNU Affero General Public License for more details.\n\n'
          'You should have received a copy of the GNU Affero General Public License '
          'along with this program. If not, see https://www.gnu.org/licenses/.\n\n'
          'Note: The InkForge core engine is proprietary and not covered by this license. '
          'For source code access, please contact the author.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context).close),
        ),
      ],
    );
  }
}
