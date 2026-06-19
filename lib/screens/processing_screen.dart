import 'dart:typed_data';
import 'package:flutter/material.dart';
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
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    '正在处理图片...',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // 参数面板
                ParameterPanel(
                  params: params,
                  onChanged: onParamsChanged,
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
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '未识别到字符',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '请尝试调整阈值或选择更清晰的图片',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                                ),
                              ),
                            ],
                          ),
                        )
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
                                setState(() {
                                  if (selectedCells.contains(index)) {
                                    selectedCells.remove(index);
                                  } else {
                                    selectedCells.add(index);
                                  }
                                });
                              },
                              onLongPress: () => showEditDialog(index),
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
}
