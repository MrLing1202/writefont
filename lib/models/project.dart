import 'dart:typed_data';

/// Represents a single point on a glyph contour.
class ContourPoint {
  final int x;
  final int y;
  final bool onCurve;

  ContourPoint(this.x, this.y, {this.onCurve = true});
}

/// Represents a contour (closed path) of a glyph.
class Contour {
  final List<ContourPoint> points;
  Contour(this.points);
}

/// Represents a single glyph (character) with its contours and metrics.
class GlyphData {
  final String character;
  final int unicode;
  List<Contour> contours;
  int advanceWidth;
  int leftSideBearing;
  int xMin, yMin, xMax, yMax;

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
  }) : contours = contours ?? [];
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
    this.smoothness = 0.5,
    this.erosion = 0,
    this.dilation = 0,
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
}

/// Represents a font project containing all glyph data.
class FontProject {
  final String id;
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
}
