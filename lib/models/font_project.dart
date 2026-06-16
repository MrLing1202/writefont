import 'dart:typed_data';
import 'dart:ui' show Offset;

/// 单个字形数据
class GlyphData {
  final String character;
  Uint8List? originalImage; // 原始图片
  Uint8List? processedImage; // 处理后的图片
  List<List<Offset>> contours; // 轮廓点
  double threshold; // 二值化阈值 0-255
  double smoothness; // 平滑度 0-1
  double strokeWidth; // 笔画粗细调整
  bool isIncluded; // 是否包含在字体中

  GlyphData({
    required this.character,
    this.originalImage,
    this.processedImage,
    List<List<Offset>>? contours,
    this.threshold = 128.0,
    this.smoothness = 0.5,
    this.strokeWidth = 1.0,
    this.isIncluded = true,
  }) : contours = contours ?? [];

  GlyphData copyWith({
    String? character,
    Uint8List? originalImage,
    Uint8List? processedImage,
    List<List<Offset>>? contours,
    double? threshold,
    double? smoothness,
    double? strokeWidth,
    bool? isIncluded,
  }) {
    return GlyphData(
      character: character ?? this.character,
      originalImage: originalImage ?? this.originalImage,
      processedImage: processedImage ?? this.processedImage,
      contours: contours ?? List.from(this.contours),
      threshold: threshold ?? this.threshold,
      smoothness: smoothness ?? this.smoothness,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isIncluded: isIncluded ?? this.isIncluded,
    );
  }
}

/// 字体项目
class FontProject {
  String name;
  String description;
  List<GlyphData> glyphs;
  DateTime createdAt;
  DateTime updatedAt;

  FontProject({
    this.name = '我的手写字体',
    this.description = '',
    List<GlyphData>? glyphs,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : glyphs = glyphs ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int get includedGlyphCount =>
      glyphs.where((g) => g.isIncluded).length;

  /// 检查字符是否已存在
  bool hasCharacter(String char) {
    return glyphs.any((g) => g.character == char);
  }

  /// 添加或替换字形
  void addOrUpdateGlyph(GlyphData glyph) {
    final index = glyphs.indexWhere((g) => g.character == glyph.character);
    if (index >= 0) {
      glyphs[index] = glyph;
    } else {
      glyphs.add(glyph);
    }
    updatedAt = DateTime.now();
  }

  /// 删除字形
  void removeGlyph(String character) {
    glyphs.removeWhere((g) => g.character == character);
    updatedAt = DateTime.now();
  }
}
