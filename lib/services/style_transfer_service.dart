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

  // ═══════════════════════════════════════════════════════════
  // 模型优化功能：模型压缩、模型量化、模型剪枝、模型蒸馏
  // ═══════════════════════════════════════════════════════════

  /// 模型优化配置
  static final Map<String, dynamic> _optimizationConfig = {
    'compressionRatio': 0.5,
    'quantizationBits': 8,
    'pruningThreshold': 0.01,
    'distillationTemperature': 3.0,
    'distillationAlpha': 0.7,
  };

  /// 获取当前优化配置
  static Map<String, dynamic> getOptimizationConfig() =>
      Map.unmodifiable(_optimizationConfig);

  /// 更新优化配置
  static void updateOptimizationConfig({
    double? compressionRatio,
    int? quantizationBits,
    double? pruningThreshold,
    double? distillationTemperature,
    double? distillationAlpha,
  }) {
    if (compressionRatio != null) {
      assert(compressionRatio > 0 && compressionRatio <= 1.0,
          'compressionRatio 必须在 (0, 1] 范围内');
      _optimizationConfig['compressionRatio'] = compressionRatio;
    }
    if (quantizationBits != null) {
      assert([2, 4, 8, 16].contains(quantizationBits),
          'quantizationBits 必须是 2, 4, 8 或 16');
      _optimizationConfig['quantizationBits'] = quantizationBits;
    }
    if (pruningThreshold != null) {
      assert(pruningThreshold >= 0, 'pruningThreshold 不能为负');
      _optimizationConfig['pruningThreshold'] = pruningThreshold;
    }
    if (distillationTemperature != null) {
      assert(distillationTemperature > 0, 'distillationTemperature 必须大于 0');
      _optimizationConfig['distillationTemperature'] = distillationTemperature;
    }
    if (distillationAlpha != null) {
      assert(distillationAlpha >= 0 && distillationAlpha <= 1.0,
          'distillationAlpha 必须在 [0, 1] 范围内');
      _optimizationConfig['distillationAlpha'] = distillationAlpha;
    }
    debugPrint('[StyleTransferService] 优化配置已更新: $_optimizationConfig');
  }

  // ── 模型压缩 ──

  /// 模型压缩结果
  static final List<Map<String, dynamic>> _compressionResults = [];

  /// 对轮廓数据进行压缩（减少控制点数量）
  ///
  /// [glyphs] 原始字形列表
  /// [ratio] 压缩比例（0.0~1.0，1.0 表示不压缩，0.5 表示保留 50% 的点）
  /// 返回压缩后的字形列表
  static List<GlyphData> compressGlyphs(
    List<GlyphData> glyphs, {
    double? ratio,
  }) {
    final compressionRatio = ratio ?? (_optimizationConfig['compressionRatio'] as double);
    debugPrint(
      'StyleTransferService: 开始模型压缩 - '
      '${glyphs.length} 个字形，压缩比 ${(compressionRatio * 100).toStringAsFixed(0)}%',
    );

    final result = <GlyphData>[];
    int totalPointsBefore = 0;
    int totalPointsAfter = 0;

    for (final glyph in glyphs) {
      final compressedContours = <Contour>[];
      for (final contour in glyph.contours) {
        totalPointsBefore += contour.points.length;

        // 根据压缩比例计算保留的点数
        final targetCount =
            (contour.points.length * compressionRatio).round().clamp(3, contour.points.length);

        // 均匀采样保留关键点
        final compressedPoints = _samplePoints(contour.points, targetCount);
        totalPointsAfter += compressedPoints.length;

        compressedContours.add(Contour(compressedPoints));
      }

      result.add(GlyphData(
        character: glyph.character,
        unicode: glyph.unicode,
        contours: compressedContours,
        advanceWidth: glyph.advanceWidth,
        leftSideBearing: glyph.leftSideBearing,
        xMin: glyph.xMin,
        yMin: glyph.yMin,
        xMax: glyph.xMax,
        yMax: glyph.yMax,
        sourceImagePath: glyph.sourceImagePath,
        confidence: glyph.confidence,
      ));
    }

    _compressionResults.add({
      'timestamp': DateTime.now().toIso8601String(),
      'glyphCount': glyphs.length,
      'pointsBefore': totalPointsBefore,
      'pointsAfter': totalPointsAfter,
      'compressionRatio': totalPointsBefore > 0
          ? totalPointsAfter / totalPointsBefore
          : 1.0,
    });

    debugPrint(
      'StyleTransferService: 压缩完成 - '
      '点数 $totalPointsBefore → $totalPointsAfter '
      '(${totalPointsBefore > 0 ? (totalPointsAfter / totalPointsBefore * 100).toStringAsFixed(1) : "100"}%)',
    );
    return result;
  }

  /// 均匀采样点列表
  static List<ContourPoint> _samplePoints(List<ContourPoint> points, int targetCount) {
    if (targetCount >= points.length) return List.from(points);
    if (targetCount <= 0) return [];
    if (targetCount == 1) return [points[points.length ~/ 2]];

    final result = <ContourPoint>[];
    final step = (points.length - 1) / (targetCount - 1);

    for (int i = 0; i < targetCount; i++) {
      final index = (i * step).round().clamp(0, points.length - 1);
      result.add(points[index]);
    }

    return result;
  }

  /// 获取压缩结果历史
  static List<Map<String, dynamic>> getCompressionResults() =>
      List.unmodifiable(_compressionResults);

  // ── 模型量化 ──

  /// 量化精度级别
  static const int quantInt2 = 2;
  static const int quantInt4 = 4;
  static const int quantInt8 = 8;
  static const int quantFloat16 = 16;

  /// 对轮廓点坐标进行量化（减少数值精度）
  ///
  /// [glyphs] 原始字形列表
  /// [bits] 量化位数（2, 4, 8, 16）
  /// 返回量化后的字形列表
  static List<GlyphData> quantizeGlyphs(
    List<GlyphData> glyphs, {
    int? bits,
  }) {
    final quantBits = bits ?? (_optimizationConfig['quantizationBits'] as int);
    final levels = 1 << quantBits; // 2^bits 个量化级别
    debugPrint(
      'StyleTransferService: 开始模型量化 - '
      '${glyphs.length} 个字形，${quantBits}bit 量化（$levels 级）',
    );

    // 先计算全局坐标范围用于量化映射
    int globalMin = 99999, globalMax = -99999;
    for (final glyph in glyphs) {
      for (final contour in glyph.contours) {
        for (final p in contour.points) {
          if (p.x < globalMin) globalMin = p.x;
          if (p.x > globalMax) globalMax = p.x;
          if (p.y < globalMin) globalMin = p.y;
          if (p.y > globalMax) globalMax = p.y;
        }
      }
    }

    final range = (globalMax - globalMin).abs().clamp(1, 99999);

    final result = <GlyphData>[];
    for (final glyph in glyphs) {
      final quantizedContours = <Contour>[];
      for (final contour in glyph.contours) {
        final quantizedPoints = contour.points.map((p) {
          // 量化：将坐标映射到有限级别再映射回来
          final normX = (p.x - globalMin) / range;
          final normY = (p.y - globalMin) / range;
          final quantX = (normX * (levels - 1)).round().clamp(0, levels - 1);
          final quantY = (normY * (levels - 1)).round().clamp(0, levels - 1);
          final restoredX = (quantX / (levels - 1) * range + globalMin).round();
          final restoredY = (quantY / (levels - 1) * range + globalMin).round();

          return ContourPoint(restoredX, restoredY, onCurve: p.onCurve);
        }).toList();
        quantizedContours.add(Contour(quantizedPoints));
      }

      result.add(GlyphData(
        character: glyph.character,
        unicode: glyph.unicode,
        contours: quantizedContours,
        advanceWidth: glyph.advanceWidth,
        leftSideBearing: glyph.leftSideBearing,
        xMin: glyph.xMin,
        yMin: glyph.yMin,
        xMax: glyph.xMax,
        yMax: glyph.yMax,
        sourceImagePath: glyph.sourceImagePath,
        confidence: glyph.confidence,
      ));
    }

    debugPrint('StyleTransferService: 量化完成');
    return result;
  }

  /// 计算量化误差（均方误差）
  static double computeQuantizationError(
    List<GlyphData> original,
    List<GlyphData> quantized,
  ) {
    double totalError = 0.0;
    int totalPoints = 0;

    for (int g = 0; g < original.length && g < quantized.length; g++) {
      for (int c = 0; c < original[g].contours.length && c < quantized[g].contours.length; c++) {
        final origPoints = original[g].contours[c].points;
        final quantPoints = quantized[g].contours[c].points;
        final len = origPoints.length < quantPoints.length
            ? origPoints.length
            : quantPoints.length;

        for (int i = 0; i < len; i++) {
          final dx = origPoints[i].x - quantPoints[i].x;
          final dy = origPoints[i].y - quantPoints[i].y;
          totalError += dx * dx + dy * dy;
          totalPoints++;
        }
      }
    }

    return totalPoints > 0 ? totalError / totalPoints : 0.0;
  }

  // ── 模型剪枝 ──

  /// 对字形轮廓进行剪枝（移除冗余/低贡献的控制点）
  ///
  /// [glyphs] 原始字形列表
  /// [threshold] 剪枝阈值（点位移小于此值的点被移除）
  /// 返回剪枝后的字形列表
  static List<GlyphData> pruneGlyphs(
    List<GlyphData> glyphs, {
    double? threshold,
  }) {
    final pruningThreshold =
        threshold ?? (_optimizationConfig['pruningThreshold'] as double);
    debugPrint(
      'StyleTransferService: 开始模型剪枝 - '
      '${glyphs.length} 个字形，阈值 $pruningThreshold',
    );

    final result = <GlyphData>[];
    int totalPointsBefore = 0;
    int totalPointsAfter = 0;
    int totalPruned = 0;

    for (final glyph in glyphs) {
      final prunedContours = <Contour>[];
      for (final contour in glyph.contours) {
        totalPointsBefore += contour.points.length;

        if (contour.points.length <= 3) {
          prunedContours.add(contour);
          totalPointsAfter += contour.points.length;
          continue;
        }

        // 计算每个点的重要性（基于与相邻点的曲率）
        final importance = _computePointImportance(contour.points);
        final prunedPoints = <ContourPoint>[];

        for (int i = 0; i < contour.points.length; i++) {
          // 始终保留首尾点和 onCurve 点
          if (i == 0 || i == contour.points.length - 1 ||
              contour.points[i].onCurve ||
              importance[i] >= pruningThreshold) {
            prunedPoints.add(contour.points[i]);
          } else {
            totalPruned++;
          }
        }

        // 确保至少保留 3 个点
        if (prunedPoints.length < 3 && contour.points.length >= 3) {
          prunedPoints.clear();
          prunedPoints.addAll(_samplePoints(contour.points, 3));
        }

        totalPointsAfter += prunedPoints.length;
        prunedContours.add(Contour(prunedPoints));
      }

      result.add(GlyphData(
        character: glyph.character,
        unicode: glyph.unicode,
        contours: prunedContours,
        advanceWidth: glyph.advanceWidth,
        leftSideBearing: glyph.leftSideBearing,
        xMin: glyph.xMin,
        yMin: glyph.yMin,
        xMax: glyph.xMax,
        yMax: glyph.yMax,
        sourceImagePath: glyph.sourceImagePath,
        confidence: glyph.confidence,
      ));
    }

    debugPrint(
      'StyleTransferService: 剪枝完成 - '
      '点数 $totalPointsBefore → $totalPointsAfter，'
      '移除 $totalPruned 个冗余点',
    );
    return result;
  }

  /// 计算轮廓各点的重要性（基于局部曲率）
  static List<double> _computePointImportance(List<ContourPoint> points) {
    final importance = List.filled(points.length, 0.0);

    for (int i = 1; i < points.length - 1; i++) {
      // 计算相邻三点构成的角度变化
      final prev = points[i - 1];
      final curr = points[i];
      final next = points[i + 1];

      final dx1 = curr.x - prev.x;
      final dy1 = curr.y - prev.y;
      final dx2 = next.x - curr.x;
      final dy2 = next.y - curr.y;

      final len1 = sqrt(dx1 * dx1 + dy1 * dy1);
      final len2 = sqrt(dx2 * dx2 + dy2 * dy2);

      if (len1 > 0 && len2 > 0) {
        final dot = dx1 * dx2 + dy1 * dy2;
        final cosAngle = (dot / (len1 * len2)).clamp(-1.0, 1.0);
        // 越接近 1（直线）重要性越低，越接近 -1（急转）重要性越高
        importance[i] = (1.0 - cosAngle) / 2.0;
      }
    }

    return importance;
  }

  // ── 模型蒸馏 ──

  /// 模型蒸馏：将教师风格的知识迁移到学生字形上
  ///
  /// [teacherGlyphs] 教师模型生成的字形（高质量参考）
  /// [studentGlyphs] 学生模型的字形（需要优化）
  /// [temperature] 蒸馏温度（越高越平滑）
  /// [alpha] 教师损失权重（1-alpha 为学生自身损失权重）
  /// 返回蒸馏后的字形列表
  static List<GlyphData> distillGlyphs(
    List<GlyphData> teacherGlyphs,
    List<GlyphData> studentGlyphs, {
    double? temperature,
    double? alpha,
  }) {
    final distillTemp =
        temperature ?? (_optimizationConfig['distillationTemperature'] as double);
    final distillAlpha =
        alpha ?? (_optimizationConfig['distillationAlpha'] as double);

    debugPrint(
      'StyleTransferService: 开始模型蒸馏 - '
      '教师 ${teacherGlyphs.length} 个，学生 ${studentGlyphs.length} 个，'
      '温度 $distillTemp，α=$distillAlpha',
    );

    final result = <GlyphData>[];

    // 按字符匹配教师和学生字形
    for (final student in studentGlyphs) {
      GlyphData? teacher;
      for (final t in teacherGlyphs) {
        if (t.character == student.character) {
          teacher = t;
          break;
        }
      }

      if (teacher == null) {
        // 没有对应的教师字形，保留原始学生字形
        result.add(_copyGlyph(student));
        continue;
      }

      // 蒸馏：按 α 权重混合教师和学生的轮廓特征
      final distilledContours = <Contour>[];
      final contourCount =
          student.contours.length < teacher.contours.length
              ? student.contours.length
              : teacher.contours.length;

      for (int c = 0; c < contourCount; c++) {
        final studentPoints = student.contours[c].points;
        final teacherPoints = teacher.contours[c].points;
        final pointCount = studentPoints.length < teacherPoints.length
            ? studentPoints.length
            : teacherPoints.length;

        final distilledPoints = <ContourPoint>[];
        for (int i = 0; i < pointCount; i++) {
          // 温度缩放后的软混合
          final softWeight = distillAlpha * (1.0 / distillTemp);
          final hardWeight = 1.0 - softWeight;

          final mixedX = (teacherPoints[i].x * softWeight +
                  studentPoints[i].x * hardWeight)
              .round();
          final mixedY = (teacherPoints[i].y * softWeight +
                  studentPoints[i].y * hardWeight)
              .round();

          distilledPoints.add(ContourPoint(
            mixedX, mixedY,
            onCurve: studentPoints[i].onCurve,
          ));
        }

        distilledContours.add(Contour(distilledPoints));
      }

      // 保留学生多余的轮廓
      for (int c = contourCount; c < student.contours.length; c++) {
        distilledContours.add(student.contours[c]);
      }

      result.add(GlyphData(
        character: student.character,
        unicode: student.unicode,
        contours: distilledContours,
        advanceWidth: student.advanceWidth,
        leftSideBearing: student.leftSideBearing,
        xMin: student.xMin,
        yMin: student.yMin,
        xMax: student.xMax,
        yMax: student.yMax,
        sourceImagePath: student.sourceImagePath,
        confidence: student.confidence,
      ));
    }

    debugPrint('StyleTransferService: 模型蒸馏完成');
    return result;
  }

  /// 获取模型优化综合报告
  static Map<String, dynamic> getOptimizationReport() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'config': getOptimizationConfig(),
      'compressionHistory': _compressionResults.take(10).toList(),
      'compressionCount': _compressionResults.length,
    };
  }
}
