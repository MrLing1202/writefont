import 'package:flutter/material.dart';

/// 说明横幅：提示用户书写和拍照建议
class InfoBanner extends StatelessWidget {
  final ColorScheme colorScheme;

  const InfoBanner({super.key, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tips_and_updates_outlined,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '拍照建议',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTip(
            Icons.wb_sunny_outlined,
            '光线充足，避免反光和阴影',
          ),
          const SizedBox(height: 4),
          _buildTip(
            Icons.pan_tool_outlined,
            '保持手机稳定，对焦清晰',
          ),
          const SizedBox(height: 4),
          _buildTip(
            Icons.center_focus_strong_outlined,
            '纸张平整，字迹清晰工整',
          ),
        ],
      ),
    );
  }

  Widget _buildTip(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}
