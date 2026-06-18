import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';
import 'auto_generate_screen.dart';
import 'capture_screen.dart';
import 'font_preview_screen.dart';
import 'processing_screen.dart';
import 'project_list_screen.dart';
import 'character_grid_screen.dart';
import 'settings_screen.dart';
import 'writing_tips_screen.dart';
import '../services/storage_service.dart';

class HomeScreen extends StatefulWidget {
  /// 主题变更回调，用于从设置页返回时刷新主题
  final VoidCallback? onThemeChanged;

  const HomeScreen({super.key, this.onThemeChanged});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _savedProjectCount = 0;
  List<FontProject> _recentProjects = [];

  @override
  void initState() {
    super.initState();
    _loadProjectData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadProjectData();
  }

  /// 加载项目数据（数量 + 最近项目）
  Future<void> _loadProjectData() async {
    try {
      final projects = await StorageService.loadProjects();
      if (mounted) {
        setState(() {
          _savedProjectCount = projects.length;
          // 取最近 2 个项目（StorageService 已按 updatedAt 倒序排列）
          _recentProjects = projects.take(2).toList();
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
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProjectListScreen()),
            );
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
                MaterialPageRoute(builder: (_) => SettingsScreen(
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
              _buildWelcomeHeader(),
              const SizedBox(height: 28),

              // ── 主要功能入口 ──
              WFAnimations.fadeInSlide(
                WFActionCard(
                  icon: Icons.auto_awesome,
                  title: '一键生成',
                  subtitle: '拍照即生成，全自动无需手动操作',
                  color: WFColors.primary,
                  onTap: () => _quickCapture(context),
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
                      MaterialPageRoute(
                        builder: (_) => const WritingTipsScreen(),
                      ),
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
                  onTap: () => _startQuickMode(context),
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
                  onTap: () => _pickImages(context),
                ),
                delay: const Duration(milliseconds: 320),
              ),
              const SizedBox(height: 14),

              // ── 辅助功能入口 ──
              WFAnimations.fadeInSlide(
                _buildSecondaryEntry(context),
                delay: const Duration(milliseconds: 400),
              ),
              const SizedBox(height: 24),

              // ── 最近项目快捷入口 ──
              if (_recentProjects.isNotEmpty) ...[
                _buildRecentProjectsHeader(),
                const SizedBox(height: 12),
                ..._recentProjects.asMap().entries.map((entry) {
                  return WFAnimations.fadeInSlide(
                    _buildRecentProjectCard(context, entry.value),
                    delay: Duration(milliseconds: 480 + entry.key * 80),
                  );
                }),
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

  // ═══════════════════════════════════════════════════════
  // 欢迎区域
  // ═══════════════════════════════════════════════════════

  Widget _buildWelcomeHeader() {
    return WFAnimations.fadeInSlide(
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [WFColors.primary, WFColors.primaryLight],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: WFColors.primary.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            // 图标
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.font_download,
                size: 36,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '欢迎使用手迹造字',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '拍照生成你的专属手写字体',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 20),
            // 统计栏
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatItem('$_savedProjectCount', '已保存项目'),
                Container(
                  width: 1,
                  height: 32,
                  color: Colors.white.withValues(alpha: 0.2),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                ),
                _buildStatItem('v1.15.0', '当前版本'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // 最近项目快捷入口
  // ═══════════════════════════════════════════════════════

  Widget _buildRecentProjectsHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(Icons.history, size: 18, color: WFColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            '最近项目',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: WFColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentProjectCard(BuildContext context, FontProject project) {
    final glyphCount = project.glyphs.length;
    // 计算时间差描述
    final diff = DateTime.now().difference(project.updatedAt);
    String timeDesc;
    if (diff.inMinutes < 1) {
      timeDesc = '刚刚';
    } else if (diff.inHours < 1) {
      timeDesc = '${diff.inMinutes} 分钟前';
    } else if (diff.inDays < 1) {
      timeDesc = '${diff.inHours} 小时前';
    } else if (diff.inDays < 30) {
      timeDesc = '${diff.inDays} 天前';
    } else {
      timeDesc = '${project.updatedAt.month}/${project.updatedAt.day}';
    }

    return WFCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CharacterGridScreen(project: project),
          ),
        );
      },
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 项目图标
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: WFColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.font_download, size: 22, color: WFColors.info),
          ),
          const SizedBox(width: 14),
          // 项目信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: WFColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$glyphCount 个字符 · $timeDesc',
                  style: const TextStyle(
                    fontSize: 12,
                    color: WFColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: WFColors.textLight),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 辅助功能入口（我的字体 / 字符总览 / 字体预览）
  // ═══════════════════════════════════════════════════════

  Widget _buildSecondaryEntry(BuildContext context) {
    return WFCard(
      child: Column(
        children: [
          _buildListTile(
            context,
            icon: Icons.folder_special,
            iconColor: WFColors.info,
            title: '我的字体',
            subtitle: _savedProjectCount > 0
                ? '已保存 $_savedProjectCount 个字体项目'
                : '查看和管理已保存的字体项目',
            trailing: _savedProjectCount > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: WFColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_savedProjectCount',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  )
                : null,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProjectListScreen()),
              );
              _loadProjectData();
            },
          ),
          const Divider(height: 1, indent: 56),
          _buildListTile(
            context,
            icon: Icons.dashboard,
            iconColor: WFColors.success,
            title: '字符总览',
            subtitle: '查看造字进度',
            onTap: () => _openCharacterGrid(context),
          ),
          const Divider(height: 1, indent: 56),
          _buildListTile(
            context,
            icon: Icons.visibility,
            iconColor: WFColors.accent,
            title: '字体预览',
            subtitle: '输入文字查看手迹效果',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FontPreviewScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildListTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: WFColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: WFColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing,
              const SizedBox(width: 8),
            ],
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: WFColors.textLight,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 业务逻辑
  // ═══════════════════════════════════════════════════════

  /// 打开字符总览（需先选择项目）
  Future<void> _openCharacterGrid(BuildContext context) async {
    final projects = await StorageService.loadProjects();
    if (!context.mounted) return;

    if (projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建并保存一个字体项目')),
      );
      return;
    }

    final selected = await showDialog<FontProject>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择项目'),
        children: projects
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, p),
                child: ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(p.name),
                  subtitle: Text('${p.glyphs.length} 个字符'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            )
            .toList(),
      ),
    );

    if (selected != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CharacterGridScreen(project: selected),
        ),
      );
    }
  }

