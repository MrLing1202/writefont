import 'dart:typed_data';
import 'dart:math';

/// 手写风格类型
enum HandwritingStyle {
  regular,    // 楷书 — 笔画清晰、结构工整
  cursive,    // 行书/草书 — 连笔多、笔画简省
  light,      // 轻笔 — 笔画细、力度轻
  heavy,      // 重笔 — 笔画粗、力度重
  mixed,      // 混合风格
}

/// 图像特征分析结果
class ImageFeatures {
  final double contrast; // 对比度 0-1（越高越清晰）
  final double noise; // 噪声水平 0-1（越高越嘈杂）
  final double blur; // 模糊程度 0-1（越高越模糊）
  final double lineThickness; // 线条粗细 0-1（越高越粗）
  final double connection; // 连笔程度 0-1（越高连笔越多）

  // v4.8.0: 手写风格自适应 — 新增风格特征
  final double slantAngle;       // 倾斜角度 0-1（0=正直，1=严重右倾）
  final double strokeVariability; // 笔画粗细变异度 0-1（0=非常均匀，1=极度不均）
  final double inkDensity;       // 墨迹密度 0-1（笔画像素占比的归一化值）
  final double edgeSharpness;    // 边缘锐度 0-1（0=模糊，1=清晰）
  final HandwritingStyle style;  // 检测到的书写风格

  const ImageFeatures({
    required this.contrast,
    required this.noise,
    required this.blur,
    required this.lineThickness,
    required this.connection,
    this.slantAngle = 0.0,
    this.strokeVariability = 0.0,
    this.inkDensity = 0.0,
    this.edgeSharpness = 0.5,
    this.style = HandwritingStyle.regular,
  });

  /// 质量等级：high / medium / low
  String get qualityLevel {
    double score = 0;
    score += contrast.clamp(0, 1); // 高对比度 = 好
    score += (1 - noise).clamp(0, 1); // 低噪声 = 好
    score += (1 - blur).clamp(0, 1); // 低模糊 = 好
    score /= 3;
    if (score > 0.65) return 'high';
    if (score > 0.4) return 'medium';
    return 'low';
  }

  /// 质量 emoji
  String get qualityEmoji {
    switch (qualityLevel) {
      case 'high':
        return '🟢';
      case 'medium':
        return '🟡';
      default:
        return '🔴';
    }
  }

  /// 风格名称
  String get styleName {
    switch (style) {
      case HandwritingStyle.regular:
        return '楷书';
      case HandwritingStyle.cursive:
        return '行书/草书';
      case HandwritingStyle.light:
        return '轻笔';
      case HandwritingStyle.heavy:
        return '重笔';
      case HandwritingStyle.mixed:
        return '混合';
    }
  }
}

/// 图像分析器 - 分析手写字符图像特征
class ImageAnalyzer {
  static const int _gridSize = 64; // 分析用缩放尺寸

  /// 分析图像特征（v4.8.0: 增加手写风格分析）
  Future<ImageFeatures> analyzeImage(Uint8List imageBytes) async {
    // 解析为灰度像素（简化处理：假设 RGBA 或灰度）
    final pixels = _extractGrayscalePixels(imageBytes);

    final contrast = _calculateContrast(pixels);
    final noise = _calculateNoise(pixels);
    final blur = _calculateBlur(pixels);
    final lineThickness = _calculateLineThickness(pixels);
    final connection = _calculateConnection(pixels);

    // v4.8.0: 手写风格自适应 — 新增风格特征分析
    final slantAngle = _calculateSlantAngle(pixels);
    final strokeVariability = _calculateStrokeVariability(pixels);
    final inkDensity = _calculateInkDensity(pixels);
    final edgeSharpness = _calculateEdgeSharpness(pixels);
    final style = _classifyHandwritingStyle(
      lineThickness: lineThickness,
      connection: connection,
      strokeVariability: strokeVariability,
      inkDensity: inkDensity,
      edgeSharpness: edgeSharpness,
    );

    return ImageFeatures(
      contrast: contrast,
      noise: noise,
      blur: blur,
      lineThickness: lineThickness,
      connection: connection,
      slantAngle: slantAngle,
      strokeVariability: strokeVariability,
      inkDensity: inkDensity,
      edgeSharpness: edgeSharpness,
      style: style,
    );
  }

