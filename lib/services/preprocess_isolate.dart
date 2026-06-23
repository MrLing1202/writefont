/// 预处理 Isolate 工作者 — v4.9.0
///
/// 将 CPU 密集型图像预处理放到独立 Isolate 中执行，
/// 与主线程的 ML Kit 识别形成流水线，减少总识别耗时。
///
/// 架构：
///   主线程: [预处理A] → [ML Kit A] → [预处理B] → [ML Kit B] → ...
///   v4.9.0: [预处理A,B,C,D‖] → [ML Kit A] → [ML Kit B] → [ML Kit C] → ...
///           ↑ 4核并行                           ↑ 顺序识别（ML Kit 不支持并发）
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// 预处理任务参数
class PreprocessTask {
  final Uint8List imageBytes;
  final String strategyName;
  final int taskIndex; // 用于保持顺序

  const PreprocessTask({
    required this.imageBytes,
    required this.strategyName,
    required this.taskIndex,
  });
}

/// 预处理结果
class PreprocessResult {
  final Uint8List processedBytes;
  final String strategyName;
  final int taskIndex;

  const PreprocessResult({
    required this.processedBytes,
    required this.strategyName,
    required this.taskIndex,
  });
}

/// Isolate 入口：接收 [PreprocessTask]，返回 [PreprocessResult]
///
/// 使用方式：`Isolate.run(() => preprocessInIsolate(task))`
PreprocessResult preprocessInIsolate(PreprocessTask task) {
  final decoded = img.decodeImage(task.imageBytes);
  if (decoded == null) {
    return PreprocessResult(
      processedBytes: task.imageBytes,
      strategyName: task.strategyName,
      taskIndex: task.taskIndex,
    );
  }

  final result = applyStrategy(task.strategyName, decoded);
  final encoded = Uint8List.fromList(img.encodePng(result));

  return PreprocessResult(
    processedBytes: encoded,
    strategyName: task.strategyName,
    taskIndex: task.taskIndex,
  );
}

/// 策略调度器：根据策略名应用对应的图像处理
img.Image applyStrategy(String name, img.Image src) {
  switch (name) {
    // ═══ 基础策略 ═══
    case '灰度':
      return img.grayscale(src);
    case '灰度+对比度':
      return img.adjustColor(img.grayscale(src), contrast: 1.5, brightness: 1.1);
    case '灰度+锐化':
      return _sharpen(img.grayscale(src));
    case '灰度+去噪':
      return _medianFilter(img.grayscale(src));
    case '灰度+自适应二值化':
      return _adaptiveBinarize(img.grayscale(src), blockSize: 31, c: 10);
    case '灰度+对比度+二值化':
      return _binarize(img.adjustColor(img.grayscale(src), contrast: 1.5, brightness: 1.1));
    case '灰度+去噪+锐化':
      return _sharpen(_medianFilter(img.grayscale(src)));
    case '灰度+去噪+自适应二值化':
      return _adaptiveBinarize(_medianFilter(img.grayscale(src)), blockSize: 31, c: 10);
    case '灰度+对比度+去噪+二值化':
      return _binarize(_medianFilter(img.adjustColor(img.grayscale(src), contrast: 1.5, brightness: 1.1)));

    // ═══ 手写体专用 ═══
    case '手写体笔画增强':
      return _handwritingEnhance(src);
    case '倾斜校正':
      return _skewCorrection(src);
    case '笔画归一化':
      return _strokeNormalization(src);
    case '手写体增强+对比度':
      return img.adjustColor(_handwritingEnhance(src), contrast: 1.5, brightness: 1.1);

    // ═══ CLAHE / 背景归一化 / 边缘增强 ═══
    case '自适应对比度增强':
      return _clahe(img.grayscale(src));
    case '背景归一化':
      return _normalizeBackground(src);
    case '方向边缘增强':
      return _directionalEdgeEnhance(src);
    case 'CLAHE自适应':
      return _claheAdaptive(src);

    // ═══ USM 锐化 ═══
    case 'USM笔画锐化':
      return _unsharpMaskSharpen(src, amount: 1.5);
    case 'USM强锐化':
      return _unsharpMaskSharpen(src, amount: 2.0);
    case 'USM锐化+CLAHE':
      return _clahe(_unsharpMaskSharpen(src, amount: 1.5));

    // ═══ v2.6.0 新增 ═══
    case '自适应直方图均衡':
      return _adaptiveHistogramEqualizeQuadrants(src);
    case '形态学骨架化':
      return _morphologicalSkeletonize(src);
    case '高斯模糊去噪+锐化':
      return _gaussianBlurSharpen(src);
    case '局部阈值二值化':
      return _localThresholdBinarize(src);

    // ═══ v4.3.0 形态学 ═══
    case '笔画粗细自适应':
      return _strokeThicknessAdaptive(src);
    case '断笔修复':
      return _morphologicalClose(img.grayscale(src), radius: 1);
    case '细笔画增强':
      return _thinStrokeEnhance(src);
    case '开运算去噪':
      return _morphologicalOpen(img.grayscale(src), radius: 1);
    case '多尺度形态学':
      return _multiScaleMorphology(src);

    // ═══ v4.5.0 增强 ═══
    case '自适应伽马校正':
      return _adaptiveGammaCorrection(src);
    case '多尺度边缘增强':
      return _multiScaleEdgeEnhance(src);
    case '笔画感知去噪':
      return _strokeAwareDenoise(src);
    case '伽马+CLAHE':
      return _clahe(_adaptiveGammaCorrection(src));
    case '边缘增强+锐化':
      return _unsharpMaskSharpen(_multiScaleEdgeEnhance(src), amount: 1.2);

    // ═══ v4.7.0 去模糊 ═══
    case '迭代去模糊':
      return _iterativeDeblur(src, iterations: 4);
    case '去模糊+锐化':
      return _unsharpMaskSharpen(_iterativeDeblur(src, iterations: 3), amount: 1.2);
    case '去模糊+CLAHE':
      return _clahe(_iterativeDeblur(src, iterations: 3));

    // ═══ v4.8.0 Sauvola ═══
    case 'Sauvola二值化':
      return _sauvolaBinarize(src, blockSize: 25, k: 0.2);
    case '去噪+Sauvola':
      return _sauvolaBinarize(_strokeAwareDenoise(src), blockSize: 25, k: 0.2);
    case '伽马+Sauvola':
      return _sauvolaBinarize(_adaptiveGammaCorrection(src), blockSize: 25, k: 0.2);

    // ═══ 未知策略：返回灰度 ═══
    default:
      return img.grayscale(src);
  }
}

