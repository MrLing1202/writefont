import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/project.dart';
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

  @override
  void initState() {
    super.initState();
    _loadProjectCount();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadProjectCount();
  }

  /// 加载已保存项目数量
  Future<void> _loadProjectCount() async {
    try {
      final projects = await StorageService.loadProjects();
      if (mounted) {
        setState(() => _savedProjectCount = projects.length);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        // 左侧：我的字体图标按钮（有项目时显示徽章）
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
            _loadProjectCount();
          },
        ),
        title: const Text('WriteFont'),
        centerTitle: true,
        // 右侧：设置图标按钮
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
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.font_download,
                  size: 50,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),

              // 标题
              Text(
                '手迹造字',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '拍照生成你的专属手写字体',
                style: TextStyle(
                  fontSize: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 48),

              // 标准字表造字卡片
              _buildModeCard(
                context,
                icon: Icons.grid_on,
                title: '标准字表造字',
                description: '按40个常用字书写，AI自动识别匹配',
                color: colorScheme.primaryContainer,
                iconColor: colorScheme.primary,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const WritingTipsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // 一键生成卡片（醒目主按钮）
              _buildPrimaryCard(
                context,
                icon: Icons.auto_awesome,
                title: '一键生成',
                description: '拍照即生成，全自动无需手动操作',
                onTap: () => _quickCapture(context),
              ),
              const SizedBox(height: 16),

              // 快速体验卡片（橙色系）
              _buildModeCard(
                context,
                icon: Icons.bolt,
                title: '快速体验',
                description: '只需写10个字，快速体验造字',
                color: const Color(0xFFFFE0B2), // 浅橙色
                iconColor: const Color(0xFFE65100), // 深橙色
                onTap: () => _startQuickMode(context),
              ),
              const SizedBox(height: 16),

              // 自由拍照造字卡片
              _buildModeCard(
                context,
                icon: Icons.camera_alt,
                title: '自由拍照造字',
                description: '任意手写内容，自由拍照识别',
                color: colorScheme.tertiaryContainer,
                iconColor: colorScheme.tertiary,
                onTap: () => _pickImages(context),
              ),
              const SizedBox(height: 16),

              // 我的字体入口卡片
              _buildMyFontsCard(context, colorScheme),

              const SizedBox(height: 16),

              // 字符总览入口卡片
              _buildCharacterGridCard(context, colorScheme),
              const SizedBox(height: 16),

              // 字体预览入口卡片
              _buildPreviewCard(context, colorScheme),
              const SizedBox(height: 32),

              // 底部提示
              Text(
                '推荐使用标准字表，生成效果更好',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shadowColor: color.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color,
                color.withValues(alpha: 0.7),
              ],
            ),
          ),
          child: Row(
            children: [
              // 图标
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 32, color: iconColor),
              ),
              const SizedBox(width: 20),

              // 文字
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: iconColor.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),

              // 箭头
              Icon(
                Icons.arrow_forward_ios,
                color: iconColor.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 一键生成的醒目主按钮
  Widget _buildPrimaryCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 6,
      shadowColor: colorScheme.primary.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary,
                colorScheme.primary.withValues(alpha: 0.8),
              ],
            ),
          ),
          child: Row(
            children: [
              // 图标
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 32, color: Colors.white),
              ),
              const SizedBox(width: 20),

              // 文字
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),

              // 箭头
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 我的字体入口卡片
  Widget _buildMyFontsCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shadowColor: colorScheme.secondaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ProjectListScreen(),
            ),
          );
          // 返回后刷新项目数量
          _loadProjectCount();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              // 图标
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.folder_special,
                  size: 28,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 16),

              // 文字
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '我的字体',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _savedProjectCount > 0
                          ? '已保存 $_savedProjectCount 个字体项目'
                          : '查看和管理已保存的字体项目',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // 项目数量徽章
              if (_savedProjectCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_savedProjectCount',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              const SizedBox(width: 8),

              // 箭头
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 字体预览入口卡片
  Widget _buildPreviewCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shadowColor: colorScheme.tertiaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const FontPreviewScreen(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: colorScheme.tertiaryContainer.withValues(alpha: 0.15),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.visibility,
                  size: 28,
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '字体预览',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '输入文字查看手迹效果',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 字符总览入口卡片（需要先选择项目）
  Widget _buildCharacterGridCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shadowColor: colorScheme.primaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () async {
          // 加载项目列表供用户选择
          final projects = await StorageService.loadProjects();
          if (!context.mounted) return;

          if (projects.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请先创建并保存一个字体项目')),
            );
            return;
          }

          // 弹出项目选择对话框
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
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: colorScheme.primaryContainer.withValues(alpha: 0.15),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.dashboard,
                  size: 28,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '字符总览',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '查看造字进度',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 快速体验模式：只需10个常用字
  void _startQuickMode(BuildContext context) {
    // 10个最常用汉字
    const quickCharsList = ['的', '一', '是', '不', '了', '在', '人', '有', '我', '他', '这'];
    final now = DateTime.now();
    final dateStr = '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    // 创建快速体验项目
    final project = FontProject(
      id: StorageService.generateId(),
      name: '快速体验 $dateStr',
    );
    // 初始化10个常用字的字形数据
    for (final char in quickCharsList) {
      project.glyphs[char] = GlyphData(
        character: char,
        unicode: char.codeUnitAt(0),
      );
    }

    // 保存项目并跳转到拍照页面
    StorageService.saveProject(project);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaptureScreen(
          charset: quickCharsList,
        ),
      ),
    );
  }

  /// 一键生成：拍照或选图后直接进入自动处理
  Future<void> _quickCapture(BuildContext context) async {
    final picker = ImagePicker();

    // 弹出选择：拍照 or 从相册选
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
          builder: (context) => AutoGenerateScreen(imageBytes: imageBytes),
        ),
      );
    }
  }

  Future<void> _pickImages(BuildContext context) async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 95);

    if (images.isNotEmpty && context.mounted) {
      // 读取图片字节
      final imageBytes = await Future.wait(
        images.map((img) => img.readAsBytes()),
      );

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProcessingScreen(
              sourceImages: imageBytes,
            ),
          ),
        );
      }
    }
  }
}
