import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 图像质量评估与增强服务
///
/// 在 OCR 识别前评估图像质量，对低质量图像自动应用增强预处理，
/// 提升手写汉字的识别率。
///
/// 评估指标：
/// - 对比度：灰度像素标准差
/// - 清晰度：拉普拉斯方差
/// - 噪声水平：高频分量能量比例
/// - 笔画粗细均匀度：骨架化前后前景像素比
/// - 倾斜角度：水平投影方差法检测
class ImageQualityService {
  static final ImageQualityService instance = ImageQualityService._();
  ImageQualityService._();

  // ═══════════════════════════════════════════════════════════
  // 质量评估
  // ═══════════════════════════════════════════════════════════

  /// 评估图像质量，返回 0.0（极差）~ 1.0（优秀）的综合分数
  ///
  /// 同时返回详细的评估指标 [QualityReport]，供增强策略使用。
  QualityReport assessQuality(img.Image image) {
    final gray = img.grayscale(image);

    // 1. 对比度（像素标准差）
    final contrast = _assessContrast(gray);

    // 2. 清晰度（拉普拉斯方差）
    final sharpness = _assessSharpness(gray);

    // 3. 噪声水平（高频分量比例）
    final noiseLevel = _assessNoiseLevel(gray);

    // 4. 笔画粗细均匀度（骨架化前后像素比）
    final strokeScore = _assessStrokeUniformity(gray);

    // 5. 倾斜角度
    final skewAngle = _detectSkewAngle(gray);

    // 综合评分（加权平均）
    // 对比度 25%，清晰度 30%，噪声 20%，笔画 25%
    final contrastScore = _normalizeContrast(contrast);
    final sharpnessScore = _normalizeSharpness(sharpness);
    final noiseScore = 1.0 - noiseLevel; // 噪声越低越好

    final overall = contrastScore * 0.25 +
        sharpnessScore * 0.30 +
        noiseScore * 0.20 +
        strokeScore * 0.25;

    debugPrint('图像质量评估: 综合=${(overall * 100).toStringAsFixed(0)}% '
        '对比度=${(contrastScore * 100).toStringAsFixed(0)}% '
        '清晰度=${(sharpnessScore * 100).toStringAsFixed(0)}% '
        '噪声=${(noiseScore * 100).toStringAsFixed(0)}% '
        '笔画=${(strokeScore * 100).toStringAsFixed(0)}% '
        '倾斜=${skewAngle.toStringAsFixed(1)}°');

    return QualityReport(
      overallScore: overall.clamp(0.0, 1.0),
      contrast: contrast,
      contrastScore: contrastScore,
      sharpness: sharpness,
      sharpnessScore: sharpnessScore,
      noiseLevel: noiseLevel,
      noiseScore: noiseScore,
      strokeScore: strokeScore,
      skewAngle: skewAngle,
    );
  }

