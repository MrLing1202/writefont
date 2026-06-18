import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bezier_glyph_painter.dart';

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
        painter: BezierGlyphPainter(
          glyph: glyph,
          fillColor: WFColors.textPrimary,
        ),
      ),
    );
  }
}
