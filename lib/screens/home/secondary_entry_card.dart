import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 辅助功能入口卡片（我的字体 / 字符总览 / 字体预览 / 风格迁移）
class SecondaryEntryCard extends StatelessWidget {
  final int savedProjectCount;
  final VoidCallback onMyFontsTap;
  final VoidCallback onCharGridTap;
  final VoidCallback onFontPreviewTap;
  final VoidCallback onStyleTransferTap;
  final VoidCallback onEnhancedPreviewTap;
  final VoidCallback onTemplateGeneratorTap;
  final VoidCallback onFontCompareTap;
  final VoidCallback onPracticeModeTap;
  final VoidCallback onKerningEditorTap;
  final VoidCallback onCharRecommendTap;
  final VoidCallback onGlyphQualityTap;
  final VoidCallback onWebExportTap;
  final VoidCallback onFontFamilyTap;
  final VoidCallback onStrokeOrderTap;
  final VoidCallback onCharsetAnalysisTap;
  final VoidCallback onGlyphCompletionTap;
  final VoidCallback onTextPreviewTap;

  const SecondaryEntryCard({
    super.key,
    required this.savedProjectCount,
    required this.onMyFontsTap,
    required this.onCharGridTap,
    required this.onFontPreviewTap,
    required this.onStyleTransferTap,
    required this.onEnhancedPreviewTap,
    required this.onTemplateGeneratorTap,
    required this.onFontCompareTap,
    required this.onPracticeModeTap,
    required this.onKerningEditorTap,
    required this.onCharRecommendTap,
    required this.onGlyphQualityTap,
    required this.onWebExportTap,
    required this.onFontFamilyTap,
    required this.onStrokeOrderTap,
    required this.onCharsetAnalysisTap,
    required this.onGlyphCompletionTap,
    required this.onTextPreviewTap,
  });

  @override
  Widget build(BuildContext context) {
    return WFCard(
      child: Column(
        children: [
          _SecondaryListTile(
            icon: Icons.folder_special,
            iconColor: WFColors.info,
            title: '我的字体',
            subtitle: savedProjectCount > 0
                ? '已保存 $savedProjectCount 个字体项目'
                : '查看和管理已保存的字体项目',
            trailing: savedProjectCount > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: WFColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$savedProjectCount',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  )
                : null,
            onTap: onMyFontsTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.dashboard,
            iconColor: WFColors.success,
            title: '字符总览',
            subtitle: '查看造字进度',
            onTap: onCharGridTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.visibility,
            iconColor: WFColors.accent,
            title: '字体预览',
            subtitle: '输入文字查看手迹效果',
            onTap: onFontPreviewTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.dashboard_customize,
            iconColor: WFColors.info,
            title: '增强预览',
            subtitle: '多字号 · 多场景 · 实时对比',
            onTap: onEnhancedPreviewTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.auto_fix_high,
            iconColor: WFColors.warning,
            title: '风格迁移',
            subtitle: 'AI 智能字体风格转换',
            onTap: onStyleTransferTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.grid_on,
            iconColor: WFColors.primary,
            title: '手写模板',
            subtitle: '生成可打印方格纸模板',
            onTap: onTemplateGeneratorTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.compare,
            iconColor: WFColors.accent,
            title: '字体对比',
            subtitle: '多字体并排预览对比',
            onTap: onFontCompareTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.edit_note,
            iconColor: WFColors.success,
            title: '练习模式',
            subtitle: '针对弱字反复练习',
            onTap: onPracticeModeTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.space_bar,
            iconColor: WFColors.primary,
            title: '字形间距',
            subtitle: '调整字形对之间的间距',
            onTap: onKerningEditorTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.recommend,
            iconColor: WFColors.warning,
            title: '智能推荐',
            subtitle: '查看待写字符与完成进度',
            onTap: onCharRecommendTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.assessment,
            iconColor: const Color(0xFF9B59B6),
            title: '字形质量',
            subtitle: '四维评分 · 发现待改进字形',
            onTap: onGlyphQualityTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.language,
            iconColor: WFColors.info,
            title: '网页导出',
            subtitle: '生成 @font-face CSS · HTML · Flutter 代码',
            onTap: onWebExportTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.font_download,
            iconColor: const Color(0xFF2ECC71),
            title: '字体家族',
            subtitle: '一键生成 Bold · Italic 变体',
            onTap: onFontFamilyTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.brush,
            iconColor: const Color(0xFFE67E22),
            title: '笔画顺序',
            subtitle: '演示汉字书写笔画顺序动画',
            onTap: onStrokeOrderTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.pie_chart,
            iconColor: const Color(0xFF1ABC9C),
            title: '字符集分析',
            subtitle: 'GB2312 覆盖率统计 · 缺失字符',
            onTap: onCharsetAnalysisTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.auto_fix_high,
            iconColor: const Color(0xFFE74C3C),
            title: '字形自动补全',
            subtitle: '笔画模板组合生成缺失字形',
            onTap: onGlyphCompletionTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.text_snippet,
            iconColor: const Color(0xFF3498DB),
            title: '自定义文本预览',
            subtitle: '输入任意文字查看字体效果',
            onTap: onTextPreviewTap,
          ),
        ],
      ),
    );
  }
}

class _SecondaryListTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SecondaryListTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
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
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: WFColors.textPrimaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: WFColors.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 8),
            ],
            Icon(
              Icons.chevron_right,
              size: 20,
              color: WFColors.textLightColor(context),
            ),
          ],
        ),
      ),
    );
  }
}
