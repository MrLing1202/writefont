import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../processing_screen.dart';

/// 单个字符格子 — 带识别状态、置信度边框、弹跳动画
/// v4.6.0: 长按弹出候选字面板
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

  /// v4.6.0: 精确置信度（0.0~1.0）
  final double? preciseConfidence;

  /// v4.6.0: 候选字列表（按得分降序）
  final List<String>? candidates;

  /// v4.6.0: 候选字选择回调
  final void Function(String)? onCandidateSelected;

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
    this.preciseConfidence,
    this.candidates,
    this.onCandidateSelected,
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
      onLongPress: () {
        // v4.6.0: 有候选字时弹出候选面板
        if (candidates != null && candidates!.length > 1) {
          _showCandidatePanel(context);
        } else {
          onLongPress();
        }
      },
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

              // v4.6.0: 精确置信度百分比（右上角，仅低/中置信度时显示）
              if (preciseConfidence != null &&
                  status == CellStatus.recognized &&
                  confidence != ConfidenceLevel.high)
                Positioned(
                  top: 1,
                  right: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${(preciseConfidence! * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 8,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

              // v4.6.0: 候选字数量指示（左下角，有多个候选时显示）
              if (candidates != null && candidates!.length > 1)
                Positioned(
                  bottom: 1,
                  left: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${candidates!.length}',
                      style: const TextStyle(
                        fontSize: 8,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// v4.6.0: 显示候选字面板
  void _showCandidatePanel(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.text_fields, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  '候选字 (共 ${candidates!.length} 个)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (preciseConfidence != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _confidenceColor(preciseConfidence!).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '置信度 ${(preciseConfidence! * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _confidenceColor(preciseConfidence!),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 候选字网格
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(candidates!.length, (i) {
                final isTop = i == 0;
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    onCandidateSelected?.call(candidates![i]);
                  },
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isTop
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isTop
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                        width: isTop ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          candidates![i],
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: isTop ? FontWeight.bold : FontWeight.normal,
                            color: isTop
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurface,
                          ),
                        ),
                        if (isTop)
                          Text(
                            '最佳',
                            style: TextStyle(
                              fontSize: 9,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 12),

            // 提示
            Text(
              '点击候选字可替换当前识别结果',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),

            // 安全区域底部间距
            SizedBox(height: MediaQuery.of(ctx).padding.bottom),
          ],
        ),
      ),
    );
  }

  /// 根据置信度返回颜色
  static Color _confidenceColor(double conf) {
    if (conf >= 0.8) return Colors.green;
    if (conf >= 0.6) return Colors.orange;
    return Colors.red;
  }
}
