import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/project.dart';
import '../services/storage_service.dart';
import '../widgets/bezier_glyph_painter.dart';
import 'font_test_screen.dart';

/// 字体实时预览页面
/// 用户输入文字后，使用已编辑的 GlyphData 轮廓实时渲染预览
class FontPreviewScreen extends StatefulWidget {
  /// 项目 ID，为 null 时自动选择最新项目
  final String? projectId;

  const FontPreviewScreen({super.key, this.projectId});

  @override
  State<FontPreviewScreen> createState() => _FontPreviewScreenState();
}

class _FontPreviewScreenState extends State<FontPreviewScreen> {
  final TextEditingController _textController = TextEditingController();
  final GlobalKey _previewKey = GlobalKey();
  final TransformationController _transformController = TransformationController();

  FontProject? _project;
  bool _isLoading = true;
  bool _isFullscreen = false;
  bool _isExporting = false;
  double _fontSize = 48;
  double _lineHeight = 1.5;
  int _bgColorIndex = 0; // 0=白, 1=黑, 2=灰

  /// 预览背景色选项
  static const _bgColors = [
    Colors.white,
    Color(0xFF1A1A1A),
    Color(0xFFE0E0E0),
  ];
  static const _bgLabels = ['白', '黑', '灰'];

  /// 快捷预设文本
  static const _presets = [
    '天地玄黄 宇宙洪荒',
    '永字八法',
    'WriteFont手迹造字',
  ];

