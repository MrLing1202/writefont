import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import 'capture/image_quality.dart';
import 'capture/image_preview_screen.dart';
import 'capture/grid_guide_overlay.dart';
import 'capture/thumbnail_strip.dart';
import 'capture/bottom_bar.dart';
import 'capture/empty_state.dart';
import 'capture/progress_banner.dart';
import 'capture/image_list.dart';
import 'capture/info_banner.dart';

/// 拍照 / 选图页面
class CaptureScreen extends StatefulWidget {
  final List<String>? charset; // 标准字表，null = 自由模式

  const CaptureScreen({super.key, this.charset});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedImages = [];
  bool _isLoading = false;
  bool _showGridGuide = false;
  // 批量拍摄模式：拍照后自动准备下一张
  bool _batchMode = false;
  // 拍照计数器（批量模式下显示已拍数量）
  int _captureCount = 0;
  // 帮助引导状态
  bool _showHelpOverlay = false;
  int _helpStep = 0;
  // 教程状态
  bool _showTutorial = false;
  int _tutorialStep = 0;
  final List<int> _completedTutorials = [];
  // 教程进度跟踪
  int _totalTutorialSteps = 0;
  int _viewedTutorialSteps = 0;

  @override
  void initState() {
    super.initState();
    _loadTutorialProgress();
  }

