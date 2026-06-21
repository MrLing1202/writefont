import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 笔画特征数据类
///
/// 包含笔画数量、主要方向分布、结构类型三个维度的特征。
class StrokeFeature {
  /// 笔画数量估算
  final int strokeCount;

  /// 主要笔画方向分布 (各方向权重 0.0~1.0)
  final Map<String, double> directions;

  /// 字形结构类型
  final CharStructure structure;

  const StrokeFeature({
    required this.strokeCount,
    required this.directions,
    required this.structure,
  });

  /// 计算两个特征之间的相似度 (0.0~1.0)
  double similarityTo(StrokeFeature other) {
    // 1. 笔画数量相似度 (权重 0.4)
    final countDiff = (strokeCount - other.strokeCount).abs();
    final countSimilarity = countDiff == 0
        ? 1.0
        : countDiff == 1
            ? 0.7
            : countDiff == 2
                ? 0.4
                : max(0.0, 1.0 - countDiff * 0.15);

    // 2. 方向相似度 (权重 0.35)
    double directionSimilarity = 0.0;
    double totalWeight = 0.0;
    for (final key in ['heng', 'shu', 'pie', 'na']) {
      final a = directions[key] ?? 0.0;
      final b = other.directions[key] ?? 0.0;
      directionSimilarity += 1.0 - (a - b).abs();
      totalWeight += 1.0;
    }
    directionSimilarity = totalWeight > 0 ? directionSimilarity / totalWeight : 0.0;

    // 3. 结构相似度 (权重 0.25)
    final structureSimilarity = structure == other.structure ? 1.0 : 0.3;

    return countSimilarity * 0.4 +
        directionSimilarity * 0.35 +
        structureSimilarity * 0.25;
  }

  Map<String, dynamic> toJson() => {
        'strokeCount': strokeCount,
        'directions': directions,
        'structure': structure.name,
      };

  @override
  String toString() =>
      'StrokeFeature(count=$strokeCount, dir=$directions, struct=${structure.name})';
}

/// 字形结构类型
enum CharStructure {
  /// 独体字
  single,

  /// 左右结构 (如 "明"、"好")
  leftRight,

  /// 上下结构 (如 "思"、"花")
  topBottom,

  /// 包围结构 (如 "国"、"回")
  surround,

  /// 半包围 (如 "远"、"病")
  semiSurround,

  /// 左中右结构 (如 "做")
  leftMiddleRight,

  /// 上中下结构 (如 "意")
  topMiddleBottom,
}

/// 笔画特征分析服务
///
/// 通过图片像素级分析，提取笔画数量、方向、结构三个维度的特征。
/// 用于低置信度识别场景下的候选字符辅助选择。
class StrokeAnalyzer {
  static StrokeAnalyzer? _instance;
  static StrokeAnalyzer get instance => _instance ??= StrokeAnalyzer._();

  StrokeAnalyzer._();

  // ═══════════════════════════════════════════════════════════
  // 公开 API
  // ═══════════════════════════════════════════════════════════