  @override
  void initState() {
    super.initState();
    _textController.text = _presets[0];
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
      FontProject? project;
      if (widget.projectId != null) {
        project = await StorageService.loadProject(widget.projectId!);
      } else {
        // 自动选择最新项目
        final projects = await StorageService.loadProjects();
        if (projects.isNotEmpty) {
          project = projects.first;
        }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载项目失败: $e')),
        );
      }
    }
  }

  /// 切换全屏模式
  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
  }

  /// 截图保存为图片并分享
  Future<void> _sharePreview() async {
    try {
      final boundary = _previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/font_preview.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '字体预览',
        text: '手迹造字字体预览',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  /// 导出 TTF 字体文件并分享
  Future<void> _exportAndShareTtf() async {
    if (_project == null || _isExporting) return;

    setState(() => _isExporting = true);
    try {
      // 统计已编辑字符数
      final editedCount = _project!.glyphs.values
          .where((g) => g.contours.isNotEmpty)
          .length;

      if (editedCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有可导出的字符，请先编辑字符轮廓')),
          );
        }
        return;
      }

      // 生成 TTF 文件
      final filePath = await StorageService.exportTtf(_project!);

      // 分享 TTF 文件
      await StorageService.shareTtf(filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出 $editedCount 个字符的字体文件')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  /// 重置缩放
  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: const Text('字体预览'),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.text_fields),
                  tooltip: '字体测试',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FontTestScreen(project: _project),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '重新加载',
                  onPressed: _loadProject,
                ),
              ],
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _project == null
              ? _buildEmptyState(colorScheme, '没有找到项目')
              : _hasGlyphs
                  ? _buildPreviewBody(colorScheme)
                  : _buildEmptyState(colorScheme, '请先在字表中书写字符'),
      // 全屏模式下的浮动退出按钮
      floatingActionButton: _isFullscreen
          ? FloatingActionButton.small(
              onPressed: _toggleFullscreen,
              tooltip: '退出全屏',
              child: const Icon(Icons.fullscreen_exit),
            )
          : null,
    );
  }

  /// 是否有已编辑的字符轮廓数据
  bool get _hasGlyphs {
    if (_project == null) return false;
    return _project!.glyphs.values.any((g) => g.contours.isNotEmpty);
  }

  /// 构建空状态引导
  Widget _buildEmptyState(ColorScheme colorScheme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.text_fields,
              size: 80,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: TextStyle(
                fontSize: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '在字表中书写字符后即可预览字体效果',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建预览主体
  Widget _buildPreviewBody(ColorScheme colorScheme) {
    return Column(
      children: [
        // 文本输入区（全屏模式下隐藏）
        if (!_isFullscreen) _buildInputArea(colorScheme),

        // 预览渲染区
        Expanded(
          child: RepaintBoundary(
            key: _previewKey,
            child: Container(
              color: _bgColors[_bgColorIndex],
              child: InteractiveViewer(
                transformationController: _transformController,
                panEnabled: true,
                scaleEnabled: true,
                minScale: 0.5,
                maxScale: 5.0,
                child: _buildPreviewContent(colorScheme),
              ),
            ),
          ),
        ),

        // 底部工具栏（全屏模式下隐藏）
        if (!_isFullscreen) _buildToolbar(colorScheme),
      ],
    );
  }

  /// 构建文本输入区域
  Widget _buildInputArea(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 多行文本输入框
          TextField(
            controller: _textController,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: '输入要预览的文字…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              filled: true,
              fillColor: colorScheme.surface,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),

          // 提示文字
          Text(
            '输入文字预览字体效果',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),

          // 快捷预设按钮
          Wrap(
            spacing: 8,
            children: _presets.map((preset) {
              final isSelected = _textController.text == preset;
              return ActionChip(
                label: Text(
                  preset,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                backgroundColor: isSelected
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                onPressed: () {
                  setState(() => _textController.text = preset);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// 构建预览内容（逐字渲染）
  Widget _buildPreviewContent(ColorScheme colorScheme) {
    final text = _textController.text;
    if (text.isEmpty) {
      return Center(
        child: Text(
          '请输入文字',
          style: TextStyle(
            fontSize: 18,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    // 按行分组
    final lines = text.split('\n');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) {
          if (line.isEmpty) {
            // 空行占位
            return SizedBox(height: _fontSize * _lineHeight);
          }
          return Padding(
            padding: EdgeInsets.only(bottom: _fontSize * (_lineHeight - 1)),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              children: line.split('').map((char) {
                return _buildGlyphWidget(char, colorScheme);
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 构建单个字符的渲染部件
  Widget _buildGlyphWidget(String char, ColorScheme colorScheme) {
    // 根据背景色决定前景色
    final bool isDarkBg = _bgColorIndex == 1;
    final Color fgColor = isDarkBg ? Colors.white : colorScheme.onSurface;
    final Color placeholderBg = isDarkBg
        ? Colors.white.withValues(alpha: 0.1)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final Color placeholderFg = isDarkBg
        ? Colors.white.withValues(alpha: 0.3)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.3);

    // 查找对应的 GlyphData
    final glyph = _project!.glyphs[char];

    if (glyph == null || glyph.contours.isEmpty) {
      // 没有轮廓数据，显示占位方块
      return Container(
        width: _fontSize,
        height: _fontSize,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: placeholderBg,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          char,
          style: TextStyle(
            fontSize: _fontSize * 0.6,
            color: placeholderFg,
          ),
        ),
      );
    }

    // 有轮廓数据，用 CustomPainter 渲染贝塞尔曲线
    return SizedBox(
      width: _fontSize,
      height: _fontSize,
      child: CustomPaint(
        painter: BezierGlyphPainter(
          glyph: glyph,
          fillColor: fgColor,
        ),
      ),
    );
  }

  /// 构建底部工具栏
  Widget _buildToolbar(ColorScheme colorScheme) {
    final text = _textController.text;
    final charCount = text.replaceAll(RegExp(r'\s'), '').length;
    final glyphCount = _project != null
        ? text.split('').where((c) => _project!.glyphs[c]?.contours.isNotEmpty == true).length
        : 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 字号调节 + 预设按钮
          Row(
            children: [
              Icon(Icons.format_size, size: 20, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                '字号',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 12,
                  max: 120,
                  divisions: 108,
                  label: '${_fontSize.round()}pt',
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
              ),
              // 字号预设按钮
              ...([24, 48, 72, 96].map((size) {
                final isSelected = _fontSize.round() == size;
                return Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _fontSize = size.toDouble()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primary.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(alpha: 0.4),
                          width: isSelected ? 1.5 : 0.5,
                        ),
                      ),
                      child: Text(
                        '$size',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              })),
            ],
          ),

          // 行距调节 + 背景色切换 + 字符统计
          Row(
            children: [
              Icon(Icons.format_line_spacing, size: 20, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                '行距',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
              Expanded(
                child: Slider(
                  value: _lineHeight,
                  min: 1.0,
                  max: 3.0,
                  divisions: 20,
                  label: _lineHeight.toStringAsFixed(1),
                  onChanged: (v) => setState(() => _lineHeight = v),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  _lineHeight.toStringAsFixed(1),
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),

          // 背景色切换 + 字符统计
          Row(
            children: [
              // 背景色切换
              Icon(Icons.palette_outlined, size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              ...List.generate(3, (i) {
                final isSelected = _bgColorIndex == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _bgColorIndex = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(alpha: 0.4),
                          width: isSelected ? 1.5 : 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _bgColors[i],
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _bgLabels[i],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const Spacer(),
              // 字符统计
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.text_fields, size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      '$charCount 字 · $glyphCount 有字形',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 操作按钮
          Row(
            children: [
              // 重置缩放
              TextButton.icon(
                onPressed: _resetZoom,
                icon: const Icon(Icons.zoom_out_map, size: 18),
                label: const Text('重置缩放'),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),

              // 全屏预览
              FilledButton.tonalIcon(
                onPressed: _toggleFullscreen,
                icon: const Icon(Icons.fullscreen, size: 20),
                label: const Text('全屏预览'),
              ),
              const SizedBox(width: 8),

              // 导出字体按钮
              _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: _exportAndShareTtf,
                      icon: const Icon(Icons.font_download, size: 18),
                      label: const Text('导出'),
                    ),
              const SizedBox(width: 8),

              // 分享预览图按钮
              FilledButton.icon(
                onPressed: _sharePreview,
                icon: const Icon(Icons.share, size: 18),
                label: const Text('分享'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
