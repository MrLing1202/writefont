import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 单个字符格子 — 显示字符图片、识别结果标签、状态图标
class CharacterCell extends StatelessWidget {
  final Uint8List cellImageBytes;
  final String char;
  final bool isRecognized;
  final bool isEdited;
  final bool isFailed;
  final bool isGenerating;
  final int index;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  const CharacterCell({
    super.key,
    required this.cellImageBytes,
    required this.char,
    required this.isRecognized,
    required this.isEdited,
    required this.isFailed,
    required this.isGenerating,
    required this.index,
    this.onTap,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // 根据状态确定边框颜色
    Color borderColor;
    if (isEdited) {
      borderColor = Colors.blue.shade400;
    } else if (isRecognized) {
      borderColor = Colors.green.shade400;
    } else {
      borderColor = Colors.orange.shade300;
    }

    return GestureDetector(
      onTap: isGenerating ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1.5),
          color: Theme.of(context).colorScheme.surface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 字符图片
            Padding(
              padding: const EdgeInsets.all(4),
              child: Image.memory(
                cellImageBytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                cacheWidth: 200,
                cacheHeight: 200,
              ),
            ),

            // 识别结果标签（底部居中）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                  border: Border(
                    top: BorderSide(color: borderColor.withValues(alpha: 0.3)),
                  ),
                ),
                child: Text(
                  char,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),

            // 状态图标（右上角）
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isEdited
                      ? Colors.blue.shade400
                      : isRecognized
                          ? Colors.green.shade500
                          : Colors.orange.shade400,
                ),
                child: Icon(
                  isEdited
                      ? Icons.edit
                      : isRecognized
                          ? Icons.check
                          : Icons.swap_horiz,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),

            // 重试按钮（识别失败时显示）
            if (isFailed && !isGenerating)
              Positioned(
                top: 0,
                left: 0,
                child: GestureDetector(
                  onTap: onRetry,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.red.shade400.withValues(alpha: 0.9),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                    ),
                    child: const Icon(
                      Icons.refresh,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // 索引编号（左上角，无重试按钮时显示）
            if (!isFailed || isGenerating)
              Positioned(
                top: 2,
                left: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
