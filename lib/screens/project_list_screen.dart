import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import 'preview_screen.dart';
import '../theme/app_theme.dart';
import 'batch_processing_screen.dart';
import 'project_list/sort_mode.dart';
import 'project_list/project_list_widgets.dart';

// Re-export split modules so external imports remain valid
export 'project_list/sort_mode.dart';

/// 项目管理页面：列出所有已保存的字体项目
class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen>
    with ProjectListWidgets {
  List<FontProject> _projects = [];
  bool _isLoading = true;
  SortMode _sortMode = SortMode.updatedDesc;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 项目筛选状态
  // null = 全部, 'completed' = 已完成, 'in_progress' = 进行中, 'empty' = 未开始
  String? _filterStatus;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
        WFSnackBar.error(context, '加载项目失败: $e');
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
      case SortMode.charCountDesc:
        _projects.sort((a, b) => b.glyphs.length.compareTo(a.glyphs.length));
        break;
      case SortMode.charCountAsc:
        _projects.sort((a, b) => a.glyphs.length.compareTo(b.glyphs.length));
        break;
    }
  }

  /// 根据搜索关键词过滤项目
  List<FontProject> get _filteredProjects {
    var filtered = _projects;

    // 按状态筛选
    if (_filterStatus != null) {
      filtered = filtered.where((p) {
        final editedCount = p.glyphs.values.where((g) => g.contours.isNotEmpty).length;
        switch (_filterStatus) {
          case 'completed':
            return editedCount > 0 && editedCount >= p.glyphs.length * 0.8;
          case 'in_progress':
            return editedCount > 0 && editedCount < p.glyphs.length * 0.8;
          case 'empty':
            return editedCount == 0;
          default:
            return true;
        }
      }).toList();
    }

    // 按搜索关键词过滤
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((p) => p.name.toLowerCase().contains(query)).toList();
    }

    return filtered;
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
          _sortMode = SortMode.charCountDesc;
          break;
        case SortMode.charCountDesc:
          _sortMode = SortMode.charCountAsc;
          break;
        case SortMode.charCountAsc:
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
      case SortMode.charCountDesc:
        return (Icons.numbers, '字符数↓');
      case SortMode.charCountAsc:
        return (Icons.numbers, '字符数↑');
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
          WFSnackBar.show(
            context,
            '「${project.name}」已删除',
            action: SnackBarAction(label: '知道了', onPressed: () {}),
          );
        }
      } catch (e) {
        if (mounted) {
          WFSnackBar.error(context, '删除失败: $e');
        }
      }
    }
  }

  /// 直接删除项目（无确认对话框，用于滑动删除后）
  Future<void> _deleteProjectDirect(FontProject project) async {
    await StorageService.deleteProject(project.id);
    setState(() {
      _projects.removeWhere((p) => p.id == project.id);
    });
  }

  // === 批量删除 ===
  bool _isMultiSelectMode = false;
  final Set<String> _selectedProjectIds = {};

  /// 进入/退出多选模式
  void _toggleMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) {
        _selectedProjectIds.clear();
      }
    });
  }

  /// 切换选中状态
  void _toggleProjectSelection(String projectId) {
    setState(() {
      if (_selectedProjectIds.contains(projectId)) {
        _selectedProjectIds.remove(projectId);
      } else {
        _selectedProjectIds.add(projectId);
      }
    });
  }

  /// 全选/取消全选
  void _selectAll() {
    setState(() {
      if (_selectedProjectIds.length == _filteredProjects.length) {
        _selectedProjectIds.clear();
      } else {
        _selectedProjectIds.clear();
        _selectedProjectIds.addAll(_filteredProjects.map((p) => p.id));
      }
    });
  }

  /// 切换筛选状态
  void _cycleFilterStatus() {
    setState(() {
      switch (_filterStatus) {
        case null:
          _filterStatus = 'completed';
          break;
        case 'completed':
          _filterStatus = 'in_progress';
          break;
        case 'in_progress':
          _filterStatus = 'empty';
          break;
        case 'empty':
          _filterStatus = null;
          break;
      }
    });
  }

  /// 获取筛选状态信息
  (IconData, String) _getFilterInfo() {
    switch (_filterStatus) {
      case 'completed':
        return (Icons.check_circle, '已完成');
      case 'in_progress':
        return (Icons.edit_note, '进行中');
      case 'empty':
        return (Icons.inbox_outlined, '未开始');
      default:
        return (Icons.filter_list, '全部');
    }
  }

  /// 批量导出选中项目的 TTF
  Future<void> _batchExportSelectedTtf() async {
    if (_selectedProjectIds.isEmpty) return;

    final selectedProjects = _projects
        .where((p) => _selectedProjectIds.contains(p.id))
        .toList();

    final confirmed = await WFDialog.confirm(
      context,
      title: '批量导出 TTF',
      message: '将为选中的 ${selectedProjects.length} 个项目生成 TTF 字体文件，是否继续？',
      confirmText: '开始导出',
      icon: Icons.font_download,
      iconColor: WFColors.info,
    );

    if (confirmed != true) return;

    try {
      int successCount = 0;
      int failCount = 0;
      for (final project in selectedProjects) {
        try {
          await StorageService.exportTtf(project);
          successCount++;
        } catch (e) {
          failCount++;
        }
      }
      if (mounted) {
        setState(() {
          _isMultiSelectMode = false;
          _selectedProjectIds.clear();
        });
        WFSnackBar.show(context, '导出完成: $successCount 成功, $failCount 失败');
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '批量导出失败: $e');
      }
    }
  }

  /// 批量删除选中项目
  Future<void> _batchDeleteProjects() async {
    if (_selectedProjectIds.isEmpty) return;

    final count = _selectedProjectIds.length;
    final confirmed = await WFDialog.show<bool>(
      context,
      title: '批量删除',
      content: Text('确定要删除选中的 $count 个项目吗？\n该操作不可撤销。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: WFColors.error),
          child: Text('删除 $count 个项目'),
        ),
      ],
    );

    if (confirmed == true) {
      try {
        for (final id in _selectedProjectIds) {
          await StorageService.deleteProject(id);
        }
        setState(() {
          _isMultiSelectMode = false;
          _selectedProjectIds.clear();
        });
        await _loadProjects();
        if (mounted) {
          WFSnackBar.show(context, '已删除 $count 个项目');
        }
      } catch (e) {
        if (mounted) {
          WFSnackBar.error(context, '批量删除失败: $e');
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
          WFSnackBar.error(context, '重命名失败: $e');
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
        WFSnackBar.show(context, '已创建「${newProject.name}」');
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '复制失败: $e');
      }
    }
  }

  /// 导出项目 TTF
  Future<void> _exportProject(FontProject project) async {
    try {
      final filePath = await StorageService.exportTtf(project);
      await StorageService.shareTtf(filePath);
      if (mounted) {
        WFSnackBar.show(context, '已导出: $filePath');
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '导出失败: $e');
      }
    }
  }

  /// 导出项目备份（JSON 格式，含源图片 base64）
  Future<void> _exportProjectBackup(FontProject project) async {
    try {
      final filePath = await StorageService.exportProject(project);
      if (mounted) {
        WFSnackBar.show(
          context,
          '备份已导出: ${project.name}_backup.json',
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
        );
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '备份导出失败: $e');
      }
    }
  }

  /// 从文件选择器导入项目备份
  ///
  /// 导入前检查文件格式是否为合法的 WriteFont 项目 JSON
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
          WFSnackBar.show(context, '无法读取文件路径');
        }
        return;
      }

      // ── 导入前格式校验 ──
      final file = File(filePath);
      final jsonString = await file.readAsString();
      Map<String, dynamic> json;
      try {
        json = jsonDecode(jsonString) as Map<String, dynamic>;
      } catch (_) {
        if (mounted) {
          WFSnackBar.error(context, '导入失败：文件不是有效的 JSON 格式');
        }
        return;
      }

      // 检查必要字段
      if (!json.containsKey('name') || !json.containsKey('glyphs')) {
        if (mounted) {
          WFSnackBar.error(context, '导入失败：缺少必要字段（name / glyphs）');
        }
        return;
      }

      final project = await StorageService.importProjectFromJson(json);
      if (project != null) {
        await _loadProjects();
        if (mounted) {
          WFSnackBar.show(context, '已导入项目「${project.name}」');
        }
      } else {
        if (mounted) {
          WFSnackBar.error(context, '导入失败：数据解析异常');
        }
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '导入失败: $e');
      }
    }
  }

  /// 打开项目预览
  void _openProject(FontProject project) {
    Navigator.push(
      context,
      WFAnimations.slideRoute(PreviewScreen(project: project)),
    ).then((_) => _loadProjects()); // 返回时刷新列表
  }

  /// 构建筛选状态指示条
  Widget _buildFilterIndicator(ColorScheme colorScheme) {
    final filterInfo = _getFilterInfo();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: colorScheme.primaryContainer.withValues(alpha: 0.2),
      child: Row(
        children: [
          Icon(filterInfo.$1, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            '筛选: ${filterInfo.$2}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${_filteredProjects.length} 个项目)',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _filterStatus = null),
            child: Text(
              '清除筛选',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sortInfo = _getSortInfo();
    final filterInfo = _getFilterInfo();

    return Scaffold(
      appBar: WFAppBar(
        title: '我的字体',
        actions: [
          // 批量处理按钮
          if (_projects.isNotEmpty && !_isMultiSelectMode)
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  WFAnimations.slideRoute(const BatchProcessingScreen()),
                ).then((_) => _loadProjects());
              },
              icon: const Icon(Icons.dynamic_feed_outlined),
              tooltip: '批量处理',
            ),
          // 筛选按钮
          if (_projects.isNotEmpty && !_isMultiSelectMode)
            IconButton(
              onPressed: _cycleFilterStatus,
              icon: Icon(filterInfo.$1),
              tooltip: '筛选: ${filterInfo.$2}',
            ),
          // 批量删除按钮
          if (_projects.isNotEmpty)
            IconButton(
              onPressed: _toggleMultiSelectMode,
              icon: Icon(_isMultiSelectMode ? Icons.close : Icons.checklist),
              tooltip: _isMultiSelectMode ? '退出多选' : '多选操作',
            ),
          // 多选模式下的全选和删除
          if (_isMultiSelectMode) ...[
            IconButton(
              onPressed: _selectAll,
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
            ),
            if (_selectedProjectIds.isNotEmpty)
              IconButton(
                onPressed: _batchExportSelectedTtf,
                icon: const Icon(Icons.font_download, color: WFColors.info),
                tooltip: '导出 TTF',
              ),
            if (_selectedProjectIds.isNotEmpty)
              IconButton(
                onPressed: _batchDeleteProjects,
                icon: Icon(Icons.delete_forever, color: WFColors.error),
                tooltip: '删除选中',
              ),
          ],
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
              ? buildEmptyState(
                  colorScheme: colorScheme,
                  onCreateProject: () => Navigator.pop(context),
                )
              : Column(
                  children: [
                    // 搜索框
                    buildSearchBar(
                      colorScheme: colorScheme,
                      searchController: _searchController,
                      searchQuery: _searchQuery,
                      onChanged: (value) => setState(() => _searchQuery = value.trim()),
                      onClear: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                    // 筛选状态指示
                    if (_filterStatus != null)
                      _buildFilterIndicator(colorScheme),
                    // 项目列表或搜索空状态
                    Expanded(
                      child: _filteredProjects.isEmpty
                          ? buildSearchEmptyState(colorScheme)
                          : buildProjectList(
                              colorScheme: colorScheme,
                              projects: _filteredProjects,
                              onRefresh: _loadProjects,
                              onDelete: _deleteProject,
                              onRename: _renameProject,
                              onDuplicate: _duplicateProject,
                              onExport: _exportProject,
                              onExportBackup: _exportProjectBackup,
                              onOpen: _openProject,
                              isMultiSelectMode: _isMultiSelectMode,
                              selectedProjectIds: _selectedProjectIds,
                              onToggleSelection: _toggleProjectSelection,
                              onShowActions: (project) => showProjectActions(
                                context: context,
                                project: project,
                                onRename: _renameProject,
                                onDuplicate: _duplicateProject,
                                onExport: _exportProject,
                                onExportBackup: _exportProjectBackup,
                                onDelete: _deleteProject,
                                onLoadProjects: _loadProjects,
                              ),
                              onLoadProjects: _loadProjects,
                              onDirectDelete: _deleteProjectDirect,
                              searchQuery: _searchQuery,
                              context: context,
                            ),
                    ),
                  ],
                ),
    );
  }
}
