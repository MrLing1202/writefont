import 'dart:math';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';
import 'character_edit_screen.dart';

/// 字形质量评分页面
///
/// 对所有已编辑字形进行四维质量评分（0-100分）：
/// - 笔画平滑度：轮廓点间距方差（越均匀越好）
/// - 闭合度：首尾点距离（越近越好）
/// - 复杂度：轮廓点数适中（20-80点最佳）
/// - 对称性：左右半边轮廓点分布对比
///
/// 支持项目选择、排序、点击跳转编辑、整体质量报告。
class GlyphQualityScreen extends StatefulWidget {
  /// 可选传入项目，若为空则显示项目选择器
  final FontProject? project;

  /// 所有可用项目列表（用于项目选择器）
  final List<FontProject>? projects;

  const GlyphQualityScreen({super.key, this.project, this.projects});

  @override
  State<GlyphQualityScreen> createState() => _GlyphQualityScreenState();
}

class _GlyphQualityScreenState extends State<GlyphQualityScreen> {
  /// 当前选中的项目
  FontProject? _currentProject;

  /// 所有可用项目
  late List<FontProject> _availableProjects;

  /// 各字形评分结果，key 为字符
  Map<String, _GlyphScore> _scores = {};

  /// 是否正在计算
  bool _isLoading = true;

  /// 排序模式
  _SortMode _sortMode = _SortMode.scoreAsc;

  @override
  void initState() {
    super.initState();
    _availableProjects = widget.projects ?? [];
    _currentProject = widget.project;

    // 如果没有传入项目但有项目列表，默认选第一个
    if (_currentProject == null && _availableProjects.isNotEmpty) {
      _currentProject = _availableProjects.first;
    }

    if (_currentProject != null) {
      _analyzeAll();
    } else {
      _isLoading = false;
    }
  }

  /// 切换项目
  void _onProjectChanged(FontProject? project) {
    if (project == null || project == _currentProject) return;
    setState(() {
      _currentProject = project;
      _isLoading = true;
    });
    _analyzeAll();
  }

