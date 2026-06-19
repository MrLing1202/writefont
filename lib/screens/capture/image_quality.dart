import 'dart:io';
import 'package:image/image.dart' as img;

/// 图片质量检测结果
class ImageQualityResult {
  final double brightness; // 平均灰度值 (0-255)
  final double sharpness; // 拉普拉斯方差
  final String summary; // 质量总结
  final QualityLevel level; // 质量等级

  ImageQualityResult({
    required this.brightness,
    required this.sharpness,
    required this.summary,
    required this.level,
  });
}

enum QualityLevel { good, medium, poor }

/// 检测图片质量（亮度 + 模糊度）
Future<ImageQualityResult> detectImageQuality(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return ImageQualityResult(
      brightness: 0,
      sharpness: 0,
      summary: '无法解析图片',
      level: QualityLevel.poor,
    );
  }

  // 缩小图片以加速计算（最长边 300px）
  final resized = img.copyResize(decoded, width: decoded.width > decoded.height ? 300 : null, height: decoded.height >= decoded.width ? 300 : null);
  final width = resized.width;
  final height = resized.height;
  final pixels = resized;

  // 1. 计算平均灰度值（亮度）
  double totalBrightness = 0;
  final pixelCount = width * height;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final pixel = pixels.getPixel(x, y);
      final gray = pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
      totalBrightness += gray;
    }
  }
  final avgBrightness = totalBrightness / pixelCount;

  // 2. 拉普拉斯方差法检测模糊
  final grayImg = img.grayscale(resized);
  double laplacianSum = 0;
  double laplacianSqSum = 0;
  int laplacianCount = 0;

  // 3×3 拉普拉斯算子: [0,1,0; 1,-4,1; 0,1,0]
  for (int y = 1; y < height - 1; y++) {
    for (int x = 1; x < width - 1; x++) {
      final center = grayImg.getPixel(x, y).r.toDouble();
      final top = grayImg.getPixel(x, y - 1).r.toDouble();
      final bottom = grayImg.getPixel(x, y + 1).r.toDouble();
      final left = grayImg.getPixel(x - 1, y).r.toDouble();
      final right = grayImg.getPixel(x + 1, y).r.toDouble();

      final laplacian = top + bottom + left + right - 4 * center;
      laplacianSum += laplacian;
      laplacianSqSum += laplacian * laplacian;
      laplacianCount++;
    }
  }

  final laplacianMean = laplacianSum / laplacianCount;
  final laplacianVariance = (laplacianSqSum / laplacianCount) - (laplacianMean * laplacianMean);

  // 3. 评估质量
  final bool isDark = avgBrightness < 50;
  final bool isBright = avgBrightness > 220;
  final bool isBlurry = laplacianVariance < 100;
  final bool isSlightlyDark = avgBrightness < 80;
  final bool isSlightlyBright = avgBrightness > 200;
  final bool isSlightlyBlurry = laplacianVariance < 200;

  final List<String> issues = [];
  if (isDark) {
    issues.add('图片较暗');
  } else if (isSlightlyDark) {
    issues.add('光线略暗');
  }
  if (isBright) {
    issues.add('图片过亮');
  } else if (isSlightlyBright) {
    issues.add('光线略亮');
  }
  if (isBlurry) {
    issues.add('图片模糊');
  } else if (isSlightlyBlurry) {
    issues.add('可能有轻微模糊');
  }

  QualityLevel level;
  String summary;
  if (isDark || isBright || isBlurry) {
    level = QualityLevel.poor;
    summary = issues.join('、');
  } else if (isSlightlyDark || isSlightlyBright || isSlightlyBlurry) {
    level = QualityLevel.medium;
    summary = issues.isNotEmpty ? issues.join('、') : '质量一般';
  } else {
    level = QualityLevel.good;
    summary = '图片清晰，亮度适中';
  }

  return ImageQualityResult(
    brightness: avgBrightness,
    sharpness: laplacianVariance,
    summary: summary,
    level: level,
  );
}
