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
