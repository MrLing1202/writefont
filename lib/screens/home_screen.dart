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
  void _nextOnboardingStep() { @@
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