  /// 从图像字节提取灰度值（0-255）
  List<int> _extractGrayscalePixels(Uint8List bytes) {
    // 简化：直接使用字节值作为灰度
    // 实际场景中需要解码 PNG/JPEG
    if (bytes.length >= _gridSize * _gridSize) {
      // 按步长采样到 gridSize x gridSize
      final step = bytes.length ~/ (_gridSize * _gridSize);
      return List.generate(
        _gridSize * _gridSize,
        (i) => bytes[i * step] & 0xFF,
      );
    }
    // 不足则填充
    final result = List<int>.filled(_gridSize * _gridSize, 255);
    for (int i = 0; i < bytes.length && i < result.length; i++) {
      result[i] = bytes[i] & 0xFF;
    }
    return result;
  }

  /// 对比度：灰度标准差 / 128
  double _calculateContrast(List<int> pixels) {
    final sd = _stdDev(pixels);
    return (sd / 128).clamp(0.0, 1.0);
  }

  /// 噪声：Laplacian 高频分量方差
  double _calculateNoise(List<int> pixels) {
    final laplacian = <int>[];
    final w = _gridSize;
    for (int y = 1; y < _gridSize - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final idx = y * w + x;
        // 简化 Laplacian: 4*center - 4邻居
        final val = 4 * pixels[idx] -
            pixels[idx - 1] -
            pixels[idx + 1] -
            pixels[idx - w] -
            pixels[idx + w];
        laplacian.add(val.abs());
      }
    }
    if (laplacian.isEmpty) return 0.0;
    final variance = _variance(laplacian);
    // 归一化到 0-1（经验值：方差>2000视为高噪声）
    return (variance / 2000).clamp(0.0, 1.0);
  }

  /// 模糊：边缘强度均值（低=模糊）
  double _calculateBlur(List<int> pixels) {
    final edges = <int>[];
    final w = _gridSize;
    for (int y = 1; y < _gridSize - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final idx = y * w + x;
        // Sobel 近似
        final gx = (pixels[idx + 1] - pixels[idx - 1]).abs();
        final gy = (pixels[idx + w] - pixels[idx - w]).abs();
        edges.add(max(gx, gy));
      }
    }
    if (edges.isEmpty) return 1.0;
    final mean = edges.reduce((a, b) => a + b) / edges.length;
    // 低边缘强度 = 模糊；归一化：mean<20 视为很模糊
    return (1.0 - mean / 80).clamp(0.0, 1.0);
  }

  /// 线条粗细：黑色像素占比（占比高=粗）
  double _calculateLineThickness(List<int> pixels) {
    final threshold = 128;
    final blackCount = pixels.where((p) => p < threshold).length;
    final ratio = blackCount / pixels.length;
    // 手写字符通常黑像素占比 5%-30%
    // 5%以下→极细，10%→正常，20%+→粗
    return (ratio / 0.25).clamp(0.0, 1.0);
  }

  /// 连笔程度：连通区域密度（少=连笔多）
  double _calculateConnection(List<int> pixels) {
    final w = _gridSize;
    final threshold = 128;
    final visited = List<bool>.filled(pixels.length, false);
    int componentCount = 0;
    for (int i = 0; i < pixels.length; i++) {
      if (visited[i] || pixels[i] >= threshold) continue;
      componentCount++;
      // BFS
      final queue = [i];
      visited[i] = true;
      while (queue.isNotEmpty) {
        final cur = queue.removeLast();
        final cx = cur % w;
        final cy = cur ~/ w;
        for (final (dx, dy) in [(0, 1), (0, -1), (1, 0), (-1, 0)]) {
          final nx = cx + dx;
          final ny = cy + dy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= _gridSize) continue;
          final ni = ny * w + nx;
          if (!visited[ni] && pixels[ni] < threshold) {
            visited[ni] = true;
            queue.add(ni);
          }
        }
      }
    }
    // 连通区域少 → 连笔多
    // 1-2个区域 → 极可能连笔；10+个区域 → 分散
    return (1.0 - componentCount / 10).clamp(0.0, 1.0);
  }

  // ═══════════════════════════════════════════════════
  // v4.8.0: 手写风格自适应 — 新增分析方法
  // ═══════════════════════════════════════════════════

  /// 倾斜角度：分析笔画主方向的偏斜程度
  /// 使用 Sobel 梯度方向统计，检测整体书写倾斜
  double _calculateSlantAngle(List<int> pixels) {
    final w = _gridSize;
    int gxSum = 0;
    int gySum = 0;
    int count = 0;
    for (int y = 1; y < _gridSize - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final idx = y * w + x;
        if (pixels[idx] >= 128) continue; // 只关注笔画像素
        final gx = pixels[idx + 1] - pixels[idx - 1];
        final gy = pixels[idx + w] - pixels[idx - w];
        gxSum += gx.abs();
        gySum += gy.abs();
        count++;
      }
    }
    if (count == 0) return 0.0;
    // gx/gy 比值反映倾斜：gx 大 → 垂直笔画多（正直），gy 大 → 水平笔画多（倾斜）
    final ratio = gxSum / max(gySum, 1);
    // ratio > 1.5 → 正直，ratio < 0.8 → 严重倾斜
    return (1.0 - (ratio - 0.5).clamp(0.0, 1.5) / 1.5).clamp(0.0, 1.0);
  }

  /// 笔画粗细变异度：分析笔画宽度的一致性
  /// 变异度高 → 书写不稳定，可能压力不均
  double _calculateStrokeVariability(List<int> pixels) {
    final w = _gridSize;
    final threshold = 128;
    // 计算每一行的笔画宽度
    final rowWidths = <int>[];
    for (int y = 0; y < _gridSize; y++) {
      int start = -1;
      int end = -1;
      for (int x = 0; x < w; x++) {
        if (pixels[y * w + x] < threshold) {
          if (start < 0) start = x;
          end = x;
        }
      }
      if (start >= 0) {
        rowWidths.add(end - start + 1);
      }
    }
    if (rowWidths.length < 3) return 0.0;
    final sd = _stdDev(rowWidths);
    final mean = rowWidths.reduce((a, b) => a + b) / rowWidths.length;
    if (mean < 1) return 0.0;
    // 变异系数 = sd / mean
    final cv = sd / mean;
    // CV > 0.8 → 高变异，CV < 0.2 → 非常均匀
    return (cv / 0.8).clamp(0.0, 1.0);
  }

  /// 墨迹密度：笔画像素占有效区域的比例
  double _calculateInkDensity(List<int> pixels) {
    final threshold = 128;
    final totalPixels = pixels.length;
    final inkPixels = pixels.where((p) => p < threshold).length;
    // 手写字符正常密度 5%-30%
    return (inkPixels / totalPixels / 0.3).clamp(0.0, 1.0);
  }

  /// 边缘锐度：笔画边缘的梯度强度
  double _calculateEdgeSharpness(List<int> pixels) {
    final w = _gridSize;
    final threshold = 128;
    double edgeSum = 0;
    int edgeCount = 0;
    for (int y = 1; y < _gridSize - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final idx = y * w + x;
        // 只在笔画边缘计算梯度（像素跨过阈值的位置）
        final isEdge = (pixels[idx] < threshold &&
            (pixels[idx - 1] >= threshold || pixels[idx + 1] >= threshold ||
                pixels[idx - w] >= threshold || pixels[idx + w] >= threshold));
        if (!isEdge) continue;
        final gx = (pixels[idx + 1] - pixels[idx - 1]).abs();
        final gy = (pixels[idx + w] - pixels[idx - w]).abs();
        edgeSum += max(gx, gy);
        edgeCount++;
      }
    }
    if (edgeCount == 0) return 0.5;
    final meanEdge = edgeSum / edgeCount;
    // 归一化：edge>150 → 非常锐利，edge<30 → 很模糊
    return (meanEdge / 150).clamp(0.0, 1.0);
  }

  /// 手写风格分类
  HandwritingStyle _classifyHandwritingStyle({
    required double lineThickness,
    required double connection,
    required double strokeVariability,
    required double inkDensity,
    required double edgeSharpness,
  }) {
    // 规则引擎：基于多维特征组合判断风格

    // 连笔多 + 笔画变异度高 → 行书/草书
    if (connection > 0.6 && strokeVariability > 0.4) {
      return HandwritingStyle.cursive;
    }

    // 连笔中等 + 笔画变异度中等 → 行书
    if (connection > 0.45 && strokeVariability > 0.3) {
      return HandwritingStyle.cursive;
    }

    // 笔画细 + 墨迹密度低 → 轻笔
    if (lineThickness < 0.3 && inkDensity < 0.35) {
      return HandwritingStyle.light;
    }

    // 笔画粗 + 墨迹密度高 → 重笔
    if (lineThickness > 0.6 && inkDensity > 0.55) {
      return HandwritingStyle.heavy;
    }

    // 笔画变异度高但连笔不多 → 混合
    if (strokeVariability > 0.5) {
      return HandwritingStyle.mixed;
    }

    // 默认 → 楷书
    return HandwritingStyle.regular;
  }

  /// 标准差
  double _stdDev(List<int> values) {
    if (values.isEmpty) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sumSq = values.fold<double>(
      0,
      (sum, v) => sum + (v - mean) * (v - mean),
    );
    return sqrt(sumSq / values.length);
  }

  /// 方差
  double _variance(List<int> values) {
    if (values.isEmpty) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    return values.fold<double>(
          0,
          (sum, v) => sum + (v - mean) * (v - mean),
        ) /
        values.length;
  }
}
