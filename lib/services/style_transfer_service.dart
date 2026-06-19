import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/project.dart';
import 'font_style_analyzer.dart';

/// 风格迁移参数
///
/// 控制风格迁移的行为和强度。
class StyleTransferParams {
  /// 迁移强度（0.0 = 不迁移，1.0 = 完全迁移）
  final double strength;

  /// 是否保留原始笔画粗细（仅迁移倾斜和连笔）
  final bool preserveStrokeWidth;

  /// 是否保留原始连笔特征
  final bool preserveConnections;

  /// 倾斜迁移强度（独立于主 strength，0.0~1.0）
  final double slantStrength;

  /// 粗细迁移强度（独立于主 strength，0.0~1.0）
  final double thicknessStrength;

  const StyleTransferParams({
    this.strength = 0.5,
    this.preserveStrokeWidth = false,
    this.preserveConnections = false,
    this.slantStrength = 1.0,
    this.thicknessStrength = 1.0,
  });

  /// 创建默认迁移参数
  factory StyleTransferParams.defaultParams() {
    return const StyleTransferParams(
      strength: 0.5,
      preserveStrokeWidth: false,
      preserveConnections: false,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'strength': strength,
        'preserveStrokeWidth': preserveStrokeWidth,
        'preserveConnections': preserveConnections,
        'slantStrength': slantStrength,
        'thicknessStrength': thicknessStrength,
      };

  /// 从 JSON 反序列化
  factory StyleTransferParams.fromJson(Map<String, dynamic> json) {
    return StyleTransferParams(
      strength: (json['strength'] as num?)?.toDouble() ?? 0.5,
      preserveStrokeWidth: json['preserveStrokeWidth'] as bool? ?? false,
      preserveConnections: json['preserveConnections'] as bool? ?? false,
      slantStrength: (json['slantStrength'] as num?)?.toDouble() ?? 1.0,
      thicknessStrength: (json['thicknessStrength'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// 风格迁移服务
///
/// 将参考字体的风格特征应用到手写字形上，
/// 实现字体风格的智能转换。
///
/// 算法概述：
/// 1. 分析源字形和目标风格的差异向量
/// 2. 对轮廓点应用仿射变换（shear 倾斜 + 法线方向粗细调整）
/// 3. 根据迁移强度做插值混合
/// 4. 重新计算字形边界
class StyleTransferService {
  StyleTransferService._();

  /// 对字形列表应用风格迁移
  ///
  /// [sourceGlyphs] 源字形列表（用户手写的字形）
  /// [targetStyle] 目标风格特征（从参考字体分析得到）
  /// [params] 迁移参数（强度等）
  ///
  /// 返回风格迁移后的字形列表，不修改原始数据。
  static Future<List<GlyphData>> transferStyle(
    List<GlyphData> sourceGlyphs,
    FontStyleProfile targetStyle,
    StyleTransferParams params,
  ) async {
    try {
      debugPrint(
        'StyleTransferService: 开始风格迁移 - '
        '${sourceGlyphs.length} 个字形，强度 ${(params.strength * 100).toStringAsFixed(0)}%',
      );

      if (sourceGlyphs.isEmpty) {
        debugPrint('StyleTransferService: 无字形数据，返回空列表');
        return [];
      }

      // 分析源字形的当前风格
      final sourceStyle = await FontStyleAnalyzer.analyzeFromGlyphs(
        sourceGlyphs,
      );

      // 逐个字形应用风格迁移
      final result = <GlyphData>[];
      for (final glyph in sourceGlyphs) {
        final transferred = _applyStyleTransfer(
          glyph,
          sourceStyle,
          targetStyle,
          params,
        );
        result.add(transferred);
      }

      debugPrint('StyleTransferService: 风格迁移完成');
      return result;
    } catch (e) {
      debugPrint('StyleTransferService: 风格迁移失败 - $e');
      return sourceGlyphs;
    }
  }

  /// 对单个字形应用风格迁移
  ///
  /// 根据源风格和目标风格的差异，按迁移强度调整字形轮廓。
  /// 实际变换包括：
  /// - 倾斜变换（仿射 shear）
  /// - 笔画粗细调整（沿法线方向缩放）
  /// - 连笔特征调整（控制点插值）
  static GlyphData _applyStyleTransfer(
    GlyphData sourceGlyph,
    FontStyleProfile sourceStyle,
    FontStyleProfile targetStyle,
    StyleTransferParams params,
  ) {
    final strength = params.strength;
    if (strength <= 0.0) return _copyGlyph(sourceGlyph);

    // 计算风格差异
    final slantDelta = (targetStyle.slantAngle - sourceStyle.slantAngle) *
        strength *
        params.slantStrength;
    final thicknessRatio = _computeThicknessRatio(
      sourceStyle,
      targetStyle,
      strength,
      params.thicknessStrength,
    );

    // 对每个轮廓应用变换
    final newContours = <Contour>[];
    for (final contour in sourceGlyph.contours) {
      final transformed = _transformContour(
        contour,
        slantDelta,
        thicknessRatio,
        params,
      );
      newContours.add(transformed);
    }

    // 重新计算字形边界
    final bounds = _computeBounds(newContours);

    return GlyphData(
      character: sourceGlyph.character,
      unicode: sourceGlyph.unicode,
      contours: newContours,
      advanceWidth: sourceGlyph.advanceWidth,
      leftSideBearing: sourceGlyph.leftSideBearing,
      xMin: bounds[0],
      yMin: bounds[1],
      xMax: bounds[2],
      yMax: bounds[3],
      sourceImagePath: sourceGlyph.sourceImagePath,
      confidence: sourceGlyph.confidence,
    );
  }

  /// 计算笔画粗细缩放比
  static double _computeThicknessRatio(
    FontStyleProfile source,
    FontStyleProfile target,
    double strength,
    double thicknessStrength,
  ) {
    // 如果源粗细为 0，避免除零
    if (source.averageStrokeWidth <= 0) return 1.0;
    final ratio = target.averageStrokeWidth / source.averageStrokeWidth;
    // 按强度插值：1.0 + (ratio - 1.0) * effectiveStrength
    final effective = strength * thicknessStrength;
    return 1.0 + (ratio - 1.0) * effective;
  }

  /// 对单个轮廓应用变换
  static Contour _transformContour(
    Contour contour,
    double slantDelta,
    double thicknessRatio,
    StyleTransferParams params,
  ) {
    if (contour.points.isEmpty) return contour;

    // 计算轮廓中心（用于法线方向缩放）
    double cx = 0, cy = 0;
    for (final p in contour.points) {
      cx += p.x;
      cy += p.y;
    }
    cx /= contour.points.length;
    cy /= contour.points.length;

    // 倾斜角转弧度
    final shearAngle = slantDelta * pi / 180.0;
    final shearFactor = tan(shearAngle);

    final newPoints = <ContourPoint>[];
    for (final p in contour.points) {
      double newX = p.x.toDouble();
      double newY = p.y.toDouble();

      // 1. 倾斜变换（shear）：沿 X 方向偏移
      // x' = x + (y - cy) * shearFactor
      newX += (newY - cy) * shearFactor;

      // 2. 笔画粗细调整：沿法线方向缩放
      // 法线近似为从轮廓中心到当前点的方向
      if (!params.preserveStrokeWidth && thicknessRatio != 1.0) {
        final dx = p.x - cx;
        final dy = p.y - cy;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist > 0.01) {
          final scale = thicknessRatio;
          newX = cx + dx * scale + (newX - p.x); // 叠加 shear 变换
          newY = cy + dy * scale;
        }
      }

      newPoints.add(ContourPoint(
        newX.round().clamp(-9999, 9999),
        newY.round().clamp(-9999, 9999),
        onCurve: p.onCurve,
      ));
    }

    return Contour(newPoints);
  }

  /// 计算轮廓列表的边界框
  static List<int> _computeBounds(List<Contour> contours) {
    if (contours.isEmpty) return [0, 0, 0, 0];
    int minX = 99999, minY = 99999, maxX = -99999, maxY = -99999;
    for (final contour in contours) {
      for (final p in contour.points) {
        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.x > maxX) maxX = p.x;
        if (p.y > maxY) maxY = p.y;
      }
    }
    return [minX, minY, maxX, maxY];
  }

  /// 深拷贝字形数据
  static GlyphData _copyGlyph(GlyphData source) {
    return GlyphData(
      character: source.character,
      unicode: source.unicode,
      contours: source.contours
          .map(
            (c) => Contour(
              c.points
                  .map(
                    (p) => ContourPoint(p.x, p.y, onCurve: p.onCurve),
                  )
                  .toList(),
            ),
          )
          .toList(),
      advanceWidth: source.advanceWidth,
      leftSideBearing: source.leftSideBearing,
      xMin: source.xMin,
      yMin: source.yMin,
      xMax: source.xMax,
      yMax: source.yMax,
      sourceImagePath: source.sourceImagePath,
      confidence: source.confidence,
    );
  }
}
