/// 字符识别状态
enum CellStatus { pending, recognizing, recognized, failed }

/// 单个字符的识别结果
class CellResult {
  final String? character; // 识别结果，null = 未识别
  final CellStatus status;
  /// 置信度：high（与目标匹配）、medium（识别到但不匹配）、low（未识别）
  final ConfidenceLevel confidence;

  const CellResult({
    this.character,
    this.status = CellStatus.pending,
    this.confidence = ConfidenceLevel.low,
  });

  CellResult copyWith({String? character, CellStatus? status, ConfidenceLevel? confidence}) {
    return CellResult(
      character: character ?? this.character,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
    );
  }
}

enum ConfidenceLevel { high, medium, low }
