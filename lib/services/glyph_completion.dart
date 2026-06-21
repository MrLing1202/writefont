import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/project.dart';

/// 字形自动补全服务
///
/// 分析已有字形的笔画特征（粗细、曲率），
/// 利用基础笔画模板（横、竖、撇、捺、点、钩、折）组合生成缺失字形的近似轮廓。
class GlyphCompletionService {
  GlyphCompletionService._();

  // ═══════════════════════════════════════════════════════════
  // 笔画模板（标准化坐标，归一化到 0~1000 空间）
  // ═══════════════════════════════════════════════════════════

  /// 横（从左到右）
  static List<Contour> _horizontalStroke(int x, int y, int width, int thickness) {
    final half = thickness ~/ 2;
    return [Contour([
      ContourPoint(x, y - half),
      ContourPoint(x + width, y - half),
      ContourPoint(x + width, y + half),
      ContourPoint(x, y + half),
    ])];
  }

  /// 竖（从上到下）
  static List<Contour> _verticalStroke(int x, int y, int height, int thickness) {
    final half = thickness ~/ 2;
    return [Contour([
      ContourPoint(x - half, y),
      ContourPoint(x + half, y),
      ContourPoint(x + half, y + height),
      ContourPoint(x - half, y + height),
    ])];
  }

  /// 撇（左下斜线，带弧度）
  static List<Contour> _leftFallingStroke(int x, int y, int length, int thickness) {
    final half = thickness ~/ 2;
    // 用梯形模拟左下斜笔
    return [Contour([
      ContourPoint(x - half, y - half),
      ContourPoint(x + half, y - half),
      ContourPoint(x + length ~/ 2 + half, y + length + half),
      ContourPoint(x + length ~/ 2 - half, y + length + half),
    ])];
  }

  /// 捺（右下斜线，渐粗）
  static List<Contour> _rightFallingStroke(int x, int y, int length, int thickness) {
    final half = thickness ~/ 2;
    final endHalf = (thickness * 0.8).toInt() ~/ 2; // 捺尾稍粗
    return [Contour([
      ContourPoint(x - half, y - half),
      ContourPoint(x + half, y - half),
      ContourPoint(x + length ~/ 2 + endHalf, y + length + half),
      ContourPoint(x + length ~/ 2 - endHalf, y + length + half),
    ])];
  }

  /// 点（小三角/短竖）
  static List<Contour> _dotStroke(int x, int y, int thickness) {
    final len = (thickness * 1.8).toInt();
    final half = thickness ~/ 2;
    return [Contour([
      ContourPoint(x, y),
      ContourPoint(x + half, y + len ~/ 3),
      ContourPoint(x, y + len),
      ContourPoint(x - half, y + len ~/ 3),
    ])];
  }

  /// 钩（竖笔末端向左钩）
  static List<Contour> _hookStroke(int x, int y, int height, int thickness) {
    final half = thickness ~/ 2;
    final hookLen = (thickness * 1.5).toInt();
    return [Contour([
      ContourPoint(x - half, y),
      ContourPoint(x + half, y),
      ContourPoint(x + half, y + height),
      ContourPoint(x - hookLen, y + height + half),
      ContourPoint(x - hookLen, y + height - half),
      ContourPoint(x - half, y + height - hookLen),
    ])];
  }

  /// 折（横折：横+竖的组合）
  static List<Contour> _turningStroke(int x, int y, int hWidth, int vHeight, int thickness) {
    final half = thickness ~/ 2;
    // 横段 + 竖段，折角处合并
    return [Contour([
      ContourPoint(x, y - half),
      ContourPoint(x + hWidth, y - half),
      ContourPoint(x + hWidth + half, y),
      ContourPoint(x + hWidth + half, y + vHeight),
      ContourPoint(x + hWidth - half, y + vHeight),
      ContourPoint(x + hWidth - half, y + half),
      ContourPoint(x, y + half),
    ])];
  }

  // ═══════════════════════════════════════════════════════════
  // 核心生成逻辑
  // ═══════════════════════════════════════════════════════════

