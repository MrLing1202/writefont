import 'package:flutter/material.dart';
import '../models/project.dart';

/// 共享的字形渲染组件
///
/// 将字体轮廓（contours）渲染为可视化的字形 Widget。
/// 可在预览页面、项目列表等多个场景复用。
///
/// 使用方式：
/// ```dart
/// GlyphWidget(
///   contours: glyph.contours,
///   size: 32,
///   color: Colors.black,
/// )
/// ```
class GlyphWidget extends StatelessWidget {
  /// 字形轮廓数据
  final List<Contour> contours;

  /// 渲染尺寸（正方形，宽高相等）
  final double size;

  /// 渲染颜色
  final Color color;

  const GlyphWidget({
    super.key,
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
        painter: GlyphPainter(contours: contours, color: color),
      ),
    );
  }
}

/// 字形轮廓绘制器
///
/// 将字体轮廓数据绘制到 Canvas 上。
/// 支持多轮廓（外轮廓 + 内部镂空），使用 nonZero 填充规则
/// 自动处理轮廓方向以正确渲染空心区域（如"口"、"日"等字形）。
class GlyphPainter extends CustomPainter {
  /// 字形轮廓数据
  final List<Contour> contours;

  /// 渲染颜色
  final Color color;

  GlyphPainter({required this.contours, required this.color});

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
  bool shouldRepaint(covariant GlyphPainter oldDelegate) {
    return oldDelegate.contours != contours || oldDelegate.color != color;
  }
}
