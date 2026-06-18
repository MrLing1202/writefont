import 'dart:convert';
import 'dart:typed_data';

/// Represents a single point on a glyph contour.
class ContourPoint {
  final int x;
  final int y;
  final bool onCurve;

  ContourPoint(this.x, this.y, {this.onCurve = true});

  /// 是否为控制点（off-curve 贝塞尔控制点），与 onCurve 互为取反
  bool get isControl => !onCurve;

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'onCurve': onCurve,
      };

  /// 从 JSON 反序列化
  factory ContourPoint.fromJson(Map<String, dynamic> json) => ContourPoint(
        json['x'] as int,
        json['y'] as int,
        onCurve: json['onCurve'] as bool? ?? true,
      );
}

/// Represents a contour (closed path) of a glyph.
class Contour {
  final List<ContourPoint> points;
  Contour(this.points);

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'points': points.map((p) => p.toJson()).toList(),
      };

  /// 从 JSON 反序列化
  factory Contour.fromJson(Map<String, dynamic> json) => Contour(
        (json['points'] as List)
            .map((p) => ContourPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

/// Represents a single glyph (character) with its contours and metrics.
class GlyphData {
  String character;
  int unicode;
  List<Contour> contours;
  int advanceWidth;
  int leftSideBearing;
  int xMin, yMin, xMax, yMax;
  String? sourceImagePath; // 原始图片路径
  double? confidence; // 识别置信度 0.0-1.0

  GlyphData({
    required this.character,
    required this.unicode,
    List<Contour>? contours,
    this.advanceWidth = 500,
    this.leftSideBearing = 0,
    this.xMin = 0,
    this.yMin = 0,
    this.xMax = 0,
    this.yMax = 0,
    this.sourceImagePath,
    this.confidence,
  }) : contours = contours ?? [];

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'character': character,
        'unicode': unicode,
        'contours': contours.map((c) => c.toJson()).toList(),
        'advanceWidth': advanceWidth,
        'leftSideBearing': leftSideBearing,
        'xMin': xMin,
        'yMin': yMin,
        'xMax': xMax,
        'yMax': yMax,
        'sourceImagePath': sourceImagePath,
        'confidence': confidence,
      };

  /// 从 JSON 反序列化
  factory GlyphData.fromJson(Map<String, dynamic> json) => GlyphData(
        character: json['character'] as String,
        unicode: json['unicode'] as int,
        contours: (json['contours'] as List?)
                ?.map((c) => Contour.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        advanceWidth: json['advanceWidth'] as int? ?? 500,
        leftSideBearing: json['leftSideBearing'] as int? ?? 0,
        xMin: json['xMin'] as int? ?? 0,
        yMin: json['yMin'] as int? ?? 0,
        xMax: json['xMax'] as int? ?? 0,
        yMax: json['yMax'] as int? ?? 0,
        sourceImagePath: json['sourceImagePath'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble(),
      );

  /// 根据轮廓实际边界计算动态字宽
  /// 基于所有轮廓点的 minX/maxX 加上左右边距
  int calculateAdvanceWidth() {
    if (contours.isEmpty) return 500;
    int minX = 99999, maxX = -99999;
    for (final contour in contours) {
      for (final p in contour.points) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
      }
    }
    // 字宽 = 轮廓宽度 + 左右边距（各50单位），限制在合理范围
    return (maxX - minX + 100).clamp(200, 1500);
  }
}

/// Image processing parameters.
class ProcessingParams {
  double threshold; // 0.0 - 1.0
  double strokeWidth; // 0.5 - 3.0
  double smoothness; // 0.0 - 1.0
  int erosion; // 0 - 5
  int dilation; // 0 - 5
  bool invertColors;
  double contrast;

  ProcessingParams({
    this.threshold = 0.5,
    this.strokeWidth = 1.0,
    this.smoothness = 0.3,
    this.erosion = 1,
    this.dilation = 1,
    this.invertColors = false,
    this.contrast = 1.0,
  });

  ProcessingParams copyWith({
    double? threshold,
    double? strokeWidth,
    double? smoothness,
    int? erosion,
    int? dilation,
    bool? invertColors,
    double? contrast,
  }) {
    return ProcessingParams(
      threshold: threshold ?? this.threshold,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      smoothness: smoothness ?? this.smoothness,
      erosion: erosion ?? this.erosion,
      dilation: dilation ?? this.dilation,
      invertColors: invertColors ?? this.invertColors,
      contrast: contrast ?? this.contrast,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'threshold': threshold,
        'strokeWidth': strokeWidth,
        'smoothness': smoothness,
        'erosion': erosion,
        'dilation': dilation,
        'invertColors': invertColors,
        'contrast': contrast,
      };

  /// 从 JSON 反序列化
  factory ProcessingParams.fromJson(Map<String, dynamic> json) =>
      ProcessingParams(
        threshold: (json['threshold'] as num?)?.toDouble() ?? 0.5,
        strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 1.0,
        smoothness: (json['smoothness'] as num?)?.toDouble() ?? 0.3,
        erosion: json['erosion'] as int? ?? 1,
        dilation: json['dilation'] as int? ?? 1,
        invertColors: json['invertColors'] as bool? ?? false,
        contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
      );
}

/// Represents a font project containing all glyph data.
class FontProject {
  String id;
  String name;
  DateTime createdAt;
  DateTime updatedAt;
  Map<String, GlyphData> glyphs;
  ProcessingParams params;
  List<Uint8List> sourceImages;

  FontProject({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, GlyphData>? glyphs,
    ProcessingParams? params,
    List<Uint8List>? sourceImages,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        glyphs = glyphs ?? {},
        params = params ?? ProcessingParams(),
        sourceImages = sourceImages ?? [];

  /// 序列化为 JSON（不含 sourceImages 二进制数据，需单独存储）
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'glyphs': glyphs.map((k, v) => MapEntry(k, v.toJson())),
        'params': params.toJson(),
      };

  /// 从 JSON 反序列化
  factory FontProject.fromJson(Map<String, dynamic> json) {
    final glyphsMap = <String, GlyphData>{};
    final glyphsJson = json['glyphs'] as Map<String, dynamic>? ?? {};
    for (final entry in glyphsJson.entries) {
      glyphsMap[entry.key] =
          GlyphData.fromJson(entry.value as Map<String, dynamic>);
    }

    return FontProject(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      glyphs: glyphsMap,
      params: json['params'] != null
          ? ProcessingParams.fromJson(json['params'] as Map<String, dynamic>)
          : null,
    );
  }
}
