import 'dart:math';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../data/standard_charset.dart';
import '../theme/app_theme.dart';

/// 字体质量分析页面
///
/// 分析每个字符的轮廓完整性、笔画清晰度，给出质量评分（0-100），
/// 并用颜色标记质量等级（绿=好，黄=一般，红=差）。
class FontQualityScreen extends StatefulWidget {
  final FontProject project;

  const FontQualityScreen({super.key, required this.project});

  @override
  State<FontQualityScreen> createState() => _FontQualityScreenState();
}

class _FontQualityScreenState extends State<FontQualityScreen> {
  Map<String, _CharQuality> _qualities = {};
  bool _isLoading = true;
  _SortMode _sortMode = _SortMode.scoreAsc;

  @override
  void initState() {
    super.initState();
    _analyzeAll();
  }

  /// 分析所有字符质量
  void _analyzeAll() {
    setState(() => _isLoading = true);
    final allChars = _getAllCharacters();
    final qualities = <String, _CharQuality>{};
    for (final char in allChars) {
      final glyph = widget.project.glyphs[char];
      qualities[char] = _analyzeChar(char, glyph);
    }
    setState(() {
      _qualities = qualities;
      _isLoading = false;
    });
  }

  /// 获取所有字符
  List<String> _getAllCharacters() {
    final standardChars = StandardCharset.allCharStrings;
    final userChars = widget.project.glyphs.keys
        .where((c) => !standardChars.contains(c))
        .toList();
    return [...standardChars, ...userChars];
  }

  /// 分析单个字符质量
  _CharQuality _analyzeChar(String char, GlyphData? glyph) {
    if (glyph == null || glyph.contours.isEmpty) {
      return _CharQuality(
        character: char,
        score: 0,
        completeness: 0,
        clarity: 0,
        balance: 0,
        status: _QualityStatus.empty,
        totalPoints: 0,
        onCurvePoints: 0,
        contourCount: 0,
      );
    }

    // 统计点信息
    int totalPoints = 0;
    int onCurvePoints = 0;
    int minX = 99999, minY = 99999, maxX = -99999, maxY = -99999;
    double sumX = 0, sumY = 0;

    for (final contour in glyph.contours) {
      for (final p in contour.points) {
        totalPoints++;
        if (p.onCurve) onCurvePoints++;
        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.x > maxX) maxX = p.x;
        if (p.y > maxY) maxY = p.y;
        sumX += p.x;
        sumY += p.y;
      }
    }

    if (totalPoints == 0) {
      return _CharQuality(
        character: char,
        score: 0,
        completeness: 0,
        clarity: 0,
        balance: 0,
        status: _QualityStatus.empty,
        totalPoints: 0,
        onCurvePoints: 0,
        contourCount: glyph.contours.length,
      );
    }

    // ── 1. 完整性评分 (0-100) ──
    // 基于：轮廓数、点数、on-curve比例
    double completeness = 0;

    // 有轮廓就给基础分
    if (glyph.contours.isNotEmpty) completeness += 30;

    // 点数越多越完整（至少需要一定数量才能构成字形）
    if (totalPoints >= 20) {
      completeness += 30;
    } else if (totalPoints >= 10) {
      completeness += 20;
    } else if (totalPoints >= 5) {
      completeness += 10;
    }

    // on-curve 点比例合理（太低说明控制点多但锚点少）
    final onCurveRatio = onCurvePoints / totalPoints;
    if (onCurveRatio >= 0.3 && onCurveRatio <= 0.8) {
      completeness += 25;
    } else if (onCurveRatio >= 0.2) {
      completeness += 15;
    } else {
      completeness += 5;
    }

    // 多个轮廓通常意味着更完整的字形（如"口"需要外框+可能的内部结构）
    if (glyph.contours.length >= 2) {
      completeness += 15;
    } else {
      completeness += 10;
    }

    completeness = completeness.clamp(0, 100);

    // ── 2. 清晰度评分 (0-100) ──
    // 基于：轮廓点密度（点数/面积）是否合理
    final width = (maxX - minX).toDouble();
    final height = (maxY - minY).toDouble();
    final area = width * height;

