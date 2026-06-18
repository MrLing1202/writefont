import 'package:flutter/material.dart';
import '../models/project.dart';
import '../data/standard_charset.dart';
import '../services/storage_service.dart';
import 'character_edit_screen.dart';
import 'capture_screen.dart';
import 'font_test_screen.dart';
import 'font_quality_screen.dart';
import '../theme/app_theme.dart';

/// 筛选模式枚举
enum FilterMode {
  all, // 全部
  completed, // 已完成
  incomplete, // 未完成
}

/// 字符总览网格页面：显示项目中所有字符的状态和进度
class CharacterGridScreen extends StatefulWidget {
  final FontProject project;

  const CharacterGridScreen({super.key, required this.project});

  @override
  State<CharacterGridScreen> createState() => _CharacterGridScreenState();
}

class _CharacterGridScreenState extends State<CharacterGridScreen> {
  late FontProject _project;
  FilterMode _filterMode = FilterMode.all;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // 批量选择模式
  bool _isSelectionMode = false;
  final Set<String> _selectedChars = {};

  @override
  void initState() {
    super.initState();
    _project = widget.project;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 获取所有字符（标准40字 + 用户添加的字符）
  List<String> _getAllCharacters() {
    final standardChars = StandardCharset.allCharStrings;
    final userChars = _project.glyphs.keys
        .where((c) => !standardChars.contains(c))
        .toList();
    return [...standardChars, ...userChars];
  }

  /// 获取筛选后的字符列表
  List<String> _getFilteredCharacters() {
    final allChars = _getAllCharacters();

    // 应用搜索过滤
    List<String> filtered = allChars;
    if (_searchQuery.isNotEmpty) {
      filtered =
          filtered.where((c) => c.contains(_searchQuery)).toList();
    }

    // 应用状态过滤
    switch (_filterMode) {
      case FilterMode.all:
        break;
      case FilterMode.completed:
        filtered = filtered.where((c) {
          final glyph = _project.glyphs[c];
          return glyph != null && glyph.contours.isNotEmpty;
        }).toList();
        break;
      case FilterMode.incomplete:
        filtered = filtered.where((c) {
          final glyph = _project.glyphs[c];
          return glyph == null || glyph.contours.isEmpty;
        }).toList();
        break;
    }

    return filtered;
  }

  /// 获取字符状态颜色
  Color _getCharacterColor(String char, ColorScheme colorScheme) {
    final glyph = _project.glyphs[char];
    if (glyph == null) {
      // 未开始 - 灰色
      return WFColors.textLight.withValues(alpha: 0.3);
    }
    if (glyph.contours.isNotEmpty) {
      // 已书写有轮廓数据 - 绿色
      return WFColors.success.withValues(alpha: 0.15);
    }
    if (glyph.sourceImagePath != null) {
      // 已拍照识别但未编辑 - 黄色
      return WFColors.warning.withValues(alpha: 0.15);
    }
    // 未开始 - 灰色
    return WFColors.textLight.withValues(alpha: 0.3);
  }

  /// 获取字符状态图标颜色
  Color _getCharacterIconColor(String char, ColorScheme colorScheme) {
    final glyph = _project.glyphs[char];
    if (glyph == null) {
      return WFColors.textSecondary.withValues(alpha: 0.4);
    }
    if (glyph.contours.isNotEmpty) {
      return WFColors.success;
    }
    if (glyph.sourceImagePath != null) {
      return WFColors.warning;
    }
    return WFColors.textSecondary.withValues(alpha: 0.4);
  }

  /// 获取字符状态文字
  String _getStatusText(String char) {
    final glyph = _project.glyphs[char];
    if (glyph == null) return '未开始';
    if (glyph.contours.isNotEmpty) return '已完成';
    if (glyph.sourceImagePath != null) return '已识别';
    return '未开始';
  }

  /// 处理字符点击
  void _onCharacterTap(String char) {
    final glyph = _project.glyphs[char];
    if (glyph != null && glyph.contours.isNotEmpty) {
      // 已编辑字符 → 进入编辑页面
      showDialog(
        context: context,
        builder: (ctx) => CharacterEditDialog(
          character: char,
          glyph: glyph,
          projectId: _project.id,
          onCharacterChanged: () {
            setState(() {});
            _saveProject();
          },
          onCharacterDeleted: () {
            setState(() {
              _project.glyphs.remove(char);
            });
            _saveProject();
          },
        ),
      );
    } else {
      // 未编辑字符 → 进入拍照页面
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CaptureScreen(charset: [char]),
        ),
      ).then((_) async {
        // 拍照返回后重新加载项目数据
        final updated = await StorageService.loadProject(_project.id);
        if (updated != null && mounted) {
          setState(() => _project = updated);
        }
      });
    }
  }

  /// 进入/退出选择模式
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedChars.clear();
      }
    });
  }

  /// 切换字符选中状态
  void _toggleCharSelection(String char) {
    setState(() {
      if (_selectedChars.contains(char)) {
        _selectedChars.remove(char);
        if (_selectedChars.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedChars.add(char);
      }
    });
  }

  /// 批量删除选中字符
  void _batchDelete() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除已选的 ${_selectedChars.length} 个字符吗？\n删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        setState(() {
          for (final char in _selectedChars) {
            _project.glyphs.remove(char);
          }
          _selectedChars.clear();
          _isSelectionMode = false;
        });
        _saveProject();
      }
    });
  }

  /// 保存项目
  Future<void> _saveProject() async {
    try {
      await StorageService.saveProject(_project);
    } catch (_) {}
  }

  /// 计算统计数据
  (int total, int completed, double progress) _getStats() {
    final allChars = _getAllCharacters();
    final total = allChars.length;
    final completed = allChars.where((c) {
      final glyph = _project.glyphs[c];
      return glyph != null && glyph.contours.isNotEmpty;
    }).length;
    final progress = total > 0 ? completed / total : 0.0;
    return (total, completed, progress);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stats = _getStats();
    final filteredChars = _getFilteredCharacters();

    return Scaffold(
      appBar: _isSelectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              ),
              title: Text('已选 ${_selectedChars.length} 个'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '批量删除',
                  onPressed: _selectedChars.isNotEmpty ? _batchDelete : null,
                ),
              ],
            )
          : WFAppBar(
              title: _project.name,
              actions: [
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FontTestScreen(project: _project),
                      ),
                    );
                  },
                  icon: const Icon(Icons.text_fields),
                  tooltip: '字体测试',
                ),
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FontQualityScreen(project: _project),
                      ),
                    );
                  },
                  icon: const Icon(Icons.assessment),
                  tooltip: '质量分析',
                ),
                IconButton(
                  onPressed: () async {
                    final updated =
                        await StorageService.loadProject(_project.id);
                    if (updated != null && mounted) {
                      setState(() => _project = updated);
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新',
                ),
              ],
            ),
      body: Column(
        children: [
          // 顶部统计栏
          _buildStatsBar(colorScheme, stats),
          // 搜索框
          _buildSearchBar(colorScheme),
          // 筛选按钮
          _buildFilterChips(colorScheme),
          // 字符网格
          Expanded(
            child: filteredChars.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isNotEmpty ? '未找到匹配的字符' : '暂无字符数据',
                      style: TextStyle(
                        fontSize: 16,
                        color: WFColors.textSecondary,
                      ),
                    ),
                  )
                : _buildCharacterGrid(filteredChars, colorScheme),
          ),
        ],
      ),
    );
  }

  /// 顶部统计栏
  Widget _buildStatsBar(
      ColorScheme colorScheme, (int, int, double) stats) {
    final total = stats.$1;
    final completed = stats.$2;
    final progress = stats.$3;

    return WFCard(
      accentColor: WFColors.primary,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // 圆形进度指示器
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: WFColors.textLight.withValues(alpha: 0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress >= 1.0 ? WFColors.success : WFColors.primary,
                  ),
                ),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: progress >= 1.0
                        ? WFColors.success
                        : WFColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 统计文字
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '造字进度',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: WFColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '已完成 $completed / $total 个字符',
                  style: TextStyle(
                    fontSize: 14,
                    color: WFColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // 图例
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildLegendItem(WFColors.success.withValues(alpha: 0.15), WFColors.success,
                  '已完成'),
              const SizedBox(height: 4),
              _buildLegendItem(
                  WFColors.warning.withValues(alpha: 0.15), WFColors.warning, '已识别'),
              const SizedBox(height: 4),
              _buildLegendItem(WFColors.textLight.withValues(alpha: 0.3),
                  WFColors.textSecondary, '未开始'),
            ],
          ),
        ],
      ),
    );
  }

  /// 图例项
  Widget _buildLegendItem(Color bgColor, Color textColor, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: textColor),
        ),
      ],
    );
  }

  /// 搜索框
  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '搜索字符...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.clear),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (value) {
          setState(() => _searchQuery = value);
        },
      ),
    );
  }

  /// 筛选按钮
  Widget _buildFilterChips(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          _buildFilterChip('全部', FilterMode.all, colorScheme),
          const SizedBox(width: 8),
          _buildFilterChip('已完成', FilterMode.completed, colorScheme),
          const SizedBox(width: 8),
          _buildFilterChip('未完成', FilterMode.incomplete, colorScheme),
        ],
      ),
    );
  }

  /// 单个筛选按钮
  Widget _buildFilterChip(
      String label, FilterMode mode, ColorScheme colorScheme) {
    final isSelected = _filterMode == mode;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filterMode = mode);
      },
      selectedColor: WFColors.primary.withValues(alpha: 0.15),
      checkmarkColor: WFColors.primary,
    );
  }

  /// 字符网格
  Widget _buildCharacterGrid(
      List<String> chars, ColorScheme colorScheme) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: chars.length,
      itemBuilder: (context, index) {
        final char = chars[index];
        return _buildCharacterCell(char, colorScheme);
      },
    );
  }

  /// 单个字符格子
  Widget _buildCharacterCell(String char, ColorScheme colorScheme) {
    final bgColor = _getCharacterColor(char, colorScheme);
    final iconColor = _getCharacterIconColor(char, colorScheme);
    final glyph = _project.glyphs[char];
    final isCompleted = glyph != null && glyph.contours.isNotEmpty;
    final isSelected = _selectedChars.contains(char);

    return GestureDetector(
      onTap: () {
        if (_isSelectionMode) {
          _toggleCharSelection(char);
        } else {
          _onCharacterTap(char);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          _toggleSelectionMode();
          _selectedChars.add(char);
          // setState 已在 _toggleSelectionMode 中调用
          setState(() {});
        }
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isSelected
              ? WFColors.primary.withValues(alpha: 0.2)
              : bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? WFColors.primary
                : isCompleted
                    ? WFColors.success.withValues(alpha: 0.5)
                    : WFColors.textLight.withValues(alpha: 0.3),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 字符
            Text(
              char,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isSelected ? WFColors.primary : iconColor,
              ),
            ),
            // 置信度指示器（右下角）
            if (!isSelected && glyph?.confidence != null)
              Positioned(
                right: 1,
                bottom: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: (glyph!.confidence! < 0.5)
                        ? WFColors.error.withValues(alpha: 0.85)
                        : (glyph.confidence! > 0.8)
                            ? WFColors.success.withValues(alpha: 0.85)
                            : WFColors.warning.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${(glyph.confidence! * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            else if (isCompleted && !isSelected)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: WFColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            // 选中勾选标记
            if (isSelected)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: WFColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
