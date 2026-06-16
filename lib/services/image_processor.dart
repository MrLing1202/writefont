import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Offset;
import 'package:image/image.dart' as img;

/// 图像处理服务 - 负责将手写字符图片转换为字形轮廓
class ImageProcessor {
  /// 将图片二值化（黑白化）
  static Uint8List binarizeImage(
    Uint8List imageBytes, {
    double threshold = 128.0,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return imageBytes;

    // 转灰度
    final grayscale = img.grayscale(image);

    // 二值化
    final width = grayscale.width;
    final height = grayscale.height;
    final result = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final luminance = pixel.r.toDouble();
        if (luminance < threshold) {
          result.setPixelRgba(x, y, 0, 0, 0, 255);
        } else {
          result.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }

    return Uint8List.fromList(img.encodePng(result));
  }

  /// 从图片中检测单个字符区域并裁剪
  static List<Uint8List> extractCharacterRegions(
    Uint8List imageBytes, {
    double threshold = 128.0,
    int minSize = 20,
    int maxSize = 500,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return [];

    final grayscale = img.grayscale(image);
    final width = grayscale.width;
    final height = grayscale.height;

    // 创建二值化矩阵
    List<List<bool>> binary = List.generate(
      height,
      (y) => List.generate(
        width,
        (x) => grayscale.getPixel(x, y).r.toDouble() < threshold,
      ),
    );

    // 连通区域标记 (flood fill)
    List<Rect> regions = [];
    List<List<bool>> visited = List.generate(
      height,
      (y) => List.generate(width, (x) => false),
    );

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (binary[y][x] && !visited[y][x]) {
          final region = _floodFill(binary, visited, x, y, width, height);
          final regionWidth = region.right - region.left;
          final regionHeight = region.bottom - region.top;

          if (regionWidth >= minSize &&
              regionWidth <= maxSize &&
              regionHeight >= minSize &&
              regionHeight <= maxSize) {
            regions.add(region);
          }
        }
      }
    }

    // 按位置排序（从左到右，从上到下）
    regions.sort((a, b) {
      final rowDiff = (a.top ~/ (maxSize * 0.5)) - (b.top ~/ (maxSize * 0.5));
      if (rowDiff.abs() < 1) {
        return a.left.compareTo(b.left);
      }
      return rowDiff;
      //return a.top.compareTo(b.top);
    });

    // 裁剪每个区域
    List<Uint8List> results = [];
    for (final region in regions) {
      final padding = 10;
      final left = max(0, region.left - padding);
      final top = max(0, region.top - padding);
      final right = min(width, region.right + padding);
      final bottom = min(height, region.bottom + padding);

      final cropped = img.copyCrop(
        grayscale,
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      );
      results.add(Uint8List.fromList(img.encodePng(cropped)));
    }

    return results;
  }

