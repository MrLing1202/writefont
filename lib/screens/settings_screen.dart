import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../generated/l10n/app_localizations.dart';
import '../services/app_config_service.dart';
import '../services/locale_service.dart';
import '../services/recognition_service.dart';
import '../services/storage_service.dart';
import '../services/cloud_sync_service.dart';
import '../theme/app_theme.dart';
import 'cloud_sync_screen.dart';
import 'ocr_settings_screen.dart';
import 'package:flutter/services.dart';

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

  // 设置搜索
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 默认参数
  double _threshold = AppConfigService.defaultThreshold;
  double _contrast = AppConfigService.defaultContrast;
  double _smoothness = AppConfigService.defaultSmoothness;
  double _strokeWidth = AppConfigService.defaultStrokeWidth;

  // 缓存状态
  bool _isClearing = false;

  // 云同步状态
  String _syncStatus = 'none'; // none | synced | pending

  // ── 更新功能 ──
  String _latestVersion = '';
  String _currentVersion = '';
  bool _isCheckingUpdate = false;
  bool _hasUpdate = false;
  String _updateChangelog = '';
  List<Map<String, dynamic>> _versionHistory = [];
  bool _isRollingBack = false;

  // 错误日志记录
  final List<_ErrorLogEntry> _errorLogs = [];
  static const int _maxErrorLogs = 50;

  // 用户反馈
  final List<_FeedbackEntry> _feedbackList = [];
  static const int _maxFeedbackEntries = 100;
  static const String _feedbackStorageKey = 'user_feedback_entries';

  // 反馈分类
  static const Map<String, Map<String, dynamic>> _feedbackCategories = {
    'bug': {'icon': '🐛', 'label': 'Bug 报告', 'priority': 1},
    'feature': {'icon': '💡', 'label': '功能建议', 'priority': 2},
    'ux': {'icon': '🎨', 'label': '体验改进', 'priority': 3},
    'performance': {'icon': '⚡', 'label': '性能问题', 'priority': 4},
    'other': {'icon': '📝', 'label': '其他', 'priority': 5},
  };

  // 外观设置
  String _themeMode = AppConfigService.defaultThemeMode;

  // 版本信息
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadFeedbackEntries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

      // 加载版本信息
      _loadVersionInfo();
    }
  }

  /// 切换识别模式
  Future<void> _toggleUseCloud(bool value) async {
    try {
      await _recognition.setUseCloud(value);
      if (mounted) {
        setState(() => _useCloud = value);
        final l10n = AppLocalizations.of(context);
        WFSnackBar.show(context, value ? l10n.switchedToCloud : l10n.switchedToLocal);
      }
    } catch (e) {
      _logError('识别模式切换', e);
      if (mounted) {
        _showErrorWithRecovery('识别模式切换失败', e.toString(), () {
          _toggleUseCloud(!value); // 尝试恢复原状态
        });
      }
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
      _logError('清除缓存', e);
      if (mounted) {
        _showErrorWithRecovery('清除缓存失败', e.toString(), _clearCache);
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  /// 重置默认参数
  Future<void> _resetParams() async {
    try {
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
    } catch (e) {
      _logError('重置参数', e);
      if (mounted) {
        _showErrorWithRecovery('重置参数失败', e.toString(), _resetParams);
      }
    }
  }

  /// 重置所有设置（含外观和识别模式）
  Future<void> _resetAllSettings() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await WFDialog.confirm(
      context,
      title: '重置所有设置',
      message: '确定要将所有设置恢复为默认值吗？包括外观、识别模式和字体生成参数。',
      confirmText: '重置',
      isDestructive: true,
    );

    if (confirmed != true) return;

    try {
      // 重置处理参数
      await _config.resetParams();
      // 重置主题为跟随系统
      await _config.setThemeMode(AppConfigService.defaultThemeMode);
      // 重置识别模式为本地
      await _recognition.setUseCloud(false);

      if (mounted) {
        setState(() {
          _threshold = AppConfigService.defaultThreshold;
          _contrast = AppConfigService.defaultContrast;
          _smoothness = AppConfigService.defaultSmoothness;
          _strokeWidth = AppConfigService.defaultStrokeWidth;
          _themeMode = AppConfigService.defaultThemeMode;
          _useCloud = false;
        });
        widget.onThemeChanged?.call();
        WFSnackBar.show(context, '所有设置已重置为默认值');
      }
    } catch (e) {
      _logError('重置所有设置', e);
      if (mounted) {
        _showErrorWithRecovery('重置设置失败', e.toString(), _resetAllSettings);
      }
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
      _logError('导出设置', e);
      if (mounted) {
        _showErrorWithRecovery('导出设置失败', e.toString(), _exportSettings);
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
      _logError('导入设置', e);
      if (mounted) {
        _showErrorWithRecovery('导入设置失败', e.toString(), _importSettings);
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

  // ═══════════════════════════════════════════════════════════
  // 版本更新功能
  // ═══════════════════════════════════════════════════════════

  /// 加载版本信息
  Future<void> _loadVersionInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;

      // 检查版本更新
      final versionInfo = await RecognitionService.checkVersion();
      final versionHistory = await RecognitionService.getVersionHistory();

      if (mounted) {
        setState(() {
          _latestVersion = versionInfo['latestVersion'] as String? ?? _currentVersion;
          _hasUpdate = versionInfo['needsUpdate'] as bool? ?? false;
          _updateChangelog = versionInfo['changelog'] as String? ?? '';
          _versionHistory = versionHistory;
        });
      }
    } catch (e) {
      debugPrint('[Settings] 加载版本信息失败: $e');
    }
  }

  /// 检查版本更新
  Future<void> _checkForUpdate() async {
    setState(() => _isCheckingUpdate = true);

    try {
      final versionInfo = await RecognitionService.checkVersion();

      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
          _hasUpdate = versionInfo['needsUpdate'] as bool? ?? false;
          _latestVersion = versionInfo['latestVersion'] as String? ?? _currentVersion;
          _updateChangelog = versionInfo['changelog'] as String? ?? '';
        });

        if (_hasUpdate) {
          _showUpdateDialog();
        } else {
          WFSnackBar.show(context, '已是最新版本');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
        WFSnackBar.error(context, '检查更新失败: $e');
      }
    }
  }

  /// 显示更新对话框
  void _showUpdateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update, color: WFColors.primary, size: 36),
        title: const Text('发现新版本'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前版本: v$_currentVersion'),
              Text('最新版本: v$_latestVersion'),
              if (_updateChangelog.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('更新日志:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(_updateChangelog, style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performIncrementalUpdate();
            },
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  /// 执行增量更新
  Future<void> _performIncrementalUpdate() async {
    try {
      WFSnackBar.show(context, '正在更新到 v$_latestVersion...');

      // 执行增量更新
      await RecognitionService.updateVersion(_latestVersion, changelog: _updateChangelog);

      // 重新加载版本信息
      await _loadVersionInfo();

      if (mounted) {
        WFSnackBar.show(context, '更新完成！');
      }
    } catch (e) {
      if (mounted) {
        _logError('版本更新', e);
        _showErrorWithRecovery('更新失败', e.toString(), _performIncrementalUpdate);
      }
    }
  }

  /// 显示更新日志对话框
  void _showChangelogDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更新日志'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: _versionHistory.isEmpty
              ? const Center(child: Text('暂无更新记录'))
              : ListView.builder(
                  itemCount: _versionHistory.length,
                  itemBuilder: (ctx, i) {
                    final entry = _versionHistory[i];
                    final version = entry['version'] as String? ?? '';
                    final changelog = entry['changelog'] as String? ?? '';
                    final timestamp = entry['timestamp'] as String? ?? '';
                    final isRollback = entry['isRollback'] as bool? ?? false;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          isRollback ? Icons.undo : Icons.update,
                          color: isRollback ? WFColors.warning : WFColors.primary,
                        ),
                        title: Text('v$version${isRollback ? ' (回滚)' : ''}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (changelog.isNotEmpty) Text(changelog, maxLines: 2, overflow: TextOverflow.ellipsis),
                            Text(timestamp, style: const TextStyle(fontSize: 11, color: WFColors.textSecondary)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 回滚到指定版本
  Future<void> _rollbackToVersion(String targetVersion) async {
    final confirmed = await WFDialog.confirm(
      context,
      title: '版本回滚',
      message: '确定要回滚到 v$targetVersion 吗？\n\n回滚后将使用该版本的识别引擎。',
      confirmText: '回滚',
      isDestructive: true,
    );

    if (confirmed != true) return;

    setState(() => _isRollingBack = true);

    try {
      final success = await RecognitionService.rollbackVersion(
        targetVersion,
        reason: '用户手动回滚',
      );

      if (mounted) {
        setState(() => _isRollingBack = false);

        if (success) {
          WFSnackBar.show(context, '已回滚到 v$targetVersion');
          await _loadVersionInfo();
        } else {
          WFSnackBar.error(context, '回滚失败');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRollingBack = false);
        _logError('版本回滚', e);
        _showErrorWithRecovery('回滚失败', e.toString(), () => _rollbackToVersion(targetVersion));
      }
    }
  }

  /// 显示版本历史对话框
  void _showVersionHistoryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('版本历史'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: _versionHistory.isEmpty
              ? const Center(child: Text('暂无版本历史'))
              : ListView.builder(
                  itemCount: _versionHistory.length,
                  itemBuilder: (ctx, i) {
                    final entry = _versionHistory[i];
                    final version = entry['version'] as String? ?? '';
                    final timestamp = entry['timestamp'] as String? ?? '';
                    final isRollback = entry['isRollback'] as bool? ?? false;

                    return ListTile(
                      leading: Icon(
                        isRollback ? Icons.undo : Icons.update,
                        color: isRollback ? WFColors.warning : WFColors.primary,
                      ),
                      title: Text('v$version'),
                      subtitle: Text(timestamp),
                      trailing: !isRollback && version != _currentVersion
                          ? TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _rollbackToVersion(version);
                              },
                              child: const Text('回滚'),
                            )
                          : null,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 设置搜索框
  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value.trim()),
      decoration: InputDecoration(
        hintText: '搜索设置项...',
        hintStyle: TextStyle(
          color: WFColors.textSecondary,
        ),
        prefixIcon: Icon(Icons.search, color: WFColors.textSecondary),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        filled: true,
        fillColor: WFColors.textLight.withValues(alpha: 0.15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
      ),
    );
  }

  /// 检查设置项是否匹配搜索
  bool _matchesSearch(List<String> keywords) {
    if (_searchQuery.isEmpty) return true;
    final query = _searchQuery.toLowerCase();
    for (final kw in keywords) {
      if (kw.toLowerCase().contains(query)) return true;
    }
    return false;
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
                // 设置搜索框
                _buildSearchBar(),
                const SizedBox(height: 8),

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
                const SizedBox(height: 16),

                // ═══ 版本更新 ═══
                _buildSectionHeader('版本更新', Icons.system_update),
                _buildUpdateCard(),
                const SizedBox(height: 16),
                // ═══ 用户反馈 ═══
                _buildSectionHeader('用户反馈', Icons.feedback_outlined),
                _buildFeedbackCard(),
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
  // 版本更新卡片
  // ═══════════════════════════════════════════════════════════

  Widget _buildUpdateCard() {
    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              _hasUpdate ? Icons.system_update : Icons.check_circle,
              color: _hasUpdate ? WFColors.warning : WFColors.success,
            ),
            title: Text(_hasUpdate ? '有新版本可用' : '已是最新版本'),
            subtitle: Text(_hasUpdate
                ? 'v$_currentVersion → v$_latestVersion'
                : '当前版本 v$_currentVersion'),
            trailing: _isCheckingUpdate
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _checkForUpdate,
          ),
          _buildDivider(),
          ListTile(
            leading: const Icon(Icons.history, color: WFColors.info),
            title: const Text('更新日志'),
            subtitle: const Text('查看历史版本和更新内容'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showChangelogDialog,
          ),
          _buildDivider(),
          ListTile(
            leading: Icon(
              Icons.undo,
              color: _isRollingBack ? WFColors.textLight : WFColors.warning,
            ),
            title: const Text('版本回滚'),
            subtitle: const Text('回滚到之前的版本'),
            trailing: _isRollingBack
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isRollingBack ? null : _showVersionHistoryDialog,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 错误处理与日志系统
  // ═══════════════════════════════════════════════════════════

  /// 记录错误日志
  void _logError(String operation, dynamic error) {
    final entry = _ErrorLogEntry(
      timestamp: DateTime.now(),
      operation: operation,
      error: error.toString(),
    );
    setState(() {
      _errorLogs.insert(0, entry);
      if (_errorLogs.length > _maxErrorLogs) {
        _errorLogs.removeLast();
      }
    });
    debugPrint('[SettingsError] $operation: $error');
  }

  /// 分类错误类型，便于用户理解
  String _classifyError(dynamic error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('network') || msg.contains('socket') || msg.contains('connection')) {
      return '网络错误';
    } else if (msg.contains('permission') || msg.contains('denied')) {
      return '权限错误';
    } else if (msg.contains('file') || msg.contains('path') || msg.contains('io')) {
      return '文件错误';
    } else if (msg.contains('timeout')) {
      return '超时错误';
    } else if (msg.contains('format') || msg.contains('parse') || msg.contains('json')) {
      return '数据格式错误';
    }
    return '未知错误';
  }

  /// 显示带恢复选项的错误对话框
  void _showErrorWithRecovery(String title, String error, VoidCallback? onRetry) {
    final category = _classifyError(error);
    HapticFeedback.mediumImpact(); // 触觉反馈提示错误
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: WFColors.error, size: 36),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: WFColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(category, style: const TextStyle(fontSize: 12, color: WFColors.error, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            Text(error, style: const TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showErrorLogDialog();
            },
            child: const Text('查看日志'),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onRetry();
              },
              child: const Text('重试'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _reportError(title, error);
            },
            child: const Text('报告问题'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 显示错误日志对话框
  void _showErrorLogDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('错误日志'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: _errorLogs.isEmpty
              ? const Center(child: Text('暂无错误日志'))
              : ListView.builder(
                  itemCount: _errorLogs.length,
                  itemBuilder: (ctx, i) {
                    final log = _errorLogs[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.bug_report, size: 18, color: WFColors.error),
                      title: Text(log.operation, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        '${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')} - ${log.error}',
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
        ),
        actions: [
          if (_errorLogs.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _errorLogs.clear());
                Navigator.pop(ctx);
              },
              child: const Text('清除日志'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 报告错误（复制到剪贴板）
  void _reportError(String title, String error) {
    final report = 'WriteFont 错误报告\n标题: $title\n错误: $error\n时间: ${DateTime.now()}\n版本: v$_version';
    Clipboard.setData(ClipboardData(text: report));
    WFSnackBar.show(context, '错误报告已复制到剪贴板，可粘贴发送给开发者');
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

  // ═══════════════════════════════════════════════════════════
  // 用户反馈优化：反馈收集、分类、处理、统计
  // ═══════════════════════════════════════════════════════════

  /// 加载已保存的反馈条目
  Future<void> _loadFeedbackEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_feedbackStorageKey);
      if (json != null && mounted) {
        final list = jsonDecode(json) as List;
        setState(() {
          _feedbackList.clear();
          _feedbackList.addAll(
            list.map((e) => _FeedbackEntry.fromJson(e as Map<String, dynamic>)),
          );
        });
      }
    } catch (e) {
      debugPrint('[Settings] 加载反馈失败: $e');
    }
  }

  /// 保存反馈条目
  Future<void> _saveFeedbackEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_feedbackList.map((e) => e.toJson()).toList());
      await prefs.setString(_feedbackStorageKey, json);
    } catch (e) {
      debugPrint('[Settings] 保存反馈失败: $e');
    }
  }

  /// 显示反馈收集对话框
  void _showFeedbackDialog() {
    final TextEditingController contentController = TextEditingController();
    String selectedCategory = 'bug';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          icon: const Icon(Icons.feedback, color: WFColors.primary, size: 36),
          title: const Text('提交反馈'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('反馈类型', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _feedbackCategories.entries.map((entry) {
                    final isSelected = selectedCategory == entry.key;
                    return ChoiceChip(
                      label: Text('${entry.value['icon']} ${entry.value['label']}'),
                      selected: isSelected,
                      selectedColor: WFColors.primary.withValues(alpha: 0.2),
                      onSelected: (_) => setDialogState(() => selectedCategory = entry.key),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('反馈内容', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: contentController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: '请详细描述您的反馈...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final content = contentController.text.trim();
                if (content.isEmpty) {
                  WFSnackBar.error(context, '请输入反馈内容');
                  return;
                }
                _submitFeedback(selectedCategory, content);
                Navigator.pop(ctx);
              },
              child: const Text('提交'),
            ),
          ],
        ),
      ),
    );
  }

  /// 提交反馈
  void _submitFeedback(String category, String content) {
    final entry = _FeedbackEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      category: category,
      content: content,
      timestamp: DateTime.now(),
      appVersion: 'v$_version',
      status: 'submitted',
    );

    setState(() {
      _feedbackList.insert(0, entry);
      if (_feedbackList.length > _maxFeedbackEntries) {
        _feedbackList.removeLast();
      }
    });

    _saveFeedbackEntries();
    WFSnackBar.show(context, '反馈已提交，感谢您的反馈！');
    debugPrint('[Settings] 反馈已提交: $category - ${content.substring(0, content.length.clamp(0, 50))}');
  }

  /// 获取反馈统计数据
  Map<String, dynamic> _getFeedbackStats() {
    final categoryCount = <String, int>{};
    for (final entry in _feedbackList) {
      categoryCount[entry.category] = (categoryCount[entry.category] ?? 0) + 1;
    }

    final now = DateTime.now();
    final last7d = _feedbackList.where((e) => now.difference(e.timestamp).inDays < 7).length;
    final last30d = _feedbackList.where((e) => now.difference(e.timestamp).inDays < 30).length;

    return {
      'total': _feedbackList.length,
      'categoryCount': categoryCount,
      'last7d': last7d,
      'last30d': last30d,
    };
  }

  /// 显示反馈统计对话框
  void _showFeedbackStatsDialog() {
    final stats = _getFeedbackStats();
    final categoryCount = stats['categoryCount'] as Map<String, int>;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.bar_chart, color: WFColors.primary, size: 36),
        title: const Text('反馈统计'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatRow('总反馈数', '${stats['total']}'),
            _buildStatRow('最近7天', '${stats['last7d']}'),
            _buildStatRow('最近30天', '${stats['last30d']}'),
            const Divider(),
            const Text('按类型统计', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...categoryCount.entries.map((e) {
              final catInfo = _feedbackCategories[e.key];
              return _buildStatRow(
                '${catInfo?['icon'] ?? '📝'} ${catInfo?['label'] ?? e.key}',
                '${e.value}',
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: WFColors.primary)),
        ],
      ),
    );
  }

  /// 构建用户反馈卡片
  Widget _buildFeedbackCard() {
    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.edit_note, color: WFColors.primary),
            title: const Text('提交反馈'),
            subtitle: const Text('报告问题或提出建议'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showFeedbackDialog,
          ),
          _buildDivider(),
          ListTile(
            leading: const Icon(Icons.analytics_outlined, color: WFColors.accent),
            title: const Text('反馈统计'),
            subtitle: Text('已提交 ${_feedbackList.length} 条反馈'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showFeedbackStatsDialog,
          ),
          if (_feedbackList.isNotEmpty) ...[
            _buildDivider(),
            ListTile(
              leading: const Icon(Icons.history, color: WFColors.info),
              title: const Text('反馈历史'),
              subtitle: const Text('查看已提交的反馈'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showFeedbackHistoryDialog,
            ),
          ],
        ],
      ),
    );
  }

  /// 显示反馈历史对话框
  void _showFeedbackHistoryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('反馈历史'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: _feedbackList.isEmpty
              ? const Center(child: Text('暂无反馈记录'))
              : ListView.builder(
                  itemCount: _feedbackList.length,
                  itemBuilder: (ctx, i) {
                    final entry = _feedbackList[i];
                    final catInfo = _feedbackCategories[entry.category];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Text(catInfo?['icon'] ?? '📝', style: const TextStyle(fontSize: 24)),
                        title: Text(
                          entry.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '${catInfo?['label'] ?? entry.category} · ${_formatFeedbackTime(entry.timestamp)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: WFColors.error),
                          onPressed: () {
                            setState(() => _feedbackList.removeAt(i));
                            _saveFeedbackEntries();
                            if (_feedbackList.isEmpty) Navigator.pop(ctx);
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          if (_feedbackList.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _feedbackList.clear());
                _saveFeedbackEntries();
                Navigator.pop(ctx);
              },
              child: const Text('清除全部', style: TextStyle(color: WFColors.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 格式化反馈时间
  String _formatFeedbackTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day}';
  }
}

/// 错误日志条目数据类
class _ErrorLogEntry {
  final DateTime timestamp;
  final String operation;
  final String error;

  const _ErrorLogEntry({
    required this.timestamp,
    required this.operation,
    required this.error,
  });
}

/// 用户反馈条目数据类
class _FeedbackEntry {
  final String id;
  final String category;
  final String content;
  final DateTime timestamp;
  final String appVersion;
  final String status;

  const _FeedbackEntry({
    required this.id,
    required this.category,
    required this.content,
    required this.timestamp,
    required this.appVersion,
    this.status = 'submitted',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'appVersion': appVersion,
        'status': status,
      };

  factory _FeedbackEntry.fromJson(Map<String, dynamic> json) => _FeedbackEntry(
        id: json['id'] as String,
        category: json['category'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        appVersion: json['appVersion'] as String? ?? '',
        status: json['status'] as String? ?? 'submitted',
      );
}