import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/storage_service.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';

/// 字体对比工具页面
///
/// 支持选择多个已生成的字体项目，并排预览对比效果。
/// 可切换不同文字内容、字号大小，快速发现各字体间的差异。
class FontCompareScreen extends StatefulWidget {
  const FontCompareScreen({super.key});

  @override
  State<FontCompareScreen> createState() => _FontCompareScreenState();
}

class _FontCompareScreenState extends State<FontCompareScreen> {
  List<FontProject> _allProjects = [];
  final List<FontProject> _selected = [];
  String _previewText = '永东国酬鹰郁画齣龘龖';
  double _fontSize = 28;
  bool _loading = true;

  /// 预设文本选项
  static const _presetTexts = {
    '笔画全': '永东国酬鹰郁画齣龘龖',
    '常用字': '的一是不了人我在有他这中大来上个国到说们为子',
    '偏旁部首': '亻彳氵灬扌忄讠钅饣犭纟疒',
    '数字字母': '0123456789 ABCDEF abcdef',
    '标点符号': '，。！？、；：""''（）',
    ' pangram': 'The quick brown fox jumps over the lazy dog',
  };

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await StorageService.loadProjects();
      if (mounted) {
        setState(() {
          _allProjects = projects.where((p) => p.glyphs.isNotEmpty).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载项目失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('字体对比'),
        actions: [
          if (_selected.length >= 2)
            TextButton.icon(
              icon: const Icon(Icons.clear_all),
              label: const Text('清空'),
              onPressed: () => setState(() => _selected.clear()),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _allProjects.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildSelector(theme),
                    if (_selected.length >= 2) ...[
                      _buildToolbar(theme),
                      const Divider(height: 1),
                      Expanded(child: _buildCompareView()),
                    ] else
                      Expanded(child: _buildHint()),
                  ],
                ),
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.font_download_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('暂无已生成的字体', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('请先生成至少两个字体后再来对比', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ),
    );
  }

  /// 字体选择器
  Widget _buildSelector(ThemeData theme) {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _allProjects.length,
        itemBuilder: (context, index) {
          final project = _allProjects[index];
          final isSelected = _selected.contains(project);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _toggleSelection(project),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 80,
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.font_download,
                      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      size: 28,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      project.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    if (isSelected)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_selected.indexOf(project) + 1}',
                          style: TextStyle(fontSize: 10, color: theme.colorScheme.onPrimary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 工具栏
  Widget _buildToolbar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          // 预设文本
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _presetTexts.entries.map((e) {
                final isSelected = _previewText == e.value;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(e.key, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _previewText = e.value),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // 字号滑块
          Row(
            children: [
              const Text('字号: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 12,
                  max: 64,
                  divisions: 26,
                  label: '${_fontSize.round()}px',
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
              ),
              Text('${_fontSize.round()}px', style: const TextStyle(fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  /// 对比视图
  Widget _buildCompareView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _selected.length,
      itemBuilder: (context, index) {
        final project = _selected[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: WFColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        project.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${project.glyphs.length} 字',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _previewText,
                    style: TextStyle(fontSize: _fontSize, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 提示
  Widget _buildHint() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            '请选择至少 ${2 - _selected.length} 个字体',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '点击上方字体卡片进行选择',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  /// 切换选中状态
  void _toggleSelection(FontProject project) {
    setState(() {
      if (_selected.contains(project)) {
        _selected.remove(project);
      } else if (_selected.length < 4) {
        _selected.add(project);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('最多对比4个字体')),
        );
      }
    });
  }
}
