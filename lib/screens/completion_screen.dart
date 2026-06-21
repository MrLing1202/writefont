import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/charset_analyzer.dart';
import '../services/glyph_completion.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bezier_glyph_painter.dart';

/// 字形自动补全页面
///
/// 显示缺失字符列表，支持一键自动生成近似字形，
/// 用户可逐个预览并接受/拒绝。
class CompletionScreen extends StatefulWidget {
  final FontProject project;

  const CompletionScreen({super.key, required this.project});

  @override
  State<CompletionScreen> createState() => _CompletionScreenState();
}

class _CompletionScreenState extends State<CompletionScreen> {
  // 分析结果
  CharsetAnalysisResult? _analysis;
  // 生成状态
  bool _isGenerating = false;
  int _completedCount = 0;
  int _totalCount = 0;
  // 生成结果：字符 -> 轮廓
  Map<String, List<Contour>> _generated = {};
  // 接受状态：字符 -> 是否接受
  final Map<String, bool> _accepted = {};
  // 是否已显示结果
  bool _showResults = false;
  // 缺失字符选择（默认全选一级汉字）
  bool _includeLevel1 = true;
  bool _includeLevel2 = false;
  bool _includeSymbols = false;

  @override
  void initState() {
    super.initState();
    _analysis = CharsetAnalyzer.analyze(widget.project);
  }

  /// 获取待生成字符列表
  List<String> _getMissingChars() {
    if (_analysis == null) return [];
    final chars = <String>[];
    if (_includeLevel1) chars.addAll(_analysis!.missingLevel1);
    if (_includeLevel2) chars.addAll(_analysis!.missingLevel2);
    if (_includeSymbols) chars.addAll(_analysis!.missingSymbols);
    return chars;
  }

  /// 开始自动补全
  Future<void> _startGeneration() async {
    final missing = _getMissingChars();
    if (missing.isEmpty) {
      WFSnackBar.show(context, '没有需要补全的字符');
      return;
    }

    setState(() {
      _isGenerating = true;
      _completedCount = 0;
      _totalCount = missing.length;
      _generated.clear();
      _accepted.clear();
      _showResults = false;
    });

    final result = await GlyphCompletionService.generateMissingGlyphs(
      widget.project,
      missing,
      onProgress: (completed, total) {
        if (mounted) {
          setState(() => _completedCount = completed);
        }
      },
    );

    if (!mounted) return;

    setState(() {
      _isGenerating = false;
      _generated = result;
      _showResults = true;
      // 默认全部接受
      for (final char in result.keys) {
        _accepted[char] = true;
      }
    });

    WFSnackBar.show(context, '生成完成: ${result.length} 个字形');
  }