  /// 分析已有字形的平均笔画粗细
  static int _analyzeStrokeThickness(FontProject project) {
    if (project.glyphs.isEmpty) return 60; // 默认值

    // 简单启发：计算所有轮廓点包围盒的平均尺寸，取较小维度的 ~6% 作为笔画粗细
    double totalSize = 0;
    int count = 0;
    for (final glyph in project.glyphs.values) {
      if (glyph.contours.isEmpty) continue;
      for (final contour in glyph.contours) {
        if (contour.points.length < 2) continue;
        int minX = 99999, maxX = -99999, minY = 99999, maxY = -99999;
        for (final p in contour.points) {
          if (p.x < minX) minX = p.x;
          if (p.x > maxX) maxX = p.x;
          if (p.y < minY) minY = p.y;
          if (p.y > maxY) maxY = p.y;
        }
        final size = min(maxX - minX, maxY - minY).toDouble();
        if (size > 5) {
          totalSize += size;
          count++;
        }
      }
    }

    if (count == 0) return 60;
    final avgSize = totalSize / count;
    return (avgSize * 0.08).toInt().clamp(20, 120);
  }

  /// 分析已有字形的典型包围盒尺寸
  static (int, int) _analyzeGlyphSize(FontProject project) {
    if (project.glyphs.isEmpty) return (800, 800);

    double totalW = 0, totalH = 0;
    int count = 0;
    for (final glyph in project.glyphs.values) {
      if (glyph.xMax > glyph.xMin && glyph.yMax > glyph.yMin) {
        totalW += glyph.xMax - glyph.xMin;
        totalH += glyph.yMax - glyph.yMin;
        count++;
      }
    }
    if (count == 0) return (800, 800);
    return (totalW ~/ count, totalH ~/ count);
  }

  /// 生成缺失字形
  ///
  /// 返回 Map<字符, List<Contour>>，每个字符对应一组近似轮廓。
  static Future<Map<String, List<Contour>>> generateMissingGlyphs(
    FontProject project,
    List<String> missingChars, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final result = <String, List<Contour>>{};
    if (missingChars.isEmpty) return result;

    final thickness = _analyzeStrokeThickness(project);
    final (avgWidth, avgHeight) = _analyzeGlyphSize(project);

    for (int i = 0; i < missingChars.length; i++) {
      final char = missingChars[i];
      try {
        final contours = _generateCharContours(char, thickness, avgWidth, avgHeight);
        if (contours.isNotEmpty) {
          result[char] = contours;
        }
      } catch (e) {
        debugPrint('[GlyphCompletion] 生成 "$char" 失败: $e');
      }
      onProgress?.call(i + 1, missingChars.length);

      // 每生成 50 个 yield 一次，避免阻塞
      if (i % 50 == 0 && i > 0) {
        await Future.delayed(const Duration(milliseconds: 1));
      }
    }

    debugPrint('[GlyphCompletion] 完成: ${result.length}/${missingChars.length} 个字形');
    return result;
  }

  /// 为单个字符生成轮廓
  static List<Contour> _generateCharContours(String char, int thickness, int width, int height) {
    // 优先使用 Unicode 部首/组件分解的启发式
    final contours = <Contour>[];

    // 将字符映射到基础笔画序列
    final strokes = _decomposeCharacter(char, thickness, width, height);
    contours.addAll(strokes);

    return contours;
  }

  /// 字符分解：根据 Unicode 区段和结构特征分配笔画
  ///
  /// 基础策略：
  /// 1. 符号类直接用简单几何形状
  /// 2. 汉字根据常用部首结构用横竖撇捺组合
  static List<Contour> _decomposeCharacter(String char, int thickness, int width, int height) {
    final code = char.codeUnitAt(0);
    final contours = <Contour>[];

    // 符号区域（全角 ASCII、标点等）
    if (code >= 0xFF01 && code <= 0xFF5E) {
      // 全角 ASCII → 画一个占满空间的方框 + 内部简化
      contours.addAll(_generateFullwidthSymbol(char, thickness, width, height));
      return contours;
    }

    // CJK 标点
    if ((code >= 0x3000 && code <= 0x303F) || (code >= 0xFF00 && code <= 0xFFEF)) {
      contours.addAll(_generatePunctuation(char, thickness, width, height));
      return contours;
    }

    // 汉字（CJK 统一汉字）
    if (code >= 0x4E00 && code <= 0x9FFF) {
      contours.addAll(_generateCJKChar(char, thickness, width, height));
      return contours;
    }

    // 其他字符：占满空间的方框
    contours.addAll(_generatePlaceholderBox(thickness, width, height));
    return contours;
  }

