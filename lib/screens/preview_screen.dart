import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/storage_service.dart';

class PreviewScreen extends StatefulWidget {
  final FontProject project;

  const PreviewScreen({super.key, required this.project});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  String _previewText = '你好世界 Hello';
  bool _isExporting = false;
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

  Future<void> _exportFont() async {
    setState(() => _isExporting = true);
    try {
      final filePath = await StorageService.exportTtf(widget.project);

      if (mounted) {
        // Show success dialog
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
                Text('字体文件已保存到：'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
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
            color: colorScheme.primaryContainer.withOpacity(0.3),
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
                        color: colorScheme.onSurfaceVariant.withOpacity(0.5),
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
          child: Row(
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
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
            color: colorScheme.surface,
          ),
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
                  color: colorScheme.onSurfaceVariant.withOpacity(0.3),
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
                      trailing: Text(
                        entry.key,
                        style: const TextStyle(fontSize: 24),
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

    for (final contour in contours) {
      if (contour.points.length < 3) continue;

      final path = Path();
      final first = contour.points.first;
      path.moveTo(first.x * scale, (1000 - first.y) * scale);

      for (int i = 1; i < contour.points.length; i++) {
        final p = contour.points[i];
        path.lineTo(p.x * scale, (1000 - p.y) * scale);
      }

      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter oldDelegate) {
    return oldDelegate.contours != contours || oldDelegate.color != color;
  }
}
