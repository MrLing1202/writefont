import 'dart:math';
import '../models/project.dart';

/// 字体家族生成器
/// 从一个手写体项目生成 Bold（粗体）和 Italic（斜体）变体。
class FontFamilyGenerator {
  /// 粗体偏移量（font units），控制笔画加粗程度
  static const int _boldOffset = 30;

  /// 斜体倾斜角度（度）
  static const double _italicAngle = 12.0;

  /// 生成粗体变体
  ///
  /// 策略：对每个轮廓的每个点，沿远离轮廓重心的方向偏移，
  /// 使笔画看起来更粗。
  static FontProject generateBold(FontProject project) {
    final boldGlyphs = <String, GlyphData>{};

    for (final entry in project.glyphs.entries) {
      final original = entry.value;
      if (original.contours.isEmpty) {
        boldGlyphs[entry.key] = _copyGlyph(original);
        continue;
      }
      boldGlyphs[entry.key] = _boldifyGlyph(original);
    }

    return FontProject(
      id: '${project.id}_bold',
      name: '${project.name} Bold',
      glyphs: boldGlyphs,
      params: project.params,
      kerningPairs: Map.from(project.kerningPairs),
    );
  }

  /// 生成斜体变体
  ///
  /// 策略：对每个轮廓点施加倾斜变换 x' = x + y * tan(angle)
  static FontProject generateItalic(FontProject project) {
    final italicGlyphs = <String, GlyphData>{};
    final tanAngle = tan(_italicAngle * pi / 180.0);

    for (final entry in project.glyphs.entries) {
      final original = entry.value;
      if (original.contours.isEmpty) {
        italicGlyphs[entry.key] = _copyGlyph(original);
        continue;
      }
      italicGlyphs[entry.key] = _italicizeGlyph(original, tanAngle);
    }

    return FontProject(
      id: '${project.id}_italic',
      name: '${project.name} Italic',
      glyphs: italicGlyphs,
      params: project.params,
      kerningPairs: Map.from(project.kerningPairs),
    );
  }

  /// 一次性生成完整字体家族（Regular / Bold / Italic）
  static Map<String, FontProject> generateFamily(FontProject project) {
    return {
      'regular': project,
      'bold': generateBold(project),
      'italic': generateItalic(project),
    };
  }

  // ── 内部辅助方法 ──

  /// 深拷贝一个 GlyphData（不含轮廓变换）
  static GlyphData _copyGlyph(GlyphData original) {
    return GlyphData(
      character: original.character,
      unicode: original.unicode,
      contours: original.contours
          .map((c) => Contour(c.points
              .map((p) => ContourPoint(p.x, p.y, onCurve: p.onCurve))
              .toList()))
          .toList(),
      advanceWidth: original.advanceWidth,
      leftSideBearing: original.leftSideBearing,
      xMin: original.xMin,
      yMin: original.yMin,
      xMax: original.xMax,
      yMax: original.yMax,
      sourceImagePath: original.sourceImagePath,
      confidence: original.confidence,
    );
  }

  /// 生成粗体字形
  ///
  /// 使用重心膨胀——每个点远离轮廓中心移动 [_boldOffset] 个单位。
  static GlyphData _boldifyGlyph(GlyphData original) {
    final newContours = <Contour>[];

    for (final contour in original.contours) {
      if (contour.points.length < 3) {
        newContours.add(Contour(contour.points
            .map((p) => ContourPoint(p.x, p.y, onCurve: p.onCurve))
            .toList()));
        continue;
      }

      // 计算轮廓重心
      double cx = 0, cy = 0;
      for (final p in contour.points) {
        cx += p.x;
        cy += p.y;
      }
      cx /= contour.points.length;
      cy /= contour.points.length;

      // 每个点沿远离重心的方向偏移
      final newPoints = <ContourPoint>[];
      for (final p in contour.points) {
        final dx = p.x - cx;
        final dy = p.y - cy;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < 0.001) {
          // 靠近重心的点不偏移
          newPoints.add(ContourPoint(p.x, p.y, onCurve: p.onCurve));
        } else {
          final nx = dx / dist;
          final ny = dy / dist;
          final newX = (p.x + nx * _boldOffset).round();
          final newY = (p.y + ny * _boldOffset).round();
          newPoints.add(ContourPoint(newX, newY, onCurve: p.onCurve));
        }
      }

      newContours.add(Contour(newPoints));
    }

    return _buildGlyphFromContours(original, newContours);
  }

  /// 生成斜体字形
  static GlyphData _italicizeGlyph(GlyphData original, double tanAngle) {
    final newContours = <Contour>[];

    for (final contour in original.contours) {
      final newPoints = <ContourPoint>[];
      for (final p in contour.points) {
        // 倾斜变换：x' = x + y * tan(angle)，y 不变
        final newX = (p.x + p.y * tanAngle).round();
        newPoints.add(ContourPoint(newX, p.y, onCurve: p.onCurve));
      }
      newContours.add(Contour(newPoints));
    }

    return _buildGlyphFromContours(original, newContours);
  }

  /// 从轮廓数据构建新的 GlyphData，自动更新边界框
  static GlyphData _buildGlyphFromContours(
      GlyphData original, List<Contour> newContours) {
    int xMin = 99999, yMin = 99999, xMax = -99999, yMax = -99999;
    for (final contour in newContours) {
      for (final p in contour.points) {
        if (p.x < xMin) xMin = p.x;
        if (p.y < yMin) yMin = p.y;
        if (p.x > xMax) xMax = p.x;
        if (p.y > yMax) yMax = p.y;
      }
    }

    // 轮廓为空时保持原始边界框
    if (newContours.isEmpty ||
        (xMin == 99999 && yMin == 99999 && xMax == -99999 && yMax == -99999)) {
      xMin = original.xMin;
      yMin = original.yMin;
      xMax = original.xMax;
      yMax = original.yMax;
    }

    final glyph = GlyphData(
      character: original.character,
      unicode: original.unicode,
      contours: newContours,
      advanceWidth: original.advanceWidth,
      leftSideBearing: original.leftSideBearing,
      xMin: xMin,
      yMin: yMin,
      xMax: xMax,
      yMax: yMax,
      sourceImagePath: original.sourceImagePath,
      confidence: original.confidence,
    );

    // 粗体字形可能需要更宽的 advanceWidth
    final calculatedWidth = glyph.calculateAdvanceWidth();
    if (calculatedWidth > glyph.advanceWidth) {
      glyph.advanceWidth = calculatedWidth;
    }

    return glyph;
  }
}
