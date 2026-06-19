import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glyph_widget.dart';

/// 预览区域 — 大/中/小字预览卡片
class PreviewArea extends StatelessWidget {
  final String previewText;
  final Map<String, GlyphData> glyphs;

  const PreviewArea({
    super.key,
    required this.previewText,
    required this.glyphs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPreviewCard('大字预览', 48),
        const SizedBox(height: 12),
        _buildPreviewCard('中字预览', 28),
        const SizedBox(height: 12),
        _buildPreviewCard('小字预览', 16),
      ],
    );
  }

  /// 预览卡片 — WFCard 包裹
  Widget _buildPreviewCard(String label, double fontSize) {
    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: WFColors.textSecondary),
          ),
          const SizedBox(height: 8),
          _buildGlyphPreviewText(previewText, fontSize),
        ],
      ),
    );
  }

  /// 构建字形预览文本
  Widget _buildGlyphPreviewText(String text, double fontSize) {
    final List<InlineSpan> spans = [];
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final glyph = glyphs[char];
      if (glyph != null && glyph.contours.isNotEmpty) {
        spans.add(WidgetSpan(
          child: GlyphWidget(
            contours: glyph.contours,
            size: fontSize,
            color: WFColors.textPrimary,
          ),
          alignment: PlaceholderAlignment.middle,
        ));
      } else {
        spans.add(TextSpan(
          text: char,
          style: TextStyle(fontSize: fontSize, color: WFColors.textPrimary),
        ));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }
}
