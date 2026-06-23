import 'dart:typed_data';

/// v5.1.0: 分割后的字符数据对象
///
/// 包含字符图片、原始尺寸信息、宽高比和边界框，
/// 为后续识别和可视化提供完整的元数据。
class SegmentedCharacter {
  /// 字符图片 PNG 字节数据
  final Uint8List imageBytes;

  /// 原始图像宽度（分割前的宽度）
  final int originalWidth;

  /// 原始图像高度（分割前的高度）
  final int originalHeight;

  /// 字符区域宽高比（width / height）
  final double aspectRatio;

  /// 边界框：在原图中的位置
  final BoundingBox boundingBox;

  /// 字符大小分类（small / medium / large）
  final CharacterSize sizeCategory;

  /// 字符面积占原图面积的比例
  final double areaRatio;

  const SegmentedCharacter({
    required this.imageBytes,
    required this.originalWidth,
    required this.originalHeight,
    required this.aspectRatio,
    required this.boundingBox,
    required this.sizeCategory,
    required this.areaRatio,
  });

  /// 序列化为 JSON（不含 imageBytes，用于日志和调试）
  Map<String, dynamic> toJson() => {
        'originalWidth': originalWidth,
        'originalHeight': originalHeight,
        'aspectRatio': aspectRatio,
        'boundingBox': boundingBox.toJson(),
        'sizeCategory': sizeCategory.name,
        'areaRatio': areaRatio,
      };

  @override
  String toString() =>
      'SegmentedCharacter(${boundingBox.width}x${boundingBox.height}, '
      'ar=${aspectRatio.toStringAsFixed(2)}, size=${sizeCategory.name})';
}

/// 边界框
class BoundingBox {
  final int x;
  final int y;
  final int width;
  final int height;

  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  int get right => x + width;
  int get bottom => y + height;
  double get centerX => x + width / 2.0;
  double get centerY => y + height / 2.0;
  int get area => width * height;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  @override
  String toString() => 'BBox($x,$y ${width}x$height)';
}

/// 字符大小分类
enum CharacterSize {
  /// 小字符（面积 < 中位数的 50%）
  small,

  /// 中等字符（正常大小）
  medium,

  /// 大字符（面积 > 中位数的 200%）
  large,
}
