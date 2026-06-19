import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 处理中的视图 — 图片预览 + 进度指示器 + 状态文字
class ProcessingView extends StatelessWidget {
  final Uint8List imageBytes;
  final double progress;
  final String status;
  final ColorScheme colorScheme;

  const ProcessingView({
    super.key,
    required this.imageBytes,
    required this.progress,
    required this.status,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 图片预览
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(
                imageBytes,
                fit: BoxFit.cover,
                cacheWidth: 800,
                cacheHeight: 800,
              ),
            ),
            const SizedBox(height: 40),

            // 进度指示器
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                value: progress < 1.0 ? progress : null,
                strokeWidth: 4,
                color: colorScheme.primary,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 24),

            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: colorScheme.primary,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 16),

            // 状态文字
            Text(
              status,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