  /// 将接受的字形写入项目
  Future<void> _applyAccepted() async {
    final acceptedChars = _accepted.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (acceptedChars.isEmpty) {
      WFSnackBar.show(context, '没有接受的字形');
      return;
    }

    int added = 0;
    for (final char in acceptedChars) {
      final contours = _generated[char];
      if (contours == null || contours.isEmpty) continue;

      // 计算包围盒
      int minX = 99999, maxX = -99999, minY = 99999, maxY = -99999;
      for (final contour in contours) {
        for (final p in contour.points) {
          if (p.x < minX) minX = p.x;
          if (p.x > maxX) maxX = p.x;
          if (p.y < minY) minY = p.y;
          if (p.y > maxY) maxY = p.y;
        }
      }

      final glyph = GlyphData(
        character: char,
        unicode: char.codeUnitAt(0),
        contours: contours,
        xMin: minX,
        yMin: minY,
        xMax: maxX,
        yMax: maxY,
        confidence: 0.3, // 自动生成的字形置信度标记为较低
      );

      widget.project.glyphs[char] = glyph;
      added++;
    }

    widget.project.updatedAt = DateTime.now();
    await StorageService.saveProject(widget.project);

    if (!mounted) return;
    WFSnackBar.show(context, '已添加 $added 个字形到项目');

    // 返回上一页
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    if (analysis == null) {
      return Scaffold(
        appBar: WFAppBar(title: '字形补全'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: WFAppBar(
        title: '字形自动补全',
        actions: [
          if (_showResults)
            TextButton.icon(
              onPressed: _applyAccepted,
              icon: const Icon(Icons.check),
              label: const Text('应用'),
            ),
        ],
      ),
      body: _showResults
          ? _buildResultView()
          : _buildConfigView(analysis),
    );
  }

  /// 配置视图：选择缺失字符范围 + 开始生成
  Widget _buildConfigView(CharsetAnalysisResult analysis) {
    final missingTotal = _getMissingChars().length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 覆盖率概览
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: WFColors.bgCardColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: WFColors.textLightColor(context).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.analytics_outlined, size: 20, color: WFColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      '字符集覆盖率',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimaryColor(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildCoverageRow('一级汉字', analysis.level1Covered, analysis.level1Total),
                const SizedBox(height: 8),
                _buildCoverageRow('二级汉字', analysis.level2Covered, analysis.level2Total),
                const SizedBox(height: 8),
                _buildCoverageRow('符号', analysis.symbolCovered, analysis.symbolTotal),
                const SizedBox(height: 12),
                _buildCoverageRow('总覆盖率', analysis.coveredChars, analysis.totalChars),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 选择补全范围
          Text(
            '选择补全范围',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: WFColors.textPrimaryColor(context),
            ),
          ),
          const SizedBox(height: 12),

          _buildRangeCheckbox(
            '一级汉字（常用）',
            '${analysis.missingLevel1.length} 个缺失',
            _includeLevel1,
            (v) => setState(() => _includeLevel1 = v ?? false),
          ),
          _buildRangeCheckbox(
            '二级汉字（次常用）',
            '${analysis.missingLevel2.length} 个缺失',
            _includeLevel2,
            (v) => setState(() => _includeLevel2 = v ?? false),
          ),
          _buildRangeCheckbox(
            '符号',
            '${analysis.missingSymbols.length} 个缺失',
            _includeSymbols,
            (v) => setState(() => _includeSymbols = v ?? false),
          ),

          const SizedBox(height: 24),

          // 说明提示
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: WFColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 18, color: WFColors.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '自动补全会根据已有字形的笔画特征，'
                    '使用基础笔画模板（横、竖、撇、捺、点、钩、折）'
                    '组合生成近似轮廓。生成结果可在下一步逐个预览和筛选。',
                    style: TextStyle(
                      fontSize: 13,
                      color: WFColors.textSecondaryColor(context),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // 生成进度或开始按钮
          if (_isGenerating) ...[
            LinearProgressIndicator(
              value: _totalCount > 0 ? _completedCount / _totalCount : 0,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              '正在生成... $_completedCount / $_totalCount',
              style: TextStyle(
                fontSize: 14,
                color: WFColors.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: missingTotal > 0 ? _startGeneration : null,
                icon: const Icon(Icons.auto_fix_high),
                label: Text('自动补全 $missingTotal 个字符'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: WFColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 覆盖率行
  Widget _buildCoverageRow(String label, int covered, int total) {
    final percent = total > 0 ? covered / total : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: WFColors.textSecondaryColor(context),
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 8,
              backgroundColor: WFColors.textLightColor(context).withValues(alpha: 0.2),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: Text(
            '${(percent * 100).toStringAsFixed(1)}% ($covered/$total)',
            style: TextStyle(
              fontSize: 12,
              color: WFColors.textSecondaryColor(context),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  /// 补全范围复选框
  Widget _buildRangeCheckbox(String title, String subtitle, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: WFColors.textSecondaryColor(context))),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }

  /// 结果视图：网格预览 + 接受/拒绝
  Widget _buildResultView() {
    final entries = _generated.entries.toList();
    final acceptedCount = _accepted.values.where((v) => v).length;

    return Column(
      children: [
        // 顶部统计栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: WFColors.bgCardColor(context),
            border: Border(
              bottom: BorderSide(
                color: WFColors.textLightColor(context).withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_fix_high, size: 20, color: WFColors.success),
              const SizedBox(width: 8),
              Text(
                '已生成 ${entries.length} 个字形',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
              const Spacer(),
              Text(
                '已选 $acceptedCount 个',
                style: TextStyle(
                  fontSize: 13,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),

        // 网格
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    '没有生成任何字形',
                    style: TextStyle(color: WFColors.textSecondaryColor(context)),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (ctx, index) {
                    final char = entries[index].key;
                    final contours = entries[index].value;
                    final isAccepted = _accepted[char] ?? false;

                    return _GlyphPreviewCard(
                      character: char,
                      contours: contours,
                      isAccepted: isAccepted,
                      onToggle: () {
                        setState(() {
                          _accepted[char] = !(_accepted[char] ?? false);
                        });
                      },
                    );
                  },
                ),
        ),

        // 底部操作栏
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 全选/全不选
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        final allAccepted = _accepted.values.every((v) => v);
                        for (final key in _accepted.keys) {
                          _accepted[key] = !allAccepted;
                        }
                      });
                    },
                    child: Text(
                      _accepted.values.every((v) => v) ? '全不选' : '全选',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 应用按钮
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: acceptedCount > 0 ? _applyAccepted : null,
                    icon: const Icon(Icons.check),
                    label: Text('应用 $acceptedCount 个字形'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WFColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 字形预览卡片
class _GlyphPreviewCard extends StatelessWidget {
  final String character;
  final List<Contour> contours;
  final bool isAccepted;
  final VoidCallback onToggle;

  const _GlyphPreviewCard({
    required this.character,
    required this.contours,
    required this.isAccepted,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // 构造临时 GlyphData 用于绘制
    final glyph = GlyphData(
      character: character,
      unicode: character.codeUnitAt(0),
      contours: contours,
    );

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        decoration: BoxDecoration(
          color: isAccepted
              ? WFColors.primary.withValues(alpha: 0.08)
              : WFColors.bgCardColor(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isAccepted
                ? WFColors.primary.withValues(alpha: 0.5)
                : WFColors.textLightColor(context).withValues(alpha: 0.3),
            width: isAccepted ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // 字形预览
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: CustomPaint(
                  painter: BezierGlyphPainter(
                    glyph: glyph,
                    fillColor: isAccepted
                        ? WFColors.primary
                        : WFColors.textSecondaryColor(context),
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            // 字符 + 状态
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: WFColors.textLightColor(context).withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    character,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WFColors.textPrimaryColor(context),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isAccepted ? Icons.check_circle : Icons.cancel_outlined,
                    size: 14,
                    color: isAccepted ? WFColors.success : WFColors.textLightColor(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
