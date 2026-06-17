import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/image_processor.dart';
import '../services/storage_service.dart';

class ProcessingScreen extends StatefulWidget {
  final List<Uint8List> sourceImages;

  const ProcessingScreen({super.key, required this.sourceImages});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  late ProcessingParams _params;
  List<Uint8List> _processedCells = [];
  bool _isProcessing = true;
  int _selectedCellIndex = -1;

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
    _processImages();
  }

  void _processImages() {
    setState(() => _isProcessing = true);

    Future.microtask(() {
      final allCells = <Uint8List>[];
      for (final img in widget.sourceImages) {
        final cells = ImageProcessor.segmentCharacters(img, _params);
        allCells.addAll(cells);
      }

      // Auto-assign characters
      for (int i = 0; i < allCells.length && i < _defaultCharacters.length; i++) {
        _charAssignments[i] = _defaultCharacters[i];
      }

      if (mounted) {
        setState(() {
          _processedCells = allCells;
          _isProcessing = false;
        });
      }
    });
  }

  void _onParamsChanged(ProcessingParams newParams) {
    setState(() {
      _params = newParams;
    });
    _processImages();
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
        title: const Text('调节参数'),
        actions: [
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
                      Text(
                        '识别到 ${_processedCells.length} 个字符',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      if (_selectedCellIndex >= 0)
                        Text(
                          '已选: ${_charAssignments[_selectedCellIndex] ?? "?"}',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
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
          // Threshold
          _buildSlider(
            label: '阈值',
            value: _params.threshold,
            min: 0.1,
            max: 0.9,
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
    final isSelected = _selectedCellIndex == index;
    final assignedChar = _charAssignments[index];

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCellIndex = isSelected ? -1 : index;
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
