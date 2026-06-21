import 'package:flutter/material.dart';
import '../data/standard_charset.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';

/// 智能字符推荐页面
/// 展示标准字表完成进度，推荐待写字符
class CharRecommendScreen extends StatefulWidget {
  final FontProject project;

  const CharRecommendScreen({super.key, required this.project});

  @override
  State<CharRecommendScreen> createState() => _CharRecommendScreenState();
}

class _CharRecommendScreenState extends State<CharRecommendScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// 已完成的字符集合
  late final Set<String> _writtenChars;

  /// 推荐字符（基础30字中未写的，排在最前）
  late final List<StandardChar> _recommendedChars;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _writtenChars = widget.project.glyphs.keys.toSet();
    _recommendedChars = _buildRecommendations();
  }

  /// 构建推荐列表：基础字未写的优先，然后扩展字未写的
  List<StandardChar> _buildRecommendations() {
    final unwrittenBasic = StandardCharset.basicChars
        .where((c) => !_writtenChars.contains(c.char))
        .toList();
    final unwrittenExtended = StandardCharset.extendedChars
        .where((c) => !_writtenChars.contains(c.char))
        .toList();
    return [...unwrittenBasic, ...unwrittenExtended];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = StandardCharset.allChars.length; // 108
    final written = _writtenChars.length;
    final percent = total > 0 ? (written / total * 100).round() : 0;

    // 基础/扩展完成数
    final basicWritten = StandardCharset.basicChars
        .where((c) => _writtenChars.contains(c.char))
        .length;
    final extendedWritten = StandardCharset.extendedChars
        .where((c) => _writtenChars.contains(c.char))
        .length;

    return Scaffold(
      appBar: WFAppBar(
        title: '智能推荐',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // ── 顶部进度区域 ──
          _buildProgressSection(colorScheme, written, total, percent),

          // ── Tab 栏 ──
          Container(
            decoration: BoxDecoration(
              color: WFColors.bgPrimaryColor(context),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: colorScheme.primary,
              unselectedLabelColor: WFColors.textSecondaryColor(context),
              indicatorColor: colorScheme.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
              tabs: [
                Tab(text: '全部 ($total)'),
                Tab(text: '已完成 ($written)'),
                Tab(text: '待写 (${total - written})'),
              ],
            ),
          ),

          // ── Tab 内容 ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAllTab(colorScheme),
                _buildCompletedTab(colorScheme),
                _buildPendingTab(colorScheme),
              ],
            ),
          ),

          // ── 底部统计 ──
          _buildBottomStats(colorScheme, basicWritten, extendedWritten),
        ],
      ),
    );
  }

  /// 顶部进度条区域
  Widget _buildProgressSection(
    ColorScheme colorScheme,
    int written,
    int total,
    int percent,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: WFCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '书写进度',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
              Text(
                '$written / $total',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total > 0 ? written / total : 0,
              minHeight: 10,
              backgroundColor:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              valueColor:
                  AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$percent%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: WFColors.textSecondaryColor(context),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// 全部字符 Tab
  Widget _buildAllTab(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('基础 30 字', colorScheme),
          const SizedBox(height: 8),
          _buildCharGrid(StandardCharset.basicChars, colorScheme),
          const SizedBox(height: 20),
          _buildSectionTitle('扩展 78 字', colorScheme),
          const SizedBox(height: 8),
          _buildCharGrid(StandardCharset.extendedChars, colorScheme),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 已完成 Tab
  Widget _buildCompletedTab(ColorScheme colorScheme) {
    final completed = StandardCharset.allChars
        .where((c) => _writtenChars.contains(c.char))
        .toList();

    if (completed.isEmpty) {
      return _buildEmptyState(
        colorScheme,
        Icons.edit_note,
        '还没有书写任何字符',
        '去写字页面开始创作吧',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _buildCharGrid(completed, colorScheme),
    );
  }

  /// 待写 Tab（推荐字符）
  Widget _buildPendingTab(ColorScheme colorScheme) {
    if (_recommendedChars.isEmpty) {
      return _buildEmptyState(
        colorScheme,
        Icons.celebration,
        '全部完成！',
        '108 个标准字符已全部书写',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 推荐提示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: WFColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    size: 18, color: WFColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '优先书写黄色推荐字符，基础字对字体效果影响最大',
                    style: TextStyle(
                      fontSize: 13,
                      color: WFColors.textSecondaryColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildCharGrid(_recommendedChars, colorScheme),
        ],
      ),
    );
  }

  /// 构建字符网格
  Widget _buildCharGrid(List<StandardChar> chars, ColorScheme colorScheme) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: chars.length,
      itemBuilder: (context, index) {
        final char = chars[index];
        return _buildCharCard(char, colorScheme);
      },
    );
  }

  /// 单个字符卡片
  Widget _buildCharCard(StandardChar char, ColorScheme colorScheme) {
    final isWritten = _writtenChars.contains(char.char);
    final isBasic = StandardCharset.basicChars.contains(char);

    // 状态颜色
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    if (isWritten) {
      // 已完成：绿色
      bgColor = WFColors.success.withValues(alpha: 0.08);
      borderColor = WFColors.success.withValues(alpha: 0.4);
      textColor = WFColors.success;
    } else if (isBasic) {
      // 推荐（基础字未写）：黄色
      bgColor = WFColors.warning.withValues(alpha: 0.08);
      borderColor = WFColors.warning.withValues(alpha: 0.4);
      textColor = WFColors.textPrimaryColor(context);
    } else {
      // 未完成：灰色
      bgColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.2);
      borderColor = colorScheme.outlineVariant.withValues(alpha: 0.3);
      textColor = WFColors.textSecondaryColor(context);
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Stack(
        children: [
          // 完成标记
          if (isWritten)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.check_circle,
                size: 14,
                color: WFColors.success,
              ),
            ),

          // 汉字
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  char.char,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  char.pinyin,
                  style: TextStyle(
                    fontSize: 10,
                    color: isWritten
                        ? WFColors.success.withValues(alpha: 0.7)
                        : WFColors.textSecondaryColor(context)
                            .withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 小节标题
  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: WFColors.textPrimaryColor(context),
      ),
    );
  }

  /// 空状态提示
  Widget _buildEmptyState(
    ColorScheme colorScheme,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 56,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部统计栏
  Widget _buildBottomStats(
    ColorScheme colorScheme,
    int basicWritten,
    int extendedWritten,
  ) {
    final basicTotal = StandardCharset.basicChars.length;
    final extendedTotal = StandardCharset.extendedChars.length;
    final basicPercent =
        basicTotal > 0 ? (basicWritten / basicTotal * 100).round() : 0;
    final extendedPercent =
        extendedTotal > 0 ? (extendedWritten / extendedTotal * 100).round() : 0;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: WFColors.bgCardColor(context),
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Row(
          children: [
            _buildStatChip(
              colorScheme,
              '基础',
              '$basicWritten/$basicTotal',
              '$basicPercent%',
              basicWritten >= basicTotal
                  ? WFColors.success
                  : colorScheme.primary,
            ),
            const SizedBox(width: 12),
            _buildStatChip(
              colorScheme,
              '扩展',
              '$extendedWritten/$extendedTotal',
              '$extendedPercent%',
              extendedWritten >= extendedTotal
                  ? WFColors.success
                  : colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  /// 单个统计标签
  Widget _buildStatChip(
    ColorScheme colorScheme,
    String label,
    String count,
    String percent,
    Color accentColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: WFColors.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ],
            ),
            Text(
              percent,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