  /// 根据质量评估结果自动选择增强策略
  ///
  /// [image] 原始图像
  /// [report] 质量评估报告
  /// 返回增强后的图像
  img.Image enhanceForRecognition(img.Image image, QualityReport report) {
    img.Image result = image;
    final actions = <String>[];

    // 低对比度 → 增强对比度
    if (report.contrastScore < 0.5) {
      result = _enhanceContrast(result);
      actions.add('对比度增强');
    }

    // 模糊 → 锐化 + 去噪
    if (report.sharpnessScore < 0.4) {
      result = _medianFilter(result); // 先去噪
      result = _sharpen(result); // 再锐化
      actions.add('锐化+去噪');
    }

    // 噪声大 → 中值滤波（如果前面没有去噪过）
    if (report.noiseLevel > 0.3 && report.sharpnessScore >= 0.4) {
      result = _medianFilter(result);
      actions.add('中值滤波去噪');
    }

    // 笔画太细 → 膨胀
    if (report.strokeScore < 0.4) {
      result = _morphologicalDilate(result, radius: 1);
      actions.add('膨胀增强笔画');
    }
    // 笔画太粗 → 腐蚀
    else if (report.strokeScore > 0.85) {
      result = _morphologicalErode(result, radius: 1);
      actions.add('腐蚀细化笔画');
    }

    // 倾斜 → 校正
    if (report.skewAngle.abs() >= 2.0) {
      result = img.copyRotate(result, angle: -report.skewAngle);
      actions.add('倾斜校正 ${report.skewAngle.toStringAsFixed(1)}°');
    }

    if (actions.isNotEmpty) {
      debugPrint('图像增强: ${actions.join(" → ")}');
    } else {
      debugPrint('图像质量良好，跳过增强');
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // 指标计算
  // ═══════════════════════════════════════════════════════════

  /// 对比度评估：灰度像素标准差
  ///
  /// 标准差越大，对比度越高。
  /// 典型值：低对比度 < 40，正常 50~80，高对比度 > 80
  double _assessContrast(img.Image gray) {
    final w = gray.width, h = gray.height;
    if (w == 0 || h == 0) return 0.0;

    // 采样计算（每 2 个像素取一个）
    double sum = 0;
    double sumSq = 0;
    int count = 0;

    for (int y = 0; y < h; y += 2) {
      for (int x = 0; x < w; x += 2) {
        final v = gray.getPixel(x, y).r.toDouble();
        sum += v;
        sumSq += v * v;
        count++;
      }
    }

    if (count == 0) return 0.0;
    final mean = sum / count;
    final variance = (sumSq / count) - mean * mean;
    return sqrt(max(0, variance));
  }

  /// 将对比度标准差归一化到 0.0~1.0
  double _normalizeContrast(double stdDev) {
    // 标准差 40 以下为低对比度，80 以上为高对比度
    return ((stdDev - 20) / 60).clamp(0.0, 1.0);
  }

  /// 清晰度评估：拉普拉斯方差
  ///
  /// 拉普拉斯算子响应的方差越大，图像越清晰。
  /// 典型值：模糊 < 50，正常 100~500，清晰 > 500
  double _assessSharpness(img.Image gray) {
    final w = gray.width, h = gray.height;
    if (w < 3 || h < 3) return 0.0;

    // 采样计算（每 2 个像素取一个）
    double sum = 0;
    double sumSq = 0;
    int count = 0;

    for (int y = 1; y < h - 1; y += 2) {
      for (int x = 1; x < w - 1; x += 2) {
        // 拉普拉斯核: [0,1,0, 1,-4,1, 0,1,0]
        final center = gray.getPixel(x, y).r.toInt() * 4;
        final top = gray.getPixel(x, y - 1).r.toInt();
        final bottom = gray.getPixel(x, y + 1).r.toInt();
        final left = gray.getPixel(x - 1, y).r.toInt();
        final right = gray.getPixel(x + 1, y).r.toInt();
        final laplacian = (top + bottom + left + right - center).abs().toDouble();
        sum += laplacian;
        sumSq += laplacian * laplacian;
        count++;
      }
    }

    if (count == 0) return 0.0;
    final mean = sum / count;
    final variance = (sumSq / count) - mean * mean;
    return max(0, variance);
  }

  /// 将拉普拉斯方差归一化到 0.0~1.0
  double _normalizeSharpness(double variance) {
    // 方差 50 以下为模糊，500 以上为清晰
    return ((variance - 30) / 470).clamp(0.0, 1.0);
  }

  /// 噪声水平评估：高频分量能量比例
  ///
  /// 通过拉普拉斯算子提取高频分量，
  /// 计算高频能量占总能量的比例。比例越高，噪声越大。
  /// 典型值：干净图像 < 0.15，中等噪声 0.15~0.35，高噪声 > 0.35
  double _assessNoiseLevel(img.Image gray) {
    final w = gray.width, h = gray.height;
    if (w < 3 || h < 3) return 0.0;

    double totalEnergy = 0;
    double highFreqEnergy = 0;
    int count = 0;

    for (int y = 1; y < h - 1; y += 2) {
      for (int x = 1; x < w - 1; x += 2) {
        final v = gray.getPixel(x, y).r.toDouble();
        totalEnergy += v * v;

        // 拉普拉斯响应（高频分量）
        final center = v * 4;
        final top = gray.getPixel(x, y - 1).r.toDouble();
        final bottom = gray.getPixel(x, y + 1).r.toDouble();
        final left = gray.getPixel(x - 1, y).r.toDouble();
        final right = gray.getPixel(x + 1, y).r.toDouble();
        final laplacian = (top + bottom + left + right - center).abs();
        highFreqEnergy += laplacian * laplacian;
        count++;
      }
    }

    if (count == 0 || totalEnergy == 0) return 0.0;

    // 高频能量占比
    final ratio = highFreqEnergy / totalEnergy;
    // 归一化：经验值，占比 0.05 以下为干净，0.2 以上为高噪声
    return ((ratio - 0.02) / 0.18).clamp(0.0, 1.0);
  }

  /// 笔画粗细均匀度评估
  ///
  /// 通过骨架化前后的前景像素比估算笔画宽度均匀性。
  /// 比值越接近 1，笔画越细（接近骨架）；
  /// 比值越大，笔画越粗。
  /// 返回 0.0~1.0 的分数，0.5 附近为最佳（标准笔画宽度）。
  double _assessStrokeUniformity(img.Image gray) {
    final w = gray.width, h = gray.height;
    if (w < 10 || h < 10) return 0.5;

    // 自适应二值化
    final binary = _adaptiveBinarize(gray, blockSize: 31, c: 10);

    // 统计前景像素数
    int foregroundCount = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (binary.getPixel(x, y).r.toInt() < 128) foregroundCount++;
      }
    }

    if (foregroundCount == 0) return 0.5;

    // 快速骨架化（简化版，仅用于评估）
    final skeletonCount = _quickSkeletonCount(binary);

    // 像素比：原始前景 / 骨架前景
    // 比值 1.0 = 已经是单像素宽，比值 5+ = 非常粗的笔画
    final ratio = skeletonCount > 0 ? foregroundCount / skeletonCount : 1.0;

    // 最佳比值约 2~3（标准笔画宽度约 2~3 像素）
    // 返回评分：比值在 1.5~4.0 范围内得分最高
    if (ratio < 1.2) return 0.3; // 笔画太细
    if (ratio > 6.0) return 0.3; // 笔画太粗
    if (ratio >= 1.5 && ratio <= 4.0) return 0.9; // 理想范围
    if (ratio < 1.5) return 0.5 + (ratio - 1.2) * 1.33; // 偏细
    return 0.9 - (ratio - 4.0) * 0.3; // 偏粗
  }