  /// 分析图片的笔画特征签名（整合三个维度）
  ///
  /// [imageBytes] PNG/JPEG 图片的原始字节
  /// 返回完整的笔画特征，分析失败时返回 null
  StrokeFeature? getStrokeSignatureFromBytes(Uint8List imageBytes) {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;
      return getStrokeSignature(decoded);
    } catch (e) {
      debugPrint('笔画分析: 解码图片失败 $e');
      return null;
    }
  }

  /// 分析 img.Image 的笔画特征签名
  StrokeFeature getStrokeSignature(img.Image image) {
    final binary = _preprocess(image);
    final skeleton = _skeletonize(binary);

    final count = analyzeStrokeCount(skeleton);
    final dirs = analyzeStrokeDirection(skeleton);
    final structure = analyzeStructure(binary);

    debugPrint('笔画分析: 笔画数=$count, 方向=$dirs, 结构=${structure.name}');

    return StrokeFeature(
      strokeCount: count,
      directions: dirs,
      structure: structure,
    );
  }

  /// 辅助识别：当置信度低时，用笔画特征从候选中选择最佳
  ///
  /// [imageBytes] 原始图片字节
  /// [currentResult] 当前识别结果
  /// [confidence] 当前置信度
  /// 返回更优的候选字符，无更优选择时返回 null
  Future<String?> assistRecognition(
    Uint8List imageBytes,
    String currentResult,
    double confidence,
  ) async {
    try {
      final feature = getStrokeSignatureFromBytes(imageBytes);
      if (feature == null) return null;

      // 获取候选字符（当前结果 + 形近字）
      final candidates = _getCandidates(currentResult);
      if (candidates.isEmpty) return null;

      // 用笔画特征匹配
      final best = selectBestCandidate(candidates, feature);
      if (best != null && best != currentResult) {
        debugPrint('笔画辅助: "$currentResult" → "$best" (置信度=${(confidence * 100).toStringAsFixed(0)}%)');
        return best;
      }
    } catch (e) {
      debugPrint('笔画辅助识别失败: $e');
    }
    return null;
  }

  /// 从候选列表中选择笔画特征最匹配的字符
  String? selectBestCandidate(List<String> candidates, StrokeFeature actual) {
    if (candidates.isEmpty) return null;

    String? bestChar;
    double bestScore = -1.0;

    for (final char in candidates) {
      final standard = _charStrokeDatabase[char];
      if (standard == null) continue;

      final score = actual.similarityTo(standard);
      if (score > bestScore) {
        bestScore = score;
        bestChar = char;
      }
    }

    return bestChar;
  }

  /// 获取指定字符的标准笔画特征
  StrokeFeature? getStandardFeature(String char) => _charStrokeDatabase[char];

  // ═══════════════════════════════════════════════════════════
  // 笔画数量分析
  // ═══════════════════════════════════════════════════════════

  /// 估算笔画数量
  ///
  /// 通过骨架端点和交叉点分析：
  /// - 端点 (1 个黑色邻居) = 笔画末端
  /// - 交叉点 (≥3 个黑色邻居) = 笔画交汇处
  /// - 笔画数 ≈ (端点数 + 交叉点数) / 2
  int analyzeStrokeCount(img.Image skeleton) {
    final w = skeleton.width, h = skeleton.height;
    int endpoints = 0;
    int junctions = 0;

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        if (_isBlack(skeleton, x, y)) {
          final neighborCount = _countBlackNeighbors(skeleton, x, y);
          if (neighborCount == 1) {
            endpoints++;
          } else if (neighborCount >= 3) {
            junctions++;
          }
        }
      }
    }

    // 笔画数估算公式
    // 每条独立笔画贡献 2 个端点，交叉点连接多条笔画
    final estimate = ((endpoints + junctions) / 2).round();
    return estimate.clamp(1, 30);
  }

  // ═══════════════════════════════════════════════════════════
  // 笔画方向分析
  // ═══════════════════════════════════════════════════════════

  /// 分析主要笔画方向分布
  ///
  /// 对骨架像素计算梯度方向，统计四个方向的权重：
  /// - 横 (heng): 水平方向，角度接近 0° 或 180°
  /// - 竖 (shu): 垂直方向，角度接近 90°
  /// - 撇 (pie): 左上→右下对角，角度约 135°
  /// - 捺 (na): 右上→左下对角，角度约 45°
  Map<String, double> analyzeStrokeDirection(img.Image skeleton) {
    final w = skeleton.width, h = skeleton.height;
    double heng = 0, shu = 0, pie = 0, na = 0;

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        if (!_isBlack(skeleton, x, y)) continue;

        // 用 Sobel 算子计算梯度方向
        final gx = _sobelX(skeleton, x, y);
        final gy = _sobelY(skeleton, x, y);
        if (gx == 0 && gy == 0) continue;

        // 梯度方向垂直于笔画方向
        // gx 大 → 垂直边缘 → 水平笔画 (横)
        // gy 大 → 水平边缘 → 垂直笔画 (竖)
        final absGx = gx.abs().toDouble();
        final absGy = gy.abs().toDouble();
        final magnitude = sqrt(gx * gx + gy * gy).toDouble();
        if (magnitude < 1) continue;

        // 判断主方向
        if (absGx > absGy * 2) {
          heng += magnitude; // 横
        } else if (absGy > absGx * 2) {
          shu += magnitude; // 竖
        } else if (gx * gy > 0) {
          na += magnitude; // 捺 (右下方向)
        } else {
          pie += magnitude; // 撇 (左下方向)
        }
      }
    }

    // 归一化
    final total = heng + shu + pie + na;
    if (total < 1) {
      return {'heng': 0.25, 'shu': 0.25, 'pie': 0.25, 'na': 0.25};
    }

    return {
      'heng': heng / total,
      'shu': shu / total,
      'pie': pie / total,
      'na': na / total,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 字形结构分析
  // ═══════════════════════════════════════════════════════════

  /// 分析字形结构
  ///
  /// 通过墨量分布分析：
  /// 1. 将图片分为 3x3 九宫格
  /// 2. 计算每个格子的墨量占比
  /// 3. 根据墨量分布模式判断结构类型
  CharStructure analyzeStructure(img.Image binary) {
    final w = binary.width, h = binary.height;
    if (w < 10 || h < 10) return CharStructure.single;

    // 统计总墨量
    int totalInk = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (_isBlack(binary, x, y)) totalInk++;
      }
    }
    if (totalInk == 0) return CharStructure.single;

    // 分成 3x3 九宫格，计算每格墨量
    final grid = List.generate(3, (_) => List.filled(3, 0));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (_isBlack(binary, x, y)) {
          final gi = (y * 3 / h).floor().clamp(0, 2);
          final gj = (x * 3 / w).floor().clamp(0, 2);
          grid[gi][gj]++;
        }
      }
    }

    // 计算左/右、上/下、中/边的墨量比
    final leftInk = grid[0][0] + grid[1][0] + grid[2][0];
    final rightInk = grid[0][2] + grid[1][2] + grid[2][2];
    final topInk = grid[0][0] + grid[0][1] + grid[0][2];
    final bottomInk = grid[2][0] + grid[2][1] + grid[2][2];
    final centerInk = grid[1][1];
    final borderInk = totalInk - centerInk;

    // 左右比
    final lrTotal = leftInk + rightInk;
    final lrRatio = lrTotal > 0 ? leftInk / lrTotal : 0.5;

    // 上下比
    final tbTotal = topInk + bottomInk;
    final tbRatio = tbTotal > 0 ? topInk / tbTotal : 0.5;

    // 中心占比
    final centerRatio = totalInk > 0 ? centerInk / totalInk : 0.0;

    // 判断结构
    // 包围结构：中心占比高，四周墨量均匀
    if (centerRatio > 0.25 && borderInk > totalInk * 0.5) {
      // 检查四周是否均匀（上、下、左、右墨量相近）
      final topRatio = totalInk > 0 ? topInk / totalInk : 0;
      final bottomRatio = totalInk > 0 ? bottomInk / totalInk : 0;
      final leftRatio = totalInk > 0 ? leftInk / totalInk : 0;
      final rightRatio = totalInk > 0 ? rightInk / totalInk : 0;
      final borderVariance = _variance([topRatio, bottomRatio, leftRatio, rightRatio]).toDouble();
      if (borderVariance < 0.02) {
        return CharStructure.surround;
      }
      return CharStructure.semiSurround;
    }

    // 左右结构：左右墨量均分，且中间有明显空白
    if (lrRatio > 0.3 && lrRatio < 0.7) {
      // 检查中间列是否相对空白
      final midColInk = grid[0][1] + grid[1][1] + grid[2][1];
      final midColRatio = totalInk > 0 ? midColInk / totalInk : 0;
      if (midColRatio < 0.4) {
        return CharStructure.leftRight;
      }
    }

    // 上下结构：上下墨量均分，且中间有明显空白
    if (tbRatio > 0.3 && tbRatio < 0.7) {
      final midRowInk = grid[1][0] + grid[1][1] + grid[1][2];
      final midRowRatio = totalInk > 0 ? midRowInk / totalInk : 0;
      if (midRowRatio < 0.4) {
        return CharStructure.topBottom;
      }
    }

    // 左中右结构：三列墨量较均匀
    final col0 = grid[0][0] + grid[1][0] + grid[2][0];
    final col1 = grid[0][1] + grid[1][1] + grid[2][1];
    final col2 = grid[0][2] + grid[1][2] + grid[2][2];
    if (col0 > totalInk * 0.2 && col1 > totalInk * 0.2 && col2 > totalInk * 0.2) {
      return CharStructure.leftMiddleRight;
    }

    // 上中下结构：三行墨量较均匀
    final row0 = grid[0][0] + grid[0][1] + grid[0][2];
    final row1 = grid[1][0] + grid[1][1] + grid[1][2];
    final row2 = grid[2][0] + grid[2][1] + grid[2][2];
    if (row0 > totalInk * 0.2 && row1 > totalInk * 0.2 && row2 > totalInk * 0.2) {
      return CharStructure.topMiddleBottom;
    }

    return CharStructure.single;
  }

  // ═══════════════════════════════════════════════════════════
  // 图片预处理（内部使用）
  // ═══════════════════════════════════════════════════════════

  /// 预处理：灰度 → 自适应二值化
  img.Image _preprocess(img.Image src) {
    final gray = img.grayscale(src);
    return _adaptiveBinarize(gray);
  }

  /// 自适应二值化（局部均值法）
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

  /// 形态学细化（骨架化）— Zhang-Suen 算法
  img.Image _skeletonize(img.Image binary) {
    final gray = img.grayscale(binary);
    final w = gray.width, h = gray.height;

    var pixels = List.generate(
        h, (y) => List.generate(w, (x) => gray.getPixel(x, y).r.toInt() < 128));

    bool changed = true;
    int iterations = 0;
    const maxIterations = 50;

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

    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = pixels[y][x] ? 0 : 255;
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // 像素级辅助方法
  // ═══════════════════════════════════════════════════════════

  /// 判断像素是否为黑色（前景）
  bool _isBlack(img.Image image, int x, int y) {
    return image.getPixel(x, y).r.toInt() < 128;
  }

  /// 统计 8-邻域中黑色像素数量
  int _countBlackNeighbors(img.Image image, int x, int y) {
    int count = 0;
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = (x + dx).clamp(0, image.width - 1);
        final ny = (y + dy).clamp(0, image.height - 1);
        if (_isBlack(image, nx, ny)) count++;
      }
    }
    return count;
  }

  /// Sobel X 方向梯度（检测垂直边缘 → 水平笔画）
  int _sobelX(img.Image image, int x, int y) {
    int sum = 0;
    const kernel = [-1, 0, 1, -2, 0, 2, -1, 0, 1];
    int ki = 0;
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        final nx = (x + dx).clamp(0, image.width - 1);
        final ny = (y + dy).clamp(0, image.height - 1);
        sum += image.getPixel(nx, ny).r.toInt() * kernel[ki++];
      }
    }
    return sum;
  }

  /// Sobel Y 方向梯度（检测水平边缘 → 垂直笔画）
  int _sobelY(img.Image image, int x, int y) {
    int sum = 0;
    const kernel = [-1, -2, -1, 0, 0, 0, 1, 2, 1];
    int ki = 0;
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        final nx = (x + dx).clamp(0, image.width - 1);
        final ny = (y + dy).clamp(0, image.height - 1);
        sum += image.getPixel(nx, ny).r.toInt() * kernel[ki++];
      }
    }
    return sum;
  }

  /// 计算方差
  double _variance(List<double> values) {
    if (values.isEmpty) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    double sumSq = 0;
    for (final v in values) {
      sumSq += (v - mean) * (v - mean);
    }
    return sumSq / values.length;
  }

  // ═══════════════════════════════════════════════════════════
  // 候选字符获取
  // ═══════════════════════════════════════════════════════════

  /// 获取候选字符列表（当前结果 + 形近字）
  List<String> _getCandidates(String currentResult) {
    final candidates = <String>[currentResult];

    // 形近字映射
    const similarMap = {
      '已': ['己', '巳'],
      '己': ['已', '巳'],
      '巳': ['已', '己'],
      '未': ['末'],
      '末': ['未'],
      '大': ['太', '犬'],
      '太': ['大', '犬'],
      '犬': ['大', '太'],
      '日': ['目', '且'],
      '目': ['日', '且'],
      '且': ['日', '目'],
      '土': ['士'],
      '士': ['土'],
      '刀': ['力'],
      '力': ['刀'],
      '入': ['人'],
      '人': ['入'],
      '天': ['夫'],
      '夫': ['天'],
      '王': ['玉'],
      '玉': ['王'],
      '干': ['千', '于'],
      '千': ['干', '于'],
      '于': ['干', '千'],
      '田': ['由', '甲'],
      '由': ['田', '甲'],
      '甲': ['田', '由'],
      '白': ['百'],
      '百': ['白'],
      '问': ['间'],
      '间': ['问'],
      '午': ['牛'],
      '牛': ['午'],
      '买': ['卖'],
      '卖': ['买'],
      '贝': ['见'],
      '见': ['贝'],
      '几': ['九'],
      '九': ['几'],
      '万': ['方'],
      '方': ['万'],
      '今': ['令'],
      '令': ['今'],
      '折': ['拆'],
      '拆': ['折'],
      '处': ['外'],
      '外': ['处'],
      '体': ['休'],
      '休': ['体'],
      '候': ['侯'],
      '侯': ['候'],
      '拔': ['拨'],
      '拨': ['拔'],
      '辩': ['辨', '辫'],
      '辨': ['辩', '辫'],
      '辫': ['辩', '辨'],
    };

    final similar = similarMap[currentResult];
    if (similar != null) {
      candidates.addAll(similar);
    }

    return candidates;
  }

  // ═══════════════════════════════════════════════════════════
  // 常用汉字笔画特征数据库
  // ═══════════════════════════════════════════════════════════

  /// 常用汉字的标准笔画特征
  ///
  /// 特征值说明：
  /// - strokeCount: 标准笔画数
  /// - directions: 主要方向权重 (heng/横, shu/竖, pie/撇, na/捺)
  /// - structure: 字形结构类型
  static final Map<String, StrokeFeature> _charStrokeDatabase = {
    // ── 1 画 ──
    '一': StrokeFeature(strokeCount: 1, directions: {'heng': 0.9, 'shu': 0.0, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),
    '乙': StrokeFeature(strokeCount: 1, directions: {'heng': 0.2, 'shu': 0.2, 'pie': 0.3, 'na': 0.3}, structure: CharStructure.single),

    // ── 2 画 ──
    '二': StrokeFeature(strokeCount: 2, directions: {'heng': 0.85, 'shu': 0.05, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.topBottom),
    '十': StrokeFeature(strokeCount: 2, directions: {'heng': 0.5, 'shu': 0.5, 'pie': 0.0, 'na': 0.0}, structure: CharStructure.single),
    '人': StrokeFeature(strokeCount: 2, directions: {'heng': 0.05, 'shu': 0.1, 'pie': 0.5, 'na': 0.35}, structure: CharStructure.single),
    '入': StrokeFeature(strokeCount: 2, directions: {'heng': 0.05, 'shu': 0.1, 'pie': 0.45, 'na': 0.4}, structure: CharStructure.single),
    '八': StrokeFeature(strokeCount: 2, directions: {'heng': 0.05, 'shu': 0.1, 'pie': 0.45, 'na': 0.4}, structure: CharStructure.single),
    '几': StrokeFeature(strokeCount: 2, directions: {'heng': 0.1, 'shu': 0.2, 'pie': 0.4, 'na': 0.3}, structure: CharStructure.single),
    '九': StrokeFeature(strokeCount: 2, directions: {'heng': 0.15, 'shu': 0.15, 'pie': 0.4, 'na': 0.3}, structure: CharStructure.single),
    '力': StrokeFeature(strokeCount: 2, directions: {'heng': 0.15, 'shu': 0.35, 'pie': 0.35, 'na': 0.15}, structure: CharStructure.single),
    '刀': StrokeFeature(strokeCount: 2, directions: {'heng': 0.15, 'shu': 0.4, 'pie': 0.3, 'na': 0.15}, structure: CharStructure.single),
    '又': StrokeFeature(strokeCount: 2, directions: {'heng': 0.1, 'shu': 0.1, 'pie': 0.4, 'na': 0.4}, structure: CharStructure.single),
    '七': StrokeFeature(strokeCount: 2, directions: {'heng': 0.5, 'shu': 0.3, 'pie': 0.1, 'na': 0.1}, structure: CharStructure.single),

    // ── 3 画 ──
    '三': StrokeFeature(strokeCount: 3, directions: {'heng': 0.9, 'shu': 0.0, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.topBottom),
    '大': StrokeFeature(strokeCount: 3, directions: {'heng': 0.3, 'shu': 0.1, 'pie': 0.35, 'na': 0.25}, structure: CharStructure.single),
    '小': StrokeFeature(strokeCount: 3, directions: {'heng': 0.1, 'shu': 0.5, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.single),
    '口': StrokeFeature(strokeCount: 3, directions: {'heng': 0.4, 'shu': 0.5, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),
    '山': StrokeFeature(strokeCount: 3, directions: {'heng': 0.3, 'shu': 0.6, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),
    '千': StrokeFeature(strokeCount: 3, directions: {'heng': 0.4, 'shu': 0.4, 'pie': 0.1, 'na': 0.1}, structure: CharStructure.single),
    '干': StrokeFeature(strokeCount: 3, directions: {'heng': 0.6, 'shu': 0.35, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '于': StrokeFeature(strokeCount: 3, directions: {'heng': 0.5, 'shu': 0.35, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '上': StrokeFeature(strokeCount: 3, directions: {'heng': 0.5, 'shu': 0.45, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '下': StrokeFeature(strokeCount: 3, directions: {'heng': 0.5, 'shu': 0.45, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '土': StrokeFeature(strokeCount: 3, directions: {'heng': 0.5, 'shu': 0.45, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '士': StrokeFeature(strokeCount: 3, directions: {'heng': 0.5, 'shu': 0.45, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '工': StrokeFeature(strokeCount: 3, directions: {'heng': 0.6, 'shu': 0.35, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '女': StrokeFeature(strokeCount: 3, directions: {'heng': 0.25, 'shu': 0.1, 'pie': 0.35, 'na': 0.3}, structure: CharStructure.single),
    '子': StrokeFeature(strokeCount: 3, directions: {'heng': 0.4, 'shu': 0.3, 'pie': 0.15, 'na': 0.15}, structure: CharStructure.single),
    '马': StrokeFeature(strokeCount: 3, directions: {'heng': 0.3, 'shu': 0.35, 'pie': 0.15, 'na': 0.2}, structure: CharStructure.single),
    '也': StrokeFeature(strokeCount: 3, directions: {'heng': 0.2, 'shu': 0.35, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.single),
    '万': StrokeFeature(strokeCount: 3, directions: {'heng': 0.35, 'shu': 0.25, 'pie': 0.25, 'na': 0.15}, structure: CharStructure.single),
    '方': StrokeFeature(strokeCount: 4, directions: {'heng': 0.3, 'shu': 0.3, 'pie': 0.25, 'na': 0.15}, structure: CharStructure.single),

    // ── 4 画 ──
    '王': StrokeFeature(strokeCount: 4, directions: {'heng': 0.6, 'shu': 0.35, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '玉': StrokeFeature(strokeCount: 5, directions: {'heng': 0.5, 'shu': 0.3, 'pie': 0.1, 'na': 0.1}, structure: CharStructure.single),
    '不': StrokeFeature(strokeCount: 4, directions: {'heng': 0.35, 'shu': 0.3, 'pie': 0.2, 'na': 0.15}, structure: CharStructure.single),
    '中': StrokeFeature(strokeCount: 4, directions: {'heng': 0.35, 'shu': 0.55, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),
    '日': StrokeFeature(strokeCount: 4, directions: {'heng': 0.45, 'shu': 0.5, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '月': StrokeFeature(strokeCount: 4, directions: {'heng': 0.35, 'shu': 0.5, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '目': StrokeFeature(strokeCount: 5, directions: {'heng': 0.45, 'shu': 0.5, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '木': StrokeFeature(strokeCount: 4, directions: {'heng': 0.3, 'shu': 0.35, 'pie': 0.2, 'na': 0.15}, structure: CharStructure.single),
    '水': StrokeFeature(strokeCount: 4, directions: {'heng': 0.1, 'shu': 0.35, 'pie': 0.25, 'na': 0.3}, structure: CharStructure.single),
    '火': StrokeFeature(strokeCount: 4, directions: {'heng': 0.1, 'shu': 0.3, 'pie': 0.3, 'na': 0.3}, structure: CharStructure.single),
    '手': StrokeFeature(strokeCount: 4, directions: {'heng': 0.5, 'shu': 0.35, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '心': StrokeFeature(strokeCount: 4, directions: {'heng': 0.2, 'shu': 0.15, 'pie': 0.3, 'na': 0.35}, structure: CharStructure.single),
    '牛': StrokeFeature(strokeCount: 4, directions: {'heng': 0.45, 'shu': 0.45, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),
    '午': StrokeFeature(strokeCount: 4, directions: {'heng': 0.4, 'shu': 0.45, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '天': StrokeFeature(strokeCount: 4, directions: {'heng': 0.45, 'shu': 0.1, 'pie': 0.25, 'na': 0.2}, structure: CharStructure.single),
    '夫': StrokeFeature(strokeCount: 4, directions: {'heng': 0.45, 'shu': 0.2, 'pie': 0.2, 'na': 0.15}, structure: CharStructure.single),
    '太': StrokeFeature(strokeCount: 4, directions: {'heng': 0.25, 'shu': 0.1, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.single),
    '犬': StrokeFeature(strokeCount: 4, directions: {'heng': 0.2, 'shu': 0.15, 'pie': 0.35, 'na': 0.3}, structure: CharStructure.single),
    '今': StrokeFeature(strokeCount: 4, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.25, 'na': 0.2}, structure: CharStructure.topBottom),
    '令': StrokeFeature(strokeCount: 5, directions: {'heng': 0.25, 'shu': 0.3, 'pie': 0.25, 'na': 0.2}, structure: CharStructure.topBottom),

    // ── 5 画 ──
    '田': StrokeFeature(strokeCount: 5, directions: {'heng': 0.4, 'shu': 0.55, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '由': StrokeFeature(strokeCount: 5, directions: {'heng': 0.35, 'shu': 0.5, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '甲': StrokeFeature(strokeCount: 5, directions: {'heng': 0.35, 'shu': 0.55, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),
    '白': StrokeFeature(strokeCount: 5, directions: {'heng': 0.4, 'shu': 0.5, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),
    '百': StrokeFeature(strokeCount: 6, directions: {'heng': 0.45, 'shu': 0.4, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.topBottom),
    '目': StrokeFeature(strokeCount: 5, directions: {'heng': 0.45, 'shu': 0.5, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '且': StrokeFeature(strokeCount: 5, directions: {'heng': 0.45, 'shu': 0.45, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),
    '电': StrokeFeature(strokeCount: 5, directions: {'heng': 0.35, 'shu': 0.5, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '四': StrokeFeature(strokeCount: 5, directions: {'heng': 0.35, 'shu': 0.5, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '出': StrokeFeature(strokeCount: 5, directions: {'heng': 0.3, 'shu': 0.55, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '生': StrokeFeature(strokeCount: 5, directions: {'heng': 0.5, 'shu': 0.4, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),
    '头': StrokeFeature(strokeCount: 5, directions: {'heng': 0.3, 'shu': 0.2, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.single),
    '左': StrokeFeature(strokeCount: 5, directions: {'heng': 0.35, 'shu': 0.15, 'pie': 0.3, 'na': 0.2}, structure: CharStructure.single),
    '右': StrokeFeature(strokeCount: 5, directions: {'heng': 0.35, 'shu': 0.15, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.single),
    '用': StrokeFeature(strokeCount: 5, directions: {'heng': 0.35, 'shu': 0.5, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '半': StrokeFeature(strokeCount: 5, directions: {'heng': 0.4, 'shu': 0.45, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '立': StrokeFeature(strokeCount: 5, directions: {'heng': 0.4, 'shu': 0.3, 'pie': 0.15, 'na': 0.15}, structure: CharStructure.single),
    '正': StrokeFeature(strokeCount: 5, directions: {'heng': 0.5, 'shu': 0.4, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),

    // ── 6 画 ──
    '字': StrokeFeature(strokeCount: 6, directions: {'heng': 0.35, 'shu': 0.35, 'pie': 0.15, 'na': 0.15}, structure: CharStructure.topBottom),
    '问': StrokeFeature(strokeCount: 6, directions: {'heng': 0.3, 'shu': 0.55, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.surround),
    '间': StrokeFeature(strokeCount: 7, directions: {'heng': 0.35, 'shu': 0.5, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.surround),
    '好': StrokeFeature(strokeCount: 6, directions: {'heng': 0.2, 'shu': 0.25, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.leftRight),
    '在': StrokeFeature(strokeCount: 6, directions: {'heng': 0.35, 'shu': 0.25, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.single),
    '有': StrokeFeature(strokeCount: 6, directions: {'heng': 0.4, 'shu': 0.25, 'pie': 0.2, 'na': 0.15}, structure: CharStructure.single),
    '他': StrokeFeature(strokeCount: 5, directions: {'heng': 0.2, 'shu': 0.35, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '她': StrokeFeature(strokeCount: 6, directions: {'heng': 0.2, 'shu': 0.25, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.leftRight),
    '这': StrokeFeature(strokeCount: 7, directions: {'heng': 0.3, 'shu': 0.2, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.semiSurround),
    '那': StrokeFeature(strokeCount: 6, directions: {'heng': 0.3, 'shu': 0.3, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.leftRight),
    '买': StrokeFeature(strokeCount: 6, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.single),
    '卖': StrokeFeature(strokeCount: 8, directions: {'heng': 0.35, 'shu': 0.2, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.topBottom),
    '吗': StrokeFeature(strokeCount: 6, directions: {'heng': 0.25, 'shu': 0.35, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.leftRight),
    '后': StrokeFeature(strokeCount: 6, directions: {'heng': 0.3, 'shu': 0.2, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.single),
    '会': StrokeFeature(strokeCount: 6, directions: {'heng': 0.3, 'shu': 0.2, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.topBottom),
    '年': StrokeFeature(strokeCount: 6, directions: {'heng': 0.45, 'shu': 0.4, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '多': StrokeFeature(strokeCount: 6, directions: {'heng': 0.15, 'shu': 0.15, 'pie': 0.35, 'na': 0.35}, structure: CharStructure.topBottom),
    '同': StrokeFeature(strokeCount: 6, directions: {'heng': 0.3, 'shu': 0.5, 'pie': 0.1, 'na': 0.1}, structure: CharStructure.surround),
    '回': StrokeFeature(strokeCount: 6, directions: {'heng': 0.35, 'shu': 0.55, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.surround),

    // ── 7 画 ──
    '我': StrokeFeature(strokeCount: 7, directions: {'heng': 0.2, 'shu': 0.25, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.single),
    '你': StrokeFeature(strokeCount: 7, directions: {'heng': 0.2, 'shu': 0.3, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.leftRight),
    '他': StrokeFeature(strokeCount: 5, directions: {'heng': 0.2, 'shu': 0.35, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '来': StrokeFeature(strokeCount: 7, directions: {'heng': 0.3, 'shu': 0.3, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.single),
    '时': StrokeFeature(strokeCount: 7, directions: {'heng': 0.3, 'shu': 0.35, 'pie': 0.15, 'na': 0.2}, structure: CharStructure.leftRight),
    '到': StrokeFeature(strokeCount: 8, directions: {'heng': 0.35, 'shu': 0.3, 'pie': 0.15, 'na': 0.2}, structure: CharStructure.leftRight),
    '作': StrokeFeature(strokeCount: 7, directions: {'heng': 0.35, 'shu': 0.25, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.leftRight),
    '走': StrokeFeature(strokeCount: 7, directions: {'heng': 0.35, 'shu': 0.15, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.single),
    '里': StrokeFeature(strokeCount: 7, directions: {'heng': 0.45, 'shu': 0.45, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),
    '没': StrokeFeature(strokeCount: 7, directions: {'heng': 0.2, 'shu': 0.25, 'pie': 0.25, 'na': 0.3}, structure: CharStructure.leftRight),
    '还': StrokeFeature(strokeCount: 7, directions: {'heng': 0.3, 'shu': 0.2, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.semiSurround),
    '进': StrokeFeature(strokeCount: 7, directions: {'heng': 0.25, 'shu': 0.2, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.semiSurround),
    '远': StrokeFeature(strokeCount: 7, directions: {'heng': 0.2, 'shu': 0.2, 'pie': 0.3, 'na': 0.3}, structure: CharStructure.semiSurround),
    '体': StrokeFeature(strokeCount: 7, directions: {'heng': 0.3, 'shu': 0.3, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.leftRight),
    '休': StrokeFeature(strokeCount: 6, directions: {'heng': 0.25, 'shu': 0.3, 'pie': 0.25, 'na': 0.2}, structure: CharStructure.leftRight),

    // ── 8 画 ──
    '国': StrokeFeature(strokeCount: 8, directions: {'heng': 0.35, 'shu': 0.5, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.surround),
    '和': StrokeFeature(strokeCount: 8, directions: {'heng': 0.3, 'shu': 0.3, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.leftRight),
    '的': StrokeFeature(strokeCount: 8, directions: {'heng': 0.25, 'shu': 0.3, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '是': StrokeFeature(strokeCount: 9, directions: {'heng': 0.4, 'shu': 0.2, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.topBottom),
    '明': StrokeFeature(strokeCount: 8, directions: {'heng': 0.3, 'shu': 0.45, 'pie': 0.125, 'na': 0.125}, structure: CharStructure.leftRight),
    '现': StrokeFeature(strokeCount: 8, directions: {'heng': 0.3, 'shu': 0.3, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.leftRight),
    '学': StrokeFeature(strokeCount: 8, directions: {'heng': 0.3, 'shu': 0.3, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.topBottom),
    '事': StrokeFeature(strokeCount: 8, directions: {'heng': 0.45, 'shu': 0.35, 'pie': 0.1, 'na': 0.1}, structure: CharStructure.single),
    '知': StrokeFeature(strokeCount: 8, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '话': StrokeFeature(strokeCount: 8, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '使': StrokeFeature(strokeCount: 8, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.25, 'na': 0.2}, structure: CharStructure.leftRight),
    '候': StrokeFeature(strokeCount: 10, directions: {'heng': 0.25, 'shu': 0.3, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '侯': StrokeFeature(strokeCount: 9, directions: {'heng': 0.25, 'shu': 0.25, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.single),

    // ── 9 画 ──
    '要': StrokeFeature(strokeCount: 9, directions: {'heng': 0.35, 'shu': 0.2, 'pie': 0.25, 'na': 0.2}, structure: CharStructure.topBottom),
    '说': StrokeFeature(strokeCount: 9, directions: {'heng': 0.25, 'shu': 0.25, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.leftRight),
    '就': StrokeFeature(strokeCount: 12, directions: {'heng': 0.3, 'shu': 0.2, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.leftRight),
    '看': StrokeFeature(strokeCount: 9, directions: {'heng': 0.4, 'shu': 0.25, 'pie': 0.2, 'na': 0.15}, structure: CharStructure.topBottom),
    '种': StrokeFeature(strokeCount: 9, directions: {'heng': 0.3, 'shu': 0.35, 'pie': 0.15, 'na': 0.2}, structure: CharStructure.leftRight),
    '点': StrokeFeature(strokeCount: 9, directions: {'heng': 0.3, 'shu': 0.3, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.topBottom),
    '面': StrokeFeature(strokeCount: 9, directions: {'heng': 0.45, 'shu': 0.4, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '前': StrokeFeature(strokeCount: 9, directions: {'heng': 0.35, 'shu': 0.3, 'pie': 0.175, 'na': 0.175}, structure: CharStructure.topBottom),
    '开': StrokeFeature(strokeCount: 4, directions: {'heng': 0.35, 'shu': 0.35, 'pie': 0.15, 'na': 0.15}, structure: CharStructure.single),

    // ── 10+ 画 ──
    '家': StrokeFeature(strokeCount: 10, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.25, 'na': 0.2}, structure: CharStructure.topBottom),
    '能': StrokeFeature(strokeCount: 10, directions: {'heng': 0.25, 'shu': 0.3, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '得': StrokeFeature(strokeCount: 11, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '想': StrokeFeature(strokeCount: 13, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.topBottom),
    '做': StrokeFeature(strokeCount: 11, directions: {'heng': 0.25, 'shu': 0.25, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.leftMiddleRight),
    '意': StrokeFeature(strokeCount: 13, directions: {'heng': 0.35, 'shu': 0.2, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.topMiddleBottom),
    '感': StrokeFeature(strokeCount: 13, directions: {'heng': 0.3, 'shu': 0.2, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.topBottom),
    '谢': StrokeFeature(strokeCount: 12, directions: {'heng': 0.25, 'shu': 0.25, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.leftMiddleRight),

    // ── 更多常用字 ──
    '爱': StrokeFeature(strokeCount: 10, directions: {'heng': 0.25, 'shu': 0.2, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.topBottom),
    '把': StrokeFeature(strokeCount: 7, directions: {'heng': 0.25, 'shu': 0.3, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '被': StrokeFeature(strokeCount: 10, directions: {'heng': 0.25, 'shu': 0.25, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.leftRight),
    '本': StrokeFeature(strokeCount: 5, directions: {'heng': 0.35, 'shu': 0.35, 'pie': 0.15, 'na': 0.15}, structure: CharStructure.single),
    '比': StrokeFeature(strokeCount: 4, directions: {'heng': 0.1, 'shu': 0.5, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.leftRight),
    '边': StrokeFeature(strokeCount: 5, directions: {'heng': 0.2, 'shu': 0.2, 'pie': 0.3, 'na': 0.3}, structure: CharStructure.semiSurround),
    '长': StrokeFeature(strokeCount: 4, directions: {'heng': 0.2, 'shu': 0.25, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.single),
    '常': StrokeFeature(strokeCount: 11, directions: {'heng': 0.35, 'shu': 0.3, 'pie': 0.175, 'na': 0.175}, structure: CharStructure.topBottom),
    '场': StrokeFeature(strokeCount: 6, directions: {'heng': 0.25, 'shu': 0.25, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.leftRight),
    '车': StrokeFeature(strokeCount: 4, directions: {'heng': 0.4, 'shu': 0.4, 'pie': 0.1, 'na': 0.1}, structure: CharStructure.single),
    '成': StrokeFeature(strokeCount: 6, directions: {'heng': 0.2, 'shu': 0.2, 'pie': 0.3, 'na': 0.3}, structure: CharStructure.single),
    '出': StrokeFeature(strokeCount: 5, directions: {'heng': 0.25, 'shu': 0.55, 'pie': 0.1, 'na': 0.1}, structure: CharStructure.single),
    '从': StrokeFeature(strokeCount: 4, directions: {'heng': 0.05, 'shu': 0.15, 'pie': 0.4, 'na': 0.4}, structure: CharStructure.leftRight),
    '当': StrokeFeature(strokeCount: 6, directions: {'heng': 0.35, 'shu': 0.3, 'pie': 0.175, 'na': 0.175}, structure: CharStructure.topBottom),
    '地': StrokeFeature(strokeCount: 6, directions: {'heng': 0.25, 'shu': 0.25, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.leftRight),
    '动': StrokeFeature(strokeCount: 6, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '对': StrokeFeature(strokeCount: 5, directions: {'heng': 0.2, 'shu': 0.25, 'pie': 0.25, 'na': 0.3}, structure: CharStructure.leftRight),
    '发': StrokeFeature(strokeCount: 5, directions: {'heng': 0.2, 'shu': 0.2, 'pie': 0.3, 'na': 0.3}, structure: CharStructure.single),
    '高': StrokeFeature(strokeCount: 10, directions: {'heng': 0.4, 'shu': 0.35, 'pie': 0.125, 'na': 0.125}, structure: CharStructure.topBottom),
    '给': StrokeFeature(strokeCount: 9, directions: {'heng': 0.25, 'shu': 0.25, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.leftRight),
    '工': StrokeFeature(strokeCount: 3, directions: {'heng': 0.6, 'shu': 0.35, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '关': StrokeFeature(strokeCount: 6, directions: {'heng': 0.3, 'shu': 0.15, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.single),
    '过': StrokeFeature(strokeCount: 6, directions: {'heng': 0.25, 'shu': 0.2, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.semiSurround),
    '行': StrokeFeature(strokeCount: 6, directions: {'heng': 0.35, 'shu': 0.25, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.leftRight),
    '很': StrokeFeature(strokeCount: 9, directions: {'heng': 0.2, 'shu': 0.25, 'pie': 0.25, 'na': 0.3}, structure: CharStructure.leftRight),
    '后': StrokeFeature(strokeCount: 6, directions: {'heng': 0.3, 'shu': 0.2, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.single),
    '话': StrokeFeature(strokeCount: 8, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '加': StrokeFeature(strokeCount: 5, directions: {'heng': 0.25, 'shu': 0.3, 'pie': 0.25, 'na': 0.2}, structure: CharStructure.leftRight),
    '见': StrokeFeature(strokeCount: 4, directions: {'heng': 0.25, 'shu': 0.4, 'pie': 0.15, 'na': 0.2}, structure: CharStructure.single),
    '将': StrokeFeature(strokeCount: 9, directions: {'heng': 0.25, 'shu': 0.3, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '经': StrokeFeature(strokeCount: 8, directions: {'heng': 0.3, 'shu': 0.2, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.leftRight),
    '可': StrokeFeature(strokeCount: 5, directions: {'heng': 0.35, 'shu': 0.35, 'pie': 0.15, 'na': 0.15}, structure: CharStructure.single),
    '老': StrokeFeature(strokeCount: 6, directions: {'heng': 0.35, 'shu': 0.2, 'pie': 0.25, 'na': 0.2}, structure: CharStructure.topBottom),
    '了': StrokeFeature(strokeCount: 2, directions: {'heng': 0.3, 'shu': 0.4, 'pie': 0.15, 'na': 0.15}, structure: CharStructure.single),
    '理': StrokeFeature(strokeCount: 11, directions: {'heng': 0.4, 'shu': 0.3, 'pie': 0.15, 'na': 0.15}, structure: CharStructure.leftRight),
    '们': StrokeFeature(strokeCount: 5, directions: {'heng': 0.2, 'shu': 0.45, 'pie': 0.15, 'na': 0.2}, structure: CharStructure.leftRight),
    '么': StrokeFeature(strokeCount: 3, directions: {'heng': 0.1, 'shu': 0.1, 'pie': 0.4, 'na': 0.4}, structure: CharStructure.single),
    '面': StrokeFeature(strokeCount: 9, directions: {'heng': 0.45, 'shu': 0.4, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '民': StrokeFeature(strokeCount: 5, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.25, 'na': 0.2}, structure: CharStructure.single),
    '那': StrokeFeature(strokeCount: 6, directions: {'heng': 0.3, 'shu': 0.3, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.leftRight),
    '你': StrokeFeature(strokeCount: 7, directions: {'heng': 0.2, 'shu': 0.3, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.leftRight),
    '年': StrokeFeature(strokeCount: 6, directions: {'heng': 0.45, 'shu': 0.4, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '起': StrokeFeature(strokeCount: 10, directions: {'heng': 0.25, 'shu': 0.2, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.single),
    '人': StrokeFeature(strokeCount: 2, directions: {'heng': 0.05, 'shu': 0.1, 'pie': 0.5, 'na': 0.35}, structure: CharStructure.single),
    '日': StrokeFeature(strokeCount: 4, directions: {'heng': 0.45, 'shu': 0.5, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '如': StrokeFeature(strokeCount: 6, directions: {'heng': 0.2, 'shu': 0.25, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.leftRight),
    '生': StrokeFeature(strokeCount: 5, directions: {'heng': 0.5, 'shu': 0.4, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),
    '实': StrokeFeature(strokeCount: 8, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.topBottom),
    '十': StrokeFeature(strokeCount: 2, directions: {'heng': 0.5, 'shu': 0.5, 'pie': 0.0, 'na': 0.0}, structure: CharStructure.single),
    '时': StrokeFeature(strokeCount: 7, directions: {'heng': 0.3, 'shu': 0.35, 'pie': 0.15, 'na': 0.2}, structure: CharStructure.leftRight),
    '手': StrokeFeature(strokeCount: 4, directions: {'heng': 0.5, 'shu': 0.35, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '她': StrokeFeature(strokeCount: 6, directions: {'heng': 0.2, 'shu': 0.25, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.leftRight),
    '他': StrokeFeature(strokeCount: 5, directions: {'heng': 0.2, 'shu': 0.35, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '天': StrokeFeature(strokeCount: 4, directions: {'heng': 0.45, 'shu': 0.1, 'pie': 0.25, 'na': 0.2}, structure: CharStructure.single),
    '同': StrokeFeature(strokeCount: 6, directions: {'heng': 0.3, 'shu': 0.5, 'pie': 0.1, 'na': 0.1}, structure: CharStructure.surround),
    '为': StrokeFeature(strokeCount: 4, directions: {'heng': 0.2, 'shu': 0.25, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.single),
    '文': StrokeFeature(strokeCount: 4, directions: {'heng': 0.15, 'shu': 0.1, 'pie': 0.4, 'na': 0.35}, structure: CharStructure.single),
    '无': StrokeFeature(strokeCount: 4, directions: {'heng': 0.3, 'shu': 0.15, 'pie': 0.3, 'na': 0.25}, structure: CharStructure.single),
    '西': StrokeFeature(strokeCount: 6, directions: {'heng': 0.35, 'shu': 0.4, 'pie': 0.125, 'na': 0.125}, structure: CharStructure.single),
    '下': StrokeFeature(strokeCount: 3, directions: {'heng': 0.5, 'shu': 0.45, 'pie': 0.025, 'na': 0.025}, structure: CharStructure.single),
    '先': StrokeFeature(strokeCount: 6, directions: {'heng': 0.35, 'shu': 0.2, 'pie': 0.25, 'na': 0.2}, structure: CharStructure.topBottom),
    '想': StrokeFeature(strokeCount: 13, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.topBottom),
    '小': StrokeFeature(strokeCount: 3, directions: {'heng': 0.1, 'shu': 0.5, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.single),
    '新': StrokeFeature(strokeCount: 13, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '些': StrokeFeature(strokeCount: 8, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.topBottom),
    '心': StrokeFeature(strokeCount: 4, directions: {'heng': 0.2, 'shu': 0.15, 'pie': 0.3, 'na': 0.35}, structure: CharStructure.single),
    '信': StrokeFeature(strokeCount: 9, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.leftRight),
    '样': StrokeFeature(strokeCount: 10, directions: {'heng': 0.3, 'shu': 0.3, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.leftRight),
    '也': StrokeFeature(strokeCount: 3, directions: {'heng': 0.2, 'shu': 0.35, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.single),
    '已': StrokeFeature(strokeCount: 3, directions: {'heng': 0.3, 'shu': 0.3, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.single),
    '己': StrokeFeature(strokeCount: 3, directions: {'heng': 0.25, 'shu': 0.35, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.single),
    '巳': StrokeFeature(strokeCount: 3, directions: {'heng': 0.3, 'shu': 0.35, 'pie': 0.175, 'na': 0.175}, structure: CharStructure.single),
    '以': StrokeFeature(strokeCount: 4, directions: {'heng': 0.1, 'shu': 0.15, 'pie': 0.4, 'na': 0.35}, structure: CharStructure.leftRight),
    '用': StrokeFeature(strokeCount: 5, directions: {'heng': 0.35, 'shu': 0.5, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '又': StrokeFeature(strokeCount: 2, directions: {'heng': 0.1, 'shu': 0.1, 'pie': 0.4, 'na': 0.4}, structure: CharStructure.single),
    '有': StrokeFeature(strokeCount: 6, directions: {'heng': 0.4, 'shu': 0.25, 'pie': 0.2, 'na': 0.15}, structure: CharStructure.single),
    '在': StrokeFeature(strokeCount: 6, directions: {'heng': 0.35, 'shu': 0.25, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.single),
    '这': StrokeFeature(strokeCount: 7, directions: {'heng': 0.3, 'shu': 0.2, 'pie': 0.25, 'na': 0.25}, structure: CharStructure.semiSurround),
    '中': StrokeFeature(strokeCount: 4, directions: {'heng': 0.35, 'shu': 0.55, 'pie': 0.05, 'na': 0.05}, structure: CharStructure.single),
    '主': StrokeFeature(strokeCount: 5, directions: {'heng': 0.5, 'shu': 0.35, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '自': StrokeFeature(strokeCount: 6, directions: {'heng': 0.35, 'shu': 0.5, 'pie': 0.075, 'na': 0.075}, structure: CharStructure.single),
    '子': StrokeFeature(strokeCount: 3, directions: {'heng': 0.4, 'shu': 0.3, 'pie': 0.15, 'na': 0.15}, structure: CharStructure.single),
    '总': StrokeFeature(strokeCount: 9, directions: {'heng': 0.3, 'shu': 0.25, 'pie': 0.2, 'na': 0.25}, structure: CharStructure.topBottom),
    '最': StrokeFeature(strokeCount: 12, directions: {'heng': 0.35, 'shu': 0.25, 'pie': 0.2, 'na': 0.2}, structure: CharStructure.topBottom),
  };
}
