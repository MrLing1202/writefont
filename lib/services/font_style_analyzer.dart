import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/project.dart';

/// 字体风格特征数据类
///
/// 包含从 TTF 文件或手写字形中提取的风格参数，
/// 用于风格迁移时的目标风格参考。
class FontStyleProfile {
  /// 平均笔画粗细（单位：轮廓坐标单位）
  final double averageStrokeWidth;

  /// 倾斜角度（度数，正值右倾，负值左倾）
  final double slantAngle;

  /// 连笔特征强度（0.0 = 无连笔，1.0 = 强连笔）
  final double connectionStrength;

  /// 笔画起笔特征（0.0 = 尖锐，1.0 = 圆润）
  final double strokeStartRoundness;

  /// 笔画收笔特征（0.0 = 尖锐，1.0 = 圆润）
  final double strokeEndRoundness;

  /// 整体字形宽高比
  final double aspectRatio;

  /// 风格特征向量（用于相似度计算）
  final List<double> featureVector;

  const FontStyleProfile({
    required this.averageStrokeWidth,
    required this.slantAngle,
    required this.connectionStrength,
    required this.strokeStartRoundness,
    required this.strokeEndRoundness,
    required this.aspectRatio,
    required this.featureVector,
  });

  /// 创建默认的风格配置
  factory FontStyleProfile.defaultProfile() {
    return const FontStyleProfile(
      averageStrokeWidth: 100.0,
      slantAngle: 0.0,
      connectionStrength: 0.0,
      strokeStartRoundness: 0.5,
      strokeEndRoundness: 0.5,
      aspectRatio: 1.0,
      featureVector: [0.5, 0.5, 0.0, 0.5, 0.5, 1.0],
    );
  }

  @override
  String toString() {
    return 'FontStyleProfile('
        'strokeWidth: ${averageStrokeWidth.toStringAsFixed(1)}, '
        'slant: ${slantAngle.toStringAsFixed(1)}°, '
        'connection: ${(connectionStrength * 100).toStringAsFixed(0)}%, '
        'startRound: ${(strokeStartRoundness * 100).toStringAsFixed(0)}%, '
        'endRound: ${(strokeEndRoundness * 100).toStringAsFixed(0)}%, '
        'ratio: ${aspectRatio.toStringAsFixed(2)})';
  }
}

/// 字体风格分析服务
///
/// 解析 TTF 文件或手写字形数据，提取风格特征向量。
/// 用于风格迁移时确定目标风格。
class FontStyleAnalyzer {
  FontStyleAnalyzer._();

  /// 相邻轮廓点距离小于此阈值视为"连笔"
  static const double _connectionThreshold = 50.0;

  /// 计算两点间欧氏距离
  static double _dist(int x1, int y1, int x2, int y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    return sqrt(dx * dx + dy * dy);
  }

  /// 用三个点近似曲率：返回 |angle|，0 = 直线，π = 折返
  static double _curvature3(ContourPoint a, ContourPoint b, ContourPoint c) {
    final v1x = b.x - a.x;
    final v1y = b.y - a.y;
    final v2x = c.x - b.x;
    final v2y = c.y - b.y;
    final cross = (v1x * v2y - v1y * v2x).toDouble();
    final dot = (v1x * v2x + v1y * v2y).toDouble();
    return atan2(cross.abs(), dot.abs());
  }

  /// 将 [0, π/2] 范围的曲率映射到 [0, 1] 圆润度
  static double _roundnessFromCurvature(double curvature) {
    return (curvature / (pi / 2)).clamp(0.0, 1.0);
  }

  /// 归一化 6 个特征值到 [0, 1] 范围，组成 featureVector
  static List<double> _buildFeatureVector({
    required double averageStrokeWidth,
    required double slantAngle,
    required double connectionStrength,
    required double strokeStartRoundness,
    required double strokeEndRoundness,
    required double aspectRatio,
  }) {
    // strokeWidth: 假设正常范围 [10, 500]
    final swNorm = ((averageStrokeWidth - 10) / 490).clamp(0.0, 1.0);
    // slantAngle: 假设范围 [-30, 30] 度
    final slNorm = ((slantAngle + 30) / 60).clamp(0.0, 1.0);
    // connectionStrength: 已经是 [0, 1]
    final csNorm = connectionStrength.clamp(0.0, 1.0);
    // strokeStartRoundness / strokeEndRoundness: 已经是 [0, 1]
    final srNorm = strokeStartRoundness.clamp(0.0, 1.0);
    final erNorm = strokeEndRoundness.clamp(0.0, 1.0);
    // aspectRatio: 假设范围 [0.3, 3.0]
    final arNorm = ((aspectRatio - 0.3) / 2.7).clamp(0.0, 1.0);
    return [swNorm, slNorm, csNorm, srNorm, erNorm, arNorm];
  }

