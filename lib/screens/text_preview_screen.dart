import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bezier_glyph_painter.dart';

/// 自定义文本预览页面
///
/// 让用户输入任意文字，用自己制作的字体实时预览效果。
/// 支持字号调节、行距/字距调节、背景色切换、截图分享。
class TextPreviewScreen extends StatefulWidget {
  final FontProject? project;

  const TextPreviewScreen({super.key, this.project});

  @override
  State<TextPreviewScreen> createState() => _TextPreviewScreenState();
}

class _TextPreviewScreenState extends State<TextPreviewScreen> {
  final TextEditingController _textController = TextEditingController();
  final GlobalKey _previewKey = GlobalKey();

  FontProject? _project;
  bool _isLoading = true;

  // 预览参数
  double _fontSize = 48;
  double _lineHeight = 1.5;
  double _letterSpacing = 2.0;
  int _bgColorIndex = 0;
  Color _customBgColor = const Color(0xFFF5F5DC); // 自定义背景色（米色）

  /// 背景色选项
  static const _bgColors = [
    Colors.white,
    Color(0xFFF0F0F0),
    Color(0xFFF5F5DC),
    Color(0xFF505050),
    Color(0xFF1A1A1A),
  ];

  static const _bgLabels = ['白色', '浅灰', '米色', '深灰', '黑色'];

  @override
  void initState() {
    super.initState();
    _textController.text = '你好世界\nHello World';
    _loadProject();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// 加载项目数据
  Future<void> _loadProject() async {
    setState(() => _isLoading = true);
    try {
      FontProject? project = widget.project;
      if (project == null) {
        final projects = await StorageService.loadProjects();
        if (projects.isNotEmpty) {
          project = projects.first;
        }
      } else if (project.id.isNotEmpty) {
        project = await StorageService.loadProject(project.id) ?? project;
      }
      if (mounted) {
        setState(() {
          _project = project;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        WFSnackBar.error(context, '加载项目失败: $e');
      }
    }
  }

  /// 截图分享
  Future<void> _sharePreview() async {
    try {
      final boundary = _previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/text_preview.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '自定义文本预览',
        text: '手迹造字 · 自定义文本预览',
      );
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '分享失败: $e');
      }
    }
  }

  /// 是否有已编辑的字符轮廓数据
  bool get _hasGlyphs {
    if (_project == null) return false;
    return _project!.glyphs.values.any((g) => g.contours.isNotEmpty);
  }

  /// 当前背景是否为深色
  bool get _isDarkBg => _bgColorIndex >= 3;

  /// 当前背景色
  Color get _currentBgColor {
    if (_bgColorIndex == _bgColors.length) {
      return _customBgColor;
    }
    return _bgColors[_bgColorIndex];
  }

