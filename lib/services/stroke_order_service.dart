import 'dart:math';
import '../models/project.dart';

/// 笔画顺序服务
/// 从字形轮廓数据推断笔画顺序，并生成动画路径。
class StrokeOrderService {
  /// 从字形数据提取笔画顺序
  /// 返回按书写顺序排列的笔画列表（每笔是一个轮廓）
  static List<Contour> extractStrokeOrder(GlyphData glyph) {
    if (glyph.contours.isEmpty) return [];
    if (glyph.contours.length <= 1) return List.from(glyph.contours);

    // 按起始点位置排序：从上到下、从左到右
    final sorted = List<Contour>.from(glyph.contours);
    sorted.sort((a, b) {
      final aStart = a.points.isNotEmpty ? a.points.first : null;
      final bStart = b.points.isNotEmpty ? b.points.first : null;
      if (aStart == null || bStart == null) return 0;

      // 先按 Y 坐标（上到下，Y 值大在上）
      final yDiff = bStart.y.compareTo(aStart.y);
      if (yDiff.abs() > 50) return yDiff;

      // Y 相近时按 X 坐标（左到右）
      return aStart.x.compareTo(bStart.x);
    });

    return sorted;
  }

  /// 生成笔画动画路径数据
  /// 返回每笔的点序列，用于动画绘制
  static List<List<ContourPoint>> generateAnimationPaths(GlyphData glyph) {
    final strokes = extractStrokeOrder(glyph);
    return strokes.map((contour) {
      return contour.points.where((p) => p.onCurve).toList();
    }).toList();
  }

  /// 获取笔画统计信息
  static StrokeStats getStrokeStats(GlyphData glyph) {
    final strokes = extractStrokeOrder(glyph);
    int totalPoints = 0;
    for (final s in strokes) {
      totalPoints += s.points.length;
    }
    return StrokeStats(
      strokeCount: strokes.length,
      totalPoints: totalPoints,
      complexity: strokes.length > 8
          ? StrokeComplexity.complex
          : strokes.length > 4
              ? StrokeComplexity.medium
              : StrokeComplexity.simple,
    );
  }
}

/// 笔画统计
class StrokeStats {
  final int strokeCount;
  final int totalPoints;
  final StrokeComplexity complexity;

  const StrokeStats({
    required this.strokeCount,
    required this.totalPoints,
    required this.complexity,
  });
}

enum StrokeComplexity { simple, medium, complex }