// ═══════════════════════════════════════════════
// 以下为纯图像处理函数（可在 Isolate 中安全执行）
// ═══════════════════════════════════════════════

/// 中值滤波去噪（3x3 窗口）
img.Image _medianFilter(img.Image src) {
  final result = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final values = <int>[];
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final nx = (x + dx).clamp(0, src.width - 1);
          final ny = (y + dy).clamp(0, src.height - 1);
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
  final result = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      num r = 0, g = 0, b = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final nx = (x + dx).clamp(0, src.width - 1);
          final ny = (y + dy).clamp(0, src.height - 1);
          final pixel = src.getPixel(nx, ny);
          final weight = (dx == 0 && dy == 0) ? 5 : ((dx == 0 || dy == 0) ? -1 : 0);
          r += pixel.r * weight;
          g += pixel.g * weight;
          b += pixel.b * weight;
        }
      }
      result.setPixelRgba(x, y, r.clamp(0, 255).toInt(), g.clamp(0, 255).toInt(), b.clamp(0, 255).toInt(), 255);
    }
  }
  return result;
}

/// 自适应二值化（局部均值法）
img.Image _adaptiveBinarize(img.Image src, {int blockSize = 31, int c = 10}) {
  if (blockSize.isEven) blockSize++;
  final half = blockSize ~/ 2;
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  final result = img.Image(width: w, height: h);

  // 积分图加速
  final integral = List.generate(h + 1, (_) => List.filled(w + 1, 0));
  for (int y = 0; y < h; y++) {
    int rowSum = 0;
    for (int x = 0; x < w; x++) {
      rowSum += gray.getPixel(x, y).r.toInt();
      integral[y + 1][x + 1] = integral[y][x + 1] + rowSum;
    }
  }

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final x0 = (x - half).clamp(0, w - 1);
      final y0 = (y - half).clamp(0, h - 1);
      final x1 = (x + half).clamp(0, w - 1);
      final y1 = (y + half).clamp(0, h - 1);
      final count = (x1 - x0 + 1) * (y1 - y0 + 1);
      final sum = integral[y1 + 1][x1 + 1] - integral[y0][x1 + 1] - integral[y1 + 1][x0] + integral[y0][x0];
      final threshold = (sum / count) - c;
      final v = gray.getPixel(x, y).r.toInt() > threshold ? 255 : 0;
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// 二值化（Otsu 自动阈值）
img.Image _binarize(img.Image src) {
  final gray = img.grayscale(src);
  final threshold = _otsuThreshold(gray);
  final result = img.Image(width: gray.width, height: gray.height);
  for (int y = 0; y < gray.height; y++) {
    for (int x = 0; x < gray.width; x++) {
      final v = gray.getPixel(x, y).r.toInt() > threshold ? 255 : 0;
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// Otsu 阈值计算
int _otsuThreshold(img.Image gray) {
  final hist = List.filled(256, 0);
  for (int y = 0; y < gray.height; y++) {
    for (int x = 0; x < gray.width; x++) {
      hist[gray.getPixel(x, y).r.toInt()]++;
    }
  }
  final total = gray.width * gray.height;
  int sum = 0;
  for (int i = 0; i < 256; i++) sum += i * hist[i];
  int sumB = 0, wB = 0;
  double maxVariance = 0;
  int bestThreshold = 0;
  for (int t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final variance = wB * wF * (mB - mF) * (mB - mF);
    if (variance > maxVariance) {
      maxVariance = variance;
      bestThreshold = t;
    }
  }
  return bestThreshold;
}

/// USM 锐化（Unsharp Mask）
img.Image _unsharpMaskSharpen(img.Image src, {double amount = 1.5}) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;

  // 高斯模糊
  final blurred = _gaussianBlur(gray, sigma: 1.5);

  // 差值锐化
  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final orig = gray.getPixel(x, y).r.toDouble();
      final blur = blurred[y * w + x];
      final v = (orig + amount * (orig - blur)).round().clamp(0, 255);
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// 高斯模糊（返回浮点数组）
List<double> _gaussianBlur(img.Image gray, {double sigma = 1.5}) {
  final w = gray.width, h = gray.height;
  final radius = (sigma * 2).ceil();
  final kernelSize = radius * 2 + 1;
  final kernel = List.filled(kernelSize, 0.0);
  double kernelSum = 0;
  for (int i = 0; i < kernelSize; i++) {
    final x = i - radius;
    kernel[i] = _exp(-x * x / (2 * sigma * sigma));
    kernelSum += kernel[i];
  }
  for (int i = 0; i < kernelSize; i++) kernel[i] /= kernelSum;

  // 水平
  final temp = List.filled(w * h, 0.0);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double sum = 0;
      for (int k = 0; k < kernelSize; k++) {
        final nx = (x + k - radius).clamp(0, w - 1);
        sum += gray.getPixel(nx, y).r.toDouble() * kernel[k];
      }
      temp[y * w + x] = sum;
    }
  }

  // 垂直
  final result = List.filled(w * h, 0.0);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double sum = 0;
      for (int k = 0; k < kernelSize; k++) {
        final ny = (y + k - radius).clamp(0, h - 1);
        sum += temp[ny * w + x] * kernel[k];
      }
      result[y * w + x] = sum;
    }
  }
  return result;
}