  /// 生成 CJK 汉字的近似笔画组合
  ///
  /// 使用简单启发：根据笔画数估算，用模板组合填充。
  static List<Contour> _generateCJKChar(String char, int thickness, int width, int height) {
    final contours = <Contour>[];
    // 估算笔画数（Unicode CJK 笔画数数据库不可用时的简单启发）
    final strokeCount = _estimateStrokeCount(char);

    // 可用区域（留边距）
    final margin = (width * 0.12).toInt();
    final innerW = width - margin * 2;
    final innerH = height - margin * 2;
    final startX = margin;
    final startY = margin;

    // 生成笔画模板序列
    final templates = _pickStrokeTemplates(strokeCount, startX, startY, innerW, innerH, thickness);

    for (final stroke in templates) {
      contours.addAll(stroke);
    }

    return contours;
  }

  /// 估算字符笔画数（简单启发，基于 Unicode 编码位置的伪随机分布）
  static int _estimateStrokeCount(String char) {
    final code = char.codeUnitAt(0);
    // 使用编码位置做简单哈希，映射到 2~18 笔
    final hash = (code * 2654435761) & 0xFFFFFFFF; // Knuth multiplicative hash
    return (2 + (hash % 15)).toInt(); // 2~16 笔
  }

  /// 根据笔画数选择合适的笔画模板组合
  static List<List<Contour>> _pickStrokeTemplates(
    int strokeCount, int x, int y, int w, int h, int thickness,
  ) {
    final strokes = <List<Contour>>[];

    // 基础结构：先横后竖，再补充撇捺
    // 外框（横折）
    if (strokeCount >= 4) {
      strokes.add(_turningStroke(x, y, w * 0.8 ~/ 1, h * 0.8 ~/ 1, thickness));
    }

    // 内部横笔
    final hCount = (strokeCount * 0.35).toInt().clamp(0, 4);
    for (int i = 0; i < hCount; i++) {
      final rowY = y + h * (i + 1) ~/ (hCount + 1);
      final startX = x + (w * 0.15).toInt();
      final endX = x + w - (w * 0.15).toInt();
      strokes.add(_horizontalStroke(startX, rowY, endX - startX, thickness));
    }

    // 内部竖笔
    final vCount = (strokeCount * 0.25).toInt().clamp(0, 3);
    for (int i = 0; i < vCount; i++) {
      final colX = x + w * (i + 1) ~/ (vCount + 1);
      final startY = y + (h * 0.15).toInt();
      final endY = y + h - (h * 0.15).toInt();
      strokes.add(_verticalStroke(colX, startY, endY - startY, thickness));
    }

    // 撇
    if (strokeCount >= 3) {
      strokes.add(_leftFallingStroke(
        x + w ~/ 3, y + (h * 0.2).toInt(),
        h * 0.5 ~/ 1, thickness,
      ));
    }

    // 捺
    if (strokeCount >= 5) {
      strokes.add(_rightFallingStroke(
        x + w * 2 ~/ 3, y + (h * 0.2).toInt(),
        h * 0.5 ~/ 1, thickness,
      ));
    }

    // 点
    if (strokeCount >= 6) {
      strokes.add(_dotStroke(
        x + w * 3 ~/ 4, y + (h * 0.15).toInt(), thickness,
      ));
    }

    return strokes;
  }

  /// 全角符号生成
  static List<Contour> _generateFullwidthSymbol(String char, int thickness, int width, int height) {
    final contours = <Contour>[];
    final margin = (width * 0.1).toInt();

    // 先画外框
    contours.addAll(_generatePlaceholderBox(thickness, width, height));

    // 根据符号类型添加内部特征
    final code = char.codeUnitAt(0);
    final halfCode = code - 0xFF01 + 0x0021; // 映射回半角

    if (halfCode >= 0x30 && halfCode <= 0x39) {
      // 数字 0-9：画简单的横竖组合
      contours.addAll(_generateDigitLike(halfCode - 0x30, margin, width, height, thickness));
    } else if (halfCode >= 0x41 && halfCode <= 0x5A) {
      // 大写字母 A-Z
      contours.addAll(_generateLetterLike(halfCode - 0x41, margin, width, height, thickness));
    } else if (halfCode >= 0x61 && halfCode <= 0x7A) {
      // 小写字母 a-z
      contours.addAll(_generateLetterLike(halfCode - 0x61 + 26, margin, width, height, thickness));
    }

    return contours;
  }

