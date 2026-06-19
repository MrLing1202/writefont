import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/project.dart';

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

  for (int y = 0; y < binary.height; y++) {
    for (int x = 0; x < binary.width; x++) {
      if (!visited[y][x] && ImageProcessor._isBlack(binary, x, y)) {
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
  final queue = <List<int>>[];
  for (int x = 0; x < w; x++) {
    if (!ImageProcessor._isBlack(binary, x, 0)) {
      queue.add([x, 0]);
      isExterior[0][x] = true;
    }
    if (!ImageProcessor._isBlack(binary, x, h - 1)) {
      queue.add([x, h - 1]);
      isExterior[h - 1][x] = true;
    }
  }
  for (int y = 1; y < h - 1; y++) {
    if (!ImageProcessor._isBlack(binary, 0, y)) {
      queue.add([0, y]);
      isExterior[y][0] = true;
    }
    if (!ImageProcessor._isBlack(binary, w - 1, y)) {
      queue.add([w - 1, y]);
      isExterior[y][w - 1] = true;
    }
  }
  while (queue.isNotEmpty) {
    final p = queue.removeAt(0);
    for (final d in bfsDirs4) {
      final nx = p[0] + d[0], ny = p[1] + d[1];
      if (nx >= 0 &&
          nx < w &&
          ny >= 0 &&
          ny < h &&
          !isExterior[ny][nx] &&
          !ImageProcessor._isBlack(binary, nx, ny)) {
        isExterior[ny][nx] = true;
        queue.add([nx, ny]);
      }
    }
  }

  // Find interior white regions (holes) and trace their contours
  final holeVisited = List.generate(h, (_) => List.filled(w, false));

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (ImageProcessor._isBlack(binary, x, y) ||
          isExterior[y][x] ||
          holeVisited[y][x]) continue;

      final holePixels = <Point>[];
      int minX = x, maxX = x, minY = y, maxY = y;
      final holeQueue = <List<int>>[];
      holeQueue.add([x, y]);
      holeVisited[y][x] = true;

      while (holeQueue.isNotEmpty) {
        final p = holeQueue.removeAt(0);
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
              !ImageProcessor._isBlack(binary, nx, ny) &&
              !isExterior[ny][nx]) {
            holeVisited[ny][nx] = true;
            holeQueue.add([nx, ny]);
          }
        }
      }

      if (holePixels.length < 4) continue;
      final holeW = maxX - minX + 1;
      final holeH = maxY - minY + 1;
      if (holeW > w * 0.4 || holeH > h * 0.4) continue;

      int bx = -1, by = -1;
      for (final p in holePixels) {
        if (p.x > 0 && ImageProcessor._isBlack(binary, p.x - 1, p.y)) {
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
                ImageProcessor._isBlack(binary, nx, ny)) {
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
              ImageProcessor._isBlack(binary, nx, ny)) {
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
class ImageProcessor {
  /// Process a source image into individual character glyphs.
  /// Assumes characters are written on a grid (e.g., graph paper).
  /// Returns a map of character string -> binary image data.
  static List<Uint8List> segmentCharacters(
    Uint8List imageBytes,
    ProcessingParams params,
  ) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return [];

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

    // Apply morphological operations
    img.Image processed = binary;
    // Scale erosion/dilation based on resolution relative to a 1500px reference
    final resolutionScale = refWidth / 1500.0;
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

    // Each entry: [minX, minY, maxX, maxY, area]
    final List<List<int>> bboxes = [];

    for (int sy = 0; sy < h; sy++) {
      for (int sx = 0; sx < w; sx++) {
        if (visited[sy][sx] || !_isBlack(processed, sx, sy)) continue;

        // BFS
        int minX = sx, maxX = sx, minY = sy, maxY = sy, area = 0;
        final queue = <List<int>>[];
        queue.add([sx, sy]);
        visited[sy][sx] = true;

        while (queue.isNotEmpty) {
          final p = queue.removeAt(0);
          final px = p[0], py = p[1];
          area++;
          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;

          for (final d in directions) {
            final nx = px + d[0], ny = py + d[1];
            if (nx >= 0 && nx < w && ny >= 0 && ny < h &&
                !visited[ny][nx] && _isBlack(processed, nx, ny)) {
              visited[ny][nx] = true;
              queue.add([nx, ny]);
            }
          }
        }

        // Filter by area
        if (area < minArea || area > maxArea) continue;

        // Filter by dimension ratio: single character shouldn't exceed 45% of image width/height
        final bw = maxX - minX + 1;
        final bh = maxY - minY + 1;
        if (bw > w * 0.45 || bh > h * 0.45) continue;

        // Filter by aspect ratio: single character should be roughly square (< 2.5:1)
        final aspect = bw > bh ? bw / bh : bh / bw;
        if (aspect > 2.5) continue;

        bboxes.add([minX, minY, maxX, maxY, area]);
      }
    }

    debugPrint('轮廓提取: 找到 ${bboxes.length} 个连通区域 (图片 ${w}x$h)');

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
  }

  /// Process a single character image with given parameters.
  static Uint8List processCharacterImage(
    Uint8List imageBytes,
    ProcessingParams params,
  ) {
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

    return img.encodePng(processed);
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

    onProgress?.call(1.0, '轮廓提取完成');
    return allContours;
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
}

class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);
}
