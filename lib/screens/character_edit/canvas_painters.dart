import 'package:flutter/material.dart';
import 'drawing_models.dart';

/// 画布绘制器 - 绘制所有笔画
class CanvasPainter extends CustomPainter {
  final List<StrokeRecord> strokes;
  final StrokeRecord? activeStroke;
  final Offset? eraserPosition;
  final double eraserRadius;

  CanvasPainter({
    required this.strokes,
    this.activeStroke,
    this.eraserPosition,
    this.eraserRadius = 10.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制所有已完成的笔画
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    // 绘制当前活动笔画
    if (activeStroke != null) {
      _drawStroke(canvas, activeStroke!);
    }
    // 绘制橡皮擦光标
    if (eraserPosition != null) {
      final fillPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(eraserPosition!, eraserRadius, fillPaint);
      final borderPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(eraserPosition!, eraserRadius, borderPaint);
    }
  }

  /// 绘制单个笔画
  void _drawStroke(Canvas canvas, StrokeRecord stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (stroke.points.length == 1) {
      // 单点绘制为圆点
      final dotPaint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(stroke.points.first, stroke.strokeWidth / 2, dotPaint);
    } else {
      final path = Path();
      path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        final p0 = stroke.points[i - 1];
        final p1 = stroke.points[i];
        final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
        path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
      }
      final last = stroke.points.last;
      path.lineTo(last.dx, last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) => true;
}

/// 米字格绘制器（十字线 + 对角线）
class GridPainter extends CustomPainter {
  final Color gridColor;

  GridPainter({required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final crossPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;

    // 水平中线
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      crossPaint,
    );
    // 垂直中线
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      crossPaint,
    );

    // 对角线
    final diagPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    // 左上 → 右下
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), diagPaint);
    // 右上 → 左下
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), diagPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
