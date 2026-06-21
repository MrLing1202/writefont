import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/project.dart';
import '../services/font_family_generator.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bezier_glyph_painter.dart';

/// 字体家族生成页面
/// 展示 Regular / Bold / Italic 三种变体的预览，并支持逐个导出。
class FontFamilyScreen extends StatefulWidget {
  final FontProject project;

  const FontFamilyScreen({super.key, required this.project});

  @override
  State<FontFamilyScreen> createState() => _FontFamilyScreenState();
}

class _FontFamilyScreenState extends State<FontFamilyScreen> {
  /// 'regular' / 'bold' / 'italic'
  String _selectedVariant = 'regular';

  /// 生成后的三个变体项目（延迟生成）
  Map<String, FontProject>? _family;
  bool _isGenerating = false;
  bool _isExporting = false;

  /// 预览文本
  final TextEditingController _previewTextController =
      TextEditingController(text: '永字八法 天地玄黄');

  @override
  void initState() {
    super.initState();
    _generateFamily();
  }

  @override
  void dispose() {
    _previewTextController.dispose();
    super.dispose();
  }

  /// 生成字体家族
  Future<void> _generateFamily() async {
    setState(() => _isGenerating = true);
    try {
      // 在下一帧执行，避免阻塞 build
      await Future.delayed(Duration.zero);
      final family = FontFamilyGenerator.generateFamily(widget.project);
      if (mounted) {
        setState(() {
          _family = family;
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        WFSnackBar.error(context, '生成字体家族失败: $e');
      }
    }
  }

  /// 导出当前选中的变体
  Future<void> _exportVariant() async {
    if (_family == null) return;
    final project = _family![_selectedVariant];
    if (project == null) return;

    final editedCount =
        project.glyphs.values.where((g) => g.contours.isNotEmpty).length;
    if (editedCount == 0) {
      WFSnackBar.show(context, '该变体没有可导出的字符');
      return;
    }

    setState(() => _isExporting = true);
    try {
      final variantLabel = _variantLabel(_selectedVariant);
      final filePath = await StorageService.exportTtf(
        project,
        familyName: widget.project.name,
        subfamilyName: variantLabel,
      );
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: '${widget.project.name} $variantLabel',
        text: '手迹造字 - ${widget.project.name} $variantLabel 字体',
      );

      if (mounted) {
        WFSnackBar.success(context, '已导出 $variantLabel（$editedCount 个字符）');
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

  /// 导出全部三个变体
  Future<void> _exportAll() async {
    if (_family == null) return;

    setState(() => _isExporting = true);
    try {
      final paths = <String>[];
      for (final entry in _family!.entries) {
        final project = entry.value;
        final editedCount =
            project.glyphs.values.where((g) => g.contours.isNotEmpty).length;
        if (editedCount == 0) continue;

        final variantLabel = _variantLabel(entry.key);
        final filePath = await StorageService.exportTtf(
          project,
          familyName: widget.project.name,
          subfamilyName: variantLabel,
        );
        paths.add(filePath);
      }

      if (paths.isEmpty) {
        if (mounted) WFSnackBar.show(context, '没有可导出的字符');
        return;
      }

      await Share.shareXFiles(
        paths.map((p) => XFile(p)).toList(),
        subject: '${widget.project.name} 字体家族',
        text: '手迹造字 - ${widget.project.name} 字体家族（${paths.length} 个变体）',
      );

      if (mounted) {
        WFSnackBar.success(context, '已导出 ${paths.length} 个字体变体');
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

  String _variantLabel(String key) {
    switch (key) {
      case 'bold':
        return 'Bold';
      case 'italic':
        return 'Italic';
      default:
        return 'Regular';
    }
  }

  String _variantLabelCn(String key) {
    switch (key) {
      case 'bold':
        return '粗体';
      case 'italic':
        return '斜体';
      default:
        return '常规';
    }
  }

  IconData _variantIcon(String key) {
    switch (key) {
      case 'bold':
        return Icons.format_bold;
      case 'italic':
        return Icons.format_italic;
      default:
        return Icons.text_fields;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WFAppBar(
        title: '字体家族',
        actions: [
          // 导出全部
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.archive),
            tooltip: '导出全部变体',
            onPressed: _isExporting || _family == null ? null : _exportAll,
          ),
        ],
      ),
      body: _isGenerating
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在生成字体家族...'),
                ],
              ),
            )
          : _family == null
              ? const Center(child: Text('生成失败'))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // ── 变体选择器 ──
        _buildVariantSelector(),
        const Divider(height: 1),

        // ── 预览区域 ──
        Expanded(
          child: _buildPreview(),
        ),

        // ── 预览文本输入 ──
        _buildPreviewInput(),

        // ── 导出按钮 ──
        _buildExportBar(),
      ],
    );
  }

  /// 三个变体的选择标签
  Widget _buildVariantSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: ['regular', 'bold', 'italic'].map((key) {
          final isSelected = _selectedVariant == key;
          final glyphCount = _family![key]!
              .glyphs
              .values
              .where((g) => g.contours.isNotEmpty)
              .length;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: WFAnimations.fadeInSlide(
                GestureDetector(
                  onTap: () => setState(() => _selectedVariant = key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? WFColors.primary
                          : WFColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? WFColors.primary
                            : WFColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _variantIcon(key),
                          color: isSelected ? Colors.white : WFColors.primary,
                          size: 22,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _variantLabelCn(key),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color:
                                isSelected ? Colors.white : WFColors.primary,
                          ),
                        ),
                        Text(
                          '$glyphCount 字',
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? Colors.white70
                                : WFColors.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                delay: Duration(milliseconds: 100 * ['regular', 'bold', 'italic'].indexOf(key)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 字形预览区域
  Widget _buildPreview() {
    final project = _family![_selectedVariant]!;
    final text = _previewTextController.text;

    if (text.isEmpty) {
      return Center(
        child: Text(
          '请输入预览文字',
          style: TextStyle(
            fontSize: 16,
            color: WFColors.textSecondaryColor(context),
          ),
        ),
      );
    }

    final lines = text.split('\n');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) {
          if (line.isEmpty) {
            return const SizedBox(height: 48);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              children: line.split('').map((char) {
                return _buildGlyphPreview(char, project);
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 单个字形预览方块
  Widget _buildGlyphPreview(String char, FontProject project) {
    const double cellSize = 56;
    final glyph = project.glyphs[char];
    final colorScheme = Theme.of(context).colorScheme;

    if (glyph == null || glyph.contours.isEmpty) {
      return Container(
        width: cellSize,
        height: cellSize,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          char,
          style: TextStyle(
            fontSize: cellSize * 0.5,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ),
      );
    }

    return Container(
      width: cellSize,
      height: cellSize,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: CustomPaint(
        painter: BezierGlyphPainter(
          glyph: glyph,
          fillColor: colorScheme.onSurface,
        ),
      ),
    );
  }

  /// 预览文本输入
  Widget _buildPreviewInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Row(
        children: [
          const Icon(Icons.text_fields, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _previewTextController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: '输入预览文字...',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: '恢复默认文本',
            onPressed: () {
              _previewTextController.text = '永字八法 天地玄黄';
              setState(() {});
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  /// 底部导出栏
  Widget _buildExportBar() {
    final project = _family![_selectedVariant]!;
    final editedCount =
        project.glyphs.values.where((g) => g.contours.isNotEmpty).length;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 变体信息
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.project.name} ${_variantLabel(_selectedVariant)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$editedCount 个字符',
                    style: TextStyle(
                      fontSize: 12,
                      color: WFColors.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            ),
            // 导出按钮
            FilledButton.icon(
              onPressed: _isExporting || editedCount == 0
                  ? null
                  : _exportVariant,
              icon: _isExporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.file_download, size: 18),
              label: Text(_isExporting ? '导出中...' : '导出 TTF'),
            ),
          ],
        ),
      ),
    );
  }
}
