import 'dart:math';
import 'package:flutter/material.dart';

/// 网格引导叠加层 — 显示书写引导网格
class GridGuideOverlay extends StatelessWidget {
  final List<String> charset;
  final int completedCount;
  final ColorScheme colorScheme;

  const GridGuideOverlay({
    super.key,
    required this.charset,
    required this.completedCount,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final count = charset.length;
    if (count <= 0) return const SizedBox.shrink();
    final cols = (sqrt(count)).ceil();
    final rows = (count / cols).ceil();

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.grid_on, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '书写引导网格 ($cols×$rows)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '请按此布局在纸上书写',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 网格
          Padding(
            padding: const EdgeInsets.all(8),
            child: Table(
              border: TableBorder.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              defaultColumnWidth: const FlexColumnWidth(),
              children: List.generate(rows, (row) {
                return TableRow(
                  children: List.generate(cols, (col) {
                    final index = row * cols + col;
                    if (index >= charset.length) {
                      return const SizedBox(height: 48);
                    }
                    final char = charset[index];
                    final isCompleted = index < completedCount;
                    return Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? Colors.green.withValues(alpha: 0.1)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isCompleted)
                            const Icon(Icons.check, size: 14, color: Colors.green)
                          else
                            Text(
                              char,
                              style: TextStyle(
                                fontSize: 18,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.4),
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 9,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
