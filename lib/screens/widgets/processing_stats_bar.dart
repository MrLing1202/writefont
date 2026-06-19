import 'package:flutter/material.dart';

/// 识别进度与置信度统计栏
class ProcessingStatsBar extends StatelessWidget {
  final int? charsetLength;
  final int matchedCount;
  final int cellCount;
  final bool isRecognizing;
  final bool isProcessing;
  final int recognizedCount;
  final int totalCount;
  final bool useCloudRecognition;
  final int highConfidenceCount;
  final int needConfirmCount;
  final int selectedCount;

  const ProcessingStatsBar({
    super.key,
    this.charsetLength,
    required this.matchedCount,
    required this.cellCount,
    required this.isRecognizing,
    required this.isProcessing,
    required this.recognizedCount,
    required this.totalCount,
    required this.useCloudRecognition,
    required this.highConfidenceCount,
    required this.needConfirmCount,
    required this.selectedCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surfaceVariant.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.grid_view, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          if (charsetLength != null)
            Text(
              '已匹配 $matchedCount/$charsetLength',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Text(
              '识别到 $cellCount 个字符',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (isRecognizing) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'AI识别中 $recognizedCount/$totalCount',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
              ),
            ),
          ] else if (!isProcessing) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_circle, size: 14, color: colorScheme.primary),
            const SizedBox(width: 2),
            Text(
              useCloudRecognition ? '云端识别' : '本地识别',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
              ),
            ),
          ],
          const Spacer(),
          // 置信度统计
          if (!isRecognizing && (highConfidenceCount > 0 || needConfirmCount > 0)) ...[
            _buildConfidenceChip('🟢 高', highConfidenceCount, Colors.green, colorScheme),
            const SizedBox(width: 4),
            _buildConfidenceChip('🟡 中', needConfirmCount, Colors.orange, colorScheme),
          ],
          if (selectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '已选 $selectedCount 个',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConfidenceChip(String label, int count, Color color, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
