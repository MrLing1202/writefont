import 'package:flutter/material.dart';
import 'charset_guide_screen.dart';

/// 书写规范提示页面
class WritingTipsScreen extends StatelessWidget {
  const WritingTipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('书写规范'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 标题
            Text(
              '按照规范书写，生成效果更好',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),

            // 4步引导卡片
            _buildTipCard(
              context,
              step: 1,
              icon: Icons.edit_note,
              title: '准备纸和笔',
              description: '使用白纸和黑色签字笔，效果最佳',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 16),

            _buildTipCard(
              context,
              step: 2,
              icon: Icons.grid_on,
              title: '按字表逐行书写',
              description: '按照提供的40个常用字，逐行书写',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 16),

            _buildTipCard(
              context,
              step: 3,
              icon: Icons.straighten,
              title: '保持大小均等',
              description: '每个字大小尽量一致，间距均匀，排版工整',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 16),

            _buildTipCard(
              context,
              step: 4,
              icon: Icons.camera_alt,
              title: '拍照上传',
              description: '将写好的字拍照上传，AI 自动识别生成字体',
              colorScheme: colorScheme,
            ),

            const SizedBox(height: 24),

            // 书写规范说明
            _buildSectionHeader(context, icon: Icons.rule, title: '书写规范', colorScheme: colorScheme),
            const SizedBox(height: 12),
            _buildDetailTipCard(
              context,
              icon: Icons.pen_fountain,
              title: '使用黑色签字笔或中性笔',
              description: '避免使用铅笔、彩色笔或可擦笔，黑色笔迹对比度高，识别效果最好。建议使用 0.5mm 或 0.7mm 笔芯。',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _buildDetailTipCard(
              context,
              icon: Icons.description,
              title: '白色纸张书写',
              description: '使用白色或浅色纸张，避免使用带横线、格子花纹的纸张。纯白背景能让字迹更清晰。',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _buildDetailTipCard(
              context,
              icon: Icons.auto_fix_high,
              title: '字迹工整清晰',
              description: '不要潦草书写，保持笔画完整、结构清晰。尽量保持你平时正常的书写习惯。',
              colorScheme: colorScheme,
            ),

            const SizedBox(height: 24),

            // 格子大小建议
            _buildSectionHeader(context, icon: Icons.grid_4x4, title: '格子大小建议', colorScheme: colorScheme),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                      ),
                      child: Center(
                        child: Text(
                          '2cm',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '建议每格约 2cm × 2cm',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '字体约占格子的 80%，留出上下左右的边距。格子太小会导致笔画粘连，太大会浪费空间。',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 常见问题提示
            _buildSectionHeader(context, icon: Icons.warning_amber_rounded, title: '常见问题', colorScheme: colorScheme),
            const SizedBox(height: 12),
            _buildProblemCard(
              context,
              icon: Icons.block,
              problem: '避免连笔',
              description: '每个字单独书写，笔画之间不要连笔。连笔会导致轮廓提取失败或识别不准确。',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _buildProblemCard(
              context,
              icon: Icons.crop_free,
              problem: '字不要写出格子',
              description: '保持字在格子范围内书写，不要让笔画超出边界，否则会导致相邻字符粘连。',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _buildProblemCard(
              context,
              icon: Icons.space_bar,
              problem: '保持间距均匀',
              description: '字与字之间的间距保持一致，避免过密或过疏。均匀的间距有助于自动分割字符。',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _buildProblemCard(
              context,
              icon: Icons.zoom_out_map,
              problem: '大小保持一致',
              description: '所有字的大小尽量相同，不要忽大忽小。大小差异过大会影响字体的整体一致性。',
              colorScheme: colorScheme,
            ),

            const SizedBox(height: 24),

            // 小贴士
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '最少写30字，写得越多生成的字体越像你的笔迹',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 开始按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CharsetGuideScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.arrow_forward),
                label: const Text('开始写字'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 区域标题
  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required ColorScheme colorScheme,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  /// 详细提示卡片（书写规范用）
  Widget _buildDetailTipCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required ColorScheme colorScheme,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
              ),
              child: Icon(icon, size: 20, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
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

  /// 常见问题卡片
  Widget _buildProblemCard(
    BuildContext context, {
    required IconData icon,
    required String problem,
    required String description,
    required ColorScheme colorScheme,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.errorContainer.withValues(alpha: 0.5),
        ),
      ),
      color: colorScheme.errorContainer.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
              ),
              child: Icon(icon, size: 18, color: colorScheme.error),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    problem,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
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

  Widget _buildTipCard(
    BuildContext context, {
    required int step,
    required IconData icon,
    required String title,
    required String description,
    required ColorScheme colorScheme,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // 步骤编号
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '0$step',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // 图标
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 28, color: colorScheme.primary),
            ),
            const SizedBox(width: 16),

            // 文字
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
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
}
