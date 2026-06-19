import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';
import 'font_preview_screen.dart';
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
  String _lastActivityDesc = '';
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

        String lastDesc = '';
        if (projects.isNotEmpty) {
          final last = projects.first.updatedAt;
          final diff = DateTime.now().difference(last);
          if (diff.inMinutes < 1) {
            lastDesc = '刚刚';
          } else if (diff.inHours < 1) {
            lastDesc = '${diff.inMinutes} 分钟前';
          } else if (diff.inDays < 1) {
            lastDesc = '${diff.inHours} 小时前';
          } else if (diff.inDays < 30) {
            lastDesc = '${diff.inDays} 天前';
          } else {
            lastDesc = '${last.month}/${last.day}';
          }
        }

        setState(() {
          _savedProjectCount = projects.length;
          _totalCharCount = charCount;
          _lastActivityDesc = lastDesc;
          _recentProjects = projects.take(2).toList();
        });
      }
    } catch (_) {}
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
    return Scaffold(
      appBar: WFAppBar(
        title: '手迹造字',
        leading: IconButton(
          icon: Badge(
            isLabelVisible: _savedProjectCount > 0,
            label: Text('$_savedProjectCount'),
            child: const Icon(Icons.folder_special),
          ),
          tooltip: '我的字体',
          onPressed: () async {
            await HomeActions.openProjectList(context);
            _loadProjectData();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
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
                  lastActivityDesc: _lastActivityDesc,
                ),
              ),
              const SizedBox(height: 28),

              // ── 主要功能入口 ──
              WFAnimations.fadeInSlide(
                WFActionCard(
                  icon: Icons.auto_awesome,
                  title: '一键生成',
                  subtitle: '拍照即生成，全自动无需手动操作',
                  color: WFColors.primary,
                  onTap: () => HomeActions.quickCapture(context),
                ),
                delay: const Duration(milliseconds: 80),
              ),
              const SizedBox(height: 14),

              WFAnimations.fadeInSlide(
                WFActionCard(
                  icon: Icons.grid_on,
                  title: '标准字表造字',
                  subtitle: '按40个常用字书写，AI自动识别匹配',
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
                  title: '快速体验',
                  subtitle: '只需写10个字，快速体验造字',
                  color: WFColors.warning,
                  onTap: () => HomeActions.startQuickMode(context),
                ),
                delay: const Duration(milliseconds: 240),
              ),
              const SizedBox(height: 14),

              WFAnimations.fadeInSlide(
                WFActionCard(
                  icon: Icons.camera_alt,
                  title: '自由拍照造字',
                  subtitle: '任意手写内容，自由拍照识别',
                  color: WFColors.accent,
                  onTap: () => HomeActions.pickImages(context),
                ),
                delay: const Duration(milliseconds: 320),
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
                '推荐使用标准字表，生成效果更好',
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
