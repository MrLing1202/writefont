import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/project.dart';
import '../services/storage_service.dart';
import 'font_test_screen.dart';
import 'font_preview_enhanced_screen.dart';
import '../theme/app_theme.dart';
import 'font_preview/preview_empty_state.dart';
import 'font_preview/preview_input_area.dart';
import 'font_preview/preview_content.dart';
import 'font_preview/preview_toolbar.dart';

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
  int _bgColorIndex = 0;

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
    _textController.addListener(() => setState(() {}));
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
        WFSnackBar.error(context, '加载项目失败: $e');
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
        WFSnackBar.error(context, '分享失败: $e');
      }
    }
  }

  /// 导出 TTF 字体文件并分享
  Future<void> _exportAndShareTtf() async {
    if (_project == null || _isExporting) return;

    setState(() => _isExporting = true);
    try {
      final editedCount = _project!.glyphs.values
          .where((g) => g.contours.isNotEmpty)
          .length;

      if (editedCount == 0) {
        if (mounted) {
          WFSnackBar.show(context, '没有可导出的字符，请先编辑字符轮廓');
        }
        return;
      }

      final filePath = await StorageService.exportTtf(_project!);
      await StorageService.shareTtf(filePath);

      if (mounted) {
        WFSnackBar.show(context, '已导出 $editedCount 个字符的字体文件');
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '导出失败: $e');
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

  /// 是否有已编辑的字符轮廓数据
  bool get _hasGlyphs {
    if (_project == null) return false;
    return _project!.glyphs.values.any((g) => g.contours.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullscreen
          ? null
          : WFAppBar(
              title: '字体预览',
              actions: [
                IconButton(
                  icon: const Icon(Icons.dashboard_customize),
                  tooltip: '增强预览',
                  onPressed: () {
                    Navigator.push(
                      context,
                      WFAnimations.slideRoute(FontPreviewEnhancedScreen(project: _project)),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.text_fields),
                  tooltip: '字体测试',
                  onPressed: () {
                    Navigator.push(
                      context,
                      WFAnimations.slideRoute(FontTestScreen(project: _project)),
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
              ? const PreviewEmptyState(message: '没有找到项目')
              : _hasGlyphs
                  ? _buildPreviewBody()
                  : const PreviewEmptyState(message: '请先在字表中书写字符'),
      floatingActionButton: _isFullscreen
          ? FloatingActionButton.small(
              onPressed: _toggleFullscreen,
              tooltip: '退出全屏',
              child: const Icon(Icons.fullscreen_exit),
            )
          : null,
    );
  }

  Widget _buildPreviewBody() {
    return Column(
      children: [
        if (!_isFullscreen)
          PreviewInputArea(
            textController: _textController,
            presets: _presets,
          ),

        // 预览渲染区
        Expanded(
          child: RepaintBoundary(
            key: _previewKey,
            child: Container(
              color: PreviewContent.bgColors[_bgColorIndex],
              child: InteractiveViewer(
                transformationController: _transformController,
                panEnabled: true,
                scaleEnabled: true,
                minScale: 0.5,
                maxScale: 5.0,
                child: ListenableBuilder(
                  listenable: _textController,
                  builder: (context, _) => PreviewContent(
                    project: _project!,
                    text: _textController.text,
                    fontSize: _fontSize,
                    lineHeight: _lineHeight,
                    bgColorIndex: _bgColorIndex,
                  ),
                ),
              ),
            ),
          ),
        ),

        // 底部工具栏
        if (!_isFullscreen)
          PreviewToolbar(
            project: _project,
            previewText: _textController.text,
            fontSize: _fontSize,
            lineHeight: _lineHeight,
            bgColorIndex: _bgColorIndex,
            isExporting: _isExporting,
            onFontSizeChanged: (v) => setState(() => _fontSize = v),
            onLineHeightChanged: (v) => setState(() => _lineHeight = v),
            onBgColorChanged: (i) => setState(() => _bgColorIndex = i),
            onFontSizePreset: () {},
            onResetZoom: _resetZoom,
            onToggleFullscreen: _toggleFullscreen,
            onExport: _exportAndShareTtf,
            onShare: _sharePreview,
          ),
      ],
    );
  }
}
