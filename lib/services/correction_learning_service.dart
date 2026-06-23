import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v5.1.0: 修正学习服务
///
/// 保存用户修正记录，在后续识别中应用修正学习。
/// 与 UserFeedbackService 互补：FeedbackService 以图片相似度匹配，
/// CorrectionLearning 以字符特征（尺寸/笔画密度/候选字符）匹配。
class CorrectionLearningService {
  static CorrectionLearningService? _instance;
  static CorrectionLearningService get instance =>
      _instance ??= CorrectionLearningService._();

  CorrectionLearningService._();

  static const String _prefKeyCorrections = 'correction_learning_data';
  static const int _maxRecords = 500;

  /// 修正记录列表（内存缓存）
  final List<CorrectionRecord> _records = [];
  bool _loaded = false;

  /// 加载持久化的修正记录
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKeyCorrections);
      if (json != null && json.isNotEmpty) {
        final list = jsonDecode(json) as List;
        _records.clear();
        for (final item in list) {
          _records.add(CorrectionRecord.fromJson(item as Map<String, dynamic>));
        }
        debugPrint('修正学习: 已加载 ${_records.length} 条记录');
      }
    } catch (e) {
      debugPrint('修正学习: 加载失败 $e');
    }
  }

  /// 持久化修正记录
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_records.map((r) => r.toJson()).toList());
      await prefs.setString(_prefKeyCorrections, json);
    } catch (e) {
      debugPrint('修正学习: 保存失败 $e');
    }
  }

  /// 记录一次用户修正
  ///
  /// [originalResult] 识别服务返回的原始结果
  /// [correctedChar] 用户修正后的正确字符
  /// [confidence] 原始识别的置信度
  /// [topCandidates] 原始识别的 Top-N 候选列表
  /// [imageWidth] 图片宽度（用于特征匹配）
  /// [imageHeight] 图片高度
  Future<void> recordCorrection({
    required String originalResult,
    required String correctedChar,
    required double confidence,
    List<String>? topCandidates,
    int? imageWidth,
    int? imageHeight,
  }) async {
    await _ensureLoaded();

    final record = CorrectionRecord(
      originalResult: originalResult,
      correctedChar: correctedChar,
      confidence: confidence,
      topCandidates: topCandidates ?? [],
      imageWidth: imageWidth ?? 0,
      imageHeight: imageHeight ?? 0,
      timestamp: DateTime.now(),
    );

    _records.add(record);

    // 限制记录数量
    if (_records.length > _maxRecords) {
      _records.removeAt(0);
    }

    await _save();
    debugPrint('修正学习: 记录 "$originalResult" → "$correctedChar" '
        '(置信度=${(confidence * 100).toStringAsFixed(0)}%)');
  }

  /// v5.3.0: 增强修正建议查找
  ///
  /// 匹配条件（v5.3.0 增强）：
  /// 1. 原始识别结果相同（直接匹配）或出现在 topCandidates 中（候选匹配）
  /// 2. 置信度相近（±25%）
  /// 3. 图片尺寸相近（同级别）
  /// 4. 时间衰减：近期修正权重更高（30天半衰期）
  ///
  /// 返回修正后的字符，无匹配时返回 null
  Future<String?> findCorrection({
    required String recognizedChar,
    required double confidence,
    int? imageWidth,
    int? imageHeight,
  }) async {
    await _ensureLoaded();
    if (_records.isEmpty) return null;

    // 按匹配度排序
    final candidates = <_MatchResult>[];

    for (final record in _records) {
      // v5.3.0: 支持两种匹配模式
      // 模式A: 原始识别结果直接匹配
      // 模式B: recognizedChar 出现在 topCandidates 中（候选匹配）
      final isDirectMatch = record.originalResult == recognizedChar;
      final isCandidateMatch = record.topCandidates.contains(recognizedChar);
      if (!isDirectMatch && !isCandidateMatch) continue;

      // 置信度相似度（越接近越好）
      final confDiff = (record.confidence - confidence).abs();
      if (confDiff > 0.25) continue;

      // 尺寸相似度
      double sizeScore = 1.0;
      if (imageWidth != null &&
          imageHeight != null &&
          record.imageWidth > 0 &&
          record.imageHeight > 0) {
        final wDiff =
            (record.imageWidth - imageWidth).abs() / imageWidth.clamp(1, 99999);
        final hDiff =
            (record.imageHeight - imageHeight).abs() / imageHeight.clamp(1, 99999);
        sizeScore = 1.0 - ((wDiff + hDiff) / 2).clamp(0.0, 1.0);
      }

      // v5.3.0: 时间衰减（30天半衰期）
      final daysSinceCorrection = DateTime.now().difference(record.timestamp).inDays;
      final timeDecay = math.pow(0.5, daysSinceCorrection / 30.0).toDouble();

      // 综合匹配分（置信度相似度 50% + 尺寸相似度 30% + 时间衰减 20%）
      // 直接匹配比候选匹配得分更高
      final matchBonus = isDirectMatch ? 1.0 : 0.8;
      final score = ((1.0 - confDiff) * 0.5 + sizeScore * 0.3 + timeDecay * 0.2) * matchBonus;
      candidates.add(_MatchResult(record, score));
    }

    if (candidates.isEmpty) return null;

    // 按匹配分降序
    candidates.sort((a, b) => b.score.compareTo(a.score));

    // 取最佳匹配
    final best = candidates.first.record;
    final sameCorrectionCount = _records
        .where((r) =>
            r.originalResult == recognizedChar &&
            r.correctedChar == best.correctedChar)
        .length;

    // v5.3.0: 放宽采纳条件
    // 原条件：≥2次相同修正 或 confidence < 0.5
    // 新增条件：单次修正但原始置信度高(>0.8，说明用户对结果很确定才修正)
    if (sameCorrectionCount >= 2 ||
        best.confidence < 0.5 ||
        (sameCorrectionCount >= 1 && best.confidence >= 0.8)) {
      debugPrint('修正学习: 匹配 "$recognizedChar" → "${best.correctedChar}" '
          '(出现$sameCorrectionCount次, 匹配分=${candidates.first.score.toStringAsFixed(2)})');
      return best.correctedChar;
    }

    return null;
  }

  /// 获取修正统计（供 UI 展示）
  Map<String, dynamic> getStats() {
    final Map<String, int> correctionCounts = {};
    for (final r in _records) {
      final key = '${r.originalResult}→${r.correctedChar}';
      correctionCounts[key] = (correctionCounts[key] ?? 0) + 1;
    }
    return {
      'totalRecords': _records.length,
      'uniqueCorrections': correctionCounts.length,
      'topCorrections': correctionCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)),
    };
  }

  /// 清除所有修正记录
  Future<void> clearAll() async {
    _records.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyCorrections);
    debugPrint('修正学习: 已清除所有记录');
  }
}

/// 修正记录
class CorrectionRecord {
  final String originalResult;
  final String correctedChar;
  final double confidence;
  final List<String> topCandidates;
  final int imageWidth;
  final int imageHeight;
  final DateTime timestamp;

  const CorrectionRecord({
    required this.originalResult,
    required this.correctedChar,
    required this.confidence,
    required this.topCandidates,
    required this.imageWidth,
    required this.imageHeight,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'originalResult': originalResult,
        'correctedChar': correctedChar,
        'confidence': confidence,
        'topCandidates': topCandidates,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'timestamp': timestamp.toIso8601String(),
      };

  factory CorrectionRecord.fromJson(Map<String, dynamic> json) =>
      CorrectionRecord(
        originalResult: json['originalResult'] as String,
        correctedChar: json['correctedChar'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        topCandidates: (json['topCandidates'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        imageWidth: (json['imageWidth'] as num?)?.toInt() ?? 0,
        imageHeight: (json['imageHeight'] as num?)?.toInt() ?? 0,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// 匹配结果（内部使用）
class _MatchResult {
  final CorrectionRecord record;
  final double score;
  _MatchResult(this.record, this.score);
}