  /// 加载教程进度
  Future<void> _loadTutorialProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getStringList('capture_completed_tutorials');
      if (completed != null && mounted) {
        setState(() {
          _completedTutorials.clear();
          _completedTutorials.addAll(completed.map(int.parse));
        });
      }
    } catch (_) {}
  }

  /// 保存教程进度
  Future<void> _saveTutorialProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'capture_completed_tutorials',
        _completedTutorials.map((e) => e.toString()).toList(),
      );
    } catch (_) {}
  }

  // ── 声音反馈方法 ──

  /// 拍照声音反馈（系统快门音 + 触觉）
  void _playCaptureSound() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();
  }

  /// 成功提示音（轻触 + 震动）
  void _playSuccessSound() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }

  /// 错误提示音（重触 + 震动）
  void _playErrorSound() {
    HapticFeedback.heavyImpact();
  }

  /// 操作反馈音（轻触）
  void _playActionSound() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
  }

  Future<void> _takePhoto() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (photo != null) {
        await _handleCapturedImage(photo);
        _playCaptureSound(); // 拍照声音反馈
        // 批量模式：拍照成功后自动提示继续
        if (_batchMode && mounted) {
          _captureCount++;
          final remaining = (widget.charset?.length ?? 0) - _selectedImages.length;
          if (remaining > 0) {
            WFSnackBar.show(context, '已拍 $_captureCount 张，还需 $remaining 张');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '拍照失败: $e');
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (photo != null) {
        await _handleCapturedImage(photo);
        _playSuccessSound(); // 选图成功声音
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '选择图片失败: $e');
        _playErrorSound(); // 错误声音
      }
    }
  }

  /// 处理拍摄/选择的图片：质量检测 + 预览
  Future<void> _handleCapturedImage(XFile photo) async {
    setState(() => _isLoading = true);

    try {
      final quality = await detectImageQuality(photo.path);

      if (!mounted) return;

      // 批量模式下跳过低质量图片的预览确认，直接添加
      bool confirmed;
      if (_batchMode && quality.level != QualityLevel.poor) {
        confirmed = true;
      } else {
        confirmed = await Navigator.of(context).push<bool>(
          WFAnimations.slideRoute<bool>(ImagePreviewScreen(
            imagePath: photo.path,
            quality: quality,
          )),
        ) ?? false;
      }

      if (confirmed == true && mounted) {
        setState(() {
          _selectedImages.add(photo);
        });
        _playSuccessSound(); // 添加图片成功声音
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '图片处理失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _removeImage(int index) {
    _playActionSound(); // 删除操作声音
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _proceed() async {
    if (_selectedImages.isEmpty) {
      WFSnackBar.show(context, '请至少选择一张图片');
      _playErrorSound(); // 空列表错误声音
      return;
    }

    setState(() => _isLoading = true);

    try {
      final total = _selectedImages.length;
      final List<Uint8List> imageBytes = [];
      for (int i = 0; i < total; i++) {
        final bytes = await File(_selectedImages[i].path).readAsBytes();
        imageBytes.add(bytes);
        // 显示读取进度
        if (mounted && total > 1) {
          WFSnackBar.show(context, '正在读取图片 ${i + 1}/$total...');
        }
      }

      if (mounted) {
        Navigator.of(context).pushNamed(
          '/processing',
          arguments: {
            'images': imageBytes,
            if (widget.charset != null) 'charset': widget.charset,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '读取图片失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 显示网格引导对话框
  void _showGridGuideDialog() {
    final charset = widget.charset;
    if (charset == null || charset.isEmpty) {
      WFSnackBar.show(context, '自由模式下无网格引导');
      return;
    }
    setState(() {
      _showGridGuide = !_showGridGuide;
    });
  }

  /// 切换批量拍摄模式
  void _toggleBatchMode() {
    _playActionSound(); // 模式切换声音
    setState(() {
      _batchMode = !_batchMode;
      if (_batchMode) {
        _captureCount = 0;
      }
    });
    if (_batchMode) {
      WFSnackBar.show(context, '批量模式已开启，拍照后自动准备下一张');
    }
  }

  /// 显示操作引导帮助
  void _toggleHelp() {
    setState(() {
      _showHelpOverlay = !_showHelpOverlay;
      _helpStep = 0;
    });
  }

  /// 下一步帮助引导
  void _nextHelpStep() {
    final helpSteps = _getHelpSteps();
    if (_helpStep < helpSteps.length - 1) {
      setState(() => _helpStep++);
    } else {
      setState(() => _showHelpOverlay = false);
    }
  }

  /// 获取帮助步骤列表
  List<Map<String, dynamic>> _getHelpSteps() {
    return [
      {
        'icon': Icons.camera_alt,
        'title': '拍照或选图',
        'desc': '点击底部"拍照"按钮拍摄手写字体，或从相册选择已有的图片',
      },
      {
        'icon': Icons.grid_on,
        'title': '网格引导',
        'desc': '开启网格引导可帮助你按照标准字表逐字拍摄，确保每个字符位置准确',
      },
      {
        'icon': Icons.burst_mode,
        'title': '批量拍摄',
        'desc': '开启批量模式后，拍照成功会自动准备下一张，适合连续拍摄多个字符',
      },
      {
        'icon': Icons.high_quality,
        'title': '图片质量',
        'desc': '系统会自动检测图片质量，建议使用光线充足、清晰度高的图片以获得最佳识别效果',
      },
      {
        'icon': Icons.arrow_forward,
        'title': '开始处理',
        'desc': '选择完图片后点击"下一步"，系统将自动识别字符并生成字体',
      },
    ];
  }

  // ── 教程功能 ──

  /// 获取图文教程内容
  List<Map<String, dynamic>> _getTutorialSteps() {
    return [
      {
        'icon': Icons.camera_alt_outlined,
        'title': '第1步：准备拍摄',
        'desc': '选择光线充足的环境，准备白色纸张和黑色签字笔',
        'detail': '建议：\n• 使用A4白色纸张\n• 黑色签字笔或马克笔\n• 自然光或台灯照明\n• 避免阴影和反光',
        'videoId': 'prepare_capture',
      },
      {
        'icon': Icons.edit_note,
        'title': '第2步：书写字符',
        'desc': '在纸张上逐个书写汉字，保持间距均匀',
        'detail': '建议：\n• 每个字符大小约1-2厘米\n• 字符间距保持一致\n• 书写清晰，笔画完整\n• 按照标准字表顺序书写',
        'videoId': 'write_chars',
      },
      {
        'icon': Icons.photo_camera,
        'title': '第3步：拍摄图片',
        'desc': '使用应用拍照功能，确保图片清晰完整',
        'detail': '建议：\n• 手机保持稳定\n• 镜头对准字符区域\n• 避免倾斜和变形\n• 可使用网格引导辅助',
        'videoId': 'take_photo',
      },
      {
        'icon': Icons.tune,
        'title': '第4步：调节参数',
        'desc': '根据图片情况调节识别参数，优化识别效果',
        'detail': '建议：\n• 阈值：控制识别灵敏度\n• 对比度：增强字符边缘\n• 平滑度：优化轮廓质量\n• 线宽：调整笔画粗细',
        'videoId': 'adjust_params',
      },
      {
        'icon': Icons.font_download,
        'title': '第5步：生成字体',
        'desc': '预览并导出手写字体，安装到设备使用',
        'detail': '建议：\n• 预览检查每个字符\n• 手动修正识别错误\n• 导出TTF格式字体\n• 安装到系统字体库',
        'videoId': 'generate_font',
      },
    ];
  }

  /// 显示教程
  void _showTutorialDialog() {
    setState(() {
      _showTutorial = true;
      _tutorialStep = 0;
    });
  }

  /// 下一步教程
  void _nextTutorialStep() {
    final steps = _getTutorialSteps();
    if (!_completedTutorials.contains(_tutorialStep)) {
      _completedTutorials.add(_tutorialStep);
      _saveTutorialProgress();
    }
    if (_tutorialStep < steps.length - 1) {
      setState(() {
        _tutorialStep++;
        _viewedTutorialSteps++;
      });
    } else {
      setState(() {
        _showTutorial = false;
        _viewedTutorialSteps = _totalTutorialSteps;
      });
    }
  }

  /// 获取教程进度
  double _getTutorialProgress() {
    final total = _getTutorialSteps().length;
    if (total == 0) return 0;
    return _completedTutorials.length / total;
  }

  /// 显示常见问题解答
  void _showFAQDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: WFColors.primary),
            SizedBox(width: 8),
            Text('常见问题'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 350,
          child: ListView(
            children: [
              _buildFAQItem(
                'Q: 什么样的图片效果最好？',
                'A: 建议使用白色背景、黑色字体的手写图片。光线均匀、无阴影、图片清晰度高效果最佳。',
              ),
              _buildFAQItem(
                'Q: 可以一次选多少张图片？',
                'A: 没有数量限制，但建议每个字符使用一张独立图片，方便后续识别和编辑。',
              ),
              _buildFAQItem(
                'Q: 图片质量提示"较差"怎么办？',
                'A: 可以继续使用，但可能影响识别准确率。建议重新拍摄或选择更清晰的图片。',
              ),
              _buildFAQItem(
                'Q: 批量模式是什么？',
                'A: 批量模式下拍照成功后会自动准备下一张拍摄，适合连续拍摄多个字符的场景。',
              ),
              _buildFAQItem(
                'Q: 网格引导有什么用？',
                'A: 网格引导会按照标准字表显示字符位置，帮助你有序地逐字拍摄。',
              ),
              _buildFAQItem(
                'Q: 支持哪些图片格式？',
                'A: 支持常见的 JPG、PNG 格式。建议使用 PNG 格式以获得更好的透明度支持。',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 构建FAQ条目
  Widget _buildFAQItem(String question, String answer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          Text(answer, style: TextStyle(fontSize: 13, color: WFColors.textSecondary, height: 1.4)),
        ],
      ),
    );
  }

  /// 批量从相册选择（并行检测质量）
  Future<void> _pickMultiFromGallery() async {
    try {
      final photos = await _picker.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (photos.isNotEmpty) {
        // 并行检测所有图片质量
        final qualityResults = await Future.wait(
          photos.map((photo) async {
            try {
              return await detectImageQuality(photo.path);
            } catch (_) {
              return null;
            }
          }),
        );

        final poorCount = qualityResults
            .where((q) => q != null && q.level == QualityLevel.poor)
            .length;

        setState(() {
          _selectedImages.addAll(photos);
        });

        if (mounted) {
          if (poorCount > 0) {
            WFSnackBar.showWithDuration(
              context,
              '已添加 ${photos.length} 张图片，其中 $poorCount 张质量较差，可能影响识别效果',
              duration: const Duration(seconds: 3),
            );
          } else {
            WFSnackBar.show(context, '已添加 ${photos.length} 张图片');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '选择图片失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final charset = widget.charset;
    final totalChars = charset?.length ?? 0;

    return Scaffold(
      appBar: WFAppBar(
        title: '拍照 / 选图',
        actions: [
          // 教程按钮
          IconButton(
            onPressed: _showTutorialDialog,
            icon: Icon(
              Icons.menu_book,
              color: _getTutorialProgress() >= 1.0 ? WFColors.success : null,
            ),
            tooltip: '使用教程',
          ),
          // 帮助按钮
          IconButton(
            onPressed: _toggleHelp,
            icon: const Icon(Icons.help_outline),
            tooltip: '操作帮助',
          ),
          if (charset != null && charset.isNotEmpty)
            IconButton(
              onPressed: _showGridGuideDialog,
              icon: Icon(
                _showGridGuide ? Icons.grid_off : Icons.grid_on,
              ),
              tooltip: _showGridGuide ? '关闭网格引导' : '显示网格引导',
            ),
          // 批量拍摄模式切换
          IconButton(
            onPressed: _toggleBatchMode,
            icon: Icon(
              _batchMode ? Icons.burst_mode : Icons.photo_camera_outlined,
              color: _batchMode ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: _batchMode ? '关闭批量拍摄' : '开启批量拍摄',
          ),
          if (_selectedImages.isNotEmpty)
            TextButton.icon(
              onPressed: _proceed,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('下一步'),
            ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? Center(
                  child: WFAnimations.pulse(
                    child: const CircularProgressIndicator(),
                  ),
                )
              : Column(
                  children: [
                    // 进度指示条
                    if (totalChars > 0)
                      ProgressBanner(
                        imageCount: _selectedImages.length,
                        totalChars: totalChars,
                        colorScheme: colorScheme,
                      ),

                    // 网格引导叠加层
                    if (_showGridGuide && charset != null)
                      GridGuideOverlay(
                        charset: charset,
                        completedCount: _selectedImages.length,
                        colorScheme: colorScheme,
                      ),

                    // 说明横幅
                    InfoBanner(colorScheme: colorScheme),

                    // 已选图片缩略图
                    if (_selectedImages.isNotEmpty)
                      ThumbnailStrip(
                        images: _selectedImages,
                        onRemove: _removeImage,
                        colorScheme: colorScheme,
                      ),

                    if (_selectedImages.isNotEmpty) const Divider(height: 1),

                    // 主内容区域
                    Expanded(
                      child: _selectedImages.isEmpty
                          ? CaptureEmptyState(colorScheme: colorScheme)
                          : CaptureImageList(
                              images: _selectedImages,
                              onRemove: _removeImage,
                              colorScheme: colorScheme,
                            ),
                    ),

                    // 底部操作栏
                    CaptureBottomBar(
                      onTakePhoto: _takePhoto,
                      onPickFromGallery: _pickFromGallery,
                      onPickMulti: _pickMultiFromGallery,
                      colorScheme: colorScheme,
                    ),
                  ],
                ),

          // 帮助引导覆盖层
          if (_showHelpOverlay) _buildHelpOverlay(),
          // 教程覆盖层
          if (_showTutorial) _buildTutorialOverlay(),
        ],
      ),
    );
  }

  /// 构建帮助引导覆盖层
  Widget _buildHelpOverlay() {
    final helpSteps = _getHelpSteps();
    final step = helpSteps[_helpStep];

    return GestureDetector(
      onTap: _nextHelpStep,
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: WFColors.bgCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  step['icon'] as IconData,
                  size: 56,
                  color: WFColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  step['title'] as String,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: WFColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  step['desc'] as String,
                  style: const TextStyle(
                    fontSize: 15,
                    color: WFColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // 进度指示点
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    helpSteps.length,
                    (i) => Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _helpStep ? WFColors.primary : WFColors.textLight,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _showHelpOverlay = false),
                      child: const Text('跳过', style: TextStyle(color: WFColors.textSecondary)),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _showFAQDialog,
                          child: const Text('常见问题'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _nextHelpStep,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WFColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            _helpStep < helpSteps.length - 1 ? '下一步' : '完成',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建图文教程覆盖层
  Widget _buildTutorialOverlay() {
    final steps = _getTutorialSteps();
    final step = steps[_tutorialStep];
    final progress = (_tutorialStep + 1) / steps.length;

    return GestureDetector(
      onTap: _nextTutorialStep,
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        child: SafeArea(
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: WFColors.bgCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 顶部进度条
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: WFColors.textLight.withValues(alpha: 0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(WFColors.primary),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 步骤图标
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: WFColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        step['icon'] as IconData,
                        size: 36,
                        color: WFColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 步骤标题
                    Text(
                      step['title'] as String,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: WFColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    // 步骤描述
                    Text(
                      step['desc'] as String,
                      style: const TextStyle(
                        fontSize: 15,
                        color: WFColors.textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // 详细说明（图文教程内容）
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: WFColors.textLight.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: WFColors.textLight.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        step['detail'] as String,
                        style: const TextStyle(
                          fontSize: 13,
                          color: WFColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 交互提示
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: WFColors.info.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app, size: 18, color: WFColors.info),
                          SizedBox(width: 6),
                          Text(
                            '点击任意位置继续',
                            style: TextStyle(fontSize: 12, color: WFColors.info),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 进度指示点
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        steps.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: i == _tutorialStep ? 20 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: i == _tutorialStep
                                ? WFColors.primary
                                : _completedTutorials.contains(i)
                                    ? WFColors.success.withValues(alpha: 0.5)
                                    : WFColors.textLight,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 底部按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _showTutorial = false),
                          child: const Text('关闭教程', style: TextStyle(color: WFColors.textSecondary)),
                        ),
                        Row(
                          children: [
                            Text(
                              '${_tutorialStep + 1}/${steps.length}',
                              style: const TextStyle(fontSize: 13, color: WFColors.textSecondary),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: _nextTutorialStep,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WFColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: Text(
                                _tutorialStep < steps.length - 1 ? '下一步' : '完成',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
