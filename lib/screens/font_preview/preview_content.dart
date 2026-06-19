import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../widgets/bezier_glyph_painter.dart';

/// 预览内容渲染组件（逐字渲染贝塞尔曲线）
class PreviewContent extends StatelessWidget {
  final FontProject project;
  final String text;
  final double fontSize;
  final double lineHeight;
  final int bgColorIndex;

  static const bgColors = [
    Colors.white,
    Color(0xFF1A1A1A),
    Color(0xFFE0E0E0),
  ];

  const PreviewContent({
    super.key,
    required this.project,
    required this.text,
    required this.fontSize,
    required this.lineHeight,
    required this.bgColorIndex,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
            return SizedBox(height: fontSize * lineHeight);
          }
          return Padding(
            padding: EdgeInsets.only(bottom: fontSize * (lineHeight - 1)),
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

  Widget _buildGlyphWidget(String char, ColorScheme colorScheme) {
    final bool isDarkBg = bgColorIndex == 1;
    final Color fgColor = isDarkBg ? Colors.white : colorScheme.onSurface;
    final Color placeholderBg = isDarkBg
        ? Colors.white.withValues(alpha: 0.1)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final Color placeholderFg = isDarkBg
        ? Colors.white.withValues(alpha: 0.3)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.3);

    final glyph = project.glyphs[char];

    if (glyph == null || glyph.contours.isEmpty) {
      return Container(
        width: fontSize,
        height: fontSize,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: placeholderBg,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          char,
          style: TextStyle(
            fontSize: fontSize * 0.6,
            color: placeholderFg,
          ),
        ),
      );
    }

    return SizedBox(
      width: fontSize,
      height: fontSize,
      child: CustomPaint(
        painter: BezierGlyphPainter(
          glyph: glyph,
          fillColor: fgColor,
        ),
      ),
    );
  }
}
