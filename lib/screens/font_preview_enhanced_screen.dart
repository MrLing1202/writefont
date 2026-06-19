import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/project.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bezier_glyph_painter.dart';
import 'preview/templates.dart';

/// 增强字体预览页面
/// 支持多字号、多场景、实时调节、手势缩放、截图分享
class FontPreviewEnhancedScreen extends StatefulWidget {
  final FontProject? project;

  const FontPreviewEnhancedScreen({super.key, this.project});

  @override
  State<FontPreviewEnhancedScreen> createState() =>
      _FontPreviewEnhancedScreenState();
}

class _FontPreviewEnhancedScreenState extends State<FontPreviewEnhancedScreen> {
  final TextEditingController _textController = TextEditingController();
  final GlobalKey _previewKey = GlobalKey();
  final TransformationController _transformController =
      TransformationController();

  FontProject? _project;
  bool _isLoading = true;

  // 预览参数
  double _lineHeight = 1.5;
  double _letterSpacing = 0.0;
  int _bgColorIndex = 0;

  // 场景选择
  int _selectedSceneIndex = 0; // 0=自定义, 1+=模板索引
  bool _inputExpanded = true;

  /// 背景色选项
  static const _bgColors = [
    Colors.white,
    Color(0xFFF0F0F0),
    Color(0xFF505050),
    Color(0xFF1A1A1A),
  ];

  static const _bgLabels = ['白色', '浅灰', '深灰', '黑色'];

  /// 多字号预览尺寸
  static const _previewSizes = [12.0, 16.0, 24.0, 32.0, 48.0, 64.0];

  @override
  void initState() {
    super.initState();
    _textController.text = '手迹造字';
    _loadProject();
  }