/// CLAHE（自适应直方图均衡化，8x8 瓦片）
img.Image _clahe(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  const tileSize = 8;
  const clipLimit = 3.0;

  final tilesX = (w / tileSize).ceil().clamp(1, w);
  final tilesY = (h / tileSize).ceil().clamp(1, h);

  final tileMaps = List.generate(tilesY, (_) =>
      List.generate(tilesX, (_) => List.filled(256, 0)));

  for (int ty = 0; ty < tilesY; ty++) {
    for (int tx = 0; tx < tilesX; tx++) {
      final x0 = tx * tileSize;
      final y0 = ty * tileSize;
      final x1 = ((tx + 1) * tileSize).clamp(0, w);
      final y1 = ((ty + 1) * tileSize).clamp(0, h);
      final pixelCount = (x1 - x0) * (y1 - y0);

      final hist = List.filled(256, 0);
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          hist[gray.getPixel(x, y).r.toInt()]++;
        }
      }

      int excess = 0;
      for (int i = 0; i < 256; i++) {
        if (hist[i] > clipLimit) {
          excess += hist[i] - clipLimit.toInt();
          hist[i] = clipLimit.toInt();
        }
      }
      final redistribPerBin = excess ~/ 256;
      final residual = excess % 256;
      for (int i = 0; i < 256; i++) {
        hist[i] += redistribPerBin;
        if (i < residual) hist[i]++;
      }

      int cdf = 0, cdfMin = 0;
      bool foundMin = false;
      for (int i = 0; i < 256; i++) {
        cdf += hist[i];
        if (!foundMin && cdf > 0) { cdfMin = cdf; foundMin = true; }
      }
      cdf = 0;
      for (int i = 0; i < 256; i++) {
        cdf += hist[i];
        tileMaps[ty][tx][i] = cdfMin == pixelCount
            ? i
            : ((cdf - cdfMin) * 255 / (pixelCount - cdfMin)).round().clamp(0, 255);
      }
    }
  }

  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final val = gray.getPixel(x, y).r.toInt();
      final txf = (x / tileSize - 0.5).clamp(0.0, (tilesX - 1).toDouble());
      final tyf = (y / tileSize - 0.5).clamp(0.0, (tilesY - 1).toDouble());
      final tx0 = txf.floor(), ty0 = tyf.floor();
      final tx1 = (tx0 + 1).clamp(0, tilesX - 1);
      final ty1 = (ty0 + 1).clamp(0, tilesY - 1);
      final fx = txf - tx0, fy = tyf - ty0;
      final v = (tileMaps[ty0][tx0][val] * (1 - fx) * (1 - fy) +
          tileMaps[ty0][tx1][val] * fx * (1 - fy) +
          tileMaps[ty1][tx0][val] * (1 - fx) * fy +
          tileMaps[ty1][tx1][val] * fx * fy).round().clamp(0, 255);
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// CLAHE 自适应（根据对比度自动选参数）
img.Image _claheAdaptive(img.Image src) {
  final gray = img.grayscale(src);
  // 计算标准差
  double mean = 0;
  final w = gray.width, h = gray.height;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      mean += gray.getPixel(x, y).r.toDouble();
    }
  }
  mean /= w * h;
  double variance = 0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final d = gray.getPixel(x, y).r.toDouble() - mean;
      variance += d * d;
    }
  }
  final stdDev = _sqrt(variance / (w * h));

  if (stdDev > 65) return gray;
  if (stdDev < 30) return _claheWithParams(gray, tileGridSize: 12, clipLimit: 3.0);
  if (stdDev < 50) return _claheWithParams(gray, tileGridSize: 8, clipLimit: 2.5);
  return _claheWithParams(gray, tileGridSize: 8, clipLimit: 2.0);
}

