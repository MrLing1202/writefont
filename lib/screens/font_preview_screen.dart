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
  final TextEditingController _compareTextController = TextEditingController();
  final GlobalKey _previewKey = GlobalKey();
  final TransformationController _transformController = TransformationController();

  FontProject? _project;
  FontProject? _compareProject; // 对比预览用的第二个字体项目
  bool _isLoading = true;
  bool _isFullscreen = false;
  bool _isExporting = false;
  double _fontSize = 48;
  double _lineHeight = 1.5;
  int _bgColorIndex = 0;
  bool _showMultiSize = false; // 多字号预览开关
  bool _showCompare = false; // 字体对比预览开关
  bool _isSavingScreenshot = false; // 截图保存状态

  /// 快捷预设文本
  static const _presets = [
    '天地玄黄 宇宙洪荒',
    '永字八法',
    'WriteFont手迹造字',
  ];

  /// 多字号预览尺寸列表
  static const _multiSizes = [12.0, 24.0, 36.0, 48.0, 72.0];

  @override
  void initState() {
    super.initState();
    _textController.text = _presets[0];
    _compareTextController.text = _presets[0];
    _textController.addListener(() {
      _compareTextController.text = _textController.text;
      setState(() {});
    });
    _loadProject();
  }

  @override
  void dispose() {
    _textController.dispose();
    _compareTextController.dispose();
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

  /// 切换多字号预览模式
  void _toggleMultiSize() {
    setState(() => _showMultiSize = !_showMultiSize);
  }

  /// 切换字体对比预览模式
  void _toggleCompare() async {
    if (_showCompare) {
      setState(() {
        _showCompare = false;
        _compareProject = null;
      });
      return;
    }

    // 加载可用项目列表供选择
    try {
      final projects = await StorageService.loadProjects();
      if (!mounted || projects.length < 2) {
        if (mounted) {
          WFSnackBar.show(context, '需要至少2个项目才能对比');
        }
        return;
      }

      final otherProjects = projects.where((p) => p.id != _project?.id).toList();
      final selected = await WFDialog.singleChoice<FontProject>(
        context,
        title: '选择对比字体',
        items: otherProjects,
        itemBuilder: (p) {
          final editedCount = p.glyphs.values
              .where((g) => g.contours.isNotEmpty)
              .length;
          return ListTile(
            leading: const Icon(Icons.font_download),
            title: Text(p.name),
            subtitle: Text('$editedCount 个字符'),
          );
        },
      );

      if (selected != null && mounted) {
        setState(() {
          _compareProject = selected;
          _showCompare = true;
        });
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '加载项目列表失败: $e');
      }
    }
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

  /// 截图保存到相册/文件系统
  Future<void> _saveScreenshot() async {
    if (_isSavingScreenshot) return;
    setState(() => _isSavingScreenshot = true);

    try {
      final boundary = _previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) WFSnackBar.error(context, '截图失败：无法获取预览区域');
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0); // 高分辨率
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/font_preview_$timestamp.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (mounted) {
        WFSnackBar.success(context, '预览截图已保存',
          action: SnackBarAction(
            label: '分享',
            onPressed: () => Share.shareXFiles(
              [XFile(file.path)],
              subject: '字体预览截图',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '保存截图失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isSavingScreenshot = false);
    }
  }

  /// 导出 TTF 字体文件并分享
  Future<void> _exportAndShareTtf() async {
    if (_project == null || _isExporting) return;

    // 确认导出
    final confirmed = await WFDialog.confirm(
      context,
      title: '导出字体',
      message: '即将导出 TTF 字体文件，是否继续？',
      confirmText: '导出',
      icon: Icons.font_download,
    );
    if (confirmed != true) return;

    if (!mounted) return;
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
        WFSnackBar.success(context, '已导出 $editedCount 个字符的字体文件');
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
                // 多字号预览开关
                IconButton(
                  icon: Icon(
                    Icons.format_size,
                    color: _showMultiSize ? Theme.of(context).colorScheme.primary : null,
                  ),
                  tooltip: _showMultiSize ? '关闭多字号预览' : '多字号预览',
                  onPressed: _toggleMultiSize,
                ),
                // 字体对比预览开关
                IconButton(
                  icon: Icon(
                    Icons.compare,
                    color: _showCompare ? Theme.of(context).colorScheme.primary : null,
                  ),
                  tooltip: _showCompare ? '关闭字体对比' : '字体对比',
                  onPressed: _toggleCompare,
                ),
                // 截图保存
                IconButton(
                  icon: _isSavingScreenshot
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.screenshot),
                  tooltip: '保存预览截图',
                  onPressed: _isSavingScreenshot ? null : _saveScreenshot,
                ),
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
              child: _showMultiSize
                  ? _buildMultiSizePreview()
                  : _showCompare
                      ? _buildComparePreview()
                      : InteractiveViewer(
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

  /// 多字号预览视图
  Widget _buildMultiSizePreview() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkBg = _bgColorIndex == 1;
    final labelColor = isDarkBg ? Colors.white70 : colorScheme.onSurfaceVariant;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ListenableBuilder(
        listenable: _textController,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 提示标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.format_size, size: 16, color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    '多字号预览',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 各字号预览
            ..._multiSizes.map((size) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 字号标签
                    Text(
                      '${size.round()}px',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 预览内容
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: PreviewContent(
                        project: _project!,
                        text: _textController.text,
                        fontSize: size,
                        lineHeight: _lineHeight,
                        bgColorIndex: _bgColorIndex,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 字体对比预览视图
  Widget _buildComparePreview() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkBg = _bgColorIndex == 1;
    final labelColor = isDarkBg ? Colors.white70 : colorScheme.onSurfaceVariant;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ListenableBuilder(
        listenable: _textController,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 提示标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.compare, size: 16, color: colorScheme.onTertiaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    '字体对比',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 当前字体
            _buildCompareSection(
              label: '当前字体：${_project!.name}',
              project: _project!,
              labelColor: labelColor,
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 16),
            // 对比字体
            if (_compareProject != null)
              _buildCompareSection(
                label: '对比字体：${_compareProject!.name}',
                project: _compareProject!,
                labelColor: labelColor,
                colorScheme: colorScheme,
              ),
          ],
        ),
      ),
    );
  }

  /// 对比预览中的单个字体区块
  Widget _buildCompareSection({
    required String label,
    required FontProject project,
    required Color labelColor,
    required ColorScheme colorScheme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: PreviewContent(
            project: project,
            text: _textController.text,
            fontSize: _fontSize,
            lineHeight: _lineHeight,
            bgColorIndex: _bgColorIndex,
          ),
        ),
      ],
    );
  }
}
