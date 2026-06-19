import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 字体信息头部 — WFCard 包裹，显示字体名称、字符完成度、创建日期
class FontInfoHeader extends StatelessWidget {
  final String fontName;
  final String dateStr;
  final int editedCount;
  final int totalCount;

  const FontInfoHeader({
    super.key,
    required this.fontName,
    required this.dateStr,
    required this.editedCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: WFCard(
        accentColor: WFColors.accent,
        child: Row(
          children: [
            // 左侧：字体名称 & 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fontName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: WFColors.textPrimaryColor(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.text_fields, size: 14, color: WFColors.textSecondaryColor(context)),
                      const SizedBox(width: 4),
                      Text(
                        '$editedCount / $totalCount 个字符',
                        style: TextStyle(
                          fontSize: 13,
                          color: WFColors.textSecondaryColor(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.calendar_today, size: 14, color: WFColors.textSecondaryColor(context)),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 13,
                          color: WFColors.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 右侧：完成度指示
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: editedCount == totalCount && totalCount > 0
                    ? WFColors.success.withValues(alpha: 0.12)
                    : WFColors.primary.withValues(alpha: 0.12),
              ),
              child: Center(
                child: Text(
                  totalCount > 0 ? '${(editedCount * 100 ~/ totalCount)}%' : '0%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: editedCount == totalCount && totalCount > 0
                        ? WFColors.success
                        : WFColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