  /// 前景色
  Color get _fgColor =>
      _isDarkBg ? Colors.white : WFColors.textPrimaryColor(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WFAppBar(
        title: '自定义文本预览',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新加载',
            onPressed: _loadProject,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '截图分享',
            onPressed: _sharePreview,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _project == null
              ? _buildEmptyState('没有找到项目')
              : _hasGlyphs
                  ? _buildPreviewBody()
                  : _buildEmptyState('请先在字表中书写字符'),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.text_snippet,
                size: 80, color: WFColors.textLightColor(context)),
            const SizedBox(height: 24),
            Text(
              message,
              style: TextStyle(
                  fontSize: 18, color: WFColors.textSecondaryColor(context)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '在字表中书写字符后即可使用自定义文本预览',
              style: TextStyle(
                  fontSize: 14, color: WFColors.textLightColor(context)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewBody() {
    return Column(
      children: [
        // 输入区
        _buildInputSection(),
        // 预览主体
        Expanded(
          child: _buildPreviewArea(),
        ),
        // 底部控制栏
        _buildBottomControls(),
      ],
    );
  }

  /// 输入区
  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: WFColors.bgCardColor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit,
                  size: 18, color: WFColors.textSecondaryColor(context)),
              const SizedBox(width: 8),
              Text(
                '输入文字',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
              const Spacer(),
              // 背景色选择
              ...List.generate(_bgColors.length, (index) {
                final selected = _bgColorIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _bgColorIndex = index),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _bgColors[index],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? WFColors.primary
                              : WFColors.textLightColor(context)
                                  .withValues(alpha: 0.4),
                          width: selected ? 2.5 : 1,
                        ),
                      ),
                      child: selected
                          ? Icon(
                              Icons.check,
                              size: 14,
                              color:
                                  _isDarkBg ? Colors.white : WFColors.primary,
                            )
                          : null,
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 10),
          // 输入框
          TextField(
            controller: _textController,
            maxLines: 4,
            minLines: 2,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: '输入想预览的文字…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              filled: true,
              fillColor: WFColors.bgPrimaryColor(context),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  /// 预览主体区域
  Widget _buildPreviewArea() {
    final text = _textController.text;
    if (text.isEmpty) {
      return Center(
        child: Text(
          '请输入文字',
          style: TextStyle(
            fontSize: 18,
            color: _isDarkBg
                ? Colors.white.withValues(alpha: 0.4)
                : WFColors.textSecondaryColor(context).withValues(alpha: 0.4),
          ),
        ),
      );
    }

    return RepaintBoundary(
      key: _previewKey,
      child: Container(
        color: _currentBgColor,
        width: double.infinity,
        height: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _buildTextPreview(text, _fontSize),
        ),
      ),
    );
  }

  /// 渲染文字预览
  Widget _buildTextPreview(String text, double fontSize) {
    final effectiveLineHeight = _lineHeight;
    final lines = text.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.isEmpty) {
          return SizedBox(height: fontSize * effectiveLineHeight);
        }
        return Padding(
          padding: EdgeInsets.only(bottom: fontSize * (effectiveLineHeight - 1)),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            children: line.split('').map((char) {
              return _buildGlyphWidget(char, fontSize);
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  /// 构建单个字符的渲染部件
  Widget _buildGlyphWidget(String char, double fontSize) {
    final glyph = _project!.glyphs[char];
    final effectiveFontSize = fontSize + _letterSpacing;

    if (glyph == null || glyph.contours.isEmpty) {
      // 无轮廓数据，显示占位
      return Container(
        width: effectiveFontSize,
        height: effectiveFontSize,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: _isDarkBg
              ? Colors.white.withValues(alpha: 0.08)
              : WFColors.textLightColor(context).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _isDarkBg
                ? Colors.white.withValues(alpha: 0.15)
                : WFColors.textLightColor(context).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          char,
          style: TextStyle(
            fontSize: fontSize * 0.6,
            color: _isDarkBg
                ? Colors.white.withValues(alpha: 0.25)
                : WFColors.textLightColor(context).withValues(alpha: 0.5),
          ),
        ),
      );
    }

    // 有轮廓数据，用贝塞尔曲线渲染
    return SizedBox(
      width: effectiveFontSize,
      height: effectiveFontSize,
      child: CustomPaint(
        painter: BezierGlyphPainter(
          glyph: glyph,
          fillColor: _fgColor,
        ),
      ),
    );
  }

  /// 底部控制栏
  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: WFColors.bgCardColor(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 字号调节
            _buildSliderRow(
              icon: Icons.format_size,
              label: '字号',
              value: _fontSize,
              min: 12,
              max: 120,
              divisions: 54,
              format: (v) => '${v.round()}',
              onChanged: (v) => setState(() => _fontSize = v),
            ),
            const SizedBox(height: 4),
            // 行高调节
            _buildSliderRow(
              icon: Icons.format_line_spacing,
              label: '行高',
              value: _lineHeight,
              min: 1.0,
              max: 3.0,
              divisions: 20,
              format: (v) => v.toStringAsFixed(1),
              onChanged: (v) => setState(() => _lineHeight = v),
            ),
            const SizedBox(height: 4),
            // 字距调节
            _buildSliderRow(
              icon: Icons.space_bar,
              label: '字距',
              value: _letterSpacing,
              min: -4.0,
              max: 20.0,
              divisions: 24,
              format: (v) => v.toStringAsFixed(1),
              onChanged: (v) => setState(() => _letterSpacing = v),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建滑块行
  Widget _buildSliderRow({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) format,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: WFColors.textSecondaryColor(context)),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: WFColors.textSecondaryColor(context),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: WFColors.primary,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            format(value),
            style: TextStyle(
              fontSize: 12,
              color: WFColors.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
