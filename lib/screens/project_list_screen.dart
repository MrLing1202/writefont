import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  SortMode? _secondarySortMode; // 二级排序
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 搜索历史记录
  List<String> _searchHistory = [];
  static const String _searchHistoryKey = 'project_search_history';
  static const int _maxSearchHistory = 10;
  // 搜索建议列表
  List<String> _searchSuggestions = [];
  bool _showSuggestions = false;

  // 项目筛选状态
  // null = 全部, 'completed' = 已完成, 'in_progress' = 进行中, 'empty' = 未开始
  String? _filterStatus;

  // 多条件筛选
  String? _filterCharRange; // null, 'small'(<20), 'medium'(20-50), 'large'(>50)
  String? _filterTimeRange; // null, 'today', 'week', 'month', 'older'
  static const String _filterPresetsKey = 'filter_presets';
  List<Map<String, String?>> _filterPresets = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _loadSearchHistory();
    _loadFilterPresets();
  }

  /// 加载搜索历史记录
  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList(_searchHistoryKey);
      if (history != null && mounted) {
        setState(() => _searchHistory = history);
      }
    } catch (_) {}
  }

  /// 保存搜索关键词到历史记录
  Future<void> _saveSearchToHistory(String query) async {
    if (query.isEmpty) return;
    try {
      _searchHistory.remove(query);
      _searchHistory.insert(0, query);
      if (_searchHistory.length > _maxSearchHistory) {
        _searchHistory = _searchHistory.sublist(0, _maxSearchHistory);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_searchHistoryKey, _searchHistory);
    } catch (_) {}
  }

  /// 清除搜索历史
  Future<void> _clearSearchHistory() async {
    try {
      _searchHistory.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_searchHistoryKey);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  /// 根据输入更新搜索建议
  void _updateSearchSuggestions(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchSuggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    final suggestions = _projects
        .map((p) => p.name)
        .where((name) => name.toLowerCase().contains(lowerQuery))
        .toSet()
        .toList();
    final historyMatches = _searchHistory
        .where((h) => h.toLowerCase().contains(lowerQuery) && !suggestions.contains(h))
        .toList();
    suggestions.addAll(historyMatches);
    setState(() {
      _searchSuggestions = suggestions.take(5).toList();
      _showSuggestions = suggestions.isNotEmpty;
    });
  }

  /// 执行搜索（提交时调用）
  void _executeSearch(String query) {
    setState(() {
      _searchQuery = query.trim();
      _showSuggestions = false;
    });
    _saveSearchToHistory(query.trim());
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
    _projects.sort((a, b) {
      int result = _compareByMode(a, b, _sortMode);
      if (result != 0) return result;
      // 二级排序
      if (_secondarySortMode != null) {
        return _compareByMode(a, b, _secondarySortMode!);
      }
      return 0;
    });
  }

  /// 按指定排序模式比较两个项目
  int _compareByMode(FontProject a, FontProject b, SortMode mode) {
    switch (mode) {
      case SortMode.nameAsc:
        return a.name.compareTo(b.name);
      case SortMode.nameDesc:
        return b.name.compareTo(a.name);
      case SortMode.createdDesc:
        return b.createdAt.compareTo(a.createdAt);
      case SortMode.createdAsc:
        return a.createdAt.compareTo(b.createdAt);
      case SortMode.updatedDesc:
        return b.updatedAt.compareTo(a.updatedAt);
      case SortMode.updatedAsc:
        return a.updatedAt.compareTo(b.updatedAt);
      case SortMode.charCountDesc:
        return b.glyphs.length.compareTo(a.glyphs.length);
      case SortMode.charCountAsc:
        return a.glyphs.length.compareTo(b.glyphs.length);
      case SortMode.progressDesc:
        return _getProgress(b).compareTo(_getProgress(a));
      case SortMode.progressAsc:
        return _getProgress(a).compareTo(_getProgress(b));
    }
  }

  /// 获取项目的编辑进度（0.0-1.0）
  double _getProgress(FontProject project) {
    if (project.glyphs.isEmpty) return 0.0;
    final edited = project.glyphs.values.where((g) => g.contours.isNotEmpty).length;
    return edited / project.glyphs.length;
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

    // 按字符数量范围筛选
    if (_filterCharRange != null) {
      filtered = filtered.where((p) {
        final count = p.glyphs.length;
        switch (_filterCharRange) {
          case 'small': return count < 20;
          case 'medium': return count >= 20 && count <= 50;
          case 'large': return count > 50;
          default: return true;
        }
      }).toList();
    }

    // 按时间范围筛选
    if (_filterTimeRange != null) {
      final now = DateTime.now();
      filtered = filtered.where((p) {
        switch (_filterTimeRange) {
          case 'today': return now.difference(p.updatedAt).inDays == 0;
          case 'week': return now.difference(p.updatedAt).inDays <= 7;
          case 'month': return now.difference(p.updatedAt).inDays <= 30;
          case 'older': return now.difference(p.updatedAt).inDays > 30;
          default: return true;
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

  /// 是否有任何筛选条件激活
  bool get _hasActiveFilters =>
      _filterStatus != null || _filterCharRange != null || _filterTimeRange != null;

  /// 清除所有筛选条件
  void _clearAllFilters() {
    setState(() {
      _filterStatus = null;
      _filterCharRange = null;
      _filterTimeRange = null;
    });
  }

  /// 保存当前筛选为预设
  Future<void> _saveFilterPreset(String name) async {
    final preset = <String, String?>{
      'name': name,
      'status': _filterStatus,
      'charRange': _filterCharRange,
      'timeRange': _filterTimeRange,
    };
    _filterPresets.add(preset);
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = _filterPresets.map((p) => jsonEncode(p)).toList();
      await prefs.setStringList(_filterPresetsKey, json);
    } catch (_) {}
  }

  /// 加载筛选预设
  Future<void> _loadFilterPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getStringList(_filterPresetsKey);
      if (json != null) {
        _filterPresets = json.map((s) {
          final map = jsonDecode(s) as Map<String, dynamic>;
          return map.map((k, v) => MapEntry(k, v as String?));
        }).toList();
      }
    } catch (_) {}
  }

  /// 应用筛选预设
  void _applyFilterPreset(Map<String, String?> preset) {
    setState(() {
      _filterStatus = preset['status'];
      _filterCharRange = preset['charRange'];
      _filterTimeRange = preset['timeRange'];
    });
  }

  /// 删除筛选预设
  Future<void> _deleteFilterPreset(int index) async {
    _filterPresets.removeAt(index);
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = _filterPresets.map((p) => jsonEncode(p)).toList();
      await prefs.setStringList(_filterPresetsKey, json);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  /// 获取筛选结果统计信息
  Map<String, int> get _filterStats {
    final filtered = _filteredProjects;
    final edited = filtered.where((p) =>
        p.glyphs.values.where((g) => g.contours.isNotEmpty).length > 0).length;
    final completed = filtered.where((p) {
      final ec = p.glyphs.values.where((g) => g.contours.isNotEmpty).length;
      return ec > 0 && ec >= p.glyphs.length * 0.8;
    }).length;
    final totalGlyphs = filtered.fold(0, (sum, p) => sum + p.glyphs.length);
    return {
      'total': filtered.length,
      'edited': edited,
      'completed': completed,
      'totalGlyphs': totalGlyphs,
    };
  }

  /// 显示高级筛选底部面板
  void _showAdvancedFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final stats = _filterStats;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('高级筛选', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (_hasActiveFilters)
                        TextButton(
                          onPressed: () {
                            _clearAllFilters();
                            setSheetState(() {});
                          },
                          child: Text('重置', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 结果统计
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildFilterStat('匹配', stats['total'].toString(), Theme.of(ctx).colorScheme),
                        _buildFilterStat('已编辑', stats['edited'].toString(), Theme.of(ctx).colorScheme),
                        _buildFilterStat('已完成', stats['completed'].toString(), Theme.of(ctx).colorScheme),
                        _buildFilterStat('总字符', stats['totalGlyphs'].toString(), Theme.of(ctx).colorScheme),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 状态筛选
                  const Text('项目状态', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildFilterChip(null, '全部', _filterStatus, (v) => setSheetState(() => _filterStatus = v)),
                      _buildFilterChip('completed', '已完成', _filterStatus, (v) => setSheetState(() => _filterStatus = v)),
                      _buildFilterChip('in_progress', '进行中', _filterStatus, (v) => setSheetState(() => _filterStatus = v)),
                      _buildFilterChip('empty', '未开始', _filterStatus, (v) => setSheetState(() => _filterStatus = v)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 字符数范围
                  const Text('字符数量', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildFilterChip(null, '全部', _filterCharRange, (v) => setSheetState(() => _filterCharRange = v)),
                      _buildFilterChip('small', '<20个', _filterCharRange, (v) => setSheetState(() => _filterCharRange = v)),
                      _buildFilterChip('medium', '20-50个', _filterCharRange, (v) => setSheetState(() => _filterCharRange = v)),
                      _buildFilterChip('large', '>50个', _filterCharRange, (v) => setSheetState(() => _filterCharRange = v)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 时间范围
                  const Text('更新时间', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildFilterChip(null, '全部', _filterTimeRange, (v) => setSheetState(() => _filterTimeRange = v)),
                      _buildFilterChip('today', '今天', _filterTimeRange, (v) => setSheetState(() => _filterTimeRange = v)),
                      _buildFilterChip('week', '最近一周', _filterTimeRange, (v) => setSheetState(() => _filterTimeRange = v)),
                      _buildFilterChip('month', '最近一月', _filterTimeRange, (v) => setSheetState(() => _filterTimeRange = v)),
                      _buildFilterChip('older', '更早', _filterTimeRange, (v) => setSheetState(() => _filterTimeRange = v)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // 保存为预设
                  if (_hasActiveFilters)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final controller = TextEditingController();
                        final name = await showDialog<String>(
                          context: ctx,
                          builder: (dctx) => AlertDialog(
                            title: const Text('保存筛选预设'),
                            content: TextField(controller: controller, decoration: const InputDecoration(hintText: '预设名称')),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
                              FilledButton(onPressed: () => Navigator.pop(dctx, controller.text.trim()), child: const Text('保存')),
                            ],
                          ),
                        );
                        if (name != null && name.isNotEmpty) {
                          await _saveFilterPreset(name);
                          setSheetState(() {});
                        }
                      },
                      icon: const Icon(Icons.bookmark_add),
                      label: const Text('保存为预设'),
                    ),
                  // 已保存的预设
                  if (_filterPresets.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('已保存的预设', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    ..._filterPresets.asMap().entries.map((entry) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.bookmark, size: 20),
                      title: Text(entry.value['name'] ?? '未命名'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _deleteFilterPreset(entry.key),
                      ),
                      onTap: () {
                        _applyFilterPreset(entry.value);
                        Navigator.pop(ctx);
                      },
                    )),
                  ],
                  const SizedBox(height: 16),
                  // 应用按钮
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('应用筛选'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 构建筛选条件Chip
  Widget _buildFilterChip(String? value, String label, String? groupValue, ValueChanged<String?> onSelected) {
    final isSelected = value == groupValue;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(isSelected ? null : value),
    );
  }

  /// 构建筛选统计项
  Widget _buildFilterStat(String label, String value, ColorScheme cs) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.primary)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
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
          _sortMode = SortMode.progressDesc;
          break;
        case SortMode.progressDesc:
          _sortMode = SortMode.progressAsc;
          break;
        case SortMode.progressAsc:
          _sortMode = SortMode.updatedDesc;
          break;
      }
      _sortProjects();
    });
  }

  /// 显示排序选项底部面板（支持多字段排序和预设）
  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('排序方式', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              // 主排序
              const Text('主排序', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: SortMode.values.map((mode) {
                  final info = _getSortInfoForMode(mode);
                  return ChoiceChip(
                    label: Text(info.$2),
                    selected: _sortMode == mode,
                    onSelected: (_) {
                      setState(() {
                        _sortMode = mode;
                        _sortProjects();
                      });
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // 二级排序
              const Text('二级排序（可选）', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('无'),
                    selected: _secondarySortMode == null,
                    onSelected: (_) {
                      setState(() => _secondarySortMode = null);
                      Navigator.pop(ctx);
                    },
                  ),
                  ...SortMode.values.where((m) => m != _sortMode).map((mode) {
                    final info = _getSortInfoForMode(mode);
                    return ChoiceChip(
                      label: Text(info.$2),
                      selected: _secondarySortMode == mode,
                      onSelected: (_) {
                        setState(() {
                          _secondarySortMode = mode;
                          _sortProjects();
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 获取排序图标和文字
  (IconData, String) _getSortInfo() {
    return _getSortInfoForMode(_sortMode);
  }

  /// 获取指定排序模式的图标和文字
  (IconData, String) _getSortInfoForMode(SortMode mode) {
    switch (mode) {
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
      case SortMode.progressDesc:
        return (Icons.trending_up, '进度↓');
      case SortMode.progressAsc:
        return (Icons.trending_up, '进度↑');
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

  // ═══════════════════════════════════════════════════════════
  // 数据导出功能：CSV、JSON、PDF、Excel
  // ═══════════════════════════════════════════════════════════

  /// 导出项目列表为 CSV 格式
  ///
  /// 将当前筛选后的项目列表导出为 CSV 文件
  /// 包含项目名称、字符数、完成度、创建时间、更新时间等字段
  Future<void> _exportProjectsAsCsv() async {
    try {
      final projects = _filteredProjects;
      if (projects.isEmpty) {
        if (mounted) WFSnackBar.show(context, '没有可导出的项目');
        return;
      }

      final buffer = StringBuffer();
      // CSV 表头
      buffer.writeln('项目名称,字符数,已编辑数,完成率(%),创建时间,更新时间');

      for (final project in projects) {
        final glyphCount = project.glyphs.length;
        final editedCount = project.glyphs.values
            .where((g) => g.contours.isNotEmpty)
            .length;
        final progress = glyphCount > 0
            ? (editedCount / glyphCount * 100).toStringAsFixed(1)
            : '0.0';

        // CSV 字段转义（处理包含逗号的项目名称）
        final safeName = project.name.contains(',')
            ? '"${project.name}"'
            : project.name;

        buffer.writeln(
          '$safeName,$glyphCount,$editedCount,$progress,'
          '${project.createdAt.toIso8601String()},'
          '${project.updatedAt.toIso8601String()}',
        );
      }

      // 保存到临时文件
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final fileName = 'writefont_projects_$timestamp.csv';
      final filePath = '${Directory.systemTemp.path}/$fileName';
      final file = File(filePath);
      // 添加 BOM 头以支持中文在 Excel 中正确显示
      await file.writeAsString('\uFEFF${buffer.toString()}');

      // 分享文件
      await Share.shareXFiles([XFile(filePath)], subject: 'WriteFont 项目列表 CSV');

      if (mounted) {
        WFSnackBar.show(context, 'CSV 导出完成: ${projects.length} 个项目');
      }
      debugPrint('[ProjectListScreen] CSV 导出完成: $filePath');
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, 'CSV 导出失败: $e');
      }
      debugPrint('[ProjectListScreen] CSV 导出失败: $e');
    }
  }

  /// 导出项目列表为 JSON 格式
  ///
  /// 将当前筛选后的项目列表导出为 JSON 文件
  /// 包含完整的项目元数据（不含源图片二进制数据）
  Future<void> _exportProjectsAsJson() async {
    try {
      final projects = _filteredProjects;
      if (projects.isEmpty) {
        if (mounted) WFSnackBar.show(context, '没有可导出的项目');
        return;
      }

      final exportData = <String, dynamic>{
        'exportDate': DateTime.now().toIso8601String(),
        'appVersion': 'v2.13.0',
        'format': 'WriteFont Project List Export',
        'projectCount': projects.length,
        'projects': projects.map((p) {
          final glyphCount = p.glyphs.length;
          final editedCount = p.glyphs.values
              .where((g) => g.contours.isNotEmpty)
              .length;
          return {
            'id': p.id,
            'name': p.name,
            'glyphCount': glyphCount,
            'editedCount': editedCount,
            'progress': glyphCount > 0
                ? (editedCount / glyphCount * 100).toStringAsFixed(1)
                : '0.0',
            'createdAt': p.createdAt.toIso8601String(),
            'updatedAt': p.updatedAt.toIso8601String(),
          };
        }).toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final fileName = 'writefont_projects_$timestamp.json';
      final filePath = '${Directory.systemTemp.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(jsonString);

      await Share.shareXFiles([XFile(filePath)], subject: 'WriteFont 项目列表 JSON');

      if (mounted) {
        WFSnackBar.show(context, 'JSON 导出完成: ${projects.length} 个项目');
      }
      debugPrint('[ProjectListScreen] JSON 导出完成: $filePath');
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, 'JSON 导出失败: $e');
      }
      debugPrint('[ProjectListScreen] JSON 导出失败: $e');
    }
  }

  /// 导出项目列表为 PDF 格式（文本形式）
  ///
  /// 由于无 PDF 生成依赖，使用格式化文本替代
  /// 包含项目概览和详情表格
  Future<void> _exportProjectsAsPdf() async {
    try {
      final projects = _filteredProjects;
      if (projects.isEmpty) {
        if (mounted) WFSnackBar.show(context, '没有可导出的项目');
        return;
      }

      final buffer = StringBuffer();
      buffer.writeln('╔══════════════════════════════════════════════════════╗');
      buffer.writeln('║            WriteFont 项目报告 (PDF 格式)            ║');
      buffer.writeln('║            生成时间: ${DateTime.now().toLocal()}            ║');
      buffer.writeln('╚══════════════════════════════════════════════════════╝');
      buffer.writeln();

      // 统计概览
      int totalGlyphs = 0;
      int totalEdited = 0;
      for (final p in projects) {
        totalGlyphs += p.glyphs.length;
        totalEdited += p.glyphs.values.where((g) => g.contours.isNotEmpty).length;
      }

      buffer.writeln('┌─ 项目概览 ─────────────────────────────────────────┐');
      buffer.writeln('│  总项目数: ${projects.length}');
      buffer.writeln('│  总字符数: $totalGlyphs');
      buffer.writeln('│  已编辑数: $totalEdited');
      buffer.writeln('│  完成率: ${totalGlyphs > 0 ? (totalEdited / totalGlyphs * 100).toStringAsFixed(1) : 0}%');
      buffer.writeln('└─────────────────────────────────────────────────────┘');
      buffer.writeln();

      // 项目详情表格
      buffer.writeln('┌─ 项目详情 ─────────────────────────────────────────┐');
      buffer.writeln('│  序号 │ 项目名称          │ 字符 │ 编辑 │ 进度   │');
      buffer.writeln('├───────┼───────────────────┼──────┼──────┼────────┤');

      for (int i = 0; i < projects.length; i++) {
        final p = projects[i];
        final glyphCount = p.glyphs.length;
        final editedCount = p.glyphs.values
            .where((g) => g.contours.isNotEmpty)
            .length;
        final progress = glyphCount > 0
            ? '${(editedCount / glyphCount * 100).toStringAsFixed(0)}%'
            : '0%';
        final name = p.name.length > 16
            ? '${p.name.substring(0, 16)}..'
            : p.name.padRight(18);

        buffer.writeln('│  ${(i + 1).toString().padLeft(4)} │ $name │ ${glyphCount.toString().padLeft(4)} │ ${editedCount.toString().padLeft(4)} │ ${progress.padLeft(6)} │');
      }

      buffer.writeln('└───────┴───────────────────┴──────┴──────┴────────┘');
      buffer.writeln();
      buffer.writeln('报告结束 - WriteFont v2.13.0');

      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final fileName = 'writefont_report_$timestamp.txt';
      final filePath = '${Directory.systemTemp.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles([XFile(filePath)], subject: 'WriteFont 项目报告');

      if (mounted) {
        WFSnackBar.show(context, '报告导出完成: ${projects.length} 个项目');
      }
      debugPrint('[ProjectListScreen] PDF 报告导出完成: $filePath');
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '报告导出失败: $e');
      }
      debugPrint('[ProjectListScreen] PDF 报告导出失败: $e');
    }
  }

  /// 导出项目列表为 Excel 格式（TSV 格式，兼容 Excel 打开）
  ///
  /// 使用制表符分隔，可直接在 Excel 中打开
  /// 包含多个工作表风格的数据分区
  Future<void> _exportProjectsAsExcel() async {
    try {
      final projects = _filteredProjects;
      if (projects.isEmpty) {
        if (mounted) WFSnackBar.show(context, '没有可导出的项目');
        return;
      }

      final buffer = StringBuffer();

      // Sheet 1: 项目列表
      buffer.writeln('WriteFont 项目数据导出');
      buffer.writeln('导出时间:\t${DateTime.now().toLocal()}');
      buffer.writeln();

      // 表头
      buffer.writeln('项目名称\t项目ID\t字符数\t已编辑数\t完成率(%)\t创建时间\t更新时间\t状态');

      for (final project in projects) {
        final glyphCount = project.glyphs.length;
        final editedCount = project.glyphs.values
            .where((g) => g.contours.isNotEmpty)
            .length;
        final progress = glyphCount > 0
            ? (editedCount / glyphCount * 100).toStringAsFixed(1)
            : '0.0';

        String status;
        if (glyphCount == 0 || editedCount == 0) {
          status = '未开始';
        } else if (editedCount >= glyphCount * 0.8) {
          status = '已完成';
        } else {
          status = '进行中';
        }

        buffer.writeln(
          '${project.name}\t${project.id}\t$glyphCount\t$editedCount\t$progress\t'
          '${project.createdAt.toIso8601String()}\t'
          '${project.updatedAt.toIso8601String()}\t$status',
        );
      }

      buffer.writeln();

      // Sheet 2: 统计汇总
      buffer.writeln('统计汇总');
      buffer.writeln('指标\t数值');

      int totalGlyphs = 0;
      int totalEdited = 0;
      int completedCount = 0;
      int inProgressCount = 0;
      int emptyCount = 0;

      for (final p in projects) {
        totalGlyphs += p.glyphs.length;
        totalEdited += p.glyphs.values.where((g) => g.contours.isNotEmpty).length;
        final edited = p.glyphs.values.where((g) => g.contours.isNotEmpty).length;
        if (p.glyphs.length == 0 || edited == 0) {
          emptyCount++;
        } else if (edited >= p.glyphs.length * 0.8) {
          completedCount++;
        } else {
          inProgressCount++;
        }
      }

      buffer.writeln('总项目数\t${projects.length}');
      buffer.writeln('总字符数\t$totalGlyphs');
      buffer.writeln('已编辑字符\t$totalEdited');
      buffer.writeln('完成率\t${totalGlyphs > 0 ? (totalEdited / totalGlyphs * 100).toStringAsFixed(1) : 0}%');
      buffer.writeln('已完成项目\t$completedCount');
      buffer.writeln('进行中项目\t$inProgressCount');
      buffer.writeln('未开始项目\t$emptyCount');

      // 保存为 .xls 扩展名，Excel 可直接打开 TSV
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final fileName = 'writefont_data_$timestamp.xls';
      final filePath = '${Directory.systemTemp.path}/$fileName';
      final file = File(filePath);
      // 添加 BOM 头支持中文
      await file.writeAsString('\uFEFF${buffer.toString()}');

      await Share.shareXFiles([XFile(filePath)], subject: 'WriteFont 项目数据 Excel');

      if (mounted) {
        WFSnackBar.show(context, 'Excel 导出完成: ${projects.length} 个项目');
      }
      debugPrint('[ProjectListScreen] Excel 导出完成: $filePath');
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, 'Excel 导出失败: $e');
      }
      debugPrint('[ProjectListScreen] Excel 导出失败: $e');
    }
  }

  /// 显示数据导出选项面板
  ///
  /// 提供 CSV、JSON、PDF、Excel 四种导出格式选择
  void _showExportOptionsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '数据导出',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '导出 ${_filteredProjects.length} 个项目的数据',
                style: TextStyle(fontSize: 14, color: WFColors.textSecondaryColor(context)),
              ),
              const SizedBox(height: 20),
              // CSV 导出
              ListTile(
                leading: const Icon(Icons.table_chart, color: WFColors.success),
                title: const Text('CSV 格式'),
                subtitle: const Text('适合在表格软件中打开'),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportProjectsAsCsv();
                },
              ),
              // JSON 导出
              ListTile(
                leading: const Icon(Icons.code, color: WFColors.info),
                title: const Text('JSON 格式'),
                subtitle: const Text('适合程序化处理和备份'),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportProjectsAsJson();
                },
              ),
              // PDF 导出
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: WFColors.error),
                title: const Text('PDF 报告'),
                subtitle: const Text('生成格式化的项目报告'),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportProjectsAsPdf();
                },
              ),
              // Excel 导出
              ListTile(
                leading: const Icon(Icons.grid_on, color: WFColors.warning),
                title: const Text('Excel 格式'),
                subtitle: const Text('包含项目列表和统计汇总'),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportProjectsAsExcel();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
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

  /// 批量导入项目备份
  ///
  /// 支持同时选择多个 JSON 文件进行批量导入
  /// 导入前自动检测文件格式（WriteFont 备份 JSON 或字体项目 JSON）
  Future<void> _batchImportProjects() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: '选择要导入的项目文件（支持多选）',
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      int successCount = 0;
      int failCount = 0;
      final List<String> errors = [];

      for (final file in result.files) {
        final filePath = file.path;
        if (filePath == null) {
          failCount++;
          continue;
        }

        try {
          final fileObj = File(filePath);
          final jsonString = await fileObj.readAsString();
          final json = jsonDecode(jsonString) as Map<String, dynamic>;

          // 格式检测：检查必要字段
          final formatType = _detectImportFormat(json);
          if (formatType == 'unknown') {
            failCount++;
            errors.add('${file.name}: 不支持的文件格式');
            continue;
          }

          final project = await StorageService.importProjectFromJson(json);
          if (project != null) {
            successCount++;
          } else {
            failCount++;
            errors.add('${file.name}: 数据解析失败');
          }
        } catch (e) {
          failCount++;
          errors.add('${file.name}: $e');
        }
      }

      await _loadProjects();
      if (mounted) {
        final message = '批量导入完成: $successCount 成功, $failCount 失败';
        if (errors.isNotEmpty && errors.length <= 3) {
          WFSnackBar.show(context, '$message\n${errors.join('\n')}');
        } else {
          WFSnackBar.show(context, message);
        }
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '批量导入失败: $e');
      }
    }
  }

  /// 导入字体文件（TTF/OTF）
  ///
  /// 从字体文件中提取字形数据创建新项目
  Future<void> _importFontFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
        dialogTitle: '选择字体文件',
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) {
        if (mounted) WFSnackBar.show(context, '无法读取文件路径');
        return;
      }

      // 检测文件格式
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final fileName = result.files.single.name;

      // 简单的字体文件格式检测
      if (bytes.length < 4) {
        if (mounted) WFSnackBar.error(context, '文件格式无效');
        return;
      }

      // 检查 TTF/OTF 魔数
      final magic = String.fromCharCodes(bytes.take(4));
      final isTtf = magic == '\x00\x01\x00\x00' || magic == 'true';
      final isOtf = magic == 'OTTO';

      if (!isTtf && !isOtf) {
        if (mounted) {
          WFSnackBar.error(context, '不支持的字体格式，仅支持 TTF 和 OTF 文件');
        }
        return;
      }

      // 从文件名提取项目名称
      final projectName = fileName.replaceAll(RegExp(r'\.(ttf|otf)$'), '');

      // 创建基础项目结构
      final project = FontProject(
        id: StorageService.generateId(),
        name: projectName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        glyphs: {},
        params: ProcessingParams(),
      );

      await StorageService.saveProject(project);
      await _loadProjects();

      if (mounted) {
        WFSnackBar.show(context, '已导入字体文件「$projectName」，请在项目中编辑字形');
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '导入字体文件失败: $e');
      }
    }
  }

  /// 检测导入文件格式
  ///
  /// 返回格式类型：
  /// - 'writefont_backup': WriteFont 完整备份（含 glyphs + sourceImagesBase64）
  /// - 'writefont_project': WriteFont 项目 JSON（含 name + glyphs）
  /// - 'csv_export': CSV 导出数据
  /// - 'unknown': 不支持的格式
  String _detectImportFormat(Map<String, dynamic> json) {
    // 检查 WriteFont 完整备份格式
    if (json.containsKey('name') &&
        json.containsKey('glyphs') &&
        json.containsKey('sourceImagesBase64')) {
      return 'writefont_backup';
    }

    // 检查 WriteFont 项目格式
    if (json.containsKey('name') && json.containsKey('glyphs')) {
      return 'writefont_project';
    }

    // 检查 WriteFont 导出格式（包含 projects 数组）
    if (json.containsKey('format') &&
        json['format'] == 'WriteFont Project List Export') {
      return 'csv_export';
    }

    return 'unknown';
  }

  /// 显示导入选项面板
  ///
  /// 提供多种导入方式选择
  void _showImportOptionsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '导入项目',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '选择要导入的文件类型',
                style: TextStyle(fontSize: 14, color: WFColors.textSecondaryColor(context)),
              ),
              const SizedBox(height: 20),
              // 项目备份导入
              ListTile(
                leading: const Icon(Icons.file_upload, color: WFColors.primary),
                title: const Text('导入项目备份'),
                subtitle: const Text('从 JSON 备份文件导入单个项目'),
                onTap: () {
                  Navigator.pop(ctx);
                  _importProject();
                },
              ),
              // 批量导入
              ListTile(
                leading: const Icon(Icons.upload_file, color: WFColors.info),
                title: const Text('批量导入'),
                subtitle: const Text('同时导入多个 JSON 项目文件'),
                onTap: () {
                  Navigator.pop(ctx);
                  _batchImportProjects();
                },
              ),
              // 字体文件导入
              ListTile(
                leading: const Icon(Icons.font_download, color: WFColors.success),
                title: const Text('导入字体文件'),
                subtitle: const Text('从 TTF/OTF 字体文件创建项目'),
                onTap: () {
                  Navigator.pop(ctx);
                  _importFontFile();
                },
              ),
              const SizedBox(height: 16),
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
      WFAnimations.slideRoute(PreviewScreen(project: project)),
    ).then((_) => _loadProjects()); // 返回时刷新列表
  }

  /// 构建搜索建议列表
  Widget _buildSearchSuggestions(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _searchSuggestions.map((suggestion) {
          return ListTile(
            dense: true,
            leading: Icon(Icons.search, size: 18, color: colorScheme.onSurfaceVariant),
            title: _buildHighlightedText(suggestion, _searchQuery, colorScheme),
            onTap: () {
              _searchController.text = suggestion;
              _executeSearch(suggestion);
            },
          );
        }).toList(),
      ),
    );
  }

  /// 构建搜索历史记录列表
  Widget _buildSearchHistory(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.history, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('搜索历史', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                const Spacer(),
                GestureDetector(
                  onTap: _clearSearchHistory,
                  child: Text('清除', style: TextStyle(fontSize: 12, color: colorScheme.error)),
                ),
              ],
            ),
          ),
          ..._searchHistory.take(5).map((query) => ListTile(
            dense: true,
            leading: Icon(Icons.access_time, size: 16, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            title: Text(query, style: TextStyle(fontSize: 14, color: colorScheme.onSurface)),
            trailing: Icon(Icons.north_west, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            onTap: () {
              _searchController.text = query;
              _executeSearch(query);
            },
          )),
        ],
      ),
    );
  }

  /// 构建带高亮的文本（用于搜索建议）
  Widget _buildHighlightedText(String text, String query, ColorScheme colorScheme) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);
    if (index == -1) {
      return Text(text, style: TextStyle(fontSize: 14, color: colorScheme.onSurface));
    }
    return RichText(
      text: TextSpan(children: [
        TextSpan(text: text.substring(0, index), style: TextStyle(fontSize: 14, color: colorScheme.onSurface)),
        TextSpan(text: text.substring(index, index + query.length), style: TextStyle(fontSize: 14, color: colorScheme.primary, fontWeight: FontWeight.bold)),
        TextSpan(text: text.substring(index + query.length), style: TextStyle(fontSize: 14, color: colorScheme.onSurface)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 构建筛选状态指示条
  Widget _buildFilterIndicator(ColorScheme colorScheme) {
    final stats = _filterStats;
    final conditions = <String>[];
    if (_filterStatus != null) {
      final info = _getFilterInfo();
      conditions.add(info.$2);
    }
    if (_filterCharRange != null) {
      switch (_filterCharRange) {
        case 'small': conditions.add('<20字符'); break;
        case 'medium': conditions.add('20-50字符'); break;
        case 'large': conditions.add('>50字符'); break;
      }
    }
    if (_filterTimeRange != null) {
      switch (_filterTimeRange) {
        case 'today': conditions.add('今天'); break;
        case 'week': conditions.add('最近一周'); break;
        case 'month': conditions.add('最近一月'); break;
        case 'older': conditions.add('更早'); break;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: colorScheme.primaryContainer.withValues(alpha: 0.2),
      child: Row(
        children: [
          Icon(Icons.filter_list_alt, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              conditions.isEmpty ? '筛选' : conditions.join(' · '),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colorScheme.primary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${stats["total"]} 项目 · ${stats["totalGlyphs"]} 字符',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _clearAllFilters,
            child: Text('清除筛选', style: TextStyle(fontSize: 12, color: colorScheme.error)),
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
              onPressed: _showAdvancedFilterSheet,
              onLongPress: _cycleFilterStatus,
              icon: Icon(_hasActiveFilters ? Icons.filter_list_alt : filterInfo.$1),
              tooltip: '筛选${_hasActiveFilters ? " (已激活)" : ": ${filterInfo.$2}"}',
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
            onPressed: _showImportOptionsSheet,
            icon: const Icon(Icons.file_upload),
            tooltip: '导入项目',
          ),
          // 数据导出按钮
          if (_projects.isNotEmpty && !_isMultiSelectMode)
            IconButton(
              onPressed: _showExportOptionsSheet,
              icon: const Icon(Icons.file_download),
              tooltip: '数据导出',
            ),
          // 排序按钮
          IconButton(
            onPressed: _showSortSheet,
            onLongPress: _toggleSortMode,
            icon: Icon(sortInfo.$1),
            tooltip: '排序: ${sortInfo.$2}${_secondarySortMode != null ? " (二级)" : ""}',
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
                      onChanged: (value) {
                        setState(() => _searchQuery = value.trim());
                        _updateSearchSuggestions(value.trim());
                      },
                      onSubmitted: _executeSearch,
                      onClear: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _showSuggestions = false;
                        });
                      },
                    ),
                    // 搜索建议和历史记录
                    if (_showSuggestions && _searchSuggestions.isNotEmpty)
                      _buildSearchSuggestions(colorScheme)
                    else if (_searchQuery.isEmpty && _searchHistory.isNotEmpty)
                      _buildSearchHistory(colorScheme),
                    // 筛选状态指示
                    if (_hasActiveFilters)
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
