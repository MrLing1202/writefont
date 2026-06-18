import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import 'preview_screen.dart';
import 'character_grid_screen.dart';
import '../theme/app_theme.dart';

/// 排序方式枚举
enum SortMode {
  nameAsc, // 按名称升序
  nameDesc, // 按名称降序
  createdDesc, // 按创建时间倒序
  createdAsc, // 按创建时间正序
  updatedDesc, // 按修改时间倒序
  updatedAsc, // 按修改时间正序
}

/// 项目管理页面：列出所有已保存的字体项目
class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<FontProject> _projects = [];
  bool _isLoading = true;
  SortMode _sortMode = SortMode.updatedDesc;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  /// 加载所有项目
  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);
    try {
      final projects = await StorageService.loadProjects();
      if (mounted) {
        setState(() {
          _projects = projects;
          _isLoading = false;
          _sortProjects();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载项目失败: $e')),
        );
      }
    }
  }

  /// 按当前排序模式排序项目列表
  void _sortProjects() {
    switch (_sortMode) {
      case SortMode.nameAsc:
        _projects.sort((a, b) => a.name.compareTo(b.name));
        break;
      case SortMode.nameDesc:
        _projects.sort((a, b) => b.name.compareTo(a.name));
        break;
      case SortMode.createdDesc:
        _projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortMode.createdAsc:
        _projects.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case SortMode.updatedDesc:
        _projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case SortMode.updatedAsc:
        _projects.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        break;
    }
  }

  /// 切换排序模式
  void _toggleSortMode() {
    setState(() {
      switch (_sortMode) {
        case SortMode.updatedDesc:
          _sortMode = SortMode.updatedAsc;
          break;
        case SortMode.updatedAsc:
          _sortMode = SortMode.nameAsc;
          break;
        case SortMode.nameAsc:
          _sortMode = SortMode.nameDesc;
          break;
        case SortMode.nameDesc:
          _sortMode = SortMode.createdDesc;
          break;
        case SortMode.createdDesc:
          _sortMode = SortMode.createdAsc;
          break;
        case SortMode.createdAsc:
          _sortMode = SortMode.updatedDesc;
          break;
      }
      _sortProjects();
    });
  }

  /// 获取排序图标和文字
  (IconData, String) _getSortInfo() {
    switch (_sortMode) {
      case SortMode.nameAsc:
        return (Icons.sort_by_alpha, '名称 A-Z');
      case SortMode.nameDesc:
        return (Icons.sort_by_alpha, '名称 Z-A');
      case SortMode.createdDesc:
        return (Icons.calendar_today, '创建时间↓');
      case SortMode.createdAsc:
        return (Icons.calendar_today, '创建时间↑');
      case SortMode.updatedDesc:
        return (Icons.access_time, '修改时间↓');
      case SortMode.updatedAsc:
        return (Icons.access_time, '修改时间↑');
    }
  }

  /// 删除项目
  Future<void> _deleteProject(FontProject project) async {
    final confirmed = await WFDialog.show<bool>(
      context,
      title: '删除项目',
      content: Text('确定要删除「${project.name}」吗？\n该操作不可撤销。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: WFColors.error,
          ),
          child: const Text('删除'),
        ),
      ],
    );

    if (confirmed == true) {
      try {
        await StorageService.deleteProject(project.id);
        await _loadProjects();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('「${project.name}」已删除'),
              action: SnackBarAction(
                label: '知道了',
                onPressed: () {},
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  /// 重命名项目
  Future<void> _renameProject(FontProject project) async {
    final controller = TextEditingController(text: project.name);
    final newName = await WFDialog.show<String>(
      context,
      title: '重命名项目',
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '项目名称',
          hintText: '输入新的项目名称',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              Navigator.pop(context, name);
            }
          },
          child: const Text('确认'),
        ),
      ],
    );

    if (newName != null && newName != project.name) {
      project.name = newName;
      try {
        await StorageService.saveProject(project);
        await _loadProjects();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('重命名失败: $e')),
          );
        }
      }
    }
    controller.dispose();
  }

  /// 复制项目
  Future<void> _duplicateProject(FontProject project) async {
    try {
      // 深拷贝 GlyphData
      final newGlyphs = <String, GlyphData>{};
      for (final entry in project.glyphs.entries) {
        final original = entry.value;
        newGlyphs[entry.key] = GlyphData(
          character: original.character,
          unicode: original.unicode,
          contours: original.contours
              .map((c) => Contour(
                    c.points
                        .map((p) => ContourPoint(p.x, p.y, onCurve: p.onCurve))
                        .toList(),
                  ))
              .toList(),
          advanceWidth: original.advanceWidth,
          leftSideBearing: original.leftSideBearing,
          xMin: original.xMin,
          yMin: original.yMin,
          xMax: original.xMax,
          yMax: original.yMax,
          sourceImagePath: original.sourceImagePath,
        );
      }

      // 创建新项目
      final newProject = FontProject(
        id: StorageService.generateId(),
        name: '${project.name}(副本)',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        glyphs: newGlyphs,
        params: project.params.copyWith(),
      );

      await StorageService.saveProject(newProject);
      await _loadProjects();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已创建「${newProject.name}」')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('复制失败: $e')),
        );
      }
    }
  }

  /// 导出项目 TTF
  Future<void> _exportProject(FontProject project) async {
    try {
      final filePath = await StorageService.exportTtf(project);
      await StorageService.shareTtf(filePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出: $filePath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  /// 导出项目备份（JSON 格式，含源图片 base64）
  Future<void> _exportProjectBackup(FontProject project) async {
    try {
      final filePath = await StorageService.exportProject(project);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('备份已导出: ${project.name}_backup.json'),
            action: SnackBarAction(
              label: '分享',
              onPressed: () {
                Share.shareXFiles(
                  [XFile(filePath)],
                  subject: 'WriteFont 项目备份',
                  text: 'WriteFont 项目备份文件',
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份导出失败: $e')),
        );
      }
    }
  }

  /// 从文件选择器导入项目备份
  Future<void> _importProject() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: '选择 WriteFont 备份文件',
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法读取文件路径')),
          );
        }
        return;
      }

      final project = await StorageService.importProject(filePath);
      if (project != null) {
        await _loadProjects();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已导入项目「${project.name}」')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('导入失败：文件格式不正确')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  /// 显示项目操作底部菜单
  void _showProjectActions(FontProject project) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖拽指示条
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 项目名称标题
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  project.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 重命名
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameProject(project);
                },
              ),
              // 复制
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制项目'),
                subtitle: const Text('创建项目副本'),
                onTap: () {
                  Navigator.pop(ctx);
                  _duplicateProject(project);
                },
              ),
              // 导出
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('导出字体'),
                subtitle: const Text('导出为 TTF 文件'),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportProject(project);
                },
              ),
              // 导出备份
              ListTile(
                leading: const Icon(Icons.backup),
                title: const Text('导出备份'),
                subtitle: const Text('导出 JSON 备份文件'),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportProjectBackup(project);
                },
              ),
              // 字符总览
              ListTile(
                leading: const Icon(Icons.grid_view),
                title: const Text('字符总览'),
                subtitle: const Text('查看造字进度'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CharacterGridScreen(project: project),
                    ),
                  ).then((_) => _loadProjects());
                },
              ),
              // 删除（带危险样式）
              ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title: Text('删除项目',
                    style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteProject(project);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开项目预览
  void _openProject(FontProject project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PreviewScreen(project: project),
      ),
    ).then((_) => _loadProjects()); // 返回时刷新列表
  }

  /// 获取项目统计信息
  (int total, int edited, double progress) _getProjectStats(FontProject project) {
    final total = project.glyphs.length;
    final edited = project.glyphs.values
        .where((g) => g.contours.isNotEmpty)
        .length;
    final progress = total > 0 ? edited / total : 0.0;
    return (total, edited, progress);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sortInfo = _getSortInfo();

    return Scaffold(
      appBar: WFAppBar(
        title: '我的字体',
        actions: [
          // 导入备份按钮
          IconButton(
            onPressed: _importProject,
            icon: const Icon(Icons.file_upload),
            tooltip: '导入备份',
          ),
          // 排序按钮
          IconButton(
            onPressed: _toggleSortMode,
            icon: Icon(sortInfo.$1),
            tooltip: '排序: ${sortInfo.$2}',
          ),
          IconButton(
            onPressed: _loadProjects,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? _buildEmptyState(colorScheme)
              : _buildProjectList(colorScheme),
    );
  }

  /// 空状态提示
  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.font_download_off,
                size: 60,
                color: colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '还没有保存的字体项目',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '拍照生成字体后，\n在预览页面点击「保存项目」即可保存到这里',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.add),
              label: const Text('去创建字体'),
            ),
          ],
        ),
      ),
    );
  }

  /// 项目列表（支持滑动删除）
  Widget _buildProjectList(ColorScheme colorScheme) {
    return RefreshIndicator(
      onRefresh: _loadProjects,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _projects.length,
        itemBuilder: (context, index) {
          final project = _projects[index];
          return _buildDismissibleCard(project, colorScheme);
        },
      ),
    );
  }

  /// 可滑动删除的项目卡片
  Widget _buildDismissibleCard(FontProject project, ColorScheme colorScheme) {
    return Dismissible(
      key: Key(project.id),
      direction: DismissDirection.endToStart,
      // 红色删除背景
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colorScheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.delete,
              color: colorScheme.onError,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              '删除',
              style: TextStyle(
                color: colorScheme.onError,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        // 二次确认
        return await WFDialog.show<bool>(
          context,
          title: '确认删除',
          content: Text('确定要删除「${project.name}」吗？\n该操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: WFColors.error,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
      onDismissed: (direction) async {
        try {
          await StorageService.deleteProject(project.id);
          setState(() {
            _projects.removeWhere((p) => p.id == project.id);
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('「${project.name}」已删除'),
                action: SnackBarAction(
                  label: '知道了',
                  onPressed: () {},
                ),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('删除失败: $e')),
            );
          }
          // 删除失败时重新加载
          await _loadProjects();
        }
      },
      child: _buildProjectCard(project, colorScheme),
    );
  }

  /// 单个项目卡片（带统计信息和长按菜单）
  Widget _buildProjectCard(FontProject project, ColorScheme colorScheme) {
    final stats = _getProjectStats(project);
    final total = stats.$1;
    final edited = stats.$2;
    final progress = stats.$3;
    final createdStr = _formatDate(project.createdAt);
    final updatedStr = _formatDate(project.updatedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _openProject(project),
        onLongPress: () => _showProjectActions(project),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  // 项目图标
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        project.glyphs.isNotEmpty
                            ? project.glyphs.keys.first
                            : '字',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 项目信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // 统计信息
                        Row(
                          children: [
                            Icon(
                              Icons.text_fields,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$total 个字符',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.edit_note,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '已编辑 $edited',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '创建于 $createdStr',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              updatedStr,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 操作按钮
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          _renameProject(project);
                          break;
                        case 'duplicate':
                          _duplicateProject(project);
                          break;
                        case 'export':
                          _exportProject(project);
                          break;
                        case 'exportBackup':
                          _exportProjectBackup(project);
                          break;
                        case 'grid':
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CharacterGridScreen(project: project),
                            ),
                          ).then((_) => _loadProjects());
                          break;
                        case 'delete':
                          _deleteProject(project);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: ListTile(
                          leading: Icon(Icons.edit),
                          title: Text('重命名'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'duplicate',
                        child: ListTile(
                          leading: Icon(Icons.copy),
                          title: Text('复制'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'export',
                        child: ListTile(
                          leading: Icon(Icons.ios_share),
                          title: Text('导出'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'exportBackup',
                        child: ListTile(
                          leading: Icon(Icons.backup),
                          title: Text('导出备份'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'grid',
                        child: ListTile(
                          leading: Icon(Icons.grid_view),
                          title: Text('字符总览'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline,
                              color: colorScheme.error),
                          title: Text('删除',
                              style: TextStyle(color: colorScheme.error)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // 进度条
              if (total > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress >= 1.0
                                ? Colors.green
                                : colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: progress >= 1.0
                            ? Colors.green
                            : colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';

    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
