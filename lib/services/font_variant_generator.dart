import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/project.dart';
import 'ttf_builder.dart';

/// 字体变体类型枚举
enum FontVariantType {
  bold,   // 加粗
  italic, // 倾斜
  light,  // 变细
}

/// 字体变体生成结果
class FontVariantResult {
  /// 变体类型
  final FontVariantType type;

  /// 生成的 TTF 文件路径
  final String filePath;

  /// 文件大小（字节）
  final int fileSize;

  /// 变体名称
  final String variantName;

  const FontVariantResult({
    required this.type,
    required this.filePath,
    required this.fileSize,
    required this.variantName,
  });
}

/// 字体变体生成器
///
/// 从基础字体的轮廓数据生成 Bold（加粗）、Italic（倾斜）、Light（变细）变体。
/// 核心原理：
/// - Bold：对轮廓点进行径向外扩，增加笔画粗细
/// - Italic：对所有点应用仿射倾斜变换
/// - Light：对轮廓点进行径向内缩，减细笔画
class FontVariantGenerator {
  /// 从基础项目生成指定变体
  ///
  /// [project] 基础字体项目
  /// [variant] 变体类型
  /// [intensity] 变体强度 0.0-1.0（默认 0.5）
  /// [familyName] 字体家族名称（可选）
  static Future<FontVariantResult> generate({
    required FontProject project,
    required FontVariantType variant,
    double intensity = 0.5,
    String? familyName,
  }) async {
    // 复制字形数据并应用变换
    final transformedGlyphs = <GlyphData>[];
    for (final glyph in project.glyphs.values) {
      if (glyph.contours.isEmpty) continue;
      final transformed = _transformGlyph(glyph, variant, intensity);
      transformedGlyphs.add(transformed);
    }

    // 确定变体名称和子族名
    final variantName = _getVariantName(variant);
    final subfamilyName = _getSubfamilyName(variant);
    final baseName = familyName ?? project.metadata?.familyName ?? project.name;

    // 构建 TTF
    final builder = TtfBuilder(
      glyphs: transformedGlyphs,
      familyName: baseName,
      customFamilyName: baseName,
      customSubfamilyName: subfamilyName,
      customVersion: 'Version 1.0',
      customCopyright: project.metadata?.copyright ?? '',
    );

    final ttfBytes = builder.build(
      familyName: baseName,
      subfamilyName: subfamilyName,
    );

    // 保存到临时目录
    final dir = await getTemporaryDirectory();
    final safeName = baseName.replaceAll(RegExp(r'[^\w\-]'), '_');
    final fileName = '${safeName}_$variantName.ttf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(ttfBytes);

    return FontVariantResult(
      type: variant,
      filePath: file.path,
      fileSize: ttfBytes.length,
      variantName: '$baseName $subfamilyName',
    );
  }

  /// 批量生成所有变体（Bold、Italic、Light）
  ///
  /// [project] 基础字体项目
  /// [intensity] 变体强度 0.0-1.0
  /// [familyName] 字体家族名称（可选）
  /// 返回所有变体结果列表
  static Future<List<FontVariantResult>> generateAll({
    required FontProject project,
    double intensity = 0.5,
    String? familyName,
  }) async {
    final results = <FontVariantResult>[];
    for (final variant in FontVariantType.values) {
      final result = await generate(
        project: project,
        variant: variant,
        intensity: intensity,
        familyName: familyName,
      );
      results.add(result);
    }
    return results;
  }

  /// 对单个字形应用变体变换
  static GlyphData _transformGlyph(
    GlyphData glyph,
    FontVariantType variant,
    double intensity,
  ) {
    // 复制轮廓数据
    final newContours = <Contour>[];
    for (final contour in glyph.contours) {
      final newPoints = <ContourPoint>[];
      for (final point in contour.points) {
        var x = point.x;
        var y = point.y;

        switch (variant) {
          case FontVariantType.bold:
            // 加粗：计算点到轮廓中心的方向，沿方向外扩
            final center = _getContourCenter(contour);
            final dx = x - center.x;
            final dy = y - center.y;
            final dist = sqrt(dx * dx + dy * dy);
            if (dist > 0) {
              // 加粗量：基于强度，最大外扩 30 个单位
              final boldAmount = intensity * 30.0;
              x = x + (dx / dist * boldAmount).round();
              y = y + (dy / dist * boldAmount).round();
            }
            break;

          case FontVariantType.italic:
            // 倾斜：应用仿射变换 x' = x + y * tan(angle)
            // 倾斜角度：基于强度，最大 12 度
            final angle = intensity * 12.0 * pi / 180.0;
            final shear = tan(angle);
            x = x + (y * shear).round();
            break;

          case FontVariantType.light:
            // 变细：计算点到轮廓中心的方向，沿方向内缩
            final center = _getContourCenter(contour);
            final dx = x - center.x;
            final dy = y - center.y;
            final dist = sqrt(dx * dx + dy * dy);
            if (dist > 0) {
              // 变细量：基于强度，最大内缩 20 个单位
              final lightAmount = intensity * 20.0;
              x = x - (dx / dist * lightAmount).round();
              y = y - (dy / dist * lightAmount).round();
            }
            break;
        }

        newPoints.add(ContourPoint(x, y, onCurve: point.onCurve));
      }
      newContours.add(Contour(newPoints));
    }

    // 计算新的边界框
    int xMin = 9999, yMin = 9999, xMax = -9999, yMax = -9999;
    for (final contour in newContours) {
      for (final point in contour.points) {
        if (point.x < xMin) xMin = point.x;
        if (point.y < yMin) yMin = point.y;
        if (point.x > xMax) xMax = point.x;
        if (point.y > yMax) yMax = point.y;
      }
    }

    return GlyphData(
      character: glyph.character,
      unicode: glyph.unicode,
      contours: newContours,
      advanceWidth: glyph.advanceWidth,
      leftSideBearing: glyph.leftSideBearing,
      xMin: xMin == 9999 ? glyph.xMin : xMin,
      yMin: yMin == 9999 ? glyph.yMin : yMin,
      xMax: xMax == -9999 ? glyph.xMax : xMax,
      yMax: yMax == -9999 ? glyph.yMax : yMax,
    );
  }

  /// 计算轮廓的几何中心点
  static ({int x, int y}) _getContourCenter(Contour contour) {
    if (contour.points.isEmpty) return (x: 0, y: 0);
    int sumX = 0, sumY = 0;
    for (final point in contour.points) {
      sumX += point.x;
      sumY += point.y;
    }
    final count = contour.points.length;
    return (x: sumX ~/ count, y: sumY ~/ count);
  }

  /// 获取变体名称（用于文件名）
  static String _getVariantName(FontVariantType variant) {
    switch (variant) {
      case FontVariantType.bold:
        return 'Bold';
      case FontVariantType.italic:
        return 'Italic';
      case FontVariantType.light:
        return 'Light';
    }
  }

  /// 获取变体子族名称（用于字体元数据）
  static String _getSubfamilyName(FontVariantType variant) {
    switch (variant) {
      case FontVariantType.bold:
        return 'Bold';
      case FontVariantType.italic:
        return 'Italic';
      case FontVariantType.light:
        return 'Light';
    }
  }
}
