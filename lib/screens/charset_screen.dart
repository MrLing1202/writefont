import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/charset_analyzer.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'character_edit_screen.dart';

/// 字符集完整性分析页面
///
/// 分析字体项目对 GB2312 字符集的覆盖率，
/// 展示分类统计和缺失字符列表。
class CharsetScreen extends StatefulWidget {
  final FontProject project;

  const CharsetScreen({super.key, required this.project});

  @override
  State<CharsetScreen> createState() => _CharsetScreenState();
}

class _CharsetScreenState extends State<CharsetScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  CharsetAnalysisResult? _result;
  bool _isAnalyzing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _analyze();
  }

  Future<void> _analyze() async {
    setState(() {
      _isAnalyzing = true;
      _error = null;
    });
    try {
      // 分析在 isolate 中执行太快，直接同步即可
      final result = CharsetAnalyzer.analyze(widget.project);
      if (mounted) {
        setState(() {
          _result = result;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _error = '分析失败: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WFAppBar(
        title: '字符集分析',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导出缺失字符',
            onPressed: _isAnalyzing ? null : _exportMissingList,
          ),
        ],
      ),
      body: _isAnalyzing
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: WFColors.error),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _analyze,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
              children: [
                // ── 顶部覆盖率概览 ──
                _buildCoverageHeader(),

                // ── 分类统计卡片 ──
                _buildCategoryStats(),

                // ── Tab 栏 ──
                _buildTabBar(),

                // ── 缺失字符列表 ──
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMissingGrid(_result!.allMissing, '全部'),
                      _buildMissingGrid(_result!.missingLevel1, '一级汉字'),
                      _buildMissingGrid(_result!.missingLevel2, '二级汉字'),
                      _buildMissingGrid(_result!.missingSymbols, '符号'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// 顶部覆盖率概览区域
  Widget _buildCoverageHeader() {
    final result = _result!;
    final percent = result.coveragePercent;
    final color = _getCoverageColor(percent);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.08),
            color.withValues(alpha: 0.02),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          // 环形进度
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: percent / 100,
                    strokeWidth: 8,
                    backgroundColor:
                        WFColors.textLightColor(context).withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${percent.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      '${result.coveredChars}/${result.totalChars}',
                      style: TextStyle(
                        fontSize: 11,
                        color: WFColors.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // 覆盖详情
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GB2312 覆盖率',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: WFColors.textPrimaryColor(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '已覆盖 ${result.coveredChars} 个字符，'
                  '缺失 ${result.allMissing.length} 个',
                  style: TextStyle(
                    fontSize: 13,
                    color: WFColors.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getCoverageDescription(percent),
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 分类统计卡片
  Widget _buildCategoryStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(child: _buildStatCard(
            '一级汉字',
            _result!.level1Covered,
            _result!.level1Total,
            _result!.level1Percent,
            Icons.text_fields,
            WFColors.primary,
          )),
          const SizedBox(width: 10),
          Expanded(child: _buildStatCard(
            '二级汉字',
            _result!.level2Covered,
            _result!.level2Total,
            _result!.level2Percent,
            Icons.translate,
            WFColors.info,
          )),
          const SizedBox(width: 10),
          Expanded(child: _buildStatCard(
            '符号',
            _result!.symbolCovered,
            _result!.symbolTotal,
            _result!.symbolPercent,
            Icons.tag,
            WFColors.accent,
          )),
        ],
      ),
    );
  }

  /// 单个统计卡片
  Widget _buildStatCard(
    String label,
    int covered,
    int total,
    double percent,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WFColors.bgCardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: WFColors.textLightColor(context).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: WFColors.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${percent.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$covered/$total',
            style: TextStyle(
              fontSize: 11,
              color: WFColors.textLightColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Tab 栏
  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: WFColors.bgPrimaryColor(context),
        border: Border(
          bottom: BorderSide(
            color: WFColors.textLightColor(context).withValues(alpha: 0.3),
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: WFColors.primary,
        unselectedLabelColor: WFColors.textSecondaryColor(context),
        indicatorColor: WFColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          Tab(text: '全部 (${_result!.allMissing.length})'),
          Tab(text: '一级 (${_result!.missingLevel1.length})'),
          Tab(text: '二级 (${_result!.missingLevel2.length})'),
          Tab(text: '符号 (${_result!.missingSymbols.length})'),
        ],
      ),
    );
  }

  /// 缺失字符网格
  Widget _buildMissingGrid(List<String> chars, String category) {
    if (chars.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: WFColors.success),
            const SizedBox(height: 12),
            Text(
              '$category已全部覆盖！',
              style: TextStyle(
                fontSize: 16,
                color: WFColors.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 56,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: chars.length,
      itemBuilder: (ctx, index) {
        final char = chars[index];
        return _buildCharTile(char);
      },
    );
  }

  /// 单个缺失字符方块
  Widget _buildCharTile(String char) {
    return GestureDetector(
      onTap: () => _navigateToEdit(char),
      child: Container(
        decoration: BoxDecoration(
          color: WFColors.bgCardColor(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: WFColors.textLightColor(context).withValues(alpha: 0.4),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          char,
          style: TextStyle(
            fontSize: 20,
            color: WFColors.textPrimaryColor(context),
          ),
        ),
      ),
    );
  }

  /// 导航到字符编辑页面
  void _navigateToEdit(String char) {
    // 确保项目中有该字符的 glyph
    final project = widget.project;
    if (!project.glyphs.containsKey(char)) {
      project.glyphs[char] = GlyphData(
        character: char,
        unicode: char.codeUnitAt(0),
      );
    }

    final glyph = project.glyphs[char]!;

    showDialog(
      context: context,
      builder: (ctx) => CharacterEditDialog(
        character: char,
        glyph: glyph,
        projectId: project.id,
        onCharacterChanged: () {
          // 编辑后保存项目并重新分析
          StorageService.saveProject(project);
          _analyze();
        },
        onCharacterDeleted: () {
          project.glyphs.remove(char);
          StorageService.saveProject(project);
          _analyze();
        },
      ),
    );
  }

  /// 导出缺失字符列表
  Future<void> _exportMissingList() async {
    try {
      final result = _result;
      if (result == null) return;
      await CharsetAnalyzer.shareMissingList(result);
    } catch (e) {
      if (mounted) {
        WFSnackBar.show(context, '导出失败: $e');
      }
    }
  }

  /// 根据覆盖率返回颜色
  Color _getCoverageColor(double percent) {
    if (percent >= 80) return WFColors.success;
    if (percent >= 50) return WFColors.info;
    if (percent >= 20) return WFColors.warning;
    return WFColors.error;
  }

  /// 覆盖率描述文本
  String _getCoverageDescription(double percent) {
    if (percent >= 90) return '优秀！字体已基本覆盖常用字符';
    if (percent >= 70) return '良好，继续补充缺失字符';
    if (percent >= 50) return '中等，建议重点补充一级汉字';
    if (percent >= 20) return '较低，建议优先覆盖常用字';
    return '起步阶段，加油造字！';
  }
}
