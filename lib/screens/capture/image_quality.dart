import 'dart:io';
import 'package:image/image.dart' as img;

/// 图片质量检测结果
class ImageQualityResult {
  final double brightness; // 平均灰度值 (0-255)
  final double sharpness; // 拉普拉斯方差
  final double contrast; // 对比度（标准差）
  final String summary; // 质量总结
  final QualityLevel level; // 质量等级
  final List<String> suggestions; // 具体操作建议

  ImageQualityResult({
    required this.brightness,
    required this.sharpness,
    required this.contrast,
    required this.summary,
    required this.level,
    this.suggestions = const [],
  });
}

enum QualityLevel { good, medium, poor }

/// 检测图片质量（亮度 + 模糊度 + 对比度）
/// 使用采样策略提升性能：缩放至 200px，每 4 像素取 1
Future<ImageQualityResult> detectImageQuality(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return ImageQualityResult(
      brightness: 0,
      sharpness: 0,
      contrast: 0,
      summary: '无法解析图片',
      level: QualityLevel.poor,
      suggestions: ['请重新拍照或选择其他图片'],
    );
  }

  // 缩小图片以加速计算（最长边 200px，比原 300px 更快）
  final resized = img.copyResize(decoded,
      width: decoded.width > decoded.height ? 200 : null,
      height: decoded.height >= decoded.width ? 200 : null);
  final width = resized.width;
  final height = resized.height;

  // 1. 采样计算平均灰度值（亮度） — 每 4 个像素取 1 个
  double totalBrightness = 0;
  int sampledCount = 0;
  for (int y = 0; y < height; y += 2) {
    for (int x = 0; x < width; x += 2) {
      final pixel = resized.getPixel(x, y);
      totalBrightness += pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
      sampledCount++;
    }
  }
  final avgBrightness = totalBrightness / sampledCount;

  // 2. 采样计算对比度（灰度标准差）
  double sqDiffSum = 0;
  for (int y = 0; y < height; y += 2) {
    for (int x = 0; x < width; x += 2) {
      final pixel = resized.getPixel(x, y);
      final gray = pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
      sqDiffSum += (gray - avgBrightness) * (gray - avgBrightness);
    }
  }
  final contrast = (sqDiffSum / sampledCount > 0)
      ? (sqDiffSum / sampledCount)
      : 0.0;

  // 3. 采样拉普拉斯方差法检测模糊（每 4 个像素取 1）
  final grayImg = img.grayscale(resized);
  double laplacianSum = 0;
  double laplacianSqSum = 0;
  int laplacianCount = 0;

  // 3×3 拉普拉斯算子: [0,1,0; 1,-4,1; 0,1,0]
  for (int y = 2; y < height - 1; y += 2) {
    for (int x = 2; x < width - 1; x += 2) {
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
  final laplacianVariance =
      (laplacianSqSum / laplacianCount) - (laplacianMean * laplacianMean);

  // 4. 评估质量
  final bool isDark = avgBrightness < 50;
  final bool isBright = avgBrightness > 220;
  final bool isBlurry = laplacianVariance < 100;
  final bool isLowContrast = contrast < 500;
  final bool isSlightlyDark = avgBrightness < 80;
  final bool isSlightlyBright = avgBrightness > 200;
  final bool isSlightlyBlurry = laplacianVariance < 200;
  final bool isSlightlyLowContrast = contrast < 1000;

  final List<String> issues = [];
  final List<String> suggestions = [];

  if (isDark) {
    issues.add('图片较暗');
    suggestions.add('请在光线充足的环境下重新拍照');
  } else if (isSlightlyDark) {
    issues.add('光线略暗');
    suggestions.add('建议靠近光源或打开闪光灯');
  }
  if (isBright) {
    issues.add('图片过亮');
    suggestions.add('避免强光直射，可调整拍摄角度');
  } else if (isSlightlyBright) {
    issues.add('光线略亮');
    suggestions.add('避免反光区域，调整拍摄角度');
  }
  if (isBlurry) {
    issues.add('图片模糊');
    suggestions.add('请保持手机稳定，确保对焦清晰');
  } else if (isSlightlyBlurry) {
    issues.add('可能有轻微模糊');
    suggestions.add('建议靠近拍摄或手动点击对焦');
  }
  if (isLowContrast) {
    issues.add('对比度不足');
    suggestions.add('请使用深色笔在白纸上书写，提高字迹与背景对比度');
  } else if (isSlightlyLowContrast) {
    issues.add('对比度偏低');
    suggestions.add('建议使用颜色更深的笔书写');
  }

  QualityLevel level;
  String summary;
  if (isDark || isBright || isBlurry || isLowContrast) {
    level = QualityLevel.poor;
    summary = issues.join('、');
  } else if (isSlightlyDark || isSlightlyBright || isSlightlyBlurry || isSlightlyLowContrast) {
    level = QualityLevel.medium;
    summary = issues.isNotEmpty ? issues.join('、') : '质量一般';
  } else {
    level = QualityLevel.good;
    summary = '图片清晰，亮度适中，对比度良好';
  }

  return ImageQualityResult(
    brightness: avgBrightness,
    sharpness: laplacianVariance,
    contrast: contrast,
    summary: summary,
    level: level,
    suggestions: suggestions,
  );
}