  /// 快速统计骨架化后的前景像素数（简化的 Zhang-Suen 算法）
  ///
  /// 只统计像素数，不生成完整图像，性能更高。
  int _quickSkeletonCount(img.Image binary) {
    final w = binary.width, h = binary.height;

    // 初始化标记数组
    var pixels = List.generate(
        h, (y) => List.generate(w, (x) => binary.getPixel(x, y).r.toInt() < 128));

    bool changed = true;
    int iterations = 0;
    const maxIterations = 30; // 限制迭代次数，仅用于评估

    while (changed && iterations < maxIterations) {
      changed = false;
      iterations++;
      final toRemove = List.generate(h, (_) => List.filled(w, false));

      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          if (!pixels[y][x]) continue;

          final p = [
            pixels[y - 1][x] ? 1 : 0,
            pixels[y - 1][x + 1] ? 1 : 0,
            pixels[y][x + 1] ? 1 : 0,
            pixels[y + 1][x + 1] ? 1 : 0,
            pixels[y + 1][x] ? 1 : 0,
            pixels[y + 1][x - 1] ? 1 : 0,
            pixels[y][x - 1] ? 1 : 0,
            pixels[y - 1][x - 1] ? 1 : 0,
          ];
          final bp = p[0] + p[1] + p[2] + p[3] + p[4] + p[5] + p[6] + p[7];
          if (bp < 2 || bp > 6) continue;

          int transitions = 0;
          for (int i = 0; i < 8; i++) {
            if (p[i] == 0 && p[(i + 1) % 8] == 1) transitions++;
          }
          if (transitions != 1) continue;
          if (p[0] * p[2] * p[4] != 0) continue;
          if (p[2] * p[4] * p[6] != 0) continue;

          toRemove[y][x] = true;
          changed = true;
        }
      }

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          if (toRemove[y][x]) pixels[y][x] = false;
        }
      }
    }

    // 统计剩余前景像素
    int count = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (pixels[y][x]) count++;
      }
    }
    return count;
  }

  /// 倾斜角度检测（投影法，±15° 范围）
  ///
  /// 对二值化图片在 -15°~+15° 范围内逐角度旋转，
  /// 计算每次旋转后水平投影的方差。方差最大时文字行最整齐，
  /// 即为最佳校正角度。
  double _detectSkewAngle(img.Image gray) {
    final w = gray.width, h = gray.height;
    if (w < 20 || h < 20) return 0.0;

    final binary = _adaptiveBinarize(gray, blockSize: 31, c: 10);

    double bestAngle = 0;
    double maxVariance = 0;

    // 以 1 度步长搜索最佳角度
    for (double angle = -15; angle <= 15; angle += 1.0) {
      final rotated = img.copyRotate(binary, angle: angle);
      final variance = _horizontalProjectionVariance(rotated);
      if (variance > maxVariance) {
        maxVariance = variance;
        bestAngle = angle;
      }
    }

    // 倾斜不足 1 度时返回 0
    if (bestAngle.abs() < 1.0) return 0.0;
    return bestAngle;
  }

  // ═══════════════════════════════════════════════════════════
  // 图像增强方法
  // ═══════════════════════════════════════════════════════════

  /// 对比度增强（CLAHE 简化版：局部直方图均衡化）
  img.Image _enhanceContrast(img.Image src) {
    // 先尝试简单的方法：调整对比度和亮度
    return img.adjustColor(src, contrast: 1.6, brightness: 1.1);
  }

  /// 中值滤波去噪（3x3 窗口）
  img.Image _medianFilter(img.Image src) {
    final w = src.width, h = src.height;
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final values = <int>[];
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            values.add(src.getPixel(nx, ny).r.toInt());
          }
        }
        values.sort();
        final median = values[4];
        result.setPixelRgba(x, y, median, median, median, 255);
      }
    }
    return result;
  }

  /// 锐化卷积（3x3 锐化核）
  img.Image _sharpen(img.Image src) {
    final w = src.width, h = src.height;
    final result = img.Image(width: w, height: h);
    // 锐化核: [0,-1,0, -1,5,-1, 0,-1,0]
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        num r = 0, g = 0, b = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            final pixel = src.getPixel(nx, ny);
            final weight = (dx == 0 && dy == 0) ? 5 : ((dx == 0 || dy == 0) ? -1 : 0);
            r += pixel.r * weight;
            g += pixel.g * weight;
            b += pixel.b * weight;
          }
        }
        result.setPixelRgba(
          x, y,
          r.clamp(0, 255).toInt(),
          g.clamp(0, 255).toInt(),
          b.clamp(0, 255).toInt(),
          255,
        );
      }
    }
    return result;
  }

  /// 形态学膨胀
  img.Image _morphologicalDilate(img.Image src, {int radius = 1}) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bool hasBlack = false;
        for (int dy = -radius; dy <= radius && !hasBlack; dy++) {
          for (int dx = -radius; dx <= radius && !hasBlack; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            if (gray.getPixel(nx, ny).r.toInt() < 128) hasBlack = true;
          }
        }
        final v = hasBlack ? 0 : 255;
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// 形态学腐蚀
  img.Image _morphologicalErode(img.Image src, {int radius = 1}) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bool allBlack = true;
        for (int dy = -radius; dy <= radius && allBlack; dy++) {
          for (int dx = -radius; dx <= radius && allBlack; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            if (gray.getPixel(nx, ny).r.toInt() >= 128) allBlack = false;
          }
        }
        final v = allBlack ? 0 : 255;
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// 自适应二值化（积分图加速）
  img.Image _adaptiveBinarize(img.Image gray, {int blockSize = 31, int c = 10}) {
    if (blockSize.isEven) blockSize++;
    final half = blockSize ~/ 2;
    final w = gray.width, h = gray.height;
    final result = img.Image(width: w, height: h);

    // 积分图加速
    final integral = List.generate(h, (_) => List.filled(w, 0));
    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        rowSum += gray.getPixel(x, y).r.toInt();
        integral[y][x] = rowSum + (y > 0 ? integral[y - 1][x] : 0);
      }
    }

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final x1 = (x - half).clamp(0, w - 1);
        final y1 = (y - half).clamp(0, h - 1);
        final x2 = (x + half).clamp(0, w - 1);
        final y2 = (y + half).clamp(0, h - 1);
        final count = (x2 - x1 + 1) * (y2 - y1 + 1);

        int sum = integral[y2][x2];
        if (x1 > 0) sum -= integral[y2][x1 - 1];
        if (y1 > 0) sum -= integral[y1 - 1][x2];
        if (x1 > 0 && y1 > 0) sum += integral[y1 - 1][x1 - 1];

        final localMean = sum / count;
        final threshold = localMean - c;
        final brightness = gray.getPixel(x, y).r.toInt();
        final v = brightness < threshold ? 0 : 255;
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// 水平投影方差（用于倾斜检测）
  double _horizontalProjectionVariance(img.Image binary) {
    final gray = img.grayscale(binary);
    final w = gray.width, h = gray.height;
    if (h == 0) return 0;

    final projections = List.filled(h, 0);
    for (int y = 0; y < h; y++) {
      int count = 0;
      for (int x = 0; x < w; x++) {
        if (gray.getPixel(x, y).r.toInt() < 128) count++;
      }
      projections[y] = count;
    }

    final mean = projections.reduce((a, b) => a + b) / h;
    double variance = 0;
    for (final p in projections) {
      variance += (p - mean) * (p - mean);
    }
    return variance / h;
  }
}