    double clarity = 0;
    if (area > 0) {
      // 点密度 = 点数 / 面积(万单位²)
      final density = totalPoints / (area / 10000);
      // 合理密度范围：0.5 - 5 点/万单位²
      if (density >= 0.5 && density <= 5.0) {
        clarity = 100;
      } else if (density >= 0.2 && density <= 10.0) {
        clarity = 70;
      } else if (density > 0) {
        clarity = 40;
      }
    } else {
      // 所有点重叠，清晰度低
      clarity = 10;
    }

    // ── 3. 均衡性评分 (0-100) ──
    // 基于：质心是否接近几何中心
    double balance = 50; // 默认中等
    final avgX = sumX / totalPoints;
    final avgY = sumY / totalPoints;
    final centerX = (minX + maxX) / 2.0;
    final centerY = (minY + maxY) / 2.0;

    if (width > 0 && height > 0) {
      final offsetX = (avgX - centerX).abs() / width;
      final offsetY = (avgY - centerY).abs() / height;
      // 偏移越小越好
      final offset = sqrt(offsetX * offsetX + offsetY * offsetY);
      if (offset < 0.15) {
        balance = 100;
      } else if (offset < 0.3) {
        balance = 80;
      } else if (offset < 0.5) {
        balance = 60;
      } else {
        balance = 40;
      }
    }

    // ── 综合评分 ──
    final score =
        (completeness * 0.4 + clarity * 0.35 + balance * 0.25).round();

    // 质量等级
    _QualityStatus status;
    if (score >= 70) {
      status = _QualityStatus.good;
    } else if (score >= 40) {
      status = _QualityStatus.medium;
    } else {
      status = _QualityStatus.poor;
    }

