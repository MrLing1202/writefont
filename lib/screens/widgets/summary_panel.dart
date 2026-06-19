import 'package:flutter/material.dart';

/// 完成汇总面板 — 显示识别统计和操作按钮
class SummaryPanel extends StatelessWidget {
  final int totalCount;
  final int recognizedSuccessCount;
  final int needConfirmCount;
  final VoidCallback onCheckEach;
  final VoidCallback onContinue;

  const SummaryPanel({
    super.key,
    required this.totalCount,
    required this.recognizedSuccessCount,
    required this.needConfirmCount,
    required this.onCheckEach,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 汇总标题
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.celebration, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '全部完成！',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 统计数据
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSummaryItem('总字符', totalCount, colorScheme.onSurface),
              const SizedBox(width: 16),
              _buildSummaryItem('识别成功', recognizedSuccessCount, Colors.green),
              const SizedBox(width: 16),
              _buildSummaryItem('需确认', needConfirmCount, Colors.orange),
            ],
          ),
          const SizedBox(height: 12),
          // 两个按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCheckEach,
                  icon: const Icon(Icons.checklist, size: 18),
                  label: const Text('逐个检查'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onContinue,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('全部正确，继续'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
