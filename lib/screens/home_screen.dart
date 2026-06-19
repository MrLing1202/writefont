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

class HomeScreen extends StatefulWidget {
  /// 主题变更回调，用于从设置页返回时刷新主题
  final VoidCallback? onThemeChanged;

  const HomeScreen({super.key, this.onThemeChanged});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  int _savedProjectCount = 0;
  int _totalCharCount = 0;
  DateTime? _lastActivityTime;
  List<FontProject> _recentProjects = [];
  String _appVersion = '';
  bool _showOnboarding = false;
  int _onboardingStep = 0;
  bool _isRefreshing = false;

  // 快捷操作动画控制器
  late AnimationController _quickActionAnimController;
  late Animation<double> _quickActionScale;

  @override
  void initState() {
    super.initState();
    _loadProjectData();
    _loadAppVersion();
    _checkOnboardingGuide();
    _quickActionAnimController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _quickActionScale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _quickActionAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _quickActionAnimController.dispose();
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

  /// 加载项目数据（数量 + 最近项目 + 统计）
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

        setState(() {
          _savedProjectCount = projects.length;
          _totalCharCount = charCount;
          _lastActivityTime = lastTime;
          _recentProjects = projects.take(2).toList();
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
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _onRefresh,
            color: WFColors.primary,
            child: Center(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  const SizedBox(height: 24),

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
          ), // end RefreshIndicator

          // 新手引导遮罩
          if (_showOnboarding) _buildOnboardingOverlay(context),
        ],
      ),
    );
  }

  /// 构建快速操作网格
  Widget _buildQuickActionsGrid(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
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

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: actions.map((action) => _buildQuickActionButton(action)).toList(),
      ),
    );
  }

  /// 构建快速操作按钮
  Widget _buildQuickActionButton(_QuickAction action) {
    return GestureDetector(
      onTapDown: (_) => _quickActionAnimController.forward(),
      onTapUp: (_) {
        _quickActionAnimController.reverse();
        action.onTap();
      },
      onTapCancel: () => _quickActionAnimController.reverse(),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: action.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              action.icon,
              color: action.color,
              size: 24,
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
    );
  }

  /// 构建使用统计卡片
  Widget _buildUsageStatsCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    return Container(
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