  /// 快速体验模式：只需10个常用字
  void _startQuickMode(BuildContext context) {
    const quickCharsList = ['的', '一', '是', '不', '了', '在', '人', '有', '我', '他', '这'];
    final now = DateTime.now();
    final dateStr = '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    final project = FontProject(
      id: StorageService.generateId(),
      name: '快速体验 $dateStr',
    );
    for (final char in quickCharsList) {
      project.glyphs[char] = GlyphData(
        character: char,
        unicode: char.codeUnitAt(0),
      );
    }

    StorageService.saveProject(project);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaptureScreen(charset: quickCharsList),
      ),
    );
  }

  /// 一键生成：拍照或选图后直接进入自动处理
  Future<void> _quickCapture(BuildContext context) async {
    final picker = ImagePicker();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('拍照'),
                subtitle: const Text('拍摄手写内容'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('从相册选择'),
                subtitle: const Text('选择已有的手写照片'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null || !context.mounted) return;

    XFile? image;
    if (source == ImageSource.camera) {
      image = await picker.pickImage(source: ImageSource.camera, imageQuality: 95);
    } else {
      image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    }

    if (image == null || !context.mounted) return;

    final imageBytes = await image.readAsBytes();

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AutoGenerateScreen(imageBytes: imageBytes),
        ),
      );
    }
  }

  Future<void> _pickImages(BuildContext context) async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 95);

    if (images.isNotEmpty && context.mounted) {
      final imageBytes = await Future.wait(
        images.map((img) => img.readAsBytes()),
      );

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProcessingScreen(sourceImages: imageBytes),
          ),
        );
      }
    }
  }
}