img.Image _claheWithParams(img.Image gray, {int tileGridSize = 8, double clipLimit = 3.0}) {
  final w = gray.width, h = gray.height;
  final tileSize = tileGridSize;
  final tilesX = (w / tileSize).ceil().clamp(1, w);
  final tilesY = (h / tileSize).ceil().clamp(1, h);

  final tileMaps = List.generate(tilesY, (_) =>
      List.generate(tilesX, (_) => List.filled(256, 0)));

  for (int ty = 0; ty < tilesY; ty++) {
    for (int tx = 0; tx < tilesX; tx++) {
      final x0 = tx * tileSize, y0 = ty * tileSize;
      final x1 = ((tx + 1) * tileSize).clamp(0, w);
      final y1 = ((ty + 1) * tileSize).clamp(0, h);
      final pixelCount = (x1 - x0) * (y1 - y0);
      final hist = List.filled(256, 0);
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          hist[gray.getPixel(x, y).r.toInt()]++;
        }
      }
      int excess = 0;
      for (int i = 0; i < 256; i++) {
        if (hist[i] > clipLimit) { excess += hist[i] - clipLimit.toInt(); hist[i] = clipLimit.toInt(); }
      }
      final rpb = excess ~/ 256, res = excess % 256;
      for (int i = 0; i < 256; i++) { hist[i] += rpb; if (i < res) hist[i]++; }
      int cdf = 0, cdfMin = 0; bool fm = false;
      for (int i = 0; i < 256; i++) { cdf += hist[i]; if (!fm && cdf > 0) { cdfMin = cdf; fm = true; } }
      cdf = 0;
      for (int i = 0; i < 256; i++) {
        cdf += hist[i];
        tileMaps[ty][tx][i] = cdfMin == pixelCount ? i : ((cdf - cdfMin) * 255 / (pixelCount - cdfMin)).round().clamp(0, 255);
      }
    }
  }

  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final val = gray.getPixel(x, y).r.toInt();
      final txf = (x / tileSize - 0.5).clamp(0.0, (tilesX - 1).toDouble());
      final tyf = (y / tileSize - 0.5).clamp(0.0, (tilesY - 1).toDouble());
      final tx0 = txf.floor(), ty0 = tyf.floor();
      final tx1 = (tx0 + 1).clamp(0, tilesX - 1), ty1 = (ty0 + 1).clamp(0, tilesY - 1);
      final fx = txf - tx0, fy = tyf - ty0;
      final v = (tileMaps[ty0][tx0][val] * (1 - fx) * (1 - fy) +
          tileMaps[ty0][tx1][val] * fx * (1 - fy) +
          tileMaps[ty1][tx0][val] * (1 - fx) * fy +
          tileMaps[ty1][tx1][val] * fx * fy).round().clamp(0, 255);
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// 背景归一化（Retinex 思路）
img.Image _normalizeBackground(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  final bg = List.generate(h, (_) => List.filled(w, 0));
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final values = <int>[];
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          values.add(gray.getPixel((x + dx).clamp(0, w - 1), (y + dy).clamp(0, h - 1)).r.toInt());
        }
      }
      values.sort();
      bg[y][x] = values[4];
    }
  }
  double minVal = 255, maxVal = 0;
  final raw = List.generate(h, (_) => List.filled(w, 0.0));
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final ratio = gray.getPixel(x, y).r.toDouble() / bg[y][x].toDouble().clamp(1.0, 255.0) * 128.0;
      raw[y][x] = ratio;
      if (ratio < minVal) minVal = ratio;
      if (ratio > maxVal) maxVal = ratio;
    }
  }
  final range = (maxVal - minVal).clamp(1.0, 255.0);
  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final v = ((raw[y][x] - minVal) / range * 255).round().clamp(0, 255);
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// 方向边缘增强（Sobel）
img.Image _directionalEdgeEnhance(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int sx = 0, sy = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final nx = (x + dx).clamp(0, w - 1);
          final ny = (y + dy).clamp(0, h - 1);
          final v = gray.getPixel(nx, ny).r.toInt();
          sx += v * ((dx == -1 ? -1 : dx == 1 ? 1 : 0) * (dy == 0 ? 2 : 1));
          sy += v * ((dy == -1 ? -1 : dy == 1 ? 1 : 0) * (dx == 0 ? 2 : 1));
        }
      }
      final edge = _sqrt((sx * sx + sy * sy).toDouble()).clamp(0.0, 255.0);
      final orig = gray.getPixel(x, y).r.toDouble();
      final v = (orig + 0.5 * edge).round().clamp(0, 255);
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// 形态学膨胀
img.Image _morphologicalDilate(img.Image binary, {int radius = 1}) {
  final gray = img.grayscale(binary);
  final w = gray.width, h = gray.height;
  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int minVal = 255;
      for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
          final v = gray.getPixel((x + dx).clamp(0, w - 1), (y + dy).clamp(0, h - 1)).r.toInt();
          if (v < minVal) minVal = v;
        }
      }
      result.setPixelRgba(x, y, minVal, minVal, minVal, 255);
    }
  }
  return result;
}

