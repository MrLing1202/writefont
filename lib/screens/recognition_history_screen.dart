import 'package:flutter/material.dart';
import '../models/recognition_history.dart';
import '../theme/app_theme.dart';
import 'recognition_diagnostic_screen.dart';

/// 识别历史记录页面
///
/// 展示所有识别历史，支持按字符搜索、查看统计数据、清空历史。
class RecognitionHistoryScreen extends StatefulWidget {
  const RecognitionHistoryScreen({super.key});

  @override
  State<RecognitionHistoryScreen> createState() => _RecognitionHistoryScreenState();
}

class _RecognitionHistoryScreenState extends State<RecognitionHistoryScreen> {
  List<RecognitionHistoryEntry> _entries = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  bool _showStats = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final entries = await RecognitionHistoryService.getAll();
      final stats = await RecognitionHistoryService.getStats();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  List<RecognitionHistoryEntry> get _filteredEntries {
    if (_searchQuery.isEmpty) return _entries;
    return _entries.where((e) => e.character.contains(_searchQuery)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: WFAppBar(
        title: '识别历史',
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecognitionDiagnosticScreen()),
              );
            },
            icon: const Icon(Icons.analytics_outlined),
            tooltip: '识别诊断报告',
          ),
          IconButton(
            onPressed: () => setState(() => _showStats = !_showStats),
            icon: Icon(_showStats ? Icons.list : Icons.bar_chart),
            tooltip: _showStats ? '查看列表' : '查看统计',
          ),
          IconButton(
            onPressed: _confirmClear,
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空历史',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmptyState(colorScheme)
              : _showStats
                  ? _buildStatsView(colorScheme)
                  : _buildListView(colorScheme),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无识别历史',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '识别字符后会自动记录在这里',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(ColorScheme colorScheme) {
    final filtered = _filteredEntries;

    return Column(
      children: [
        // 搜索栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: '搜索字符...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      onPressed: () => setState(() => _searchQuery = ''),
                      icon: const Icon(Icons.clear, size: 18),
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
          ),
        ),

        // 数量提示
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                _searchQuery.isEmpty
                    ? '共 ${_entries.length} 条记录'
                    : '找到 ${filtered.length} 条',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),

        // 列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filtered.length,
            itemBuilder: (ctx, index) {
              final entry = filtered[index];
              return _buildHistoryCard(entry, colorScheme, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryCard(RecognitionHistoryEntry entry, ColorScheme colorScheme, int index) {
    final confColor = entry.confidence >= 0.8
        ? Colors.green
        : entry.confidence >= 0.6
            ? Colors.orange
            : Colors.red;

    final timeStr = _formatTime(entry.timestamp);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 字符展示
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  entry.character,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 详情
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 置信度标签
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: confColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${(entry.confidence * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: confColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 模式标签
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: entry.mode == 'cloud'
                              ? Colors.blue.withValues(alpha: 0.15)
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          entry.mode == 'cloud' ? '云端' : '本地',
                          style: TextStyle(
                            fontSize: 10,
                            color: entry.mode == 'cloud'
                                ? Colors.blue
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (entry.wasCorrected) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '已纠正',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 候选字
                  if (entry.candidates.length > 1)
                    Text(
                      '候选: ${entry.candidates.take(5).join("、")}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  // 时间
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsView(ColorScheme colorScheme) {
    final total = _stats['total'] ?? 0;
    final corrected = _stats['corrected'] ?? 0;
    final correctionRate = _stats['correctionRate'] ?? 0.0;
    final localCount = _stats['localCount'] ?? 0;
    final cloudCount = _stats['cloudCount'] ?? 0;
    final avgConf = _stats['avgConfidence'] ?? 0.0;
    final topChars = _stats['topCharacters'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 总览卡片
          _buildStatCard(
            title: '识别总览',
            colorScheme: colorScheme,
            children: [
              _buildStatRow('总识别次数', '$total', colorScheme),
              _buildStatRow('平均置信度', '${(avgConf * 100).toStringAsFixed(1)}%', colorScheme),
              _buildStatRow('纠正次数', '$corrected (${(correctionRate * 100).toStringAsFixed(1)}%)', colorScheme),
              _buildStatRow('本地识别', '$localCount', colorScheme),
              _buildStatRow('云端识别', '$cloudCount', colorScheme),
            ],
          ),

          const SizedBox(height: 16),

          // 常用字符
          if (topChars.isNotEmpty)
            _buildStatCard(
              title: '高频字符 Top10',
              colorScheme: colorScheme,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: topChars.map((item) {
                    final parts = (item as String).split(':');
                    if (parts.length < 2) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            parts[0],
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            '${parts[1]} 次',
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required ColorScheme colorScheme,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';

    return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmClear() async {
    final confirmed = await WFDialog.confirm(
      context,
      title: '清空识别历史',
      message: '确定要清空所有识别历史记录吗？该操作不可撤销。',
      confirmText: '清空',
      isDestructive: true,
      icon: Icons.delete_forever,
      iconColor: WFColors.error,
    );

    if (confirmed == true) {
      await RecognitionHistoryService.clear();
      await _loadData();
      if (mounted) {
        WFSnackBar.show(context, '历史记录已清空');
      }
    }
  }
}
