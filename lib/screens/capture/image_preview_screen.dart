import 'dart:io';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'image_quality.dart';

/// 图片预览页面 — 显示图片 + 质量检测结果 + 确认/重拍按钮
class ImagePreviewScreen extends StatelessWidget {
  final String imagePath;
  final ImageQualityResult quality;

  const ImagePreviewScreen({
    super.key,
    required this.imagePath,
    required this.quality,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const WFAppBar(
        title: '图片预览',
      ),
      body: Column(
        children: [
          // 质量检测结果
          _buildQualityBanner(colorScheme),

          // 可缩放的图片预览
          Expanded(
            child: InteractiveViewer(
              maxScale: 5.0,
              minScale: 0.5,
              child: Center(
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.contain,
                  cacheWidth: 800,
                  cacheHeight: 800,
                ),
              ),
            ),
          ),

          // 底部按钮
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('重新拍摄'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.check),
                      label: const Text('确认使用'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityBanner(ColorScheme colorScheme) {
    final Color bannerColor;
    final Color textColor;
    final IconData icon;
    final String emoji;

    switch (quality.level) {
      case QualityLevel.good:
        bannerColor = Colors.green.withValues(alpha: 0.1);
        textColor = Colors.green.shade800;
        icon = Icons.check_circle;
        emoji = '🟢';
        break;
      case QualityLevel.medium:
        bannerColor = Colors.orange.withValues(alpha: 0.1);
        textColor = Colors.orange.shade800;
        icon = Icons.warning_amber;
        emoji = '🟡';
        break;
      case QualityLevel.poor:
        bannerColor = Colors.red.withValues(alpha: 0.1);
        textColor = Colors.red.shade800;
        icon = Icons.error_outline;
        emoji = '🔴';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: bannerColor,
      child: Row(
        children: [
          Icon(icon, size: 20, color: textColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$emoji 质量检测: ${quality.summary}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '亮度: ${quality.brightness.toStringAsFixed(0)}  '
                  '清晰度: ${quality.sharpness.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
                if (quality.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ...quality.suggestions.map((s) => Text(
                    '💡 $s',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
