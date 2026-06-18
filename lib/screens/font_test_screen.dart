import 'dart:math';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// 字体测试页面
/// 用户输入想测试的文字，用生成的字体轮廓大字号渲染显示
class FontTestScreen extends StatefulWidget {
  final FontProject? project;

  const FontTestScreen({super.key, this.project});

  @override
  State<FontTestScreen> createState() => _FontTestScreenState();
}

class _FontTestScreenState extends State<FontTestScreen> {
  final TextEditingController _textController = TextEditingController();

  FontProject? _project;
  bool _isLoading = true;
  double _fontSize = 72;

  @override
  void initState() {
    super.initState();
    _textController.text = '手迹造字';
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
        // 自动选择最新项目
        final projects = await StorageService.loadProjects();
        if (projects.isNotEmpty) {
          project = projects.first;
        }
      } else if (project.id.isNotEmpty) {
        // 如果传入了项目，重新加载最新数据
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载项目失败: $e')),
        );
      }
    }
  }

  /// 是否有已编辑的字符轮廓数据
  bool get _hasGlyphs {
    if (_project == null) return false;
    return _project!.glyphs.values.any((g) => g.contours.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WFAppBar(
        title: '字体测试',
        actions: [
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
              ? _buildEmptyState('没有找到项目')
              : _hasGlyphs
                  ? _buildTestBody()
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
            Icon(
              Icons.text_fields,
              size: 80,
              color: WFColors.textLight,
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: TextStyle(
                fontSize: 18,
                color: WFColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '在字表中书写字符后即可测试字体效果',
              style: TextStyle(
                fontSize: 14,
                color: WFColors.textLight,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestBody() {
    return Column(
      children: [
        // 顶部输入区
        _buildInputArea(),
        // 字号调节滑块
        _buildFontSizeSlider(),
        // 大字号渲染区域
        Expanded(
          child: _buildRenderArea(),
        ),
      ],
    );
  }

  /// 顶部输入区
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: WFColors.bgCard,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _textController,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              hintText: '输入想测试的文字…',
              prefixIcon: const Icon(Icons.edit),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              filled: true,
              fillColor: WFColors.bgPrimary,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Text(
            '输入文字后下方会用生成的字体轮廓渲染显示',
            style: TextStyle(
              fontSize: 12,
              color: WFColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 字号调节滑块
  Widget _buildFontSizeSlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: WFColors.bgCard,
      child: Row(
        children: [
          Icon(Icons.format_size, size: 20, color: WFColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            '字号',
            style: TextStyle(
              fontSize: 13,
              color: WFColors.textSecondary,
            ),
          ),
          Expanded(
            child: Slider(
              value: _fontSize,
              min: 24,
              max: 200,
              divisions: 88,
              activeColor: WFColors.primary,
              label: '${_fontSize.round()}pt',
              onChanged: (v) => setState(() => _fontSize = v),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${_fontSize.round()}pt',
              style: TextStyle(
                fontSize: 13,
                color: WFColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 大字号渲染区域
  Widget _buildRenderArea() {
    final text = _textController.text;
    if (text.isEmpty) {
      return Center(
        child: Text(
          '请输入文字',
          style: TextStyle(
            fontSize: 18,
            color: WFColors.textLight,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: WFColors.bgPrimary,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: text.split('\n').map((line) {
            if (line.isEmpty) {
              return SizedBox(height: _fontSize * 1.5);
            }
            return Padding(
              padding: EdgeInsets.only(bottom: _fontSize * 0.5),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                children: line.split('').map((char) {
                  return _buildGlyphWidget(char);
                }).toList(),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// 构建单个字符的渲染部件
  Widget _buildGlyphWidget(String char) {
    final glyph = _project!.glyphs[char];

    if (glyph == null || glyph.contours.isEmpty) {
      // 没有轮廓数据，显示灰色占位方块
      return Container(
        width: _fontSize,
        height: _fontSize,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: WFColors.textLight.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: WFColors.textLight.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          char,
          style: TextStyle(
            fontSize: _fontSize * 0.6,
            color: WFColors.textLight,
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
          fillColor: WFColors.textPrimary,
        ),
      ),
    );
  }
}

/// 贝塞尔曲线字形绘制器（与 FontPreviewScreen 共用逻辑）
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
        path.lineTo(current.x.toDouble(), current.y.toDouble());
      } else {
        final nextIdx = (i + 1) % totalPoints;
        final next = points[nextIdx];

        if (next.onCurve) {
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
