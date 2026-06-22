import 'package:flutter/material.dart';

/// 统计信息栏 — 显示总数、AI识别、用户修正、自动补齐、低置信度
class StatsBar extends StatelessWidget {
  final Map<String, int> stats;
  final ColorScheme colorScheme;
  final int lowConfidenceCount;

  const StatsBar({
    super.key,
    required this.stats,
    required this.colorScheme,
    this.lowConfidenceCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildStatChip(
                icon: Icons.grid_view,
                label: '共 ${stats['total']} 个',
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              _buildStatChip(
                icon: Icons.auto_awesome,
                label: 'AI 识别 ${stats['aiRecognized']}',
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 8),
              _buildStatChip(
                icon: Icons.edit,
                label: '已修正 ${stats['userEdited']}',
                color: Colors.blue.shade700,
              ),
              const SizedBox(width: 8),
              _buildStatChip(
                icon: Icons.format_list_numbered,
                label: '自动补齐 ${stats['fallbackAssigned']}',
                color: Colors.orange.shade700,
              ),
            ],
          ),
          // 低置信度警告（仅在有低置信度字符时显示）
          if (lowConfidenceCount > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.shade200, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber, size: 14, color: Colors.red.shade700),
                  const SizedBox(width: 4),
                  Text(
                    '$lowConfidenceCount 个字符置信度较低，建议检查',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