  // ──────────────────────────────────────────────
  // 公开 API
  // ──────────────────────────────────────────────

  /// 从 TTF 文件路径分析字体风格
  ///
  /// 解析 TTF 文件的 glyf 表，提取所有字形的轮廓数据，
  /// 复用 [analyzeFromGlyphs] 计算平均风格参数。
  static Future<FontStyleProfile> analyzeTtf(String ttfPath) async {
    try {
      debugPrint('FontStyleAnalyzer: 开始分析 TTF 文件 - $ttfPath');

      final file = File(ttfPath);
      final bytes = await file.readAsBytes();
      final glyphs = _parseTtfGlyphs(bytes);

      if (glyphs.isEmpty) {
        debugPrint('FontStyleAnalyzer: TTF 文件未解析到字形，返回默认配置');
        return FontStyleProfile.defaultProfile();
      }

      debugPrint('FontStyleAnalyzer: 解析到 ${glyphs.length} 个字形');
      final profile = await analyzeFromGlyphs(glyphs);

      debugPrint('FontStyleAnalyzer: TTF 分析完成 - $profile');
      return profile;
    } catch (e) {
      debugPrint('FontStyleAnalyzer: TTF 分析失败 - $e');
      return FontStyleProfile.defaultProfile();
    }
  }

  /// 从手写字形列表分析风格
  ///
  /// 分析用户手写的字形数据，提取风格特征。
  /// 适用于从已有项目中提取手写风格。
  static Future<FontStyleProfile> analyzeFromGlyphs(
    List<GlyphData> glyphs,
  ) async {
    try {
      debugPrint(
        'FontStyleAnalyzer: 开始分析 ${glyphs.length} 个手写字形',
      );

      if (glyphs.isEmpty) {
        debugPrint('FontStyleAnalyzer: 无字形数据，返回默认配置');
        return FontStyleProfile.defaultProfile();
      }

      // 收集所有轮廓
      final allContours = <List<ContourPoint>>[];
      for (final g in glyphs) {
        for (final c in g.contours) {
          if (c.points.length >= 2) {
            allContours.add(c.points);
          }
        }
      }

      if (allContours.isEmpty) {
        debugPrint('FontStyleAnalyzer: 无有效轮廓，返回默认配置');
        return FontStyleProfile.defaultProfile();
      }

      // 1. averageStrokeWidth：所有轮廓边界框对角线平均值的 1/10
      double diagSum = 0;
      for (final pts in allContours) {
        var cxMin = pts.first.x, cyMin = pts.first.y;
        var cxMax = pts.first.x, cyMax = pts.first.y;
        for (final p in pts) {
          if (p.x < cxMin) cxMin = p.x;
          if (p.y < cyMin) cyMin = p.y;
          if (p.x > cxMax) cxMax = p.x;
          if (p.y > cyMax) cyMax = p.y;
        }
        diagSum += _dist(cxMin, cyMin, cxMax, cyMax);
      }
      final averageStrokeWidth = diagSum / allContours.length / 10.0;

      // 2. slantAngle：取所有轮廓最高点和最低点的 x 差值，atan2
      var topX = 0.0, bottomX = 0.0;
      var topY = 1 << 30, bottomY = -(1 << 30);
      for (final pts in allContours) {
        for (final p in pts) {
          if (p.y < topY) {
            topY = p.y;
            topX = p.x.toDouble();
          }
          if (p.y > bottomY) {
            bottomY = p.y;
            bottomX = p.x.toDouble();
          }
        }
      }
      final slantAngle =
          atan2(bottomX - topX, (bottomY - topY).abs()) * 180 / pi;

      // 3. connectionStrength：相邻 on-curve 点之间距离 < 阈值的比例
      var closeCount = 0;
      var totalPairs = 0;
      for (final pts in allContours) {
        final onCurvePts = pts.where((p) => p.onCurve).toList();
        for (var i = 0; i < onCurvePts.length - 1; i++) {
          totalPairs++;
          final d = _dist(
            onCurvePts[i].x,
            onCurvePts[i].y,
            onCurvePts[i + 1].x,
            onCurvePts[i + 1].y,
          );
          if (d < _connectionThreshold) closeCount++;
        }
      }
      final connectionStrength =
          totalPairs > 0 ? closeCount / totalPairs : 0.0;

      // 4. strokeStartRoundness / strokeEndRoundness
      // 取每个轮廓首尾各 3 个 on-curve 点，计算曲率
      double startCurvSum = 0, endCurvSum = 0;
      var startCurvCount = 0, endCurvCount = 0;
      for (final pts in allContours) {
        final onCurvePts = pts.where((p) => p.onCurve).toList();
        if (onCurvePts.length >= 3) {
          startCurvSum +=
              _curvature3(onCurvePts[0], onCurvePts[1], onCurvePts[2]);
          startCurvCount++;
          final n = onCurvePts.length;
          endCurvSum +=
              _curvature3(onCurvePts[n - 3], onCurvePts[n - 2], onCurvePts[n - 1]);
          endCurvCount++;
        }
      }
      final strokeStartRoundness = startCurvCount > 0
          ? _roundnessFromCurvature(startCurvSum / startCurvCount)
          : 0.5;
      final strokeEndRoundness = endCurvCount > 0
          ? _roundnessFromCurvature(endCurvSum / endCurvCount)
          : 0.5;

      // 5. aspectRatio：所有字形边界框的平均宽高比
      double ratioSum = 0;
      var ratioCount = 0;
      for (final g in glyphs) {
        final w = g.xMax - g.xMin;
        final h = g.yMax - g.yMin;
        if (h > 0) {
          ratioSum += w / h;
          ratioCount++;
        }
      }
      final aspectRatio = ratioCount > 0 ? ratioSum / ratioCount : 1.0;

      // 6. featureVector：以上 6 个值归一化后组成
      final featureVector = _buildFeatureVector(
        averageStrokeWidth: averageStrokeWidth,
        slantAngle: slantAngle,
        connectionStrength: connectionStrength,
        strokeStartRoundness: strokeStartRoundness,
        strokeEndRoundness: strokeEndRoundness,
        aspectRatio: aspectRatio,
      );

      final profile = FontStyleProfile(
        averageStrokeWidth: averageStrokeWidth,
        slantAngle: slantAngle,
        connectionStrength: connectionStrength,
        strokeStartRoundness: strokeStartRoundness,
        strokeEndRoundness: strokeEndRoundness,
        aspectRatio: aspectRatio,
        featureVector: featureVector,
      );

      debugPrint('FontStyleAnalyzer: 手写字形分析完成 - $profile');
      return profile;
    } catch (e) {
      debugPrint('FontStyleAnalyzer: 手写字形分析失败 - $e');
      return FontStyleProfile.defaultProfile();
    }
  }

