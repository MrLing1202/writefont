import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单条识别历史记录
class RecognitionHistoryEntry {
  /// 识别结果字符
  final String character;

  /// 精确置信度（0.0~1.0）
  final double confidence;

  /// 候选字列表
  final List<String> candidates;

  /// 识别时间
  final DateTime timestamp;

  /// 识别模式（local / cloud）
  final String mode;

  /// 图片哈希（用于去重）
  final int imageHash;

  /// 是否被用户纠正过
  final bool wasCorrected;

  /// 原始识别结果（纠正前）
  final String? originalCharacter;

  const RecognitionHistoryEntry({
    required this.character,
    required this.confidence,
    this.candidates = const [],
    required this.timestamp,
    this.mode = 'local',
    required this.imageHash,
    this.wasCorrected = false,
    this.originalCharacter,
  });

  Map<String, dynamic> toJson() => {
    'character': character,
    'confidence': confidence,
    'candidates': candidates,
    'timestamp': timestamp.toIso8601String(),
    'mode': mode,
    'imageHash': imageHash,
    'wasCorrected': wasCorrected,
    'originalCharacter': originalCharacter,
  };

  factory RecognitionHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RecognitionHistoryEntry(
      character: json['character'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      candidates: (json['candidates'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      mode: json['mode'] as String? ?? 'local',
      imageHash: json['imageHash'] as int? ?? 0,
      wasCorrected: json['wasCorrected'] as bool? ?? false,
      originalCharacter: json['originalCharacter'] as String?,
    );
  }
}

/// 识别历史记录存储服务
class RecognitionHistoryService {
  static const String _prefKey = 'recognition_history';
  static const int _maxEntries = 500;
  static bool _loaded = false;

  static final List<RecognitionHistoryEntry> _entries = [];

  /// 确保数据已加载
  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKey);
      if (json != null && json.isNotEmpty) {
        final list = jsonDecode(json) as List<dynamic>;
        _entries.clear();
        for (final item in list) {
          _entries.add(RecognitionHistoryEntry.fromJson(item as Map<String, dynamic>));
        }
        debugPrint('识别历史: 已加载 ${_entries.length} 条记录');
      }
    } catch (e) {
      debugPrint('识别历史: 加载失败 $e');
    }
  }

  /// 保存到持久化存储
  static Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await prefs.setString(_prefKey, json);
    } catch (e) {
      debugPrint('识别历史: 保存失败 $e');
    }
  }

  /// 添加一条识别历史记录
  static Future<void> addEntry(RecognitionHistoryEntry entry) async {
    await _ensureLoaded();
    _entries.insert(0, entry);
    // 限制最大条目数
    while (_entries.length > _maxEntries) {
      _entries.removeLast();
    }
    // 异步保存（不阻塞）
    _save();
  }

  /// 获取所有历史记录（按时间降序）
  static Future<List<RecognitionHistoryEntry>> getAll() async {
    await _ensureLoaded();
    return List.unmodifiable(_entries);
  }

  /// 按字符搜索历史记录
  static Future<List<RecognitionHistoryEntry>> searchByCharacter(String char) async {
    await _ensureLoaded();
    return _entries.where((e) => e.character == char).toList();
  }

  /// 获取最近 N 条记录
  static Future<List<RecognitionHistoryEntry>> getRecent({int count = 50}) async {
    await _ensureLoaded();
    final end = count < _entries.length ? count : _entries.length;
    return List.unmodifiable(_entries.sublist(0, end));
  }

  /// 获取统计数据
  static Future<Map<String, dynamic>> getStats() async {
    await _ensureLoaded();
    final total = _entries.length;
    final corrected = _entries.where((e) => e.wasCorrected).length;
    final localCount = _entries.where((e) => e.mode == 'local').length;
    final cloudCount = _entries.where((e) => e.mode == 'cloud').length;

    // 字符频率统计
    final charFreq = <String, int>{};
    for (final e in _entries) {
      charFreq[e.character] = (charFreq[e.character] ?? 0) + 1;
    }
    final topChars = charFreq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 平均置信度
    double avgConf = 0;
    if (total > 0) {
      avgConf = _entries.map((e) => e.confidence).reduce((a, b) => a + b) / total;
    }

    return {
      'total': total,
      'corrected': corrected,
      'correctionRate': total > 0 ? corrected / total : 0.0,
      'localCount': localCount,
      'cloudCount': cloudCount,
      'avgConfidence': avgConf,
      'topCharacters': topChars.take(10).map((e) => '${e.key}:${e.value}').toList(),
    };
  }

  /// 清空历史记录
  static Future<void> clear() async {
    _entries.clear();
    _loaded = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    debugPrint('识别历史: 已清空');
  }

  /// 删除单条记录
  static Future<void> removeAt(int index) async {
    await _ensureLoaded();
    if (index >= 0 && index < _entries.length) {
      _entries.removeAt(index);
      _save();
    }
  }
}
