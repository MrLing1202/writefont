import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';

import '../models/font_project.dart';
import '../services/image_processor.dart';

/// 字形编辑界面 - 调节参数并实时预览
class GlyphEditorScreen extends StatefulWidget {
  final GlyphData glyph;

  const GlyphEditorScreen({super.key, required this.glyph});

  @override
  State<GlyphEditorScreen> createState() => _GlyphEditorScreenState();
}

class _GlyphEditorScreenState extends State<GlyphEditorScreen> {
  late GlyphData _glyph;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _glyph = widget.glyph;
    if (_glyph.originalImage != null && _glyph.contours.isEmpty) {
      _reprocess();
    }
  }

  void _reprocess() {
    if (_glyph.originalImage == null && _glyph.processedImage == null) return;

    setState(() => _isProcessing = true);

    final imageBytes = _glyph.originalImage ?? _glyph.processedImage!;
    try {
      final binarized = ImageProcessor.binarizeImage(
        imageBytes,
        threshold: _glyph.threshold,
      );
      final contours = ImageProcessor.extractContours(
        imageBytes,
        threshold: _glyph.threshold,
        smoothness: _glyph.smoothness,
      );

      setState(() {
        _glyph = _glyph.copyWith(
          processedImage: binarized,
          contours: contours,
        );
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
    }
  }

  void _takePhoto() async {
    try {
      final imagePicker = ImagePicker();
      final file = await imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _glyph = _glyph.copyWith(originalImage: bytes);
        });
        _reprocess();
      }
    } catch (e) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('编辑: ${_glyph.character}'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context, _glyph),
          child: const Text('保存'),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 大字符预览
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _isProcessing
                    ? const Center(child: CupertinoActivityIndicator())
                    : Center(
                        child: _glyph.processedImage != null
                            ? Image.memory(
                                _glyph.processedImage!,
                                height: 180,
                                fit: BoxFit.contain,
                              )
                            : Text(
                                _glyph.character,
                                style: const TextStyle(
                                  fontSize: 120,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                      ),
              ),
              const SizedBox(height: 24),

              // 轮廓预览
              if (_glyph.contours.isNotEmpty) ...[
                const Text(
                  '轮廓预览',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: CupertinoColors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CustomPaint(
                    painter: _ContourPreviewPainter(
                      contours: _glyph.contours,
                    ),
                    size: const Size(double.infinity, 150),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_glyph.contours.length} 条轮廓，${_glyph.contours.fold(0, (sum, c) => sum + c.length)} 个点',
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // 重新拍照按钮
              CupertinoButton.tinted(
                onPressed: _takePhoto,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(CupertinoIcons.camera, size: 20),
                    SizedBox(width: 8),
                    Text('重新拍照'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 参数调节区域
              _buildParameterSection(),

              const SizedBox(height: 20),

              // 包含/排除开关
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '包含在字体中',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '关闭后此字符不会出现在生成的字体中',
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.secondaryLabel,
                          ),
                        ),
                      ],
                    ),
                    CupertinoSwitch(
                      value: _glyph.isIncluded,
                      onChanged: (value) {
                        setState(() {
                          _glyph = _glyph.copyWith(isIncluded: value);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParameterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '参数调节',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          // 阈值
          _buildSlider(
            label: '二值化阈值',
            value: _glyph.threshold,
            min: 0,
            max: 255,
            onChanged: (v) {
              setState(() {
                _glyph = _glyph.copyWith(threshold: v);
              });
            },
            onChangeEnd: (_) => _reprocess(),
          ),
          const SizedBox(height: 12),

          // 平滑度
          _buildSlider(
            label: '轮廓平滑',
            value: _glyph.smoothness,
            min: 0,
            max: 1,
            displayValue: '${(_glyph.smoothness * 100).round()}%',
            onChanged: (v) {
              setState(() {
                _glyph = _glyph.copyWith(smoothness: v);
              });
            },
            onChangeEnd: (_) => _reprocess(),
          ),
          const SizedBox(height: 12),

          // 笔画粗细
          _buildSlider(
            label: '笔画粗细',
            value: _glyph.strokeWidth,
            min: 0.5,
            max: 2.0,
            displayValue: '${_glyph.strokeWidth.toStringAsFixed(1)}x',
            onChanged: (v) {
              setState(() {
                _glyph = _glyph.copyWith(strokeWidth: v);
              });
            },
            onChangeEnd: (_) => _reprocess(),
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
    String? displayValue,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            Text(
              displayValue ?? value.round().toString(),
              style: const TextStyle(
                fontSize: 14,
                color: CupertinoColors.activeBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        CupertinoSlider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

/// 轮廓预览画笔
class _ContourPreviewPainter extends CustomPainter {
  final List<List<Offset>> contours;

  _ContourPreviewPainter({required this.contours});

  @override
  void paint(Canvas canvas, Size size) {
    if (contours.isEmpty) return;

    // 计算边界
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final contour in contours) {
      for (final p in contour) {
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
        maxX = math.max(maxX, p.dx);
        maxY = math.max(maxY, p.dy);
      }
    }

    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;
    if (contentWidth <= 0 || contentHeight <= 0) return;

    final scale =
        math.min(size.width / contentWidth, size.height / contentHeight) * 0.8;
    final offsetX = (size.width - contentWidth * scale) / 2 - minX * scale;
    final offsetY = (size.height - contentHeight * scale) / 2 - minY * scale;

    final paint = Paint()
      ..color = CupertinoColors.activeGreen
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = CupertinoColors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.fill;

    for (final contour in contours) {
      if (contour.length < 2) continue;

      final path = Path();
      final first = Offset(
        contour[0].dx * scale + offsetX,
        contour[0].dy * scale + offsetY,
      );
      path.moveTo(first.dx, first.dy);

      for (int i = 1; i < contour.length; i++) {
        final point = Offset(
          contour[i].dx * scale + offsetX,
          contour[i].dy * scale + offsetY,
        );
        path.lineTo(point.dx, point.dy);
      }
      path.close();

      canvas.drawPath(path, paint);

      // 绘制控制点
      for (final point in contour) {
        canvas.drawCircle(
          Offset(point.dx * scale + offsetX, point.dy * scale + offsetY),
          2,
          pointPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