    return _CharQuality(
      character: char,
      score: score,
      completeness: completeness.round(),
      clarity: clarity.round(),
      balance: balance.round(),
      status: status,
      totalPoints: totalPoints,
      onCurvePoints: onCurvePoints,
      contourCount: glyph.contours.length,
    );
  }

  /// 获取排序后的字符列表
  List<MapEntry<String, _CharQuality>> _getSortedEntries() {
    final entries = _qualities.entries.toList();
    switch (_sortMode) {
      case _SortMode.scoreAsc:
        entries.sort((a, b) => a.value.score.compareTo(b.value.score));
      case _SortMode.scoreDesc:
        entries.sort((a, b) => b.value.score.compareTo(a.value.score));
      case _SortMode.char:
        // 按字符原始顺序
        break;
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    // 统计各等级数量
    int goodCount = 0, mediumCount = 0, poorCount = 0, emptyCount = 0;
    for (final q in _qualities.values) {
      switch (q.status) {
        case _QualityStatus.good:
          goodCount++;
        case _QualityStatus.medium:
          mediumCount++;
        case _QualityStatus.poor:
          poorCount++;
        case _QualityStatus.empty:
          emptyCount++;
      }
    }
    final totalWithGlyphs = _qualities.length - emptyCount;
    final avgScore = totalWithGlyphs > 0
        ? _qualities.values
                .where((q) => q.status != _QualityStatus.empty)
                .fold<int>(0, (sum, q) => sum + q.score) /
            totalWithGlyphs
        : 0.0;

    return Scaffold(
      appBar: WFAppBar(
        title: '字体质量分析',
        actions: [
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort),
            tooltip: '排序方式',
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _SortMode.scoreAsc,
                child: Text('评分从低到高'),
              ),
              const PopupMenuItem(
                value: _SortMode.scoreDesc,
                child: Text('评分从高到低'),
              ),
              const PopupMenuItem(
                value: _SortMode.char,
                child: Text('按字符顺序'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 顶部总览卡片
                _buildOverviewCard(avgScore, goodCount, mediumCount, poorCount,
                    emptyCount, totalWithGlyphs),
                // 图例
                _buildLegend(),
                // 字符质量列表
                Expanded(child: _buildQualityList()),
              ],
            ),
    );
  }

  /// 顶部总览卡片
  Widget _buildOverviewCard(double avgScore, int good, int medium, int poor,
      int empty, int totalWithGlyphs) {
    return WFCard(
      accentColor: WFColors.primary,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              // 平均分大字
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: avgScore / 100,
                      strokeWidth: 8,
                      backgroundColor: WFColors.textLight.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getScoreColor(avgScore.round()),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${avgScore.round()}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _getScoreColor(avgScore.round()),
                          ),
                        ),
                        Text(
                          '均分',
                          style: TextStyle(
                            fontSize: 10,
                            color: WFColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // 统计
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '质量总览',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '已分析 $totalWithGlyphs / ${_qualities.length} 个字符',
                      style: TextStyle(
                        fontSize: 13,
                        color: WFColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 彩色条
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 12,
                        child: totalWithGlyphs > 0
                            ? Row(
                                children: [
                                  if (good > 0)
                                    Expanded(
                                      flex: good,
                                      child: Container(color: WFColors.success),
                                    ),
                                  if (medium > 0)
                                    Expanded(
                                      flex: medium,
                                      child: Container(color: WFColors.warning),
                                    ),
                                  if (poor > 0)
                                    Expanded(
                                      flex: poor,
                                      child: Container(color: WFColors.error),
                                    ),
                                  if (empty > 0)
                                    Expanded(
                                      flex: empty,
                                      child: Container(
                                        color: WFColors.textLight
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                ],
                              )
                            : Container(
                                color: WFColors.textLight.withValues(alpha: 0.3),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 图例行
  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildLegendChip(WFColors.success, '好 (≥70)'),
          const SizedBox(width: 12),
          _buildLegendChip(WFColors.warning, '一般 (40-69)'),
          const SizedBox(width: 12),
          _buildLegendChip(WFColors.error, '差 (<40)'),
        ],
      ),
    );
  }

  Widget _buildLegendChip(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: WFColors.textSecondary),
        ),
      ],
    );
  }

  /// 质量列表
  Widget _buildQualityList() {
    final entries = _getSortedEntries();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _buildQualityItem(entry.key, entry.value);
      },
    );
  }

  /// 单个字符质量项
  Widget _buildQualityItem(String char, _CharQuality quality) {
    final scoreColor = _getScoreColor(quality.score);
    final statusColor = _getStatusColor(quality.status);

    return WFCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 字符 + 状态色块
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: quality.status == _QualityStatus.empty
                ? Icon(Icons.hourglass_empty, size: 20, color: WFColors.textLight)
                : Text(
                    char,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: WFColors.textPrimary,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          // 详细信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 分项得分
                Row(
                  children: [
                    _buildScoreTag('完整', quality.completeness),
                    const SizedBox(width: 6),
                    _buildScoreTag('清晰', quality.clarity),
                    const SizedBox(width: 6),
                    _buildScoreTag('均衡', quality.balance),
                  ],
                ),
                const SizedBox(height: 4),
                // 技术细节
                Text(
                  quality.status == _QualityStatus.empty
                      ? '未书写'
                      : '${quality.contourCount} 轮廓 · '
                          '${quality.totalPoints} 点 · '
                          '${quality.onCurvePoints} 锚点',
                  style: TextStyle(
                    fontSize: 11,
                    color: WFColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // 综合评分
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scoreColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: scoreColor.withValues(alpha: 0.5), width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              quality.status == _QualityStatus.empty ? '-' : '${quality.score}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: scoreColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分项得分小标签
  Widget _buildScoreTag(String label, int score) {
    final color = _getScoreColor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label $score',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  /// 根据分数获取颜色
  Color _getScoreColor(int score) {
    if (score >= 70) return WFColors.success;
    if (score >= 40) return WFColors.warning;
    return WFColors.error;
  }

  /// 根据状态获取颜色
  Color _getStatusColor(_QualityStatus status) {
    switch (status) {
      case _QualityStatus.good:
        return WFColors.success;
      case _QualityStatus.medium:
        return WFColors.warning;
      case _QualityStatus.poor:
        return WFColors.error;
      case _QualityStatus.empty:
        return WFColors.textLight;
    }
  }
}

/// 质量等级
enum _QualityStatus { good, medium, poor, empty }

/// 排序模式
enum _SortMode { scoreAsc, scoreDesc, char }

/// 单个字符的质量分析结果
class _CharQuality {
  final String character;
  final int score; // 综合评分 0-100
  final int completeness; // 完整性 0-100
  final int clarity; // 清晰度 0-100
  final int balance; // 均衡性 0-100
  final _QualityStatus status;
  final int totalPoints;
  final int onCurvePoints;
  final int contourCount;

  const _CharQuality({
    required this.character,
    required this.score,
    required this.completeness,
    required this.clarity,
    required this.balance,
    required this.status,
    required this.totalPoints,
    required this.onCurvePoints,
    required this.contourCount,
  });
}
