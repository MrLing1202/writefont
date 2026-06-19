import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '选择图片失败: $e');
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
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _proceed() async {
    if (_selectedImages.isEmpty) {
      WFSnackBar.show(context, '请至少选择一张图片');
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
              ? const Center(child: CircularProgressIndicator())
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

}
