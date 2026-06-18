import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/image_processor.dart';
import '../services/storage_service.dart';
import '../services/recognition_service.dart';
import '../services/app_config_service.dart';

/// 字符识别状态
enum CellStatus { pending, recognizing, recognized, failed }

/// 单个字符的识别结果
class CellResult {
  final String? character; // 识别结果，null = 未识别
  final CellStatus status;
  /// 置信度：high（与目标匹配）、medium（识别到但不匹配）、low（未识别）
  final ConfidenceLevel confidence;

  const CellResult({
    this.character,
    this.status = CellStatus.pending,
    this.confidence = ConfidenceLevel.low,
  });

  CellResult copyWith({String? character, CellStatus? status, ConfidenceLevel? confidence}) {
    return CellResult(
      character: character ?? this.character,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
    );
  }
}

enum ConfidenceLevel { high, medium, low }

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

class _ProcessingScreenState extends State<ProcessingScreen> with TickerProviderStateMixin {
  late ProcessingParams _params;
  List<Uint8List> _processedCells = [];
  bool _isProcessing = true;
  final Set<int> _selectedCells = {};
  Timer? _debounceTimer;

  // AI recognition
  final RecognitionService _recognitionService = RecognitionService.instance;
  bool _isRecognizing = false;
  int _recognizedCount = 0;
  int _totalCount = 0;
  bool _useCloudRecognition = false;

  // 逐字识别结果
  final Map<int, CellResult> _cellResults = {};

  // 动画：每个格子完成时的弹跳动画
  final Map<int, AnimationController> _bounceControllers = {};

  // 全部完成的庆祝动画
  AnimationController? _celebrationController;
  late Animation<double> _celebrationAnimation;

  // 是否显示完成汇总
  bool _showSummary = false;

  // 任务代数计数器，用于取消过期的异步任务
  int _generation = 0;

  // Character assignment
  final List<String> _defaultCharacters = _getDefaultChars();
  final Map<int, String> _charAssignments = {};

  static List<String> _getDefaultChars() {
    final chars = <String>[];
    for (int i = 0x4E00; i <= 0x4E3F; i++) {
      chars.add(String.fromCharCode(i));
    }
    for (int c = 0x21; c <= 0x7E; c++) {
      chars.add(String.fromCharCode(c));
    }
    return chars;
  }

  @override
  void initState() {
    super.initState();
    _celebrationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _celebrationAnimation = CurvedAnimation(
      parent: _celebrationController!,
      curve: Curves.easeInOut,
    );
    _loadParams().then((_) => _processImages());
  }

  Future<void> _loadParams() async {
    final config = AppConfigService.instance;
    _params = ProcessingParams(
      threshold: await config.getThreshold(),
      contrast: await config.getContrast(),
      smoothness: await config.getSmoothness(),
      strokeWidth: await config.getStrokeWidth(),
    );
    _loadUseCloudSetting();
  }