/// 形态学腐蚀
img.Image _morphologicalErode(img.Image binary, {int radius = 1}) {
  final gray = img.grayscale(binary);
  final w = gray.width, h = gray.height;
  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int maxVal = 0;
      for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
          final v = gray.getPixel((x + dx).clamp(0, w - 1), (y + dy).clamp(0, h - 1)).r.toInt();
          if (v > maxVal) maxVal = v;
        }
      }
      result.setPixelRgba(x, y, maxVal, maxVal, maxVal, 255);
    }
  }
  return result;
}

/// 形态学闭运算（膨胀→腐蚀）
img.Image _morphologicalClose(img.Image binary, {int radius = 1}) {
  return _morphologicalErode(_morphologicalDilate(binary, radius: radius), radius: radius);
}

/// 形态学开运算（腐蚀→膨胀）
img.Image _morphologicalOpen(img.Image binary, {int radius = 1}) {
  return _morphologicalDilate(_morphologicalErode(binary, radius: radius), radius: radius);
}

/// 手写体笔画增强
img.Image _handwritingEnhance(img.Image src) {
  final gray = img.grayscale(src);
  final denoised = _medianFilter(gray);
  final sharpened = _sharpen(denoised);
  return _morphologicalClose(sharpened, radius: 1);
}

/// 倾斜校正
img.Image _skewCorrection(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  final binary = _adaptiveBinarize(gray, blockSize: 31, c: 10);

  // 检测最佳角度
  double bestAngle = 0;
  double maxVariance = 0;
  for (double angle = -15; angle <= 15; angle += 0.5) {
    final rad = angle * math.pi / 180;
    final projections = List.filled(h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final srcX = (x + y * _tan(rad)).round();
        if (srcX >= 0 && srcX < w && binary.getPixel(srcX, y).r.toInt() < 128) {
          projections[y]++;
        }
      }
    }
    final mean = projections.reduce((a, b) => a + b) / h;
    double variance = 0;
    for (final p in projections) variance += (p - mean) * (p - mean);
    variance /= h;
    if (variance > maxVariance) { maxVariance = variance; bestAngle = angle; }
  }

  if (bestAngle.abs() < 0.5) return src;

  // 旋转
  final rad = -bestAngle * math.pi / 180;
  final cosA = _cos(rad), sinA = _sin(rad);
  final result = img.Image(width: w, height: h, numChannels: src.numChannels);
  final cx = w / 2, cy = h / 2;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final srcX = ((x - cx) * cosA + (y - cy) * sinA + cx).round();
      final srcY = (-(x - cx) * sinA + (y - cy) * cosA + cy).round();
      if (srcX >= 0 && srcX < w && srcY >= 0 && srcY < h) {
        result.setPixel(x, y, src.getPixel(srcX, srcY));
      } else {
        result.setPixelRgba(x, y, 255, 255, 255, 255);
      }
    }
  }
  return result;
}

/// 笔画归一化
img.Image _strokeNormalization(img.Image src) {
  final gray = img.grayscale(src);
  final binary = _adaptiveBinarize(gray, blockSize: 31, c: 10);
  final w = gray.width, h = gray.height;

  int fgCount = 0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (binary.getPixel(x, y).r.toInt() < 128) fgCount++;
    }
  }
  final fgRatio = fgCount / (w * h);

  if (fgRatio < 0.08) return _morphologicalDilate(gray, radius: 1);
  if (fgRatio > 0.30) return _morphologicalErode(gray, radius: 1);
  return gray;
}

/// 笔画粗细自适应
img.Image _strokeThicknessAdaptive(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  if (w < 20 || h < 20) return gray;
  final binary = _adaptiveBinarize(gray, blockSize: 31, c: 10);
  int fgCount = 0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (binary.getPixel(x, y).r.toInt() < 128) fgCount++;
    }
  }
  final fgRatio = fgCount / (w * h);
  if (fgRatio < 0.08) return _morphologicalDilate(gray, radius: 1);
  if (fgRatio > 0.30) return _morphologicalErode(gray, radius: 1);
  return gray;
}

