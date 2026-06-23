/// 字符识别状态
enum CellStatus { pending, recognizing, recognized, failed }

/// 单个字符的识别结果
class CellResult {
  final String? character; // 识别结果，null = 未识别
  final CellStatus status;
  /// 置信度：high（与目标匹配）、medium（识别到但不匹配）、low（未识别）
  final ConfidenceLevel confidence;

  /// v4.6.0: 精确置信度（0.0~1.0），由识别引擎计算
  final double? preciseConfidence;

  /// v4.6.0: 候选字列表（按得分降序），由 recognizeCharacterTopN 提供
  final List<String>? candidates;

  const CellResult({
    this.character,
    this.status = CellStatus.pending,
    this.confidence = ConfidenceLevel.low,
    this.preciseConfidence,
    this.candidates,
  });

  CellResult copyWith({
    String? character,
    CellStatus? status,
    ConfidenceLevel? confidence,
    double? preciseConfidence,
    List<String>? candidates,
  }) {
    return CellResult(
      character: character ?? this.character,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      preciseConfidence: preciseConfidence ?? this.preciseConfidence,
      candidates: candidates ?? this.candidates,
    );
  }
}

enum ConfidenceLevel { high, medium, low }
