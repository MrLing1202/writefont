import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// 辅助功能入口卡片（我的字体 / 字符总览 / 字体预览 / 风格迁移）
class SecondaryEntryCard extends StatelessWidget {
  final int savedProjectCount;
  final VoidCallback onMyFontsTap;
  final VoidCallback onCharGridTap;
  final VoidCallback onFontPreviewTap;
  final VoidCallback onStyleTransferTap;
  final VoidCallback onEnhancedPreviewTap;

  const SecondaryEntryCard({
    super.key,
    required this.savedProjectCount,
    required this.onMyFontsTap,
    required this.onCharGridTap,
    required this.onFontPreviewTap,
    required this.onStyleTransferTap,
    required this.onEnhancedPreviewTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WFCard(
      child: Column(
        children: [
          _SecondaryListTile(
            icon: Icons.folder_special,
            iconColor: WFColors.info,
            title: l10n.myFonts,
            subtitle: savedProjectCount > 0
                ? l10n.myFontsSaved(savedProjectCount)
                : l10n.myFontsDesc,
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
            title: l10n.charOverview,
            subtitle: l10n.charOverviewDesc,
            onTap: onCharGridTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.visibility,
            iconColor: WFColors.accent,
            title: l10n.fontPreview,
            subtitle: l10n.fontPreviewDesc,
            onTap: onFontPreviewTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.dashboard_customize,
            iconColor: WFColors.info,
            title: l10n.enhancedPreview,
            subtitle: l10n.enhancedPreviewDesc,
            onTap: onEnhancedPreviewTap,
          ),
          const Divider(height: 1, indent: 56),
          _SecondaryListTile(
            icon: Icons.auto_fix_high,
            iconColor: WFColors.warning,
            title: l10n.styleTransfer,
            subtitle: l10n.styleTransferDesc,
            onTap: onStyleTransferTap,
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: WFColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: WFColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 8),
            ],
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: WFColors.textLight,
            ),
          ],
        ),
      ),
    );
  }
}