/// 细笔画增强
img.Image _thinStrokeEnhance(img.Image src) {
  final gray = img.grayscale(src);
  final binary = _adaptiveBinarize(gray, blockSize: 25, c: 8);
  final w = gray.width, h = gray.height;
  int fgCount = 0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (binary.getPixel(x, y).r.toInt() < 128) fgCount++;
    }
  }
  final fgRatio = fgCount / (w * h);
  if (fgRatio < 0.10) return _morphologicalDilate(gray, radius: 1);
  return gray;
}

/// 多尺度形态学
img.Image _multiScaleMorphology(img.Image src) {
  final gray = img.grayscale(src);
  final binary = _adaptiveBinarize(gray, blockSize: 25, c: 8);
  final dilated = _morphologicalDilate(binary, radius: 1);
  return _morphologicalClose(dilated, radius: 1);
}

/// 自适应伽马校正
img.Image _adaptiveGammaCorrection(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  double mean = 0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      mean += gray.getPixel(x, y).r.toDouble();
    }
  }
  mean /= w * h;
  final normalizedMean = mean / 255.0;
  final gamma = normalizedMean < 0.01 ? 1.0 : (_log2(0.5) / _log2(normalizedMean)).clamp(0.3, 3.0);

  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final v = (255.0 * _pow(gray.getPixel(x, y).r.toDouble() / 255.0, gamma)).round().clamp(0, 255);
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// 多尺度边缘增强
img.Image _multiScaleEdgeEnhance(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  final result = img.Image(width: w, height: h);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double edgeSum = 0;
      // 3x3 Sobel
      int sx3 = 0, sy3 = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final nx = (x + dx).clamp(0, w - 1);
          final ny = (y + dy).clamp(0, h - 1);
          final v = gray.getPixel(nx, ny).r.toInt();
          sx3 += v * ((dx == -1 ? -1 : dx == 1 ? 1 : 0) * (dy == 0 ? 2 : 1));
          sy3 += v * ((dy == -1 ? -1 : dy == 1 ? 1 : 0) * (dx == 0 ? 2 : 1));
        }
      }
      edgeSum += _sqrt((sx3 * sx3 + sy3 * sy3).toDouble()) * 0.6;

      // 5x5 Sobel
      if (x >= 2 && x < w - 2 && y >= 2 && y < h - 2) {
        int sx5 = 0, sy5 = 0;
        for (int dy = -2; dy <= 2; dy++) {
          for (int dx = -2; dx <= 2; dx++) {
            final v = gray.getPixel(x + dx, y + dy).r.toInt();
            final wx = dx == 0 ? 0 : (dx.abs() == 1 ? -2 : -1) * (dx > 0 ? 1 : -1);
            final wy = dy == 0 ? 0 : (dy.abs() == 1 ? -2 : -1) * (dy > 0 ? 1 : -1);
            sx5 += v * wx;
            sy5 += v * wy;
          }
        }
        edgeSum += _sqrt((sx5 * sx5 + sy5 * sy5).toDouble()) * 0.4;
      }

      final orig = gray.getPixel(x, y).r.toDouble();
      final v = (orig + 0.4 * edgeSum).round().clamp(0, 255);
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// 笔画感知去噪（各向异性扩散）
img.Image _strokeAwareDenoise(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  var current = List.generate(h, (y) => List.generate(w, (x) => gray.getPixel(x, y).r.toDouble()));

  for (int iter = 0; iter < 3; iter++) {
    final next = List.generate(h, (_) => List.filled(w, 0.0));
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final center = current[y][x];
        double sum = 0, weightSum = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final neighbor = current[y + dy][x + dx];
            final diff = (center - neighbor).abs();
            final weight = _exp(-diff * diff / (2 * 25 * 25));
            sum += neighbor * weight;
            weightSum += weight;
          }
        }
        next[y][x] = sum / weightSum;
      }
    }
    current = next;
  }

  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final v = current[y][x].round().clamp(0, 255);
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// 迭代反投影去模糊
img.Image _iterativeDeblur(img.Image src, {int iterations = 4}) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;

  var current = List.generate(h, (y) => List.generate(w, (x) => gray.getPixel(x, y).r.toDouble()));

  // 边缘强度图
  final edgeMap = List.filled(w * h, 0.0);
  double maxEdge = 0;
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      final gx = _sobelX(gray, x, y).toDouble();
      final gy = _sobelY(gray, x, y).toDouble();
      final mag = _sqrt(gx * gx + gy * gy);
      edgeMap[y * w + x] = mag;
      if (mag > maxEdge) maxEdge = mag;
    }
  }
  if (maxEdge > 0) {
    for (int i = 0; i < w * h; i++) edgeMap[i] /= maxEdge;
  }

  for (int iter = 0; iter < iterations; iter++) {
    // 模糊当前估计
    final flat = List.generate(h, (y) => List.generate(w, (x) => current[y][x])).expand((e) => e).toList();
    final blurred = _gaussianBlurFromFloat(flat, w, h, sigma: 1.0 + iter * 0.3);

    // 反投影
    final baseGain = 0.5 / (1 + iter * 0.15);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = y * w + x;
        final residual = gray.getPixel(x, y).r.toDouble() - blurred[i];
        final edgeWeight = 0.6 + 0.9 * edgeMap[i];
        current[y][x] = (current[y][x] + residual * baseGain * edgeWeight).clamp(0, 255);
      }
    }
  }

  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final v = current[y][x].round().clamp(0, 255);
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

