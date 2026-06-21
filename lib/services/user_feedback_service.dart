import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

/// 用户反馈学习服务
///
/// 核心思路：用户纠正过的字符存下来，相似图片优先用纠正结果，越用越准。
///
/// 实现：
/// - 使用感知哈希（Average Hash）为每张图片生成 64-bit 指纹
/// - 通过汉明距离匹配相似图片（阈值 ≤ 10 bits）
/// - SharedPreferences 持久化存储，最大 1000 条记录（LRU 淘汰）
class UserFeedbackService {
  // SharedPreferences key
  static const String _prefKey = 'user_feedback_records';

  // 单例
  static UserFeedbackService? _instance;
  static UserFeedbackService get instance => _instance ??= UserFeedbackService._();

  UserFeedbackService._();

  /// 感知哈希尺寸（8x8 = 64-bit hash）
  static const int _hashSize = 8;

  /// 相似度阈值（汉明距离 ≤ 此值视为相似）
  static const int _similarityThreshold = 10;

  /// 最大存储条目数
  static const int _maxRecords = 1000;

  /// 内存缓存（启动时从 SharedPreferences 加载）
  List<_FeedbackRecord> _records = [];
  bool _loaded = false;

  /// 用户纠正反馈
  ///
  /// [imageBytes] 原始图片字节
  /// [correctChar] 用户纠正后的正确字符
  Future<void> feedback(Uint8List imageBytes, String correctChar) async {
    if (correctChar.isEmpty) return;

    await _ensureLoaded();

    final hash = _computePerceptualHash(imageBytes);

    // 检查是否已存在相同哈希的记录，有则更新
    final existingIndex = _records.indexWhere((r) => r.hash == hash);
    if (existingIndex >= 0) {
      _records[existingIndex] = _FeedbackRecord(
        hash: hash,
        char: correctChar,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      _records.add(_FeedbackRecord(
        hash: hash,
        char: correctChar,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
    }

    // LRU 淘汰：超出上限时移除最旧的记录
    if (_records.length > _maxRecords) {
      _records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _records = _records.sublist(0, _maxRecords);
    }

    await _save();
    debugPrint('用户反馈: 存储纠正 "$correctChar" (hash=$hash, 总记录=${_records.length})');
  }

  /// 查找相似的用户纠正记录
  ///
  /// [imageBytes] 待查询的图片字节
  /// 返回匹配到的纠正字符，未找到返回 null
  Future<String?> findSimilarFeedback(Uint8List imageBytes) async {
    await _ensureLoaded();
    if (_records.isEmpty) return null;

    final hash = _computePerceptualHash(imageBytes);

    // 1. 精确匹配
    for (final record in _records) {
      if (record.hash == hash) {
        debugPrint('用户反馈: 精确匹配 "${record.char}" (hash=$hash)');
        return record.char;
      }
    }

    // 2. 相似匹配（汉明距离最小的记录）
    _FeedbackRecord? bestMatch;
    int bestDistance = _similarityThreshold + 1;

    for (final record in _records) {
      final distance = _hammingDistance(hash, record.hash);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestMatch = record;
      }
    }

    if (bestMatch != null && bestDistance <= _similarityThreshold) {
      debugPrint('用户反馈: 相似匹配 "${bestMatch.char}" (距离=$bestDistance/64)');
      return bestMatch.char;
    }

    return null;
  }

  /// 获取反馈记录总数
  int get recordCount => _records.length;

  /// 清空所有反馈记录
  Future<void> clearAll() async {
    _records.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    debugPrint('用户反馈: 已清空所有记录');
  }

  /// 获取反馈统计信息
  Map<String, dynamic> getStats() {
    final charFrequency = <String, int>{};
    for (final record in _records) {
      charFrequency[record.char] = (charFrequency[record.char] ?? 0) + 1;
    }

    // 按频次排序
    final sorted = charFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'totalRecords': _records.length,
      'maxRecords': _maxRecords,
      'uniqueChars': charFrequency.length,
      'topChars': sorted.take(10).map((e) => '${e.key}(${e.value})').toList(),
    };
  }

  // ═══════════════════════════════════════════
  // 内部方法
  // ═══════════════════════════════════════════

  /// 确保记录已从持久化存储加载
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKey);
      if (json != null && json.isNotEmpty) {
        final list = jsonDecode(json) as List;
        _records = list
            .map((e) => _FeedbackRecord.fromJson(e as Map<String, dynamic>))
            .toList();
        debugPrint('用户反馈: 已加载 ${_records.length} 条记录');
      }
    } catch (e) {
      debugPrint('用户反馈: 加载记录失败 $e');
      _records = [];
    }
  }

  /// 持久化保存记录
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_records.map((r) => r.toJson()).toList());
      await prefs.setString(_prefKey, json);
    } catch (e) {
      debugPrint('用户反馈: 保存记录失败 $e');
    }
  }

  /// 计算感知哈希（Average Hash）
  ///
  /// 将图片缩放为 [_hashSize] x [_hashSize] 灰度图，
  /// 计算平均灰度值，每个像素与均值比较生成 1-bit，
  /// 最终得到 64-bit 哈希值。
  ///
  /// 对手写体的优势：忽略细微笔画差异，关注整体结构。
  int _computePerceptualHash(Uint8List imageBytes) {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return 0;

      // 缩放到 hashSize x hashSize，灰度化
      final resized = img.copyResize(decoded,
          width: _hashSize, height: _hashSize,
          interpolation: img.Interpolation.linear);
      final gray = img.grayscale(resized);

      // 收集像素值并计算均值
      final pixels = List<int>.filled(_hashSize * _hashSize, 0);
      int sum = 0;
      for (int y = 0; y < _hashSize; y++) {
        for (int x = 0; x < _hashSize; x++) {
          final v = gray.getPixel(x, y).r.toInt();
          pixels[y * _hashSize + x] = v;
          sum += v;
        }
      }
      final avg = sum / pixels.length;

      // 生成哈希：像素值 >= 均值为 1，否则为 0
      int hash = 0;
      for (int i = 0; i < pixels.length; i++) {
        if (pixels[i] >= avg) {
          hash |= (1 << i);
        }
      }

      return hash;
    } catch (e) {
      debugPrint('用户反馈: 感知哈希计算失败 $e');
      return 0;
    }
  }

  /// 计算两个哈希值的汉明距离（不同 bit 的个数）
  static int _hammingDistance(int a, int b) {
    int xor = a ^ b;
    int count = 0;
    while (xor != 0) {
      count++;
      xor &= xor - 1; // 清除最低位的 1
    }
    return count;
  }
}

/// 反馈记录
class _FeedbackRecord {
  /// 图片感知哈希
  final int hash;

  /// 纠正后的字符
  final String char;

  /// 记录时间戳（毫秒）
  final int timestamp;

  _FeedbackRecord({
    required this.hash,
    required this.char,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'char': char,
        'timestamp': timestamp,
      };

  factory _FeedbackRecord.fromJson(Map<String, dynamic> json) =>
      _FeedbackRecord(
        hash: json['hash'] as int,
        char: json['char'] as String,
        timestamp: json['timestamp'] as int,
      );
}
