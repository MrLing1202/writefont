import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

class HomeScreen extends StatefulWidget {
  /// 主题变更回调，用于从设置页返回时刷新主题
  final VoidCallback? onThemeChanged;

  const HomeScreen({super.key, this.onThemeChanged});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _savedProjectCount = 0;
  int _totalCharCount = 0;
  DateTime? _lastActivityTime;
  List<FontProject> _recentProjects = [];
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadProjectData();
    _loadAppVersion();
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
    } catch (_) {}
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
        leading: IconButton(
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
      body: Center(
        child: SingleChildScrollView(
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

              // ── 主要功能入口 ──
              WFAnimations.fadeInSlide(
                WFActionCard(
                  icon: Icons.auto_awesome,
                  title: l10n.oneClickGenerate,
                  subtitle: l10n.oneClickGenerateDesc,
                  color: WFColors.primary,
                  onTap: () => HomeActions.quickCapture(context),
                ),
                delay: const Duration(milliseconds: 80),
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
                delay: const Duration(milliseconds: 160),
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
                delay: const Duration(milliseconds: 240),
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
                delay: const Duration(milliseconds: 320),
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
                delay: const Duration(milliseconds: 360),
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
                delay: const Duration(milliseconds: 400),
              ),
              const SizedBox(height: 24),

              // ── 最近项目快捷入口 ──
              if (_recentProjects.isNotEmpty) ...[
                WFAnimations.fadeInSlide(
                  RecentProjectsSection(recentProjects: _recentProjects),
                  delay: const Duration(milliseconds: 480),
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
      ),
    );
  }
}
