import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../generated/l10n/app_localizations.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';
import 'font_preview_screen.dart';
import 'font_preview_enhanced_screen.dart';
import 'project_list_screen.dart';
import 'settings_screen.dart';
import 'writing_tips_screen.dart';
import '../services/storage_service.dart';
import 'home/welcome_header.dart';
import 'home/recent_projects_section.dart';
import 'home/secondary_entry_card.dart';
import 'home/home_actions.dart';
import 'package:flutter/services.dart';
import '../main.dart';

/// 推送设置模型
class PushSettings {
  bool enabled;
  TimeOfDay reminderTime;
  String reminderContent;
  int frequencyDays; // 推送频率（天数）
  bool projectReminder;
  bool syncReminder;
  bool updateReminder;

  PushSettings({
    this.enabled = true,
    this.reminderTime = const TimeOfDay(hour: 9, minute: 0),
    this.reminderContent = '今天来创建新的手写字体吧！',
    this.frequencyDays = 1,
    this.projectReminder = true,
    this.syncReminder = true,
    this.updateReminder = true,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'reminderHour': reminderTime.hour,
        'reminderMinute': reminderTime.minute,
        'reminderContent': reminderContent,
        'frequencyDays': frequencyDays,
        'projectReminder': projectReminder,
        'syncReminder': syncReminder,
        'updateReminder': updateReminder,
      };

  factory PushSettings.fromJson(Map<String, dynamic> json) => PushSettings(
        enabled: json['enabled'] as bool? ?? true,
        reminderTime: TimeOfDay(
          hour: json['reminderHour'] as int? ?? 9,
          minute: json['reminderMinute'] as int? ?? 0,
        ),
        reminderContent: json['reminderContent'] as String? ?? '今天来创建新的手写字体吧！',
        frequencyDays: json['frequencyDays'] as int? ?? 1,
        projectReminder: json['projectReminder'] as bool? ?? true,
        syncReminder: json['syncReminder'] as bool? ?? true,
        updateReminder: json['updateReminder'] as bool? ?? true,
      );
}

class HomeScreen extends StatefulWidget {
  /// 主题变更回调，用于从设置页返回时刷新主题
  final VoidCallback? onThemeChanged;

  const HomeScreen({super.key, this.onThemeChanged});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _savedProjectCount = 0;
  int _totalCharCount = 0;
  DateTime? _lastActivityTime;
  List<FontProject> _recentProjects = [];
  String _appVersion = '';
  bool _showOnboarding = false;
  int _onboardingStep = 0;
  bool _isRefreshing = false;
  // 功能引导状态
  bool _showFeatureGuide = false;
  int _featureGuideStep = 0;
  final List<String> _completedFeatureGuides = [];
  // 操作引导状态
  bool _showOperationGuide = false;
  String _operationGuideTarget = '';
  // 手势状态
  double _scaleFactor = 1.0; // 捏合缩放比例
  double _previousScale = 1.0;

  // 推送设置状态
  PushSettings _pushSettings = PushSettings();
  int _unreadNotificationCount = 0;

  // 分类统计
  Map<String, int> _categoryStats = {};

  // 快捷操作动画控制器
  late AnimationController _quickActionAnimController;
  late Animation<double> _quickActionScale;
  // 双击缩放动画控制器
  late AnimationController _doubleTapAnimController;
  late Animation<double> _doubleTapScale;

