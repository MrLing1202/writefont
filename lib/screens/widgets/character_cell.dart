import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../processing_screen.dart';

/// 单个字符格子 — 带识别状态、置信度边框、弹跳动画
class CharacterCell extends StatelessWidget {
  final int index;
  final Uint8List imageBytes;
  final bool isSelected;
  final String? assignedChar;
  final CellStatus status;
  final ConfidenceLevel confidence;
  final AnimationController? bounceController;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const CharacterCell({
    super.key,
    required this.index,
    required this.imageBytes,
    required this.isSelected,
    this.assignedChar,
    required this.status,
    required this.confidence,
    this.bounceController,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 弹跳动画缩放值
    double scale = 1.0;
    if (bounceController != null && bounceController!.isAnimating) {
      scale = 1.0 + 0.15 * sin(bounceController!.value * pi);
    }

    // 置信度边框颜色
    Color borderColor;
    if (isSelected) {
      borderColor = colorScheme.primary;
    } else {
      switch (confidence) {
        case ConfidenceLevel.high:
          borderColor = Colors.green;
          break;
        case ConfidenceLevel.medium:
          borderColor = Colors.orange;
          break;
        case ConfidenceLevel.low:
          borderColor = status == CellStatus.failed
              ? Colors.red
              : colorScheme.outlineVariant;
          break;
      }
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedBuilder(
        animation: bounceController ?? const AlwaysStoppedAnimation<double>(0),
        builder: (context, child) {
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 2 : (confidence == ConfidenceLevel.high ? 1.5 : 1),
            ),
            color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 字符图片
              Padding(
                padding: const EdgeInsets.all(4),
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  cacheWidth: 200,
                  cacheHeight: 200,
                ),
              ),

              // 识别中：旋转加载动画
              if (status == CellStatus.recognizing)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                ),

              // 识别失败：红色问号
              if (status == CellStatus.failed)
                Positioned(
                  top: 2,
                  left: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '?',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // 识别结果标签
              if (assignedChar != null && status != CellStatus.recognizing)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: confidence == ConfidenceLevel.high
                          ? Colors.green
                          : confidence == ConfidenceLevel.medium
                              ? Colors.orange
                              : colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      assignedChar!,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // 置信度小圆点（左上角）
              if (status == CellStatus.recognized)
                Positioned(
                  top: 2,
                  left: 2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: confidence == ConfidenceLevel.high
                          ? Colors.green
                          : confidence == ConfidenceLevel.medium
                              ? Colors.orange
                              : Colors.red,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