  /// 读取 OCR 识别模式设置
  Future<void> _loadUseCloudSetting() async {
    final useCloud = await _recognitionService.getUseCloud();
    if (mounted) {
      setState(() => _useCloudRecognition = useCloud);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  void _processImages() {
    final gen = ++_generation; // 递增代数，取消旧任务
    setState(() => _isProcessing = true);

    Future.microtask(() async {
      final allCells = <Uint8List>[];
      for (final img in widget.sourceImages) {
        final cells = ImageProcessor.segmentCharacters(img, _params);
        allCells.addAll(cells);
      }

      // 代数不匹配，旧任务已过期
      if (!mounted || _generation != gen) return;

      setState(() {
        _processedCells = allCells;
        _isProcessing = false;
        // 初始化所有格子为 pending 状态
        _cellResults.clear();
        for (int i = 0; i < allCells.length; i++) {
          _cellResults[i] = const CellResult(status: CellStatus.pending);
        }
        _showSummary = false;
      });

      // 逐个识别字符
      await _recognizeCharacters(allCells, gen);
    });
  }

  /// 根据识别结果和目标字符计算置信度
  ConfidenceLevel _calcConfidence(int index, String? recognized) {
    if (recognized == null) return ConfidenceLevel.low;
    final charset = widget.charset;
    if (charset != null && charset.isNotEmpty && index < charset.length) {
      // 标准字表模式：比较识别结果与目标字符
      if (recognized == charset[index]) return ConfidenceLevel.high;
      return ConfidenceLevel.medium; // 识别到文字但不匹配
    }
    // 自由模式：只要识别到就算中等置信度
    return ConfidenceLevel.medium;
  }

  Future<void> _recognizeCharacters(List<Uint8List> cells, [int? gen]) async {
    if (cells.isEmpty) return;
    if (gen != null && _generation != gen) return; // 代数不匹配，取消

    final charset = widget.charset;
    final useStandardCharset = charset != null && charset.isNotEmpty;

    if (mounted) {
      setState(() {
        _isRecognizing = true;
        _recognizedCount = 0;
        _totalCount = cells.length;
        _showSummary = false;
      });
    }

    // 逐个识别，带并发控制，每完成一个就更新 UI
    const maxConcurrent = 3;
    final semaphore = _Semaphore(maxConcurrent);
    bool anyRecognized = false;
    int completed = 0;

    final futures = <Future>[];
    for (int i = 0; i < cells.length; i++) {
      futures.add(() async {
        await semaphore.acquire();
        try {
          // 代数不匹配，跳过
          if (gen != null && _generation != gen) return;

          if (mounted) {
            setState(() {
              _cellResults[i] = const CellResult(status: CellStatus.recognizing);
            });
          }

          String? result;
          try {
            result = await _recognitionService.recognizeCharacter(cells[i]);
          } catch (_) {
            result = null;
          }

          // 代数不匹配，丢弃结果
          if (gen != null && _generation != gen) return;

          final confidence = _calcConfidence(i, result);
          final status = result != null ? CellStatus.recognized : CellStatus.failed;

          if (mounted && (gen == null || _generation == gen)) {
            setState(() {
              if (result != null) {
                _charAssignments[i] = result;
                anyRecognized = true;
              }
              _cellResults[i] = CellResult(
                character: result,
                status: status,
                confidence: confidence,
              );
              completed++;
              _recognizedCount = completed;
            });
          }

          // 触发弹跳动画
          if (gen == null || _generation == gen) {
            _triggerBounce(i);
          }
        } finally {
          semaphore.release();
        }
      }());
    }

    await Future.wait(futures);

    // 代数不匹配，取消后续逻辑
    if (gen != null && _generation != gen) return;

    // 标准字表模式：用字表顺序补齐未识别的格子
    if (useStandardCharset) {
      for (int i = 0; i < cells.length; i++) {
        if (!_charAssignments.containsKey(i)) {
          if (i < charset.length) {
            _charAssignments[i] = charset[i];
            _cellResults[i] = CellResult(
              character: charset[i],
              status: CellStatus.recognized,
              confidence: ConfidenceLevel.low, // 字表补齐，非实际识别
            );
          }
        }
      }
    } else {
      // 自由模式：如果识别失败，用默认字符凑数
      if (!anyRecognized) {
        _assignFallbackCharacters(cells.length);
      } else {
        int fallbackIndex = 0;
        for (int i = 0; i < cells.length; i++) {
          if (!_charAssignments.containsKey(i)) {
            while (fallbackIndex < _defaultCharacters.length &&
                _charAssignments.containsValue(_defaultCharacters[fallbackIndex])) {
              fallbackIndex++;
            }
            if (fallbackIndex < _defaultCharacters.length) {
              _charAssignments[i] = _defaultCharacters[fallbackIndex];
              fallbackIndex++;
            }
          }
        }
      }
    }

    // 最终检查代数
    if (gen != null && _generation != gen) return;

    if (mounted) {
      setState(() {
        _isRecognizing = false;
        _showSummary = true;
      });
      _celebrationController?.forward(from: 0);
    }
  }

  void _assignFallbackCharacters(int count) {
    for (int i = 0; i < count && i < _defaultCharacters.length; i++) {
      _charAssignments[i] = _defaultCharacters[i];
    }
  }

  /// 触发格子弹跳动画
  void _triggerBounce(int index) {
    _bounceControllers[index]?.dispose();
    final controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _bounceControllers[index] = controller;
    // AnimatedBuilder 会监听 controller 并局部刷新对应格子，无需全局 setState
    controller.forward();
  }

  void _onParamsChanged(ProcessingParams newParams) {
    setState(() {
      _params = newParams;
    });
    final config = AppConfigService.instance;
    config.setThreshold(newParams.threshold);
    config.setContrast(newParams.contrast);
    config.setSmoothness(newParams.smoothness);
    config.setStrokeWidth(newParams.strokeWidth);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _processImages();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    for (final c in _bounceControllers.values) {
      c.dispose();
    }
    _celebrationController?.dispose();
    super.dispose();
  }

  Future<void> _proceedToPreview() async {
    if (_processedCells.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有识别到字符，请调整参数后重试')),
      );
      return;
    }

    final project = FontProject(
      id: StorageService.generateId(),
      name: '我的手写字体',
      params: _params,
    );

    for (int i = 0; i < _processedCells.length; i++) {
      final char = _charAssignments[i];
      if (char == null) continue;

      final contours = await ImageProcessor.extractContours(
        _processedCells[i],
        _params,
      );

      project.glyphs[char] = GlyphData(
        character: char,
        unicode: char.codeUnitAt(0),
        contours: contours,
        advanceWidth: 500,
      );
    }

    Navigator.of(context).pushNamed('/preview', arguments: {'project': project});
  }

  /// 跳转到字符编辑器，从第一个需确认的字符开始
  void _proceedToEditor() {
    // 找到第一个需确认（低置信度或失败）的字符索引
    int startIndex = 0;
    for (int i = 0; i < _processedCells.length; i++) {
      final result = _cellResults[i];
      if (result != null && result.confidence != ConfidenceLevel.high) {
        startIndex = i;
        break;
      }
    }
    _proceedToPreview(); // 暂时直接跳转预览，后续可改为跳转到编辑器指定位置
  }

  /// 统计信息
  int get _highConfidenceCount =>
      _cellResults.values.where((r) => r.confidence == ConfidenceLevel.high).length;
  int get _needConfirmCount =>
      _cellResults.values.where((r) => r.confidence != ConfidenceLevel.high).length;
  int get _recognizedSuccessCount =>
      _cellResults.values.where((r) => r.status == CellStatus.recognized).length;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.charset != null ? '标准字表匹配' : '调节参数'),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed('/ocr-settings').then((_) {
                _recognitionService.clearCache();
                _loadUseCloudSetting().then((_) {
                  if (_processedCells.isNotEmpty) {
                    _charAssignments.clear();
                    _cellResults.clear();
                    _recognizeCharacters(_processedCells);
                  }
                });
              });
            },
            icon: const Icon(Icons.tune),
            label: const Text('识别'),
          ),
          TextButton.icon(
            onPressed: _proceedToPreview,
            icon: const Icon(Icons.preview),
            label: const Text('预览'),
          ),
        ],
      ),
      body: _isProcessing
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
                _buildParameterPanel(colorScheme),

                const Divider(height: 1),

                // 识别进度与统计栏
                _buildStatsBar(colorScheme),

                // 全选行
                if (_processedCells.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          '识别到 ${_processedCells.length} 个字符',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              if (_selectedCells.length == _processedCells.length) {
                                _selectedCells.clear();
                              } else {
                                _selectedCells.addAll(
                                  List.generate(_processedCells.length, (i) => i),
                                );
                              }
                            });
                          },
                          icon: Icon(
                            _selectedCells.length == _processedCells.length
                                ? Icons.deselect
                                : Icons.select_all,
                            size: 18,
                          ),
                          label: Text(
                            _selectedCells.length == _processedCells.length
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
                  child: _processedCells.isEmpty
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
                          itemCount: _processedCells.length,
                          itemBuilder: (context, index) {
                            return _buildCharacterCell(index, colorScheme);
                          },
                        ),
                ),

                // 底部统计 + 完成汇总 / 按钮
                _buildBottomSection(colorScheme),
              ],
            ),
    );
  }

  /// 识别进度与置信度统计栏
  Widget _buildStatsBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surfaceVariant.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.grid_view, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          if (widget.charset != null)
            Text(
              '已匹配 ${_charAssignments.length}/${widget.charset!.length}',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Text(
              '识别到 ${_processedCells.length} 个字符',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (_isRecognizing) ...[
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
              'AI识别中 $_recognizedCount/$_totalCount',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
              ),
            ),
          ] else if (!_isProcessing) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_circle, size: 14, color: colorScheme.primary),
            const SizedBox(width: 2),
            Text(
              _useCloudRecognition ? '云端识别' : '本地识别',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
              ),
            ),
          ],
          const Spacer(),
          // 置信度统计
          if (!_isRecognizing && _cellResults.isNotEmpty) ...[
            _buildConfidenceChip('🟢 高', _highConfidenceCount, Colors.green, colorScheme),
            const SizedBox(width: 4),
            _buildConfidenceChip('🟡 中', _needConfirmCount, Colors.orange, colorScheme),
          ],
          if (_selectedCells.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '已选 ${_selectedCells.length} 个',
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

  Widget _buildConfidenceChip(String label, int count, Color color, ColorScheme colorScheme) {
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
  Widget _buildBottomSection(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: _celebrationAnimation,
      builder: (context, child) {
        // 庆祝渐变色
        final celebrationColor = _showSummary
            ? Color.lerp(
                colorScheme.primaryContainer,
                colorScheme.tertiaryContainer,
                _celebrationAnimation.value,
              )
            : null;

        return Container(
          decoration: BoxDecoration(
            color: celebrationColor ?? colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: _showSummary && !_isRecognizing
                ? _buildSummaryPanel(colorScheme)
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _processedCells.isNotEmpty && !_isRecognizing
                            ? _proceedToPreview
                            : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(_isRecognizing ? '识别中...' : '生成字体预览'),
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
      },
    );
  }

  /// 完成汇总面板
  Widget _buildSummaryPanel(ColorScheme colorScheme) {
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
              _buildSummaryItem('总字符', _totalCount, colorScheme.onSurface),
              const SizedBox(width: 16),
              _buildSummaryItem('识别成功', _recognizedSuccessCount, Colors.green),
              const SizedBox(width: 16),
              _buildSummaryItem('需确认', _needConfirmCount, Colors.orange),
            ],
          ),
          const SizedBox(height: 12),
          // 两个按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _proceedToEditor,
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
                  onPressed: _proceedToPreview,
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

  Widget _buildSummaryItem(String label, int count, Color color) {
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

  Widget _buildParameterPanel(ColorScheme colorScheme) {
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
                onPressed: () => _onParamsChanged(ProcessingParams()),
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
          _buildSlider(
            label: '阈值',
            value: _params.threshold,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            icon: Icons.contrast,
            colorScheme: colorScheme,
            onChanged: (v) => _onParamsChanged(_params.copyWith(threshold: v)),
          ),
          const SizedBox(height: 8),

          // Two sliders in a row
          Row(
            children: [
              Expanded(
                child: _buildSlider(
                  label: '腐蚀',
                  value: _params.erosion.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  icon: Icons.remove_circle_outline,
                  colorScheme: colorScheme,
                  onChanged: (v) => _onParamsChanged(_params.copyWith(erosion: v.round())),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSlider(
                  label: '膨胀',
                  value: _params.dilation.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  icon: Icons.add_circle_outline,
                  colorScheme: colorScheme,
                  onChanged: (v) => _onParamsChanged(_params.copyWith(dilation: v.round())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Smoothing and contrast
          Row(
            children: [
              Expanded(
                child: _buildSlider(
                  label: '平滑度',
                  value: _params.smoothness,
                  min: 0.0,
                  max: 1.0,
                  icon: Icons.blur_on,
                  colorScheme: colorScheme,
                  onChanged: (v) => _onParamsChanged(_params.copyWith(smoothness: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSlider(
                  label: '对比度',
                  value: _params.contrast,
                  min: 0.5,
                  max: 3.0,
                  icon: Icons.brightness_6,
                  colorScheme: colorScheme,
                  onChanged: (v) => _onParamsChanged(_params.copyWith(contrast: v)),
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
                value: _params.invertColors,
                onChanged: (v) => _onParamsChanged(_params.copyWith(invertColors: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
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
  Widget _buildCharacterCell(int index, ColorScheme colorScheme) {
    final isSelected = _selectedCells.contains(index);
    final assignedChar = _charAssignments[index];
    final result = _cellResults[index];
    final status = result?.status ?? CellStatus.pending;
    final confidence = result?.confidence ?? ConfidenceLevel.low;

    // 弹跳动画缩放值
    double scale = 1.0;
    final bounceController = _bounceControllers[index];
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
      onTap: () {
        // 点击：选中/取消选中
        setState(() {
          if (isSelected) {
            _selectedCells.remove(index);
          } else {
            _selectedCells.add(index);
          }
        });
      },
      onLongPress: () => _showEditDialog(index),
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
                  _processedCells[index],
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

  /// 弹出编辑对话框（带图片预览）
  void _showEditDialog(int index) {
    final controller = TextEditingController(text: _charAssignments[index] ?? '');
    final result = _cellResults[index];
    final confidence = result?.confidence ?? ConfidenceLevel.low;

    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              const Text('修正字符'),
              const Spacer(),
              // 置信度指示
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: confidence == ConfidenceLevel.high
                      ? Colors.green.withValues(alpha: 0.1)
                      : confidence == ConfidenceLevel.medium
                          ? Colors.orange.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: confidence == ConfidenceLevel.high
                        ? Colors.green
                        : confidence == ConfidenceLevel.medium
                            ? Colors.orange
                            : Colors.red,
                  ),
                ),
                child: Text(
                  confidence == ConfidenceLevel.high
                      ? '高置信'
                      : confidence == ConfidenceLevel.medium
                          ? '中置信'
                          : '低置信',
                  style: TextStyle(
                    fontSize: 12,
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 原始裁切图片
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _processedCells[index],
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 编辑输入框
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 1,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: '识别结果',
                  hintText: '输入对应字符',
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            // 跳过按钮
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('跳过'),
            ),
            // 正确按钮（确认当前识别结果）
            if (_charAssignments[index] != null)
              FilledButton.tonal(
                onPressed: () {
                  // 标记为高置信度
                  setState(() {
                    _cellResults[index] = CellResult(
                      character: _charAssignments[index],
                      status: CellStatus.recognized,
                      confidence: ConfidenceLevel.high,
                    );
                  });
                  Navigator.pop(context);
                },
                child: const Text('正确'),
              ),
            // 确认修正
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  setState(() {
                    _charAssignments[index] = text;
                    _cellResults[index] = CellResult(
                      character: text,
                      status: CellStatus.recognized,
                      confidence: ConfidenceLevel.high, // 用户手动修正 = 高置信
                    );
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }
}

/// 简单的信号量实现，用于并发控制
class _Semaphore {
  final int _maxCount;
  int _currentCount;
  final List<Completer<void>> _waiters = [];

  _Semaphore(this._maxCount) : _currentCount = _maxCount;

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _currentCount++;
    }
  }
}