  /// 对所有已编辑字形进行质量评分
  void _analyzeAll() {
    setState(() => _isLoading = true);

    final project = _currentProject;
    if (project == null) {
      setState(() {
        _scores = {};
        _isLoading = false;
      });
      return;
    }

    final scores = <String, _GlyphScore>{};
    for (final entry in project.glyphs.entries) {
      final glyph = entry.value;
      // 只分析有轮廓数据的字形
      if (glyph.contours.isNotEmpty) {
        scores[entry.key] = _scoreGlyph(glyph);
      }
    }

    setState(() {
      _scores = scores;
      _isLoading = false;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 四维评分算法
  // ═══════════════════════════════════════════════════════════

  /// 对单个字形进行四维评分
  _GlyphScore _scoreGlyph(GlyphData glyph) {
    // 收集所有轮廓点
    final allPoints = <ContourPoint>[];
    for (final contour in glyph.contours) {
      allPoints.addAll(contour.points);
    }

    if (allPoints.isEmpty) {
      return const _GlyphScore(
        character: '',
        total: 0,
        smoothness: 0,
        closure: 0,
        complexity: 0,
        symmetry: 0,
      );
    }

    final smoothness = _calcSmoothness(glyph.contours);
    final closure = _calcClosure(glyph.contours);
    final complexity = _calcComplexity(allPoints);
    final symmetry = _calcSymmetry(allPoints);

    // 综合评分：四项加权平均
    // 平滑度权重最高（对字形质量影响最大）
    final total = (smoothness * 0.35 +
            closure * 0.20 +
            complexity * 0.20 +
            symmetry * 0.25)
        .round()
        .clamp(0, 100);

    return _GlyphScore(
      character: glyph.character,
      total: total,
      smoothness: smoothness.round(),
      closure: closure.round(),
      complexity: complexity.round(),
      symmetry: symmetry.round(),
    );
  }

  /// 笔画平滑度评分（0-100）
  ///
  /// 计算方式：相邻轮廓点之间的距离方差。
  /// 方差越小 → 间距越均匀 → 笔画越平滑。
  double _calcSmoothness(List<Contour> contours) {
    double totalScore = 0;
    int contourCount = 0;

    for (final contour in contours) {
      final pts = contour.points;
      if (pts.length < 3) continue;

      // 计算相邻点之间的距离
      final distances = <double>[];
      for (int i = 0; i < pts.length; i++) {
        final next = pts[(i + 1) % pts.length];
        final dx = (next.x - pts[i].x).toDouble();
        final dy = (next.y - pts[i].y).toDouble();
        distances.add(sqrt(dx * dx + dy * dy));
      }

      // 计算距离均值
      final mean = distances.reduce((a, b) => a + b) / distances.length;
      if (mean == 0) continue;

      // 计算方差（归一化）
      final variance = distances
              .map((d) => (d - mean) * (d - mean))
              .reduce((a, b) => a + b) /
          distances.length;
      final normalizedVariance = variance / (mean * mean);

      // 方差越小分数越高，使用指数衰减映射到 0-100
      // normalizedVariance 在 0（完全均匀）到很大（极不均匀）之间
      final score = 100 * exp(-normalizedVariance * 0.5);
      totalScore += score;
      contourCount++;
    }

    return contourCount > 0 ? totalScore / contourCount : 0;
  }

  /// 闭合度评分（0-100）
  ///
  /// 计算方式：每个轮廓首尾点的距离。
  /// 距离越近 → 闭合越好 → 分数越高。
  double _calcClosure(List<Contour> contours) {
    double totalScore = 0;
    int contourCount = 0;

    for (final contour in contours) {
      final pts = contour.points;
      if (pts.length < 2) continue;

      final first = pts.first;
      final last = pts.last;
      final dx = (last.x - first.x).toDouble();
      final dy = (last.y - first.y).toDouble();
      final distance = sqrt(dx * dx + dy * dy);

      // 计算轮廓的整体尺度（用于归一化）
      int minX = 99999, minY = 99999, maxX = -99999, maxY = -99999;
      for (final p in pts) {
        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.x > maxX) maxX = p.x;
        if (p.y > maxY) maxY = p.y;
      }
      final scale = sqrt(
          (maxX - minX).toDouble() * (maxX - minX).toDouble() +
              (maxY - minY).toDouble() * (maxY - minY).toDouble());

      if (scale == 0) {
        // 所有点重叠，视为完全闭合
        totalScore += 100;
      } else {
        // 距离占尺度的比例越小越好
        final ratio = distance / scale;
        // ratio=0 → 100分, ratio=0.1 → ~60分, ratio>=0.5 → ~0分
        final score = 100 * exp(-ratio * 8);
        totalScore += score;
      }
      contourCount++;
    }

    return contourCount > 0 ? totalScore / contourCount : 0;
  }

  /// 复杂度评分（0-100）
  ///
  /// 计算方式：总轮廓点数是否在最佳范围（20-80点）。
  /// 太少 → 简陋；太多 → 杂乱。
  double _calcComplexity(List<ContourPoint> allPoints) {
    final count = allPoints.length;

    // 最佳范围：20-80 点
    if (count >= 20 && count <= 80) {
      // 在最佳范围内，越接近中间（50）越好
      final center = 50.0;
      final dist = (count - center).abs() / 30.0; // 0 到 1
      return 100 - dist * 15; // 85-100 分
    } else if (count < 20) {
      // 太少：线性递减
      return (count / 20.0 * 70).clamp(0, 70);
    } else {
      // 太多：缓慢递减（80点=85分，120点=60分，200点=30分）
      final excess = count - 80;
      return (85 - excess * 0.5).clamp(0, 85);
    }
  }

  /// 对称性评分（0-100）
  ///
  /// 计算方式：以轮廓水平中心为轴，比较左右半边的轮廓点分布。
  /// 分布越对称 → 分数越高。
  double _calcSymmetry(List<ContourPoint> allPoints) {
    if (allPoints.length < 4) return 50; // 点太少无法判断

    // 计算水平中心
    int minX = 99999, maxX = -99999;
    for (final p in allPoints) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
    }
    final centerX = (minX + maxX) / 2.0;
    final width = (maxX - minX).toDouble();
    if (width == 0) return 50;

    // 将点按 x 坐标分到左右两半，统计分布
    // 使用分桶法：将垂直方向分为 10 个桶，比较左右每桶的点数
    int minY = 99999, maxY = -99999;
    for (final p in allPoints) {
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    final height = (maxY - minY).toDouble();
    if (height == 0) return 50;

    const bucketCount = 10;
    final leftBuckets = List.filled(bucketCount, 0);
    final rightBuckets = List.filled(bucketCount, 0);

    for (final p in allPoints) {
      final bucketIndex =
          ((p.y - minY) / height * (bucketCount - 1)).floor().clamp(0, bucketCount - 1);
      if (p.x < centerX) {
        leftBuckets[bucketIndex]++;
      } else if (p.x > centerX) {
        rightBuckets[bucketIndex]++;
      }
      // 恰好在中心线上的点忽略
    }

    // 计算左右分布的差异
    double totalDiff = 0;
    double totalSum = 0;
    for (int i = 0; i < bucketCount; i++) {
      totalDiff += (leftBuckets[i] - rightBuckets[i]).abs().toDouble();
      totalSum += (leftBuckets[i] + rightBuckets[i]).toDouble();
    }

    if (totalSum == 0) return 50;

    // 差异比例越小越对称
    final asymmetry = totalDiff / totalSum; // 0（完全对称）到 1（完全不对称）
    return (100 * (1 - asymmetry)).clamp(0, 100);
  }

  // ═══════════════════════════════════════════════════════════
  // 排序 & 数据
  // ═══════════════════════════════════════════════════════════

  /// 获取排序后的字形评分列表
  List<MapEntry<String, _GlyphScore>> _getSortedEntries() {
    final entries = _scores.entries.toList();
    switch (_sortMode) {
      case _SortMode.scoreAsc:
        entries.sort((a, b) => a.value.total.compareTo(b.value.total));
      case _SortMode.scoreDesc:
        entries.sort((a, b) => b.value.total.compareTo(a.value.total));
      case _SortMode.smoothness:
        entries.sort(
            (a, b) => a.value.smoothness.compareTo(b.value.smoothness));
      case _SortMode.closure:
        entries.sort((a, b) => a.value.closure.compareTo(b.value.closure));
      case _SortMode.complexity:
        entries.sort(
            (a, b) => a.value.complexity.compareTo(b.value.complexity));
      case _SortMode.symmetry:
        entries.sort(
            (a, b) => a.value.symmetry.compareTo(b.value.symmetry));
    }
    return entries;
  }

  /// 计算整体统计数据
  _OverallStats _calcOverallStats() {
    if (_scores.isEmpty) {
      return const _OverallStats(
        avgScore: 0,
        minScore: 0,
        maxScore: 0,
        needImprovement: [],
        totalCount: 0,
      );
    }

    final scores = _scores.values.map((s) => s.total).toList();
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    final min = scores.reduce(min);
    final max = scores.reduce(max);

    // 找出需要改进的字符（低于平均分 - 15）
    final threshold = avg - 15;
    final needImprovement = _scores.entries
        .where((e) => e.value.total < threshold && e.value.total < 60)
        .toList()
      ..sort((a, b) => a.value.total.compareTo(b.value.total));

    return _OverallStats(
      avgScore: avg,
      minScore: min,
      maxScore: max,
      needImprovement: needImprovement.map((e) => e.key).toList(),
      totalCount: _scores.length,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 跳转编辑
  // ═══════════════════════════════════════════════════════════

  /// 点击字形跳转到编辑页面
  void _navigateToEdit(String char) {
    final glyph = _currentProject?.glyphs[char];
    if (glyph == null || _currentProject == null) return;

    // 使用 CharacterEditDialog 进行编辑
    CharacterEditDialog.show(
      context,
      character: char,
      glyph: glyph,
      projectId: _currentProject!.id,
      onCharacterChanged: () {
        // 编辑完成后重新分析
        _analyzeAll();
      },
      onCharacterDeleted: () {
        // 删除后重新分析
        _analyzeAll();
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // UI 构建
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WFAppBar(
        title: '字形质量评分',
        actions: [
          // 排序菜单
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort),
            tooltip: '排序方式',
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _SortMode.scoreAsc,
                child: Text('总分 从低到高'),
              ),
              const PopupMenuItem(
                value: _SortMode.scoreDesc,
                child: Text('总分 从高到低'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _SortMode.smoothness,
                child: Text('按平滑度排序'),
              ),
              const PopupMenuItem(
                value: _SortMode.closure,
                child: Text('按闭合度排序'),
              ),
              const PopupMenuItem(
                value: _SortMode.complexity,
                child: Text('按复杂度排序'),
              ),
              const PopupMenuItem(
                value: _SortMode.symmetry,
                child: Text('按对称性排序'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 项目选择器
          if (_availableProjects.length > 1) _buildProjectSelector(),
          // 主内容
          Expanded(
            child: _currentProject == null
                ? _buildEmptyState()
                : _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _scores.isEmpty
                        ? _buildNoGlyphsState()
                        : _buildContent(),
          ),
        ],
      ),
    );
  }

  /// 项目选择器
  Widget _buildProjectSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: WFColors.bgCardColor(context),
        border: Border(
          bottom: BorderSide(
            color: WFColors.textLightColor(context).withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open,
              size: 20, color: WFColors.textSecondaryColor(context)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<FontProject>(
                value: _currentProject,
                isExpanded: true,
                style: TextStyle(
                  color: WFColors.textPrimaryColor(context),
                  fontSize: 14,
                ),
                items: _availableProjects.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: _onProjectChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 无项目空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.font_download_off,
              size: 64, color: WFColors.textLightColor(context)),
          const SizedBox(height: 16),
          Text(
            '请先创建或选择一个项目',
            style: TextStyle(
              fontSize: 16,
              color: WFColors.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 无已编辑字形的状态
  Widget _buildNoGlyphsState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.brush,
              size: 64, color: WFColors.textLightColor(context)),
          const SizedBox(height: 16),
          Text(
            '该项目暂无已编辑的字形',
            style: TextStyle(
              fontSize: 16,
              color: WFColors.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请先书写或导入字形后再进行质量评分',
            style: TextStyle(
              fontSize: 13,
              color: WFColors.textLightColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 主内容区域
  Widget _buildContent() {
    final stats = _calcOverallStats();

    return Column(
      children: [
        // 整体质量报告
        _buildOverallReport(stats),
        // 维度图例
        _buildDimensionLegend(),
        // 字形评分列表
        Expanded(child: _buildGlyphList()),
      ],
    );
  }

  /// 整体质量报告卡片
  Widget _buildOverallReport(_OverallStats stats) {
    return WFCard(
      accentColor: WFColors.primary,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Icon(Icons.analytics, size: 20, color: WFColors.primary),
              const SizedBox(width: 8),
              Text(
                '质量报告',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
              const Spacer(),
              Text(
                '共 ${stats.totalCount} 个字形',
                style: TextStyle(
                  fontSize: 12,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 三项统计
          Row(
            children: [
              _buildStatItem('平均分', stats.avgScore.round(),
                  _getScoreColor(stats.avgScore.round())),
              const SizedBox(width: 16),
              _buildStatItem('最低分', stats.minScore,
                  _getScoreColor(stats.minScore)),
              const SizedBox(width: 16),
              _buildStatItem('最高分', stats.maxScore,
                  _getScoreColor(stats.maxScore)),
            ],
          ),
          // 建议改进
          if (stats.needImprovement.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: WFColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: WFColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 16, color: WFColors.warning),
                      const SizedBox(width: 6),
                      Text(
                        '建议优先改进',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: WFColors.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: stats.needImprovement.take(20).map((char) {
                      final score = _scores[char]?.total ?? 0;
                      return GestureDetector(
                        onTap: () => _navigateToEdit(char),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getScoreColor(score).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color:
                                  _getScoreColor(score).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            '$char ($score)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _getScoreColor(score),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 单项统计数据
  Widget _buildStatItem(String label, int score, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$score',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: WFColors.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 维度图例
  Widget _buildDimensionLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildLegendDot(WFColors.primary, '平滑'),
          const SizedBox(width: 12),
          _buildLegendDot(WFColors.success, '闭合'),
          const SizedBox(width: 12),
          _buildLegendDot(WFColors.warning, '复杂'),
          const SizedBox(width: 12),
          _buildLegendDot(const Color(0xFF9B59B6), '对称'),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: WFColors.textSecondaryColor(context),
          ),
        ),
      ],
    );
  }

  /// 字形评分列表
  Widget _buildGlyphList() {
    final entries = _getSortedEntries();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _buildGlyphCard(entry.key, entry.value);
      },
    );
  }

  /// 单个字形评分卡片
  Widget _buildGlyphCard(String char, _GlyphScore score) {
    final scoreColor = _getScoreColor(score.total);

    return GestureDetector(
      onTap: () => _navigateToEdit(char),
      child: WFCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 字符显示
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: scoreColor.withValues(alpha: 0.4),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                char,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // 四维分数 + 颜色条
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDimensionRow('平滑', score.smoothness, WFColors.primary),
                  const SizedBox(height: 4),
                  _buildDimensionRow('闭合', score.closure, WFColors.success),
                  const SizedBox(height: 4),
                  _buildDimensionRow('复杂', score.complexity, WFColors.warning),
                  const SizedBox(height: 4),
                  _buildDimensionRow(
                      '对称', score.symmetry, const Color(0xFF9B59B6)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // 总分圆圈
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: scoreColor.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${score.total}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scoreColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单个维度分数行（标签 + 颜色条 + 分数）
  Widget _buildDimensionRow(String label, int value, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: WFColors.textSecondaryColor(context),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 8,
              child: LinearProgressIndicator(
                value: value / 100,
                backgroundColor:
                    WFColors.textLightColor(context).withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 24,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  /// 根据分数获取颜色
  Color _getScoreColor(int score) {
    if (score >= 70) return WFColors.success;
    if (score >= 40) return WFColors.warning;
    return WFColors.error;
  }
}

// ═══════════════════════════════════════════════════════════
// 内部数据模型
// ═══════════════════════════════════════════════════════════

/// 排序模式
enum _SortMode {
  scoreAsc, // 总分从低到高
  scoreDesc, // 总分从高到低
  smoothness, // 按平滑度
  closure, // 按闭合度
  complexity, // 按复杂度
  symmetry, // 按对称性
}

/// 单个字形的四维评分结果
class _GlyphScore {
  final String character;
  final int total; // 综合总分 0-100
  final int smoothness; // 笔画平滑度 0-100
  final int closure; // 闭合度 0-100
  final int complexity; // 复杂度 0-100
  final int symmetry; // 对称性 0-100

  const _GlyphScore({
    required this.character,
    required this.total,
    required this.smoothness,
    required this.closure,
    required this.complexity,
    required this.symmetry,
  });
}

/// 整体统计数据
class _OverallStats {
  final double avgScore;
  final int minScore;
  final int maxScore;
  final List<String> needImprovement;
  final int totalCount;

  const _OverallStats({
    required this.avgScore,
    required this.minScore,
    required this.maxScore,
    required this.needImprovement,
    required this.totalCount,
  });
}

/// 字形编辑对话框（桩，供跳转使用）
/// 实际项目中应导入 character_edit_screen.dart 中的 CharacterEditDialog
class CharacterEditDialog extends StatelessWidget {
  final GlyphData glyph;
  final FontProject project;

  const CharacterEditDialog({
    super.key,
    required this.glyph,
    required this.project,
  });

  @override
  Widget build(BuildContext context) {
    // 此处为桩实现，实际使用时应替换为真实的编辑对话框
    return AlertDialog(
      title: Text('编辑字形: ${glyph.character}'),
      content: Text('字形编辑功能请从字符网格页面进入。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
