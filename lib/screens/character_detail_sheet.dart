import 'package:flutter/material.dart';
import '../services/recognition_service.dart';

/// 字符详情底部弹窗 — 展示识别结果、置信度、投票详情
/// v2.7.0: 让用户看到"这个字是怎么选出来的"
class CharacterDetailSheet extends StatelessWidget {
  final String char;
  final RecognitionDetail? detail;
  final VoidCallback onRetry;
  final VoidCallback onEdit;

  const CharacterDetailSheet({
    super.key,
    required this.char,
    this.detail,
    required this.onRetry,
    required this.onEdit,
  });

  static Future<void> show(
    BuildContext context, {
    required String char,
    RecognitionDetail? detail,
    required VoidCallback onRetry,
    required VoidCallback onEdit,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CharacterDetailSheet(
        char: char,
        detail: detail,
        onRetry: onRetry,
        onEdit: onEdit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 拖拽指示条
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 字符 + 置信度
          Row(
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(char, style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('识别结果: $char', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    const SizedBox(height: 6),
                    if (detail != null) ...[
                      Row(
                        children: [
                          Icon(Icons.circle, size: 10, color: _confidenceColor(detail!.confidence)),
                          const SizedBox(width: 6),
                          Text('置信度: ${(detail!.confidence * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 15, color: _confidenceColor(detail!.confidence), fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${detail!.strategiesUsed} 种策略参与识别', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    ] else
                      Text('暂无投票详情', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),

          if (detail != null) ...[
            const SizedBox(height: 20),
            Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),

            // 投票详情
            Text('📊 投票详情', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 10),

            ..._buildVoteBars(cs),

            const SizedBox(height: 16),

            // 提前终止 & 最可靠策略
            if (detail!.earlyTerminated)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Text('⚡', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('提前终止 — 节省了 ${detail!.attemptsSaved} 次识别', style: TextStyle(fontSize: 13, color: Colors.amber.shade900))),
                  ],
                ),
              ),
            if (detail!.topStrategy != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Text('🏆', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('最可靠策略: ${detail!.topStrategy} (成功率 ${(detail!.topStrategyReliability * 100).toStringAsFixed(0)}%)', style: TextStyle(fontSize: 13, color: Colors.green.shade900))),
                  ],
                ),
              ),
            ],
          ],

          const SizedBox(height: 24),

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () { Navigator.pop(context); onRetry(); },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新识别'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () { Navigator.pop(context); onEdit(); },
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('手动修改'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildVoteBars(ColorScheme cs) {
    if (detail == null || detail!.voteBreakdown.isEmpty) {
      return [Text('无投票数据', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))];
    }

    // 收集所有策略的投票
    final allVotes = <String, int>{};
    for (final charVotes in detail!.voteBreakdown.values) {
      for (final entry in charVotes.entries) {
        allVotes[entry.key] = (allVotes[entry.key] ?? 0) + entry.value;
      }
    }
    if (allVotes.isEmpty) return [Text('无投票数据', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))];

    final sorted = allVotes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxVotes = sorted.first.value;

    return sorted.take(8).map((entry) {
      final isWinner = entry == sorted.first;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(
                entry.key,
                style: TextStyle(fontSize: 12, color: isWinner ? cs.primary : cs.onSurfaceVariant, fontWeight: isWinner ? FontWeight.w600 : FontWeight.normal),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: entry.value / maxVotes,
                  minHeight: 14,
                  color: isWinner ? cs.primary : cs.primary.withValues(alpha: 0.4),
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 50,
              child: Text(
                '${entry.value}票${isWinner ? " 👑" : ""}',
                style: TextStyle(fontSize: 11, color: isWinner ? cs.primary : cs.onSurfaceVariant, fontWeight: isWinner ? FontWeight.w600 : FontWeight.normal),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Color _confidenceColor(double conf) {
    if (conf >= 0.85) return Colors.green.shade600;
    if (conf >= 0.6) return Colors.orange.shade700;
    return Colors.red.shade600;
  }
}
