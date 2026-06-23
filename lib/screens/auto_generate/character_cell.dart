import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/image_analyzer.dart';

/// 单个字符格子 — 显示字符图片、识别结果标签、状态图标、置信度
///
/// v5.1.0: 新增 Top-3 候选展示、置信度颜色编码（绿>90%、黄70-90%、红<70%）、
/// 长按弹出候选选择菜单
class CharacterCell extends StatelessWidget {
  final Uint8List cellImageBytes;
  final String char;
  final bool isRecognized;
  final bool isEdited;
  final bool isFailed;
  final bool isGenerating;
  final int index;
  final double confidence;
  final ImageFeatures? imageFeatures;
  /// v5.1.0: Top-N 候选字符列表
  final List<String> topCandidates;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;
  /// v5.1.0: 选择候选字符的回调
  final void Function(String candidate)? onSelectCandidate;

  const CharacterCell({
    super.key,
    required this.cellImageBytes,
    required this.char,
    required this.isRecognized,
    required this.isEdited,
    required this.isFailed,
    required this.isGenerating,
    required this.index,
    this.confidence = 0.7,
    this.imageFeatures,
    this.topCandidates = const [],
    this.onTap,
    this.onRetry,
    this.onSelectCandidate,
  });

  /// 置信度背景色 — 热力图效果
  /// v5.1.0: 三色编码 — 绿色 >90%、黄色 70-90%、红色 <70%
  Color _confidenceBg(ColorScheme cs) {
    if (confidence >= 0.9) return Color.lerp(cs.surface, Colors.green.shade50, 0.6)!;
    if (confidence >= 0.7) return Color.lerp(cs.surface, Colors.amber.shade50, 0.5)!;
    return Color.lerp(cs.surface, Colors.red.shade50, 0.5)!;
  }

  /// v5.1.0: 根据置信度返回对应颜色（三色编码）
  Color get _confidenceColor {
    if (confidence >= 0.9) return Colors.green.shade600;
    if (confidence >= 0.7) return Colors.amber.shade700;
    return Colors.red.shade500;
  }

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
      // v5.1.0: 长按弹出候选选择菜单
      onLongPress: isGenerating || topCandidates.length < 2
          ? null
          : () => _showCandidateMenu(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1.5),
          color: _confidenceBg(Theme.of(context).colorScheme),
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

            // 图像质量指示器
            if (imageFeatures != null)
              Positioned(
                top: 2,
                right: 2,
                child: Text(
                  imageFeatures!.qualityEmoji,
                  style: const TextStyle(fontSize: 10),
                ),
              ),

            // 识别结果标签（底部居中）+ 置信度指示 + 候选提示
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.only(top: 2, bottom: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                  border: Border(
                    top: BorderSide(color: borderColor.withValues(alpha: 0.3)),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 主识别结果
                    Text(
                      char,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    // v5.1.0: 置信度指示：彩色条 + 百分比
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 置信度条
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _confidenceColor,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${(confidence * 100).round()}%',
                          style: TextStyle(
                            fontSize: 8,
                            color: _confidenceColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        // v5.1.0: 候选数指示（有多个候选时显示）
                        if (topCandidates.length > 1) ...[
                          const SizedBox(width: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '${topCandidates.length}',
                              style: TextStyle(
                                fontSize: 7,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
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

  /// v5.1.0: 长按弹出候选选择菜单
  void _showCandidateMenu(BuildContext context) {
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fill,
      items: [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            '选择正确的字符',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ...topCandidates.map((candidate) => PopupMenuItem<String>(
              value: candidate,
              child: Row(
                children: [
                  Text(
                    candidate,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: candidate == char
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: candidate == char
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  if (candidate == char) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.check,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ],
              ),
            )),
      ],
    ).then((selected) {
      if (selected != null && selected != char && onSelectCandidate != null) {
        onSelectCandidate!(selected);
      }
    });
  }
}
