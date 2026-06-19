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

  const StyleTransferParams({
    this.strength = 0.5,
    this.preserveStrokeWidth = false,
    this.preserveConnections = false,
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
      };

  /// 从 JSON 反序列化
  factory StyleTransferParams.fromJson(Map<String, dynamic> json) {
    return StyleTransferParams(
      strength: (json['strength'] as num?)?.toDouble() ?? 0.5,
      preserveStrokeWidth: json['preserveStrokeWidth'] as bool? ?? false,
      preserveConnections: json['preserveConnections'] as bool? ?? false,
    );
  }
}

/// 风格迁移服务
///
/// 将参考字体的风格特征应用到手写字形上，
/// 实现字体风格的智能转换。
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
  static GlyphData _applyStyleTransfer(
    GlyphData sourceGlyph,
    FontStyleProfile sourceStyle,
    FontStyleProfile targetStyle,
    StyleTransferParams params,
  ) {
    // TODO: 私有算法，需替换为实际实现
    // 实际实现应包括：
    // 1. 计算源风格和目标风格的差异向量
    // 2. 根据迁移强度缩放差异
    // 3. 对轮廓点应用变换：
    //    - 笔画粗细调整（沿法线方向缩放）
    //    - 倾斜变换（仿射变换 shear）
    //    - 连笔特征调整（控制点插值）
    // 4. 重新计算字形边界和字宽

    // 占位符：返回原始字形的副本（不做实际变换）
    final transferred = GlyphData(
      character: sourceGlyph.character,
      unicode: sourceGlyph.unicode,
      contours: sourceGlyph.contours
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
      advanceWidth: sourceGlyph.advanceWidth,
      leftSideBearing: sourceGlyph.leftSideBearing,
      xMin: sourceGlyph.xMin,
      yMin: sourceGlyph.yMin,
      xMax: sourceGlyph.xMax,
      yMax: sourceGlyph.yMax,
      sourceImagePath: sourceGlyph.sourceImagePath,
      confidence: sourceGlyph.confidence,
    );

    return transferred;
  }
}
