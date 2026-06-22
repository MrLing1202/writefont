import 'dart:typed_data';
import 'dart:math';

/// 图像特征分析结果
class ImageFeatures {
  final double contrast; // 对比度 0-1（越高越清晰）
  final double noise; // 噪声水平 0-1（越高越嘈杂）
  final double blur; // 模糊程度 0-1（越高越模糊）
  final double lineThickness; // 线条粗细 0-1（越高越粗）
  final double connection; // 连笔程度 0-1（越高连笔越多）

  const ImageFeatures({
    required this.contrast,
    required this.noise,
    required this.blur,
    required this.lineThickness,
    required this.connection,
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
}

/// 图像分析器 - 分析手写字符图像特征
class ImageAnalyzer {
  static const int _gridSize = 64; // 分析用缩放尺寸

  /// 分析图像特征
  Future<ImageFeatures> analyzeImage(Uint8List imageBytes) async {
    // 解析为灰度像素（简化处理：假设 RGBA 或灰度）
    final pixels = _extractGrayscalePixels(imageBytes);

    final contrast = _calculateContrast(pixels);
    final noise = _calculateNoise(pixels);
    final blur = _calculateBlur(pixels);
    final lineThickness = _calculateLineThickness(pixels);
    final connection = _calculateConnection(pixels);

    return ImageFeatures(
      contrast: contrast,
      noise: noise,
      blur: blur,
      lineThickness: lineThickness,
      connection: connection,
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
      if (pixels[i] < threshold && !visited[i]) {
        componentCount++;
        // BFS 标记连通区域
        final queue = [i];
        visited[i] = true;
        while (queue.isNotEmpty) {
          final cur = queue.removeAt(0);
          final cy = cur ~/ w;
          final cx = cur % w;
          for (final [dy, dx] in [
            [-1, 0],
            [1, 0],
            [0, -1],
            [0, 1]
          ]) {
            final ny = cy + dy;
            final nx = cx + dx;
            if (ny >= 0 &&
                ny < _gridSize &&
                nx >= 0 &&
                nx < w) {
              final ni = ny * w + nx;
              if (!visited[ni] && pixels[ni] < threshold) {
                visited[ni] = true;
                queue.add(ni);
              }
            }
          }
        }
      }
    }

    // 手写汉字通常有 2-10 个连通区域
    // 1-2个→高度连笔，10+→笔画分离
    // 返回值：连笔程度高→值高
    if (componentCount <= 1) return 0.9; // 几乎全连
    if (componentCount <= 3) return 0.6; // 部分连笔
    if (componentCount <= 6) return 0.3; // 正常
    return 0.1; // 笔画分离
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
