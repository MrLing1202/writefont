import 'dart:math';
import 'package:flutter/material.dart';
import '../models/recognition_history.dart';
import '../theme/app_theme.dart';

/// 识别诊断报告
///
/// 展示识别统计、字符置信度分布、薄弱字符分析、趋势、策略效果等。
class RecognitionDiagnosticScreen extends StatefulWidget {
  const RecognitionDiagnosticScreen({super.key});

  @override
  State<RecognitionDiagnosticScreen> createState() =>
      _RecognitionDiagnosticScreenState();
}

class _RecognitionDiagnosticScreenState
    extends State<RecognitionDiagnosticScreen> {
  // 原始数据
  List<RecognitionHistoryEntry> _entries = [];
  Map<String, dynamic> _stats = {};

  // 派生数据
  List<_CharDiagnostic> _charDiagnostics = [];
  List<_CharDiagnostic> _weakChars = [];
  Map<String, List<_ConfidenceBucket>> _histogramData = {};
  List<_StrategyEffectiveness> _strategyData = [];
  bool _isLoading = true;

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

      _entries = entries;
      _stats = stats;
      _analyzeData();

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('[Diagnostic] 加载失败: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 分析数据：字符诊断、直方图、趋势
  void _analyzeData() {
    // ── 按字符分组 ──
    final charMap = <String, List<RecognitionHistoryEntry>>{};
    for (final e in _entries) {
      if (e.character.isEmpty) continue;
      charMap.putIfAbsent(e.character, () => []);
      charMap[e.character]!.add(e);
    }

    // ── 字符诊断 ──
    _charDiagnostics = charMap.entries.map((entry) {
      final char = entry.key;
      final history = entry.value;
      final confidences = history.map((e) => e.confidence).toList();
      final avgConf = confidences.reduce((a, b) => a + b) / confidences.length;
      final correctionCount = history.where((e) => e.wasCorrected).length;

      // 趋势：前半 vs 后半
      final mid = history.length ~/ 2;
      final recentAvg = mid > 0
          ? history.sublist(0, mid).map((e) => e.confidence).reduce((a, b) => a + b) / mid
          : avgConf;
      final olderAvg = mid < history.length
          ? history.sublist(mid).map((e) => e.confidence).reduce((a, b) => a + b) /
              (history.length - mid)
          : avgConf;

      String trend;
      if (history.length < 3) {
        trend = 'insufficient';
      } else if (recentAvg > olderAvg + 0.03) {
        trend = 'improving';
      } else if (recentAvg < olderAvg - 0.03) {
        trend = 'declining';
      } else {
        trend = 'stable';
      }

      return _CharDiagnostic(
        character: char,
        count: history.length,
        avgConfidence: avgConf,
        minConfidence: confidences.reduce(min),
        maxConfidence: confidences.reduce(max),
        correctionCount: correctionCount,
        correctionRate: correctionCount / history.length,
        trend: trend,
        recentConfidence: recentAvg,
      );
    }).toList();

    _charDiagnostics.sort((a, b) => a.avgConfidence.compareTo(b.avgConfidence));

    // ── 薄弱字符（置信度 < 75% 或纠正率 > 20%）──
    _weakChars = _charDiagnostics
        .where((d) => d.avgConfidence < 0.75 || d.correctionRate > 0.2)
        .take(20)
        .toList();

    // ── 置信度分布直方图（按字符）──
    final buckets = <_ConfidenceBucket>[];
    for (int i = 0; i < 10; i++) {
      buckets.add(_ConfidenceBucket(
        label: '${i * 10}-${(i + 1) * 10}%',
        min: i / 10,
        max: (i + 1) / 10,
        count: 0,
      ));
    }
    for (final d in _charDiagnostics) {
      final bucketIndex = (d.avgConfidence * 10).floor().clamp(0, 9);
      buckets[bucketIndex].count++;
    }
    _histogramData['overall'] = buckets;

    // ── 置信度分布直方图（按记录）──
    final entryBuckets = <_ConfidenceBucket>[];
    for (int i = 0; i < 10; i++) {
      entryBuckets.add(_ConfidenceBucket(
        label: '${i * 10}-${(i + 1) * 10}%',
        min: i / 10,
        max: (i + 1) / 10,
        count: 0,
      ));
    }
    for (final e in _entries) {
      final bucketIndex = (e.confidence * 10).floor().clamp(0, 9);
      entryBuckets[bucketIndex].count++;
    }
    _histogramData['entries'] = entryBuckets;

    // ── 策略效果（按识别模式统计）──
    final modeStats = <String, _StrategyEffectiveness>{};
    for (final e in _entries) {
      final key = e.mode;
      if (!modeStats.containsKey(key)) {
        modeStats[key] = _StrategyEffectiveness(
          name: key == 'cloud' ? '云端识别' : '本地识别',
          count: 0,
          totalConfidence: 0,
          correctionCount: 0,
        );
      }
      final stat = modeStats[key]!;
      stat.count++;
      stat.totalConfidence += e.confidence;
      if (e.wasCorrected) stat.correctionCount++;
    }
    _strategyData = modeStats.values.toList();
    _strategyData.sort((a, b) => b.count.compareTo(a.count));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const WFAppBar(title: '识别诊断报告'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmptyState(colorScheme)
              : _buildReport(colorScheme),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('暂无识别数据',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('识别字符后自动生成诊断报告',
              style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _buildReport(ColorScheme colorScheme) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. 总览
          _buildOverviewCard(colorScheme),
          const SizedBox(height: 16),
          // 2. 置信度分布
          _buildHistogramCard(colorScheme),
          const SizedBox(height: 16),
          // 3. 薄弱字符
          if (_weakChars.isNotEmpty) ...[
            _buildWeakCharsCard(colorScheme),
            const SizedBox(height: 16),
          ],
          // 4. 趋势分析
          _buildTrendCard(colorScheme),
          const SizedBox(height: 16),
          // 5. 识别模式效果
          if (_strategyData.isNotEmpty) ...[
            _buildStrategyCard(colorScheme),
            const SizedBox(height: 16),
          ],
          // 6. 全部字符明细
          _buildFullCharList(colorScheme),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 1. 总览卡片
  // ═══════════════════════════════════════════
  Widget _buildOverviewCard(ColorScheme colorScheme) {
    final total = _stats['total'] ?? 0;
    final avgConf = _stats['avgConfidence'] ?? 0.0;
    final correctionRate = _stats['correctionRate'] ?? 0.0;
    final uniqueChars = _charDiagnostics.length;

    return _sectionCard(
      title: '📊 总览',
      colorScheme: colorScheme,
      children: [
        Row(
          children: [
            _statTile('总识别', '$total', '次', Colors.blue, colorScheme),
            _statTile('不同字符', '$uniqueChars', '个', Colors.green, colorScheme),
            _statTile('平均置信度', '${(avgConf * 100).toStringAsFixed(1)}', '%',
                Colors.orange, colorScheme),
            _statTile('纠正率', '${(correctionRate * 100).toStringAsFixed(1)}', '%',
                Colors.red, colorScheme),
          ],
        ),
      ],
    );
  }

  Widget _statTile(String label, String value, String unit,
      Color color, ColorScheme colorScheme) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(unit,
                style: TextStyle(
                    fontSize: 11, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 2. 置信度分布直方图
  // ═══════════════════════════════════════════
  Widget _buildHistogramCard(ColorScheme colorScheme) {
    final buckets = _histogramData['entries'] ?? [];
    if (buckets.isEmpty) return const SizedBox.shrink();
    final maxCount = buckets.map((b) => b.count).reduce(max);
    if (maxCount == 0) return const SizedBox.shrink();

    return _sectionCard(
      title: '📈 置信度分布',
      subtitle: '按识别记录统计',
      colorScheme: colorScheme,
      children: [
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: buckets.map((bucket) {
              final ratio = maxCount > 0 ? bucket.count / maxCount : 0.0;
              final barColor = bucket.min < 0.5
                  ? Colors.red
                  : bucket.min < 0.7
                      ? Colors.orange
                      : Colors.green;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (bucket.count > 0)
                        Text('${bucket.count}',
                            style: TextStyle(
                                fontSize: 9,
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Container(
                        height: ratio * 100,
                        decoration: BoxDecoration(
                          color: barColor.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(bucket.label,
                          style: TextStyle(
                              fontSize: 7,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6)),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // 3. 薄弱字符
  // ═══════════════════════════════════════════
  Widget _buildWeakCharsCard(ColorScheme colorScheme) {
    return _sectionCard(
      title: '⚠️ 薄弱字符',
      subtitle: '置信度低或纠正率高的字符，建议重点练习',
      colorScheme: colorScheme,
      children: _weakChars.take(10).map((d) {
        final confColor = d.avgConfidence >= 0.8
            ? Colors.green
            : d.avgConfidence >= 0.6
                ? Colors.orange
                : Colors.red;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              // 字符
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: confColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(d.character,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: confColor)),
                ),
              ),
              const SizedBox(width: 10),
              // 详情
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('置信度 ${(d.avgConfidence * 100).toInt()}%',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface)),
                        const SizedBox(width: 8),
                        _trendBadge(d.trend),
                      ],
                    ),
                    Text(
                      '识别${d.count}次 · 纠正${d.correctionCount}次 · '
                      '范围 ${d.minConfidence.toStringAsFixed(2)}-${d.maxConfidence.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              // 建议
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: WFColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_getSuggestion(d),
                    style: const TextStyle(fontSize: 10, color: WFColors.info)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 根据诊断数据给出建议
  String _getSuggestion(_CharDiagnostic d) {
    if (d.avgConfidence < 0.4) return '笔画需更清晰';
    if (d.avgConfidence < 0.6) return '字形需更规范';
    if (d.correctionRate > 0.3) return '常被误识别';
    if (d.avgConfidence < 0.75) return '注意笔画间距';
    return '继续练习';
  }

  // ═══════════════════════════════════════════
  // 4. 趋势分析
  // ═══════════════════════════════════════════
  Widget _buildTrendCard(ColorScheme colorScheme) {
    final improving = _charDiagnostics.where((d) => d.trend == 'improving').length;
    final declining = _charDiagnostics.where((d) => d.trend == 'declining').length;
    final stable = _charDiagnostics.where((d) => d.trend == 'stable').length;
    final insufficient = _charDiagnostics.where((d) => d.trend == 'insufficient').length;

    return _sectionCard(
      title: '📉 趋势分析',
      subtitle: '每个字符近期 vs 早期的置信度变化',
      colorScheme: colorScheme,
      children: [
        Row(
          children: [
            _trendTile('提升中', improving, Colors.green, Icons.trending_up),
            _trendTile('稳定', stable, Colors.blue, Icons.trending_flat),
            _trendTile('下降中', declining, Colors.red, Icons.trending_down),
            _trendTile('数据不足', insufficient, Colors.grey, Icons.help_outline),
          ],
        ),
        if (improving > 0) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _charDiagnostics
                .where((d) => d.trend == 'improving')
                .take(10)
                .map((d) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${d.character} ↑',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.green)),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _trendTile(String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 5. 识别模式效果
  // ═══════════════════════════════════════════
  Widget _buildStrategyCard(ColorScheme colorScheme) {
    return _sectionCard(
      title: '🔧 识别模式效果',
      subtitle: '本地 vs 云端识别的表现对比',
      colorScheme: colorScheme,
      children: _strategyData.map((s) {
        final avgConf = s.count > 0 ? s.totalConfidence / s.count : 0.0;
        final corrRate = s.count > 0 ? s.correctionCount / s.count : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(s.name.contains('云端') ? Icons.cloud : Icons.phone_android,
                      size: 18,
                      color: s.name.contains('云端') ? Colors.blue : Colors.green),
                  const SizedBox(width: 6),
                  Text(s.name,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface)),
                  const Spacer(),
                  Text('${s.count} 次',
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 6),
              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: avgConf,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                      avgConf >= 0.8 ? Colors.green : avgConf >= 0.6 ? Colors.orange : Colors.red),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('平均置信度: ${(avgConf * 100).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  Text('纠正率: ${(corrRate * 100).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════
  // 6. 全部字符明细
  // ═══════════════════════════════════════════
  Widget _buildFullCharList(ColorScheme colorScheme) {
    return _sectionCard(
      title: '📋 全部字符明细',
      subtitle: '共 ${_charDiagnostics.length} 个不同字符',
      colorScheme: colorScheme,
      children: [
        // 表头
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(width: 36, child: Text('字', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant))),
              SizedBox(width: 50, child: Text('次数', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant))),
              Expanded(child: Text('置信度', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant))),
              SizedBox(width: 44, child: Text('趋势', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant))),
            ],
          ),
        ),
        Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ..._charDiagnostics.take(30).map((d) {
          final confColor = d.avgConfidence >= 0.8
              ? Colors.green
              : d.avgConfidence >= 0.6
                  ? Colors.orange
                  : Colors.red;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(d.character,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                ),
                SizedBox(
                  width: 50,
                  child: Text('${d.count}',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: d.avgConfidence,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(confColor),
                      minHeight: 5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text('${(d.avgConfidence * 100).toInt()}%',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: confColor)),
                ),
              ],
            ),
          );
        }),
        if (_charDiagnostics.length > 30)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('… 仅显示前 30 个字符',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5))),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // 通用组件
  // ═══════════════════════════════════════════

  Widget _sectionCard({
    required String title,
    String? subtitle,
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
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _trendBadge(String trend) {
    Color color;
    String text;
    IconData icon;
    switch (trend) {
      case 'improving':
        color = Colors.green;
        text = '↑';
        icon = Icons.trending_up;
        break;
      case 'declining':
        color = Colors.red;
        text = '↓';
        icon = Icons.trending_down;
        break;
      case 'insufficient':
        color = Colors.grey;
        text = '—';
        icon = Icons.remove;
        break;
      default:
        color = Colors.blue;
        text = '→';
        icon = Icons.trending_flat;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 1),
          Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// 数据模型
// ═══════════════════════════════════════════

class _CharDiagnostic {
  final String character;
  final int count;
  final double avgConfidence;
  final double minConfidence;
  final double maxConfidence;
  final int correctionCount;
  final double correctionRate;
  final String trend; // improving / declining / stable / insufficient
  final double recentConfidence;

  const _CharDiagnostic({
    required this.character,
    required this.count,
    required this.avgConfidence,
    required this.minConfidence,
    required this.maxConfidence,
    required this.correctionCount,
    required this.correctionRate,
    required this.trend,
    required this.recentConfidence,
  });
}

class _ConfidenceBucket {
  final String label;
  final double min;
  final double max;
  int count;

  _ConfidenceBucket({
    required this.label,
    required this.min,
    required this.max,
    required this.count,
  });
}

class _StrategyEffectiveness {
  final String name;
  int count;
  double totalConfidence;
  int correctionCount;

  _StrategyEffectiveness({
    required this.name,
    required this.count,
    required this.totalConfidence,
    required this.correctionCount,
  });
}
