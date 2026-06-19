import 'package:flutter/material.dart';

/// 画笔工具模式
enum DrawTool {
  pencil, // 铅笔
  eraser, // 橡皮擦
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
}
