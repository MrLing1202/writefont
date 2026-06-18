import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/project.dart';
import '../services/storage_service.dart';
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
              color: colorScheme.surface,
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
    // 查找对应的 GlyphData
    final glyph = _project!.glyphs[char];

    if (glyph == null || glyph.contours.isEmpty) {
      // 没有轮廓数据，显示灰色占位方块
      return Container(
        width: _fontSize,
        height: _fontSize,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          char,
          style: TextStyle(
            fontSize: _fontSize * 0.6,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ),
      );
    }

    // 有轮廓数据，用 CustomPainter 渲染贝塞尔曲线
    return SizedBox(
      width: _fontSize,
      height: _fontSize,
      child: CustomPaint(
        painter: _GlyphPainter(
          glyph: glyph,
          fillColor: colorScheme.onSurface,
        ),
      ),
    );
  }

  /// 构建底部工具栏
  Widget _buildToolbar(ColorScheme colorScheme) {
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
          // 字号调节
          Row(
            children: [
              Icon(Icons.format_size, size: 20, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                '字号',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
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
              SizedBox(
                width: 48,
                child: Text(
                  '${_fontSize.round()}',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),

          // 行距调节
          Row(
            children: [
              Icon(Icons.format_line_spacing, size: 20, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                '行距',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
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
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),

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

/// 贝塞尔曲线字形绘制器
/// 遍历 GlyphData 的 contours，将 on-curve / off-curve 点用
/// 二次贝塞尔曲线连接，使用 nonZero 填充规则处理内外轮廓。
class _GlyphPainter extends CustomPainter {
  final GlyphData glyph;
  final Color fillColor;

  _GlyphPainter({
    required this.glyph,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (glyph.contours.isEmpty) return;

    // 计算字符轮廓的包围盒
    int minX = 99999, minY = 99999, maxX = -99999, maxY = -99999;
    for (final contour in glyph.contours) {
      for (final p in contour.points) {
        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.x > maxX) maxX = p.x;
        if (p.y > maxY) maxY = p.y;
      }
    }

    final glyphWidth = (maxX - minX).toDouble();
    final glyphHeight = (maxY - minY).toDouble();
    if (glyphWidth <= 0 || glyphHeight <= 0) return;

    // 计算缩放比例，保持宽高比，居中适配 size
    final scaleX = size.width / glyphWidth;
    final scaleY = size.height / glyphHeight;
    final scale = min(scaleX, scaleY) * 0.85; // 留 15% 边距

    // 平移到中心
    final offsetX = (size.width - glyphWidth * scale) / 2 - minX * scale;
    // OpenType 坐标 y 轴向上，Flutter y 轴向下，需翻转
    final offsetY = (size.height + glyphHeight * scale) / 2 - minY * scale;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale, -scale); // y 轴翻转

    // 构建路径
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;

    for (final contour in glyph.contours) {
      final path = _buildContourPath(contour);
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  /// 将单个轮廓转换为 Path
  /// 使用二次贝塞尔曲线连接 on-curve 和 off-curve 点
  Path _buildContourPath(Contour contour) {
    final points = contour.points;
    if (points.isEmpty) return Path();

    final path = Path()..fillType = PathFillType.nonZero;

    // 找到第一个 on-curve 点作为起点
    int startIndex = 0;
    for (int i = 0; i < points.length; i++) {
      if (points[i].onCurve) {
        startIndex = i;
        break;
      }
    }

    final start = points[startIndex];
    path.moveTo(start.x.toDouble(), start.y.toDouble());

    int i = startIndex;
    int count = 0;
    final totalPoints = points.length;

    while (count < totalPoints) {
      i = (i + 1) % totalPoints;
      count++;

      final current = points[i];

      if (current.onCurve) {
        // 当前点在曲线上，直线连接
        path.lineTo(current.x.toDouble(), current.y.toDouble());
      } else {
        // 当前点是 off-curve 控制点
        // 查看下一个点
        final nextIdx = (i + 1) % totalPoints;
        final next = points[nextIdx];

        if (next.onCurve) {
          // 二次贝塞尔：控制点 current，终点 next
          path.quadraticBezierTo(
            current.x.toDouble(),
            current.y.toDouble(),
            next.x.toDouble(),
            next.y.toDouble(),
          );
          i = nextIdx;
          count++;
        } else {
          // 两个连续 off-curve 点，在中间插入隐含 on-curve 点
          final midX = (current.x + next.x) / 2.0;
          final midY = (current.y + next.y) / 2.0;

          path.quadraticBezierTo(
            current.x.toDouble(),
            current.y.toDouble(),
            midX,
            midY,
          );
          // 不推进 i，下一轮从 next 开始
        }
      }
    }

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter oldDelegate) {
    return oldDelegate.glyph != glyph || oldDelegate.fillColor != fillColor;
  }
}
