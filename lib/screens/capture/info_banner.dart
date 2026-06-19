import 'package:flutter/material.dart';

/// 说明横幅：提示用户书写建议
class InfoBanner extends StatelessWidget {
  final ColorScheme colorScheme;

  const InfoBanner({super.key, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '建议使用方格纸书写，每个格子写一个字符，拍照时保持平整清晰',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
