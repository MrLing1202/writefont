import 'dart:math';
import 'package:flutter/material.dart';
import '../models/project.dart';

/// 贝塞尔曲线字形绘制器
/// 遍历 GlyphData 的 contours，将 on-curve / off-curve 点用
/// 二次贝塞尔曲线连接，使用 nonZero 填充规则处理内外轮廓。
class BezierGlyphPainter extends CustomPainter {
  final GlyphData glyph;
  final Color fillColor;

  BezierGlyphPainter({
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
  bool shouldRepaint(covariant BezierGlyphPainter oldDelegate) {
    return oldDelegate.glyph != glyph || oldDelegate.fillColor != fillColor;
  }
}