List<double> _gaussianBlurFromFloat(List<double> data, int w, int h, {double sigma = 1.0}) {
  final radius = (sigma * 2).ceil();
  final kernelSize = radius * 2 + 1;
  final kernel = List.filled(kernelSize, 0.0);
  double kernelSum = 0;
  for (int i = 0; i < kernelSize; i++) {
    kernel[i] = _exp(-(i - radius) * (i - radius) / (2 * sigma * sigma));
    kernelSum += kernel[i];
  }
  for (int i = 0; i < kernelSize; i++) kernel[i] /= kernelSum;

  final temp = List.filled(w * h, 0.0);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double sum = 0;
      for (int k = 0; k < kernelSize; k++) {
        sum += data[y * w + (x + k - radius).clamp(0, w - 1)] * kernel[k];
      }
      temp[y * w + x] = sum;
    }
  }
  final result = List.filled(w * h, 0.0);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double sum = 0;
      for (int k = 0; k < kernelSize; k++) {
        sum += temp[(y + k - radius).clamp(0, h - 1) * w + x] * kernel[k];
      }
      result[y * w + x] = sum;
    }
  }
  return result;
}

/// Sauvola 自适应二值化
img.Image _sauvolaBinarize(img.Image src, {int blockSize = 25, double k = 0.2, double R = 128.0}) {
  if (blockSize.isEven) blockSize++;
  final half = blockSize ~/ 2;
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;

  // 积分图
  final integral = List.generate(h + 1, (_) => List.filled(w + 1, 0.0));
  final integralSq = List.generate(h + 1, (_) => List.filled(w + 1, 0.0));
  for (int y = 0; y < h; y++) {
    double rowSum = 0, rowSumSq = 0;
    for (int x = 0; x < w; x++) {
      final v = gray.getPixel(x, y).r.toDouble();
      rowSum += v;
      rowSumSq += v * v;
      integral[y + 1][x + 1] = integral[y][x + 1] + rowSum;
      integralSq[y + 1][x + 1] = integralSq[y][x + 1] + rowSumSq;
    }
  }

  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final x0 = (x - half).clamp(0, w - 1);
      final y0 = (y - half).clamp(0, h - 1);
      final x1 = (x + half).clamp(0, w - 1);
      final y1 = (y + half).clamp(0, h - 1);
      final count = (x1 - x0 + 1) * (y1 - y0 + 1).toDouble();
      final sum = integral[y1 + 1][x1 + 1] - integral[y0][x1 + 1] - integral[y1 + 1][x0] + integral[y0][x0];
      final sumSq = integralSq[y1 + 1][x1 + 1] - integralSq[y0][x1 + 1] - integralSq[y1 + 1][x0] + integralSq[y0][x0];
      final mean = sum / count;
      final variance = (sumSq / count) - mean * mean;
      final stdDev = _sqrt(variance > 0 ? variance : 0);
      final threshold = mean * (1 + k * (stdDev / R - 1));
      final v = gray.getPixel(x, y).r.toDouble() > threshold ? 255 : 0;
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// 形态学骨架化
img.Image _morphologicalSkeletonize(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  var foreground = List.generate(h, (y) => List.generate(w, (x) => gray.getPixel(x, y).r.toInt() < 128));
  final skeleton = List.generate(h, (_) => List.filled(w, false));
  bool changed = true;
  int iterations = 0;

  while (changed && iterations < 50) {
    changed = false;
    iterations++;
    final eroded = List.generate(h, (_) => List.filled(w, false));
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        if (!foreground[y][x]) continue;
        bool allFg = true;
        for (int dy = -1; dy <= 1 && allFg; dy++) {
          for (int dx = -1; dx <= 1 && allFg; dx++) {
            if (!foreground[y + dy][x + dx]) allFg = false;
          }
        }
        eroded[y][x] = allFg;
      }
    }
    final opened = List.generate(h, (_) => List.filled(w, false));
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        if (!eroded[y][x]) continue;
        bool hasFg = false;
        for (int dy = -1; dy <= 1 && !hasFg; dy++) {
          for (int dx = -1; dx <= 1 && !hasFg; dx++) {
            if (eroded[y + dy][x + dx]) hasFg = true;
          }
        }
        opened[y][x] = hasFg;
      }
    }
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (foreground[y][x] && !opened[y][x]) { skeleton[y][x] = true; changed = true; }
      }
    }
    foreground = opened;
  }

  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final v = skeleton[y][x] ? 0 : 255;
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// 高斯模糊去噪+锐化
img.Image _gaussianBlurSharpen(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  final blurred = _gaussianBlur(gray, sigma: 1.5);
  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final orig = gray.getPixel(x, y).r.toDouble();
      final blur = blurred[y * w + x];
      final v = (orig + 1.2 * (orig - blur)).round().clamp(0, 255);
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// 局部阈值二值化
img.Image _localThresholdBinarize(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  const blockSize = 15;
  const c = 5;
  final half = blockSize ~/ 2;
  final result = img.Image(width: w, height: h);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int sum = 0, count = 0;
      for (int dy = -half; dy <= half; dy++) {
        for (int dx = -half; dx <= half; dx++) {
          final nx = (x + dx).clamp(0, w - 1);
          final ny = (y + dy).clamp(0, h - 1);
          sum += gray.getPixel(nx, ny).r.toInt();
          count++;
        }
      }
      final threshold = (sum / count) - c;
      final v = gray.getPixel(x, y).r.toInt() > threshold ? 255 : 0;
      result.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return result;
}

/// 自适应直方图均衡（四象限）
img.Image _adaptiveHistogramEqualizeQuadrants(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width, h = gray.height;
  final result = img.Image(width: w, height: h);
  final midX = w ~/ 2, midY = h ~/ 2;

  for (int qy = 0; qy < 2; qy++) {
    for (int qx = 0; qx < 2; qx++) {
      final x0 = qx == 0 ? 0 : midX;
      final y0 = qy == 0 ? 0 : midY;
      final x1 = qx == 0 ? midX : w;
      final y1 = qy == 0 ? midY : h;
      final hist = List.filled(256, 0);
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          hist[gray.getPixel(x, y).r.toInt()]++;
        }
      }
      final pixelCount = (x1 - x0) * (y1 - y0);
      int cdf = 0, cdfMin = 0;
      bool foundMin = false;
      for (int i = 0; i < 256; i++) {
        cdf += hist[i];
        if (!foundMin && cdf > 0) { cdfMin = cdf; foundMin = true; }
      }
      final map = List.filled(256, 0);
      cdf = 0;
      for (int i = 0; i < 256; i++) {
        cdf += hist[i];
        map[i] = cdfMin == pixelCount ? i : ((cdf - cdfMin) * 255 / (pixelCount - cdfMin)).round().clamp(0, 255);
      }
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          final v = map[gray.getPixel(x, y).r.toInt()];
          result.setPixelRgba(x, y, v, v, v, 255);
        }
      }
    }
  }
  return result;
}