  // ──────────────────────────────────────────────
  // TTF 解析相关
  // ──────────────────────────────────────────────

  /// TTF glyf 表中单个字形的偏移与长度
  static List<GlyphData> _parseTtfGlyphs(Uint8List bytes) {
    if (bytes.length < 12) return [];

    final view = ByteData.sublistView(bytes);

    // 读取 offset table
    final numTables = view.getUint16(4);
    int glyfOffset = 0;
    int locaOffset = 0;
    int headOffset = 0;
    int numGlyphs = 0;

    for (var i = 0; i < numTables; i++) {
      final entryOffset = 12 + i * 16;
      if (entryOffset + 16 > bytes.length) break;
      final tag = String.fromCharCodes([
        bytes[entryOffset],
        bytes[entryOffset + 1],
        bytes[entryOffset + 2],
        bytes[entryOffset + 3],
      ]);
      final offset = view.getUint32(entryOffset + 8);
      if (tag == 'glyf') {
        glyfOffset = offset;
      } else if (tag == 'loca') {
        locaOffset = offset;
      } else if (tag == 'head') {
        headOffset = offset;
      } else if (tag == 'maxp') {
        numGlyphs = view.getUint16(offset + 4);
      }
    }

    if (glyfOffset == 0 || locaOffset == 0 || numGlyphs == 0) {
      debugPrint('FontStyleAnalyzer: TTF 缺少必要表 (glyf/loca/maxp)');
      return [];
    }

    // 判断 loca 格式：short (0) or long (1)
    final indexToLocFormat = view.getUint16(headOffset + 50);
    final glyphRecords = <({int index, int offset, int length})>[];

    for (var i = 0; i < numGlyphs; i++) {
      int start, end;
      if (indexToLocFormat == 0) {
        // short format: offset = value * 2
        start = view.getUint16(locaOffset + i * 2) * 2;
        end = view.getUint16(locaOffset + (i + 1) * 2) * 2;
      } else {
        // long format: offset = value
        start = view.getUint32(locaOffset + i * 4);
        end = view.getUint32(locaOffset + (i + 1) * 4);
      }
      if (start != end) {
        glyphRecords.add((
          index: i,
          offset: glyfOffset + start,
          length: end - start,
        ));
      }
    }

    // 解析每个字形的轮廓
    final glyphs = <GlyphData>[];
    for (final rec in glyphRecords) {
      if (rec.offset + rec.length > bytes.length) continue;
      final contours = _parseGlyphContours(view, rec.offset, rec.length);
      if (contours.isEmpty) continue;

      // 从轮廓点推算边界框
      var bxMin = 1 << 30, byMin = 1 << 30;
      var bxMax = -(1 << 30), byMax = -(1 << 30);
      for (final c in contours) {
        for (final p in c.points) {
          if (p.x < bxMin) bxMin = p.x;
          if (p.y < byMin) byMin = p.y;
          if (p.x > bxMax) bxMax = p.x;
          if (p.y > byMax) byMax = p.y;
        }
      }

      glyphs.add(GlyphData(
        character: '',
        unicode: rec.index,
        contours: contours,
        xMin: bxMin,
        yMin: byMin,
        xMax: bxMax,
        yMax: byMax,
      ));
    }

    return glyphs;
  }