  /// Flood fill 连通区域检测
  static Rect _floodFill(
    List<List<bool>> binary,
    List<List<bool>> visited,
    int startX,
    int startY,
    int width,
    int height,
  ) {
    int left = startX, right = startX;
    int top = startY, bottom = startY;

    final queue = <List<int>>[];
    queue.add([startX, startY]);
    visited[startY][startX] = true;

    while (queue.isNotEmpty) {
      final point = queue.removeLast();
      final x = point[0], y = point[1];

      left = min(left, x);
      right = max(right, x);
      top = min(top, y);
      bottom = max(bottom, y);

      // 8 方向连通
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 &&
              nx < width &&
              ny >= 0 &&
              ny < height &&
              binary[ny][nx] &&
              !visited[ny][nx]) {
            visited[ny][nx] = true;
            queue.add([nx, ny]);
          }
        }
      }
    }

    return Rect(left, top, right, bottom);
  }

  /// 提取轮廓点（使用 marching squares 算法）
  static List<List<Offset>> extractContours(
    Uint8List imageBytes, {
    double threshold = 128.0,
    double smoothness = 0.5,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return [];

    final grayscale = img.grayscale(image);
    final width = grayscale.width;
    final height = grayscale.height;

    // 创建二值化矩阵，加一圈边框
    final gridWidth = width + 2;
    final gridHeight = height + 2;
    List<List<bool>> grid = List.generate(
      gridHeight,
      (y) => List.generate(
        gridWidth,
        (x) {
          if (x == 0 || x == gridWidth - 1 || y == 0 || y == gridHeight - 1) {
            return false;
          }
          return grayscale.getPixel(x - 1, y - 1).r.toDouble() < threshold;
        },
      ),
    );

    // Marching squares 轮廓追踪
    List<List<Offset>> allContours = [];
    List<List<bool>> processed = List.generate(
      gridHeight,
      (y) => List.generate(gridWidth, (x) => false),
    );

    for (int y = 0; y < gridHeight - 1; y++) {
      for (int x = 0; x < gridWidth - 1; x++) {
        final tl = grid[y][x] ? 1 : 0;
        final tr = grid[y][x + 1] ? 1 : 0;
        final br = grid[y + 1][x + 1] ? 1 : 0;
        final bl = grid[y + 1][x] ? 1 : 0;
        final caseIndex = tl * 8 + tr * 4 + br * 2 + bl;

        if (caseIndex != 0 && caseIndex != 15 && !processed[y][x]) {
          final contour = _traceContour(grid, x, y, gridWidth, gridHeight);
          if (contour.length > 4) {
            // 转换坐标（减去边框偏移，转为字体坐标系）
            final scaledContour = contour
                .map((p) => Offset(p.dx - 1, p.dy - 1))
                .toList();
            // 平滑处理
            final smoothed = _smoothContour(scaledContour, smoothness);
            allContours.add(smoothed);
            // 标记已处理
            for (final p in contour) {
              final px = p.dx.round();
              final py = p.dy.round();
              if (px >= 0 && px < gridWidth && py >= 0 && py < gridHeight) {
                processed[py][px] = true;
              }
            }
          }
        }
      }
    }

    return allContours;
  }

  /// 追踪单条轮廓
  static List<Offset> _traceContour(
    List<List<bool>> grid,
    int startX,
    int startY,
    int width,
    int height,
  ) {
    List<Offset> points = [];
    int x = startX, y = startY;
    int dir = 0; // 0=右, 1=下, 2=左, 3=上
    final maxSteps = width * height;
    int steps = 0;

    do {
      points.add(Offset(x.toDouble() + 0.5, y.toDouble() + 0.5));

      // 根据当前cell状态决定移动方向
      final tl = grid[y][x] ? 1 : 0;
      final tr = grid[y][x + 1] ? 1 : 0;
      final br = grid[y + 1][x + 1] ? 1 : 0;
      final bl = grid[y + 1][x] ? 1 : 0;

      bool moved = false;
      for (int i = 0; i < 8 && !moved; i++) {
        int newDir = (dir + (i.isEven ? i ~/ 2 : -(i + 1) ~/ 2)) % 4;
        if (newDir < 0) newDir += 4;

        int nx = x, ny = y;
        switch (newDir) {
          case 0:
            nx = x + 1;
            break; // 右
          case 1:
            ny = y + 1;
            break; // 下
          case 2:
            nx = x - 1;
            break; // 左
          case 3:
            ny = y - 1;
            break; // 上
        }

        if (nx >= 0 && nx < width - 1 && ny >= 0 && ny < height - 1) {
          x = nx;
          y = ny;
          dir = newDir;
          moved = true;
        }
      }

      if (!moved) break;
      steps++;
    } while ((x != startX || y != startY) && steps < maxSteps);

    return points;
  }

  /// 平滑轮廓（Douglas-Peucker 简化 + 均匀采样）
  static List<Offset> _smoothContour(List<Offset> points, double smoothness) {
    if (points.length < 3) return points;

    // Douglas-Peucker 简化
    final epsilon = 1.0 + smoothness * 3.0;
    final simplified = _douglasPeucker(points, epsilon);

    return simplified;
  }

  /// Douglas-Peucker 线简化算法
  static List<Offset> _douglasPeucker(List<Offset> points, double epsilon) {
    if (points.length <= 2) return points;

    double maxDist = 0;
    int maxIndex = 0;
    final start = points.first;
    final end = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      final dist = _perpendicularDistance(points[i], start, end);
      if (dist > maxDist) {
        maxDist = dist;
        maxIndex = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _douglasPeucker(
          points.sublist(0, maxIndex + 1), epsilon);
      final right =
          _douglasPeucker(points.sublist(maxIndex), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [start, end];
    }
  }

  /// 点到线段的垂直距离
  static double _perpendicularDistance(
      Offset point, Offset lineStart, Offset lineEnd) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;

    if (dx == 0 && dy == 0) {
      return (point - lineStart).distance;
    }

    final t =
        ((point.dx - lineStart.dx) * dx + (point.dy - lineStart.dy) * dy) /
            (dx * dx + dy * dy);

    final clampedT = t.clamp(0.0, 1.0);
    final projX = lineStart.dx + clampedT * dx;
    final projY = lineStart.dy + clampedT * dy;

    return (point - Offset(projX, projY)).distance;
  }
}

/// 简单的矩形类
class Rect {
  final int left, top, right, bottom;
  const Rect(this.left, this.top, this.right, this.bottom);
}
