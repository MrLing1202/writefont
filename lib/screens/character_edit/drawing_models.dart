import 'package:flutter/material.dart';

/// 画笔工具模式
enum DrawTool {
  pencil, // 铅笔
  eraser, // 橡皮擦
  smooth, // 平滑
}

/// 笔画记录（用于撤销/重做）
class StrokeRecord {
  final List<Offset> points;
  final double strokeWidth;
  final Color color;

  StrokeRecord({
    required this.points,
    required this.strokeWidth,
    required this.color,
  });

  /// Chaikin's corner cutting 平滑算法
  /// 对每对相邻点，在 1/4 和 3/4 处插入新点，替换原线段。
  /// [iterations] 迭代次数，默认 2 轮。
  static List<Offset> chaikinSmooth(List<Offset> points,
      {int iterations = 2}) {
    if (points.length < 3) return List.of(points);
    var result = List<Offset>.from(points);
    for (var iter = 0; iter < iterations; iter++) {
      if (result.length < 3) break;
      final smoothed = <Offset>[result.first];
      for (var i = 0; i < result.length - 1; i++) {
        final p0 = result[i];
        final p1 = result[i + 1];
        // 1/4 处新点
        smoothed.add(Offset(
          p0.dx * 0.75 + p1.dx * 0.25,
          p0.dy * 0.75 + p1.dy * 0.25,
        ));
        // 3/4 处新点
        smoothed.add(Offset(
          p0.dx * 0.25 + p1.dx * 0.75,
          p0.dy * 0.25 + p1.dy * 0.75,
        ));
      }
      smoothed.add(result.last);
      result = smoothed;
    }
    return result;
  }
}
