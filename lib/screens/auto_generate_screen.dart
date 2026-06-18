import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/image_processor.dart';
import '../services/storage_service.dart';
import '../services/recognition_service.dart';

/// 一键生成页面
/// 拍照后自动完成：分割字符 → AI 识别 → 生成字体 → 跳转预览
class AutoGenerateScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const AutoGenerateScreen({
    super.key,
    required this.imageBytes,
  });

  @override
  State<AutoGenerateScreen> createState() => _AutoGenerateScreenState();
}

class _AutoGenerateScreenState extends State<AutoGenerateScreen>
    with SingleTickerProviderStateMixin {
  // 处理阶段
  String _status = '准备中...';
  double _progress = 0.0;
  bool _hasError = false;
  String? _errorMessage;

  // 处理结果
  List<Uint8List> _cells = [];
  final Map<int, String> _charAssignments = {};

  // 默认参数（推荐值）
  final ProcessingParams _params = ProcessingParams();

  // 动画
  late AnimationController _animController;

  // 默认字符池
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

  final List<String> _defaultCharacters = _getDefaultChars();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _startProcessing();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _startProcessing() async {
    try {
      // 1. 分割字符
      setState(() {
        _status = '正在分割字符...';
        _progress = 0.1;
      });

      // 短暂延迟让 UI 更新
      await Future.delayed(const Duration(milliseconds: 300));

      final cells = ImageProcessor.segmentCharacters(
        widget.imageBytes,
        _params,
      );

      if (cells.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = '未识别到字符，请确保照片中包含清晰的手写文字';
          _status = '分割失败';
        });
        return;
      }

      setState(() {
        _cells = cells;
        _progress = 0.3;
        _status = '已分割 ${cells.length} 个字符，正在识别...';
      });

      await Future.delayed(const Duration(milliseconds: 200));

      // 2. AI 识别字符
      final recognitionService = RecognitionService.instance;
      final batchResults = await recognitionService.recognizeBatch(
        cells,
        onProgress: (completed, total) {
          if (mounted) {
            final recognitionProgress = 0.3 + (completed / total) * 0.5;
            setState(() {
              _progress = recognitionProgress;
              _status = '正在识别字符 $completed/$total...';
            });
          }
        },
      );

      // 记录识别结果（去重：如果识别出重复字符，跳过，留给 fallback 分配）
      for (int i = 0; i < batchResults.length; i++) {
        if (batchResults[i] != null) {
          final char = batchResults[i]!;
          if (!_charAssignments.containsValue(char)) {
            _charAssignments[i] = char;
          } else {
            debugPrint('自动分配: 跳过重复字符 "$char" (cell $i)');
          }
        }
      }

      // 补齐未识别的字符
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

      setState(() {
        _progress = 0.85;
        _status = '正在生成字体...';
      });

      await Future.delayed(const Duration(milliseconds: 200));

      // 3. 生成字体项目
      final project = FontProject(
        id: StorageService.generateId(),
        name: '一键生成字体',
        params: _params,
        sourceImages: [widget.imageBytes],
      );

      for (int i = 0; i < cells.length; i++) {
        final char = _charAssignments[i];
        if (char == null) continue;

        final contours = ImageProcessor.extractContours(cells[i], _params);

        project.glyphs[char] = GlyphData(
          character: char,
          unicode: char.codeUnitAt(0),
          contours: contours,
          advanceWidth: 500,
        );
      }

      setState(() {
        _progress = 1.0;
        _status = '生成完成！';
      });

      await Future.delayed(const Duration(milliseconds: 500));

      // 4. 跳转预览
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(
          '/preview',
          arguments: {'project': project},
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = '处理出错: $e';
          _status = '处理失败';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('一键生成'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 图片预览
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(
                  widget.imageBytes,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 40),

              // 进度指示器
              if (!_hasError) ...[
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    value: _progress < 1.0 ? _progress : null,
                    strokeWidth: 4,
                    color: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                // 进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 8,
                    color: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),

                // 状态文字
                Text(
                  _status,
                  style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // 已识别字符数
                if (_cells.isNotEmpty)
                  Text(
                    '已分割 ${_cells.length} 个字符，'
                    '已识别 ${_charAssignments.length} 个',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],

              // 错误状态
              if (_hasError) ...[
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  _status,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? '未知错误',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _errorMessage = null;
                      _progress = 0.0;
                      _charAssignments.clear();
                    });
                    _startProcessing();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
