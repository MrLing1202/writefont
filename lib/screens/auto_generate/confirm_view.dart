import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'character_cell.dart';
import 'stats_bar.dart';

/// 确认字符视图 — 统计栏 + 字符网格 + 底部操作按钮
class ConfirmView extends StatelessWidget {
  final List<Uint8List> cells;
  final String? Function(int index) getCharAt;
  final bool Function(int index) isAiRecognized;
  final bool Function(int index) isUserEdited;
  final bool Function(int index) isFailedRecognition;
  final bool isGenerating;
  final double progress;
  final String status;
  final Map<String, int> stats;
  final void Function(int index) onQuickEdit;
  final void Function(int index) onRetryRecognition;
  final VoidCallback onReidentify;
  final VoidCallback onConfirmGenerate;
  final ColorScheme colorScheme;

  const ConfirmView({
    super.key,
    required this.cells,
    required this.getCharAt,
    required this.isAiRecognized,
    required this.isUserEdited,
    required this.isFailedRecognition,
    required this.isGenerating,
    required this.progress,
    required this.status,
    required this.stats,
    required this.onQuickEdit,
    required this.onRetryRecognition,
    required this.onReidentify,
    required this.onConfirmGenerate,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部统计信息栏
        StatsBar(stats: stats, colorScheme: colorScheme),

        // 字符网格
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: cells.length,
            itemBuilder: (context, index) {
              return CharacterCell(
                cellImageBytes: cells[index],
                char: getCharAt(index) ?? '',
                isRecognized: isAiRecognized(index),
                isEdited: isUserEdited(index),
                isFailed: isFailedRecognition(index),
                isGenerating: isGenerating,
                index: index,
                onTap: () => onQuickEdit(index),
                onRetry: () => onRetryRecognition(index),
              );
            },
          ),
        ),

        // 底部操作按钮
        _buildBottomActions(context),
      ],
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '点击字符可修改识别结果',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),

          // 图例说明
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendDot(Colors.green.shade500, 'AI 识别'),
              const SizedBox(width: 16),
              _buildLegendDot(Colors.blue.shade400, '已修正'),
              const SizedBox(width: 16),
              _buildLegendDot(Colors.orange.shade400, '自动补齐'),
            ],
          ),
          const SizedBox(height: 16),

          // 生成进度（生成中显示）
          if (isGenerating) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: colorScheme.primary,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              status,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 按钮行
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isGenerating ? null : onReidentify,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新识别'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: isGenerating ? null : onConfirmGenerate,
                  icon: Icon(isGenerating ? Icons.hourglass_top : Icons.check_circle),
                  label: Text(isGenerating ? '生成中...' : '确认生成'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