  @override
  void dispose() {
    _textController.dispose();
    _transformController.dispose();
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
      final file = File('${tempDir.path}/font_preview_enhanced.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '增强字体预览',
        text: '手迹造字 · 增强预览',
      );
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '分享失败: $e');
      }
    }
  }

  /// 重置缩放
  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  /// 获取当前预览文本
  String get _previewText {
    if (_selectedSceneIndex == 0) {
      return _textController.text;
    }
    final templateIndex = _selectedSceneIndex - 1;
    if (templateIndex < PreviewTemplates.all.length) {
      return PreviewTemplates.all[templateIndex].content;
    }
    return _textController.text;
  }

  /// 是否有已编辑的字符轮廓数据
  bool get _hasGlyphs {
    if (_project == null) return false;
    return _project!.glyphs.values.any((g) => g.contours.isNotEmpty);
  }

  /// 当前背景是否为深色
  bool get _isDarkBg => _bgColorIndex >= 2;

  /// 前景色
  Color get _fgColor => _isDarkBg ? Colors.white : WFColors.textPrimary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WFAppBar(
        title: '增强预览',
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
            Icon(Icons.dashboard_customize, size: 80, color: WFColors.textLight),
            const SizedBox(height: 24),
            Text(
              message,
              style: TextStyle(fontSize: 18, color: WFColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '在字表中书写字符后即可使用增强预览',
              style: TextStyle(fontSize: 14, color: WFColors.textLight),
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
        // 输入区（可折叠）
        _buildInputSection(),

        // 场景选择栏
        _buildSceneSelector(),

        // 预览主体
        Expanded(
          child: _buildPreviewArea(),
        ),

        // 底部控制栏
        _buildBottomControls(),
      ],
    );
  }

  /// 输入区（可折叠）
  Widget _buildInputSection() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Column(
        children: [
          // 折叠按钮
          InkWell(
            onTap: () => setState(() => _inputExpanded = !_inputExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: WFColors.bgCard,
              child: Row(
                children: [
                  Icon(Icons.edit, size: 18, color: WFColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    '输入设置',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WFColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _inputExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: WFColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 展开内容
          if (_inputExpanded) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              color: WFColors.bgCard,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 输入框
                  TextField(
                    controller: _textController,
                    maxLines: 2,
                    minLines: 1,
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
                      fillColor: WFColors.bgPrimary,
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),

                  // 背景色选择
                  Row(
                    children: [
                      Text(
                        '背景',
                        style: TextStyle(
                          fontSize: 13,
                          color: WFColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ...List.generate(_bgColors.length, (index) {
                        final selected = _bgColorIndex == index;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _bgColorIndex = index),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _bgColors[index],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? WFColors.primary
                                      : WFColors.textLight
                                          .withValues(alpha: 0.4),
                                  width: selected ? 2.5 : 1,
                                ),
                              ),
                              child: selected
                                  ? Icon(
                                      Icons.check,
                                      size: 16,
                                      color: _isDarkBg
                                          ? Colors.white
                                          : WFColors.primary,
                                    )
                                  : null,
                            ),
                          ),
                        );
                      }),
                      const SizedBox(width: 8),
                      Text(
                        _bgLabels[_bgColorIndex],
                        style: TextStyle(
                          fontSize: 12,
                          color: WFColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  /// 场景选择栏
  Widget _buildSceneSelector() {
    return Container(
      height: 48,
      color: WFColors.bgPrimary,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          // 自定义场景
          _buildSceneChip(
            label: '自定义',
            icon: Icons.edit,
            index: 0,
          ),
          // 模板场景
          ...List.generate(PreviewTemplates.all.length, (i) {
            final template = PreviewTemplates.all[i];
            return _buildSceneChip(
              label: template.name,
              icon: template.category.icon,
              index: i + 1,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSceneChip({
    required String label,
    required IconData icon,
    required int index,
  }) {
    final selected = _selectedSceneIndex == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        avatar: Icon(
          icon,
          size: 16,
          color: selected ? Colors.white : WFColors.textSecondary,
        ),
        selected: selected,
        selectedColor: WFColors.primary,
        labelStyle: TextStyle(
          fontSize: 13,
          color: selected ? Colors.white : WFColors.textPrimary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
        backgroundColor: WFColors.bgCard,
        side: BorderSide(
          color: selected
              ? WFColors.primary
              : WFColors.textLight.withValues(alpha: 0.3),
        ),
        onSelected: (_) {
          setState(() => _selectedSceneIndex = index);
          // 切换到模板时折叠输入区
          if (index > 0 && _inputExpanded) {
            setState(() => _inputExpanded = false);
          }
        },
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// 预览主体区域
  Widget _buildPreviewArea() {
    return RepaintBoundary(
      key: _previewKey,
      child: Container(
        color: _bgColors[_bgColorIndex],
        child: InteractiveViewer(
          transformationController: _transformController,
          panEnabled: true,
          scaleEnabled: true,
          minScale: 0.5,
          maxScale: 5.0,
          child: _selectedSceneIndex == 0
              ? _buildCustomPreview()
              : _buildTemplatePreview(),
        ),
      ),
    );
  }

  /// 自定义文本预览 - 多字号并排
  Widget _buildCustomPreview() {
    final text = _textController.text;
    if (text.isEmpty) {
      return Center(
        child: Text(
          '请输入文字',
          style: TextStyle(
            fontSize: 18,
            color: _isDarkBg
                ? Colors.white.withValues(alpha: 0.4)
                : WFColors.textSecondary.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _previewSizes.map((size) {
          return _buildSizePreview(text, size);
        }).toList(),
      ),
    );
  }

  /// 单个字号的预览块
  Widget _buildSizePreview(String text, double fontSize) {
    return Padding(
      padding: EdgeInsets.only(bottom: fontSize * 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 字号标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _isDarkBg
                  ? Colors.white.withValues(alpha: 0.12)
                  : WFColors.textPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${fontSize.round()}px',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _isDarkBg
                    ? Colors.white.withValues(alpha: 0.6)
                    : WFColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 渲染文字
          _buildTextPreview(text, fontSize),
        ],
      ),
    );
  }

  /// 模板场景预览
  Widget _buildTemplatePreview() {
    final templateIndex = _selectedSceneIndex - 1;
    if (templateIndex >= PreviewTemplates.all.length) {
      return const SizedBox.shrink();
    }

    final template = PreviewTemplates.all[templateIndex];
    final category = template.category;
    final text = template.content;

    // 根据场景类型选择合适的字号和行高
    double fontSize;
    double effectiveLineHeight;
    switch (category) {
      case PreviewCategory.body:
        fontSize = 24;
        effectiveLineHeight = _lineHeight;
        break;
      case PreviewCategory.headline:
        fontSize = 48;
        effectiveLineHeight = 1.3;
        break;
      case PreviewCategory.table:
        fontSize = 20;
        effectiveLineHeight = 1.8;
        break;
      case PreviewCategory.code:
        fontSize = 18;
        effectiveLineHeight = 1.6;
        break;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 场景标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: WFColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(category.icon, size: 14, color: WFColors.info),
                const SizedBox(width: 6),
                Text(
                  '${category.label} · ${template.name}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: WFColors.info,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 渲染内容
          _buildTextPreview(text, fontSize, lineHeight: effectiveLineHeight),
        ],
      ),
    );
  }

  /// 渲染文字预览（通用）
  Widget _buildTextPreview(String text, double fontSize, {double? lineHeight}) {
    final effectiveLineHeight = lineHeight ?? _lineHeight;
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
              : WFColors.textLight.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _isDarkBg
                ? Colors.white.withValues(alpha: 0.15)
                : WFColors.textLight.withValues(alpha: 0.3),
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
                : WFColors.textLight.withValues(alpha: 0.5),
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
        color: WFColors.bgCard,
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
              max: 12.0,
              divisions: 16,
              format: (v) => v.toStringAsFixed(1),
              onChanged: (v) => setState(() => _letterSpacing = v),
            ),
            const SizedBox(height: 4),
            // 重置缩放按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _resetZoom,
                  icon: Icon(Icons.zoom_out_map, size: 16, color: WFColors.textSecondary),
                  label: Text(
                    '重置缩放',
                    style: TextStyle(fontSize: 12, color: WFColors.textSecondary),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
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
        Icon(icon, size: 18, color: WFColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: WFColors.textSecondary,
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
              color: WFColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
