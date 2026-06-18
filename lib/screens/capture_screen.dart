import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

/// 图片质量检测结果
class ImageQualityResult {
  final double brightness; // 平均灰度值 (0-255)
  final double sharpness; // 拉普拉斯方差
  final String summary; // 质量总结
  final QualityLevel level; // 质量等级

  ImageQualityResult({
    required this.brightness,
    required this.sharpness,
    required this.summary,
    required this.level,
  });
}

enum QualityLevel { good, medium, poor }

/// 检测图片质量（亮度 + 模糊度）
Future<ImageQualityResult> detectImageQuality(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return ImageQualityResult(
      brightness: 0,
      sharpness: 0,
      summary: '无法解析图片',
      level: QualityLevel.poor,
    );
  }

  // 缩小图片以加速计算（最长边 300px）
  final resized = img.copyResize(decoded, width: decoded.width > decoded.height ? 300 : null, height: decoded.height >= decoded.width ? 300 : null);
  final width = resized.width;
  final height = resized.height;
  final pixels = resized;

  // 1. 计算平均灰度值（亮度）
  double totalBrightness = 0;
  final pixelCount = width * height;
  // 转灰度并计算平均值
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final pixel = pixels.getPixel(x, y);
      final gray = pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
      totalBrightness += gray;
    }
  }
  final avgBrightness = totalBrightness / pixelCount;

  // 2. 拉普拉斯方差法检测模糊
  // 先转为灰度图
  final grayImg = img.grayscale(resized);
  double laplacianSum = 0;
  double laplacianSqSum = 0;
  int laplacianCount = 0;

  // 3×3 拉普拉斯算子: [0,1,0; 1,-4,1; 0,1,0]
  for (int y = 1; y < height - 1; y++) {
    for (int x = 1; x < width - 1; x++) {
      final center = grayImg.getPixel(x, y).r.toDouble();
      final top = grayImg.getPixel(x, y - 1).r.toDouble();
      final bottom = grayImg.getPixel(x, y + 1).r.toDouble();
      final left = grayImg.getPixel(x - 1, y).r.toDouble();
      final right = grayImg.getPixel(x + 1, y).r.toDouble();

      final laplacian = top + bottom + left + right - 4 * center;
      laplacianSum += laplacian;
      laplacianSqSum += laplacian * laplacian;
      laplacianCount++;
    }
  }

  final laplacianMean = laplacianSum / laplacianCount;
  final laplacianVariance = (laplacianSqSum / laplacianCount) - (laplacianMean * laplacianMean);

  // 3. 评估质量
  final bool isDark = avgBrightness < 50;
  final bool isBright = avgBrightness > 220;
  final bool isBlurry = laplacianVariance < 100;
  final bool isSlightlyDark = avgBrightness < 80;
  final bool isSlightlyBright = avgBrightness > 200;
  final bool isSlightlyBlurry = laplacianVariance < 200;

  final List<String> issues = [];
  if (isDark) {
    issues.add('图片较暗');
  } else if (isSlightlyDark) {
    issues.add('光线略暗');
  }
  if (isBright) {
    issues.add('图片过亮');
  } else if (isSlightlyBright) {
    issues.add('光线略亮');
  }
  if (isBlurry) {
    issues.add('图片模糊');
  } else if (isSlightlyBlurry) {
    issues.add('可能有轻微模糊');
  }

  QualityLevel level;
  String summary;
  if (isDark || isBright || isBlurry) {
    level = QualityLevel.poor;
    summary = issues.join('、');
  } else if (isSlightlyDark || isSlightlyBright || isSlightlyBlurry) {
    level = QualityLevel.medium;
    summary = issues.isNotEmpty ? issues.join('、') : '质量一般';
  } else {
    level = QualityLevel.good;
    summary = '图片清晰，亮度适中';
  }

  return ImageQualityResult(
    brightness: avgBrightness,
    sharpness: laplacianVariance,
    summary: summary,
    level: level,
  );
}

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
  bool _showGridGuide = false; // 是否显示网格引导

  /// 计算网格行列数
  (int rows, int cols) _calculateGridSize() {
    final count = widget.charset?.length ?? 0;
    if (count <= 0) return (0, 0);
    final cols = (sqrt(count)).ceil();
    final rows = (count / cols).ceil();
    return (rows, cols);
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

      // 显示预览页面
      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => _ImagePreviewScreen(
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final charset = widget.charset;
    final totalChars = charset?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('拍照 / 选图'),
        actions: [
          // 网格引导切换
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
                  _buildProgressBanner(colorScheme, totalChars),

                // 网格引导叠加层
                if (_showGridGuide && charset != null)
                  _buildGridGuideOverlay(colorScheme, charset),

                // 说明横幅
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '建议使用方格纸书写，每个格子写一个字符，拍照时保持平整清晰',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 已选图片缩略图
                if (_selectedImages.isNotEmpty)
                  _buildThumbnailStrip(colorScheme),

                if (_selectedImages.isNotEmpty) const Divider(height: 1),

                // 主内容区域
                Expanded(
                  child: _selectedImages.isEmpty
                      ? _buildEmptyState(colorScheme)
                      : _buildImageList(colorScheme),
                ),

                // 底部操作栏
                _buildBottomBar(colorScheme),
              ],
            ),
    );
  }

  /// 进度指示条
  Widget _buildProgressBanner(ColorScheme colorScheme, int totalChars) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.camera_alt, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '已拍摄 ${_selectedImages.length} / $totalChars 个字符',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          // 已完成字符绿色勾号
          ...List.generate(
            _selectedImages.length.clamp(0, 10),
            (i) => Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(Icons.check_circle, size: 16, color: Colors.green),
            ),
          ),
          if (_selectedImages.length > 10)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '+${_selectedImages.length - 10}',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  /// 网格引导叠加层
  Widget _buildGridGuideOverlay(ColorScheme colorScheme, List<String> charset) {
    final (rows, cols) = _calculateGridSize();
    if (rows == 0 || cols == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.grid_on, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '书写引导网格 ($cols×$rows)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '请按此布局在纸上书写',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 网格
          Padding(
            padding: const EdgeInsets.all(8),
            child: Table(
              border: TableBorder.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              defaultColumnWidth: const FlexColumnWidth(),
              children: List.generate(rows, (row) {
                return TableRow(
                  children: List.generate(cols, (col) {
                    final index = row * cols + col;
                    if (index >= charset.length) {
                      return const SizedBox(height: 48);
                    }
                    final char = charset[index];
                    final isCompleted = index < _selectedImages.length;
                    return Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? Colors.green.withValues(alpha: 0.1)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isCompleted)
                            Icon(Icons.check, size: 14, color: Colors.green)
                          else
                            Text(
                              char,
                              style: TextStyle(
                                fontSize: 18,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.4),
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 9,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// 缩略图条
  Widget _buildThumbnailStrip(ColorScheme colorScheme) {
    return Container(
      height: 140,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _selectedImages.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(_selectedImages[index].path),
                    width: 120,
                    height: 120,
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
                      decoration: BoxDecoration(
                        color: colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: colorScheme.onError,
                      ),
                    ),
                  ),
                ),
                // 编号
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                // 绿色勾号标记
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.check, size: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 底部操作栏：大圆形拍照按钮 + 相册按钮
  Widget _buildBottomBar(ColorScheme colorScheme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 相册选择按钮
            SizedBox(
              width: 64,
              height: 64,
              child: OutlinedButton(
                onPressed: _pickFromGallery,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_library, size: 24, color: colorScheme.primary),
                    const SizedBox(height: 2),
                    Text(
                      '相册',
                      style: TextStyle(fontSize: 11, color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
            // 大圆形拍照按钮
            SizedBox(
              width: 80,
              height: 80,
              child: ElevatedButton(
                onPressed: _takePhoto,
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  elevation: 4,
                ),
                child: const Icon(Icons.camera_alt, size: 36),
              ),
            ),
            const SizedBox(width: 24),
            // 批量相册选择
            SizedBox(
              width: 64,
              height: 64,
              child: OutlinedButton(
                onPressed: _pickMultiFromGallery,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_library_outlined, size: 24, color: colorScheme.primary),
                    const SizedBox(height: 2),
                    Text(
                      '多选',
                      style: TextStyle(fontSize: 11, color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
        // 批量添加时跳过预览，直接添加
        setState(() {
          _selectedImages.addAll(photos);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已添加 ${photos.length} 张图片')),
          );
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

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 80,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有选择图片',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击下方按钮拍照或从相册选图',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageList(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _selectedImages.length,
      itemBuilder: (context, index) {
        return Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(_selectedImages[index].path),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
            title: Text('图片 ${index + 1}'),
            subtitle: FutureBuilder<File>(
              future: Future.value(File(_selectedImages[index].path)),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return FutureBuilder<int>(
                    future: snapshot.data!.length(),
                    builder: (context, sizeSnapshot) {
                      if (sizeSnapshot.hasData) {
                        return Text(
                          '${(sizeSnapshot.data! / 1024).toStringAsFixed(1)} KB',
                        );
                      }
                      return const SizedBox();
                    },
                  );
                }
                return const SizedBox();
              },
            ),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline, color: colorScheme.error),
              onPressed: () => _removeImage(index),
            ),
          ),
        );
      },
    );
  }
}

/// 图片预览页面
class _ImagePreviewScreen extends StatelessWidget {
  final String imagePath;
  final ImageQualityResult quality;

  const _ImagePreviewScreen({
    required this.imagePath,
    required this.quality,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('图片预览'),
      ),
      body: Column(
        children: [
          // 质量检测结果
          _buildQualityBanner(colorScheme),

          // 可缩放的图片预览
          Expanded(
            child: InteractiveViewer(
              maxScale: 5.0,
              minScale: 0.5,
              child: Center(
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // 底部按钮
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('重新拍摄'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.check),
                      label: const Text('确认使用'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
      ),
    );
  }

  Widget _buildQualityBanner(ColorScheme colorScheme) {
    final Color bannerColor;
    final Color textColor;
    final IconData icon;
    final String emoji;

    switch (quality.level) {
      case QualityLevel.good:
        bannerColor = Colors.green.withValues(alpha: 0.1);
        textColor = Colors.green.shade800;
        icon = Icons.check_circle;
        emoji = '🟢';
        break;
      case QualityLevel.medium:
        bannerColor = Colors.orange.withValues(alpha: 0.1);
        textColor = Colors.orange.shade800;
        icon = Icons.warning_amber;
        emoji = '🟡';
        break;
      case QualityLevel.poor:
        bannerColor = Colors.red.withValues(alpha: 0.1);
        textColor = Colors.red.shade800;
        icon = Icons.error_outline;
        emoji = '🔴';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: bannerColor,
      child: Row(
        children: [
          Icon(icon, size: 20, color: textColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$emoji 质量检测: ${quality.summary}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '亮度: ${quality.brightness.toStringAsFixed(0)}  '
                  '清晰度: ${quality.sharpness.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
                if (quality.level == QualityLevel.poor) ...[
                  const SizedBox(height: 4),
                  Text(
                    '建议重新拍摄以获得更好的识别效果',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