  @override
  void initState() {
    super.initState();
    _loadProjectData();
    _loadAppVersion();
    _checkOnboardingGuide();
    _checkFeatureGuideProgress();
    _loadPushSettings();
    _loadNotificationCount();
    _quickActionAnimController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _quickActionScale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _quickActionAnimController, curve: Curves.easeInOut),
    );
    // 双击缩放动画控制器
    _doubleTapAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _doubleTapScale = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _doubleTapAnimController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    NotificationService.instance.removeListener(_onNotificationChanged);
    _quickActionAnimController.dispose();
    _doubleTapAnimController.dispose();
    super.dispose();
  }

  /// 检查是否需要显示新手引导
  Future<void> _checkOnboardingGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenGuide = prefs.getBool('home_onboarding_seen') ?? false;
      if (mounted && !hasSeenGuide) {
        setState(() {
          _showOnboarding = true;
        });
      }
    } catch (_) {}
  }

  /// 检查功能引导进度
  Future<void> _checkFeatureGuideProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getStringList('completed_feature_guides') ?? [];
      if (mounted) {
        setState(() {
          _completedFeatureGuides.clear();
          _completedFeatureGuides.addAll(completed);
        });
      }
    } catch (_) {}
  }

  /// 完成功能引导步骤
  Future<void> _completeFeatureGuide(String guideId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _completedFeatureGuides.add(guideId);
      await prefs.setStringList('completed_feature_guides', _completedFeatureGuides);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  /// 显示功能引导
  void _showFeatureGuideFor(String featureId) {
    setState(() {
      _showFeatureGuide = true;
      _featureGuideStep = 0;
    });
  }

  /// 下一步功能引导
  void _nextFeatureGuideStep() {
    final steps = _getFeatureGuideSteps();
    if (_featureGuideStep < steps.length - 1) {
      setState(() => _featureGuideStep++);
    } else {
      _completeFeatureGuide('main_features');
      setState(() => _showFeatureGuide = false);
    }
  }

  /// 获取功能引导步骤
  List<Map<String, dynamic>> _getFeatureGuideSteps() {
    return [
      {
        'icon': Icons.auto_awesome,
        'title': '一键生成字体',
        'desc': '拍照或选择手写图片，系统自动识别字符并生成可安装的手写字体',
        'tip': '建议使用白色背景、黑色字体的清晰图片',
      },
      {
        'icon': Icons.grid_on,
        'title': '标准字表模式',
        'desc': '使用标准字表逐字拍摄，确保覆盖常用汉字，生成完整字体',
        'tip': '标准字表包含3500个常用字',
      },
      {
        'icon': Icons.bolt,
        'title': '快速体验模式',
        'desc': '无需完整拍摄，快速生成体验版字体，感受手写字体的魅力',
        'tip': '适合初次体验的用户',
      },
      {
        'icon': Icons.auto_awesome_outlined,
        'title': 'AI 智能生成',
        'desc': '通过文字描述风格，AI 自动生成独特字体，无需手写',
        'tip': '支持多种风格描述，如"优雅"、"粗犷"等',
      },
      {
        'icon': Icons.folder_special,
        'title': '项目管理',
        'desc': '所有字体项目集中管理，支持编辑、预览、导出和分享',
        'tip': '长按项目可快速操作',
      },
    ];
  }

  /// 显示操作引导（针对特定功能的上下文引导）
  void _showOperationGuideFor(String target) {
    setState(() {
      _showOperationGuide = true;
      _operationGuideTarget = target;
    });
  }

  /// 获取引导进度百分比
  double _getGuideProgress() {
    const totalGuides = ['main_features', 'capture_tips', 'font_editing', 'export_share'];
    final completed = totalGuides.where((g) => _completedFeatureGuides.contains(g)).length;
    return completed / totalGuides.length;
  }

  /// 完成新手引导
  Future<void> _completeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('home_onboarding_seen', true);
      if (mounted) {
        setState(() {
          _showOnboarding = false;
        });
      }
    } catch (_) {}
  }
  /// 加载推送设置
  Future<void> _loadPushSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('push_settings');
      if (json != null && mounted) {
        setState(() {
          _pushSettings = PushSettings.fromJson(
            Map<String, dynamic>.from(
              const JsonDecoder().convert(json) as Map,
            ),
          );
        });
      }
    } catch (_) {}
  }

  /// 保存推送设置
  Future<void> _savePushSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('push_settings',
          const JsonEncoder().convert(_pushSettings.toJson()));
    } catch (_) {}
  }

  /// 加载未读通知数量
  void _loadNotificationCount() {
    setState(() {
      _unreadNotificationCount = NotificationService.instance.unreadCount;
    });
    // 监听通知变更
    NotificationService.instance.addListener(_onNotificationChanged);
  }

  /// 通知变更回调
  void _onNotificationChanged() {
    if (mounted) {
      setState(() {
        _unreadNotificationCount = NotificationService.instance.unreadCount;
      });
    }
  }

  /// 显示推送设置面板
  void _showPushSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '推送设置',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: WFColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                // 推送开关
                SwitchListTile(
                  title: const Text('启用推送通知'),
                  subtitle: const Text('接收创作提醒和同步通知'),
                  value: _pushSettings.enabled,
                  onChanged: (val) {
                    setSheetState(() => _pushSettings.enabled = val);
                    setState(() {});
                    _savePushSettings();
                  },
                ),
                if (_pushSettings.enabled) ...[
                  const Divider(),
                  // 提醒时间
                  ListTile(
                    leading: const Icon(Icons.access_time),
                    title: const Text('提醒时间'),
                    subtitle: Text(
                      '${_pushSettings.reminderTime.hour.toString().padLeft(2, '0')}:'
                      '${_pushSettings.reminderTime.minute.toString().padLeft(2, '0')}',
                    ),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: _pushSettings.reminderTime,
                      );
                      if (picked != null) {
                        setSheetState(() => _pushSettings.reminderTime = picked);
                        setState(() {});
                        _savePushSettings();
                      }
                    },
                  ),
                  // 推送频率
                  ListTile(
                    leading: const Icon(Icons.repeat),
                    title: const Text('推送频率'),
                    subtitle: Text('每 ${_pushSettings.frequencyDays} 天'),
                    trailing: DropdownButton<int>(
                      value: _pushSettings.frequencyDays,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('每天')),
                        DropdownMenuItem(value: 3, child: Text('每3天')),
                        DropdownMenuItem(value: 7, child: Text('每周')),
                        DropdownMenuItem(value: 14, child: Text('每两周')),
                        DropdownMenuItem(value: 30, child: Text('每月')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => _pushSettings.frequencyDays = val);
                          setState(() {});
                          _savePushSettings();
                        }
                      },
                    ),
                  ),
                  // 推送内容设置
                  ListTile(
                    leading: const Icon(Icons.edit_note),
                    title: const Text('提醒内容'),
                    subtitle: Text(_pushSettings.reminderContent),
                    onTap: () {
                      final controller = TextEditingController(
                        text: _pushSettings.reminderContent,
                      );
                      showDialog(
                        context: ctx,
                        builder: (dctx) => AlertDialog(
                          title: const Text('自定义提醒内容'),
                          content: TextField(
                            controller: controller,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: '输入提醒内容...',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dctx),
                              child: const Text('取消'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setSheetState(() =>
                                    _pushSettings.reminderContent = controller.text);
                                setState(() {});
                                _savePushSettings();
                                Navigator.pop(dctx);
                              },
                              child: const Text('保存'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  // 分类推送开关
                  SwitchListTile(
                    title: const Text('项目提醒'),
                    subtitle: const Text('提醒继续创作手写字体'),
                    value: _pushSettings.projectReminder,
                    onChanged: (val) {
                      setSheetState(() => _pushSettings.projectReminder = val);
                      setState(() {});
                      _savePushSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('同步提醒'),
                    subtitle: const Text('云端同步状态通知'),
                    value: _pushSettings.syncReminder,
                    onChanged: (val) {
                      setSheetState(() => _pushSettings.syncReminder = val);
                      setState(() {});
                      _savePushSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('更新提醒'),
                    subtitle: const Text('应用版本更新通知'),
                    value: _pushSettings.updateReminder,
                    onChanged: (val) {
                      setSheetState(() => _pushSettings.updateReminder = val);
                      setState(() {});
                      _savePushSettings();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 显示通知中心面板
  void _showNotificationCenter() {
    final notifications = NotificationService.instance.notifications;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            // 顶部操作栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '通知中心',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (notifications.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        NotificationService.instance.markAllAsRead();
                        Navigator.pop(ctx);
                      },
                      child: const Text('全部已读'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 通知列表
            Expanded(
              child: notifications.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none, size: 48, color: WFColors.textLight),
                          SizedBox(height: 12),
                          Text('暂无通知', style: TextStyle(color: WFColors.textSecondary)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: notifications.length,
                      itemBuilder: (ctx, index) {
                        final n = notifications[index];
                        return Dismissible(
                          key: Key(n.id),
                          onDismissed: (_) {
                            NotificationService.instance.dismiss(n.id);
                          },
                          background: Container(
                            color: WFColors.error,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: n.isRead
                                  ? WFColors.textLight.withValues(alpha: 0.3)
                                  : WFColors.primary.withValues(alpha: 0.2),
                              child: Icon(
                                _getCategoryIcon(n.category),
                                color: n.isRead ? WFColors.textSecondary : WFColors.primary,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              n.title,
                              style: TextStyle(
                                fontWeight: n.isRead ? FontWeight.normal : FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              n.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: n.isRead
                                ? null
                                : Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: WFColors.primary,
                                    ),
                                  ),
                            onTap: () {
                              NotificationService.instance.markAsRead(n.id);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 获取分类图标
  IconData _getCategoryIcon(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.system:
        return Icons.info_outline;
      case NotificationCategory.sync:
        return Icons.cloud_sync;
      case NotificationCategory.reminder:
        return Icons.alarm;
      case NotificationCategory.update:
        return Icons.system_update;
      case NotificationCategory.social:
        return Icons.share;
    }
  }

  /// 下一步引导
  void _nextOnboardingStep() {
    if (_onboardingStep < 3) {
      setState(() {
        _onboardingStep++;
      });
    } else {
      _completeOnboarding();
    }
  }

  /// 显示功能引导入口提示
  Widget _buildGuideEntryPoint() {
    final progress = _getGuideProgress();
    if (progress >= 1.0) return const SizedBox.shrink();

    return WFAnimations.fadeInSlide(
      GestureDetector(
        onTap: () => _showFeatureGuideFor('main_features'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                WFColors.primary.withValues(alpha: 0.08),
                WFColors.info.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: WFColors.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              // 引导图标
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: WFColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.explore, color: WFColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              // 引导信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '功能引导',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '了解应用的核心功能 (${(progress * 100).toInt()}% 已完成)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: WFColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 进度环
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  backgroundColor: WFColors.textLight.withValues(alpha: 0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(WFColors.primary),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: WFColors.textSecondary),
            ],
          ),
        ),
      ),
      delay: const Duration(milliseconds: 120),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadProjectData();
  }

  /// 加载项目数据（数量 + 最近项目 + 统计 + 分类统计）
  Future<void> _loadProjectData() async {
    try {
      final projects = await StorageService.loadProjects();
      if (mounted) {
        int charCount = 0;
        for (final p in projects) {
          charCount += p.glyphs.values.where((g) => g.contours.isNotEmpty).length;
        }

        DateTime? lastTime;
        if (projects.isNotEmpty) {
          lastTime = projects.first.updatedAt;
        }

        // 计算分类统计
        final categoryStats = CategoryService.instance.getCategoryStats(projects);

        setState(() {
          _savedProjectCount = projects.length;
          _totalCharCount = charCount;
          _lastActivityTime = lastTime;
          _recentProjects = projects.take(2).toList();
          _categoryStats = categoryStats;
        });
      }
    } catch (e) {
      // 加载失败时静默处理，避免中断用户操作
      debugPrint('加载项目数据失败: $e');
    }
  }

  /// 下拉刷新项目数据
  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    HapticFeedback.lightImpact(); // 触觉反馈
    await _loadProjectData();
    await _loadAppVersion();
    if (mounted) setState(() => _isRefreshing = false);
  }

  /// 双击缩放 — 切换 1.0x ↔ 1.5x
  void _handleDoubleTap() {
    HapticFeedback.mediumImpact();
    final target = _scaleFactor > 1.2 ? 1.0 : 1.5;
    _doubleTapScale = Tween<double>(begin: _scaleFactor, end: target).animate(
      CurvedAnimation(parent: _doubleTapAnimController, curve: Curves.easeOutBack),
    );
    _doubleTapAnimController.forward(from: 0).then((_) {
      if (mounted) setState(() => _scaleFactor = target);
    });
  }

  /// 长按操作 — 显示快捷菜单
  void _handleLongPress() {
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('快速拍照'),
              onTap: () {
                Navigator.pop(ctx);
                HomeActions.quickCapture(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('我的字体'),
              onTap: () {
                Navigator.pop(ctx);
                HomeActions.openProjectList(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新数据'),
              onTap: () {
                Navigator.pop(ctx);
                _onRefresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 根据时间差生成本地化的描述文本
  String _formatLastActivity(BuildContext context) {
    if (_lastActivityTime == null) return '-';
    final l10n = AppLocalizations.of(context);
    final diff = DateTime.now().difference(_lastActivityTime!);
    if (diff.inMinutes < 1) {
      return l10n.justNow;
    } else if (diff.inHours < 1) {
      return l10n.minutesAgo(diff.inMinutes);
    } else if (diff.inDays < 1) {
      return l10n.hoursAgo(diff.inHours);
    } else if (diff.inDays < 30) {
      return l10n.daysAgo(diff.inDays);
    } else {
      return '${_lastActivityTime!.month}/${_lastActivityTime!.day}';
    }
  }

  /// 动态获取应用版本号
  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${packageInfo.version}';
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // ── 多设备适配：检测设备类型和方向 ──
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isTablet = screenWidth >= 600;
    final isLargeTablet = screenWidth >= 900;
    // 根据屏幕宽度计算内容区域最大宽度（适配平板）
    final contentMaxWidth = isLargeTablet ? 800.0 : isTablet ? 600.0 : double.infinity;
    // 根据设备调整内边距
    final horizontalPadding = isTablet ? screenWidth * 0.08 : 20.0;

    return Scaffold(
      appBar: WFAppBar(
        title: l10n.appName,
        leading: IconButton( // 主题变更回调，用于从设置页返回时刷新主题
          icon: Badge(
            isLabelVisible: _savedProjectCount > 0,
            label: Text('$_savedProjectCount'),
            child: const Icon(Icons.folder_special),
          ),
          tooltip: l10n.myFonts,
          onPressed: () async {
            await HomeActions.openProjectList(context);
            _loadProjectData();
          },
        ),
        actions: [
          // 通知中心按钮
          IconButton(
            icon: Badge(
              isLabelVisible: _unreadNotificationCount > 0,
              label: Text('$_unreadNotificationCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: '通知中心',
            onPressed: _showNotificationCenter,
          ),
          // 推送设置按钮
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '推送设置',
            onPressed: _showPushSettingsSheet,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.settings,
            onPressed: () async {
              await Navigator.push(
                context,
                WFAnimations.slideRoute(SettingsScreen(
                  onThemeChanged: widget.onThemeChanged,
                )),
              );
              widget.onThemeChanged?.call();
            },
          ),
        ],
      ),
      body: GestureDetector(
        // 双击缩放
        onDoubleTap: _handleDoubleTap,
        // 长按快捷菜单
        onLongPress: _handleLongPress,
        // 捏合缩放
        onScaleStart: (_) {
          _previousScale = _scaleFactor;
        },
        onScaleUpdate: (details) {
          final newScale = (_previousScale * details.scale).clamp(0.8, 2.0);
          if (newScale != _scaleFactor) {
            setState(() => _scaleFactor = newScale);
          }
        },
        onScaleEnd: (_) {
          // 缩放比例过小时自动回弹到 1.0
          if (_scaleFactor < 0.9) {
            HapticFeedback.lightImpact();
            setState(() => _scaleFactor = 1.0);
          }
        },
        child: AnimatedBuilder(
          animation: _doubleTapAnimController,
          builder: (context, child) {
            final scale = _doubleTapAnimController.isAnimating
                ? _doubleTapScale.value
                : _scaleFactor;
            return Transform.scale(scale: scale, child: child);
          },
          child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _onRefresh,
            color: WFColors.primary,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
              child: Column(
                children: [
                  // ── 欢迎语 + 统计 ──
                  WFAnimations.fadeInSlide(
                    WelcomeHeader(
                      savedProjectCount: _savedProjectCount,
                      totalCharCount: _totalCharCount,
                      lastActivityDesc: _formatLastActivity(context),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── 快速操作网格 ──
                  WFAnimations.fadeInSlide(
                    ScaleTransition(
                      scale: _quickActionScale,
                      child: _buildQuickActionsGrid(context),
                    ),
                    delay: const Duration(milliseconds: 80),
                  ),
                  const SizedBox(height: 20),

                  // ── 功能引导入口（未完成时显示）──
                  _buildGuideEntryPoint(),
                  if (_getGuideProgress() < 1.0) const SizedBox(height: 14),

                  // ── 主要功能入口 ──
                  WFAnimations.fadeInSlide(
                    WFActionCard(
                      icon: Icons.auto_awesome,
                      title: l10n.oneClickGenerate,
                      subtitle: l10n.oneClickGenerateDesc,
                      color: WFColors.primary,
                      onTap: () => HomeActions.quickCapture(context),
                    ),
                    delay: const Duration(milliseconds: 160),
                  ),
                  const SizedBox(height: 14),

                  WFAnimations.fadeInSlide(
                    WFActionCard(
                      icon: Icons.grid_on,
                      title: l10n.standardCharset,
                      subtitle: l10n.standardCharsetDesc,
                      color: WFColors.info,
                      onTap: () {
                        Navigator.push(
                          context,
                          WFAnimations.slideRoute(const WritingTipsScreen()),
                        );
                      },
                    ),
                    delay: const Duration(milliseconds: 240),
                  ),
                  const SizedBox(height: 14),

                  WFAnimations.fadeInSlide(
                    WFActionCard(
                      icon: Icons.bolt,
                      title: l10n.quickExperience,
                      subtitle: l10n.quickExperienceDesc,
                      color: WFColors.warning,
                      onTap: () => HomeActions.startQuickMode(context),
                    ),
                    delay: const Duration(milliseconds: 320),
                  ),
                  const SizedBox(height: 14),

                  WFAnimations.fadeInSlide(
                    WFActionCard(
                      icon: Icons.camera_alt,
                      title: l10n.freeCapture,
                      subtitle: l10n.freeCaptureDesc,
                      color: WFColors.accent,
                      onTap: () => HomeActions.pickImages(context),
                    ),
                    delay: const Duration(milliseconds: 400),
                  ),
                  const SizedBox(height: 14),

                  // ── AI 智能字体生成器 ──
                  WFAnimations.fadeInSlide(
                    WFActionCard(
                      icon: Icons.auto_awesome_outlined,
                      title: 'AI 智能生成',
                      subtitle: '通过文字描述，AI 自动生成独特字体风格',
                      color: const Color(0xFF8E44AD), // 紫色区分
                      onTap: () => HomeActions.openAiFontGenerator(context),
                    ),
                    delay: const Duration(milliseconds: 480),
                  ),
                  const SizedBox(height: 14),

                  // ── 辅助功能入口 ──
                  WFAnimations.fadeInSlide(
                    SecondaryEntryCard(
                      savedProjectCount: _savedProjectCount,
                      onMyFontsTap: () async {
                        await HomeActions.openProjectList(context);
                        _loadProjectData();
                      },
                      onCharGridTap: () => HomeActions.openCharacterGrid(context),
                      onFontPreviewTap: () {
                        Navigator.push(
                          context,
                          WFAnimations.slideRoute(const FontPreviewScreen()),
                        );
                      },
                      onEnhancedPreviewTap: () {
                        Navigator.push(
                          context,
                          WFAnimations.slideRoute(const FontPreviewEnhancedScreen()),
                        );
                      },
                      onStyleTransferTap: () => HomeActions.openStyleTransfer(context),
                    ),
                    delay: const Duration(milliseconds: 560),
                  ),
                  const SizedBox(height: 24),

                  // ── 使用统计卡片 ──
                  WFAnimations.fadeInSlide(
                    _buildUsageStatsCard(context),
                    delay: const Duration(milliseconds: 640),
                  ),
                  const SizedBox(height: 16),

                  // ── 数据可视化区域 ──
                  // 项目进度可视化
                  if (_savedProjectCount > 0)
                    WFAnimations.fadeInSlide(
                      _buildProjectProgressVisualization(context),
                      delay: const Duration(milliseconds: 700),
                    ),
                  if (_savedProjectCount > 0) const SizedBox(height: 16),

                  // 字符使用统计可视化
                  if (_totalCharCount > 0)
                    WFAnimations.fadeInSlide(
                      _buildCharUsageVisualization(context),
                      delay: const Duration(milliseconds: 740),
                    ),
                  if (_totalCharCount > 0) const SizedBox(height: 16),

                  // 时间线可视化
                  if (_recentProjects.isNotEmpty)
                    WFAnimations.fadeInSlide(
                      _buildTimelineVisualization(context),
                      delay: const Duration(milliseconds: 780),
                    ),
                  if (_recentProjects.isNotEmpty) const SizedBox(height: 16),

                  // 趋势分析可视化
                  if (_savedProjectCount > 1)
                    WFAnimations.fadeInSlide(
                      _buildTrendAnalysisVisualization(context),
                      delay: const Duration(milliseconds: 820),
                    ),
                  if (_savedProjectCount > 1) const SizedBox(height: 24),

                  // ── 分类统计卡片 ──
                  if (_savedProjectCount > 0)
                    WFAnimations.fadeInSlide(
                      _buildCategoryStatsCard(context),
                      delay: const Duration(milliseconds: 680),
                    ),
                  if (_savedProjectCount > 0) const SizedBox(height: 24),

                  // ── 最近项目快捷入口 ──
                  if (_recentProjects.isNotEmpty) ...[
                    WFAnimations.fadeInSlide(
                      RecentProjectsSection(recentProjects: _recentProjects),
                      delay: const Duration(milliseconds: 720),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 底部提示
                  Text(
                    l10n.recommendStandard,
                    style: TextStyle(
                      fontSize: 13,
                      color: WFColors.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            ), // end ConstrainedBox
          ), // end RefreshIndicator

          // 新手引导遮罩
          if (_showOnboarding) _buildOnboardingOverlay(context),
          // 功能引导遮罩
          if (_showFeatureGuide) _buildFeatureGuideOverlay(context),
          // 操作引导浮层
          if (_showOperationGuide) _buildOperationGuideOverlay(context),
        ],
          ),
        ),
      ),
    );
  }

  /// 构建快速操作网格（适配平板和横屏）
  Widget _buildQuickActionsGrid(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    final actions = [
      _QuickAction(
        icon: Icons.camera_alt,
        label: l10n.freeCapture,
        color: WFColors.accent,
        onTap: () => HomeActions.pickImages(context),
      ),
      _QuickAction(
        icon: Icons.auto_awesome,
        label: l10n.oneClickGenerate,
        color: WFColors.primary,
        onTap: () => HomeActions.quickCapture(context),
      ),
      _QuickAction(
        icon: Icons.grid_on,
        label: l10n.standardCharset,
        color: WFColors.info,
        onTap: () => Navigator.push(
          context,
          WFAnimations.slideRoute(const WritingTipsScreen()),
        ),
      ),
      _QuickAction(
        icon: Icons.folder,
        label: l10n.myFonts,
        color: WFColors.success,
        onTap: () async {
          await HomeActions.openProjectList(context);
          _loadProjectData();
        },
      ),
    ];

    // 平板/横屏使用 Wrap 布局，手机使用 Row 布局
    final iconSize = isTablet ? 28.0 : 24.0;
    final buttonSize = isTablet ? 56.0 : 48.0;

    return Container(
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      decoration: BoxDecoration(
        color: WFColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isTablet || isLandscape
          ? Wrap(
              alignment: WrapAlignment.spaceAround,
              spacing: 16,
              runSpacing: 16,
              children: actions.map((action) => _buildQuickActionButton(action, iconSize: iconSize, buttonSize: buttonSize)).toList(),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: actions.map((action) => _buildQuickActionButton(action, iconSize: iconSize, buttonSize: buttonSize)).toList(),
            ),
      ),
    );
  }

  /// 构建快速操作按钮（支持自定义尺寸，适配不同设备）
  Widget _buildQuickActionButton(_QuickAction action, {double iconSize = 24.0, double buttonSize = 48.0}) {
    return Semantics(
      label: action.label,
      button: true,
      child: GestureDetector(
      onTapDown: (_) => _quickActionAnimController.forward(),
      onTapUp: (_) {
        _quickActionAnimController.reverse();
        action.onTap();
      },
      onTapCancel: () => _quickActionAnimController.reverse(),
      child: Column(
        children: [
          Container(
            width: buttonSize,
            height: buttonSize,
            decoration: BoxDecoration(
              color: action.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              action.icon,
              color: action.color,
              size: iconSize,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            action.label,
            style: const TextStyle(
              fontSize: 12,
              color: WFColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
    );
  }

  /// 构建使用统计卡片（含无障碍语义标注）
  Widget _buildUsageStatsCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    return Semantics(
      label: '${l10n.createdProjects}: $_savedProjectCount, ${l10n.recognizedChars}: $_totalCharCount',
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WFColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: WFColors.textLight.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_outlined,
                size: 20,
                color: WFColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '使用统计',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  icon: Icons.folder,
                  label: l10n.createdProjects,
                  value: _savedProjectCount.toString(),
                  color: WFColors.info,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  icon: Icons.text_fields,
                  label: l10n.recognizedChars,
                  value: _totalCharCount.toString(),
                  color: WFColors.success,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  icon: Icons.access_time,
                  label: l10n.recentActivity,
                  value: _formatLastActivity(context),
                  color: WFColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  /// 构建统计项
  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: WFColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: WFColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// 构建分类统计卡片
  Widget _buildCategoryStatsCard(BuildContext context) {
    final completed = _categoryStats['completed'] ?? 0;
    final inProgress = _categoryStats['inProgress'] ?? 0;
    final empty = _categoryStats['empty'] ?? 0;
    final recent = _categoryStats['recent'] ?? 0;

    return Semantics(
      label: '分类统计: 已完成$completed, 进行中$inProgress, 未开始$empty',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: WFColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: WFColors.textLight.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.category_outlined, size: 20, color: WFColors.primary),
                const SizedBox(width: 8),
                const Text(
                  '项目分类',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: WFColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildCategoryChip('已完成', completed, Colors.green, Icons.check_circle),
                _buildCategoryChip('进行中', inProgress, WFColors.primary, Icons.edit_note),
                _buildCategoryChip('未开始', empty, WFColors.textSecondary, Icons.inbox_outlined),
                _buildCategoryChip('最近活跃', recent, WFColors.accent, Icons.access_time),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建分类标签
  Widget _buildCategoryChip(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 数据可视化组件
  // ═══════════════════════════════════════════════════════════

  /// 项目进度可视化
  ///
  /// 使用自定义绘制的进度条和环形图展示各项目的完成度
  Widget _buildProjectProgressVisualization(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WFColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WFColors.textLight.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline, size: 20, color: WFColors.primary),
              const SizedBox(width: 8),
              const Text(
                '项目进度概览',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WFColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 环形进度指示器（纯自定义绘制，无第三方依赖）
          Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: _ProgressRingPainter(
                  completed: _categoryStats['completed'] ?? 0,
                  inProgress: _categoryStats['inProgress'] ?? 0,
                  empty: _categoryStats['empty'] ?? 0,
                  total: _savedProjectCount,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 图例
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('已完成', Colors.green),
              const SizedBox(width: 16),
              _buildLegendItem('进行中', WFColors.primary),
              const SizedBox(width: 16),
              _buildLegendItem('未开始', WFColors.textLight),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建图例项
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: WFColors.textSecondary),
        ),
      ],
    );
  }

  /// 字符使用统计可视化
  ///
  /// 使用自定义绘制的柱状图展示字符使用分布
  Widget _buildCharUsageVisualization(BuildContext context) {
    // 按项目计算字符数分布
    final charCounts = _recentProjects.map((p) => p.glyphs.values.where((g) => g.contours.isNotEmpty).length).toList();
    final maxCount = charCounts.isEmpty ? 1 : charCounts.reduce((a, b) => a > b ? a : b).clamp(1, 9999);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WFColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WFColors.textLight.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, size: 20, color: WFColors.info),
              const SizedBox(width: 8),
              const Text(
                '字符使用统计',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WFColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 水平柱状图（自定义绘制）
          SizedBox(
            height: 100,
            child: CustomPaint(
              painter: _BarChartPainter(
                values: charCounts.map((c) => c / maxCount).toList(),
                labels: _recentProjects.map((p) => p.name.length > 4 ? '${p.name.substring(0, 4)}..' : p.name).toList(),
                color: WFColors.info,
              ),
              size: const Size(double.infinity, 100),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '总字符数: $_totalCharCount',
            style: const TextStyle(fontSize: 12, color: WFColors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 时间线可视化
  ///
  /// 使用自定义绘制的时间线展示项目创建和更新时间
  Widget _buildTimelineVisualization(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WFColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WFColors.textLight.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline, size: 20, color: WFColors.accent),
              const SizedBox(width: 8),
              const Text(
                '创作时间线',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WFColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 时间线节点（自定义绘制）
          ...List.generate(_recentProjects.take(4).length, (index) {
            final project = _recentProjects[index];
            final diff = DateTime.now().difference(project.updatedAt);
            final timeLabel = diff.inDays > 0
                ? '${diff.inDays}天前'
                : diff.inHours > 0
                    ? '${diff.inHours}小时前'
                    : '刚刚';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: index == 0 ? WFColors.accent : WFColors.accent.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (index < _recentProjects.take(4).length - 1)
                    Container(
                      width: 2,
                      height: 20,
                      margin: const EdgeInsets.only(left: 5),
                      color: WFColors.accent.withValues(alpha: 0.2),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WFColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          timeLabel,
                          style: const TextStyle(fontSize: 11, color: WFColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 趋势分析可视化
  ///
  /// 使用自定义绘制的折线图展示项目增长趋势
  Widget _buildTrendAnalysisVisualization(BuildContext context) {
    // 基于最近项目计算7天趋势数据
    final now = DateTime.now();
    final weekData = List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      // 使用 _recentProjects 和 _savedProjectCount 来估算趋势
      return _recentProjects.where((p) {
        return p.createdAt.year == day.year &&
            p.createdAt.month == day.month &&
            p.createdAt.day == day.day;
      }).length;
    });
    // 如果所有天数都是0，使用模拟数据展示UI
    final hasData = weekData.any((v) => v > 0);
    final displayData = hasData ? weekData : [0, 1, 0, 2, 1, 0, 1];
    final maxDayCount = displayData.reduce((a, b) => a > b ? a : b).clamp(1, 9999);

    final dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WFColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WFColors.textLight.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, size: 20, color: WFColors.success),
              const SizedBox(width: 8),
              const Text(
                '创作趋势',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WFColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 折线图（自定义绘制）
          SizedBox(
            height: 100,
            child: CustomPaint(
              painter: _LineChartPainter(
                values: displayData.map((c) => c / maxDayCount).toList(),
                labels: dayLabels,
                color: WFColors.success,
              ),
              size: const Size(double.infinity, 100),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '最近7天项目创建趋势',
            style: const TextStyle(fontSize: 12, color: WFColors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 构建新手引导遮罩
  Widget _buildOnboardingOverlay(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    final steps = [
      {
        'title': l10n.welcomeToApp,
        'desc': '让我们快速了解主要功能',
        'icon': Icons.waving_hand,
      },
      {
        'title': l10n.oneClickGenerate,
        'desc': l10n.oneClickGenerateDesc,
        'icon': Icons.auto_awesome,
      },
      {
        'title': l10n.standardCharset,
        'desc': l10n.standardCharsetDesc,
        'icon': Icons.grid_on,
      },
      {
        'title': l10n.settings,
        'desc': '自定义主题、语言和更多设置',
        'icon': Icons.settings,
      },
    ];

    final step = steps[_onboardingStep];

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: WFColors.bgCard,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                step['icon'] as IconData,
                size: 64,
                color: WFColors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                step['title'] as String,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: WFColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                step['desc'] as String,
                style: const TextStyle(
                  fontSize: 16,
                  color: WFColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _completeOnboarding,
                    child: Text(
                      l10n.skip,
                      style: const TextStyle(color: WFColors.textSecondary),
                    ),
                  ),
                  Row(
                    children: List.generate(
                      steps.length,
                      (index) => Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _onboardingStep
                              ? WFColors.primary
                              : WFColors.textLight,
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _nextOnboardingStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WFColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      _onboardingStep < steps.length - 1
                          ? l10n.nextStep
                          : l10n.done,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建功能引导覆盖层
  Widget _buildFeatureGuideOverlay(BuildContext context) {
    final steps = _getFeatureGuideSteps();
    final step = steps[_featureGuideStep];
    final progress = (_featureGuideStep + 1) / steps.length;

    return GestureDetector(
      onTap: _nextFeatureGuideStep,
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: WFColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: WFColors.primary.withValues(alpha: 0.15),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: WFColors.textLight.withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(WFColors.primary),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 20),
                // 功能图标
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: WFColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    step['icon'] as IconData,
                    size: 40,
                    color: WFColors.primary,
                  ),
                ),
                const SizedBox(height: 16),
                // 步骤计数
                Text(
                  '${_featureGuideStep + 1} / ${steps.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: WFColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                // 功能标题
                Text(
                  step['title'] as String,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: WFColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // 功能描述
                Text(
                  step['desc'] as String,
                  style: const TextStyle(
                    fontSize: 15,
                    color: WFColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // 提示信息
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: WFColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lightbulb_outline, size: 16, color: WFColors.info),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          step['tip'] as String,
                          style: const TextStyle(fontSize: 12, color: WFColors.info),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // 进度指示点
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    steps.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _featureGuideStep ? 20 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: i == _featureGuideStep
                            ? WFColors.primary
                            : i < _featureGuideStep
                                ? WFColors.primary.withValues(alpha: 0.4)
                                : WFColors.textLight,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 操作按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _showFeatureGuide = false),
                      child: const Text('稍后再看', style: TextStyle(color: WFColors.textSecondary)),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            _completeFeatureGuide('main_features');
                            setState(() => _showFeatureGuide = false);
                          },
                          child: const Text('跳过全部'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _nextFeatureGuideStep,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WFColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            _featureGuideStep < steps.length - 1 ? '下一步' : '完成',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建操作引导浮层（上下文相关的引导提示）
  Widget _buildOperationGuideOverlay(BuildContext context) {
    final tips = _getOperationGuideTips(_operationGuideTarget);
    if (tips.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 100,
      left: 20,
      right: 20,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WFColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: WFColors.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.tips_and_updates, color: WFColors.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '操作提示',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _showOperationGuide = false),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...tips.map((tip) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 14, color: WFColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tip,
                        style: const TextStyle(fontSize: 13, color: WFColors.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  /// 获取操作引导提示内容
  List<String> _getOperationGuideTips(String target) {
    switch (target) {
      case 'capture':
        return [
          '建议在光线充足的环境下拍摄',
          '使用白色背景、黑色字体效果最佳',
          '每个字符独立拍摄可提高识别准确率',
        ];
      case 'editing':
        return [
          '长按字符可手动修改识别结果',
          '使用参数面板调节识别灵敏度',
          '低置信度字符建议手动确认',
        ];
      case 'export':
        return [
          '预览满意后可导出为 TTF/OTF 字体',
          '导出的字体可安装到系统使用',
          '支持分享给朋友使用',
        ];
      default:
        return [];
    }
  }
}

/// 快速操作数据类
class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

// ═══════════════════════════════════════════════════════════
// 自定义绘制器（图表可视化）
// ═══════════════════════════════════════════════════════════

/// 环形进度图绘制器
///
/// 绘制多层环形图展示已完成、进行中、未开始项目的占比
class _ProgressRingPainter extends CustomPainter {
  final int completed;
  final int inProgress;
  final int empty;
  final int total;

  _ProgressRingPainter({
    required this.completed,
    required this.inProgress,
    required this.empty,
    required this.total,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeWidth = 14.0;

    // 背景环
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = Colors.grey.withValues(alpha: 0.1);
    canvas.drawCircle(center, radius, bgPaint);

    if (total == 0) return;

    double startAngle = -90 * (3.14159265 / 180);

    // 已完成部分
    final completedAngle = (completed / total) * 360 * (3.14159265 / 180);
    final completedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.green;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      completedAngle,
      false,
      completedPaint,
    );
    startAngle += completedAngle;

    // 进行中部分
    final inProgressAngle = (inProgress / total) * 360 * (3.14159265 / 180);
    final inProgressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF2196F3); // WFColors.primary
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      inProgressAngle,
      false,
      inProgressPaint,
    );
    startAngle += inProgressAngle;

    // 未开始部分
    final emptyAngle = (empty / total) * 360 * (3.14159265 / 180);
    final emptyPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.grey.withValues(alpha: 0.4);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      emptyAngle,
      false,
      emptyPaint,
    );

    // 中心文字
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$total',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Color(0xFF333333),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2 - 6),
    );

    final labelPainter = TextPainter(
      text: const TextSpan(
        text: '项目',
        style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(
      canvas,
      Offset(center.dx - labelPainter.width / 2, center.dy + 12),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 柱状图绘制器
///
/// 绘制垂直柱状图展示各项目字符数
class _BarChartPainter extends CustomPainter {
  final List<double> values; // 0.0 - 1.0 归一化值
  final List<String> labels;
  final Color color;

  _BarChartPainter({
    required this.values,
    required this.labels,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final barWidth = (size.width - 20) / values.length - 8;
    final maxHeight = size.height - 24;
    final startX = 10.0;

    for (int i = 0; i < values.length; i++) {
      final x = startX + i * (barWidth + 8);
      final barHeight = (values[i] * maxHeight).clamp(4.0, maxHeight);

      // 柱体
      final barPaint = Paint()
        ..color = color.withValues(alpha: 0.7 + 0.3 * values[i])
        ..style = PaintingStyle.fill;
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, maxHeight - barHeight + 4, barWidth, barHeight),
        const Radius.circular(4),
      );
      canvas.drawRRect(barRect, barPaint);

      // 标签
      if (i < labels.length) {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        labelPainter.paint(
          canvas,
          Offset(x + barWidth / 2 - labelPainter.width / 2, size.height - 14),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 折线图绘制器
///
/// 绘制折线图展示趋势变化
class _LineChartPainter extends CustomPainter {
  final List<double> values; // 0.0 - 1.0 归一化值
  final List<String> labels;
  final Color color;

  _LineChartPainter({
    required this.values,
    required this.labels,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final chartWidth = size.width - 40;
    final chartHeight = size.height - 24;
    final startX = 20.0;
    final startY = 4.0;

    // 绘制网格线
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = startY + chartHeight * i / 4;
      canvas.drawLine(Offset(startX, y), Offset(startX + chartWidth, y), gridPaint);
    }

    // 绘制折线
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final points = <Offset>[];

    for (int i = 0; i < values.length; i++) {
      final x = startX + (i / (values.length - 1).clamp(1, 9999)) * chartWidth;
      final y = startY + chartHeight * (1 - values[i]);
      points.add(Offset(x, y));

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // 填充渐变
    if (points.length > 1) {
      final fillPath = Path.from(path);
      fillPath.lineTo(points.last.dx, startY + chartHeight);
      fillPath.lineTo(points.first.dx, startY + chartHeight);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.3),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(startX, startY, chartWidth, chartHeight));
      canvas.drawPath(fillPath, fillPaint);
    }

    canvas.drawPath(path, linePaint);

    // 绘制数据点
    for (int i = 0; i < points.length; i++) {
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(points[i], 3, dotPaint);

      // 白色内圈
      canvas.drawCircle(points[i], 1.5, Paint()..color = Colors.white);
    }

    // X轴标签
    for (int i = 0; i < labels.length && i < points.length; i++) {
      final labelPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(points[i].dx - labelPainter.width / 2, size.height - 12),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 散点图绘制器（供 storage_service 统计图表使用）
///
/// 绘制散点图展示数据分布
class ScatterPlotPainter extends CustomPainter {
  final List<Offset> points; // 0.0-1.0 归一化坐标
  final Color color;
  final double dotRadius;

  ScatterPlotPainter({
    required this.points,
    required this.color,
    this.dotRadius = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final chartWidth = size.width - 40;
    final chartHeight = size.height - 24;
    final startX = 20.0;
    final startY = 4.0;

    // 绘制网格
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = startY + chartHeight * i / 4;
      canvas.drawLine(Offset(startX, y), Offset(startX + chartWidth, y), gridPaint);
    }
    for (int i = 0; i <= 4; i++) {
      final x = startX + chartWidth * i / 4;
      canvas.drawLine(Offset(x, startY), Offset(x, startY + chartHeight), gridPaint);
    }

    // 绘制散点
    for (final point in points) {
      final x = startX + point.dx * chartWidth;
      final y = startY + chartHeight * (1 - point.dy);

      // 外圈光晕
      canvas.drawCircle(
        Offset(x, y),
        dotRadius + 2,
        Paint()..color = color.withValues(alpha: 0.2),
      );
      // 实心点
      canvas.drawCircle(
        Offset(x, y),
        dotRadius,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
