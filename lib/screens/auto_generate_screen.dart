import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/image_processor.dart';
import '../services/storage_service.dart';
import '../services/recognition_service.dart';
import 'character_edit_screen.dart';

/// 一键生成页面
/// 拍照后自动完成：分割字符 → AI 识别 → 确认字符 → 生成字体 → 跳转预览
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

  // 确认模式相关状态
  bool _isConfirming = false; // 是否处于确认模式
  bool _isGenerating = false; // 是否正在生成字体
  final Map<int, String> _editedAssignments = {}; // 用户修正过的字符
  final Set<int> _aiRecognized = {}; // AI 原始识别成功的索引

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

  /// 获取当前字符分配（合并 AI 识别和用户修正）
  String? _getCharAt(int index) {
    // 优先使用用户修正的结果
    if (_editedAssignments.containsKey(index)) {
      return _editedAssignments[index];
    }
    return _charAssignments[index];
  }

  /// 判断某索引是否为 AI 原始识别成功
  bool _isAiRecognized(int index) {
    return _aiRecognized.contains(index);
  }

  /// 判断某索引是否被用户修正过
  bool _isUserEdited(int index) {
    return _editedAssignments.containsKey(index);
  }

  /// 获取识别统计信息
  Map<String, int> _getStats() {
    int aiRecognized = 0;
    int userEdited = 0;
    int fallbackAssigned = 0;

    for (int i = 0; i < _cells.length; i++) {
      if (_isUserEdited(i)) {
        userEdited++;
      } else if (_isAiRecognized(i)) {
        aiRecognized++;
      } else if (_charAssignments.containsKey(i)) {
        fallbackAssigned++;
      }
    }

    return {
      'total': _cells.length,
      'aiRecognized': aiRecognized,
      'userEdited': userEdited,
      'fallbackAssigned': fallbackAssigned,
    };
  }

  Future<void> _startProcessing() async {
    try {
      // 1. 分割字符
      setState(() {
        _status = '正在分割字符...';
        _progress = 0.1;
        _isConfirming = false;
        _isGenerating = false;
        _editedAssignments.clear();
        _aiRecognized.clear();
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
            _aiRecognized.add(i); // 标记为 AI 识别成功
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

      // 识别完成，进入确认模式（不直接生成字体）
      setState(() {
        _progress = 1.0;
        _status = '识别完成';
        _isConfirming = true;
      });
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

  /// 打开字符编辑对话框，让用户修正识别结果
  void _editCharacter(int index) {
    final currentChar = _getCharAt(index) ?? '';
    if (currentChar.isEmpty) return;

    // 创建临时 GlyphData 用于编辑对话框
    final tempGlyph = GlyphData(
      character: currentChar,
      unicode: currentChar.codeUnitAt(0),
      contours: [], // 轮廓尚未提取，传空
    );

    CharacterEditDialog.show(
      context,
      character: currentChar,
      glyph: tempGlyph,
      onCharacterChanged: () {
        // 用户修改了字符标签
        final newChar = tempGlyph.character;
        if (newChar != currentChar && newChar.isNotEmpty) {
          setState(() {
            _editedAssignments[index] = newChar;
          });
        }
      },
      onCharacterDeleted: () {
        // 用户删除了该字符的分配
        setState(() {
          _charAssignments.remove(index);
          _editedAssignments.remove(index);
        });
      },
    );
  }

  /// 快速修改字符（弹出简单输入框）
  void _quickEditCharacter(int index) {
    final currentChar = _getCharAt(index) ?? '';
    final controller = TextEditingController(text: currentChar);

    showDialog<String>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              // 字符图片缩略图
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(_cells[index], fit: BoxFit.contain),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('修改字符', style: TextStyle(fontSize: 18)),
                    Text(
                      '第 ${index + 1} 个字符',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: TextField(
            controller: controller,
            maxLength: 1,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '输入正确字符',
              hintText: '输入一个字符',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: (v) {
              if (v.isNotEmpty) {
                Navigator.pop(ctx, v);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final val = controller.text;
                if (val.isNotEmpty) {
                  Navigator.pop(ctx, val);
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    ).then((newChar) {
      if (newChar != null && newChar.isNotEmpty && newChar != currentChar) {
        setState(() {
          _editedAssignments[index] = newChar;
        });
      }
    });
  }

  /// 确认生成字体
  Future<void> _confirmAndGenerate() async {
    setState(() {
      _isGenerating = true;
      _progress = 0.0;
      _status = '正在生成字体...';
    });

    try {
      await Future.delayed(const Duration(milliseconds: 200));

      // 构建最终字符分配（合并 AI 识别和用户修正）
      final finalAssignments = <int, String>{};
      for (int i = 0; i < _cells.length; i++) {
        final char = _getCharAt(i);
        if (char != null && char.isNotEmpty) {
          finalAssignments[i] = char;
        }
      }

      // 生成字体项目
      final project = FontProject(
        id: StorageService.generateId(),
        name: '一键生成字体',
        params: _params,
        sourceImages: [widget.imageBytes],
      );

      final total = finalAssignments.length;
      int completed = 0;

      for (final entry in finalAssignments.entries) {
        final i = entry.key;
        final char = entry.value;

        final contours = ImageProcessor.extractContours(_cells[i], _params);

        // 动态计算字宽，根据实际轮廓边界而非固定值
        final glyph = GlyphData(
          character: char,
          unicode: char.codeUnitAt(0),
          contours: contours,
        );
        glyph.advanceWidth = glyph.calculateAdvanceWidth();
        project.glyphs[char] = glyph;

        completed++;
        if (mounted) {
          setState(() {
            _progress = completed / total;
            _status = '正在生成字体 $completed/$total...';
          });
        }
      }

      setState(() {
        _progress = 1.0;
        _status = '生成完成！';
      });

      await Future.delayed(const Duration(milliseconds: 500));

      // 跳转预览
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(
          '/preview',
          arguments: {'project': project},
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _hasError = true;
          _errorMessage = '生成字体出错: $e';
          _status = '生成失败';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isConfirming ? '确认字符' : '一键生成'),
        centerTitle: true,
      ),
      body: _hasError
          ? _buildErrorView(colorScheme)
          : _isConfirming
              ? _buildConfirmView(colorScheme)
              : _buildProcessingView(colorScheme),
    );
  }

  /// 构建处理中的视图
  Widget _buildProcessingView(ColorScheme colorScheme) {
    return Center(
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
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                value: _progress < 1.0 ? _progress : null,
                strokeWidth: 4,
                color: colorScheme.primary,
                backgroundColor: colorScheme.surfaceContainerHighest,
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
                backgroundColor: colorScheme.surfaceContainerHighest,
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
        ),
      ),
    );
  }

  /// 构建确认字符视图
  Widget _buildConfirmView(ColorScheme colorScheme) {
    final stats = _getStats();
    final isGenerating = _isGenerating;

    return Column(
      children: [
        // 顶部统计信息栏
        _buildStatsBar(colorScheme, stats),

        // 字符网格
        Expanded(
          child: _buildCharacterGrid(colorScheme, isGenerating),
        ),

        // 底部操作按钮
        _buildBottomActions(colorScheme, isGenerating),
      ],
    );
  }

  /// 构建统计信息栏
  Widget _buildStatsBar(ColorScheme colorScheme, Map<String, int> stats) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          // 总数
          _buildStatChip(
            icon: Icons.grid_view,
            label: '共 ${stats['total']} 个',
            color: colorScheme.onSurfaceVariant,
            colorScheme: colorScheme,
          ),
          const SizedBox(width: 8),
          // AI 识别
          _buildStatChip(
            icon: Icons.auto_awesome,
            label: 'AI 识别 ${stats['aiRecognized']}',
            color: Colors.green.shade700,
            colorScheme: colorScheme,
          ),
          const SizedBox(width: 8),
          // 用户修正
          _buildStatChip(
            icon: Icons.edit,
            label: '已修正 ${stats['userEdited']}',
            color: Colors.blue.shade700,
            colorScheme: colorScheme,
          ),
          const SizedBox(width: 8),
          // 补齐分配
          _buildStatChip(
            icon: Icons.format_list_numbered,
            label: '自动补齐 ${stats['fallbackAssigned']}',
            color: Colors.orange.shade700,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  /// 构建统计标签
  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建字符网格
  Widget _buildCharacterGrid(ColorScheme colorScheme, bool isGenerating) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _cells.length,
      itemBuilder: (context, index) {
        final char = _getCharAt(index) ?? '';
        final isRecognized = _isAiRecognized(index);
        final isEdited = _isUserEdited(index);

        return _buildCharacterCell(
          colorScheme: colorScheme,
          index: index,
          char: char,
          isRecognized: isRecognized,
          isEdited: isEdited,
          isGenerating: isGenerating,
        );
      },
    );
  }

  /// 构建单个字符格子
  Widget _buildCharacterCell({
    required ColorScheme colorScheme,
    required int index,
    required String char,
    required bool isRecognized,
    required bool isEdited,
    required bool isGenerating,
  }) {
    // 根据状态确定边框颜色
    Color borderColor;
    if (isEdited) {
      borderColor = Colors.blue.shade400; // 用户修正：蓝色
    } else if (isRecognized) {
      borderColor = Colors.green.shade400; // AI 识别：绿色
    } else {
      borderColor = Colors.orange.shade300; // 自动补齐：橙色
    }

    return GestureDetector(
      onTap: isGenerating ? null : () => _quickEditCharacter(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1.5),
          color: colorScheme.surface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 字符图片
            Padding(
              padding: const EdgeInsets.all(4),
              child: Image.memory(
                _cells[index],
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),

            // 识别结果标签（底部居中）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.85),
                  border: Border(
                    top: BorderSide(
                      color: borderColor.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Text(
                  char,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
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

            // 索引编号（左上角）
            Positioned(
              top: 2,
              left: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
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

  /// 构建底部操作按钮
  Widget _buildBottomActions(ColorScheme colorScheme, bool isGenerating) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 提示文字
          Text(
            '点击字符可修改识别结果',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),

          // 图例说明
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendDot(Colors.green.shade500, 'AI 识别'),
              const SizedBox(width: 16),
              _buildLegendDot(Colors.blue.shade400, '已修正'),
              const SizedBox(width: 16),
              _buildLegendDot(Colors.orange.shade400, '自动补齐'),
            ],
          ),
          const SizedBox(height: 16),

          // 生成进度（生成中显示）
          if (isGenerating) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                color: colorScheme.primary,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _status,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 按钮行
          Row(
            children: [
              // 重新识别按钮
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isGenerating
                      ? null
                      : () {
                          setState(() {
                            _charAssignments.clear();
                            _editedAssignments.clear();
                            _aiRecognized.clear();
                            _isConfirming = false;
                            _hasError = false;
                            _errorMessage = null;
                            _progress = 0.0;
                          });
                          _startProcessing();
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新识别'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 确认生成按钮
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: isGenerating ? null : _confirmAndGenerate,
                  icon: Icon(isGenerating
                      ? Icons.hourglass_top
                      : Icons.check_circle),
                  label: Text(isGenerating ? '生成中...' : '确认生成'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建图例标记点
  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  /// 构建错误视图
  Widget _buildErrorView(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
                  _editedAssignments.clear();
                  _aiRecognized.clear();
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
        ),
      ),
    );
  }
}
