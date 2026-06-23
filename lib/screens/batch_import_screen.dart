import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/project.dart';
import '../services/image_processor.dart';
import '../services/recognition_service.dart';
import '../services/dictionary_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'auto_generate/generate_font.dart';
import 'font_preview_screen.dart';

/// 批量照片导入页面
///
/// 从相册选择多张手写照片，自动分割字符并 OCR 识别，
/// 用户确认后生成字体项目。
class BatchImportScreen extends StatefulWidget {
  const BatchImportScreen({super.key});

  @override
  State<BatchImportScreen> createState() => _BatchImportScreenState();
}

class _BatchImportScreenState extends State<BatchImportScreen>
    with SingleTickerProviderStateMixin {
  // ── 状态 ──
  _BatchPhase _phase = _BatchPhase.pickImages;

  // 图片相关
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedImages = [];
  final List<Uint8List> _imageBytesList = [];

  // 处理进度
  int _currentImageIndex = 0;
  int _totalImages = 0;
  String _statusText = '准备中...';
  double _overallProgress = 0.0;

  // 识别结果：每张图片分割出的字符单元格 + 识别结果
  final List<_ImageResult> _imageResults = [];

  // 去重后的确认列表
  final List<_ConfirmedChar> _confirmedChars = [];
  // 被排除的索引集合
  final Set<int> _excludedIndices = {};

  // 处理参数
  final ProcessingParams _params = ProcessingParams();

  // 取消标志
  bool _cancelled = false;

  // 动画
  AnimationController? _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseAnim?.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // 第一步：选择图片
  // ═══════════════════════════════════════════════════════════

  Future<void> _pickImages() async {
    try {
      final photos = await _picker.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (photos.isEmpty) return;

      setState(() {
        _selectedImages.clear();
        _selectedImages.addAll(photos);
      });

      WFSnackBar.show(context, '已选择 ${photos.length} 张图片');
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '选择图片失败: $e');
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (photo == null) return;

      setState(() {
        _selectedImages.add(photo);
      });

      WFSnackBar.show(context, '已添加 1 张图片，共 ${_selectedImages.length} 张');
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '拍照失败: $e');
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 第二步：批量处理（分割 + 识别）
  // ═══════════════════════════════════════════════════════════

  Future<void> _startProcessing() async {
    if (_selectedImages.isEmpty) {
      WFSnackBar.show(context, '请先选择图片');
      return;
    }

    setState(() {
      _phase = _BatchPhase.processing;
      _totalImages = _selectedImages.length;
      _currentImageIndex = 0;
      _overallProgress = 0.0;
      _imageResults.clear();
      _cancelled = false;
    });

    // 读取所有图片字节
    _imageBytesList.clear();
    for (final img in _selectedImages) {
      try {
        _imageBytesList.add(await File(img.path).readAsBytes());
      } catch (e) {
        debugPrint('[批量导入] 读取图片失败: $e');
      }
    }

    if (_imageBytesList.isEmpty) {
      _setError('所有图片读取失败');
      return;
    }

    // 逐张处理
    for (int i = 0; i < _imageBytesList.length; i++) {
      if (_cancelled) return;

      setState(() {
        _currentImageIndex = i;
        _statusText = '正在处理第 ${i + 1}/${_imageBytesList.length} 张图片...';
        _overallProgress = i / _imageBytesList.length;
      });

      try {
        await _processOneImage(_imageBytesList[i], i);
      } catch (e) {
        debugPrint('[批量导入] 处理第 ${i + 1} 张图片失败: $e');
        // 继续处理下一张
      }
    }

    if (_cancelled) return;

    // 合并去重，进入确认阶段
    _buildConfirmedChars();

    setState(() {
      _phase = _BatchPhase.confirm;
      _overallProgress = 1.0;
    });
  }

  /// 处理单张图片：分割字符 → 逐个 OCR 识别
  Future<void> _processOneImage(Uint8List imageBytes, int imageIndex) async {
    // 1. 分割字符
    setState(() => _statusText = '正在分割第 ${imageIndex + 1} 张图片的字符...');

    final cells = ImageProcessor.segmentCharacters(imageBytes, _params);

    if (cells.isEmpty) {
      debugPrint('[批量导入] 第 ${imageIndex + 1} 张图片未分割出字符');
      return;
    }

    debugPrint('[批量导入] 第 ${imageIndex + 1} 张图片分割出 ${cells.length} 个字符');

    // 2. 逐个识别
    final result = _ImageResult(
      imageIndex: imageIndex,
      cells: cells,
      recognitions: List.filled(cells.length, null),
    );

    for (int j = 0; j < cells.length; j++) {
      if (_cancelled) return;

      setState(() {
        _statusText = '识别第 ${imageIndex + 1} 张图片的第 ${j + 1}/${cells.length} 个字符...';
        // 细粒度进度：当前图片内的进度
        final imageProgress = (j + 1) / cells.length;
        _overallProgress = (imageIndex + imageProgress) / _imageBytesList.length;
      });

      try {
        final recognized = await RecognitionService.instance
            .recognizeCharacter(cells[j])
            .timeout(const Duration(seconds: 15), onTimeout: () => null);

        result.recognitions[j] = recognized;
        if (recognized != null) {
          debugPrint('[批量导入] 图${imageIndex + 1}-字${j + 1}: "$recognized"');
        }
      } catch (e) {
        debugPrint('[批量导入] 图${imageIndex + 1}-字${j + 1} 识别异常: $e');
      }
    }

    // ── 同音字上下文纠错 ──
    for (int j = 0; j < cells.length; j++) {
      final current = result.recognitions[j];
      if (current == null || current.isEmpty) continue;
      final prevChar = j > 0 ? result.recognitions[j - 1] : null;
      final nextChar = (j < cells.length - 1) ? result.recognitions[j + 1] : null;
      // v4.3.0: 扩展上下文到3-4字短语
      final prev2Char = j > 1 ? '${result.recognitions[j - 2]}${result.recognitions[j - 1]}' : null;
      final next2Char = (j < cells.length - 2) ? '${result.recognitions[j + 1]}${result.recognitions[j + 2]}' : null;
      final corrected = DictionaryService.instance.correctWithHomophone(
        current,
        prevChar: prevChar,
        nextChar: nextChar,
        prev2Char: prev2Char,
        next2Char: next2Char,
        confidence: 0.75, // 批量导入默认中等置信度
      );
      if (corrected != current) {
        debugPrint('[批量导入] 同音字纠错: "$current" → "$corrected"');
        result.recognitions[j] = corrected;
      }
    }

    _imageResults.add(result);
  }

  /// 合并所有识别结果，按字符去重
  void _buildConfirmedChars() {
    _confirmedChars.clear();
    final seen = <String, int>{}; // char → index in _confirmedChars

    for (final result in _imageResults) {
      for (int i = 0; i < result.cells.length; i++) {
        final char = result.recognitions[i];
        if (char == null || char.isEmpty) continue;

        if (seen.containsKey(char)) {
          // 已存在：如果新结果置信度更高，替换图片
          final existingIdx = seen[char]!;
          _confirmedChars[existingIdx].occurrenceCount++;
        } else {
          seen[char] = _confirmedChars.length;
          _confirmedChars.add(_ConfirmedChar(
            character: char,
            cellImage: result.cells[i],
            imageIndex: result.imageIndex,
            cellIndex: i,
            confidence: RecognitionService.instance
                    .getConfidence(
                        _hashBytes(result.cells[i])) ??
                0.7,
            occurrenceCount: 1,
          ));
        }
      }
    }

    debugPrint('[批量导入] 去重后共 ${_confirmedChars.length} 个不同字符');
  }

  int _hashBytes(Uint8List bytes) {
    int hash = 0x811c9dc5;
    for (int i = 0; i < bytes.length && i < 1024; i++) {
      hash ^= bytes[i];
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  void _setError(String message) {
    if (mounted) {
      setState(() {
        _phase = _BatchPhase.error;
        _statusText = message;
      });
    }
  }

  void _cancelProcessing() {
    _cancelled = true;
    if (mounted) Navigator.of(context).pop();
  }

  // ═══════════════════════════════════════════════════════════
  // 第三步：确认字符 + 生成字体
  // ═══════════════════════════════════════════════════════════

  void _toggleExclude(int index) {
    setState(() {
      if (_excludedIndices.contains(index)) {
        _excludedIndices.remove(index);
      } else {
        _excludedIndices.add(index);
      }
    });
  }

  Future<void> _generateFont() async {
    // 过滤掉被排除的字符
    final included = <_ConfirmedChar>[];
    for (int i = 0; i < _confirmedChars.length; i++) {
      if (!_excludedIndices.contains(i)) {
        included.add(_confirmedChars[i]);
      }
    }

    if (included.isEmpty) {
      WFSnackBar.show(context, '请至少保留一个字符');
      return;
    }

    setState(() {
      _phase = _BatchPhase.generating;
      _statusText = '正在生成字体...';
      _overallProgress = 0.0;
    });

    try {
      // 构建 cells 和 assignments
      final cells = included.map((c) => c.cellImage).toList();
      final assignments = <int, String>{};
      for (int i = 0; i < included.length; i++) {
        assignments[i] = included[i].character;
      }

      // 复用已有的字体生成逻辑
      final project = await generateFontFromCells(
        cells,
        assignments,
        _params,
        _imageBytesList.isNotEmpty ? _imageBytesList.first : Uint8List(0),
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _overallProgress = progress;
              _statusText = status;
            });
          }
        },
      );

      if (project == null) {
        _setError('字体生成失败：没有有效的字符轮廓');
        return;
      }

      // 更新项目名称
      final now = DateTime.now();
      final dateStr =
          '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      project.name = '批量导入 $dateStr';
      project.sourceImages = _imageBytesList.take(5).toList(); // 最多保存5张源图

      await StorageService.saveProject(project);

      if (!mounted) return;

      setState(() {
        _phase = _BatchPhase.done;
        _overallProgress = 1.0;
      });

      // 跳转到字体预览
      Navigator.pushReplacement(
        context,
        WFAnimations.slideRoute(FontPreviewScreen(projectId: project.id)),
      );
    } catch (e) {
      _setError('字体生成失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // UI 构建
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WFAppBar(
        title: '批量照片导入',
        actions: [
          if (_phase == _BatchPhase.pickImages && _selectedImages.isNotEmpty)
            TextButton.icon(
              onPressed: _startProcessing,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始识别'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _BatchPhase.pickImages:
        return _buildPickPhase();
      case _BatchPhase.processing:
        return _buildProcessingPhase();
      case _BatchPhase.confirm:
        return _buildConfirmPhase();
      case _BatchPhase.generating:
        return _buildGeneratingPhase();
      case _BatchPhase.done:
        return _buildDonePhase();
      case _BatchPhase.error:
        return _buildErrorPhase();
    }
  }

  // ── 选择图片阶段 ──
  Widget _buildPickPhase() {
    return Column(
      children: [
        // 说明横幅
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WFColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: WFColors.info.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 20, color: WFColors.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '选择多张手写照片，系统将自动分割字符并识别，去重后生成字体',
                  style: TextStyle(
                    fontSize: 13,
                    color: WFColors.textSecondaryColor(context),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 已选图片列表
        Expanded(
          child: _selectedImages.isEmpty
              ? _buildEmptyPickState()
              : _buildSelectedImageList(),
        ),

        // 底部操作栏
        SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: WFColors.bgCardColor(context),
              border: Border(
                top: BorderSide(
                  color: WFColors.textLightColor(context).withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                // 拍照按钮
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt, size: 20),
                    label: const Text('拍照'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 相册按钮
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.photo_library, size: 20),
                    label: const Text('从相册选择'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WFColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPickState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 72,
            color: WFColors.textLightColor(context),
          ),
          const SizedBox(height: 16),
          Text(
            '选择包含手写汉字的照片',
            style: TextStyle(
              fontSize: 16,
              color: WFColors.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '支持一次选择多张，每张照片中的字符将被自动识别',
            style: TextStyle(
              fontSize: 13,
              color: WFColors.textLightColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedImageList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '已选 ${_selectedImages.length} 张图片',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _selectedImages.clear()),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                  foregroundColor: WFColors.error,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _selectedImages.length,
            itemBuilder: (ctx, i) => _buildImageThumb(i),
          ),
        ),
      ],
    );
  }

  Widget _buildImageThumb(int index) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(_selectedImages[index].path),
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        // 删除按钮
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removeImage(index),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
        // 序号
        Positioned(
          bottom: 4,
          left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 处理中阶段 ──
  Widget _buildProcessingPhase() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 动画图标
            AnimatedBuilder(
              animation: _pulseAnim!,
              builder: (ctx, child) {
                return Transform.scale(
                  scale: 1.0 + _pulseAnim!.value * 0.1,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: WFColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.document_scanner,
                      size: 40,
                      color: WFColors.primary,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _overallProgress,
                minHeight: 8,
                backgroundColor:
                    WFColors.textLightColor(context).withValues(alpha: 0.3),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(WFColors.primary),
              ),
            ),
            const SizedBox(height: 16),
            // 进度百分比
            Text(
              '${(_overallProgress * 100).toInt()}%',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: WFColors.textPrimaryColor(context),
              ),
            ),
            const SizedBox(height: 8),
            // 状态文本
            Text(
              _statusText,
              style: TextStyle(
                fontSize: 14,
                color: WFColors.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // 取消按钮
            TextButton.icon(
              onPressed: _cancelProcessing,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('取消'),
              style: TextButton.styleFrom(
                foregroundColor: WFColors.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 确认字符阶段 ──
  Widget _buildConfirmPhase() {
    final totalChars = _confirmedChars.length;
    final excludedCount = _excludedIndices.length;
    final keepCount = totalChars - excludedCount;

    return Column(
      children: [
        // 顶部统计栏
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WFColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: WFColors.success.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 20, color: WFColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '共识别 $totalChars 个不同字符（来自 ${_imageResults.length} 张图片），'
                  '保留 $keepCount 个',
                  style: TextStyle(
                    fontSize: 13,
                    color: WFColors.textSecondaryColor(context),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 字符网格
        Expanded(
          child: totalChars == 0
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off,
                          size: 56,
                          color: WFColors.textLightColor(context)),
                      const SizedBox(height: 12),
                      Text(
                        '未识别到有效字符',
                        style: TextStyle(
                          fontSize: 15,
                          color: WFColors.textSecondaryColor(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '请确保照片中包含清晰的手写汉字',
                        style: TextStyle(
                          fontSize: 13,
                          color: WFColors.textLightColor(context),
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: totalChars,
                  itemBuilder: (ctx, i) => _buildCharConfirmCell(i),
                ),
        ),

        // 底部操作栏
        SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: WFColors.bgCardColor(context),
              border: Border(
                top: BorderSide(
                  color:
                      WFColors.textLightColor(context).withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                // 重新选择
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _phase = _BatchPhase.pickImages;
                      _imageResults.clear();
                      _confirmedChars.clear();
                      _excludedIndices.clear();
                    }),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('重选'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 生成字体
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: keepCount > 0 ? _generateFont : null,
                    icon: const Icon(Icons.font_download, size: 20),
                    label: Text('生成字体 ($keepCount 字)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WFColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          WFColors.textLightColor(context).withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCharConfirmCell(int index) {
    final char = _confirmedChars[index];
    final excluded = _excludedIndices.contains(index);

    return GestureDetector(
      onTap: () => _toggleExclude(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: excluded
              ? WFColors.error.withValues(alpha: 0.06)
              : WFColors.bgCardColor(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: excluded
                ? WFColors.error.withValues(alpha: 0.4)
                : WFColors.textLightColor(context).withValues(alpha: 0.3),
            width: excluded ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            // 字符图片
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.memory(
                  char.cellImage,
                  fit: BoxFit.contain,
                  color: excluded ? Colors.grey.withValues(alpha: 0.5) : null,
                  colorBlendMode: excluded ? BlendMode.saturation : null,
                ),
              ),
            ),
            // 识别字符标签
            Positioned(
              bottom: 4,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: excluded
                        ? WFColors.error.withValues(alpha: 0.15)
                        : WFColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    char.character,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: excluded
                          ? WFColors.error
                          : WFColors.primary,
                    ),
                  ),
                ),
              ),
            ),
            // 排除标记
            if (excluded)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: WFColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      size: 12, color: Colors.white),
                ),
              ),
            // 出现次数（多次出现时显示）
            if (char.occurrenceCount > 1 && !excluded)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: WFColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '×${char.occurrenceCount}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: WFColors.warning,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 生成中阶段 ──
  Widget _buildGeneratingPhase() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseAnim!,
              builder: (ctx, child) {
                return Transform.scale(
                  scale: 1.0 + _pulseAnim!.value * 0.1,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: WFColors.success.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.font_download,
                      size: 40,
                      color: WFColors.success,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _overallProgress,
                minHeight: 8,
                backgroundColor:
                    WFColors.textLightColor(context).withValues(alpha: 0.3),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(WFColors.success),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _statusText,
              style: TextStyle(
                fontSize: 15,
                color: WFColors.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── 完成阶段 ──
  Widget _buildDonePhase() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 64, color: WFColors.success),
          const SizedBox(height: 16),
          const Text(
            '字体生成完成！',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: WFColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('返回首页'),
          ),
        ],
      ),
    );
  }

  // ── 错误阶段 ──
  Widget _buildErrorPhase() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: WFColors.error),
            const SizedBox(height: 16),
            Text(
              _statusText,
              style: TextStyle(
                fontSize: 15,
                color: WFColors.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => setState(() {
                _phase = _BatchPhase.pickImages;
                _imageResults.clear();
                _confirmedChars.clear();
                _excludedIndices.clear();
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: WFColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 内部数据模型
// ═══════════════════════════════════════════════════════════

enum _BatchPhase {
  pickImages, // 选择图片
  processing, // 分割+识别中
  confirm, // 确认字符
  generating, // 生成字体中
  done, // 完成
  error, // 错误
}

/// 单张图片的处理结果
class _ImageResult {
  final int imageIndex;
  final List<Uint8List> cells;
  final List<String?> recognitions;

  _ImageResult({
    required this.imageIndex,
    required this.cells,
    required this.recognitions,
  });
}

/// 去重后的确认字符
class _ConfirmedChar {
  final String character;
  final Uint8List cellImage;
  final int imageIndex;
  final int cellIndex;
  final double confidence;
  int occurrenceCount;

  _ConfirmedChar({
    required this.character,
    required this.cellImage,
    required this.imageIndex,
    required this.cellIndex,
    required this.confidence,
    this.occurrenceCount = 1,
  });
}