  /// 解析单个 glyf 记录的轮廓
  static List<Contour> _parseGlyphContours(
    ByteData view,
    int offset,
    int length,
  ) {
    if (length < 10) return [];

    final numberOfContours = view.getInt16(offset);
    // 复合字形 (numberOfContours < 0) 跳过，只处理简单字形
    if (numberOfContours <= 0) return [];

    // 读取每个轮廓的终点索引
    final endPtsOfContours = <int>[];
    for (var i = 0; i < numberOfContours; i++) {
      endPtsOfContours.add(view.getUint16(offset + 10 + i * 2));
    }
    final totalPoints = endPtsOfContours.last + 1;

    // instruction length（跳过）
    final instrLenOffset = offset + 10 + numberOfContours * 2;
    final instrLen = view.getUint16(instrLenOffset);
    var pos = instrLenOffset + 2 + instrLen;

    // 读取 flags
    final flags = <int>[];
    while (flags.length < totalPoints) {
      if (pos >= view.lengthInBytes) break;
      final flag = view.getUint8(pos++);
      flags.add(flag);
      // REPEAT_BIT
      if (flag & 0x08 != 0) {
        if (pos >= view.lengthInBytes) break;
        final repeatCount = view.getUint8(pos++);
        for (var r = 0; r < repeatCount; r++) {
          flags.add(flag);
        }
      }
    }

    // 读取 x 坐标
    final xs = <int>[];
    var curX = 0;
    for (var i = 0; i < flags.length && i < totalPoints; i++) {
      final f = flags[i];
      if (f & 0x02 != 0) {
        // x-short vector
        if (pos >= view.lengthInBytes) break;
        final dx = view.getUint8(pos++);
        curX += (f & 0x10 != 0) ? dx : -dx;
      } else if (f & 0x10 == 0) {
        // 16-bit signed delta
        if (pos + 2 > view.lengthInBytes) break;
        curX += view.getInt16(pos);
        pos += 2;
      }
      // else: same x (delta = 0)
      xs.add(curX);
    }

    // 读取 y 坐标
    final ys = <int>[];
    var curY = 0;
    for (var i = 0; i < flags.length && i < totalPoints; i++) {
      final f = flags[i];
      if (f & 0x04 != 0) {
        // y-short vector
        if (pos >= view.lengthInBytes) break;
        final dy = view.getUint8(pos++);
        curY += (f & 0x20 != 0) ? dy : -dy;
      } else if (f & 0x20 == 0) {
        // 16-bit signed delta
        if (pos + 2 > view.lengthInBytes) break;
        curY += view.getInt16(pos);
        pos += 2;
      }
      // else: same y (delta = 0)
      ys.add(curY);
    }

    // 组装轮廓
    final pointCount = min(flags.length, min(xs.length, ys.length));
    if (pointCount < totalPoints) return [];

    final contours = <Contour>[];
    var startIdx = 0;
    for (var c = 0; c < numberOfContours; c++) {
      final endIdx = endPtsOfContours[c] + 1;
      final pts = <ContourPoint>[];
      for (var i = startIdx; i < endIdx && i < pointCount; i++) {
        pts.add(ContourPoint(
          xs[i],
          ys[i],
          onCurve: (flags[i] & 0x01) != 0,
        ));
      }
      if (pts.isNotEmpty) {
        contours.add(Contour(pts));
      }
      startIdx = endIdx;
    }

    return contours;
  }
}
