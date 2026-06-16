import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart' as picker;

import '../models/font_project.dart';
import '../services/image_processor.dart';

/// ImageSource 枚举
enum ImageSource { camera, gallery }

/// 拍照/选图界面
class CaptureScreen extends StatefulWidget {
  final ImageSource source;

  const CaptureScreen({super.key, required this.source});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final picker.ImagePicker _picker = picker.ImagePicker();
  Uint8List? _imageBytes;
  List<Uint8List> _extractedRegions = [];
  bool _isProcessing = false;
  String? _errorMessage;
  double _threshold = 128.0;
  int _gridCols = 1; // 网格列数（手动模式）

  @override
  void initState() {
    super.initState();
    _pickImage();
  }

  Future<void> _pickImage() async {
    try {
      final pickerSource = widget.source == ImageSource.camera
          ? picker.ImageSource.camera
          : picker.ImageSource.gallery;
      final picker.XFile? file = await _picker.pickImage(
        source: pickerSource,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );

      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _imageBytes = bytes;
        });
        _processImage();
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _errorMessage = '无法获取图片: $e';
      });
    }
  }

  void _processImage() {
    if (_imageBytes == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // 二值化图片
      final binarized = ImageProcessor.binarizeImage(
        _imageBytes!,
        threshold: _threshold,
      );

      // 提取字符区域
      final regions = ImageProcessor.extractCharacterRegions(
        _imageBytes!,
        threshold: _threshold,
        minSize: 20,
        maxSize: 600,
      );

      setState(() {
        _extractedRegions = regions.isEmpty ? [binarized] : regions;
        _isProcessing = false;
      });

      if (regions.isEmpty) {
        setState(() {
          _errorMessage = '未检测到独立字符区域，请调整阈值或手动选择';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = '处理图片时出错: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('图片识别'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        trailing: _extractedRegions.isNotEmpty
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _confirmSelection,
                child: const Text('确认'),
              )
            : null,
      ),
      child: SafeArea(
        child: _imageBytes == null
            ? const Center(child: CupertinoActivityIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 原始图片预览
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _imageBytes!,
                        height: 200,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 阈值调节
                    _buildThresholdSlider(),
                    const SizedBox(height: 20),

                    // 处理状态
                    if (_isProcessing)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          children: [
                            CupertinoActivityIndicator(),
                            SizedBox(height: 12),
                            Text('正在识别字符...'),
                          ],
                        ),
                      ),

                    // 错误信息
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemYellow.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              CupertinoIcons.exclamationmark_triangle,
                              color: CupertinoColors.systemOrange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: CupertinoColors.systemOrange,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 重新处理按钮
                    const SizedBox(height: 16),
                    CupertinoButton.filled(
                      onPressed: _processImage,
                      child: const Text('重新识别'),
                    ),

                    // 提取的字符区域
                    if (_extractedRegions.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        '识别到 ${_extractedRegions.length} 个字符',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '请输入每个字符对应的汉字',
                        style: TextStyle(
                          fontSize: 14,
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildExtractedRegionsGrid(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildThresholdSlider() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '二值化阈值',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _threshold.round().toString(),
                style: const TextStyle(
                  fontSize: 15,
                  color: CupertinoColors.activeBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CupertinoSlider(
            value: _threshold,
            min: 0,
            max: 255,
            divisions: 255,
            onChanged: (value) {
              setState(() {
                _threshold = value;
              });
            },
            onChangeEnd: (_) => _processImage(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '深色',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.tertiaryLabel,
                ),
              ),
              Text(
                '浅色',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.tertiaryLabel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedRegionsGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: _extractedRegions.length,
      itemBuilder: (context, index) {
        return _buildRegionCard(index);
      },
    );
  }

  Widget _buildRegionCard(int index) {
    final textController = TextEditingController();
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CupertinoColors.systemGrey4),
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.memory(
                _extractedRegions[index],
                fit: BoxFit.contain,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: CupertinoTextField(
              controller: textController,
              placeholder: '输入字符',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              onChanged: (value) {
                // 存储字符对应关系
                if (value.isNotEmpty) {
                  _characterMap[index] = value[0];
                } else {
                  _characterMap.remove(index);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // 字符映射: region index -> character
  final Map<int, String> _characterMap = {};

  void _confirmSelection() {
    final List<GlyphData> result = [];

    for (int i = 0; i < _extractedRegions.length; i++) {
      String character;
      if (_characterMap.containsKey(i)) {
        character = _characterMap[i]!;
      } else {
        // 如果没有输入字符，使用序号作为临时标识
        character = String.fromCharCode(0x4E00 + i); // 使用连续中文字符
      }

      // 提取轮廓
      final contours = ImageProcessor.extractContours(
        _extractedRegions[i],
        threshold: _threshold,
      );

      result.add(GlyphData(
        character: character,
        processedImage: _extractedRegions[i],
        contours: contours,
        threshold: _threshold,
      ));
    }

    Navigator.pop(context, result);
  }
}
