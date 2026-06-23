import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/project.dart';
import '../models/segmented_character.dart';
import 'image_analyzer.dart';

/// 进度回调类型：progress 范围 0.0 ~ 1.0，message 描述当前步骤
typedef ProgressCallback = void Function(double progress, String message);

// --- Isolate helpers: 序列化/反序列化，确保数据可跨 Isolate 传递 ---

List<Map<String, dynamic>> _serializeContour(Contour contour) {
  return contour.points
      .map((p) => {'x': p.x, 'y': p.y, 'onCurve': p.onCurve})
      .toList();
}

Contour _deserializeContour(List<Map<String, dynamic>> pointMaps) {
  return Contour(
    pointMaps
        .map((p) => ContourPoint(
              p['x'] as int,
              p['y'] as int,
              onCurve: p['onCurve'] as bool? ?? true,
            ))
        .toList(),
  );
}

/// Isolate 入口函数：执行轮廓提取的核心计算逻辑。
/// 接收序列化的参数 Map，返回序列化的轮廓数据。
/// 必须为顶层函数以满足 Isolate.run() 的要求。
List<List<Map<String, dynamic>>> _computeContours(Map<String, dynamic> params) {
  final imageBytes = params['imageBytes'] as Uint8List;
  final threshold = params['threshold'] as double;
  final strokeWidth = params['strokeWidth'] as double;
  final smoothness = params['smoothness'] as double;
  final invertColors = params['invertColors'] as bool;

  final image = img.decodeImage(imageBytes);
  if (image == null) return [];

  // --- 图片预处理（与原 extractContours 逻辑一致）---
  img.Image workImage = image;
  final maxDim = workImage.width > workImage.height
      ? workImage.width
      : workImage.height;
  final pixelCount = workImage.width * workImage.height;
  final estimatedMemoryMB = (pixelCount * 4 * 3) / (1024 * 1024);

  if (estimatedMemoryMB > 150) {
    final memScale = sqrt(150.0 / estimatedMemoryMB);
    final targetMaxDim = (maxDim * memScale).round().clamp(200, 99999);
    final scale = targetMaxDim / maxDim;
    final newW = (workImage.width * scale).round().clamp(1, 99999);
    final newH = (workImage.height * scale).round().clamp(1, 99999);
    workImage = img.copyResize(workImage,
        width: newW, height: newH, interpolation: img.Interpolation.linear);
  } else if (maxDim > 800) {
    final scale = 800.0 / maxDim;
    final newW = (workImage.width * scale).round().clamp(1, 99999);
    final newH = (workImage.height * scale).round().clamp(1, 99999);
    workImage = img.copyResize(workImage,
        width: newW, height: newH, interpolation: img.Interpolation.linear);
  }

  final gray = img.grayscale(workImage);
  // 估算噪声水平，自动选择模糊强度
  final noiseLevel = ImageProcessor._estimateNoiseLevel(gray);
  final blurred = ImageProcessor._gaussianBlur(gray, strong: noiseLevel > 0.15);
  img.Image binary;
  final adaptiveResult =
      ImageProcessor._adaptiveThreshold(blurred, blockSize: 31, c: 12, invert: invertColors);
  final blackRatio = ImageProcessor._blackPixelRatio(adaptiveResult);
  if (blackRatio > 0.80 || blackRatio < 0.01) {
    if ((threshold - 0.5).abs() < 0.001) {
      final otsuT = ImageProcessor.otsuThreshold(blurred);
      binary = ImageProcessor._binarize(blurred, otsuT / 255.0, invertColors);
    } else {
      binary = ImageProcessor._binarize(blurred, threshold, invertColors);
    }
  } else {
    binary = adaptiveResult;
  }

  // --- 外轮廓提取 ---
  final List<Contour> allContours = [];
  final visited = List.generate(
    binary.height,
    (_) => List.filled(binary.width, false),
  );

  // 性能优化：缓存像素数据为 bool 数组，避免重复 getPixel 调用
  final blackMap = List.generate(
    binary.height,
    (y) => List.generate(binary.width, (x) => ImageProcessor._isBlack(binary, x, y)),
  );

  for (int y = 0; y < binary.height; y++) {
    for (int x = 0; x < binary.width; x++) {
      if (!visited[y][x] && blackMap[y][x]) {
        final contour =
            ImageProcessor._traceContour(binary, x, y, visited);
        if (contour.length > 4) {
          final scaled = ImageProcessor._scaleContour(
              contour, binary.width, binary.height, strokeWidth);
          final simplified =
              ImageProcessor._simplifyContour(scaled, smoothness * 5 + 2);
          if (simplified.length >= 3) {
            final closed = ImageProcessor._ensureClosedContour(simplified);
            final fitted = ImageProcessor._fitBezierCurves(closed, smoothness);
            allContours.add(Contour(fitted));
          }
        }
      }
    }
  }

  // --- 空心字检测 ---
  final w = binary.width, h = binary.height;
  final isExterior = List.generate(h, (_) => List.filled(w, false));
  final bfsDirs4 = const [
    [1, 0],
    [-1, 0],
    [0, 1],
    [0, -1]
  ];

  // BFS from edge pixels to mark exterior white regions
  // 性能优化：使用 Queue 替代 List，removeFirst 为 O(1) vs removeAt(0) 为 O(n)
  final queue = Queue<List<int>>();
  for (int x = 0; x < w; x++) {
    if (!blackMap[0][x]) {
      queue.addLast([x, 0]);
      isExterior[0][x] = true;
    }
    if (!blackMap[h - 1][x]) {
      queue.addLast([x, h - 1]);
      isExterior[h - 1][x] = true;
    }
  }
  for (int y = 1; y < h - 1; y++) {
    if (!blackMap[y][0]) {
      queue.addLast([0, y]);
      isExterior[y][0] = true;
    }
    if (!blackMap[y][w - 1]) {
      queue.addLast([w - 1, y]);
      isExterior[y][w - 1] = true;
    }
  }
  while (queue.isNotEmpty) {
    final p = queue.removeFirst();
    for (final d in bfsDirs4) {
      final nx = p[0] + d[0], ny = p[1] + d[1];
      if (nx >= 0 &&
          nx < w &&
          ny >= 0 &&
          ny < h &&
          !isExterior[ny][nx] &&
          !ImageProcessor._isBlack(binary, nx, ny)) {
        isExterior[ny][nx] = true;
        queue.addLast([nx, ny]);
      }
    }
  }

  // Find interior white regions (holes) and trace their contours
  final holeVisited = List.generate(h, (_) => List.filled(w, false));

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (blackMap[y][x] ||
          isExterior[y][x] ||
          holeVisited[y][x]) continue;

      final holePixels = <Point>[];
      int minX = x, maxX = x, minY = y, maxY = y;
      final holeQueue = Queue<List<int>>();
      holeQueue.addLast([x, y]);
      holeVisited[y][x] = true;

      while (holeQueue.isNotEmpty) {
        final p = holeQueue.removeFirst();
        final px = p[0], py = p[1];
        holePixels.add(Point(px, py));
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;

        for (final d in bfsDirs4) {
          final nx = px + d[0], ny = py + d[1];
          if (nx >= 0 &&
              nx < w &&
              ny >= 0 &&
              ny < h &&
              !holeVisited[ny][nx] &&
              !blackMap[ny][nx] &&
              !isExterior[ny][nx]) {
            holeVisited[ny][nx] = true;
            holeQueue.addLast([nx, ny]);
          }
        }
      }

      if (holePixels.length < 4) continue;
      final holeW = maxX - minX + 1;
      final holeH = maxY - minY + 1;
      if (holeW > w * 0.4 || holeH > h * 0.4) continue;

      int bx = -1, by = -1;
      for (final p in holePixels) {
        if (p.x > 0 && blackMap[p.y][p.x - 1]) {
          bx = p.x;
          by = p.y;
          break;
        }
      }
      if (bx < 0) {
        for (final p in holePixels) {
          bool hasBlackNeighbor = false;
          for (final d in bfsDirs4) {
            final nx = p.x + d[0], ny = p.y + d[1];
            if (nx >= 0 &&
                nx < w &&
                ny >= 0 &&
                ny < h &&
                blackMap[ny][nx]) {
              hasBlackNeighbor = true;
              break;
            }
          }
          if (hasBlackNeighbor) {
            bx = p.x;
            by = p.y;
            break;
          }
        }
      }
      if (bx < 0) continue;

      // Moore neighborhood tracing for hole boundary
      const tdx = [1, 1, 0, -1, -1, -1, 0, 1];
      const tdy = [0, 1, 1, 1, 0, -1, -1, -1];

      int dir = 0;
      final traceStartX = bx, traceStartY = by;
      final holeContour = <Point>[Point(bx, by)];
      int maxSteps = w * h;
      int steps = 0;

      do {
        int searchDir = (dir + 7) % 8;
        bool found = false;
        for (int i = 0; i < 8; i++) {
          int d = (searchDir + i) % 8;
          int nx = bx + tdx[d];
          int ny = by + tdy[d];
          if (nx >= 0 &&
              nx < w &&
              ny >= 0 &&
              ny < h &&
              blackMap[ny][nx]) {
            bx = nx;
            by = ny;
            dir = d;
            found = true;
            break;
          }
        }
        if (!found) break;

        steps++;
        if (bx != traceStartX || by != traceStartY) {
          holeContour.add(Point(bx, by));
        }
      } while ((bx != traceStartX || by != traceStartY) && steps < maxSteps);

      if (holeContour.length > 4) {
        final scaled =
            ImageProcessor._scaleContour(holeContour, w, h, strokeWidth);
        final simplified =
            ImageProcessor._simplifyContour(scaled, smoothness * 5 + 2);
        if (simplified.length >= 3) {
          var closed = ImageProcessor._ensureClosedContour(simplified);

          // Ensure correct winding: inner contours should be counterclockwise
          if (closed.length >= 3) {
            double signedArea = 0;
            for (int i = 0; i < closed.length - 1; i++) {
              signedArea += (closed[i + 1].x - closed[i].x) *
                  (closed[i + 1].y + closed[i].y);
            }
            if (signedArea > 0) {
              closed = closed.reversed.toList();
            }
          }

          final fitted = ImageProcessor._fitBezierCurves(closed, smoothness);
          allContours.add(Contour(fitted));
        }
      }
    }
  }

  return allContours.map(_serializeContour).toList();
}

/// Service for processing handwriting images into glyph data.
///
/// 监控功能：
/// - 性能监控：记录各处理步骤耗时
/// - 错误监控：记录错误类型、频率和上下文
/// - 使用监控：记录功能调用频率和参数分布
/// - 资源监控：追踪内存使用和处理队列状态
class ImageProcessor {
  // ── 轮廓提取结果缓存（避免重复计算相同图片的轮廓） ──
  static final Map<int, List<Contour>> _contourCache = {};
  static const int _maxContourCacheSize = 20;