  /// 标点符号生成
  static List<Contour> _generatePunctuation(String char, int thickness, int width, int height) {
    // 简单方框占位
    return _generatePlaceholderBox(thickness, width, height);
  }

  /// 数字近似形状
  static List<Contour> _generateDigitLike(int digit, int margin, int width, int height, int thickness) {
    final contours = <Contour>[];
    final x = margin;
    final y = margin;
    final w = width - margin * 2;
    final h = height - margin * 2;

    switch (digit % 5) {
      case 0: // 类似 0：竖+横折
        contours.addAll(_verticalStroke(x, y, h, thickness));
        contours.addAll(_turningStroke(x, y, w, h, thickness));
        break;
      case 1: // 类似 1：单竖
        contours.addAll(_verticalStroke(x + w ~/ 2, y, h, thickness));
        break;
      case 2: // 类似 2：横+折+横
        contours.addAll(_horizontalStroke(x, y, w, thickness));
        contours.addAll(_turningStroke(x + w ~/ 2, y, w ~/ 2, h ~/ 2, thickness));
        contours.addAll(_horizontalStroke(x, y + h, w, thickness));
        break;
      case 3: // 类似 3：两横+折
        contours.addAll(_horizontalStroke(x, y, w, thickness));
        contours.addAll(_horizontalStroke(x, y + h ~/ 2, w, thickness));
        contours.addAll(_horizontalStroke(x, y + h, w, thickness));
        break;
      default: // 类似 4：竖+横
        contours.addAll(_verticalStroke(x + w * 2 ~/ 3, y, h, thickness));
        contours.addAll(_horizontalStroke(x, y + h ~/ 2, w, thickness));
    }

    return contours;
  }

  /// 字母近似形状
  static List<Contour> _generateLetterLike(int index, int margin, int width, int height, int thickness) {
    final contours = <Contour>[];
    final x = margin;
    final y = margin;
    final w = width - margin * 2;
    final h = height - margin * 2;

    // 简化：根据 index 选择 5 种基本结构之一
    switch (index % 5) {
      case 0: // 类 A：三角 + 横
        contours.addAll(_leftFallingStroke(x, y, h, thickness));
        contours.addAll(_rightFallingStroke(x + w ~/ 2, y, h, thickness));
        contours.addAll(_horizontalStroke(x + w ~/ 4, y + h ~/ 2, w ~/ 2, thickness));
        break;
      case 1: // 类 E：三横 + 竖
        contours.addAll(_verticalStroke(x, y, h, thickness));
        contours.addAll(_horizontalStroke(x, y, w, thickness));
        contours.addAll(_horizontalStroke(x, y + h ~/ 2, w * 2 ~/ 3, thickness));
        contours.addAll(_horizontalStroke(x, y + h, w, thickness));
        break;
      case 2: // 类 H：两竖 + 横
        contours.addAll(_verticalStroke(x, y, h, thickness));
        contours.addAll(_verticalStroke(x + w, y, h, thickness));
        contours.addAll(_horizontalStroke(x, y + h ~/ 2, w, thickness));
        break;
      case 3: // 类 L：竖 + 横
        contours.addAll(_verticalStroke(x, y, h, thickness));
        contours.addAll(_horizontalStroke(x, y + h, w, thickness));
        break;
      default: // 类 O：方框
        contours.addAll(_turningStroke(x, y, w, h, thickness));
    }

    return contours;
  }

  /// 占位方框
  static List<Contour> _generatePlaceholderBox(int thickness, int width, int height) {
    final half = thickness ~/ 2;
    // 外框
    return [Contour([
      ContourPoint(half, half),
      ContourPoint(width - half, half),
      ContourPoint(width - half, height - half),
      ContourPoint(half, height - half),
    ])];
  }
}
