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
  // 帮助系统状态
  bool _showHelpPanel = false;
  int _helpCategoryIndex = 0;
  String _helpSearchQuery = '';
  final TextEditingController _helpSearchController = TextEditingController();
  // 帮助反馈
  final List<Map<String, dynamic>> _helpFeedback = [];

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
    _helpSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: WFAppBar(
        title: widget.charset != null ? '标准字表匹配' : '调节参数',
        actions: [
          // 帮助按钮
          IconButton(
            onPressed: () => setState(() => _showHelpPanel = !_showHelpPanel),
            icon: Icon(
              _showHelpPanel ? Icons.help : Icons.help_outline,
              color: _showHelpPanel ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: '帮助文档',
          ),
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
      body: Stack(
        children: [
          isProcessing
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
                              preciseConfidence: cellResults[index]?.preciseConfidence,
                              candidates: cellResults[index]?.candidates,
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
                              onCandidateSelected: (selected) {
                                // v4.6.0: 候选字选择回调
                                setState(() {
                                  charAssignments[index] = selected;
                                  cellResults[index] = cellResults[index]?.copyWith(
                                    character: selected,
                                    confidence: ConfidenceLevel.medium,
                                  );
                                });
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
          // 帮助面板覆盖层
          if (_showHelpPanel) _buildHelpPanel(colorScheme),
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

  // ═══════════════════════════════════════════════════════════
  // 帮助系统
  // ═══════════════════════════════════════════════════════════

  /// 获取帮助分类列表
  List<Map<String, dynamic>> _getHelpCategories() {
    return [
      {
        'icon': Icons.tune,
        'title': '参数调节',
        'docs': [
          {'title': '阈值参数', 'content': '阈值控制字符识别的灵敏度。值越低，识别越宽松，可能识别更多字符但准确率下降；值越高，识别越严格，准确率更高但可能遗漏字符。建议从默认值0.5开始，根据识别效果微调。'},
          {'title': '对比度参数', 'content': '对比度增强字符边缘的清晰度。值越高，字符边缘越锐利，适合模糊或对比度低的图片。建议范围1.0-2.0。'},
          {'title': '平滑度参数', 'content': '平滑度控制轮廓的光滑程度。值越高，轮廓越平滑，适合手写不太工整的情况。过高可能丢失细节。'},
          {'title': '线宽参数', 'content': '线宽控制笔画的粗细。根据手写字体的实际笔画粗细调节，使生成的字体更接近原始手写效果。'},
        ],
      },
      {
        'icon': Icons.text_fields,
        'title': '字符识别',
        'docs': [
          {'title': '识别流程', 'content': '系统先将图片分割为单个字符区域，然后提取轮廓，最后进行字符匹配。整个过程自动完成，你只需调节参数优化效果。'},
          {'title': '识别结果颜色', 'content': '绿色表示高置信度识别，黄色表示需要确认，红色表示低置信度建议手动修改。'},
          {'title': '手动修改', 'content': '长按任意字符格子可打开编辑对话框，手动指定该字符对应的汉字。低置信度字符建议手动确认。'},
          {'title': '本地 vs 云端识别', 'content': '本地识别速度快、无需网络；云端识别准确率更高，适合复杂手写。可在设置中切换。'},
        ],
      },
      {
        'icon': Icons.grid_on,
        'title': '字表匹配',
        'docs': [
          {'title': '标准字表模式', 'content': '使用标准字表时，系统会将识别结果自动匹配到字表中的对应字符。字表模式下建议逐字拍摄，确保每个字符清晰。'},
          {'title': '自由模式', 'content': '自由模式不限制字符集，系统会自动识别所有可见字符。适合实验性创作或自定义字符集。'},
          {'title': '匹配率', 'content': '匹配率表示已识别字符占字表总字符数的比例。匹配率越高，生成的字体越完整。'},
        ],
      },
      {
        'icon': Icons.build,
        'title': '常见问题',
        'docs': [
          {'title': '识别不到字符怎么办？', 'content': '1. 降低阈值参数\n2. 增加对比度\n3. 确保图片清晰、光线充足\n4. 检查字符是否被正确裁剪'},
          {'title': '识别结果不准确？', 'content': '1. 提高阈值参数\n2. 使用更清晰的图片\n3. 手动修改错误的识别结果\n4. 尝试云端识别模式'},
          {'title': '如何获得最佳效果？', 'content': '1. 使用白色背景、黑色字体\n2. 光线均匀，避免阴影\n3. 每个字符独立拍摄\n4. 适当调节参数后微调'},
          {'title': '处理速度慢怎么办？', 'content': '1. 减少同时处理的图片数量\n2. 使用本地识别模式\n3. 关闭其他应用释放内存\n4. 耐心等待处理完成'},
        ],
      },
    ];
  }

  /// 获取过滤后的帮助文档
  List<Map<String, dynamic>> _getFilteredHelpDocs() {
    final categories = _getHelpCategories();
    if (_helpCategoryIndex >= categories.length) return [];
    final docs = categories[_helpCategoryIndex]['docs'] as List<Map<String, dynamic>>;
    if (_helpSearchQuery.isEmpty) return docs;
    return docs.where((doc) {
      final title = (doc['title'] as String).toLowerCase();
      final content = (doc['content'] as String).toLowerCase();
      final query = _helpSearchQuery.toLowerCase();
      return title.contains(query) || content.contains(query);
    }).toList();
  }

  /// 提交帮助反馈
  void _submitHelpFeedback(String docTitle, bool helpful) {
    _helpFeedback.add({
      'docTitle': docTitle,
      'helpful': helpful,
      'timestamp': DateTime.now().toIso8601String(),
    });
    WFSnackBar.show(context, helpful ? '感谢您的反馈！' : '我们会改进这篇文档');
  }

  /// 构建帮助面板
  Widget _buildHelpPanel(ColorScheme colorScheme) {
    final categories = _getHelpCategories();
    final filteredDocs = _getFilteredHelpDocs();

    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width > 600 ? 380 : MediaQuery.of(context).size.width * 0.85,
      child: Material(
        elevation: 12,
        child: Container(
          color: colorScheme.surface,
          child: Column(
            children: [
              // 帮助面板头部
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
                ),
                child: Row(
                  children: [
                    Icon(Icons.help_outline, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '帮助文档',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() => _showHelpPanel = false),
                    ),
                  ],
                ),
              ),
              // 搜索框
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _helpSearchController,
                  onChanged: (v) => setState(() => _helpSearchQuery = v.trim()),
                  decoration: InputDecoration(
                    hintText: '搜索帮助...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _helpSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _helpSearchController.clear();
                              setState(() => _helpSearchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              // 分类标签
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: categories.length,
                  itemBuilder: (ctx, i) {
                    final cat = categories[i];
                    final isActive = i == _helpCategoryIndex;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: Icon(cat['icon'] as IconData, size: 16),
                        label: Text(cat['title'] as String, style: const TextStyle(fontSize: 12)),
                        selected: isActive,
                        onSelected: (_) => setState(() {
                          _helpCategoryIndex = i;
                          _helpSearchQuery = '';
                          _helpSearchController.clear();
                        }),
                        selectedColor: colorScheme.primaryContainer,
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              // 帮助文档列表
              Expanded(
                child: filteredDocs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text(
                              '未找到相关帮助',
                              style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: filteredDocs.length,
                        itemBuilder: (ctx, i) {
                          final doc = filteredDocs[i];
                          return _buildHelpDocCard(doc, colorScheme);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建帮助文档卡片
  Widget _buildHelpDocCard(Map<String, dynamic> doc, ColorScheme colorScheme) {
    final title = doc['title'] as String;
    final content = doc['content'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(Icons.article_outlined, size: 20, color: colorScheme.primary),
        title: Text(
          title,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colorScheme.onSurface),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, height: 1.6),
                ),
                const SizedBox(height: 12),
                // 反馈按钮
                Row(
                  children: [
                    Text(
                      '这篇文档有帮助吗？',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.thumb_up_outlined, size: 16),
                      onPressed: () => _submitHelpFeedback(title, true),
                      tooltip: '有帮助',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.thumb_down_outlined, size: 16),
                      onPressed: () => _submitHelpFeedback(title, false),
                      tooltip: '需改进',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
