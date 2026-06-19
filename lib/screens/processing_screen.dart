import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'widgets/parameter_panel.dart';
import 'widgets/processing_stats_bar.dart';
import 'widgets/character_cell.dart';
import 'widgets/edit_character_dialog.dart';
import 'processing/cell_result.dart';
import 'processing/processing_logic.dart';
import 'processing/processing_widgets.dart';

// Re-export split modules so external imports remain valid
export 'processing/cell_result.dart';

class ProcessingScreen extends StatefulWidget {
  final List<Uint8List> sourceImages;
  final List<String>? charset; // 标准字表，null = 自由模式

  const ProcessingScreen({
    super.key,
    required this.sourceImages,
    this.charset,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with TickerProviderStateMixin, ProcessingLogic, ProcessingWidgets {
  @override
  void initState() {
    super.initState();
    celebrationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    celebrationAnimation = CurvedAnimation(
      parent: celebrationController!,
      curve: Curves.easeInOut,
    );
    // 添加识别完成监听：触发成功触觉反馈
    celebrationController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _playSuccessHaptic();
      }
    });
    loadParams().then((_) => processImages());
  }

  @override
  void dispose() {
    debounceTimer?.cancel();
    for (final c in bounceControllers.values) {
      c.dispose();
    }
    celebrationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: WFAppBar(
        title: widget.charset != null ? '标准字表匹配' : '调节参数',
        actions: [
          // 撤销/重做按钮
          IconButton(
            onPressed: canUndo ? undo : null,
            icon: const Icon(Icons.undo),
            tooltip: '撤销参数修改',
          ),
          IconButton(
            onPressed: canRedo ? redo : null,
            icon: const Icon(Icons.redo),
            tooltip: '重做参数修改',
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed('/ocr-settings').then((_) {
                recognitionService.clearCache();
                loadUseCloudSetting().then((_) {
                  if (processedCells.isNotEmpty) {
                    charAssignments.clear();
                    cellResults.clear();
                    recognizeCharacters(processedCells);
                  }
                });
              });
            },
            icon: const Icon(Icons.tune),
            label: const Text('识别'),
          ),
          TextButton.icon(
            onPressed: proceedToPreview,
            icon: const Icon(Icons.preview),
            label: const Text('预览'),
          ),
        ],
      ),
      body: isProcessing
          ? _buildProcessingFeedback(colorScheme)
          : Column(
              children: [
                // 参数面板
                ParameterPanel(
                  params: params,
                  onChanged: onParamsChanged,
                  presets: presetNames,
                  onPresetSelected: applyPreset,
                ),

                const Divider(height: 1),

                // 识别进度与统计栏
                ProcessingStatsBar(
                  charsetLength: widget.charset?.length,
                  matchedCount: charAssignments.length,
                  cellCount: processedCells.length,
                  isRecognizing: isRecognizing,
                  isProcessing: isProcessing,
                  recognizedCount: recognizedCount,
                  totalCount: totalCount,
                  useCloudRecognition: useCloudRecognition,
                  highConfidenceCount: highConfidenceCount,
                  needConfirmCount: needConfirmCount,
                  selectedCount: selectedCells.length,
                ),

                // 全选行
                if (processedCells.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          '识别到 ${processedCells.length} 个字符',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            _playSelectionHaptic(); // 全选触觉反馈
                            setState(() {
                              if (selectedCells.length == processedCells.length) {
                                selectedCells.clear();
                              } else {
                                selectedCells.addAll(
                                  List.generate(processedCells.length, (i) => i),
                                );
                              }
                            });
                          },
                          icon: Icon(
                            selectedCells.length == processedCells.length
                                ? Icons.deselect
                                : Icons.select_all,
                            size: 18,
                          ),
                          label: Text(
                            selectedCells.length == processedCells.length
                                ? '取消全选'
                                : '全选',
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 字符网格
                Expanded(
                  child: processedCells.isEmpty
                      ? _buildEmptyStateFeedback(colorScheme)
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: processedCells.length,
                          itemBuilder: (context, index) {
                            return CharacterCell(
                              index: index,
                              imageBytes: processedCells[index],
                              isSelected: selectedCells.contains(index),
                              assignedChar: charAssignments[index],
                              status: cellResults[index]?.status ?? CellStatus.pending,
                              confidence: cellResults[index]?.confidence ?? ConfidenceLevel.low,
                              bounceController: bounceControllers[index],
                              onTap: () {
                                _playSelectionHaptic(); // 选择触觉反馈
                                setState(() {
                                  if (selectedCells.contains(index)) {
                                    selectedCells.remove(index);
                                  } else {
                                    selectedCells.add(index);
                                  }
                                });
                              },
                              onLongPress: () {
                                _playHeavyHaptic(); // 长按重触反馈
                                showEditDialog(index);
                              },
                            );
                          },
                        ),
                ),

                // 底部统计 + 完成汇总 / 按钮
                buildBottomBar(
                  colorScheme: colorScheme,
                  showSummary: showSummary,
                  isRecognizing: isRecognizing,
                  isProcessing: isProcessing,
                  processedCells: processedCells,
                  totalCount: totalCount,
                  recognizedSuccessCount: recognizedSuccessCount,
                  needConfirmCount: needConfirmCount,
                  onProceedToEditor: proceedToEditor,
                  onProceedToPreview: proceedToPreview,
                ),
              ],
            ),
    );
  }

  /// 构建处理中的反馈界面（带动画和进度提示）
  Widget _buildProcessingFeedback(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 主加载动画（带脉冲效果）
          WFAnimations.pulse(
            child: SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 5,
                color: colorScheme.primary,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 处理状态文本
          Text(
            '正在处理图片...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          // 详细步骤提示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildProcessingStep(Icons.crop, '图片分割', true, colorScheme),
                const SizedBox(height: 8),
                _buildProcessingStep(Icons.auto_fix_high, '轮廓提取', false, colorScheme),
                const SizedBox(height: 8),
                _buildProcessingStep(Icons.text_fields, '字符识别', false, colorScheme),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '请稍候，正在分析您的手写字体...',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建处理步骤指示项
  Widget _buildProcessingStep(IconData icon, String label, bool isActive, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        if (isActive) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }

  /// 构建空状态反馈界面（带操作建议）
  Widget _buildEmptyStateFeedback(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 72,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 20),
            Text(
              '未识别到字符',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            // 操作建议卡片
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  _buildSuggestionItem(Icons.tune, '调整阈值参数', '降低阈值可能识别更多字符', colorScheme),
                  const Divider(height: 16),
                  _buildSuggestionItem(Icons.image, '使用更清晰的图片', '确保光线充足、字体清晰', colorScheme),
                  const Divider(height: 16),
                  _buildSuggestionItem(Icons.crop, '检查图片裁剪', '确保字符区域被正确裁剪', colorScheme),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // 操作反馈提示
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lightbulb_outline, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '提示：调整参数后系统会自动重新处理',
                    style: TextStyle(fontSize: 12, color: colorScheme.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建建议项
  Widget _buildSuggestionItem(IconData icon, String title, String subtitle, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.primary.withValues(alpha: 0.7)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colorScheme.onSurface)),
              Text(subtitle, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
            ],
          ),
        ),
      ],
    );
  }

  // ── 触觉反馈方法 ──

  /// 轻触反馈 — 用于普通点击、选择操作
  void _playLightHaptic() {
    HapticFeedback.lightImpact();
  }

  /// 重按反馈 — 用于长按、重要操作
  void _playHeavyHaptic() {
    HapticFeedback.heavyImpact();
  }

  /// 成功反馈 — 用于识别完成、操作成功
  void _playSuccessHaptic() {
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.mediumImpact();
    });
  }

  /// 错误反馈 — 用于识别失败、操作错误
  void _playErrorHaptic() {
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 80), () {
      HapticFeedback.heavyImpact();
    });
  }

  /// 选择反馈 — 用于切换选中状态
  void _playSelectionHaptic() {
    HapticFeedback.selectionClick();
  }

  /// 显示成功提示（触觉反馈 + 视觉提示）
  void _showSuccessFeedback(String message) {
    _playSuccessHaptic();
    WFSnackBar.show(context, message);
  }

  /// 显示失败提示（触觉反馈 + 错误提示）
  void _showFailureFeedback(String message) {
    _playErrorHaptic();
    WFSnackBar.error(context, message);
  }
}