// ═══ 数学辅助函数 ═══

int _sobelX(img.Image gray, int x, int y) {
  final w = gray.width, h = gray.height;
  int s = 0;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      final v = gray.getPixel((x + dx).clamp(0, w - 1), (y + dy).clamp(0, h - 1)).r.toInt();
      s += v * ((dx == -1 ? -1 : dx == 1 ? 1 : 0) * (dy == 0 ? 2 : 1));
    }
  }
  return s;
}

int _sobelY(img.Image gray, int x, int y) {
  final w = gray.width, h = gray.height;
  int s = 0;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      final v = gray.getPixel((x + dx).clamp(0, w - 1), (y + dy).clamp(0, h - 1)).r.toInt();
      s += v * ((dy == -1 ? -1 : dy == 1 ? 1 : 0) * (dx == 0 ? 2 : 1));
    }
  }
  return s;
}

double _sqrt(double x) {
  if (x <= 0) return 0;
  double guess = x / 2;
  for (int i = 0; i < 10; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}

double _log2(double x) => _ln(x) / _ln(2);

double _ln(double x) {
  if (x <= 0) return -999;
  final t = (x - 1) / (x + 1);
  double sum = 0, term = t;
  for (int i = 0; i < 20; i++) { sum += term / (2 * i + 1); term *= t * t; }
  return 2 * sum;
}

double _pow(double base, double exponent) {
  if (base <= 0) return 0;
  if (exponent == 0) return 1;
  if (exponent == 1) return base;
  return _exp(exponent * _ln(base));
}

double _exp(double x) {
  if (x < -10) return 0;
  if (x > 10) return 22026.0;
  double sum = 1, term = 1;
  for (int i = 1; i < 30; i++) { term *= x / i; sum += term; }
  return sum;
}

double _tan(double x) {
  final c = _cos(x);
  if (c.abs() < 1e-10) return x > 0 ? 1e10 : -1e10;
  return _sin(x) / c;
}

double _sin(double x) {
  // Taylor 展开，归一化到 [-π, π]
  x = x % (2 * math.pi);
  if (x > math.pi) x -= 2 * math.pi;
  if (x < -math.pi) x += 2 * math.pi;
  double sum = x, term = x;
  for (int i = 1; i < 15; i++) { term *= -x * x / ((2 * i) * (2 * i + 1)); sum += term; }
  return sum;
}

double _cos(double x) => _sin(x + math.pi / 2);
