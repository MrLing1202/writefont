import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import 'character_edit_screen.dart';

class PreviewScreen extends StatefulWidget {
  final FontProject project;

  const PreviewScreen({super.key, required this.project});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  String _previewText = '你好世界 Hello';
  bool _isExporting = false;
  bool _isSaving = false;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _textController.text = _previewText;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// 导出 TTF 字体（先弹出命名对话框）
  Future<void> _exportFont() async {
    // 弹出字体命名对话框
    final fontName = await _showFontNameDialog();
    if (fontName == null || fontName.isEmpty) return; // 用户取消

    // 更新项目名称
    widget.project.name = fontName;

    setState(() => _isExporting = true);
    try {
      final filePath = await StorageService.exportTtf(widget.project);

      if (mounted) {
        // Show success dialog with install hint
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
              size: 48,
            ),
            title: const Text('导出成功'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('字体文件已保存到：'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    filePath,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '共导出 ${widget.project.glyphs.length} 个字符',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                // 安装提示
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '安装字体：将 TTF 文件发送到电脑，双击安装即可在设计软件中使用。Android 可通过「设置→显示→字体」导入。',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  StorageService.shareTtf(filePath);
                },
                icon: const Icon(Icons.share),
                label: const Text('分享'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// 显示字体命名对话框，返回用户输入的字体名称（取消返回 null）
  Future<String?> _showFontNameDialog() async {
    final controller = TextEditingController(text: widget.project.name);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.font_download, color: colorScheme.primary, size: 36),
          title: const Text('为你的字体命名'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '这个名字将作为字体文件名和项目标题',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '字体名称',
                    hintText: '例如：我的手写体',
                    prefixIcon: const Icon(Icons.edit),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入字体名称';
                    }
                    // 检查非法文件名字符
                    if (RegExp(r'[<>:"/\\|?*]').hasMatch(value)) {
                      return '名称不能包含特殊字符';
                    }
                    return null;
                  },
                  maxLength: 30,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(context, controller.text.trim());
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: const Text('导出'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result;
  }

  /// 保存项目到本地
  Future<void> _saveProject() async {
    setState(() => _isSaving = true);
    try {
      await StorageService.saveProject(widget.project);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('项目「${widget.project.name}」已保存'),
            action: SnackBarAction(
              label: '知道了',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 打开字符编辑对话框
  void _editCharacter(String character, GlyphData glyph) {
    CharacterEditDialog.show(
      context,
      character: character,
      glyph: glyph,
      projectId: widget.project.id,
      onCharacterChanged: () {
        // 如果字符标签改变了，需要更新 glyphs Map
        if (glyph.character != character) {
          widget.project.glyphs.remove(character);
          widget.project.glyphs[glyph.character] = glyph;
        }
        setState(() {});
      },
      onCharacterDeleted: () {
        widget.project.glyphs.remove(character);
        setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final glyphs = widget.project.glyphs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('字体预览'),
        actions: [
          IconButton(
            onPressed: () => _showGlyphList(colorScheme),
            icon: const Icon(Icons.list),
            tooltip: '查看字符列表',
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(Icons.font_download, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '${widget.project.name} · ${glyphs.length} 个字符',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                // 字符可点击提示
                Icon(
                  Icons.touch_app,
                  size: 16,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  '点击字符可编辑',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),

          // Preview input
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                labelText: '预览文字',
                hintText: '输入要预览的文字',
                prefixIcon: const Icon(Icons.text_fields),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _textController.clear();
                    setState(() => _previewText = '');
                  },
                ),
              ),
              onChanged: (v) => setState(() => _previewText = v),
              maxLines: 2,
            ),
          ),

          // Preview area
          Expanded(
            child: _previewText.isEmpty
                ? Center(
                    child: Text(
                      '输入文字查看预览效果',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        fontSize: 16,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Large preview
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: colorScheme.outlineVariant),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '大字预览',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildGlyphPreviewText(_previewText, 48),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Medium preview
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: colorScheme.outlineVariant),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '中字预览',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildGlyphPreviewText(_previewText, 28),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Small preview
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: colorScheme.outlineVariant),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '小字预览',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildGlyphPreviewText(_previewText, 16),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Character grid preview
                        Text(
                          '已收录字符',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '点击字符可编辑标签、删除或查看原图',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildCharacterGrid(glyphs, colorScheme),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 保存项目按钮
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _saveProject,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? '保存中...' : '保存项目'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // 底部操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.edit),
                      label: const Text('返回编辑'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _isExporting ? null : _exportFont,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_download),
                      label: Text(_isExporting ? '导出中...' : '导出 TTF'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlyphPreviewText(String text, double fontSize) {
    final colorScheme = Theme.of(context).colorScheme;
    final List<InlineSpan> spans = [];

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final glyph = widget.project.glyphs[char];

      if (glyph != null && glyph.contours.isNotEmpty) {
        // We have this glyph - render it using a custom painter approach
        spans.add(WidgetSpan(
          child: _GlyphWidget(
            contours: glyph.contours,
            size: fontSize,
            color: colorScheme.onSurface,
          ),
          alignment: PlaceholderAlignment.middle,
        ));
      } else {
        // Use default font
        spans.add(TextSpan(
          text: char,
          style: TextStyle(
            fontSize: fontSize,
            color: colorScheme.onSurface,
          ),
        ));
      }
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  Widget _buildCharacterGrid(Map<String, GlyphData> glyphs, ColorScheme colorScheme) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: glyphs.entries.map((entry) {
        final glyph = entry.value;
        final character = entry.key;
        final unicodeHex = 'U+${glyph.unicode.toRadixString(16).toUpperCase().padLeft(4, '0')}';
        return GestureDetector(
          onTap: () => _editCharacter(character, glyph),
          child: Tooltip(
            message: '$unicodeHex · 点击编辑',
            child: Container(
              width: 48,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
                color: colorScheme.surface,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: glyph.contours.isNotEmpty
                        ? _GlyphWidget(
                            contours: glyph.contours,
                            size: 32,
                            color: colorScheme.onSurface,
                          )
                        : Center(
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 20,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                  ),
                  Text(
                    unicodeHex.substring(2), // 显示 4 位十六进制
                    style: TextStyle(
                      fontSize: 8,
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showGlyphList(ColorScheme colorScheme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) {
          final glyphs = widget.project.glyphs.entries.toList();
          return Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '字符列表 (${glyphs.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: glyphs.length,
                  itemBuilder: (context, index) {
                    final entry = glyphs[index];
                    return ListTile(
                      onTap: () {
                        Navigator.pop(context);
                        _editCharacter(entry.key, entry.value);
                      },
                      leading: SizedBox(
                        width: 40,
                        height: 40,
                        child: entry.value.contours.isNotEmpty
                            ? _GlyphWidget(
                                contours: entry.value.contours,
                                size: 32,
                                color: colorScheme.onSurface,
                              )
                            : Center(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                      ),
                      title: Text('U+${entry.value.unicode.toRadixString(16).toUpperCase().padLeft(4, '0')}'),
                      subtitle: Text('${entry.value.contours.length} 个轮廓'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(fontSize: 24),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.edit,
                            size: 16,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A widget that renders glyph contours using a CustomPainter.
class _GlyphWidget extends StatelessWidget {
  final List<Contour> contours;
  final double size;
  final Color color;

  const _GlyphWidget({
    required this.contours,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GlyphPainter(contours: contours, color: color),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final List<Contour> contours;
  final Color color;

  _GlyphPainter({required this.contours, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (contours.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Scale from font units (0-1000) to widget size
    // Font Y goes up, screen Y goes down
    final scale = size.width / 1000;

    // Merge all contours into a single Path with nonZero fill type.
    // This ensures inner contours (holes) create hollow regions:
    // - Outer contour winding number +1 → filled
    // - Inner contour winding number -1 → total 0 → unfilled (hole)
    final path = Path()..fillType = PathFillType.nonZero;

    // Helper: compute signed area via shoelace formula.
    // Positive = clockwise in screen coords (Y down), negative = counter-clockwise.
    double signedArea(List<ContourPoint> pts) {
      double a = 0;
      for (int i = 0; i < pts.length; i++) {
        final j = (i + 1) % pts.length;
        a += pts[i].x * pts[j].y - pts[j].x * pts[i].y;
      }
      return a;
    }

    // Find the outer contour (largest by absolute area).
    double maxArea = 0;
    int outerIdx = 0;
    for (int c = 0; c < contours.length; c++) {
      if (contours[c].points.length < 3) continue;
      final a = signedArea(contours[c].points).abs();
      if (a > maxArea) {
        maxArea = a;
        outerIdx = c;
      }
    }

    // Determine the winding direction of the outer contour.
    final outerCW = signedArea(contours[outerIdx].points) > 0;

    // Add each contour, ensuring inner contours have opposite winding
    // so the non-zero rule produces hollow regions.
    for (int c = 0; c < contours.length; c++) {
      final contour = contours[c];
      if (contour.points.length < 3) continue;

      final pts = contour.points;
      final isCW = signedArea(pts) > 0;

      // If winding matches the outer contour and it's not the outer itself,
      // reverse it so it becomes a hole.
      final needReverse = c != outerIdx && isCW == outerCW;
      final ordered = needReverse ? pts.reversed.toList() : pts;

      final first = ordered.first;
      path.moveTo(first.x * scale, (1000 - first.y) * scale);
      for (int i = 1; i < ordered.length; i++) {
        final p = ordered[i];
        path.lineTo(p.x * scale, (1000 - p.y) * scale);
      }
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter oldDelegate) {
    return oldDelegate.contours != contours || oldDelegate.color != color;
  }
}
