import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/project.dart';

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

    // Convert to grayscale
    final gray = img.grayscale(image);

    // Apply contrast
    final contrasted = img.adjustColor(gray, contrast: params.contrast);

    // Apply threshold to create binary image
    final binary = _binarize(contrasted, params.threshold, params.invertColors);

    // Apply morphological operations
    img.Image processed = binary;
    for (int i = 0; i < params.erosion; i++) {
      processed = _erode(processed);
    }
    for (int i = 0; i < params.dilation; i++) {
      processed = _dilate(processed);
    }

    // --- Adaptive connected component segmentation ---
    final w = processed.width;
    final h = processed.height;
    final totalArea = w * h;
    final minArea = (totalArea * 0.001).toInt();   // 0.1% — filter noise
    final maxArea = (totalArea * 0.15).toInt();     // 15%  — filter multi-char blobs (e.g. nine-grid)

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
  static List<Contour> extractContours(
    Uint8List imageBytes,
    ProcessingParams params,
  ) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return [];

    final gray = img.grayscale(image);
    final binary = _binarize(gray, params.threshold, params.invertColors);

    // Find connected components and trace contours
    final List<Contour> allContours = [];
    final visited = List.generate(
      binary.height,
      (_) => List.filled(binary.width, false),
    );

    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        if (!visited[y][x] && _isBlack(binary, x, y)) {
          final contour = _traceContour(binary, x, y, visited);
          if (contour.length > 4) {
            // Scale to font units (0-1000) with Y-axis flipped
            final scaled = _scaleContour(contour, binary.width, binary.height, params.strokeWidth);
            final simplified = _simplifyContour(scaled, params.smoothness * 3 + 1);
            if (simplified.length >= 3) {
              allContours.add(Contour(simplified));
            }
          }
        }
      }
    }

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
    final result = img.Image(width: binary.width, height: binary.height);
    final kernelSize = (amount * 2 + 1).toInt();
    final half = kernelSize ~/ 2;

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
      if (!found) break;

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
