import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/image_processor.dart';
import '../../theme/app_theme.dart';
import '../widgets/summary_panel.dart';
import 'cell_result.dart';

/// ProcessingScreen 的 Widget 构建方法集合
///
/// 这些方法通过顶级函数实现，接收所有需要的参数。
mixin ProcessingWidgets {
  /// 识别进度与置信度统计栏
  Widget buildStatsBar({
    required ColorScheme colorScheme,
    required int? charsetLength,
    required int matchCount,
    required int cellCount,
    required bool isRecognizing,
    required bool isProcessing,
    required int recognizedCount,
    required int totalCount,
    required bool useCloudRecognition,
    required int highConfidenceCount,
    required int needConfirmCount,
    required int selectedCount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surfaceVariant.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.grid_view, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          if (charsetLength != null)
            Text(
              '已匹配 $matchCount/$charsetLength',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Text(
              '识别到 $cellCount 个字符',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (isRecognizing) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'AI识别中 $recognizedCount/$totalCount',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
              ),
            ),
          ] else if (!isProcessing) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_circle, size: 14, color: colorScheme.primary),
            const SizedBox(width: 2),
            Text(
              useCloudRecognition ? '云端识别' : '本地识别',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
              ),
            ),
          ],
          const Spacer(),
          // 置信度统计
          if (!isRecognizing) ...[
            buildConfidenceChip('🟢 高', highConfidenceCount, Colors.green, colorScheme),
            const SizedBox(width: 4),
            buildConfidenceChip('🟡 中', needConfirmCount, Colors.orange, colorScheme),
          ],
          if (selectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '已选 $selectedCount 个',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildConfidenceChip(String label, int count, Color color, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 底部区域：完成汇总或操作按钮
  Widget buildBottomBar({
    required ColorScheme colorScheme,
    required bool showSummary,
    required bool isRecognizing,
    required bool isProcessing,
    required List<Uint8List> processedCells,
    required int totalCount,
    required int recognizedSuccessCount,
    required int needConfirmCount,
    required VoidCallback onProceedToEditor,
    required VoidCallback onProceedToPreview,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: showSummary && !isRecognizing
            ? SummaryPanel(
                totalCount: totalCount,
                recognizedSuccessCount: recognizedSuccessCount,
                needConfirmCount: needConfirmCount,
                onCheckEach: onProceedToEditor,
                onContinue: onProceedToPreview,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: processedCells.isNotEmpty && !isRecognizing
                        ? onProceedToPreview
                        : null,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(isRecognizing ? '识别中...' : '生成字体预览'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  /// 完成汇总面板
  Widget buildSummaryPanel({
    required ColorScheme colorScheme,
    required int totalCount,
    required int recognizedSuccessCount,
    required int needConfirmCount,
    required VoidCallback onProceedToEditor,
    required VoidCallback onProceedToPreview,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 汇总标题
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.celebration, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '全部完成！',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 统计数据
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              buildSummaryItem('总字符', totalCount, colorScheme.onSurface),
              const SizedBox(width: 16),
              buildSummaryItem('识别成功', recognizedSuccessCount, Colors.green),
              const SizedBox(width: 16),
              buildSummaryItem('需确认', needConfirmCount, Colors.orange),
            ],
          ),
          const SizedBox(height: 12),
          // 两个按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onProceedToEditor,
                  icon: const Icon(Icons.checklist, size: 18),
                  label: const Text('逐个检查'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onProceedToPreview,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('全部正确，继续'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildSummaryItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget buildParameterPanel({
    required ColorScheme colorScheme,
    required ProcessingParams params,
    required ValueChanged<ProcessingParams> onParamsChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with reset button
          Row(
            children: [
              Text(
                '参数调节',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '（推荐值）',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => onParamsChanged(ProcessingParams()),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('恢复默认'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Threshold
          buildSlider(
            label: '阈值',
            value: params.threshold,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            icon: Icons.contrast,
            colorScheme: colorScheme,
            onChanged: (v) => onParamsChanged(params.copyWith(threshold: v)),
          ),
          const SizedBox(height: 8),

          // Two sliders in a row
          Row(
            children: [
              Expanded(
                child: buildSlider(
                  label: '腐蚀',
                  value: params.erosion.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  icon: Icons.remove_circle_outline,
                  colorScheme: colorScheme,
                  onChanged: (v) => onParamsChanged(params.copyWith(erosion: v.round())),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: buildSlider(
                  label: '膨胀',
                  value: params.dilation.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  icon: Icons.add_circle_outline,
                  colorScheme: colorScheme,
                  onChanged: (v) => onParamsChanged(params.copyWith(dilation: v.round())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Smoothing and contrast
          Row(
            children: [
              Expanded(
                child: buildSlider(
                  label: '平滑度',
                  value: params.smoothness,
                  min: 0.0,
                  max: 1.0,
                  icon: Icons.blur_on,
                  colorScheme: colorScheme,
                  onChanged: (v) => onParamsChanged(params.copyWith(smoothness: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: buildSlider(
                  label: '对比度',
                  value: params.contrast,
                  min: 0.5,
                  max: 3.0,
                  icon: Icons.brightness_6,
                  colorScheme: colorScheme,
                  onChanged: (v) => onParamsChanged(params.copyWith(contrast: v)),
                ),
              ),
            ],
          ),

          // Invert toggle
          Row(
            children: [
              Icon(Icons.swap_horiz, size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('反转颜色', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
              const Spacer(),
              Switch(
                value: params.invertColors,
                onChanged: (v) => onParamsChanged(params.copyWith(invertColors: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required IconData icon,
    required ColorScheme colorScheme,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// 构建单个字符格子（带识别状态、置信度边框、动画）
  Widget buildCharacterCell({
    required int index,
    required ColorScheme colorScheme,
    required List<Uint8List> processedCells,
    required Set<int> selectedCells,
    required Map<int, String> charAssignments,
    required Map<int, CellResult> cellResults,
    required Map<int, AnimationController> bounceControllers,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    final isSelected = selectedCells.contains(index);
    final assignedChar = charAssignments[index];
    final result = cellResults[index];
    final status = result?.status ?? CellStatus.pending;
    final confidence = result?.confidence ?? ConfidenceLevel.low;

    // 弹跳动画缩放值
    double scale = 1.0;
    final bounceController = bounceControllers[index];
    if (bounceController != null && bounceController.isAnimating) {
      scale = 1.0 + 0.15 * sin(bounceController.value * pi);
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
                  processedCells[index],
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
                      assignedChar,
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
