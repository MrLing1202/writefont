import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/font_project.dart';
import '../services/ttf_builder.dart';

/// 字体预览与导出界面
class FontPreviewScreen extends StatefulWidget {
  final FontProject project;

  const FontPreviewScreen({super.key, required this.project});

  @override
  State<FontPreviewScreen> createState() => _FontPreviewScreenState();
}

class _FontPreviewScreenState extends State<FontPreviewScreen> {
  final TextEditingController _previewTextController = TextEditingController();
  double _previewFontSize = 48.0;
  bool _isGenerating = false;
  bool _isGenerated = false;
  String? _generatedFilePath;
  String _previewText = '字海无涯\n勤为舟';
  Uint8List? _fontBytes;

  @override
  void initState() {
    super.initState();
    _previewTextController.text = _previewText;
  }

  @override
  void dispose() {
    _previewTextController.dispose();
    super.dispose();
  }

  Future<void> _generateFont() async {
    if (widget.project.includedGlyphCount == 0) {
      _showAlert('无法生成', '请先添加一些字符到字库中');
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      // 生成 TTF
      final ttfBytes = TtfBuilder.build(widget.project);

      // 保存到临时目录
      final dir = await getTemporaryDirectory();
      final fileName =
          '${widget.project.name.replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), '_')}.ttf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(ttfBytes);

      setState(() {
        _fontBytes = ttfBytes;
        _generatedFilePath = file.path;
        _isGenerating = false;
        _isGenerated = true;
      });

      _showAlert('生成成功', '字体已生成，共 ${widget.project.includedGlyphCount} 个字符');
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });
      _showAlert('生成失败', '错误: $e');
    }
  }

  Future<void> _shareFont() async {
    if (_generatedFilePath == null) return;

    try {
      await Share.shareXFiles(
        [XFile(_generatedFilePath!)],
        subject: '${widget.project.name} - 手迹造字',
        text: '我用「手迹造字」生成了手写字体「${widget.project.name}」，快来试试吧！',
      );
    } catch (e) {
      _showAlert('分享失败', '错误: $e');
    }
  }

  void _showAlert(String title, String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 预览文本输入
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '预览文本',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CupertinoTextField(
                    controller: _previewTextController,
                    maxLines: 3,
                    placeholder: '输入要预览的文字',
                    onChanged: (value) {
                      setState(() {
                        _previewText = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 字号调节
            Container(
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
                        '预览字号',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_previewFontSize.round()} pt',
                        style: const TextStyle(
                          fontSize: 14,
                          color: CupertinoColors.activeBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CupertinoSlider(
                    value: _previewFontSize,
                    min: 12,
                    max: 120,
                    divisions: 108,
                    onChanged: (value) {
                      setState(() {
                        _previewFontSize = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 预览区域
            Container(
              constraints: const BoxConstraints(minHeight: 200),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: CupertinoColors.systemGrey4,
                ),
              ),
              child: Column(
                children: [
                  if (_previewText.isEmpty)
                    const Text(
                      '输入文字后即可预览',
                      style: TextStyle(
                        color: CupertinoColors.systemGrey,
                        fontSize: 16,
                      ),
                    )
                  else
                    ..._buildPreviewLines(),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 字形缩略图网格
            if (widget.project.glyphs.isNotEmpty) ...[
              Text(
                '已收录字符 (${widget.project.includedGlyphCount}/${widget.project.glyphs.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.project.glyphs.map((glyph) {
                  return Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: glyph.isIncluded
                          ? CupertinoColors.systemGrey6
                          : CupertinoColors.systemGrey5,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: glyph.isIncluded
                            ? CupertinoColors.activeBlue
                            : CupertinoColors.systemGrey4,
                      ),
                    ),
                    child: Center(
                      child: glyph.processedImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                glyph.processedImage!,
                                width: 36,
                                height: 36,
                                fit: BoxFit.contain,
                              ),
                            )
                          : Text(
                              glyph.character,
                              style: TextStyle(
                                fontSize: 20,
                                color: glyph.isIncluded
                                    ? CupertinoColors.label
                                    : CupertinoColors.systemGrey,
                              ),
                            ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],

            // 生成按钮
            CupertinoButton.filled(
              onPressed: _isGenerating ? null : _generateFont,
              child: _isGenerating
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CupertinoActivityIndicator(
                          color: CupertinoColors.white,
                        ),
                        SizedBox(width: 12),
                        Text('正在生成...'),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.textformat, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _isGenerated ? '重新生成字体' : '生成字体',
                          style: const TextStyle(fontSize: 17),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),

            // 分享按钮
            if (_isGenerated)
              CupertinoButton.tinted(
                onPressed: _shareFont,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.share, size: 20),
                    SizedBox(width: 8),
                    Text('分享字体文件', style: TextStyle(fontSize: 17)),
                  ],
                ),
              ),

            // 生成信息
            if (_isGenerated && _generatedFilePath != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CupertinoColors.activeGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.check_mark_circled,
                            color: CupertinoColors.activeGreen,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '字体已生成',
                            style: const TextStyle(
                              color: CupertinoColors.activeGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '字符数: ${widget.project.includedGlyphCount}',
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ),
                      Text(
                        '文件路径: $_generatedFilePath',
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.tertiaryLabel,
                        ),
                      ),
                      if (_fontBytes != null)
                        Text(
                          '文件大小: ${(_fontBytes!.length / 1024).toStringAsFixed(1)} KB',
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.tertiaryLabel,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // 使用说明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💡 使用提示',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildTip('1. 建议使用白纸黑字书写，背景干净清晰'),
                  _buildTip('2. 每个字符单独书写，保持间距'),
                  _buildTip('3. 调整阈值可以改善识别效果'),
                  _buildTip('4. 生成的 TTF 字体可以安装到任何设备'),
                  _buildTip('5. 通过 AirDrop 可以快速传输到 Mac 安装'),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPreviewLines() {
    // 使用用户字形的字符进行预览
    final lines = _previewText.split('\n');
    return lines.map((line) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Wrap(
          children: line.characters.map((char) {
            final glyph = widget.project.glyphs
                .where((g) => g.character == char && g.isIncluded)
                .toList();

            if (glyph.isNotEmpty && glyph.first.processedImage != null) {
              // 使用用户字形预览
              return Container(
                width: _previewFontSize,
                height: _previewFontSize,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                child: Image.memory(
                  glyph.first.processedImage!,
                  fit: BoxFit.contain,
                ),
              );
            } else {
              // 使用默认字体
              return Container(
                width: _previewFontSize,
                height: _previewFontSize,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                child: Center(
                  child: Text(
                    char,
                    style: TextStyle(
                      fontSize: _previewFontSize * 0.8,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ),
              );
            }
          }).toList(),
        ),
      );
    }).toList();
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel,
        ),
      ),
    );
  }
}
