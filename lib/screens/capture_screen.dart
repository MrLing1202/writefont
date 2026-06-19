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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失败: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
      }
    }
  }

  /// 处理拍摄/选择的图片：质量检测 + 预览
  Future<void> _handleCapturedImage(XFile photo) async {
    setState(() => _isLoading = true);

    try {
      final quality = await detectImageQuality(photo.path);

      if (!mounted) return;

      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen(
            imagePath: photo.path,
            quality: quality,
          ),
        ),
      );

      if (confirmed == true && mounted) {
        setState(() {
          _selectedImages.add(photo);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片处理失败: $e')),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一张图片')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final List<Uint8List> imageBytes = [];
      for (final file in _selectedImages) {
        final bytes = await File(file.path).readAsBytes();
        imageBytes.add(bytes);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取图片失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 显示网格引导对话框
  void _showGridGuideDialog() {
    final charset = widget.charset;
    if (charset == null || charset.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自由模式下无网格引导')),
      );
      return;
    }
    setState(() {
      _showGridGuide = !_showGridGuide;
    });
  }

  /// 批量从相册选择
  Future<void> _pickMultiFromGallery() async {
    try {
      final photos = await _picker.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (photos.isNotEmpty) {
        int poorCount = 0;
        for (final photo in photos) {
          try {
            final quality = await detectImageQuality(photo.path);
            if (quality.level == QualityLevel.poor) poorCount++;
          } catch (_) {
            // 单张检测失败不影响整体添加
          }
        }

        setState(() {
          _selectedImages.addAll(photos);
        });

        if (mounted) {
          if (poorCount > 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已添加 ${photos.length} 张图片，其中 $poorCount 张质量较差，可能影响识别效果'),
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已添加 ${photos.length} 张图片')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
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
          if (charset != null && charset.isNotEmpty)
            IconButton(
              onPressed: _showGridGuideDialog,
              icon: Icon(
                _showGridGuide ? Icons.grid_off : Icons.grid_on,
              ),
              tooltip: _showGridGuide ? '关闭网格引导' : '显示网格引导',
            ),
          if (_selectedImages.isNotEmpty)
            TextButton.icon(
              onPressed: _proceed,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('下一步'),
            ),
        ],
      ),
      body: _isLoading
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
    );
  }

}
