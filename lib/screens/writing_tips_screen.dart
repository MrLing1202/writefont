import 'package:flutter/material.dart';
import 'charset_guide_screen.dart';
import '../theme/app_theme.dart';

/// 书写规范提示页面
class WritingTipsScreen extends StatelessWidget {
  const WritingTipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: WFAppBar(
        title: '书写规范',
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

            // 实用书写技巧
            _buildSectionHeader(context, icon: Icons.tips_and_updates, title: '实用书写技巧', colorScheme: colorScheme),
            const SizedBox(height: 12),
            _buildPracticalTipCard(
              context,
              icon: Icons.edit,
              iconColor: WFColors.primary,
              title: '黑色签字笔 + 白纸',
              description: '用黑色签字笔在白纸上书写效果最佳。避免铅笔、彩色笔或可擦笔，黑色笔迹对比度高，识别最准确。',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _buildPracticalTipCard(
              context,
              icon: Icons.format_size,
              iconColor: WFColors.info,
              title: '字写大一点，笔画清晰',
              description: '每个字尽量写大，笔画之间留出空隙。建议每格约 2cm，字体占格子 80%。笔画清晰的字生成质量更高。',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _buildPracticalTipCard(
              context,
              icon: Icons.block,
              iconColor: WFColors.warning,
              title: '避免连笔和潦草字',
              description: '一笔一画书写，不要连笔或潦草。连笔会导致轮廓提取失败，潦草字会影响最终字体的美观度。',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _buildPracticalTipCard(
              context,
              icon: Icons.wb_sunny,
              iconColor: WFColors.success,
              title: '纸面平整，光线均匀',
              description: '拍照时保持纸张平整无褶皱，光线均匀无阴影。避免反光和暗角，这样 AI 识别效果最好。',
              colorScheme: colorScheme,
            ),

            const SizedBox(height: 24),

            // 格子大小建议
            _buildSectionHeader(context, icon: Icons.grid_4x4, title: '格子大小建议', colorScheme: colorScheme),
            const SizedBox(height: 12),
            WFCard(
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
            color: WFColors.textPrimary,
          ),
        ),
      ],
    );
  }

  /// 实用书写技巧卡片（带彩色图标）
  Widget _buildPracticalTipCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required ColorScheme colorScheme,
  }) {
    return WFCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: iconColor.withValues(alpha: 0.12),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
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
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    return WFCard(
      accentColor: WFColors.error,
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
    return WFCard(
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
    );
  }
}