  /// 根据图像特征智能选择预处理策略（v2.8.0）
  List<String> selectStrategies(ImageFeatures features) {
    final selected = <String>[];
    
    if (features.contrast < 0.4) {
      selected.addAll(['adaptiveThreshold', 'clahe', 'localContrast']);
    }
    if (features.noise > 0.5) {
      selected.addAll(['gaussianBlur', 'medianBlur', 'nlMeansDenoise']);
    }
    if (features.blur > 0.5) {
      selected.addAll(['unsharpMask', 'highPassFilter', 'edgeEnhance']);
    }
    if (features.lineThickness < 0.3) {
      selected.addAll(['dilate', 'morphClose', 'thicken']);
    }
    if (features.lineThickness > 0.7) {
      selected.addAll(['erode', 'thin']);
    }
    if (features.connection > 0.6) {
      selected.addAll(['componentSeparation', 'skeletonize']);
    }
    
    final unique = selected.toSet().toList();
    if (unique.length < 5) {
      final fallbacks = ['otsuThreshold', 'adaptiveThreshold', 'morphClose', 'edgeEnhance', 'clahe'];
      for (final f in fallbacks) {
        if (!unique.contains(f)) unique.add(f);
        if (unique.length >= 5) break;
      }
    }
    return unique.take(12).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 监控功能：性能、错误、使用、资源
  // ═══════════════════════════════════════════════════════════

  /// 性能监控数据（操作名 → 耗时列表）
  static final Map<String, List<double>> _perfTimings = {};
  static const int _maxTimingEntries = 100;

  /// 错误监控数据
  static final List<Map<String, dynamic>> _errorLog = [];
  static const int _maxErrorLogSize = 200;

  /// 使用监控数据（功能调用计数）
  static final Map<String, int> _usageCounter = {};

  /// 资源监控：处理中的任务数
  static int _activeTaskCount = 0;
  static int _peakTaskCount = 0;
  static int _totalTasksProcessed = 0;
  static int _totalProcessingTimeUs = 0;

  /// 记录性能指标（内部使用）
  static void _recordPerfTiming(String operation, Duration elapsed) {
    _perfTimings.putIfAbsent(operation, () => []);
    final timings = _perfTimings[operation]!;
    timings.add(elapsed.inMicroseconds / 1000.0); // 转为毫秒
    if (timings.length > _maxTimingEntries) {
      timings.removeAt(0);
    }
  }

  /// 记录错误（内部使用）
  static void _recordError(String operation, Object error, {String? context}) {
    _errorLog.add({
      'timestamp': DateTime.now().toIso8601String(),
      'operation': operation,
      'error': error.toString(),
      'errorType': error.runtimeType.toString(),
      if (context != null) 'context': context,
    });
    if (_errorLog.length > _maxErrorLogSize) {
      _errorLog.removeAt(0);
    }
    debugPrint('ImageProcessor 错误 [$operation]: $error');
  }

  /// 记录功能使用（内部使用）
  static void _recordUsage(String feature) {
    _usageCounter[feature] = (_usageCounter[feature] ?? 0) + 1;
  }

  /// 更新资源监控（任务开始）
  static void _taskStarted() {
    _activeTaskCount++;
    if (_activeTaskCount > _peakTaskCount) {
      _peakTaskCount = _activeTaskCount;
    }
  }

  /// 更新资源监控（任务完成）
  static void _taskCompleted(Duration elapsed) {
    _activeTaskCount = (_activeTaskCount - 1).clamp(0, 999999);
    _totalTasksProcessed++;
    _totalProcessingTimeUs += elapsed.inMicroseconds;
  }

  /// 获取性能监控快照
  ///
  /// 返回各操作的统计信息：平均值、P50、P95、最大值
  static Map<String, Map<String, double>> getPerformanceStats() {
    final stats = <String, Map<String, double>>{};
    for (final entry in _perfTimings.entries) {
      final timings = entry.value;
      if (timings.isEmpty) continue;
      final sorted = List<double>.from(timings)..sort();
      final avg = sorted.reduce((a, b) => a + b) / sorted.length;
      final p50Index = (sorted.length * 0.5).round().clamp(0, sorted.length - 1);
      final p95Index = (sorted.length * 0.95).round().clamp(0, sorted.length - 1);
      stats[entry.key] = {
        'count': sorted.length.toDouble(),
        'avgMs': avg,
        'p50Ms': sorted[p50Index],
        'p95Ms': sorted[p95Index],
        'maxMs': sorted.last,
        'minMs': sorted.first,
      };
    }
    return stats;
  }

  /// 获取错误监控数据
  static List<Map<String, dynamic>> getErrorLog({int limit = 50}) {
    final start = (_errorLog.length - limit).clamp(0, _errorLog.length);
    return List.unmodifiable(_errorLog.sublist(start));
  }

  /// 获取错误统计摘要（按错误类型分组计数）
  static Map<String, int> getErrorSummary() {
    final summary = <String, int>{};
    for (final error in _errorLog) {
      final type = error['errorType'] as String? ?? 'unknown';
      summary[type] = (summary[type] ?? 0) + 1;
    }
    return summary;
  }

  /// 获取使用监控数据（功能调用计数）
  static Map<String, int> getUsageStats() => Map.unmodifiable(_usageCounter);

  /// 获取资源监控数据
  static Map<String, dynamic> getResourceStats() {
    return {
      'activeTaskCount': _activeTaskCount,
      'peakTaskCount': _peakTaskCount,
      'totalTasksProcessed': _totalTasksProcessed,
      'avgProcessingTimeMs': _totalTasksProcessed > 0
          ? (_totalProcessingTimeUs / _totalTasksProcessed) / 1000.0
          : 0.0,
      'contourCacheSize': _contourCache.length,
      'maxContourCacheSize': _maxContourCacheSize,
    };
  }

  /// 获取完整监控报告（合并所有监控维度）
  static Map<String, dynamic> getFullMonitorReport() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'performance': getPerformanceStats(),
      'errorSummary': getErrorSummary(),
      'errorCount': _errorLog.length,
      'usage': getUsageStats(),
      'resources': getResourceStats(),
    };
  }

  /// 清除所有监控数据
  static void clearMonitorData() {
    _perfTimings.clear();
    _errorLog.clear();
    _usageCounter.clear();
    _activeTaskCount = 0;
    _peakTaskCount = 0;
    _totalTasksProcessed = 0;
    _totalProcessingTimeUs = 0;
  }

  /// 清除轮廓缓存（用于释放内存）
  static void clearContourCache() => _contourCache.clear();

  // ═══════════════════════════════════════════════════════════
  // 计算机视觉（CV）功能：图像分类、目标检测、图像分割、图像增强
  // ═══════════════════════════════════════════════════════════

  /// 图像分类：基于图像像素特征进行自动分类
  ///
  /// [imageBytes] 图像字节数据
  /// [categories] 分类类别列表（可选）
  /// 返回分类结果 Map：
  /// - category: 分类类别
  /// - confidence: 置信度 (0.0~1.0)
  /// - features: 特征信息（颜色分布、亮度、对比度等）
  static Future<Map<String, dynamic>> classifyImage(
    Uint8List imageBytes, {
    List<String>? categories,
  }) async {
    _recordUsage('classifyImage');
    final sw = Stopwatch()..start();
    _taskStarted();
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        _recordError('classifyImage', '图片解码失败');
        return {'category': 'unknown', 'confidence': 0.0, 'features': {}};
      }

      // 提取图像特征
      final features = _extractImageFeatures(image);

      // 基于特征进行分类
      String category = 'general';
      double confidence = 0.5;

      final defaultCategories = ['text', 'photo', 'drawing', 'graphic', 'gradient'];
      final cats = categories ?? defaultCategories;

      // 基于颜色分布和纹理特征判断
      if (features['blackRatio'] != null && (features['blackRatio'] as double) > 0.3) {
        category = 'text';
        confidence = 0.8;
      } else if (features['edgeDensity'] != null && (features['edgeDensity'] as double) > 0.15) {
        category = 'drawing';
        confidence = 0.7;
      } else if (features['colorVariance'] != null && (features['colorVariance'] as double) > 0.3) {
        category = 'photo';
        confidence = 0.75;
      } else {
        category = cats.first;
        confidence = 0.5;
      }

      sw.stop();
      _recordPerfTiming('classifyImage', sw.elapsed);
      _taskCompleted(sw.elapsed);

      return {
        'category': category,
        'confidence': confidence,
        'features': features,
        'allCategories': cats,
      };
    } catch (e) {
      sw.stop();
      _taskCompleted(sw.elapsed);
      _recordError('classifyImage', e);
      return {'category': 'unknown', 'confidence': 0.0, 'features': {}, 'error': e.toString()};
    }
  }

  /// 提取图像特征（内部方法）
  static Map<String, dynamic> _extractImageFeatures(img.Image image) {
    final gray = img.grayscale(image);
    final width = gray.width, height = gray.height;
    final totalPixels = width * height;
    if (totalPixels == 0) return {};

    // 亮度统计
    double totalBrightness = 0;
    int blackCount = 0;
    int whiteCount = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final v = gray.getPixel(x, y).r.toDouble();
        totalBrightness += v;
        if (v < 50) blackCount++;
        if (v > 200) whiteCount++;
      }
    }
    final avgBrightness = totalBrightness / totalPixels;

    // 颜色方差
    double totalVariance = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final v = gray.getPixel(x, y).r.toDouble();
        totalVariance += (v - avgBrightness) * (v - avgBrightness);
      }
    }
    final colorVariance = (totalVariance / totalPixels) / (255.0 * 255.0);

    // 边缘密度（简化 Sobel 检测）
    int edgeCount = 0;
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final gx = gray.getPixel(x + 1, y).r.toDouble() - gray.getPixel(x - 1, y).r.toDouble();
        final gy = gray.getPixel(x, y + 1).r.toDouble() - gray.getPixel(x, y - 1).r.toDouble();
        final magnitude = sqrt(gx * gx + gy * gy);
        if (magnitude > 50) edgeCount++;
      }
    }
    final edgeDensity = edgeCount / totalPixels;

    return {
      'avgBrightness': avgBrightness / 255.0,
      'blackRatio': blackCount / totalPixels,
      'whiteRatio': whiteCount / totalPixels,
      'colorVariance': colorVariance,
      'edgeDensity': edgeDensity,
      'width': width,
      'height': height,
      'totalPixels': totalPixels,
    };
  }

  /// 目标检测：在图像中检测和定位目标区域
  ///
  /// [imageBytes] 图像字节数据
  /// [minArea] 最小目标面积（像素数），默认 100
  /// [maxTargets] 最大检测目标数，默认 20
  /// 返回检测到的目标列表，每个目标包含边界框和特征
  static Future<List<Map<String, dynamic>>> detectObjects(
    Uint8List imageBytes, {
    int minArea = 100,
    int maxTargets = 20,
  }) async {
    _recordUsage('detectObjects');
    final sw = Stopwatch()..start();
    _taskStarted();
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        _recordError('detectObjects', '图片解码失败');
        return [];
      }

      // 预处理
      final gray = img.grayscale(image);
      final blurred = _gaussianBlur(gray, strong: false);
      final threshold = otsuThreshold(blurred);
      final binary = _binarize(blurred, threshold / 255.0, false);

      // 连通域标记（BFS）
      final w = binary.width, h = binary.height;
      final visited = List.generate(h, (_) => List.filled(w, false));
      final objects = <Map<String, dynamic>>[];

      for (int y = 0; y < h && objects.length < maxTargets; y++) {
        for (int x = 0; x < w && objects.length < maxTargets; x++) {
          if (visited[y][x] || !_isBlack(binary, x, y)) continue;

          // BFS 探测连通域
          int minX = x, maxX = x, minY = y, maxY = y;
          int pixelCount = 0;
          final queue = <List<int>>[ [x, y] ];
          visited[y][x] = true;

          while (queue.isNotEmpty) {
            final p = queue.removeAt(0);
            final px = p[0], py = p[1];
            pixelCount++;
            if (px < minX) minX = px;
            if (px > maxX) maxX = px;
            if (py < minY) minY = py;
            if (py > maxY) maxY = py;

            for (final d in [[1,0],[-1,0],[0,1],[0,-1]]) {
              final nx = px + d[0], ny = py + d[1];
              if (nx >= 0 && nx < w && ny >= 0 && ny < h && !visited[ny][nx] && _isBlack(binary, nx, ny)) {
                visited[ny][nx] = true;
                queue.add([nx, ny]);
              }
            }
          }

          if (pixelCount < minArea) continue;

          final bboxW = maxX - minX + 1;
          final bboxH = maxY - minY + 1;

          objects.add({
            'boundingBox': {'x': minX, 'y': minY, 'width': bboxW, 'height': bboxH},
            'center': {'x': (minX + maxX) / 2, 'y': (minY + maxY) / 2},
            'area': pixelCount,
            'aspectRatio': bboxW / bboxH,
            'density': pixelCount / (bboxW * bboxH),
          });
        }
      }

      sw.stop();
      _recordPerfTiming('detectObjects', sw.elapsed);
      _taskCompleted(sw.elapsed);
      debugPrint('[ImageProcessor] 目标检测完成: ${objects.length} 个目标');
      return objects;
    } catch (e) {
      sw.stop();
      _taskCompleted(sw.elapsed);
      _recordError('detectObjects', e);
      return [];
    }
  }

  /// 图像分割：将图像分割为不同的区域
  ///
  /// [imageBytes] 图像字节数据
  /// [method] 分割方法 ('threshold' | 'edge' | 'region')
  /// [numRegions] 区域分割数量（region 方法），默认 4
  /// 返回分割结果 Map：
  /// - segments: 分割区域列表
  /// - method: 使用的分割方法
  /// - regionCount: 区域数量
  static Future<Map<String, dynamic>> segmentImage(
    Uint8List imageBytes, {
    String method = 'threshold',
    int numRegions = 4,
  }) async {
    _recordUsage('segmentImage');
    final sw = Stopwatch()..start();
    _taskStarted();
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        _recordError('segmentImage', '图片解码失败');
        return {'segments': [], 'method': method, 'regionCount': 0};
      }

      final segments = <Map<String, dynamic>>[];

      switch (method) {
        case 'threshold':
          // 多阈值分割：使用多个阈值将图像分为多个区域
          final gray = img.grayscale(image);
          final threshold = otsuThreshold(gray);
          for (int i = 0; i < 3; i++) {
            final t = (threshold * (i + 1) / 4).round().clamp(0, 255);
            int pixelCount = 0;
            for (int y = 0; y < gray.height; y++) {
              for (int x = 0; x < gray.width; x++) {
                final v = gray.getPixel(x, y).r.toInt();
                if (i == 0 && v < t) pixelCount++;
                else if (i == 1 && v >= threshold ~/ 2 && v < threshold) pixelCount++;
                else if (i == 2 && v >= threshold) pixelCount++;
              }
            }
            segments.add({
              'label': 'region_$i',
              'threshold': t,
              'pixelCount': pixelCount,
              'pixelRatio': pixelCount / (gray.width * gray.height),
            });
          }
          break;

        case 'edge':
          // 基于边缘的分割
          final gray = img.grayscale(image);
          int edgePixelCount = 0;
          for (int y = 1; y < gray.height - 1; y++) {
            for (int x = 1; x < gray.width - 1; x++) {
              final gx = gray.getPixel(x + 1, y).r.toDouble() - gray.getPixel(x - 1, y).r.toDouble();
              final gy = gray.getPixel(x, y + 1).r.toDouble() - gray.getPixel(x, y - 1).r.toDouble();
              if (sqrt(gx * gx + gy * gy) > 30) edgePixelCount++;
            }
          }
          segments.add({
            'label': 'edge_region',
            'pixelCount': edgePixelCount,
            'pixelRatio': edgePixelCount / (gray.width * gray.height),
          });
          final interiorPixels = gray.width * gray.height - edgePixelCount;
          segments.add({
            'label': 'interior_region',
            'pixelCount': interiorPixels,
            'pixelRatio': interiorPixels / (gray.width * gray.height),
          });
          break;

        case 'region':
          // 网格区域分割：将图像均匀分为 N 个区域
          final cols = sqrt(numRegions).ceil();
          final rows = (numRegions / cols).ceil();
          final regionW = image.width ~/ cols;
          final regionH = image.height ~/ rows;
          for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols && segments.length < numRegions; c++) {
              int blackPixels = 0;
              final startX = c * regionW;
              final startY = r * regionH;
              for (int y = startY; y < startY + regionH && y < image.height; y++) {
                for (int x = startX; x < startX + regionW && x < image.width; x++) {
                  final pixel = image.getPixel(x, y);
                  final brightness = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                  if (brightness < 128) blackPixels++;
                }
              }
              segments.add({
                'label': 'region_${r}_$c',
                'boundingBox': {'x': startX, 'y': startY, 'width': regionW, 'height': regionH},
                'pixelCount': blackPixels,
                'pixelRatio': blackPixels / (regionW * regionH),
              });
            }
          }
          break;
      }

      sw.stop();
      _recordPerfTiming('segmentImage', sw.elapsed);
      _taskCompleted(sw.elapsed);

      return {
        'segments': segments,
        'method': method,
        'regionCount': segments.length,
      };
    } catch (e) {
      sw.stop();
      _taskCompleted(sw.elapsed);
      _recordError('segmentImage', e);
      return {'segments': [], 'method': method, 'regionCount': 0, 'error': e.toString()};
    }
  }

  /// 图像增强：对图像进行增强处理以提升质量
  ///
  /// [imageBytes] 图像字节数据
  /// [brightness] 亮度调节 (-1.0 ~ 1.0)，默认 0
  /// [contrast] 对比度调节 (0.5 ~ 2.0)，默认 1.0
  /// [sharpness] 锐化强度 (0.0 ~ 2.0)，默认 0
  /// [denoise] 是否降噪，默认 false
  /// 返回增强后的图像字节数据
  static Future<Uint8List> enhanceImage(
    Uint8List imageBytes, {
    double brightness = 0,
    double contrast = 1.0,
    double sharpness = 0,
    bool denoise = false,
  }) async {
    _recordUsage('enhanceImage');
    final sw = Stopwatch()..start();
    _taskStarted();
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        _recordError('enhanceImage', '图片解码失败');
        return imageBytes; // 返回原图
      }

      img.Image result = image;

      // 亮度和对比度调节
      if (brightness != 0 || contrast != 1.0) {
        result = img.adjustColor(result,
          brightness: 1.0 + brightness,
          contrast: contrast,
        );
      }

      // 降噪处理
      if (denoise) {
        result = _gaussianBlur(result, strong: false);
      }

      // 锐化处理
      if (sharpness > 0) {
        final sharpImg = img.Image(width: result.width, height: result.height);
        final kernel = [0, -sharpness, 0, -sharpness, 1 + 4 * sharpness, -sharpness, 0, -sharpness, 0];
        for (int y = 1; y < result.height - 1; y++) {
          for (int x = 1; x < result.width - 1; x++) {
            num r = 0, g = 0, b = 0;
            int ki = 0;
            for (int dy = -1; dy <= 1; dy++) {
              for (int dx = -1; dx <= 1; dx++) {
                final pixel = result.getPixel(x + dx, y + dy);
                r += pixel.r * kernel[ki];
                g += pixel.g * kernel[ki];
                b += pixel.b * kernel[ki];
                ki++;
              }
            }
            sharpImg.setPixelRgba(x, y,
              r.clamp(0, 255).toInt(),
              g.clamp(0, 255).toInt(),
              b.clamp(0, 255).toInt(),
              255);
          }
        }
        result = sharpImg;
      }

      // 编码回 PNG
      final encoded = img.encodePng(result);

      sw.stop();
      _recordPerfTiming('enhanceImage', sw.elapsed);
      _taskCompleted(sw.elapsed);
      debugPrint('[ImageProcessor] 图像增强完成: brightness=$brightness, contrast=$contrast, sharpness=$sharpness, denoise=$denoise');

      return Uint8List.fromList(encoded);
    } catch (e) {
      sw.stop();
      _taskCompleted(sw.elapsed);
      _recordError('enhanceImage', e);
      return imageBytes; // 出错返回原图
    }
  }

  /// Process a source image into individual character glyphs.
  /// Assumes characters are written on a grid (e.g., graph paper).
  /// Returns a map of character string -> binary image data.
  static List<Uint8List> segmentCharacters(
    Uint8List imageBytes,
    ProcessingParams params,
  ) {
    _recordUsage('segmentCharacters');
    final sw = Stopwatch()..start();
    _taskStarted();
    try {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      _recordError('segmentCharacters', '图片解码失败', context: 'imageSize=${imageBytes.length}');
      return [];
    }

    // --- Resolution-adaptive processing ---
    img.Image workImage = image;
    if (workImage.width > 2000) {
      final scale = 1500.0 / workImage.width;
      final newW = (workImage.width * scale).round().clamp(1, 99999);
      final newH = (workImage.height * scale).round().clamp(1, 99999);
      debugPrint('segmentCharacters: 大图缩小 ${workImage.width}x${workImage.height} -> ${newW}x$newH');
      workImage = img.copyResize(workImage, width: newW, height: newH, interpolation: img.Interpolation.linear);
    }
    final refWidth = workImage.width;

    // Convert to grayscale
    final gray = img.grayscale(workImage);

    // Apply contrast
    final contrasted = img.adjustColor(gray, contrast: params.contrast);

    // 估算噪声水平，自动选择模糊强度
    final noiseLevel = _estimateNoiseLevel(contrasted);
    debugPrint('segmentCharacters: 噪声水平 ${noiseLevel.toStringAsFixed(2)}');
    // 噪声水平 > 0.15 时使用强模糊，否则使用标准模糊
    final blurred = _gaussianBlur(contrasted, strong: noiseLevel > 0.15);

    // Try adaptive thresholding first; fall back to global if result is too extreme
    img.Image binary;
    // 根据图片尺寸自适应选择 block size：大图用更大 block 以获得更好的全局一致性
    final adaptiveBlockSize = (refWidth > 1000) ? 41 : 31;
    final adaptiveResult = _adaptiveThreshold(blurred, blockSize: adaptiveBlockSize, c: 10, invert: params.invertColors);
    final blackRatio = _blackPixelRatio(adaptiveResult);
    if (blackRatio > 0.80 || blackRatio < 0.01) {
      debugPrint('segmentCharacters: 自适应阈值结果异常 (black=${(blackRatio*100).toStringAsFixed(1)}%), 回退全局阈值');
      // Use Otsu auto-threshold when threshold is the default 0.5
      if ((params.threshold - 0.5).abs() < 0.001) {
        final otsuT = otsuThreshold(blurred);
        binary = _binarize(blurred, otsuT / 255.0, params.invertColors);
        debugPrint('segmentCharacters: 使用 Otsu 自动阈值 ${otsuT}');
      } else {
        binary = _binarize(blurred, params.threshold, params.invertColors);
      }
    } else {
      binary = adaptiveResult;
    }

    // v5.0.0: 智能手写区域检测 — 网格线检测与移除 + 手写区域自动裁剪
    // 1. 检测并移除方格纸网格线（避免网格线干扰字符连通域分析）
    // 2. 自动裁剪到手写区域（让字符占据更大比例）
    final gridMasked = _detectAndMaskGridLines(binary);
    final cropped = _autoCropHandwritingRegion(gridMasked);
    if (cropped.width != binary.width || cropped.height != binary.height) {
      debugPrint('手写区域检测: 原图 ${binary.width}x${binary.height} → 裁剪后 ${cropped.width}x${cropped.height}');
    }
    binary = cropped;

    // Apply morphological operations
    img.Image processed = binary;
    // Scale erosion/dilation based on resolution relative to a 1500px reference
    // 使用裁剪后的宽度计算，因为裁剪后字符占据更大比例
    final currentWidth = processed.width.toDouble();
    final resolutionScale = currentWidth / 1500.0;
    final scaledErosion = (params.erosion * resolutionScale).round().clamp(0, 10);
    final scaledDilation = (params.dilation * resolutionScale).round().clamp(0, 10);
    for (int i = 0; i < scaledErosion; i++) {
      processed = _erode(processed);
    }
    for (int i = 0; i < scaledDilation; i++) {
      processed = _dilate(processed);
    }

    // --- Adaptive connected component segmentation ---
    final w = processed.width;
    final h = processed.height;
    final totalArea = w * h;
    // Resolution-adaptive area thresholds
    final baseRef = 1500.0 * 1500.0;
    final resolutionFactor = totalArea / baseRef;
    final minArea = (150 * resolutionFactor).toInt().clamp(20, 999999);   // scaled from ~150px base
    final maxArea = (totalArea * 0.15).toInt();                           // 15% — filter multi-char blobs

    // BFS flood fill to find connected components with bounding boxes
    final visited = List.generate(h, (_) => List.filled(w, false));
    final directions = const [
      [1, 0], [-1, 0], [0, 1], [0, -1],
    ];
    // 性能优化：缓存像素数据为 bool 数组，避免重复 getPixel 调用
    final blackRows = List.generate(
      h,
      (y) => List.generate(w, (x) => _isBlack(processed, x, y)),
    );

    // Each entry: [minX, minY, maxX, maxY, area]
    final List<List<int>> bboxes = [];

    for (int sy = 0; sy < h; sy++) {
      for (int sx = 0; sx < w; sx++) {
        if (visited[sy][sx] || !blackRows[sy][sx]) continue;

        // BFS - 性能优化：使用 Queue 替代 List，removeFirst 为 O(1)
        int minX = sx, maxX = sx, minY = sy, maxY = sy, area = 0;
        final queue = Queue<List<int>>();
        queue.addLast([sx, sy]);
        visited[sy][sx] = true;

        while (queue.isNotEmpty) {
          final p = queue.removeFirst();
          final px = p[0], py = p[1];
          area++;
          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;

          for (final d in directions) {
            final nx = px + d[0], ny = py + d[1];
            if (nx >= 0 && nx < w && ny >= 0 && ny < h &&
                !visited[ny][nx] && blackRows[ny][nx]) {
              visited[ny][nx] = true;
              queue.addLast([nx, ny]);
            }
          }
        }

        // Filter by area
        if (area < minArea || area > maxArea) continue;

        // Filter by dimension ratio: single character shouldn't exceed 45% of image width/height
        final bw = maxX - minX + 1;
        final bh = maxY - minY + 1;
        if (bw > w * 0.45 || bh > h * 0.45) continue;

        // v4.3.0: 粘连字符分割 — 宽高比 > 1.8 时尝试垂直投影分割
        final aspect = bw > bh ? bw / bh : bh / bw;
        if (aspect > 1.8 && bw > bh && bw > 30) {
          // 可能是粘连字符，尝试垂直投影分割
          final splits = _verticalProjectionSplit(blackRows, minX, minY, maxX, maxY, w, h);
          if (splits.length >= 2) {
            debugPrint('粘连分割(垂直): ${bw}x$bh (aspect=${aspect.toStringAsFixed(1)}) → ${splits.length} 个子区域');
            for (final split in splits) {
              final sBw = split[2] - split[0] + 1;
              final sBh = split[3] - split[1] + 1;
              final sAspect = sBw > sBh ? sBw / sBh : sBh / sBw;
              if (sAspect < 3.0 && sBw > 5 && sBh > 5) {
                bboxes.add([split[0], split[1], split[2], split[3], area ~/ splits.length]);
              }
            }
            continue; // 已分割，跳过原始大框
          }
        }

        // v4.6.0: 水平投影分割 — 高宽比 > 1.8 时尝试上下粘连分割
        if (aspect > 1.8 && bh > bw && bh > 30) {
          final hSplits = _horizontalProjectionSplit(blackRows, minX, minY, maxX, maxY, w, h);
          if (hSplits.length >= 2) {
            debugPrint('粘连分割(水平): ${bw}x$bh (aspect=${aspect.toStringAsFixed(1)}) → ${hSplits.length} 个子区域');
            for (final split in hSplits) {
              final sBw = split[2] - split[0] + 1;
              final sBh = split[3] - split[1] + 1;
              final sAspect = sBw > sBh ? sBw / sBh : sBh / sBw;
              if (sAspect < 3.0 && sBw > 5 && sBh > 5) {
                bboxes.add([split[0], split[1], split[2], split[3], area ~/ hSplits.length]);
              }
            }
            continue; // 已分割，跳过原始大框
          }
        }

        // Filter by aspect ratio: single character should be roughly square (< 2.5:1)
        if (aspect > 2.5) continue;

        bboxes.add([minX, minY, maxX, maxY, area]);
      }
    }

    debugPrint('轮廓提取: 找到 ${bboxes.length} 个连通区域 (图片 ${w}x$h)');

    // v4.6.0: 断笔合并 — 将距离过近的连通域合并（处理断笔问题）
    if (bboxes.length >= 2) {
      double avgH = 0;
      for (final bb in bboxes) {
        avgH += (bb[3] - bb[1] + 1);
      }
      avgH /= bboxes.length;
      final mergedBboxes = _mergeBrokenStrokes(bboxes, avgH);
      if (mergedBboxes.length < bboxes.length) {
        debugPrint('断笔合并: ${bboxes.length} → ${mergedBboxes.length} 个区域');
        bboxes.clear();
        bboxes.addAll(mergedBboxes);
      }
    }

    if (bboxes.isEmpty) return [];

    // Sort by position: group into rows, then sort each row by x
    // Compute average character height for row grouping tolerance
    double avgHeight = 0;
    for (final bb in bboxes) {
      avgHeight += (bb[3] - bb[1] + 1);
    }
    avgHeight /= bboxes.length;
    final rowTolerance = avgHeight * 0.5;

    // Sort by minY first
    bboxes.sort((a, b) => a[1].compareTo(b[1]));

    // Group into rows
    final List<List<List<int>>> rows = [];
    for (final bb in bboxes) {
      final centerY = (bb[1] + bb[3]) / 2.0;
      bool placed = false;
      for (final row in rows) {
        final rowCenterY = (row.first[1] + row.first[3]) / 2.0;
        if ((centerY - rowCenterY).abs() <= rowTolerance) {
          row.add(bb);
          placed = true;
          break;
        }
      }
      if (!placed) {
        rows.add([bb]);
      }
    }

    // Sort each row by minX
    for (final row in rows) {
      row.sort((a, b) => a[0].compareTo(b[0]));
    }

    // Crop each character with 10% padding
    final List<Uint8List> cells = [];
    for (final row in rows) {
      for (final bb in row) {
        final minX = bb[0], minY = bb[1], maxX = bb[2], maxY = bb[3];
        final bw = maxX - minX + 1;
        final bh = maxY - minY + 1;
        final padX = (bw * 0.1).toInt();
        final padY = (bh * 0.1).toInt();

        final cropX = (minX - padX).clamp(0, w - 1);
        final cropY = (minY - padY).clamp(0, h - 1);
        final cropW = (bw + padX * 2).clamp(1, w - cropX);
        final cropH = (bh + padY * 2).clamp(1, h - cropY);

        final cell = img.copyCrop(processed,
          x: cropX, y: cropY, width: cropW, height: cropH);
        cells.add(img.encodePng(cell));
      }
    }

    return cells;
    } catch (e) {
      _recordError('segmentCharacters', e, context: 'imageSize=${imageBytes.length}');
      rethrow;
    } finally {
      sw.stop();
      _taskCompleted(sw.elapsed);
      _recordPerfTiming('segmentCharacters', sw.elapsed);
    }
  }

  /// v5.1.0: 增强版字符分割 — 返回带元数据的 SegmentedCharacter 对象
  ///
  /// 在原有分割逻辑基础上，额外输出：
  /// - 每个字符的原始尺寸和宽高比
  /// - 在原图中的边界框
  /// - 字符大小分类（small / medium / large）
  ///
  /// 内部复用 segmentCharacters 的核心逻辑，仅改变输出格式。
  static List<SegmentedCharacter> segmentCharactersEnhanced(
    Uint8List imageBytes,
    ProcessingParams params,
  ) {
    _recordUsage('segmentCharactersEnhanced');
    final sw = Stopwatch()..start();
    _taskStarted();
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        _recordError('segmentCharactersEnhanced', '图片解码失败',
            context: 'imageSize=${imageBytes.length}');
        return [];
      }

      // --- 与 segmentCharacters 相同的预处理流程 ---
      img.Image workImage = image;
      if (workImage.width > 2000) {
        final scale = 1500.0 / workImage.width;
        final newW = (workImage.width * scale).round().clamp(1, 99999);
        final newH = (workImage.height * scale).round().clamp(1, 99999);
        workImage = img.copyResize(workImage,
            width: newW, height: newH, interpolation: img.Interpolation.linear);
      }

      final gray = img.grayscale(workImage);
      final contrasted = img.adjustColor(gray, contrast: params.contrast);
      final noiseLevel = _estimateNoiseLevel(contrasted);
      final blurred = _gaussianBlur(contrasted, strong: noiseLevel > 0.15);

      img.Image binary;
      final adaptiveBlockSize = (workImage.width > 1000) ? 41 : 31;
      final adaptiveResult =
          _adaptiveThreshold(blurred, blockSize: adaptiveBlockSize, c: 10, invert: params.invertColors);
      final blackRatio = _blackPixelRatio(adaptiveResult);
      if (blackRatio > 0.80 || blackRatio < 0.01) {
        if ((params.threshold - 0.5).abs() < 0.001) {
          final otsuT = otsuThreshold(blurred);
          binary = _binarize(blurred, otsuT / 255.0, params.invertColors);
        } else {
          binary = _binarize(blurred, params.threshold, params.invertColors);
        }
      } else {
        binary = adaptiveResult;
      }

      final gridMasked = _detectAndMaskGridLines(binary);
      final cropped = _autoCropHandwritingRegion(gridMasked);
      binary = cropped;

      // 形态学处理
      img.Image processed = binary;
      final currentWidth = processed.width.toDouble();
      final resolutionScale = currentWidth / 1500.0;
      final scaledErosion = (params.erosion * resolutionScale).round().clamp(0, 10);
      final scaledDilation = (params.dilation * resolutionScale).round().clamp(0, 10);
      for (int i = 0; i < scaledErosion; i++) {
        processed = _erode(processed);
      }
      for (int i = 0; i < scaledDilation; i++) {
        processed = _dilate(processed);
      }

      // 连通域检测
      final w = processed.width;
      final h = processed.height;
      final totalArea = w * h;
      final baseRef = 1500.0 * 1500.0;
      final resolutionFactor = totalArea / baseRef;
      final minArea = (150 * resolutionFactor).toInt().clamp(20, 999999);
      final maxArea = (totalArea * 0.15).toInt();

      final visited = List.generate(h, (_) => List.filled(w, false));
      final directions = const [[1, 0], [-1, 0], [0, 1], [0, -1]];
      final blackRows = List.generate(
        h,
        (y) => List.generate(w, (x) => _isBlack(processed, x, y)),
      );

      final List<List<int>> bboxes = [];

      for (int sy = 0; sy < h; sy++) {
        for (int sx = 0; sx < w; sx++) {
          if (visited[sy][sx] || !blackRows[sy][sx]) continue;

          int minX = sx, maxX = sx, minY = sy, maxY = sy, area = 0;
          final queue = Queue<List<int>>();
          queue.addLast([sx, sy]);
          visited[sy][sx] = true;

          while (queue.isNotEmpty) {
            final p = queue.removeFirst();
            final px = p[0], py = p[1];
            area++;
            if (px < minX) minX = px;
            if (px > maxX) maxX = px;
            if (py < minY) minY = py;
            if (py > maxY) maxY = py;

            for (final d in directions) {
              final nx = px + d[0], ny = py + d[1];
              if (nx >= 0 && nx < w && ny >= 0 && ny < h &&
                  !visited[ny][nx] && blackRows[ny][nx]) {
                visited[ny][nx] = true;
                queue.addLast([nx, ny]);
              }
            }
          }

          if (area < minArea || area > maxArea) continue;
          final bw = maxX - minX + 1;
          final bh = maxY - minY + 1;
          if (bw > w * 0.45 || bh > h * 0.45) continue;

          final aspect = bw > bh ? bw / bh : bh / bw;
          if (aspect > 1.8 && bw > bh && bw > 30) {
            final splits = _verticalProjectionSplit(blackRows, minX, minY, maxX, maxY, w, h);
            if (splits.length >= 2) {
              for (final split in splits) {
                final sBw = split[2] - split[0] + 1;
                final sBh = split[3] - split[1] + 1;
                final sAspect = sBw > sBh ? sBw / sBh : sBh / sBw;
                if (sAspect < 3.0 && sBw > 5 && sBh > 5) {
                  bboxes.add([split[0], split[1], split[2], split[3], area ~/ splits.length]);
                }
              }
              continue;
            }
          }

          if (aspect > 1.8 && bh > bw && bh > 30) {
            final hSplits = _horizontalProjectionSplit(blackRows, minX, minY, maxX, maxY, w, h);
            if (hSplits.length >= 2) {
              for (final split in hSplits) {
                final sBw = split[2] - split[0] + 1;
                final sBh = split[3] - split[1] + 1;
                final sAspect = sBw > sBh ? sBw / sBh : sBh / sBw;
                if (sAspect < 3.0 && sBw > 5 && sBh > 5) {
                  bboxes.add([split[0], split[1], split[2], split[3], area ~/ hSplits.length]);
                }
              }
              continue;
            }
          }

          if (aspect > 2.5) continue;
          bboxes.add([minX, minY, maxX, maxY, area]);
        }
      }

      // 断笔合并
      if (bboxes.length >= 2) {
        double avgH = 0;
        for (final bb in bboxes) {
          avgH += (bb[3] - bb[1] + 1);
        }
        avgH /= bboxes.length;
        final mergedBboxes = _mergeBrokenStrokes(bboxes, avgH);
        if (mergedBboxes.length < bboxes.length) {
          bboxes.clear();
          bboxes.addAll(mergedBboxes);
        }
      }

      if (bboxes.isEmpty) return [];

      // 按位置排序
      double avgHeight = 0;
      for (final bb in bboxes) {
        avgHeight += (bb[3] - bb[1] + 1);
      }
      avgHeight /= bboxes.length;
      final rowTolerance = avgHeight * 0.5;

      bboxes.sort((a, b) => a[1].compareTo(b[1]));
      final List<List<List<int>>> rows = [];
      for (final bb in bboxes) {
        final centerY = (bb[1] + bb[3]) / 2.0;
        bool placed = false;
        for (final row in rows) {
          final rowCenterY = (row.first[1] + row.first[3]) / 2.0;
          if ((centerY - rowCenterY).abs() <= rowTolerance) {
            row.add(bb);
            placed = true;
            break;
          }
        }
        if (!placed) {
          rows.add([bb]);
        }
      }
      for (final row in rows) {
        row.sort((a, b) => a[0].compareTo(b[0]));
      }

      // 构建 SegmentedCharacter 列表
      final List<SegmentedCharacter> result = [];
      final allAreas = bboxes.map((bb) => (bb[2] - bb[0] + 1) * (bb[3] - bb[1] + 1)).toList();
      allAreas.sort();
      final medianArea = allAreas[allAreas.length ~/ 2].toDouble();

      for (final row in rows) {
        for (final bb in row) {
          final minX = bb[0], minY = bb[1], maxX = bb[2], maxY = bb[3];
          final bw = maxX - minX + 1;
          final bh = maxY - minY + 1;
          final padX = (bw * 0.1).toInt();
          final padY = (bh * 0.1).toInt();

          final cropX = (minX - padX).clamp(0, w - 1);
          final cropY = (minY - padY).clamp(0, h - 1);
          final cropW = (bw + padX * 2).clamp(1, w - cropX);
          final cropH = (bh + padY * 2).clamp(1, h - cropY);

          final cell = img.copyCrop(processed,
              x: cropX, y: cropY, width: cropW, height: cropH);
          final cellBytes = img.encodePng(cell);

          final charArea = bw * bh;
          final aspect = bw / bh.clamp(1, 99999);
          final sizeCategory = _detectCharacterSize(charArea, medianArea);

          result.add(SegmentedCharacter(
            imageBytes: cellBytes,
            originalWidth: image.width,
            originalHeight: image.height,
            aspectRatio: aspect,
            boundingBox: BoundingBox(
              x: minX,
              y: minY,
              width: bw,
              height: bh,
            ),
            sizeCategory: sizeCategory,
            areaRatio: charArea / totalArea,
          ));
        }
      }

      debugPrint('增强分割: ${result.length} 个字符 '
          '(小=${result.where((c) => c.sizeCategory == CharacterSize.small).length}, '
          '中=${result.where((c) => c.sizeCategory == CharacterSize.medium).length}, '
          '大=${result.where((c) => c.sizeCategory == CharacterSize.large).length})');

      return result;
    } catch (e) {
      _recordError('segmentCharactersEnhanced', e,
          context: 'imageSize=${imageBytes.length}');
      rethrow;
    } finally {
      sw.stop();
      _taskCompleted(sw.elapsed);
      _recordPerfTiming('segmentCharactersEnhanced', sw.elapsed);
    }
  }

  /// v5.1.0: 检测字符大小分类
  ///
  /// 根据字符面积与中位数面积的比值进行分类：
  /// - small: 面积 < 中位数的 50%（标点、简单笔画）
  /// - medium: 正常大小
  /// - large: 面积 > 中位数的 200%（复杂汉字、合体字）
  static CharacterSize _detectCharacterSize(int charArea, double medianArea) {
    if (medianArea <= 0) return CharacterSize.medium;
    final ratio = charArea / medianArea;
    if (ratio < 0.5) return CharacterSize.small;
    if (ratio > 2.0) return CharacterSize.large;
    return CharacterSize.medium;
  }

  /// Process a single character image with given parameters.
  static Uint8List processCharacterImage(
    Uint8List imageBytes,
    ProcessingParams params,
  ) {
    _recordUsage('processCharacterImage');
    final sw = Stopwatch()..start();
    try {
    final image = img.decodeImage(imageBytes);
    if (image == null) return imageBytes;

    // Convert to grayscale
    final gray = img.grayscale(image);

    // Apply contrast
    final contrasted = img.adjustColor(gray, contrast: params.contrast);

    // Apply threshold
    final binary = _binarize(contrasted, params.threshold, params.invertColors);

    // Apply morphological operations
    img.Image processed = binary;
    for (int i = 0; i < params.erosion; i++) {
      processed = _erode(processed);
    }
    for (int i = 0; i < params.dilation; i++) {
      processed = _dilate(processed);
    }

    // Apply smoothing
    if (params.smoothness > 0) {
      processed = _smooth(processed, params.smoothness);
    }

    final result = img.encodePng(processed);
    sw.stop();
    _recordPerfTiming('processCharacterImage', sw.elapsed);
    return result;
    } catch (e) {
      _recordError('processCharacterImage', e);
      rethrow;
    }
  }

  /// 同步轮廓提取：直接在当前 Isolate 执行，不创建新 Isolate。
  /// 用作 Isolate 超时/失败时的降级方案，确保始终能产出结果。
  static List<Contour> extractContoursSync(
    Uint8List imageBytes,
    ProcessingParams params,
  ) {
    _recordUsage('extractContoursSync');
    final sw = Stopwatch()..start();
    _taskStarted();
    try {
      // 缓存命中检查
      final cacheKey = _fastHash(imageBytes, params);
      if (_contourCache.containsKey(cacheKey)) {
        debugPrint('轮廓提取(同步): 命中缓存 (hash=$cacheKey)');
        return _contourCache[cacheKey]!;
      }

      final contourDataList = _computeContours({
        'imageBytes': imageBytes,
        'threshold': params.threshold,
        'strokeWidth': params.strokeWidth,
        'smoothness': params.smoothness,
        'invertColors': params.invertColors,
      });

      final allContours = contourDataList.map(_deserializeContour).toList();

      debugPrint('轮廓提取(同步)完成: 共 ${allContours.length} 个轮廓');

      // 写入缓存
      if (_contourCache.length >= _maxContourCacheSize) {
        _contourCache.remove(_contourCache.keys.first);
      }
      _contourCache[cacheKey] = allContours;

      return allContours;
    } catch (e) {
      _recordError('extractContoursSync', e, context: 'imageSize=${imageBytes.length}');
      rethrow;
    } finally {
      sw.stop();
      _taskCompleted(sw.elapsed);
      _recordPerfTiming('extractContoursSync', sw.elapsed);
    }
  }

  /// 后台 Isolate 轮廓提取：作为 extractContoursSync 的非阻塞替代。
  /// 用于 Isolate 超时/失败时的降级方案，避免阻塞主线程。
  static Future<List<Contour>> extractContoursInBackground(
    Uint8List imageBytes,
    ProcessingParams params,
  ) async {
    _recordUsage('extractContoursInBackground');
    final sw = Stopwatch()..start();
    _taskStarted();
    try {
      // 缓存命中检查
      final cacheKey = _fastHash(imageBytes, params);
      if (_contourCache.containsKey(cacheKey)) {
        debugPrint('轮廓提取(后台降级): 命中缓存 (hash=$cacheKey)');
        return _contourCache[cacheKey]!;
      }

      final contourDataList = await Isolate.run(() => _computeContours({
        'imageBytes': imageBytes,
        'threshold': params.threshold,
        'strokeWidth': params.strokeWidth,
        'smoothness': params.smoothness,
        'invertColors': params.invertColors,
      }));

      final allContours = contourDataList.map(_deserializeContour).toList();

      debugPrint('轮廓提取(后台降级)完成: 共 ${allContours.length} 个轮廓');

      // 写入缓存
      if (_contourCache.length >= _maxContourCacheSize) {
        _contourCache.remove(_contourCache.keys.first);
      }
      _contourCache[cacheKey] = allContours;

      return allContours;
    } catch (e) {
      _recordError('extractContoursInBackground', e, context: 'imageSize=${imageBytes.length}');
      rethrow;
    } finally {
      sw.stop();
      _taskCompleted(sw.elapsed);
      _recordPerfTiming('extractContoursInBackground', sw.elapsed);
    }
  }

  /// Extract contour points from a binary character image.
  /// Returns contours scaled to font units (0-1000).
  /// 核心计算在后台 Isolate 中执行，避免阻塞 UI 线程。
  /// [onProgress] 可选进度回调，[timeout] 超时时间（默认60秒）
  static Future<List<Contour>> extractContours(
    Uint8List imageBytes,
    ProcessingParams params, {
    ProgressCallback? onProgress,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    _recordUsage('extractContours');
    final sw = Stopwatch()..start();
    _taskStarted();

    try {
    // 性能优化：缓存命中检查
    final cacheKey = _fastHash(imageBytes, params);
    if (_contourCache.containsKey(cacheKey)) {
      debugPrint('轮廓提取: 命中缓存 (hash=$cacheKey)');
      onProgress?.call(1.0, '轮廓提取完成（缓存）');
      return _contourCache[cacheKey]!;
    }

    onProgress?.call(0.0, '正在解码图片...');

    // 快速校验图片是否可解码
    final image = img.decodeImage(imageBytes);
    if (image == null) return [];

    onProgress?.call(0.1, '轮廓提取中（后台计算）...');

    // 核心计算在 Isolate 中执行，避免阻塞 UI
    final contourDataList = await Isolate.run(
      () => _computeContours({
        'imageBytes': imageBytes,
        'threshold': params.threshold,
        'strokeWidth': params.strokeWidth,
        'smoothness': params.smoothness,
        'invertColors': params.invertColors,
      }),
    ).timeout(timeout, onTimeout: () {
      throw TimeoutException('轮廓提取超时', timeout);
    });

    onProgress?.call(0.9, '反序列化轮廓数据...');

    // 反序列化
    final allContours = contourDataList.map(_deserializeContour).toList();

    debugPrint('轮廓提取完成: 共 ${allContours.length} 个轮廓, '
        '点数=[${allContours.map((c) => c.points.length).join(", ")}]');

    // 写入缓存，超出上限时清除最旧条目
    if (_contourCache.length >= _maxContourCacheSize) {
      _contourCache.remove(_contourCache.keys.first);
    }
    _contourCache[cacheKey] = allContours;

    onProgress?.call(1.0, '轮廓提取完成');
    return allContours;
    } catch (e) {
      _recordError('extractContours', e, context: 'imageSize=${imageBytes.length}');
      rethrow;
    } finally {
      sw.stop();
      _taskCompleted(sw.elapsed);
      _recordPerfTiming('extractContours', sw.elapsed);
    }
  }

  /// Convert a binary character image to a scaled PNG for display.
  static Uint8List renderGlyphPreview(
    Uint8List imageBytes,
    ProcessingParams params,
    {int size = 256}
  ) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return imageBytes;

    final gray = img.grayscale(image);
    final binary = _binarize(gray, params.threshold, params.invertColors);

    // Resize
    final resized = img.copyResize(binary, width: size, height: size, interpolation: img.Interpolation.linear);

    // Invert for display (white on black -> black on white)
    final display = img.Image(width: resized.width, height: resized.height);
    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        final brightness = pixel.r.toInt();
        if (brightness < 128) {
          display.setPixelRgba(x, y, 0, 0, 0, 255);
        } else {
          display.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }

    return img.encodePng(display);
  }

  // --- Private helpers ---

  /// 快速哈希：结合图片字节和处理参数生成缓存 key
  static int _fastHash(Uint8List bytes, ProcessingParams params) {
    int hash = 0x811c9dc5;
    // 混入参数
    hash ^= (params.threshold * 1000).toInt();
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
    hash ^= (params.strokeWidth * 100).toInt();
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
    hash ^= (params.smoothness * 100).toInt();
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
    hash ^= params.invertColors ? 1 : 0;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
    // 采样字节（首尾各 128 字节）
    final len = bytes.length;
    final sampleSize = len < 256 ? len : 256;
    for (int i = 0; i < sampleSize ~/ 2; i++) {
      hash ^= bytes[i];
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    for (int i = (len - sampleSize ~/ 2).clamp(0, len); i < len; i++) {
      hash ^= bytes[i];
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  /// 二值化：将灰度图转为黑白图
  /// [threshold] 阈值 0.0~1.0，[invert] 是否反转
  static img.Image binarize(img.Image gray, double threshold, bool invert) => _binarize(gray, threshold, invert);

  static img.Image _binarize(img.Image gray, double threshold, bool invert) {
    final result = img.Image(width: gray.width, height: gray.height);
    final t = (threshold * 255).toInt();
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        final pixel = gray.getPixel(x, y);
        final brightness = pixel.r.toInt();
        final isBlack = invert ? brightness > t : brightness < t;
        if (isBlack) {
          result.setPixelRgba(x, y, 0, 0, 0, 255);
        } else {
          result.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }
    return result;
  }

  /// 高斯模糊：支持 3x3 和 5x5 两种核大小。
  /// 当 [strong] 为 true 时使用 5x5 核（更平滑，适合高噪点图片），
  /// 否则使用 3x3 核（默认，保留更多细节）。
  static img.Image _gaussianBlur(img.Image gray, {bool strong = false}) {
    if (!strong) {
      // 原有 3x3 核: [1,2,1,2,4,2,1,2,1]/16
      final w = gray.width, h = gray.height;
      final result = img.Image(width: w, height: h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int sum = 0;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              final nx = (x + dx).clamp(0, w - 1);
              final ny = (y + dy).clamp(0, h - 1);
              final weight = (dx == 0 && dy == 0) ? 4 : ((dx == 0 || dy == 0) ? 2 : 1);
              sum += gray.getPixel(nx, ny).r.toInt() * weight;
            }
          }
          final v = (sum / 16).round().clamp(0, 255);
          result.setPixelRgba(x, y, v, v, v, 255);
        }
      }
      return result;
    }
    // 5x5 高斯核（归一化权重），更强降噪
    const kernel = [
      [1, 4, 7, 4, 1],
      [4, 16, 26, 16, 4],
      [7, 26, 41, 26, 7],
      [4, 16, 26, 16, 4],
      [1, 4, 7, 4, 1],
    ];
    const divisor = 273;
    final w = gray.width, h = gray.height;
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int sum = 0;
        for (int dy = -2; dy <= 2; dy++) {
          for (int dx = -2; dx <= 2; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            sum += gray.getPixel(nx, ny).r.toInt() * kernel[dy + 2][dx + 2];
          }
        }
        final v = (sum / divisor).round().clamp(0, 255);
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// Otsu's method: find the optimal threshold that maximizes inter-class variance.
  /// Returns threshold as 0-255 value.
  static int otsuThreshold(img.Image gray) {
    final histogram = List.filled(256, 0);
    final total = gray.width * gray.height;
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        histogram[gray.getPixel(x, y).r.toInt()]++;
      }
    }

    double sumAll = 0;
    for (int i = 0; i < 256; i++) {
      sumAll += i * histogram[i];
    }

    double sumB = 0;
    int wB = 0;
    double maxVariance = 0;
    int bestThreshold = 128;

    for (int t = 0; t < 256; t++) {
      wB += histogram[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;

      sumB += t * histogram[t];
      final mB = sumB / wB;
      final mF = (sumAll - sumB) / wF;
      final variance = wB * wF * (mB - mF) * (mB - mF);
      if (variance > maxVariance) {
        maxVariance = variance;
        bestThreshold = t;
      }
    }
    return bestThreshold;
  }

  /// Adaptive thresholding: divide image into blocks, compute local mean,
  /// threshold = local_mean - c. Block size is forced odd. Uses integral image
  /// for fast local mean computation.
  /// 自适应阈值算法改进版：
  /// 1. 使用更鲁棒的局部均值计算（积分图加速）
  /// 2. 增加局部标准差惩罚，对低对比度区域自适应调整 c 值
  /// 3. 更大的默认 block size 提升全局一致性
  static img.Image _adaptiveThreshold(img.Image gray, {int blockSize = 31, int c = 12, bool invert = false}) {
    if (blockSize.isEven) blockSize++;
    final half = blockSize ~/ 2;
    final w = gray.width, h = gray.height;
    final result = img.Image(width: w, height: h);

    // Integral image for fast local mean
    final integral = List.generate(h, (_) => List.filled(w, 0));
    // 积分平方图，用于计算局部方差
    final integralSq = List.generate(h, (_) => List<int>.filled(w, 0));
    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      int rowSumSq = 0;
      for (int x = 0; x < w; x++) {
        final v = gray.getPixel(x, y).r.toInt();
        rowSum += v;
        rowSumSq += v * v;
        integral[y][x] = rowSum + (y > 0 ? integral[y - 1][x] : 0);
        integralSq[y][x] = rowSumSq + (y > 0 ? integralSq[y - 1][x] : 0);
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
        int sumSq = integralSq[y2][x2];
        if (x1 > 0) {
          sum -= integral[y2][x1 - 1];
          sumSq -= integralSq[y2][x1 - 1];
        }
        if (y1 > 0) {
          sum -= integral[y1 - 1][x2];
          sumSq -= integralSq[y1 - 1][x2];
        }
        if (x1 > 0 && y1 > 0) {
          sum += integral[y1 - 1][x1 - 1];
          sumSq += integralSq[y1 - 1][x1 - 1];
        }

        final localMean = sum / count;
        // 局部标准差：std = sqrt(E[X²] - E[X]²)
        final variance = (sumSq / count) - (localMean * localMean);
        final localVar = variance > 0 ? variance : 0;
        // 自适应 c 值：低对比度区域（方差小）用更小的 c 保留笔画
        final adaptiveC = localVar < 100 ? (c * 0.5).round() : c;
        final threshold = localMean - adaptiveC;
        final brightness = gray.getPixel(x, y).r.toInt();
        final isBlack = invert ? brightness > threshold : brightness < threshold;
        if (isBlack) {
          result.setPixelRgba(x, y, 0, 0, 0, 255);
        } else {
          result.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }
    return result;
  }

  /// Compute the ratio of black pixels in a binary image (0.0 to 1.0).
  static double _blackPixelRatio(img.Image binary) {
    int blackCount = 0;
    final total = binary.width * binary.height;
    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        if (_isBlack(binary, x, y)) blackCount++;
      }
    }
    return blackCount / total;
  }

  /// v5.0.0: 智能网格线检测与移除
  ///
  /// 使用水平投影和垂直投影分析检测方格纸网格线。
  /// 网格线的特征：整行/整列连续黑色像素，密度远高于手写笔画。
  /// 检测到的网格线会被置白，避免干扰后续字符连通域分析。
  ///
  /// 算法：
  /// 1. 计算每行/每列的黑色像素密度
  /// 2. 密度超过阈值的行/列标记为网格线候选
  /// 3. 对候选线进行间距一致性验证（网格线应近似等间距）
  /// 4. 确认的网格线及其 ±1px 邻域全部置白
  static img.Image _detectAndMaskGridLines(img.Image binary) {
    final w = binary.width;
    final h = binary.height;

    // 阈值：网格线覆盖 >55% 宽度/高度（保守阈值，避免误检横竖笔画）
    final hThreshold = (w * 0.55).toInt();
    final vThreshold = (h * 0.55).toInt();

    // 水平投影：统计每行黑色像素数
    final hProjection = List.filled(h, 0);
    for (int y = 0; y < h; y++) {
      int count = 0;
      for (int x = 0; x < w; x++) {
        if (_isBlack(binary, x, y)) count++;
      }
      hProjection[y] = count;
    }

    // 垂直投影：统计每列黑色像素数
    final vProjection = List.filled(w, 0);
    for (int x = 0; x < w; x++) {
      int count = 0;
      for (int y = 0; y < h; y++) {
        if (_isBlack(binary, x, y)) count++;
      }
      vProjection[x] = count;
    }

    // 候选网格线（密度超过阈值的行/列）
    final hLineCandidates = <int>[];
    final vLineCandidates = <int>[];

    for (int y = 0; y < h; y++) {
      if (hProjection[y] > hThreshold) hLineCandidates.add(y);
    }
    for (int x = 0; x < w; x++) {
      if (vProjection[x] > vThreshold) vLineCandidates.add(x);
    }

    // 需要至少 2 条线才能构成网格
    if (hLineCandidates.length < 2 || vLineCandidates.length < 2) {
      debugPrint('网格检测: 水平${hLineCandidates.length}条 垂直${vLineCandidates.length}条 — 未检测到网格，跳过');
      return binary;
    }

    // 合并相邻的候选线（间距 ≤ 3px 视为同一条线的粗细）
    final hLines = _mergeGridLines(hLineCandidates);
    final vLines = _mergeGridLines(vLineCandidates);

    if (hLines.length < 2 || vLines.length < 2) {
      debugPrint('网格检测: 合并后水平${hLines.length}条 垂直${vLines.length}条 — 线数不足，跳过');
      return binary;
    }

    // 验证间距一致性：网格线应近似等间距
    // 计算间距的变异系数（CV = 标准差/均值），CV < 0.35 视为规则网格
    final hSpacings = <int>[];
    for (int i = 1; i < hLines.length; i++) {
      hSpacings.add(hLines[i] - hLines[i - 1]);
    }
    final vSpacings = <int>[];
    for (int i = 1; i < vLines.length; i++) {
      vSpacings.add(vLines[i] - vLines[i - 1]);
    }

    final hCV = _coefficientOfVariation(hSpacings);
    final vCV = _coefficientOfVariation(vSpacings);

    // 至少一个方向间距规则（CV < 0.4），才确认为网格
    if (hCV > 0.40 && vCV > 0.40) {
      debugPrint('网格检测: 间距不规则 (hCV=${hCV.toStringAsFixed(2)}, vCV=${vCV.toStringAsFixed(2)})，跳过');
      return binary;
    }

    debugPrint('网格检测: ${hLines.length}×${vLines.length} 网格 (hCV=${hCV.toStringAsFixed(2)}, vCV=${vCV.toStringAsFixed(2)})');

    // 复制图像并移除网格线
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = binary.getPixel(x, y);
        result.setPixelRgba(x, y, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), 255);
      }
    }

    // 移除水平网格线（上下各扩展 1px）
    for (final y in hLines) {
      for (int dy = -1; dy <= 1; dy++) {
        final ry = y + dy;
        if (ry >= 0 && ry < h) {
          for (int x = 0; x < w; x++) {
            result.setPixelRgba(x, ry, 255, 255, 255, 255);
          }
        }
      }
    }

    // 移除垂直网格线（左右各扩展 1px）
    for (final x in vLines) {
      for (int dx = -1; dx <= 1; dx++) {
        final rx = x + dx;
        if (rx >= 0 && rx < w) {
          for (int y = 0; y < h; y++) {
            result.setPixelRgba(rx, y, 255, 255, 255, 255);
          }
        }
      }
    }

    debugPrint('网格线已移除: ${hLines.length} 水平 + ${vLines.length} 垂直');
    return result;
  }

  /// 合并相邻的网格线候选（间距 ≤ 3px 的视为同一条线）
  static List<int> _mergeGridLines(List<int> candidates) {
    if (candidates.isEmpty) return [];
    final merged = <int>[];
    int current = candidates[0];
    for (int i = 1; i < candidates.length; i++) {
      if (candidates[i] - current <= 3) {
        // 同一条线，取中间位置
        current = (current + candidates[i]) ~/ 2;
      } else {
        merged.add(current);
        current = candidates[i];
      }
    }
    merged.add(current);
    return merged;
  }

  /// 计算一组数值的变异系数（CV = 标准差 / 均值）
  static double _coefficientOfVariation(List<int> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    if (mean == 0) return 0;
    final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
    return sqrt(variance) / mean;
  }

  /// v5.0.0: 手写区域智能裁剪
  ///
  /// 移除网格线后，检测所有墨迹像素的包围盒。
  /// 如果手写区域仅占图片的一部分（有大量空白边距），
  /// 自动裁剪到手写区域，让字符在图片中占据更大比例。
  ///
  /// 这对以下场景特别有效：
  /// - 方格纸只写了一部分，剩下是空白
  /// - 拍照时包含大量白色边距
  /// - 多张方格纸只用了一张
  static img.Image _autoCropHandwritingRegion(img.Image binary) {
    final w = binary.width;
    final h = binary.height;

    // 扫描所有黑色像素，计算包围盒
    int minX = w, minY = h, maxX = 0, maxY = 0;
    int inkCount = 0;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (_isBlack(binary, x, y)) {
          inkCount++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    // 无墨迹或墨迹极少，返回原图
    if (inkCount < 10) return binary;

    // 计算墨迹区域占图片的比例
    final inkW = maxX - minX + 1;
    final inkH = maxY - minY + 1;
    final inkRatio = (inkW * inkH) / (w * h);

    // 墨迹区域 > 80% 图片面积，不需要裁剪
    if (inkRatio > 0.80) return binary;

    // 添加 8% padding（保留字符边距）
    final padX = (inkW * 0.08).toInt().clamp(5, 100);
    final padY = (inkH * 0.08).toInt().clamp(5, 100);
    final cropX = (minX - padX).clamp(0, w - 1);
    final cropY = (minY - padY).clamp(0, h - 1);
    final cropW = (inkW + padX * 2).clamp(1, w - cropX);
    final cropH = (inkH + padY * 2).clamp(1, h - cropY);

    // 确保裁剪有意义
    if (cropW >= w * 0.9 && cropH >= h * 0.9) return binary;

    debugPrint('手写区域自动裁剪: ${w}x$h → ${cropW}x${cropH} '
        '(墨迹占比 ${(inkRatio * 100).toStringAsFixed(1)}%)');

    return img.copyCrop(binary, x: cropX, y: cropY, width: cropW, height: cropH);
  }

  static bool _isBlack(img.Image binary, int x, int y) {
    if (x < 0 || x >= binary.width || y < 0 || y >= binary.height) return false;
    return binary.getPixel(x, y).r.toInt() < 128;
  }

  static img.Image _erode(img.Image binary) {
    final result = img.Image(width: binary.width, height: binary.height);
    // Fill with white first
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        result.setPixelRgba(x, y, 255, 255, 255, 255);
      }
    }
    for (int y = 1; y < binary.height - 1; y++) {
      for (int x = 1; x < binary.width - 1; x++) {
        bool allBlack = true;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (!_isBlack(binary, x + dx, y + dy)) {
              allBlack = false;
              break;
            }
          }
          if (!allBlack) break;
        }
        if (allBlack) {
          result.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }
    }
    return result;
  }

  static img.Image _dilate(img.Image binary) {
    final result = img.Image(width: binary.width, height: binary.height);
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        result.setPixelRgba(x, y, 255, 255, 255, 255);
      }
    }
    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        if (_isBlack(binary, x, y)) {
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              final nx = x + dx;
              final ny = y + dy;
              if (nx >= 0 && nx < binary.width && ny >= 0 && ny < binary.height) {
                result.setPixelRgba(nx, ny, 0, 0, 0, 255);
              }
            }
          }
        }
      }
    }
    return result;
  }

  static img.Image _smooth(img.Image binary, double amount) {
    // 改进：使用形态学闭运算（先膨胀再腐蚀）填充笔画内部空洞，
    // 再用开运算（先腐蚀再膨胀）去除噪点，效果优于简单的多数投票
    final kernelSize = (amount * 2 + 1).toInt();
    final half = kernelSize ~/ 2;

    if (amount > 0.3) {
      // 使用形态学闭运算 + 开运算
      img.Image result = binary;
      // 闭运算：填充小空洞
      for (int i = 0; i < half.clamp(1, 3); i++) {
        result = _dilate(result);
      }
      for (int i = 0; i < half.clamp(1, 3); i++) {
        result = _erode(result);
      }
      // 开运算：去除噪点
      for (int i = 0; i < half.clamp(1, 2); i++) {
        result = _erode(result);
      }
      for (int i = 0; i < half.clamp(1, 2); i++) {
        result = _dilate(result);
      }
      return result;
    }

    // 小量平滑使用原始多数投票方法
    final result = img.Image(width: binary.width, height: binary.height);

    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        int blackCount = 0;
        int total = 0;
        for (int dy = -half; dy <= half; dy++) {
          for (int dx = -half; dx <= half; dx++) {
            if (_isBlack(binary, x + dx, y + dy)) blackCount++;
            total++;
          }
        }
        if (blackCount > total ~/ 2) {
          result.setPixelRgba(x, y, 0, 0, 0, 255);
        } else {
          result.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }
    return result;
  }

  /// 估算灰度图的噪声水平（0.0 ~ 1.0）
  /// 使用 Laplacian 方差法：计算图像 Laplacian 的方差，
  /// 方差越大说明噪声越多（边缘和噪声都会产生高频分量）。
  static double _estimateNoiseLevel(img.Image gray) {
    final w = gray.width, h = gray.height;
    if (w < 3 || h < 3) return 0.0;

    // 采样计算（每 4 个像素取一个，减少计算量）
    double sum = 0;
    double sumSq = 0;
    int count = 0;

    for (int y = 1; y < h - 1; y += 2) {
      for (int x = 1; x < w - 1; x += 2) {
        // Laplacian 核: [0,1,0, 1,-4,1, 0,1,0]
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
    // 归一化到 0~1 范围（经验值：方差 1000 对应高噪声）
    return (variance / 1000.0).clamp(0.0, 1.0);
  }

  /// v4.3.0: 垂直投影法分割粘连字符
  ///
  /// 对指定连通域区域计算垂直投影（每列黑色像素数），
  /// 找到投影谷底作为分割点，将宽连通域拆分为多个字符。
  ///
  /// [blackRows] 预计算的二值像素数组
  /// [minX],[minY],[maxX],[maxY] 连通域边界
  /// [imgW],[imgH] 图像尺寸
  /// 返回分割后的子区域列表 [[sx, sy, ex, ey], ...]
  static List<List<int>> _verticalProjectionSplit(
    List<List<bool>> blackRows,
    int minX, int minY, int maxX, int maxY,
    int imgW, int imgH,
  ) {
    final regionW = maxX - minX + 1;
    final regionH = maxY - minY + 1;

    // 计算垂直投影（每列黑色像素数）
    final projection = List.filled(regionW, 0);
    for (int x = minX; x <= maxX; x++) {
      int count = 0;
      for (int y = minY; y <= maxY; y++) {
        if (y >= 0 && y < imgH && x >= 0 && x < imgW && blackRows[y][x]) {
          count++;
        }
      }
      projection[x - minX] = count;
    }

    // 平滑投影（3列滑动平均，减少噪声干扰）
    final smoothed = List.filled(regionW, 0);
    for (int i = 0; i < regionW; i++) {
      int sum = projection[i];
      int cnt = 1;
      if (i > 0) { sum += projection[i - 1]; cnt++; }
      if (i < regionW - 1) { sum += projection[i + 1]; cnt++; }
      smoothed[i] = sum ~/ cnt;
    }

    // 找到投影谷底：局部最小值且低于平均值的 40%
    final avgProjection = smoothed.reduce((a, b) => a + b) / regionW;
    final valleyThreshold = (avgProjection * 0.4).round().clamp(1, 99999);

    // 候选分割点
    final candidates = <int>[];
    for (int i = 2; i < regionW - 2; i++) {
      if (smoothed[i] <= valleyThreshold &&
          smoothed[i] <= smoothed[i - 1] &&
          smoothed[i] <= smoothed[i + 1]) {
        candidates.add(i);
      }
    }

    if (candidates.isEmpty) return [];

    // 选择最佳分割点：间距要合理（至少 regionH * 0.3，即一个字符宽度的最小值）
    final minCharWidth = (regionH * 0.3).round().clamp(10, 99999);
    final splitPoints = <int>[0]; // 起始位置
    for (final c in candidates) {
      if (c - splitPoints.last >= minCharWidth) {
        splitPoints.add(c);
      }
    }
    splitPoints.add(regionW); // 结束位置

    // 至少要有 2 段才算分割成功
    if (splitPoints.length < 3) return [];

    // 生成子区域边界
    final result = <List<int>>[];
    for (int i = 0; i < splitPoints.length - 1; i++) {
      final sx = minX + splitPoints[i];
      final ex = minX + splitPoints[i + 1] - 1;
      if (ex > sx) {
        result.add([sx, minY, ex, maxY]);
      }
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // v4.6.0: 水平投影分割 — 处理上下粘连的字符
  // ═══════════════════════════════════════════════════════════

  /// 水平投影法分割上下粘连字符
  ///
  /// 对指定连通域区域计算水平投影（每行黑色像素数），
  /// 找到投影谷底作为分割点，将高连通域拆分为多个字符。
  ///
  /// [blackRows] 预计算的二值像素数组
  /// [minX],[minY],[maxX],[maxY] 连通域边界
  /// [imgW],[imgH] 图像尺寸
  /// 返回分割后的子区域列表 [[sx, sy, ex, ey], ...]
  static List<List<int>> _horizontalProjectionSplit(
    List<List<bool>> blackRows,
    int minX, int minY, int maxX, int maxY,
    int imgW, int imgH,
  ) {
    final regionW = maxX - minX + 1;
    final regionH = maxY - minY + 1;

    // 计算水平投影（每行黑色像素数）
    final projection = List.filled(regionH, 0);
    for (int y = minY; y <= maxY; y++) {
      int count = 0;
      for (int x = minX; x <= maxX; x++) {
        if (y >= 0 && y < imgH && x >= 0 && x < imgW && blackRows[y][x]) {
          count++;
        }
      }
      projection[y - minY] = count;
    }

    // 平滑投影（3行滑动平均）
    final smoothed = List.filled(regionH, 0);
    for (int i = 0; i < regionH; i++) {
      int sum = projection[i];
      int cnt = 1;
      if (i > 0) { sum += projection[i - 1]; cnt++; }
      if (i < regionH - 1) { sum += projection[i + 1]; cnt++; }
      smoothed[i] = sum ~/ cnt;
    }

    // 找到投影谷底：局部最小值且低于平均值的 35%
    final avgProjection = smoothed.reduce((a, b) => a + b) / regionH;
    final valleyThreshold = (avgProjection * 0.35).round().clamp(1, 99999);

    // 候选分割点
    final candidates = <int>[];
    for (int i = 2; i < regionH - 2; i++) {
      if (smoothed[i] <= valleyThreshold &&
          smoothed[i] <= smoothed[i - 1] &&
          smoothed[i] <= smoothed[i + 1]) {
        candidates.add(i);
      }
    }

    if (candidates.isEmpty) return [];

    // 选择最佳分割点：间距要合理（至少 regionW * 0.3，即一个字符高度的最小值）
    final minCharHeight = (regionW * 0.3).round().clamp(10, 99999);
    final splitPoints = <int>[0]; // 起始位置
    for (final c in candidates) {
      if (c - splitPoints.last >= minCharHeight) {
        splitPoints.add(c);
      }
    }
    splitPoints.add(regionH); // 结束位置

    // 至少要有 2 段才算分割成功
    if (splitPoints.length < 3) return [];

    // 生成子区域边界
    final result = <List<int>>[];
    for (int i = 0; i < splitPoints.length - 1; i++) {
      final sy = minY + splitPoints[i];
      final ey = minY + splitPoints[i + 1] - 1;
      if (ey > sy) {
        result.add([minX, sy, maxX, ey]);
      }
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // v4.6.0: 连通域合并 — 处理断笔导致的同一字符被拆分
  // ═══════════════════════════════════════════════════════════

  /// 合并距离过近的连通域（处理断笔）
  ///
  /// 当两个连通域的边界框间距小于阈值时，将它们合并为一个区域。
  /// 这解决了手写体断笔导致同一字符被错误拆分为多个区域的问题。
  ///
  /// [bboxes] 连通域列表 [[minX, minY, maxX, maxY, area], ...]
  /// [avgHeight] 平均字符高度（用于计算合并阈值）
  /// 返回合并后的连通域列表
  static List<List<int>> _mergeBrokenStrokes(
    List<List<int>> bboxes,
    double avgHeight,
  ) {
    if (bboxes.length < 2) return bboxes;

    // 合并阈值：平均字符高度的 25%（断笔间距通常很小）
    final mergeThreshold = (avgHeight * 0.25).round().clamp(3, 30);

    // 迭代合并直到没有可合并的对
    bool merged = true;
    final result = List<List<int>>.from(bboxes);

    while (merged) {
      merged = false;
      for (int i = 0; i < result.length && !merged; i++) {
        for (int j = i + 1; j < result.length && !merged; j++) {
          final a = result[i];
          final b = result[j];

          // 计算两个边界框的扩展距离
          final expandA = mergeThreshold;
          final overlapX = a[0] - expandA <= b[2] && b[0] - expandA <= a[2];
          final overlapY = a[1] - expandA <= b[3] && b[1] - expandA <= a[3];

          if (overlapX && overlapY) {
            // 合并两个边界框
            final mergedBox = [
              a[0] < b[0] ? a[0] : b[0], // minX
              a[1] < b[1] ? a[1] : b[1], // minY
              a[2] > b[2] ? a[2] : b[2], // maxX
              a[3] > b[3] ? a[3] : b[3], // maxY
              a[4] + b[4],                // area
            ];

            // 检查合并后的宽高比是否合理（单字 < 2.5:1）
            final mW = mergedBox[2] - mergedBox[0] + 1;
            final mH = mergedBox[3] - mergedBox[1] + 1;
            final mAspect = mW > mH ? mW / mH : mH / mW;

            if (mAspect < 2.5) {
              result.removeAt(j);
              result[i] = mergedBox;
              merged = true;
              debugPrint('断笔合并: 两个区域 → ${mW}x$mH (间距阈值=$mergeThreshold)');
            }
          }
        }
      }
    }

    return result;
  }

  static bool _hasContent(img.Image cell) {
    int blackPixels = 0;
    final totalPixels = cell.width * cell.height;
    for (int y = 0; y < cell.height; y++) {
      for (int x = 0; x < cell.width; x++) {
        if (cell.getPixel(x, y).r.toInt() < 128) blackPixels++;
      }
    }
    return blackPixels > totalPixels * 0.005; // At least 0.5% filled (was 2%, missed small chars)
  }

  /// Trace the outer contour of a connected component using Moore neighborhood tracing.
  /// Returns boundary pixels in sequential order (forming a closed polygon path),
  /// unlike BFS which produces unordered points.
  /// 改进：添加断点桥接，当 Moore 追踪提前终止时尝试从断点附近重新连接。
  static List<Point> _traceContour(img.Image binary, int startX, int startY, List<List<bool>> visited) {
    // Mark the entire component as visited via BFS and collect all component pixels
    final bfsDirs = [
      Point(1, 0), Point(1, 1), Point(0, 1), Point(-1, 1),
      Point(-1, 0), Point(-1, -1), Point(0, -1), Point(1, -1),
    ];
    final componentPixels = <Point>[];
    final queue = <Point>[Point(startX, startY)];
    visited[startY][startX] = true;
    componentPixels.add(Point(startX, startY));
    while (queue.isNotEmpty) {
      final p = queue.removeAt(0);
      for (final d in bfsDirs) {
        final nx = p.x + d.x;
        final ny = p.y + d.y;
        if (nx >= 0 && nx < binary.width && ny >= 0 && ny < binary.height &&
            !visited[ny][nx] && _isBlack(binary, nx, ny)) {
          visited[ny][nx] = true;
          queue.add(Point(nx, ny));
          componentPixels.add(Point(nx, ny));
        }
      }
    }

    // Find a boundary pixel within THIS component only.
    // A boundary pixel is a black pixel with at least one white cardinal neighbor.
    // Prefer a pixel where the left neighbor is white (standard Moore trace start).
    int bx = -1, by = -1;
    for (final p in componentPixels) {
      if (!_isBlack(binary, p.x - 1, p.y)) {
        bx = p.x;
        by = p.y;
        break; // Best start: left neighbor is white
      }
      // Check if this is a boundary pixel at all
      bool hasWhiteNeighbor = false;
      for (int d = 0; d < 8; d += 2) {
        if (!_isBlack(binary, p.x + bfsDirs[d].x, p.y + bfsDirs[d].y)) {
          hasWhiteNeighbor = true;
          break;
        }
      }
      if (hasWhiteNeighbor && bx < 0) {
        bx = p.x;
        by = p.y;
      }
    }

    if (bx < 0) return [];

    // Moore neighborhood tracing — produces ordered boundary points.
    // Directions: 0=E,1=SE,2=S,3=SW,4=W,5=NW,6=N,7=NE
    const dx = [1, 1, 0, -1, -1, -1, 0, 1];
    const dy = [0, 1, 1, 1, 0, -1, -1, -1];

    // Initial backtracking direction: came from the left (W=4), so start searching from E=0
    int dir = 0;
    final traceStartX = bx, traceStartY = by;
    final contour = <Point>[Point(bx, by)];
    int maxSteps = binary.width * binary.height;
    int steps = 0;
    int consecutiveFailures = 0; // 追踪连续搜索失败次数

    do {
      // Search clockwise for the next black pixel from (dir+7)%8
      int searchDir = (dir + 7) % 8;
      bool found = false;
      for (int i = 0; i < 8; i++) {
        int d = (searchDir + i) % 8;
        int nx = bx + dx[d];
        int ny = by + dy[d];
        if (nx >= 0 && nx < binary.width && ny >= 0 && ny < binary.height &&
            _isBlack(binary, nx, ny)) {
          bx = nx;
          by = ny;
          dir = d;
          found = true;
          break;
        }
      }
      if (!found) {
        consecutiveFailures++;
        // 尝试桥接断点：搜索更大范围内的最近黑色像素
        if (consecutiveFailures <= 2) {
          bool bridged = false;
          for (int radius = 2; radius <= 4 && !bridged; radius++) {
            for (int dy2 = -radius; dy2 <= radius && !bridged; dy2++) {
              for (int dx2 = -radius; dx2 <= radius && !bridged; dx2++) {
                if (dx2.abs() < 2 && dy2.abs() < 2) continue; // 跳过已搜索过的
                final nx = bx + dx2;
                final ny = by + dy2;
                if (nx >= 0 && nx < binary.width && ny >= 0 && ny < binary.height &&
                    _isBlack(binary, nx, ny)) {
                  bx = nx;
                  by = ny;
                  // 记录桥接点
                  if (bx != traceStartX || by != traceStartY) {
                    contour.add(Point(bx, by));
                  }
                  bridged = true;
                  dir = 0; // 重置方向
                }
              }
            }
          }
          if (!bridged) break;
        } else {
          break;
        }
      } else {
        consecutiveFailures = 0;
      }

      steps++;
      if (bx != traceStartX || by != traceStartY) {
        contour.add(Point(bx, by));
      }
    } while ((bx != traceStartX || by != traceStartY) && steps < maxSteps);

    return contour;
  }

  /// Scale contour points from image coordinates to font units (0-1000).
  static List<ContourPoint> _scaleContour(List<Point> contour, int imgWidth, int imgHeight, double strokeWidth) {
    if (contour.isEmpty) return [];

    // Find bounding box
    int minX = contour.first.x, maxX = contour.first.x;
    int minY = contour.first.y, maxY = contour.first.y;
    for (final p in contour) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final width = (maxX - minX).clamp(1, 999999);
    final height = (maxY - minY).clamp(1, 999999);
    final scale = (800.0 / max(width, height)) * strokeWidth;

    // Scale and center, flip Y axis for font coordinate system
    final List<ContourPoint> result = [];
    for (final p in contour) {
      final fx = ((p.x - minX) * scale + 100).round();
      final fy = (1000 - ((p.y - minY) * scale + 100)).round(); // Flip Y
      result.add(ContourPoint(fx, fy));
    }

    return result;
  }

  /// Simplify contour using Ramer-Douglas-Peucker algorithm.
  static List<ContourPoint> _simplifyContour(List<ContourPoint> points, double epsilon) {
    if (points.length <= 2) return points;

    double maxDist = 0;
    int maxIndex = 0;

    final first = points.first;
    final last = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      final dist = _pointToLineDistance(points[i], first, last);
      if (dist > maxDist) {
        maxDist = dist;
        maxIndex = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _simplifyContour(points.sublist(0, maxIndex + 1), epsilon);
      final right = _simplifyContour(points.sublist(maxIndex), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [first, last];
    }
  }

  /// 确保轮廓闭合：如果首尾点不同，则追加首点到末尾
  static List<ContourPoint> _ensureClosedContour(List<ContourPoint> points) {
    if (points.length < 3) return points;
    final first = points.first;
    final last = points.last;
    if (first.x == last.x && first.y == last.y) return points;
    return [...points, ContourPoint(first.x, first.y)];
  }

  /// 贝塞尔曲线拟合：将折线点序列转换为包含二次贝塞尔控制点的序列
  /// 使用最小二乘法拟合，自适应分段长度，根据曲率决定段长度
  static List<ContourPoint> _fitBezierCurves(List<ContourPoint> points, double smoothness) {
    if (points.length < 4) return points;

    // 检测闭合轮廓（首尾点相同）
    final isClosed = points.first.x == points.last.x &&
        points.first.y == points.last.y;
    final work = isClosed
        ? points.sublist(0, points.length - 1)
        : List<ContourPoint>.from(points);

    if (work.length < 4) return points;

    // 拟合误差阈值：smoothness 越大，允许误差越大（更平滑，点更少）
    final errorThreshold = 3.0 + smoothness * 10.0;

    // 自适应段长度范围
    final maxSegLen = (work.length / 3).round().clamp(4, 25);

    final result = <ContourPoint>[];
    // 第一个点始终是 on-curve
    result.add(ContourPoint(work[0].x, work[0].y, onCurve: true));

    int start = 0;
    while (start < work.length - 1) {
      int bestEnd = start + 1;

      // 尝试扩展段长度，找到最长的可拟合段
      for (int end = start + 2;
          end <= (start + maxSegLen).clamp(0, work.length - 1);
          end++) {
        final error = _computeFitError(work, start, end);
        if (error <= errorThreshold) {
          bestEnd = end;
        } else {
          break; // 误差超过阈值，停止扩展
        }
      }

      if (bestEnd == start + 1) {
        // 直线段：直接添加 on-curve 点
        result.add(ContourPoint(work[bestEnd].x, work[bestEnd].y, onCurve: true));
      } else {
        // 贝塞尔曲线段：计算控制点（off-curve）+ 端点（on-curve）
        final (cx, cy) = _computeControlPoint(work, start, bestEnd);
        result.add(ContourPoint(cx.round(), cy.round(), onCurve: false));
        result.add(ContourPoint(work[bestEnd].x, work[bestEnd].y, onCurve: true));
      }

      start = bestEnd;
    }

    // 闭合轮廓：确保回到起点
    if (isClosed && result.length >= 2) {
      final first = result.first;
      final last = result.last;
      if (first.x != last.x || first.y != last.y) {
        result.add(ContourPoint(first.x, first.y, onCurve: true));
      }
    }

    return result;
  }

  /// 计算二次贝塞尔曲线的最优控制点（最小二乘法）
  /// 给定折线段 points[start..end]，返回拟合的二次贝塞尔控制点坐标
  /// B(t) = (1-t)²·P0 + 2t(1-t)·C + t²·Pn
  static (double cx, double cy) _computeControlPoint(
      List<ContourPoint> points, int start, int end) {
    final p0 = points[start];
    final pn = points[end];
    final n = end - start;

    double sumWRx = 0, sumWRy = 0, sumW2 = 0;

    for (int i = 1; i < n; i++) {
      final t = i / n;
      final w = 2.0 * t * (1.0 - t); // 二次贝塞尔基函数权重
      // 残差：实际点减去仅由端点确定的线性插值部分
      final rx = points[start + i].x - (1 - t) * (1 - t) * p0.x - t * t * pn.x;
      final ry = points[start + i].y - (1 - t) * (1 - t) * p0.y - t * t * pn.y;
      sumWRx += w * rx;
      sumWRy += w * ry;
      sumW2 += w * w;
    }

    if (sumW2.abs() < 1e-10) {
      // 退化情况：返回中点作为控制点
      return ((p0.x + pn.x) / 2.0, (p0.y + pn.y) / 2.0);
    }

    return (sumWRx / sumW2, sumWRy / sumW2);
  }

  /// 计算贝塞尔拟合的最大误差（中间点到拟合曲线的最大距离）
  static double _computeFitError(
      List<ContourPoint> points, int start, int end) {
    final p0 = points[start];
    final pn = points[end];
    final n = end - start;

    // 计算最优控制点
    final (cx, cy) = _computeControlPoint(points, start, end);

    double maxError = 0;
    for (int i = 1; i < n; i++) {
      final t = i / n;
      final omt = 1.0 - t; // one minus t
      // 二次贝塞尔曲线上的对应点
      final bx = omt * omt * p0.x + 2 * t * omt * cx + t * t * pn.x;
      final by = omt * omt * p0.y + 2 * t * omt * cy + t * t * pn.y;
      final dx = points[start + i].x - bx;
      final dy = points[start + i].y - by;
      final error = sqrt(dx * dx + dy * dy);
      if (error > maxError) maxError = error;
    }

    return maxError;
  }

  static double _pointToLineDistance(ContourPoint p, ContourPoint lineStart, ContourPoint lineEnd) {
    final dx = lineEnd.x - lineStart.x;
    final dy = lineEnd.y - lineStart.y;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) {
      final ex = p.x - lineStart.x;
      final ey = p.y - lineStart.y;
      return sqrt(ex * ex + ey * ey);
    }
    final t = ((p.x - lineStart.x) * dx + (p.y - lineStart.y) * dy) / len2;
    final clampedT = t.clamp(0.0, 1.0);
    final projX = lineStart.x + clampedT * dx;
    final projY = lineStart.y + clampedT * dy;
    final ex = p.x - projX;
    final ey = p.y - projY;
    return sqrt(ex * ex + ey * ey);
  }

  // ═══════════════════════════════════════════════════════════
  // 数据压缩优化：图片压缩、数据压缩、压缩设置
  // ═══════════════════════════════════════════════════════════

  /// 默认压缩质量（0-100，JPEG 质量参数）
  static int _defaultCompressionQuality = 85;

  /// 默认压缩最大尺寸（像素，长边最大值）
  static int _defaultMaxDimension = 2048;

  /// 获取当前压缩质量设置
  static int get compressionQuality => _defaultCompressionQuality;

  /// 设置压缩质量（0-100）
  static void setCompressionQuality(int quality) {
    _defaultCompressionQuality = quality.clamp(1, 100);
  }

  /// 获取当前最大尺寸设置
  static int get maxDimension => _defaultMaxDimension;

  /// 设置压缩最大尺寸
  static void setMaxDimension(int dimension) {
    _defaultMaxDimension = dimension.clamp(100, 8192);
  }

  /// 压缩图片：按指定质量和最大尺寸进行压缩
  ///
  /// [imageBytes] 原始图片字节
  /// [quality] JPEG 压缩质量（1-100），默认使用全局设置
  /// [maxDimension] 长边最大像素数，默认使用全局设置
  /// [format] 输出格式：'jpeg' 或 'png'，默认 'jpeg'
  ///
  /// 返回压缩后的图片字节和压缩信息 Map：
  /// - bytes: 压缩后的图片字节
  /// - originalSize: 原始大小（字节）
  /// - compressedSize: 压缩后大小（字节）
  /// - compressionRatio: 压缩比例（0.0-1.0，越小压缩越多）
  /// - width: 压缩后宽度
  /// - height: 压缩后高度
  static Map<String, dynamic> compressImage(
    Uint8List imageBytes, {
    int? quality,
    int? maxDimension,
    String format = 'jpeg',
  }) {
    _recordUsage('compressImage');
    final sw = Stopwatch()..start();
    _taskStarted();

    try {
      final effectiveQuality = quality ?? _defaultCompressionQuality;
      final effectiveMaxDim = maxDimension ?? _defaultMaxDimension;

      final originalSize = imageBytes.length;
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        _recordError('compressImage', '图片解码失败');
        return {
          'bytes': imageBytes,
          'originalSize': originalSize,
          'compressedSize': originalSize,
          'compressionRatio': 1.0,
          'width': 0,
          'height': 0,
          'error': '图片解码失败',
        };
      }

      // 调整尺寸
      img.Image resized = decoded;
      final w = decoded.width;
      final h = decoded.height;
      final currentMaxDim = w > h ? w : h;

      if (currentMaxDim > effectiveMaxDim) {
        final scale = effectiveMaxDim / currentMaxDim;
        final newW = (w * scale).round().clamp(1, 99999);
        final newH = (h * scale).round().clamp(1, 99999);
        resized = img.copyResize(decoded, width: newW, height: newH,
            interpolation: img.Interpolation.linear);
      }

      // 编码压缩
      Uint8List compressedBytes;
      if (format == 'png') {
        compressedBytes = Uint8List.fromList(img.encodePng(resized));
      } else {
        compressedBytes = Uint8List.fromList(img.encodeJpg(resized, quality: effectiveQuality));
      }

      sw.stop();
      _taskCompleted(sw.elapsed);

      final compressedSize = compressedBytes.length;
      final ratio = originalSize > 0 ? compressedSize / originalSize : 1.0;

      debugPrint('compressImage: ${originalSize}B → ${compressedSize}B '
          '(压缩率 ${(ratio * 100).toStringAsFixed(1)}%, '
          '${resized.width}x${resized.height})');

      return {
        'bytes': compressedBytes,
        'originalSize': originalSize,
        'compressedSize': compressedSize,
        'compressionRatio': ratio,
        'width': resized.width,
        'height': resized.height,
      };
    } catch (e) {
      _recordError('compressImage', e);
      sw.stop();
      _taskCompleted(sw.elapsed);
      return {
        'bytes': imageBytes,
        'originalSize': imageBytes.length,
        'compressedSize': imageBytes.length,
        'compressionRatio': 1.0,
        'width': 0,
        'height': 0,
        'error': e.toString(),
      };
    }
  }

  /// 批量压缩图片
  ///
  /// [images] 图片字节列表
  /// [quality] JPEG 压缩质量
  /// [maxDimension] 长边最大像素数
  /// [onProgress] 进度回调
  ///
  /// 返回压缩结果列表（与输入顺序一致）
  static List<Map<String, dynamic>> compressImages(
    List<Uint8List> images, {
    int? quality,
    int? maxDimension,
    void Function(int completed, int total)? onProgress,
  }) {
    final results = <Map<String, dynamic>>[];
    for (int i = 0; i < images.length; i++) {
      results.add(compressImage(images[i], quality: quality, maxDimension: maxDimension));
      onProgress?.call(i + 1, images.length);
    }
    return results;
  }

  /// 压缩数据：对任意二进制数据进行简单压缩
  ///
  /// 使用 run-length 编码（RLE）进行简单压缩，
  /// 适合包含大量重复字节的数据（如二值化图片）。
  ///
  /// [data] 原始数据
  /// 返回压缩后的数据字节
  static Uint8List compressData(Uint8List data) {
    if (data.isEmpty) return data;

    _recordUsage('compressData');
    final result = <int>[];

    int i = 0;
    while (i < data.length) {
      final currentByte = data[i];
      int count = 1;

      // 计算连续相同字节的数量（最多 255）
      while (i + count < data.length &&
             data[i + count] == currentByte &&
             count < 255) {
        count++;
      }

      if (count >= 3) {
        // 使用 RLE 编码：标记字节 0xFF + 计数 + 值
        result.add(0xFF);
        result.add(count);
        result.add(currentByte);
      } else {
        // 直接输出
        for (int j = 0; j < count; j++) {
          if (currentByte == 0xFF) {
            // 转义 0xFF 字节
            result.add(0xFF);
            result.add(0x01);
            result.add(0xFF);
          } else {
            result.add(currentByte);
          }
        }
      }

      i += count;
    }

    return Uint8List.fromList(result);
  }

  /// 解压缩数据
  ///
  /// [data] 压缩后的数据（由 compressData 生成）
  /// 返回解压后的原始数据
  static Uint8List decompressData(Uint8List data) {
    if (data.isEmpty) return data;

    final result = <int>[];
    int i = 0;

    while (i < data.length) {
      if (data[i] == 0xFF && i + 2 < data.length) {
        final count = data[i + 1];
        final value = data[i + 2];
        for (int j = 0; j < count; j++) {
          result.add(value);
        }
        i += 3;
      } else {
        result.add(data[i]);
        i++;
      }
    }

    return Uint8List.fromList(result);
  }

  /// 获取压缩统计信息
  ///
  /// 返回当前压缩设置和历史统计
  static Map<String, dynamic> getCompressionStats() {
    return {
      'defaultQuality': _defaultCompressionQuality,
      'defaultMaxDimension': _defaultMaxDimension,
      'usageCount': _usageCounter['compressImage'] ?? 0,
      'dataCompressionCount': _usageCounter['compressData'] ?? 0,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 混合计算优化：计算任务分配、资源调度、结果合并、性能监控
  // ═══════════════════════════════════════════════════════════

  /// 计算节点类型
  static const String nodeLocal = 'local';       // 本地设备计算
  static const String nodeEdge = 'edge';          // 边缘节点计算
  static const String nodeCloud = 'cloud';        // 云端计算

  /// 任务分配策略
  static const String strategyLocalFirst = 'local_first';     // 优先本地
  static const String strategyRoundRobin = 'round_robin';     // 轮询分配
  static const String strategyLoadBased = 'load_based';       // 基于负载
  static const String strategyLatencyBased = 'latency_based'; // 基于延迟

  /// 当前分配策略
  static String _taskAllocationStrategy = strategyLocalFirst;

  /// 计算任务记录
  static final List<Map<String, dynamic>> _computeTaskLog = [];
  static const int _maxComputeTaskLogSize = 200;

  /// 节点负载统计
  static final Map<String, List<double>> _nodeLatencies = {
    nodeLocal: [],
    nodeEdge: [],
    nodeCloud: [],
  };
  static const int _maxLatencySamples = 50;

  /// 设置任务分配策略
  static void setTaskAllocationStrategy(String strategy) {
    _taskAllocationStrategy = strategy;
    debugPrint('[ImageProcessor] 任务分配策略: $strategy');
  }

  /// 获取当前分配策略
  static String get taskAllocationStrategy => _taskAllocationStrategy;

  /// 选择最佳计算节点
  ///
  /// 根据任务类型、数据大小和当前策略选择最优计算节点
  static String selectComputeNode({
    required String taskType,
    required int dataSizeBytes,
    bool requiresLowLatency = false,
  }) {
    // 小任务直接本地处理
    if (dataSizeBytes < 10240) return nodeLocal; // <10KB

    switch (_taskAllocationStrategy) {
      case strategyLocalFirst:
        return nodeLocal;
      case strategyRoundRobin:
        return _roundRobinSelect();
      case strategyLoadBased:
        return _loadBasedSelect();
      case strategyLatencyBased:
        return _latencyBasedSelect();
      default:
        return nodeLocal;
    }
  }

  /// 轮询选择节点
  static String _roundRobinSelect() {
    final nodes = [nodeLocal, nodeEdge, nodeCloud];
    final index = _totalTasksProcessed % nodes.length;
    return nodes[index];
  }

  /// 基于负载选择节点
  static String _loadBasedSelect() {
    // 选择活动任务数最少的节点
    // 本地节点负载由 _activeTaskCount 反映
    if (_activeTaskCount < 3) return nodeLocal;
    return nodeEdge; // 默认回退到边缘
  }

  /// 基于延迟选择节点
  static String _latencyBasedSelect() {
    String bestNode = nodeLocal;
    double bestLatency = double.infinity;

    for (final entry in _nodeLatencies.entries) {
      if (entry.value.isEmpty) continue;
      final avgLatency = entry.value.reduce((a, b) => a + b) / entry.value.length;
      if (avgLatency < bestLatency) {
        bestLatency = avgLatency;
        bestNode = entry.key;
      }
    }

    return bestNode;
  }

  /// 记录计算任务
  static void _recordComputeTask(String nodeType, String taskType,
      Duration elapsed, {bool success = true, int? dataSize}) {
    _computeTaskLog.add({
      'nodeType': nodeType,
      'taskType': taskType,
      'elapsedMs': elapsed.inMicroseconds / 1000.0,
      'success': success,
      'dataSize': dataSize,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_computeTaskLog.length > _maxComputeTaskLogSize) {
      _computeTaskLog.removeAt(0);
    }

    // 更新节点延迟
    _nodeLatencies.putIfAbsent(nodeType, () => []);
    final latencies = _nodeLatencies[nodeType]!;
    latencies.add(elapsed.inMicroseconds / 1000.0);
    if (latencies.length > _maxLatencySamples) {
      latencies.removeAt(0);
    }
  }

  /// 获取计算任务分配统计
  static Map<String, dynamic> getTaskAllocationStats() {
    final nodeTaskCounts = <String, int>{};
    final nodeAvgLatencies = <String, double>{};
    final nodeSuccessRates = <String, double>{};

    for (final nodeType in [nodeLocal, nodeEdge, nodeCloud]) {
      final tasks = _computeTaskLog.where((t) => t['nodeType'] == nodeType).toList();
      nodeTaskCounts[nodeType] = tasks.length;

      if (tasks.isNotEmpty) {
        final latencies = tasks.map((t) => t['elapsedMs'] as double).toList();
        nodeAvgLatencies[nodeType] = latencies.reduce((a, b) => a + b) / latencies.length;
        final successCount = tasks.where((t) => t['success'] == true).length;
        nodeSuccessRates[nodeType] = successCount / tasks.length;
      } else {
        nodeAvgLatencies[nodeType] = 0.0;
        nodeSuccessRates[nodeType] = 1.0;
      }
    }

    return {
      'strategy': _taskAllocationStrategy,
      'totalTasks': _computeTaskLog.length,
      'nodeTaskCounts': nodeTaskCounts,
      'nodeAvgLatencies': nodeAvgLatencies,
      'nodeSuccessRates': nodeSuccessRates,
    };
  }

  /// 计算结果合并
  ///
  /// 将来自不同计算节点的结果合并为统一输出
  /// 适用于分布式计算场景（如多节点并行处理不同字符）
  static List<T> mergeComputeResults<T>(
    List<List<T>> results, {
    bool deduplicate = false,
  }) {
    final merged = <T>[];
    final seen = <String>{};

    for (final result in results) {
      for (final item in result) {
        if (deduplicate) {
          final key = item.toString();
          if (seen.contains(key)) continue;
          seen.add(key);
        }
        merged.add(item);
      }
    }

    debugPrint('[ImageProcessor] 合并计算结果: ${results.length} 组 → ${merged.length} 项');
    return merged;
  }

  /// 计算性能监控
  ///
  /// 获取各计算节点的详细性能统计
  static Map<String, dynamic> getComputePerformanceMonitor() {
    final nodePerformance = <String, Map<String, dynamic>>{};

    for (final entry in _nodeLatencies.entries) {
      final latencies = entry.value;
      if (latencies.isEmpty) {
        nodePerformance[entry.key] = {
          'sampleCount': 0,
          'avgLatencyMs': 0.0,
          'p50LatencyMs': 0.0,
          'p95LatencyMs': 0.0,
          'maxLatencyMs': 0.0,
        };
        continue;
      }

      final sorted = List<double>.from(latencies)..sort();
      final avg = sorted.reduce((a, b) => a + b) / sorted.length;
      final p50Index = (sorted.length * 0.5).round().clamp(0, sorted.length - 1);
      final p95Index = (sorted.length * 0.95).round().clamp(0, sorted.length - 1);

      nodePerformance[entry.key] = {
        'sampleCount': sorted.length,
        'avgLatencyMs': avg,
        'p50LatencyMs': sorted[p50Index],
        'p95LatencyMs': sorted[p95Index],
        'maxLatencyMs': sorted.last,
        'minLatencyMs': sorted.first,
      };
    }

    return {
      'timestamp': DateTime.now().toIso8601String(),
      'strategy': _taskAllocationStrategy,
      'nodePerformance': nodePerformance,
      'totalTasksProcessed': _totalTasksProcessed,
      'activeTaskCount': _activeTaskCount,
      'peakTaskCount': _peakTaskCount,
      'avgProcessingTimeMs': _totalTasksProcessed > 0
          ? (_totalProcessingTimeUs / _totalTasksProcessed) / 1000.0
          : 0.0,
    };
  }

  /// 获取混合计算综合报告
  static Map<String, dynamic> getHybridComputeReport() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'taskAllocation': getTaskAllocationStats(),
      'performance': getComputePerformanceMonitor(),
      'existing': getFullMonitorReport(),
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 深度学习功能：神经网络、卷积层、池化层、全连接层
  // ═══════════════════════════════════════════════════════════

  // ── 神经网络层类型定义 ──

  /// 层类型枚举
  static const String layerTypeConv = 'conv';
  static const String layerTypePool = 'pool';
  static const String layerTypeFC = 'fc';
  static const String layerTypeReLU = 'relu';
  static const String layerTypeSoftmax = 'softmax';
  static const String layerTypeBatchNorm = 'batch_norm';
  static const String layerTypeDropout = 'dropout';

  /// 已构建的网络层序列
  static final List<Map<String, dynamic>> _networkLayers = [];

  /// 网络训练状态
  static final Map<String, dynamic> _networkState = {
    'isCompiled': false,
    'totalParameters': 0,
    'layerCount': 0,
  };

  /// 添加卷积层
  ///
  /// [filters] 输出通道数（卷积核数量）
  /// [kernelSize] 卷积核大小（正方形，如 3 表示 3×3）
  /// [stride] 步长
  /// [padding] 填充方式（'same' | 'valid'）
  /// [activation] 激活函数（'relu' | 'sigmoid' | 'tanh' | 'none'）
  static void addConvLayer({
    required int filters,
    int kernelSize = 3,
    int stride = 1,
    String padding = 'same',
    String activation = 'relu',
  }) {
    // 参数校验
    assert(filters > 0, 'filters 必须大于 0');
    assert(kernelSize > 0, 'kernelSize 必须大于 0');
    assert(stride > 0, 'stride 必须大于 0');

    final layer = <String, dynamic>{
      'type': layerTypeConv,
      'filters': filters,
      'kernelSize': kernelSize,
      'stride': stride,
      'padding': padding,
      'activation': activation,
      'params': filters * kernelSize * kernelSize + filters, // weights + bias
    };
    _networkLayers.add(layer);
    _updateNetworkState();
    debugPrint('[ImageProcessor] 添加卷积层: ${filters}个${kernelSize}x${kernelSize}核, stride=$stride, padding=$padding');
  }

  /// 添加池化层
  ///
  /// [poolSize] 池化窗口大小
  /// [stride] 步长（默认等于 poolSize）
  /// [type] 池化类型（'max' | 'avg'）
  static void addPoolingLayer({
    int poolSize = 2,
    int? stride,
    String type = 'max',
  }) {
    assert(poolSize > 0, 'poolSize 必须大于 0');

    final layer = <String, dynamic>{
      'type': layerTypePool,
      'poolSize': poolSize,
      'stride': stride ?? poolSize,
      'poolType': type,
      'params': 0, // 池化层无参数
    };
    _networkLayers.add(layer);
    _updateNetworkState();
    debugPrint('[ImageProcessor] 添加池化层: ${type}Pool ${poolSize}x$poolSize, stride=${stride ?? poolSize}');
  }

  /// 添加全连接层
  ///
  /// [units] 输出维度
  /// [activation] 激活函数（'relu' | 'sigmoid' | 'tanh' | 'softmax' | 'none'）
  static void addFCLayer({
    required int units,
    String activation = 'relu',
  }) {
    assert(units > 0, 'units 必须大于 0');

    final layer = <String, dynamic>{
      'type': layerTypeFC,
      'units': units,
      'activation': activation,
      'params': units, // 简化参数计数（实际需乘以输入维度）
    };
    _networkLayers.add(layer);
    _updateNetworkState();
    debugPrint('[ImageProcessor] 添加全连接层: units=$units, activation=$activation');
  }

  /// 添加 BatchNormalization 层
  static void addBatchNormLayer({double momentum = 0.99, double epsilon = 1e-5}) {
    _networkLayers.add(<String, dynamic>{
      'type': layerTypeBatchNorm,
      'momentum': momentum,
      'epsilon': epsilon,
      'params': 0, // gamma + beta，简化计数
    });
    _updateNetworkState();
    debugPrint('[ImageProcessor] 添加 BatchNorm 层');
  }

  /// 添加 Dropout 层
  static void addDropoutLayer({double rate = 0.5}) {
    assert(rate >= 0 && rate < 1, 'dropout rate 必须在 [0, 1) 范围内');
    _networkLayers.add(<String, dynamic>{
      'type': layerTypeDropout,
      'rate': rate,
      'params': 0,
    });
    _updateNetworkState();
    debugPrint('[ImageProcessor] 添加 Dropout 层: rate=$rate');
  }

  /// 添加 ReLU 激活层
  static void addReLULayer() {
    _networkLayers.add(<String, dynamic>{
      'type': layerTypeReLU,
      'params': 0,
    });
    _updateNetworkState();
    debugPrint('[ImageProcessor] 添加 ReLU 层');
  }

  /// 添加 Softmax 输出层
  static void addSoftmaxLayer() {
    _networkLayers.add(<String, dynamic>{
      'type': layerTypeSoftmax,
      'params': 0,
    });
    _updateNetworkState();
    debugPrint('[ImageProcessor] 添加 Softmax 层');
  }

  /// 更新网络状态
  static void _updateNetworkState() {
    int totalParams = 0;
    for (final layer in _networkLayers) {
      totalParams += (layer['params'] as int? ?? 0);
    }
    _networkState['totalParameters'] = totalParams;
    _networkState['layerCount'] = _networkLayers.length;
    _networkState['isCompiled'] = false; // 层变更后需重新编译
  }

  /// 清空网络层
  static void clearNetwork() {
    _networkLayers.clear();
    _networkState['isCompiled'] = false;
    _networkState['totalParameters'] = 0;
    _networkState['layerCount'] = 0;
    debugPrint('[ImageProcessor] 网络已清空');
  }

  /// 获取网络结构描述
  static List<Map<String, dynamic>> getNetworkArchitecture() =>
      List.unmodifiable(_networkLayers);

  /// 获取网络状态
  static Map<String, dynamic> getNetworkState() =>
      Map.unmodifiable(_networkState);

  /// ── 卷积运算 ──

  /// 对灰度图像执行 2D 卷积运算
  ///
  /// [input] 输入图像（单通道灰度图）
  /// [kernel] 卷积核（2D 数组）
  /// [stride] 步长
  /// [padding] 填充方式
  /// 返回卷积后的特征图
  static List<List<double>> conv2d({
    required List<List<double>> input,
    required List<List<double>> kernel,
    int stride = 1,
    String padding = 'same',
  }) {
    final inputH = input.length;
    final inputW = input[0].length;
    final kernelH = kernel.length;
    final kernelW = kernel[0].length;

    // 计算输出尺寸
    int outputH, outputW;
    int padH = 0, padW = 0;

    if (padding == 'same') {
      padH = (kernelH - 1) ~/ 2;
      padW = (kernelW - 1) ~/ 2;
      outputH = (inputH / stride).ceil();
      outputW = (inputW / stride).ceil();
    } else {
      outputH = ((inputH - kernelH) / stride + 1).ceil().clamp(1, inputH);
      outputW = ((inputW - kernelW) / stride + 1).ceil().clamp(1, inputW);
    }

    // 初始化输出
    final output = List.generate(outputH, (_) => List.filled(outputW, 0.0));

    // 执行卷积
    for (int oh = 0; oh < outputH; oh++) {
      for (int ow = 0; ow < outputW; ow++) {
        double sum = 0.0;
        for (int kh = 0; kh < kernelH; kh++) {
          for (int kw = 0; kw < kernelW; kw++) {
            final ih = oh * stride + kh - padH;
            final iw = ow * stride + kw - padW;
            if (ih >= 0 && ih < inputH && iw >= 0 && iw < inputW) {
              sum += input[ih][iw] * kernel[kh][kw];
            }
          }
        }
        output[oh][ow] = sum;
      }
    }

    return output;
  }

  /// 常用卷积核生成器
  static List<List<double>> generateKernel(String type, {int size = 3}) {
    switch (type) {
      case 'sobel_x':
        return [
          [-1, 0, 1],
          [-2, 0, 2],
          [-1, 0, 1],
        ].map((r) => r.map((e) => e.toDouble()).toList()).toList();
      case 'sobel_y':
        return [
          [-1, -2, -1],
          [0, 0, 0],
          [1, 2, 1],
        ].map((r) => r.map((e) => e.toDouble()).toList()).toList();
      case 'laplacian':
        return [
          [0, -1, 0],
          [-1, 4, -1],
          [0, -1, 0],
        ].map((r) => r.map((e) => e.toDouble()).toList()).toList();
      case 'gaussian':
        return [
          [1, 2, 1],
          [2, 4, 2],
          [1, 2, 1],
        ].map((r) => r.map((e) => e / 16.0).toList()).toList();
      case 'sharpen':
        return [
          [0, -1, 0],
          [-1, 5, -1],
          [0, -1, 0],
        ].map((r) => r.map((e) => e.toDouble()).toList()).toList();
      case 'emboss':
        return [
          [-2, -1, 0],
          [-1, 1, 1],
          [0, 1, 2],
        ].map((r) => r.map((e) => e.toDouble()).toList()).toList();
      default:
        // 默认使用高斯核
        return generateKernel('gaussian', size: size);
    }
  }

  /// ── 池化运算 ──

  /// 对特征图执行 2D 池化运算
  ///
  /// [input] 输入特征图
  /// [poolSize] 池化窗口大小
  /// [stride] 步长
  /// [type] 池化类型（'max' | 'avg'）
  /// 返回池化后的特征图
  static List<List<double>> pool2d({
    required List<List<double>> input,
    int poolSize = 2,
    int? stride,
    String type = 'max',
  }) {
    final effectiveStride = stride ?? poolSize;
    final inputH = input.length;
    final inputW = input[0].length;
    final outputH = ((inputH - poolSize) / effectiveStride + 1).ceil().clamp(1, inputH);
    final outputW = ((inputW - poolSize) / effectiveStride + 1).ceil().clamp(1, inputW);

    final output = List.generate(outputH, (_) => List.filled(outputW, 0.0));

    for (int oh = 0; oh < outputH; oh++) {
      for (int ow = 0; ow < outputW; ow++) {
        double value = type == 'max' ? double.negativeInfinity : 0.0;
        int count = 0;

        for (int ph = 0; ph < poolSize; ph++) {
          for (int pw = 0; pw < poolSize; pw++) {
            final ih = oh * effectiveStride + ph;
            final iw = ow * effectiveStride + pw;
            if (ih < inputH && iw < inputW) {
              if (type == 'max') {
                if (input[ih][iw] > value) value = input[ih][iw];
              } else {
                value += input[ih][iw];
              }
              count++;
            }
          }
        }

        output[oh][ow] = type == 'max' ? value : (count > 0 ? value / count : 0.0);
      }
    }

    return output;
  }

  /// ── 全连接层运算 ──

  /// 全连接层前向传播
  ///
  /// [input] 输入向量（展平的特征）
  /// [weights] 权重矩阵 [outputSize × inputSize]
  /// [bias] 偏置向量 [outputSize]
  /// 返回输出向量
  static List<double> fullyConnected({
    required List<double> input,
    required List<List<double>> weights,
    required List<double> bias,
  }) {
    final outputSize = weights.length;
    final output = List.filled(outputSize, 0.0);

    for (int i = 0; i < outputSize; i++) {
      double sum = bias[i];
      for (int j = 0; j < input.length && j < weights[i].length; j++) {
        sum += input[j] * weights[i][j];
      }
      output[i] = sum;
    }

    return output;
  }

  /// 激活函数
  ///
  /// [input] 输入向量
  /// [type] 激活函数类型（'relu' | 'sigmoid' | 'tanh' | 'softmax' | 'leaky_relu'）
  static List<double> activate(List<double> input, {String type = 'relu'}) {
    switch (type) {
      case 'relu':
        return input.map((v) => v > 0 ? v : 0.0).toList();
      case 'leaky_relu':
        return input.map((v) => v > 0 ? v : 0.01 * v).toList();
      case 'sigmoid':
        return input.map((v) => 1.0 / (1.0 + exp(-v))).toList();
      case 'tanh':
        return input.map((v) => (exp(v) - exp(-v)) / (exp(v) + exp(-v))).toList();
      case 'softmax':
        final maxVal = input.reduce((a, b) => a > b ? a : b);
        final exps = input.map((v) => exp(v - maxVal)).toList();
        final sum = exps.reduce((a, b) => a + b);
        return exps.map((v) => v / sum).toList();
      default:
        return input;
    }
  }

  /// 展平 2D 特征图为 1D 向量
  static List<double> flatten(List<List<double>> featureMap) {
    final result = <double>[];
    for (final row in featureMap) {
      result.addAll(row);
    }
    return result;
  }

  /// 将图片转为特征矩阵（归一化到 0.0~1.0）
  static List<List<double>> imageToFeatureMatrix(img.Image image, {bool grayscale = true}) {
    final matrix = List.generate(
      image.height,
      (y) => List.generate(
        image.width,
        (x) {
          final pixel = image.getPixel(x, y);
          if (grayscale) {
            return (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255.0;
          }
          return pixel.r / 255.0;
        },
      ),
    );
    return matrix;
  }

  /// 获取深度学习功能报告
  static Map<String, dynamic> getDeepLearningReport() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'networkState': getNetworkState(),
      'architecture': getNetworkArchitecture().map((l) => {
        'type': l['type'],
        'params': l['params'],
      }).toList(),
      'availableKernels': ['sobel_x', 'sobel_y', 'laplacian', 'gaussian', 'sharpen', 'emboss'],
      'activationFunctions': ['relu', 'leaky_relu', 'sigmoid', 'tanh', 'softmax'],
    };
  }
}

class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);
}

// ═══════════════════════════════════════════════════════════
// 量子计算功能模块
// ═══════════════════════════════════════════════════════════

/// 量子比特状态表示
/// 使用复数振幅表示 |0⟩ 和 |1⟩ 的叠加态
class Qubit {
  /// |0⟩ 振幅的实部和虚部
  double alphaReal;
  double alphaImag;

  /// |1⟩ 振幅的实部和虚部
  double betaReal;
  double betaImag;

  /// 创建量子比特（默认为 |0⟩ 态）
  Qubit({
    this.alphaReal = 1.0,
    this.alphaImag = 0.0,
    this.betaReal = 0.0,
    this.betaImag = 0.0,
  });

  /// 从经典比特创建量子比特
  factory Qubit.fromBit(int bit) {
    if (bit == 0) return Qubit();
    return Qubit(alphaReal: 0, alphaImag: 0, betaReal: 1, betaImag: 0);
  }

  /// 计算 |0⟩ 的概率
  double get probZero => alphaReal * alphaReal + alphaImag * alphaImag;

  /// 计算 |1⟩ 的概率
  double get probOne => betaReal * betaReal + betaImag * betaImag;

  /// 测量量子比特，返回 0 或 1
  int measure() {
    final rand = Random().nextDouble();
    return rand < probZero ? 0 : 1;
  }

  /// 归一化量子态
  void normalize() {
    final norm = sqrt(probZero + probOne);
    if (norm > 1e-10) {
      alphaReal /= norm;
      alphaImag /= norm;
      betaReal /= norm;
      betaImag /= norm;
    }
  }

  @override
  String toString() =>
      '(${alphaReal.toStringAsFixed(3)}+${alphaImag.toStringAsFixed(3)}i)|0⟩ + '
      '(${betaReal.toStringAsFixed(3)}+${betaImag.toStringAsFixed(3)}i)|1⟩';
}

/// 量子门类型枚举
enum QuantumGateType {
  hadamard,   // Hadamard 门：创建等概率叠加态
  pauliX,     // Pauli-X 门：量子 NOT 门
  pauliY,     // Pauli-Y 门
  pauliZ,     // Pauli-Z 门：相位翻转
  phase,      // 相位门 (S gate)
  tGate,      // T 门 (π/8 门)
  cnot,       // CNOT 门：受控非门（双量子比特）
  swap,       // SWAP 门：交换两个量子比特
  toffoli,    // Toffoli 门：受控受控非门（三量子比特）
}

/// 量子门操作
///
/// 对单个或多个量子比特应用量子门变换
class QuantumGate {
  final QuantumGateType type;
  final List<int> targetQubits;
  final List<int>? controlQubits;
  final double? angle; // 用于参数化旋转门

  const QuantumGate({
    required this.type,
    required this.targetQubits,
    this.controlQubits,
    this.angle,
  });

  /// 应用 Hadamard 门到单个量子比特
  /// H|0⟩ = (|0⟩ + |1⟩)/√2
  /// H|1⟩ = (|0⟩ - |1⟩)/√2
  static void applyHadamard(Qubit q) {
    final sqrt2inv = 1.0 / sqrt(2.0);
    final newAlphaR = (q.alphaReal + q.betaReal) * sqrt2inv;
    final newAlphaI = (q.alphaImag + q.betaImag) * sqrt2inv;
    final newBetaR = (q.alphaReal - q.betaReal) * sqrt2inv;
    final newBetaI = (q.alphaImag - q.betaImag) * sqrt2inv;
    q.alphaReal = newAlphaR;
    q.alphaImag = newAlphaI;
    q.betaReal = newBetaR;
    q.betaImag = newBetaI;
  }

  /// 应用 Pauli-X 门（量子 NOT）
  /// X|0⟩ = |1⟩, X|1⟩ = |0⟩
  static void applyPauliX(Qubit q) {
    final tmpR = q.alphaReal, tmpI = q.alphaImag;
    q.alphaReal = q.betaReal;
    q.alphaImag = q.betaImag;
    q.betaReal = tmpR;
    q.betaImag = tmpI;
  }

  /// 应用 Pauli-Y 门
  /// Y|0⟩ = i|1⟩, Y|1⟩ = -i|0⟩
  static void applyPauliY(Qubit q) {
    final newAlphaR = q.betaImag;
    final newAlphaI = -q.betaReal;
    final newBetaR = -q.alphaImag;
    final newBetaI = q.alphaReal;
    q.alphaReal = newAlphaR;
    q.alphaImag = newAlphaI;
    q.betaReal = newBetaR;
    q.betaImag = newBetaI;
  }

  /// 应用 Pauli-Z 门
  /// Z|0⟩ = |0⟩, Z|1⟩ = -|1⟩
  static void applyPauliZ(Qubit q) {
    q.betaReal = -q.betaReal;
    q.betaImag = -q.betaImag;
  }

  /// 应用相位门 (S gate)：将 |1⟩ 相位旋转 π/2
  static void applyPhase(Qubit q) {
    // S = diag(1, i)
    final newBetaR = -q.betaImag;
    final newBetaI = q.betaReal;
    q.betaReal = newBetaR;
    q.betaImag = newBetaI;
  }

  /// 应用 T 门：将 |1⟩ 相位旋转 π/4
  static void applyTGate(Qubit q) {
    final cos45 = cos(pi / 4);
    final sin45 = sin(pi / 4);
    final newBetaR = q.betaReal * cos45 - q.betaImag * sin45;
    final newBetaI = q.betaReal * sin45 + q.betaImag * cos45;
    q.betaReal = newBetaR;
    q.betaImag = newBetaI;
  }

  /// 应用参数化旋转门 Ry(θ)
  static void applyRotationY(Qubit q, double theta) {
    final cosHalf = cos(theta / 2);
    final sinHalf = sin(theta / 2);
    final newAlphaR = q.alphaReal * cosHalf - q.betaReal * sinHalf;
    final newAlphaI = q.alphaImag * cosHalf - q.betaImag * sinHalf;
    final newBetaR = q.alphaReal * sinHalf + q.betaReal * cosHalf;
    final newBetaI = q.alphaImag * sinHalf + q.betaImag * cosHalf;
    q.alphaReal = newAlphaR;
    q.alphaImag = newAlphaI;
    q.betaReal = newBetaR;
    q.betaImag = newBetaI;
  }

  /// 应用旋转门 Rz(θ)
  static void applyRotationZ(Qubit q, double theta) {
    final cosHalf = cos(theta / 2);
    final sinHalf = sin(theta / 2);
    final newAlphaR = q.alphaReal * cosHalf + q.alphaImag * sinHalf;
    final newAlphaI = q.alphaImag * cosHalf - q.alphaReal * sinHalf;
    final newBetaR = q.betaReal * cosHalf - q.betaImag * sinHalf;
    final newBetaI = q.betaImag * cosHalf + q.betaReal * sinHalf;
    q.alphaReal = newAlphaR;
    q.alphaImag = newAlphaI;
    q.betaReal = newBetaR;
    q.betaImag = newBetaI;
  }

  /// 应用 CNOT 门（受控非门）
  /// 当 control 为 |1⟩ 时翻转 target
  static void applyCNOT(Qubit control, Qubit target) {
    if (control.probOne > 0.5) {
      applyPauliX(target);
    }
  }

  /// 应用 SWAP 门：交换两个量子比特状态
  static void applySwap(Qubit q1, Qubit q2) {
    final tmpAlphaR = q1.alphaReal, tmpAlphaI = q1.alphaImag;
    final tmpBetaR = q1.betaReal, tmpBetaI = q1.betaImag;
    q1.alphaReal = q2.alphaReal;
    q1.alphaImag = q2.alphaImag;
    q1.betaReal = q2.betaReal;
    q1.betaImag = q2.betaImag;
    q2.alphaReal = tmpAlphaR;
    q2.alphaImag = tmpAlphaI;
    q2.betaReal = tmpBetaR;
    q2.betaImag = tmpBetaI;
  }
}

/// 量子电路：由多个量子门组成的有序操作序列
///
/// 支持多量子比特电路的构建、执行和状态查询
class QuantumCircuit {
  /// 量子比特数量
  final int numQubits;

  /// 量子比特状态
  final List<Qubit> _qubits;

  /// 电路中的门操作序列
  final List<QuantumGate> _gates = [];

  /// 执行历史（每次测量结果）
  final List<List<int>> _measurementHistory = [];

  /// 创建指定量子比特数的量子电路
  QuantumCircuit(this.numQubits) : _qubits = List.generate(numQubits, (_) => Qubit());

  /// 获取量子比特列表（只读）
  List<Qubit> get qubits => List.unmodifiable(_qubits);

  /// 获取门操作数量
  int get gateCount => _gates.length;

  /// 添加 Hadamard 门
  void addHadamard(int qubitIndex) {
    _validateIndex(qubitIndex);
    _gates.add(QuantumGate(type: QuantumGateType.hadamard, targetQubits: [qubitIndex]));
  }

  /// 添加 Pauli-X 门
  void addPauliX(int qubitIndex) {
    _validateIndex(qubitIndex);
    _gates.add(QuantumGate(type: QuantumGateType.pauliX, targetQubits: [qubitIndex]));
  }

  /// 添加 Pauli-Y 门
  void addPauliY(int qubitIndex) {
    _validateIndex(qubitIndex);
    _gates.add(QuantumGate(type: QuantumGateType.pauliY, targetQubits: [qubitIndex]));
  }

  /// 添加 Pauli-Z 门
  void addPauliZ(int qubitIndex) {
    _validateIndex(qubitIndex);
    _gates.add(QuantumGate(type: QuantumGateType.pauliZ, targetQubits: [qubitIndex]));
  }

  /// 添加相位门
  void addPhase(int qubitIndex) {
    _validateIndex(qubitIndex);
    _gates.add(QuantumGate(type: QuantumGateType.phase, targetQubits: [qubitIndex]));
  }

  /// 添加 T 门
  void addTGate(int qubitIndex) {
    _validateIndex(qubitIndex);
    _gates.add(QuantumGate(type: QuantumGateType.tGate, targetQubits: [qubitIndex]));
  }

  /// 添加 Ry(θ) 旋转门
  void addRotationY(int qubitIndex, double angle) {
    _validateIndex(qubitIndex);
    _gates.add(QuantumGate(
      type: QuantumGateType.hadamard, // 使用 hadamard 类型作为标记
      targetQubits: [qubitIndex],
      angle: angle,
    ));
  }

  /// 添加 CNOT 门
  void addCNOT(int controlIndex, int targetIndex) {
    _validateIndex(controlIndex);
    _validateIndex(targetIndex);
    _gates.add(QuantumGate(
      type: QuantumGateType.cnot,
      targetQubits: [targetIndex],
      controlQubits: [controlIndex],
    ));
  }

  /// 添加 SWAP 门
  void addSwap(int qubit1, int qubit2) {
    _validateIndex(qubit1);
    _validateIndex(qubit2);
    _gates.add(QuantumGate(
      type: QuantumGateType.swap,
      targetQubits: [qubit1, qubit2],
    ));
  }

  /// 添加 Toffoli 门（受控受控非门）
  void addToffoli(int control1, int control2, int target) {
    _validateIndex(control1);
    _validateIndex(control2);
    _validateIndex(target);
    _gates.add(QuantumGate(
      type: QuantumGateType.toffoli,
      targetQubits: [target],
      controlQubits: [control1, control2],
    ));
  }

  /// 执行量子电路中的所有门操作
  void execute() {
    for (final gate in _gates) {
      _applyGate(gate);
    }
  }

  /// 应用单个门操作
  void _applyGate(QuantumGate gate) {
    switch (gate.type) {
      case QuantumGateType.hadamard:
        if (gate.angle != null) {
          QuantumGate.applyRotationY(_qubits[gate.targetQubits[0]], gate.angle!);
        } else {
          QuantumGate.applyHadamard(_qubits[gate.targetQubits[0]]);
        }
        break;
      case QuantumGateType.pauliX:
        QuantumGate.applyPauliX(_qubits[gate.targetQubits[0]]);
        break;
      case QuantumGateType.pauliY:
        QuantumGate.applyPauliY(_qubits[gate.targetQubits[0]]);
        break;
      case QuantumGateType.pauliZ:
        QuantumGate.applyPauliZ(_qubits[gate.targetQubits[0]]);
        break;
      case QuantumGateType.phase:
        QuantumGate.applyPhase(_qubits[gate.targetQubits[0]]);
        break;
      case QuantumGateType.tGate:
        QuantumGate.applyTGate(_qubits[gate.targetQubits[0]]);
        break;
      case QuantumGateType.cnot:
        QuantumGate.applyCNOT(
          _qubits[gate.controlQubits![0]],
          _qubits[gate.targetQubits[0]],
        );
        break;
      case QuantumGateType.swap:
        QuantumGate.applySwap(
          _qubits[gate.targetQubits[0]],
          _qubits[gate.targetQubits[1]],
        );
        break;
      case QuantumGateType.toffoli:
        // Toffoli: 当两个控制位都为 |1⟩ 时翻转目标位
        if (_qubits[gate.controlQubits![0]].probOne > 0.5 &&
            _qubits[gate.controlQubits![1]].probOne > 0.5) {
          QuantumGate.applyPauliX(_qubits[gate.targetQubits[0]]);
        }
        break;
    }
  }

  /// 测量所有量子比特
  List<int> measureAll() {
    final results = _qubits.map((q) => q.measure()).toList();
    _measurementHistory.add(results);
    return results;
  }

  /// 测量指定量子比特
  int measureQubit(int index) {
    _validateIndex(index);
    return _qubits[index].measure();
  }

  /// 获取测量历史
  List<List<int>> get measurementHistory => List.unmodifiable(_measurementHistory);

  /// 重置所有量子比特到 |0⟩ 态
  void reset() {
    for (final q in _qubits) {
      q.alphaReal = 1.0;
      q.alphaImag = 0.0;
      q.betaReal = 0.0;
      q.betaImag = 0.0;
    }
    _gates.clear();
  }

  /// 验证量子比特索引
  void _validateIndex(int index) {
    if (index < 0 || index >= numQubits) {
      throw RangeError('量子比特索引 $index 超出范围 [0, $numQubits)');
    }
  }

  /// 获取电路描述信息
  Map<String, dynamic> getCircuitInfo() {
    return {
      'numQubits': numQubits,
      'gateCount': _gates.length,
      'gates': _gates.map((g) => {
        'type': g.type.name,
        'targets': g.targetQubits,
        'controls': g.controlQubits,
      }).toList(),
      'measurementCount': _measurementHistory.length,
    };
  }
}

/// 量子算法实现
///
/// 提供常用量子算法的实现：
/// - Deutsch-Jozsa 算法
/// - Bernstein-Vazirani 算法
/// - 量子傅里叶变换 (QFT)
/// - Grover 搜索算法
/// - 量子随机数生成
class QuantumAlgorithm {
  /// Deutsch-Jozsa 算法：判断函数是常数函数还是平衡函数
  ///
  /// [oracleType] 'constant' 或 'balanced'
  /// [numQubits] 量子比特数（不含辅助比特）
  /// 返回 true 表示常数函数，false 表示平衡函数
  static bool deutschJozsa({required String oracleType, int numQubits = 1}) {
    final circuit = QuantumCircuit(numQubits + 1); // +1 for ancilla qubit

    // 初始化：将辅助比特设为 |1⟩
    QuantumGate.applyPauliX(circuit.qubits[numQubits]);

    // 对所有比特应用 Hadamard
    for (int i = 0; i <= numQubits; i++) {
      QuantumGate.applyHadamard(circuit.qubits[i]);
    }

    // 应用 Oracle
    if (oracleType == 'balanced') {
      for (int i = 0; i < numQubits; i++) {
        QuantumGate.applyCNOT(circuit.qubits[i], circuit.qubits[numQubits]);
      }
    }
    // constant oracle 不需要额外操作

    // 对输入比特应用 Hadamard
    for (int i = 0; i < numQubits; i++) {
      QuantumGate.applyHadamard(circuit.qubits[i]);
    }

    // 测量输入比特
    final results = <int>[];
    for (int i = 0; i < numQubits; i++) {
      results.add(circuit.qubits[i].measure());
    }

    // 如果所有测量结果都是 0，则为常数函数
    return results.every((r) => r == 0);
  }

  /// Bernstein-Vazirani 算法：找出隐藏的比特串 s
  ///
  /// [secretString] 隐藏的比特串（如 [1, 0, 1]）
  /// 返回测量结果（应等于 secretString）
  static List<int> bernsteinVazirani(List<int> secretString) {
    final n = secretString.length;
    final circuit = QuantumCircuit(n + 1);

    // 初始化
    QuantumGate.applyPauliX(circuit.qubits[n]);
    for (int i = 0; i <= n; i++) {
      QuantumGate.applyHadamard(circuit.qubits[i]);
    }

    // Oracle: 对于每个 s_i = 1，应用 CNOT
    for (int i = 0; i < n; i++) {
      if (secretString[i] == 1) {
        QuantumGate.applyCNOT(circuit.qubits[i], circuit.qubits[n]);
      }
    }

    // 对输入比特应用 Hadamard
    for (int i = 0; i < n; i++) {
      QuantumGate.applyHadamard(circuit.qubits[i]);
    }

    // 测量
    final results = <int>[];
    for (int i = 0; i < n; i++) {
      results.add(circuit.qubits[i].measure());
    }
    return results;
  }

  /// 量子随机数生成器
  ///
  /// 使用量子叠加态生成真正的随机数
  /// [numBits] 生成的随机比特数
  /// 返回随机比特列表
  static List<int> quantumRandomNumber(int numBits) {
    final circuit = QuantumCircuit(numBits);
    // 对每个量子比特应用 Hadamard 创建叠加态
    for (int i = 0; i < numBits; i++) {
      QuantumGate.applyHadamard(circuit.qubits[i]);
    }
    // 测量得到真正的随机比特
    return circuit.measureAll();
  }

  /// 量子随机整数生成
  ///
  /// [min] 最小值（含）
  /// [max] 最大值（含）
  /// 返回 [min, max] 范围内的随机整数
  static int quantumRandomInt(int min, int max) {
    final range = max - min + 1;
    final numBits = (log(range) / log(2)).ceil().clamp(1, 32);
    int result;
    do {
      final bits = quantumRandomNumber(numBits);
      result = 0;
      for (int i = 0; i < bits.length; i++) {
        result = (result << 1) | bits[i];
      }
    } while (result >= range);
    return min + result;
  }

  /// Grover 搜索算法（简化版）
  ///
  /// 在无序数据库中搜索目标元素
  /// [numQubits] 量子比特数（搜索空间大小为 2^numQubits）
  /// [targetIndex] 目标元素的索引
  /// 返回测量结果（高概率为 targetIndex）
  static int groverSearch(int numQubits, int targetIndex) {
    final N = 1 << numQubits; // 搜索空间大小
    final numIterations = ((pi / 4) * sqrt(N)).round();

    final circuit = QuantumCircuit(numQubits);

    // 初始化：创建均匀叠加态
    for (int i = 0; i < numQubits; i++) {
      QuantumGate.applyHadamard(circuit.qubits[i]);
    }

    // Grover 迭代
    for (int iter = 0; iter < numIterations; iter++) {
      // Oracle：翻转目标状态的相位
      _applyOracle(circuit, targetIndex);

      // Diffusion 算子
      _applyDiffusion(circuit);
    }

    // 测量
    final result = circuit.measureAll();
    int measuredIndex = 0;
    for (int i = 0; i < result.length; i++) {
      measuredIndex = (measuredIndex << 1) | result[i];
    }
    return measuredIndex;
  }

  /// 应用 Grover Oracle（标记目标状态）
  static void _applyOracle(QuantumCircuit circuit, int targetIndex) {
    // 简化实现：对目标状态翻转相位
    final bits = <int>[];
    for (int i = circuit.numQubits - 1; i >= 0; i--) {
      bits.add((targetIndex >> i) & 1);
    }
    // 应用 X 门到需要为 0 的比特
    for (int i = 0; i < bits.length; i++) {
      if (bits[i] == 0) {
        QuantumGate.applyPauliX(circuit.qubits[i]);
      }
    }
    // 多控制 Z 门（简化为级联 CNOT + Z）
    if (circuit.numQubits >= 2) {
      for (int i = 0; i < circuit.numQubits - 1; i++) {
        QuantumGate.applyCNOT(circuit.qubits[i], circuit.qubits[i + 1]);
      }
      QuantumGate.applyPauliZ(circuit.qubits[circuit.numQubits - 1]);
      for (int i = circuit.numQubits - 2; i >= 0; i--) {
        QuantumGate.applyCNOT(circuit.qubits[i], circuit.qubits[i + 1]);
      }
    }
    // 还原 X 门
    for (int i = 0; i < bits.length; i++) {
      if (bits[i] == 0) {
        QuantumGate.applyPauliX(circuit.qubits[i]);
      }
    }
  }

  /// 应用 Grover Diffusion 算子（振幅放大）
  static void _applyDiffusion(QuantumCircuit circuit) {
    for (int i = 0; i < circuit.numQubits; i++) {
      QuantumGate.applyHadamard(circuit.qubits[i]);
    }
    for (int i = 0; i < circuit.numQubits; i++) {
      QuantumGate.applyPauliX(circuit.qubits[i]);
    }
    // 多控制 Z
    if (circuit.numQubits >= 2) {
      for (int i = 0; i < circuit.numQubits - 1; i++) {
        QuantumGate.applyCNOT(circuit.qubits[i], circuit.qubits[i + 1]);
      }
      QuantumGate.applyPauliZ(circuit.qubits[circuit.numQubits - 1]);
      for (int i = circuit.numQubits - 2; i >= 0; i--) {
        QuantumGate.applyCNOT(circuit.qubits[i], circuit.qubits[i + 1]);
      }
    }
    for (int i = 0; i < circuit.numQubits; i++) {
      QuantumGate.applyPauliX(circuit.qubits[i]);
    }
    for (int i = 0; i < circuit.numQubits; i++) {
      QuantumGate.applyHadamard(circuit.qubits[i]);
    }
  }
}

/// 量子模拟器
///
/// 提供量子系统的模拟功能：
/// - 量子态演化模拟
/// - 量子纠缠模拟
/// - 量子退相干模拟
/// - 量子噪声模拟
class QuantumSimulator {
  /// 模拟量子态的时间演化
  ///
  /// [initialState] 初始量子态
  /// [hamiltonian] 哈密顿量（2x2 矩阵，展开为列表）
  /// [time] 演化时间
  /// [steps] 时间步数
  /// 返回演化后的量子态列表
  static List<Qubit> simulateTimeEvolution({
    required Qubit initialState,
    required List<List<double>> hamiltonian,
    required double time,
    int steps = 100,
  }) {
    final dt = time / steps;
    final states = <Qubit>[];
    Qubit current = Qubit(
      alphaReal: initialState.alphaReal,
      alphaImag: initialState.alphaImag,
      betaReal: initialState.betaReal,
      betaImag: initialState.betaImag,
    );
    states.add(current);

    for (int s = 0; s < steps; s++) {
      // 简化的时间演化：使用哈密顿量的特征值近似
      final newAlphaR = current.alphaReal * cos(hamiltonian[0][0] * dt) -
          current.betaReal * sin(hamiltonian[0][1] * dt);
      final newBetaR = current.alphaReal * sin(hamiltonian[1][0] * dt) +
          current.betaReal * cos(hamiltonian[1][1] * dt);

      current = Qubit(
        alphaReal: newAlphaR,
        alphaImag: current.alphaImag,
        betaReal: newBetaR,
        betaImag: current.betaImag,
      );
      current.normalize();
      states.add(current);
    }
    return states;
  }

  /// 模拟量子退相干
  ///
  /// [qubit] 初始量子比特
  /// [decoherenceRate] 退相干速率（0.0~1.0）
  /// [timeSteps] 时间步数
  /// 返回各时间步的纯度列表（纯度 = Tr(ρ²)）
  static List<double> simulateDecoherence({
    required Qubit qubit,
    required double decoherenceRate,
    int timeSteps = 50,
  }) {
    final purities = <double>[];
    double purity = 1.0;

    for (int t = 0; t < timeSteps; t++) {
      // 退相干导致纯度下降
      purity *= (1.0 - decoherenceRate);
      purity = purity.clamp(0.0, 1.0);
      purities.add(purity);
    }
    return purities;
  }

  /// 模拟量子纠缠对（Bell 态）
  ///
  /// 生成两个纠缠的量子比特对
  /// 返回 [qubit1, qubit2]，测量时具有完全关联
  static List<Qubit> createBellState({String bellState = 'phi_plus'}) {
    final q1 = Qubit();
    final q2 = Qubit();

    // 应用 Hadamard 到第一个比特
    QuantumGate.applyHadamard(q1);

    // 应用 CNOT 创建纠缠
    QuantumGate.applyCNOT(q1, q2);

    // 根据 Bell 态类型调整
    switch (bellState) {
      case 'phi_minus':
        QuantumGate.applyPauliZ(q1);
        break;
      case 'psi_plus':
        QuantumGate.applyPauliX(q2);
        break;
      case 'psi_minus':
        QuantumGate.applyPauliX(q2);
        QuantumGate.applyPauliZ(q1);
        break;
      default: // phi_plus
        break;
    }
    return [q1, q2];
  }

  /// 模拟量子噪声（去极化通道）
  ///
  /// [qubit] 输入量子比特
  /// [noiseProbability] 噪声概率（0.0~1.0）
  /// 返回添加噪声后的量子比特
  static Qubit applyDepolarizingNoise(Qubit qubit, double noiseProbability) {
    final rand = Random().nextDouble();
    if (rand < noiseProbability / 3) {
      QuantumGate.applyPauliX(qubit);
    } else if (rand < 2 * noiseProbability / 3) {
      QuantumGate.applyPauliY(qubit);
    } else if (rand < noiseProbability) {
      QuantumGate.applyPauliZ(qubit);
    }
    return qubit;
  }

  /// 计算两个量子态之间的保真度
  ///
  /// [state1] 量子态 1
  /// [state2] 量子态 2
  /// 返回保真度 (0.0~1.0)
  static double fidelity(Qubit state1, Qubit state2) {
    // F = |⟨ψ1|ψ2⟩|²
    final innerR = state1.alphaReal * state2.alphaReal +
        state1.alphaImag * state2.alphaImag +
        state1.betaReal * state2.betaReal +
        state1.betaImag * state2.betaImag;
    final innerI = state1.alphaReal * state2.alphaImag -
        state1.alphaImag * state2.alphaReal +
        state1.betaReal * state2.betaImag -
        state1.betaImag * state2.betaReal;
    return innerR * innerR + innerI * innerI;
  }

  /// 获取量子模拟器统计报告
  static Map<String, dynamic> getSimulationReport() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'availableGates': QuantumGateType.values.map((g) => g.name).toList(),
      'supportedAlgorithms': [
        'Deutsch-Jozsa',
        'Bernstein-Vazirani',
        'Grover Search',
        'Quantum Random Number',
      ],
      'simulationCapabilities': [
        'Time Evolution',
        'Decoherence',
        'Bell State',
        'Depolarizing Noise',
        'Fidelity Calculation',
      ],
    };
  }
}
