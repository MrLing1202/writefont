import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/image_processor.dart';
import '../services/storage_service.dart';
import '../services/recognition_service.dart';
import '../data/standard_charset.dart';

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

class _ProcessingScreenState extends State<ProcessingScreen> {
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

  // Character assignment
  final List<String> _defaultCharacters = _getDefaultChars();
  final Map<int, String> _charAssignments = {};

  static List<String> _getDefaultChars() {
    final chars = <String>[];
    // Common Chinese characters + ASCII
    for (int i = 0x4E00; i <= 0x4E3F; i++) {
      chars.add(String.fromCharCode(i));
    }
    // Add some common ASCII
    for (int c = 0x21; c <= 0x7E; c++) {
      chars.add(String.fromCharCode(c));
    }
    return chars;
  }

  @override
  void initState() {
    super.initState();
    _params = ProcessingParams();
    _loadUseCloudSetting();
    _processImages();
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
    setState(() => _isProcessing = true);

    Future.microtask(() async {
      final allCells = <Uint8List>[];
      for (final img in widget.sourceImages) {
        final cells = ImageProcessor.segmentCharacters(img, _params);
        allCells.addAll(cells);
      }

      if (mounted) {
        setState(() {
          _processedCells = allCells;
          _isProcessing = false;
        });
      }

      // Try AI recognition
      await _recognizeCharacters(allCells);
    });
  }

  Future<void> _recognizeCharacters(List<Uint8List> cells) async {
    if (cells.isEmpty) return;

    final charset = widget.charset;
    final useStandardCharset = charset != null && charset.isNotEmpty;

    if (mounted) {
      setState(() {
        _isRecognizing = true;
        _recognizedCount = 0;
        _totalCount = cells.length;
      });
    }

    bool anyRecognized = false;

    // 带进度回调的批量识别
    final batchResults = await _recognitionService.recognizeBatch(
      cells,
      onProgress: (completed, total) {
        if (mounted) {
          setState(() => _recognizedCount = completed);
        }
      },
    );

    for (int i = 0; i < batchResults.length; i++) {
      if (batchResults[i] != null) {
        _charAssignments[i] = batchResults[i]!;
        anyRecognized = true;
      }
    }

    // 标准字表模式：用字表顺序补齐未识别的格子
    if (useStandardCharset) {
      for (int i = 0; i < cells.length; i++) {
        if (!_charAssignments.containsKey(i)) {
          if (i < charset.length) {
            _charAssignments[i] = charset[i];
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

    if (mounted) {
      setState(() => _isRecognizing = false);
    }
  }

  void _assignFallbackCharacters(int count) {
    for (int i = 0; i < count && i < _defaultCharacters.length; i++) {
      _charAssignments[i] = _defaultCharacters[i];
    }
  }

  void _onParamsChanged(ProcessingParams newParams) {
    setState(() {
      _params = newParams;
    });
    // Debounce: 只在用户停止拖动 500ms 后才触发处理
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _processImages();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _proceedToPreview() {
    if (_processedCells.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有识别到字符，请调整参数后重试')),
      );
      return;
    }

    // Build glyphs from processed cells
    final project = FontProject(
      id: StorageService.generateId(),
      name: '我的手写字体',
      params: _params,
    );

    for (int i = 0; i < _processedCells.length; i++) {
      final char = _charAssignments[i];
      if (char == null) continue;

      final contours = ImageProcessor.extractContours(
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
                // 从 OCR 设置页返回时，重新读取识别模式设置
                _recognitionService.clearCache();
                _loadUseCloudSetting();
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
                // Parameter panel
                _buildParameterPanel(colorScheme),

                const Divider(height: 1),

                // Stats bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: colorScheme.surfaceVariant.withOpacity(0.3),
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
                      ] else ...[
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
                      if (_selectedCells.isNotEmpty)
                        Text(
                          '已选 ${_selectedCells.length} 个',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),

                // Select all row
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

                // Character grid
                Expanded(
                  child: _processedCells.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '未识别到字符',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '请尝试调整阈值或选择更清晰的图片',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
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

                // Bottom button
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _processedCells.isNotEmpty ? _proceedToPreview : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('生成字体预览'),
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
              ],
            ),
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

  Widget _buildCharacterCell(int index, ColorScheme colorScheme) {
    final isSelected = _selectedCells.contains(index);
    final assignedChar = _charAssignments[index];

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedCells.remove(index);
          } else {
            _selectedCells.add(index);
          }
        });
      },
      onLongPress: () => _editCharacter(index),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? colorScheme.primaryContainer.withOpacity(0.3) : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Character image
            Padding(
              padding: const EdgeInsets.all(4),
              child: Image.memory(
                _processedCells[index],
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
            // Character label
            if (assignedChar != null)
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    assignedChar,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _editCharacter(int index) {
    final controller = TextEditingController(text: _charAssignments[index] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑字符'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 1,
          decoration: const InputDecoration(
            labelText: '输入对应字符',
            hintText: '例如: 我',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                if (controller.text.isNotEmpty) {
                  _charAssignments[index] = controller.text;
                }
              });
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
