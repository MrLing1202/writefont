import 'package:flutter/material.dart';

/// 拍摄进度指示条
class ProgressBanner extends StatelessWidget {
  final int imageCount;
  final int totalChars;
  final ColorScheme colorScheme;

  const ProgressBanner({
    super.key,
    required this.imageCount,
    required this.totalChars,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.camera_alt, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '已拍摄 $imageCount / $totalChars 个字符',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          ...List.generate(
            imageCount.clamp(0, 10),
            (i) => const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Icon(Icons.check_circle, size: 16, color: Colors.green),
            ),
          ),
          if (imageCount > 10)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '+${imageCount - 10}',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