/// 图像质量评估报告
///
/// 包含各维度的原始测量值和归一化评分（0.0~1.0）。
class QualityReport {
  /// 综合质量分数（0.0~1.0）
  final double overallScore;

  /// 对比度：灰度像素标准差（原始值）
  final double contrast;

  /// 对比度评分（0.0~1.0，越高越好）
  final double contrastScore;

  /// 清晰度：拉普拉斯方差（原始值）
  final double sharpness;

  /// 清晰度评分（0.0~1.0，越高越好）
  final double sharpnessScore;

  /// 噪声水平（0.0~1.0，越低越好）
  final double noiseLevel;

  /// 噪声评分（0.0~1.0，越高越好，即 1 - noiseLevel）
  final double noiseScore;

  /// 笔画粗细均匀度评分（0.0~1.0，0.5 附近为最佳）
  final double strokeScore;

  /// 倾斜角度（度，负值表示左倾，正值表示右倾）
  final double skewAngle;

  const QualityReport({
    required this.overallScore,
    required this.contrast,
    required this.contrastScore,
    required this.sharpness,
    required this.sharpnessScore,
    required this.noiseLevel,
    required this.noiseScore,
    required this.strokeScore,
    required this.skewAngle,
  });

  /// 是否需要增强（综合评分低于 0.6）
  bool get needsEnhancement => overallScore < 0.6;

  /// 是否为低对比度
  bool get isLowContrast => contrastScore < 0.5;

  /// 是否模糊
  bool get isBlurry => sharpnessScore < 0.4;

  /// 是否高噪声
  bool get isNoisy => noiseLevel > 0.3;

  /// 笔画是否太细
  bool get isStrokeThin => strokeScore < 0.4;

  /// 笔画是否太粗
  bool get isStrokeThick => strokeScore > 0.85;

  /// 是否倾斜
  bool get isSkewed => skewAngle.abs() >= 2.0;

  @override
  String toString() => 'QualityReport('
      'overall=${(overallScore * 100).toStringAsFixed(0)}%, '
      'contrast=${(contrastScore * 100).toStringAsFixed(0)}%, '
      'sharpness=${(sharpnessScore * 100).toStringAsFixed(0)}%, '
      'noise=${(noiseScore * 100).toStringAsFixed(0)}%, '
      'stroke=${(strokeScore * 100).toStringAsFixed(0)}%, '
      'skew=${skewAngle.toStringAsFixed(1)}°)';
}
